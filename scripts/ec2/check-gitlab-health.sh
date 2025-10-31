#!/bin/bash
# Quick health check for GitLab instance
# Can be run locally (checks CloudWatch) or on the instance (checks system)

PROFILE="gemini-pro_ck"
INSTANCE_ID="i-00b89a08e62a762a9"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "GitLab Health Check"
echo "=========================================="
echo ""

# Check if running on EC2 or locally
if [ -f /sys/hypervisor/uuid ] || [ -d /sys/devices/virtual/dmi/id/ ]; then
    # Running on EC2 instance
    echo -e "${BLUE}Mode: ON-INSTANCE CHECK${NC}"
    echo ""

    # System memory
    echo "--- Memory Usage ---"
    free -h
    echo ""

    # Top processes by memory
    echo "--- Top 10 Processes by Memory ---"
    ps aux --sort=-%mem | head -n 11
    echo ""

    # GitLab status
    if command -v gitlab-ctl &> /dev/null; then
        echo "--- GitLab Services Status ---"
        sudo gitlab-ctl status
        echo ""

        # GitLab version
        echo "--- GitLab Version ---"
        sudo gitlab-rake gitlab:env:info | grep "GitLab information"
        echo ""
    fi

    # Check for OOM errors
    echo "--- Recent OOM (Out of Memory) Errors ---"
    sudo dmesg | grep -i "out of memory" | tail -n 5 || echo "No recent OOM errors"
    echo ""

    # Swap usage
    echo "--- Swap Usage ---"
    swapon --show || echo "No swap configured"
    echo ""

    # Load average
    echo "--- System Load ---"
    uptime
    echo ""

    # Disk usage
    echo "--- Disk Usage ---"
    df -h | grep -E "Filesystem|/$"
    echo ""

else
    # Running locally - check CloudWatch
    echo -e "${BLUE}Mode: REMOTE CHECK (CloudWatch)${NC}"
    echo ""

    # Get instance state
    echo "--- Instance State ---"
    aws --profile $PROFILE ec2 describe-instances \
      --instance-ids $INSTANCE_ID \
      --query 'Reservations[0].Instances[0].[State.Name,InstanceType,LaunchTime]' \
      --output table
    echo ""

    # Get recent CPU metrics (last 1 hour)
    echo "--- CPU Utilization (Last Hour) ---"
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
    START_TIME=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -u -v-1H +"%Y-%m-%dT%H:%M:%S")

    CPU_STATS=$(aws --profile $PROFILE cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --dimensions Name=InstanceId,Value=$INSTANCE_ID \
      --start-time $START_TIME \
      --end-time $END_TIME \
      --period 300 \
      --statistics Average,Maximum \
      --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
      --output text | sort -r | head -n 5)

    if [ -n "$CPU_STATS" ]; then
        echo "Recent CPU usage (5-minute intervals):"
        echo "$CPU_STATS"
    else
        echo "No CPU data available"
    fi
    echo ""

    # Check if CloudWatch Agent is installed
    echo "--- CloudWatch Agent Status ---"
    CW_METRICS=$(aws --profile $PROFILE cloudwatch list-metrics \
      --namespace CWAgent \
      --dimensions Name=InstanceId,Value=$INSTANCE_ID \
      --query 'Metrics[*].MetricName' \
      --output text)

    if [ -n "$CW_METRICS" ]; then
        echo -e "${GREEN}✅ CloudWatch Agent is installed${NC}"
        echo "Available metrics: $(echo $CW_METRICS | tr '\t' ', ')"

        # Get memory usage if available
        MEM_STATS=$(aws --profile $PROFILE cloudwatch get-metric-statistics \
          --namespace CWAgent \
          --metric-name mem_used_percent \
          --dimensions Name=InstanceId,Value=$INSTANCE_ID \
          --start-time $START_TIME \
          --end-time $END_TIME \
          --period 300 \
          --statistics Average,Maximum \
          --query 'Datapoints[-1].[Timestamp,Average,Maximum]' \
          --output text 2>/dev/null)

        if [ -n "$MEM_STATS" ]; then
            echo ""
            echo "--- Memory Usage (Latest) ---"
            echo "$MEM_STATS"
        fi
    else
        echo -e "${RED}❌ CloudWatch Agent is NOT installed${NC}"
        echo "   Memory metrics not available"
        echo "   Run: scripts/ec2/install-cloudwatch-agent.sh (on instance)"
    fi
    echo ""

    # Check status checks
    echo "--- Status Checks ---"
    aws --profile $PROFILE ec2 describe-instance-status \
      --instance-ids $INSTANCE_ID \
      --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
      --output table
    echo ""

    # Recommendations
    echo "=========================================="
    echo "Quick Recommendations"
    echo "=========================================="
    echo ""
    echo "To check detailed memory usage, SSH to the instance:"
    echo "  ssh ec2-user@\$(aws --profile $PROFILE ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
    echo ""
    echo "Then run:"
    echo "  free -h                    # Memory usage"
    echo "  top -o %MEM                # Top processes by memory"
    echo "  sudo gitlab-ctl status     # GitLab services"
    echo "  sudo gitlab-ctl tail       # View logs"
fi

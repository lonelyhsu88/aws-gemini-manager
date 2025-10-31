#!/bin/bash
# Install and configure CloudWatch Agent on GitLab instance
# This script should be run ON the GitLab EC2 instance (not locally)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "CloudWatch Agent Installation Script"
echo "=========================================="
echo ""

# Check if running on EC2
if [ ! -f /sys/hypervisor/uuid ] && [ ! -d /sys/devices/virtual/dmi/id/ ]; then
    echo -e "${RED}❌ This script must be run on an EC2 instance${NC}"
    exit 1
fi

# Get instance info
INSTANCE_ID=$(ec2-metadata --instance-id | cut -d " " -f 2)
echo "Instance ID: $INSTANCE_ID"

# Update system
echo ""
echo "Step 1: Updating system packages..."
sudo yum update -y || sudo apt-get update -y

# Download CloudWatch Agent
echo ""
echo "Step 2: Downloading CloudWatch Agent..."
cd /tmp

if [ -f /etc/redhat-release ]; then
    # Amazon Linux / RHEL
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    echo "Step 3: Installing CloudWatch Agent..."
    sudo rpm -U ./amazon-cloudwatch-agent.rpm
elif [ -f /etc/debian_version ]; then
    # Ubuntu / Debian
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    echo "Step 3: Installing CloudWatch Agent..."
    sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
else
    echo -e "${RED}❌ Unsupported OS${NC}"
    exit 1
fi

echo -e "${GREEN}✅ CloudWatch Agent installed${NC}"

# Create configuration file
echo ""
echo "Step 4: Creating CloudWatch Agent configuration..."

sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_IOWAIT",
            "unit": "Percent"
          },
          "cpu_time_guest"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ],
        "totalcpu": true
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED_PERCENT",
            "unit": "Percent"
          },
          "inodes_free"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          "io_time",
          "write_bytes",
          "read_bytes",
          "writes",
          "reads"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEMORY_USED_PERCENT",
            "unit": "Percent"
          },
          "mem_available",
          "mem_used",
          "mem_total"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          {
            "name": "swap_used_percent",
            "rename": "SWAP_USED_PERCENT",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

echo -e "${GREEN}✅ Configuration file created${NC}"

# Start CloudWatch Agent
echo ""
echo "Step 5: Starting CloudWatch Agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo -e "${GREEN}✅ CloudWatch Agent started${NC}"

# Verify status
echo ""
echo "Step 6: Verifying CloudWatch Agent status..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query \
  -m ec2 \
  -c default

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Wait 5-10 minutes for metrics to appear in CloudWatch"
echo "2. Check metrics in AWS Console:"
echo "   - CloudWatch > Metrics > CWAgent > InstanceId"
echo "3. Create CloudWatch alarms for memory usage"
echo ""
echo "Useful commands:"
echo "- Check status: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2"
echo "- Stop agent: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop -m ec2"
echo "- Start agent: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2"
echo "- View logs: sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"

#!/bin/bash
# Upgrade GitLab EC2 instance type
# Profile: gemini-pro_ck
# Instance: Gemini-Gitlab (i-00b89a08e62a762a9)

set -e

# Configuration
PROFILE="gemini-pro_ck"
INSTANCE_ID="i-00b89a08e62a762a9"
CURRENT_TYPE="c5a.xlarge"
NEW_TYPE="c5a.2xlarge"  # Can be changed

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "GitLab Instance Upgrade Script"
echo "=========================================="
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Current Type: $CURRENT_TYPE"
echo "New Type: $NEW_TYPE"
echo ""

# Confirm
read -p "⚠️  This will STOP the instance. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Upgrade cancelled."
    exit 0
fi

echo ""
echo "Step 1: Checking current instance state..."
STATE=$(aws --profile $PROFILE ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)
echo "Current state: $STATE"

if [ "$STATE" != "running" ] && [ "$STATE" != "stopped" ]; then
    echo -e "${RED}❌ Instance is in $STATE state. Cannot proceed.${NC}"
    exit 1
fi

# Create snapshot before upgrade
echo ""
echo "Step 2: Creating backup snapshot (recommended)..."
read -p "Create EBS snapshot before upgrade? (yes/no): " create_snapshot

if [ "$create_snapshot" = "yes" ]; then
    # Get volume IDs
    VOLUME_IDS=$(aws --profile $PROFILE ec2 describe-instances \
      --instance-ids $INSTANCE_ID \
      --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].Ebs.VolumeId' \
      --output text)

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    for VOLUME_ID in $VOLUME_IDS; do
        echo "Creating snapshot for $VOLUME_ID..."
        aws --profile $PROFILE ec2 create-snapshot \
          --volume-id $VOLUME_ID \
          --description "Backup before GitLab upgrade - $TIMESTAMP" \
          --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=gitlab-upgrade-backup-$TIMESTAMP}]"
    done
    echo -e "${GREEN}✅ Snapshots created${NC}"
fi

# Stop instance if running
if [ "$STATE" = "running" ]; then
    echo ""
    echo "Step 3: Stopping instance..."
    aws --profile $PROFILE ec2 stop-instances --instance-ids $INSTANCE_ID
    echo "Waiting for instance to stop..."
    aws --profile $PROFILE ec2 wait instance-stopped --instance-ids $INSTANCE_ID
    echo -e "${GREEN}✅ Instance stopped${NC}"
else
    echo ""
    echo "Step 3: Instance already stopped, skipping..."
fi

# Modify instance type
echo ""
echo "Step 4: Modifying instance type to $NEW_TYPE..."
aws --profile $PROFILE ec2 modify-instance-attribute \
  --instance-id $INSTANCE_ID \
  --instance-type "{\"Value\": \"$NEW_TYPE\"}"
echo -e "${GREEN}✅ Instance type modified${NC}"

# Start instance
echo ""
echo "Step 5: Starting instance..."
read -p "Start instance now? (yes/no): " start_now

if [ "$start_now" = "yes" ]; then
    aws --profile $PROFILE ec2 start-instances --instance-ids $INSTANCE_ID
    echo "Waiting for instance to start..."
    aws --profile $PROFILE ec2 wait instance-running --instance-ids $INSTANCE_ID

    # Get new IP
    NEW_IP=$(aws --profile $PROFILE ec2 describe-instances \
      --instance-ids $INSTANCE_ID \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text)

    echo -e "${GREEN}✅ Instance started${NC}"
    echo ""
    echo "=========================================="
    echo "Upgrade Complete!"
    echo "=========================================="
    echo "Instance ID: $INSTANCE_ID"
    echo "New Type: $NEW_TYPE"
    echo "Public IP: $NEW_IP"
    echo ""
    echo "Next steps:"
    echo "1. SSH to instance: ssh ec2-user@$NEW_IP"
    echo "2. Check GitLab status: sudo gitlab-ctl status"
    echo "3. Monitor memory: free -h"
    echo "4. Check logs: sudo gitlab-ctl tail"
else
    echo -e "${YELLOW}⚠️  Instance stopped but not started. Start manually when ready.${NC}"
fi

echo ""
echo "=========================================="
echo "Cost Impact:"
echo "=========================================="
echo "c5a.xlarge:  \$0.154/hour ≈ \$110/month"
echo "c5a.2xlarge: \$0.308/hour ≈ \$220/month"
echo "Increase: \$110/month"

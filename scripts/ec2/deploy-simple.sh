#!/bin/bash

################################################################################
# Simple EC2 Deployment for Game Load Testing in ap-south-1
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_PROFILE="gemini-pro_ck"
REGION="ap-south-1"
INSTANCE_NAME="game-load-test-mumbai"
INSTANCE_TYPE="t3.medium"
KEY_NAME="game-test-mumbai-key"
SECURITY_GROUP_NAME="game-test-sg"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
GAME_TEST_SOURCE="/Users/lonelyhsu/gemini/toolkits/game_login/game-test"

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }

# Get Ubuntu AMI
get_ubuntu_ami() {
    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text
}

# Get or create security group
get_security_group() {
    SG_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        echo "$SG_ID"
        return 0
    fi

    VPC_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)

    SG_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for game load testing" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)

    MY_IP=$(curl -s https://api.ipify.org)
    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${MY_IP}/32"

    echo "$SG_ID"
}

print_info "Getting Ubuntu AMI..."
AMI_ID=$(get_ubuntu_ami)
print_success "AMI: $AMI_ID"

print_info "Getting security group..."
SG_ID=$(get_security_group)
print_success "Security Group: $SG_ID"

print_info "Launching instance..."
INSTANCE_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --query 'Instances[0].InstanceId' \
    --output text)

print_success "Instance launched: $INSTANCE_ID"

# Tag the instance separately
print_info "Adding tags..."
aws --profile "$AWS_PROFILE" --region "$REGION" ec2 create-tags \
    --resources "$INSTANCE_ID" \
    --tags Key=Name,Value="$INSTANCE_NAME" Key=Purpose,Value=GameLoadTest

print_info "Waiting for instance to be running..."
aws --profile "$AWS_PROFILE" --region "$REGION" ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

print_success "Instance running: $PUBLIC_IP"

print_info "Waiting for SSH (this may take 1-2 minutes)..."
for i in {1..30}; do
    if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        ubuntu@"$PUBLIC_IP" "echo connected" &>/dev/null; then
        print_success "SSH ready"
        break
    fi
    sleep 10
done

print_info "Installing dependencies..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" << 'ENDSSH'
# Update and install Node.js
sudo apt-get update -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs curl git build-essential

# Install Puppeteer dependencies
sudo apt-get install -y \
    ca-certificates fonts-liberation libasound2 libatk-bridge2.0-0 \
    libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 \
    libfontconfig1 libgbm1 libgcc1 libglib2.0-0 libgtk-3-0 \
    libnspr4 libnss3 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 \
    libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 \
    libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
    libxss1 libxtst6 lsb-release wget xdg-utils

mkdir -p ~/game-test
echo "Dependencies installed"
ENDSSH

print_success "Dependencies installed"

print_info "Uploading test files..."
rsync -avz --progress \
    -e "ssh -i $KEY_FILE -o StrictHostKeyChecking=no" \
    --exclude 'node_modules' \
    --exclude 'puppeteer_results' \
    --exclude '.claude' \
    "$GAME_TEST_SOURCE/" \
    ubuntu@"$PUBLIC_IP":~/game-test/

print_success "Files uploaded"

print_info "Installing npm packages..."
ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" << 'ENDSSH'
cd ~/game-test
npm install
chmod +x *.sh
echo "Setup complete"
ENDSSH

print_success "Setup complete"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Deployment Complete                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Instance ID:${NC}  $INSTANCE_ID"
echo -e "${CYAN}Region:${NC}       $REGION"
echo -e "${CYAN}Public IP:${NC}    $PUBLIC_IP"
echo ""
echo -e "${YELLOW}Connect:${NC}"
echo "  ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
echo ""
echo -e "${YELLOW}Run test:${NC}"
echo "  cd game-test"
echo "  ./test_games_cache_comparison_optimized.sh 5"
echo ""
echo -e "${YELLOW}Download results:${NC}"
echo "  scp -i $KEY_FILE -r ubuntu@$PUBLIC_IP:~/game-test/puppeteer_results ./results-mumbai"
echo ""
echo -e "${YELLOW}Terminate when done:${NC}"
echo "  aws --profile $AWS_PROFILE --region $REGION ec2 terminate-instances --instance-ids $INSTANCE_ID"
echo ""

# Save info
cat > "instance-$INSTANCE_ID.txt" <<EOF
Instance ID: $INSTANCE_ID
Region: $REGION
Public IP: $PUBLIC_IP
Key: $KEY_FILE
Created: $(date)

Connect: ssh -i $KEY_FILE ubuntu@$PUBLIC_IP
Terminate: aws --profile $AWS_PROFILE --region $REGION ec2 terminate-instances --instance-ids $INSTANCE_ID
EOF

print_success "Instance info saved to: instance-$INSTANCE_ID.txt"

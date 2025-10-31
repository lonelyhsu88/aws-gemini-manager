#!/bin/bash

################################################################################
# Deploy EC2 Instance for Game Load Testing in ap-south-1 (Mumbai)
#
# This script:
# 1. Creates/verifies key pair and security group
# 2. Launches EC2 instance in ap-south-1
# 3. Waits for instance to be ready
# 4. Installs Node.js and dependencies
# 5. Uploads game test scripts
# 6. Provides connection instructions
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
INSTANCE_TYPE="t3.medium"  # 2 vCPU, 4GB RAM - good for Puppeteer
KEY_NAME="game-test-mumbai-key"
SECURITY_GROUP_NAME="game-test-sg"
AMI_ID=""  # Will be auto-detected (latest Ubuntu 22.04 LTS)

# Local paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GAME_TEST_SOURCE="/Users/lonelyhsu/gemini/toolkits/game_login/game-test"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║   %-52s ║${NC}\n" "$1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

################################################################################
# AWS Helper Functions
################################################################################

get_ubuntu_ami() {
    # Get latest Ubuntu 22.04 LTS AMI in ap-south-1
    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-images \
        --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text
}

################################################################################
# Step 1: Create/Verify Key Pair
################################################################################

setup_key_pair() {
    print_header "Step 1: Key Pair Setup"

    if [ -f "$KEY_FILE" ]; then
        print_info "Key file already exists: $KEY_FILE"

        # Verify key exists in AWS
        if aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-key-pairs \
            --key-names "$KEY_NAME" &>/dev/null; then
            print_success "Key pair '$KEY_NAME' verified in AWS"
            return 0
        else
            print_warning "Local key file exists but not found in AWS, recreating..."
            rm -f "$KEY_FILE"
        fi
    fi

    print_info "Creating new key pair: $KEY_NAME"

    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "$KEY_FILE"

    chmod 400 "$KEY_FILE"
    print_success "Key pair created: $KEY_FILE"
}

################################################################################
# Step 2: Create/Verify Security Group
################################################################################

setup_security_group() {
    print_header "Step 2: Security Group Setup"

    # Check if security group exists
    SG_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        print_success "Security group already exists: $SG_ID"
        echo "$SG_ID"
        return 0
    fi

    print_info "Creating security group: $SECURITY_GROUP_NAME"

    # Get default VPC ID
    VPC_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)

    # Create security group
    SG_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for game load testing" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)

    # Add SSH rule from your IP
    MY_IP=$(curl -s https://api.ipify.org)
    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${MY_IP}/32"

    print_success "Security group created: $SG_ID"
    print_info "SSH allowed from: $MY_IP"
    echo "$SG_ID"
}

################################################################################
# Step 3: Launch EC2 Instance
################################################################################

launch_instance() {
    print_header "Step 3: Launch EC2 Instance"

    # Get Ubuntu AMI
    print_info "Finding latest Ubuntu 22.04 LTS AMI..."
    AMI_ID=$(get_ubuntu_ami)
    print_success "Using AMI: $AMI_ID"

    # Get security group ID
    SG_ID=$(setup_security_group)

    # Create user data script file for initial setup
    USER_DATA_FILE=$(mktemp)
    cat > "$USER_DATA_FILE" <<'EOF'
#!/bin/bash
set -x
exec > /var/log/user-data.log 2>&1

# Update system
apt-get update -y

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install other dependencies
apt-get install -y curl git build-essential

# Install Chromium dependencies for Puppeteer
apt-get install -y \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgcc1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    wget \
    xdg-utils

# Create test directory
mkdir -p /home/ubuntu/game-test
chown ubuntu:ubuntu /home/ubuntu/game-test

echo "Setup complete" > /home/ubuntu/setup-complete.txt
EOF

    print_info "Launching $INSTANCE_TYPE instance in $REGION..."

    INSTANCE_ID=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "file://$USER_DATA_FILE" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME},{Key=Purpose,Value=GameLoadTest}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    # Clean up user data file
    rm -f "$USER_DATA_FILE"

    print_success "Instance launched: $INSTANCE_ID"
    echo "$INSTANCE_ID"
}

################################################################################
# Step 4: Wait for Instance Ready
################################################################################

wait_for_instance() {
    local instance_id="$1"

    print_header "Step 4: Waiting for Instance"

    print_info "Waiting for instance to be running..."
    aws --profile "$AWS_PROFILE" --region "$REGION" ec2 wait instance-running \
        --instance-ids "$instance_id"

    print_success "Instance is running"

    # Get public IP
    PUBLIC_IP=$(aws --profile "$AWS_PROFILE" --region "$REGION" ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    print_success "Public IP: $PUBLIC_IP"

    # Wait for SSH to be ready
    print_info "Waiting for SSH to be ready (this may take 1-2 minutes)..."
    for i in {1..30}; do
        if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            ubuntu@"$PUBLIC_IP" "echo connected" &>/dev/null; then
            print_success "SSH is ready"
            break
        fi
        echo -n "."
        sleep 10
    done
    echo ""

    # Wait for user-data script to complete
    print_info "Waiting for initial setup to complete..."
    for i in {1..60}; do
        if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no \
            ubuntu@"$PUBLIC_IP" "test -f /home/ubuntu/setup-complete.txt" &>/dev/null; then
            print_success "Initial setup complete"
            break
        fi
        echo -n "."
        sleep 5
    done
    echo ""

    echo "$PUBLIC_IP"
}

################################################################################
# Step 5: Upload Test Files
################################################################################

upload_test_files() {
    local public_ip="$1"

    print_header "Step 5: Upload Test Files"

    if [ ! -d "$GAME_TEST_SOURCE" ]; then
        print_error "Source directory not found: $GAME_TEST_SOURCE"
        exit 1
    fi

    print_info "Uploading game-test directory..."

    # Use rsync for efficient upload (excluding node_modules and results)
    rsync -avz --progress \
        -e "ssh -i $KEY_FILE -o StrictHostKeyChecking=no" \
        --exclude 'node_modules' \
        --exclude 'puppeteer_results' \
        --exclude '.claude' \
        "$GAME_TEST_SOURCE/" \
        ubuntu@"$public_ip":/home/ubuntu/game-test/

    print_success "Files uploaded"

    # Install npm dependencies
    print_info "Installing npm dependencies (this may take a few minutes)..."
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$public_ip" << 'ENDSSH'
cd /home/ubuntu/game-test
npm install
chmod +x *.sh
ENDSSH

    print_success "Dependencies installed"
}

################################################################################
# Step 6: Verify Setup
################################################################################

verify_setup() {
    local public_ip="$1"

    print_header "Step 6: Verify Setup"

    print_info "Checking Node.js version..."
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$public_ip" "node --version"

    print_info "Checking npm version..."
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$public_ip" "npm --version"

    print_info "Checking Puppeteer installation..."
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no ubuntu@"$public_ip" \
        "test -d /home/ubuntu/game-test/node_modules/puppeteer && echo 'Puppeteer installed'"

    print_success "All checks passed"
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "Game Load Test EC2 Deployment - ap-south-1"

    # Verify source directory exists
    if [ ! -d "$GAME_TEST_SOURCE" ]; then
        print_error "Game test source directory not found: $GAME_TEST_SOURCE"
        exit 1
    fi

    # Setup
    setup_key_pair

    # Launch instance
    INSTANCE_ID=$(launch_instance)

    # Wait for ready
    PUBLIC_IP=$(wait_for_instance "$INSTANCE_ID")

    # Upload files
    upload_test_files "$PUBLIC_IP"

    # Verify
    verify_setup "$PUBLIC_IP"

    # Final instructions
    print_header "Deployment Complete"

    echo -e "${GREEN}Instance Details:${NC}"
    echo -e "  Instance ID:  ${CYAN}$INSTANCE_ID${NC}"
    echo -e "  Region:       ${CYAN}$REGION${NC}"
    echo -e "  Public IP:    ${CYAN}$PUBLIC_IP${NC}"
    echo -e "  Instance Type: ${CYAN}$INSTANCE_TYPE${NC}"
    echo ""

    echo -e "${GREEN}Connect to instance:${NC}"
    echo -e "  ${YELLOW}ssh -i $KEY_FILE ubuntu@$PUBLIC_IP${NC}"
    echo ""

    echo -e "${GREEN}Run test (example):${NC}"
    echo -e "  ${YELLOW}ssh -i $KEY_FILE ubuntu@$PUBLIC_IP${NC}"
    echo -e "  ${YELLOW}cd game-test${NC}"
    echo -e "  ${YELLOW}./test_games_cache_comparison_optimized.sh 5${NC}"
    echo ""

    echo -e "${GREEN}Download results:${NC}"
    echo -e "  ${YELLOW}scp -i $KEY_FILE -r ubuntu@$PUBLIC_IP:/home/ubuntu/game-test/puppeteer_results ./results-mumbai${NC}"
    echo ""

    echo -e "${GREEN}Terminate instance when done:${NC}"
    echo -e "  ${YELLOW}aws --profile $AWS_PROFILE --region $REGION ec2 terminate-instances --instance-ids $INSTANCE_ID${NC}"
    echo ""

    # Save instance info
    INFO_FILE="$PROJECT_ROOT/scripts/ec2/instance-info-${INSTANCE_ID}.txt"
    cat > "$INFO_FILE" <<EOF
Instance ID: $INSTANCE_ID
Region: $REGION
Public IP: $PUBLIC_IP
Key File: $KEY_FILE
Created: $(date)

Connect:
ssh -i $KEY_FILE ubuntu@$PUBLIC_IP

Terminate:
aws --profile $AWS_PROFILE --region $REGION ec2 terminate-instances --instance-ids $INSTANCE_ID
EOF

    print_success "Instance info saved to: $INFO_FILE"
}

# Run main
main "$@"

#!/usr/bin/env bash
#
# Update RDS Storage Alarms for Remaining PROD Instances
#
# 更新 bingo-prd-backstage, bingo-prd-backstage-replica1, bingo-prd-loyalty
# 的告警閾值並添加 Slack 通知
#

set -euo pipefail

PROFILE="gemini-pro_ck"
REGION="ap-east-1"
SNS_TOPIC_ARN="arn:aws:sns:ap-east-1:470013648166:Cloudwatch-Slack-Notification"

# 顏色輸出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=============================================="
echo "Update Remaining PROD RDS Storage Alarms"
echo "=============================================="
echo ""

# ============================================
# bingo-prd-backstage (5024 GB)
# ============================================
echo -e "${BLUE}[1/9] bingo-prd-backstage (5024 GB)${NC}"
echo ""

# Warning: 5024 GB * 15% = 753.6 GB = 808961351680 bytes
echo -e "${YELLOW}Updating Warning alarm (15% = 753.6 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-LowDiskSpace-Warning" \
  --alarm-description "Alert when bingo-prd-backstage free storage < 15% (753.6 GB) - Autoscaling early warning" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 808961351680 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Warning alarm updated with Slack notification${NC}"

# Autoscaling Imminent: 5024 GB * 11% = 552.64 GB = 593356554240 bytes
echo -e "${YELLOW}Creating Autoscaling Imminent alarm (11% = 552.64 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-Autoscaling-Imminent" \
  --alarm-description "Alert when bingo-prd-backstage free storage < 11% (552.64 GB) - Autoscaling will trigger at 10%" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 593356554240 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Autoscaling Imminent alarm created${NC}"

# Critical: Update to add Slack notification
echo -e "${YELLOW}Updating Critical alarm to add Slack notification...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-LowDiskSpace-Critical" \
  --alarm-description "CRITICAL: bingo-prd-backstage free storage < 20 GB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 21474836480 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Critical alarm updated with Slack notification${NC}"
echo ""

# ============================================
# bingo-prd-backstage-replica1 (1465 GB)
# ============================================
echo -e "${BLUE}[2/9] bingo-prd-backstage-replica1 (1465 GB)${NC}"
echo ""

# Warning: 1465 GB * 15% = 219.75 GB = 235930787840 bytes
echo -e "${YELLOW}Updating Warning alarm (15% = 219.75 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-replica1-LowDiskSpace-Warning" \
  --alarm-description "Alert when bingo-prd-backstage-replica1 free storage < 15% (219.75 GB) - Autoscaling early warning" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 235930787840 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Warning alarm updated with Slack notification${NC}"

# Autoscaling Imminent: 1465 GB * 11% = 161.15 GB = 173016244224 bytes
echo -e "${YELLOW}Creating Autoscaling Imminent alarm (11% = 161.15 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-replica1-Autoscaling-Imminent" \
  --alarm-description "Alert when bingo-prd-backstage-replica1 free storage < 11% (161.15 GB) - Autoscaling will trigger at 10%" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 173016244224 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Autoscaling Imminent alarm created${NC}"

# Critical: Update to add Slack notification
echo -e "${YELLOW}Updating Critical alarm to add Slack notification...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-replica1-LowDiskSpace-Critical" \
  --alarm-description "CRITICAL: bingo-prd-backstage-replica1 free storage < 20 GB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 21474836480 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Critical alarm updated with Slack notification${NC}"
echo ""

# ============================================
# bingo-prd-loyalty (200 GB)
# ============================================
echo -e "${BLUE}[3/9] bingo-prd-loyalty (200 GB)${NC}"
echo ""

# Warning: 200 GB * 15% = 30 GB = 32212254720 bytes
echo -e "${YELLOW}Updating Warning alarm (15% = 30 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-loyalty-LowDiskSpace-Warning" \
  --alarm-description "Alert when bingo-prd-loyalty free storage < 15% (30 GB) - Autoscaling early warning" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 32212254720 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-loyalty \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Warning alarm updated with Slack notification${NC}"

# Autoscaling Imminent: 200 GB * 11% = 22 GB = 23622320128 bytes
echo -e "${YELLOW}Creating Autoscaling Imminent alarm (11% = 22 GB)...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-loyalty-Autoscaling-Imminent" \
  --alarm-description "Alert when bingo-prd-loyalty free storage < 11% (22 GB) - Autoscaling will trigger at 10%" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 23622320128 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-loyalty \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Autoscaling Imminent alarm created${NC}"

# Critical: Update to add Slack notification
echo -e "${YELLOW}Updating Critical alarm to add Slack notification...${NC}"
aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-loyalty-LowDiskSpace-Critical" \
  --alarm-description "CRITICAL: bingo-prd-loyalty free storage < 10 GB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 10737418240 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-loyalty \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"
echo -e "${GREEN}✅ Critical alarm updated with Slack notification${NC}"
echo ""

# 顯示摘要
echo "=============================================="
echo -e "${GREEN}✅ All Alarms Updated Successfully!${NC}"
echo "=============================================="
echo ""
echo "Updated Instances:"
echo ""
echo -e "${BLUE}1. bingo-prd-backstage (5024 GB):${NC}"
echo "   ⚠️  Warning (15%):      753.6 GB"
echo "   🔔 Autoscaling (11%):   552.64 GB"
echo "   ⚙️  Autoscaling (10%):   502.4 GB (RDS trigger)"
echo "   🔴 Critical:            20 GB"
echo "   📢 Slack notifications: ✅ Enabled for all levels"
echo ""
echo -e "${BLUE}2. bingo-prd-backstage-replica1 (1465 GB):${NC}"
echo "   ⚠️  Warning (15%):      219.75 GB"
echo "   🔔 Autoscaling (11%):   161.15 GB"
echo "   ⚙️  Autoscaling (10%):   146.5 GB (RDS trigger)"
echo "   🔴 Critical:            20 GB"
echo "   📢 Slack notifications: ✅ Enabled for all levels"
echo ""
echo -e "${BLUE}3. bingo-prd-loyalty (200 GB):${NC}"
echo "   ⚠️  Warning (15%):      30 GB"
echo "   🔔 Autoscaling (11%):   22 GB"
echo "   ⚙️  Autoscaling (10%):   20 GB (RDS trigger)"
echo "   🔴 Critical:            10 GB"
echo "   📢 Slack notifications: ✅ Enabled for all levels"
echo ""
echo "All PROD RDS instances now have:"
echo "  ✅ 15% early warning threshold"
echo "  ✅ 11% autoscaling imminent alert"
echo "  ✅ Slack notifications for all alarm levels"
echo "  ✅ Consistent monitoring across the fleet"
echo ""
echo "View alarms in AWS Console:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:"
echo ""

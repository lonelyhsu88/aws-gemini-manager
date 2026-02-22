#!/usr/bin/env bash
#
# Update RDS Storage Alarms for Autoscaling Early Warning
#
# 更新現有的 bingo-prd 和 bingo-prd-replica1 儲存空間告警
# 將閾值調整為 15%，提前於 autoscaling 10% 閾值預警
#

set -euo pipefail

PROFILE="gemini-pro_ck"
REGION="ap-east-1"
SNS_TOPIC_ARN="arn:aws:sns:ap-east-1:470013648166:Cloudwatch-Slack-Notification"

# 顏色輸出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "Update RDS Storage Alarms Configuration"
echo "========================================="
echo ""

# 1. 更新 bingo-prd Warning 告警 (15% = 412.5 GB)
echo -e "${YELLOW}[1/4] Updating bingo-prd Warning alarm (15% threshold)...${NC}"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-LowDiskSpace-Warning" \
  --alarm-description "Alert when bingo-prd free storage < 15% (412.5 GB) - Autoscaling early warning" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 442654720000 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ bingo-prd Warning updated: < 412.5 GB (15%)${NC}"

# 2. 保持 bingo-prd Critical 告警不變 (20 GB)
echo ""
echo -e "${YELLOW}[2/4] Keeping bingo-prd Critical alarm unchanged (20 GB)...${NC}"
echo -e "${GREEN}✅ bingo-prd Critical: < 20 GB (existing)${NC}"

# 3. 更新 bingo-prd-replica1 Warning 告警並添加 SNS 通知
echo ""
echo -e "${YELLOW}[3/4] Updating bingo-prd-replica1 Warning alarm + adding Slack notification...${NC}"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-replica1-LowDiskSpace-Warning" \
  --alarm-description "Alert when bingo-prd-replica1 free storage < 15% (439.35 GB) - Autoscaling early warning" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 471669964800 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ bingo-prd-replica1 Warning updated: < 439.35 GB (15%)${NC}"
echo -e "${GREEN}✅ Added Slack notification via SNS${NC}"

# 4. 更新 bingo-prd-replica1 Critical 告警並添加 SNS 通知
echo ""
echo -e "${YELLOW}[4/4] Updating bingo-prd-replica1 Critical alarm + adding Slack notification...${NC}"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-replica1-LowDiskSpace-Critical" \
  --alarm-description "CRITICAL: bingo-prd-replica1 free storage < 20 GB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 21474836480 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ bingo-prd-replica1 Critical updated: < 20 GB${NC}"
echo -e "${GREEN}✅ Added Slack notification via SNS${NC}"

# 5. 顯示摘要
echo ""
echo "========================================="
echo -e "${GREEN}✅ Update Complete!${NC}"
echo "========================================="
echo ""
echo "Updated Alarm Configuration:"
echo ""
echo "bingo-prd (2750 GB capacity):"
echo "  ⚠️  Warning:  < 412.5 GB (15%) - Current: ~325 GB ⚠️ WILL TRIGGER SOON"
echo "  🔴 Critical: < 20 GB (0.7%)"
echo ""
echo "bingo-prd-replica1 (2929 GB capacity):"
echo "  ⚠️  Warning:  < 439.35 GB (15%) - Current: ~530 GB ✅ OK"
echo "  🔴 Critical: < 20 GB (0.7%)"
echo ""
echo "Notification:"
echo "  📢 SNS Topic: Cloudwatch-Slack-Notification"
echo "  💬 Destination: Slack channel (via Lambda)"
echo ""
echo "Autoscaling Reference:"
echo "  RDS triggers autoscaling when free space < 10%"
echo "  - bingo-prd: < 275 GB"
echo "  - bingo-prd-replica1: < 292.9 GB"
echo ""
echo "View alarms in AWS Console:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:"
echo ""
echo "Expected behavior:"
echo "  1. bingo-prd Warning will trigger soon (~325 GB < 412.5 GB)"
echo "  2. Slack notification will be sent"
echo "  3. Monitor for autoscaling event (< 275 GB)"
echo ""

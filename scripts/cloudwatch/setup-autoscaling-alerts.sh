#!/usr/bin/env bash
#
# Setup Autoscaling Trigger Alerts for RDS Storage
#
# 在即將觸發 autoscaling (10%) 時發送告警
# 閾值設定為 11% 提供即時通知
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

echo "========================================="
echo "Setup RDS Autoscaling Trigger Alerts"
echo "========================================="
echo ""

# bingo-prd: 2750 GB * 11% = 302.5 GB = 324650229760 bytes
echo -e "${YELLOW}[1/2] Creating bingo-prd Autoscaling Imminent alarm (11% threshold)...${NC}"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-Autoscaling-Imminent" \
  --alarm-description "Alert when bingo-prd free storage < 11% (302.5 GB) - Autoscaling will trigger at 10%" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 324650229760 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ bingo-prd Autoscaling Imminent alarm created: < 302.5 GB (11%)${NC}"

# bingo-prd-replica1: 2929 GB * 11% = 322.19 GB = 345848504320 bytes
echo ""
echo -e "${YELLOW}[2/2] Creating bingo-prd-replica1 Autoscaling Imminent alarm (11% threshold)...${NC}"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-replica1-Autoscaling-Imminent" \
  --alarm-description "Alert when bingo-prd-replica1 free storage < 11% (322.19 GB) - Autoscaling will trigger at 10%" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 345848504320 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --ok-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ bingo-prd-replica1 Autoscaling Imminent alarm created: < 322.19 GB (11%)${NC}"

# 顯示摘要
echo ""
echo "========================================="
echo -e "${GREEN}✅ Autoscaling Alert Setup Complete!${NC}"
echo "========================================="
echo ""
echo "Alarm Thresholds Summary:"
echo ""
echo -e "${BLUE}bingo-prd (2750 GB capacity):${NC}"
echo "  ⚠️  Warning (15%):      < 412.5 GB  - Early warning"
echo "  🔔 Autoscaling (11%):   < 302.5 GB  - Imminent autoscaling notification"
echo "  ⚙️  Autoscaling (10%):   < 275 GB   - RDS automatic trigger"
echo "  🔴 Critical (20 GB):    < 20 GB     - Emergency"
echo ""
echo -e "${BLUE}bingo-prd-replica1 (2929 GB capacity):${NC}"
echo "  ⚠️  Warning (15%):      < 439.35 GB - Early warning"
echo "  🔔 Autoscaling (11%):   < 322.19 GB - Imminent autoscaling notification"
echo "  ⚙️  Autoscaling (10%):   < 292.9 GB  - RDS automatic trigger"
echo "  🔴 Critical (20 GB):    < 20 GB     - Emergency"
echo ""
echo "Notification:"
echo "  📢 SNS Topic: Cloudwatch-Slack-Notification"
echo "  💬 Destination: Slack channel"
echo ""
echo "Current Status (bingo-prd):"
echo "  Free Space: ~326 GB (11.8%)"
echo "  Status: Between Warning (15%) and Autoscaling (11%) thresholds"
echo "  Expected: Will trigger Autoscaling Imminent alarm soon"
echo ""
echo "View alarms in AWS Console:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:"
echo ""

#!/usr/bin/env bash
#
# RDS Storage Space Monitoring - CloudWatch Alarms Setup
#
# 功能：為 bingo-prd 和 bingo-prd-replica1 設定儲存空間告警
# 觸發條件：可用空間 < 15% (提前於 autoscaling 10% 閾值預警)
#
# 使用方式：
#   ./setup-rds-storage-alarms.sh [email]
#
# 範例：
#   ./setup-rds-storage-alarms.sh ops-alerts@ftgaming.cc

set -euo pipefail

PROFILE="gemini-pro_ck"
REGION="ap-east-1"
SNS_TOPIC_NAME="rds-storage-autoscaling-alerts"

# 接收通知的 Email（從參數或預設值）
ALERT_EMAIL="${1:-ops-alerts@ftgaming.cc}"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "RDS Storage Space Monitoring Setup"
echo "========================================="
echo ""
echo "Profile: ${PROFILE}"
echo "Region: ${REGION}"
echo "Alert Email: ${ALERT_EMAIL}"
echo ""

# 1. 創建或獲取 SNS Topic
echo -e "${YELLOW}[1/4] Setting up SNS Topic...${NC}"

SNS_TOPIC_ARN=$(aws --profile "${PROFILE}" sns list-topics \
  --region "${REGION}" \
  --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
  --output text)

if [ -z "${SNS_TOPIC_ARN}" ]; then
  echo "Creating new SNS topic: ${SNS_TOPIC_NAME}"
  SNS_TOPIC_ARN=$(aws --profile "${PROFILE}" sns create-topic \
    --name "${SNS_TOPIC_NAME}" \
    --region "${REGION}" \
    --tags Key=Environment,Value=Production Key=Service,Value=RDS Key=Alert,Value=Storage \
    --query 'TopicArn' \
    --output text)
  echo -e "${GREEN}✅ SNS Topic created: ${SNS_TOPIC_ARN}${NC}"
else
  echo -e "${GREEN}✅ Using existing SNS Topic: ${SNS_TOPIC_ARN}${NC}"
fi

# 2. 訂閱 Email 通知
echo ""
echo -e "${YELLOW}[2/4] Subscribing email to SNS Topic...${NC}"

# 檢查是否已訂閱
EXISTING_SUBSCRIPTION=$(aws --profile "${PROFILE}" sns list-subscriptions-by-topic \
  --topic-arn "${SNS_TOPIC_ARN}" \
  --region "${REGION}" \
  --query "Subscriptions[?Endpoint=='${ALERT_EMAIL}'].SubscriptionArn" \
  --output text)

if [ -z "${EXISTING_SUBSCRIPTION}" ] || [ "${EXISTING_SUBSCRIPTION}" == "None" ]; then
  aws --profile "${PROFILE}" sns subscribe \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint "${ALERT_EMAIL}" \
    --region "${REGION}" > /dev/null
  echo -e "${GREEN}✅ Email subscription created: ${ALERT_EMAIL}${NC}"
  echo -e "${YELLOW}⚠️  Please check your email and confirm the subscription!${NC}"
else
  echo -e "${GREEN}✅ Email already subscribed: ${ALERT_EMAIL}${NC}"
fi

# 3. 為 bingo-prd 創建告警
echo ""
echo -e "${YELLOW}[3/4] Creating alarm for bingo-prd...${NC}"

# bingo-prd: 2750 GB, 15% = 412.5 GB = 442,654,720,000 bytes
BINGO_PRD_THRESHOLD="442654720000"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-storage-low-space" \
  --alarm-description "Alert when bingo-prd free storage space < 15% (approaching autoscaling threshold)" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold "${BINGO_PRD_THRESHOLD}" \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ Alarm created: bingo-prd-storage-low-space${NC}"
echo "   Threshold: < 412.5 GB (15% of 2750 GB)"
echo "   Evaluation: 2 periods of 5 minutes"

# 4. 為 bingo-prd-replica1 創建告警
echo ""
echo -e "${YELLOW}[4/4] Creating alarm for bingo-prd-replica1...${NC}"

# bingo-prd-replica1: 2929 GB, 15% = 439.35 GB = 471,669,964,800 bytes
BINGO_REPLICA1_THRESHOLD="471669964800"

aws --profile "${PROFILE}" cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-replica1-storage-low-space" \
  --alarm-description "Alert when bingo-prd-replica1 free storage space < 15% (approaching autoscaling threshold)" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold "${BINGO_REPLICA1_THRESHOLD}" \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1 \
  --alarm-actions "${SNS_TOPIC_ARN}" \
  --treat-missing-data notBreaching \
  --region "${REGION}"

echo -e "${GREEN}✅ Alarm created: bingo-prd-replica1-storage-low-space${NC}"
echo "   Threshold: < 439.35 GB (15% of 2929 GB)"
echo "   Evaluation: 2 periods of 5 minutes"

# 5. 顯示摘要
echo ""
echo "========================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "========================================="
echo ""
echo "SNS Topic ARN:"
echo "  ${SNS_TOPIC_ARN}"
echo ""
echo "Email Subscription:"
echo "  ${ALERT_EMAIL}"
if [ -z "${EXISTING_SUBSCRIPTION}" ] || [ "${EXISTING_SUBSCRIPTION}" == "None" ]; then
  echo -e "  ${YELLOW}Status: Pending Confirmation${NC}"
  echo -e "  ${YELLOW}Action: Check your email and confirm subscription${NC}"
else
  echo -e "  ${GREEN}Status: Confirmed${NC}"
fi
echo ""
echo "CloudWatch Alarms Created:"
echo "  1. bingo-prd-storage-low-space"
echo "     - Threshold: < 412.5 GB (15%)"
echo "     - Current: ~325 GB (11.8%) ⚠️ WILL TRIGGER SOON"
echo ""
echo "  2. bingo-prd-replica1-storage-low-space"
echo "     - Threshold: < 439.35 GB (15%)"
echo "     - Current: ~530 GB (18.1%) ✅ OK"
echo ""
echo "View alarms in AWS Console:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:"
echo ""
echo "Next Steps:"
echo "  1. Confirm email subscription (check inbox)"
echo "  2. Monitor alarm status in CloudWatch console"
echo "  3. Wait for alert when storage drops below 15%"
echo ""

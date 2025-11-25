#!/bin/bash
# ========================================
# 設定 Zabbix Server 磁碟監控告警
# ========================================
# 前提: 已安裝 CloudWatch Agent
# Usage: ./setup-zabbix-disk-alerts.sh <email>

set -e

export AWS_PROFILE=gemini-pro_ck
INSTANCE_ID="i-040c741a76a42169b"
INSTANCE_NAME="gemini-monitor-01"

# 檢查是否提供 email
if [ -z "$1" ]; then
    echo "❌ 錯誤: 請提供告警通知 email"
    echo "用法: $0 <your-email@example.com>"
    exit 1
fi

EMAIL="$1"

echo "========================================"
echo "📧 設定 Zabbix Server 磁碟監控告警"
echo "========================================"
echo "實例: $INSTANCE_NAME ($INSTANCE_ID)"
echo "通知 Email: $EMAIL"
echo ""

# Step 1: 建立 SNS Topic
echo "📝 Step 1: 建立 SNS Topic..."
SNS_TOPIC_NAME="zabbix-disk-alert"

# 檢查 topic 是否已存在
EXISTING_TOPIC=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

if [ -n "$EXISTING_TOPIC" ]; then
    echo "ℹ️  SNS Topic 已存在: $EXISTING_TOPIC"
    SNS_ARN="$EXISTING_TOPIC"
else
    SNS_ARN=$(aws sns create-topic \
      --name $SNS_TOPIC_NAME \
      --query 'TopicArn' \
      --output text)
    echo "✅ SNS Topic 建立完成: $SNS_ARN"
fi

# Step 2: 訂閱 Email
echo ""
echo "📧 Step 2: 設定 Email 訂閱..."

# 檢查是否已訂閱
EXISTING_SUB=$(aws sns list-subscriptions-by-topic \
  --topic-arn $SNS_ARN \
  --query "Subscriptions[?Endpoint=='$EMAIL'].SubscriptionArn" \
  --output text)

if [ -n "$EXISTING_SUB" ] && [ "$EXISTING_SUB" != "PendingConfirmation" ]; then
    echo "ℹ️  Email 已訂閱: $EMAIL"
else
    aws sns subscribe \
      --topic-arn $SNS_ARN \
      --protocol email \
      --notification-endpoint $EMAIL > /dev/null
    echo "✅ Email 訂閱請求已送出: $EMAIL"
    echo "⚠️  請檢查您的信箱並確認訂閱！"
fi

# Step 3: 建立 CloudWatch 告警
echo ""
echo "🔔 Step 3: 建立 CloudWatch 告警..."

# 告警 1: 磁碟使用率 > 80% (警告)
echo ""
echo "  📊 設定 80% 警告告警..."
aws cloudwatch put-metric-alarm \
  --alarm-name "zabbix-server-disk-usage-80-percent" \
  --alarm-description "Warning: Zabbix server disk usage > 80%" \
  --actions-enabled \
  --alarm-actions $SNS_ARN \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching

if [ $? -eq 0 ]; then
    echo "  ✅ 80% 警告告警設定完成"
else
    echo "  ⚠️  80% 告警設定失敗（可能是因為 CloudWatch Agent 未啟動或 metric 不存在）"
fi

# 告警 2: 磁碟使用率 > 90% (緊急)
echo ""
echo "  🚨 設定 90% 緊急告警..."
aws cloudwatch put-metric-alarm \
  --alarm-name "zabbix-server-disk-usage-90-percent-critical" \
  --alarm-description "CRITICAL: Zabbix server disk usage > 90%" \
  --actions-enabled \
  --alarm-actions $SNS_ARN \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 90 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching

if [ $? -eq 0 ]; then
    echo "  ✅ 90% 緊急告警設定完成"
else
    echo "  ⚠️  90% 告警設定失敗（可能是因為 CloudWatch Agent 未啟動或 metric 不存在）"
fi

# 告警 3: 磁碟使用率 > 95% (嚴重)
echo ""
echo "  🔴 設定 95% 嚴重告警..."
aws cloudwatch put-metric-alarm \
  --alarm-name "zabbix-server-disk-usage-95-percent-severe" \
  --alarm-description "SEVERE: Zabbix server disk usage > 95%" \
  --actions-enabled \
  --alarm-actions $SNS_ARN \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching

if [ $? -eq 0 ]; then
    echo "  ✅ 95% 嚴重告警設定完成"
else
    echo "  ⚠️  95% 告警設定失敗（可能是因為 CloudWatch Agent 未啟動或 metric 不存在）"
fi

# Step 4: 驗證設定
echo ""
echo "========================================"
echo "✅ 告警設定完成"
echo "========================================"
echo ""
echo "📋 已建立的告警："
aws cloudwatch describe-alarms \
  --alarm-name-prefix "zabbix-server-disk" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,Threshold,ComparisonOperator]' \
  --output table

echo ""
echo "📧 SNS 訂閱狀態："
aws sns list-subscriptions-by-topic \
  --topic-arn $SNS_ARN \
  --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' \
  --output table

echo ""
echo "========================================"
echo "⚠️  重要提示"
echo "========================================"
echo ""
echo "1. 📧 如果這是第一次訂閱，請檢查信箱並確認訂閱"
echo "2. 🔧 確認 CloudWatch Agent 已安裝並運行："
echo "   ssh <zabbix-server>"
echo "   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2 -c default"
echo ""
echo "3. 📊 檢查 CloudWatch metric 是否有資料："
echo "   aws --profile gemini-pro_ck cloudwatch get-metric-statistics \\"
echo "     --namespace CWAgent \\"
echo "     --metric-name disk_used_percent \\"
echo "     --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=path,Value=/ \\"
echo "     --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \\"
echo "     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "     --period 300 \\"
echo "     --statistics Average"
echo ""
echo "4. 🧪 測試告警（可選）："
echo "   aws --profile gemini-pro_ck cloudwatch set-alarm-state \\"
echo "     --alarm-name zabbix-server-disk-usage-80-percent \\"
echo "     --state-value ALARM \\"
echo "     --state-reason 'Testing alarm'"
echo ""
echo "========================================"

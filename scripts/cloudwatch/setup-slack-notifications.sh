#!/bin/bash
#
# 配置 CloudWatch 告警发送到 Slack
#
# 前置要求：
# 1. Slack Incoming Webhook URL
# 2. AWS Lambda 函数（将 SNS 转发到 Slack）
#
# 用法: ./setup-slack-notifications.sh
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

AWS_PROFILE="gemini-pro_ck"
AWS_REGION="us-east-1"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}🔔 配置 RDS 告警发送到 Slack${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""

# 步骤说明
cat << 'EOF'
配置步骤：
  1️⃣  创建 SNS Topic
  2️⃣  配置 Lambda 函数（SNS → Slack）
  3️⃣  更新告警配置
  4️⃣  发送测试通知

EOF

echo -e "${YELLOW}${BOLD}⚠️  在开始之前，你需要准备：${NC}"
echo -e "${YELLOW}  - Slack Incoming Webhook URL${NC}"
echo -e "${YELLOW}  - 如何获取: https://api.slack.com/messaging/webhooks${NC}"
echo ""

read -p "是否已经有 Slack Webhook URL？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}请先创建 Slack Incoming Webhook:${NC}"
    echo "  1. 访问: https://api.slack.com/messaging/webhooks"
    echo "  2. 点击 'Create your Slack app'"
    echo "  3. 选择 'From scratch'"
    echo "  4. 输入 App Name (例如: RDS Alerts) 和选择 Workspace"
    echo "  5. 启用 'Incoming Webhooks'"
    echo "  6. 点击 'Add New Webhook to Workspace'"
    echo "  7. 选择要发送通知的频道"
    echo "  8. 复制 Webhook URL"
    echo ""
    exit 0
fi

echo ""
echo -e "${CYAN}请输入 Slack Webhook URL:${NC}"
read -r SLACK_WEBHOOK_URL

if [[ ! $SLACK_WEBHOOK_URL =~ ^https://hooks.slack.com/services/ ]]; then
    echo -e "${RED}错误：无效的 Slack Webhook URL${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Slack Webhook URL 验证通过${NC}"
echo ""

# 步骤 1: 创建 SNS Topic
echo -e "${CYAN}${BOLD}步骤 1/4: 创建 SNS Topic${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

SNS_TOPIC_NAME="rds-bingo-prd-alerts"

# 检查 Topic 是否已存在
EXISTING_TOPIC=$(aws --profile "$AWS_PROFILE" sns list-topics \
    --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_TOPIC" ]; then
    echo -e "${YELLOW}⚠️  SNS Topic 已存在: ${EXISTING_TOPIC}${NC}"
    SNS_TOPIC_ARN="$EXISTING_TOPIC"
else
    echo "创建 SNS Topic..."
    SNS_TOPIC_ARN=$(aws --profile "$AWS_PROFILE" sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' \
        --output text)
    echo -e "${GREEN}✓ SNS Topic 创建成功${NC}"
fi

echo "Topic ARN: ${SNS_TOPIC_ARN}"
echo ""

# 步骤 2: 创建 Lambda 函数
echo -e "${CYAN}${BOLD}步骤 2/4: 创建 Lambda 函数 (SNS → Slack)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

LAMBDA_FUNCTION_NAME="rds-alerts-to-slack"

# 创建 Lambda 函数代码
cat > /tmp/lambda_function.py << 'PYTHON_CODE'
import json
import urllib3
import os

http = urllib3.PoolManager()

def lambda_handler(event, context):
    slack_webhook_url = os.environ['SLACK_WEBHOOK_URL']

    # 解析 SNS 消息
    message = json.loads(event['Records'][0]['Sns']['Message'])

    # 提取告警信息
    alarm_name = message.get('AlarmName', 'Unknown')
    alarm_description = message.get('AlarmDescription', '')
    new_state = message.get('NewStateValue', 'UNKNOWN')
    reason = message.get('NewStateReason', '')
    timestamp = message.get('StateChangeTime', '')

    # 提取指标信息
    trigger = message.get('Trigger', {})
    metric_name = trigger.get('MetricName', '')
    threshold = trigger.get('Threshold', '')
    namespace = trigger.get('Namespace', '')

    # 确定颜色
    if new_state == 'ALARM':
        color = '#FF0000'  # 红色
        emoji = '🚨'
    elif new_state == 'OK':
        color = '#36A64F'  # 绿色
        emoji = '✅'
    else:
        color = '#FFA500'  # 橙色
        emoji = '⚠️'

    # 构建 Slack 消息
    slack_message = {
        'attachments': [{
            'color': color,
            'title': f'{emoji} RDS Alert: {alarm_name}',
            'text': alarm_description,
            'fields': [
                {
                    'title': 'Status',
                    'value': new_state,
                    'short': True
                },
                {
                    'title': 'Metric',
                    'value': f'{namespace} - {metric_name}',
                    'short': True
                },
                {
                    'title': 'Threshold',
                    'value': str(threshold),
                    'short': True
                },
                {
                    'title': 'Time',
                    'value': timestamp,
                    'short': True
                },
                {
                    'title': 'Reason',
                    'value': reason,
                    'short': False
                }
            ],
            'footer': 'AWS CloudWatch',
            'ts': int(context.aws_request_id[:8], 16)
        }]
    }

    # 发送到 Slack
    encoded_msg = json.dumps(slack_message).encode('utf-8')
    resp = http.request('POST', slack_webhook_url, body=encoded_msg,
                       headers={'Content-Type': 'application/json'})

    print(f"Response status: {resp.status}")

    return {
        'statusCode': 200,
        'body': json.dumps('Message sent to Slack')
    }
PYTHON_CODE

# 打包 Lambda 函数
cd /tmp
zip lambda_function.zip lambda_function.py
cd - > /dev/null

echo "检查 Lambda 函数是否存在..."
LAMBDA_EXISTS=$(aws --profile "$AWS_PROFILE" lambda get-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --query 'Configuration.FunctionArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$LAMBDA_EXISTS" ]; then
    echo -e "${YELLOW}⚠️  Lambda 函数已存在，将更新代码...${NC}"

    aws --profile "$AWS_PROFILE" lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file fileb:///tmp/lambda_function.zip > /dev/null

    aws --profile "$AWS_PROFILE" lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" > /dev/null

    LAMBDA_ARN="$LAMBDA_EXISTS"
    echo -e "${GREEN}✓ Lambda 函数更新成功${NC}"
else
    echo "创建 IAM Role for Lambda..."

    # 创建信任策略
    cat > /tmp/trust-policy.json << 'TRUST_POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST_POLICY

    ROLE_NAME="rds-alerts-lambda-role"

    ROLE_ARN=$(aws --profile "$AWS_PROFILE" iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --query 'Role.Arn' \
        --output text 2>/dev/null || \
        aws --profile "$AWS_PROFILE" iam get-role \
        --role-name "$ROLE_NAME" \
        --query 'Role.Arn' \
        --output text)

    # 附加基本执行策略
    aws --profile "$AWS_PROFILE" iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

    echo "等待 IAM Role 生效..."
    sleep 10

    echo "创建 Lambda 函数..."
    LAMBDA_ARN=$(aws --profile "$AWS_PROFILE" lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda_function.zip \
        --environment "Variables={SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}}" \
        --timeout 30 \
        --query 'FunctionArn' \
        --output text)

    echo -e "${GREEN}✓ Lambda 函数创建成功${NC}"
fi

echo "Lambda ARN: ${LAMBDA_ARN}"
echo ""

# 步骤 3: 配置 SNS 订阅 Lambda
echo -e "${CYAN}${BOLD}步骤 3/4: 配置 SNS 订阅 Lambda${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

echo "添加 Lambda 权限允许 SNS 调用..."
aws --profile "$AWS_PROFILE" lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id sns-invoke \
    --action lambda:InvokeFunction \
    --principal sns.amazonaws.com \
    --source-arn "$SNS_TOPIC_ARN" 2>/dev/null || echo "权限已存在"

echo "创建 SNS 订阅..."
SUBSCRIPTION_ARN=$(aws --profile "$AWS_PROFILE" sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol lambda \
    --notification-endpoint "$LAMBDA_ARN" \
    --query 'SubscriptionArn' \
    --output text 2>/dev/null)

if [[ "$SUBSCRIPTION_ARN" == *"pending"* ]]; then
    echo -e "${YELLOW}⚠️  订阅等待确认${NC}"
else
    echo -e "${GREEN}✓ SNS 订阅配置成功${NC}"
fi

echo ""

# 步骤 4: 发送测试通知
echo -e "${CYAN}${BOLD}步骤 4/4: 发送测试通知${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

read -p "是否发送测试消息到 Slack？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "发送测试消息..."

    TEST_MESSAGE=$(cat << EOF
{
  "AlarmName": "RDS-bingo-prd-TEST",
  "AlarmDescription": "这是一条测试告警消息",
  "NewStateValue": "ALARM",
  "NewStateReason": "测试告警 - CloudWatch 告警配置成功！",
  "StateChangeTime": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "Trigger": {
    "MetricName": "DBLoad",
    "Namespace": "AWS/RDS",
    "Threshold": 3.0
  }
}
EOF
)

    aws --profile "$AWS_PROFILE" sns publish \
        --topic-arn "$SNS_TOPIC_ARN" \
        --message "$TEST_MESSAGE" \
        --subject "RDS Alert Test" > /dev/null

    echo -e "${GREEN}✓ 测试消息已发送！请检查 Slack 频道${NC}"
fi

echo ""

# 总结
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}${BOLD}✅ 配置完成！${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""
echo -e "${CYAN}配置摘要:${NC}"
echo "  SNS Topic: ${SNS_TOPIC_ARN}"
echo "  Lambda Function: ${LAMBDA_ARN}"
echo ""
echo -e "${CYAN}下一步 - 更新告警配置:${NC}"
echo -e "  使用以下命令为 bingo-prd 的告警添加 Slack 通知:"
echo ""
echo -e "  ${YELLOW}./create-rds-alarms.sh bingo-prd ${SNS_TOPIC_ARN}${NC}"
echo ""
echo -e "${CYAN}或者只更新单个告警:${NC}"
echo ""
cat << EXAMPLE
  aws --profile gemini-pro_ck cloudwatch put-metric-alarm \\
    --alarm-name RDS-bingo-prd-HighDBLoad-Critical \\
    --alarm-description "数据库负载超过 4 (2x vCPUs)" \\
    --namespace AWS/RDS \\
    --metric-name DBLoad \\
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \\
    --statistic Average \\
    --period 60 \\
    --evaluation-periods 3 \\
    --datapoints-to-alarm 3 \\
    --threshold 4 \\
    --comparison-operator GreaterThanThreshold \\
    --alarm-actions ${SNS_TOPIC_ARN}
EXAMPLE

echo ""
echo -e "${GREEN}✓ 所有配置完成！${NC}"
echo -e "${BLUE}================================================================================================${NC}"

# 清理临时文件
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/trust-policy.json

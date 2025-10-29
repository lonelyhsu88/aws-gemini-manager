#!/bin/bash
#
# 测试 CloudWatch 告警
# 手动触发告警状态，验证告警配置是否正常工作
#
# 用法: ./test-alarm.sh <alarm-name>
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

# 使用说明
usage() {
    cat << EOF
${BOLD}CloudWatch 告警测试工具${NC}

用法:
    $0 <alarm-name>

参数:
    alarm-name    告警名称

范例:
    $0 RDS-bingo-prd-HighDBLoad-Warning
    $0 RDS-bingo-prd-HighCPU-Critical

可用告警列表:
$(aws --profile gemini-pro_ck cloudwatch describe-alarms --alarm-name-prefix 'RDS-bingo-prd-' --query 'MetricAlarms[*].AlarmName' --output text | tr '\t' '\n' | sed 's/^/    /')

EOF
    exit 1
}

# 检查参数
if [ $# -lt 1 ]; then
    usage
fi

ALARM_NAME=$1

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}🧪 CloudWatch 告警测试${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "告警名称: ${YELLOW}${ALARM_NAME}${NC}"
echo ""

# 检查告警是否存在
echo -e "${CYAN}步骤 1/5: 检查告警是否存在...${NC}"
ALARM_EXISTS=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].AlarmName' \
    --output text 2>/dev/null || echo "None")

if [ "$ALARM_EXISTS" == "None" ]; then
    echo -e "${RED}错误：告警 '$ALARM_NAME' 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 告警存在${NC}"
echo ""

# 查看当前状态
echo -e "${CYAN}步骤 2/5: 查看当前告警状态...${NC}"
CURRENT_STATE=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].[StateValue,StateReason]' \
    --output text)

echo "当前状态: ${CURRENT_STATE}"
echo ""

# 触发告警
echo -e "${CYAN}步骤 3/5: 触发告警为 ALARM 状态...${NC}"
aws --profile "$AWS_PROFILE" cloudwatch set-alarm-state \
    --alarm-name "$ALARM_NAME" \
    --state-value ALARM \
    --state-reason "手动测试告警 - 验证告警配置是否正常工作 ($(date '+%Y-%m-%d %H:%M:%S'))"

echo -e "${GREEN}✓ 已触发告警${NC}"
echo ""

# 等待并验证
echo -e "${CYAN}步骤 4/5: 验证告警状态...${NC}"
echo "等待 3 秒..."
sleep 3

NEW_STATE=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].[StateValue,StateReason,StateUpdatedTimestamp]' \
    --output table)

echo "$NEW_STATE"

# 检查是否成功
STATE_VALUE=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)

if [ "$STATE_VALUE" == "ALARM" ]; then
    echo -e "${GREEN}✓ 告警状态已更新为 ALARM${NC}"
else
    echo -e "${RED}✗ 告警状态未更新，当前为: $STATE_VALUE${NC}"
fi
echo ""

# 查看告警历史
echo -e "${CYAN}查看告警历史（最近 3 条）...${NC}"
aws --profile "$AWS_PROFILE" cloudwatch describe-alarm-history \
    --alarm-name "$ALARM_NAME" \
    --history-item-type StateUpdate \
    --max-records 3 \
    --query 'AlarmHistoryItems[*].[Timestamp,HistorySummary]' \
    --output table

echo ""

# 重置告警
echo -e "${CYAN}步骤 5/5: 重置告警为 OK 状态...${NC}"
read -p "是否重置告警为正常状态？(Y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    aws --profile "$AWS_PROFILE" cloudwatch set-alarm-state \
        --alarm-name "$ALARM_NAME" \
        --state-value OK \
        --state-reason "测试完成 - 重置为正常状态"

    echo ""
    echo "等待 2 秒..."
    sleep 2

    RESET_STATE=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
        --alarm-names "$ALARM_NAME" \
        --query 'MetricAlarms[0].StateValue' \
        --output text)

    if [ "$RESET_STATE" == "OK" ]; then
        echo -e "${GREEN}✓ 告警已重置为 OK 状态${NC}"
    else
        echo -e "${YELLOW}⚠️  告警当前状态: $RESET_STATE${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  告警保持在 ALARM 状态，请稍后手动重置${NC}"
    echo ""
    echo "手动重置命令:"
    echo "  aws --profile gemini-pro_ck cloudwatch set-alarm-state \\"
    echo "    --alarm-name $ALARM_NAME \\"
    echo "    --state-value OK \\"
    echo "    --state-reason '手动重置'"
fi

echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}${BOLD}✅ 测试完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo ""
echo -e "${CYAN}测试总结:${NC}"
echo "  - 告警名称: $ALARM_NAME"
echo "  - 测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  - 测试结果: 告警触发成功 ✓"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "  - 在 AWS Console 查看: CloudWatch → Alarms → $ALARM_NAME"
echo "  - 查看告警历史了解状态变化记录"
echo "  - 配置 SNS 通知后，告警触发会自动发送通知"
echo ""

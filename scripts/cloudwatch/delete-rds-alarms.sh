#!/bin/bash
#
# 删除 RDS CloudWatch 告警
#
# 用法: ./delete-rds-alarms.sh <instance-id>
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AWS_PROFILE="gemini-pro_ck"

if [ $# -lt 1 ]; then
    echo "用法: $0 <instance-id>"
    echo "范例: $0 bingo-prd"
    exit 1
fi

INSTANCE_ID=$1

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${YELLOW}🗑️  删除 RDS CloudWatch 告警${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "实例: ${YELLOW}${INSTANCE_ID}${NC}"
echo ""

# 获取所有告警
ALARMS=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-name-prefix "RDS-${INSTANCE_ID}-" \
    --query 'MetricAlarms[*].AlarmName' \
    --output text)

if [ -z "$ALARMS" ]; then
    echo -e "${YELLOW}未找到告警${NC}"
    exit 0
fi

echo -e "${CYAN}找到以下告警:${NC}"
for alarm in $ALARMS; do
    echo "  - $alarm"
done
echo ""

read -p "确认删除这些告警？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}开始删除...${NC}"
for alarm in $ALARMS; do
    echo -e "${CYAN}删除: $alarm${NC}"
    aws --profile "$AWS_PROFILE" cloudwatch delete-alarms --alarm-names "$alarm"
done

echo ""
echo -e "${GREEN}✅ 删除完成${NC}"

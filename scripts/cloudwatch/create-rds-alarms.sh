#!/bin/bash
#
# 创建 RDS CloudWatch 告警
# 针对 bingo-prd 数据库的关键指标设置告警
#
# 用法: ./create-rds-alarms.sh [instance-id] [sns-topic-arn]
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

# AWS Profile
AWS_PROFILE="gemini-pro_ck"

# 使用说明
usage() {
    cat << EOF
${BOLD}RDS CloudWatch 告警创建工具${NC}

用法:
    $0 <instance-id> [sns-topic-arn]

参数:
    instance-id      RDS 实例标识符 (必需)
    sns-topic-arn    SNS Topic ARN for notifications (可选)
                     如果不提供，将创建但不发送通知

范例:
    # 仅创建告警（无通知）
    $0 bingo-prd

    # 创建告警并配置 SNS 通知
    $0 bingo-prd arn:aws:sns:us-east-1:123456789012:rds-alerts

可用实例:
    - bingo-prd
    - bingo-prd-backstage
    - bingo-prd-loyalty
    - bingo-stress

EOF
    exit 1
}

# 检查 AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}错误：未找到 aws 命令${NC}"
    exit 1
fi

# 检查参数
if [ $# -lt 1 ]; then
    usage
fi

INSTANCE_ID=$1
SNS_TOPIC_ARN=${2:-""}

# 获取实例配置的函数
get_instance_config() {
    local instance_id=$1
    case "$instance_id" in
        bingo-prd)
            echo "db.m6g.large:2"
            ;;
        bingo-prd-backstage)
            echo "db.m6g.large:2"
            ;;
        bingo-prd-loyalty)
            echo "db.t4g.medium:2"
            ;;
        bingo-prd-replica1)
            echo "db.m6g.large:2"
            ;;
        bingo-prd-backstage-replica1)
            echo "db.t4g.medium:2"
            ;;
        bingo-stress)
            echo "db.t4g.medium:2"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 获取实例配置
INSTANCE_INFO=$(get_instance_config "$INSTANCE_ID")
if [ -z "$INSTANCE_INFO" ]; then
    echo -e "${RED}错误：未知的实例 '$INSTANCE_ID'${NC}"
    echo -e "${YELLOW}可用实例: bingo-prd, bingo-prd-backstage, bingo-prd-loyalty, bingo-stress${NC}"
    exit 1
fi

IFS=':' read -r INSTANCE_TYPE VCPUS <<< "$INSTANCE_INFO"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}📊 创建 RDS CloudWatch 告警${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "实例: ${YELLOW}${INSTANCE_ID}${NC}"
echo -e "类型: ${YELLOW}${INSTANCE_TYPE}${NC}"
echo -e "vCPUs: ${YELLOW}${VCPUS}${NC}"
if [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "通知: ${YELLOW}${SNS_TOPIC_ARN}${NC}"
else
    echo -e "通知: ${YELLOW}未配置 (告警将被创建但不发送通知)${NC}"
fi
echo ""

# 检查是否已有告警
echo -e "${CYAN}检查现有告警...${NC}"
EXISTING_ALARMS=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-name-prefix "RDS-${INSTANCE_ID}-" \
    --query 'MetricAlarms[*].AlarmName' \
    --output text 2>/dev/null)

if [ -n "$EXISTING_ALARMS" ]; then
    ALARM_COUNT=$(echo "$EXISTING_ALARMS" | wc -w | tr -d ' ')
    echo -e "${YELLOW}⚠️  发现 ${ALARM_COUNT} 个现有告警：${NC}"
    for alarm in $EXISTING_ALARMS; do
        echo "  - $alarm"
    done
    echo ""
    echo -e "${YELLOW}继续执行将会覆盖这些告警的配置。${NC}"
    echo ""
else
    echo -e "${GREEN}✓ 未发现现有告警${NC}"
    echo ""
fi

echo -e "${CYAN}${BOLD}即将创建 15 个告警：${NC}"
echo "  - CPU 使用率告警 (2个)"
echo "  - 数据库负载告警 (2个)"
echo "  - 连接数告警 (2个)"
echo "  - ReadIOPS 告警 (2个)"
echo "  - WriteIOPS 告警 (2个)"
echo "  - 磁盘空间告警 (2个)"
echo "  - 内存告警 (1个)"
echo "  - 读延迟告警 (1个)"
echo "  - 写延迟告警 (1个)"
echo ""
echo -e "${GREEN}✓ 此操作对数据库无任何负载影响（仅配置 CloudWatch）${NC}"
echo ""
read -p "确认创建这些告警？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 0
fi
echo ""

# SNS 参数
if [ -n "$SNS_TOPIC_ARN" ]; then
    ALARM_ACTIONS="--alarm-actions $SNS_TOPIC_ARN"
else
    ALARM_ACTIONS=""
fi

# 创建告警计数器
CREATED_ALARMS=0
FAILED_ALARMS=0

# 辅助函数：创建告警
create_alarm() {
    local alarm_name=$1
    local description=$2
    local metric_name=$3
    local threshold=$4
    local comparison=$5
    local eval_periods=$6
    local datapoints=$7
    local period=${8:-60}
    local statistic=${9:-Average}

    echo -e "${CYAN}创建告警: ${alarm_name}${NC}"

    if aws --profile "$AWS_PROFILE" cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$description" \
        --namespace AWS/RDS \
        --metric-name "$metric_name" \
        --dimensions Name=DBInstanceIdentifier,Value="$INSTANCE_ID" \
        --statistic "$statistic" \
        --period "$period" \
        --evaluation-periods "$eval_periods" \
        --datapoints-to-alarm "$datapoints" \
        --threshold "$threshold" \
        --comparison-operator "$comparison" \
        --treat-missing-data notBreaching \
        $ALARM_ACTIONS \
        2>&1; then
        echo -e "${GREEN}  ✅ 成功${NC}"
        ((CREATED_ALARMS++))
    else
        echo -e "${RED}  ❌ 失败${NC}"
        ((FAILED_ALARMS++))
    fi
    echo ""
}

echo -e "${GREEN}${BOLD}开始创建告警...${NC}"
echo ""

# 1. CPU 使用率告警
echo -e "${BLUE}【1/9】CPU 使用率告警${NC}"
create_alarm \
    "RDS-${INSTANCE_ID}-HighCPU-Warning" \
    "CPU使用率超过70%持续5分钟" \
    "CPUUtilization" \
    70 \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-HighCPU-Critical" \
    "CPU使用率超过85%持续3分钟" \
    "CPUUtilization" \
    85 \
    "GreaterThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 2. 数据库负载告警
echo -e "${BLUE}【2/9】数据库负载 (DBLoad) 告警${NC}"

# DBLoad 阈值基于 vCPU 数量
DBLOAD_WARNING=$(echo "$VCPUS * 1.5" | bc)
DBLOAD_CRITICAL=$(echo "$VCPUS * 2" | bc)

create_alarm \
    "RDS-${INSTANCE_ID}-HighDBLoad-Warning" \
    "数据库负载超过 ${DBLOAD_WARNING} (1.5x vCPUs) 持续5分钟" \
    "DBLoad" \
    "$DBLOAD_WARNING" \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-HighDBLoad-Critical" \
    "数据库负载超过 ${DBLOAD_CRITICAL} (2x vCPUs) 持续3分钟" \
    "DBLoad" \
    "$DBLOAD_CRITICAL" \
    "GreaterThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 3. 连接数告警
echo -e "${BLUE}【3/9】数据库连接数告警${NC}"

# 根据实例类型计算最大连接数
case "$INSTANCE_TYPE" in
    *m6g.large*)
        MAX_CONN=901
        ;;
    *t4g.medium*)
        MAX_CONN=450
        ;;
    *t3.small*)
        MAX_CONN=225
        ;;
    *)
        MAX_CONN=500
        ;;
esac

CONN_WARNING=$(echo "$MAX_CONN * 0.7" | bc | cut -d. -f1)
CONN_CRITICAL=$(echo "$MAX_CONN * 0.85" | bc | cut -d. -f1)

create_alarm \
    "RDS-${INSTANCE_ID}-HighConnections-Warning" \
    "数据库连接数超过 ${CONN_WARNING} (70% of max) 持续5分钟" \
    "DatabaseConnections" \
    "$CONN_WARNING" \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-HighConnections-Critical" \
    "数据库连接数超过 ${CONN_CRITICAL} (85% of max) 持续3分钟" \
    "DatabaseConnections" \
    "$CONN_CRITICAL" \
    "GreaterThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 4. ReadIOPS 告警
echo -e "${BLUE}【4/9】ReadIOPS 告警${NC}"

# bingo-prd 基线约 500-600, 异常峰值 > 2000
create_alarm \
    "RDS-${INSTANCE_ID}-HighReadIOPS-Warning" \
    "ReadIOPS 超过 1500 持续5分钟" \
    "ReadIOPS" \
    1500 \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-HighReadIOPS-Critical" \
    "ReadIOPS 超过 2000 持续3分钟 (异常高)" \
    "ReadIOPS" \
    2000 \
    "GreaterThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 5. WriteIOPS 告警
echo -e "${BLUE}【5/9】WriteIOPS 告警${NC}"

# bingo-prd 基线约 800-950, 异常峰值 > 1500
create_alarm \
    "RDS-${INSTANCE_ID}-HighWriteIOPS-Warning" \
    "WriteIOPS 超过 1200 持续5分钟" \
    "WriteIOPS" \
    1200 \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-HighWriteIOPS-Critical" \
    "WriteIOPS 超过 1500 持续3分钟 (异常高)" \
    "WriteIOPS" \
    1500 \
    "GreaterThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 6. 磁盘空间告警
echo -e "${BLUE}【6/9】磁盘空间告警${NC}"

create_alarm \
    "RDS-${INSTANCE_ID}-LowDiskSpace-Warning" \
    "可用磁盘空间低于 50GB" \
    "FreeStorageSpace" \
    53687091200 \
    "LessThanThreshold" \
    2 \
    2 \
    300 \
    "Average"

create_alarm \
    "RDS-${INSTANCE_ID}-LowDiskSpace-Critical" \
    "可用磁盘空间低于 20GB (严重)" \
    "FreeStorageSpace" \
    21474836480 \
    "LessThanThreshold" \
    1 \
    1 \
    300 \
    "Average"

# 7. 内存告警
echo -e "${BLUE}【7/9】可用内存告警${NC}"

create_alarm \
    "RDS-${INSTANCE_ID}-LowMemory-Warning" \
    "可用内存低于 1GB" \
    "FreeableMemory" \
    1073741824 \
    "LessThanThreshold" \
    3 \
    3 \
    60 \
    "Average"

# 8. ReadLatency 告警
echo -e "${BLUE}【8/9】读延迟告警${NC}"

create_alarm \
    "RDS-${INSTANCE_ID}-HighReadLatency" \
    "读延迟超过 5ms 持续5分钟" \
    "ReadLatency" \
    0.005 \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

# 9. WriteLatency 告警
echo -e "${BLUE}【9/9】写延迟告警${NC}"

create_alarm \
    "RDS-${INSTANCE_ID}-HighWriteLatency" \
    "写延迟超过 10ms 持续5分钟" \
    "WriteLatency" \
    0.010 \
    "GreaterThanThreshold" \
    5 \
    5 \
    60 \
    "Average"

# 总结
echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}${BOLD}📊 告警创建总结${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}成功创建: ${CREATED_ALARMS} 个告警${NC}"
if [ $FAILED_ALARMS -gt 0 ]; then
    echo -e "${RED}创建失败: ${FAILED_ALARMS} 个告警${NC}"
fi
echo ""

# 列出已创建的告警
echo -e "${CYAN}已创建的告警列表:${NC}"
aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
    --alarm-name-prefix "RDS-${INSTANCE_ID}-" \
    --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
    --output table

echo ""
echo -e "${YELLOW}💡 提示:${NC}"
echo -e "  - 使用以下命令查看告警状态:"
echo -e "    ${CYAN}aws --profile gemini-pro_ck cloudwatch describe-alarms --alarm-name-prefix 'RDS-${INSTANCE_ID}-'${NC}"
echo -e ""
echo -e "  - 如需配置 SNS 通知，请创建 SNS Topic 并重新运行脚本:"
echo -e "    ${CYAN}$0 ${INSTANCE_ID} arn:aws:sns:region:account:topic-name${NC}"
echo -e ""
echo -e "  - 删除所有告警:"
echo -e "    ${CYAN}./delete-rds-alarms.sh ${INSTANCE_ID}${NC}"
echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"

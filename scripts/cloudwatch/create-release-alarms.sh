#!/bin/bash
#
# Create CloudWatch alarms for Release environment RDS instances
# No SNS notifications - alarms only for monitoring
#
# Instances:
#   - pgsqlrel (db.t3.small, 2 vCPUs, max_connections: 225)
#   - pgsqlrel-backstage (db.t3.micro, 2 vCPUs, max_connections: 112)
#
# Usage: ./create-release-alarms.sh
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
REGION="ap-east-1"

# 实例列表
INSTANCES=(
    "pgsqlrel"
    "pgsqlrel-backstage"
)

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}📊 创建 Release 环境 RDS CloudWatch 告警${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "Profile: ${YELLOW}${AWS_PROFILE}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo ""
echo -e "${CYAN}将为以下实例创建告警:${NC}"
for instance in "${INSTANCES[@]}"; do
    echo "  • $instance"
done
echo ""
echo -e "${YELLOW}⚠️  注意: 这些告警不会发送 SNS 通知，仅用于监控和记录${NC}"
echo ""

# 检查是否已有告警
echo -e "${CYAN}检查现有告警...${NC}"
TOTAL_EXISTING=0
for instance in "${INSTANCES[@]}"; do
    EXISTING_COUNT=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
        --alarm-name-prefix "RDS-${instance}-" \
        --region "$REGION" \
        --query 'length(MetricAlarms)' \
        --output text 2>/dev/null)
    if [ "$EXISTING_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠️  ${instance}: 发现 ${EXISTING_COUNT} 个现有告警${NC}"
        TOTAL_EXISTING=$((TOTAL_EXISTING + EXISTING_COUNT))
    fi
done

if [ $TOTAL_EXISTING -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  总共发现 ${TOTAL_EXISTING} 个现有告警${NC}"
    echo -e "${YELLOW}继续执行将会覆盖这些告警的配置${NC}"
    echo ""
    read -p "确认继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ 未发现现有告警${NC}"
fi
echo ""

echo -e "${CYAN}${BOLD}每个实例将创建 15 个告警：${NC}"
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
echo -e "${CYAN}总计: ${YELLOW}$(( ${#INSTANCES[@]} * 15 ))${NC}${CYAN} 个告警${NC}"
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

# 实例配置
get_instance_config() {
    local instance_id=$1
    case "$instance_id" in
        pgsqlrel)
            echo "db.t3.small:2:225"
            ;;
        pgsqlrel-backstage)
            echo "db.t3.micro:2:112"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 创建告警计数器
TOTAL_CREATED=0
TOTAL_FAILED=0

# 辅助函数：创建告警
create_alarm() {
    local alarm_name=$1
    local description=$2
    local metric_name=$3
    local threshold=$4
    local comparison=$5
    local eval_periods=$6
    local datapoints=$7
    local instance_id=$8
    local period=${9:-60}
    local statistic=${10:-Average}

    if aws --profile "$AWS_PROFILE" cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$description" \
        --namespace AWS/RDS \
        --metric-name "$metric_name" \
        --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
        --statistic "$statistic" \
        --period "$period" \
        --evaluation-periods "$eval_periods" \
        --datapoints-to-alarm "$datapoints" \
        --threshold "$threshold" \
        --comparison-operator "$comparison" \
        --treat-missing-data notBreaching \
        --region "$REGION" \
        2>&1 > /dev/null; then
        echo -e "${GREEN}  ✅ ${alarm_name}${NC}"
        ((TOTAL_CREATED++))
        return 0
    else
        echo -e "${RED}  ❌ ${alarm_name}${NC}"
        ((TOTAL_FAILED++))
        return 1
    fi
}

# 为每个实例创建告警
for instance in "${INSTANCES[@]}"; do
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${CYAN}${BOLD}创建告警: ${instance}${NC}"
    echo -e "${BLUE}================================================================================================${NC}"

    # 获取实例配置
    INSTANCE_INFO=$(get_instance_config "$instance")
    if [ -z "$INSTANCE_INFO" ]; then
        echo -e "${RED}错误：未知的实例 '$instance'${NC}"
        continue
    fi

    IFS=':' read -r INSTANCE_TYPE VCPUS MAX_CONN <<< "$INSTANCE_INFO"

    echo -e "实例类型: ${YELLOW}${INSTANCE_TYPE}${NC}"
    echo -e "vCPUs: ${YELLOW}${VCPUS}${NC}"
    echo -e "最大连接数: ${YELLOW}${MAX_CONN}${NC}"
    echo ""

    # 1. CPU 使用率告警
    echo -e "${CYAN}[1/9] CPU 使用率告警${NC}"
    create_alarm \
        "RDS-${instance}-HighCPU-Warning" \
        "CPU使用率超过70%持续5分钟" \
        "CPUUtilization" \
        70 \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    create_alarm \
        "RDS-${instance}-HighCPU-Critical" \
        "CPU使用率超过85%持续3分钟" \
        "CPUUtilization" \
        85 \
        "GreaterThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 2. 数据库负载告警
    echo -e "${CYAN}[2/9] 数据库负载 (DBLoad) 告警${NC}"
    DBLOAD_WARNING=$(echo "$VCPUS * 1.5" | bc)
    DBLOAD_CRITICAL=$(echo "$VCPUS * 2" | bc)

    create_alarm \
        "RDS-${instance}-HighDBLoad-Warning" \
        "数据库负载超过 ${DBLOAD_WARNING} (1.5x vCPUs) 持续5分钟" \
        "DBLoad" \
        "$DBLOAD_WARNING" \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    create_alarm \
        "RDS-${instance}-HighDBLoad-Critical" \
        "数据库负载超过 ${DBLOAD_CRITICAL} (2x vCPUs) 持续3分钟" \
        "DBLoad" \
        "$DBLOAD_CRITICAL" \
        "GreaterThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 3. 连接数告警
    echo -e "${CYAN}[3/9] 数据库连接数告警${NC}"
    CONN_WARNING=$(echo "$MAX_CONN * 0.7" | bc | cut -d. -f1)
    CONN_CRITICAL=$(echo "$MAX_CONN * 0.85" | bc | cut -d. -f1)

    create_alarm \
        "RDS-${instance}-HighConnections-Warning" \
        "数据库连接数超过 ${CONN_WARNING} (70% of max) 持续5分钟" \
        "DatabaseConnections" \
        "$CONN_WARNING" \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    create_alarm \
        "RDS-${instance}-HighConnections-Critical" \
        "数据库连接数超过 ${CONN_CRITICAL} (85% of max) 持续3分钟" \
        "DatabaseConnections" \
        "$CONN_CRITICAL" \
        "GreaterThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 4. ReadIOPS 告警
    echo -e "${CYAN}[4/9] ReadIOPS 告警${NC}"
    create_alarm \
        "RDS-${instance}-HighReadIOPS-Warning" \
        "ReadIOPS 超过 1000 持续5分钟" \
        "ReadIOPS" \
        1000 \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    create_alarm \
        "RDS-${instance}-HighReadIOPS-Critical" \
        "ReadIOPS 超过 1500 持续3分钟 (异常高)" \
        "ReadIOPS" \
        1500 \
        "GreaterThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 5. WriteIOPS 告警
    echo -e "${CYAN}[5/9] WriteIOPS 告警${NC}"
    create_alarm \
        "RDS-${instance}-HighWriteIOPS-Warning" \
        "WriteIOPS 超过 800 持续5分钟" \
        "WriteIOPS" \
        800 \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    create_alarm \
        "RDS-${instance}-HighWriteIOPS-Critical" \
        "WriteIOPS 超过 1200 持续3分钟 (异常高)" \
        "WriteIOPS" \
        1200 \
        "GreaterThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 6. 磁盘空间告警 (Release 环境 40GB 存储，阈值调整为 10GB/5GB)
    echo -e "${CYAN}[6/9] 磁盘空间告警${NC}"
    create_alarm \
        "RDS-${instance}-LowDiskSpace-Warning" \
        "可用磁盘空间低于 10GB" \
        "FreeStorageSpace" \
        10737418240 \
        "LessThanThreshold" \
        2 \
        2 \
        "$instance" \
        300 \
        "Average"

    create_alarm \
        "RDS-${instance}-LowDiskSpace-Critical" \
        "可用磁盘空间低于 5GB (严重)" \
        "FreeStorageSpace" \
        5368709120 \
        "LessThanThreshold" \
        1 \
        1 \
        "$instance" \
        300 \
        "Average"

    # 7. 内存告警
    echo -e "${CYAN}[7/9] 可用内存告警${NC}"
    create_alarm \
        "RDS-${instance}-LowMemory-Warning" \
        "可用内存低于 512MB" \
        "FreeableMemory" \
        536870912 \
        "LessThanThreshold" \
        3 \
        3 \
        "$instance" \
        60 \
        "Average"

    # 8. ReadLatency 告警
    echo -e "${CYAN}[8/9] 读延迟告警${NC}"
    create_alarm \
        "RDS-${instance}-HighReadLatency" \
        "读延迟超过 5ms 持续5分钟" \
        "ReadLatency" \
        0.005 \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    # 9. WriteLatency 告警
    echo -e "${CYAN}[9/9] 写延迟告警${NC}"
    create_alarm \
        "RDS-${instance}-HighWriteLatency" \
        "写延迟超过 10ms 持续5分钟" \
        "WriteLatency" \
        0.010 \
        "GreaterThanThreshold" \
        5 \
        5 \
        "$instance" \
        60 \
        "Average"

    echo ""
done

# 总结
echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}${BOLD}📊 告警创建总结${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}成功创建: ${TOTAL_CREATED} 个告警${NC}"
if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "${RED}创建失败: ${TOTAL_FAILED} 个告警${NC}"
fi
echo ""

# 列出所有已创建的告警
echo -e "${CYAN}已创建的告警列表:${NC}"
for instance in "${INSTANCES[@]}"; do
    ALARM_COUNT=$(aws --profile "$AWS_PROFILE" cloudwatch describe-alarms \
        --alarm-name-prefix "RDS-${instance}-" \
        --region "$REGION" \
        --query 'length(MetricAlarms)' \
        --output text 2>/dev/null)
    echo -e "  ${YELLOW}${instance}${NC}: ${ALARM_COUNT} 个告警"
done
echo ""

echo -e "${YELLOW}💡 提示:${NC}"
echo -e "  - 查看所有告警:"
echo -e "    ${CYAN}aws --profile gemini-pro_ck cloudwatch describe-alarms --region ap-east-1 --alarm-name-prefix 'RDS-pgsqlrel'${NC}"
echo ""
echo -e "  - 查看告警状态:"
echo -e "    ${CYAN}aws --profile gemini-pro_ck cloudwatch describe-alarms --region ap-east-1 --state-value ALARM${NC}"
echo ""
echo -e "  - 删除特定实例的告警:"
echo -e "    ${CYAN}./delete-rds-alarms.sh <instance-name>${NC}"
echo ""
echo -e "  - 访问 CloudWatch Console:"
echo -e "    ${CYAN}https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#alarmsV2:${NC}"
echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"

#!/bin/bash
#
# RDS Connection Pool Monitoring Script
# 监控数据库连接池健康状况，结合 CloudWatch 和直接数据库查询
#
# 用法:
#   ./monitor-connection-pool.sh bingo-prd
#   ./monitor-connection-pool.sh bingo-prd --with-db-query
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# AWS Profile
AWS_PROFILE="gemini-pro_ck"

# RDS 实例配置 (实例名:实例类型:最大连接数)
declare -A RDS_CONFIG=(
  ["bingo-prd"]="db.m6g.large:901"
  ["bingo-prd-backstage"]="db.m6g.large:901"
  ["bingo-prd-backstage-replica1"]="db.t4g.medium:450"
  ["bingo-prd-loyalty"]="db.t4g.medium:450"
  ["bingo-prd-replica1"]="db.m6g.large:901"
  ["bingo-stress"]="db.t4g.medium:450"
  ["bingo-stress-backstage"]="db.t4g.medium:450"
  ["bingo-stress-loyalty"]="db.t4g.medium:450"
)

# 使用说明
usage() {
    cat << EOF
${BOLD}RDS 连接池监控工具${NC}

用法:
    $0 <instance-id> [OPTIONS]

参数:
    instance-id              RDS 实例标识符 (必需)

选项:
    --with-db-query          同时执行数据库直接查询 (需要数据库凭证)
    --db-host HOST           数据库主机地址
    --db-port PORT           数据库端口 (默认: 5432)
    --db-name DATABASE       数据库名称 (默认: postgres)
    --db-user USER           数据库用户名
    --db-password PASSWORD   数据库密码
    -h, --help              显示此帮助信息

范例:
    # 仅使用 CloudWatch 监控
    $0 bingo-prd

    # 结合数据库直接查询
    $0 bingo-prd --with-db-query \\
        --db-host bingo-prd.xxx.rds.amazonaws.com \\
        --db-user readonly_user \\
        --db-password 'password123'

EOF
    exit 1
}

# 检查必要工具
check_dependencies() {
    local missing_tools=()

    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi

    if [ "$WITH_DB_QUERY" = true ] && ! command -v psql &> /dev/null; then
        missing_tools+=("postgresql-client")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}错误：缺少必要工具: ${missing_tools[*]}${NC}"
        exit 1
    fi
}

# 获取 CloudWatch 指标
get_cloudwatch_metric() {
    local instance_id=$1
    local metric_name=$2
    local period=$3
    local stat=$4

    local end_time=$(date -u +%Y-%m-%dT%H:%M:%S)Z
    local start_time

    case "$(uname)" in
        Darwin)
            start_time=$(date -u -v-${period}M +%Y-%m-%dT%H:%M:%S)Z
            ;;
        Linux)
            start_time=$(date -u -d "${period} minutes ago" +%Y-%m-%dT%H:%M:%S)Z
            ;;
    esac

    aws --profile "$AWS_PROFILE" cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name "$metric_name" \
        --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
        --statistics "$stat" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period $((period * 60)) \
        --query "Datapoints[0].$stat" \
        --output text 2>/dev/null || echo "N/A"
}

# 显示连接池状态
show_connection_pool_status() {
    local instance_id=$1
    local instance_info="${RDS_CONFIG[$instance_id]}"

    if [ -z "$instance_info" ]; then
        echo -e "${RED}错误：未知的实例 '$instance_id'${NC}"
        exit 1
    fi

    IFS=':' read -r instance_type max_conn <<< "$instance_info"

    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${CYAN}${BOLD}📊 RDS 连接池监控报告${NC}"
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "实例: ${YELLOW}${BOLD}$instance_id${NC}"
    echo -e "类型: ${YELLOW}$instance_type${NC}"
    echo -e "最大连接数: ${YELLOW}$max_conn${NC}"
    echo -e "时间: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S %Z')${NC}"
    echo ""

    # 获取 CloudWatch 指标
    echo -e "${GREEN}${BOLD}📈 CloudWatch 指标 (最近 5 分钟)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    local avg_conn_5m=$(get_cloudwatch_metric "$instance_id" "DatabaseConnections" 5 "Average")
    local max_conn_5m=$(get_cloudwatch_metric "$instance_id" "DatabaseConnections" 5 "Maximum")
    local min_conn_5m=$(get_cloudwatch_metric "$instance_id" "DatabaseConnections" 5 "Minimum")

    if [ "$avg_conn_5m" != "N/A" ] && [ "$avg_conn_5m" != "None" ]; then
        avg_conn_5m=$(printf "%.0f" "$avg_conn_5m")
        max_conn_5m=$(printf "%.0f" "$max_conn_5m")
        min_conn_5m=$(printf "%.0f" "$min_conn_5m")
        local usage=$(awk "BEGIN {printf \"%.1f\", ($avg_conn_5m / $max_conn) * 100}")
        local max_usage=$(awk "BEGIN {printf \"%.1f\", ($max_conn_5m / $max_conn) * 100}")

        # 连接数颜色
        local conn_color=$GREEN
        if (( $(echo "$usage > 80" | bc -l) )); then
            conn_color=$RED
        elif (( $(echo "$usage > 60" | bc -l) )); then
            conn_color=$YELLOW
        fi

        printf "%-30s: ${conn_color}%s${NC}\n" "平均连接数" "$avg_conn_5m / $max_conn (${usage}%)"
        printf "%-30s: %s\n" "峰值连接数" "$max_conn_5m / $max_conn (${max_usage}%)"
        printf "%-30s: %s\n" "最低连接数" "$min_conn_5m"
    else
        echo -e "${RED}无法获取连接数据${NC}"
    fi

    echo ""

    # 获取其他关键指标
    echo -e "${GREEN}${BOLD}⚡ 性能指标 (最近 5 分钟)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    local cpu_avg=$(get_cloudwatch_metric "$instance_id" "CPUUtilization" 5 "Average")
    local db_load_avg=$(get_cloudwatch_metric "$instance_id" "DBLoad" 5 "Average")
    local db_load_max=$(get_cloudwatch_metric "$instance_id" "DBLoad" 5 "Maximum")
    local read_iops=$(get_cloudwatch_metric "$instance_id" "ReadIOPS" 5 "Average")
    local write_iops=$(get_cloudwatch_metric "$instance_id" "WriteIOPS" 5 "Average")

    if [ "$cpu_avg" != "N/A" ] && [ "$cpu_avg" != "None" ]; then
        cpu_avg=$(printf "%.1f" "$cpu_avg")
        local cpu_color=$GREEN
        if (( $(echo "$cpu_avg > 80" | bc -l) )); then
            cpu_color=$RED
        elif (( $(echo "$cpu_avg > 60" | bc -l) )); then
            cpu_color=$YELLOW
        fi
        printf "%-30s: ${cpu_color}%s%%${NC}\n" "CPU 使用率" "$cpu_avg"
    fi

    if [ "$db_load_avg" != "N/A" ] && [ "$db_load_avg" != "None" ]; then
        db_load_avg=$(printf "%.2f" "$db_load_avg")
        db_load_max=$(printf "%.2f" "$db_load_max")

        # 获取 vCPU 数量
        local vcpus=2
        case "$instance_type" in
            *xlarge) vcpus=4 ;;
            *2xlarge) vcpus=8 ;;
            *medium) vcpus=2 ;;
            *small) vcpus=2 ;;
        esac

        local load_color=$GREEN
        if (( $(echo "$db_load_max > $vcpus" | bc -l) )); then
            load_color=$RED
        elif (( $(echo "$db_load_avg > $(echo "$vcpus * 0.8" | bc)" | bc -l) )); then
            load_color=$YELLOW
        fi

        printf "%-30s: ${load_color}%s (峰值: %s, vCPUs: %d)${NC}\n" "数据库负载" "$db_load_avg" "$db_load_max" "$vcpus"
    fi

    if [ "$read_iops" != "N/A" ] && [ "$read_iops" != "None" ]; then
        read_iops=$(printf "%.0f" "$read_iops")
        write_iops=$(printf "%.0f" "$write_iops")
        printf "%-30s: %s IOPS\n" "读取 IOPS" "$read_iops"
        printf "%-30s: %s IOPS\n" "写入 IOPS" "$write_iops"
    fi

    echo ""

    # 24小时峰值
    echo -e "${GREEN}${BOLD}📊 24小时峰值${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    local conn_24h_max=$(get_cloudwatch_metric "$instance_id" "DatabaseConnections" 1440 "Maximum")
    local cpu_24h_max=$(get_cloudwatch_metric "$instance_id" "CPUUtilization" 1440 "Maximum")
    local db_load_24h_max=$(get_cloudwatch_metric "$instance_id" "DBLoad" 1440 "Maximum")

    if [ "$conn_24h_max" != "N/A" ] && [ "$conn_24h_max" != "None" ]; then
        conn_24h_max=$(printf "%.0f" "$conn_24h_max")
        local usage_24h=$(awk "BEGIN {printf \"%.1f\", ($conn_24h_max / $max_conn) * 100}")
        printf "%-30s: %s / %s (%s%%)\n" "连接数峰值 (24h)" "$conn_24h_max" "$max_conn" "$usage_24h"
    fi

    if [ "$cpu_24h_max" != "N/A" ] && [ "$cpu_24h_max" != "None" ]; then
        cpu_24h_max=$(printf "%.1f" "$cpu_24h_max")
        printf "%-30s: %s%%\n" "CPU 峰值 (24h)" "$cpu_24h_max"
    fi

    if [ "$db_load_24h_max" != "N/A" ] && [ "$db_load_24h_max" != "None" ]; then
        db_load_24h_max=$(printf "%.2f" "$db_load_24h_max")
        printf "%-30s: %s\n" "数据库负载峰值 (24h)" "$db_load_24h_max"
    fi
}

# 数据库直接查询
query_database_connections() {
    if [ "$WITH_DB_QUERY" != true ]; then
        return
    fi

    if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo -e "${YELLOW}⚠️  跳过数据库直接查询 (缺少数据库凭证)${NC}"
        return
    fi

    echo ""
    echo -e "${GREEN}${BOLD}🔍 数据库实时连接分析${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    export PGPASSWORD="$DB_PASSWORD"

    # 查询总连接数
    echo -e "${CYAN}总连接数统计:${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -t -A << 'EOSQL'
SELECT
    COUNT(*) as total_connections,
    COUNT(*) FILTER (WHERE state = 'active') as active,
    COUNT(*) FILTER (WHERE state = 'idle') as idle,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
    COUNT(*) FILTER (WHERE state = 'idle in transaction (aborted)') as aborted
FROM pg_stat_activity
WHERE pid != pg_backend_pid();
EOSQL

    echo ""

    # 查询按应用分组的连接
    echo -e "${CYAN}按应用分组:${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" << 'EOSQL'
SELECT
    COALESCE(application_name, 'N/A') as application,
    COUNT(*) as connections,
    COUNT(*) FILTER (WHERE state = 'active') as active,
    COUNT(*) FILTER (WHERE state = 'idle') as idle
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY application_name
ORDER BY COUNT(*) DESC
LIMIT 10;
EOSQL

    echo ""

    # 查询长时间运行的查询
    echo -e "${CYAN}长时间运行的查询 (>10秒):${NC}"
    local long_queries=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -t -A -c "
SELECT COUNT(*)
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND state != 'idle'
    AND query_start < NOW() - INTERVAL '10 seconds';
")

    if [ "$long_queries" -gt 0 ]; then
        echo -e "${RED}⚠️  发现 $long_queries 个长时间运行的查询${NC}"
        psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" << 'EOSQL'
SELECT
    pid,
    usename,
    EXTRACT(EPOCH FROM (NOW() - query_start))::int as duration_sec,
    state,
    LEFT(query, 80) as query_preview
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND state != 'idle'
    AND query_start < NOW() - INTERVAL '10 seconds'
ORDER BY query_start ASC
LIMIT 5;
EOSQL
    else
        echo -e "${GREEN}✅ 无长时间运行的查询${NC}"
    fi

    echo ""

    # 查询锁等待
    echo -e "${CYAN}锁等待检查:${NC}"
    local lock_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" -t -A -c "
SELECT COUNT(*)
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND wait_event_type = 'Lock';
")

    if [ "$lock_count" -gt 0 ]; then
        echo -e "${RED}⚠️  发现 $lock_count 个锁等待${NC}"
    else
        echo -e "${GREEN}✅ 无锁等待${NC}"
    fi

    unset PGPASSWORD
}

# 健康评估
health_assessment() {
    echo ""
    echo -e "${GREEN}${BOLD}🏥 健康评估${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    local health_issues=()

    # 检查连接数使用率
    if [ "$avg_conn_5m" != "N/A" ] && [ "$avg_conn_5m" != "None" ]; then
        local usage=$(awk "BEGIN {printf \"%.1f\", ($avg_conn_5m / $max_conn) * 100}")
        if (( $(echo "$usage > 80" | bc -l) )); then
            health_issues+=("${RED}❌ 连接数使用率过高 (${usage}%)${NC}")
        elif (( $(echo "$usage > 60" | bc -l) )); then
            health_issues+=("${YELLOW}⚠️  连接数使用率偏高 (${usage}%)${NC}")
        fi
    fi

    # 检查数据库负载
    if [ "$db_load_max" != "N/A" ] && [ "$db_load_max" != "None" ]; then
        local vcpus=2
        case "$instance_type" in
            *xlarge) vcpus=4 ;;
            *2xlarge) vcpus=8 ;;
        esac

        if (( $(echo "$db_load_max > $vcpus" | bc -l) )); then
            health_issues+=("${RED}❌ 数据库负载超过 vCPU 容量 (${db_load_max} > ${vcpus})${NC}")
        fi
    fi

    # 检查 CPU 使用率
    if [ "$cpu_avg" != "N/A" ] && [ "$cpu_avg" != "None" ]; then
        if (( $(echo "$cpu_avg > 80" | bc -l) )); then
            health_issues+=("${RED}❌ CPU 使用率过高 (${cpu_avg}%)${NC}")
        elif (( $(echo "$cpu_avg > 70" | bc -l) )); then
            health_issues+=("${YELLOW}⚠️  CPU 使用率偏高 (${cpu_avg}%)${NC}")
        fi
    fi

    if [ ${#health_issues[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ 所有指标正常${NC}"
    else
        echo -e "${BOLD}发现以下问题:${NC}"
        for issue in "${health_issues[@]}"; do
            echo -e "  $issue"
        done
    fi
}

# 参数解析
INSTANCE_ID=""
WITH_DB_QUERY=false
DB_HOST=""
DB_PORT="5432"
DB_NAME="postgres"
DB_USER=""
DB_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --with-db-query)
            WITH_DB_QUERY=true
            shift
            ;;
        --db-host)
            DB_HOST="$2"
            shift 2
            ;;
        --db-port)
            DB_PORT="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        --db-user)
            DB_USER="$2"
            shift 2
            ;;
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$INSTANCE_ID" ]; then
                INSTANCE_ID="$1"
            else
                echo -e "${RED}错误：未知参数 '$1'${NC}"
                usage
            fi
            shift
            ;;
    esac
done

# 检查必需参数
if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}错误：缺少实例标识符${NC}"
    usage
fi

# 主程序
check_dependencies
show_connection_pool_status "$INSTANCE_ID"
query_database_connections
health_assessment

echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 监控完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"

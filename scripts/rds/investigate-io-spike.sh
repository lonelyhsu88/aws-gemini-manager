#!/bin/bash
#
# I/O Spike Investigation Script
# 调查特定时间段的 I/O 密集型操作根本原因
#
# 用法:
#   ./investigate-io-spike.sh -h bingo-prd.xxx.rds.amazonaws.com \
#       -d postgres -u your_user -w 'password'
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

# 使用说明
usage() {
    cat << EOF
${BOLD}I/O Spike 调查工具${NC}

用法:
    $0 -h HOST -u USER -w PASSWORD [OPTIONS]

必需参数:
    -h, --host HOST          数据库主机地址
    -u, --user USER          数据库用户名
    -w, --password PASSWORD  数据库密码

可选参数:
    -p, --port PORT          端口 (默认: 5432)
    -d, --database DATABASE  数据库名称 (默认: postgres)
    --help                   显示此帮助信息

范例:
    $0 -h bingo-prd.xxx.rds.amazonaws.com \\
       -u admin_user -w 'password123'

EOF
    exit 1
}

# 参数解析
HOST=""
PORT="5432"
DATABASE="postgres"
USER=""
PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -u|--user)
            USER="$2"
            shift 2
            ;;
        -w|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            usage
            ;;
    esac
done

# 检查必需参数
if [[ -z "$HOST" ]] || [[ -z "$USER" ]] || [[ -z "$PASSWORD" ]]; then
    echo -e "${RED}错误：缺少必需参数${NC}"
    usage
fi

# 设置 PGPASSWORD
export PGPASSWORD="$PASSWORD"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}🔍 I/O Spike 根本原因分析 (完整版)${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "数据库: ${YELLOW}${HOST}${NC}"
echo -e "时间: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""
echo -e "${YELLOW}${BOLD}⚠️  负载影响警告${NC}"
echo -e "${YELLOW}此脚本会执行多个诊断查询，预计影响:${NC}"
echo -e "${YELLOW}  - 执行时间: 3-8 秒${NC}"
echo -e "${YELLOW}  - DBLoad 影响: +0.7-1.5${NC}"
echo -e "${YELLOW}  - 占用 1 个数据库连接${NC}"
echo ""
echo -e "${RED}⚠️  如果当前 DBLoad > 10，建议使用轻量级版本:${NC}"
echo -e "${RED}     ./investigate-io-spike-lite.sh${NC}"
echo ""
read -p "确认继续执行完整分析？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}已取消。建议使用: ./investigate-io-spike-lite.sh${NC}"
    exit 0
fi
echo ""

# 1. 检查 pg_stat_statements 是否启用
echo -e "${GREEN}${BOLD}1️⃣  检查 pg_stat_statements 扩展${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

pg_stat_enabled=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -A -c "
SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';
" 2>/dev/null || echo "0")

if [ "$pg_stat_enabled" == "0" ]; then
    echo -e "${RED}⚠️  pg_stat_statements 未启用${NC}"
    echo -e "${YELLOW}建议：执行 'CREATE EXTENSION pg_stat_statements;' 来启用查询统计${NC}"
    echo ""
else
    echo -e "${GREEN}✅ pg_stat_statements 已启用${NC}"
    echo ""

    # 2. 查询最消耗 I/O 的 SQL 语句
    echo -e "${GREEN}${BOLD}2️⃣  最消耗 I/O 的 SQL 语句 (按总 I/O 排序)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    queryid,
    calls as "执行次数",
    ROUND(total_exec_time::numeric / 1000, 2) as "总执行时间(秒)",
    ROUND((total_exec_time / calls)::numeric / 1000, 2) as "平均执行时间(秒)",
    shared_blks_read + local_blks_read as "读取块数",
    shared_blks_written + local_blks_written as "写入块数",
    (shared_blks_read + local_blks_read + shared_blks_written + local_blks_written) as "总I/O块数",
    LEFT(query, 80) as "查询预览"
FROM pg_stat_statements
WHERE (shared_blks_read + local_blks_read + shared_blks_written + local_blks_written) > 1000
ORDER BY (shared_blks_read + local_blks_read + shared_blks_written + local_blks_written) DESC
LIMIT 15;
EOSQL

    echo ""

    # 3. 查询执行次数最多的语句
    echo -e "${GREEN}${BOLD}3️⃣  执行次数最多的 SQL 语句${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    queryid,
    calls as "执行次数",
    ROUND(total_exec_time::numeric / 1000, 2) as "总执行时间(秒)",
    ROUND((total_exec_time / calls)::numeric, 2) as "平均执行时间(ms)",
    rows as "返回行数",
    LEFT(query, 100) as "查询预览"
FROM pg_stat_statements
WHERE calls > 100
ORDER BY calls DESC
LIMIT 15;
EOSQL

    echo ""

    # 4. 慢查询（平均执行时间 > 1秒）
    echo -e "${GREEN}${BOLD}4️⃣  慢查询 (平均执行时间 > 1秒)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    queryid,
    calls as "执行次数",
    ROUND((total_exec_time / calls)::numeric / 1000, 2) as "平均执行时间(秒)",
    ROUND(total_exec_time::numeric / 1000, 2) as "总执行时间(秒)",
    shared_blks_read + local_blks_read as "读取块数",
    LEFT(query, 100) as "查询预览"
FROM pg_stat_statements
WHERE (total_exec_time / calls) > 1000
ORDER BY (total_exec_time / calls) DESC
LIMIT 15;
EOSQL

    echo ""
fi

# 5. 表的统计信息
echo -e "${GREEN}${BOLD}5️⃣  表的 I/O 活动统计${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    schemaname as "模式",
    relname as "表名",
    seq_scan as "顺序扫描",
    seq_tup_read as "顺序读取行数",
    idx_scan as "索引扫描",
    idx_tup_fetch as "索引获取行数",
    n_tup_ins as "插入",
    n_tup_upd as "更新",
    n_tup_del as "删除",
    n_live_tup as "存活行数",
    n_dead_tup as "死亡行数"
FROM pg_stat_user_tables
WHERE (n_tup_ins + n_tup_upd + n_tup_del) > 1000
   OR seq_scan > 100
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC
LIMIT 15;
EOSQL

echo ""

# 6. 缺失索引检查
echo -e "${GREEN}${BOLD}6️⃣  可能缺失索引的表 (高顺序扫描比例)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    schemaname as "模式",
    relname as "表名",
    seq_scan as "顺序扫描",
    COALESCE(idx_scan, 0) as "索引扫描",
    CASE
        WHEN seq_scan + COALESCE(idx_scan, 0) > 0
        THEN ROUND(100.0 * seq_scan / (seq_scan + COALESCE(idx_scan, 0)), 2)
        ELSE 0
    END as "顺序扫描占比%",
    n_live_tup as "存活行数"
FROM pg_stat_user_tables
WHERE seq_scan > 100
    AND n_live_tup > 10000
    AND CASE
        WHEN seq_scan + COALESCE(idx_scan, 0) > 0
        THEN 100.0 * seq_scan / (seq_scan + COALESCE(idx_scan, 0))
        ELSE 0
    END > 50
ORDER BY seq_scan DESC
LIMIT 10;
EOSQL

echo ""

# 7. Vacuum 和 Autovacuum 状态
echo -e "${GREEN}${BOLD}7️⃣  表维护状态 (Vacuum/Analyze)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    schemaname as "模式",
    relname as "表名",
    n_dead_tup as "死亡行数",
    n_live_tup as "存活行数",
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) as "死亡行占比%",
    last_vacuum as "最后 VACUUM",
    last_autovacuum as "最后 AUTOVACUUM",
    last_analyze as "最后 ANALYZE",
    last_autoanalyze as "最后 AUTOANALYZE"
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 10;
EOSQL

echo ""

# 8. 数据库大小和表大小
echo -e "${GREEN}${BOLD}8️⃣  最大的表 (Top 10)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    schemaname as "模式",
    tablename as "表名",
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as "总大小",
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as "表大小",
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as "索引大小"
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
EOSQL

echo ""

# 9. 临时文件使用情况
echo -e "${GREEN}${BOLD}9️⃣  临时文件使用情况 (表示可能的内存不足)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    datname as "数据库",
    temp_files as "临时文件数",
    pg_size_pretty(temp_bytes) as "临时文件大小"
FROM pg_stat_database
WHERE temp_files > 0
ORDER BY temp_bytes DESC;
EOSQL

echo ""

# 10. 建议
echo -e "${GREEN}${BOLD}💡 调查建议${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

cat << 'EOF'
根据上述分析，可能的 I/O 密集型操作原因：

1. 【批量操作】
   - 检查是否有定时任务在 21:18 执行 (cron jobs, scheduled tasks)
   - 查看应用日志中的批量插入/更新操作
   - 确认是否有数据同步或 ETL 任务

2. 【缺失索引】
   - 查看"可能缺失索引的表"部分，顺序扫描占比 > 50% 的表需要添加索引
   - 特别关注大表（> 100万行）的顺序扫描

3. 【Vacuum 需求】
   - 检查"表维护状态"中死亡行占比 > 20% 的表
   - 考虑手动执行 VACUUM ANALYZE

4. 【慢查询优化】
   - 查看"慢查询"部分，优化平均执行时间 > 1秒的查询
   - 使用 EXPLAIN ANALYZE 分析具体查询计划

5. 【应用层面】
   - 检查应用是否有 N+1 查询问题
   - 确认连接池配置是否合理
   - 查看是否有未使用连接池的直接数据库连接

6. 【查看 Performance Insights】
   访问 AWS RDS Performance Insights:
   - 查看 Top SQL 在 21:18-21:38 时段的具体执行情况
   - 分析 Wait Events 来定位具体的 I/O 瓶颈类型

下一步操作:
- 如果 pg_stat_statements 未启用，启用后等待一段时间再次运行本脚本
- 将上述查询结果与应用日志关联分析
- 在 AWS Console 查看 Performance Insights 的详细等待事件
EOF

echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 分析完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"

# 清理
unset PGPASSWORD

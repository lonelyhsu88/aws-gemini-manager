#!/bin/bash
#
# I/O Spike Investigation Script - LIGHTWEIGHT VERSION
# 轻量级版本：最小化数据库负载，仅查询最关键信息
#
# ⚠️  适用场景：数据库已经高负载时使用此版本
# ✅  正常场景：使用完整版 investigate-io-spike.sh
#
# 用法:
#   ./investigate-io-spike-lite.sh -h bingo-prd.xxx.rds.amazonaws.com \
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
${BOLD}I/O Spike 调查工具 - 轻量级版本${NC}

${YELLOW}⚠️  此版本专为高负载场景设计，仅执行最关键的查询${NC}

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
       -u readonly_user -w 'password123'

${CYAN}与完整版的区别:${NC}
  - ❌ 跳过锁等待 JOIN 查询（避免复杂 JOIN）
  - ❌ 跳过表大小查询（避免大量元数据读取）
  - ❌ 跳过缺失索引详细分析
  - ✅ 仅查询 pg_stat_statements Top 10
  - ✅ 快速检查当前活动查询
  - ⚡ 预计执行时间: 0.5-2 秒

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
echo -e "${CYAN}${BOLD}⚡ I/O Spike 快速分析 (轻量级)${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "数据库: ${YELLOW}${HOST}${NC}"
echo -e "时间: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${YELLOW}⚠️  轻量级模式：仅执行最小必要查询以减少数据库负载${NC}"
echo ""

# 1. 检查 pg_stat_statements 是否启用
echo -e "${GREEN}${BOLD}1️⃣  检查查询统计扩展${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

pg_stat_enabled=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -A -c "
SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';
" 2>/dev/null || echo "0")

if [ "$pg_stat_enabled" == "0" ]; then
    echo -e "${RED}⚠️  pg_stat_statements 未启用，无法分析历史查询${NC}"
    echo -e "${YELLOW}建议：联系 DBA 启用此扩展${NC}"
    echo ""
else
    echo -e "${GREEN}✅ pg_stat_statements 已启用${NC}"
    echo ""

    # 2. Top 10 最消耗 I/O 的查询
    echo -e "${GREEN}${BOLD}2️⃣  Top 10 I/O 密集型查询${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t << 'EOSQL'
SELECT
    LPAD(calls::text, 8) || ' | ' ||
    LPAD(ROUND((total_exec_time/calls)::numeric, 1)::text || 'ms', 10) || ' | ' ||
    LPAD((shared_blks_read + local_blks_read)::text, 10) || ' | ' ||
    LEFT(query, 70)
FROM pg_stat_statements
WHERE (shared_blks_read + local_blks_read + shared_blks_written + local_blks_written) > 1000
ORDER BY (shared_blks_read + local_blks_read + shared_blks_written + local_blks_written) DESC
LIMIT 10;
EOSQL

    echo ""

    # 3. Top 10 慢查询
    echo -e "${GREEN}${BOLD}3️⃣  Top 10 慢查询 (按平均执行时间)${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t << 'EOSQL'
SELECT
    LPAD(calls::text, 8) || ' | ' ||
    LPAD(ROUND((total_exec_time/calls)::numeric, 1)::text || 'ms', 10) || ' | ' ||
    LEFT(query, 70)
FROM pg_stat_statements
WHERE calls > 10
ORDER BY (total_exec_time / calls) DESC
LIMIT 10;
EOSQL

    echo ""
fi

# 4. 当前活动查询（非常轻量）
echo -e "${GREEN}${BOLD}4️⃣  当前活动查询 (state != idle)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

active_count=$(psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -A -c "
SELECT COUNT(*) FROM pg_stat_activity WHERE pid != pg_backend_pid() AND state != 'idle';
" 2>/dev/null)

echo -e "当前活动查询数: ${YELLOW}${active_count}${NC}"

if [ "$active_count" -gt 0 ]; then
    echo ""
    psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    pid,
    usename,
    EXTRACT(EPOCH FROM (NOW() - query_start))::int as "执行秒数",
    state,
    LEFT(query, 80) as "查询"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND state != 'idle'
ORDER BY query_start ASC
LIMIT 10;
EOSQL
fi

echo ""

# 5. 快速表统计（仅 Top 5）
echo -e "${GREEN}${BOLD}5️⃣  Top 5 活跃表 (按操作数)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    schemaname || '.' || relname as "表名",
    n_tup_ins + n_tup_upd + n_tup_del as "操作总数",
    n_tup_ins as "插入",
    n_tup_upd as "更新",
    n_tup_del as "删除",
    seq_scan as "顺序扫描"
FROM pg_stat_user_tables
WHERE (n_tup_ins + n_tup_upd + n_tup_del) > 1000
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC
LIMIT 5;
EOSQL

echo ""

# 6. 简单建议
echo -e "${GREEN}${BOLD}💡 快速建议${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

cat << 'EOF'
基于轻量级分析：

1. 【查看完整分析】
   如果数据库负载已恢复正常（DBLoad < 3），运行完整版脚本：
   ./investigate-io-spike.sh -h ... -u ... -w ...

2. 【使用 Performance Insights】
   在 AWS Console 查看更详细的等待事件和 Top SQL：
   RDS → bingo-prd → Performance Insights

3. 【检查应用层】
   - 查看应用日志中 21:18-21:38 时段的操作
   - 检查是否有定时任务或批量操作
   - 确认是否有数据同步任务

4. 【监控当前状态】
   使用连接池监控脚本实时查看：
   ./monitor-connection-pool.sh bingo-prd

EOF

echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 轻量级分析完成 (预计影响 DBLoad: +0.3-0.5)${NC}"
echo -e "${BLUE}================================================================================================${NC}"

# 清理
unset PGPASSWORD

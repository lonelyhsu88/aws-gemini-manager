#!/bin/bash
#
# 快速查詢 RDS PostgreSQL 的活動連接
# 使用 psql 直接查詢數據庫
#

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 使用說明
usage() {
    cat << EOF
使用方法: $0 [OPTIONS]

選項:
    -h, --host HOST          數據庫主機地址（必需）
    -p, --port PORT          端口（默認: 5432）
    -d, --database DATABASE  數據庫名稱（必需）
    -u, --user USER          用戶名（必需）
    -w, --password PASSWORD  密碼（必需）
    --help                   顯示此幫助信息

範例:
    $0 -h bingo-prd-backstage-replica1.xxx.rds.amazonaws.com \\
       -d postgres -u readonly_user -w 'password123'

EOF
    exit 1
}

# 解析參數
HOST=""
PORT="5432"
DATABASE=""
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
            echo "未知選項: $1"
            usage
            ;;
    esac
done

# 檢查必需參數
if [[ -z "$HOST" ]] || [[ -z "$DATABASE" ]] || [[ -z "$USER" ]] || [[ -z "$PASSWORD" ]]; then
    echo -e "${RED}錯誤：缺少必需參數${NC}"
    usage
fi

# 設置 PGPASSWORD 環境變數
export PGPASSWORD="$PASSWORD"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}🔍 PostgreSQL 活動連接分析${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "主機: ${YELLOW}$HOST${NC}"
echo -e "數據庫: ${YELLOW}$DATABASE${NC}"
echo -e "時間: ${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# 查詢 1: 連接統計
echo -e "${GREEN}📊 連接統計 (按 IP 分組)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" -t -A -F',' << 'EOSQL' | column -t -s ','
SELECT
    COALESCE(client_addr::text, 'localhost') as "來源IP",
    COUNT(*) as "總連接數",
    COUNT(*) FILTER (WHERE state = 'active') as "活動中",
    COUNT(*) FILTER (WHERE state = 'idle') as "閒置",
    COUNT(*) FILTER (WHERE state = 'idle in transaction') as "事務中閒置",
    COALESCE(application_name, 'N/A') as "應用名稱"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY client_addr, application_name
ORDER BY COUNT(*) DESC;
EOSQL

echo ""

# 查詢 2: 當前活動查詢
echo -e "${GREEN}⚡ 當前活動查詢 (非 idle)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    pid as "PID",
    usename as "用戶",
    COALESCE(client_addr::text, 'localhost') as "來源IP",
    COALESCE(application_name, 'N/A') as "應用",
    state as "狀態",
    EXTRACT(EPOCH FROM (NOW() - query_start))::int as "執行秒數",
    COALESCE(wait_event_type, '') as "等待類型",
    COALESCE(wait_event, '') as "等待事件",
    LEFT(query, 100) as "查詢預覽"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND state != 'idle'
ORDER BY query_start DESC
LIMIT 20;
EOSQL

echo ""

# 查詢 3: 長時間運行的查詢
echo -e "${GREEN}🐌 長時間運行的查詢 (>5秒)${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    pid as "PID",
    usename as "用戶",
    COALESCE(client_addr::text, 'localhost') as "來源IP",
    EXTRACT(EPOCH FROM (NOW() - query_start))::int as "執行秒數",
    state as "狀態",
    LEFT(query, 150) as "查詢"
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
    AND state != 'idle'
    AND query_start < NOW() - INTERVAL '5 seconds'
ORDER BY query_start ASC;
EOSQL

echo ""

# 查詢 4: 數據庫統計
echo -e "${GREEN}💾 數據庫基本信息${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    datname as "數據庫",
    numbackends as "連接數",
    xact_commit as "提交事務數",
    xact_rollback as "回滾事務數",
    blks_read as "磁盤塊讀取",
    blks_hit as "緩存塊命中",
    CASE
        WHEN blks_read + blks_hit = 0 THEN 0
        ELSE ROUND(100.0 * blks_hit / (blks_read + blks_hit), 2)
    END as "緩存命中率%"
FROM pg_stat_database
WHERE datname = current_database();
EOSQL

echo ""

# 查詢 5: 檢查是否有阻塞
echo -e "${GREEN}🔒 當前鎖等待情況${NC}"
echo -e "${BLUE}------------------------------------------------------------------------------------------------${NC}"

psql -h "$HOST" -p "$PORT" -d "$DATABASE" -U "$USER" << 'EOSQL'
SELECT
    blocked.pid as "被阻塞PID",
    blocked_user.usename as "被阻塞用戶",
    blocking.pid as "阻塞者PID",
    blocking_user.usename as "阻塞者用戶",
    blocked.query as "被阻塞查詢"
FROM pg_catalog.pg_locks blocked
JOIN pg_catalog.pg_stat_activity blocked_user ON blocked_user.pid = blocked.pid
JOIN pg_catalog.pg_locks blocking ON blocking.locktype = blocked.locktype
    AND blocking.database IS NOT DISTINCT FROM blocked.database
    AND blocking.relation IS NOT DISTINCT FROM blocked.relation
    AND blocking.page IS NOT DISTINCT FROM blocked.page
    AND blocking.tuple IS NOT DISTINCT FROM blocked.tuple
    AND blocking.virtualxid IS NOT DISTINCT FROM blocked.virtualxid
    AND blocking.transactionid IS NOT DISTINCT FROM blocked.transactionid
    AND blocking.classid IS NOT DISTINCT FROM blocked.classid
    AND blocking.objid IS NOT DISTINCT FROM blocked.objid
    AND blocking.objsubid IS NOT DISTINCT FROM blocked.objsubid
    AND blocking.pid != blocked.pid
JOIN pg_catalog.pg_stat_activity blocking_user ON blocking_user.pid = blocking.pid
WHERE NOT blocked.granted;
EOSQL

if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ 無鎖等待${NC}"
fi

echo ""
echo -e "${BLUE}================================================================================================${NC}"
echo -e "${GREEN}✅ 分析完成${NC}"
echo -e "${BLUE}================================================================================================${NC}"

# 清理密碼環境變數
unset PGPASSWORD

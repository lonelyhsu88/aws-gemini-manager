#!/bin/bash

#####################################################################
# PostgreSQL 慢查詢檢查工具
#
# 用途：查詢和分析 PostgreSQL 慢查詢
# 作者：Claude Code Analysis
# 日期：2025-11-16
#####################################################################

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 預設值
DB_HOST="bingo-prd-replica1.ch0kboae4kuj.ap-east-1.rds.amazonaws.com"
DB_PORT="5432"
DB_NAME="bingo"
DB_USER="postgres"
DB_PASSWORD=""

# 函數：打印帶顏色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 函數：顯示幫助
show_help() {
    cat <<EOF
用法: $0 [選項]

選項:
  -h HOST         數據庫主機 (預設: bingo-prd-replica1...)
  -p PORT         數據庫端口 (預設: 5432)
  -d DATABASE     數據庫名稱 (預設: bingo)
  -U USER         數據庫用戶 (預設: postgres)
  -w PASSWORD     數據庫密碼
  --help          顯示此幫助訊息

查詢類型:
  1. pg_stat_statements - 統計歷史慢查詢 (需要啟用擴展)
  2. pg_stat_activity - 查看當前運行的查詢
  3. 慢查詢日誌 - 分析 PostgreSQL 日誌 (需要配置 log_min_duration_statement)

範例:
  $0 -w 'your_password'
  $0 -h bingo-prd.xxx.rds.amazonaws.com -w 'password'
EOF
}

# 解析參數
while [[ $# -gt 0 ]]; do
    case $1 in
        -h)
            DB_HOST="$2"
            shift 2
            ;;
        -p)
            DB_PORT="$2"
            shift 2
            ;;
        -d)
            DB_NAME="$2"
            shift 2
            ;;
        -U)
            DB_USER="$2"
            shift 2
            ;;
        -w)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "未知選項: $1"
            show_help
            exit 1
            ;;
    esac
done

# 檢查密碼
if [ -z "$DB_PASSWORD" ]; then
    print_error "請提供數據庫密碼 (-w 選項)"
    show_help
    exit 1
fi

# 設置 PGPASSWORD 環境變數
export PGPASSWORD="$DB_PASSWORD"

# 函數：執行 SQL 查詢
execute_sql() {
    local sql="$1"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$sql" 2>&1
}

# 函數：檢查 pg_stat_statements 擴展
check_pg_stat_statements() {
    print_info "檢查 pg_stat_statements 擴展..."

    local result=$(execute_sql "SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';")

    if echo "$result" | grep -q "1"; then
        print_success "pg_stat_statements 擴展已啟用"
        return 0
    else
        print_warning "pg_stat_statements 擴展未啟用"
        print_info "啟用方法："
        echo "  1. 修改 RDS 參數組: shared_preload_libraries = 'pg_stat_statements'"
        echo "  2. 重啟 RDS 實例"
        echo "  3. 執行: CREATE EXTENSION pg_stat_statements;"
        return 1
    fi
}

# 函數：查詢 Top 慢查詢 (pg_stat_statements)
query_top_slow_queries() {
    print_info "查詢 Top 20 慢查詢 (根據平均執行時間)..."
    echo ""

    execute_sql "
    SELECT
        calls AS 執行次數,
        ROUND(total_exec_time::numeric, 2) AS 總執行時間_毫秒,
        ROUND(mean_exec_time::numeric, 2) AS 平均執行時間_毫秒,
        ROUND(max_exec_time::numeric, 2) AS 最大執行時間_毫秒,
        ROUND((100.0 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS 時間佔比_百分比,
        rows AS 返回行數,
        LEFT(query, 100) AS 查詢語句_前100字符
    FROM pg_stat_statements
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY mean_exec_time DESC
    LIMIT 20;
    "
}

# 函數：查詢執行次數最多的查詢
query_most_frequent() {
    print_info "查詢執行次數最多的 Top 20 查詢..."
    echo ""

    execute_sql "
    SELECT
        calls AS 執行次數,
        ROUND(mean_exec_time::numeric, 2) AS 平均執行時間_毫秒,
        ROUND(total_exec_time::numeric, 2) AS 總執行時間_毫秒,
        rows AS 返回行數,
        LEFT(query, 100) AS 查詢語句_前100字符
    FROM pg_stat_statements
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY calls DESC
    LIMIT 20;
    "
}

# 函數：查詢當前運行的查詢
query_current_running() {
    print_info "查詢當前運行的查詢..."
    echo ""

    execute_sql "
    SELECT
        pid AS 進程ID,
        usename AS 用戶,
        application_name AS 應用名稱,
        client_addr AS 客戶端IP,
        state AS 狀態,
        EXTRACT(EPOCH FROM (now() - query_start))::INTEGER AS 執行時間_秒,
        wait_event_type AS 等待事件類型,
        wait_event AS 等待事件,
        LEFT(query, 100) AS 查詢語句_前100字符
    FROM pg_stat_activity
    WHERE state != 'idle'
        AND pid != pg_backend_pid()
        AND query NOT LIKE '%pg_stat_activity%'
    ORDER BY query_start ASC;
    "
}

# 函數：查詢長時間運行的查詢 (>5秒)
query_long_running() {
    print_info "查詢長時間運行的查詢 (>5秒)..."
    echo ""

    execute_sql "
    SELECT
        pid AS 進程ID,
        usename AS 用戶,
        application_name AS 應用名稱,
        client_addr AS 客戶端IP,
        EXTRACT(EPOCH FROM (now() - query_start))::INTEGER AS 執行時間_秒,
        state AS 狀態,
        wait_event_type AS 等待事件類型,
        wait_event AS 等待事件,
        query AS 查詢語句
    FROM pg_stat_activity
    WHERE state != 'idle'
        AND pid != pg_backend_pid()
        AND (now() - query_start) > interval '5 seconds'
    ORDER BY query_start ASC;
    "
}

# 函數：查詢表統計信息
query_table_stats() {
    print_info "查詢 t_orders 表統計信息..."
    echo ""

    execute_sql "
    SELECT
        schemaname AS 模式名,
        relname AS 表名,
        seq_scan AS 順序掃描次數,
        seq_tup_read AS 順序掃描讀取行數,
        idx_scan AS 索引掃描次數,
        idx_tup_fetch AS 索引掃描獲取行數,
        n_tup_ins AS 插入行數,
        n_tup_upd AS 更新行數,
        n_tup_del AS 刪除行數,
        n_live_tup AS 活躍行數,
        n_dead_tup AS 死亡行數,
        last_vacuum AS 最後VACUUM時間,
        last_autovacuum AS 最後自動VACUUM時間,
        last_analyze AS 最後ANALYZE時間,
        last_autoanalyze AS 最後自動ANALYZE時間
    FROM pg_stat_user_tables
    WHERE relname IN ('t_orders', 't_game')
    ORDER BY seq_scan DESC;
    "
}

# 函數：查詢索引使用情況
query_index_usage() {
    print_info "查詢 t_orders 和 t_game 表的索引使用情況..."
    echo ""

    execute_sql "
    SELECT
        schemaname AS 模式名,
        tablename AS 表名,
        indexname AS 索引名,
        idx_scan AS 索引掃描次數,
        idx_tup_read AS 索引讀取行數,
        idx_tup_fetch AS 索引獲取行數,
        pg_size_pretty(pg_relation_size(indexrelid)) AS 索引大小
    FROM pg_stat_user_indexes
    WHERE tablename IN ('t_orders', 't_game')
    ORDER BY tablename, idx_scan DESC;
    "
}

# 函數：查詢慢查詢配置
query_slow_query_config() {
    print_info "查詢慢查詢相關配置..."
    echo ""

    execute_sql "
    SELECT
        name AS 參數名,
        setting AS 當前值,
        unit AS 單位,
        context AS 上下文
    FROM pg_settings
    WHERE name IN (
        'log_min_duration_statement',
        'log_statement',
        'log_duration',
        'shared_preload_libraries',
        'pg_stat_statements.max',
        'pg_stat_statements.track'
    );
    "
}

# 函數：分析 t_orders 特定慢查詢
analyze_orders_slow_queries() {
    print_info "分析 t_orders 表的慢查詢模式..."
    echo ""

    execute_sql "
    SELECT
        calls AS 執行次數,
        ROUND(mean_exec_time::numeric, 2) AS 平均時間_毫秒,
        ROUND(max_exec_time::numeric, 2) AS 最大時間_毫秒,
        rows AS 平均返回行數,
        query AS 查詢語句
    FROM pg_stat_statements
    WHERE query LIKE '%t_orders%'
        AND query NOT LIKE '%pg_stat_statements%'
        AND mean_exec_time > 100  -- 平均執行時間 > 100ms
    ORDER BY mean_exec_time DESC
    LIMIT 10;
    "
}

# 函數：重置 pg_stat_statements 統計
reset_pg_stat_statements() {
    print_warning "這將重置所有 pg_stat_statements 統計數據！"
    read -p "確定要繼續嗎？(y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        execute_sql "SELECT pg_stat_statements_reset();"
        print_success "pg_stat_statements 統計已重置"
    else
        print_info "取消重置操作"
    fi
}

# 主函數
main() {
    echo "========================================"
    echo "  PostgreSQL 慢查詢檢查工具"
    echo "========================================"
    echo ""

    print_info "連接信息："
    echo "  主機: $DB_HOST"
    echo "  端口: $DB_PORT"
    echo "  數據庫: $DB_NAME"
    echo "  用戶: $DB_USER"
    echo ""

    # 檢查 pg_stat_statements
    if check_pg_stat_statements; then
        echo ""

        # 1. 查詢配置
        query_slow_query_config
        echo ""

        # 2. Top 慢查詢
        query_top_slow_queries
        echo ""

        # 3. 執行次數最多
        query_most_frequent
        echo ""

        # 4. t_orders 慢查詢分析
        analyze_orders_slow_queries
        echo ""
    fi

    # 5. 當前運行的查詢
    query_current_running
    echo ""

    # 6. 長時間運行的查詢
    query_long_running
    echo ""

    # 7. 表統計信息
    query_table_stats
    echo ""

    # 8. 索引使用情況
    query_index_usage
    echo ""

    print_success "✅ 檢查完成！"
    echo ""

    # 互動式選項
    cat <<EOF
其他操作：
  1. 重新執行檢查
  2. 重置 pg_stat_statements 統計 (清空歷史數據)
  3. 只查看當前運行的查詢
  4. 退出

EOF

    read -p "請選擇操作 (1-4): " -n 1 -r
    echo

    case $REPLY in
        1)
            main
            ;;
        2)
            reset_pg_stat_statements
            ;;
        3)
            query_current_running
            query_long_running
            ;;
        4)
            print_info "退出"
            exit 0
            ;;
        *)
            print_error "無效選項"
            exit 1
            ;;
    esac
}

# 執行主函數
main "$@"

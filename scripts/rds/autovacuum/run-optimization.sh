#!/bin/bash
#
# Autovacuum 優化工具 - 簡化執行腳本
# 使用方式：./run-optimization.sh [選項]
#

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默認配置
DB_HOST="bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com"
DB_PORT="5432"
DB_NAME="postgres"
DB_USER="postgres"
DB_PASSWORD=""

# 使用說明
usage() {
    cat << EOF
${CYAN}============================================================================${NC}
${GREEN}Autovacuum 優化工具${NC}
${CYAN}============================================================================${NC}

${YELLOW}使用方式：${NC}
    $0 [操作] [選項]

${YELLOW}操作：${NC}
    diagnose        診斷 t_orders 表狀態
    optimize-mild   溫和優化（推薦）
    optimize-manual 手動排程優化
    monitor         監控 autovacuum 活動
    vacuum          立即執行 VACUUM

${YELLOW}選項：${NC}
    -h, --host HOST          資料庫主機（默認: $DB_HOST）
    -p, --port PORT          端口（默認: $DB_PORT）
    -d, --database DATABASE  資料庫名稱（默認: $DB_NAME）
    -u, --user USER          用戶名（默認: $DB_USER）
    -w, --password PASSWORD  密碼（必需）
    --help                   顯示此幫助信息

${YELLOW}範例：${NC}
    # 診斷表狀態
    $0 diagnose -w 'your_password'

    # 執行溫和優化
    $0 optimize-mild -w 'your_password'

    # 監控 autovacuum
    $0 monitor -w 'your_password'

${CYAN}============================================================================${NC}
EOF
    exit 1
}

# 檢查必需參數
check_requirements() {
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -e "${RED}錯誤：缺少密碼參數${NC}"
        echo -e "請使用 -w 或 --password 指定密碼"
        exit 1
    fi

    # 檢查 psql 是否安裝
    if ! command -v psql &> /dev/null; then
        echo -e "${RED}錯誤：未找到 psql 命令${NC}"
        echo -e "請安裝 PostgreSQL 客戶端"
        exit 1
    fi
}

# 執行 SQL 腳本
execute_sql() {
    local sql_file=$1
    local description=$2

    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${GREEN}$description${NC}"
    echo -e "${BLUE}============================================================================${NC}"
    echo ""

    export PGPASSWORD="$DB_PASSWORD"

    psql -h "$DB_HOST" \
         -p "$DB_PORT" \
         -U "$DB_USER" \
         -d "$DB_NAME" \
         -f "$sql_file"

    local exit_code=$?

    unset PGPASSWORD

    if [ $exit_code -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ 執行成功${NC}"
    else
        echo ""
        echo -e "${RED}❌ 執行失敗（退出碼: $exit_code）${NC}"
        exit $exit_code
    fi
}

# 主函數
main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    local action=$1
    shift

    # 解析參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                DB_HOST="$2"
                shift 2
                ;;
            -p|--port)
                DB_PORT="$2"
                shift 2
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            -u|--user)
                DB_USER="$2"
                shift 2
                ;;
            -w|--password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                echo -e "${RED}未知選項: $1${NC}"
                usage
                ;;
        esac
    done

    check_requirements

    # 獲取腳本所在目錄
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 根據操作執行對應腳本
    case $action in
        diagnose)
            execute_sql "$SCRIPT_DIR/01-diagnose-t_orders.sql" "診斷 t_orders 表狀態"
            ;;
        optimize-mild)
            echo -e "${YELLOW}即將執行溫和優化...${NC}"
            echo -e "${CYAN}此操作會調整 autovacuum 參數，但不會禁用它${NC}"
            echo ""
            read -p "確認繼續？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute_sql "$SCRIPT_DIR/02-optimize-t_orders-mild.sql" "執行溫和優化"
            else
                echo -e "${YELLOW}操作已取消${NC}"
                exit 0
            fi
            ;;
        optimize-manual)
            echo -e "${RED}⚠️  警告：此操作將禁用 t_orders 的自動 VACUUM${NC}"
            echo -e "${YELLOW}您必須設置定時任務來手動執行 VACUUM${NC}"
            echo ""
            read -p "確認繼續？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute_sql "$SCRIPT_DIR/02-optimize-t_orders-manual.sql" "執行手動排程優化"
            else
                echo -e "${YELLOW}操作已取消${NC}"
                exit 0
            fi
            ;;
        monitor)
            execute_sql "$SCRIPT_DIR/03-monitor-autovacuum.sql" "監控 Autovacuum 活動"
            ;;
        vacuum)
            echo -e "${YELLOW}即將執行完整 VACUUM...${NC}"
            echo -e "${CYAN}此操作可能需要 1-2 小時，請勿中斷${NC}"
            echo ""
            read -p "確認繼續？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute_sql "$SCRIPT_DIR/04-manual-vacuum-t_orders.sql" "執行手動 VACUUM"
            else
                echo -e "${YELLOW}操作已取消${NC}"
                exit 0
            fi
            ;;
        *)
            echo -e "${RED}未知操作: $action${NC}"
            usage
            ;;
    esac
}

main "$@"

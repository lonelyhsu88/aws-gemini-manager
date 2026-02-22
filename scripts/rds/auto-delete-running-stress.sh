#!/usr/bin/env bash
# auto-delete-running-stress.sh - 自動偵測並刪除執行中的 STRESS 環境實例
# 用途：自動偵測指定的 bingo-stress* 實例，若在執行中則刪除（無快照）
# 警告：這是破壞性操作，請謹慎使用！

set -euo pipefail

# 配置
AWS_PROFILE="gemini-pro_ck"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/auto-delete-running-$(date +%Y%m%d_%H%M%S).log"

# 目標實例列表（硬編碼）
INSTANCES=(
    "bingo-stress"
    "bingo-stress-loyalty"
    "bingo-stress-backstage"
)

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日誌函數
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_error() {
    log "${RED}[錯誤]${NC} ${1}"
}

log_success() {
    log "${GREEN}[成功]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[警告]${NC} ${1}"
}

log_info() {
    log "${BLUE}[資訊]${NC} ${1}"
}

# 檢查 AWS CLI
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安裝"
        exit 1
    fi

    # 驗證 AWS profile
    if ! aws --profile "$AWS_PROFILE" sts get-caller-identity &> /dev/null; then
        log_error "無法使用 AWS profile: $AWS_PROFILE"
        exit 1
    fi

    log_success "AWS CLI 和 profile 驗證成功"
}

# 檢查實例狀態
check_instance_status() {
    local db_identifier=$1

    local status
    status=$(aws --profile "$AWS_PROFILE" rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null) || {
        echo "NOT_FOUND"
        return 0  # Return 0 to avoid triggering set -e
    }

    echo "$status"
    return 0
}

# 檢查是否為 Read Replica Source
is_read_replica_source() {
    local db_identifier=$1

    local replica_count
    replica_count=$(aws --profile "$AWS_PROFILE" rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].ReadReplicaDBInstanceIdentifiers' \
        --output json 2>/dev/null | jq 'length')

    if [[ $? -ne 0 ]]; then
        log_error "無法查詢 $db_identifier 的 Read Replica 資訊"
        return 2
    fi

    if [[ "$replica_count" -gt 0 ]]; then
        return 0  # 是 Read Replica Source
    else
        return 1  # 不是 Read Replica Source
    fi
}

# 獲取 Read Replicas 列表
get_read_replicas() {
    local db_identifier=$1

    aws --profile "$AWS_PROFILE" rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].ReadReplicaDBInstanceIdentifiers[]' \
        --output text 2>/dev/null
}

# 刪除實例（如果在執行中）
delete_if_running() {
    local db_identifier=$1

    log_info "檢查實例: $db_identifier"

    # 檢查實例狀態
    local status
    status=$(check_instance_status "$db_identifier") || true  # Prevent set -e exit

    if [[ "$status" == "NOT_FOUND" ]]; then
        log_warning "實例 $db_identifier 不存在，跳過"
        return 254  # 特殊返回碼表示「不存在」
    fi

    log "實例狀態: $status"

    # 只刪除 available (執行中) 的實例
    if [[ "$status" != "available" ]]; then
        log_info "實例狀態不是 available，跳過刪除"
        return 0
    fi

    # 檢查是否為 Read Replica Source
    if is_read_replica_source "$db_identifier"; then
        local replicas
        replicas=$(get_read_replicas "$db_identifier")
        log_error "實例 $db_identifier 仍有以下 Read Replicas，無法刪除："
        echo "$replicas" | tr '\t' '\n' | sed 's/^/  - /'
        log_error "請先刪除所有 Read Replicas，或手動處理"
        return 1
    fi

    # 執行刪除（不創建快照）
    log "執行刪除命令（無快照）..."

    local error_output
    error_output=$(aws --profile "$AWS_PROFILE" rds delete-db-instance \
        --db-instance-identifier "$db_identifier" \
        --skip-final-snapshot 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "實例 $db_identifier 刪除請求已提交"
        return 0
    else
        log_error "實例 $db_identifier 刪除失敗"
        log_error "AWS 錯誤訊息: $error_output"
        return 1
    fi
}

# 主函數
main() {
    log "========================================"
    log "RDS STRESS 實例自動偵測與刪除腳本"
    log "開始時間: $(date '+%Y-%m-%d %H:%M:%S')"
    log "日誌文件: $LOG_FILE"
    log "========================================"

    # 檢查 AWS CLI
    check_aws_cli

    log ""
    log "目標實例列表："
    for instance in "${INSTANCES[@]}"; do
        log "  - $instance"
    done
    log ""

    log "開始偵測並刪除執行中的實例..."
    log ""

    # 計數器
    local success_count=0
    local fail_count=0
    local skip_count=0
    local not_found_count=0

    for instance in "${INSTANCES[@]}"; do
        log "----------------------------------------"

        # Capture return code before || true
        set +e  # Temporarily disable exit on error
        delete_if_running "$instance"
        local result=$?
        set -e  # Re-enable exit on error

        if [[ $result -eq 0 ]]; then
            success_count=$((success_count + 1))
        elif [[ $result -eq 254 ]]; then
            not_found_count=$((not_found_count + 1))
        elif [[ $result -eq 1 ]]; then
            fail_count=$((fail_count + 1))
        else
            skip_count=$((skip_count + 1))
        fi

        log ""
    done

    # 總結
    log "========================================"
    log "操作完成"
    log "成功刪除: $success_count"
    log "跳過（非 available 狀態）: $skip_count"
    log "不存在: $not_found_count"
    log "失敗: $fail_count"
    log "結束時間: $(date '+%Y-%m-%d %H:%M:%S')"
    log "========================================"

    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

# 執行主函數
main "$@"

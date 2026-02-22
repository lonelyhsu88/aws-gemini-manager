#!/usr/bin/env bash
# delete-rds-stress.sh - 安全刪除 RDS STRESS 環境實例
# 用途：刪除 instances_rds.list 中標記為狀態 2 的 STRESS RDS 實例
# 警告：這是破壞性操作，請謹慎使用！

set -euo pipefail

# 配置
AWS_PROFILE="gemini-pro_ck"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_LIST="${SCRIPT_DIR}/instances_rds.list"
LOG_FILE="${SCRIPT_DIR}/delete-rds-stress-$(date +%Y%m%d_%H%M%S).log"

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
        --output text 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        log_error "無法查詢 $db_identifier 的狀態，可能是權限不足或實例不存在"
        return 1
    fi

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

# 刪除 RDS 實例
delete_rds_instance() {
    local db_identifier=$1

    log "開始刪除實例: $db_identifier"

    # 檢查實例狀態
    local status
    status=$(check_instance_status "$db_identifier")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    log "實例狀態: $status"

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
    log "執行刪除命令..."

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

# 確認操作
confirm_deletion() {
    local instances=("$@")

    log_warning "========================================"
    log_warning "警告：即將刪除以下 RDS 實例"
    log_warning "========================================"

    for instance in "${instances[@]}"; do
        log_warning "  - $instance"
    done

    log_warning ""
    log_warning "這是破壞性操作，無法撤銷！"
    log_warning "將直接刪除，不創建快照"
    log_warning "========================================"
    log_warning ""

    read -p "確定要繼續刪除嗎？請輸入 'DELETE' 確認: " confirmation

    if [[ "$confirmation" != "DELETE" ]]; then
        log "操作已取消"
        exit 0
    fi
}

# 主函數
main() {
    log "========================================"
    log "RDS STRESS 實例刪除腳本"
    log "開始時間: $(date '+%Y-%m-%d %H:%M:%S')"
    log "日誌文件: $LOG_FILE"
    log "========================================"

    # 檢查 AWS CLI
    check_aws_cli

    # 檢查實例列表文件
    if [[ ! -f "$INSTANCES_LIST" ]]; then
        log_error "找不到實例列表文件: $INSTANCES_LIST"
        exit 1
    fi

    # 讀取狀態為 2 的實例（STRESS 環境）
    local instances=()
    while IFS= read -r line; do
        # 跳過註解和空行
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        # 提取狀態和實例名稱
        local status=$(echo "$line" | awk '{print $1}')
        local db_identifier=$(echo "$line" | awk '{print $2}')

        # 只處理狀態為 2 的實例
        if [[ "$status" == "2" && "$db_identifier" =~ stress ]]; then
            instances+=("$db_identifier")
        fi
    done < "$INSTANCES_LIST"

    if [[ ${#instances[@]} -eq 0 ]]; then
        log "沒有找到需要刪除的 STRESS 實例"
        exit 0
    fi

    # 確認刪除操作
    confirm_deletion "${instances[@]}"

    log ""
    log "開始刪除實例..."
    log ""

    # 刪除每個實例
    local success_count=0
    local fail_count=0

    for instance in "${instances[@]}"; do
        log "----------------------------------------"
        if delete_rds_instance "$instance"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        log ""
    done

    # 總結
    log "========================================"
    log "刪除操作完成"
    log "成功: $success_count"
    log "失敗: $fail_count"
    log "結束時間: $(date '+%Y-%m-%d %H:%M:%S')"
    log "========================================"

    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

# 執行主函數
main "$@"

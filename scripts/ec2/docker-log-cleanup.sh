#!/bin/bash
# Docker 容器日誌定期清理腳本
# 建議使用 cron 定期執行（例如：每週日凌晨 2 點）
# Crontab: 0 2 * * 0 /usr/local/bin/docker-log-cleanup.sh

set -e

# ==================== 配置區 ====================
# 日誌大小閾值（清理大於此大小的日誌）
LOG_SIZE_THRESHOLD="100M"  # 可改為 500M, 1G 等

# 清理後保留的大小（設為 0 表示完全清空）
TRUNCATE_SIZE="0"  # 可改為 100M, 500M 等（保留最近的日誌）

# 清理腳本自己的日誌文件
CLEANUP_LOG="/home/ec2-user/toolkits/logs/docker-log-cleanup.log"

# 是否發送通知（需要安裝 mail 或設定 SNS）
ENABLE_NOTIFICATION=false
NOTIFICATION_EMAIL="your-email@example.com"

# ==================== 函數定義 ====================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$CLEANUP_LOG" > /dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_notification() {
    if [ "$ENABLE_NOTIFICATION" = true ]; then
        # 方式 1: 使用 mail 命令
        if command -v mail &> /dev/null; then
            echo "$1" | mail -s "Docker Log Cleanup Report" "$NOTIFICATION_EMAIL"
        fi

        # 方式 2: 使用 AWS SNS（如果配置了）
        # aws sns publish --topic-arn arn:aws:sns:region:account:topic --message "$1"
    fi
}

get_size_in_bytes() {
    # 將人類可讀的大小轉換為 bytes
    local size=$1
    local num=$(echo $size | sed 's/[^0-9.]//g')
    local unit=$(echo $size | sed 's/[0-9.]//g')

    case ${unit^^} in
        K|KB) echo "$(echo "$num * 1024" | bc | cut -d. -f1)" ;;
        M|MB) echo "$(echo "$num * 1024 * 1024" | bc | cut -d. -f1)" ;;
        G|GB) echo "$(echo "$num * 1024 * 1024 * 1024" | bc | cut -d. -f1)" ;;
        *) echo "$num" ;;
    esac
}

format_bytes() {
    local bytes=$1
    if [ $bytes -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [ $bytes -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [ $bytes -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

# ==================== 主程式 ====================

log "======================================"
log "🧹 Docker 容器日誌自動清理開始"
log "======================================"

# 檢查是否為 root
if [ "$EUID" -ne 0 ]; then
    log "❌ 錯誤: 請使用 sudo 執行此腳本"
    exit 1
fi

# 檢查 Docker 是否運行
if ! systemctl is-active --quiet docker; then
    log "❌ 錯誤: Docker 服務未運行"
    exit 1
fi

# 記錄清理前的磁碟使用情況
DISK_BEFORE=$(df / | tail -1 | awk '{print $5}')
log "📊 清理前磁碟使用率: $DISK_BEFORE"

# 找到 Docker root 目錄
DOCKER_ROOT=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
CONTAINERS_DIR="${DOCKER_ROOT}/containers"

if [ ! -d "$CONTAINERS_DIR" ]; then
    log "❌ 錯誤: 找不到 Docker containers 目錄: $CONTAINERS_DIR"
    exit 1
fi

log "📂 Docker Root: $DOCKER_ROOT"

# 找出大於閾值的日誌文件
log "🔍 尋找大於 $LOG_SIZE_THRESHOLD 的日誌文件..."

LARGE_LOGS=$(find "$CONTAINERS_DIR" -name "*-json.log" -type f -size +$LOG_SIZE_THRESHOLD 2>/dev/null)

if [ -z "$LARGE_LOGS" ]; then
    log "✅ 沒有發現大於 $LOG_SIZE_THRESHOLD 的容器日誌"
    log "======================================"
    exit 0
fi

# 統計
TOTAL_FILES=0
TOTAL_FREED=0
CLEANED_CONTAINERS=""

# 清理每個大日誌文件
while IFS= read -r LOG_FILE; do
    if [ ! -f "$LOG_FILE" ]; then
        continue
    fi

    CONTAINER_ID=$(basename $(dirname "$LOG_FILE"))
    CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER_ID" 2>/dev/null | sed 's/^\///' || echo "unknown")

    # 獲取文件大小
    SIZE_BEFORE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    SIZE_BEFORE_HR=$(format_bytes $SIZE_BEFORE)

    log "  📝 清理 $CONTAINER_NAME ($SIZE_BEFORE_HR)..."

    # 執行清理
    if truncate -s $TRUNCATE_SIZE "$LOG_FILE" 2>/dev/null; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_FREED=$((TOTAL_FREED + SIZE_BEFORE))
        CLEANED_CONTAINERS="${CLEANED_CONTAINERS}\n  - ${CONTAINER_NAME}: ${SIZE_BEFORE_HR}"
        log "    ✅ 成功釋放 $SIZE_BEFORE_HR"
    else
        log "    ❌ 清理失敗"
    fi

done <<< "$LARGE_LOGS"

# 記錄清理後的磁碟使用情況
DISK_AFTER=$(df / | tail -1 | awk '{print $5}')
TOTAL_FREED_HR=$(format_bytes $TOTAL_FREED)

log "======================================"
log "✅ 清理完成"
log "======================================"
log "📊 統計資訊:"
log "  - 清理文件數: $TOTAL_FILES"
log "  - 釋放空間: $TOTAL_FREED_HR"
log "  - 清理前磁碟使用: $DISK_BEFORE"
log "  - 清理後磁碟使用: $DISK_AFTER"

if [ $TOTAL_FILES -gt 0 ]; then
    log "📝 已清理的容器:"
    echo -e "$CLEANED_CONTAINERS" | tee -a "$CLEANUP_LOG"
fi

# 顯示當前磁碟情況
log ""
log "💾 當前磁碟使用情況:"
df -h / | tee -a "$CLEANUP_LOG"

log ""
log "======================================"

# 發送通知（如果啟用）
if [ $TOTAL_FILES -gt 0 ]; then
    NOTIFICATION_MSG="Docker Log Cleanup Report

清理時間: $(date '+%Y-%m-%d %H:%M:%S')
清理文件數: $TOTAL_FILES
釋放空間: $TOTAL_FREED_HR
磁碟使用率: $DISK_BEFORE → $DISK_AFTER

已清理的容器:
$(echo -e "$CLEANED_CONTAINERS")
"
    send_notification "$NOTIFICATION_MSG"
fi

# 清理舊的清理日誌（保留最近 30 天）
find $(dirname "$CLEANUP_LOG") -name "$(basename "$CLEANUP_LOG")*" -type f -mtime +30 -delete 2>/dev/null || true

exit 0

#!/usr/bin/env bash
# cron-delete-stress.sh - RDS STRESS 實例定期刪除排程包裝腳本
# 用途：透過 cron 自動化執行 STRESS 實例清理
# 建議排程：每週日凌晨 2:00 執行

set -euo pipefail

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DELETE_SCRIPT="${SCRIPT_DIR}/delete-rds-stress.sh"
LOG_DIR="${SCRIPT_DIR}/logs"
CRON_LOG="${LOG_DIR}/cron-delete-stress-$(date +%Y%m%d_%H%M%S).log"

# 建立日誌目錄
mkdir -p "$LOG_DIR"

# 日誌函數
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$CRON_LOG"
}

log "=========================================="
log "開始 RDS STRESS 實例自動刪除排程任務"
log "=========================================="

# 檢查刪除腳本是否存在
if [[ ! -f "$DELETE_SCRIPT" ]]; then
    log "錯誤：找不到刪除腳本: $DELETE_SCRIPT"
    exit 1
fi

# 檢查腳本是否可執行
if [[ ! -x "$DELETE_SCRIPT" ]]; then
    log "警告：刪除腳本不可執行，正在設定執行權限..."
    chmod +x "$DELETE_SCRIPT"
fi

# 執行刪除腳本（自動確認模式）
# 注意：cron 模式下自動選擇創建快照並確認刪除
log "執行刪除腳本..."

# 自動提供確認輸入（DELETE）
echo "DELETE" | "$DELETE_SCRIPT" >> "$CRON_LOG" 2>&1
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    log "=========================================="
    log "✅ RDS STRESS 實例刪除任務完成"
    log "=========================================="
else
    log "=========================================="
    log "❌ RDS STRESS 實例刪除任務失敗（退出碼: $EXIT_CODE）"
    log "=========================================="

    # 可選：發送錯誤通知
    # 例如：發送郵件、Slack 通知等
    # mail -s "RDS STRESS 刪除失敗" admin@example.com < "$CRON_LOG"
fi

# 清理超過 30 天的舊日誌
log "清理舊日誌檔案（保留最近 30 天）..."
find "$LOG_DIR" -name "cron-delete-stress-*.log" -mtime +30 -delete

log "任務結束，詳細日誌: $CRON_LOG"
exit $EXIT_CODE

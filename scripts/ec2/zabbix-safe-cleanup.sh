#!/bin/bash
# ========================================
# Zabbix Server 安全清理腳本
# ========================================
# 釋放約 28GB 空間（零風險）
# 實例: gemini-monitor-01 (i-040c741a76a42169b)

set -e

echo "========================================"
echo "🧹 Zabbix Server 安全磁碟清理"
echo "========================================"
echo "預計釋放: ~28GB"
echo "風險等級: 🟢 零風險"
echo ""

# 檢查是否為 root 或有 sudo 權限
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "❌ 需要 sudo 權限執行此腳本"
    echo "請使用: sudo $0"
    exit 1
fi

# 顯示當前磁碟使用情況
echo "📊 清理前磁碟使用情況："
df -h / | grep -v Filesystem
echo ""

# 詢問確認
read -p "是否繼續清理？ (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 取消清理"
    exit 0
fi

echo ""
echo "========================================"
echo "開始清理..."
echo "========================================"

# ========================================
# 1. 清理 Grafana 容器日誌 (23GB)
# ========================================
echo ""
echo "1️⃣ 清理 Grafana 容器日誌..."
GRAFANA_LOG="/var/lib/docker/containers/9e0162c7ccf869b7ef68afcf11038236711197fe8f2517cc9dc72718c5241763/9e0162c7ccf869b7ef68afcf11038236711197fe8f2517cc9dc72718c5241763-json.log"

if [ -f "$GRAFANA_LOG" ]; then
    BEFORE=$(du -sh "$GRAFANA_LOG" | awk '{print $1}')
    echo "   清理前: $BEFORE"
    sudo truncate -s 0 "$GRAFANA_LOG"
    AFTER=$(du -sh "$GRAFANA_LOG" | awk '{print $1}')
    echo "   清理後: $AFTER"
    echo "   ✅ Grafana 日誌已清理"
else
    echo "   ⚠️  Grafana 日誌檔案不存在，跳過"
fi

# ========================================
# 2. 清理 YUM cache (1.9GB)
# ========================================
echo ""
echo "2️⃣ 清理 YUM package cache..."
BEFORE_YUM=$(du -sh /var/cache/yum 2>/dev/null | awk '{print $1}' || echo "0")
echo "   清理前: $BEFORE_YUM"
sudo yum clean all -q
AFTER_YUM=$(du -sh /var/cache/yum 2>/dev/null | awk '{print $1}' || echo "0")
echo "   清理後: $AFTER_YUM"
echo "   ✅ YUM cache 已清理"

# ========================================
# 3. 清理 Docker build cache (3.6GB)
# ========================================
echo ""
echo "3️⃣ 清理 Docker build cache..."
echo "   執行: docker builder prune -a --force"
docker builder prune -a --force 2>/dev/null || echo "   ⚠️  Docker builder prune 失敗或無可清理的 cache"
echo "   ✅ Docker build cache 已清理"

# ========================================
# 4. 清理 /tmp 和 /var/tmp (可選)
# ========================================
echo ""
echo "4️⃣ 清理暫存檔案..."
echo "   清理 7 天前的暫存檔案"
sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
echo "   ✅ 暫存檔案已清理"

# ========================================
# 完成
# ========================================
echo ""
echo "========================================"
echo "✅ 清理完成！"
echo "========================================"
echo ""
echo "📊 清理後磁碟使用情況："
df -h / | grep -v Filesystem
echo ""

# 顯示詳細的磁碟空間變化
echo "📈 詳細空間使用："
echo "   系統總容量: $(df -h / | tail -1 | awk '{print $2}')"
echo "   已使用空間: $(df -h / | tail -1 | awk '{print $3}')"
echo "   可用空間: $(df -h / | tail -1 | awk '{print $4}')"
echo "   使用率: $(df -h / | tail -1 | awk '{print $5}')"
echo ""

echo "💡 下一步建議："
echo "   1. 設定 Docker 日誌輪替（防止再次發生）"
echo "   2. 安裝 CloudWatch Agent 監控磁碟使用率"
echo "   3. 設定告警（80% 警告, 90% 緊急）"
echo ""
echo "📚 詳細資訊請參考："
echo "   - ZABBIX_DISK_ANALYSIS_REPORT.md"
echo "   - ZABBIX_DISK_EMERGENCY_GUIDE.md"
echo ""

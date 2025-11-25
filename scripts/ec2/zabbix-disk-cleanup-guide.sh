#!/bin/bash
# ========================================
# Zabbix Server 磁碟空間診斷與清理指南
# ========================================
# Instance: gemini-monitor-01 (i-040c741a76a42169b)
# Problem: / (root) disk usage > 80%
# System disk: /dev/xvda (60 GB gp3)
# Data disk: /dev/sdf (100 GB gp3)

echo "========================================"
echo "🔍 Zabbix Server 磁碟空間診斷"
echo "========================================"
echo ""

# ========================================
# STEP 1: 確認磁碟使用情況
# ========================================
echo "📊 STEP 1: 檢查磁碟使用情況"
echo "----------------------------------------"
echo "$ df -h"
df -h
echo ""
echo "$ df -i  # 檢查 inode 使用情況"
df -i
echo ""

# ========================================
# STEP 2: 找出最大的目錄
# ========================================
echo "📂 STEP 2: 找出根目錄下最大的 10 個目錄"
echo "----------------------------------------"
echo "$ du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20"
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20
echo ""

# ========================================
# STEP 3: 檢查常見的空間佔用元凶
# ========================================
echo "🔎 STEP 3: 檢查常見空間佔用問題"
echo "----------------------------------------"

echo ""
echo "1️⃣ 系統日誌 (/var/log):"
echo "$ du -sh /var/log/*  | sort -hr | head -10"
du -sh /var/log/* 2>/dev/null | sort -hr | head -10
echo ""

echo "2️⃣ Zabbix 日誌:"
echo "$ du -sh /var/log/zabbix/* 2>/dev/null | sort -hr"
du -sh /var/log/zabbix/* 2>/dev/null | sort -hr
echo ""

echo "3️⃣ 舊的核心檔案 (kernel):"
echo "$ du -sh /boot/* 2>/dev/null | sort -hr"
du -sh /boot/* 2>/dev/null | sort -hr
echo "$ dpkg --list | grep linux-image  # 列出已安裝的核心"
dpkg --list 2>/dev/null | grep linux-image
echo ""

echo "4️⃣ APT 套件快取:"
echo "$ du -sh /var/cache/apt/archives/"
du -sh /var/cache/apt/archives/ 2>/dev/null
echo ""

echo "5️⃣ 暫存檔案 (/tmp):"
echo "$ du -sh /tmp/*  2>/dev/null | sort -hr | head -10"
du -sh /tmp/* 2>/dev/null | sort -hr | head -10
echo ""

echo "6️⃣ Docker 相關 (如果有安裝):"
echo "$ docker system df 2>/dev/null"
docker system df 2>/dev/null || echo "Docker 未安裝或未啟動"
echo ""

echo "7️⃣ 系統 Journal 日誌:"
echo "$ journalctl --disk-usage"
journalctl --disk-usage 2>/dev/null || echo "journalctl 無法執行"
echo ""

echo "8️⃣ Zabbix 資料庫 (如果在本機):"
if [ -d /var/lib/mysql ]; then
    echo "$ du -sh /var/lib/mysql/*  | sort -hr | head -10"
    du -sh /var/lib/mysql/* 2>/dev/null | sort -hr | head -10
elif [ -d /var/lib/pgsql ]; then
    echo "$ du -sh /var/lib/pgsql/* | sort -hr | head -10"
    du -sh /var/lib/pgsql/* 2>/dev/null | sort -hr | head -10
else
    echo "資料庫目錄未找到（可能使用外部 RDS）"
fi
echo ""

echo "9️⃣ 找出大於 100MB 的檔案:"
echo "$ find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{print \$9, \$5}' | head -20"
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | awk '{print $9, $5}' | head -20
echo ""

# ========================================
# STEP 4: 清理建議
# ========================================
echo "========================================"
echo "🧹 清理建議（執行前請備份！）"
echo "========================================"
echo ""

cat << 'EOF'
1️⃣ 清理系統日誌（安全）：
   # 清理 7 天前的日誌
   sudo find /var/log -type f -name "*.log.*" -mtime +7 -delete
   sudo find /var/log -type f -name "*.gz" -mtime +7 -delete

   # 限制 journal 日誌大小
   sudo journalctl --vacuum-time=7d
   sudo journalctl --vacuum-size=500M

2️⃣ 清理 APT 套件快取（安全）：
   sudo apt-get clean
   sudo apt-get autoclean
   sudo apt-get autoremove

3️⃣ 清理舊核心（⚠️ 小心，保留當前和上一個版本）：
   # 列出當前核心
   uname -r

   # 移除舊核心（保留當前）
   sudo apt-get autoremove --purge

4️⃣ 清理 Zabbix 日誌（根據實際情況）：
   # 檢查 Zabbix 日誌輪替設定
   cat /etc/logrotate.d/zabbix-server

   # 手動清理舊日誌（謹慎！）
   sudo find /var/log/zabbix -name "*.log.*" -mtime +30 -delete

5️⃣ 清理 Docker（如果有使用）：
   sudo docker system prune -a --volumes
   # ⚠️ 這會刪除所有未使用的映像、容器和 volumes

6️⃣ 清理暫存檔案：
   sudo find /tmp -type f -atime +7 -delete
   sudo find /var/tmp -type f -atime +7 -delete

7️⃣ Zabbix 資料庫清理（⚠️ 高風險，請先諮詢 DBA）：
   # 檢查 Zabbix 歷史資料保留設定
   # 調整 Administration -> General -> Housekeeping
   # 或透過資料庫直接清理舊資料

8️⃣ 考慮擴充磁碟容量：
   # 如果清理後仍然不足，建議擴充 EBS volume
   # 當前: /dev/xvda 60 GB
   # 建議: 擴充至 80-100 GB

EOF

echo ""
echo "========================================"
echo "⚠️  重要注意事項"
echo "========================================"
echo ""
echo "1. 🔴 執行任何清理前，請先建立 EBS snapshot 備份"
echo "2. 🔴 確認 Zabbix 服務狀態，避免清理期間中斷監控"
echo "3. 🟡 建議先執行安全的清理（日誌、APT cache）"
echo "4. 🟡 如需清理 Zabbix 資料，請先確認資料保留政策"
echo "5. 🟢 建立 CloudWatch 告警監控磁碟使用率"
echo ""

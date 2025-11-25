# Zabbix Server Docker 日誌自動清理機制部署

**JIRA Ticket**: [OPS-830](https://jira.ftgaming.cc/browse/OPS-830)
**部署日期**: 2025-11-25
**狀態**: ✅ 已完成
**伺服器**: gemini-monitor-01 (i-040c741a76a42169b)

---

## 📋 任務概述

在 Zabbix Server (gemini-monitor-01) 上部署 Docker 容器日誌自動清理機制，防止磁碟空間被容器日誌佔滿。

---

## 🎯 部署內容

### 1. Docker Daemon 日誌輪替配置

**配置文件**: `/etc/docker/daemon.json`

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

- 每個容器日誌最大 10MB
- 保留 3 個輪替文件
- 總上限: 30MB/容器

### 2. 自動清理腳本

**安裝位置**: `/home/ec2-user/toolkits/docker-log-cleanup.sh`

**功能**:
- 自動找到大於 100MB 的容器日誌
- 清理日誌文件 (truncate 到 0)
- 記錄清理過程和結果
- 顯示釋放的空間大小

### 3. Cron Job 自動排程

**執行時間**: 每天凌晨 4 點
**執行用戶**: ec2-user
**Cron 設定**:
```
0 4 * * * sudo /home/ec2-user/toolkits/docker-log-cleanup.sh >> /home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log 2>&1
```

### 4. 日誌目錄結構

```
/home/ec2-user/toolkits/
├── docker-log-cleanup.sh (5.5K)           # 清理腳本
└── logs/
    ├── docker-log-cleanup.log             # 清理執行日誌
    └── docker-log-cleanup-cron.log        # Cron 執行日誌
```

---

## ✅ 部署結果

### 部署狀態

| 項目 | 狀態 |
|------|------|
| 腳本安裝 | ✅ 已安裝到 /home/ec2-user/toolkits/ |
| Cron Job | ✅ 已設定 (每天凌晨 4 點) |
| Docker 配置 | ✅ 已更新 |
| 日誌目錄 | ✅ 已創建 |
| 權限問題 | ✅ 已修正 |
| 測試執行 | ✅ 成功無錯誤 |

### 系統狀態

| 項目 | 當前狀態 |
|------|---------|
| **磁碟使用率** | 20% (健康) |
| **可用空間** | 49 GB / 60 GB |
| **容器日誌** | 無大於 100MB 的日誌 |
| **運行容器** | Grafana, Zabbix Server, Zabbix Web, MariaDB |

---

## 📂 部署文件

### 已創建的腳本和文檔

```
scripts/ec2/
├── docker-log-cleanup.sh                  # 清理腳本 (5.5K)
├── docker-log-rotation-setup.sh           # 自動化安裝腳本 (4.4K)
├── DEPLOY_GUIDE.md                        # 部署指南 (7.1K)
├── DOCKER_GRAFANA_GUIDE.md                # 快速指南 (5.3K)
├── DOCKER_LOG_ROTATION_GUIDE.md           # 完整文檔 (11K)
└── create_jira_ticket.py                  # JIRA ticket 創建腳本
```

---

## 🔧 維護命令

### 日常檢查

```bash
# SSH 登入
ssh -i ~/.ssh/hk-devops.pem ec2-user@43.199.41.16

# 查看清理執行日誌
tail -f /home/ec2-user/toolkits/logs/docker-log-cleanup.log

# 查看 Cron 執行日誌
tail -f /home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log

# 檢查磁碟使用
df -h /

# 檢查容器日誌大小
find /var/lib/docker/containers -name "*-json.log" -exec ls -lh {} \; | sort -k5 -hr | head -10
```

### 手動操作

```bash
# 手動執行清理
sudo /home/ec2-user/toolkits/docker-log-cleanup.sh

# 檢查 Cron 設定
sudo -u ec2-user crontab -l

# 檢查 Docker daemon 配置
cat /etc/docker/daemon.json

# 檢查容器狀態
docker ps
```

---

## ⚠️ 重要提醒

### Docker 重啟

**現有容器需要重啟才會使用新的日誌輪替設定**：

```bash
# 建議在維護時段執行（凌晨 2-5 點）
sudo systemctl restart docker

# 或只重啟特定容器
docker restart grafana
docker restart zabbix-web-apache-mysql
docker restart zabbix-server-mysql
docker restart mariadb
```

### 下次自動執行

- **下次執行時間**: 2025-11-26 04:00 (明天凌晨 4 點)
- **驗證方式**: 檢查 `/home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log`

---

## 🐛 問題與解決

### 問題 1: 權限錯誤

**問題描述**:
```
tee: /var/log/docker-log-cleanup.log: Permission denied
```

**原因**: 腳本嘗試寫入 `/var/log/` 目錄時沒有權限

**解決方案**:
1. 將日誌路徑改為 `/home/ec2-user/toolkits/logs/docker-log-cleanup.log`
2. 修改 log() 函數使用 `sudo tee` 確保寫入權限
3. 重新部署腳本

**修正後的日誌配置**:
```bash
CLEANUP_LOG="/home/ec2-user/toolkits/logs/docker-log-cleanup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$CLEANUP_LOG" > /dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}
```

---

## 📊 部署效果預估

雖然當前磁碟使用率已經很健康 (20%)，但此機制將確保：

| 預防場景 | 效果 |
|---------|------|
| Grafana 日誌暴增 | 自動清理 > 100MB 的日誌 |
| Zabbix Web 日誌增長 | 自動清理 > 100MB 的日誌 |
| 新容器日誌累積 | 自動輪替（10MB x 3 = 30MB 上限）|
| 長期運行 | 保持磁碟使用率在健康範圍 |

---

## 📚 相關文檔

### 本地文檔

- **DEPLOY_GUIDE.md** - 詳細部署指南
- **DOCKER_GRAFANA_GUIDE.md** - 快速參考指南
- **DOCKER_LOG_ROTATION_GUIDE.md** - 完整文檔 (11K)
- **ZABBIX_DISK_EMERGENCY_GUIDE.md** - 緊急處理指南
- **ZABBIX_DISK_ANALYSIS_REPORT.md** - 磁碟分析報告

### 線上資源

- **JIRA Ticket**: https://jira.ftgaming.cc/browse/OPS-830
- **Docker 日誌驅動文檔**: https://docs.docker.com/config/containers/logging/json-file/

---

## ✅ 檢查清單

### 部署驗證

- [x] 腳本已上傳到 `/home/ec2-user/toolkits/`
- [x] Cron job 已設定並驗證
- [x] Docker daemon 配置已更新
- [x] 日誌目錄已創建
- [x] 手動執行測試成功
- [x] 權限問題已解決
- [x] JIRA ticket 已創建 (OPS-830)
- [x] 本地文檔已創建

### 後續追蹤

- [ ] 2025-11-26 檢查 Cron 是否正常執行
- [ ] 一週後檢查磁碟使用情況
- [ ] 維護時段重啟 Docker（套用新配置）
- [ ] 監控日誌輪替是否正常運作

---

## 📞 聯絡資訊

- **JIRA Ticket**: [OPS-830](https://jira.ftgaming.cc/browse/OPS-830)
- **部署工程師**: Claude (AI Assistant)
- **審核**: DevOps Team

---

**最後更新**: 2025-11-25 10:38
**版本**: 1.0
**狀態**: ✅ 已完成並驗證

# Docker 日誌自動清理與輪替設定指南

## 📋 概述

本指南提供 Docker 容器日誌的自動清理與輪替解決方案，防止日誌無限增長導致磁碟空間耗盡。

**問題背景**:
- Grafana 容器日誌達到 23GB
- Zabbix Web 容器日誌達到 1.7GB
- 系統碟使用率高達 78%

**解決方案**:
1. **Docker Daemon 日誌輪替**: 限制每個容器的日誌大小
2. **定期清理腳本**: 自動清理超大日誌文件
3. **Cron 排程**: 定期執行清理

---

## 🚀 快速開始

### 一鍵安裝（推薦）

```bash
# 1. 上傳腳本到伺服器
scp -i <key.pem> docker-log-cleanup.sh ubuntu@<server-ip>:/tmp/
scp -i <key.pem> docker-log-rotation-setup.sh ubuntu@<server-ip>:/tmp/

# 2. SSH 登入
ssh -i <key.pem> ubuntu@<server-ip>

# 3. 執行自動化設定
cd /tmp
sudo bash docker-log-rotation-setup.sh
```

**設定內容**:
- ✅ 配置 Docker daemon 日誌輪替 (max-size: 10m, max-file: 3)
- ✅ 安裝清理腳本到 `/usr/local/bin/docker-log-cleanup.sh`
- ✅ 設定 Cron job (預設每週日凌晨 2 點執行)
- ✅ (可選) 重啟 Docker 服務

---

## 📁 腳本說明

### 1. `docker-log-cleanup.sh` - 定期清理腳本

**功能**:
- 自動找到大於閾值的容器日誌 (預設 100MB)
- 清理日誌文件 (truncate 到指定大小)
- 記錄清理過程和結果
- 支援通知功能 (Email/SNS)

**配置參數**:

```bash
# 編輯 /usr/local/bin/docker-log-cleanup.sh

# 日誌大小閾值（清理大於此大小的日誌）
LOG_SIZE_THRESHOLD="100M"  # 可改為 500M, 1G 等

# 清理後保留的大小
TRUNCATE_SIZE="0"  # 0=完全清空, 或 100M, 500M 等

# 清理腳本日誌
CLEANUP_LOG="/var/log/docker-log-cleanup.log"

# Email 通知
ENABLE_NOTIFICATION=false
NOTIFICATION_EMAIL="your-email@example.com"
```

**手動執行測試**:

```bash
sudo /usr/local/bin/docker-log-cleanup.sh
```

**預期輸出**:

```
======================================
🧹 Docker 容器日誌自動清理開始
======================================
📊 清理前磁碟使用率: 78%
📂 Docker Root: /var/lib/docker
🔍 尋找大於 100M 的日誌文件...
  📝 清理 grafana (23.45 GB)...
    ✅ 成功釋放 23.45 GB
  📝 清理 zabbix-web-apache-mysql (1.68 GB)...
    ✅ 成功釋放 1.68 GB
======================================
✅ 清理完成
======================================
📊 統計資訊:
  - 清理文件數: 2
  - 釋放空間: 25.13 GB
  - 清理前磁碟使用: 78%
  - 清理後磁碟使用: 31%
```

---

### 2. `docker-log-rotation-setup.sh` - 自動化設定腳本

**功能**:
- 配置 Docker daemon 日誌輪替
- 安裝清理腳本
- 設定 Cron job
- 重啟 Docker 服務

**執行流程**:

```
[1/4] 設定 Docker Daemon 日誌輪替配置
  → 備份 /etc/docker/daemon.json
  → 新增/合併日誌輪替設定

[2/4] 安裝定期清理腳本
  → 複製到 /usr/local/bin/docker-log-cleanup.sh
  → 設定執行權限

[3/4] 設定 Cron Job
  → 選擇執行頻率
  → 新增到 crontab

[4/4] 重啟 Docker 服務
  → 詢問是否立即重啟
  → 驗證服務狀態
```

---

## ⚙️ 詳細配置

### Docker Daemon 日誌輪替

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

**說明**:
- `max-size`: 單個日誌文件最大大小 (10m = 10MB)
- `max-file`: 保留的日誌文件數量 (3 個)
- 總日誌大小 = max-size × max-file = 30MB/容器

**應用方式**:
- **新容器**: 自動應用新設定
- **現有容器**: 需要重啟容器才會生效

```bash
# 重啟所有容器（謹慎操作！）
docker restart $(docker ps -q)

# 或只重啟特定容器
docker restart grafana zabbix-web-apache-mysql
```

**驗證**:

```bash
# 檢查容器的日誌配置
docker inspect <container-name> | grep -A 5 LogConfig
```

---

### Cron Job 設定

**檢查 Cron job**:

```bash
crontab -l
```

**預期輸出**:

```
# 每週日凌晨 2 點執行
0 2 * * 0 /usr/local/bin/docker-log-cleanup.sh >> /var/log/docker-log-cleanup-cron.log 2>&1
```

**修改執行頻率**:

```bash
crontab -e
```

**常見 Cron 格式**:

| 頻率 | Cron 格式 | 說明 |
|------|----------|------|
| 每天凌晨 2 點 | `0 2 * * *` | 適合日誌增長快速的環境 |
| 每週日凌晨 2 點 | `0 2 * * 0` | **推薦** - 平衡清理頻率和資源 |
| 每月 1 號凌晨 2 點 | `0 2 1 * *` | 適合日誌增長緩慢的環境 |
| 每 6 小時 | `0 */6 * * *` | 緊急情況或日誌暴增時使用 |

**查看 Cron 執行日誌**:

```bash
tail -f /var/log/docker-log-cleanup-cron.log
```

---

## 📊 監控與驗證

### 1. 檢查清理腳本日誌

```bash
tail -f /var/log/docker-log-cleanup.log
```

### 2. 檢查磁碟使用情況

```bash
# 系統整體
df -h /

# Docker 目錄
du -sh /var/lib/docker/containers/*
```

### 3. 檢查容器日誌大小

```bash
# 手動檢查
find /var/lib/docker/containers -name "*-json.log" -type f -exec ls -lh {} \; | sort -k5 -hr | head -10

# 或使用腳本
sudo bash /tmp/clean-docker-logs.sh
```

### 4. 檢查 Docker 配置是否生效

```bash
# 檢查 daemon 配置
cat /etc/docker/daemon.json

# 檢查特定容器的日誌配置
docker inspect grafana | jq '.[0].HostConfig.LogConfig'
```

**預期輸出**:

```json
{
  "Type": "json-file",
  "Config": {
    "max-file": "3",
    "max-size": "10m"
  }
}
```

---

## 🔄 維護操作

### 手動清理（緊急情況）

```bash
# 1. 清理所有大於 100MB 的日誌
sudo find /var/lib/docker/containers -name "*-json.log" -type f -size +100M -exec truncate -s 0 {} \;

# 2. 或執行清理腳本
sudo /usr/local/bin/docker-log-cleanup.sh

# 3. 檢查效果
df -h /
```

### 調整清理參數

```bash
# 編輯清理腳本
sudo vi /usr/local/bin/docker-log-cleanup.sh

# 修改這些參數:
LOG_SIZE_THRESHOLD="500M"  # 提高閾值
TRUNCATE_SIZE="100M"       # 保留最近 100MB
```

### 調整 Cron 頻率

```bash
# 編輯 crontab
crontab -e

# 改為每天執行
0 2 * * * /usr/local/bin/docker-log-cleanup.sh >> /var/log/docker-log-cleanup-cron.log 2>&1
```

### 停用自動清理

```bash
# 移除 Cron job
crontab -e
# 刪除或註釋掉相關行

# 或完全清空 crontab
crontab -r
```

---

## ⚠️ 重要注意事項

### Docker 重啟影響

- ✅ **Docker daemon 重啟**: 新設定立即生效於新容器
- ⚠️ **現有容器**: 需要重啟容器才會應用新的日誌設定
- ⚠️ **服務中斷**: 重啟 Docker 會短暫中斷所有容器

**建議重啟時機**:
- 低峰時段 (例如凌晨)
- 維護時段
- 或等待容器自然重啟

### 日誌保留策略

**Truncate vs Delete**:
- ✅ **Truncate** (`truncate -s 0`): 清空內容但保留文件，容器無需重啟
- ⚠️ **Delete** (`rm`): 刪除文件，可能導致 Docker 日誌驅動出錯

**保留建議**:
- 生產環境: 保留 3-7 天日誌 (或 100-500MB)
- 測試環境: 保留 1-3 天日誌
- 監控環境 (Grafana/Zabbix): 可以更短 (日誌量大)

### 備份考量

**清理前**:
- ✅ 重要容器的日誌應該先備份或匯出
- ✅ 考慮使用集中式日誌系統 (ELK, CloudWatch Logs)
- ✅ 設定 Docker 日誌驅動轉發 (syslog, fluentd, awslogs)

---

## 🎯 最佳實踐

### 1. 多層防護策略

```
第一層: Docker Daemon 日誌輪替
  └─ 限制單個容器日誌上限 (30MB)

第二層: 定期清理腳本
  └─ 清理超大歷史日誌 (>100MB)

第三層: CloudWatch 告警
  └─ 磁碟使用率 > 80% 發送通知
```

### 2. 日誌管理階梯

| 環境 | max-size | max-file | 清理閾值 | Cron 頻率 |
|------|----------|----------|---------|----------|
| 開發 | 5m | 2 | 50M | 每天 |
| 測試 | 10m | 3 | 100M | 每週 |
| 生產 (低流量) | 10m | 3 | 100M | 每週 |
| 生產 (高流量) | 20m | 5 | 500M | 每天 |
| 監控系統 | 10m | 3 | 100M | 每週 |

### 3. 集中式日誌方案

考慮使用日誌聚合系統:

**AWS CloudWatch Logs**:

```json
{
  "log-driver": "awslogs",
  "log-opts": {
    "awslogs-region": "ap-east-1",
    "awslogs-group": "zabbix-containers",
    "awslogs-create-group": "true"
  }
}
```

**Syslog**:

```json
{
  "log-driver": "syslog",
  "log-opts": {
    "syslog-address": "tcp://syslog.example.com:514",
    "tag": "{{.Name}}/{{.ID}}"
  }
}
```

### 4. 容器特定配置

不同容器使用不同的日誌策略:

**docker-compose.yml**:

```yaml
version: '3'
services:
  grafana:
    image: grafana/grafana-enterprise:11.6.2
    logging:
      driver: "json-file"
      options:
        max-size: "20m"   # Grafana 日誌較多
        max-file: "5"

  zabbix-server:
    image: zabbix/zabbix-server-mysql:latest
    logging:
      driver: "json-file"
      options:
        max-size: "10m"   # Zabbix Server 日誌適中
        max-file: "3"
```

---

## 🧪 測試驗證

### 測試日誌輪替是否生效

```bash
# 1. 重啟一個測試容器
docker restart grafana

# 2. 產生大量日誌
docker logs -f grafana &

# 3. 等待一段時間後檢查日誌文件
ls -lh /var/lib/docker/containers/*/grafana*-json.log*

# 預期看到多個日誌文件 (*.log, *.log.1, *.log.2)
# 每個不超過 max-size
```

### 測試清理腳本

```bash
# 1. 乾跑（dry-run）模式
# 修改腳本加入 --dry-run 邏輯，只顯示不執行

# 2. 實際執行
sudo /usr/local/bin/docker-log-cleanup.sh

# 3. 檢查結果
cat /var/log/docker-log-cleanup.log
df -h /
```

---

## 📞 故障排除

### Q1: Docker 重啟後容器未啟動

```bash
# 檢查 Docker 狀態
sudo systemctl status docker

# 檢查 daemon.json 語法
sudo dockerd --validate --config-file=/etc/docker/daemon.json

# 查看 Docker 日誌
sudo journalctl -u docker -n 50
```

### Q2: Cron job 沒有執行

```bash
# 檢查 Cron 服務
sudo systemctl status cron

# 檢查 Cron 日誌
sudo grep CRON /var/log/syslog

# 測試腳本權限
ls -l /usr/local/bin/docker-log-cleanup.sh
```

### Q3: 清理後磁碟空間未釋放

```bash
# 1. 確認文件已清理
ls -lh /var/lib/docker/containers/*/*.log

# 2. 檢查是否有程序占用
lsof | grep deleted

# 3. 重啟 Docker（釋放句柄）
sudo systemctl restart docker
```

### Q4: 日誌輪替未生效於現有容器

```bash
# 重啟容器以應用新配置
docker restart <container-name>

# 或使用 docker-compose
cd <compose-directory>
docker-compose restart
```

---

## 📚 參考資料

- [Docker Logging Drivers](https://docs.docker.com/config/containers/logging/configure/)
- [Docker JSON File Logging Driver](https://docs.docker.com/config/containers/logging/json-file/)
- [Cron Job Tutorial](https://crontab.guru/)
- [Linux Disk Space Management](https://www.cyberciti.biz/faq/linux-find-large-files-in-directory-recursively-using-find-du/)

---

## ✅ 檢查清單

### 初次設定

- [ ] 上傳腳本到伺服器
- [ ] 執行 `docker-log-rotation-setup.sh`
- [ ] 確認 `/etc/docker/daemon.json` 配置正確
- [ ] 確認清理腳本已安裝到 `/usr/local/bin/`
- [ ] 確認 Cron job 已設定
- [ ] (維護時段) 重啟 Docker 服務
- [ ] 驗證容器狀態正常
- [ ] 測試手動執行清理腳本

### 定期檢查 (每月)

- [ ] 檢查清理腳本日誌: `/var/log/docker-log-cleanup.log`
- [ ] 檢查磁碟使用率: `df -h /`
- [ ] 檢查容器日誌大小
- [ ] 檢查 Cron job 是否正常執行
- [ ] 驗證日誌輪替是否生效

### 問題發生時

- [ ] 檢查磁碟使用情況
- [ ] 手動執行清理腳本
- [ ] 檢查 Docker daemon 日誌
- [ ] 檢查 Cron 日誌
- [ ] 必要時調整清理參數
- [ ] 考慮磁碟擴充

---

**最後更新**: 2025-11-25
**維護者**: DevOps Team
**版本**: 1.0

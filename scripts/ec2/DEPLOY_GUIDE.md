# Docker 日誌自動清理部署指南

> **目標伺服器**: gemini-monitor-01 (Zabbix Server)
> **腳本位置**: `/home/ec2-user/toolkits/docker-log-cleanup.sh`
> **執行排程**: 每天凌晨 4 點 (ec2-user Cron)

---

## 🚀 快速部署

### 步驟 1: 上傳腳本到 Zabbix Server

```bash
# 切換到腳本目錄
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/ec2

# 上傳兩個腳本
scp -i <your-key.pem> \
  docker-log-cleanup.sh \
  docker-log-rotation-setup.sh \
  ec2-user@<zabbix-server-ip>:/tmp/
```

### 步驟 2: SSH 登入並執行安裝

```bash
# SSH 登入
ssh -i <your-key.pem> ec2-user@<zabbix-server-ip>

# 執行安裝腳本（需要 sudo）
cd /tmp
sudo bash docker-log-rotation-setup.sh
```

**安裝過程會自動完成**:

1. ✅ 設定 Docker daemon 日誌輪替
2. ✅ 創建 `/home/ec2-user/toolkits/` 目錄
3. ✅ 創建 `/home/ec2-user/toolkits/logs/` 日誌目錄
4. ✅ 複製清理腳本到 toolkits
5. ✅ 設定 ec2-user 的 Cron job (每天凌晨 4 點)
6. ⚠️ 詢問是否重啟 Docker

### 步驟 3: 驗證安裝

```bash
# 1. 檢查腳本是否安裝
ls -lh /home/ec2-user/toolkits/

# 預期輸出:
# -rwxr-xr-x 1 ec2-user ec2-user 5.5K docker-log-cleanup.sh
# drwxr-xr-x 2 ec2-user ec2-user logs/

# 2. 檢查 Cron job
sudo -u ec2-user crontab -l

# 預期輸出:
# 0 4 * * * sudo /home/ec2-user/toolkits/docker-log-cleanup.sh >> /home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log 2>&1

# 3. 檢查 Docker daemon 配置
cat /etc/docker/daemon.json

# 預期輸出:
# {
#   "log-driver": "json-file",
#   "log-opts": {
#     "max-size": "10m",
#     "max-file": "3"
#   }
# }

# 4. 測試手動執行
sudo /home/ec2-user/toolkits/docker-log-cleanup.sh

# 5. 查看清理日誌
cat /var/log/docker-log-cleanup.log
```

---

## 📂 文件結構

部署完成後的目錄結構：

```
/home/ec2-user/toolkits/
├── docker-log-cleanup.sh           # 清理腳本
└── logs/
    └── docker-log-cleanup-cron.log # Cron 執行日誌

/etc/docker/
└── daemon.json                     # Docker 日誌輪替配置

/var/log/
└── docker-log-cleanup.log          # 清理腳本執行日誌
```

---

## ⚙️ Cron Job 配置

**執行用戶**: ec2-user
**執行時間**: 每天凌晨 4 點
**執行命令**: `sudo /home/ec2-user/toolkits/docker-log-cleanup.sh`

**Cron 設定**:
```
0 4 * * * sudo /home/ec2-user/toolkits/docker-log-cleanup.sh >> /home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log 2>&1
```

**修改執行時間**:
```bash
# 編輯 ec2-user 的 crontab
sudo -u ec2-user crontab -e

# 修改為其他時間:
0 2 * * *     # 每天凌晨 2 點
0 6 * * *     # 每天凌晨 6 點
0 */6 * * *   # 每 6 小時
0 2 * * 0     # 每週日凌晨 2 點
```

---

## 📊 清理效果預估

| 項目 | 當前狀況 | 清理後 |
|------|---------|--------|
| **Grafana 日誌** | 23 GB | 10 MB |
| **Zabbix Web 日誌** | 1.7 GB | 10 MB |
| **磁碟使用率** | 78% | **~30%** |
| **可用空間** | 14 GB | **~42 GB** |

---

## 🔧 日常維護

### 查看清理狀態

```bash
# 查看清理腳本執行日誌
tail -f /var/log/docker-log-cleanup.log

# 查看 Cron 執行日誌
tail -f /home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log

# 查看最近一次清理結果
tail -50 /var/log/docker-log-cleanup.log
```

### 手動執行清理

```bash
# 立即執行清理
sudo /home/ec2-user/toolkits/docker-log-cleanup.sh

# 查看執行結果
df -h /
```

### 檢查 Docker 容器日誌大小

```bash
# 查看所有容器日誌大小
find /var/lib/docker/containers -name "*-json.log" -exec ls -lh {} \; | sort -k5 -hr | head -10

# 查看特定容器日誌
docker inspect grafana | grep LogPath
```

---

## ⚠️ 重要提醒

### Docker 重啟

設定完成後，**現有容器需要重啟才會使用新的日誌輪替設定**：

```bash
# 建議在維護時段執行（凌晨 2-5 點）
sudo systemctl restart docker

# 或只重啟特定容器
docker restart grafana
docker restart zabbix-web-apache-mysql
```

### Sudo 權限設定

如果 ec2-user 沒有 sudo 權限執行清理腳本，需要設定：

```bash
# 編輯 sudoers
sudo visudo

# 添加以下行（允許 ec2-user 無密碼執行清理腳本）
ec2-user ALL=(ALL) NOPASSWD: /home/ec2-user/toolkits/docker-log-cleanup.sh
```

---

## 🔄 回滾方案

### 還原 Docker 配置

```bash
# 配置文件會自動備份
ls -lt /etc/docker/daemon.json.backup.*

# 還原備份
sudo cp /etc/docker/daemon.json.backup.YYYYMMDD-HHMMSS /etc/docker/daemon.json
sudo systemctl restart docker
```

### 停用自動清理

```bash
# 移除 Cron job
sudo -u ec2-user crontab -e
# 刪除相關行

# 或完全清空
sudo -u ec2-user crontab -r

# 刪除腳本
sudo rm -rf /home/ec2-user/toolkits/docker-log-cleanup.sh
```

---

## 📊 監控建議

### 1. 設定 CloudWatch 告警

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/ec2
./setup-zabbix-disk-alerts.sh your-email@example.com
```

### 2. 設定清理結果通知

編輯清理腳本啟用 Email 通知：

```bash
sudo vi /home/ec2-user/toolkits/docker-log-cleanup.sh

# 修改這些變數:
ENABLE_NOTIFICATION=true
NOTIFICATION_EMAIL="your-email@example.com"
```

### 3. Zabbix 自我監控

在 Zabbix 中添加監控項目：
- 磁碟使用率 > 80% 觸發警告
- 磁碟使用率 > 90% 觸發緊急告警

---

## 🧪 測試檢查清單

### 安裝後檢查

- [ ] `/home/ec2-user/toolkits/docker-log-cleanup.sh` 存在且可執行
- [ ] `/home/ec2-user/toolkits/logs/` 目錄存在
- [ ] `/etc/docker/daemon.json` 配置正確
- [ ] `sudo -u ec2-user crontab -l` 顯示 Cron job
- [ ] 手動執行成功: `sudo /home/ec2-user/toolkits/docker-log-cleanup.sh`
- [ ] Docker 服務運行正常
- [ ] 容器狀態正常

### 第二天檢查（驗證 Cron 執行）

- [ ] 檢查 Cron 日誌: `/home/ec2-user/toolkits/logs/docker-log-cleanup-cron.log`
- [ ] 檢查清理日誌: `/var/log/docker-log-cleanup.log`
- [ ] 確認磁碟使用率下降: `df -h /`
- [ ] 確認容器日誌大小正常

---

## 📞 故障排除

### Q1: Cron 沒有執行

```bash
# 檢查 Cron 服務
sudo systemctl status crond

# 查看系統日誌
sudo grep CRON /var/log/messages

# 檢查 ec2-user 的 Cron
sudo -u ec2-user crontab -l

# 檢查腳本權限
ls -l /home/ec2-user/toolkits/docker-log-cleanup.sh
```

### Q2: 沒有 sudo 權限

```bash
# 測試 sudo 權限
sudo /home/ec2-user/toolkits/docker-log-cleanup.sh

# 如果要求密碼，設定 NOPASSWD
sudo visudo
# 添加: ec2-user ALL=(ALL) NOPASSWD: /home/ec2-user/toolkits/docker-log-cleanup.sh
```

### Q3: 清理後空間未釋放

```bash
# 檢查文件是否清理
ls -lh /var/lib/docker/containers/*/*.log

# 檢查是否有程序占用
lsof | grep deleted

# 重啟 Docker 釋放句柄
sudo systemctl restart docker
```

---

## 📚 相關文檔

- **快速指南**: `DOCKER_GRAFANA_GUIDE.md`
- **完整文檔**: `DOCKER_LOG_ROTATION_GUIDE.md`
- **緊急處理**: `ZABBIX_DISK_EMERGENCY_GUIDE.md`
- **磁碟分析**: `ZABBIX_DISK_ANALYSIS_REPORT.md`

---

**最後更新**: 2025-11-25
**腳本位置**: `/home/ec2-user/toolkits/`
**執行排程**: 每天凌晨 4 點 (ec2-user Cron)
**維護者**: DevOps Team

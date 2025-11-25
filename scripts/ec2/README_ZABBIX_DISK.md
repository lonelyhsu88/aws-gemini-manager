# Zabbix Server 磁碟管理工具

## 🚨 緊急情況快速指南

### 當前問題
- **實例**: gemini-monitor-01 (i-040c741a76a42169b)
- **問題**: `/` (root) 磁碟使用率 > 80%
- **系統碟**: /dev/xvda (60 GB gp3)

### 🔥 立即行動（3 步驟）

```bash
# 1. 備份（5 分鐘）
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager
chmod +x scripts/ec2/quick-backup-zabbix.sh
./scripts/ec2/quick-backup-zabbix.sh

# 2. SSH 登入並診斷
ssh -i <your-key.pem> ubuntu@<zabbix-server-ip>
df -h  # 確認使用率

# 3. 執行安全清理
sudo apt-get clean
sudo apt-get autoclean
sudo find /var/log -type f -name "*.gz" -mtime +7 -delete
sudo journalctl --vacuum-time=7d
df -h  # 再次確認
```

---

## 📁 工具清單

### 1. 快速備份腳本
**檔案**: `quick-backup-zabbix.sh`

自動建立系統碟和資料碟的 EBS snapshot。

```bash
chmod +x scripts/ec2/quick-backup-zabbix.sh
./scripts/ec2/quick-backup-zabbix.sh
```

**輸出範例**:
```
✅ 系統碟 Snapshot: snap-0abc123def456
✅ 資料碟 Snapshot: snap-0def789ghi012
```

---

### 2. 磁碟診斷腳本
**檔案**: `zabbix-disk-cleanup-guide.sh`

需要在 Zabbix Server 實例上執行，提供詳細的磁碟使用分析。

```bash
# 上傳到實例
scp -i <key.pem> scripts/ec2/zabbix-disk-cleanup-guide.sh ubuntu@<ip>:/tmp/

# 在實例上執行
ssh -i <key.pem> ubuntu@<ip>
bash /tmp/zabbix-disk-cleanup-guide.sh
```

**功能**:
- ✅ 檢查磁碟使用情況（df -h, df -i）
- ✅ 找出最大的目錄和檔案
- ✅ 分析常見的空間佔用問題
- ✅ 提供清理建議

---

### 3. 監控告警設定腳本
**檔案**: `setup-zabbix-disk-alerts.sh`

設定 CloudWatch 告警，預防未來再次發生。

**前提**: 實例上已安裝 CloudWatch Agent

```bash
chmod +x scripts/ec2/setup-zabbix-disk-alerts.sh
./scripts/ec2/setup-zabbix-disk-alerts.sh your-email@example.com
```

**建立的告警**:
- 🟡 80% 警告告警（2 個 5 分鐘週期）
- 🟠 90% 緊急告警（1 個 5 分鐘週期）
- 🔴 95% 嚴重告警（1 個 1 分鐘週期）

---

### 4. 磁碟狀況檢查（唯讀）
**檔案**: `check-zabbix-disk-status.py`

使用 AWS CloudWatch 指標檢查磁碟 I/O 活動（不需登入實例）。

```bash
python3 scripts/ec2/check-zabbix-disk-status.py
```

**限制**: 無法查看實際磁碟使用率（需要 CloudWatch Agent）

---

### 5. 完整處理指南
**檔案**: `ZABBIX_DISK_EMERGENCY_GUIDE.md`

詳細的 Step-by-step 指南，包含：
- 📋 診斷流程
- 💾 備份步驟
- 🧹 清理建議（3 個等級）
- 📊 磁碟擴充步驟
- 🔔 監控設定
- 🔄 長期預防措施

```bash
# 閱讀完整指南
cat scripts/ec2/ZABBIX_DISK_EMERGENCY_GUIDE.md
```

---

## 🎯 推薦處理流程

### 階段 1: 緊急處理（30 分鐘）

```bash
# 1. 備份
./scripts/ec2/quick-backup-zabbix.sh

# 2. SSH 登入診斷
ssh -i <key> ubuntu@<ip>
df -h

# 3. 快速安全清理
sudo apt-get clean
sudo journalctl --vacuum-time=7d
sudo find /var/log -type f -name "*.gz" -mtime +7 -delete

# 4. 確認效果
df -h
```

### 階段 2: 深入分析（1 小時）

```bash
# 在實例上執行完整診斷
bash /tmp/zabbix-disk-cleanup-guide.sh > /tmp/disk-analysis.txt 2>&1
cat /tmp/disk-analysis.txt

# 根據診斷結果決定：
# - 繼續清理
# - 或擴充磁碟
```

### 階段 3: 長期預防（持續）

```bash
# 1. 安裝 CloudWatch Agent（在實例上）
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb

# 2. 設定告警（在本機）
./scripts/ec2/setup-zabbix-disk-alerts.sh your-email@example.com

# 3. 設定自動清理（參考 ZABBIX_DISK_EMERGENCY_GUIDE.md）
```

---

## 📊 清理效果預估

| 清理項目 | 預期釋放空間 | 風險等級 |
|---------|-------------|---------|
| APT cache | 100-500 MB | 🟢 無風險 |
| 系統日誌 (7天前) | 500 MB - 2 GB | 🟢 低風險 |
| Journal logs | 200 MB - 1 GB | 🟢 低風險 |
| 暫存檔案 | 100-500 MB | 🟢 無風險 |
| 舊核心 | 500 MB - 2 GB | 🟡 中風險 |
| Zabbix 日誌 | 1-5 GB | 🟡 中風險 |
| Docker 資料 | 1-10 GB | 🟠 高風險 |
| Zabbix 資料庫 | 5-20 GB+ | 🔴 高風險 |

---

## ⚠️ 重要注意事項

### 執行清理前
1. ✅ **必須先備份**：執行 `quick-backup-zabbix.sh`
2. ✅ **確認 Zabbix 服務狀態**：避免清理期間中斷監控
3. ✅ **選擇低峰時段**：減少對生產環境的影響

### 清理規則
- 🟢 **無風險操作**：可直接執行
- 🟡 **中風險操作**：需確認不影響服務
- 🔴 **高風險操作**：需諮詢 DBA 或主管

### 磁碟擴充時機
- 使用率 > 85% 且清理效果有限
- 持續增長趨勢
- 清理後 1 週內又回到 80%

---

## 🔍 故障排除

### Q1: 備份腳本執行失敗
```bash
# 檢查 AWS credentials
aws --profile gemini-pro_ck sts get-caller-identity

# 檢查 volume ID 是否正確
aws --profile gemini-pro_ck ec2 describe-volumes --volume-ids vol-009d7af16c7120d50
```

### Q2: CloudWatch Agent 未安裝
```bash
# 在實例上檢查
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a query -m ec2 -c default

# 如果未安裝，參考 ZABBIX_DISK_EMERGENCY_GUIDE.md 的安裝步驟
```

### Q3: 告警設定失敗
```bash
# 檢查是否有 disk_used_percent metric
aws --profile gemini-pro_ck cloudwatch list-metrics \
  --namespace CWAgent \
  --dimensions Name=InstanceId,Value=i-040c741a76a42169b

# 如果沒有，需要先安裝和配置 CloudWatch Agent
```

### Q4: 清理後空間仍不足
1. 參考 `ZABBIX_DISK_EMERGENCY_GUIDE.md` 的磁碟擴充步驟
2. 考慮清理 Zabbix 資料庫（諮詢 DBA）
3. 優化 Zabbix Housekeeping 設定

---

## 📞 支援

如遇到問題，請聯絡：
- DevOps Team
- Zabbix 管理員
- DBA（資料庫相關問題）

---

## 📚 相關文件

- [完整處理指南](./ZABBIX_DISK_EMERGENCY_GUIDE.md)
- [AWS EBS Snapshot 文件](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSSnapshots.html)
- [CloudWatch Agent 文件](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
- [Zabbix Housekeeping](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/administration/general#housekeeper)

---

**最後更新**: 2025-11-15
**維護者**: DevOps Team

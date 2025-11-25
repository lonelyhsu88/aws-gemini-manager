# 🚨 Zabbix Server 磁碟空間緊急處理指南

## 📋 問題概述

- **實例**: gemini-monitor-01 (i-040c741a76a42169b)
- **問題**: `/` (root) 磁碟使用率 > 80%
- **系統碟**: /dev/xvda (60 GB gp3)
- **資料碟**: /dev/sdf (100 GB gp3)
- **風險等級**: 🔴 **HIGH** - 磁碟空間不足可能導致服務中斷

## 🎯 立即行動計畫

### Phase 1: 緊急診斷（5 分鐘）

#### 1. SSH 登入實例並執行診斷

```bash
# 登入 Zabbix Server
ssh -i <your-key.pem> ubuntu@<zabbix-server-ip>

# 快速診斷
df -h                          # 確認磁碟使用率
df -i                          # 確認 inode 使用率
du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20
```

或者使用自動診斷腳本：

```bash
# 從本機上傳腳本到實例
scp -i <your-key.pem> scripts/ec2/zabbix-disk-cleanup-guide.sh ubuntu@<zabbix-server-ip>:/tmp/

# 執行診斷
ssh -i <your-key.pem> ubuntu@<zabbix-server-ip> "bash /tmp/zabbix-disk-cleanup-guide.sh"
```

#### 2. 快速評估

根據診斷結果判斷：

| 使用率 | 嚴重程度 | 行動 |
|--------|----------|------|
| 80-85% | 🟡 中等 | 執行安全清理（日誌、快取） |
| 85-90% | 🟠 高 | 立即清理 + 規劃擴充 |
| 90-95% | 🔴 緊急 | 緊急清理 + 立即擴充 |
| >95% | 🔴🔴 嚴重 | 停止非關鍵服務 + 緊急擴充 |

---

### Phase 2: 備份（10 分鐘）

⚠️ **在執行任何清理或變更前，必須先備份！**

#### 建立 EBS Snapshot

```bash
# 使用 AWS CLI 建立 snapshot
export AWS_PROFILE=gemini-pro_ck

# 備份系統碟
aws ec2 create-snapshot \
  --volume-id vol-009d7af16c7120d50 \
  --description "gemini-monitor-01 system disk - emergency backup $(date +%Y%m%d-%H%M%S)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=zabbix-emergency-backup-system},{Key=Purpose,Value=disk-cleanup-backup},{Key=Date,Value='$(date +%Y%m%d)'}]'

# 備份資料碟
aws ec2 create-snapshot \
  --volume-id vol-04386deecccee2560 \
  --description "gemini-monitor-01 data disk - emergency backup $(date +%Y%m%d-%H%M%S)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=zabbix-emergency-backup-data},{Key=Purpose,Value=disk-cleanup-backup},{Key=Date,Value='$(date +%Y%m%d)'}]'

# 確認 snapshot 建立狀態
aws ec2 describe-snapshots \
  --filters "Name=volume-id,Values=vol-009d7af16c7120d50,vol-04386deecccee2560" \
  --query 'Snapshots[?StartTime>=`'$(date -u -v-1H +%Y-%m-%d)'`].[SnapshotId,VolumeId,State,Progress,StartTime]' \
  --output table
```

#### 快速備份指令（一鍵執行）

```bash
#!/bin/bash
export AWS_PROFILE=gemini-pro_ck
INSTANCE_ID="i-040c741a76a42169b"
DATE=$(date +%Y%m%d-%H%M%S)

echo "🔄 正在建立 EBS Snapshots..."

# 系統碟
SNAPSHOT_SYS=$(aws ec2 create-snapshot \
  --volume-id vol-009d7af16c7120d50 \
  --description "zabbix-emergency-backup-system-$DATE" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=zabbix-emergency-$DATE-system}]" \
  --query 'SnapshotId' --output text)

# 資料碟
SNAPSHOT_DATA=$(aws ec2 create-snapshot \
  --volume-id vol-04386deecccee2560 \
  --description "zabbix-emergency-backup-data-$DATE" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=zabbix-emergency-$DATE-data}]" \
  --query 'SnapshotId' --output text)

echo "✅ Snapshot 建立完成："
echo "   系統碟: $SNAPSHOT_SYS"
echo "   資料碟: $SNAPSHOT_DATA"
echo ""
echo "⏳ Snapshot 正在建立中（背景執行），可以繼續後續步驟"
```

---

### Phase 3: 安全清理（15 分鐘）

#### 🟢 Level 1: 安全清理（無風險）

```bash
# 登入實例執行

# 1. 清理 APT 快取
sudo apt-get clean
sudo apt-get autoclean
sudo apt-get autoremove -y

# 2. 清理系統日誌（保留 7 天）
sudo find /var/log -type f -name "*.log.*" -mtime +7 -delete
sudo find /var/log -type f -name "*.gz" -mtime +7 -delete

# 3. 限制 journal 日誌大小
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=500M

# 4. 清理暫存檔案
sudo find /tmp -type f -atime +7 -delete
sudo find /var/tmp -type f -atime +7 -delete

# 5. 再次檢查磁碟使用率
df -h
```

**預期釋放空間**: 500 MB - 2 GB

#### 🟡 Level 2: 進階清理（需確認）

```bash
# 1. 檢查並清理 Zabbix 日誌
sudo ls -lh /var/log/zabbix/
sudo find /var/log/zabbix -name "*.log.*" -mtime +14 -delete

# 2. 清理舊核心（保留當前和前一版本）
# 先查看當前核心
uname -r

# 列出所有已安裝的核心
dpkg --list | grep linux-image

# 移除舊核心（⚠️ 確認保留當前版本）
sudo apt-get autoremove --purge -y

# 3. 清理 Docker（如果有使用）
sudo docker system df
sudo docker system prune -a --volumes  # ⚠️ 確認無重要容器

# 4. 檢查大檔案
find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | head -20
```

**預期釋放空間**: 1 GB - 5 GB

#### 🔴 Level 3: Zabbix 資料清理（高風險）

⚠️ **請先諮詢 Zabbix 管理員或 DBA**

```bash
# 1. 檢查 Zabbix 資料庫大小（如果在本機）
sudo du -sh /var/lib/mysql/zabbix* 2>/dev/null
sudo du -sh /var/lib/pgsql/*/zabbix* 2>/dev/null

# 2. 調整 Zabbix Housekeeping 設定
# 登入 Zabbix Web UI:
# Administration -> General -> Housekeeping
# 建議設定：
#   - History: 7-14 days
#   - Trends: 90 days
#   - Enable housekeeping

# 3. 手動執行資料庫清理（⚠️ 高風險）
# 需要 DBA 協助，可能需要：
# - 刪除舊的 history 資料
# - 刪除舊的 trend 資料
# - 優化資料庫表格
# - VACUUM（PostgreSQL）或 OPTIMIZE（MySQL）
```

**預期釋放空間**: 5 GB - 20 GB+

---

### Phase 4: 擴充磁碟（30 分鐘）

如果清理後仍不足，或使用率持續增長，建議擴充 EBS volume。

#### 步驟 1: 擴充 EBS Volume（AWS Console 或 CLI）

**使用 AWS CLI**:

```bash
export AWS_PROFILE=gemini-pro_ck

# 擴充系統碟從 60 GB 到 100 GB
aws ec2 modify-volume \
  --volume-id vol-009d7af16c7120d50 \
  --size 100

# 檢查修改狀態
aws ec2 describe-volumes-modifications \
  --volume-ids vol-009d7af16c7120d50 \
  --query 'VolumesModifications[*].[VolumeId,ModificationState,Progress,TargetSize,OriginalSize]' \
  --output table
```

**使用 AWS Console**:
1. EC2 Console → Volumes
2. 選擇 vol-009d7af16c7120d50
3. Actions → Modify Volume
4. 修改 Size: 60 → 100 GB
5. Modify → Yes

#### 步驟 2: 擴充檔案系統（在實例內執行）

等待 volume 修改完成（optimizing 狀態），然後登入實例：

```bash
# SSH 登入實例

# 1. 檢查分區表
sudo lsblk

# 2. 擴充分區（如果使用 LVM）
sudo growpart /dev/xvda 1

# 3. 調整檔案系統大小
# 對於 ext4:
sudo resize2fs /dev/xvda1

# 對於 xfs:
sudo xfs_growfs -d /

# 4. 確認新大小
df -h
```

完整腳本：

```bash
#!/bin/bash
# 在實例內執行

echo "📊 目前磁碟狀態："
df -h
lsblk

echo ""
echo "🔧 開始擴充檔案系統..."

# 擴充分區
sudo growpart /dev/xvda 1

# 擴充檔案系統（根據檔案系統類型選擇）
FS_TYPE=$(df -T / | tail -1 | awk '{print $2}')

if [ "$FS_TYPE" = "ext4" ]; then
    echo "檔案系統: ext4"
    sudo resize2fs /dev/xvda1
elif [ "$FS_TYPE" = "xfs" ]; then
    echo "檔案系統: xfs"
    sudo xfs_growfs -d /
else
    echo "⚠️  未知的檔案系統類型: $FS_TYPE"
fi

echo ""
echo "✅ 擴充完成，新的磁碟狀態："
df -h
```

---

## 📊 設定監控告警（防止再次發生）

### 方案 1: CloudWatch Agent（推薦）

#### 安裝 CloudWatch Agent

```bash
# 在實例上執行

# 1. 下載並安裝 CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb

# 2. 建立配置檔案
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/config.json > /dev/null <<EOF
{
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "disk_used_percent",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 300,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "mem_used_percent",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 300
      }
    }
  }
}
EOF

# 3. 啟動 CloudWatch Agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# 4. 確認運行狀態
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query \
  -m ec2 \
  -c default
```

#### 建立 CloudWatch 告警

```bash
export AWS_PROFILE=gemini-pro_ck

# 建立 SNS Topic（如果尚未建立）
SNS_ARN=$(aws sns create-topic \
  --name zabbix-disk-alert \
  --query 'TopicArn' \
  --output text)

# 訂閱 Email 通知
aws sns subscribe \
  --topic-arn $SNS_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com

# 建立磁碟使用率告警（80% 閾值）
aws cloudwatch put-metric-alarm \
  --alarm-name "zabbix-server-disk-usage-80-percent" \
  --alarm-description "Alert when Zabbix server disk usage > 80%" \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-040c741a76a42169b Name=path,Value=/ Name=device,Value=xvda1 Name=fstype,Value=ext4 \
  --alarm-actions $SNS_ARN

# 建立 90% 緊急告警
aws cloudwatch put-metric-alarm \
  --alarm-name "zabbix-server-disk-usage-90-percent-critical" \
  --alarm-description "CRITICAL: Zabbix server disk usage > 90%" \
  --metric-name disk_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 90 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-040c741a76a42169b Name=path,Value=/ Name=device,Value=xvda1 Name=fstype,Value=ext4 \
  --alarm-actions $SNS_ARN
```

### 方案 2: Zabbix 自我監控

在 Zabbix 中新增監控項目：

```bash
# 在 Zabbix Server 上新增監控
# Configuration -> Hosts -> Zabbix server -> Items -> Create item

# Item 設定：
# - Name: Disk space usage on /
# - Type: Zabbix agent
# - Key: vfs.fs.size[/,pused]
# - Type of information: Numeric (float)
# - Units: %
# - Update interval: 5m

# Trigger 設定：
# Configuration -> Hosts -> Zabbix server -> Triggers -> Create trigger

# Trigger 設定（警告）：
# - Name: Disk space is low on / (used > 80%)
# - Severity: Warning
# - Expression: {Zabbix server:vfs.fs.size[/,pused].last()}>80

# Trigger 設定（嚴重）：
# - Name: Disk space is critically low on / (used > 90%)
# - Severity: High
# - Expression: {Zabbix server:vfs.fs.size[/,pused].last()}>90
```

---

## 🔄 長期預防措施

### 1. 建立日誌輪替政策

```bash
# /etc/logrotate.d/zabbix-server
/var/log/zabbix/zabbix_server.log {
    daily
    rotate 7
    maxsize 100M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 zabbix zabbix
    postrotate
        /usr/bin/killall -HUP zabbix_server 2>/dev/null || true
    endscript
}
```

### 2. 設定自動清理 Cron Job

```bash
# 建立清理腳本
sudo tee /usr/local/bin/zabbix-disk-cleanup.sh > /dev/null <<'EOF'
#!/bin/bash
# Zabbix Server 自動清理腳本

LOG_FILE="/var/log/zabbix-disk-cleanup.log"

echo "=== Disk Cleanup Started: $(date) ===" >> $LOG_FILE

# 清理 APT cache
apt-get clean >> $LOG_FILE 2>&1

# 清理舊日誌
find /var/log -type f -name "*.log.*" -mtime +7 -delete >> $LOG_FILE 2>&1
find /var/log -type f -name "*.gz" -mtime +7 -delete >> $LOG_FILE 2>&1

# 限制 journal 大小
journalctl --vacuum-time=7d >> $LOG_FILE 2>&1

# 清理暫存檔案
find /tmp -type f -atime +7 -delete >> $LOG_FILE 2>&1

# 記錄清理後的磁碟使用率
df -h >> $LOG_FILE 2>&1

echo "=== Disk Cleanup Finished: $(date) ===" >> $LOG_FILE
echo "" >> $LOG_FILE
EOF

# 設定權限
sudo chmod +x /usr/local/bin/zabbix-disk-cleanup.sh

# 新增到 crontab（每週日凌晨 2 點執行）
sudo crontab -e
# 加入以下行：
# 0 2 * * 0 /usr/local/bin/zabbix-disk-cleanup.sh
```

### 3. 優化 Zabbix Housekeeping

登入 Zabbix Web UI：
- **Administration** → **General** → **Housekeeping**

建議設定：
- ✅ Enable internal housekeeping
- History and trends:
  - **Override item history period**: 14 days
  - **Override item trend period**: 90 days
- Events and alerts:
  - **Events and alerts (trigger-based)**: 90 days
  - **Internal events**: 7 days
- Services:
  - **User sessions**: 7 days

### 4. 考慮使用外部資料庫（如 RDS）

如果 Zabbix 資料庫持續成長，考慮：
- 將 Zabbix 資料庫遷移到 RDS PostgreSQL/MySQL
- 使用 TimescaleDB 優化時序資料儲存
- 實施資料分區（Partitioning）策略

---

## 📞 緊急聯絡清單

- **AWS Support**: [AWS Console Support Center]
- **Zabbix 管理員**: [填入聯絡資訊]
- **DBA**: [填入聯絡資訊]
- **On-call DevOps**: [填入聯絡資訊]

---

## 📚 參考資料

- [AWS EBS Volume Modification](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/requesting-ebs-volume-modifications.html)
- [CloudWatch Agent Installation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html)
- [Zabbix Housekeeping](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/administration/general#housekeeper)
- [Linux Disk Space Management](https://www.cyberciti.biz/faq/linux-find-large-files-in-directory-recursively-using-find-du/)

---

## ✅ 檢查清單

### 緊急處理
- [ ] 確認當前磁碟使用率和嚴重程度
- [ ] 建立 EBS Snapshot 備份
- [ ] 執行 Level 1 安全清理
- [ ] 檢查清理後的磁碟使用率
- [ ] 如需要，執行 Level 2 進階清理
- [ ] 如仍不足，規劃磁碟擴充

### 磁碟擴充（如需要）
- [ ] 使用 AWS CLI/Console 修改 EBS Volume 大小
- [ ] 等待 Volume 修改完成（optimizing）
- [ ] SSH 登入實例擴充檔案系統
- [ ] 確認新的磁碟大小

### 監控設定
- [ ] 安裝 CloudWatch Agent
- [ ] 建立 SNS Topic 和訂閱
- [ ] 設定 80% 警告告警
- [ ] 設定 90% 緊急告警
- [ ] 測試告警是否正常運作

### 長期預防
- [ ] 設定日誌輪替政策
- [ ] 建立自動清理 Cron Job
- [ ] 優化 Zabbix Housekeeping 設定
- [ ] 文件化處理流程
- [ ] 規劃容量增長趨勢

---

**最後更新**: 2025-11-15
**維護者**: DevOps Team

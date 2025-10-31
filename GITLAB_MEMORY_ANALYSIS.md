# GitLab Memory Low 問題分析報告

生成時間: 2025-10-31
實例: Gemini-Gitlab (i-00b89a08e62a762a9)
AWS Profile: gemini-pro_ck

---

## 🔍 問題概述

GitLab 實例出現 memory low（記憶體不足）的情況。

## 📊 當前配置

### EC2 實例資訊
- **實例 ID**: i-00b89a08e62a762a9
- **實例類型**: c5a.xlarge
- **vCPUs**: 4
- **記憶體**: 8 GB RAM
- **啟動時間**: 2023-11-12（運行超過2年）
- **私有 IP**: 172.31.5.23
- **公有 IP**: 16.162.37.5

### 監控狀態
- ❌ CloudWatch 詳細監控: **DISABLED**
- ❌ CloudWatch Agent: **未安裝**
- ⚠️ **無法獲取記憶體使用指標**

## 📈 資源使用分析（最近 24 小時）

### CPU 使用率
- **平均使用率**: 3.31%
- **峰值**: 74.15%
- **最近 6 小時平均**: 4.58%
- **結論**: CPU 不是瓶頸

### 網路流量
- **入站**: 18.62 GB (0.01 Mbps 平均)
- **出站**: 2351.88 GB (0.74 Mbps 平均)
- **結論**: 網路流量正常

### 磁碟 I/O
- **讀取操作**: 69,481,260 次
- **寫入操作**: 28,842,900 次
- **讀取數據**: 7074.71 GB
- **寫入數據**: 4571.87 GB
- **平均讀取 IOPS**: 804.18
- **平均寫入 IOPS**: 333.83
- **結論**: ⚠️ 磁碟 I/O 非常高，可能是記憶體不足導致頻繁 swap

## 🎯 為什麼 Memory Low？

### 根本原因分析

#### 1. **GitLab 本身記憶體需求高**
GitLab 是一個記憶體密集型應用，包含多個服務：
- **Puma (Web Server)**: 每個 worker 約 500MB-1GB
- **Sidekiq (Background Jobs)**: 約 1-2GB
- **PostgreSQL**: 約 1-2GB
- **Redis**: 約 500MB-1GB
- **Gitaly (Git RPC)**: 約 500MB-1GB
- **GitLab Workhorse**: 約 100-200MB
- **Prometheus (Monitoring)**: 約 500MB-1GB
- **其他服務**: 約 500MB

**預估總需求**: 至少 **12-16 GB**

#### 2. **8GB RAM 對 GitLab 來說嚴重不足**
- GitLab 官方建議最低 **4GB** for up to 500 users
- 生產環境建議 **8GB** for up to 1000 users
- 但這是「最低」需求，實際運行需要更多

#### 3. **長時間運行導致記憶體碎片化**
- 實例運行超過 2 年未重啟
- 記憶體洩漏累積
- 快取持續增長

#### 4. **高磁碟 I/O 是記憶體不足的徵兆**
- 24 小時讀取 7TB 數據極不正常
- 可能是系統頻繁使用 swap
- 或是 GitLab 的快取機制失效

#### 5. ⚠️ **累積的「垃圾」數據佔用記憶體**
GitLab 長期運行會累積大量數據，間接消耗記憶體：
- **CI/CD Artifacts**: 可能數十 GB，處理時需要記憶體
- **Redis 快取**: 直接佔用記憶體（可能 1-2 GB）
- **Git 倉庫**: 大量鬆散對象需要更多 inode cache
- **PostgreSQL 數據庫**: 查詢快取和 shared_buffers 佔用記憶體
- **Container Registry**: 大量 Docker layers 消耗記憶體
- **日誌文件**: 大量日誌影響系統 page cache

💡 **重要發現**: 清理這些垃圾可以**間接釋放 1-3 GB 記憶體**！

詳見: [GITLAB_GARBAGE_CLEANUP_GUIDE.md](./GITLAB_GARBAGE_CLEANUP_GUIDE.md)

## 💡 解決方案

### 🚨 立即行動（緊急處理）

#### 選項 1: 快速清理垃圾 + 重啟（推薦！✨）
```bash
# SSH 到實例
ssh ec2-user@16.162.37.5

# 清理 Redis（立即釋放 1-2 GB 記憶體！）
sudo gitlab-redis-cli FLUSHALL

# 清理孤立的 artifacts
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false

# 清理孤立的 LFS 文件
sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# 重啟 GitLab（釋放記憶體碎片）
sudo gitlab-ctl restart

# 檢查效果
free -h
df -h
```

**預期效果**:
- 💾 釋放 1-3 GB 記憶體
- 📦 釋放 5-20 GB 磁碟空間
- ⏱️ 總耗時約 5-10 分鐘

#### 選項 2: 僅重啟 GitLab 服務（最快但效果有限）
```bash
# SSH 到實例
ssh ec2-user@16.162.37.5

# 重啟 GitLab（釋放記憶體）
sudo gitlab-ctl restart

# 檢查記憶體使用
free -h
top -o %MEM
```

#### 選項 3: 重啟 EC2 實例（停機時間較長）
```bash
# 使用 AWS CLI
aws --profile gemini-pro_ck ec2 reboot-instances --instance-ids i-00b89a08e62a762a9

# 或者從控制台重啟
```

### 📊 短期改善（1-2 天內）

#### 0. 完整垃圾清理（強烈推薦！🎯）

**使用自動化清理腳本**（最簡單）:
```bash
# SSH 到實例
ssh ec2-user@16.162.37.5

# 複製清理腳本到實例
# (從本地機器執行)
scp scripts/ec2/cleanup-gitlab.sh ec2-user@16.162.37.5:~

# SSH 到實例後執行
sudo bash cleanup-gitlab.sh
```

這個腳本會自動執行：
- ✅ 清理孤立的 Job Artifacts
- ✅ 清理孤立的 LFS 文件
- ✅ 清理項目導出文件
- ✅ 清理 Redis 快取
- ✅ 輪轉日誌
- ✅ 清理舊備份（保留最近 3 個）
- ✅ 重啟 GitLab

**完整垃圾清理指南**: 參見 [GITLAB_GARBAGE_CLEANUP_GUIDE.md](./GITLAB_GARBAGE_CLEANUP_GUIDE.md)

**診斷工具**:
```bash
# 檢查磁碟使用情況
bash scripts/ec2/check-gitlab-disk-usage.sh
```

#### 1. 安裝 CloudWatch Agent（監控記憶體）
```bash
# SSH 到實例
ssh -i your-key.pem ec2-user@16.162.37.5

# 安裝 CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# 配置 Agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard

# 啟動 Agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
```

#### 2. 優化 GitLab 配置
```bash
# 編輯 GitLab 配置
sudo vim /etc/gitlab/gitlab.rb

# 減少 Puma workers
puma['worker_processes'] = 2  # 從預設 4 減少到 2

# 減少 Sidekiq concurrency
sidekiq['concurrency'] = 10  # 從預設 25 減少到 10

# 優化 PostgreSQL
postgresql['shared_buffers'] = "256MB"  # 減少共享緩衝區
postgresql['work_mem'] = "16MB"

# 禁用不使用的功能
prometheus_monitoring['enable'] = false  # 如果不需要內建監控
gitlab_kas['enable'] = false  # 如果不使用 Kubernetes Agent

# 套用配置
sudo gitlab-ctl reconfigure
```

#### 3. 檢查並清理
```bash
# 清理舊的容器和映像（如果使用 Container Registry）
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files
sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# 清理 Redis
sudo gitlab-redis-cli FLUSHALL

# 檢查磁碟空間
df -h
```

### 🎯 中期解決方案（1 週內）

#### 升級實例類型
**從 c5a.xlarge (8GB) 升級到 c5a.2xlarge (16GB)**

```bash
# 1. 停止實例
aws --profile gemini-pro_ck ec2 stop-instances --instance-ids i-00b89a08e62a762a9

# 2. 等待停止完成
aws --profile gemini-pro_ck ec2 wait instance-stopped --instance-ids i-00b89a08e62a762a9

# 3. 修改實例類型
aws --profile gemini-pro_ck ec2 modify-instance-attribute \
  --instance-id i-00b89a08e62a762a9 \
  --instance-type c5a.2xlarge

# 4. 啟動實例
aws --profile gemini-pro_ck ec2 start-instances --instance-ids i-00b89a08e62a762a9

# 5. 等待啟動完成
aws --profile gemini-pro_ck ec2 wait instance-running --instance-ids i-00b89a08e62a762a9
```

**成本影響**:
- c5a.xlarge: $0.154/hour ≈ $110/month
- c5a.2xlarge: $0.308/hour ≈ $220/month
- **增加**: $110/month

#### 替代方案: 使用 r5 系列（記憶體優化）
**r5.xlarge (4 vCPU, 32GB RAM)**
- 成本: $0.252/hour ≈ $180/month
- 記憶體增加 4 倍
- 適合記憶體密集型應用

### 🔧 長期優化（持續改善）

#### 1. 設定 CloudWatch 警報
```bash
# 創建記憶體使用率警報（需要先安裝 CloudWatch Agent）
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name gitlab-high-memory \
  --alarm-description "Alert when memory usage exceeds 80%" \
  --metric-name mem_used_percent \
  --namespace CWAgent \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=i-00b89a08e62a762a9
```

#### 2. 實施定期維護
```bash
# 創建 crontab 定期清理
# 每週日凌晨 3 點清理
0 3 * * 0 /usr/bin/gitlab-rake gitlab:cleanup:orphan_job_artifact_files
0 4 * * 0 /usr/bin/gitlab-rake gitlab:cleanup:orphan_lfs_file_references
```

#### 3. 考慮架構優化
- **拆分服務**: 將 PostgreSQL、Redis 遷移到 RDS 和 ElastiCache
- **使用外部對象存儲**: 將 Git 數據、Artifacts 存到 S3
- **實施 GitLab Runner**: 將 CI/CD 工作負載分離到專用 Runner

## 📋 執行檢查清單

### ✅ 立即行動（今天）✨ 優先執行
- [ ] **檢查磁碟使用**: 運行 `scripts/ec2/check-gitlab-disk-usage.sh`
- [ ] **執行快速清理**: 清理 Redis + Artifacts + 重啟 GitLab
  - `sudo gitlab-redis-cli FLUSHALL`
  - `sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false`
  - `sudo gitlab-ctl restart`
- [ ] **驗證改善**: `free -h` 和 `df -h` 檢查記憶體和磁碟
- [ ] SSH 登入檢查實際記憶體使用: `free -h` 和 `top`
- [ ] 檢查系統日誌: `sudo dmesg | grep -i "out of memory"`
- [ ] 檢查 GitLab 日誌: `sudo gitlab-ctl tail`

### ✅ 短期行動（本週）
- [ ] **完整垃圾清理**: 運行 `scripts/ec2/cleanup-gitlab.sh`
- [ ] 安裝 CloudWatch Agent（使用 `scripts/ec2/install-cloudwatch-agent.sh`）
- [ ] 優化 GitLab 配置（減少 workers）
- [ ] 設定 CloudWatch 警報
- [ ] 配置自動清理 cron job

### ✅ 中期行動（下週）
- [ ] 評估升級實例的必要性
- [ ] 如需升級，規劃維護視窗
- [ ] 執行實例升級
- [ ] 驗證升級後性能

### ✅ 長期行動（持續）
- [ ] 監控記憶體使用趨勢
- [ ] 定期清理和維護
- [ ] 考慮架構優化方案

## 🔗 相關資源

### 本專案文檔
- 📄 [GitLab 垃圾清理完整指南](./GITLAB_GARBAGE_CLEANUP_GUIDE.md) - **必讀！**
- 🐍 [資源分析腳本](./scripts/ec2/analyze-gitlab-resources.py)
- 🧹 [垃圾清理腳本](./scripts/ec2/cleanup-gitlab.sh)
- 🔍 [磁碟使用檢查腳本](./scripts/ec2/check-gitlab-disk-usage.sh)
- 📊 [健康檢查腳本](./scripts/ec2/check-gitlab-health.sh)
- ⬆️ [實例升級腳本](./scripts/ec2/upgrade-gitlab-instance.sh)
- 📈 [CloudWatch Agent 安裝腳本](./scripts/ec2/install-cloudwatch-agent.sh)

### GitLab 官方文檔
- [Hardware requirements](https://docs.gitlab.com/ee/install/requirements.html)
- [Performance tuning](https://docs.gitlab.com/ee/administration/operations/gitlab_performance.html)
- [Memory use](https://docs.gitlab.com/ee/administration/operations/puma.html#reducing-memory-use)
- [GitLab Rake cleanup tasks](https://docs.gitlab.com/ee/raketasks/cleanup.html)

### AWS 文檔
- [CloudWatch Agent installation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html)
- [Changing instance type](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-resize.html)

## 📞 後續支援

如果問題持續存在，建議：
1. 檢查 GitLab 版本並考慮升級到最新版本
2. 分析使用模式（用戶數、倉庫數、CI/CD 使用情況）
3. 考慮聯繫 GitLab 支援團隊（如有企業版）

---

**報告生成**: 使用 `scripts/ec2/analyze-gitlab-resources.py`
**AWS Profile**: gemini-pro_ck

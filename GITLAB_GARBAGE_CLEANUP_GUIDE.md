# GitLab 垃圾清理完整指南

生成時間: 2025-10-31
實例: Gemini-Gitlab (i-00b89a08e62a762a9)

---

## 🎯 為什麼 GitLab 會累積垃圾？

GitLab 是一個全功能的 DevOps 平台，會在運行過程中累積大量數據：

### 常見的「垃圾」來源

#### 1. **CI/CD Artifacts** ⚠️ 高風險
- **位置**: `/var/opt/gitlab/gitlab-rails/shared/artifacts`
- **累積原因**: 每次 CI/CD 運行都會生成 artifacts（編譯產物、測試報告等）
- **問題**: 預設可能永久保留，快速累積數 GB 到 TB
- **記憶體影響**: 大量小文件會消耗 inode 和緩衝區記憶體

#### 2. **Git 倉庫 (Repositories)**
- **位置**: `/var/opt/gitlab/git-data/repositories`
- **累積原因**:
  - 未打包的鬆散對象 (loose objects)
  - 歷史記錄中的大文件
  - 被刪除但仍在歷史中的文件
  - Fork 和 merged 分支
- **問題**: 倉庫大小持續增長，Git 操作變慢
- **記憶體影響**: Git 操作需要載入對象到記憶體

#### 3. **Container Registry Images** ⚠️ 高風險
- **位置**: `/var/opt/gitlab/gitlab-rails/shared/registry`
- **累積原因**: Docker images 的每個 tag 和 layer 都會佔用空間
- **問題**: 可以快速增長到數百 GB
- **記憶體影響**: Registry 服務需要記憶體來處理請求

#### 4. **Git LFS Objects** (Large File Storage)
- **位置**: `/var/opt/gitlab/gitlab-rails/shared/lfs-objects`
- **累積原因**: 二進制大文件、圖片、影片等
- **問題**: 即使項目刪除，LFS 對象可能仍存在（orphaned）

#### 5. **Database (PostgreSQL)** ⚠️ 記憶體殺手
- **位置**: `/var/opt/gitlab/postgresql`
- **累積原因**:
  - 事件日誌 (events)
  - 審計日誌 (audit logs)
  - 已刪除記錄未回收
  - 數據庫碎片化
- **問題**: 查詢變慢，需要更多記憶體
- **記憶體影響**: PostgreSQL 會快取數據，佔用大量 shared_buffers

#### 6. **Redis Cache**
- **位置**: `/var/opt/gitlab/redis`
- **累積原因**:
  - Session 數據
  - Cache 數據
  - Background job queues
- **記憶體影響**: ⚠️ **直接佔用記憶體！Redis 是內存資料庫**

#### 7. **Logs** 📝
- **位置**: `/var/log/gitlab`
- **累積原因**: 各種服務的日誌文件持續增長
- **問題**: 可能累積數 GB 的日誌

#### 8. **Uploads & Attachments**
- **位置**: `/var/opt/gitlab/gitlab-rails/uploads`
- **累積原因**: Issue、MR 的附件，Wiki 圖片等
- **問題**: 大量上傳文件從未清理

#### 9. **Backups**
- **位置**: `/var/opt/gitlab/backups`
- **累積原因**: 定期備份但未設定保留策略
- **問題**: 每個備份可能數 GB

#### 10. **Temporary Files**
- **位置**: `/var/opt/gitlab/gitlab-rails/tmp`
- **累積原因**: 臨時操作產生的文件未清理

---

## 🔍 診斷：檢查垃圾狀況

### 快速檢查腳本

```bash
# SSH 到 GitLab 實例
ssh ec2-user@16.162.37.5

# 下載並運行檢查腳本
# (或直接複製 scripts/ec2/check-gitlab-disk-usage.sh 的內容)
sudo bash check-gitlab-disk-usage.sh
```

### 手動檢查關鍵指標

```bash
# 1. 總磁碟使用
df -h

# 2. GitLab 各目錄大小
sudo du -sh /var/opt/gitlab/*

# 3. 最大的目錄
sudo du -h /var/opt/gitlab | sort -rh | head -n 20

# 4. Artifacts 大小
sudo du -sh /var/opt/gitlab/gitlab-rails/shared/artifacts

# 5. 倉庫大小
sudo du -sh /var/opt/gitlab/git-data/repositories

# 6. Redis 記憶體使用
sudo gitlab-redis-cli INFO memory

# 7. PostgreSQL 數據庫大小
sudo gitlab-psql -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;"
```

---

## 🧹 清理方案

### 🟢 Level 1: 安全快速清理（隨時可執行）

**預計釋放空間**: 5-20 GB
**執行時間**: 5-15 分鐘
**停機時間**: 無（最後重啟 GitLab 約 2-3 分鐘）

#### 使用自動化腳本

```bash
# 下載清理腳本到 GitLab 實例
scp scripts/ec2/cleanup-gitlab.sh ec2-user@16.162.37.5:~

# SSH 到實例
ssh ec2-user@16.162.37.5

# 先測試運行（不會改變任何東西）
sudo bash cleanup-gitlab.sh --dry-run

# 確認後執行
sudo bash cleanup-gitlab.sh
```

#### 手動執行清理

```bash
# 1. 清理孤立的 Job Artifacts（GitLab 已標記為過期但未刪除的）
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false

# 2. 清理孤立的 LFS 文件
sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# 3. 清理項目導出文件
sudo gitlab-rake gitlab:cleanup:project_exports

# 4. 清理 Redis 快取（立即釋放記憶體！）
sudo gitlab-redis-cli FLUSHALL

# 5. 輪轉日誌
sudo logrotate -f /etc/logrotate.d/gitlab

# 6. 清理系統包管理器快取
sudo yum clean all  # Amazon Linux
# 或
sudo apt-get clean  # Ubuntu

# 7. 刪除舊備份（保留最近 3 個）
cd /var/opt/gitlab/backups
ls -t | tail -n +4 | xargs -I {} sudo rm -f {}

# 8. 重啟 GitLab（釋放記憶體）
sudo gitlab-ctl restart
```

**立即效果**:
- ✅ 釋放磁碟空間
- ✅ 釋放 Redis 記憶體（可能釋放 1-2 GB）
- ✅ 重啟後釋放記憶體碎片

---

### 🟡 Level 2: 需維護窗口清理

**預計釋放空間**: 20-100+ GB
**執行時間**: 30 分鐘 - 數小時（取決於倉庫大小）
**停機時間**: 建議排程維護窗口

#### 2.1 Git 倉庫清理（最耗時但效果最好）

```bash
# Git 垃圾回收（所有倉庫）
# 警告：可能需要數小時！
sudo gitlab-rake gitlab:git:gc

# 或者針對特定倉庫（更快）
# 先找出最大的倉庫
sudo du -sh /var/opt/gitlab/git-data/repositories/*/*.git | sort -rh | head -n 10

# 對單個倉庫進行 GC
sudo -u git -H git --git-dir=/var/opt/gitlab/git-data/repositories/<namespace>/<project>.git gc --aggressive

# 重新打包倉庫（優化空間）
sudo gitlab-rake gitlab:git:repack

# 清理未引用的對象
sudo gitlab-rake gitlab:git:prune
```

#### 2.2 數據庫清理

```bash
# PostgreSQL VACUUM（回收空間）
sudo gitlab-rake gitlab:db:vacuum

# 重建索引（可選，改善性能）
sudo gitlab-rake gitlab:db:reindex

# 清理舊的事件日誌（超過 90 天）
# 在 GitLab Rails console 中執行
sudo gitlab-rails console

# 在 console 中：
Event.where('created_at < ?', 90.days.ago).in_batches.delete_all
AuditEvent.where('created_at < ?', 90.days.ago).in_batches.delete_all
exit
```

#### 2.3 Container Registry 清理

```bash
# 啟用 Registry 垃圾回收
sudo gitlab-ctl registry-garbage-collect

# 或手動刪除未使用的 tags（通過 UI 或 API）
```

---

### 🔴 Level 3: 預防性配置（長期解決方案）

這些配置需要修改 `/etc/gitlab/gitlab.rb` 並重新配置。

#### 3.1 設定 Artifacts 自動過期

```ruby
# 編輯配置
sudo vim /etc/gitlab/gitlab.rb

# 添加或修改以下設定：

# 設定預設 artifact 保留時間為 30 天
gitlab_rails['artifacts_expire_at'] = '30 days'

# 限制 artifact 最大大小（100 MB）
gitlab_rails['max_artifacts_size'] = 100

# 套用配置
sudo gitlab-ctl reconfigure
```

#### 3.2 配置自動清理任務

```ruby
# 在 /etc/gitlab/gitlab.rb 中添加

# 啟用 PostgreSQL 自動 vacuum
postgresql['autovacuum'] = 'on'

# 設定日誌保留
logging['logrotate_frequency'] = "daily"
logging['logrotate_maxsize'] = "100M"
logging['logrotate_rotate'] = 7  # 保留 7 天
```

#### 3.3 限制 Redis 記憶體

```ruby
# 設定 Redis 最大記憶體（建議 1-2GB）
redis['maxmemory'] = '1gb'
redis['maxmemory_policy'] = 'allkeys-lru'  # 使用 LRU 淘汰策略

# 套用配置
sudo gitlab-ctl reconfigure
```

#### 3.4 優化 PostgreSQL

```ruby
# 減少 shared_buffers（釋放記憶體）
postgresql['shared_buffers'] = "256MB"  # 從預設值降低

# 減少 work_mem
postgresql['work_mem'] = "16MB"

# 套用配置
sudo gitlab-ctl reconfigure
```

#### 3.5 設定定期清理 Cron Job

```bash
# 創建清理腳本
sudo tee /usr/local/bin/gitlab-auto-cleanup.sh > /dev/null <<'EOF'
#!/bin/bash
# GitLab 自動清理腳本

# 清理孤立文件
/opt/gitlab/bin/gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false
/opt/gitlab/bin/gitlab-rake gitlab:cleanup:orphan_lfs_file_references
/opt/gitlab/bin/gitlab-rake gitlab:cleanup:project_exports

# 輪轉日誌
/usr/sbin/logrotate -f /etc/logrotate.d/gitlab

# 記錄執行時間
echo "GitLab cleanup completed at $(date)" >> /var/log/gitlab-cleanup.log
EOF

# 設定權限
sudo chmod +x /usr/local/bin/gitlab-auto-cleanup.sh

# 添加到 crontab（每週日凌晨 3 點執行）
sudo crontab -e
# 添加：
0 3 * * 0 /usr/local/bin/gitlab-auto-cleanup.sh
```

---

## 📊 預期效果

### 清理前後對比（假設情境）

| 項目 | 清理前 | 清理後 | 節省 |
|-----|-------|-------|------|
| Artifacts | 50 GB | 5 GB | 45 GB |
| Git 倉庫 | 100 GB | 70 GB | 30 GB |
| Container Registry | 80 GB | 30 GB | 50 GB |
| Logs | 10 GB | 2 GB | 8 GB |
| Backups | 30 GB | 10 GB | 20 GB |
| Database | 15 GB | 12 GB | 3 GB |
| **總計** | **285 GB** | **129 GB** | **156 GB** |

### 記憶體改善

清理可以間接改善記憶體使用：

- ✅ **Redis**: FLUSHALL 立即釋放快取記憶體（可能 1-2 GB）
- ✅ **PostgreSQL**: VACUUM 後查詢更快，需要更少 buffers
- ✅ **File cache**: 更少的文件 = 更少的 inode cache
- ✅ **重啟後**: 釋放記憶體碎片和洩漏

**預計記憶體釋放**: 1-3 GB

---

## ⚠️ 重要注意事項

### 在清理前

1. **創建備份**
   ```bash
   sudo gitlab-backup create
   ```

2. **測試運行**（如果可用）
   ```bash
   # 許多 rake 任務支援 DRY_RUN
   sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=true
   ```

3. **通知用戶**（如果需要維護窗口）

### 清理時

1. **監控進度**
   ```bash
   # 另開一個 SSH session 監控
   watch -n 5 df -h
   sudo gitlab-ctl tail
   ```

2. **檢查服務狀態**
   ```bash
   sudo gitlab-ctl status
   ```

### 清理後

1. **驗證 GitLab 正常**
   - 訪問 Web UI
   - 測試 git clone
   - 檢查 CI/CD 是否正常

2. **監控記憶體和磁碟**
   ```bash
   free -h
   df -h
   ```

---

## 🎯 推薦執行順序

### 今天立即執行

```bash
# 1. 檢查當前狀況
sudo bash check-gitlab-disk-usage.sh

# 2. 執行快速清理
sudo bash cleanup-gitlab.sh

# 3. 檢查效果
df -h
free -h
```

### 本週安排（需維護窗口）

```bash
# 週末或低峰時段執行
# 1. Git 倉庫 GC
sudo gitlab-rake gitlab:git:gc

# 2. 數據庫清理
sudo gitlab-rake gitlab:db:vacuum

# 3. Registry 清理
sudo gitlab-ctl registry-garbage-collect
```

### 永久配置

```bash
# 1. 修改 /etc/gitlab/gitlab.rb
# 2. 設定 artifacts 過期
# 3. 限制 Redis 記憶體
# 4. 優化 PostgreSQL
# 5. 設定自動清理 cron job
```

---

## 📚 相關文檔

- [GitLab Rake tasks - Cleanup](https://docs.gitlab.com/ee/raketasks/cleanup.html)
- [GitLab Repository storage](https://docs.gitlab.com/ee/administration/repository_storage_types.html)
- [GitLab CI/CD job artifacts](https://docs.gitlab.com/ee/ci/jobs/job_artifacts.html)
- [Container Registry garbage collection](https://docs.gitlab.com/ee/administration/packages/container_registry.html#container-registry-garbage-collection)

---

## 🆘 故障排除

### Q: 清理後空間沒有釋放？

A: 某些清理需要重啟服務或系統才能真正釋放空間。

```bash
sudo gitlab-ctl restart
# 或
sudo reboot
```

### Q: Git GC 執行太久怎麼辦？

A: 可以針對最大的倉庫單獨處理，其他倉庫之後再處理。

### Q: 清理後 GitLab 出錯？

A: 從備份恢復：

```bash
sudo gitlab-backup restore BACKUP=<timestamp>
```

---

**腳本位置**:
- 檢查腳本: `scripts/ec2/check-gitlab-disk-usage.sh`
- 清理腳本: `scripts/ec2/cleanup-gitlab.sh`

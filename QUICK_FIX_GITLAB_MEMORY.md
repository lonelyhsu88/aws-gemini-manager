# GitLab Memory Low - 快速修復指南 ⚡

**問題**: GitLab 記憶體不足
**實例**: Gemini-Gitlab (i-00b89a08e62a762a9)
**目標**: 立即釋放 1-3 GB 記憶體

---

## 🚨 立即執行（5 分鐘內完成）

### 選項 A: 一鍵清理腳本（推薦）✨

```bash
# 1. SSH 到 GitLab 實例
ssh ec2-user@16.162.37.5

# 2. 複製並執行以下命令（一次性）
sudo bash << 'EOF'
echo "🧹 開始清理..."

# 清理 Redis（立即釋放 1-2 GB 記憶體）
echo "1/4 清理 Redis..."
gitlab-redis-cli FLUSHALL

# 清理孤立的 artifacts
echo "2/4 清理 artifacts..."
gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false

# 清理孤立的 LFS 文件
echo "3/4 清理 LFS..."
gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# 重啟 GitLab（釋放記憶體碎片）
echo "4/4 重啟 GitLab..."
gitlab-ctl restart

echo "✅ 清理完成！"
echo ""
echo "檢查效果："
free -h
df -h
EOF
```

**預期效果**:
- ✅ 釋放 1-3 GB 記憶體
- ✅ 釋放 5-20 GB 磁碟空間
- ⏱️ 總耗時約 5 分鐘
- 🔄 停機時間約 2-3 分鐘（重啟時）

---

### 選項 B: 手動執行（更可控）

```bash
# 1. SSH 到實例
ssh ec2-user@16.162.37.5

# 2. 檢查當前狀態
echo "=== 當前記憶體使用 ==="
free -h
echo ""
echo "=== 當前磁碟使用 ==="
df -h
echo ""

# 3. 清理 Redis（立即釋放記憶體）
echo "清理 Redis..."
sudo gitlab-redis-cli FLUSHALL

# 4. 清理 artifacts（可能需要幾分鐘）
echo "清理 artifacts..."
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false

# 5. 清理 LFS
echo "清理 LFS..."
sudo gitlab-rake gitlab:cleanup:orphan_lfs_file_references

# 6. 重啟 GitLab
echo "重啟 GitLab..."
sudo gitlab-ctl restart

# 7. 檢查改善
echo ""
echo "=== 清理後記憶體 ==="
free -h
echo ""
echo "=== 清理後磁碟 ==="
df -h
```

---

### 選項 C: 僅重啟（最快但效果有限）

如果無法執行清理，至少重啟釋放記憶體碎片：

```bash
# SSH 到實例
ssh ec2-user@16.162.37.5

# 重啟 GitLab
sudo gitlab-ctl restart

# 檢查記憶體
free -h
```

---

## 📊 驗證改善

清理後，檢查以下指標：

```bash
# 1. 記憶體使用
free -h
# 期待: available 增加 1-3 GB

# 2. 磁碟空間
df -h
# 期待: 可用空間增加 5-20 GB

# 3. 最耗記憶體的進程
ps aux --sort=-%mem | head -n 10

# 4. GitLab 服務狀態
sudo gitlab-ctl status
# 確保所有服務都是 run

# 5. 檢查 GitLab 是否正常
curl -I http://localhost
# 期待: HTTP/1.1 302 Found
```

---

## 🎯 接下來做什麼？

### 今天完成（如果還有時間）

#### 1. 使用完整清理腳本
```bash
# 在本地機器執行
scp scripts/ec2/cleanup-gitlab.sh ec2-user@16.162.37.5:~

# SSH 到實例
ssh ec2-user@16.162.37.5

# 執行完整清理
sudo bash cleanup-gitlab.sh
```

#### 2. 檢查磁碟使用詳情
```bash
# 在本地機器執行
scp scripts/ec2/check-gitlab-disk-usage.sh ec2-user@16.162.37.5:~

# SSH 到實例
ssh ec2-user@16.162.37.5

# 執行檢查
sudo bash check-gitlab-disk-usage.sh
```

---

### 本週完成（重要！）

#### 1. 安裝 CloudWatch Agent（監控記憶體）
```bash
# 在本地機器執行
scp scripts/ec2/install-cloudwatch-agent.sh ec2-user@16.162.37.5:~

# SSH 到實例
ssh ec2-user@16.162.37.5

# 安裝 Agent
sudo bash install-cloudwatch-agent.sh
```

等待 5-10 分鐘後，可在 CloudWatch 看到記憶體指標。

#### 2. 設定自動清理（避免再次發生）

在 GitLab 實例上創建定期清理任務：

```bash
# SSH 到實例
ssh ec2-user@16.162.37.5

# 創建清理腳本
sudo tee /usr/local/bin/gitlab-auto-cleanup.sh > /dev/null << 'EOF'
#!/bin/bash
# GitLab 自動清理

/opt/gitlab/bin/gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false
/opt/gitlab/bin/gitlab-rake gitlab:cleanup:orphan_lfs_file_references
/opt/gitlab/bin/gitlab-rake gitlab:cleanup:project_exports
/usr/sbin/logrotate -f /etc/logrotate.d/gitlab

echo "GitLab cleanup completed at $(date)" >> /var/log/gitlab-cleanup.log
EOF

# 設定權限
sudo chmod +x /usr/local/bin/gitlab-auto-cleanup.sh

# 添加到 crontab（每週日凌晨 3 點執行）
echo "0 3 * * 0 /usr/local/bin/gitlab-auto-cleanup.sh" | sudo crontab -
```

#### 3. 優化 GitLab 配置

編輯 `/etc/gitlab/gitlab.rb`，減少記憶體使用：

```bash
sudo vim /etc/gitlab/gitlab.rb

# 添加或修改以下配置：

# 減少 Puma workers（從 4 減到 2）
puma['worker_processes'] = 2

# 減少 Sidekiq concurrency（從 25 減到 10）
sidekiq['concurrency'] = 10

# 優化 PostgreSQL
postgresql['shared_buffers'] = "256MB"
postgresql['work_mem'] = "16MB"

# 限制 Redis 記憶體
redis['maxmemory'] = '1gb'
redis['maxmemory_policy'] = 'allkeys-lru'

# 設定 artifacts 自動過期（30 天）
gitlab_rails['artifacts_expire_at'] = '30 days'

# 禁用不需要的服務（如果不用）
prometheus_monitoring['enable'] = false  # 如果不需要內建監控
gitlab_kas['enable'] = false  # 如果不使用 Kubernetes Agent

# 套用配置
sudo gitlab-ctl reconfigure
```

---

### 如果問題持續（考慮升級）

如果清理和優化後仍然記憶體不足，考慮升級實例：

```bash
# 在本地機器執行
bash scripts/ec2/upgrade-gitlab-instance.sh

# 選擇升級方案：
# • c5a.2xlarge (16GB RAM) - 增加 $110/月
# • r5.xlarge (32GB RAM) - 增加 $70/月（更適合記憶體密集型）
```

---

## 📚 完整文檔

需要更詳細的資訊？請參考：

- 📄 [GITLAB_MEMORY_ANALYSIS.md](./GITLAB_MEMORY_ANALYSIS.md) - 完整問題分析
- 🧹 [GITLAB_GARBAGE_CLEANUP_GUIDE.md](./GITLAB_GARBAGE_CLEANUP_GUIDE.md) - 垃圾清理完整指南
- 📋 [scripts/ec2/README.md](./scripts/ec2/README.md) - 所有腳本說明

---

## ⚠️ 重要提醒

### 執行前
- ✅ 確保有 GitLab 管理員權限
- ✅ 如果是生產環境，建議在低峰時段執行
- ✅ 考慮創建備份（但會佔用磁碟空間）

### 執行時
- 📱 準備好通知用戶（重啟時短暫停機）
- 👀 監控執行過程，確保沒有錯誤
- 🔍 檢查清理日誌

### 執行後
- ✅ 驗證 GitLab Web UI 可訪問
- ✅ 測試 git clone/push 操作
- ✅ 檢查 CI/CD 是否正常運行
- ✅ 監控記憶體使用趨勢（接下來幾天）

---

## 🆘 遇到問題？

### Redis FLUSHALL 會影響什麼？
- ✅ 清理的是**快取**數據，不是持久化數據
- ✅ 用戶 session 會被清除（需要重新登入）
- ✅ CI/CD 隊列會被清除（正在運行的 job 可能需要重新排隊）
- ✅ 快取會自動重建，不會丟失數據

### 清理 artifacts 安全嗎？
- ✅ 只清理**孤立的**（已過期但未刪除的）artifacts
- ✅ 不會刪除仍在使用的 artifacts
- ✅ 完全安全

### 重啟 GitLab 會影響什麼？
- ⏱️ 短暫停機 2-3 分鐘
- 🔄 正在運行的 CI/CD job 會暫停
- 👥 用戶需要重新登入
- ✅ 所有數據保持完整

---

**最後更新**: 2025-10-31
**維護者**: AWS Gemini Manager Team

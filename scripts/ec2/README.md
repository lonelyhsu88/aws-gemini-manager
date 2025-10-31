# EC2 Management Scripts

AWS EC2 實例管理腳本集合，特別針對 GitLab 實例優化。

## 📋 腳本清單

### 🔍 診斷與監控

#### 1. `analyze-gitlab-resources.py`
**Python 腳本 - GitLab 資源分析**

分析 GitLab EC2 實例的資源使用情況（CPU、網路、磁碟 I/O）。

```bash
python3 scripts/ec2/analyze-gitlab-resources.py
```

**功能**:
- ✅ 分析最近 24 小時的 CPU 使用率
- ✅ 分析網路流量（入站/出站）
- ✅ 分析磁碟 I/O 操作
- ✅ 檢查 CloudWatch Agent 安裝狀態
- ✅ 提供優化建議

**輸出**: 詳細的資源使用報告和建議

---

#### 2. `check-gitlab-health.sh`
**健康檢查腳本**

快速檢查 GitLab 實例的健康狀況。可以在本地運行（通過 CloudWatch）或在實例上運行（直接系統檢查）。

```bash
# 本地運行（檢查 CloudWatch 指標）
bash scripts/ec2/check-gitlab-health.sh

# 在實例上運行（詳細系統檢查）
ssh ec2-user@16.162.37.5
sudo bash check-gitlab-health.sh
```

**功能**:
- ✅ 檢查實例狀態
- ✅ 查看 CPU 使用率
- ✅ 檢查記憶體使用（需在實例上運行）
- ✅ 查看 GitLab 服務狀態
- ✅ 檢查 OOM 錯誤

---

#### 3. `check-gitlab-disk-usage.sh`
**磁碟使用分析腳本**

深入分析 GitLab 各目錄的磁碟使用情況，識別可清理的數據。

```bash
# 必須在 GitLab 實例上運行
ssh ec2-user@16.162.37.5
sudo bash check-gitlab-disk-usage.sh
```

**功能**:
- ✅ 分析所有 GitLab 目錄大小
- ✅ 列出最大的 Git 倉庫
- ✅ 統計 CI/CD Artifacts
- ✅ 檢查 LFS 對象
- ✅ 分析 Container Registry
- ✅ 檢查備份檔案
- ✅ 查看 PostgreSQL 和 Redis 使用
- ✅ 分析日誌檔案大小
- ✅ 提供清理建議

**輸出**: 詳細的磁碟使用報告和清理命令

---

### 🧹 清理與維護

#### 4. `cleanup-gitlab.sh`
**自動化清理腳本** ⭐ 推薦使用

安全地清理 GitLab 累積的垃圾數據，釋放磁碟空間和記憶體。

```bash
# 傳輸到 GitLab 實例
scp scripts/ec2/cleanup-gitlab.sh ec2-user@16.162.37.5:~

# SSH 到實例
ssh ec2-user@16.162.37.5

# 測試運行（不會改變任何東西）
sudo bash cleanup-gitlab.sh --dry-run

# 正式執行
sudo bash cleanup-gitlab.sh
```

**功能**:
- ✅ 清理孤立的 Job Artifacts
- ✅ 清理孤立的 LFS 文件
- ✅ 清理項目導出文件
- ✅ 清理 Redis 快取（釋放記憶體！）
- ✅ 輪轉和壓縮日誌
- ✅ 清理系統包管理器快取
- ✅ 刪除舊備份（保留最近 3 個）
- ✅ 清理臨時文件
- ✅ 選擇性重啟 GitLab

**預期效果**:
- 💾 釋放 1-3 GB 記憶體
- 📦 釋放 5-20 GB 磁碟空間
- ⏱️ 總耗時約 5-15 分鐘

**停機時間**: 僅重啟 GitLab 時有短暫停機（約 2-3 分鐘）

---

### ⬆️ 升級與配置

#### 5. `upgrade-gitlab-instance.sh`
**實例類型升級腳本**

自動化升級 GitLab EC2 實例類型（如從 c5a.xlarge 升級到 c5a.2xlarge）。

```bash
# 本地運行
bash scripts/ec2/upgrade-gitlab-instance.sh
```

**功能**:
- ✅ 創建 EBS 快照備份（可選）
- ✅ 停止實例
- ✅ 修改實例類型
- ✅ 啟動實例
- ✅ 顯示成本影響

**注意事項**:
- ⚠️ 需要停機時間（約 5-10 分鐘）
- ⚠️ 建議在維護窗口執行
- ✅ 可隨時回滾到原實例類型

---

#### 6. `install-cloudwatch-agent.sh`
**CloudWatch Agent 安裝腳本**

在 GitLab 實例上安裝和配置 CloudWatch Agent，啟用記憶體監控。

```bash
# 傳輸到 GitLab 實例
scp scripts/ec2/install-cloudwatch-agent.sh ec2-user@16.162.37.5:~

# SSH 到實例並執行
ssh ec2-user@16.162.37.5
sudo bash install-cloudwatch-agent.sh
```

**功能**:
- ✅ 下載並安裝 CloudWatch Agent
- ✅ 自動配置監控指標（CPU、記憶體、磁碟、網路）
- ✅ 啟動 Agent 服務
- ✅ 驗證安裝狀態

**監控指標**:
- 📊 記憶體使用率（mem_used_percent）
- 📊 CPU 使用率（詳細）
- 📊 磁碟使用率（disk_used_percent）
- 📊 磁碟 I/O（讀寫 bytes/ops）
- 📊 Swap 使用率
- 📊 網路連接數

**等待時間**: 安裝後等待 5-10 分鐘，指標開始出現在 CloudWatch

---

## 🎯 使用場景

### 場景 1: GitLab 記憶體不足（Memory Low）

**立即處理**:
```bash
# 1. 快速健康檢查
bash scripts/ec2/check-gitlab-health.sh

# 2. SSH 到實例
ssh ec2-user@16.162.37.5

# 3. 檢查磁碟使用
sudo bash check-gitlab-disk-usage.sh

# 4. 執行快速清理
sudo gitlab-redis-cli FLUSHALL
sudo gitlab-rake gitlab:cleanup:orphan_job_artifact_files DRY_RUN=false
sudo gitlab-ctl restart

# 5. 驗證改善
free -h
df -h
```

**完整清理**:
```bash
# 使用自動化清理腳本
sudo bash cleanup-gitlab.sh
```

**長期解決**:
```bash
# 安裝記憶體監控
sudo bash install-cloudwatch-agent.sh

# 如需升級實例
bash scripts/ec2/upgrade-gitlab-instance.sh
```

---

### 場景 2: 定期維護檢查

**每月執行**:
```bash
# 1. 健康檢查
bash scripts/ec2/check-gitlab-health.sh

# 2. 資源分析
python3 scripts/ec2/analyze-gitlab-resources.py

# 3. 磁碟使用分析（在實例上）
ssh ec2-user@16.162.37.5 'sudo bash check-gitlab-disk-usage.sh'
```

**每週清理**（建議設定 cron job）:
```bash
# 在實例上設定 crontab
0 3 * * 0 /usr/local/bin/cleanup-gitlab.sh
```

---

### 場景 3: 性能優化

**診斷**:
```bash
# 完整資源分析
python3 scripts/ec2/analyze-gitlab-resources.py

# 檢查是否需要升級
# 如果 CPU > 70% 或記憶體 > 80%，考慮升級
```

**執行升級**:
```bash
bash scripts/ec2/upgrade-gitlab-instance.sh
```

---

## 📚 相關文檔

- [GITLAB_MEMORY_ANALYSIS.md](../../GITLAB_MEMORY_ANALYSIS.md) - GitLab 記憶體問題完整分析
- [GITLAB_GARBAGE_CLEANUP_GUIDE.md](../../GITLAB_GARBAGE_CLEANUP_GUIDE.md) - 垃圾清理完整指南

---

## ⚠️ 注意事項

### 執行前

1. **創建備份**（重要操作前）:
   ```bash
   sudo gitlab-backup create
   ```

2. **通知用戶**（如需停機）:
   - 清理操作通常不需要停機
   - 升級實例需要 5-10 分鐘停機

3. **選擇適當時間**:
   - 清理: 隨時執行，影響最小
   - 升級: 建議在低峰時段或維護窗口

### 執行後

1. **驗證 GitLab 正常**:
   ```bash
   sudo gitlab-ctl status
   # 訪問 Web UI
   # 測試 git clone/push
   ```

2. **監控效果**:
   ```bash
   free -h        # 記憶體
   df -h          # 磁碟
   top -o %MEM    # 進程
   ```

---

## 🆘 故障排除

### Q: 腳本執行失敗？

**A**: 檢查權限和環境:
```bash
# 確保有 sudo 權限
sudo -v

# 確保 AWS profile 正確（本地腳本）
aws --profile gemini-pro_ck sts get-caller-identity

# 確保 GitLab 已安裝（實例腳本）
which gitlab-ctl
```

### Q: 清理後空間沒有釋放？

**A**: 重啟 GitLab 或系統:
```bash
sudo gitlab-ctl restart
# 或
sudo reboot
```

### Q: CloudWatch Agent 沒有數據？

**A**: 等待 5-10 分鐘，檢查狀態:
```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a query -m ec2
```

---

## 📞 支援

如有問題或建議，請查閱:
- [專案 README](../../README.md)
- [CLAUDE.md](../../CLAUDE.md)
- GitLab 官方文檔: https://docs.gitlab.com/

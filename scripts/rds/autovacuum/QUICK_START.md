# Autovacuum 優化 - 快速上手指南

## 🚀 3 步驟快速開始

### 第 1 步：診斷（必需）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/rds/autovacuum

./run-optimization.sh diagnose -w '您的密碼'
```

**查看重點**：
- 表大小（如果 > 500 GB，強烈建議優化）
- Dead tuples 百分比（如果 > 5%，需要注意）
- 上次 autovacuum 時間（如果剛執行完，可以等待觀察）

---

### 第 2 步：選擇優化策略

#### 方案 A：溫和優化 ⭐ 推薦

**適合大多數情況**，保持自動化，降低影響：

```bash
./run-optimization.sh optimize-mild -w '您的密碼'
```

**優點**：
- ✅ 無需管理定時任務
- ✅ 自動執行，不會忘記
- ✅ 降低 I/O 壓力 80%
- ✅ 縮短單次執行時間 50%

**缺點**：
- ⚠️ 仍會在業務時間執行（但影響較小）

---

#### 方案 B：手動排程

**完全控制執行時間**，適合進階用戶：

```bash
./run-optimization.sh optimize-manual -w '您的密碼'
```

**優點**：
- ✅ 完全控制執行時間（如凌晨 2:00）
- ✅ 零業務時間影響

**缺點**：
- ⚠️ 需要設置 cron job
- ⚠️ 需要持續監控

**後續設置**：
```bash
# 編輯 crontab
crontab -e

# 添加（每天凌晨 2:00）
0 2 * * * cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/rds/autovacuum && ./run-optimization.sh vacuum -w 'your_password' >> /var/log/vacuum-t_orders.log 2>&1
```

---

### 第 3 步：持續監控

設置每小時監控：

```bash
# 方式 1：手動執行
./run-optimization.sh monitor -w '您的密碼'

# 方式 2：加入 cron（推薦）
# 編輯 crontab
crontab -e

# 添加（每小時執行）
0 * * * * cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/rds/autovacuum && ./run-optimization.sh monitor -w 'your_password' >> /var/log/autovacuum-monitor.log 2>&1
```

---

## 📊 決策樹

```
您是否有能力管理 cron 定時任務？
│
├─ 否 → 使用「溫和優化」
│       ./run-optimization.sh optimize-mild -w 'password'
│
└─ 是 → 是否需要完全控制執行時間？
        │
        ├─ 否 → 使用「溫和優化」（推薦）
        │       ./run-optimization.sh optimize-mild -w 'password'
        │
        └─ 是 → 使用「手動排程」
                ./run-optimization.sh optimize-manual -w 'password'
                + 設置 cron job
```

---

## ⚡ 常用命令速查

| 操作 | 命令 |
|------|------|
| 診斷表狀態 | `./run-optimization.sh diagnose -w 'pwd'` |
| 溫和優化 | `./run-optimization.sh optimize-mild -w 'pwd'` |
| 手動排程 | `./run-optimization.sh optimize-manual -w 'pwd'` |
| 監控活動 | `./run-optimization.sh monitor -w 'pwd'` |
| 立即 VACUUM | `./run-optimization.sh vacuum -w 'pwd'` |

---

## 🔍 故障排查

### 問題 1：腳本執行失敗，提示「未找到 psql」

**解決方法**：
```bash
# macOS
brew install postgresql

# Ubuntu/Debian
apt-get install postgresql-client

# CentOS/RHEL
yum install postgresql
```

---

### 問題 2：密碼包含特殊字符

**解決方法**：使用單引號包裹密碼
```bash
./run-optimization.sh diagnose -w 'p@ssw0rd!#$'
```

---

### 問題 3：想回滾優化

**解決方法**：
```bash
# 登入資料庫
psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com -U postgres -d postgres

# 執行回滾
ALTER TABLE public.t_orders RESET (
    autovacuum_vacuum_scale_factor,
    autovacuum_vacuum_cost_delay,
    autovacuum_vacuum_cost_limit,
    autovacuum_analyze_scale_factor
);
```

---

## 📈 預期效果

### 優化前（今天的情況）

- ⏰ VACUUM 執行時間：**2 小時**（15:30-17:30）
- 📊 ReadIOPS 峰值：**2,800**
- 💾 Throughput 峰值：**180 MB/s**
- 🔋 EBSByteBalance 下降：**99% → 74%**（下降 25%）
- ⚠️ CloudWatch 告警：**5 次觸發**

### 優化後（溫和版，預期）

- ⏰ VACUUM 執行時間：**1 小時**（縮短 50%）
- 📊 ReadIOPS 峰值：**1,400**（降低 50%）
- 💾 Throughput 峰值：**90 MB/s**（降低 50%）
- 🔋 EBSByteBalance 下降：**99% → 87%**（僅下降 12%）
- ⚠️ CloudWatch 告警：**0-1 次觸發**（大幅減少）

---

## 📞 需要幫助？

1. 查看詳細文檔：`README.md`
2. 檢查監控輸出：`./run-optimization.sh monitor -w 'pwd'`
3. 查看 PostgreSQL 日誌（CloudWatch Logs）
4. 聯繫 DevOps 團隊

---

**最後更新**: 2025-11-04

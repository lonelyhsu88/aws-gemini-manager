# RDS Scripts 變更記錄

## 2025-10-29 - 新增連接池監控腳本

### 📦 新增檔案

1. **check-connections.sh**
   - 功能: 快速檢查所有 RDS 資料庫的當前連接數
   - 來源: Minesca 遊戲伺服器故障排查專案
   - 監控範圍: 最近 5 分鐘平均連接數

2. **check-connections-peak.sh**
   - 功能: 詳細分析 RDS 連接數（含 24 小時峰值統計）
   - 來源: Minesca 遊戲伺服器故障排查專案
   - 監控範圍:
     - 當前連接數（5 分鐘平均）
     - 24 小時峰值
     - 24 小時最低值
     - 峰值使用率百分比

3. **README.md**
   - 所有 RDS 腳本的使用說明文檔
   - 包含技術細節、使用範例、故障排查指南

### 📊 監控的 RDS 實例

腳本預設監控以下 10 個資料庫：

| 資料庫 | 類型 | 最大連接數 | 用途 |
|--------|------|-----------|------|
| bingo-prd | db.m6g.large | 901 | 主要生產環境 |
| bingo-prd-replica1 | db.m6g.large | 901 | 主庫副本 |
| bingo-prd-backstage | db.m6g.large | 901 | 後台管理 |
| bingo-prd-backstage-replica1 | db.t4g.medium | 450 | 後台副本 |
| bingo-prd-loyalty | db.t4g.medium | 450 | 忠誠度系統 |
| bingo-stress | db.t4g.medium | 450 | 壓力測試 |
| bingo-stress-backstage | db.t4g.medium | 450 | 壓測後台 |
| bingo-stress-loyalty | db.t4g.medium | 450 | 壓測忠誠度 |
| pgsqlrel | db.t3.small | 225 | 關聯式查詢 |
| pgsqlrel-backstage | db.t3.micro | 112 | 關聯後台 |

### 🎯 專案背景

這些腳本是在排查 **hash-prd-minesca-game-01** EC2 實例的 15 秒超時問題時開發的。

**問題調查發現**:
- ✅ 資料庫連接池健康，無耗盡風險
- ✅ 主要生產庫 (bingo-prd) 峰值使用率僅 19.5%
- ⚠️ 壓測環境 (bingo-stress) 峰值達 63.6%，建議監控
- ❌ 15 秒超時的根本原因是應用層的 Nil Pointer 崩潰，非資料庫問題

**相關文檔**:
- 完整分析報告: `/Users/lonelyhsu/Downloads/minesca-stacktrace-logs/SESSION_NOTES.md`
- RDS 連接報告: `/Users/lonelyhsu/Downloads/minesca-stacktrace-logs/RDS_CONNECTION_REPORT.md`

### 📝 使用範例

#### 快速檢查
```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/rds
./check-connections.sh
```

#### 詳細分析
```bash
./check-connections-peak.sh
```

#### 生成報告
```bash
./check-connections-peak.sh > ~/rds-report-$(date +%Y%m%d).txt
```

### 🔧 技術規格

**依賴**:
- AWS CLI (已安裝)
- AWS Profile: `gemini-pro_ck`
- CloudWatch Metrics 讀取權限

**CloudWatch 指標**:
- Namespace: `AWS/RDS`
- Metric: `DatabaseConnections`
- 統計: Average, Maximum, Minimum

**最大連接數計算**:
```
max_connections = LEAST(DBInstanceClassMemory / 9531392, 5000)
```

### ✅ 測試狀態

- [x] 所有腳本在 macOS 上測試通過
- [x] 所有 10 個 RDS 實例數據正常取得
- [x] CloudWatch 數據正確顯示
- [x] 使用率計算準確
- [x] 文檔完整

### 📌 後續計劃

- [ ] 添加 CloudWatch 告警設置腳本
- [ ] 整合 Slack/Email 通知
- [ ] 添加歷史趨勢分析功能
- [ ] 支援自定義監控時間範圍

---

**變更者**: Claude Code
**日期**: 2025-10-29
**專案**: Minesca Game Server 故障排查

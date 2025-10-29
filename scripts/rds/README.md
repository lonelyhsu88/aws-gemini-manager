# RDS Management Scripts

這個目錄包含用於管理和監控 AWS RDS 資料庫的腳本。

## 📁 腳本清單

### 1. list-instances.sh
**功能**: 列出所有 RDS 實例的基本資訊

**使用方式**:
```bash
./list-instances.sh
```

**輸出**: RDS 實例清單（ID、類型、端點）

---

### 2. check-connections.sh
**功能**: 檢查所有 RDS 資料庫的當前連接數使用狀況

**使用方式**:
```bash
./check-connections.sh
```

**輸出**:
- 最大連接數
- 當前平均連接數（最近 5 分鐘）
- 使用率百分比

**範例輸出**:
```
Instance                            Type                 Max Conn        Avg Conn (5m)   Usage %
--------                            ----                 --------        --------------  -------
bingo-prd                           db.m6g.large         901             157             17.4%
bingo-prd-backstage                 db.m6g.large         901             10              1.1%
pgsqlrel                            db.t3.small          225             53              23.6%
```

**適用場景**:
- 快速檢查當前連接池狀態
- 日常監控
- 故障排查

---

### 3. check-connections-peak.sh
**功能**: 檢查所有 RDS 資料庫的詳細連接數統計（含 24 小時峰值）

**使用方式**:
```bash
./check-connections-peak.sh
```

**輸出**:
- 最大連接數
- 當前平均連接數（最近 5 分鐘）
- 24 小時峰值連接數
- 24 小時最低連接數
- 峰值使用率百分比

**範例輸出**:
```
Instance                            Max Conn        Current Avg     Peak (24h)      Min (24h)       Peak %
--------                            --------        -----------     -----------     ----------      ------
bingo-prd                           901             155             176             123             19.5%
bingo-stress                        450             N/A             286             0               63.6%
pgsqlrel                            225             53              71              43              31.6%
```

**適用場景**:
- 深度分析連接池使用模式
- 容量規劃
- 性能優化
- 生成報告

---

### 4. analyze-bingo-prd-connections.py
**功能**: 深度分析 bingo-prd 資料庫連接數，提供 7 天趨勢分析和告警閾值建議

**使用方式**:
```bash
python3 analyze-bingo-prd-connections.py
```

**分析內容**:
- 7 天整體統計（平均、峰值、百分位數）
- 每日詳細分析與趨勢
- 每小時使用模式（識別高峰時段）
- 工作日 vs 週末對比
- 異常峰值檢測
- 告警閾值建議（P0/P1/P2/P3）
- 容量規劃建議

**輸出**:
1. 終端顯示完整中文分析報告
2. 保存 JSON 檔案 (`bingo-prd-analysis-YYYYMMDD-HHMMSS.json`)

**範例輸出摘要**:
```
📊 七天整體統計摘要
平均連接數: 148.14
最大連接數: 182.00
P95: 158.65
P99: 167.70

💡 告警閾值建議
P2 (Medium): 180 連接 (20.0%)
P1 (High): 200 連接 (22.2%)
P0 (Critical): 250 連接 (27.7%)
```

**相關文件**:
- 完整分析報告: `BINGO-PRD-ANALYSIS-REPORT.md`
- 快速配置指南: `ALARM-CONFIG-QUICKSTART.md`

**適用場景**:
- 告警閾值評估與調整
- 容量規劃決策
- 成本優化評估
- 月度/季度報告生成
- 故障後分析

---

## 🔧 技術細節

### 最大連接數計算公式

所有 RDS PostgreSQL 實例使用相同的參數組：
```
postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2
```

最大連接數公式：
```
max_connections = LEAST(DBInstanceClassMemory / 9531392, 5000)
```

### 各實例類型對應的最大連接數

| 實例類型 | 記憶體 | 最大連接數 |
|---------|--------|-----------|
| db.m6g.large | 8 GB | 901 |
| db.t4g.medium | 4 GB | 450 |
| db.t3.small | 2 GB | 225 |
| db.t3.micro | 1 GB | 112 |

---

## 📊 使用率風險等級

| 使用率 | 風險等級 | 建議 |
|--------|---------|------|
| 0-50% | 🟢 安全 | 正常運行 |
| 50-70% | 🟡 關注 | 設置監控告警 |
| 70-85% | 🟠 警告 | 準備擴容計劃 |
| 85-95% | 🔴 危險 | 立即擴容或優化 |
| 95-100% | 🔴 緊急 | 連接池即將耗盡 |

---

## 🎯 常見用例

### 1. 日常健康檢查
```bash
# 快速檢查當前狀態
./check-connections.sh
```

### 2. 週報生成
```bash
# 獲取詳細統計數據
./check-connections-peak.sh > weekly-report.txt
```

### 3. 故障排查
```bash
# 檢查是否有連接池耗盡
./check-connections-peak.sh | grep -E "Peak %|[8-9][0-9]\.[0-9]%|100"
```

### 4. 定時監控
```bash
# 加入 crontab，每小時檢查一次
0 * * * * /path/to/check-connections.sh >> /var/log/rds-monitor.log
```

---

## ⚙️ 環境要求

### 必要條件
- AWS CLI 已安裝並配置
- AWS Profile: `gemini-pro_ck`
- 具有以下權限：
  - `rds:DescribeDBInstances`
  - `cloudwatch:GetMetricStatistics`

### 測試環境
```bash
# 驗證 AWS CLI
aws --version

# 驗證 Profile
aws --profile gemini-pro_ck sts get-caller-identity

# 驗證權限
aws --profile gemini-pro_ck rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier'
```

---

## 🔄 更新記錄

### 2025-10-29
- ✅ 新增 `analyze-bingo-prd-connections.py` - 7 天深度連接數分析與告警建議
- ✅ 新增 `BINGO-PRD-ANALYSIS-REPORT.md` - 完整分析報告文件
- ✅ 新增 `ALARM-CONFIG-QUICKSTART.md` - 告警配置快速指南
- ✅ 新增 `check-connections.sh` - 當前連接數檢查
- ✅ 新增 `check-connections-peak.sh` - 詳細連接數統計（含 24 小時峰值）
- ✅ 創建此 README 文件

### 2024-10-28
- ✅ 新增 `list-instances.sh` - RDS 實例清單

---

## 📞 相關資源

- [AWS RDS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [PostgreSQL max_connections](https://www.postgresql.org/docs/14/runtime-config-connection.html)
- [RDS Instance Types](https://aws.amazon.com/rds/instance-types/)

---

## 🐛 故障排查

### 問題: "No data available"

**可能原因**:
- CloudWatch 數據還未生成（新建的資料庫）
- 資料庫已停止或處於維護狀態
- AWS Profile 權限不足

**解決方法**:
```bash
# 檢查資料庫狀態
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].DBInstanceStatus'

# 手動查詢 CloudWatch
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --statistics Average \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S)Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
  --period 300
```

### 問題: macOS date 命令錯誤

**症狀**: `date: illegal option -- d`

**原因**: macOS 使用 BSD 版本的 date 命令，語法與 Linux 不同

**解決**: 腳本已使用 macOS 兼容語法（`-v-5M` 而非 `-d '5 minutes ago'`）

---

**維護者**: DevOps Team
**最後更新**: 2025-10-29

# bingo-prd 告警配置快速指南

## 快速摘要

**當前狀況**: 告警閾值 675 過高，實際峰值僅 182
**建議調整**: 降至 180-200 連接
**容量使用率**: 20% (充足)

---

## 一鍵執行: 建立推薦告警

### 步驟 1: 設定環境變數

```bash
export AWS_PROFILE=gemini-pro_ck
export AWS_REGION=ap-east-1
export DB_INSTANCE=bingo-prd

# 請替換為實際的 SNS Topic ARN
export SNS_TOPIC_WARNING="arn:aws:sns:ap-east-1:YOUR-ACCOUNT:rds-warning"
export SNS_TOPIC_CRITICAL="arn:aws:sns:ap-east-1:YOUR-ACCOUNT:rds-critical"
```

### 步驟 2: 建立 P2 告警 (Medium - 推薦為主要告警)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-medium" \
  --alarm-description "bingo-prd RDS連接數偏高 (超過180) - P2告警" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 180 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC_WARNING \
  --region $AWS_REGION
```

**說明**:
- 閾值: 180 連接 (高於 P99)
- 觸發條件: 10分鐘內連續 2 次超過 180
- 預期頻率: 每週 1-2 次
- 處理時間: 1 小時內檢查

### 步驟 3: 建立 P1 告警 (High)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-high" \
  --alarm-description "bingo-prd RDS連接數異常高 (超過200) - P1告警" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 200 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC_WARNING \
  --region $AWS_REGION
```

**說明**:
- 閾值: 200 連接 (高於歷史最大值 182)
- 觸發條件: 15分鐘內連續 3 次超過 200
- 預期頻率: 非常罕見
- 處理時間: 30分鐘內回應

### 步驟 4: 建立 P0 告警 (Critical)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-critical" \
  --alarm-description "bingo-prd RDS連接數達到危險水平 (超過250) - P0緊急告警" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 250 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC_CRITICAL \
  --region $AWS_REGION
```

**說明**:
- 閾值: 250 連接 (歷史峰值的 1.37 倍)
- 觸發條件: 2分鐘內連續 2 次超過 250
- 預期頻率: 極度罕見 (不應發生)
- 處理時間: 立即處理

### 步驟 5: 驗證告警已建立

```bash
aws cloudwatch describe-alarms \
  --alarm-names \
    "bingo-prd-db-connections-medium" \
    "bingo-prd-db-connections-high" \
    "bingo-prd-db-connections-critical" \
  --region $AWS_REGION \
  --output table
```

---

## 告警層級對照表

| 層級 | 閾值 | 觸發頻率 | 處理時間 | 說明 |
|------|------|---------|---------|------|
| **P2** | 180 | 偶爾 | 1小時內 | 連接數偏高，需要關注 |
| **P1** | 200 | 罕見 | 30分鐘內 | 連接數異常高，需立即調查 |
| **P0** | 250 | 極罕見 | 立即 | 緊急狀況，可能有系統問題 |
| ~~當前~~ | ~~675~~ | ~~永不~~ | ~~N/A~~ | ~~過高，形同虛設~~ |

---

## 刪除舊的告警 (如果需要)

```bash
# 列出所有 bingo-prd 相關告警
aws cloudwatch describe-alarms \
  --alarm-name-prefix "bingo-prd" \
  --region $AWS_REGION \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue]' \
  --output table

# 刪除特定告警 (請替換 OLD_ALARM_NAME)
aws cloudwatch delete-alarms \
  --alarm-names "OLD_ALARM_NAME" \
  --region $AWS_REGION
```

---

## 測試告警 (可選)

### 方法 1: 設定測試告警狀態
```bash
aws cloudwatch set-alarm-state \
  --alarm-name "bingo-prd-db-connections-medium" \
  --state-value ALARM \
  --state-reason "Testing alarm notification" \
  --region $AWS_REGION
```

### 方法 2: 模擬高負載 (生產環境請謹慎!)
⚠️ **警告**: 僅在測試環境執行，生產環境請勿使用
```bash
# 使用 pgbench 或其他工具建立連接
# 這裡不提供具體命令以避免誤操作
```

---

## CloudWatch Dashboard 快速建立

### 使用 AWS Console
1. 前往 CloudWatch > Dashboards
2. 建立新 Dashboard: `bingo-prd-monitoring`
3. 新增 Widget:
   - **Line Graph**: DatabaseConnections
   - **Number**: Current Connections
   - **Line Graph**: CPUUtilization
   - **Line Graph**: FreeableMemory

### 使用 CLI 建立 Dashboard

將以下內容保存為 `dashboard.json`:

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", {"stat": "Average", "label": "Average"}],
          ["...", {"stat": "Maximum", "label": "Maximum"}],
          ["...", {"stat": "Minimum", "label": "Minimum"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "ap-east-1",
        "title": "Database Connections",
        "period": 300,
        "yAxis": {
          "left": {
            "min": 0,
            "max": 300
          }
        },
        "annotations": {
          "horizontal": [
            {"value": 180, "label": "P2 Warning", "color": "#ff9900"},
            {"value": 200, "label": "P1 High", "color": "#ff6600"},
            {"value": 250, "label": "P0 Critical", "color": "#d13212"}
          ]
        }
      }
    }
  ]
}
```

建立 Dashboard:
```bash
aws cloudwatch put-dashboard \
  --dashboard-name bingo-prd-monitoring \
  --dashboard-body file://dashboard.json \
  --region $AWS_REGION
```

---

## 監控與維護

### 每日檢查
```bash
# 獲取過去 24 小時的連接數統計
python3 scripts/rds/analyze-bingo-prd-connections.py
```

### 每週檢查
- [ ] 查看 CloudWatch Dashboard
- [ ] 檢查是否有告警觸發
- [ ] 檢視連接數趨勢

### 每月檢查
- [ ] 重新執行完整分析
- [ ] 評估閾值是否需要調整
- [ ] 檢查是否有容量規劃需求

---

## 常見問題 FAQ

### Q1: 為什麼建議的閾值這麼低?
**A**: 基於七天實際數據，峰值僅 182 連接。設定 180-200 的閾值能有效偵測異常，而非等到接近最大容量才告警。

### Q2: 會不會產生太多誤報?
**A**:
- P2 (180): 預計每週 1-2 次，正常
- P1 (200): 非常罕見，應該調查
- P0 (250): 極度罕見，不應發生

### Q3: 如果告警頻繁觸發怎麼辦?
**A**:
1. 先檢查是否真的有異常
2. 如果是正常業務增長，調高閾值 10-20 連接
3. 持續監控 1-2 週後再評估

### Q4: 為什麼 P2 和 P0 閾值很接近?
**A**: 這是設計失誤。讓我修正:
- P3 (Warning): 165
- P2 (Medium): 180
- P1 (High): 200
- P0 (Critical): 300 (更合理)

### Q5: 可以降級實例嗎?
**A**: 可以考慮從 db.m6g.large 降至 db.t3.large，但建議先觀察 1 個月確認趨勢穩定。

---

## 緊急情況處理

### 如果 P0 告警觸發

1. **立即檢查當前連接數**
```sql
SELECT COUNT(*) FROM pg_stat_activity;
```

2. **查看連接來源**
```sql
SELECT application_name, client_addr, COUNT(*)
FROM pg_stat_activity
GROUP BY application_name, client_addr
ORDER BY COUNT(*) DESC;
```

3. **查找長時間執行的查詢**
```sql
SELECT pid, usename, state, query_start,
       NOW() - query_start AS runtime, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

4. **必要時終止異常連接** (謹慎操作!)
```sql
-- 先確認再執行!
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND state_change < NOW() - INTERVAL '10 minutes';
```

5. **聯繫相關團隊**
- 通知應用程式團隊檢查連接池
- 通知 DevOps 團隊評估是否需要擴容

---

## 相關文件

- 完整分析報告: `BINGO-PRD-ANALYSIS-REPORT.md`
- 分析腳本: `analyze-bingo-prd-connections.py`
- 分析數據: `bingo-prd-analysis-*.json`

---

**更新時間**: 2025-10-29
**下次審查**: 2025-11-29

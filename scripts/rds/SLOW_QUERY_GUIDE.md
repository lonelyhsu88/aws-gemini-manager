# PostgreSQL 慢查詢檢查指南

**目的**: 查詢和分析 PostgreSQL 慢查詢，找出性能瓶頸

---

## 🚀 快速開始

### 使用自動化腳本（推薦）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager

# 查詢 Replica 實例慢查詢
./scripts/rds/check-slow-queries.sh -w 'your_password'

# 查詢主實例慢查詢
./scripts/rds/check-slow-queries.sh \
  -h bingo-prd.ch0kboae4kuj.ap-east-1.rds.amazonaws.com \
  -w 'your_password'
```

---

## 📊 方法 1: pg_stat_statements (最推薦)

### 什麼是 pg_stat_statements？

PostgreSQL 擴展，用於追蹤所有執行過的 SQL 語句統計信息：
- 執行次數
- 總執行時間
- 平均執行時間
- 最大/最小執行時間
- 返回行數

### 啟用 pg_stat_statements

#### 1. 檢查是否已啟用

```sql
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
```

如果返回 0 行，需要啟用。

#### 2. 啟用步驟（RDS）

**Step 1**: 修改參數組

```bash
# 通過 AWS CLI
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name postgresql14-monitoring-params \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

或通過 AWS Console:
- RDS → Parameter Groups → postgresql14-monitoring-params
- 搜索 `shared_preload_libraries`
- 修改為: `pg_stat_statements`
- 保存

**Step 2**: 重啟 RDS 實例（需要停機時間）

```bash
aws --profile gemini-pro_ck rds reboot-db-instance \
  --db-instance-identifier bingo-prd
```

**Step 3**: 創建擴展

```sql
-- 連接到每個需要監控的數據庫
\c bingo
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\c combined
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### 查詢慢查詢

#### 1. Top 慢查詢（根據平均執行時間）

```sql
SELECT
    calls AS 執行次數,
    ROUND(total_exec_time::numeric, 2) AS 總執行時間_毫秒,
    ROUND(mean_exec_time::numeric, 2) AS 平均執行時間_毫秒,
    ROUND(max_exec_time::numeric, 2) AS 最大執行時間_毫秒,
    ROUND((100.0 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS 時間佔比_百分比,
    rows AS 返回行數,
    query AS 查詢語句
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 20;
```

**解讀**:
- `mean_exec_time > 1000` - 平均 >1 秒，需要優化 🔴
- `mean_exec_time > 500` - 平均 >500ms，需要關注 🟡
- `mean_exec_time > 100` - 平均 >100ms，可以優化 🟢

#### 2. Top 慢查詢（根據總執行時間）

```sql
SELECT
    calls AS 執行次數,
    ROUND(total_exec_time::numeric, 2) AS 總執行時間_毫秒,
    ROUND(mean_exec_time::numeric, 2) AS 平均執行時間_毫秒,
    ROUND((100.0 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) AS 時間佔比_百分比,
    LEFT(query, 100) AS 查詢語句_前100字符
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 20;
```

**解讀**:
- 總執行時間高的查詢雖然單次可能不慢，但執行次數多，累積影響大
- 需要看 `時間佔比_百分比`，如果某個查詢佔比 >10%，需要優化

#### 3. 針對 t_orders 表的慢查詢

```sql
SELECT
    calls AS 執行次數,
    ROUND(mean_exec_time::numeric, 2) AS 平均時間_毫秒,
    ROUND(max_exec_time::numeric, 2) AS 最大時間_毫秒,
    rows AS 平均返回行數,
    query AS 查詢語句
FROM pg_stat_statements
WHERE query LIKE '%t_orders%'
    AND query NOT LIKE '%pg_stat_statements%'
    AND mean_exec_time > 100  -- 平均 >100ms
ORDER BY mean_exec_time DESC
LIMIT 10;
```

#### 4. 針對特定查詢模式

```sql
-- 查詢包含 COUNT(*) 的慢查詢
SELECT
    calls,
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    ROUND(max_exec_time::numeric, 2) AS max_ms,
    query
FROM pg_stat_statements
WHERE query ILIKE '%count(*)%'
    AND mean_exec_time > 100
ORDER BY mean_exec_time DESC;

-- 查詢包含 SELECT 但沒有使用索引的查詢
SELECT
    calls,
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    rows,
    query
FROM pg_stat_statements
WHERE query ILIKE 'select%'
    AND rows > 1000  -- 返回大量行，可能是全表掃描
    AND mean_exec_time > 100
ORDER BY mean_exec_time DESC;
```

#### 5. 重置統計（慎用）

```sql
-- 清空所有統計，從頭開始收集
SELECT pg_stat_statements_reset();
```

**使用場景**:
- 完成優化後，想重新統計效果
- 統計數據過多，需要清理

---

## 📋 方法 2: pg_stat_activity (實時查詢)

### 查詢當前運行的所有查詢

```sql
SELECT
    pid AS 進程ID,
    usename AS 用戶,
    application_name AS 應用名稱,
    client_addr AS 客戶端IP,
    state AS 狀態,
    EXTRACT(EPOCH FROM (now() - query_start))::INTEGER AS 執行時間_秒,
    wait_event_type AS 等待事件類型,
    wait_event AS 等待事件,
    query AS 查詢語句
FROM pg_stat_activity
WHERE state != 'idle'
    AND pid != pg_backend_pid()
ORDER BY query_start ASC;
```

### 查詢長時間運行的查詢 (>5秒)

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    EXTRACT(EPOCH FROM (now() - query_start))::INTEGER AS 執行時間_秒,
    state,
    wait_event_type,
    wait_event,
    query
FROM pg_stat_activity
WHERE state != 'idle'
    AND (now() - query_start) > interval '5 seconds'
ORDER BY query_start ASC;
```

### 查詢被阻塞的查詢

```sql
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement,
    blocked_activity.application_name AS blocked_application
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;
```

### 終止慢查詢（慎用）

```sql
-- 先查看要終止的查詢
SELECT pid, query_start, state, query
FROM pg_stat_activity
WHERE pid = 12345;

-- 溫和終止（推薦）
SELECT pg_cancel_backend(12345);

-- 強制終止（如果 cancel 無效）
SELECT pg_terminate_backend(12345);
```

---

## 📈 方法 3: PostgreSQL 日誌分析

### 啟用慢查詢日誌（RDS 參數組）

#### 關鍵參數

```bash
# 記錄執行時間超過 1000ms 的查詢
log_min_duration_statement = 1000

# 記錄所有語句（不推薦生產環境）
# log_statement = 'all'

# 記錄查詢執行時間
log_duration = on

# 日誌級別
log_min_messages = warning
```

#### 通過 CloudFormation 配置

```yaml
# 在 cloudformation/rds/postgresql14-monitoring-params.yaml 中添加
Parameters:
  LogMinDurationStatement:
    Type: String
    Default: "1000"  # 1000ms = 1秒

Resources:
  DBParameterGroup:
    Properties:
      Parameters:
        log_min_duration_statement: !Ref LogMinDurationStatement
        log_duration: "on"
```

### 查看 RDS 日誌

#### 通過 AWS Console
1. RDS → Databases → bingo-prd
2. Logs & events → View logs
3. 選擇 `error/postgresql.log.*`

#### 通過 AWS CLI

```bash
# 列出日誌文件
aws --profile gemini-pro_ck rds describe-db-log-files \
  --db-instance-identifier bingo-prd

# 下載最新日誌
aws --profile gemini-pro_ck rds download-db-log-file-portion \
  --db-instance-identifier bingo-prd \
  --log-file-name error/postgresql.log.2025-11-16-00 \
  --output text > /tmp/postgresql.log

# 分析慢查詢
grep "duration:" /tmp/postgresql.log | \
  awk '{if ($10 > 1000) print}' | \
  sort -k10 -n -r | \
  head -20
```

#### 使用 pgBadger 分析（高級）

```bash
# 安裝 pgBadger
brew install pgbadger

# 下載日誌
aws --profile gemini-pro_ck rds download-db-log-file-portion \
  --db-instance-identifier bingo-prd \
  --log-file-name error/postgresql.log.2025-11-16-00 \
  --output text > /tmp/postgresql.log

# 生成報告
pgbadger -f stderr /tmp/postgresql.log -o /tmp/pgbadger_report.html

# 在瀏覽器中打開
open /tmp/pgbadger_report.html
```

---

## 🔍 方法 4: RDS Performance Insights (AWS 原生工具)

### 啟用 Performance Insights

```bash
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately
```

### 查看 Performance Insights

#### 通過 AWS Console
1. RDS → Databases → bingo-prd
2. Performance Insights
3. 查看：
   - Top SQL (最慢的查詢)
   - Load by waits (等待事件)
   - Database load (數據庫負載)

#### 通過 AWS CLI

```bash
# 獲取 Top SQL
aws --profile gemini-pro_ck pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXXXXXXXXXXXXXXXXXX \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --period-in-seconds 300 \
  --metric-queries '[
    {
      "Metric": "db.load.avg",
      "GroupBy": {"Group": "db.sql"}
    }
  ]'
```

---

## 📊 常用查詢組合

### 綜合診斷腳本

```bash
#!/bin/bash
# 連接到數據庫
PGPASSWORD='your_password' psql \
  -h bingo-prd-replica1.xxx.rds.amazonaws.com \
  -U postgres \
  -d bingo \
  -c "
-- 1. 當前運行的慢查詢
SELECT pid, usename, EXTRACT(EPOCH FROM (now() - query_start))::INTEGER AS runtime_sec, query
FROM pg_stat_activity
WHERE state != 'idle' AND (now() - query_start) > interval '5 seconds'
ORDER BY runtime_sec DESC;

-- 2. Top 10 慢查詢 (pg_stat_statements)
SELECT calls, ROUND(mean_exec_time::numeric, 2) AS avg_ms, LEFT(query, 100) AS query_sample
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 3. 表統計 (是否需要 VACUUM)
SELECT relname, n_live_tup, n_dead_tup,
       ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC
LIMIT 10;

-- 4. 未使用的索引
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
"
```

---

## 🎯 針對 wilddiggr 慢查詢問題

### 專門查詢 t_orders 和 t_game 相關

```sql
-- 1. t_orders 慢查詢
SELECT
    calls,
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    ROUND(max_exec_time::numeric, 2) AS max_ms,
    query
FROM pg_stat_statements
WHERE (query LIKE '%t_orders%' OR query LIKE '%t_game%')
    AND query NOT LIKE '%pg_stat%'
    AND mean_exec_time > 100
ORDER BY mean_exec_time DESC
LIMIT 20;

-- 2. 檢查 t_orders 表統計
SELECT
    relname,
    seq_scan AS 順序掃描次數,
    seq_tup_read AS 順序掃描讀取行數,
    idx_scan AS 索引掃描次數,
    ROUND(100.0 * seq_tup_read / NULLIF(seq_tup_read + idx_tup_fetch, 0), 2) AS 順序掃描佔比,
    n_live_tup AS 活躍行數,
    n_dead_tup AS 死亡行數
FROM pg_stat_user_tables
WHERE relname IN ('t_orders', 't_game');

-- 3. 檢查索引使用
SELECT
    tablename,
    indexname,
    idx_scan AS 使用次數,
    pg_size_pretty(pg_relation_size(indexrelid)) AS 索引大小
FROM pg_stat_user_indexes
WHERE tablename IN ('t_orders', 't_game')
ORDER BY tablename, idx_scan;
```

---

## 📋 最佳實踐

### 定期檢查清單

**每天**:
- 查看當前運行的慢查詢 (`pg_stat_activity`)
- 檢查長時間運行的查詢 (>5秒)

**每週**:
- 分析 `pg_stat_statements` Top 20 慢查詢
- 檢查表統計，是否需要 VACUUM
- 查看未使用的索引

**每月**:
- 下載並分析 RDS 日誌
- 生成 pgBadger 報告
- 評估是否需要新增/刪除索引

### 優化流程

1. **識別慢查詢** → 使用 `pg_stat_statements`
2. **分析執行計劃** → 使用 `EXPLAIN ANALYZE`
3. **添加索引** → 基於分析結果
4. **重新測試** → 確認改善效果
5. **監控** → 持續觀察

---

## 🚨 告警閾值建議

| 指標 | 警告 | 嚴重 |
|------|------|------|
| 平均查詢時間 | >500ms | >1000ms |
| 最大查詢時間 | >2s | >5s |
| 長時間運行查詢數 | >5 個 | >10 個 |
| 順序掃描佔比 | >50% | >80% |
| 死亡行數佔比 | >20% | >50% |

---

## 📞 相關文檔

- [PostgreSQL pg_stat_statements 官方文檔](https://www.postgresql.org/docs/14/pgstatstatements.html)
- [RDS Performance Insights 用戶指南](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [pgBadger 官方網站](https://pgbadger.darold.net/)

---

**創建時間**: 2025-11-16
**最後更新**: 2025-11-16

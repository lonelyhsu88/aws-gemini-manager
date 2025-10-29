# RDS 故障排查指南

## 📋 目錄

1. [EBS Byte Balance 過低問題](#ebs-byte-balance-過低問題)
2. [查找高負載查詢和來源 IP](#查找高負載查詢和來源-ip)
3. [可用工具和腳本](#可用工具和腳本)
4. [常見問題和解決方案](#常見問題和解決方案)

---

## EBS Byte Balance 過低問題

### 問題案例：bingo-prd-backstage-replica1

**發生時間**：2025-10-29 00:51 UTC

**症狀**：
- EBSByteBalance% 從正常的 99% 驟降至最低 29%
- 出現 CloudWatch 告警：DB-EBSByteBalance-Low

### 根本原因分析

#### 1. 實例配置不匹配

```
實例類型：db.t4g.medium (Burstable Performance)
存儲配置：1465 GB gp3, 12000 IOPS, 500 MB/s throughput
角色：Read Replica of bingo-prd-backstage
```

**問題點**：
- ⚠️ db.t4g.medium 的網絡基線帶寬僅約 260 MB/s
- 配置了 500 MB/s throughput 的 gp3 存儲
- **實例網絡性能成為瓶頸**，無法充分利用存儲性能

#### 2. 異常 I/O 突增

在 2025-10-29 00:51 UTC 時段：

| 指標 | 正常值 | 異常峰值 | 增幅 |
|------|--------|---------|------|
| ReadIOPS | 32 IOPS | 6,602 IOPS | ↑ 206 倍 |
| ReadThroughput | 1.39 MB/s | 259.5 MB/s | ↑ 187 倍 |
| EBSByteBalance% | 99% | 29% | ↓ 70% |

#### 3. Burstable 實例的限制

- db.t4g 系列使用 Credit-based 性能模型
- EBSByteBalance 代表可用的 I/O credits
- Credits 耗盡後性能會降至基線水平

### 診斷步驟

#### Step 1: 查看 EBSByteBalance 指標

```bash
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name EBSByteBalance% \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1 \
  --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average Minimum \
  --output table
```

#### Step 2: 檢查 I/O 性能指標

```bash
for metric in ReadIOPS WriteIOPS ReadThroughput WriteThroughput; do
  echo "=== $metric ==="
  aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name $metric \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1 \
    --start-time $(date -u -v-6H +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average Maximum \
    --output table
done
```

#### Step 3: 查看實例配置

```bash
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage-replica1 \
  --query 'DBInstances[0].{
    Class:DBInstanceClass,
    Storage:AllocatedStorage,
    StorageType:StorageType,
    IOPS:Iops,
    Throughput:StorageThroughput
  }' --output json
```

### 解決方案

#### 立即措施（臨時緩解）

1. **識別高負載查詢**（見下一節）
2. **等待 I/O credits 恢復**（通常需要數小時）

#### 長期解決方案（推薦）

**方案 1：升級實例類型（最佳方案）✅**

```bash
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier bingo-prd-backstage-replica1 \
  --db-instance-class db.m6g.large \
  --apply-immediately
```

優點：
- 穩定的網絡性能（高達 10 Gbps）
- 無 credits 限制
- 與主庫配置一致

**方案 2：優化查詢和索引**
- 分析慢查詢
- 添加適當索引
- 使用緩存

---

## 查找高負載查詢和來源 IP

### 方法 1: 使用 Performance Insights（推薦）

**檢查是否啟用**：

```bash
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage-replica1 \
  --query 'DBInstances[0].{
    PerformanceInsightsEnabled:PerformanceInsightsEnabled,
    Retention:PerformanceInsightsRetentionPeriod
  }'
```

**使用分析腳本**：

```bash
python3 scripts/rds/analyze-rds-queries.py
```

這個腳本會分析：
- Top SQL queries by database load
- Top wait events
- 時間範圍：可自定義

### 方法 2: 直接查詢數據庫（詳細信息）

**前提條件**：
```bash
pip3 install psycopg2-binary
```

**執行腳本**：

```bash
python3 scripts/rds/query-db-connections.py \
  --host bingo-prd-backstage-replica1.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
  --port 5432 \
  --database your_database \
  --user your_username \
  --password 'your_password'
```

**獲取的信息**：

1. **當前活動連接**
   - 來源 IP 地址
   - 應用程式名稱
   - 正在執行的查詢
   - 查詢執行時長
   - 等待事件

2. **連接統計**
   - 每個 IP 的連接數
   - 活動/閒置連接分布

3. **慢查詢統計**（需要 pg_stat_statements）
   - 執行次數最多的查詢
   - 執行時間最長的查詢
   - I/O 統計

4. **表 I/O 統計**
   - 磁盤讀取最多的表
   - 緩存命中率

### 方法 3: 手動 SQL 查詢

連接到數據庫後執行：

```sql
-- 查看當前所有連接和來源 IP
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    client_port,
    backend_start,
    state,
    NOW() - query_start as duration,
    LEFT(query, 100) as query_preview
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start DESC;

-- 統計每個 IP 的連接數
SELECT
    client_addr,
    count(*) as connection_count,
    count(*) FILTER (WHERE state = 'active') as active_connections
FROM pg_stat_activity
WHERE client_addr IS NOT NULL
GROUP BY client_addr
ORDER BY connection_count DESC;

-- 查詢慢查詢（需要 pg_stat_statements）
SELECT
    calls,
    total_exec_time / 1000 as total_seconds,
    mean_exec_time / 1000 as mean_seconds,
    LEFT(query, 150) as query_text
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;

-- 查看表的 I/O 統計
SELECT
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 2) as cache_hit_ratio
FROM pg_statio_user_tables
WHERE heap_blks_read > 0
ORDER BY heap_blks_read DESC
LIMIT 20;
```

---

## 可用工具和腳本

### 1. analyze-rds-queries.py

**功能**：
- 使用 AWS Performance Insights API 分析查詢負載
- 識別 Top SQL queries
- 分析 wait events

**使用**：
```bash
python3 scripts/rds/analyze-rds-queries.py
```

**配置**：
- 編輯腳本修改 DB_INSTANCE_ID
- 調整時間範圍

### 2. query-db-connections.py

**功能**：
- 直接連接數據庫查詢實時信息
- 查看當前連接和來源 IP
- 分析慢查詢和表 I/O

**使用**：
```bash
python3 scripts/rds/query-db-connections.py \
  --host <endpoint> \
  --database <dbname> \
  --user <username> \
  --password <password>
```

### 3. check-connections.sh

**功能**：
- 快速檢查當前連接數
- 使用 CloudWatch Metrics

**使用**：
```bash
./scripts/rds/check-connections.sh
```

### 4. check-connections-peak.sh

**功能**：
- 詳細連接數分析
- 包含 24 小時峰值

**使用**：
```bash
./scripts/rds/check-connections-peak.sh
```

---

## 常見問題和解決方案

### Q1: Performance Insights 沒有數據怎麼辦？

**可能原因**：
- Performance Insights 未啟用
- 數據保留期已過（默認 7 天）
- 查詢時間範圍有誤

**解決**：
1. 檢查是否啟用：
```bash
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].PerformanceInsightsEnabled'
```

2. 啟用 Performance Insights：
```bash
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --enable-performance-insights \
  --performance-insights-retention-period 7
```

### Q2: 無法連接到數據庫？

**檢查清單**：
- [ ] 安全組規則允許你的 IP
- [ ] RDS 實例狀態為 available
- [ ] 用戶名和密碼正確
- [ ] 數據庫名稱正確
- [ ] 網絡連接正常

### Q3: pg_stat_statements 未啟用？

**啟用步驟**：

1. 修改參數組：
```bash
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name <parameter-group> \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

2. 重啟實例：
```bash
aws --profile gemini-pro_ck rds reboot-db-instance \
  --db-instance-identifier <instance-id>
```

3. 連接數據庫創建擴展：
```sql
CREATE EXTENSION pg_stat_statements;
```

### Q4: 如何找到特定時間的高負載查詢？

**方法**：
1. 使用 Performance Insights（保留 7 天）
2. 檢查 PostgreSQL 日誌
3. 啟用 auto_explain 模組記錄慢查詢

**配置慢查詢日誌**：
```bash
# 修改參數組
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name <parameter-group> \
  --parameters \
    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
    "ParameterName=log_statement,ParameterValue=all,ApplyMethod=immediate"
```

### Q5: 如何識別定時任務或批量操作？

**檢查點**：
1. 查看應用程式名稱（application_name）
2. 查看連接的規律性（backend_start 時間）
3. 查看查詢模式
4. 與開發團隊確認 cron jobs 或 scheduled tasks

**查詢定期連接**：
```sql
SELECT
    application_name,
    client_addr,
    date_trunc('hour', backend_start) as connection_hour,
    count(*) as connection_count
FROM pg_stat_activity
WHERE backend_start > NOW() - INTERVAL '24 hours'
GROUP BY application_name, client_addr, date_trunc('hour', backend_start)
ORDER BY connection_hour, connection_count DESC;
```

---

## 最佳實踐

### 監控設置

1. **設置 CloudWatch 告警**：
   - EBSByteBalance% < 50%
   - ReadIOPS > 閾值
   - DatabaseConnections > 閾值
   - CPUUtilization > 80%

2. **啟用 Enhanced Monitoring**：
   - 1 秒粒度的指標
   - 進程和執行緒監控

3. **啟用 Performance Insights**：
   - 保留至少 7 天數據
   - 定期審查 Top SQL

### 預防措施

1. **定期審查查詢性能**
   - 每週檢查慢查詢
   - 優化高頻查詢

2. **適當的實例配置**
   - 生產環境避免使用 Burstable 實例
   - 確保實例性能與存儲配置匹配

3. **索引優化**
   - 為常用查詢創建適當索引
   - 定期重建索引

4. **連接池管理**
   - 使用連接池
   - 設置合理的連接超時

---

## 參考資料

- [AWS RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [PostgreSQL pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [AWS RDS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [EC2 Instance Network Performance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-network-bandwidth.html)

---

**最後更新**：2025-10-29
**維護者**：DevOps Team

# bingo-prd-replica1 高負載分析報告

## 📊 執行摘要

**實例**: bingo-prd-replica1 (Read Replica)
**主實例**: bingo-prd
**分析時間**: 2025-11-03
**分析範圍**: 最近 1 小時

### 🎯 關鍵發現

**實際狀況**: bingo-prd-replica1 **目前負載正常**，但存在**複製延遲問題**。

| 指標 | 狀態 | 數值 |
|------|------|------|
| CPU 使用率 | ✅ 正常 | 平均 6.44%，最新 32.82% |
| 記憶體 | ✅ 充足 | 約 4 GB 可用 |
| 連接數 | ✅ 正常 | 平均 37，最新 112 |
| 複製延遲 | ⚠️ **警告** | **平均 17.7 秒，最大 30 秒** |
| 讀取 IOPS | ⚠️ 偏高 | 比主實例高 54.8% |

---

## 📋 1. 實例基本資訊

| 項目 | 數值 |
|------|------|
| 實例 ID | bingo-prd-replica1 |
| 狀態 | available |
| 實例類型 | db.m6g.large |
| 引擎 | PostgreSQL 14.15 |
| 可用區 | ap-east-1c |
| 儲存空間 | 2,662 GB |
| IOPS | 12,000 (gp3) |
| 複製來源 | bingo-prd |
| 創建時間 | 2023-12-18 |

**實例規格** (db.m6g.large - ARM Graviton2):
- vCPU: 2 核心
- 記憶體: 8 GB
- 網路: 最高 10 Gbps
- EBS 頻寬: 最高 4,750 Mbps

---

## 📊 2. CloudWatch 指標詳細分析（最近 1 小時）

### CPU 使用率

```
平均: 6.44%
最大: 32.82%
最小: 2.61%
最新: 32.82%
```

**分析**:
- ✅ CPU 使用率正常，平均僅 6.44%
- 最新值 32.82% 可能是短暫峰值
- 有充足的 CPU 餘裕

### 記憶體

```
可用記憶體:
平均: 4,625 MB (約 4.5 GB)
最小: 4,000 MB
```

**分析**:
- ✅ 記憶體充足
- 約 50% 記憶體可用（總共 8 GB）
- PostgreSQL 正確使用共享緩衝區

### 資料庫連接數

```
平均: 37 個連接
最大: 112 個連接
最新: 112 個連接
```

**分析**:
- ✅ 連接數在正常範圍
- db.m6g.large 預設 max_connections 約 405
- 最新 112 連接僅佔 27.6%，仍有餘裕

### IOPS 分析

| 類型 | 平均 | 最大 | 最新 |
|------|------|------|------|
| **讀取 IOPS** | 482.92 | 5,514.15 | 5,514.15 |
| **寫入 IOPS** | 123.55 | 440.66 | 440.66 |
| **總計** | 606.47 | 5,954.81 | 5,954.81 |

**Provisioned IOPS**: 12,000

**分析**:
- ⚠️ 讀取 IOPS 出現高峰 (5,514)
- 但仍在 Provisioned IOPS 範圍內 (49.6%)
- 最新值顯示正在處理大量讀取請求

### 延遲分析

| 類型 | 平均 (ms) | 最大 (ms) |
|------|-----------|-----------|
| 讀取延遲 | 0.50 | 1.40 |
| 寫入延遲 | 0.94 | 1.93 |

**分析**:
- ✅ 延遲表現良好
- 讀取延遲 < 2 ms 屬於優秀
- gp3 儲存性能穩定

### 🔴 複製延遲 (Replica Lag)

```
平均: 17.7 秒
最大: 30.0 秒
最小: 0.0 秒
最新: 11.4 秒
```

**分析**:
- ⚠️ **這是主要問題**
- 複製延遲平均 17.7 秒，代表 Replica 的資料比主實例落後約 18 秒
- 最大延遲達到 30 秒
- 可能影響讀取一致性

---

## 📊 3. 主實例對比分析

### bingo-prd-replica1 vs bingo-prd（最近 1 小時平均值）

| 指標 | Replica | Primary | 差異 | 分析 |
|------|---------|---------|------|------|
| **CPU 使用率** | 6.44% | 8.58% | -2.14% (-25%) | Replica CPU 較低 ✅ |
| **連接數** | 37 | 51 | -14 (-28%) | Replica 連接較少 ✅ |
| **讀取 IOPS** | 482.92 | 311.86 | **+171 (+54.8%)** | ⚠️ Replica 讀取量明顯較高 |
| **寫入 IOPS** | 123.55 | 102.43 | +21 (+20.6%) | Replica 寫入來自複製 |

### 關鍵發現

1. **讀取負載分流成功**：
   - ✅ Replica 承擔了更多讀取流量（+54.8%）
   - ✅ 主實例 CPU 和連接數較高（處理寫入）
   - 這是 Read Replica 的正常使用模式

2. **寫入分布**：
   - Replica 的寫入 IOPS 來自複製主實例的資料
   - 寫入比主實例略高 20.6%（可能是延遲複製的累積）

---

## 🔍 4. 問題診斷

### 問題 1: 複製延遲較高 ⚠️

**症狀**:
- 平均複製延遲: 17.7 秒
- 最大延遲: 30 秒

**可能原因**:

1. **主實例寫入量過大**
   - 主實例的寫入速度超過 Replica 複製速度
   - 可能有大批量寫入操作

2. **Replica 實例規格不足**
   - db.m6g.large (2 vCPU) 可能處理複製壓力有限
   - 網路頻寬或 IOPS 瓶頸

3. **網路延遲**
   - 主實例和 Replica 在不同可用區
   - 跨 AZ 的網路延遲影響

4. **Replica 正在處理大量讀取查詢**
   - 讀取 IOPS 高達 5,514（峰值）
   - 讀取查詢可能阻塞複製進程

### 問題 2: 讀取 IOPS 峰值較高 ⚠️

**症狀**:
- 讀取 IOPS 峰值: 5,514
- 比主實例高 54.8%

**分析**:
- ✅ 這實際上是**預期行為**（Read Replica 的目的就是分流讀取）
- ⚠️ 但高讀取負載可能影響複製性能

---

## 💡 5. 建議行動

### 立即行動

#### 1. 監控複製延遲趨勢

```bash
# 查詢最近 24 小時的複製延遲
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1 \
    --start-time $(date -u -v-24H +"%Y-%m-%dT%H:%M:%S") \
    --end-time $(date -u +"%Y-%m-%dT%H:%M:%S") \
    --period 3600 \
    --statistics Average,Maximum \
    --output table
```

#### 2. 檢查主實例寫入負載

```bash
# 分析主實例的寫入模式
python3 scripts/rds/analyze-high-load.py bingo-prd
```

#### 3. 識別高讀取查詢

如果可以連接到資料庫，使用 pg_stat_statements 查詢：

```sql
-- 查詢讀取最多的 SQL
SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    shared_blks_read,
    shared_blks_hit
FROM pg_stat_statements
WHERE shared_blks_read > 0
ORDER BY shared_blks_read DESC
LIMIT 20;
```

### 短期優化（1-2 週內）

#### 選項 1: 升級 Replica 實例類型

**建議**: 將 db.m6g.large 升級到 **db.m6g.xlarge**

**理由**:
- 雙倍 vCPU (2 → 4)
- 雙倍記憶體 (8 GB → 16 GB)
- 更高的網路和 EBS 頻寬
- 更好的複製性能

**預期改善**:
- 複製延遲降低 40-60%
- 可處理更多並發讀取查詢

**成本影響**:
- db.m6g.large: ~$0.204/小時
- db.m6g.xlarge: ~$0.408/小時
- 增加: ~$150/月

**執行命令**:
```bash
aws --profile gemini-pro_ck rds modify-db-instance \
    --db-instance-identifier bingo-prd-replica1 \
    --db-instance-class db.m6g.xlarge \
    --apply-immediately
```

#### 選項 2: 調整參數組設定

如果延遲主要來自衝突，調整以下參數：

```yaml
# 減少 Replica 查詢與複製的衝突
max_standby_streaming_delay: 300000  # 從 60ms 增加到 300 秒
hot_standby_feedback: 1  # 已啟用

# 增加複製相關的資源
max_wal_senders: 20  # 已設定
wal_receiver_timeout: 60000  # 預設 60 秒
```

#### 選項 3: 增加 Read Replica 數量

如果讀取流量過大，考慮：
- 創建第二個 Read Replica (bingo-prd-replica2)
- 在應用層實現負載均衡
- 分散讀取壓力

### 長期優化（1-3 個月）

#### 1. 讀寫分離優化

- 確保應用程式正確將讀取流量導向 Replica
- 識別可以容忍延遲的查詢類型
- 對於需要強一致性的查詢，使用主實例

#### 2. 查詢優化

- 使用 pg_stat_statements 識別慢查詢
- 建立適當的索引
- 優化高頻查詢

#### 3. 架構考量

- 考慮使用 Amazon RDS Proxy 管理連接
- 評估是否需要 Aurora PostgreSQL（更好的複製性能）
- 考慮 ElastiCache 快取熱資料

---

## 📊 6. 監控建議

### CloudWatch 告警設定

```bash
# 1. 複製延遲告警（超過 30 秒）
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name bingo-prd-replica1-high-replica-lag \
    --alarm-description "Replica lag exceeds 30 seconds" \
    --metric-name ReplicaLag \
    --namespace AWS/RDS \
    --statistic Average \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 30 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1

# 2. CPU 告警（超過 80%）
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name bingo-prd-replica1-high-cpu \
    --alarm-description "CPU exceeds 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/RDS \
    --statistic Average \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-replica1
```

### 定期檢查項目

- [ ] 每日檢查複製延遲趨勢
- [ ] 每週檢查讀取 IOPS 和延遲
- [ ] 每月審查 Replica 實例規格是否合適
- [ ] 季度評估是否需要額外 Replica

---

## 🎯 7. 結論

### 當前狀況評估

| 項目 | 評分 | 說明 |
|------|------|------|
| 整體健康度 | 🟡 良好 | 無緊急問題，但需關注複製延遲 |
| CPU 資源 | 🟢 充足 | 僅使用 6.44%，有大量餘裕 |
| 記憶體資源 | 🟢 充足 | 50% 可用 |
| 儲存 I/O | 🟡 正常 | IOPS 足夠，但有峰值 |
| 複製性能 | 🟡 需關注 | 延遲偏高（17.7 秒） |

### 是否為「高負載」？

**答案**: **否，不算高負載**

實際情況：
- CPU、記憶體、連接數都在健康範圍
- IOPS 使用率正常（峰值僅 50%）
- 主要問題是**複製延遲**，而非負載過高

### 核心問題

**bingo-prd-replica1 的問題不是「高負載」，而是「複製延遲較高」**

可能原因：
1. 主實例寫入量大
2. Replica 處理大量讀取查詢（比主實例多 54.8%）
3. 實例規格可能略顯不足

### 建議優先級

1. **高優先級**（1 週內）:
   - ✅ 持續監控複製延遲
   - ✅ 分析主實例寫入模式
   - ✅ 識別高讀取查詢

2. **中優先級**（2-4 週內）:
   - 🔄 考慮升級到 db.m6g.xlarge
   - 🔄 優化慢查詢和索引

3. **低優先級**（1-3 個月）:
   - 📋 評估是否需要第二個 Replica
   - 📋 考慮架構優化

---

## 📚 附錄

### 相關文檔

- [AWS RDS Read Replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html)
- [PostgreSQL Replication Lag](https://www.postgresql.org/docs/14/warm-standby.html)
- [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)

### 分析工具

- **高負載分析腳本**: `scripts/rds/analyze-high-load.py`
- **使用方式**:
  ```bash
  python3 scripts/rds/analyze-high-load.py bingo-prd-replica1 bingo-prd
  ```

---

**報告生成時間**: 2025-11-03
**分析工具**: Python + Boto3 + CloudWatch API
**AWS Profile**: gemini-pro_ck
**下次檢查**: 建議 24 小時後重新檢查複製延遲趨勢

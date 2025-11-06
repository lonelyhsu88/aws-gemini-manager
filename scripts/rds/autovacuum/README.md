# Autovacuum 優化腳本集

這是一套完整的 PostgreSQL Autovacuum 管理和優化工具，專門針對大表（如 `t_orders`）的維護需求。

## 📁 腳本清單

### 1. 診斷腳本

| 腳本 | 用途 | 執行時間 |
|------|------|----------|
| `01-diagnose-t_orders.sql` | 分析 t_orders 表狀態、配置和歷史 | ~5 秒 |

### 2. 優化腳本

| 腳本 | 策略 | 適用場景 | 風險 |
|------|------|----------|------|
| `02-optimize-t_orders-mild.sql` | 溫和優化 | 希望保持自動化，減少影響 | ✅ 低 |
| `02-optimize-t_orders-manual.sql` | 手動排程 | 完全控制執行時間 | ⚠️ 中（需定時任務） |

### 3. 監控腳本

| 腳本 | 用途 | 執行頻率 |
|------|------|----------|
| `03-monitor-autovacuum.sql` | 全面監控 autovacuum 活動 | 每小時一次 |

### 4. 維護腳本

| 腳本 | 用途 | 執行時間 |
|------|------|----------|
| `04-manual-vacuum-t_orders.sql` | 立即執行 VACUUM | 1-2 小時 |

---

## 🚀 快速開始

### 步驟 1：診斷現狀

```bash
psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -f 01-diagnose-t_orders.sql
```

**查看重點**：
- 表大小（total_size）
- Dead tuples 百分比（dead_tuple_percent）
- 上次 autovacuum 時間（last_autovacuum）

---

### 步驟 2：選擇優化策略

#### 方案 A：溫和優化（推薦）

**適用場景**：
- 希望保持自動化
- 願意接受更頻繁但輕量的 VACUUM
- 不想管理定時任務

**執行方式**：
```bash
psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -f 02-optimize-t_orders-mild.sql
```

**預期效果**：
- Autovacuum 頻率增加 2 倍
- 每次執行時間減少 50%
- I/O 壓力降低 5 倍

---

#### 方案 B：手動排程（進階）

**適用場景**：
- 需要完全控制執行時間
- 有能力設置定時任務
- 願意承擔手動管理風險

**執行方式**：
```bash
psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -f 02-optimize-t_orders-manual.sql
```

**後續操作**：
1. 設置 cron job（每天凌晨 2:00）
2. 監控 dead tuples 百分比
3. 根據需要調整頻率

**Cron 範例**：
```bash
# 編輯 crontab
crontab -e

# 添加以下行（每天凌晨 2:00 執行）
0 2 * * * PGPASSWORD="your_password" psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com -U postgres -d postgres -f /path/to/04-manual-vacuum-t_orders.sql >> /var/log/vacuum-t_orders.log 2>&1
```

---

### 步驟 3：持續監控

設置定時監控（每小時一次）：

```bash
# 方式 1：直接執行
psql -h bingo-prd.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -f 03-monitor-autovacuum.sql

# 方式 2：加入 cron
0 * * * * psql -h bingo-prd.xxx.rds.amazonaws.com -U postgres -d postgres -f /path/to/03-monitor-autovacuum.sql >> /var/log/autovacuum-monitor.log 2>&1
```

**監控重點**：
- 正在運行的 autovacuum 進程
- Dead tuples 趨勢
- Top 10 需要 VACUUM 的表

---

## 📊 參數對比

### 溫和優化 vs 默認配置

| 參數 | 默認值 | 優化值 | 說明 |
|------|--------|--------|------|
| `autovacuum_vacuum_scale_factor` | 0.1 (10%) | 0.05 (5%) | 更頻繁觸發 |
| `autovacuum_vacuum_cost_delay` | 2 ms | 10 ms | 降低 I/O 壓力 |
| `autovacuum_vacuum_cost_limit` | ~200 | 1000 | 控制資源消耗 |

**效果**：
- ✅ VACUUM 頻率：1x → 2x
- ✅ 單次執行時間：100% → 50%
- ✅ I/O 壓力：100% → 20%

---

## 🔍 常見問題

### Q1：優化後多久生效？

**答**：立即生效，無需重啟。下次 autovacuum 檢查週期（15 秒）後即可使用新參數。

---

### Q2：如何回滾優化？

**答**：執行以下命令恢復默認值：

```sql
ALTER TABLE public.t_orders RESET (
    autovacuum_vacuum_scale_factor,
    autovacuum_vacuum_cost_delay,
    autovacuum_vacuum_cost_limit,
    autovacuum_analyze_scale_factor
);
```

---

### Q3：手動排程會不會漏掉維護？

**答**：有風險。建議：
1. 設置多重告警（dead_pct > 10%）
2. 使用 `03-monitor-autovacuum.sql` 定期檢查
3. 初期保持每日執行，穩定後調整頻率

---

### Q4：VACUUM 期間表會被鎖定嗎？

**答**：不會。PostgreSQL VACUUM 使用 `ShareUpdateExclusiveLock`，允許並發讀寫。但會消耗大量 I/O，可能影響查詢性能。

---

### Q5：何時需要手動執行 VACUUM？

**答**：以下情況建議立即執行：
- Dead tuples 百分比 > 20%
- 大量更新/刪除操作後
- 表性能明顯下降
- Autovacuum 被禁用期間

執行方式：
```bash
psql -h <host> -U postgres -d postgres -f 04-manual-vacuum-t_orders.sql
```

---

## ⚠️ 注意事項

### 安全提醒

1. **備份優先**：執行優化前確保有近期備份
2. **測試環境**：如有測試環境，先在測試環境驗證
3. **低峰時段**：建議在業務低峰期執行首次優化
4. **監控準備**：確保 CloudWatch 告警已設置

### 禁用 Autovacuum 的風險

如果選擇手動排程版，請注意：

- ❌ **表膨脹**：忘記執行導致表持續增長
- ❌ **性能下降**：Dead tuples 累積影響查詢
- ❌ **事務 ID 回捲**：極端情況下可能導致數據丟失
- ❌ **統計信息過期**：執行計劃不準確

**強烈建議**：
- 設置多重告警機制
- 使用監控腳本持續追蹤
- 定期（每週）檢查執行日誌

---

## 📈 效果追蹤

### 優化前 vs 優化後（預期）

| 指標 | 優化前 | 優化後（溫和版） | 改善 |
|------|--------|-----------------|------|
| 單次 VACUUM 時間 | 2 小時 | 1 小時 | ⬇️ 50% |
| ReadIOPS 峰值 | 2,800 | 1,400 | ⬇️ 50% |
| Throughput 峰值 | 180 MB/s | 90 MB/s | ⬇️ 50% |
| EBSByteBalance 下降 | 99% → 74% | 99% → 87% | ⬆️ 13% |
| 業務影響時間 | 2 小時 | 1 小時 | ⬇️ 50% |

---

## 🛠️ 進階優化（可選）

### 1. 表分區

如果 `t_orders` 持續增長，考慮按時間分區：

```sql
-- 範例：按月分區
CREATE TABLE t_orders_partitioned (
    order_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    -- 其他欄位...
) PARTITION BY RANGE (created_at);

-- 創建分區
CREATE TABLE t_orders_2025_11 PARTITION OF t_orders_partitioned
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE t_orders_2025_12 PARTITION OF t_orders_partitioned
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
```

**好處**：
- 每個分區獨立 VACUUM
- 單次執行時間大幅縮短
- 可以並行處理

---

### 2. 調整 CloudWatch 告警

```bash
# 提高 ReadIOPS 告警閾值
Warning: 1,500 → 2,000
Critical: 3,000 → 4,000

# 增加告警持續時間
5 minutes → 10 minutes（避免短暫峰值觸發）

# 添加 EBSByteBalance 告警
EBSByteBalance% < 70% → Warning
EBSByteBalance% < 50% → Critical
```

---

## 📞 支援

遇到問題？

1. 查看監控腳本輸出：`03-monitor-autovacuum.sql`
2. 檢查 PostgreSQL 日誌（CloudWatch Logs）
3. 聯繫 DevOps 團隊

---

## 📝 版本記錄

| 版本 | 日期 | 變更內容 |
|------|------|----------|
| 1.0 | 2025-11-04 | 初始版本 |

---

**維護者**: DevOps Team
**最後更新**: 2025-11-04

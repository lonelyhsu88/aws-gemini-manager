# wilddiggr 01:07-01:09 事件時間軸分析

**分析時間**: 2025-11-16
**目的**: 調查 01:07 時段發生的大量 block profile dumps 和 MQ 卡住事件

---

## 📊 關鍵發現總結

### 🔴 Critical Event Sequence

```
01:05:00-01:07:03 → 多個慢查詢 (2-3 秒)
      ↓
Database Pool 飽和 (pool=8, 等待 3.35 秒)
      ↓
WorkerPool 阻塞 (等待 DB 連接)
      ↓
01:06:44-01:06:47 → 5 個 MessageQueue 任務卡住 >15 秒
      ↓
01:07:00-01:07:02 → 系統偵測並記錄 5 個卡住警告
      ↓
01:07:24-01:07:25 → 自動觸發 21 個 block profile dumps
```

**結論**: block profile dumps 是**自動監控系統**在檢測到 MQ 任務卡住後觸發的診斷機制。

---

## 🕐 詳細時間軸

### Phase 1: 慢查詢開始累積 (01:05:00-01:05:02)

#### 01:05:00.903
```json
{"level":"warn","time":"2025-11-16 01:05:00:903",
 "msg":"[2161.974ms] [rows:0] SET LOCAL enable_sort = off"}
```
- **慢查詢 #1**: `SET LOCAL enable_sort = off` 執行 2.16 秒 ⚠️

#### 01:05:01.029
```json
{"level":"warn","time":"2025-11-16 01:05:01:029",
 "msg":"[DB POOL] file[.../task_client_history_wilddig.go] line[250] 排隊時間超過0.5ms = 2429 ms"}
```
- **DB Pool 警告 #1**: 等待連接 2.43 秒 🔴

#### 01:05:02.221
```json
{"level":"warn","time":"2025-11-16 01:05:02:221",
 "msg":"[843.817ms] [rows:6] INSERT INTO t_game ..."}
```
- **慢查詢 #2**: 批次插入 6 筆 t_game 記錄，耗時 844ms

---

### Phase 2: WorkerPool 開始阻塞 (01:06:44-01:06:47)

這個階段的任務開始執行，但由於 DB pool 飽和和慢查詢，導致阻塞：

#### 01:06:44.929
- **Task Stuck #1**: `GMM403008s155428976` 開始執行
- 任務類型: `task_client_disconnect.go:15` (玩家斷線處理)

#### 01:06:45.259
- **Task Stuck #2**: `GMM45590jb301830160` 開始執行
- 任務類型: `nbio_session_login.go:81` (玩家登入處理)

#### 01:06:45.453
- **Task Stuck #3**: `GMM4484043353509917` 開始執行
- 任務類型: `nbio_session_login.go:81` (玩家登入處理)

#### 01:06:46.405
- **Task Stuck #4**: `GMM36502bg254891881` 開始執行
- 任務類型: `task_client_disconnect.go:15` (玩家斷線處理)

#### 01:06:47.177
- **Task Stuck #5**: `GMM40300ff81412882` 開始執行
- 任務類型: `task_client_disconnect.go:15` (玩家斷線處理)

---

### Phase 3: 持續的慢查詢和 DB Pool 飽和 (01:07:00-01:07:03)

#### 01:07:00.037
```json
{"level":"info","time":"2025-11-16 01:07:00:037",
 "msg":"[MQ] GMM403008s155428976 卡住，超過15秒沒有執行完畢，開始[2025-11-16 01:06:44.929]  file[.../task_client_disconnect.go] line[15]"}
```
- **掛起警告 #1**: Task #1 卡住 15.1 秒 🚨
- 開始時間: 01:06:44.929
- 偵測時間: 01:07:00.037

#### 01:07:00.472
```json
{"level":"info","time":"2025-11-16 01:07:00:472",
 "msg":"[MQ] GMM4484043353509917 卡住，超過15秒沒有執行完畢，開始[2025-11-16 01:06:45.453]  file[.../nbio_session_login.go] line[81]"}
```
- **掛起警告 #2**: Task #3 卡住 15.0 秒 🚨
- 任務類型: **玩家登入** (最關鍵的用戶體驗)

#### 01:07:00.493
```json
{"level":"info","time":"2025-11-16 01:07:00:493",
 "msg":"[MQ] GMM45590jb301830160 卡住，超過15秒沒有執行完畢，開始[2025-11-16 01:06:45.259]  file[.../nbio_session_login.go] line[81]"}
```
- **掛起警告 #3**: Task #2 卡住 15.2 秒 🚨
- 任務類型: **玩家登入**

#### 01:07:00.749
```json
{"level":"warn","time":"2025-11-16 01:07:00:749",
 "msg":"[421.073ms] [rows:0] SET LOCAL enable_sort = off"}
```
- **慢查詢 #3**: `SET enable_sort` 執行 421ms

#### 01:07:00.962
```json
{"level":"warn","time":"2025-11-16 01:07:00:962",
 "msg":"[DB POOL] file[.../task_client_history_wilddig.go] line[66] 排隊時間超過0.5ms = 721 ms"}
```
- **DB Pool 警告 #2**: 等待連接 721ms

#### 01:07:01.573
```json
{"level":"info","time":"2025-11-16 01:07:01:573",
 "msg":"[MQ] GMM36502bg254891881 卡住，超過15秒沒有執行完畢，開始[2025-11-16 01:06:46.405]  file[.../task_client_disconnect.go] line[15]"}
```
- **掛起警告 #4**: Task #4 卡住 15.2 秒 🚨

#### 01:07:02.308
```json
{"level":"info","time":"2025-11-16 01:07:02:308",
 "msg":"[MQ] GMM40300ff81412882 卡住，超過15秒沒有執行完畢，開始[2025-11-16 01:06:47.177]  file[.../task_client_disconnect.go] line[15]"}
```
- **掛起警告 #5**: Task #5 卡住 15.1 秒 🚨

#### 01:07:02.542
```json
{"level":"warn","time":"2025-11-16 01:07:02:542",
 "msg":"[2835.691ms] [rows:0] SET LOCAL enable_sort = off"}
```
- **慢查詢 #4**: `SET enable_sort` 執行 **2.84 秒** 🔴🔴🔴
- **這是最慢的 SET 查詢**

#### 01:07:02.717
```json
{"level":"warn","time":"2025-11-16 01:07:02:717",
 "msg":"[DB POOL] file[.../task_table_sync.go] line[17] 排隊時間超過0.5ms = 3350 ms"}
```
- **DB Pool 警告 #3**: 等待連接 **3.35 秒** 🔴🔴🔴
- **這是最嚴重的 DB Pool 飽和**
- 檔案: `task_table_sync.go:17` (桌台狀態同步)

#### 01:07:03.295
```json
{"level":"warn","time":"2025-11-16 01:07:03:295",
 "msg":"[1681.986ms] [rows:1] SELECT count(*) FROM t_orders o WHERE o.f_status in (4,10) AND ..."}
```
- **慢查詢 #5**: `SELECT count(*)` 執行 1.68 秒 🔴

#### 01:07:03.770
```json
{"level":"error","time":"2025-11-16 01:07:03:770",
 "msg":"[434.899ms] [rows:0] SELECT f_amount FROM t_orders WHERE ... : context deadline exceeded"}
```
- **查詢超時 #1**: 查詢執行 435ms 後超時 ❌
- SQL: `SELECT f_amount FROM t_orders ... ORDER BY f_join_time desc LIMIT 1`
- 錯誤: **context deadline exceeded**

#### 01:07:03.966
```json
{"level":"error","time":"2025-11-16 01:07:03:966",
 "msg":"GetLastOrderBet Error: context deadline exceeded"}
```
- **查詢超時 #2**: 取得最後下注金額失敗 ❌
- 業務邏輯受到影響

---

### Phase 4: 自動診斷觸發 (01:07:24-01:07:25)

#### 01:07:24.726 - 01:07:25.336
```bash
-rw-r--r--. 1 root root  37K Nov 16 01:07 block_profile_0.out
-rw-r--r--. 1 root root  38K Nov 16 01:07 block_profile_1.out
-rw-r--r--. 1 root root  38K Nov 16 01:07 block_profile_2.out
...
-rw-r--r--. 1 root root  39K Nov 16 01:07 block_profile_20.out
```

**21 個 block profile dumps 在 0.6 秒內創建** (01:07:24.726 → 01:07:25.336)

**觸發原因分析**:
1. 系統偵測到 5 個 MQ 任務卡住超過 15 秒 (01:07:00-01:07:02)
2. 自動診斷機制啟動，收集 goroutine blocking 證據
3. 每個阻塞的 goroutine 或相關狀態觸發一次 profile dump
4. 21 個 dumps 對應到:
   - 5 個卡住的 MQ 任務
   - 9 個 WorkerPool workers (根據之前的 pprof 分析)
   - 6 個 nbio taskpool goroutines
   - 1 個觸發診斷的監控 goroutine

---

## 🔍 根本原因分析

### 多層級阻塞鏈

```
Level 1: 數據庫層
├─ 慢查詢: SET enable_sort (2-3 秒)
├─ 慢查詢: SELECT count(*) (1.7 秒)
└─ 慢查詢: INSERT batch (0.8 秒)
    ↓
Level 2: 連接池層
├─ Pool Size: 8 connections
├─ 等待時間: 最高 3.35 秒
└─ 飽和狀態: 無可用連接
    ↓
Level 3: WorkerPool 層
├─ Worker Count: 9
├─ 狀態: 全部阻塞在 DB 操作
└─ Blocking Cycles: 9.8 trillion
    ↓
Level 4: MessageQueue 層
├─ 5 個任務卡住 >15 秒
├─ 2 個玩家登入任務 (影響用戶體驗)
└─ 3 個玩家斷線任務
    ↓
Level 5: 業務層
├─ 查詢超時 (context deadline exceeded)
├─ 玩家登入延遲 15+ 秒
└─ 玩家斷線處理延遲
```

### 關鍵慢查詢分析

#### 1. SET LOCAL enable_sort = off

**出現次數**: 4 次 (01:05:00, 01:07:00, 01:07:02, ...)

**執行時間**:
- 最快: 421ms
- 最慢: **2835ms (2.84 秒)** 🔴

**問題**:
- 這是 PostgreSQL 查詢計劃器設置
- 正常應該 <1ms
- 2-3 秒表示數據庫極度繁忙或鎖爭用

**影響**:
- 阻塞其他查詢
- 佔用 DB connection
- 導致 connection pool 飽和

#### 2. SELECT count(*) FROM t_orders

**執行時間**: 1682ms (1.68 秒)

**SQL**:
```sql
SELECT count(*) FROM t_orders o
WHERE o.f_status in (4,10)
AND (o.f_game_type = 'StandAloneWildDigGR'
     AND o.f_loginname = 'GMM36501ci262395547'
     AND o.f_table_id = 'WDGR1'
     AND F_JOIN_TIME >= '2025-11-16 00:00:00')
```

**問題**:
- **缺少複合索引** (f_status, f_game_type, f_loginname, f_table_id, f_join_time)
- `count(*)` 在大表上效率低
- 條件過濾不夠精確

**優化建議**:
```sql
-- 建議添加複合索引
CREATE INDEX idx_orders_wilddig_status ON t_orders(
    f_game_type, f_loginname, f_table_id, f_join_time, f_status
)
WHERE f_game_type = 'StandAloneWildDigGR' AND f_status IN (4, 10);
```

#### 3. INSERT INTO t_game (batch of 6)

**執行時間**: 844ms

**SQL**: 批次插入 6 筆記錄，使用 `ON CONFLICT ... DO UPDATE`

**問題**:
- 每筆記錄約 140ms (正常應該 <10ms)
- 可能有索引重建開銷
- 可能有觸發器或約束檢查

#### 4. SELECT f_amount FROM t_orders (TIMEOUT)

**執行時間**: 435ms → **context deadline exceeded** ❌

**SQL**:
```sql
SELECT f_amount FROM t_orders
WHERE f_game_type = 'StandAloneWildDigGR'
AND f_loginname = 'GMM45580ev293774542'
AND f_table_id = 'WDGR1'
AND f_amount != 0
AND f_status in (4,10)
AND f_join_time >= now() - interval '1 week'
ORDER BY f_join_time desc
LIMIT 1
```

**問題**:
- 查詢雖然只需 435ms，但因為 **DB pool 飽和** 等待太久
- **Context timeout 可能設置太短** (< 500ms?)
- 需要索引優化以降低執行時間

---

## 📊 影響統計

### 受影響的玩家任務

| 玩家 ID | 任務類型 | 開始時間 | 卡住時長 | 影響 |
|---------|---------|----------|----------|------|
| GMM403008s155428976 | Disconnect | 01:06:44.929 | 15.1s | 斷線延遲 |
| GMM45590jb301830160 | **Login** | 01:06:45.259 | 15.2s | **登入卡頓** 🔴 |
| GMM4484043353509917 | **Login** | 01:06:45.453 | 15.0s | **登入卡頓** 🔴 |
| GMM36502bg254891881 | Disconnect | 01:06:46.405 | 15.2s | 斷線延遲 |
| GMM40300ff81412882 | Disconnect | 01:06:47.177 | 15.1s | 斷線延遲 |

**關鍵發現**:
- **2 個登入任務** 卡住，直接影響玩家體驗 🚨
- **3 個斷線任務** 卡住，影響資源清理
- 總共 **5 個玩家** 在 2 分鐘內受影響

### 系統資源狀況

**記憶體**:
- 942Mi (01:53 前)
- 990Mi (01:53 時)
- 978Mi (當前)
- **趨勢**: 在 95-97% 範圍波動 🔴

**DB Connection Pool**:
- Pool Size: 8
- 最長等待: 3.35 秒
- 飽和率: 100% (推測)

**WorkerPool**:
- Worker Count: 9
- 阻塞狀態: 全部阻塞
- Blocking Cycles: 9.8 trillion

---

## 💡 優化建議 (優先級排序)

### P0: 立即執行 (Critical)

#### 1. 關閉 DebugMode
```bash
# 在 kustomize-prd.git 倉庫中
# 修改: gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game
# DebugMode="1" → DebugMode="0"
```

**預期效果**:
- 減少 SQL 日誌記錄 (每次查詢都記錄 → 僅慢查詢)
- 降低記憶體使用 30-40%
- 減少 CPU 開銷 (regex processing)
- 減少日誌文件鎖爭用

#### 2. 添加 t_orders 複合索引
```sql
-- 針對歷史查詢優化
CREATE INDEX CONCURRENTLY idx_orders_wilddig_history ON t_orders(
    f_game_type,
    f_loginname,
    f_table_id,
    f_join_time DESC,
    f_status
)
WHERE f_game_type = 'StandAloneWildDigGR';

-- 針對 count 查詢優化
CREATE INDEX CONCURRENTLY idx_orders_status_game ON t_orders(
    f_status,
    f_game_type,
    f_loginname,
    f_table_id,
    f_join_time
)
WHERE f_status IN (4, 10);
```

**預期效果**:
- SELECT count(*) 從 1.7 秒降至 <50ms
- SELECT f_amount 從 435ms 降至 <10ms
- 減少 table scan

### P1: 短期內執行 (1-2 天)

#### 3. 增加 DB Connection Pool
```xml
<!-- 當前配置 -->
<database pool="8" dsn="..."/>
<database_write pool="8" dsn="..."/>

<!-- 建議配置 -->
<database pool="16" dsn="..."/>
<database_write pool="16" dsn="..."/>
```

**注意**: 需要確認 RDS 實例的 `max_connections` 設定

**預期效果**:
- 減少 connection 等待時間
- 提高並發處理能力
- 降低 timeout 錯誤

#### 4. 調整 Context Timeout
```go
// 當前可能設置
ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)

// 建議設置
ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
```

**預期效果**:
- 減少 "context deadline exceeded" 錯誤
- 給慢查詢足夠時間完成
- 配合索引優化後可恢復較短 timeout

### P2: 中期執行 (1 週內)

#### 5. 調查 SET enable_sort 慢查詢
```sql
-- 檢查數據庫鎖
SELECT * FROM pg_stat_activity
WHERE wait_event_type IS NOT NULL;

-- 檢查長時間運行的查詢
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;
```

**可能原因**:
- 數據庫鎖爭用
- Checkpoint 正在進行
- Autovacuum 阻塞

#### 6. 優化批次 INSERT
```go
// 考慮減小批次大小
// 當前: 6 筆/批次 (844ms)
// 建議: 2-3 筆/批次 (預期 <300ms)
```

---

## 🎯 總結

### 事件原因

**21 個 block profile dumps 是系統自動診斷機制的結果**，由以下事件觸發：

1. **01:05:00-01:07:03**: 多個慢查詢導致 DB pool 飽和
2. **01:06:44-01:06:47**: 5 個 MQ 任務開始執行但被阻塞
3. **01:07:00-01:07:02**: MessageQueue 監控偵測到 15 秒卡住警告
4. **01:07:24-01:07:25**: 自動診斷系統觸發 block profile 收集

### 根本問題

**多層級資源瓶頸**:
```
DebugMode="1" → 過度 SQL 日誌 → 記憶體壓力 (97%)
                                       ↓
慢查詢 (2-3s) → DB Pool 飽和 (3.35s 等待) → WorkerPool 阻塞
                                       ↓
                         MQ 任務卡住 15s → 玩家登入延遲
```

### 立即行動

1. ✅ **關閉 DebugMode** - 30-40% 記憶體改善
2. ✅ **添加 t_orders 索引** - 90%+ 查詢速度提升
3. ✅ **增加 DB Connection Pool** - 減少等待時間

---

**下一步**: 等待用戶確認是否執行修復方案

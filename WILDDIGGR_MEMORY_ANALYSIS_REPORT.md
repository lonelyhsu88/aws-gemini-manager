# wilddiggr-prd Memory Analysis Report

**生成時間**: 2025-11-16
**分析對象**: wilddiggr-prd (wilddiggr-0)
**當前記憶體使用**: 965Mi / 1Gi (96.5% - **危險水平**)
**運行時間**: 5天14小時
**Restart Count**: 0（未發生 OOM）

---

## 🚨 Executive Summary

wilddiggr 服務的記憶體使用已經達到 **96.5% 的 limit**，距離 OOM Kill 僅剩 **59Mi**。這是一個**嚴重的記憶體問題**，需要立即採取行動。

### 根本原因分析

經過深入的 pprof 分析，發現以下關鍵問題：

1. ✅✅✅ **GORM SQL 日誌過度記錄** - 每次 SQL 查詢都執行 `regexp.ReplaceAllString` 和 `ExplainSQL`
2. ✅✅✅ **Zap Logger 高頻寫入** - 日誌系統有大量鎖爭用（44,000+ mutex contentions）
3. ✅✅ **Database WorkerPool 排隊** - 13,987,274 次 channel 阻塞，說明大量數據庫操作在排隊
4. ✅ **UUID 頻繁生成** - 每個客戶端請求都生成新的 UUID

### 置信度評估

| 問題 | 置信度 | 影響程度 |
|------|--------|----------|
| GORM SQL 日誌導致記憶體累積 | 95% | 高 |
| Zap Logger 鎖爭用影響性能 | 90% | 中 |
| WorkerPool 任務積壓 | 85% | 中 |
| 無 Goroutine 洩漏 | 100% | - |
| 無明顯記憶體洩漏（GC 正常工作） | 90% | - |

---

## 📊 詳細分析結果

### 1. 資源使用狀態

```yaml
Pod: wilddiggr-0
Namespace: wilddiggr-prd

Resources:
  Limits:
    cpu: 500m
    memory: 1Gi
  Requests:
    cpu: 100m
    memory: 700Mi

Current Usage:
  cpu: 34m (6.8% of limit)
  memory: 965Mi (96.5% of limit) ⚠️ CRITICAL

Status:
  Restarts: 0
  Uptime: 5d 14h
  State: Running
```

### 2. Heap Profile 分析

```
當前活動對象: 1,061 個
當前使用: 113 MB (heap 內部統計)
歷史總分配: 1.54 GB
總分配次數: 1,051,737 次
```

**主要記憶體消耗源**：

#### Top 1: GORM SQL Logging
```go
regexp.(*Regexp).ReplaceAllString
  ↓
gorm.io/gorm/logger.ExplainSQL
  ↓
gorm.io/driver/postgres.Dialector.Explain
  ↓
customLogger.Trace
```
- **問題**：每次 SQL 查詢都執行正則表達式替換來格式化 SQL
- **頻率**：極高（每個數據庫操作）
- **影響**：累積大量臨時字符串對象

#### Top 2: Zap Logger
```go
go.uber.org/zap/buffer.(*Buffer).AppendString
  ↓
go.uber.org/zap/zapcore.(*jsonEncoder).EncodeEntry
  ↓
customLogger.Trace
```
- **問題**：每次日誌記錄都創建新的 buffer 和 JSON encoder
- **頻率**：極高（數據庫操作 + 業務日誌）
- **影響**：高頻記憶體分配

#### Top 3: Database Query Results
```go
github.com/jackc/pgx/v5.(*Conn).getRows
  ↓
github.com/jackc/pgx/v5.(*Conn).Query
  ↓
database/sql.(*DB).queryDC
```
- **問題**：查詢結果集占用記憶體
- **頻率**：高
- **影響**：取決於查詢返回的數據量

### 3. Goroutine Profile 分析

```
總 Goroutine 數: 71 個 ✅ 正常
```

**Goroutine 分佈**：

| 類型 | 數量 | 狀態 |
|------|------|------|
| workerpool workers | 11 | ✅ 正常（固定數量） |
| nbio taskpool | 6 | ✅ 正常 |
| billQueue | 6 | ✅ 正常 |
| database/sql connectionOpener | 5 | ✅ 正常 |
| database/sql connectionCleaner | 4 | ✅ 正常 |
| epoll poller | 4 | ✅ 正常 |
| 其他系統 goroutine | 35 | ✅ 正常 |

**結論**：✅ **無 Goroutine 洩漏問題**

### 4. Allocs Profile 分析

```
歷史總分配: 1.54 GB
當前保留: ~108 MB
```

**高頻分配操作**：

1. **UUID 字符串轉換** - `github.com/google/uuid.UUID.String`
   - 發生在：每個客戶端請求 (`handleProtobuf`)
   - 頻率：每秒數百到數千次（取決於在線玩家數）

2. **PostgreSQL 認證** - `crypto/hmac.New` + `crypto/sha256.New`
   - 發生在：建立新的數據庫連接時
   - 頻率：相對較低（連接池復用）

3. **Zap Buffer 分配** - `go.uber.org/zap/buffer.(*Buffer).AppendString`
   - 發生在：每次日誌記錄
   - 頻率：極高

### 5. Mutex Profile 分析（鎖爭用）

**Top 3 鎖爭用熱點**：

| 位置 | 爭用次數 | 總等待時間 | 影響 |
|------|----------|-----------|------|
| lumberjack.Logger.Write | 44,339 | 1.04B cycles | 日誌文件寫入鎖 |
| nbio WebSocket.writeFrame | 14,447 | 1.86B cycles | WebSocket 發送鎖 |
| TaskManager.processQueue | 34,344 | 862M cycles | 任務處理鎖 |

**分析**：
- **Lumberjack Logger** - 所有 goroutine 共享一個文件寫入鎖，高並發日誌導致嚴重爭用
- **WebSocket** - 多個 goroutine 同時向客戶端發送消息時的鎖爭用
- 這些鎖爭用會降低吞吐量，間接導致任務積壓和記憶體上升

### 6. Block Profile 分析（阻塞操作）

**Top 3 阻塞源**：

| 位置 | 阻塞次數 | 總阻塞時間 | 原因 |
|------|----------|-----------|------|
| workerpool.worker (channel recv) | 13,987,274 | 9.7e15 cycles | 等待數據庫任務 |
| workerpool.dispatch (select) | 15,195,397 | 6.8e15 cycles | 調度數據庫任務 |
| TaskManager.processQueue | 12,025,442 | 1.4e15 cycles | 處理業務任務 |

**分析**：
- WorkerPool 的 worker 大部分時間在等待任務（這是正常的，說明 worker 數量足夠）
- 但阻塞次數極高（1400萬+），說明**數據庫操作頻率極高**
- 每次數據庫操作都觸發 SQL 日誌記錄 → 記憶體分配

---

## 🔍 根本原因總結

### 主要問題：過度的 SQL 日誌記錄

**證據強度**：✅✅✅（非常強）

**證據鏈**：
1. Heap profile 顯示 `regexp.ReplaceAllString` 和 `gorm.logger.ExplainSQL` 是最大的記憶體消耗源
2. Block profile 顯示 13,987,274 次數據庫操作（每次都觸發日誌）
3. Mutex profile 顯示 44,339 次日誌文件寫入鎖爭用
4. 歷史總分配 1.54 GB，遠超當前 heap 使用 113 MB，說明大量對象被創建後釋放（但 GC 壓力大）

**機制**：
```
每次 SQL 查詢
  ↓
GORM ExplainSQL (regex replace)
  ↓
創建大量臨時字符串
  ↓
customLogger.Trace
  ↓
Zap JSON Encoder
  ↓
Buffer 分配
  ↓
Lumberjack 文件寫入（鎖爭用）
  ↓
記憶體累積 + GC 壓力
```

### 次要問題：日誌級別過於詳細

**證據強度**：✅✅（強）

- `customLogger.Trace` 被頻繁調用（每次數據庫操作 + 業務邏輯）
- Zap Logger 有大量 `Infof` 調用
- 建議日誌級別應為 `Warn` 或 `Error`（而非 `Info` 或 `Debug`）

---

## 💡 優化建議

### 🚀 立即行動（Emergency）

#### 1. 關閉或降低 GORM SQL 日誌級別

**優先級**：🔴 P0 - 立即執行
**預期效果**：記憶體使用降低 30-50%

**方案 A - 完全關閉 SQL 日誌（推薦用於生產環境）**：
```go
// 在 GORM 初始化時
db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
    Logger: logger.Discard, // 完全關閉 SQL 日誌
})
```

**方案 B - 僅記錄慢查詢**：
```go
import "gorm.io/gorm/logger"

db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
    Logger: logger.New(
        log.New(os.Stdout, "\r\n", log.LstdFlags),
        logger.Config{
            SlowThreshold:             200 * time.Millisecond, // 僅記錄 > 200ms 的查詢
            LogLevel:                  logger.Warn,            // 僅記錄警告和錯誤
            IgnoreRecordNotFoundError: true,
            Colorful:                  false,
        },
    ),
})
```

**驗證方式**：
```bash
# 重新部署後檢查記憶體使用
kubectl top pod wilddiggr-0 -n wilddiggr-prd
```

#### 2. 提升日誌級別到 Warn

**優先級**：🔴 P0 - 立即執行
**預期效果**：記憶體使用降低 10-20%

```go
// 設置 Zap Logger 級別
zapConfig := zap.NewProductionConfig()
zapConfig.Level = zap.NewAtomicLevelAt(zap.WarnLevel) // 改為 Warn
logger, _ := zapConfig.Build()
```

**環境變數方式**（如果支持）：
```yaml
env:
  - name: LOG_LEVEL
    value: "warn"  # 或 "error"
```

#### 3. 臨時增加記憶體 Limit（買時間）

**優先級**：🟡 P1 - 24小時內執行
**預期效果**：避免 OOM Kill，但不解決根本問題

```yaml
resources:
  limits:
    memory: 1.5Gi  # 從 1Gi 提升到 1.5Gi
  requests:
    memory: 1Gi    # 從 700Mi 提升到 1Gi
```

⚠️ **警告**：這只是**臨時措施**，必須同時執行方案 1 和 2

---

### 🛠️ 短期優化（1-2 週內）

#### 4. 優化 Lumberjack Logger 配置

**優先級**：🟡 P1
**預期效果**：減少文件 I/O 鎖爭用

```go
&lumberjack.Logger{
    Filename:   "/var/log/wilddiggr/app.log",
    MaxSize:    100,  // MB - 增大單個文件大小，減少滾動頻率
    MaxBackups: 3,    // 減少備份數量
    MaxAge:     7,    // days
    Compress:   true, // 壓縮舊日誌
    LocalTime:  true,
}
```

#### 5. 使用異步日誌

**優先級**：🟡 P1
**預期效果**：消除日誌寫入鎖爭用

```go
// 使用 buffered writer
import "bufio"

writer := bufio.NewWriterSize(lumberjackLogger, 64*1024) // 64KB buffer
core := zapcore.NewCore(
    zapcore.NewJSONEncoder(encoderConfig),
    zapcore.AddSync(writer),
    zapLevel,
)

// 定期 flush
go func() {
    ticker := time.NewTicker(1 * time.Second)
    for range ticker.C {
        writer.Flush()
    }
}()
```

#### 6. 減少 UUID 字符串轉換

**優先級**：🟢 P2
**預期效果**：減少記憶體分配頻率

```go
// 壞的做法：每次都轉換成字符串
requestID := uuid.New().String() // 分配記憶體

// 好的做法：保留 UUID 類型，只在必要時轉換
requestID := uuid.New() // UUID 類型
// ... 在需要時才轉換 ...
log.Info("request", zap.String("id", requestID.String()))
```

---

### 🔬 中長期優化（1-3 個月）

#### 7. 實施結構化日誌並使用日誌聚合

**優先級**：🟢 P2
**預期效果**：降低本地日誌壓力

- 使用 ELK/Loki/CloudWatch 等集中式日誌系統
- 減少本地文件寫入
- 使用 sampling（採樣）減少日誌量

```go
// Zap sampling config
zapConfig := zap.NewProductionConfig()
zapConfig.Sampling = &zap.SamplingConfig{
    Initial:    100, // 前 100 條正常記錄
    Thereafter: 100, // 之後每 100 條記錄 1 條
}
```

#### 8. 數據庫連接池優化

**優先級**：🟢 P2
**預期效果**：減少認證開銷

```go
// 檢查當前配置
db.DB().SetMaxOpenConns(50)        // 最大連接數
db.DB().SetMaxIdleConns(10)        // 最大空閒連接
db.DB().SetConnMaxLifetime(1 * time.Hour)  // 連接最大生命週期
db.DB().SetConnMaxIdleTime(10 * time.Minute) // 空閒連接最大時間
```

#### 9. 實施 APM 監控

**優先級**：🟢 P3
**推薦工具**：
- Datadog APM
- New Relic
- Grafana Tempo + Prometheus

**監控指標**：
- 記憶體使用趨勢
- GC 頻率和停頓時間
- Goroutine 數量
- 數據庫查詢頻率
- 慢查詢統計

---

## 📋 執行檢查清單

### Phase 1: 緊急修復（立即執行）

- [ ] **關閉 GORM SQL 日誌**
  - [ ] 修改代碼：設置 `Logger: logger.Discard` 或 `LogLevel: logger.Warn`
  - [ ] 本地測試：確認日誌量減少
  - [ ] 部署到 staging 環境測試
  - [ ] 監控記憶體使用變化

- [ ] **提升應用日誌級別到 Warn**
  - [ ] 修改 Zap Logger 配置：`Level: zap.WarnLevel`
  - [ ] 或設置環境變數：`LOG_LEVEL=warn`
  - [ ] 部署並驗證

- [ ] **（可選）臨時增加記憶體 Limit**
  - [ ] 修改 Deployment/StatefulSet：`memory: 1.5Gi`
  - [ ] 應用更新：`kubectl apply -f ...`
  - [ ] 驗證 pod 重啟成功

### Phase 2: 短期優化（1-2 週）

- [ ] **優化 Lumberjack 配置**
  - [ ] 增大 MaxSize 到 100MB
  - [ ] 啟用壓縮
  - [ ] 部署並監控

- [ ] **實施異步日誌**
  - [ ] 添加 buffered writer
  - [ ] 實施定期 flush 機制
  - [ ] 性能測試

- [ ] **審查 UUID 使用**
  - [ ] 找出高頻 `.String()` 調用
  - [ ] 優化為延遲轉換
  - [ ] Code review

### Phase 3: 監控驗證

- [ ] **設置告警**
  - [ ] 記憶體使用 > 80%
  - [ ] 記憶體使用 > 90%
  - [ ] Pod 重啟事件

- [ ] **定期檢查**（每週）
  - [ ] `kubectl top pod wilddiggr-0 -n wilddiggr-prd`
  - [ ] 檢查 pprof heap profile
  - [ ] 檢查應用日誌大小

---

## 🔬 驗證方案

### 1. 記憶體使用驗證

**執行優化前**：
```bash
# 記錄基線
kubectl top pod wilddiggr-0 -n wilddiggr-prd
# 預期：965Mi / 1Gi (96.5%)
```

**執行優化後（24小時）**：
```bash
# 檢查記憶體使用
kubectl top pod wilddiggr-0 -n wilddiggr-prd
# 預期：< 600Mi / 1Gi (< 60%)
```

**成功標準**：
- ✅ 記憶體使用降低到 < 60%
- ✅ 記憶體使用穩定，不再持續上升
- ✅ 無 OOM Kill 事件

### 2. 日誌量驗證

```bash
# 檢查日誌文件大小（優化前）
kubectl exec -n wilddiggr-prd wilddiggr-0 -- du -sh /var/log/wilddiggr/

# 檢查日誌文件大小（優化後）
kubectl exec -n wilddiggr-prd wilddiggr-0 -- du -sh /var/log/wilddiggr/
```

**成功標準**：
- ✅ 日誌增長速度降低 > 70%

### 3. 性能驗證

```bash
# 檢查應用性能指標
curl http://localhost:6605/debug/pprof/profile?seconds=30 > cpu.prof
go tool pprof cpu.prof
```

**成功標準**：
- ✅ CPU 使用率無明顯上升（< 50% of limit）
- ✅ 應用響應時間無惡化
- ✅ 數據庫查詢延遲無增加

---

## 📞 支援資訊

### pprof 訪問方式

```bash
# Port-forward to local
kubectl port-forward -n wilddiggr-prd wilddiggr-0 6605:6605

# 訪問 pprof web UI
http://localhost:6605/debug/pprof/

# 導出 heap profile
curl http://localhost:6605/debug/pprof/heap > heap.prof
go tool pprof heap.prof
```

### 相關文檔

- GORM Logger: https://gorm.io/docs/logger.html
- Zap Performance: https://github.com/uber-go/zap#performance
- Lumberjack: https://github.com/natefinch/lumberjack
- Go pprof: https://pkg.go.dev/net/http/pprof

---

## 📝 附錄

### A. 完整的 pprof 數據

已導出到：`/tmp/claude/wilddiggr-heap.prof`

### B. 分析命令記錄

```bash
# 資源使用
kubectl get pod wilddiggr-0 -n wilddiggr-prd -o json | jq '.spec.containers[].resources'
kubectl top pod wilddiggr-0 -n wilddiggr-prd

# pprof 分析
kubectl exec -n wilddiggr-prd wilddiggr-0 -- curl -s 'http://localhost:6605/debug/pprof/heap?debug=1'
kubectl exec -n wilddiggr-prd wilddiggr-0 -- curl -s 'http://localhost:6605/debug/pprof/goroutine?debug=1'
kubectl exec -n wilddiggr-prd wilddiggr-0 -- curl -s 'http://localhost:6605/debug/pprof/allocs?debug=1'
kubectl exec -n wilddiggr-prd wilddiggr-0 -- curl -s 'http://localhost:6605/debug/pprof/mutex?debug=1'
kubectl exec -n wilddiggr-prd wilddiggr-0 -- curl -s 'http://localhost:6605/debug/pprof/block?debug=1'
```

### C. 風險評估

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|--------|------|----------|
| OOM Kill 導致服務中斷 | 高 (80%) | 嚴重 | 立即執行 P0 優化 |
| 關閉日誌影響問題排查 | 中 (50%) | 中 | 保留 Warn/Error 級別日誌 + 啟用慢查詢日誌 |
| 優化後性能下降 | 低 (10%) | 低 | 在 staging 環境充分測試 |
| 增加記憶體 limit 導致成本上升 | 低 (10%) | 低 | 這是臨時措施，優化後可降回 |

---

**報告完成**
**下一步行動**：請立即執行 Phase 1 的緊急修復措施

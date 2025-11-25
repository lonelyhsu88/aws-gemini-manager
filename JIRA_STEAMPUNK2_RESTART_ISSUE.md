# JIRA OPS Ticket - Steampunk2 重啟後無法登入問題

**JIRA Ticket**: [OPS-812](https://jira.ftgaming.cc/browse/OPS-812)
**Created**: 2025-11-17
**Status**: Open

---

## Summary (標題)

```
Steampunk2 重啟後玩家無法登入 - bg-gate WebSocket 連接池殭屍連接問題
```

---

## Issue Type (問題類型)

**Bug** / **Production Issue**

---

## Priority (優先級)

**High** (影響玩家體驗)

---

## Assignee (負責人)

**lonely.h**

---

## Components (組件)

- bg-gate
- steampunk2
- WebSocket 連接管理

---

## Labels (標籤)

```
websocket, connection-pool, high-traffic, production, steampunk2, bg-gate
```

---

## Environment (環境)

- **Cluster**: EKS Production
- **Namespace**:
  - bg-gate-prd
  - steampunk2-prd
- **發生時間**: 2025-11-17
- **影響範圍**: 高流量遊戲（Steampunk2）

---

## Description (問題描述)

### 問題現象

在對 steampunk2 進行 pod 重啟後，新玩家嘗試登入遊戲時失敗。需要進行**第二次重啟**才能恢復正常。

### 關鍵發現

1. **第一次重啟後**：
   - steampunk2 pod 狀態正常 (Running 1/1)
   - 配置正確，center 可通信
   - 但玩家**無法登入** ❌

2. **第二次重啟後**：
   - 玩家可以正常登入 ✅
   - 服務完全恢復

3. **對比發現**：
   - 低流量遊戲（OdinBingo）重啟後**立即可用**，無此問題
   - 高流量遊戲（Steampunk2）重啟後**需要第二次重啟**

---

## Root Cause Analysis (根本原因分析)

### 核心問題：WebSocket 連接池 "殭屍連接" (Stale Connection)

#### 問題機制

```
高流量遊戲重啟流程:

T0:   bg-gate ←─ WebSocket ─→ steampunk2 (連接高頻使用中，每秒 1+ 筆交易)
      └─ 連接池狀態: lastUsed=1秒前, isAlive=true

T1:   kubectl delete pod steampunk2-0  (手動重啟)

T2:   舊 pod Terminating, WebSocket 連接斷開

T3:   新 pod 快速啟動 (10-15 秒)

T4:   新玩家登入請求到達
      └─ bg-gate 從連接池取出**舊連接**
      └─ 舊連接指向已不存在的 pod IP
      └─ ❌ 登入失敗

T5:   第二次重啟（或等待足夠長時間）
      └─ 舊連接超時被清理
      └─ bg-gate 建立新連接
      └─ ✅ 登入成功
```

#### 為什麼高流量遊戲特別容易出現此問題？

| 因素 | 高流量遊戲 (Steampunk2) | 低流量遊戲 (OdinBingo) |
|------|------------------------|----------------------|
| **交易頻率** | ~60 筆/分鐘 (每秒 1 筆) | ~3 筆/分鐘 (每 20 秒 1 筆) |
| **連接狀態** | 持續 "熱" (常用) | 經常 "冷" (閒置) |
| **超時機制** | 不會觸發 (一直在用) | 容易觸發 (長時間閒置) |
| **重啟影響** | ❌ 舊連接被保留使用 | ✅ 新連接被建立 |
| **問題發生** | ✅ **會發生** | ❌ **不會發生** |

### 證據數據

#### 交易量對比（2025-11-17 08:00-08:19）

```
Steampunk2: 1,181 筆交易  (平均 59 筆/分鐘)
OdinBingo:     59 筆交易  (平均  3 筆/分鐘)

差距: 20 倍
```

#### OdinBingo 重啟時間線（正常案例）

```
08:02:09 - odinbingo-0 pod 重啟
08:02:19 - 玩家登入成功 ✅ (10 秒後，無任何問題)
08:02:34 - 玩家登入成功 ✅ (25 秒後)
```

#### Steampunk2 重啟時間線（問題案例）

```
時間未知  - 第一次重啟
         - 測試登入 ❌ 失敗
08:11:22 - 第二次重啟 (HKT)
         - 測試登入 ✅ 成功
```

### 技術推測

bg-gate 可能的連接池邏輯（**缺少連接驗證**）：

```go
// 現有邏輯（推測）
func getConnection(gameType string) (*websocket.Conn, error) {
    conn := pool.Get(gameType)
    if conn != nil {
        return conn, nil  // ❌ 直接返回，不驗證連接有效性
    }
    return dialNew(gameType)
}
```

**問題**：
- 沒有檢查連接是否真的有效
- 沒有 TCP KeepAlive
- 沒有 WebSocket Ping/Pong 機制
- 高頻使用的連接不會超時，即使已失效

---

## Steps to Reproduce (重現步驟)

### 前提條件
- 遊戲有持續的高流量（> 30 筆/分鐘）
- 玩家正在遊玩中

### 重現步驟

1. 選擇一個高流量遊戲（如 Steampunk2）
2. 執行快速重啟：
   ```bash
   kubectl delete pod steampunk2-0 -n steampunk2-prd
   ```
3. 等待 pod 變為 Running (約 10-20 秒)
4. 使用**新玩家**嘗試登入遊戲

### 預期結果
- 玩家應該能立即登入

### 實際結果
- ❌ 玩家無法登入
- 需要第二次重啟或等待 5-10 分鐘

---

## Workaround (臨時解決方案)

### 選項 1: 重啟 bg-gate（推薦）

**如果遇到遊戲重啟後無法登入：**

```bash
# 不要再次重啟遊戲服務
# 改為重啟 bg-gate，強制清理所有連接池

kubectl delete pod bg-gate-0 -n bg-gate-prd
```

**優點**：
- ✅ 立即生效
- ✅ 清理所有遊戲的連接池
- ✅ 不影響遊戲服務穩定性

**缺點**：
- ⚠️ 會中斷所有正在遊玩的玩家（需要重新登入）

### 選項 2: 等待自動恢復

等待 5-10 分鐘，讓舊連接自動超時。

**優點**：
- ✅ 不需要人工干預
- ✅ 不影響其他玩家

**缺點**：
- ⚠️ 需要等待較長時間
- ⚠️ 等待期間新玩家無法登入

### 選項 3: 第二次重啟遊戲服務（不推薦）

重複重啟遊戲服務，直到連接被清理。

**優點**：
- ✅ 最終會解決

**缺點**：
- ❌ 不可預測（可能需要多次）
- ❌ 影響服務穩定性
- ❌ 治標不治本

---

## Permanent Solution (永久解決方案)

### P0 - 立即實施

#### 1. 操作手冊更新

創建標準操作程序（SOP）：

**遊戲服務重啟 SOP**：
```
1. 檢查遊戲流量（kubectl top pod）
2. 如果是高流量遊戲（> 30 筆/分鐘）：
   - 先重啟 bg-gate
   - 等待 bg-gate Ready
   - 再重啟遊戲服務
3. 如果是低流量遊戲：
   - 直接重啟即可
4. 重啟後驗證：
   - 測試新玩家登入
   - 檢查日誌無錯誤
```

### P1 - 短期解決（1-2 週）

#### 2. 增加連接驗證機制

在 bg-gate 代碼中增加連接有效性檢查：

```go
// 改進後的邏輯
func getConnection(gameType string) (*websocket.Conn, error) {
    conn := pool.Get(gameType)

    if conn != nil {
        // ✅ 驗證連接是否真的有效
        if err := validateConnection(conn); err != nil {
            log.Warn("Connection validation failed, reconnecting",
                     "gameType", gameType,
                     "error", err)
            pool.Remove(gameType)
            return dialNewConnection(gameType)
        }
        return conn, nil
    }

    return dialNewConnection(gameType)
}

func validateConnection(conn *websocket.Conn) error {
    // 發送 Ping，等待 Pong
    deadline := time.Now().Add(time.Second)
    if err := conn.WriteControl(
        websocket.PingMessage,
        []byte{},
        deadline,
    ); err != nil {
        return err
    }
    return nil
}
```

#### 3. 配置 TCP KeepAlive

```go
dialer := &websocket.Dialer{
    NetDialContext: (&net.Dialer{
        Timeout:   10 * time.Second,
        KeepAlive: 30 * time.Second,  // 每 30 秒發送 TCP KeepAlive
    }).DialContext,
    HandshakeTimeout: 10 * time.Second,
}
```

### P2 - 長期改善（1-2 個月）

#### 4. 實現 WebSocket Ping/Pong 心跳

```go
// 在連接建立後啟動心跳
func startHeartbeat(conn *websocket.Conn, gameType string) {
    ticker := time.NewTicker(30 * time.Second)

    go func() {
        defer ticker.Stop()

        for range ticker.C {
            deadline := time.Now().Add(time.Second)
            err := conn.WriteControl(
                websocket.PingMessage,
                []byte{},
                deadline,
            )

            if err != nil {
                log.Error("Heartbeat failed, removing connection",
                         "gameType", gameType,
                         "error", err)
                pool.Remove(gameType)
                return
            }
        }
    }()
}
```

#### 5. 配置 Pod Readiness Probe

在遊戲服務 Deployment 中增加 readiness probe：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: steampunk2
spec:
  template:
    spec:
      containers:
      - name: steampunk2
        readinessProbe:
          httpGet:
            path: /health        # 需要遊戲服務實現
            port: 29011
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 3
          successThreshold: 1
```

**效果**：
- Kubernetes Service 會等到 pod **真正 Ready** 才路由流量
- 避免新 pod 還沒準備好就接收請求

#### 6. 連接池重構

實現更智能的連接池管理：

```go
type ConnectionPool struct {
    connections map[string]*Connection
    mu          sync.RWMutex
}

type Connection struct {
    Conn       *websocket.Conn
    GameType   string
    LastUsed   time.Time
    CreatedAt  time.Time
    IsHealthy  bool
}

// 定期清理不健康的連接
func (p *ConnectionPool) StartCleaner() {
    ticker := time.NewTicker(1 * time.Minute)

    go func() {
        for range ticker.C {
            p.cleanupStaleConnections()
        }
    }()
}

func (p *ConnectionPool) cleanupStaleConnections() {
    p.mu.Lock()
    defer p.mu.Unlock()

    for gameType, conn := range p.connections {
        // 超過 5 分鐘未使用，或標記為不健康
        if time.Since(conn.LastUsed) > 5*time.Minute || !conn.IsHealthy {
            log.Info("Removing stale connection", "gameType", gameType)
            conn.Conn.Close()
            delete(p.connections, gameType)
        }
    }
}
```

---

## Impact Assessment (影響評估)

### 當前影響

| 項目 | 影響 |
|------|------|
| **影響範圍** | 高流量遊戲重啟後的新玩家登入 |
| **影響頻率** | 每次高流量遊戲重啟（不頻繁，但不可預測） |
| **影響時長** | 5-10 分鐘（或需要手動干預） |
| **業務影響** | 中等 - 新玩家無法登入，現有玩家不受影響 |
| **用戶體驗** | ⭐⭐ (2/5) - 登入失敗 |

### 解決方案影響

| 解決方案 | 實施時間 | 效果 | 風險 |
|---------|---------|------|------|
| **操作手冊更新** | 1 天 | 可預防問題發生 | 低 |
| **連接驗證** | 1-2 週 | 解決 80% 問題 | 中（需測試） |
| **完整重構** | 1-2 個月 | 徹底解決 | 中（較大改動） |

---

## Testing Plan (測試計劃)

### 測試環境

- **Staging 環境**先行測試
- 選擇一個中等流量的遊戲服務

### 測試步驟

1. **基準測試**：
   ```bash
   # 在正常狀態下測試玩家登入
   for i in {1..10}; do
     curl -X POST https://test-api/login -d "game=steampunk2"
   done
   ```

2. **重啟測試**：
   ```bash
   # 重啟遊戲服務
   kubectl delete pod steampunk2-0 -n steampunk2-stg

   # 立即測試登入（預期：失敗）
   curl -X POST https://test-api/login -d "game=steampunk2"

   # 等待 30 秒後測試（預期：成功）
   sleep 30
   curl -X POST https://test-api/login -d "game=steampunk2"
   ```

3. **解決方案測試**（實施連接驗證後）：
   ```bash
   # 重啟遊戲服務
   kubectl delete pod steampunk2-0 -n steampunk2-stg

   # 立即測試登入（預期：成功 ✅）
   curl -X POST https://test-api/login -d "game=steampunk2"
   ```

### 成功標準

- ✅ 遊戲重啟後，新玩家可立即登入（< 5 秒）
- ✅ 無需第二次重啟
- ✅ 無需人工干預
- ✅ bg-gate 日誌顯示連接重建成功

---

## Monitoring & Alerting (監控告警)

### 新增監控指標

```promql
# WebSocket 連接健康度
bg_gate_websocket_connection_health{game_type="steampunk2"}

# 連接池狀態
bg_gate_connection_pool_size{game_type="steampunk2"}
bg_gate_stale_connections_count

# 登入失敗率
rate(bg_gate_login_failures_total{game_type="steampunk2"}[5m])
```

### 告警規則

```yaml
- alert: HighLoginFailureRate
  expr: rate(bg_gate_login_failures_total[5m]) > 0.1
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "遊戲 {{ $labels.game_type }} 登入失敗率過高"
    description: "可能存在連接池問題，建議檢查 bg-gate"

- alert: StaleConnectionDetected
  expr: bg_gate_stale_connections_count > 0
  for: 5m
  labels:
    severity: info
  annotations:
    summary: "檢測到殭屍連接"
    description: "連接池中有 {{ $value }} 個失效連接"
```

---

## Related Issues (相關問題)

- 無（首次發現）

---

## References (參考資料)

1. **分析報告**:
   - `/Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/STEAMPUNK2_RESTART_ANALYSIS.md`

2. **WebSocket 連接管理最佳實踐**:
   - https://github.com/gorilla/websocket#readme
   - RFC 6455 - The WebSocket Protocol

3. **Kubernetes Service 文檔**:
   - https://kubernetes.io/docs/concepts/services-networking/service/

---

## Assignee (負責人)

- **Backend Team** (bg-gate 代碼修改)
- **DevOps Team** (操作手冊、監控配置)

---

## Due Date (截止日期)

- **P0 (操作手冊)**: 2025-11-20
- **P1 (連接驗證)**: 2025-12-01
- **P2 (完整重構)**: 2026-01-15

---

## Created By (建立者)

DevOps Team / Infrastructure

**創建時間**: 2025-11-17
**問題發現**: 在 steampunk2 重啟維護期間

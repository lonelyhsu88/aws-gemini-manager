# Minesca 超時告警根因分析報告

**日期**: 2025-11-01
**伺服器**: hash-prd-minesca-game-01 (i-01b50b93d76eb1df3)
**IP 位址**: 54.46.48.86 (Public) / 172.31.15.19 (Private)
**問題**: 持續收到超過 15 秒執行超時的告警

---

## 📊 問題概述

### 症狀
- 持續收到服務響應時間超過 15 秒的告警
- 服務產生大量 stacktrace 日誌檔案（115+ 個）
- 錯誤頻率：每天產生 10-20 個 panic stacktrace

### 影響範圍
- 影響玩家改變遊戲種子（ChangeSeed）的操作
- 導致請求處理延遲，觸發超時監控告警
- 可能影響玩家體驗和遊戲公平性

---

## 🔍 根因分析

### 核心問題

**Nil Pointer Dereference（空指標引用）**

```
runtime error: invalid memory address or nil pointer dereference
```

### 錯誤呼叫鏈

```
math/rand.(*Rand).Read()                          ← 第 273 行：嘗試使用 nil 的 Rand 物件
  ↓
bcn-common-golang/algorithm/mines.genServerSeed() ← 第 110 行：生成伺服器種子
  ↓
bcn-common-golang/algorithm/mines.(*Player).ChangeSeed() ← 第 418 行：玩家改變種子
  ↓
bcn-mines-gameserver/task.ClientChangeSeedReq()   ← 第 99 行：客戶端改變種子請求
```

### 問題詳情

從 stacktrace 日誌分析：

1. **發生位置**: `bcn-common-golang/algorithm/mines/mines.go:110`
2. **觸發函式**: `genServerSeed()` - 生成新的伺服器隨機種子
3. **失敗原因**: `math/rand.Rand` 物件未正確初始化（值為 nil）
4. **觸發場景**: 玩家呼叫 `ClientChangeSeedReq` 改變遊戲種子時

### 範例 Stacktrace

```
最新錯誤 (2025-11-01 22:40:38):
檔案: MinesGame.12.1762008038.stacktrace.log

runtime error: invalid memory address or nil pointer dereference
goroutine 79973367 [running]:
math/rand.(*Rand).Read(0xc001c39be0?, {0xc001c39bc0?, 0xc010fe54e8?, 0x1175d60?})
	/usr/local/go/src/math/rand/rand.go:273 +0x17
trevi/bcn-common-golang/algorithm/mines.genServerSeed(0xc010fe5440?)
	/tmp/build/bcn-common-golang/algorithm/mines/mines.go:110 +0x30
```

---

## 💥 為什麼導致超時？

雖然有 `RecoverFunc()` 捕獲 panic，但仍會導致以下效能問題：

1. **Panic Recovery 開銷**
   - 堆疊追蹤生成和寫入磁碟（I/O 操作）
   - 每次 panic 產生約 1.9KB 的 stacktrace 檔案

2. **請求處理中斷**
   - 當前請求失敗，可能需要客戶端重試
   - 錯誤處理邏輯增加響應時間

3. **並行任務池影響**
   - 使用 `github.com/lesismal/nbio/taskpool`
   - Panic 可能影響 taskpool 中的其他任務

4. **累積效應**
   - 115 個 stacktrace = 至少 115 次 panic
   - 高並行時，多個 panic 同時發生會嚴重影響效能

---

## 📈 統計資料

### 錯誤檔案統計
```bash
總 stacktrace 檔案數: 115 個
最早錯誤時間: 2025-10-21 06:41
最新錯誤時間: 2025-11-01 22:40
過去 24 小時: 13+ 個新錯誤
```

### 錯誤時間分布（範例）
- 2025-11-01: 13+ 次
- 2025-10-30: 9 次
- 2025-10-28: 7 次
- 2025-10-27: 5 次
- 2025-10-26: 4 次

### 主日誌檔案
- `MinesGame-Server.log`: 202 MB（當前）
- 日誌歸檔: 每天壓縮（約 100-180 MB/天）

---

## 🛠️ 解決方案

### 立即措施（緊急）

#### 1. 修復程式碼 - `mines.go:110`

**問題程式碼**（推測）:
```go
func genServerSeed() string {
    var rnd *rand.Rand  // 這裡是 nil
    seed := make([]byte, 32)
    rnd.Read(seed)      // ← PANIC: nil pointer dereference
    return hex.EncodeToString(seed)
}
```

**修復方案 A: 使用全域隨機數生成器**
```go
func genServerSeed() string {
    seed := make([]byte, 32)
    _, err := rand.Read(seed)  // 使用 crypto/rand 更安全
    if err != nil {
        // 錯誤處理
        return ""
    }
    return hex.EncodeToString(seed)
}
```

**修復方案 B: 正確初始化 math/rand.Rand**
```go
func genServerSeed() string {
    rnd := rand.New(rand.NewSource(time.Now().UnixNano()))
    seed := make([]byte, 32)
    _, err := rnd.Read(seed)
    if err != nil {
        // 錯誤處理
        return ""
    }
    return hex.EncodeToString(seed)
}
```

**推薦方案 C: 使用 crypto/rand（最安全）**
```go
import "crypto/rand"

func genServerSeed() (string, error) {
    seed := make([]byte, 32)
    _, err := rand.Read(seed)
    if err != nil {
        return "", fmt.Errorf("failed to generate server seed: %w", err)
    }
    return hex.EncodeToString(seed), nil
}
```

#### 2. 增強錯誤處理

在 `task_client_seed.go:99` 新增更好的錯誤處理：

```go
func ClientChangeSeedReq(...) {
    defer func() {
        if r := recover(); r != nil {
            log.Error("ChangeSeed panic recovered: %v", r)
            // 回傳錯誤給客戶端，而不是靜默失敗
            sendErrorResponse(...)
        }
    }()

    // 原有邏輯
    err := player.ChangeSeed(newSeed)
    if err != nil {
        log.Error("ChangeSeed failed: %v", err)
        sendErrorResponse(...)
        return
    }
}
```

### 中期措施（建議）

#### 3. 程式碼審查和測試

```bash
# 在程式庫中搜尋所有使用 rand.Rand 的地方
grep -rn "rand.Rand" /path/to/bcn-common-golang/
grep -rn "genServerSeed" /path/to/bcn-common-golang/

# 檢查是否有其他未初始化的 Rand 物件
```

#### 4. 新增單元測試

```go
func TestGenServerSeed(t *testing.T) {
    for i := 0; i < 1000; i++ {
        seed, err := genServerSeed()
        if err != nil {
            t.Fatalf("genServerSeed failed: %v", err)
        }
        if len(seed) != 64 { // 32 bytes = 64 hex chars
            t.Fatalf("invalid seed length: %d", len(seed))
        }
    }
}

func TestGenServerSeedConcurrent(t *testing.T) {
    var wg sync.WaitGroup
    for i := 0; i < 100; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            _, err := genServerSeed()
            if err != nil {
                t.Errorf("concurrent genServerSeed failed: %v", err)
            }
        }()
    }
    wg.Wait()
}
```

#### 5. 監控和告警優化

```bash
# 監控 stacktrace 檔案產生速率
watch -n 60 'find /var/log/hash-minesca-game/ -name "*.stacktrace.log" -mmin -60 | wc -l'

# 清理舊的 stacktrace（保留最近 7 天）
find /var/log/hash-minesca-game/ -name "*.stacktrace.log" -mtime +7 -delete
```

### 長期措施（改進）

#### 6. 架構改進

1. **集中式隨機數生成器**
   ```go
   package random

   import (
       "crypto/rand"
       "sync"
   )

   var (
       pool = sync.Pool{
           New: func() interface{} {
               return make([]byte, 32)
           },
       }
   )

   func GenerateSeed() (string, error) {
       buf := pool.Get().([]byte)
       defer pool.Put(buf)

       _, err := rand.Read(buf)
       if err != nil {
           return "", err
       }
       return hex.EncodeToString(buf), nil
   }
   ```

2. **效能監控**
   - 新增 Prometheus metrics
   - 監控 `ChangeSeed` 操作的成功率和延遲
   - 設定 P99 延遲告警

3. **程式碼規範**
   - 強制使用 `crypto/rand` 而非 `math/rand` 生成種子
   - 新增 linter 規則檢查未初始化的指標使用

---

## 📋 執行計畫

### Phase 1: 緊急修復（1-2 天）
- [ ] 定位並修復 `mines.go:110` 的 nil pointer 問題
- [ ] 新增錯誤處理和日誌
- [ ] 編譯新版本
- [ ] 在測試環境驗證
- [ ] 部署到生產環境

### Phase 2: 驗證和監控（3-7 天）
- [ ] 監控 stacktrace 檔案產生速率
- [ ] 檢查超時告警是否減少
- [ ] 收集效能指標對比

### Phase 3: 程式碼優化（1-2 週）
- [ ] 全面程式碼審查
- [ ] 新增單元測試和整合測試
- [ ] 優化隨機數生成效能
- [ ] 新增 Prometheus 監控

---

## 🔗 相關檔案

### 日誌位置
```
伺服器: hash-prd-minesca-game-01 (172.31.15.19)
日誌目錄: /var/log/hash-minesca-game/

關鍵檔案:
- MinesGame-Server.log (主日誌)
- MinesGame.*.stacktrace.log (錯誤堆疊)
- block_profile_*.out (效能分析)
```

### 原始碼位置（編譯時）
```
/tmp/build/bcn-common-golang/algorithm/mines/mines.go:110
/tmp/build/bcn-common-golang/algorithm/mines/mines.go:418
/tmp/build/bcn-mines-gameserver/task/task_client_seed.go:99
```

---

## 📞 聯絡資訊

**相關團隊**:
- 開發團隊: 需要修復原始碼
- 維運團隊: 部署和監控
- QA 團隊: 測試驗證

**優先級**: 🔴 **高（影響玩家體驗和系統穩定性）**

---

## 附錄：快速命令參考

### 連接伺服器
```bash
# 透過 AWS SSM
aws --profile gemini-pro_ck ssm start-session --target i-01b50b93d76eb1df3

# 查看最新錯誤
ls -lt /var/log/hash-minesca-game/*.stacktrace.log | head -5

# 查看即時日誌
tail -f /var/log/hash-minesca-game/MinesGame-Server.log

# 統計今天的錯誤數
find /var/log/hash-minesca-game/ -name "*.stacktrace.log" -mtime -1 | wc -l
```

### 監控指標
```bash
# CloudWatch 監控（如果有設定）
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-01b50b93d76eb1df3 \
  --start-time 2025-11-01T00:00:00Z \
  --end-time 2025-11-01T23:59:59Z \
  --period 3600 \
  --statistics Average,Maximum
```

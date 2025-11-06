# bingo-prd-* 實例重啟歷史報告

## 📊 執行摘要

**查詢範圍**: 最近 90 天（CloudTrail 保留期限）
**查詢時間**: 2025-11-03
**實例範圍**: 所有 bingo-prd-* 實例

### 🎯 關鍵發現

**重啟事件**: 在 **2025-11-03** 發生了**集中式重啟**操作

| 實例 | 重啟次數 | 重啟時間 | 操作者 |
|------|---------|---------|-------|
| bingo-prd | **2 次** | 08:08:41, 08:12:35 | CK |
| bingo-prd-backstage | **2 次** | 08:08:48, 08:12:42 | CK |
| bingo-prd-replica1 | **2 次** | 08:08:41, 08:12:35 | CK |
| bingo-prd-backstage-replica1 | **2 次** | 08:08:48, 08:12:42 | CK |
| bingo-prd-loyalty | **1 次** | 08:09:14 | CK |

**⚠️ 重要發現**: 4 個實例在 **4 分鐘內重啟了兩次**！

---

## 📋 詳細重啟記錄

### 1. bingo-prd (主實例)

| 次數 | 時間 (UTC+8) | 操作者 | 備註 |
|------|-------------|--------|------|
| 第 1 次 | 2025-11-03 08:08:41 | CK | 首次重啟 |
| 第 2 次 | 2025-11-03 08:12:35 | CK | **3 分 54 秒後再次重啟** |

**間隔時間**: 3 分 54 秒

### 2. bingo-prd-backstage

| 次數 | 時間 (UTC+8) | 操作者 | 備註 |
|------|-------------|--------|------|
| 第 1 次 | 2025-11-03 08:08:48 | CK | 首次重啟 |
| 第 2 次 | 2025-11-03 08:12:42 | CK | **3 分 54 秒後再次重啟** |

**間隔時間**: 3 分 54 秒

### 3. bingo-prd-replica1 (Read Replica)

| 次數 | 時間 (UTC+8) | 操作者 | 備註 |
|------|-------------|--------|------|
| 第 1 次 | 2025-11-03 08:08:41 | CK | 首次重啟（與主實例同時） |
| 第 2 次 | 2025-11-03 08:12:35 | CK | **3 分 54 秒後再次重啟** |

**間隔時間**: 3 分 54 秒

### 4. bingo-prd-backstage-replica1 (Read Replica)

| 次數 | 時間 (UTC+8) | 操作者 | 備註 |
|------|-------------|--------|------|
| 第 1 次 | 2025-11-03 08:08:48 | CK | 首次重啟 |
| 第 2 次 | 2025-11-03 08:12:42 | CK | **3 分 54 秒後再次重啟** |

**間隔時間**: 3 分 54 秒

### 5. bingo-prd-loyalty

| 次數 | 時間 (UTC+8) | 操作者 | 備註 |
|------|-------------|--------|------|
| 第 1 次 | 2025-11-03 08:09:14 | CK | **僅重啟一次** ✅ |

**總重啟次數**: 1 次

---

## 📅 時間線視圖

```
2025-11-03 08:08:41  ━━━ bingo-prd (第 1 次)
2025-11-03 08:08:41  ━━━ bingo-prd-replica1 (第 1 次)
                        ↓
2025-11-03 08:08:48  ━━━ bingo-prd-backstage (第 1 次)
2025-11-03 08:08:48  ━━━ bingo-prd-backstage-replica1 (第 1 次)
                        ↓
2025-11-03 08:09:14  ━━━ bingo-prd-loyalty (唯一一次) ✅
                        ↓
                     [等待約 3 分鐘]
                        ↓
2025-11-03 08:12:35  ━━━ bingo-prd (第 2 次) ⚠️
2025-11-03 08:12:35  ━━━ bingo-prd-replica1 (第 2 次) ⚠️
                        ↓
2025-11-03 08:12:42  ━━━ bingo-prd-backstage (第 2 次) ⚠️
2025-11-03 08:12:42  ━━━ bingo-prd-backstage-replica1 (第 2 次) ⚠️
```

---

## 🔍 重啟模式分析

### 模式 1: 主實例和 Replica 同步重啟

**實例組**: bingo-prd + bingo-prd-replica1

- 第 1 次: 08:08:41（同時重啟）
- 第 2 次: 08:12:35（同時重啟）

**特徵**: 主實例和其 Read Replica 完全同步重啟

### 模式 2: Backstage 實例和 Replica 同步重啟

**實例組**: bingo-prd-backstage + bingo-prd-backstage-replica1

- 第 1 次: 08:08:48（同時重啟）
- 第 2 次: 08:12:42（同時重啟）

**特徵**: Backstage 主實例和其 Read Replica 完全同步重啟

### 模式 3: Loyalty 實例單獨重啟

**實例**: bingo-prd-loyalty

- 僅重啟 1 次: 08:09:14

**特徵**: 沒有 Read Replica，只重啟一次

---

## 🤔 為什麼重啟兩次？

### 可能原因分析

#### 1. 參數組應用需要重啟

**最可能的原因**:
- 2024-11-13 創建了新的參數組 `postgresql14-monitoring-params`
- 參數組包含 **4 個需要重啟才能生效的參數**：
  - `shared_preload_libraries`
  - `pg_stat_statements.max`
  - `rds.logical_replication`
  - `pg_prewarm.autoprewarm`

#### 2. 第一次重啟可能失敗或不完整

**可能情況**:
- 第一次重啟後發現參數未完全生效
- 或者第一次重啟過程中出現問題
- 需要再次重啟確保參數應用成功

#### 3. 分批重啟策略

**觀察**:
- 主實例組 (bingo-prd + replica1) 在 08:08:41 和 08:12:35 重啟
- Backstage 組在 08:08:48 和 08:12:42 重啟（延遲 7 秒）
- Loyalty 在中間 08:09:14 重啟（只一次）

**推測**:
- 可能是手動執行的批次重啟
- 為了確保服務可用性，分組進行

#### 4. 檢查參數是否生效

**假設流程**:
```
08:08 - 第一輪重啟所有實例
  ↓
08:09 - 檢查參數狀態
  ↓
發現部分實例仍為 pending-reboot
  ↓
08:12 - 再次重啟部分實例（不包括 loyalty）
```

---

## 📊 重啟統計

### 總體統計

- **重啟日期**: 2025-11-03
- **重啟時段**: 08:08 - 08:12 (4 分鐘內)
- **操作者**: CK
- **總重啟次數**: 9 次（5 個實例，4 個重啟 2 次，1 個重啟 1 次）

### 按實例統計

| 實例 | 類型 | 重啟次數 |
|------|------|---------|
| bingo-prd | Primary | 2 |
| bingo-prd-replica1 | Read Replica | 2 |
| bingo-prd-backstage | Primary | 2 |
| bingo-prd-backstage-replica1 | Read Replica | 2 |
| bingo-prd-loyalty | Primary | 1 |

### 按時間統計

| 時間段 | 重啟次數 | 實例 |
|--------|---------|------|
| 08:08:41 | 2 | bingo-prd, bingo-prd-replica1 |
| 08:08:48 | 2 | bingo-prd-backstage, bingo-prd-backstage-replica1 |
| 08:09:14 | 1 | bingo-prd-loyalty |
| 08:12:35 | 2 | bingo-prd, bingo-prd-replica1 |
| 08:12:42 | 2 | bingo-prd-backstage, bingo-prd-backstage-replica1 |

---

## 🎯 重啟目的推測

### 主要目的：應用參數組變更

根據參數組分析報告（`PARAMETER_GROUP_COMPARISON_REPORT.md`），這次重啟的主要目的是應用以下參數：

1. **shared_preload_libraries**: 新增 `auto_explain` 擴展
2. **pg_stat_statements.max**: 設定為 10,000
3. **rds.logical_replication**: 啟用邏輯複製
4. **pg_prewarm.autoprewarm**: 啟用自動緩存預熱

### 為什麼 loyalty 只重啟一次？

**可能原因**:
- loyalty 實例沒有 Read Replica
- 第一次重啟後參數成功應用，狀態變為 `in-sync`
- 不需要第二次重啟

### 為什麼其他實例需要重啟兩次？

**推測**:
1. **第一次重啟**: 嘗試應用參數變更
2. **檢查狀態**: 發現某些實例仍為 `pending-reboot`
3. **第二次重啟**: 確保參數完全生效

或者：

1. **第一次重啟**: 應用大部分參數
2. **第二次重啟**: 確保 `shared_preload_libraries` 正確載入

---

## 🔍 與 pgsqlrel 的對比

### pgsqlrel 實例狀態

根據之前的分析（`PGSQLREL_PENDING_REBOOT_ANALYSIS.md`）：

| 實例 | 參數組 | 狀態 | 重啟記錄 |
|------|--------|------|---------|
| **pgsqlrel** | 同一個參數組 | **pending-reboot** ⚠️ | **無（90天內）** |
| bingo-prd-* | 同一個參數組 | **in-sync** ✅ | **2025-11-03 重啟** |

**結論**:
- bingo-prd-* 實例在 2025-11-03 重啟後，參數成功應用
- pgsqlrel 沒有在這次批量重啟中，所以仍為 `pending-reboot`

---

## 💡 建議與發現

### 發現

1. ✅ **重啟操作成功**: 所有 bingo-prd-* 實例的參數已應用（狀態為 `in-sync`）

2. ⚠️ **部分實例重啟兩次**: 可能是為了確保參數完全生效

3. 📋 **pgsqlrel 被遺漏**: pgsqlrel 沒有在這次批量重啟中

### 建議

1. **記錄重啟原因**:
   - 建議在重啟時添加註釋或標籤
   - 方便日後追溯

2. **自動化重啟流程**:
   - 考慮使用腳本自動化批量重啟
   - 包含參數檢查和驗證

3. **完成 pgsqlrel 重啟**:
   - 在合適的維護窗口重啟 pgsqlrel
   - 使其參數狀態與其他實例一致

---

## 📚 相關文檔

- 參數組比較報告: `scripts/rds/PARAMETER_GROUP_COMPARISON_REPORT.md`
- pgsqlrel 分析報告: `scripts/rds/PGSQLREL_PENDING_REBOOT_ANALYSIS.md`
- 參數組變更分析: `scripts/rds/PARAMETER_GROUP_CHANGE_ANALYSIS.md`

---

## 🛠️ 查詢工具

使用以下腳本查詢重啟歷史：

```bash
# 查詢所有 bingo-prd-* 實例
python3 scripts/rds/check-reboot-history.py bingo-prd

# 查詢特定實例
python3 scripts/rds/check-reboot-history.py <instance-name>

# 查詢所有實例
python3 scripts/rds/check-reboot-history.py
```

---

**報告生成時間**: 2025-11-03
**數據來源**: AWS CloudTrail
**查詢範圍**: 最近 90 天
**操作者**: CK
**AWS Profile**: gemini-pro_ck

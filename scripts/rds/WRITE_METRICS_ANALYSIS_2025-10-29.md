# RDS Write Metrics 分析報告

**日期**: 2025-10-29
**分析期間**: 最近 7 天
**分析指標**: WriteIOPS, WriteThroughput
**目的**: 補充缺少的 Write 相關告警

---

## 📋 執行摘要

當前 RDS 監控系統缺少 **WriteIOPS** 和 **WriteThroughput** 告警，這是一個重要的監控盲點。本分析基於 7 天歷史數據，為 5 個生產 RDS 實例提供告警閾值建議。

### 關鍵發現

1. ✅ 所有實例均使用 **gp3 儲存類型**，具有預配置 IOPS
2. ✅ 主資料庫（bingo-prd）的寫入活動最高
3. ✅ 當前寫入負載遠低於預配置 IOPS 限制（健康狀態）
4. ⚠️ 缺少異常寫入活動檢測機制

### 建議行動

- **創建 10 個新告警**（5 個實例 × 2 個指標）
- **優先級分類**: 全部為 **P2 (Medium)**
- **響應時間**: < 4 小時

---

## 📊 實例詳細分析

### 1. bingo-prd (主資料庫)

**實例配置**:
- **類型**: db.m6g.large
- **儲存**: 2,750 GB (gp3)
- **預配置 IOPS**: 12,000

**WriteIOPS 分析**:
```
平均 IOPS:          263.21
中位數 IOPS:        243.64
峰值 IOPS:          6,976.70  (異常峰值，可能是批量操作)
最大值平均:         388.57
預配置 IOPS 使用率: 3.2% (平均), 58.1% (峰值)
```

**WriteThroughput 分析**:
```
平均 Throughput:    3.54 MB/s
中位數 Throughput:  2.86 MB/s
峰值 Throughput:    120.13 MB/s  (異常峰值)
最大值平均:         6.32 MB/s
```

**建議閾值**:
- **WriteIOPS**: `583 IOPS` (平均峰值的 150%)
- **WriteThroughput**: `9,933,623 bytes/s` (9 MB/s)

**告警名稱**:
- `[P2] bingo-prd-RDS-WriteIOPS-High`
- `[P2] bingo-prd-RDS-WriteThroughput-High`

---

### 2. bingo-prd-replica1 (讀取副本)

**實例配置**:
- **類型**: db.m6g.large
- **儲存**: 2,662 GB (gp3)
- **預配置 IOPS**: 12,000

**WriteIOPS 分析**:
```
平均 IOPS:          260.08
中位數 IOPS:        239.60
峰值 IOPS:          5,687.33
最大值平均:         373.34
預配置 IOPS 使用率: 3.1% (平均), 47.4% (峰值)
```

**WriteThroughput 分析**:
```
平均 Throughput:    2.44 MB/s
中位數 Throughput:  1.73 MB/s
峰值 Throughput:    98.31 MB/s
最大值平均:         4.51 MB/s
```

**建議閾值**:
- **WriteIOPS**: `560 IOPS` (平均峰值的 150%)
- **WriteThroughput**: `7,093,225 bytes/s` (7 MB/s)

**告警名稱**:
- `[P2] bingo-prd-replica1-RDS-WriteIOPS-High`
- `[P2] bingo-prd-replica1-RDS-WriteThroughput-High`

**注意**: 副本的 Write 操作主要來自複製過程

---

### 3. bingo-prd-backstage (後台資料庫)

**實例配置**:
- **類型**: db.m6g.large
- **儲存**: 5,024 GB (gp3)
- **預配置 IOPS**: 12,000

**WriteIOPS 分析**:
```
平均 IOPS:          45.53
中位數 IOPS:        30.25
峰值 IOPS:          4,354.26  (有大量批量寫入)
最大值平均:         140.39
預配置 IOPS 使用率: 0.4% (平均), 36.3% (峰值)
```

**WriteThroughput 分析**:
```
平均 Throughput:    2.31 MB/s
中位數 Throughput:  1.93 MB/s
峰值 Throughput:    73.62 MB/s
最大值平均:         10.09 MB/s
```

**建議閾值**:
- **WriteIOPS**: `211 IOPS` (平均峰值的 150%)
- **WriteThroughput**: `15,867,161 bytes/s` (15 MB/s)

**告警名稱**:
- `[P2] bingo-prd-backstage-RDS-WriteIOPS-High`
- `[P2] bingo-prd-backstage-RDS-WriteThroughput-High`

**特點**: 寫入活動較低但有周期性批量操作

---

### 4. bingo-prd-backstage-replica1 (後台讀取副本)

**實例配置**:
- **類型**: db.t4g.medium (較小實例)
- **儲存**: 1,465 GB (gp3)
- **預配置 IOPS**: 12,000

**WriteIOPS 分析**:
```
平均 IOPS:          30.99
中位數 IOPS:        16.91
峰值 IOPS:          1,791.28
最大值平均:         69.28
預配置 IOPS 使用率: 0.6% (平均), 14.9% (峰值)
```

**WriteThroughput 分析**:
```
平均 Throughput:    0.74 MB/s
中位數 Throughput:  0.44 MB/s
峰值 Throughput:    58.65 MB/s
最大值平均:         1.79 MB/s
```

**建議閾值**:
- **WriteIOPS**: `104 IOPS` (平均峰值的 150%)
- **WriteThroughput**: `2,815,853 bytes/s` (3 MB/s)

**告警名稱**:
- `[P2] bingo-prd-backstage-replica1-RDS-WriteIOPS-High`
- `[P2] bingo-prd-backstage-replica1-RDS-WriteThroughput-High`

---

### 5. bingo-prd-loyalty (黏著度資料庫)

**實例配置**:
- **類型**: db.t4g.medium
- **儲存**: 200 GB (gp3)
- **預配置 IOPS**: 3,000

**WriteIOPS 分析**:
```
平均 IOPS:          12.44
中位數 IOPS:        12.04
峰值 IOPS:          388.97
最大值平均:         22.78
預配置 IOPS 使用率: 0.8% (平均), 13.0% (峰值)
```

**WriteThroughput 分析**:
```
平均 Throughput:    0.36 MB/s
中位數 Throughput:  0.36 MB/s
峰值 Throughput:    7.95 MB/s
最大值平均:         1.24 MB/s
```

**建議閾值**:
- **WriteIOPS**: `34 IOPS` (平均峰值的 150%)
- **WriteThroughput**: `1,942,559 bytes/s` (2 MB/s)

**告警名稱**:
- `[P2] bingo-prd-loyalty-RDS-WriteIOPS-High`
- `[P2] bingo-prd-loyalty-RDS-WriteThroughput-High`

**特點**: 寫入活動最低，非常穩定

---

## 📈 告警閾值總覽

| 實例 | WriteIOPS 閾值 | WriteThroughput 閾值 | 優先級 |
|------|----------------|---------------------|--------|
| **bingo-prd** | 583 IOPS | 9 MB/s (9,933,623 bytes/s) | P2 |
| **bingo-prd-replica1** | 560 IOPS | 7 MB/s (7,093,225 bytes/s) | P2 |
| **bingo-prd-backstage** | 211 IOPS | 15 MB/s (15,867,161 bytes/s) | P2 |
| **bingo-prd-backstage-replica1** | 104 IOPS | 3 MB/s (2,815,853 bytes/s) | P2 |
| **bingo-prd-loyalty** | 34 IOPS | 2 MB/s (1,942,559 bytes/s) | P2 |

---

## 🎯 優先級建議

### 為什麼選擇 P2 (Medium Priority)?

**P2 定義**:
- **響應時間**: < 4 小時
- **影響等級**: 性能下降但不影響服務可用性
- **嚴重程度**: 中等

**理由**:

1. **非關鍵服務中斷** ✅
   - WriteIOPS/Throughput 過高會影響性能
   - 但不會立即導致服務不可用
   - 有足夠時間調查和處理

2. **預配置 IOPS 容量充足** ✅
   - 所有實例的當前使用率 < 5%
   - 峰值使用率 < 60%
   - 有足夠的緩沖空間

3. **異常檢測為主要目的** ✅
   - 閾值設定為平均峰值的 150%
   - 目的是檢測異常行為（如失控的批量寫入）
   - 不是容量保護（IOPS 容量充足）

### 為什麼不是 P0 或 P1?

- **不是 P0**: 不會立即導致服務風險或資料丟失
- **不是 P1**: 不會造成嚴重的資源壓力（IOPS 容量充足）

---

## 🔧 告警配置建議

### CloudWatch 告警參數

**WriteIOPS 告警**:
```
MetricName: WriteIOPS
Namespace: AWS/RDS
Statistic: Average
Period: 300 秒 (5 分鐘)
EvaluationPeriods: 3
Threshold: (見上表)
ComparisonOperator: GreaterThanThreshold
TreatMissingData: notBreaching
```

**WriteThroughput 告警**:
```
MetricName: WriteThroughput
Namespace: AWS/RDS
Statistic: Average
Period: 300 秒 (5 分鐘)
EvaluationPeriods: 3
Threshold: (見上表，單位 bytes/s)
ComparisonOperator: GreaterThanThreshold
TreatMissingData: notBreaching
```

### 告警描述範本

**WriteIOPS**:
```
P2 MEDIUM: {instance} write IOPS too high (>={threshold} IOPS).
May indicate excessive write operations or batch jobs.
Response time: < 4 hours
```

**WriteThroughput**:
```
P2 MEDIUM: {instance} write throughput too high (>={threshold_mb} MB/s).
May indicate large data writes or replication issues.
Response time: < 4 hours
```

---

## 📊 Dashboard 更新建議

在 Production-RDS-Dashboard 上：

1. **Write IOPS Widget** - 新增告警閾值線（紅色虛線）
2. **Write Throughput Widget** - 新增告警閾值線（紅色虛線）

**範例配置**:
```json
"annotations": {
  "horizontal": [
    {
      "label": "bingo-prd 告警閾值: 583 IOPS",
      "value": 583,
      "fill": "above",
      "color": "#d32f2f"
    },
    {
      "label": "bingo-prd-replica1 告警閾值: 560 IOPS",
      "value": 560,
      "fill": "above",
      "color": "#d32f2f"
    }
    // ... 其他實例
  ]
}
```

---

## ⚠️ 注意事項

### 1. 副本的 Write 操作

讀取副本（replica）的 WriteIOPS 和 WriteThroughput 主要來自：
- 從主庫複製資料
- WAL (Write-Ahead Log) 應用

這些是正常的複製行為，不是應用層寫入。

### 2. 批量操作峰值

分析中發現多個異常峰值（如 bingo-prd 的 6,976 IOPS），可能來自：
- 資料庫維護操作
- 大量批量插入/更新
- 備份或快照

建議閾值（平均峰值的 150%）已考慮這些正常的峰值。

### 3. gp3 性能特性

所有實例使用 gp3 儲存：
- **基準性能**: 3,000 IOPS, 125 MB/s（免費）
- **預配置 IOPS**: 3,000-12,000（已配置）
- **最大 Throughput**: 125-1,000 MB/s

當前使用率遠低於限制，容量充足。

---

## 📋 實施清單

### Phase 1: 創建告警（10 個）

**WriteIOPS 告警** (5 個):
- [ ] `[P2] bingo-prd-RDS-WriteIOPS-High`
- [ ] `[P2] bingo-prd-replica1-RDS-WriteIOPS-High`
- [ ] `[P2] bingo-prd-backstage-RDS-WriteIOPS-High`
- [ ] `[P2] bingo-prd-backstage-replica1-RDS-WriteIOPS-High`
- [ ] `[P2] bingo-prd-loyalty-RDS-WriteIOPS-High`

**WriteThroughput 告警** (5 個):
- [ ] `[P2] bingo-prd-RDS-WriteThroughput-High`
- [ ] `[P2] bingo-prd-replica1-RDS-WriteThroughput-High`
- [ ] `[P2] bingo-prd-backstage-RDS-WriteThroughput-High`
- [ ] `[P2] bingo-prd-backstage-replica1-RDS-WriteThroughput-High`
- [ ] `[P2] bingo-prd-loyalty-RDS-WriteThroughput-High`

### Phase 2: 更新 Dashboard

- [ ] Write IOPS Widget - 新增 5 條告警線
- [ ] Write Throughput Widget - 新增 5 條告警線

### Phase 3: Lambda 通知測試

- [ ] 測試 WriteIOPS 告警通知格式
- [ ] 測試 WriteThroughput 告警通知格式
- [ ] 確認 P2 優先級顯示正確（黃色）

### Phase 4: 驗證

- [ ] 確認所有告警狀態為 OK
- [ ] 驗證 Dashboard 顯示正確
- [ ] 更新告警統計（從 45 → 55 個）

---

## 📈 預期結果

完成後的告警統計:

| 優先級 | 當前數量 | 新增數量 | 完成後總數 |
|--------|---------|---------|-----------|
| 🔴 P0 (Critical) | 5 | 0 | **5** |
| 🟠 P1 (High) | 28 | 0 | **28** |
| 🟡 P2 (Medium) | 12 | **10** | **22** |
| **總計** | **45** | **+10** | **55** |

---

## 🎓 分析方法說明

### 閾值計算邏輯

```
建議閾值 = 平均最大值 × 150%
```

**為什麼是 150%?**

1. **避免誤報**: 高於正常峰值，但不會太高
2. **檢測異常**: 足以捕捉異常的寫入活動
3. **經驗法則**: 業界常用的異常檢測倍數

**為什麼不用絕對峰值?**

- 絕對峰值可能是偶發事件（如一次性批量操作）
- 使用平均最大值更穩定
- 150% 的緩沖可以容納正常的波動

### 數據收集參數

```python
Period: 600 秒 (10 分鐘)
Statistics: ['Average', 'Maximum']
Days: 7 天
Total Datapoints: 1,008 個
```

---

## 🔗 相關文件

- `analyze-write-metrics.py` - 分析工具腳本
- `SESSION_SUMMARY_2025-10-29.md` - 會話總結
- `alarm-priority-plan.md` - 優先級分類計劃

---

**報告生成時間**: 2025-10-29
**下次審查時間**: 2025-11-29
**狀態**: ✅ 分析完成，待實施


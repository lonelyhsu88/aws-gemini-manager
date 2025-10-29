# bingo-prd CloudWatch 告警優化報告

**生成時間**: 2025-10-29
**分析實例**: bingo-prd (db.m6g.large, 2 vCPUs)
**當前告警數**: 27 個
**監控指標數**: 14 個

---

## 📊 執行摘要

### 發現的問題

1. **新舊格式混用** (7 個指標)
   - 部分指標同時存在新格式 (`RDS-bingo-prd-*`) 和舊格式 (`Bingo-*` 或 `[P*]`) 告警
   - 造成告警重複、命名不一致、維護困難

2. **閾值過多** (4 個指標)
   - CPUUtilization、DatabaseConnections、FreeStorageSpace、ReadIOPS 存在 3 個不同閾值
   - 告警過於複雜，難以理解和管理

3. **遺漏監控** (6 個指標)
   - 缺少 SwapUsage、NetworkTransmitThroughput 等重要指標
   - DBLoadCPU/DBLoadNonCPU 可更精確診斷負載類型

### 優化收益

- ✅ 刪除 10 個重複告警，減少告警疲勞
- ✅ 統一命名規範，提升可維護性
- ✅ 補充 6 個重要監控指標，提升監控完整性
- ✅ 簡化閾值設置，更容易理解

---

## 🔍 詳細分析

### 1. 新舊格式混用問題

#### 1.1 CPUUtilization (3 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| Bingo-RDS-DB-CPU-High | 90% | 1 分鐘 | Maximum | 舊 | ❌ 刪除 |
| RDS-bingo-prd-HighCPU-Warning | 70% | 5 分鐘 | Average | 新 | ✅ 保留 |
| RDS-bingo-prd-HighCPU-Critical | 85% | 3 分鐘 | Average | 新 | ✅ 保留 |

**問題**:
- 舊告警使用 Maximum 統計，容易誤報（瞬間尖峰）
- 新告警使用 Average 統計，更穩定
- 90% 閾值過高，新的 70%/85% 兩級閾值更合理

**建議**: 刪除 `Bingo-RDS-DB-CPU-High`

---

#### 1.2 DatabaseConnections (3 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-HighConnections-Warning | 630 (70%) | 5 分鐘 | Average | 新 | ✅ 保留 |
| [P1] bingo-prd-RDS-Connections-High | 675 (75%) | 10 分鐘 | Average | 舊 | ❌ 刪除 |
| RDS-bingo-prd-HighConnections-Critical | 765 (85%) | 3 分鐘 | Average | 新 | ✅ 保留 |

**問題**:
- 三個閾值過於接近 (70%, 75%, 85%)
- 舊告警 675 介於新告警兩級之間，容易混淆
- max_connections = 901

**建議**: 刪除 `[P1] bingo-prd-RDS-Connections-High`

---

#### 1.3 FreeStorageSpace (3 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-LowDiskSpace-Critical | 20 GB | 5 分鐘 | Average | 新 | ✅ 保留 |
| RDS-bingo-prd-LowDiskSpace-Warning | 50 GB | 10 分鐘 | Average | 新 | ✅ 保留 |
| [P0] bingo-prd-RDS-FreeStorageSpace-Low | 200 GB | 1 分鐘 | Minimum | 舊 | ⚠️ 考慮保留 |

**問題**:
- 新告警 (20 GB / 50 GB) 適合緊急情況
- 舊告警 (200 GB) 提供更早的預警
- 三個閾值差異大，但各有用途

**建議**:
- **選項 A**: 保留全部三個（早期預警 + 緊急響應）
- **選項 B**: 刪除舊告警，只保留新的兩級告警

**推薦**: 選項 B（統一管理優先）

---

#### 1.4 FreeableMemory (2 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-LowMemory-Warning | 1 GB | 3 分鐘 | Average | 新 | ✅ 保留 |
| [P1] bingo-prd-RDS-FreeableMemory-Low | 2 GB | 10 分鐘 | Average | 舊 | ❌ 刪除 |

**問題**:
- 新告警 1 GB 更緊急，適合快速響應
- 舊告警 2 GB 較寬鬆，但反應慢（10 分鐘）
- 記憶體不足應快速發現

**建議**: 刪除 `[P1] bingo-prd-RDS-FreeableMemory-Low`

---

#### 1.5 ReadIOPS (3 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-HighReadIOPS-Warning | 1500 | 5 分鐘 | Average | 新 | ✅ 保留 |
| RDS-bingo-prd-HighReadIOPS-Critical | 2000 | 3 分鐘 | Average | 新 | ✅ 保留 |
| [P1] bingo-prd-RDS-ReadIOPS-High | 8000 | 10 分鐘 | Average | 舊 | ❌ 刪除 |

**問題**:
- 基線 ReadIOPS: 500-600
- 新告警 1500/2000 基於實際基線（2.5x / 3.3x）
- 舊告警 8000 閾值過高（13x 基線），幾乎不會觸發
- 2025-10-29 事件峰值 2950，新告警可正確捕獲

**建議**: 刪除 `[P1] bingo-prd-RDS-ReadIOPS-High`

---

#### 1.6 ReadLatency (2 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-HighReadLatency | 5 ms | 5 分鐘 | Average | 新 | ✅ 保留 |
| [P2] bingo-prd-RDS-ReadLatency-High | 10 ms | 10 分鐘 | Average | 舊 | ❌ 刪除 |

**問題**:
- 新告警 5 ms 更敏感，能更早發現延遲問題
- 舊告警 10 ms 太寬鬆

**建議**: 刪除 `[P2] bingo-prd-RDS-ReadLatency-High`

---

#### 1.7 WriteLatency (2 個告警)

| 告警名稱 | 閾值 | 持續 | 統計 | 格式 | 狀態 |
|---------|------|------|------|------|------|
| RDS-bingo-prd-HighWriteLatency | 10 ms | 5 分鐘 | Average | 新 | ✅ 保留 |
| [P2] bingo-prd-RDS-WriteLatency-High | 10 ms | 10 分鐘 | Average | 舊 | ❌ 刪除 |

**問題**:
- 閾值相同（10 ms），但新告警反應更快（5 分鐘 vs 10 分鐘）

**建議**: 刪除 `[P2] bingo-prd-RDS-WriteLatency-High`

---

### 2. 遺漏的監控指標

#### 2.1 關鍵遺漏

**無** - 所有關鍵指標已監控 ✅

---

#### 2.2 重要遺漏

##### SwapUsage
- **重要性**: 🟡 重要
- **說明**: Swap 使用量，表示記憶體不足
- **建議閾值**: > 1 GB
- **為何重要**: Swap 使用會嚴重影響性能，應避免

##### NetworkTransmitThroughput
- **重要性**: 🟡 重要
- **說明**: 網路發送流量
- **建議閾值**: > 800 MB/s
- **為何重要**: 與 NetworkReceiveThroughput 配對監控，識別網路瓶頸
- **現狀**: 已監控 NetworkReceiveThroughput，但未監控 Transmit

---

#### 2.3 性能優化指標

##### DBLoadCPU
- **重要性**: 🟢 性能
- **說明**: CPU 相關的數據庫負載
- **建議閾值**: > 1.5 (75% of vCPUs)
- **為何有用**: 區分 CPU 瓶頸 vs I/O 瓶頸

##### DBLoadNonCPU
- **重要性**: 🟢 性能
- **說明**: 非 CPU 等待（I/O、Lock 等）
- **建議閾值**: > 5
- **為何有用**: 精確診斷 I/O 或 Lock 等待問題
- **實際案例**: 2025-10-29 事件中 DBLoadNonCPU 達 24，是主要問題

##### WriteThroughput
- **重要性**: 🟢 性能
- **說明**: 寫入吞吐量
- **建議閾值**: > 600 MB/s
- **現狀**: 已監控 ReadThroughput，但未監控 WriteThroughput

##### EBSIOBalance%
- **重要性**: 🟢 性能
- **說明**: EBS I/O credit 餘額百分比
- **建議閾值**: < 50%
- **為何有用**: I/O credit 耗盡會限制 IOPS 性能
- **現狀**: 已監控 EBSByteBalance%，但未監控 EBSIOBalance%

---

## 🎯 優化建議

### 優先級 P0：立即刪除重複告警

**目標**: 刪除 10 個舊格式告警，保留新格式

#### 刪除清單

```bash
# 要刪除的 10 個舊告警
Bingo-RDS-DB-CPU-High                        # CPUUtilization
[P1] bingo-prd-RDS-Connections-High          # DatabaseConnections
[P0] bingo-prd-RDS-FreeStorageSpace-Low      # FreeStorageSpace
[P1] bingo-prd-RDS-FreeableMemory-Low        # FreeableMemory
[P1] bingo-prd-RDS-ReadIOPS-High             # ReadIOPS
[P2] bingo-prd-RDS-ReadLatency-High          # ReadLatency
[P2] bingo-prd-RDS-WriteLatency-High         # WriteLatency

# 以下 3 個告警屬於舊系統，但新系統沒有創建對應告警
# 建議保留或根據需要刪除
Bingo-RDS-DB-EBSByteBalance-Low              # EBSByteBalance%
[P2] bingo-prd-RDS-DiskQueueDepth-High       # DiskQueueDepth
[P1] bingo-prd-RDS-NetworkReceive-High       # NetworkReceiveThroughput
[P1] bingo-prd-RDS-ReadThroughput-High       # ReadThroughput
[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High  # TransactionLogsDiskUsage
```

#### 執行命令

```bash
# 刪除 7 個明確重複的舊告警
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-CPU-High" \
    "[P1] bingo-prd-RDS-Connections-High" \
    "[P0] bingo-prd-RDS-FreeStorageSpace-Low" \
    "[P1] bingo-prd-RDS-FreeableMemory-Low" \
    "[P1] bingo-prd-RDS-ReadIOPS-High" \
    "[P2] bingo-prd-RDS-ReadLatency-High" \
    "[P2] bingo-prd-RDS-WriteLatency-High"
```

#### 驗證

```bash
# 確認刪除成功
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --query 'MetricAlarms[?contains(Dimensions[0].Value, `bingo-prd`)].AlarmName' \
    --output table
```

---

### 優先級 P1：處理未配對的舊告警

**目標**: 為 5 個未配對的舊告警創建新格式版本，然後刪除舊的

#### 未配對告警清單

1. **EBSByteBalance%** - `Bingo-RDS-DB-EBSByteBalance-Low`
2. **DiskQueueDepth** - `[P2] bingo-prd-RDS-DiskQueueDepth-High`
3. **NetworkReceiveThroughput** - `[P1] bingo-prd-RDS-NetworkReceive-High`
4. **ReadThroughput** - `[P1] bingo-prd-RDS-ReadThroughput-High`
5. **TransactionLogsDiskUsage** - `[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High`

#### 選項 A：創建新格式告警（推薦）

使用 `scripts/cloudwatch/create-rds-alarms.sh` 腳本時，它只創建了部分告警。可以手動補充：

```bash
# 1. EBSByteBalance% (已存在舊告警，創建新格式)
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-LowEBSByteBalance-Warning" \
    --alarm-description "EBS Byte Balance < 50% for 5 minutes" \
    --metric-name EBSByteBalance% \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 50.0 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd

# 2. DiskQueueDepth (創建新格式)
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighDiskQueueDepth-Warning" \
    --alarm-description "Disk Queue Depth > 5 for 5 minutes" \
    --metric-name DiskQueueDepth \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 5.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd

# 3. NetworkReceiveThroughput (創建新格式)
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighNetworkReceive-Warning" \
    --alarm-description "Network Receive > 950 MB/s for 5 minutes" \
    --metric-name NetworkReceiveThroughput \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 1000000000.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd

# 4. ReadThroughput (創建新格式)
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighReadThroughput-Warning" \
    --alarm-description "Read Throughput > 800 MB/s for 5 minutes" \
    --metric-name ReadThroughput \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 838860800.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd

# 5. TransactionLogsDiskUsage (創建新格式)
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighTransactionLogs-Warning" \
    --alarm-description "Transaction Logs > 10 GB for 5 minutes" \
    --metric-name TransactionLogsDiskUsage \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 10737418240.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

創建完成後，刪除舊告警：

```bash
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-EBSByteBalance-Low" \
    "[P2] bingo-prd-RDS-DiskQueueDepth-High" \
    "[P1] bingo-prd-RDS-NetworkReceive-High" \
    "[P1] bingo-prd-RDS-ReadThroughput-High" \
    "[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High"
```

#### 選項 B：直接刪除（簡化管理）

如果認為這些指標不夠重要，可以直接刪除：

```bash
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-EBSByteBalance-Low" \
    "[P2] bingo-prd-RDS-DiskQueueDepth-High" \
    "[P1] bingo-prd-RDS-NetworkReceive-High" \
    "[P1] bingo-prd-RDS-ReadThroughput-High" \
    "[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High"
```

**推薦**: 選項 A（保持監控完整性）

---

### 優先級 P2：補充遺漏指標

**目標**: 添加 6 個遺漏的重要監控指標

#### 2.1 SwapUsage (重要)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighSwapUsage-Warning" \
    --alarm-description "Swap Usage > 1 GB for 5 minutes" \
    --metric-name SwapUsage \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 1073741824.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

#### 2.2 NetworkTransmitThroughput (重要)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighNetworkTransmit-Warning" \
    --alarm-description "Network Transmit > 800 MB/s for 5 minutes" \
    --metric-name NetworkTransmitThroughput \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 838860800.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

#### 2.3 DBLoadCPU (性能診斷)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighDBLoadCPU-Warning" \
    --alarm-description "DBLoadCPU > 1.5 for 5 minutes" \
    --metric-name DBLoadCPU \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 1.5 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

#### 2.4 DBLoadNonCPU (性能診斷)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighDBLoadNonCPU-Warning" \
    --alarm-description "DBLoadNonCPU > 5 for 5 minutes (I/O or Lock wait)" \
    --metric-name DBLoadNonCPU \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 5.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

#### 2.5 WriteThroughput (性能)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-HighWriteThroughput-Warning" \
    --alarm-description "Write Throughput > 600 MB/s for 5 minutes" \
    --metric-name WriteThroughput \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 629145600.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

#### 2.6 EBSIOBalance% (性能)

```bash
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
    --alarm-name "RDS-bingo-prd-LowEBSIOBalance-Warning" \
    --alarm-description "EBS IO Balance < 50% for 5 minutes" \
    --metric-name EBSIOBalance% \
    --namespace AWS/RDS \
    --statistic Average \
    --period 60 \
    --evaluation-periods 5 \
    --datapoints-to-alarm 5 \
    --threshold 50.0 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd
```

---

## 📋 完整執行計劃

### 階段 1：刪除明確重複的告警（P0）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager

# 刪除 7 個明確重複的舊告警
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-CPU-High" \
    "[P1] bingo-prd-RDS-Connections-High" \
    "[P0] bingo-prd-RDS-FreeStorageSpace-Low" \
    "[P1] bingo-prd-RDS-FreeableMemory-Low" \
    "[P1] bingo-prd-RDS-ReadIOPS-High" \
    "[P2] bingo-prd-RDS-ReadLatency-High" \
    "[P2] bingo-prd-RDS-WriteLatency-High"

# 驗證刪除
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --query 'MetricAlarms[?Dimensions[0].Value==`bingo-prd`].[AlarmName,MetricName,StateValue]' \
    --output table
```

**預期結果**: 告警數從 27 個減少到 20 個

---

### 階段 2：處理未配對的舊告警（P1）

#### 選項 A：創建新格式後刪除舊的（推薦）

```bash
# 創建 5 個新格式告警
# (執行上面 P1 中的 5 個 put-metric-alarm 命令)

# 刪除對應的舊告警
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-EBSByteBalance-Low" \
    "[P2] bingo-prd-RDS-DiskQueueDepth-High" \
    "[P1] bingo-prd-RDS-NetworkReceive-High" \
    "[P1] bingo-prd-RDS-ReadThroughput-High" \
    "[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High"
```

**預期結果**: 告警數保持 20 個，但全部使用新格式

#### 選項 B：直接刪除（簡化）

```bash
aws --profile gemini-pro_ck cloudwatch delete-alarms --alarm-names \
    "Bingo-RDS-DB-EBSByteBalance-Low" \
    "[P2] bingo-prd-RDS-DiskQueueDepth-High" \
    "[P1] bingo-prd-RDS-NetworkReceive-High" \
    "[P1] bingo-prd-RDS-ReadThroughput-High" \
    "[P1] bingo-prd-RDS-TransactionLogsDiskUsage-High"
```

**預期結果**: 告警數減少到 15 個

---

### 階段 3：補充遺漏指標（P2）

```bash
# 執行上面 P2 中的 6 個 put-metric-alarm 命令
# (SwapUsage, NetworkTransmitThroughput, DBLoadCPU, DBLoadNonCPU, WriteThroughput, EBSIOBalance%)
```

**預期結果**:
- 選項 A 路徑：20 + 6 = 26 個告警
- 選項 B 路徑：15 + 6 = 21 個告警

---

## 📈 優化前後對比

### 告警數量變化

| 階段 | 操作 | 告警數 | 說明 |
|------|------|--------|------|
| 初始 | - | 27 | 當前狀態 |
| 階段 1 | 刪除 7 個重複告警 | 20 | -26% |
| 階段 2A | 替換 5 個舊告警 | 20 | 格式統一 |
| 階段 2B | 刪除 5 個舊告警 | 15 | -44% |
| 階段 3A | 添加 6 個新告警 | 26 | +6 個重要指標 |
| 階段 3B | 添加 6 個新告警 | 21 | +6 個重要指標 |

### 推薦路徑

**路徑 A（完整監控）**: 27 → 20 → 20 → 26 個告警
- 保持監控完整性
- 所有告警使用新格式
- 添加重要的診斷指標

**路徑 B（簡化管理）**: 27 → 20 → 15 → 21 個告警
- 刪除次要監控
- 專注核心指標
- 告警數減少 22%

**推薦**: 路徑 A

---

## 🎓 告警命名規範

### 統一格式

```
RDS-{instance}-{metric}-{level}

範例:
- RDS-bingo-prd-HighCPU-Warning
- RDS-bingo-prd-HighCPU-Critical
- RDS-bingo-prd-LowDiskSpace-Warning
```

### 級別定義

| 級別 | 後綴 | 響應時間 | 說明 |
|------|------|---------|------|
| 警告 | Warning | 5 分鐘內 | 需要關注，但不緊急 |
| 嚴重 | Critical | 3 分鐘內 | 需要立即處理 |

### 閾值設計原則

1. **Warning**: 1.5x 正常值或容量的 70%
2. **Critical**: 2x 正常值或容量的 85%

---

## 🔗 相關文檔

- **DBLoad 詳解**: `DBLOAD_EXPLANATION.md`
- **RDS 監控指南**: `RDS_MONITORING_GUIDE.md`
- **連接池監控**: `scripts/rds/monitor-connection-pool.sh`
- **I/O 調查工具**: `scripts/rds/investigate-io-spike-lite.sh`

---

## 📞 後續行動

### 立即執行

- [ ] 執行階段 1：刪除 7 個重複告警
- [ ] 驗證刪除結果

### 本週內完成

- [ ] 決定階段 2 路徑（A 或 B）
- [ ] 執行階段 2
- [ ] 執行階段 3
- [ ] 配置 SNS 通知

### 持續改進

- [ ] 監控新告警觸發頻率（1-2 週）
- [ ] 根據實際情況調整閾值
- [ ] 建立告警響應 Playbook
- [ ] 配置告警儀表板

---

**最後更新**: 2025-10-29
**下次審查**: 2025-11-05

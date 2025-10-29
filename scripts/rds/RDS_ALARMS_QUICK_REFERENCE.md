# RDS 监控快速参考

**快速查阅表** - 用于快速了解所有告警配置

---

## 告警阈值速查表

### 按实例类型

#### db.m6g.large (3个实例)
| 指标 | 阈值 | 适用实例 |
|------|------|---------|
| CPUUtilization | ≥90% | 全部 |
| FreeableMemory | ≤2 GB | 全部 |
| DatabaseConnections | ≥150 | bingo-prd, replica1, backstage |
| ReadIOPS | ≥8000 | 全部 |
| ReadThroughput | ≥800 MB/s | 全部 |
| NetworkReceiveThroughput | ≥1000 MB/s | 全部 |
| EBSByteBalance% | ≤50% | 全部 |
| ReadLatency | ≥0.01s | bingo-prd, backstage |
| WriteLatency | ≥0.01s | bingo-prd, backstage |
| DiskQueueDepth | ≥5 | 全部 |

#### db.t4g.medium (2个实例)
| 指标 | 阈值 | 适用实例 |
|------|------|---------|
| CPUUtilization | ≥90% | 全部 |
| CPUCreditBalance | ≤100 | 全部 |
| FreeableMemory | ≤1 GB | 全部 |
| ReadIOPS | ≥4000 | 全部 |
| ReadThroughput | ≥200 MB/s | 全部 |
| NetworkReceiveThroughput | ≥250 MB/s | 全部 |
| EBSByteBalance% | ≤50% | 全部 |
| ReadLatency | ≥0.01s | backstage-replica1 |
| WriteLatency | ≥0.01s | loyalty |
| DiskQueueDepth | ≥5 | 全部 |

---

## 按实例详细配置

### bingo-prd (db.m6g.large) - 10个告警
```
✓ CPUUtilization         ≥90%
✓ FreeableMemory         ≤2 GB
✓ DatabaseConnections    ≥150
✓ ReadIOPS               ≥8000
✓ ReadThroughput         ≥800 MB/s
✓ NetworkReceiveThroughput ≥1000 MB/s
✓ ReadLatency            ≥0.01s
✓ WriteLatency           ≥0.01s
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       ≤200 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

### bingo-prd-replica1 (db.m6g.large) - 6个告警
```
✓ FreeableMemory         ≤2 GB
✓ DatabaseConnections    ≥150
✓ ReadIOPS               ≥8000
✓ ReadThroughput         ≥800 MB/s
✓ NetworkReceiveThroughput ≥1000 MB/s
✓ DiskQueueDepth         ≥5
```

### bingo-prd-backstage (db.m6g.large) - 10个告警
```
✓ CPUUtilization         ≥90%
✓ FreeableMemory         ≤2 GB
✓ DatabaseConnections    ≥150
✓ ReadIOPS               ≥8000
✓ ReadThroughput         ≥800 MB/s
✓ NetworkReceiveThroughput ≥1000 MB/s
✓ ReadLatency            ≥0.01s
✓ WriteLatency           ≥0.01s
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       ≤300 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

### bingo-prd-backstage-replica1 (db.t4g.medium) - 7个告警
```
✓ CPUCreditBalance       ≤100
✓ FreeableMemory         ≤1 GB
✓ ReadIOPS               ≥4000
✓ ReadThroughput         ≥200 MB/s
✓ NetworkReceiveThroughput ≥250 MB/s
✓ ReadLatency            ≥0.01s
✓ DiskQueueDepth         ≥5
```

### bingo-prd-loyalty (db.t4g.medium) - 9个告警
```
✓ CPUCreditBalance       ≤100
✓ FreeableMemory         ≤1 GB
✓ ReadIOPS               ≥4000
✓ ReadThroughput         ≥200 MB/s
✓ NetworkReceiveThroughput ≥250 MB/s
✓ WriteLatency           ≥0.01s
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       ≤40 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

---

## 关键决策记录

### 为什么 t4g 的 ReadThroughput 阈值是 200 MB/s？
- t4g.medium 网络带宽上限: **260 MB/s**
- 设置为 200 MB/s = **77%** 网络容量
- **本次事件触发原因**: 实例达到 259 MB/s (99.6%)

### 为什么 m6g 的 ReadThroughput 阈值是 800 MB/s？
- m6g.large 网络带宽上限: **1,250 MB/s**
- 设置为 800 MB/s = **64%** 网络容量
- 留有足够缓冲空间

### 为什么 t4g 不监控 DatabaseConnections？
- t4g 实例通常用于低连接场景
- max_connections ~112，实际使用远低于此
- 避免不必要的告警

---

## Dashboard 告警线颜色说明

- 🔴 **红色** = 主要告警阈值 (触发 SNS 通知)
- 🟠 **橙色** = 次要告警阈值 / 不同实例类型
- 📍 **灰色** = 参考线 (不触发告警)

---

## 故障响应优先级

### P0 (立即响应)
```
EBSByteBalance ≤50%
NetworkReceiveThroughput (接近上限)
CPUCreditBalance ≤100 (t4g)
FreeStorageSpace (接近阈值)
```

### P1 (1小时内响应)
```
ReadIOPS 过高
ReadThroughput 过高
FreeableMemory 过低
DatabaseConnections 过高
ReplicaLag ≥30秒
```

### P2 (4小时内响应)
```
ReadLatency ≥0.01s
WriteLatency ≥0.01s
DiskQueueDepth ≥5
TransactionLogsDiskUsage ≥10GB
```

---

**更新日期**: 2025-10-29

# RDS 监控快速参考

**快速查阅表** - 用于快速了解所有告警配置

---

## 告警阈值速查表

### 按实例类型

#### db.m6g.large (3个实例)
| 指标 | Warning 阈值 | Critical 阈值 | 适用实例 |
|------|-------------|--------------|---------|
| CPUUtilization | ≥70% | ≥85% | 全部 |
| DBLoad | ≥6.0 | ≥8.0 | 全部 |
| FreeableMemory | ≤2 GB | ≤1 GB | 全部 |
| DatabaseConnections | ≥630 | ≥765 | bingo-prd, replica1, backstage |
| ReadIOPS | ≥8000 | ≥10000 | 全部 |
| WriteIOPS | ≥7500 | ≥9000 | 全部 |
| ReadThroughput | ≥800 MB/s | - | 全部 |
| NetworkReceiveThroughput | ≥1000 MB/s | - | 全部 |
| EBSByteBalance% | ≤50% | - | 全部 |
| ReadLatency | ≥0.01s (10ms) | - | 全部 |
| WriteLatency | ≥0.01s (10ms) | - | bingo-prd, backstage |
| DiskQueueDepth | ≥5 | - | 全部 |

#### db.t4g.medium (2个实例)
| 指标 | Warning 阈值 | Critical 阈值 | 适用实例 |
|------|-------------|--------------|---------|
| CPUUtilization | ≥70% | ≥85% | 全部 |
| DBLoad | ≥5.0 | ≥7.0 | 全部 |
| CPUCreditBalance | ≤100 | - | 全部 |
| FreeableMemory | ≤1 GB | - | 全部 |
| DatabaseConnections | ≥315 | ≥382 | 全部 |
| ReadIOPS | ≥4000 | ≥5000 | 全部 |
| WriteIOPS | ≥4000 | ≥5000 | 全部 |
| ReadThroughput | ≥200 MB/s | - | 全部 |
| NetworkReceiveThroughput | ≥250 MB/s | - | 全部 |
| EBSByteBalance% | ≤50% | - | 全部 |
| ReadLatency | ≥0.01s (10ms) | - | 全部 |
| WriteLatency | ≥0.01s (10ms) | - | loyalty |
| DiskQueueDepth | ≥5 | - | 全部 |

---

## 按实例详细配置

### bingo-prd (db.m6g.large) - 18个告警
```
✓ CPUUtilization         Warning ≥70%, Critical ≥85%
✓ DBLoad                 Warning ≥6.0, Critical ≥8.0
✓ FreeableMemory         Warning ≤2 GB, Critical ≤1 GB
✓ DatabaseConnections    Warning ≥630, Critical ≥765
✓ ReadIOPS               Warning ≥8000, Critical ≥10000
✓ WriteIOPS              Warning ≥7500, Critical ≥9000
✓ ReadLatency            ≥0.01s (10ms)
✓ WriteLatency           ≥0.01s (10ms)
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       Warning ≤200 GB, Critical ≤100 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

### bingo-prd-replica1 (db.m6g.large) - 12个告警
```
✓ DBLoad                 Warning ≥6.0, Critical ≥8.0
✓ FreeableMemory         Warning ≤2 GB
✓ DatabaseConnections    Warning ≥630, Critical ≥765
✓ ReadIOPS               Warning ≥8000, Critical ≥10000
✓ WriteIOPS              Warning ≥7500, Critical ≥9000
✓ ReadLatency            ≥0.01s (10ms)
✓ DiskQueueDepth         ≥5
```

### bingo-prd-backstage (db.m6g.large) - 18个告警
```
✓ CPUUtilization         Warning ≥70%, Critical ≥85%
✓ DBLoad                 Warning ≥6.0, Critical ≥8.0
✓ FreeableMemory         Warning ≤2 GB, Critical ≤1 GB
✓ DatabaseConnections    Warning ≥630, Critical ≥765
✓ ReadIOPS               Warning ≥8000, Critical ≥10000
✓ WriteIOPS              Warning ≥7500, Critical ≥9000
✓ ReadLatency            ≥0.01s (10ms)
✓ WriteLatency           ≥0.01s (10ms)
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       Warning ≤300 GB, Critical ≤150 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

### bingo-prd-backstage-replica1 (db.t4g.medium) - 13个告警
```
✓ DBLoad                 Warning ≥5.0, Critical ≥7.0
✓ CPUCreditBalance       ≤100
✓ FreeableMemory         ≤1 GB
✓ DatabaseConnections    Warning ≥315, Critical ≥382
✓ ReadIOPS               Warning ≥4000, Critical ≥5000
✓ WriteIOPS              Warning ≥4000, Critical ≥5000
✓ ReadLatency            ≥0.01s (10ms)
✓ DiskQueueDepth         ≥5
```

### bingo-prd-loyalty (db.t4g.medium) - 17个告警
```
✓ CPUUtilization         Warning ≥70%, Critical ≥85%
✓ DBLoad                 Warning ≥5.0, Critical ≥7.0
✓ CPUCreditBalance       ≤100
✓ FreeableMemory         Warning ≤1 GB
✓ DatabaseConnections    Warning ≥315, Critical ≥382
✓ ReadIOPS               Warning ≥4000, Critical ≥5000
✓ WriteIOPS              Warning ≥4000, Critical ≥5000
✓ ReadLatency            ≥0.01s (10ms)
✓ WriteLatency           ≥0.01s (10ms)
✓ DiskQueueDepth         ≥5
✓ FreeStorageSpace       Warning ≤40 GB, Critical ≤20 GB
✓ TransactionLogsDiskUsage ≥10 GB
```

---

## 关键决策记录

### DatabaseConnections 阈值为什么是 630/765 (m6g) 和 315/382 (t4g)？
- **max_connections 计算公式**: `LEAST({DBInstanceClassMemory/9531392}, 5000)`
- **db.m6g.large (8GB RAM)**: max_connections = 901
  - Warning: 630 (70% of max)
  - Critical: 765 (85% of max)
- **db.t4g.medium (4GB RAM)**: max_connections = 450
  - Warning: 315 (70% of max)
  - Critical: 382 (85% of max)
- **实际使用情况**: 远低于阈值 (bingo-prd 峰值 176, loyalty 峰值 8)

### ReadIOPS 和 WriteIOPS 阈值为什么是 8000/7500 (m6g) 和 4000 (t4g)？
- **2025-12-26 调整**: 从 1500/1200 提高到当前值
- **调整原因**:
  - 原阈值过低，备份操作峰值 7,115 IOPS 触发大量误报
  - 批处理作业峰值 3,981 IOPS 也会触发告警
- **Provisioned IOPS**: 12,000 IOPS
- **新阈值占比**: m6g.large 66.7%, t4g.medium 33.3%
- **预期效果**: 减少 95% 的误报，仅在真正异常时告警

### DBLoad 阈值为什么是 6.0/8.0 (m6g) 和 5.0/7.0 (t4g)？
- **2025-12-26 调整**: 从 3.0/4.0 提高到当前值
- **调整原因**:
  - 原阈值基于 vCPU 的 1.5x/2x，过于保守
  - 实际峰值达到 13.0，造成频繁误报
- **新阈值倍数**: m6g (3x/4x vCPU), t4g (2.5x/3.5x vCPU)
- **依据**: 正常批处理和查询高峰可能达到 2-3x vCPU

### ReadLatency 阈值为什么统一为 10ms？
- **2025-12-26 调整**: 从 5ms 提高到 10ms
- **调整原因**:
  - 与 WriteLatency 标准统一 (都是 10ms)
  - 实际峰值 9.05ms 会触发 5ms 阈值的误报
  - 与快速参考文档建议一致
- **正常范围**: 1-5ms，10ms 已经能有效识别异常

### 为什么 t4g 的 ReadThroughput 阈值是 200 MB/s？
- t4g.medium 网络带宽上限: **260 MB/s**
- 设置为 200 MB/s = **77%** 网络容量
- **事件记录**: 实例达到 259 MB/s (99.6%) 触发告警

### 为什么 m6g 的 ReadThroughput 阈值是 800 MB/s？
- m6g.large 网络带宽上限: **1,250 MB/s**
- 设置为 800 MB/s = **64%** 网络容量
- 留有足够缓冲空间

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
DBLoad 过高
ReadIOPS 过高
WriteIOPS 过高
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

---

## 更新历史

### 2025-12-26
- ✅ **ReadIOPS**: 提高到 8000/10000 (m6g), 4000/5000 (t4g)
- ✅ **WriteIOPS**: 提高到 7500/9000 (m6g), 4000/5000 (t4g)
- ✅ **DBLoad**: 提高到 6.0/8.0 (m6g), 5.0/7.0 (t4g)
- ✅ **ReadLatency**: 统一为 10ms 所有实例
- ✅ **DatabaseConnections**: 修正为 630/765 (m6g), 315/382 (t4g)
- **原因**: 减少备份和批处理作业引起的误报

### 2025-10-29
- 初始版本创建

**最后更新**: 2025-12-26

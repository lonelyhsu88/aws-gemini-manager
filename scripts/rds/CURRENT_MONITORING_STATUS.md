# RDS 监控指标和告警阈值汇总

**生成时间**: 2025-10-29  
**总告警数**: 42 个  
**覆盖实例**: 5 个  

---

## 📊 按监控指标分类

### 1️⃣ CPU 和计算资源

#### CPUUtilization (待配置)
- **说明**: CPU 使用率监控
- **配置**: 目前未单独配置告警
- **建议**: 所有实例配置 ≥90% 告警

#### CPUCreditBalance (t4g 专属)
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd-backstage-replica1 | ≤ 100 credits | 积分过低影响性能 |
| bingo-prd-loyalty | ≤ 100 credits | 积分过低影响性能 |

---

### 2️⃣ 内存资源

#### FreeableMemory (所有实例)
| 实例 | 实例类型 | 阈值 | RAM 占比 |
|------|---------|------|----------|
| bingo-prd | m6g.large | ≤ 2 GB | 25% of 8GB |
| bingo-prd-replica1 | m6g.large | ≤ 2 GB | 25% of 8GB |
| bingo-prd-backstage | m6g.large | ≤ 2 GB | 25% of 8GB |
| bingo-prd-backstage-replica1 | t4g.medium | ≤ 1 GB | 25% of 4GB |
| bingo-prd-loyalty | t4g.medium | ≤ 1 GB | 25% of 4GB |

---

### 3️⃣ 存储 I/O 性能

#### EBSByteBalance% (待配置)
- **说明**: EBS I/O Credits 余额
- **建议阈值**: ≤ 50%
- **触发原因**: 本次事件的主要告警

#### ReadIOPS (按实例类型)
| 实例类型 | 阈值 | 适用实例 |
|---------|------|---------|
| m6g.large | ≥ 8000 IOPS | bingo-prd, replica1, backstage |
| t4g.medium | ≥ 4000 IOPS | backstage-replica1, loyalty |

#### ReadThroughput (按实例类型)
| 实例类型 | 阈值 | 网络带宽占比 | 适用实例 |
|---------|------|-------------|---------|
| m6g.large | ≥ 800 MB/s | 64% of 1,250 MB/s | bingo-prd, replica1, backstage |
| t4g.medium | ≥ 200 MB/s | 77% of 260 MB/s | backstage-replica1, loyalty |

**注**: t4g.medium 在本次事件中达到 259 MB/s (99.6% 网络容量)

#### ReadLatency
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd | ≥ 0.01s | 10ms 延迟告警 |
| bingo-prd-backstage | ≥ 0.01s | 10ms 延迟告警 |
| bingo-prd-backstage-replica1 | ≥ 0.01s | 10ms 延迟告警 |

#### WriteLatency
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd | ≥ 0.01s | 10ms 延迟告警 |
| bingo-prd-backstage | ≥ 0.01s | 10ms 延迟告警 |
| bingo-prd-loyalty | ≥ 0.01s | 10ms 延迟告警 |

#### DiskQueueDepth (所有实例)
- **阈值**: ≥ 5
- **说明**: 等待 I/O 的请求数
- **适用**: 所有 5 个实例

---

### 4️⃣ 网络吞吐量

#### NetworkReceiveThroughput (按实例类型)
| 实例类型 | 阈值 | 网络带宽占比 | 适用实例 |
|---------|------|-------------|---------|
| m6g.large | ≥ 1000 MB/s | 80% of 1,250 MB/s | bingo-prd, replica1, backstage |
| t4g.medium | ≥ 250 MB/s | 96% of 260 MB/s | backstage-replica1, loyalty |

**关键**: t4g 阈值设置为 96% 是因为本次事件达到 99.6% 导致性能问题

---

### 5️⃣ 数据库连接数

#### DatabaseConnections (仅 m6g.large)
| 实例 | 阈值 | max_connections 占比 |
|------|------|---------------------|
| bingo-prd | ≥ 150 | 69% of ~216 |
| bingo-prd-replica1 | ≥ 150 | 69% of ~216 |
| bingo-prd-backstage | ≥ 150 | 69% of ~216 |

**注**: t4g.medium 实例不监控此指标 (连接数较低)

---

### 6️⃣ 存储空间

#### FreeStorageSpace (按实例数据量)
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd | ≤ 200 GB | 主数据库 |
| bingo-prd-backstage | ≤ 300 GB | 后台数据库 (数据量较大) |
| bingo-prd-loyalty | ≤ 40 GB | 忠诚度数据库 (数据量较小) |

#### TransactionLogsDiskUsage (仅主库)
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd | ≥ 10 GB | WAL 日志过大 |
| bingo-prd-backstage | ≥ 10 GB | WAL 日志过大 |
| bingo-prd-loyalty | ≥ 10 GB | WAL 日志过大 |

**注**: 只读副本不监控此指标

---

### 7️⃣ 复制延迟

#### ReplicaLag (待配置)
- **说明**: 主从同步延迟
- **建议阈值**: ≥ 30 秒
- **适用**: bingo-prd-replica1, bingo-prd-backstage-replica1

---

## 📈 Dashboard 配置

### Dashboard 名称
**Production-RDS-Dashboard**

### Widget 数量
**19 个** (覆盖所有关键指标)

### 告警线颜色说明
- 🔴 **红色**: 主要告警阈值 (触发通知)
- 🟠 **橙色**: 次要告警 / 不同实例类型阈值
- 📍 **灰色**: 参考线 (不触发告警)

---

## 🔔 通知配置

### SNS Topic
```
ARN: arn:aws:sns:ap-east-1:470013648166:Cloudwatch-Slack-Notification
```

### 订阅者
1. **Email**: lonely.h@jvd.tw
2. **Lambda → Slack**: Cloudwatch-Slack-Notification

### 告警评估条件
- **周期**: 300 秒 (5 分钟)
- **评估次数**: 2 次
- **触发条件**: 连续 2 个周期超标 (约 10 分钟)

---

## 📝 实例类型对比

| 规格 | db.m6g.large | db.t4g.medium |
|------|-------------|---------------|
| **vCPU** | 2 | 2 |
| **内存** | 8 GB | 4 GB |
| **网络带宽** | ~1,250 MB/s | ~260 MB/s |
| **max_connections** | ~216 | ~112 |
| **性能模式** | 稳定性能 | 突发性能 (CPU Credits) |
| **实例数量** | 3 个 | 2 个 |
| **告警数量** | 10/10/6 个 | 7/9 个 |

---

## ⚠️ 关键建议

### 高优先级
1. ✅ **已配置**: NetworkReceiveThroughput 告警 (本次事件关键指标)
2. ✅ **已配置**: 实例类型特定阈值
3. ✅ **已配置**: Dashboard 完整监控

### 待配置
1. ⏳ **CPUUtilization** 单独告警 (目前未配置)
2. ⏳ **EBSByteBalance%** 告警 (本次事件主要告警，应补充)
3. ⏳ **ReplicaLag** 告警 (主从延迟监控)

### 性能优化建议
- 🔍 考虑将 `bingo-prd-backstage-replica1` 从 t4g.medium 升级到 m6g.large
- 🔍 启用 Performance Insights 保留期延长 (分析慢查询)
- 🔍 配置 `pg_stat_statements` 扩展

---

## 📚 相关文档

1. **完整记录**: `scripts/rds/RDS_MONITORING_COMPLETE_RECORD.md`
2. **快速参考**: `scripts/rds/RDS_ALARMS_QUICK_REFERENCE.md`
3. **故障排查**: `scripts/rds/RDS_TROUBLESHOOTING_GUIDE.md`
4. **脚本说明**: `scripts/rds/README.md`

---

**最后更新**: 2025-10-29

---

## 📝 更新记录

### 2025-10-29: DatabaseConnections 阈值修正

**问题**: 之前使用错误的 max_connections 计算（~216），导致阈值过低（150 = 16.6%）

**修正**: 基于正确的 max_connections 计算更新阈值

| 实例类型 | max_connections | 旧阈值 | 新阈值 | 占比 |
|---------|----------------|--------|--------|------|
| db.m6g.large | ~901 | 150 | **675** | 75% |
| db.t4g.medium | ~451 | 无 | **340** | 75% |

**详细记录**: 参见 `DATABASE_CONNECTIONS_CORRECTION_2025-10-29.md`

**告警总数**: 42 → **44** (+2)


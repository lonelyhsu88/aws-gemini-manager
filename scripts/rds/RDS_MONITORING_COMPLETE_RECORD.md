# RDS 监控配置完整记录

**日期**: 2025-10-29  
**事件**: bingo-prd-backstage-replica1 EBSByteBalance 告警  
**目的**: 建立完整的 RDS 监控体系

---

## 📋 目录

1. [问题背景](#问题背景)
2. [RDS 实例配置](#rds-实例配置)
3. [CloudWatch Alarms 配置](#cloudwatch-alarms-配置)
4. [Dashboard 配置](#dashboard-配置)
5. [实例类型特定阈值说明](#实例类型特定阈值说明)
6. [通知配置](#通知配置)
7. [问题修复记录](#问题修复记录)

---

## 问题背景

### 初始问题
**时间**: 2025-10-29 09:20-09:30 HKT (UTC 01:20-01:30)  
**告警**: bingo-prd-backstage-replica1 RDS - `DB-EBSByteBalance-Low`

### 根本原因分析
1. **I/O 激增**:
   - ReadIOPS: 32 → 6,602 IOPS (206x 增长)
   - ReadThroughput: 1.39 MB/s → 259.5 MB/s (187x 增长)

2. **实例配置瓶颈**:
   - 实例类型: `db.t4g.medium` (2 vCPU, 4GB RAM)
   - 网络带宽: **~260 MB/s**
   - 配置的存储吞吐量: 500 MB/s (超过网络上限)
   - 实际吞吐量达到 **259 MB/s** (99.6% 网络容量)

3. **EBS I/O Credits 耗尽**:
   - EBSByteBalance% 从 99% 降至 29%
   - 持续高 I/O 导致突发性能积分消耗

### 诊断工具创建
- `scripts/rds/analyze-rds-queries.py` - Performance Insights 分析
- `scripts/rds/query-db-connections.py` - 数据库连接分析
- `scripts/rds/query-active-connections.sh` - 快速连接检查

---

## RDS 实例配置

### 生产环境 RDS 实例清单

| 实例名称 | 实例类型 | vCPU | 内存 | 网络带宽 | max_connections | 用途 |
|---------|---------|------|------|----------|-----------------|------|
| **bingo-prd** | db.m6g.large | 2 | 8 GB | ~1,250 MB/s | ~216 | 主数据库 |
| **bingo-prd-replica1** | db.m6g.large | 2 | 8 GB | ~1,250 MB/s | ~216 | 只读副本 |
| **bingo-prd-backstage** | db.m6g.large | 2 | 8 GB | ~1,250 MB/s | ~216 | 后台数据库 |
| **bingo-prd-backstage-replica1** | db.t4g.medium | 2 | 4 GB | ~260 MB/s | ~112 | 后台只读副本 |
| **bingo-prd-loyalty** | db.t4g.medium | 2 | 4 GB | ~260 MB/s | ~112 | 忠诚度数据库 |

### 实例类型特性对比

#### db.m6g.large (内存优化型)
- **优势**: 稳定性能，不受积分限制
- **网络**: 高达 10 Gbps (实际 ~1.25 GB/s)
- **适用**: 生产主库、高负载副本

#### db.t4g.medium (突发型)
- **优势**: 成本较低
- **限制**: CPU Credits 和网络带宽较低
- **适用**: 低负载场景、开发环境
- **注意**: 需监控 CPU Credits 余额

---

## CloudWatch Alarms 配置

### 告警配置原则
- **评估周期**: 300秒 (5分钟)
- **评估次数**: 2 次
- **触发条件**: 2 个数据点均超标 (约 10 分钟持续超标)
- **通知方式**: SNS → Email + Slack

### 完整告警清单 (共 42 个)

#### 1. CPU 相关 (6个)

**CPUUtilization** - 所有实例
- **阈值**: ≥90%
- **统计**: Average
- **说明**: CPU 使用率过高

**CPUCreditBalance** - 仅 t4g 实例
- **实例**: bingo-prd-backstage-replica1, bingo-prd-loyalty
- **阈值**: ≤100 credits
- **说明**: CPU 积分余额过低，可能影响性能

#### 2. 内存相关 (5个)

**FreeableMemory**
| 实例 | 类型 | 阈值 | 说明 |
|------|------|------|------|
| bingo-prd | m6g.large | ≤2 GB | 25% of 8GB |
| bingo-prd-replica1 | m6g.large | ≤2 GB | 25% of 8GB |
| bingo-prd-backstage | m6g.large | ≤2 GB | 25% of 8GB |
| bingo-prd-backstage-replica1 | t4g.medium | ≤1 GB | 25% of 4GB |
| bingo-prd-loyalty | t4g.medium | ≤1 GB | 25% of 4GB |

#### 3. 存储 I/O 相关 (15个)

**EBSByteBalance%** - 所有实例
- **阈值**: ≤50%
- **说明**: EBS I/O Credits 过低

**ReadIOPS**
| 实例类型 | 阈值 | 说明 |
|---------|------|------|
| m6g.large | ≥8000 IOPS | 适配高性能实例 |
| t4g.medium | ≥4000 IOPS | 适配突发型实例 |

**ReadThroughput**
| 实例类型 | 阈值 | 网络占比 |
|---------|------|----------|
| m6g.large | ≥800 MB/s | 64% of 1,250 MB/s |
| t4g.medium | ≥200 MB/s | 77% of 260 MB/s |

**ReadLatency / WriteLatency**
- **实例**: bingo-prd, bingo-prd-backstage, bingo-prd-backstage-replica1, bingo-prd-loyalty
- **阈值**: ≥0.01s (10ms)
- **说明**: 延迟过高可能影响应用性能

**DiskQueueDepth** - 所有实例
- **阈值**: ≥5
- **说明**: 等待 I/O 的请求数过多

#### 4. 网络相关 (5个)

**NetworkReceiveThroughput**
| 实例类型 | 阈值 | 网络占比 |
|---------|------|----------|
| m6g.large | ≥1000 MB/s | 80% of 1,250 MB/s |
| t4g.medium | ≥250 MB/s | 96% of 260 MB/s |

#### 5. 连接数相关 (3个)

**DatabaseConnections**
| 实例类型 | 阈值 | max_connections 占比 |
|---------|------|---------------------|
| m6g.large | ≥150 | 69% of ~216 |
| t4g.medium | N/A | 不监控 (较少连接) |

**注**: bingo-prd, bingo-prd-replica1, bingo-prd-backstage 配置此告警

#### 6. 存储空间相关 (3个)

**FreeStorageSpace**
| 实例 | 阈值 | 说明 |
|------|------|------|
| bingo-prd | ≤200 GB | 根据实际使用量设定 |
| bingo-prd-backstage | ≤300 GB | 后台数据较大 |
| bingo-prd-loyalty | ≤40 GB | 忠诚度数据较小 |

**TransactionLogsDiskUsage** - 主库
- **实例**: bingo-prd, bingo-prd-backstage, bingo-prd-loyalty
- **阈值**: ≥10 GB
- **说明**: WAL 日志占用过大

#### 7. 复制延迟 (2个)

**ReplicaLag**
- **实例**: bingo-prd-replica1, bingo-prd-backstage-replica1
- **阈值**: ≥30 秒
- **说明**: 主从同步延迟过大

---

## Dashboard 配置

### Dashboard 名称
`Production-RDS-Dashboard`

### Widget 布局 (19个)

#### 1. CPU 使用率 (全宽)
- **指标**: CPUUtilization (所有实例)
- **告警线**: 90% (红色，上方填充)

#### 2. EBS Byte Balance (全宽)
- **指标**: EBSByteBalance% (所有实例)
- **告警线**: 50% (红色，下方填充)

#### 3-4. 读写延迟 (各半宽)
- **指标**: ReadLatency / WriteLatency
- **告警线**: 0.01s (红色，上方填充)

#### 5-6. 网络吞吐量 (各半宽)
- **指标**: NetworkReceiveThroughput / NetworkTransmitThroughput
- **告警线**:
  - 🔴 m6g.large: 1000 MB/s
  - 🟠 t4g.medium: 250 MB/s
  - 📍 参考线: 网络上限

#### 7-8. CPU Credits (仅 t4g) (各半宽)
- **指标**: CPUCreditBalance / CPUCreditUsage
- **告警线**: 100 credits (红色，下方填充)

#### 9. 磁盘队列深度 (全宽)
- **指标**: DiskQueueDepth
- **告警线**:
  - 🔴 告警阈值: 5
  - 📍 严重参考线: 10

#### 10-11. Read/Write IOPS (各半宽)
- **Read IOPS 告警线**:
  - 🔴 m6g.large: 8000 IOPS
  - 🟠 t4g.medium: 4000 IOPS

#### 12-13. Read/Write Throughput (各半宽)
- **Read Throughput 告警线**:
  - 🔴 m6g.large: 800 MB/s
  - 🟠 t4g.medium: 200 MB/s

#### 14-15. 连接数 / DB Load (各半宽)
- **DatabaseConnections 告警线**:
  - 🔴 m6g.large: 150 connections
  - 🟠 t4g.medium max: ~112 (参考)
- **DB Load 告警线**:
  - 🔴 告警阈值: 4.0
  - 🟠 参考线: 2.0

#### 16-17. 可用内存 / Replica 延迟 (各半宽)
- **FreeableMemory 告警线**:
  - 🔴 m6g.large: 2 GB
  - 🟠 t4g.medium: 1 GB
- **ReplicaLag 告警线**: 30秒

#### 18. 可用存储空间 (全宽)
- **告警线**:
  - 🔴 bingo-prd: 200 GB
  - 🟠 bingo-prd-backstage: 300 GB
  - 🟠 bingo-prd-loyalty: 40 GB

#### 19. 事务日志使用量 (全宽)
- **告警线**:
  - 🔴 告警阈值: 10 GB
  - 📍 严重参考线: 50 GB

---

## 实例类型特定阈值说明

### 为什么需要不同阈值？

不同实例类型具有不同的硬件规格和性能特性，使用统一阈值会导致：
- **m6g.large**: 阈值过低，产生误报
- **t4g.medium**: 阈值过高，无法及时发现问题

### 阈值设定逻辑

#### DatabaseConnections
```
m6g.large: 150 connections (69% of max_connections ~216)
t4g.medium: 不监控 (连接数通常较低)

理由: m6g 实例承载更多业务负载，需要监控连接数
```

#### FreeableMemory
```
m6g.large: 2 GB (25% of 8GB RAM)
t4g.medium: 1 GB (25% of 4GB RAM)

理由: 保持相同的百分比阈值 (25%)，但绝对值不同
```

#### ReadIOPS
```
m6g.large: 8000 IOPS
t4g.medium: 4000 IOPS

理由: t4g 实例 I/O 性能较低，使用更保守的阈值
```

#### ReadThroughput
```
m6g.large: 800 MB/s (64% of 1,250 MB/s 网络带宽)
t4g.medium: 200 MB/s (77% of 260 MB/s 网络带宽)

理由: 
- t4g 网络带宽仅 260 MB/s，需在接近上限前告警
- 本次事件中 t4g 实例达到 259 MB/s 导致问题
```

#### NetworkReceiveThroughput
```
m6g.large: 1000 MB/s (80% of 1,250 MB/s)
t4g.medium: 250 MB/s (96% of 260 MB/s)

理由: 
- t4g 需要更早告警，因为接近网络上限会影响性能
- 本次事件的关键指标
```

---

## 通知配置

### SNS Topic
```
ARN: arn:aws:sns:ap-east-1:470013648166:Cloudwatch-Slack-Notification
Region: ap-east-1 (Hong Kong)
```

### 订阅者

#### 1. Email
- **地址**: lonely.h@jvd.tw
- **协议**: email
- **用途**: 管理员直接通知

#### 2. Lambda → Slack
- **函数**: Cloudwatch-Slack-Notification
- **协议**: lambda
- **用途**: 团队 Slack 频道通知

### 告警触发条件
```
Period: 300 秒 (5 分钟)
EvaluationPeriods: 2
DatapointsToAlarm: 2

结果: 需要连续 2 个周期 (约 10 分钟) 超标才触发告警
```

---

## 问题修复记录

### 修复 1: 实例类型特定阈值 (2025-10-29)

**问题**: 所有实例使用统一阈值，不符合实例类型特性

**修复内容**:
- ✅ 更新 FreeableMemory: m6g 2GB, t4g 1GB
- ✅ 创建 DatabaseConnections: m6g 150 connections
- ✅ 创建/更新 ReadIOPS: m6g 8000, t4g 4000
- ✅ 创建 ReadThroughput: m6g 800MB/s, t4g 200MB/s
- ✅ 删除旧的重复告警

**影响**: 42 个告警，覆盖 5 个实例

### 修复 2: Dashboard 告警线不匹配 (2025-10-29)

**问题**: Dashboard 显示的阈值线与实际 CloudWatch Alarms 不一致

**发现的问题**:
1. ❌ ReadLatency / WriteLatency 标记为 "警戒线" 而非 "告警阈值"
2. ❌ NetworkReceiveThroughput 缺少实际告警阈值线
3. ❌ CPUCreditBalance 标记不准确
4. ❌ DiskQueueDepth 标记不准确
5. ❌ **FreeStorageSpace 完全缺少告警线** (最严重)
6. ❌ TransactionLogsDiskUsage 标记不准确

**修复内容**:
- ✅ 更新所有标签为 "告警阈值"
- ✅ 新增 NetworkReceiveThroughput 实际告警线
- ✅ 新增 FreeStorageSpace 告警线 (3条，不同实例不同阈值)
- ✅ 区分告警线 (红色/橙色) 和参考线 (灰色)

**验证**: 所有 Dashboard 阈值线现已与 CloudWatch Alarms 完全一致

---

## 快速参考

### 查看所有告警
```bash
aws cloudwatch describe-alarms \
  --profile gemini-pro_ck \
  --query 'MetricAlarms[?contains(AlarmName, `bingo-prd`)].[AlarmName,MetricName,Threshold]' \
  --output table
```

### 查看 Dashboard
```bash
aws cloudwatch get-dashboard \
  --profile gemini-pro_ck \
  --dashboard-name "Production-RDS-Dashboard"
```

### 检查实例状态
```bash
./scripts/rds/list-instances.sh
./scripts/rds/check-connections-peak.sh
```

### Performance Insights 分析
```bash
python3 scripts/rds/analyze-rds-queries.py
python3 scripts/rds/query-db-connections.py
```

---

## 建议和注意事项

### 1. t4g.medium 实例监控重点
- ⚠️ 密切关注 **NetworkReceiveThroughput** (260 MB/s 上限)
- ⚠️ 监控 **CPUCreditBalance** (避免性能降级)
- ⚠️ 考虑升级到 m6g.large 以获得稳定性能

### 2. 告警响应优先级
- 🔴 **P0**: EBSByteBalance, NetworkReceiveThroughput, CPUCreditBalance
- 🟠 **P1**: ReadIOPS, ReadThroughput, FreeableMemory, DatabaseConnections
- 🟡 **P2**: ReadLatency, WriteLatency, DiskQueueDepth

### 3. 定期检查
- 每周检查 Performance Insights 慢查询
- 每月审查告警阈值是否合理
- 季度评估实例类型是否需要调整

### 4. 性能优化建议
- 考虑为 bingo-prd-backstage-replica1 升级到 m6g.large
- 启用 `pg_stat_statements` 扩展分析慢查询
- 设置 `log_min_duration_statement = 1000` 记录慢查询

---

## 相关文档
- `scripts/rds/README.md` - RDS 脚本使用说明
- `scripts/rds/RDS_TROUBLESHOOTING_GUIDE.md` - 故障排查指南
- `.claude/settings.local.json` - Claude Code 配置

---

**最后更新**: 2025-10-29  
**维护者**: DevOps Team

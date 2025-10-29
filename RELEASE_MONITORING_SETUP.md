# Release Environment RDS Monitoring Setup

## 概述

为 Release 环境的 RDS 实例创建了完整的 CloudWatch 监控体系，包括 Dashboard 和 Alarms，完全参考 Production-RDS-Dashboard 的配置，但**不配置 SNS 通知**。

## 监控实例

| 实例名称 | 实例类型 | vCPUs | Max Connections | 存储 | 状态 |
|---------|---------|-------|----------------|------|------|
| pgsqlrel | db.t3.small | 2 | 225 | 40GB | ✅ Available |
| pgsqlrel-backstage | db.t3.micro | 2 | 112 | 40GB | ✅ Available |

## 创建的资源

### 1. CloudWatch Dashboard

**名称**: `Release-RDS-Dashboard`

**包含的监控图表** (7个):
1. **CPU Utilization** - 所有 2 个实例的 CPU 使用率
   - Warning 线: 70%
   - Critical 线: 85%

2. **Database Load (DBLoad)** - 数据库负载
   - Warning 线: 3 (1.5x vCPUs)
   - Critical 线: 4 (2x vCPUs)

3. **Database Connections** - 连接数
   - pgsqlrel: Warning 158 (70%), Critical 191 (85%)
   - pgsqlrel-backstage: Warning 78 (70%), Critical 95 (85%)

4. **IOPS (Read/Write)** - 磁盘 I/O 操作
   - 显示每个实例的读写 IOPS

5. **Freeable Memory** - 可用内存
   - Warning 线: 1GB

6. **Free Storage Space** - 可用存储空间
   - Warning 线: 10GB
   - Critical 线: 5GB

7. **Latency (Read/Write)** - 读写延迟
   - Read Warning: 5ms
   - Write Warning: 10ms

### 2. CloudWatch Alarms

**总数**: 30 个告警 (2 实例 × 15 告警/实例)

**每个实例的告警** (15个):

#### CPU 告警 (2个)
- `RDS-{instance}-HighCPU-Warning` - CPU > 70% 持续 5 分钟
- `RDS-{instance}-HighCPU-Critical` - CPU > 85% 持续 3 分钟

#### 数据库负载告警 (2个)
- `RDS-{instance}-HighDBLoad-Warning` - DBLoad > 3 持续 5 分钟
- `RDS-{instance}-HighDBLoad-Critical` - DBLoad > 4 持续 3 分钟

#### 连接数告警 (2个)
**pgsqlrel (max: 225)**:
- Warning: > 158 (70%)
- Critical: > 191 (85%)

**pgsqlrel-backstage (max: 112)**:
- Warning: > 78 (70%)
- Critical: > 95 (85%)

#### ReadIOPS 告警 (2个)
- `RDS-{instance}-HighReadIOPS-Warning` - ReadIOPS > 1000 持续 5 分钟
- `RDS-{instance}-HighReadIOPS-Critical` - ReadIOPS > 1500 持续 3 分钟

#### WriteIOPS 告警 (2个)
- `RDS-{instance}-HighWriteIOPS-Warning` - WriteIOPS > 800 持续 5 分钟
- `RDS-{instance}-HighWriteIOPS-Critical` - WriteIOPS > 1200 持续 3 分钟

#### 磁盘空间告警 (2个)
**注意**: Release 环境只有 40GB 存储，阈值调整为 10GB/5GB

- `RDS-{instance}-LowDiskSpace-Warning` - 可用空间 < 10GB
- `RDS-{instance}-LowDiskSpace-Critical` - 可用空间 < 5GB

#### 内存告警 (1个)
**注意**: t3.micro 内存较小，阈值调整为 512MB

- `RDS-{instance}-LowMemory-Warning` - 可用内存 < 512MB 持续 3 分钟

#### 读延迟告警 (1个)
- `RDS-{instance}-HighReadLatency` - 读延迟 > 5ms 持续 5 分钟

#### 写延迟告警 (1个)
- `RDS-{instance}-HighWriteLatency` - 写延迟 > 10ms 持续 5 分钟

## 关键特性

### ✅ 包含的功能
- ✅ 完整的监控指标（与 Production 相同）
- ✅ 针对小型实例调整的阈值
- ✅ Dashboard 可视化
- ✅ 告警状态记录
- ✅ CloudWatch Console 可查看

### ❌ 不包含的功能
- ❌ SNS 通知
- ❌ Slack 告警
- ❌ Email 通知
- ❌ 告警优先级分级（P0/P1/P2）

### 🔧 针对 Release 环境的调整

| 指标 | Production | Release |
|------|-----------|---------|
| **磁盘空间 Warning** | 50GB | 10GB (因为总存储只有 40GB) |
| **磁盘空间 Critical** | 20GB | 5GB (因为总存储只有 40GB) |
| **内存 Warning** | 1GB | 512MB (t3.micro 内存较小) |
| **ReadIOPS Warning** | 1500 | 1000 (较小实例) |
| **WriteIOPS Warning** | 1200 | 800 (较小实例) |

## 使用方法

### 创建 Dashboard

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/cloudwatch
./create-release-dashboard.sh
```

### 创建告警

```bash
./create-release-alarms.sh
```

### 查看 Dashboard

**AWS Console**:
```
https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=Release-RDS-Dashboard
```

**AWS CLI**:
```bash
aws --profile gemini-pro_ck cloudwatch get-dashboard \
    --dashboard-name Release-RDS-Dashboard \
    --region ap-east-1
```

### 查看告警状态

```bash
# 查看所有 release 告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --alarm-name-prefix 'RDS-pgsqlrel' \
    --output table

# 查看 ALARM 状态的告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --state-value ALARM \
    --query 'MetricAlarms[?contains(AlarmName, `pgsqlrel`)]' \
    --output table
```

## 与其他环境对比

| 特性 | Production | Stress | Release |
|------|-----------|--------|---------|
| **实例数量** | 5+ | 3 | 2 |
| **实例类型** | m6g.large, t4g.medium | t4g.medium | t3.small, t3.micro |
| **告警数量** | 70+ | 45 | 30 |
| **SNS 通知** | ✅ | ❌ | ❌ |
| **存储大小** | 200GB+ | 100GB+ | 40GB |
| **磁盘告警阈值** | 50GB/20GB | 50GB/20GB | 10GB/5GB |
| **内存告警阈值** | 1GB | 1GB | 512MB |

## 成本估算

### CloudWatch 费用

| 项目 | 数量 | 单价 | 月费用 |
|------|------|------|--------|
| Dashboard | 1 | $3/月 | $3.00 |
| Alarms | 30 | $0.10/alarm | $3.00 |
| Metrics | 基础指标 | 免费 | $0.00 |
| **总计** | - | - | **$6.00/月** |

## 文件清单

### 新创建的文件

```
aws-gemini-manager/
├── scripts/
│   └── cloudwatch/
│       ├── create-release-dashboard.sh         # Dashboard 创建脚本
│       └── create-release-alarms.sh            # 告警创建脚本（无 SNS）
└── RELEASE_MONITORING_SETUP.md                 # 本文件（项目总结）
```

## 后续操作建议

### 立即执行
1. ✅ 运行 `create-release-dashboard.sh` 创建 Dashboard
2. ✅ 运行 `create-release-alarms.sh` 创建告警
3. ✅ 在 AWS Console 验证 Dashboard 正常显示
4. ✅ 验证所有 30 个告警已创建

### 定期维护
- 📅 **每周**: 检查告警状态，确认是否有异常
- 📅 **每月**: 回顾告警历史，调整阈值（如需要）
- 📅 **发布前**: 打开 Dashboard 实时监控

### 特别注意
⚠️ **磁盘空间监控**:
- Release 环境只有 40GB 存储
- 当可用空间 < 10GB 时会触发 Warning
- 当可用空间 < 5GB 时会触发 Critical
- 建议定期清理旧数据或扩容

⚠️ **内存监控**:
- pgsqlrel-backstage 是 t3.micro，内存较小
- 阈值设置为 512MB
- 如果经常触发告警，考虑升级到 t3.small

## 技术要点

### 实例特定配置

#### pgsqlrel (db.t3.small)
- vCPUs: 2
- Memory: ~2GB
- max_connections: 225
- 连接数 Warning: 158 (70%)
- 连接数 Critical: 191 (85%)

#### pgsqlrel-backstage (db.t3.micro)
- vCPUs: 2
- Memory: ~1GB
- max_connections: 112
- 连接数 Warning: 78 (70%)
- 连接数 Critical: 95 (85%)
- **内存告警**: 512MB (比其他环境低)

### 告警设计原则

1. **阈值设置**: 参考 Production，但针对小型实例调整
2. **评估周期**:
   - Warning: 5分钟内 5个数据点
   - Critical: 3分钟内 3个数据点
3. **Missing Data**: 设置为 `notBreaching`
4. **无 SNS**: 不设置 `--alarm-actions` 参数

## 故障排查

### Dashboard 未显示数据

**可能原因**: 实例刚启动或指标名称错误

**解决方法**:
```bash
# 检查实例状态
aws --profile gemini-pro_ck rds describe-db-instances \
    --region ap-east-1 \
    --db-instance-identifier pgsqlrel

# 检查可用指标
aws --profile gemini-pro_ck cloudwatch list-metrics \
    --namespace AWS/RDS \
    --dimensions Name=DBInstanceIdentifier,Value=pgsqlrel \
    --region ap-east-1
```

### 磁盘空间告警频繁触发

**解决方案**:
1. 清理不需要的数据
2. 扩容存储空间
3. 调整告警阈值

```bash
# 检查当前存储使用
aws --profile gemini-pro_ck rds describe-db-instances \
    --region ap-east-1 \
    --db-instance-identifier pgsqlrel \
    --query 'DBInstances[0].{AllocatedStorage:AllocatedStorage,StorageType:StorageType}'

# 扩容（如需要）
aws --profile gemini-pro_ck rds modify-db-instance \
    --region ap-east-1 \
    --db-instance-identifier pgsqlrel \
    --allocated-storage 100 \
    --apply-immediately
```

### 内存告警频繁触发（pgsqlrel-backstage）

**解决方案**:
1. 升级实例类型: t3.micro → t3.small
2. 优化应用查询
3. 调整连接池配置

```bash
# 升级实例类型
aws --profile gemini-pro_ck rds modify-db-instance \
    --region ap-east-1 \
    --db-instance-identifier pgsqlrel-backstage \
    --db-instance-class db.t3.small \
    --apply-immediately
```

## 参考文档

- [Stress Monitoring Setup](STRESS_MONITORING_SETUP.md) - Stress 环境配置
- [RDS Monitoring Guide](RDS_MONITORING_GUIDE.md) - RDS 监控完整指南
- [Production RDS Dashboard](scripts/rds/README.md) - Production 环境配置
- [Alarm Configuration Quickstart](scripts/rds/ALARM-CONFIG-QUICKSTART.md) - 快速配置指南

## 环境对比总结

### 三个非生产环境监控配置

| 环境 | Dashboard | 实例数 | 告警数 | SNS | 月成本 |
|------|-----------|--------|--------|-----|--------|
| **Stress** | Stress-RDS-Dashboard | 3 | 45 | ❌ | $7.50 |
| **Release** | Release-RDS-Dashboard | 2 | 30 | ❌ | $6.00 |
| **Production** | Production-RDS-Dashboard | 5+ | 70+ | ✅ | $10+ |

### 总成本

- Stress + Release 监控: **$13.50/月**
- 仅监控，无通知成本
- 与 Production 相比节省 ~60% 成本

## 更新记录

- **2025-10-30**: 初始版本
  - 创建 Release-RDS-Dashboard
  - 创建 30 个 CloudWatch Alarms（无 SNS 通知）
  - 针对小型实例调整阈值配置
  - 完成所有脚本和文档

---

**项目**: aws-gemini-manager
**环境**: Release (ap-east-1)
**创建日期**: 2025-10-30
**状态**: ✅ Ready for Use

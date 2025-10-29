# Stress Environment RDS Monitoring Setup

## 概述

为 Stress 环境的 RDS 实例创建了完整的 CloudWatch 监控体系，包括 Dashboard 和 Alarms，完全参考 Production-RDS-Dashboard 的配置，但**不配置 SNS 通知**。

## 监控实例

| 实例名称 | 实例类型 | vCPUs | Max Connections | 状态 |
|---------|---------|-------|----------------|------|
| bingo-stress | db.t4g.medium | 2 | 450 | ✅ Active |
| bingo-stress-backstage | db.t4g.medium | 2 | 450 | ✅ Active |
| bingo-stress-loyalty | db.t4g.medium | 2 | 450 | ✅ Active |

## 创建的资源

### 1. CloudWatch Dashboard

**名称**: `Stress-RDS-Dashboard`

**包含的监控图表** (7个):
1. **CPU Utilization** - 所有 3 个实例的 CPU 使用率
   - Warning 线: 70%
   - Critical 线: 85%

2. **Database Load (DBLoad)** - 数据库负载
   - Warning 线: 3 (1.5x vCPUs)
   - Critical 线: 4 (2x vCPUs)

3. **Database Connections** - 连接数
   - Warning 线: 315 (70% of 450)
   - Critical 线: 383 (85% of 450)

4. **IOPS (Read/Write)** - 磁盘 I/O 操作
   - 显示每个实例的读写 IOPS

5. **Freeable Memory** - 可用内存
   - Warning 线: 1GB

6. **Free Storage Space** - 可用存储空间
   - Warning 线: 50GB
   - Critical 线: 20GB

7. **Latency (Read/Write)** - 读写延迟
   - Read Warning: 5ms
   - Write Warning: 10ms

### 2. CloudWatch Alarms

**总数**: 45 个告警 (3 实例 × 15 告警/实例)

**每个实例的告警** (15个):

#### CPU 告警 (2个)
- `RDS-{instance}-HighCPU-Warning` - CPU > 70% 持续 5 分钟
- `RDS-{instance}-HighCPU-Critical` - CPU > 85% 持续 3 分钟

#### 数据库负载告警 (2个)
- `RDS-{instance}-HighDBLoad-Warning` - DBLoad > 3 持续 5 分钟
- `RDS-{instance}-HighDBLoad-Critical` - DBLoad > 4 持续 3 分钟

#### 连接数告警 (2个)
- `RDS-{instance}-HighConnections-Warning` - Connections > 315 持续 5 分钟
- `RDS-{instance}-HighConnections-Critical` - Connections > 383 持续 3 分钟

#### ReadIOPS 告警 (2个)
- `RDS-{instance}-HighReadIOPS-Warning` - ReadIOPS > 1500 持续 5 分钟
- `RDS-{instance}-HighReadIOPS-Critical` - ReadIOPS > 2000 持续 3 分钟

#### WriteIOPS 告警 (2个)
- `RDS-{instance}-HighWriteIOPS-Warning` - WriteIOPS > 1200 持续 5 分钟
- `RDS-{instance}-HighWriteIOPS-Critical` - WriteIOPS > 1500 持续 3 分钟

#### 磁盘空间告警 (2个)
- `RDS-{instance}-LowDiskSpace-Warning` - 可用空间 < 50GB
- `RDS-{instance}-LowDiskSpace-Critical` - 可用空间 < 20GB

#### 内存告警 (1个)
- `RDS-{instance}-LowMemory-Warning` - 可用内存 < 1GB 持续 3 分钟

#### 读延迟告警 (1个)
- `RDS-{instance}-HighReadLatency` - 读延迟 > 5ms 持续 5 分钟

#### 写延迟告警 (1个)
- `RDS-{instance}-HighWriteLatency` - 写延迟 > 10ms 持续 5 分钟

## 关键特性

### ✅ 包含的功能
- ✅ 完整的监控指标（与 Production 相同）
- ✅ 所有告警阈值（与 Production 相同）
- ✅ Dashboard 可视化
- ✅ 告警状态记录
- ✅ CloudWatch Console 可查看

### ❌ 不包含的功能
- ❌ SNS 通知
- ❌ Slack 告警
- ❌ Email 通知
- ❌ 告警优先级分级（P0/P1/P2）

## 使用方法

### 创建 Dashboard

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/cloudwatch
./create-stress-dashboard.sh
```

### 创建告警

```bash
./create-stress-alarms.sh
```

### 查看 Dashboard

**AWS Console**:
```
https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=Stress-RDS-Dashboard
```

**AWS CLI**:
```bash
aws --profile gemini-pro_ck cloudwatch get-dashboard \
    --dashboard-name Stress-RDS-Dashboard \
    --region ap-east-1
```

### 查看告警状态

```bash
# 查看所有 stress 告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --alarm-name-prefix 'RDS-bingo-stress' \
    --output table

# 查看 ALARM 状态的告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --state-value ALARM \
    --query 'MetricAlarms[?contains(AlarmName, `stress`)]' \
    --output table
```

## 与 Production 环境对比

| 特性 | Production | Stress |
|------|-----------|--------|
| **监控指标** | ✅ 相同 | ✅ 相同 |
| **告警阈值** | ✅ 相同 | ✅ 相同 |
| **Dashboard** | Production-RDS-Dashboard | Stress-RDS-Dashboard |
| **SNS 通知** | ✅ 已配置 | ❌ 未配置 |
| **Slack 告警** | ✅ 已配置 | ❌ 未配置 |
| **告警数量** | ~70+ (含 replicas) | 45 |
| **优先级分级** | P0/P1/P2 | 统一级别 |

## 成本估算

### CloudWatch 费用

| 项目 | 数量 | 单价 | 月费用 |
|------|------|------|--------|
| Dashboard | 1 | $3/月 | $3.00 |
| Alarms | 45 | $0.10/alarm | $4.50 |
| Metrics | 基础指标 | 免费 | $0.00 |
| **总计** | - | - | **$7.50/月** |

## 文件清单

### 新创建的文件

```
aws-gemini-manager/
├── scripts/
│   └── cloudwatch/
│       ├── create-stress-dashboard.sh          # Dashboard 创建脚本
│       ├── create-stress-alarms.sh             # 告警创建脚本（无 SNS）
│       └── README-stress-monitoring.md         # 详细使用文档
└── STRESS_MONITORING_SETUP.md                  # 本文件（项目总结）
```

### 相关现有文件

```
aws-gemini-manager/
├── scripts/
│   ├── cloudwatch/
│   │   ├── create-rds-alarms.sh                # 通用告警创建（支持 SNS）
│   │   ├── delete-rds-alarms.sh                # 告警删除工具
│   │   └── list-bingo-stress-metrics.sh        # Stress 指标列表
│   └── rds/
│       ├── README.md                           # RDS 监控完整指南
│       ├── ALARM-CONFIG-QUICKSTART.md          # 告警配置快速入门
│       └── check-connections.sh                # 连接数检查工具
└── RDS_MONITORING_GUIDE.md                     # RDS 监控总指南
```

## 后续操作建议

### 立即执行
1. ✅ 运行 `create-stress-dashboard.sh` 创建 Dashboard
2. ✅ 运行 `create-stress-alarms.sh` 创建告警
3. ✅ 在 AWS Console 验证 Dashboard 正常显示
4. ✅ 验证所有 45 个告警已创建

### 定期维护
- 📅 **每周**: 检查告警状态，确认是否有异常
- 📅 **每月**: 回顾告警历史，调整阈值（如需要）
- 📅 **压测前**: 打开 Dashboard 实时监控

### 可选操作
- 🔔 如需通知，可后续配置 SNS Topic
- 📊 根据实际负载调整告警阈值
- 📈 添加自定义指标（如业务相关）

## 技术要点

### 告警设计原则

1. **阈值设置**: 完全参考 Production 环境的经验值
2. **评估周期**:
   - Warning: 5分钟内 5个数据点
   - Critical: 3分钟内 3个数据点
3. **Missing Data**: 设置为 `notBreaching`，避免数据缺失时误报
4. **无 SNS**: 不设置 `--alarm-actions` 参数

### Dashboard 设计原则

1. **布局**: 3列布局，每个图表宽度 8 或 12
2. **时间范围**: 默认显示最近 3 小时
3. **指标聚合**: 使用 5 分钟（300秒）周期
4. **标注线**: 在图表中显示 Warning 和 Critical 阈值

## 故障排查

### Dashboard 未显示数据

**可能原因**: 实例刚启动，还没有数据

**解决方法**: 等待 5-10 分钟后刷新

### 告警创建失败

**可能原因**: IAM 权限不足

**解决方法**:
```bash
# 检查权限
aws --profile gemini-pro_ck cloudwatch describe-alarms --region ap-east-1 --max-records 1

# 查看错误详情
./create-stress-alarms.sh 2>&1 | tee alarm-creation.log
```

### 告警状态异常

**检查步骤**:
1. 确认实例状态正常
2. 检查 CloudWatch 是否有最新数据
3. 查看告警历史记录

```bash
# 检查实例状态
aws --profile gemini-pro_ck rds describe-db-instances \
    --region ap-east-1 \
    --db-instance-identifier bingo-stress

# 查看最新指标
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-stress \
    --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
    --period 300 \
    --statistics Average \
    --region ap-east-1
```

## 参考文档

- [Stress Monitoring README](scripts/cloudwatch/README-stress-monitoring.md) - 详细使用指南
- [RDS Monitoring Guide](RDS_MONITORING_GUIDE.md) - RDS 监控完整指南
- [Production RDS Dashboard](scripts/rds/README.md) - Production 环境配置
- [Alarm Configuration Quickstart](scripts/rds/ALARM-CONFIG-QUICKSTART.md) - 快速配置指南

## 更新记录

- **2025-10-30**: 初始版本
  - 创建 Stress-RDS-Dashboard
  - 创建 45 个 CloudWatch Alarms（无 SNS 通知）
  - 完全参考 Production-RDS-Dashboard 配置
  - 所有脚本和文档完成

---

**项目**: aws-gemini-manager
**环境**: Stress (ap-east-1)
**创建日期**: 2025-10-30
**状态**: ✅ Ready for Use

# Stress Environment RDS Monitoring

## Overview

本文档说明如何为 Stress 环境的 RDS 实例创建 CloudWatch Dashboard 和 Alarms。

### 监控实例

- **bingo-stress** (db.t4g.medium)
- **bingo-stress-backstage** (db.t4g.medium)
- **bingo-stress-loyalty** (db.t4g.medium)

### 与 Production 环境的差异

| 特性 | Production-RDS-Dashboard | Stress-RDS-Dashboard |
|------|-------------------------|---------------------|
| **SNS 通知** | ✅ 配置了 Slack 通知 | ❌ 无通知（仅监控） |
| **告警优先级** | P0/P1/P2 分级 | 统一级别 |
| **监控指标** | 完全相同 | 完全相同 |
| **告警阈值** | 完全相同 | 完全相同 |

## 快速开始

### 1. 创建 Dashboard

```bash
cd scripts/cloudwatch
./create-stress-dashboard.sh
```

**创建内容:**
- Dashboard 名称: `Stress-RDS-Dashboard`
- 7个监控图表，涵盖所有关键指标
- 包含阈值标线（Warning 和 Critical）

**监控指标:**
1. CPU Utilization (%)
2. Database Load (DBLoad)
3. Database Connections
4. IOPS (Read/Write)
5. Freeable Memory
6. Free Storage Space
7. Latency (Read/Write)

### 2. 创建告警

```bash
./create-stress-alarms.sh
```

**创建内容:**
- 每个实例 15 个告警
- 总计 45 个告警（3 实例 × 15）
- **无 SNS 通知** - 仅用于监控和记录

**告警类型:**
- CPU 使用率 (Warning: 70%, Critical: 85%)
- 数据库负载 (Warning: 3, Critical: 4)
- 连接数 (Warning: 315, Critical: 383)
- ReadIOPS (Warning: 1500, Critical: 2000)
- WriteIOPS (Warning: 1200, Critical: 1500)
- 磁盘空间 (Warning: <50GB, Critical: <20GB)
- 可用内存 (Warning: <1GB)
- 读延迟 (Warning: >5ms)
- 写延迟 (Warning: >10ms)

## 告警配置详情

### CPU 使用率告警

```bash
# Warning: CPU > 70% 持续 5 分钟
RDS-${instance}-HighCPU-Warning

# Critical: CPU > 85% 持续 3 分钟
RDS-${instance}-HighCPU-Critical
```

### 数据库负载告警

```bash
# Warning: DBLoad > 3 (1.5x vCPUs) 持续 5 分钟
RDS-${instance}-HighDBLoad-Warning

# Critical: DBLoad > 4 (2x vCPUs) 持续 3 分钟
RDS-${instance}-HighDBLoad-Critical
```

### 连接数告警

基于 db.t4g.medium 的 max_connections = 450:

```bash
# Warning: Connections > 315 (70%) 持续 5 分钟
RDS-${instance}-HighConnections-Warning

# Critical: Connections > 383 (85%) 持续 3 分钟
RDS-${instance}-HighConnections-Critical
```

### IOPS 告警

```bash
# ReadIOPS Warning: > 1500 持续 5 分钟
RDS-${instance}-HighReadIOPS-Warning

# ReadIOPS Critical: > 2000 持续 3 分钟
RDS-${instance}-HighReadIOPS-Critical

# WriteIOPS Warning: > 1200 持续 5 分钟
RDS-${instance}-HighWriteIOPS-Warning

# WriteIOPS Critical: > 1500 持续 3 分钟
RDS-${instance}-HighWriteIOPS-Critical
```

### 存储告警

```bash
# Warning: 可用空间 < 50GB
RDS-${instance}-LowDiskSpace-Warning

# Critical: 可用空间 < 20GB
RDS-${instance}-LowDiskSpace-Critical
```

### 内存告警

```bash
# Warning: 可用内存 < 1GB 持续 3 分钟
RDS-${instance}-LowMemory-Warning
```

### 延迟告警

```bash
# 读延迟 > 5ms 持续 5 分钟
RDS-${instance}-HighReadLatency

# 写延迟 > 10ms 持续 5 分钟
RDS-${instance}-HighWriteLatency
```

## 查看和管理

### 查看 Dashboard

**AWS Console:**
```
https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=Stress-RDS-Dashboard
```

**AWS CLI:**
```bash
aws --profile gemini-pro_ck cloudwatch get-dashboard \
    --dashboard-name Stress-RDS-Dashboard \
    --region ap-east-1
```

### 查看告警

**列出所有 stress 告警:**
```bash
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --alarm-name-prefix 'RDS-bingo-stress' \
    --output table
```

**查看 ALARM 状态的告警:**
```bash
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --state-value ALARM \
    --query 'MetricAlarms[?contains(AlarmName, `stress`)].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table
```

**查看特定实例的告警:**
```bash
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --alarm-name-prefix 'RDS-bingo-stress-' \
    --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
    --output table
```

### 删除告警

**删除单个实例的告警:**
```bash
./delete-rds-alarms.sh bingo-stress
```

**删除所有 stress 告警:**
```bash
for instance in bingo-stress bingo-stress-backstage bingo-stress-loyalty; do
    ./delete-rds-alarms.sh "$instance"
done
```

## 告警与通知

### ❌ 无 SNS 通知

Stress 环境的告警**不会**发送任何通知：
- ✅ 告警状态正常记录在 CloudWatch
- ✅ 可以在 Console 和 Dashboard 中查看
- ❌ 不会发送 Slack 消息
- ❌ 不会发送 Email
- ❌ 不会发送 SMS

### 如需添加通知

如果将来需要为 Stress 环境添加通知，可以：

1. **创建 SNS Topic:**
```bash
aws --profile gemini-pro_ck sns create-topic \
    --name rds-stress-alerts \
    --region ap-east-1
```

2. **重新运行告警创建脚本（使用原有的 create-rds-alarms.sh）:**
```bash
../rds/create-rds-alarms.sh bingo-stress arn:aws:sns:ap-east-1:ACCOUNT_ID:rds-stress-alerts
../rds/create-rds-alarms.sh bingo-stress-backstage arn:aws:sns:ap-east-1:ACCOUNT_ID:rds-stress-alerts
../rds/create-rds-alarms.sh bingo-stress-loyalty arn:aws:sns:ap-east-1:ACCOUNT_ID:rds-stress-alerts
```

## 监控最佳实践

### 定期检查告警状态

建议每周检查一次 Stress 环境的告警状态：

```bash
# 检查是否有告警触发
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --state-value ALARM \
    --query 'MetricAlarms[?contains(AlarmName, `stress`)].[AlarmName,StateValue,StateUpdatedTimestamp]' \
    --output table
```

### Dashboard 使用建议

1. **定期查看**: 每周至少查看一次 Dashboard
2. **压力测试前**: 压测前打开 Dashboard 实时监控
3. **异常排查**: 遇到问题时首先查看 Dashboard 历史数据

### 阈值调整

如果发现告警频繁误报或漏报，可以调整阈值：

1. 编辑 `create-stress-alarms.sh`
2. 修改相应的阈值参数
3. 重新运行脚本覆盖现有告警

## 成本说明

### CloudWatch 费用

- **Dashboard**: 每月 $3/dashboard
- **Alarms**: 前 10 个免费，之后 $0.10/alarm/月
- **Metrics**: RDS 基础指标免费

**Stress 环境预估成本:**
- Dashboard: $3/月
- Alarms: 45 个告警 × $0.10 = $4.50/月
- **总计**: ~$7.50/月

## 故障排查

### Dashboard 创建失败

```bash
# 检查 Dashboard 是否存在
aws --profile gemini-pro_ck cloudwatch list-dashboards \
    --region ap-east-1 \
    --query 'DashboardEntries[?DashboardName==`Stress-RDS-Dashboard`]'

# 删除并重新创建
aws --profile gemini-pro_ck cloudwatch delete-dashboards \
    --dashboard-names Stress-RDS-Dashboard \
    --region ap-east-1

./create-stress-dashboard.sh
```

### 告警创建失败

```bash
# 检查 IAM 权限
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --region ap-east-1 \
    --max-records 1

# 如果权限正常，删除并重新创建
./delete-rds-alarms.sh bingo-stress
./create-stress-alarms.sh
```

### 实例不存在

```bash
# 确认实例状态
aws --profile gemini-pro_ck rds describe-db-instances \
    --region ap-east-1 \
    --query 'DBInstances[?contains(DBInstanceIdentifier, `stress`)].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}' \
    --output table
```

## 参考文档

- [Production RDS Monitoring Guide](../rds/README.md)
- [CloudWatch Metrics Documentation](../../RDS_MONITORING_GUIDE.md)
- [Alarm Configuration Quickstart](../rds/ALARM-CONFIG-QUICKSTART.md)

## 相关脚本

- `create-stress-dashboard.sh` - 创建 Stress-RDS-Dashboard
- `create-stress-alarms.sh` - 创建所有 Stress 告警（无 SNS）
- `../rds/create-rds-alarms.sh` - 通用告警创建工具（支持 SNS）
- `delete-rds-alarms.sh` - 删除指定实例的告警
- `list-bingo-stress-metrics.sh` - 列出 stress 实例的指标

## 更新历史

- **2025-10-30**: 初始版本
  - 创建 Stress-RDS-Dashboard
  - 创建 45 个告警（无 SNS 通知）
  - 完全参考 Production-RDS-Dashboard 的配置

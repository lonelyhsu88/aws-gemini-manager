# RDS 监控和告警配置指南

本指南详细说明 bingo-prd RDS 实例的监控和告警配置。

## 📋 目录

1. [Performance Insights](#performance-insights)
2. [连接池监控](#连接池监控)
3. [CloudWatch 告警](#cloudwatch-告警)
4. [I/O 调查工具](#io-调查工具)
5. [常见问题排查](#常见问题排查)

---

## 🔍 Performance Insights

### 当前状态

**bingo-prd** 已启用 Performance Insights：
- **状态**: ✅ 已启用
- **保留期**: 7 天（免费层）
- **访问方式**: AWS Console → RDS → bingo-prd → Performance Insights

### 功能特性

Performance Insights 提供以下监控能力：

1. **Top SQL 分析**
   - 查看消耗最多资源的 SQL 查询
   - 按执行时间、I/O、CPU 等维度排序
   - 实时和历史数据对比

2. **等待事件分析**
   - 识别数据库等待的资源类型（CPU、I/O、Lock 等）
   - 诊断性能瓶颈
   - 等待事件类型分布图

3. **数据库负载 (DBLoad)**
   - 实时数据库活动会话数
   - 与 vCPU 容量对比
   - DBLoad > vCPUs 表示数据库过载

### 使用建议

**日常监控**:
- 每天查看 Top SQL，识别异常查询
- 关注 DBLoad 是否经常超过 vCPU 数量（bingo-prd 为 2）
- 查看等待事件分布，识别主要瓶颈类型

**故障排查**:
- 在告警触发时，立即查看 Performance Insights
- 对比正常时段和异常时段的 Top SQL
- 使用时间范围选择器精确定位问题时段

---

## 📊 连接池监控

### 监控脚本

创建了专门的连接池监控脚本：`scripts/rds/monitor-connection-pool.sh`

### 基础用法

#### 1. 仅使用 CloudWatch 监控（无需数据库凭证）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager
./scripts/rds/monitor-connection-pool.sh bingo-prd
```

**输出内容**:
- ✅ 当前连接数（5分钟平均、峰值、最低）
- ✅ 连接数使用率（相对于最大连接数 901）
- ✅ CPU 使用率
- ✅ 数据库负载（DBLoad）
- ✅ Read/Write IOPS
- ✅ 24小时峰值统计
- ✅ 健康评估

#### 2. 结合数据库直接查询（需要数据库凭证）

```bash
./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query \
    --db-host bingo-prd.xxx.rds.amazonaws.com \
    --db-user your_user \
    --db-password 'your_password'
```

**额外输出**:
- 实时连接统计（active、idle、idle in transaction）
- 按应用分组的连接分布
- 长时间运行的查询（>10秒）
- 锁等待检查

### 监控指标说明

| 指标 | 正常范围 | 警告阈值 | 严重阈值 | 说明 |
|------|---------|---------|---------|------|
| **连接数** | < 60% | 60-80% | > 80% | 相对于 max_connections (901) |
| **CPU 使用率** | < 60% | 60-80% | > 80% | CPU 百分比 |
| **DBLoad** | < 1.5 | 1.5-3 | > 4 | 活动会话数，bingo-prd 有 2 vCPUs |
| **ReadIOPS** | 500-600 | 1000-1500 | > 2000 | 基于历史基线 |
| **WriteIOPS** | 800-950 | 1000-1200 | > 1500 | 基于历史基线 |

### 定时监控建议

创建 cron job 定期运行监控：

```bash
# 每5分钟监控一次
*/5 * * * * /path/to/monitor-connection-pool.sh bingo-prd >> /var/log/rds-monitor.log 2>&1

# 每小时生成一次完整报告（含数据库查询）
0 * * * * /path/to/monitor-connection-pool.sh bingo-prd --with-db-query --db-host ... >> /var/log/rds-detailed.log 2>&1
```

---

## 🚨 CloudWatch 告警

### 已创建的告警

为 **bingo-prd** 创建了 15 个告警，覆盖关键性能指标：

#### 1. CPU 使用率告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighCPU-Warning` | > 70% | 5分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-HighCPU-Critical` | > 85% | 3分钟 | 🚨 严重 |

#### 2. 数据库负载告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighDBLoad-Warning` | > 3 (1.5x vCPUs) | 5分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-HighDBLoad-Critical` | > 4 (2x vCPUs) | 3分钟 | 🚨 严重 |

**说明**: bingo-prd 有 2 个 vCPUs，DBLoad > 2 表示有查询在排队等待。

#### 3. 连接数告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighConnections-Warning` | > 630 (70%) | 5分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-HighConnections-Critical` | > 765 (85%) | 3分钟 | 🚨 严重 |

**最大连接数**: 901

#### 4. ReadIOPS 告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighReadIOPS-Warning` | > 1500 | 5分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-HighReadIOPS-Critical` | > 2000 | 3分钟 | 🚨 严重 |

**基线**: 正常 500-600 IOPS

#### 5. WriteIOPS 告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighWriteIOPS-Warning` | > 1200 | 5分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-HighWriteIOPS-Critical` | > 1500 | 3分钟 | 🚨 严重 |

**基线**: 正常 800-950 IOPS

#### 6. 磁盘空间告警（2个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-LowDiskSpace-Warning` | < 50GB | 10分钟 | ⚠️ 警告 |
| `RDS-bingo-prd-LowDiskSpace-Critical` | < 20GB | 5分钟 | 🚨 严重 |

#### 7. 内存告警（1个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-LowMemory-Warning` | < 1GB | 3分钟 | ⚠️ 警告 |

#### 8. 读延迟告警（1个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighReadLatency` | > 5ms | 5分钟 | ⚠️ 警告 |

#### 9. 写延迟告警（1个）

| 告警名称 | 阈值 | 持续时间 | 级别 |
|---------|------|---------|------|
| `RDS-bingo-prd-HighWriteLatency` | > 10ms | 5分钟 | ⚠️ 警告 |

### 告警管理命令

#### 查看所有告警状态

```bash
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --alarm-name-prefix 'RDS-bingo-prd-' \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

#### 查看触发的告警（ALARM 状态）

```bash
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --alarm-name-prefix 'RDS-bingo-prd-' \
    --state-value ALARM \
    --output table
```

#### 查看告警历史

```bash
aws --profile gemini-pro_ck cloudwatch describe-alarm-history \
    --alarm-name RDS-bingo-prd-HighDBLoad-Critical \
    --max-records 10
```

#### 删除所有告警

```bash
./scripts/cloudwatch/delete-rds-alarms.sh bingo-prd
```

#### 为其他实例创建告警

```bash
# bingo-prd-backstage
./scripts/cloudwatch/create-rds-alarms.sh bingo-prd-backstage

# bingo-stress
./scripts/cloudwatch/create-rds-alarms.sh bingo-stress
```

### 配置 SNS 通知

当前告警已创建但未配置通知。要添加 SNS 通知：

#### 1. 创建 SNS Topic

```bash
aws --profile gemini-pro_ck sns create-topic --name rds-alerts
```

#### 2. 订阅 Email

```bash
aws --profile gemini-pro_ck sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:YOUR_ACCOUNT:rds-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

#### 3. 重新创建告警（带 SNS）

```bash
# 先删除现有告警
./scripts/cloudwatch/delete-rds-alarms.sh bingo-prd

# 重新创建并配置 SNS
./scripts/cloudwatch/create-rds-alarms.sh bingo-prd arn:aws:sns:us-east-1:YOUR_ACCOUNT:rds-alerts
```

---

## 🔧 I/O 调查工具

### ⚠️ 重要：调查脚本也会产生负载

诊断脚本本身也会消耗数据库资源。提供了两个版本：

| 脚本 | 执行时间 | DBLoad 影响 | 适用场景 |
|------|---------|------------|---------|
| **investigate-io-spike-lite.sh** | 0.5-2秒 | +0.3-0.5 | 🚨 数据库高负载时 (DBLoad > 8) |
| **investigate-io-spike.sh** | 3-8秒 | +0.7-1.5 | ✅ 数据库正常负载时 (DBLoad < 8) |

**详细安全指南**: 参考 `scripts/rds/INVESTIGATION_SAFETY_GUIDE.md`

### 使用决策

```
当前 DBLoad 是多少？
│
├─ DBLoad < 8 (正常/中等)
│  └─ ✅ 使用完整版
│     ./investigate-io-spike.sh -h ... -u ... -w ...
│
└─ DBLoad > 8 (高负载)
   └─ ⚠️  使用轻量级版本
      ./investigate-io-spike-lite.sh -h ... -u ... -w ...
```

### 使用方法

**完整版**（正常负载时）:
```bash
./scripts/rds/investigate-io-spike.sh \
    -h bingo-prd.xxx.rds.amazonaws.com \
    -u your_admin_user \
    -w 'your_password' \
    -d postgres

# 会显示警告并要求确认
```

**轻量级版**（高负载时）:
```bash
./scripts/rds/investigate-io-spike-lite.sh \
    -h bingo-prd.xxx.rds.amazonaws.com \
    -u readonly_user \
    -w 'your_password'

# 快速执行，无需确认
```

### 分析内容

脚本会执行以下 9 项分析：

#### 1. ✅ pg_stat_statements 检查
- 确认查询统计扩展是否启用
- 如未启用，提供启用方法

#### 2. 📊 最消耗 I/O 的 SQL 语句
- 按总 I/O 块数排序
- 显示读取块数、写入块数、执行次数
- 查询预览（前80字符）

#### 3. 🔄 执行次数最多的 SQL 语句
- 识别高频查询
- 可能是连接池配置或 N+1 查询问题

#### 4. 🐌 慢查询（平均执行时间 > 1秒）
- 需要优化的查询
- 显示平均执行时间和 I/O 块数

#### 5. 📋 表的 I/O 活动统计
- 顺序扫描 vs 索引扫描
- 插入/更新/删除统计
- 存活行数 vs 死亡行数

#### 6. ⚠️ 可能缺失索引的表
- 顺序扫描占比 > 50%
- 表行数 > 10,000
- **重点优化对象**

#### 7. 🧹 Vacuum 和 Autovacuum 状态
- 死亡行数统计
- 最后 vacuum/analyze 时间
- 表膨胀评估

#### 8. 💾 最大的表（Top 10）
- 表大小、索引大小
- 识别需要分区或归档的大表

#### 9. 📁 临时文件使用情况
- 表示 work_mem 可能不足
- 需要考虑增加内存或优化查询

### 输出示例

```
================================================================================================
🔍 I/O Spike 根本原因分析
================================================================================================
数据库: bingo-prd.xxx.rds.amazonaws.com
时间: 2025-10-29 22:30:00

1️⃣  检查 pg_stat_statements 扩展
------------------------------------------------------------------------------------------------
✅ pg_stat_statements 已启用

2️⃣  最消耗 I/O 的 SQL 语句 (按总 I/O 排序)
------------------------------------------------------------------------------------------------
 queryid  | 执行次数 | 总执行时间(秒) | 平均执行时间(秒) | 读取块数 | 写入块数 | 总I/O块数 | 查询预览
----------+----------+---------------+-----------------+----------+----------+-----------+----------
 12345678 |   15000  |    1234.56    |       0.08      |  500000  |  200000  |  700000   | SELECT ...
...
```

### 调查流程建议

当发现 I/O 异常时：

1. **立即运行调查脚本**
   ```bash
   ./scripts/rds/investigate-io-spike.sh -h ... -u ... -w ...
   ```

2. **查看 Performance Insights**
   - AWS Console → RDS → bingo-prd → Performance Insights
   - 选择异常时间段
   - 查看 Top SQL 和等待事件

3. **关联分析**
   - 检查应用日志中的异常操作
   - 查看 crontab 是否有定时任务
   - 确认是否有批量操作或数据同步

4. **优化措施**
   - 添加缺失的索引
   - 优化慢查询
   - 调整批量操作的执行时间或批次大小
   - 执行 VACUUM ANALYZE

---

## 🛠️ 常见问题排查

### Q1: DBLoad 持续超过 vCPU 数量怎么办？

**症状**: DBLoad > 2 (bingo-prd 有 2 vCPUs)

**可能原因**:
1. I/O 密集型操作（读/写 IOPS 过高）
2. 大量并发查询
3. 慢查询导致查询排队
4. 锁等待

**排查步骤**:
1. 查看 Performance Insights → 等待事件类型
   - 如果是 "IO" 类型，说明 I/O 瓶颈
   - 如果是 "CPU" 类型，说明 CPU 瓶颈
   - 如果是 "Lock" 类型，说明锁竞争

2. 运行 I/O 调查脚本
   ```bash
   ./scripts/rds/investigate-io-spike.sh -h ... -u ... -w ...
   ```

3. 查看连接池状态
   ```bash
   ./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query ...
   ```

**解决方案**:
- 短期：优化慢查询、添加索引
- 中期：实施读写分离、使用只读副本
- 长期：升级实例规格（db.m6g.xlarge 或更大）

### Q2: 连接数接近最大值怎么办？

**症状**: DatabaseConnections > 630 (70% of 901)

**可能原因**:
1. 连接泄漏（未正确关闭连接）
2. 连接池配置不当
3. 应用实例数量增加
4. 大量 idle in transaction 连接

**排查步骤**:
1. 检查 idle in transaction 连接
   ```bash
   ./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query ...
   ```

2. 查看连接来源 IP 分布
   ```sql
   SELECT client_addr, COUNT(*), state
   FROM pg_stat_activity
   WHERE pid != pg_backend_pid()
   GROUP BY client_addr, state
   ORDER BY COUNT(*) DESC;
   ```

**解决方案**:
- 修复应用代码中的连接泄漏
- 配置连接池超时时间（idle_timeout）
- 使用连接池（如 PgBouncer）
- 终止长时间 idle 的连接

### Q3: ReadIOPS 突然飙升怎么办？

**症状**: ReadIOPS 从 500-600 突然飙升到 2000+

**可能原因**:
1. 定时任务触发（批量查询、报表生成）
2. 缺失索引导致全表扫描
3. 缓存失效导致大量磁盘读取
4. 应用层面的 N+1 查询问题

**排查步骤**:
1. 检查是否有定时任务
   ```bash
   crontab -l
   # 查看应用日志
   ```

2. 运行 I/O 调查脚本，查看"缺失索引"部分

3. 查看 Performance Insights Top SQL

**解决方案**:
- 将批量操作移到低峰期
- 添加必要的索引
- 批量操作分批执行，减小单次数据量
- 增加应用层缓存

### Q4: 如何识别慢查询？

**方法1: Performance Insights**
- AWS Console → RDS → bingo-prd → Performance Insights
- 按 "Total time" 排序
- 查看平均执行时间

**方法2: pg_stat_statements**
```bash
./scripts/rds/investigate-io-spike.sh -h ... -u ... -w ...
# 查看 "慢查询" 部分
```

**方法3: 实时监控**
```bash
./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query ...
# 查看 "长时间运行的查询" 部分
```

### Q5: 告警太多，如何调整阈值？

如果告警过于频繁，可以调整阈值：

1. **编辑告警创建脚本**
   ```bash
   vi scripts/cloudwatch/create-rds-alarms.sh
   # 修改相应的阈值
   ```

2. **重新创建告警**
   ```bash
   ./scripts/cloudwatch/delete-rds-alarms.sh bingo-prd
   ./scripts/cloudwatch/create-rds-alarms.sh bingo-prd
   ```

3. **或者直接在 AWS Console 修改**
   - CloudWatch → Alarms
   - 选择告警 → Actions → Edit

---

## 📚 相关文档

- [AWS RDS Performance Insights User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [PostgreSQL Monitoring](https://www.postgresql.org/docs/14/monitoring.html)
- [pg_stat_statements Documentation](https://www.postgresql.org/docs/14/pgstatstatements.html)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)

---

## 🔄 更新记录

| 日期 | 版本 | 更新内容 |
|------|------|---------|
| 2025-10-29 | 1.0 | 初始版本：配置 Performance Insights、连接池监控、CloudWatch 告警 |

---

## 📞 支持

如有问题，请联系 DevOps 团队或参考项目 README。

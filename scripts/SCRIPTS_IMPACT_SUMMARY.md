# 所有脚本的负载影响总结

## 📊 快速参考表

| 脚本 | 对数据库的影响 | 执行时间 | DBLoad 影响 | 确认提示 | 何时使用 |
|------|--------------|---------|------------|---------|---------|
| **CloudWatch 相关** |
| `create-rds-alarms.sh` | ✅ 无影响 | 5-10秒 | 0 | ✅ 有 | 配置告警时 |
| `delete-rds-alarms.sh` | ✅ 无影响 | 1-2秒 | 0 | ✅ 有 | 删除告警时 |
| `list-bingo-stress-metrics.sh` | ✅ 无影响 | 1-2秒 | 0 | ❌ 无 | 查看可用指标 |
| **RDS 监控相关** |
| `monitor-connection-pool.sh` | ✅ 极低 | 0.2-1秒 | +0.1-0.3 | ❌ 无 | ✅ 任何时候 |
| `monitor-connection-pool.sh --with-db-query` | ⚠️ 低 | 1-3秒 | +0.3-0.8 | ❌ 无 | DBLoad < 10 |
| `check-connections.sh` | ✅ 无影响 | 2-5秒 | 0 | ❌ 无 | ✅ 任何时候 |
| `check-connections-peak.sh` | ✅ 无影响 | 3-8秒 | 0 | ❌ 无 | ✅ 任何时候 |
| `list-instances.sh` | ✅ 无影响 | 1-2秒 | 0 | ❌ 无 | ✅ 任何时候 |
| **RDS 调查相关** |
| `investigate-io-spike-lite.sh` | ⚠️ 中 | 0.5-2秒 | +0.3-0.5 | ❌ 无 | DBLoad < 12 |
| `investigate-io-spike.sh` | ⚠️ 中-高 | 3-8秒 | +0.7-1.5 | ✅ 有 | DBLoad < 8 |
| `query-active-connections.sh` | ⚠️ 中 | 1-3秒 | +0.3-0.8 | ❌ 无 | DBLoad < 5 |

---

## 🎯 详细说明

### 1. CloudWatch 脚本（零数据库影响）

#### create-rds-alarms.sh
```bash
./scripts/cloudwatch/create-rds-alarms.sh bingo-prd
```

**影响**:
- ✅ **对数据库零影响**（仅调用 CloudWatch API）
- 不占用数据库连接
- 不消耗数据库资源

**功能**:
- 创建 15 个 CloudWatch 告警
- 检查现有告警
- 显示将要创建的告警列表
- ✅ **有确认提示**

**使用时机**:
- ✅ 任何时候都可以安全使用
- 初次配置监控
- 调整告警阈值

**输出示例**:
```
📊 创建 RDS CloudWatch 告警
实例: bingo-prd
类型: db.m6g.large

检查现有告警...
⚠️  发现 15 个现有告警
继续执行将会覆盖这些告警的配置。

即将创建 15 个告警：
  - CPU 使用率告警 (2个)
  - 数据库负载告警 (2个)
  ...

✓ 此操作对数据库无任何负载影响（仅配置 CloudWatch）

确认创建这些告警？(y/N)
```

---

#### delete-rds-alarms.sh
```bash
./scripts/cloudwatch/delete-rds-alarms.sh bingo-prd
```

**影响**:
- ✅ **对数据库零影响**

**功能**:
- 列出所有匹配的告警
- ✅ **有确认提示**
- 批量删除告警

---

### 2. RDS 监控脚本（极低-低影响）

#### monitor-connection-pool.sh（推荐）
```bash
# 方式1：仅 CloudWatch（零数据库影响）
./scripts/rds/monitor-connection-pool.sh bingo-prd

# 方式2：含数据库查询（低影响）
./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query \
    --db-host ... --db-user ... --db-password ...
```

**影响对比**:

| 方式 | 数据库连接 | DBLoad 影响 | 查询内容 |
|------|-----------|------------|---------|
| 仅 CloudWatch | ❌ 不连接 | 0 | CloudWatch 指标 |
| 含数据库查询 | ✅ 1个 | +0.3-0.8 | 实时连接状态、长查询、锁等待 |

**查询内容**（仅 --with-db-query）:
1. ✅ 连接统计（轻量）
2. ✅ 按应用分组（轻量）
3. ✅ 长查询检查（轻量，> 10秒）
4. ✅ 锁等待检查（轻量）

**使用建议**:
```
当前 DBLoad 是多少？
│
├─ DBLoad > 10
│  └─ 仅使用 CloudWatch
│     ./monitor-connection-pool.sh bingo-prd
│
└─ DBLoad < 10
   └─ 可以加数据库查询
      ./monitor-connection-pool.sh bingo-prd --with-db-query ...
```

---

#### check-connections.sh / check-connections-peak.sh
```bash
./scripts/rds/check-connections.sh
./scripts/rds/check-connections-peak.sh
```

**影响**:
- ✅ **对数据库零影响**（仅 CloudWatch API）
- 批量查询多个 RDS 实例的连接数

**使用时机**:
- ✅ 任何时候
- 快速浏览所有实例状态

---

### 3. RDS 调查脚本（中-高影响）⚠️

#### investigate-io-spike-lite.sh（轻量级）
```bash
./scripts/rds/investigate-io-spike-lite.sh \
    -h bingo-prd.xxx.rds.amazonaws.com \
    -u readonly_user -w 'password'
```

**影响**:
- ⚠️ DBLoad: +0.3-0.5
- ⚠️ 占用 1 个数据库连接
- ⚠️ 执行时间: 0.5-2 秒

**查询内容（5项）**:
1. ✅ pg_stat_statements 检查（极轻量）
2. ✅ Top 10 I/O 查询（轻量，限制 10 行）
3. ✅ Top 10 慢查询（轻量，限制 10 行）
4. ✅ 当前活动查询（极轻量）
5. ✅ Top 5 活跃表（轻量，限制 5 行）

**跳过的查询**:
- ❌ 表大小查询（避免元数据扫描）
- ❌ 锁等待 JOIN（避免复杂 JOIN）
- ❌ 详细索引分析

**使用时机**:
- ✅ DBLoad 8-12（高负载）
- ✅ 需要快速诊断
- ✅ 多人同时调查

**确认提示**: ❌ 无（快速执行）

---

#### investigate-io-spike.sh（完整版）
```bash
./scripts/rds/investigate-io-spike.sh \
    -h bingo-prd.xxx.rds.amazonaws.com \
    -u admin_user -w 'password'
```

**影响**:
- ⚠️⚠️ DBLoad: +0.7-1.5
- ⚠️⚠️ 占用 1 个数据库连接
- ⚠️⚠️ 执行时间: 3-8 秒

**查询内容（9项）**:
1. ✅ pg_stat_statements 检查
2. ⚠️ 最消耗 I/O 的查询（中等）
3. ⚠️ 执行次数最多的查询（中等）
4. ⚠️ 慢查询分析（中等）
5. ⚠️ 表 I/O 统计（中等）
6. ⚠️ 缺失索引分析（中等）
7. ⚠️ Vacuum 状态（中等）
8. 🚨 表大小查询（可能重，扫描元数据）
9. 🚨 锁等待 JOIN（可能重，多表 JOIN）

**使用时机**:
- ✅ DBLoad < 8（正常/中等负载）
- ✅ 事后详细分析
- ❌ 数据库高负载时（DBLoad > 8）

**确认提示**: ✅ **有**

**输出示例**:
```
🔍 I/O Spike 根本原因分析 (完整版)
数据库: bingo-prd.xxx.rds.amazonaws.com

⚠️  负载影响警告
此脚本会执行多个诊断查询，预计影响:
  - 执行时间: 3-8 秒
  - DBLoad 影响: +0.7-1.5
  - 占用 1 个数据库连接

⚠️  如果当前 DBLoad > 10，建议使用轻量级版本:
     ./investigate-io-spike-lite.sh

确认继续执行完整分析？(y/N)
```

---

#### query-active-connections.sh
```bash
./scripts/rds/query-active-connections.sh \
    -h ... -d postgres -u ... -w ...
```

**影响**:
- ⚠️ DBLoad: +0.3-0.8
- ⚠️ 执行时间: 1-3 秒

**查询内容**:
1. 连接统计（按 IP）
2. 当前活动查询
3. 长查询（> 5秒）
4. 数据库统计
5. 锁等待检查

**使用时机**:
- ✅ DBLoad < 5
- 详细连接分析

**确认提示**: ❌ 无

---

## 🚦 使用决策流程图

```
收到性能问题报告
    ↓
【第一步】查看 Performance Insights (零影响)
    ↓
【第二步】检查 CloudWatch 告警
    ↓
aws cloudwatch describe-alarms --state-value ALARM
    ↓
【第三步】快速监控
    ↓
./monitor-connection-pool.sh bingo-prd (零影响)
    ↓
【第四步】判断 DBLoad
    ↓
    ├─ DBLoad < 3 (正常)
    │  └─ ✅ 任何工具都可用
    │     - investigate-io-spike.sh (完整分析)
    │     - query-active-connections.sh
    │
    ├─ DBLoad 3-8 (中等)
    │  └─ ⚠️  优先轻量级
    │     - investigate-io-spike-lite.sh
    │     - monitor-connection-pool.sh --with-db-query
    │
    └─ DBLoad > 8 (高负载)
       └─ 🚨 极度谨慎
          1. Performance Insights (零影响 ⭐)
          2. investigate-io-spike-lite.sh
          3. ❌ 避免完整版调查
```

---

## 📋 实战场景

### 场景 1：例行健康检查
```bash
# 每小时运行（零影响）
./scripts/rds/monitor-connection-pool.sh bingo-prd

# 每天运行（选择低峰期，低影响）
./scripts/rds/monitor-connection-pool.sh bingo-prd --with-db-query ...
```

---

### 场景 2：收到 DBLoad 告警（DBLoad = 15）
```bash
# 第一时间（零影响）
# 1. 查看 Performance Insights
# 2. 检查 CloudWatch 告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --alarm-name-prefix 'RDS-bingo-prd-' --state-value ALARM

# 3. 快速监控（零影响）
./scripts/rds/monitor-connection-pool.sh bingo-prd

# 4. 如果需要数据库查询（轻量级，+0.5 DBLoad）
./scripts/rds/investigate-io-spike-lite.sh -h ... -u ... -w ...

# ❌ 不要运行完整版（会加剧负载）
# ./scripts/rds/investigate-io-spike.sh ...
```

---

### 场景 3：事后详细分析（DBLoad = 2）
```bash
# 问题已过去，可以运行完整分析
./scripts/rds/investigate-io-spike.sh -h ... -u ... -w ...

# 查看 Performance Insights 历史数据
# 选择问题时段进行分析
```

---

### 场景 4：配置新的监控
```bash
# 1. 创建 CloudWatch 告警（零影响）
./scripts/cloudwatch/create-rds-alarms.sh bingo-prd

# 2. 验证告警已创建
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --alarm-name-prefix 'RDS-bingo-prd-'

# 3. (可选) 配置 SNS 通知
# 创建 SNS topic 并重新运行脚本
```

---

## ⚠️ 关键提示

### 1. 优先级排序（从高到低）

对数据库影响最小的工具：

1. **Performance Insights** (零影响 ⭐⭐⭐)
2. **CloudWatch 脚本** (零影响)
3. **monitor-connection-pool.sh** 仅 CloudWatch (零影响)
4. **check-connections*.sh** (零影响)
5. **monitor-connection-pool.sh --with-db-query** (+0.3-0.8)
6. **investigate-io-spike-lite.sh** (+0.3-0.5)
7. **investigate-io-spike.sh** (+0.7-1.5)

### 2. 高负载时的黄金法则

```
DBLoad > 8 时：
  ✅ DO: 使用 Performance Insights
  ✅ DO: 使用 CloudWatch 监控脚本
  ⚠️  CAREFUL: 使用轻量级调查脚本
  ❌ DON'T: 使用完整版调查脚本
  ❌ DON'T: 多人同时连接调查
  ❌ DON'T: 直接执行复杂查询
```

### 3. 确认提示总结

| 脚本 | 有确认提示 | 原因 |
|------|----------|------|
| `create-rds-alarms.sh` | ✅ 有 | 避免覆盖现有配置 |
| `delete-rds-alarms.sh` | ✅ 有 | 防止误删除 |
| `investigate-io-spike.sh` | ✅ 有 | 提醒负载影响 |
| `investigate-io-spike-lite.sh` | ❌ 无 | 轻量级，快速执行 |
| `monitor-connection-pool.sh` | ❌ 无 | 影响极小 |

---

## 📚 相关文档

- **RDS_MONITORING_GUIDE.md** - 完整监控配置指南
- **scripts/rds/INVESTIGATION_SAFETY_GUIDE.md** - 调查脚本安全使用详细指南
- **CLAUDE.md** - 项目总体说明

---

**最后更新**: 2025-10-29

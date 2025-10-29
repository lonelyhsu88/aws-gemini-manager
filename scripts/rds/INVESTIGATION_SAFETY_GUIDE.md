# RDS 调查脚本安全使用指南

## ⚠️ 重要：调查脚本也会产生负载

诊断脚本本身也会消耗数据库资源。在数据库已经高负载时，不当使用可能让情况更糟。

---

## 📊 脚本负载对比

| 脚本 | 执行时间 | DBLoad 影响 | I/O 影响 | 适用场景 |
|------|---------|------------|---------|---------|
| **investigate-io-spike-lite.sh** | 0.5-2秒 | +0.3-0.5 | 极低 | 🚨 数据库高负载时 (DBLoad > 8) |
| **investigate-io-spike.sh** | 3-8秒 | +0.7-1.5 | 低 | ✅ 数据库正常或中等负载 (DBLoad < 8) |
| **monitor-connection-pool.sh** | 0.2-1秒 | +0.1-0.3 | 极低 | ✅ 任何时候都可以 |
| **query-active-connections.sh** | 1-3秒 | +0.3-0.8 | 低 | ✅ 正常负载时 |

---

## 🚦 使用决策流程

### 第一步：检查当前 DBLoad

```bash
# 快速查看当前 DBLoad（使用 CloudWatch）
./scripts/rds/monitor-connection-pool.sh bingo-prd
```

### 第二步：根据 DBLoad 选择工具

```
当前 DBLoad 是多少？
│
├─ DBLoad < 3（正常）
│  └─ ✅ 可以使用任何工具
│     - investigate-io-spike.sh (完整分析)
│     - query-active-connections.sh
│     - 或者直接在 Performance Insights 查看
│
├─ DBLoad 3-8（中等）
│  └─ ⚠️  优先使用轻量级工具
│     - monitor-connection-pool.sh
│     - investigate-io-spike-lite.sh
│     - Performance Insights (首选)
│
└─ DBLoad > 8（高负载）
   └─ 🚨 极度谨慎
      1. 首选：Performance Insights (不影响数据库)
      2. 次选：investigate-io-spike-lite.sh
      3. 避免：完整版 investigate-io-spike.sh
      4. 避免：直接连接数据库执行复杂查询
```

---

## 📋 各脚本详细说明

### 1. investigate-io-spike.sh（完整版）

**执行的查询（9 项）**:
1. ✅ pg_extension 检查 (极轻量)
2. ⚠️  pg_stat_statements Top I/O 查询 (中等)
3. ⚠️  pg_stat_statements Top 执行次数 (中等)
4. ⚠️  pg_stat_statements 慢查询 (中等)
5. ⚠️  pg_stat_user_tables 统计 (中等)
6. ⚠️  缺失索引分析 (中等)
7. ⚠️  Vacuum 状态 (中等)
8. 🚨 表大小查询 (pg_total_relation_size) (可能重)
9. 🚨 锁等待 JOIN 查询 (多表 JOIN，可能重)

**预计影响**:
- 执行时间: 3-8 秒
- DBLoad: +0.7-1.5
- CPU: 5-15%
- I/O: 少量读取（主要是系统表）

**使用时机**:
- ✅ 数据库负载正常时（DBLoad < 5）
- ✅ 事后分析（问题已经过去）
- ✅ 需要完整诊断信息时
- ❌ 数据库正在高负载时（DBLoad > 8）
- ❌ 多人同时调查时

**安全措施**:
```bash
# 脚本会在执行前显示警告并要求确认
./investigate-io-spike.sh -h ... -u ... -w ...

# 输出示例：
# ⚠️  负载影响警告
# 此脚本会执行多个诊断查询，预计影响:
#   - 执行时间: 3-8 秒
#   - DBLoad 影响: +0.7-1.5
#   - 占用 1 个数据库连接
#
# 确认继续执行完整分析？(y/N)
```

---

### 2. investigate-io-spike-lite.sh（轻量级）

**执行的查询（5 项）**:
1. ✅ pg_extension 检查 (极轻量)
2. ✅ pg_stat_statements Top 10 I/O (轻量，限制 10 行)
3. ✅ pg_stat_statements Top 10 慢查询 (轻量，限制 10 行)
4. ✅ pg_stat_activity 当前活动 (极轻量)
5. ✅ pg_stat_user_tables Top 5 (轻量，限制 5 行)

**跳过的查询**:
- ❌ 表大小查询（避免大量元数据读取）
- ❌ 锁等待 JOIN（避免复杂 JOIN）
- ❌ 缺失索引详细分析

**预计影响**:
- 执行时间: 0.5-2 秒
- DBLoad: +0.3-0.5
- CPU: 2-5%
- I/O: 极少

**使用时机**:
- ✅ 数据库高负载时（DBLoad > 8）
- ✅ 需要快速诊断时
- ✅ 多人同时调查时
- ✅ 生产环境紧急情况

**使用方法**:
```bash
./investigate-io-spike-lite.sh -h bingo-prd.xxx.rds.amazonaws.com \
    -u readonly_user -w 'password'

# 无需确认，直接执行
```

---

### 3. monitor-connection-pool.sh

**执行的操作**:
- CloudWatch API 调用（不影响数据库）
- 可选：数据库直接查询（如果使用 --with-db-query）

**预计影响**:
- 仅 CloudWatch: 0 DBLoad 影响
- 含数据库查询: +0.1-0.3 DBLoad

**使用时机**:
- ✅ 任何时候都可以安全使用（如果不加 --with-db-query）
- ✅ 实时监控
- ✅ 定期健康检查

**最佳实践**:
```bash
# 高负载时：仅使用 CloudWatch（无数据库影响）
./monitor-connection-pool.sh bingo-prd

# 正常负载时：可以加数据库查询
./monitor-connection-pool.sh bingo-prd --with-db-query ...
```

---

### 4. Performance Insights（推荐）

**优势**:
- ✅ **零影响**：不会增加数据库负载
- ✅ 实时 + 历史数据
- ✅ 等待事件详细分析
- ✅ Top SQL 自动排序
- ✅ 可视化界面

**访问方式**:
```
AWS Console → RDS → bingo-prd → Performance Insights
```

**使用时机**:
- ✅ **首选工具**，任何时候都适用
- ✅ 特别适合高负载时使用
- ✅ 可以精确选择时间范围

**限制**:
- 保留期仅 7 天（免费层）
- 需要提前启用（bingo-prd 已启用 ✅）

---

## 🎯 实战场景决策

### 场景 1：正在发生高负载（DBLoad = 15）

**❌ 不要做**:
```bash
# ❌ 不要运行完整调查脚本
./investigate-io-spike.sh ...

# ❌ 不要直接执行复杂查询
psql ... -c "SELECT * FROM pg_locks JOIN ..."

# ❌ 不要多人同时连接调查
```

**✅ 应该做**:
```bash
# 1. 首先使用 Performance Insights（零影响）
# AWS Console → RDS → Performance Insights

# 2. 快速检查连接池（仅 CloudWatch）
./monitor-connection-pool.sh bingo-prd

# 3. 如果需要数据库查询，使用轻量级版本
./investigate-io-spike-lite.sh -h ... -u ... -w ...

# 4. 查看 CloudWatch 告警
aws --profile gemini-pro_ck cloudwatch describe-alarms \
    --alarm-name-prefix 'RDS-bingo-prd-' --state-value ALARM
```

---

### 场景 2：事后分析（问题已过去，DBLoad = 2）

**✅ 可以做**:
```bash
# 1. 运行完整调查（获取详细信息）
./investigate-io-spike.sh -h ... -u ... -w ...

# 2. 查看 Performance Insights 历史数据
# 选择问题发生的时间段

# 3. 使用详细连接池监控
./monitor-connection-pool.sh bingo-prd --with-db-query ...

# 4. 执行特定的诊断查询
psql ... -c "SELECT * FROM pg_stat_statements WHERE ..."
```

---

### 场景 3：例行健康检查

**✅ 推荐做法**:
```bash
# 每小时：轻量级监控
./monitor-connection-pool.sh bingo-prd

# 每天：完整分析（选择低峰期）
./investigate-io-spike.sh -h ... -u ... -w ... > /logs/daily-analysis.log

# 实时：Performance Insights 快速查看
```

---

## ⚡ 紧急情况处理流程

### 当收到 DBLoad 严重告警时

**第一时间（1 分钟内）**:
1. 打开 Performance Insights（零影响）
2. 查看 Top SQL 和等待事件
3. 运行：`./monitor-connection-pool.sh bingo-prd`（仅 CloudWatch）

**初步判断（5 分钟内）**:
- 如果是 I/O 等待 → 可能是批量操作或慢查询
- 如果是 CPU 等待 → 可能是复杂计算或连接数过多
- 如果是 Lock 等待 → 可能是死锁或长事务

**深入调查（只在 DBLoad < 8 后）**:
```bash
# 等待负载降低后再运行
while true; do
    dbload=$(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
        --namespace AWS/RDS --metric-name DBLoad \
        --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
        --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S)Z \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
        --period 300 --statistics Average \
        --query 'Datapoints[0].Average' --output text)

    echo "当前 DBLoad: $dbload"

    if (( $(echo "$dbload < 8" | bc -l) )); then
        echo "负载已降低，可以执行完整分析"
        ./investigate-io-spike.sh -h ... -u ... -w ...
        break
    fi

    echo "负载仍然过高，等待 1 分钟..."
    sleep 60
done
```

---

## 🔒 权限和安全建议

### 使用只读用户

调查脚本只需要读取权限：

```sql
-- 创建只读用户（仅供参考，请联系 DBA）
CREATE USER readonly_diagnostics WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE postgres TO readonly_diagnostics;
GRANT USAGE ON SCHEMA public TO readonly_diagnostics;
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO readonly_diagnostics;
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO readonly_diagnostics;
GRANT pg_read_all_stats TO readonly_diagnostics;
```

### 连接数管理

避免占用过多连接：

```bash
# ❌ 不好：多个脚本并行
./investigate-io-spike.sh ... &
./query-active-connections.sh ... &
psql -h ... &  # 3 个连接

# ✅ 好：一次一个
./investigate-io-spike.sh ...
# 完成后再运行下一个
```

---

## 📊 监控脚本自身的影响

在运行调查脚本前后对比：

```bash
# 运行前：记录基线
echo "运行前 DBLoad:"
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS --metric-name DBLoad \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
    --start-time $(date -u -v-2M +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 60 --statistics Average --output table

# 运行调查脚本
./investigate-io-spike.sh -h ... -u ... -w ...

# 运行后：查看影响
echo "运行后 DBLoad:"
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS --metric-name DBLoad \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
    --start-time $(date -u -v-2M +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 60 --statistics Average --output table
```

---

## 📚 总结：推荐工作流

### 日常监控
```
Performance Insights (AWS Console)
    ↓ 每天查看
monitor-connection-pool.sh (仅 CloudWatch)
    ↓ 每小时运行
CloudWatch 告警
    ↓ 自动触发
```

### 问题调查
```
1. 收到告警
    ↓
2. Performance Insights (零影响)
    ↓
3. monitor-connection-pool.sh (极低影响)
    ↓
4. DBLoad < 8?
    ├─ Yes → investigate-io-spike.sh (完整分析)
    └─ No  → investigate-io-spike-lite.sh (轻量级)
```

### 事后分析
```
1. 问题已过去，DBLoad 正常
    ↓
2. Performance Insights 查看历史
    ↓
3. investigate-io-spike.sh (完整分析)
    ↓
4. 根据发现优化查询/索引
    ↓
5. 调整告警阈值（如需要）
```

---

## ⚠️ 注意事项总结

1. **优先使用 Performance Insights**
   - 零数据库影响
   - 功能最强大
   - 历史数据保留 7 天

2. **高负载时谨慎**
   - DBLoad > 8 时避免使用完整调查脚本
   - 使用轻量级版本或仅 CloudWatch 监控

3. **避免并发调查**
   - 多人同时连接会叠加影响
   - 协调调查时间

4. **使用只读用户**
   - 降低安全风险
   - 防止误操作

5. **选择合适时机**
   - 完整调查选择低峰期
   - 紧急情况使用轻量级工具

---

**相关文档**:
- [RDS_MONITORING_GUIDE.md](../../RDS_MONITORING_GUIDE.md) - 完整监控配置指南
- [CLAUDE.md](../../CLAUDE.md) - 项目总体说明

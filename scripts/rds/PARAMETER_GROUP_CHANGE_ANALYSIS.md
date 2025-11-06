# RDS 参数组异动分析报告

## 📊 执行摘要

根据 CloudTrail 和 RDS API 的综合分析，以下是参数组异动的完整时间线：

## 🕐 关键时间点

### 1. 参数组创建
- **时间**: 2024-11-13 13:39:19 UTC (2024-11-13 21:39 UTC+8)
- **方式**: CloudFormation Stack `postgresql14-monitoring-params`
- **参数组名称**: `postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2`
- **描述**: PostgreSQL 14 parameter group with monitoring and profiling settings v1.1

### 2. 参数组绑定到实例
- **推测时间**: 2024-11-13 （参数组创建后立即绑定，或稍后手动绑定）
- **绑定方式**: 通过 CloudFormation 或手动 ModifyDBInstance 操作
- **状态**: CloudTrail 无记录（可能超过90天保留期，或通过 CloudFormation 自动绑定）

### 3. bingo-prd-* 实例重启（应用参数）
- **时间**: 2025-11-03 08:08-08:12 UTC+8
- **操作者**: CK
- **重启实例**:
  - `bingo-prd` - 08:08:41 和 08:12:35 (重启两次)
  - `bingo-prd-backstage` - 08:08:48 和 08:12:42 (重启两次)
  - `bingo-prd-loyalty` - 08:09:14 (重启一次)
  - `bingo-prd-replica1` - 08:08:41 和 08:12:35 (重启两次)
  - `bingo-prd-backstage-replica1` - 08:08:48 和 08:12:42 (重启两次)
- **结果**: 所有参数变更生效，状态变为 `in-sync`

## 📝 当前状态 (2025-11-03)

### ✅ 已应用参数（in-sync）
以下实例已在 2025-11-03 重启，参数组变更已生效：

| 实例 | 参数组状态 | 实例状态 | 最后重启 |
|------|-----------|---------|----------|
| bingo-prd | in-sync | available | 2025-11-03 08:12 |
| bingo-prd-backstage | in-sync | available | 2025-11-03 08:12 |
| bingo-prd-backstage-replica1 | in-sync | available | 2025-11-03 08:12 |
| bingo-prd-loyalty | in-sync | available | 2025-11-03 08:09 |
| bingo-prd-replica1 | in-sync | available | 2025-11-03 08:12 |
| bingo-stress | in-sync | starting | - |
| bingo-stress-backstage | in-sync | stopped | - |
| bingo-stress-loyalty | in-sync | stopped | - |
| pgsqlrel-backstage | in-sync | available | - |

### ⚠️ 待重启实例（pending-reboot）
| 实例 | 参数组状态 | 实例状态 | 原因 |
|------|-----------|---------|------|
| pgsqlrel | **pending-reboot** | available | 未重启，参数变更未生效 |

## 🔍 关键发现

### 为什么显示 "In Sync" 和 "pending reboot"？

您提到的状态描述可能有误解：

1. **In-sync** = 参数已应用（已重启过）
2. **Pending-reboot** = 参数未应用（需要重启）

目前的实际状态：
- ✅ 大部分实例（9个）：**in-sync** - 参数已生效
- ⚠️ 只有 `pgsqlrel`：**pending-reboot** - 需要重启

### 为什么 pgsqlrel 显示 pending-reboot？

1. **参数组绑定时间**: 可能在 2024-11-13 或稍后绑定到此参数组
2. **未重启**: 此实例在 2025-11-03 的批量重启中被遗漏
3. **状态保留**: 自绑定参数组后一直未重启，所以保持 pending-reboot 状态

### CloudTrail 分析结果

#### 最近的 ModifyDBInstance 事件
- **pgsqlrel**: 2025-08-06/07 - 仅修改备份窗口（preferredBackupWindow）
- **bingo-prd-***: 2025-08-05/09 - 修改备份保留期、备份窗口等
- **无参数组变更记录**: 最近90天内无 DBParameterGroup 相关修改

#### ModifyDBParameterGroup 事件
- **搜索结果**: 无（最近90天内）
- **推论**: 参数组在创建时就配置好了，或在90天前修改过

## 📊 参数组详细信息

### 参数组配置
- **Family**: postgres14
- **ARN**: `arn:aws:rds:ap-east-1:470013648166:pg:postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2`

### 主要参数（需要重启才能生效）
以下是一些关键的 PostgreSQL 参数（pending-reboot 类型）：

- `max_connections` = LEAST({DBInstanceClassMemory/9531392},5000)
- `shared_buffers` = {DBInstanceClassMemory*1024/32768}
- `effective_cache_size` = {DBInstanceClassMemory/16384}
- `max_worker_processes` = GREATEST(${DBInstanceVCPU*2},8)
- `max_parallel_workers` = GREATEST(${DBInstanceVCPU/2},8)
- `autovacuum_max_workers` = GREATEST({DBInstanceClassMemory/64371566592},3)
- `huge_pages` = on
- `jit` = 0 (关闭 JIT 编译)
- 监控相关参数：log_checkpoints, compute_query_id 等

## 💡 建议行动

### 1. 对 pgsqlrel 实例
如果需要应用参数组变更：

```bash
# 重启 pgsqlrel 实例
aws --profile gemini-pro_ck rds reboot-db-instance \
    --db-instance-identifier pgsqlrel

# 验证状态变更
aws --profile gemini-pro_ck rds describe-db-instances \
    --db-instance-identifier pgsqlrel \
    --query 'DBInstances[0].DBParameterGroups[0].ParameterApplyStatus'
```

### 2. 验证参数是否需要应用
```bash
# 检查待应用的参数变更
aws --profile gemini-pro_ck rds describe-db-parameters \
    --db-parameter-group-name postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2 \
    --query 'Parameters[?ApplyMethod==`pending-reboot`]' \
    --output table
```

### 3. 维护窗口建议
- **建议时间**: 业务低峰期
- **预计停机**: 5-10 分钟
- **影响**: pgsqlrel 实例短暂不可用

## 📈 时间线总结

```
2024-11-13 21:39     参数组通过 CloudFormation 创建
        ↓
2024-11-13 ~ ?      参数组绑定到所有 RDS 实例
        ↓            (具体时间未知，CloudTrail 无记录)
        ↓
2025-11-03 08:08    开始批量重启 bingo-prd-* 实例
        ↓
2025-11-03 08:12    bingo-prd-* 重启完成，参数生效
        ↓
        ❌           pgsqlrel 未重启（遗漏）
        ↓
2025-11-03 现在     pgsqlrel 仍为 pending-reboot 状态
```

## 🔧 技术细节

### CloudFormation Stack
- **Stack Name**: postgresql14-monitoring-params
- **Status**: CREATE_COMPLETE
- **Created**: 2024-11-13T13:39:19.359000+00:00
- **Updated**: null (从未更新)

### 事件来源
1. **CloudFormation Events**: Stack 创建和资源创建
2. **CloudTrail Events**: RDS 实例的修改和重启操作
3. **RDS API**: 当前实例和参数组状态

---

**报告生成时间**: 2025-11-03
**分析工具**: AWS CLI + CloudTrail + RDS API
**AWS Profile**: gemini-pro_ck

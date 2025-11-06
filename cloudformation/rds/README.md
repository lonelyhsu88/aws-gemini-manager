# RDS CloudFormation Templates

## 📋 概述

此目录包含用于管理 AWS RDS 资源的 CloudFormation 模板。

## 📁 模板文件

### postgresql14-monitoring-params.yaml

**用途**: PostgreSQL 14 数据库参数组，启用详细的监控和性能分析功能

**Stack 信息**:
- **Stack Name**: `postgresql14-monitoring-params`
- **Region**: ap-east-1 (香港)
- **Created**: 2024-11-13 21:39 (UTC+8)
- **Status**: CREATE_COMPLETE

**生成的资源**:
- Parameter Group: `postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2`

**使用此参数组的 RDS 实例**:
- bingo-prd
- bingo-prd-backstage
- bingo-prd-backstage-replica1
- bingo-prd-loyalty
- bingo-prd-replica1
- bingo-stress
- bingo-stress-backstage
- bingo-stress-loyalty
- pgsqlrel
- pgsqlrel-backstage

## 🚀 部署指南

### 1. 部署新的 Stack

```bash
aws --profile gemini-pro_ck cloudformation create-stack \
    --stack-name postgresql14-monitoring-params \
    --template-body file://cloudformation/rds/postgresql14-monitoring-params.yaml \
    --region ap-east-1
```

### 2. 更新现有 Stack

```bash
aws --profile gemini-pro_ck cloudformation update-stack \
    --stack-name postgresql14-monitoring-params \
    --template-body file://cloudformation/rds/postgresql14-monitoring-params.yaml \
    --region ap-east-1
```

### 3. 查看 Stack 状态

```bash
aws --profile gemini-pro_ck cloudformation describe-stacks \
    --stack-name postgresql14-monitoring-params \
    --region ap-east-1
```

### 4. 删除 Stack（谨慎操作）

```bash
# ⚠️ 警告：删除 stack 会删除参数组
# 如果有 RDS 实例正在使用此参数组，删除会失败
aws --profile gemini-pro_ck cloudformation delete-stack \
    --stack-name postgresql14-monitoring-params \
    --region ap-east-1
```

## 📊 参数组配置详解

### 查询日志
- `log_statement: 'all'` - 记录所有 SQL 语句
- `log_min_duration_statement: '1000'` - 记录执行超过 1 秒的查询

### 性能统计
- `track_activities: '1'` - 追踪当前执行的命令
- `track_counts: '1'` - 收集行级统计信息
- `track_io_timing: '1'` - 启用 I/O 时间统计
- `track_functions: 'all'` - 追踪函数执行统计

### pg_stat_statements
- `shared_preload_libraries: 'pg_stat_statements'` - 加载查询统计扩展
- `pg_stat_statements.track: 'all'` - 追踪所有语句（包括嵌套）
- `pg_stat_statements.max: '10000'` - 最多追踪 10,000 条语句

### 连接和锁监控
- `log_connections: '1'` - 记录连接
- `log_disconnections: '1'` - 记录断开连接
- `log_lock_waits: '1'` - 记录锁等待

### Autovacuum
- `autovacuum: '1'` - 启用自动清理
- `log_autovacuum_min_duration: '250'` - 记录超过 250ms 的 autovacuum 操作

## ⚠️ 重要注意事项

### 修改参数组后需要重启

许多参数（如 `shared_preload_libraries`）需要**重启 RDS 实例**才能生效。

修改后的实例状态会显示 `pending-reboot`，需要执行：

```bash
aws --profile gemini-pro_ck rds reboot-db-instance \
    --db-instance-identifier <实例名称>
```

### 性能影响

启用详细日志可能会影响性能：
- `log_statement: 'all'` 会记录每条 SQL，可能产生大量日志
- 建议生产环境使用 `log_statement: 'mod'` 或 `'ddl'`
- 根据实际需求调整 `log_min_duration_statement` 的值

### 成本考虑

- CloudWatch Logs 存储会产生费用
- pg_stat_statements 会占用共享内存
- 详细日志会增加存储成本

## 🔧 修改建议

### 降低日志级别（生产环境）

```yaml
log_statement: 'mod'  # 只记录数据修改语句
log_min_duration_statement: '5000'  # 只记录超过 5 秒的查询
```

### 增加统计容量

```yaml
pg_stat_statements.max: '20000'  # 追踪更多查询
```

### 调整 Autovacuum 日志

```yaml
log_autovacuum_min_duration: '1000'  # 只记录超过 1 秒的 autovacuum
```

## 📝 版本历史

- **v1.1** (2024-03-21): 当前版本，包含完整的监控和性能分析配置
- **Created** (2024-11-13): Stack 首次部署

## 🔗 相关资源

- AWS RDS 参数组文档: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithParamGroups.html
- PostgreSQL 参数文档: https://www.postgresql.org/docs/14/runtime-config.html
- pg_stat_statements 文档: https://www.postgresql.org/docs/14/pgstatstatements.html

## 📞 联系信息

如需修改参数组配置，请：
1. 编辑本地模板文件
2. 使用 `update-stack` 命令更新 CloudFormation stack
3. 重启相关 RDS 实例以应用更改

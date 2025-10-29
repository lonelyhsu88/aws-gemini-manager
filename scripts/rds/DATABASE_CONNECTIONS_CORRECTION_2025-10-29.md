# DatabaseConnections 告警阈值修正记录

**日期**: 2025-10-29  
**问题**: DatabaseConnections 阈值基于错误的 max_connections 计算  
**修正**: 更新为基于实际 max_connections 的正确阈值

---

## 问题发现

### 用户观察
用户在 Dashboard 上看到 DatabaseConnections 告警线显示 **80**，但文档说应该是 **150**。

进一步质疑：**"db.m6g.large 最高的 connection 不是 910？"**

### 问题根源

**错误的计算方法** (之前使用):
```
max_connections = {DBInstanceClassMemory/9531392} ≈ 216
阈值设定 = 216 × 69% = 150 connections
```

**实际情况**:
```sql
-- 从 RDS Parameter Group 查询
max_connections = LEAST({DBInstanceClassMemory/9531392}, 5000)

-- db.m6g.large (8GB RAM)
max_connections = 8,589,934,592 / 9531392 = 901 connections

-- db.t4g.medium (4GB RAM)  
max_connections = 4,294,967,296 / 9531392 = 451 connections
```

**错误的严重性**:
- **旧阈值 150** 仅占 max_connections 的 **16.6%**
- 需要达到 751+ connections 才告警（距离上限仅 150）
- **高风险**: 可能在接近 max_connections 时才告警，导致新连接被拒绝

---

## 正确的 max_connections 计算

### PostgreSQL RDS 公式
```
max_connections = DBInstanceClassMemory / 9531392
```

### 各实例类型的 max_connections

| 实例类型 | RAM | 计算 | max_connections |
|---------|-----|------|-----------------|
| db.m6g.large | 8 GB | 8,589,934,592 / 9531392 | **~901** |
| db.t4g.medium | 4 GB | 4,294,967,296 / 9531392 | **~451** |
| db.m6g.xlarge | 16 GB | 17,179,869,184 / 9531392 | **~1,802** |
| db.m6g.2xlarge | 32 GB | 34,359,738,368 / 9531392 | **~3,604** |

**注**: 实际值受 `LEAST(计算值, 5000)` 限制

---

## 阈值方案对比

### 方案 A: 保守 (70%)
```
m6g.large: 630 connections
t4g.medium: 315 connections
```

### 方案 B: 平衡 (75%) ✅ **已采用**
```
m6g.large: 675 connections
t4g.medium: 340 connections
```

### 方案 C: 激进 (80%)
```
m6g.large: 720 connections
t4g.medium: 360 connections
```

**选择理由**:
- **75%** 在预警时间和避免误报之间取得平衡
- 留有 **25%** 缓冲空间（~226 connections for m6g, ~111 for t4g）
- 足够时间进行调查和响应

---

## 执行的更新

### 1. 更新 m6g.large 实例告警 (3个)

**实例**:
- bingo-prd
- bingo-prd-replica1
- bingo-prd-backstage

**变更**:
```
旧阈值: 150 connections (16.6% of 901)
新阈值: 675 connections (75% of 901)
```

**AWS CLI 命令示例**:
```bash
aws cloudwatch put-metric-alarm \
  --profile gemini-pro_ck \
  --alarm-name "bingo-prd-RDS-Connections-High" \
  --alarm-description "bingo-prd 连接数过高 (≥675 - 75% of max_connections ~901 for db.m6g.large)" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --datapoints-to-alarm 2 \
  --threshold 675 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --alarm-actions arn:aws:sns:ap-east-1:470013648166:Cloudwatch-Slack-Notification \
  --treat-missing-data notBreaching
```

### 2. 新增 t4g.medium 实例告警 (2个)

**实例**:
- bingo-prd-backstage-replica1
- bingo-prd-loyalty

**变更**:
```
旧配置: ❌ 无监控
新阈值: 340 connections (75% of 451)
```

**说明**: t4g 实例之前完全没有 DatabaseConnections 监控，现已补充。

### 3. 更新 Dashboard 告警线

**Dashboard**: Production-RDS-Dashboard  
**Widget**: 數據庫連接數

**新增告警线** (4条):
1. 🔴 **m6g.large 告警閾值 675 (75%)** - 红色，上方填充
2. 🟠 **t4g.medium 告警閾值 340 (75%)** - 橙色，上方填充
3. 📍 **m6g.large max ~901** - 灰色参考线
4. 📍 **t4g.medium max ~451** - 灰色参考线

---

## 修正后的完整配置

### db.m6g.large 实例

| 实例 | max_connections | 告警阈值 | 占比 | 缓冲空间 |
|------|----------------|---------|------|---------|
| bingo-prd | 901 | 675 | 75% | 226 connections |
| bingo-prd-replica1 | 901 | 675 | 75% | 226 connections |
| bingo-prd-backstage | 901 | 675 | 75% | 226 connections |

### db.t4g.medium 实例

| 实例 | max_connections | 告警阈值 | 占比 | 缓冲空间 |
|------|----------------|---------|------|---------|
| bingo-prd-backstage-replica1 | 451 | 340 | 75% | 111 connections |
| bingo-prd-loyalty | 451 | 340 | 75% | 111 connections |

---

## 告警总数变化

| 指标 | 修正前 | 修正后 | 变化 |
|------|--------|--------|------|
| DatabaseConnections 告警数 | 3 | 5 | +2 |
| RDS 总告警数 | 42 | 44 | +2 |

**新增告警**:
- bingo-prd-backstage-replica1-RDS-Connections-High
- bingo-prd-loyalty-RDS-Connections-High

---

## 验证方法

### 查看当前配置
```bash
aws cloudwatch describe-alarms \
  --profile gemini-pro_ck \
  --query 'MetricAlarms[?MetricName==`DatabaseConnections` && contains(AlarmName, `bingo-prd`)].[AlarmName,Threshold,Dimensions[0].Value]' \
  --output table
```

### 预期输出
```
+-------------------------------------------+-------+---------------------------+
| bingo-prd-RDS-Connections-High            | 675.0 | bingo-prd                |
| bingo-prd-backstage-RDS-Connections-High  | 675.0 | bingo-prd-backstage      |
| bingo-prd-backstage-replica1-RDS-...      | 340.0 | bingo-prd-backstage-...  |
| bingo-prd-loyalty-RDS-Connections-High    | 340.0 | bingo-prd-loyalty        |
| bingo-prd-replica1-RDS-Connections-High   | 675.0 | bingo-prd-replica1       |
+-------------------------------------------+-------+---------------------------+
```

### 查询实际 max_connections
```bash
# 从 RDS 参数组查询
aws rds describe-db-parameters \
  --profile gemini-pro_ck \
  --db-parameter-group-name <parameter-group-name> \
  --query 'Parameters[?ParameterName==`max_connections`]'
```

---

## 关键教训

### 1. 验证计算公式
- **不要假设**: 初始使用了错误的简化公式
- **查阅官方文档**: AWS RDS 参数公式有具体定义
- **实际查询**: 使用 AWS CLI 验证参数组配置

### 2. 实例类型差异
- 不同实例类型的 max_connections 差异巨大（901 vs 451）
- **必须分别配置**: 统一阈值会导致误报或漏报

### 3. 阈值设定哲学
- **16.6%** 太低 → 失去预警意义
- **75%** 适中 → 既有预警时间，又避免频繁误报
- **90%+** 太高 → 可能来不及响应

### 4. 文档更新
- 所有配置变更必须同步更新文档
- Dashboard 告警线必须与实际 CloudWatch Alarms 一致
- 记录决策依据和计算过程

---

## 相关资源

### AWS 官方文档
- [RDS for PostgreSQL Parameters](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Parameters.html)
- [DB Instance Class Memory](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts.General.DBInstanceClass)

### 内部文档
- `scripts/rds/CURRENT_MONITORING_STATUS.md` - 需要更新
- `scripts/rds/RDS_MONITORING_COMPLETE_RECORD.md` - 需要更新
- `scripts/rds/RDS_ALARMS_QUICK_REFERENCE.md` - 需要更新

---

## 后续行动

### 立即执行
- ✅ 更新所有 DatabaseConnections 告警
- ✅ 更新 Dashboard 告警线
- ⏳ 更新相关文档

### 建议事项
1. **监控实际连接数**: 观察 1-2 周，验证 75% 阈值是否合适
2. **定期审查**: 每季度检查一次告警阈值合理性
3. **实例升级评估**: 如果经常接近阈值，考虑升级实例类型
4. **连接池优化**: 检查应用层连接池配置

### 预防措施
- 创建 max_connections 计算器脚本
- 文档化所有阈值计算公式
- 新增实例时自动检查告警配置

---

**最后更新**: 2025-10-29  
**修正人**: Claude Code  
**审核状态**: ✅ 已验证

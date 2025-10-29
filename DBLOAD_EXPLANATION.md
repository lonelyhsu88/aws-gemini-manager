# DBLoad 指标详解

## 🎯 什么是 DBLoad？

**DBLoad** = **Database Load**（数据库负载）

这是 AWS RDS Performance Insights 的核心指标，表示**数据库中平均活动会话数**（Average Active Sessions, AAS）。

简单来说：**有多少个查询正在同时执行或等待执行**

---

## 📊 DBLoad 的含义

### 基本概念

```
DBLoad = 在数据库中活动的会话（sessions）数量

活动会话包括：
  - 正在执行的查询（Running）
  - 正在等待资源的查询（Waiting）
    ├─ 等待 CPU
    ├─ 等待 I/O
    ├─ 等待锁（Lock）
    └─ 等待网络
```

### 举例说明

```
DBLoad = 2
  → 平均有 2 个查询正在活动中
  → 如果实例有 2 个 vCPUs，负载正常

DBLoad = 5
  → 平均有 5 个查询正在活动中
  → 如果实例有 2 个 vCPUs，有 3 个查询在排队等待
  → ⚠️ 开始出现性能瓶颈

DBLoad = 10
  → 平均有 10 个查询正在活动中
  → 如果实例有 2 个 vCPUs，有 8 个查询在排队
  → 🚨 严重过载，响应时间会明显变慢
```

---

## 🖥️ DBLoad 与 vCPU 的关系

### 黄金法则

```
理想状态：DBLoad ≤ vCPU 数量
  → 所有活动会话都能立即获得 CPU 资源
  → 无需等待排队

可接受：DBLoad ≤ vCPU × 1.5
  → 有少量排队，但还能应付
  → 需要关注

警告：DBLoad > vCPU × 2
  → 大量查询排队等待
  → 性能明显下降
  → 需要立即处理

严重：DBLoad > vCPU × 5
  → 严重过载
  → 响应时间极慢
  → 可能导致超时或服务不可用
```

### bingo-prd 实例详情

```
实例类型: db.m6g.large
vCPUs: 2

告警配置：
  Warning:  DBLoad > 3 (1.5x vCPUs) → ⚠️ 需要关注
  Critical: DBLoad > 4 (2x vCPUs)   → 🚨 需要立即处理

实际案例（2025-10-29 21:18-21:38）：
  DBLoad 峰值: 26
  状态: 严重过载（13x vCPUs）
  原因: I/O 密集型操作导致大量查询排队
```

---

## 🔍 DBLoad 的组成

DBLoad 可以分解为不同的等待类型：

### 1. DBLoadCPU
```
含义: 正在使用 CPU 的会话数
例子: DBLoadCPU = 1.5
  → 平均有 1.5 个查询正在执行计算
  → 这是"真正在工作"的部分
```

### 2. DBLoadNonCPU
```
含义: 正在等待资源的会话数
包括:
  - I/O 等待（磁盘读写）
  - Lock 等待（锁竞争）
  - Network 等待（网络传输）

例子: DBLoadNonCPU = 23
  → 平均有 23 个查询在等待 I/O、锁或其他资源
  → 这些查询被"阻塞"了
```

### 实际案例分析

**2025-10-29 21:18-21:38 的事件**:

```
DBLoad 峰值: 26
├─ DBLoadCPU: 0.5-0.75 (平均)
│  └─ 仅有少量 CPU 计算
│
└─ DBLoadNonCPU: 24 (峰值)
   └─ 大部分查询在等待 I/O

结论: 这不是 CPU 瓶颈，而是 I/O 瓶颈
原因: ReadIOPS 飙升至 2950（是正常的 5 倍）
```

---

## 📈 如何解读 DBLoad

### 场景 1：CPU 密集型

```
DBLoad = 10
DBLoadCPU = 9
DBLoadNonCPU = 1

分析:
  → 大部分负载来自 CPU 计算
  → 可能是：复杂查询、聚合运算、JOIN 操作
  → 解决: 优化查询、增加 CPU（升级实例）
```

### 场景 2：I/O 密集型

```
DBLoad = 10
DBLoadCPU = 1
DBLoadNonCPU = 9

分析:
  → 大部分负载来自 I/O 等待
  → 可能是：大量读写、缺失索引、全表扫描
  → 解决: 添加索引、优化查询、增加 IOPS
```

### 场景 3：锁竞争

```
DBLoad = 10
DBLoadCPU = 1
DBLoadNonCPU = 9
Wait Events: Lock (80%)

分析:
  → 大量查询在等待锁释放
  → 可能是：长事务、死锁、高并发写入
  → 解决: 优化事务、减少锁持有时间
```

---

## ⚠️ 告警阈值设置

### RDS-bingo-prd-HighDBLoad-Warning

```
阈值: DBLoad > 3
含义: 数据库负载超过 1.5 倍 vCPU 容量
触发条件: 持续 5 分钟超过阈值

为什么是 3？
  - bingo-prd 有 2 个 vCPUs
  - 3 = 1.5 × 2 vCPUs
  - 这是"可接受但需要关注"的水平

应该做什么？
  1. 查看 Performance Insights
  2. 识别是 CPU、I/O 还是 Lock 等待
  3. 检查是否有异常查询
  4. 如果是临时性的，继续观察
  5. 如果持续发生，需要优化
```

### RDS-bingo-prd-HighDBLoad-Critical

```
阈值: DBLoad > 4
含义: 数据库负载超过 2 倍 vCPU 容量
触发条件: 持续 3 分钟超过阈值

为什么是 4？
  - bingo-prd 有 2 个 vCPUs
  - 4 = 2 × 2 vCPUs
  - 这是"需要立即处理"的水平

应该做什么？
  1. 立即查看 Performance Insights
  2. 运行 investigate-io-spike-lite.sh
  3. 识别并终止异常查询（如果需要）
  4. 通知相关团队
  5. 考虑临时扩容
```

---

## 🛠️ 如何查看 DBLoad

### 方法 1：Performance Insights（推荐）

```
AWS Console → RDS → bingo-prd → Performance Insights

可以看到：
  - DBLoad 实时图表
  - DBLoadCPU vs DBLoadNonCPU 分布
  - Top SQL 查询
  - 等待事件类型
```

### 方法 2：CloudWatch

```bash
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DBLoad \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --start-time 2025-10-29T13:00:00Z \
  --end-time 2025-10-29T14:00:00Z \
  --period 60 \
  --statistics Average Maximum
```

### 方法 3：监控脚本

```bash
./scripts/rds/monitor-connection-pool.sh bingo-prd
```

输出包含：
```
⚡ 性能指标 (最近 5 分钟)
--------------------------------
CPU 使用率: 45.2%
数据库负载: 2.85 (峰值: 19.0, vCPUs: 2)  ⚠️
读取 IOPS: 1250 IOPS
写入 IOPS: 890 IOPS
```

---

## 🎯 实战案例：2025-10-29 21:18-21:38

### 事件回顾

```
时间: 2025-10-29 21:18-21:38 (CST)
实例: bingo-prd (db.m6g.large, 2 vCPUs)
```

### 指标分析

| 时间 | DBLoad | DBLoadCPU | DBLoadNonCPU | CPU% | ReadIOPS |
|------|--------|-----------|--------------|------|----------|
| 21:18 | 5 | 1 | 4 | 32% | 2950 ⚠️⚠️⚠️ |
| 21:19 | 21 | 5 | 18 | 42% | 1237 |
| 21:21 | 24 | 9 | 24 | 44% | 745 |
| 21:29 | 26 | 6 | 23 | 44% | 505 |
| 21:35 | 24 | 11 | 22 | 43% | 477 |

### 分析结论

```
问题本质: I/O 密集型负载，不是 CPU 瓶颈

证据：
  1. DBLoadNonCPU 占 92% (24/26)
  2. ReadIOPS 飙升至 2950（是正常的 5 倍）
  3. CPU 使用率只有 32-53%（不算高）

根本原因:
  - 21:18 突然大量读取操作
  - 可能是批量查询、数据导出或定时任务
  - 导致大量查询等待 I/O 完成
  - 查询排队累积，DBLoad 飙升

如果当时 DBLoad 告警触发：
  ✅ 告警是正确的（DBLoad 26 >> 阈值 3）
  ✅ 需要立即调查（严重超载）
  ✅ 应该使用轻量级脚本（避免增加负载）
```

---

## 💡 优化建议

### 短期措施

1. **识别问题查询**
   ```bash
   ./scripts/rds/investigate-io-spike-lite.sh -h ... -u ... -w ...
   ```

2. **查看 Performance Insights**
   - 找出 Top SQL
   - 分析等待事件类型

3. **优化或终止异常查询**
   ```sql
   -- 查看当前活动查询
   SELECT pid, query_start, state, query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY query_start;

   -- 必要时终止（谨慎！）
   SELECT pg_terminate_backend(pid);
   ```

### 长期措施

1. **升级实例规格** ⭐ 最有效
   ```
   当前: db.m6g.large (2 vCPUs)
   建议: db.m6g.xlarge (4 vCPUs) 或更大

   原因: DBLoad 峰值 26 远超 2 vCPUs 的容量
   ```

2. **优化查询和索引**
   - 添加缺失的索引
   - 优化慢查询
   - 减少全表扫描

3. **实施读写分离**
   - 创建只读副本
   - 将报表查询移至副本

4. **调整批量操作**
   - 分批执行
   - 移到低峰期
   - 减小单次数据量

---

## 📚 相关概念

### DBLoad vs CPU Utilization

```
DBLoad:
  - 衡量数据库"繁忙程度"
  - 包括 CPU + I/O + 锁等待
  - 更全面的负载指标

CPU Utilization:
  - 仅衡量 CPU 使用率
  - 不包括 I/O 等待
  - 可能"误导"（I/O 高时 CPU 可能不高）

例子:
  DBLoad = 26, CPU = 45%
  → CPU 不高，但数据库严重过载
  → 原因: 大量查询在等待 I/O
```

### DBLoad vs DatabaseConnections

```
DatabaseConnections:
  - 连接总数（包括 idle）
  - 例: 150 个连接

DBLoad:
  - 活动会话数（正在工作的）
  - 例: 26 个活动会话

关系:
  150 个连接中，可能只有 26 个在活动
  其他 124 个处于 idle 状态
```

---

## 🔗 快速链接

- **查看实时 DBLoad**: AWS Console → RDS → Performance Insights
- **查看历史数据**: CloudWatch → Metrics → RDS → DBLoad
- **快速监控**: `./scripts/rds/monitor-connection-pool.sh bingo-prd`
- **详细调查**: `./scripts/rds/investigate-io-spike-lite.sh`

---

## ❓ 常见问题

### Q1: DBLoad 多少算正常？
**A**:
- 理想: ≤ vCPU 数量（bingo-prd: ≤ 2）
- 可接受: ≤ 1.5x vCPUs（bingo-prd: ≤ 3）
- 需要关注: > 2x vCPUs（bingo-prd: > 4）
- 严重: > 5x vCPUs（bingo-prd: > 10）

### Q2: DBLoad 高但 CPU 不高，正常吗？
**A**: 正常！这说明瓶颈不在 CPU，而在 I/O、锁或其他资源。查看 DBLoadNonCPU 和等待事件来确定具体原因。

### Q3: 如何快速降低 DBLoad？
**A**:
1. 终止异常的长时间查询
2. 优化或推迟批量操作
3. 临时限制连接数
4. 如果是突发流量，考虑临时拒绝部分请求

### Q4: 升级实例能解决 DBLoad 高的问题吗？
**A**: 看情况
- 如果是 CPU 瓶颈（DBLoadCPU 高）→ ✅ 升级有效
- 如果是 I/O 瓶颈（DBLoadNonCPU 高）→ ⚠️ 升级有帮助，但优化查询更重要
- 如果是锁竞争 → ❌ 升级无效，需要优化应用逻辑

### Q5: DBLoad 告警频繁触发怎么办？
**A**:
1. 先确认是否真的有性能问题（用户有无抱怨？）
2. 如果是正常业务增长 → 升级实例或优化
3. 如果是特定时段（如批量任务）→ 调整告警时间窗口或调整任务时间
4. 如果是误报 → 适当提高阈值

---

**最后更新**: 2025-10-29

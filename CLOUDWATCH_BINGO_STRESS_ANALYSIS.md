# CloudWatch Metrics Analysis: bingo-stress-* Instances

**Analysis Date:** 2025-10-29
**AWS Profile:** gemini-pro_ck
**Region:** ap-east-1

---

## Executive Summary

**Finding:** The CloudWatch metrics with prefix "bingo-stress-*" are primarily from **deleted/terminated RDS instances** used for stress testing and Blue/Green deployments. These metrics are **safe to ignore** and will automatically expire.

### Key Statistics
- **Total instances with metrics:** 17
- **Currently active instances:** 4
- **Deleted/terminated instances:** 13
- **Metrics still receiving data:** 6 (4 active + 2 recently deleted)
- **Stale/inactive metrics:** 11 (no data in 7+ days)

### Recommendation
✅ **These metrics can be safely ignored.** No action is required as CloudWatch will automatically expire them after 15 months of inactivity.

---

## Detailed Analysis

### 1. All Metrics Found (17 instances)

The following RDS instances have metrics in CloudWatch:

| Instance Identifier | Status | Last Metric Update | Purpose |
|---------------------|--------|-------------------|---------|
| `bingo-stress` | 🟢 **ACTIVE** | 2025-10-29 (today) | Production DB |
| `bingo-stress-backstage` | 🟢 **ACTIVE** | 2025-10-29 (today) | Production Backstage DB |
| `bingo-stress-loyalty` | 🟢 **ACTIVE** | 2025-10-29 (today) | Production Loyalty DB |
| `bingo-stress-loyalty-green-otcz8q` | 🟢 **ACTIVE** | 2025-10-29 (today) | Blue/Green deployment (active) |
| `bingo-stress-backstage-green-hazoel` | ⚠️ **RECENTLY DELETED** | 2025-10-26 (3 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-backstage-replica1-...` | ⚠️ **RECENTLY DELETED** | 2025-10-22 (7 days ago) | Replica (terminated) |
| `bingo-stress-green-ppbtff` | ❌ **DELETED** | 2025-10-20 (9 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-old1` | ❌ **DELETED** | 2025-10-20 (9 days ago) | Old instance (terminated) |
| `bingo-stress-replica` | ❌ **DELETED** | 2025-10-20 (9 days ago) | Replica (terminated) |
| `bingo-stress-replica-green-uub79w` | ❌ **DELETED** | 2025-10-20 (9 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-replica-old1` | ❌ **DELETED** | 2025-10-20 (9 days ago) | Old replica (terminated) |
| `bingo-stress-loyalty-green-6qdgg0` | ❌ **DELETED** | 2025-10-21 (8 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-loyalty-green-8qwxma` | ❌ **DELETED** | 2025-10-21 (8 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-loyalty-green-rvkzjw` | ❌ **DELETED** | 2025-10-21 (8 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-loyalty-green-zsqd3q` | ❌ **DELETED** | 2025-10-21 (8 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-loyalty-green-dxpd6q` | ❌ **DELETED** | 2025-10-19 (10 days ago) | Blue/Green deployment (terminated) |
| `bingo-stress-loyalty-old1` | ❌ **DELETED** | 2025-10-19 (10 days ago) | Old instance (terminated) |

---

### 2. Namespace Analysis

**All metrics belong to:** `AWS/RDS` namespace

**Common metrics found:**
- DatabaseConnections
- CPUUtilization
- FreeableMemory
- FreeStorageSpace
- ReadIOPS / WriteIOPS
- ReadLatency / WriteLatency
- NetworkReceiveThroughput / NetworkTransmitThroughput
- ReplicationSlotDiskUsage
- ReplicaLag
- TransactionLogsDiskUsage
- CheckpointLag
- CPUCreditUsage / CPUCreditBalance
- EBSIOBalance% / EBSByteBalance%
- And many other standard RDS PostgreSQL metrics

---

### 3. Currently Active RDS Instances

Only **4 instances** are currently active in the ap-east-1 region:

1. **bingo-stress**
   - Class: `db.t4g.medium`
   - Status: `available`
   - Created: 2025-10-20
   - Storage: 2750 GB (gp3)
   - Tags: Production=Bingo, Env=Prd

2. **bingo-stress-backstage**
   - Class: `db.t4g.medium`
   - Status: `available`
   - Created: 2025-10-23
   - Storage: 5024 GB (gp3)
   - Tags: Production=Bingo, Env=Prd

3. **bingo-stress-loyalty**
   - Class: `db.t4g.medium`
   - Status: `available`
   - Created: 2025-10-20
   - Storage: 200 GB (gp3)
   - Tags: Production=Bingo, Env=Stress

4. **bingo-stress-loyalty-green-otcz8q**
   - Class: `db.t4g.medium`
   - Status: `available` (Read Replica)
   - Created: 2025-10-29 (today)
   - Storage: 200 GB (gp3)
   - Source: bingo-stress-loyalty
   - Tags: Production=Bingo, Env=Stress, aws:rds:BlueGreenDeploymentId=bgd-6l53k95glg1ilocw

---

### 4. Source of Metrics

**Primary Source: Blue/Green Deployments**

Analysis shows that most deleted instances were part of AWS RDS Blue/Green deployments:
- Instances with `-green-` suffix followed by random string (e.g., `green-ppbtff`, `green-hazoel`)
- Instances with `-old1` suffix (previous versions)
- Temporary replicas created during deployment

**Evidence:**
- Tag `aws:rds:BlueGreenDeploymentId` found on `bingo-stress-loyalty-green-otcz8q`
- Naming pattern matches AWS Blue/Green deployment conventions
- Short-lived instances (1-2 days of metrics only)

**Secondary Source: Stress Testing**
- The naming convention "bingo-stress" suggests these are stress testing environments
- Tags confirm: `Env=Stress` on some instances

---

### 5. Associated Alarms

**Finding:** ✅ **ZERO alarms found** for any bingo-stress instances

```bash
# Verified with:
aws cloudwatch describe-alarms --profile gemini-pro_ck --region ap-east-1 \
  | jq '.MetricAlarms[] | select(.Dimensions[]?.Value | contains("bingo-stress"))'
# Result: No alarms
```

---

### 6. Metric Activity Status

**Active (receiving data):**
- 4 currently existing instances are actively sending metrics
- 2 recently deleted instances still have metrics from 3-7 days ago

**Stale (no new data in 7+ days):**
- 11 instances have no metrics for 7+ days
- All stale instances have been deleted from RDS
- Last updates range from October 19-21, 2025

---

## Can These Metrics Be Deleted?

### Short Answer: They will auto-expire, no action needed

### Long Answer:

**CloudWatch Behavior:**
- CloudWatch metrics **cannot be manually deleted**
- Metrics automatically expire after **15 months** with no new data
- Once the RDS instance is deleted, no new metrics are published

**Timeline for Automatic Expiration:**
| Instance Group | Last Metric | Will Expire By |
|----------------|-------------|----------------|
| Deleted on Oct 19-21 | 2025-10-19 to 2025-10-21 | 2027-01-19 to 2027-01-21 |
| Recently deleted (Oct 22-26) | 2025-10-22 to 2025-10-26 | 2027-01-22 to 2027-01-26 |

**What You Can Do:**
1. ✅ **Ignore them** - Recommended approach
2. ✅ **Document them** - This report serves that purpose
3. ❌ **Delete them manually** - Not possible via AWS API

**What Happens Next:**
- No new data will be written (instances are deleted)
- Metrics will remain visible in CloudWatch console for 15 months
- After 15 months, they automatically expire and disappear
- No cost impact (CloudWatch charges per metric/API call, not storage)

---

## Cost Impact

**Current Status:** ✅ **No ongoing costs**

- CloudWatch metrics are free for the first 10 custom metrics
- AWS/RDS metrics are **standard AWS metrics** (not custom)
- Costs only apply when:
  - Querying metrics via API (GetMetricStatistics)
  - Using CloudWatch Insights or advanced features
  - Creating dashboards with these metrics

**Since these instances are deleted:**
- No new metrics are being published (no write costs)
- Metrics sitting idle in CloudWatch have no storage cost
- Only querying them (like this analysis) has minimal cost

---

## Recommendations

### Immediate Actions
✅ **No action required** - These metrics are safe to ignore

### Best Practices for Future

1. **Blue/Green Deployment Cleanup:**
   - AWS automatically removes Blue/Green deployment instances after switchover
   - Metrics will auto-expire in 15 months
   - Consider documenting deployment IDs if needed for audit

2. **Stress Test Cleanup:**
   - Ensure stress test instances are terminated after testing
   - Use tags to identify temporary instances (already done with `Env=Stress`)
   - Consider using resource lifecycle policies

3. **Monitoring:**
   - Focus on the 4 active instances for alerts and dashboards
   - Ignore metrics from deleted instances in console views

4. **Documentation:**
   - This analysis serves as documentation
   - Archive this report for future reference if similar metrics appear

---

## Commands for Future Reference

### List all bingo-stress metrics
```bash
aws cloudwatch list-metrics --profile gemini-pro_ck --region ap-east-1 \
  --output json | jq '.Metrics[] | select(.Dimensions[]?.Value | contains("bingo-stress"))'
```

### Check active RDS instances
```bash
aws rds describe-db-instances --profile gemini-pro_ck --region ap-east-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `bingo-stress`)]'
```

### Check for alarms
```bash
aws cloudwatch describe-alarms --profile gemini-pro_ck --region ap-east-1 \
  | jq '.MetricAlarms[] | select(.Dimensions[]?.Value | contains("bingo-stress"))'
```

### Check metric activity
```bash
python3 check_metrics_activity.py
```

---

## Conclusion

The CloudWatch metrics with prefix "bingo-stress-*" are:

1. ✅ **Safe to ignore** - No action required
2. 🗑️ **Mostly from deleted instances** - 13 out of 17 instances terminated
3. 📅 **Will auto-expire** - In 15 months from last datapoint
4. 💰 **No ongoing cost** - No new metrics being written
5. ⚠️ **No alarms configured** - Won't trigger false alerts
6. 🔄 **From Blue/Green deployments** - Standard AWS RDS operational pattern

**Final Recommendation:** Document this analysis and ignore these metrics. They will automatically clean up over time.

---

## Files Created

This analysis generated the following files:

1. `/Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/check_metrics_activity.py`
   - Python script to check metric activity
   - Can be rerun in the future to verify cleanup

2. `/Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/CLOUDWATCH_BINGO_STRESS_ANALYSIS.md`
   - This comprehensive analysis document
   - Reference for future investigations

---

**Analysis completed:** 2025-10-29
**Next review recommended:** 2026-02-01 (verify stale metrics are aging out)

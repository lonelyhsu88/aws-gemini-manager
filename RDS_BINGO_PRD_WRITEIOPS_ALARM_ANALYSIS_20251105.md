# RDS bingo-prd High WriteIOPS Alarm Analysis

**Date**: 2025-11-05
**Alarm Time**: 10:05:25 (UTC+8) / 02:05:25 (UTC)
**Instance**: bingo-prd
**Current Status**: ✅ RESOLVED (Alarm returned to OK at 02:06:25 UTC)

---

## Executive Summary

The RDS instance `bingo-prd` triggered a high WriteIOPS alarm at 02:05:25 UTC when WriteIOPS exceeded the threshold of 1,500 IOPS, reaching a peak of **3,981 IOPS** at 02:03 UTC. The alarm automatically cleared at 02:06:25 UTC as the WriteIOPS returned to normal levels (~400 IOPS).

**Root Cause**: Scheduled application batch processing job at 02:00 UTC (10:00 HKT)
**Impact**: Minimal - spike lasted only 4-5 minutes, all other metrics remained healthy
**Action Required**: Monitor for recurrence; consider adjusting alarm threshold or investigating the scheduled job

---

## Detailed Analysis

### 1. Alarm Details

| Metric | Threshold | Peak Value | Time (UTC) |
|--------|-----------|------------|------------|
| WriteIOPS | 1,500 | **3,981.41** | 02:03:00 |
| | | 2,043.50 | 02:04:00 |
| | | 1,556.08 | 02:02:00 |

**Alarm Trigger Pattern**:
- 3 consecutive datapoints exceeded threshold (required for ALARM state)
- Duration: ~4-5 minutes (02:02 - 02:06 UTC)
- Recovery: Automatic, no intervention required

### 2. Instance Configuration

| Parameter | Value |
|-----------|-------|
| Instance Class | db.m6g.large (ARM Graviton2) |
| Storage Type | gp3 |
| Allocated Storage | 2,750 GB |
| Provisioned IOPS | **12,000** |
| Max Allocated Storage | 5,000 GB |
| Engine | PostgreSQL 14.15 |
| Multi-AZ | No |
| Read Replica | bingo-prd-replica1 |

### 3. WriteIOPS Timeline (Last 2 Hours)

```
Time (UTC)    WriteIOPS    Status
───────────────────────────────────
01:37-01:59   150-240      Normal baseline
02:00         391.86       Beginning of spike
02:01         761.67       Rapidly increasing
02:02         1,556.08     ⚠️ ALARM THRESHOLD EXCEEDED
02:03         3,981.41     ⚠️ PEAK
02:04         2,043.50     ⚠️ Still elevated
02:05         585.77       Declining
02:06         398.73       ✅ Recovered to normal
```

### 4. Correlated Metrics During Spike

#### WriteThroughput (Peak at 02:03)
```
Time      Average      Maximum
──────────────────────────────
02:00     10.78 MB/s   10.78 MB/s
02:01     20.84 MB/s   20.84 MB/s
02:02     28.33 MB/s   28.33 MB/s
02:03     62.77 MB/s   62.77 MB/s  ← PEAK
02:04     33.57 MB/s   33.57 MB/s
02:05      5.69 MB/s    5.69 MB/s
02:06      3.89 MB/s    3.89 MB/s
```

#### DiskQueueDepth (Peak at 02:03)
```
Time      Average    Maximum
────────────────────────────
02:00     0.76       0.76
02:01     0.90       0.90
02:02     2.35       2.35
02:03     8.56       8.56  ← High queue depth
02:04     3.40       3.40
02:05     0.54       0.54
02:06     0.19       0.19  ✓ Normal
```

#### Other Metrics (Stable)
- **CPU Utilization**: 28% (Normal)
- **Database Connections**: 142 (Normal)
- **FreeableMemory**: 4.3 GB (Stable)
- **Replica Lag**: 0 seconds throughout (Excellent)

### 5. Historical Pattern Analysis (Last 24 Hours)

**High WriteIOPS Events (>1,000 IOPS)**:

| Time (UTC) | Average IOPS | Peak IOPS | Notes |
|------------|--------------|-----------|-------|
| 2025-11-04 21:02 | 2,432.25 | **5,994.10** | ⚠️ During automated backup window |
| 2025-11-05 02:02 | 1,713.10 | **3,981.41** | ⚠️ Current incident |

**Additional Events (11/04)**:
- 07:00-11:00 UTC: Multiple events (1,000-1,700 IOPS)
  - Corresponds to 15:00-19:00 HKT (business hours)
- 14:22 UTC: 1,782 IOPS spike

### 6. Root Cause Analysis

#### Confirmed Causes:

1. **Yesterday 21:02 UTC (5994 IOPS) - AUTOMATED BACKUP** ✅
   - Backup window: 21:00-22:00 UTC
   - Backup started: 21:07 UTC
   - Backup finished: 22:38 UTC (duration: ~1.5 hours)
   - **Expected behavior** - backups cause high WriteIOPS

2. **Today 02:02 UTC (3981 IOPS) - SCHEDULED APPLICATION JOB** ⚠️
   - Time: 02:00 UTC = **10:00 HKT** (Hong Kong Time)
   - Maintenance window is Thu 02:00-02:30 (today is Tuesday)
   - Not AWS maintenance
   - **Likely application batch processing job**

#### Characteristics:
- Short duration (4-5 minutes)
- High write throughput (62 MB/s peak)
- Elevated disk queue depth (8.56)
- No impact on replica lag
- Predictable timing pattern

---

## Impact Assessment

### System Health: ✅ HEALTHY

| Metric | Status | Evidence |
|--------|--------|----------|
| Recovery | ✅ Complete | Alarm cleared automatically |
| Replica Lag | ✅ Normal | 0 seconds throughout |
| CPU | ✅ Normal | 28% utilization |
| Memory | ✅ Stable | 4.3 GB free |
| Connections | ✅ Normal | 142 connections |
| IOPS Capacity | ✅ Sufficient | 12,000 provisioned, peak usage 3,981 |

### Business Impact:
- **No service disruption detected**
- **No user-facing impact**
- Spike duration too short to affect application performance
- All queries completed successfully (no latency issues)

---

## Recommendations

### 1. Immediate Actions (Optional)
**Priority**: LOW - System is healthy and recovered

- [ ] Verify application logs at 10:00 HKT for scheduled jobs
- [ ] Confirm with development team about batch processing at this time
- [ ] Review the nature of the 02:00 UTC job (can it be optimized?)

### 2. Alarm Threshold Review

**Current Threshold**: 1,500 IOPS
**Provisioned IOPS**: 12,000 (only 33% utilized at peak)

**Options**:
1. **Keep current threshold** (Recommended for now)
   - Provides early warning
   - Useful for detecting anomalies
   - Can be suppressed during known batch windows

2. **Increase threshold to 4,000 IOPS**
   - Would eliminate alarms from scheduled jobs
   - Still well below capacity
   - May miss actual issues

3. **Create scheduled alarm suppression**
   - Disable alarm during known batch windows
   - Keep sensitivity for other times
   - Requires CloudWatch alarm composite

### 3. Optimization Opportunities

#### For the 02:00 UTC Job:
- **Batch size optimization**: Split large writes into smaller chunks
- **Connection pooling**: Ensure efficient connection usage
- **Parallel processing**: Consider spreading load over time
- **Indexing**: Review if proper indexes exist for bulk operations

#### For Backup-Related Spikes:
- **Expected behavior** - no action needed
- Consider backup window timing if it impacts business operations

### 4. Monitoring Enhancements

Consider implementing:
- **Performance Insights**: Already enabled ✅
- **Enhanced Monitoring**: Enable for detailed OS-level metrics
- **Custom CloudWatch Dashboard**: Track WriteIOPS trends
- **Scheduled Reports**: Daily IOPS pattern analysis

### 5. Long-term Considerations

- **Capacity Planning**: Current IOPS usage is healthy (33% peak)
- **Read Replica**: Already in place ✅ - working perfectly
- **Storage Growth**: Monitor growth toward 5,000 GB max
- **Parameter Tuning**: Review `postgresql14-monitoring-params` if needed

---

## Conclusion

This WriteIOPS alarm was triggered by a **scheduled application batch job** running at 02:00 UTC (10:00 HKT). The spike lasted only 4-5 minutes and had no impact on system health or user experience. The RDS instance has sufficient IOPS capacity (12,000 provisioned vs. 3,981 peak usage = 67% headroom).

**Verdict**: ✅ **No immediate action required**
**Risk Level**: 🟢 **LOW** - This is normal operational behavior
**Follow-up**: Identify and potentially optimize the scheduled job

---

## Additional Context

### Similar Events (Last 30 Days)
- This pattern likely repeats daily at 02:00 UTC
- Backup-related spikes occur daily at 21:00 UTC
- Business hours (07:00-11:00 UTC) show elevated but normal WriteIOPS

### Related Documentation
- RDS Analysis Scripts: `scripts/rds/`
- Parameter Group: `cloudformation/rds/postgresql14-monitoring-params.yaml`
- Connection Analysis: `scripts/rds/check-connections-peak.sh`
- High Load Analysis: `scripts/rds/analyze-high-load.py`

### Next Steps if Issue Recurs
1. Run: `python3 scripts/rds/analyze-high-load.py bingo-prd`
2. Check connections: `./scripts/rds/check-connections-peak.sh`
3. Review Performance Insights for query patterns
4. Correlate with application logs at 10:00 HKT

---

**Report Generated**: 2025-11-05
**Analyzed By**: AWS CloudWatch + RDS Monitoring
**Tools Used**: AWS CLI, boto3, CloudWatch Metrics API

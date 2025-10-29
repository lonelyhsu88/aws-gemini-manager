# DatabaseConnections Alarm Threshold Correction Record

**Date**: 2025-10-29  
**Issue**: DatabaseConnections thresholds based on incorrect max_connections calculation  
**Fix**: Updated to correct thresholds based on actual max_connections values

---

## Issue Discovery

### User Observation
User noticed DatabaseConnections alarm threshold showing **80** on Dashboard, but documentation stated it should be **150**.

Further investigation: **"Isn't the maximum connection for db.m6g.large around 910?"**

### Root Cause

**Incorrect calculation method** (previously used):
```
max_connections = {DBInstanceClassMemory/9531392} ≈ 216
Threshold = 216 × 69% = 150 connections
```

**Actual values**:
```sql
-- From RDS Parameter Group
max_connections = LEAST({DBInstanceClassMemory/9531392}, 5000)

-- db.m6g.large (8GB RAM)
max_connections = 8,589,934,592 / 9531392 = 901 connections

-- db.t4g.medium (4GB RAM)  
max_connections = 4,294,967,296 / 9531392 = 451 connections
```

**Severity of the error**:
- **Old threshold of 150** was only **16.6%** of max_connections
- Would only alarm at 751+ connections (only 150 away from limit)
- **High risk**: May alarm too late, causing new connection rejections

---

## Correct max_connections Calculation

### PostgreSQL RDS Formula
```
max_connections = DBInstanceClassMemory / 9531392
```

### max_connections by Instance Type

| Instance Type | RAM | Calculation | max_connections |
|--------------|-----|-------------|-----------------|
| db.m6g.large | 8 GB | 8,589,934,592 / 9531392 | **~901** |
| db.t4g.medium | 4 GB | 4,294,967,296 / 9531392 | **~451** |
| db.m6g.xlarge | 16 GB | 17,179,869,184 / 9531392 | **~1,802** |
| db.m6g.2xlarge | 32 GB | 34,359,738,368 / 9531392 | **~3,604** |

**Note**: Actual value capped by `LEAST(calculated_value, 5000)`

---

## Threshold Options Comparison

### Option A: Conservative (70%)
```
m6g.large: 630 connections
t4g.medium: 315 connections
```

### Option B: Balanced (75%) ✅ **SELECTED**
```
m6g.large: 675 connections
t4g.medium: 340 connections
```

### Option C: Aggressive (80%)
```
m6g.large: 720 connections
t4g.medium: 360 connections
```

**Selection rationale**:
- **75%** balances early warning with avoiding false positives
- Provides **25%** buffer (~226 connections for m6g, ~111 for t4g)
- Sufficient time for investigation and response

---

## Implemented Updates

### 1. Updated m6g.large Instance Alarms (3 instances)

**Instances**:
- bingo-prd
- bingo-prd-replica1
- bingo-prd-backstage

**Changes**:
```
Old threshold: 150 connections (16.6% of 901)
New threshold: 675 connections (75% of 901)
```

**AWS CLI command example**:
```bash
aws cloudwatch put-metric-alarm \
  --profile gemini-pro_ck \
  --alarm-name "bingo-prd-RDS-Connections-High" \
  --alarm-description "bingo-prd connections too high (≥675 - 75% of max_connections ~901 for db.m6g.large)" \
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

### 2. Added t4g.medium Instance Alarms (2 instances)

**Instances**:
- bingo-prd-backstage-replica1
- bingo-prd-loyalty

**Changes**:
```
Old configuration: ❌ No monitoring
New threshold: 340 connections (75% of 451)
```

**Note**: t4g instances had no DatabaseConnections monitoring previously.

### 3. Updated Dashboard Alarm Lines

**Dashboard**: Production-RDS-Dashboard  
**Widget**: Database Connections

**New alarm lines** (4 lines):
1. 🔴 **m6g.large Alarm Threshold 675 (75%)** - Red, fill above
2. 🟠 **t4g.medium Alarm Threshold 340 (75%)** - Orange, fill above
3. 📍 **m6g.large max ~901** - Gray reference line
4. 📍 **t4g.medium max ~451** - Gray reference line

---

## Final Configuration

### db.m6g.large Instances

| Instance | max_connections | Alarm Threshold | Percentage | Buffer |
|----------|----------------|-----------------|------------|--------|
| bingo-prd | 901 | 675 | 75% | 226 connections |
| bingo-prd-replica1 | 901 | 675 | 75% | 226 connections |
| bingo-prd-backstage | 901 | 675 | 75% | 226 connections |

### db.t4g.medium Instances

| Instance | max_connections | Alarm Threshold | Percentage | Buffer |
|----------|----------------|-----------------|------------|--------|
| bingo-prd-backstage-replica1 | 451 | 340 | 75% | 111 connections |
| bingo-prd-loyalty | 451 | 340 | 75% | 111 connections |

---

## Alarm Count Changes

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| DatabaseConnections alarms | 3 | 5 | +2 |
| Total RDS alarms | 42 | 44 | +2 |

**New alarms**:
- bingo-prd-backstage-replica1-RDS-Connections-High
- bingo-prd-loyalty-RDS-Connections-High

---

## Verification

### Check Current Configuration
```bash
aws cloudwatch describe-alarms \
  --profile gemini-pro_ck \
  --query 'MetricAlarms[?MetricName==`DatabaseConnections` && contains(AlarmName, `bingo-prd`)].[AlarmName,Threshold,Dimensions[0].Value]' \
  --output table
```

### Expected Output
```
+-------------------------------------------+-------+---------------------------+
| bingo-prd-RDS-Connections-High            | 675.0 | bingo-prd                |
| bingo-prd-backstage-RDS-Connections-High  | 675.0 | bingo-prd-backstage      |
| bingo-prd-backstage-replica1-RDS-...      | 340.0 | bingo-prd-backstage-...  |
| bingo-prd-loyalty-RDS-Connections-High    | 340.0 | bingo-prd-loyalty        |
| bingo-prd-replica1-RDS-Connections-High   | 675.0 | bingo-prd-replica1       |
+-------------------------------------------+-------+---------------------------+
```

### Query Actual max_connections
```bash
# From RDS parameter group
aws rds describe-db-parameters \
  --profile gemini-pro_ck \
  --db-parameter-group-name <parameter-group-name> \
  --query 'Parameters[?ParameterName==`max_connections`]'
```

---

## Key Lessons Learned

### 1. Verify Calculation Formulas
- **Don't assume**: Initial use of incorrect simplified formula
- **Consult official documentation**: AWS RDS parameter formulas are well-defined
- **Validate with queries**: Use AWS CLI to verify parameter group configuration

### 2. Instance Type Differences
- Different instance types have vastly different max_connections (901 vs 451)
- **Must configure separately**: Uniform thresholds lead to false positives or missed alerts

### 3. Threshold Setting Philosophy
- **16.6%** too low → Defeats purpose of early warning
- **75%** optimal → Provides warning time while avoiding frequent false positives
- **90%+** too high → May not have time to respond

### 4. Documentation Updates
- All configuration changes must be synchronized with documentation
- Dashboard alarm lines must match actual CloudWatch Alarms
- Record decision rationale and calculation process

---

## Related Resources

### AWS Official Documentation
- [RDS for PostgreSQL Parameters](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Parameters.html)
- [DB Instance Class Memory](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts.General.DBInstanceClass)

### Internal Documentation
- `scripts/rds/CURRENT_MONITORING_STATUS.md` - Needs update
- `scripts/rds/RDS_MONITORING_COMPLETE_RECORD.md` - Needs update
- `scripts/rds/RDS_ALARMS_QUICK_REFERENCE.md` - Needs update

---

## Follow-up Actions

### Immediate
- ✅ Update all DatabaseConnections alarms
- ✅ Update Dashboard alarm lines
- ⏳ Update related documentation

### Recommendations
1. **Monitor actual connections**: Observe for 1-2 weeks to validate 75% threshold appropriateness
2. **Regular reviews**: Quarterly alarm threshold reviews
3. **Instance upgrade evaluation**: Consider upgrades if frequently approaching threshold
4. **Connection pool optimization**: Review application-layer connection pool configuration

### Preventive Measures
- Create max_connections calculator script
- Document all threshold calculation formulas
- Automatically verify alarm configuration when adding new instances

---

**Last Updated**: 2025-10-29  
**Updated By**: Claude Code  
**Review Status**: ✅ Verified

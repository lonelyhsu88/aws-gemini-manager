# CloudWatch Metrics Cleanup Commands Reference

**Date:** 2025-10-29
**Analysis:** See `CLOUDWATCH_BINGO_STRESS_ANALYSIS.md` for full details

---

## Important Notes

⚠️ **CloudWatch metrics CANNOT be manually deleted via AWS API or Console.**

CloudWatch automatically expires metrics that haven't received new data after **15 months**.

---

## What CAN Be Done

### 1. Verify Metrics Are No Longer Active

```bash
# Quick check - run this script
./scripts/cloudwatch/list-bingo-stress-metrics.sh

# Detailed analysis
python3 check_metrics_activity.py
```

### 2. Stop Sources from Sending Metrics

The RDS instances that were sending these metrics have already been **deleted/terminated**, so no new data is being sent.

**Verification:**
```bash
# List all RDS instances with "bingo-stress" prefix
aws rds describe-db-instances --profile gemini-pro_ck --region ap-east-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `bingo-stress`)].DBInstanceIdentifier'

# Expected result: Only 4 active instances
# - bingo-stress
# - bingo-stress-backstage
# - bingo-stress-loyalty
# - bingo-stress-loyalty-green-otcz8q
```

### 3. Delete CloudWatch Alarms (if any exist)

**Status:** ✅ No alarms found for bingo-stress instances

If alarms existed, they could be deleted with:
```bash
# List alarms for bingo-stress instances
aws cloudwatch describe-alarms --profile gemini-pro_ck --region ap-east-1 \
  --output json | \
  jq -r '.MetricAlarms[] | select(.Dimensions[]?.Value | contains("bingo-stress")) | .AlarmName'

# Delete an alarm (if needed)
aws cloudwatch delete-alarms --profile gemini-pro_ck --region ap-east-1 \
  --alarm-names "alarm-name-here"
```

### 4. Remove from Dashboards (if applicable)

If these metrics were added to any CloudWatch dashboards:

```bash
# List all dashboards
aws cloudwatch list-dashboards --profile gemini-pro_ck --region ap-east-1

# Get dashboard content
aws cloudwatch get-dashboard --profile gemini-pro_ck --region ap-east-1 \
  --dashboard-name "YourDashboardName"

# Update dashboard (remove widgets with bingo-stress metrics)
aws cloudwatch put-dashboard --profile gemini-pro_ck --region ap-east-1 \
  --dashboard-name "YourDashboardName" \
  --dashboard-body file://updated-dashboard.json
```

### 5. Filter Metrics in Console

When viewing CloudWatch in the AWS Console, you can filter OUT the stale metrics:

**Console Filters:**
- Go to CloudWatch → Metrics → All metrics
- In the search box, use filters like:
  - `NOT bingo-stress-old1`
  - `NOT bingo-stress-green-*` (to exclude Blue/Green instances)
  - Search only for active instances: `bingo-stress` OR `bingo-stress-backstage` OR `bingo-stress-loyalty`

---

## Deleted Instances (Metrics Will Auto-Expire)

These instances were **deleted** and their metrics will expire automatically:

### Deleted on October 19-21, 2025 (Expires: January 2027)
- `bingo-stress-loyalty-green-dxpd6q`
- `bingo-stress-loyalty-old1`
- `bingo-stress-green-ppbtff`
- `bingo-stress-old1`
- `bingo-stress-replica`
- `bingo-stress-replica-green-uub79w`
- `bingo-stress-replica-old1`
- `bingo-stress-loyalty-green-6qdgg0`
- `bingo-stress-loyalty-green-8qwxma`
- `bingo-stress-loyalty-green-rvkzjw`
- `bingo-stress-loyalty-green-zsqd3q`

### Deleted on October 22-26, 2025 (Expires: January 2027)
- `bingo-stress-backstage-replica1-bingo-stress-backstage-replica` (Oct 22)
- `bingo-stress-backstage-green-hazoel` (Oct 26)

---

## Active Instances (Keep Metrics)

These instances are **currently active** and should continue sending metrics:

1. `bingo-stress` - Production database
2. `bingo-stress-backstage` - Production backstage database
3. `bingo-stress-loyalty` - Loyalty database
4. `bingo-stress-loyalty-green-otcz8q` - Blue/Green deployment (active)

**Do NOT attempt to delete metrics for these instances.**

---

## Verification Commands

### Check Metric Age
```bash
# Check when metrics were last updated (Python)
python3 check_metrics_activity.py
```

### Count Total Metrics
```bash
# Count all metrics for a specific instance
INSTANCE_NAME="bingo-stress-old1"
aws cloudwatch list-metrics --profile gemini-pro_ck --region ap-east-1 \
  --output json | \
  jq "[.Metrics[] | select(.Dimensions[]?.Value == \"$INSTANCE_NAME\")] | length"
```

### Check for Data in Time Range
```bash
# Check if any data exists in the last 30 days
INSTANCE_NAME="bingo-stress-old1"
python3 << EOF
import boto3
from datetime import datetime, timedelta

session = boto3.Session(profile_name='gemini-pro_ck', region_name='ap-east-1')
cloudwatch = session.client('cloudwatch')

end_time = datetime.utcnow()
start_time = end_time - timedelta(days=30)

response = cloudwatch.get_metric_statistics(
    Namespace='AWS/RDS',
    MetricName='DatabaseConnections',
    Dimensions=[{'Name': 'DBInstanceIdentifier', 'Value': '$INSTANCE_NAME'}],
    StartTime=start_time,
    EndTime=end_time,
    Period=86400,
    Statistics=['Average']
)

print(f"Datapoints in last 30 days: {len(response['Datapoints'])}")
if response['Datapoints']:
    latest = max(response['Datapoints'], key=lambda x: x['Timestamp'])
    print(f"Last datapoint: {latest['Timestamp']}")
else:
    print("No data in last 30 days - metrics will expire soon")
EOF
```

---

## What AWS Does Automatically

1. **Metric Retention:**
   - Metrics are retained for **15 months** from last datapoint
   - After 15 months, metrics automatically expire and disappear

2. **No Storage Costs:**
   - CloudWatch doesn't charge for storing idle metrics
   - Costs only apply for:
     - Publishing new metrics (already stopped - instances deleted)
     - API calls to retrieve metrics (minimal cost)
     - Advanced features (dashboards, insights, alarms)

3. **Gradual Cleanup:**
   - As time passes, the "stale" metrics will automatically age out
   - By **February 2027**, all deleted instance metrics will be gone

---

## Recommended Actions

### Immediate (Do Now)
✅ **None required** - Metrics are not causing any issues

### Short-term (Next 1-3 months)
- Monitor that deleted instances don't reappear
- Verify no unexpected costs from CloudWatch
- Update dashboards if needed to exclude old metrics

### Long-term (Next review: February 2027)
- Verify all stale metrics have expired (15 months after deletion)
- Run cleanup verification:
  ```bash
  ./scripts/cloudwatch/list-bingo-stress-metrics.sh
  ```

---

## If You Really Want to "Clean Up"

While you can't delete the metrics, you CAN:

### Option 1: Document and Ignore
✅ **RECOMMENDED** - This is what we did with `CLOUDWATCH_BINGO_STRESS_ANALYSIS.md`

### Option 2: Filter in Queries
Use metric math and filters to exclude old instances:

```python
# Example: Query only active instances
import boto3

session = boto3.Session(profile_name='gemini-pro_ck', region_name='ap-east-1')
cloudwatch = session.client('cloudwatch')

# List only active instances
active_instances = [
    'bingo-stress',
    'bingo-stress-backstage',
    'bingo-stress-loyalty',
    'bingo-stress-loyalty-green-otcz8q'
]

# Query metrics only for active instances
for instance in active_instances:
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBInstanceIdentifier', 'Value': instance}],
        StartTime=datetime.utcnow() - timedelta(days=1),
        EndTime=datetime.utcnow(),
        Period=3600,
        Statistics=['Average']
    )
    print(f"{instance}: {len(response['Datapoints'])} datapoints")
```

### Option 3: Create Saved Views in Console
In CloudWatch Console, create "favorite" metric views that only include active instances.

---

## Cost Analysis

**Current Monthly Cost Impact:** $0.00

- No new metrics being published (instances deleted)
- Existing metrics stored for free
- No alarms configured (would be $0.10/alarm/month)
- API calls for this analysis: < $0.01

**Why No Cleanup Needed:**
- Zero ongoing costs
- Metrics will auto-expire
- No operational impact
- No risk of false alarms

---

## Related Documentation

- **Full Analysis:** `CLOUDWATCH_BINGO_STRESS_ANALYSIS.md`
- **Quick Check:** `./scripts/cloudwatch/list-bingo-stress-metrics.sh`
- **Detailed Script:** `check_metrics_activity.py`

---

## AWS Documentation References

- [CloudWatch Metrics Retention](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html#metrics-retention)
- [RDS Metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html)

---

**Last Updated:** 2025-10-29
**Next Review:** 2026-02-01 (verify aging metrics)

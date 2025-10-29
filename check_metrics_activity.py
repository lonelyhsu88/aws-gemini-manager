#!/usr/bin/env python3
"""
Check CloudWatch metric activity for bingo-stress instances
"""

import boto3
from datetime import datetime, timedelta
import json

# Initialize boto3 client with profile
session = boto3.Session(profile_name='gemini-pro_ck', region_name='ap-east-1')
cloudwatch = session.client('cloudwatch')

# All bingo-stress instances found in metrics
all_instances = [
    "bingo-stress",
    "bingo-stress-backstage",
    "bingo-stress-backstage-green-hazoel",
    "bingo-stress-backstage-replica1-bingo-stress-backstage-replica",
    "bingo-stress-green-ppbtff",
    "bingo-stress-loyalty",
    "bingo-stress-loyalty-green-6qdgg0",
    "bingo-stress-loyalty-green-8qwxma",
    "bingo-stress-loyalty-green-dxpd6q",
    "bingo-stress-loyalty-green-otcz8q",
    "bingo-stress-loyalty-green-rvkzjw",
    "bingo-stress-loyalty-green-zsqd3q",
    "bingo-stress-loyalty-old1",
    "bingo-stress-old1",
    "bingo-stress-replica",
    "bingo-stress-replica-green-uub79w",
    "bingo-stress-replica-old1"
]

# Currently active instances
active_instances = [
    "bingo-stress",
    "bingo-stress-backstage",
    "bingo-stress-loyalty",
    "bingo-stress-loyalty-green-otcz8q"
]

# Calculate time range (30 days back)
end_time = datetime.utcnow()
start_time = end_time - timedelta(days=30)

print("Checking metric activity for bingo-stress instances...")
print("=" * 80)
print(f"\nTime range: {start_time.isoformat()} to {end_time.isoformat()}\n")

results = {
    'active': [],
    'stale': []
}

for instance in all_instances:
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseConnections',
            Dimensions=[
                {
                    'Name': 'DBInstanceIdentifier',
                    'Value': instance
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=86400,  # 1 day
            Statistics=['Average']
        )

        datapoints = response.get('Datapoints', [])
        is_active = instance in active_instances

        if datapoints:
            # Sort by timestamp and get the last one
            sorted_points = sorted(datapoints, key=lambda x: x['Timestamp'])
            last_timestamp = sorted_points[-1]['Timestamp']
            days_ago = (end_time - last_timestamp.replace(tzinfo=None)).days

            status = {
                'instance': instance,
                'exists': is_active,
                'last_metric': last_timestamp.isoformat(),
                'days_ago': days_ago,
                'datapoint_count': len(datapoints)
            }

            if days_ago <= 7:
                results['active'].append(status)
            else:
                results['stale'].append(status)
        else:
            results['stale'].append({
                'instance': instance,
                'exists': is_active,
                'last_metric': 'No data in last 30 days',
                'days_ago': '>30',
                'datapoint_count': 0
            })

    except Exception as e:
        print(f"Error checking {instance}: {e}")

print("\n✅ ACTIVE METRICS (data within last 7 days):")
print("-" * 80)
for item in results['active']:
    exists_marker = "🟢 EXISTS" if item['exists'] else "❌ DELETED"
    print(f"{exists_marker} {item['instance']}")
    print(f"   Last metric: {item['last_metric']} ({item['days_ago']} days ago)")
    print(f"   Datapoints in 30d: {item['datapoint_count']}")
    print()

print("\n⚠️  STALE METRICS (no data in last 7+ days):")
print("-" * 80)
for item in results['stale']:
    exists_marker = "🟢 EXISTS" if item['exists'] else "❌ DELETED"
    print(f"{exists_marker} {item['instance']}")
    print(f"   Last metric: {item['last_metric']}")
    if item['datapoint_count'] > 0:
        print(f"   Datapoints in 30d: {item['datapoint_count']}")
    print()

print("\n📊 SUMMARY:")
print("-" * 80)
print(f"Total instances with metrics: {len(all_instances)}")
print(f"Currently active instances: {len(active_instances)}")
print(f"Deleted/terminated instances: {len(all_instances) - len(active_instances)}")
print(f"Metrics still receiving data: {len(results['active'])}")
print(f"Stale/inactive metrics: {len(results['stale'])}")

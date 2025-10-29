#!/usr/bin/env python3
"""
Analyze RDS Write IOPS and Throughput metrics to determine alarm thresholds
"""

import boto3
from datetime import datetime, timedelta
import statistics

# Initialize boto3 session with profile
session = boto3.Session(profile_name='gemini-pro_ck')
cloudwatch = session.client('cloudwatch', region_name='ap-east-1')
rds = session.client('rds', region_name='ap-east-1')

# Production instances to monitor
INSTANCES = [
    'bingo-prd',
    'bingo-prd-replica1',
    'bingo-prd-backstage',
    'bingo-prd-backstage-replica1',
    'bingo-prd-loyalty'
]

def get_metric_statistics(instance_id, metric_name, days=7):
    """Get CloudWatch metric statistics for specified days"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=days)

    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName=metric_name,
        Dimensions=[
            {
                'Name': 'DBInstanceIdentifier',
                'Value': instance_id
            }
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=600,  # 10 minutes (to stay within 1440 datapoint limit for 7 days)
        Statistics=['Average', 'Maximum']
    )

    return response['Datapoints']

def analyze_instance(instance_id):
    """Analyze WriteIOPS and WriteThroughput for an instance"""
    print(f"\n{'='*80}")
    print(f"分析實例: {instance_id}")
    print(f"{'='*80}")

    # Get instance details
    try:
        instance = rds.describe_db_instances(DBInstanceIdentifier=instance_id)
        db_instance = instance['DBInstances'][0]
        instance_class = db_instance['DBInstanceClass']
        storage_type = db_instance.get('StorageType', 'N/A')
        iops = db_instance.get('Iops', 'N/A')
        storage = db_instance['AllocatedStorage']

        print(f"實例類型: {instance_class}")
        print(f"儲存類型: {storage_type}")
        print(f"儲存容量: {storage} GB")
        if iops != 'N/A':
            print(f"預配置 IOPS: {iops}")
        print()
    except Exception as e:
        print(f"無法獲取實例詳情: {e}")
        instance_class = 'Unknown'

    # Analyze WriteIOPS
    print("📊 WriteIOPS 分析 (最近 7 天)")
    print("-" * 80)

    write_iops_data = get_metric_statistics(instance_id, 'WriteIOPS', days=7)

    if write_iops_data:
        avg_values = [dp['Average'] for dp in write_iops_data]
        max_values = [dp['Maximum'] for dp in write_iops_data]

        avg_mean = statistics.mean(avg_values)
        avg_median = statistics.median(avg_values)
        max_peak = max(max_values)
        max_mean = statistics.mean(max_values)

        print(f"平均 IOPS: {avg_mean:.2f}")
        print(f"中位數 IOPS: {avg_median:.2f}")
        print(f"峰值 IOPS: {max_peak:.2f}")
        print(f"最大值平均: {max_mean:.2f}")
        print(f"數據點數: {len(write_iops_data)}")

        # Suggest threshold (150% of average maximum)
        suggested_threshold = max_mean * 1.5
        print(f"\n建議閾值: {suggested_threshold:.0f} IOPS (平均峰值的 150%)")
    else:
        print("❌ 無數據")
        suggested_threshold = None

    print()

    # Analyze WriteThroughput
    print("📊 WriteThroughput 分析 (最近 7 天)")
    print("-" * 80)

    write_throughput_data = get_metric_statistics(instance_id, 'WriteThroughput', days=7)

    if write_throughput_data:
        avg_values = [dp['Average'] for dp in write_throughput_data]
        max_values = [dp['Maximum'] for dp in write_throughput_data]

        avg_mean = statistics.mean(avg_values)
        avg_median = statistics.median(avg_values)
        max_peak = max(max_values)
        max_mean = statistics.mean(max_values)

        # Convert to MB/s for readability
        print(f"平均 Throughput: {avg_mean/1048576:.2f} MB/s")
        print(f"中位數 Throughput: {avg_median/1048576:.2f} MB/s")
        print(f"峰值 Throughput: {max_peak/1048576:.2f} MB/s")
        print(f"最大值平均: {max_mean/1048576:.2f} MB/s")
        print(f"數據點數: {len(write_throughput_data)}")

        # Suggest threshold (150% of average maximum)
        suggested_throughput = max_mean * 1.5
        print(f"\n建議閾值: {suggested_throughput/1048576:.0f} MB/s ({suggested_throughput:.0f} bytes/s)")
        print(f"         (平均峰值的 150%)")
    else:
        print("❌ 無數據")
        suggested_throughput = None

    return {
        'instance_id': instance_id,
        'instance_class': instance_class,
        'write_iops': {
            'avg_mean': avg_mean if write_iops_data else 0,
            'max_peak': max_peak if write_iops_data else 0,
            'suggested_threshold': suggested_threshold
        },
        'write_throughput': {
            'avg_mean': avg_mean if write_throughput_data else 0,
            'max_peak': max_peak if write_throughput_data else 0,
            'suggested_throughput': suggested_throughput
        }
    }

def main():
    print("="*80)
    print("RDS Write Metrics 分析工具")
    print("分析期間: 最近 7 天")
    print("="*80)

    results = []

    for instance_id in INSTANCES:
        try:
            result = analyze_instance(instance_id)
            results.append(result)
        except Exception as e:
            print(f"❌ 分析 {instance_id} 時發生錯誤: {e}")

    # Summary
    print(f"\n{'='*80}")
    print("摘要建議")
    print(f"{'='*80}\n")

    print("建議的告警閾值:")
    print("-" * 80)
    print(f"{'實例':<35} {'WriteIOPS':<15} {'WriteThroughput':<20}")
    print("-" * 80)

    for result in results:
        instance_id = result['instance_id']
        iops_threshold = result['write_iops']['suggested_threshold']
        throughput_threshold = result['write_throughput']['suggested_throughput']

        if iops_threshold:
            iops_str = f"{iops_threshold:.0f} IOPS"
        else:
            iops_str = "無數據"

        if throughput_threshold:
            throughput_str = f"{throughput_threshold/1048576:.0f} MB/s"
        else:
            throughput_str = "無數據"

        print(f"{instance_id:<35} {iops_str:<15} {throughput_str:<20}")

    print("\n建議優先級:")
    print("-" * 80)
    print("• WriteIOPS: P2 (Medium Priority)")
    print("  原因: 影響性能但通常不會立即導致服務中斷")
    print("  響應時間: < 4 小時")
    print()
    print("• WriteThroughput: P2 (Medium Priority)")
    print("  原因: 影響寫入性能但通常不會立即導致服務中斷")
    print("  響應時間: < 4 小時")
    print()
    print("建議閾值計算方式: 平均峰值的 150%")
    print("目的: 檢測異常的寫入活動，同時避免誤報")
    print("="*80)

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
分析 RDS 實例的高負載問題
"""

import boto3
import sys
from datetime import datetime, timedelta
from collections import defaultdict

AWS_PROFILE = 'gemini-pro_ck'

def get_instance_info(session, instance_id):
    """獲取實例基本資訊"""
    rds = session.client('rds')
    response = rds.describe_db_instances(DBInstanceIdentifier=instance_id)
    return response['DBInstances'][0]

def get_metric_statistics(session, instance_id, metric_name, hours=1):
    """獲取 CloudWatch 指標統計"""
    cloudwatch = session.client('cloudwatch')

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=hours)

    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName=metric_name,
        Dimensions=[
            {'Name': 'DBInstanceIdentifier', 'Value': instance_id}
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,  # 5 分鐘
        Statistics=['Average', 'Maximum', 'Minimum']
    )

    # 排序數據點
    datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
    return datapoints

def analyze_instance(session, instance_id, compare_with=None):
    """分析實例負載"""

    print("=" * 100)
    print(f"RDS 實例高負載分析: {instance_id}")
    print("=" * 100)
    print()

    # 1. 基本資訊
    print("📋 1. 實例基本資訊")
    print("-" * 100)

    instance = get_instance_info(session, instance_id)

    print(f"實例 ID:        {instance['DBInstanceIdentifier']}")
    print(f"狀態:           {instance['DBInstanceStatus']}")
    print(f"實例類型:       {instance['DBInstanceClass']}")
    print(f"引擎:           {instance['Engine']} {instance['EngineVersion']}")
    print(f"可用區:         {instance['AvailabilityZone']}")
    print(f"儲存空間:       {instance.get('AllocatedStorage', 'N/A')} GB")
    print(f"IOPS:           {instance.get('Iops', 'N/A')}")
    print(f"儲存類型:       {instance.get('StorageType', 'N/A')}")

    if instance.get('ReadReplicaSourceDBInstanceIdentifier'):
        print(f"複製來源:       {instance['ReadReplicaSourceDBInstanceIdentifier']}")

    if instance.get('ReadReplicaDBInstanceIdentifiers'):
        print(f"Read Replicas:  {', '.join(instance['ReadReplicaDBInstanceIdentifiers'])}")

    print()

    # 2. CloudWatch 指標分析（最近 1 小時）
    print("📊 2. CloudWatch 指標分析（最近 1 小時）")
    print("-" * 100)

    metrics = {
        'CPUUtilization': 'CPU 使用率 (%)',
        'DatabaseConnections': '資料庫連接數',
        'FreeableMemory': '可用記憶體 (MB)',
        'ReadIOPS': '讀取 IOPS',
        'WriteIOPS': '寫入 IOPS',
        'ReadLatency': '讀取延遲 (ms)',
        'WriteLatency': '寫入延遲 (ms)',
        'ReadThroughput': '讀取吞吐量 (MB/s)',
        'WriteThroughput': '寫入吞吐量 (MB/s)',
    }

    # 如果是 Read Replica，加入複製延遲
    if instance.get('ReadReplicaSourceDBInstanceIdentifier'):
        metrics['ReplicaLag'] = '複製延遲 (秒)'

    metric_data = {}

    for metric_name, display_name in metrics.items():
        datapoints = get_metric_statistics(session, instance_id, metric_name, hours=1)

        if datapoints:
            # 計算統計值
            values = [dp['Average'] for dp in datapoints]

            # 特殊處理記憶體（轉換為 MB）
            if metric_name == 'FreeableMemory':
                values = [v / 1024 / 1024 for v in values]

            # 特殊處理延遲（轉換為毫秒）
            if 'Latency' in metric_name:
                values = [v * 1000 for v in values]

            # 特殊處理吞吐量（轉換為 MB/s）
            if 'Throughput' in metric_name:
                values = [v / 1024 / 1024 for v in values]

            avg_value = sum(values) / len(values) if values else 0
            max_value = max(values) if values else 0
            min_value = min(values) if values else 0
            latest_value = values[-1] if values else 0

            metric_data[metric_name] = {
                'display_name': display_name,
                'avg': avg_value,
                'max': max_value,
                'min': min_value,
                'latest': latest_value,
                'datapoints': len(datapoints)
            }

    # 顯示指標
    print(f"{'指標':<25} | {'最新值':>12} | {'平均值':>12} | {'最大值':>12} | {'最小值':>12} | 狀態")
    print("-" * 100)

    for metric_name, data in metric_data.items():
        display_name = data['display_name']
        latest = data['latest']
        avg = data['avg']
        max_val = data['max']
        min_val = data['min']

        # 評估狀態
        status = "✅ 正常"
        if metric_name == 'CPUUtilization':
            if latest > 80:
                status = "🔴 嚴重"
            elif latest > 60:
                status = "⚠️ 警告"
        elif metric_name == 'DatabaseConnections':
            # 假設實例類型連接數上限
            if latest > 200:
                status = "⚠️ 偏高"
        elif metric_name == 'FreeableMemory':
            if latest < 500:  # MB
                status = "🔴 嚴重"
            elif latest < 1000:
                status = "⚠️ 警告"
        elif metric_name == 'ReplicaLag':
            if latest > 60:
                status = "🔴 嚴重"
            elif latest > 10:
                status = "⚠️ 警告"
        elif 'Latency' in metric_name:
            if latest > 10:  # ms
                status = "⚠️ 偏高"

        print(f"{display_name:<25} | {latest:>12.2f} | {avg:>12.2f} | {max_val:>12.2f} | {min_val:>12.2f} | {status}")

    print()

    # 3. 與主實例對比（如果是 Read Replica）
    if compare_with:
        print(f"📊 3. 與主實例對比: {instance_id} vs {compare_with}")
        print("-" * 100)

        compare_metrics = {}
        for metric_name in ['CPUUtilization', 'DatabaseConnections', 'ReadIOPS', 'WriteIOPS']:
            datapoints = get_metric_statistics(session, compare_with, metric_name, hours=1)
            if datapoints:
                values = [dp['Average'] for dp in datapoints]
                avg_value = sum(values) / len(values) if values else 0
                compare_metrics[metric_name] = avg_value

        print(f"{'指標':<25} | {f'{instance_id} (Replica)':>25} | {f'{compare_with} (Primary)':>25} | 差異")
        print("-" * 100)

        for metric_name in ['CPUUtilization', 'DatabaseConnections', 'ReadIOPS', 'WriteIOPS']:
            if metric_name in metric_data and metric_name in compare_metrics:
                replica_val = metric_data[metric_name]['avg']
                primary_val = compare_metrics[metric_name]
                diff = replica_val - primary_val
                diff_pct = (diff / primary_val * 100) if primary_val > 0 else 0

                diff_str = f"{diff:+.2f} ({diff_pct:+.1f}%)"

                print(f"{metrics[metric_name]:<25} | {replica_val:>25.2f} | {primary_val:>25.2f} | {diff_str}")

        print()

    # 4. 問題診斷
    print("🔍 4. 問題診斷")
    print("-" * 100)

    issues = []
    recommendations = []

    # CPU 分析
    if 'CPUUtilization' in metric_data:
        cpu_avg = metric_data['CPUUtilization']['avg']
        cpu_max = metric_data['CPUUtilization']['max']

        if cpu_avg > 80:
            issues.append(f"🔴 CPU 使用率持續偏高 (平均: {cpu_avg:.1f}%)")
            recommendations.append("考慮升級實例類型或優化查詢")
        elif cpu_avg > 60:
            issues.append(f"⚠️ CPU 使用率較高 (平均: {cpu_avg:.1f}%)")
            recommendations.append("監控是否有慢查詢，考慮建立索引")

    # 記憶體分析
    if 'FreeableMemory' in metric_data:
        mem_avg = metric_data['FreeableMemory']['avg']

        if mem_avg < 500:
            issues.append(f"🔴 可用記憶體不足 (平均: {mem_avg:.0f} MB)")
            recommendations.append("升級實例類型以獲得更多記憶體")
        elif mem_avg < 1000:
            issues.append(f"⚠️ 可用記憶體偏低 (平均: {mem_avg:.0f} MB)")
            recommendations.append("監控記憶體使用趨勢")

    # 連接數分析
    if 'DatabaseConnections' in metric_data:
        conn_avg = metric_data['DatabaseConnections']['avg']
        conn_max = metric_data['DatabaseConnections']['max']

        if conn_max > 200:
            issues.append(f"⚠️ 連接數偏高 (最大: {conn_max:.0f})")
            recommendations.append("檢查連接池配置，確保應用程式正確關閉連接")

    # 複製延遲分析
    if 'ReplicaLag' in metric_data:
        lag_avg = metric_data['ReplicaLag']['avg']
        lag_max = metric_data['ReplicaLag']['max']

        if lag_avg > 60:
            issues.append(f"🔴 複製延遲嚴重 (平均: {lag_avg:.1f} 秒)")
            recommendations.append("可能是主實例寫入量過大，考慮使用更大的 Replica 實例")
        elif lag_avg > 10:
            issues.append(f"⚠️ 複製延遲較高 (平均: {lag_avg:.1f} 秒)")
            recommendations.append("監控主實例的寫入負載")

    # IOPS 分析
    if 'ReadIOPS' in metric_data or 'WriteIOPS' in metric_data:
        read_iops = metric_data.get('ReadIOPS', {}).get('avg', 0)
        write_iops = metric_data.get('WriteIOPS', {}).get('avg', 0)
        total_iops = read_iops + write_iops

        allocated_iops = instance.get('Iops', 0)
        if allocated_iops and total_iops > allocated_iops * 0.8:
            issues.append(f"⚠️ IOPS 使用率高 ({total_iops:.0f} / {allocated_iops})")
            recommendations.append("考慮增加 Provisioned IOPS 或使用 io2 儲存")

    if issues:
        print("發現的問題：")
        for issue in issues:
            print(f"  {issue}")
    else:
        print("✅ 未發現明顯問題")

    print()

    if recommendations:
        print("建議行動：")
        for rec in recommendations:
            print(f"  • {rec}")

    print()
    print("=" * 100)

def main():
    if len(sys.argv) < 2:
        print("用法: python3 analyze-high-load.py <instance-id> [compare-with-instance-id]")
        print("範例: python3 analyze-high-load.py bingo-prd-replica1 bingo-prd")
        sys.exit(1)

    instance_id = sys.argv[1]
    compare_with = sys.argv[2] if len(sys.argv) > 2 else None

    session = boto3.Session(profile_name=AWS_PROFILE)

    try:
        analyze_instance(session, instance_id, compare_with)
    except Exception as e:
        print(f"❌ 錯誤: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

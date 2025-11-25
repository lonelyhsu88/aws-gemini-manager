#!/usr/bin/env python3
"""
Stopped EC2 Instances Cost Analysis Script
專門分析 stopped 狀態實例的成本
"""

import json
import boto3
from collections import defaultdict
from datetime import datetime

# AWS Profile
AWS_PROFILE = 'gemini-pro_ck'

# AWS ap-east-1 (Hong Kong) Pricing (USD per hour) - On-Demand Linux
EC2_PRICING = {
    't3.micro': 0.0132,
    't3.small': 0.0264,
    't3.medium': 0.0528,
    't3.large': 0.1056,
    't3.xlarge': 0.2112,
    'c5.xlarge': 0.229,
    'c5a.xlarge': 0.206,
    'c5a.2xlarge': 0.412,
}

# EBS gp3 pricing in ap-east-1 (USD per GB-month)
EBS_PRICING_PER_GB_MONTH = 0.092

# Hours per month (average)
HOURS_PER_MONTH = 730

def get_stopped_instances():
    """Get all stopped EC2 instances with details"""
    session = boto3.Session(profile_name=AWS_PROFILE)
    ec2 = session.client('ec2')

    response = ec2.describe_instances(
        Filters=[
            {'Name': 'instance-state-name', 'Values': ['stopped']}
        ]
    )

    stopped_instances = []

    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            # Get instance name from tags
            name = 'N/A'
            if 'Tags' in instance:
                for tag in instance['Tags']:
                    if tag['Key'] == 'Name':
                        name = tag['Value']
                        break

            # Get EBS volume sizes
            total_storage = 0
            volume_ids = []
            if 'BlockDeviceMappings' in instance:
                volume_ids = [bdm['Ebs']['VolumeId'] for bdm in instance['BlockDeviceMappings'] if 'Ebs' in bdm]
                if volume_ids:
                    volumes_response = ec2.describe_volumes(VolumeIds=volume_ids)
                    total_storage = sum(vol['Size'] for vol in volumes_response['Volumes'])

            # Get launch time
            launch_time = instance.get('LaunchTime', None)
            stopped_time = instance.get('StateTransitionReason', 'Unknown')

            stopped_instances.append({
                'id': instance['InstanceId'],
                'type': instance['InstanceType'],
                'name': name,
                'storage_gb': total_storage,
                'az': instance['Placement']['AvailabilityZone'],
                'launch_time': launch_time,
                'state_reason': stopped_time
            })

    return stopped_instances

def categorize_instances(instances):
    """Categorize instances by service type"""
    categories = {
        'Bingo Games': [],
        'Hash Games': [],
        'Arcade Games': [],
        'Stress Testing': [],
        'Infrastructure': []
    }

    for inst in instances:
        name = inst['name'].lower()
        if 'bingo-prd' in name and 'game' in name:
            categories['Bingo Games'].append(inst)
        elif 'hash-prd' in name:
            categories['Hash Games'].append(inst)
        elif 'arcade-prd' in name:
            categories['Arcade Games'].append(inst)
        elif 'stress' in name:
            categories['Stress Testing'].append(inst)
        else:
            categories['Infrastructure'].append(inst)

    return categories

def calculate_stopped_costs(instances):
    """Calculate costs for stopped instances"""

    results = []
    total_current_storage_cost = 0
    total_potential_compute_cost = 0
    total_potential_cost = 0

    instance_type_stats = defaultdict(lambda: {
        'count': 0,
        'storage_gb': 0,
        'current_cost': 0,
        'potential_compute_cost': 0,
        'potential_total_cost': 0
    })

    for instance in instances:
        instance_type = instance['type']
        storage_gb = instance['storage_gb']

        # Current storage cost (while stopped)
        storage_cost_monthly = storage_gb * EBS_PRICING_PER_GB_MONTH

        # Potential compute cost if running
        hourly_rate = EC2_PRICING.get(instance_type, 0)
        compute_cost_monthly = hourly_rate * HOURS_PER_MONTH

        # Total potential cost if running
        total_cost_monthly = compute_cost_monthly + storage_cost_monthly

        results.append({
            'name': instance['name'],
            'id': instance['id'],
            'type': instance_type,
            'storage_gb': storage_gb,
            'az': instance['az'],
            'current_storage_cost': storage_cost_monthly,
            'potential_compute_cost': compute_cost_monthly,
            'potential_total_cost': total_cost_monthly,
            'launch_time': instance['launch_time']
        })

        # Update totals
        total_current_storage_cost += storage_cost_monthly
        total_potential_compute_cost += compute_cost_monthly
        total_potential_cost += total_cost_monthly

        # Update instance type stats
        instance_type_stats[instance_type]['count'] += 1
        instance_type_stats[instance_type]['storage_gb'] += storage_gb
        instance_type_stats[instance_type]['current_cost'] += storage_cost_monthly
        instance_type_stats[instance_type]['potential_compute_cost'] += compute_cost_monthly
        instance_type_stats[instance_type]['potential_total_cost'] += total_cost_monthly

    return {
        'instances': results,
        'instance_type_stats': dict(instance_type_stats),
        'totals': {
            'count': len(instances),
            'total_storage_gb': sum(inst['storage_gb'] for inst in instances),
            'current_storage_cost': total_current_storage_cost,
            'potential_compute_cost': total_potential_compute_cost,
            'potential_total_cost': total_potential_cost
        }
    }

def print_report(cost_data, categories):
    """Print formatted report for stopped instances"""

    totals = cost_data['totals']

    print("=" * 120)
    print("Stopped EC2 實例成本分析報告")
    print(f"生成時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"AWS Region: ap-east-1 (Hong Kong)")
    print("=" * 120)
    print()

    # Summary
    print("📊 總覽")
    print("-" * 120)
    print(f"Stopped 實例總數: {totals['count']} 個")
    print(f"總 EBS 儲存容量: {totals['total_storage_gb']} GB")
    print()

    # Current vs Potential costs
    print("💰 成本對比 (月度)")
    print("-" * 120)
    print(f"{'項目':<50} {'成本 (USD/月)':<20}")
    print("-" * 120)
    print(f"{'當前狀態 (Stopped - 僅 EBS 儲存)':<50} ${totals['current_storage_cost']:>18,.2f}")
    print(f"{'如果全部啟動 (Running - 運算 + 儲存)':<50} ${totals['potential_total_cost']:>18,.2f}")
    print("-" * 120)
    print(f"{'差額 (啟動的額外成本)':<50} ${totals['potential_compute_cost']:>18,.2f}")
    print(f"{'成本增幅':<50} {(totals['potential_compute_cost']/totals['current_storage_cost']*100):>17,.1f}%")
    print()

    # Instance type breakdown
    print("🖥️  按實例類型分組")
    print("-" * 120)
    print(f"{'類型':<15} {'數量':<8} {'儲存(GB)':<12} {'當前成本':<18} {'潛在運算成本':<18} {'啟動後總成本':<18}")
    print("-" * 120)

    instance_type_stats = cost_data['instance_type_stats']
    for itype in sorted(instance_type_stats.keys()):
        stats = instance_type_stats[itype]
        print(f"{itype:<15} {stats['count']:<8} {stats['storage_gb']:<12} "
              f"${stats['current_cost']:<17,.2f} ${stats['potential_compute_cost']:<17,.2f} "
              f"${stats['potential_total_cost']:<17,.2f}")

    print()

    # Category breakdown
    print("🎮 按服務類型分組")
    print("-" * 120)
    print(f"{'服務類型':<20} {'實例數':<10} {'當前成本 (USD/月)':<25} {'啟動後成本 (USD/月)':<25}")
    print("-" * 120)

    for category_name, instances in categories.items():
        if instances:
            category_current = sum(inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH for inst in instances)
            category_potential = sum(
                (inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH +
                 EC2_PRICING.get(inst['type'], 0) * HOURS_PER_MONTH)
                for inst in instances
            )
            print(f"{category_name:<20} {len(instances):<10} ${category_current:<24,.2f} ${category_potential:<24,.2f}")

    print()

    # Top 20 most expensive if started
    print("💸 啟動成本最高的 20 個實例 (按啟動後月度成本排序)")
    print("-" * 120)
    print(f"{'實例名稱':<45} {'類型':<12} {'當前':<12} {'運算':<12} {'啟動後':<12}")
    print("-" * 120)

    sorted_instances = sorted(cost_data['instances'], key=lambda x: x['potential_total_cost'], reverse=True)[:20]
    for inst in sorted_instances:
        print(f"{inst['name']:<45} {inst['type']:<12} "
              f"${inst['current_storage_cost']:<11,.2f} ${inst['potential_compute_cost']:<11,.2f} "
              f"${inst['potential_total_cost']:<11,.2f}")

    print()

    # Detailed list by category
    print("📋 詳細實例清單 (按服務類型)")
    print("=" * 120)

    for category_name, instances in categories.items():
        if instances:
            print(f"\n### {category_name} ({len(instances)} 個)")
            print("-" * 120)
            print(f"{'實例名稱':<45} {'ID':<22} {'類型':<12} {'儲存':<10} {'當前':<12} {'啟動後':<12}")
            print("-" * 120)

            for inst in sorted(instances, key=lambda x: x['name']):
                storage_cost = inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH
                compute_cost = EC2_PRICING.get(inst['type'], 0) * HOURS_PER_MONTH
                total_cost = storage_cost + compute_cost

                print(f"{inst['name']:<45} {inst['id']:<22} {inst['type']:<12} "
                      f"{inst['storage_gb']:<10} ${storage_cost:<11,.2f} ${total_cost:<11,.2f}")

    print()
    print("=" * 120)
    print("🔑 關鍵建議")
    print("-" * 120)
    print(f"1. 當前這 {totals['count']} 個 stopped 實例每月消耗 ${totals['current_storage_cost']:.2f} USD 的 EBS 儲存成本")
    print(f"2. 如果全部啟動，月度成本將增加到 ${totals['potential_total_cost']:.2f} USD")
    print(f"3. 額外運算成本為 ${totals['potential_compute_cost']:.2f} USD/月 (增加 {(totals['potential_compute_cost']/totals['current_storage_cost']*100):.0f}%)")
    print()
    print("💡 優化建議:")
    print("   • 評估長期 stopped 的實例是否仍需保留")
    print("   • 考慮為不再使用的實例創建 AMI 快照後刪除，節省 EBS 成本")
    print("   • 如需定期使用，考慮使用 AWS Instance Scheduler 自動化啟停")
    print("   • 對於開發/測試環境，建議非工作時間自動停止")
    print("=" * 120)

def main():
    print("正在收集 Stopped EC2 實例數據...")
    stopped_instances = get_stopped_instances()

    print(f"找到 {len(stopped_instances)} 個 stopped 實例")
    print()

    print("正在分析成本...")
    cost_data = calculate_stopped_costs(stopped_instances)

    print("正在分類實例...")
    categories = categorize_instances(stopped_instances)

    print()
    print_report(cost_data, categories)

    # Save detailed results
    output_file = 'stopped_instances_cost_analysis.json'
    output_data = {
        'generated_at': datetime.now().isoformat(),
        'region': 'ap-east-1',
        'cost_data': cost_data,
        'categories': {k: [inst for inst in v] for k, v in categories.items()}
    }

    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2, default=str)

    print(f"\n✅ 詳細分析已保存至: {output_file}")

if __name__ == '__main__':
    main()

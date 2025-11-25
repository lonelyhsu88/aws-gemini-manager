#!/usr/bin/env python3
"""
EC2 Cost Analysis Script
Analyzes running vs stopped EC2 instances and calculates cost implications
"""

import json
import boto3
from collections import defaultdict
from datetime import datetime

# AWS Profile
AWS_PROFILE = 'gemini-pro_ck'

# AWS ap-east-1 (Hong Kong) Pricing (USD per hour) - On-Demand Linux
# Source: AWS Pricing as of 2024
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

def get_instances_by_state():
    """Get all EC2 instances grouped by state"""
    session = boto3.Session(profile_name=AWS_PROFILE)
    ec2 = session.client('ec2')

    response = ec2.describe_instances()

    instances_by_state = {
        'running': [],
        'stopped': []
    }

    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            state = instance['State']['Name']
            if state in ['running', 'stopped']:
                # Get instance name from tags
                name = 'N/A'
                if 'Tags' in instance:
                    for tag in instance['Tags']:
                        if tag['Key'] == 'Name':
                            name = tag['Value']
                            break

                # Get EBS volume sizes
                total_storage = 0
                if 'BlockDeviceMappings' in instance:
                    volume_ids = [bdm['Ebs']['VolumeId'] for bdm in instance['BlockDeviceMappings'] if 'Ebs' in bdm]
                    if volume_ids:
                        volumes_response = ec2.describe_volumes(VolumeIds=volume_ids)
                        total_storage = sum(vol['Size'] for vol in volumes_response['Volumes'])

                instances_by_state[state].append({
                    'id': instance['InstanceId'],
                    'type': instance['InstanceType'],
                    'name': name,
                    'storage_gb': total_storage,
                    'az': instance['Placement']['AvailabilityZone']
                })

    return instances_by_state

def calculate_costs(instances_by_state):
    """Calculate monthly costs for running and stopped instances"""

    # Hours per month (average)
    HOURS_PER_MONTH = 730

    results = {
        'running': {'instances': [], 'total_compute': 0, 'total_storage': 0, 'total': 0},
        'stopped': {'instances': [], 'total_compute': 0, 'total_storage': 0, 'total': 0},
        'summary': {}
    }

    # Count instance types
    instance_type_count = {'running': defaultdict(int), 'stopped': defaultdict(int)}

    for state in ['running', 'stopped']:
        for instance in instances_by_state[state]:
            instance_type = instance['type']
            storage_gb = instance['storage_gb']

            # Count instance types
            instance_type_count[state][instance_type] += 1

            # Calculate compute cost (only for running instances)
            compute_cost_monthly = 0
            if state == 'running':
                hourly_rate = EC2_PRICING.get(instance_type, 0)
                compute_cost_monthly = hourly_rate * HOURS_PER_MONTH

            # Calculate storage cost (for both running and stopped)
            storage_cost_monthly = storage_gb * EBS_PRICING_PER_GB_MONTH

            total_cost_monthly = compute_cost_monthly + storage_cost_monthly

            results[state]['instances'].append({
                'name': instance['name'],
                'id': instance['id'],
                'type': instance_type,
                'storage_gb': storage_gb,
                'compute_cost': compute_cost_monthly,
                'storage_cost': storage_cost_monthly,
                'total_cost': total_cost_monthly
            })

            results[state]['total_compute'] += compute_cost_monthly
            results[state]['total_storage'] += storage_cost_monthly
            results[state]['total'] += total_cost_monthly

    # Add instance type counts to results
    results['instance_type_count'] = instance_type_count

    # Calculate summary
    results['summary'] = {
        'running_count': len(instances_by_state['running']),
        'stopped_count': len(instances_by_state['stopped']),
        'total_count': len(instances_by_state['running']) + len(instances_by_state['stopped']),
        'running_monthly_cost': results['running']['total'],
        'stopped_monthly_cost': results['stopped']['total'],
        'total_monthly_cost': results['running']['total'] + results['stopped']['total'],
        'potential_savings_if_all_stopped': results['running']['total_compute'],
        'cost_if_all_running': results['running']['total'] + results['stopped']['total_compute'] + results['stopped']['total_storage']
    }

    # Calculate potential compute cost if stopped instances were running
    stopped_potential_compute = 0
    for instance in instances_by_state['stopped']:
        instance_type = instance['type']
        hourly_rate = EC2_PRICING.get(instance_type, 0)
        stopped_potential_compute += hourly_rate * HOURS_PER_MONTH

    results['summary']['stopped_potential_compute_cost'] = stopped_potential_compute
    results['summary']['cost_if_all_running'] = results['running']['total'] + stopped_potential_compute + results['stopped']['total_storage']

    return results

def print_report(results):
    """Print formatted cost analysis report"""

    print("=" * 100)
    print("EC2 成本分析報告 - AWS Gemini Manager")
    print(f"生成時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"AWS Region: ap-east-1 (Hong Kong)")
    print("=" * 100)
    print()

    # Summary
    summary = results['summary']
    print("📊 總覽")
    print("-" * 100)
    print(f"總實例數: {summary['total_count']} 個")
    print(f"  ├─ Running: {summary['running_count']} 個")
    print(f"  └─ Stopped: {summary['stopped_count']} 個")
    print()

    # Instance type breakdown
    print("🖥️  實例類型分佈")
    print("-" * 100)
    print(f"{'Instance Type':<15} {'Running':<10} {'Stopped':<10} {'Total':<10} {'單價/小時 (USD)':<20}")
    print("-" * 100)

    all_types = set(list(results['instance_type_count']['running'].keys()) +
                   list(results['instance_type_count']['stopped'].keys()))

    for itype in sorted(all_types):
        running_count = results['instance_type_count']['running'].get(itype, 0)
        stopped_count = results['instance_type_count']['stopped'].get(itype, 0)
        total_count = running_count + stopped_count
        price = EC2_PRICING.get(itype, 0)
        print(f"{itype:<15} {running_count:<10} {stopped_count:<10} {total_count:<10} ${price:.4f}")

    print()

    # Monthly costs
    print("💰 月度成本分析")
    print("-" * 100)
    print(f"{'項目':<40} {'運算成本 (USD)':<20} {'儲存成本 (USD)':<20} {'總成本 (USD)':<20}")
    print("-" * 100)

    print(f"{'Running 實例 (當前)':<40} ${results['running']['total_compute']:>18,.2f} ${results['running']['total_storage']:>18,.2f} ${results['running']['total']:>18,.2f}")
    print(f"{'Stopped 實例 (當前)':<40} ${results['stopped']['total_compute']:>18,.2f} ${results['stopped']['total_storage']:>18,.2f} ${results['stopped']['total']:>18,.2f}")
    print("-" * 100)
    print(f"{'當前總成本':<40} ${results['running']['total_compute'] + results['stopped']['total_compute']:>18,.2f} ${results['running']['total_storage'] + results['stopped']['total_storage']:>18,.2f} ${summary['total_monthly_cost']:>18,.2f}")
    print()

    # Scenarios
    print("📈 成本情境分析")
    print("-" * 100)
    print(f"1️⃣  當前狀態 (34 running + 64 stopped):")
    print(f"   月度成本: ${summary['total_monthly_cost']:,.2f} USD")
    print()

    print(f"2️⃣  全部停止 (0 running + 98 stopped):")
    all_stopped_cost = results['running']['total_storage'] + results['stopped']['total_storage']
    savings = summary['total_monthly_cost'] - all_stopped_cost
    print(f"   月度成本: ${all_stopped_cost:,.2f} USD")
    print(f"   💡 節省: ${savings:,.2f} USD/月 ({savings/summary['total_monthly_cost']*100:.1f}%)")
    print()

    print(f"3️⃣  全部運行 (98 running + 0 stopped):")
    all_running_cost = summary['cost_if_all_running']
    additional_cost = all_running_cost - summary['total_monthly_cost']
    print(f"   月度成本: ${all_running_cost:,.2f} USD")
    print(f"   ⚠️  額外成本: +${additional_cost:,.2f} USD/月 ({additional_cost/summary['total_monthly_cost']*100:.1f}%)")
    print()

    # Key insights
    print("🔑 關鍵洞察")
    print("-" * 100)
    print(f"• Stopped 實例每月仍需支付 EBS 儲存成本: ${results['stopped']['total_storage']:,.2f} USD")
    print(f"• Running 實例的運算成本佔總成本: {results['running']['total_compute']/summary['total_monthly_cost']*100:.1f}%")
    print(f"• 如果將所有 Running 實例停止，可節省: ${results['running']['total_compute']:,.2f} USD/月")
    print(f"• 如果將所有 Stopped 實例啟動，額外成本: +${summary['stopped_potential_compute_cost']:,.2f} USD/月")
    print()

    # Top 10 most expensive instances
    print("💸 成本最高的 10 個實例 (當前 Running)")
    print("-" * 100)
    print(f"{'實例名稱':<40} {'類型':<15} {'運算':<15} {'儲存':<15} {'總成本':<15}")
    print("-" * 100)

    running_sorted = sorted(results['running']['instances'], key=lambda x: x['total_cost'], reverse=True)[:10]
    for inst in running_sorted:
        print(f"{inst['name']:<40} {inst['type']:<15} ${inst['compute_cost']:<14.2f} ${inst['storage_cost']:<14.2f} ${inst['total_cost']:<14.2f}")

    print()
    print("=" * 100)
    print("注意:")
    print("1. 以上價格基於 AWS ap-east-1 (香港) 區域的 On-Demand 定價")
    print("2. EBS 定價假設使用 gp3 卷類型")
    print("3. 實際成本可能因數據傳輸、快照等額外費用而有所不同")
    print("4. Reserved Instances 或 Savings Plans 可大幅降低成本")
    print("=" * 100)

def main():
    print("正在收集 EC2 實例數據...")
    instances_by_state = get_instances_by_state()

    print("正在計算成本...")
    results = calculate_costs(instances_by_state)

    print()
    print_report(results)

    # Save detailed results to JSON
    output_file = 'ec2_cost_analysis.json'
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    print(f"\n詳細分析已保存至: {output_file}")

if __name__ == '__main__':
    main()

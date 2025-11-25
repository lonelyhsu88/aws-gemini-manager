#!/usr/bin/env python3
"""
List Stopped EC2 Instances (Excluding Stress Testing)
列出所有 stopped 實例，排除 stress 測試機器
"""

import json
import boto3
from datetime import datetime

# AWS Profile
AWS_PROFILE = 'gemini-pro_ck'

# EBS gp3 pricing in ap-east-1 (USD per GB-month)
EBS_PRICING_PER_GB_MONTH = 0.092

def get_stopped_instances_exclude_stress():
    """Get all stopped EC2 instances excluding stress testing machines"""
    session = boto3.Session(profile_name=AWS_PROFILE)
    ec2 = session.client('ec2')

    response = ec2.describe_instances(
        Filters=[
            {'Name': 'instance-state-name', 'Values': ['stopped']}
        ]
    )

    stopped_instances = []
    stress_instances = []

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

            instance_data = {
                'id': instance['InstanceId'],
                'type': instance['InstanceType'],
                'name': name,
                'storage_gb': total_storage,
                'az': instance['Placement']['AvailabilityZone'],
                'launch_time': launch_time
            }

            # Separate stress testing instances
            if 'stress' in name.lower():
                stress_instances.append(instance_data)
            else:
                stopped_instances.append(instance_data)

    return stopped_instances, stress_instances

def categorize_instances(instances):
    """Categorize instances by service type"""
    categories = {
        'Bingo Games': [],
        'Hash Games': [],
        'Arcade Games': [],
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
        else:
            categories['Infrastructure'].append(inst)

    return categories

def print_report(stopped_instances, stress_instances):
    """Print formatted report"""

    print("=" * 120)
    print("Stopped EC2 實例清單 (排除 Stress 測試機器)")
    print(f"生成時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"AWS Region: ap-east-1 (Hong Kong)")
    print("=" * 120)
    print()

    # Summary
    total_storage = sum(inst['storage_gb'] for inst in stopped_instances)
    total_storage_cost = total_storage * EBS_PRICING_PER_GB_MONTH

    stress_storage = sum(inst['storage_gb'] for inst in stress_instances)
    stress_storage_cost = stress_storage * EBS_PRICING_PER_GB_MONTH

    print("📊 總覽")
    print("-" * 120)
    print(f"排除前 Stopped 實例總數: {len(stopped_instances) + len(stress_instances)} 個")
    print(f"  ├─ Stress 測試機器 (已排除): {len(stress_instances)} 個")
    print(f"  └─ 其他 Stopped 實例: {len(stopped_instances)} 個")
    print()
    print(f"總 EBS 儲存容量: {total_storage} GB (排除後)")
    print(f"當前 EBS 月度成本: ${total_storage_cost:.2f} USD (排除後)")
    print()
    print(f"Stress 機器儲存: {stress_storage} GB (已排除)")
    print(f"Stress 機器成本: ${stress_storage_cost:.2f} USD/月 (已節省)")
    print()

    # Categorize
    categories = categorize_instances(stopped_instances)

    # Category summary
    print("🎮 按服務類型統計")
    print("-" * 120)
    print(f"{'服務類型':<20} {'實例數':<10} {'儲存 (GB)':<15} {'月度成本 (USD)':<20}")
    print("-" * 120)

    for category_name, instances in categories.items():
        if instances:
            cat_storage = sum(inst['storage_gb'] for inst in instances)
            cat_cost = cat_storage * EBS_PRICING_PER_GB_MONTH
            print(f"{category_name:<20} {len(instances):<10} {cat_storage:<15} ${cat_cost:<19.2f}")

    print()

    # Detailed list by category
    print("📋 詳細實例清單")
    print("=" * 120)

    for category_name, instances in categories.items():
        if instances:
            print(f"\n### {category_name} ({len(instances)} 個)")
            print("-" * 120)
            print(f"{'No.':<5} {'實例名稱':<45} {'Instance ID':<22} {'類型':<12} {'儲存(GB)':<10} {'月度成本':<12}")
            print("-" * 120)

            sorted_instances = sorted(instances, key=lambda x: x['name'])
            for idx, inst in enumerate(sorted_instances, 1):
                storage_cost = inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH
                print(f"{idx:<5} {inst['name']:<45} {inst['id']:<22} {inst['type']:<12} "
                      f"{inst['storage_gb']:<10} ${storage_cost:<11.2f}")

    # Excluded stress instances
    print()
    print("=" * 120)
    print(f"### ❌ 已排除的 Stress 測試機器 ({len(stress_instances)} 個)")
    print("-" * 120)
    print(f"{'實例名稱':<45} {'Instance ID':<22} {'類型':<12} {'儲存(GB)':<10}")
    print("-" * 120)

    for inst in sorted(stress_instances, key=lambda x: x['name']):
        print(f"{inst['name']:<45} {inst['id']:<22} {inst['type']:<12} {inst['storage_gb']:<10}")

    print()
    print("=" * 120)

def export_csv(stopped_instances):
    """Export to CSV format"""
    csv_file = 'stopped_instances_exclude_stress.csv'

    with open(csv_file, 'w') as f:
        # Header
        f.write("No.,Instance Name,Instance ID,Type,Storage (GB),Monthly Cost (USD),AZ\n")

        # Categorize
        categories = categorize_instances(stopped_instances)

        row_num = 1
        for category_name, instances in categories.items():
            if instances:
                # Category header
                f.write(f"\n### {category_name} ###\n")

                sorted_instances = sorted(instances, key=lambda x: x['name'])
                for inst in sorted_instances:
                    storage_cost = inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH
                    f.write(f"{row_num},{inst['name']},{inst['id']},{inst['type']},"
                           f"{inst['storage_gb']},{storage_cost:.2f},{inst['az']}\n")
                    row_num += 1

    return csv_file

def export_markdown(stopped_instances, stress_instances):
    """Export to Markdown format"""
    md_file = 'STOPPED_INSTANCES_LIST.md'

    with open(md_file, 'w') as f:
        f.write("# Stopped EC2 實例清單 (排除 Stress 測試機器)\n\n")
        f.write(f"**生成時間**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"**AWS Region**: ap-east-1 (Hong Kong)\n\n")

        # Summary
        total_storage = sum(inst['storage_gb'] for inst in stopped_instances)
        total_storage_cost = total_storage * EBS_PRICING_PER_GB_MONTH

        f.write("## 📊 總覽\n\n")
        f.write(f"- **實例總數**: {len(stopped_instances)} 個\n")
        f.write(f"- **總儲存容量**: {total_storage} GB\n")
        f.write(f"- **月度 EBS 成本**: ${total_storage_cost:.2f} USD\n\n")

        # Categorize
        categories = categorize_instances(stopped_instances)

        f.write("## 🎮 按服務類型統計\n\n")
        f.write("| 服務類型 | 實例數 | 儲存 (GB) | 月度成本 (USD) |\n")
        f.write("|---------|--------|-----------|---------------|\n")

        for category_name, instances in categories.items():
            if instances:
                cat_storage = sum(inst['storage_gb'] for inst in instances)
                cat_cost = cat_storage * EBS_PRICING_PER_GB_MONTH
                f.write(f"| {category_name} | {len(instances)} | {cat_storage} | ${cat_cost:.2f} |\n")

        f.write("\n")

        # Detailed list by category
        for category_name, instances in categories.items():
            if instances:
                f.write(f"## {category_name} ({len(instances)} 個)\n\n")
                f.write("| No. | 實例名稱 | Instance ID | 類型 | 儲存(GB) | 月度成本 |\n")
                f.write("|-----|---------|-------------|------|---------|----------|\n")

                sorted_instances = sorted(instances, key=lambda x: x['name'])
                for idx, inst in enumerate(sorted_instances, 1):
                    storage_cost = inst['storage_gb'] * EBS_PRICING_PER_GB_MONTH
                    f.write(f"| {idx} | {inst['name']} | `{inst['id']}` | {inst['type']} | "
                           f"{inst['storage_gb']} | ${storage_cost:.2f} |\n")

                f.write("\n")

        # Excluded instances
        f.write("## ❌ 已排除的 Stress 測試機器\n\n")
        f.write("| 實例名稱 | Instance ID | 類型 | 儲存(GB) |\n")
        f.write("|---------|-------------|------|----------|\n")

        for inst in sorted(stress_instances, key=lambda x: x['name']):
            f.write(f"| {inst['name']} | `{inst['id']}` | {inst['type']} | {inst['storage_gb']} |\n")

        f.write("\n---\n")
        f.write("*此清單排除了所有 stress 測試相關的機器*\n")

    return md_file

def main():
    print("正在收集 Stopped EC2 實例數據...")
    stopped_instances, stress_instances = get_stopped_instances_exclude_stress()

    print(f"找到 {len(stopped_instances)} 個 stopped 實例 (排除 {len(stress_instances)} 個 stress 機器)")
    print()

    print_report(stopped_instances, stress_instances)

    # Export to CSV
    csv_file = export_csv(stopped_instances)
    print(f"\n✅ CSV 清單已保存至: {csv_file}")

    # Export to Markdown
    md_file = export_markdown(stopped_instances, stress_instances)
    print(f"✅ Markdown 清單已保存至: {md_file}")

    # Export to JSON
    json_file = 'stopped_instances_exclude_stress.json'
    output_data = {
        'generated_at': datetime.now().isoformat(),
        'region': 'ap-east-1',
        'total_count': len(stopped_instances),
        'excluded_stress_count': len(stress_instances),
        'instances': stopped_instances,
        'excluded_stress_instances': stress_instances
    }

    with open(json_file, 'w') as f:
        json.dump(output_data, f, indent=2, default=str)

    print(f"✅ JSON 數據已保存至: {json_file}")

if __name__ == '__main__':
    main()

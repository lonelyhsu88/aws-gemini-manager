#!/usr/bin/env python3
"""
檢查 Zabbix Server (gemini-monitor-01) 的磁碟狀況
使用唯讀 profile: gemini-pro_ck
"""

import boto3
from datetime import datetime, timedelta
import json

# AWS Configuration
PROFILE_NAME = 'gemini-pro_ck'
INSTANCE_ID = 'i-040c741a76a42169b'
INSTANCE_NAME = 'gemini-monitor-01'

def get_aws_clients():
    """初始化 AWS clients"""
    session = boto3.Session(profile_name=PROFILE_NAME)
    return {
        'ec2': session.client('ec2'),
        'cloudwatch': session.client('cloudwatch')
    }

def get_volume_info(ec2_client):
    """獲取 EBS volumes 資訊"""
    response = ec2_client.describe_volumes(
        Filters=[
            {'Name': 'attachment.instance-id', 'Values': [INSTANCE_ID]}
        ]
    )

    volumes = []
    for vol in response['Volumes']:
        volume_info = {
            'VolumeId': vol['VolumeId'],
            'Size': vol['Size'],
            'Type': vol['VolumeType'],
            'IOPS': vol.get('Iops', 'N/A'),
            'Throughput': vol.get('Throughput', 'N/A'),
            'Device': vol['Attachments'][0]['Device'],
            'State': vol['Attachments'][0]['State'],
            'CreateTime': vol['CreateTime'].strftime('%Y-%m-%d %H:%M:%S')
        }
        volumes.append(volume_info)

    return volumes

def get_cloudwatch_metrics(cw_client, volume_id, metric_name, hours=24):
    """獲取 CloudWatch 指標數據"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=hours)

    try:
        response = cw_client.get_metric_statistics(
            Namespace='AWS/EBS',
            MetricName=metric_name,
            Dimensions=[
                {'Name': 'VolumeId', 'Value': volume_id}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,  # 1 hour
            Statistics=['Average', 'Maximum', 'Sum']
        )

        if response['Datapoints']:
            datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
            return datapoints
        return []
    except Exception as e:
        print(f"⚠️  獲取 {metric_name} 失敗: {str(e)}")
        return []

def format_bytes(bytes_value):
    """格式化位元組大小"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024.0:
            return f"{bytes_value:.2f} {unit}"
        bytes_value /= 1024.0
    return f"{bytes_value:.2f} PB"

def analyze_disk_metrics(cw_client, volume):
    """分析磁碟指標"""
    volume_id = volume['VolumeId']
    device = volume['Device']

    print(f"\n{'='*80}")
    print(f"📊 磁碟: {device} ({volume_id})")
    print(f"{'='*80}")
    print(f"💾 容量: {volume['Size']} GB")
    print(f"📝 類型: {volume['Type']}")
    print(f"⚡ IOPS: {volume['IOPS']}")
    print(f"🚀 Throughput: {volume['Throughput']} MB/s" if volume['Throughput'] != 'N/A' else f"🚀 Throughput: N/A")
    print(f"🕒 建立時間: {volume['CreateTime']}")
    print(f"📌 狀態: {volume['State']}")

    # 獲取各項指標
    metrics = {
        'VolumeReadBytes': '讀取流量',
        'VolumeWriteBytes': '寫入流量',
        'VolumeReadOps': '讀取操作',
        'VolumeWriteOps': '寫入操作',
        'VolumeThroughputPercentage': '吞吐量使用率',
        'VolumeConsumedReadWriteOps': '消耗的 IOPS'
    }

    print(f"\n📈 過去 24 小時指標摘要:")
    print(f"{'-'*80}")

    for metric_name, metric_label in metrics.items():
        datapoints = get_cloudwatch_metrics(cw_client, volume_id, metric_name, hours=24)

        if not datapoints:
            print(f"  {metric_label:20s}: 無數據")
            continue

        # 計算統計值
        if 'Bytes' in metric_name:
            # 對於 Bytes 指標，使用 Sum
            total = sum(dp.get('Sum', 0) for dp in datapoints)
            avg = total / len(datapoints)
            max_val = max(dp.get('Sum', 0) for dp in datapoints)
            print(f"  {metric_label:20s}: 總計 {format_bytes(total)}, 平均 {format_bytes(avg)}/小時, 峰值 {format_bytes(max_val)}/小時")
        elif 'Ops' in metric_name:
            # 對於 Ops 指標，使用 Sum
            total = sum(dp.get('Sum', 0) for dp in datapoints)
            avg = total / len(datapoints)
            max_val = max(dp.get('Sum', 0) for dp in datapoints)
            print(f"  {metric_label:20s}: 總計 {total:,.0f}, 平均 {avg:,.0f}/小時, 峰值 {max_val:,.0f}/小時")
        else:
            # 對於百分比指標，使用 Average
            avg = sum(dp.get('Average', 0) for dp in datapoints) / len(datapoints)
            max_val = max(dp.get('Maximum', 0) for dp in datapoints)
            print(f"  {metric_label:20s}: 平均 {avg:.2f}%, 峰值 {max_val:.2f}%")

def get_instance_metrics(cw_client, hours=24):
    """獲取實例級別的 EBS 指標"""
    print(f"\n{'='*80}")
    print(f"📊 實例級別 EBS 指標")
    print(f"{'='*80}")

    instance_metrics = {
        'EBSReadBytes': 'EBS 讀取流量',
        'EBSWriteBytes': 'EBS 寫入流量',
        'EBSReadOps': 'EBS 讀取操作',
        'EBSWriteOps': 'EBS 寫入操作',
        'EBSIOBalance%': 'EBS I/O 餘額'
    }

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=hours)

    for metric_name, metric_label in instance_metrics.items():
        try:
            response = cw_client.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName=metric_name,
                Dimensions=[
                    {'Name': 'InstanceId', 'Value': INSTANCE_ID}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Average', 'Maximum', 'Sum']
            )

            if not response['Datapoints']:
                print(f"  {metric_label:20s}: 無數據")
                continue

            datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])

            if 'Bytes' in metric_name:
                total = sum(dp.get('Sum', 0) for dp in datapoints)
                avg = total / len(datapoints)
                max_val = max(dp.get('Sum', 0) for dp in datapoints)
                print(f"  {metric_label:20s}: 總計 {format_bytes(total)}, 平均 {format_bytes(avg)}/小時, 峰值 {format_bytes(max_val)}/小時")
            elif 'Ops' in metric_name:
                total = sum(dp.get('Sum', 0) for dp in datapoints)
                avg = total / len(datapoints)
                max_val = max(dp.get('Sum', 0) for dp in datapoints)
                print(f"  {metric_label:20s}: 總計 {total:,.0f}, 平均 {avg:,.0f}/小時, 峰值 {max_val:,.0f}/小時")
            else:
                avg = sum(dp.get('Average', 0) for dp in datapoints) / len(datapoints)
                max_val = max(dp.get('Maximum', 0) for dp in datapoints)
                print(f"  {metric_label:20s}: 平均 {avg:.2f}%, 峰值 {max_val:.2f}%")

        except Exception as e:
            print(f"  {metric_label:20s}: 獲取失敗 ({str(e)})")

def main():
    """主程式"""
    print(f"\n{'='*80}")
    print(f"🔍 Zabbix Server 磁碟狀況檢查")
    print(f"{'='*80}")
    print(f"實例: {INSTANCE_NAME} ({INSTANCE_ID})")
    print(f"Profile: {PROFILE_NAME}")
    print(f"查詢時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # 初始化 AWS clients
    clients = get_aws_clients()
    ec2_client = clients['ec2']
    cw_client = clients['cloudwatch']

    # 獲取 Volume 資訊
    print(f"\n{'='*80}")
    print(f"💾 EBS Volumes 資訊")
    print(f"{'='*80}")

    volumes = get_volume_info(ec2_client)

    # 分析每個 volume 的指標
    for volume in volumes:
        analyze_disk_metrics(cw_client, volume)

    # 獲取實例級別指標
    get_instance_metrics(cw_client)

    # 警告提示
    print(f"\n{'='*80}")
    print(f"⚠️  重要提示")
    print(f"{'='*80}")
    print(f"1. ❌ 此實例未安裝 CloudWatch Agent，無法查看磁碟使用率（disk usage %）")
    print(f"2. 📊 目前只能查看 EBS volume 層級的 I/O 指標（IOPS、throughput、讀寫流量）")
    print(f"3. 💡 建議安裝 CloudWatch Agent 以監控:")
    print(f"   - disk_used_percent（磁碟使用率）")
    print(f"   - disk_inodes_free（inode 使用情況）")
    print(f"   - mem_used_percent（記憶體使用率）")
    print(f"4. 🔐 或透過 SSH 登入實例執行 'df -h' 查看實際磁碟使用情況")
    print(f"\n{'='*80}\n")

if __name__ == '__main__':
    main()

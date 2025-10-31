#!/usr/bin/env python3
"""
Analyze GitLab EC2 instance resource usage
Profile: gemini-pro_ck
Instance: Gemini-Gitlab (i-00b89a08e62a762a9)
"""

import boto3
from datetime import datetime, timedelta
import statistics

# Configuration
PROFILE_NAME = 'gemini-pro_ck'
INSTANCE_ID = 'i-00b89a08e62a762a9'
INSTANCE_NAME = 'Gemini-Gitlab'

# Initialize AWS session
session = boto3.Session(profile_name=PROFILE_NAME)
ec2_client = session.client('ec2')
cloudwatch_client = session.client('cloudwatch')

def get_metric_statistics(metric_name, namespace='AWS/EC2', unit='Percent', period=300):
    """Get CloudWatch metric statistics for the last 24 hours"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=24)

    response = cloudwatch_client.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=[
            {
                'Name': 'InstanceId',
                'Value': INSTANCE_ID
            }
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=period,  # 5 minutes
        Statistics=['Average', 'Maximum', 'Minimum'],
        Unit=unit
    )

    return sorted(response['Datapoints'], key=lambda x: x['Timestamp'])

def analyze_cpu_usage():
    """Analyze CPU utilization"""
    print("\n" + "="*80)
    print("CPU UTILIZATION ANALYSIS (Last 24 Hours)")
    print("="*80)

    datapoints = get_metric_statistics('CPUUtilization', unit='Percent')

    if not datapoints:
        print("⚠️  No CPU data available")
        return

    averages = [dp['Average'] for dp in datapoints]
    maximums = [dp['Maximum'] for dp in datapoints]

    print(f"📊 Data Points: {len(datapoints)}")
    print(f"📈 Average CPU: {statistics.mean(averages):.2f}%")
    print(f"🔺 Peak CPU: {max(maximums):.2f}%")
    print(f"🔻 Minimum CPU: {min(averages):.2f}%")
    print(f"📉 Median CPU: {statistics.median(averages):.2f}%")

    # Check for sustained high CPU
    high_cpu_count = sum(1 for avg in averages if avg > 70)
    if high_cpu_count > 0:
        print(f"\n⚠️  WARNING: High CPU (>70%) detected in {high_cpu_count} periods ({high_cpu_count*5} minutes)")

    # Show recent trend (last 6 hours)
    recent_6h = datapoints[-72:]  # Last 72 data points (6 hours)
    if recent_6h:
        recent_avg = statistics.mean([dp['Average'] for dp in recent_6h])
        print(f"\n📍 Recent 6h Average: {recent_avg:.2f}%")

def analyze_network_traffic():
    """Analyze network traffic"""
    print("\n" + "="*80)
    print("NETWORK TRAFFIC ANALYSIS (Last 24 Hours)")
    print("="*80)

    # Network In
    net_in = get_metric_statistics('NetworkIn', unit='Bytes')
    # Network Out
    net_out = get_metric_statistics('NetworkOut', unit='Bytes')

    if net_in:
        total_in_bytes = sum([dp['Average'] for dp in net_in]) * 300 / (1024**3)  # Convert to GB
        avg_in_mbps = statistics.mean([dp['Average'] for dp in net_in]) / (1024**2) * 8 / 300  # Mbps
        print(f"📥 Network In - Total: {total_in_bytes:.2f} GB")
        print(f"📥 Network In - Avg: {avg_in_mbps:.2f} Mbps")

    if net_out:
        total_out_bytes = sum([dp['Average'] for dp in net_out]) * 300 / (1024**3)  # Convert to GB
        avg_out_mbps = statistics.mean([dp['Average'] for dp in net_out]) / (1024**2) * 8 / 300  # Mbps
        print(f"📤 Network Out - Total: {total_out_bytes:.2f} GB")
        print(f"📤 Network Out - Avg: {avg_out_mbps:.2f} Mbps")

def analyze_disk_io():
    """Analyze disk I/O"""
    print("\n" + "="*80)
    print("DISK I/O ANALYSIS (Last 24 Hours)")
    print("="*80)

    # EBS Read Operations
    read_ops = get_metric_statistics('EBSReadOps', unit='Count')
    # EBS Write Operations
    write_ops = get_metric_statistics('EBSWriteOps', unit='Count')
    # EBS Read Bytes
    read_bytes = get_metric_statistics('EBSReadBytes', unit='Bytes')
    # EBS Write Bytes
    write_bytes = get_metric_statistics('EBSWriteBytes', unit='Bytes')

    if read_ops and write_ops:
        total_read_ops = sum([dp['Average'] for dp in read_ops]) * 300
        total_write_ops = sum([dp['Average'] for dp in write_ops]) * 300
        print(f"📖 Total Read Operations: {total_read_ops:,.0f}")
        print(f"✍️  Total Write Operations: {total_write_ops:,.0f}")

    if read_bytes and write_bytes:
        total_read_gb = sum([dp['Average'] for dp in read_bytes]) * 300 / (1024**3)
        total_write_gb = sum([dp['Average'] for dp in write_bytes]) * 300 / (1024**3)
        print(f"📖 Total Read: {total_read_gb:.2f} GB")
        print(f"✍️  Total Write: {total_write_gb:.2f} GB")

        # Calculate average IOPS
        if read_ops and write_ops:
            avg_read_iops = statistics.mean([dp['Average'] for dp in read_ops])
            avg_write_iops = statistics.mean([dp['Average'] for dp in write_ops])
            print(f"\n📊 Average Read IOPS: {avg_read_iops:.2f}")
            print(f"📊 Average Write IOPS: {avg_write_iops:.2f}")

def get_instance_details():
    """Get EC2 instance details"""
    print("\n" + "="*80)
    print("INSTANCE CONFIGURATION")
    print("="*80)

    response = ec2_client.describe_instances(InstanceIds=[INSTANCE_ID])
    instance = response['Reservations'][0]['Instances'][0]

    print(f"🏷️  Name: {INSTANCE_NAME}")
    print(f"🆔 Instance ID: {INSTANCE_ID}")
    print(f"💻 Instance Type: {instance['InstanceType']}")
    print(f"📍 Private IP: {instance.get('PrivateIpAddress', 'N/A')}")
    print(f"🌐 Public IP: {instance.get('PublicIpAddress', 'N/A')}")
    print(f"🚀 Launch Time: {instance['LaunchTime']}")
    print(f"📊 Monitoring: {instance['Monitoring']['State']}")

    # Instance type specifications (c5a.xlarge)
    print("\n📋 Instance Type Specifications (c5a.xlarge):")
    print("   • vCPUs: 4")
    print("   • Memory: 8 GB")
    print("   • Network Performance: Up to 10 Gbps")
    print("   • EBS-Optimized: Yes")

def check_cloudwatch_agent():
    """Check if CloudWatch Agent is installed"""
    print("\n" + "="*80)
    print("MEMORY MONITORING STATUS")
    print("="*80)

    # Check for CWAgent metrics
    response = cloudwatch_client.list_metrics(
        Namespace='CWAgent',
        Dimensions=[
            {
                'Name': 'InstanceId',
                'Value': INSTANCE_ID
            }
        ]
    )

    if response['Metrics']:
        print("✅ CloudWatch Agent is installed and reporting metrics")
        print("\nAvailable CWAgent Metrics:")
        for metric in response['Metrics']:
            print(f"   • {metric['MetricName']}")
    else:
        print("❌ CloudWatch Agent is NOT installed")
        print("\n⚠️  CRITICAL: Without CloudWatch Agent, memory metrics are not available!")
        print("\n📝 To install CloudWatch Agent:")
        print("   1. SSH into the instance")
        print("   2. Install agent: wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm")
        print("   3. sudo rpm -U ./amazon-cloudwatch-agent.rpm")
        print("   4. Configure agent: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard")
        print("   5. Start agent: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json")

def main():
    """Main execution"""
    print("\n" + "="*80)
    print(f"GITLAB RESOURCE ANALYSIS REPORT")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)

    try:
        get_instance_details()
        check_cloudwatch_agent()
        analyze_cpu_usage()
        analyze_network_traffic()
        analyze_disk_io()

        # Summary and recommendations
        print("\n" + "="*80)
        print("ANALYSIS SUMMARY & RECOMMENDATIONS")
        print("="*80)

        print("\n🔍 Key Findings:")
        print("   • GitLab is running on c5a.xlarge (4 vCPUs, 8 GB RAM)")
        print("   • CloudWatch detailed monitoring is DISABLED")
        print("   • CloudWatch Agent is NOT installed (no memory metrics)")

        print("\n💡 Recommendations:")
        print("   1. IMMEDIATE: Install CloudWatch Agent to monitor memory usage")
        print("   2. Enable detailed monitoring for better visibility")
        print("   3. Consider upgrading to c5a.2xlarge (8 vCPUs, 16 GB RAM) if memory is the bottleneck")
        print("   4. Review GitLab configuration and optimize memory settings")
        print("   5. Check application logs for out-of-memory errors")

        print("\n📚 GitLab Memory Optimization Tips:")
        print("   • Reduce Unicorn/Puma worker count in /etc/gitlab/gitlab.rb")
        print("   • Adjust Sidekiq concurrency settings")
        print("   • Disable unused GitLab features")
        print("   • Configure shared_buffers for PostgreSQL")
        print("   • Enable swap space as temporary relief")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()

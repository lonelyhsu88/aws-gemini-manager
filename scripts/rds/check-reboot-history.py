#!/usr/bin/env python3
"""
查詢 RDS 實例的重啟歷史
"""

import boto3
import sys
from datetime import datetime, timedelta
from collections import defaultdict

AWS_PROFILE = 'gemini-pro_ck'

def get_reboot_history(session, instance_pattern=None, days=90):
    """獲取重啟歷史"""
    cloudtrail = session.client('cloudtrail')

    # 查詢 RebootDBInstance 事件
    try:
        response = cloudtrail.lookup_events(
            LookupAttributes=[
                {
                    'AttributeKey': 'EventName',
                    'AttributeValue': 'RebootDBInstance'
                }
            ],
            MaxResults=100
        )
    except Exception as e:
        print(f"❌ 查詢 CloudTrail 失敗: {e}")
        return []

    events = response.get('Events', [])

    # 處理事件
    reboots = []
    for event in events:
        import json
        event_data = json.loads(event['CloudTrailEvent'])

        instance_id = event_data.get('requestParameters', {}).get('dBInstanceIdentifier', '')

        # 篩選符合模式的實例
        if instance_pattern:
            if not instance_id.startswith(instance_pattern):
                continue

        timestamp = event['EventTime']
        user = event.get('Username', 'Unknown')

        # 檢查是否有強制容錯移轉
        force_failover = event_data.get('requestParameters', {}).get('forceFailover', False)

        reboots.append({
            'timestamp': timestamp,
            'instance': instance_id,
            'user': user,
            'force_failover': force_failover
        })

    return reboots

def main():
    if len(sys.argv) > 1:
        pattern = sys.argv[1]
    else:
        pattern = 'bingo-prd'

    print("=" * 100)
    print(f"RDS 實例重啟歷史查詢: {pattern}*")
    print("=" * 100)
    print()

    session = boto3.Session(profile_name=AWS_PROFILE)

    # 獲取重啟記錄
    print("🔍 正在查詢 CloudTrail 事件（最近 90 天）...")
    reboots = get_reboot_history(session, instance_pattern=pattern)

    if not reboots:
        print(f"❌ 未找到 {pattern}* 實例的重啟記錄（最近 90 天內）")
        print()
        print("可能原因：")
        print("  1. 實例在過去 90 天內沒有重啟")
        print("  2. CloudTrail 事件保留期限已過")
        print("  3. 實例名稱不符合篩選條件")
        return

    print(f"✅ 找到 {len(reboots)} 筆重啟記錄")
    print()

    # 按實例分組
    by_instance = defaultdict(list)
    for reboot in reboots:
        by_instance[reboot['instance']].append(reboot)

    print("=" * 100)
    print("📊 按實例分組")
    print("=" * 100)
    print()

    # 按實例排序
    for instance in sorted(by_instance.keys()):
        instance_reboots = sorted(by_instance[instance], key=lambda x: x['timestamp'], reverse=True)

        print(f"📍 {instance}")
        print(f"   共 {len(instance_reboots)} 次重啟")
        print()

        for i, reboot in enumerate(instance_reboots, 1):
            ts = reboot['timestamp']
            user = reboot['user']
            force_failover = reboot['force_failover']

            # 格式化時間
            local_ts = ts.astimezone()

            failover_str = " [強制容錯移轉]" if force_failover else ""
            print(f"   {i}. {local_ts.strftime('%Y-%m-%d %H:%M:%S %Z')}{failover_str}")
            print(f"      操作者: {user}")

        print()

    # 時間線視圖
    print("=" * 100)
    print("📅 時間線視圖（按時間排序）")
    print("=" * 100)
    print()

    all_reboots = []
    for instance, instance_reboots in by_instance.items():
        for reboot in instance_reboots:
            all_reboots.append({
                'timestamp': reboot['timestamp'],
                'instance': instance,
                'user': reboot['user'],
                'force_failover': reboot['force_failover']
            })

    all_reboots.sort(key=lambda x: x['timestamp'], reverse=True)

    print(f"{'時間 (本地時間)':<25} | {'實例':<35} | {'操作者':<20} | 備註")
    print("-" * 105)

    for reboot in all_reboots:
        local_time = reboot['timestamp'].astimezone().strftime('%Y-%m-%d %H:%M:%S')
        instance = reboot['instance']
        user = reboot['user']
        note = "強制容錯移轉" if reboot['force_failover'] else ""

        print(f"{local_time:<25} | {instance:<35} | {user:<20} | {note}")

    print()

    # 統計分析
    print("=" * 100)
    print("📊 統計分析")
    print("=" * 100)
    print()

    # 按日期分組
    by_date = defaultdict(int)
    for reboot in all_reboots:
        date = reboot['timestamp'].astimezone().strftime('%Y-%m-%d')
        by_date[date] += 1

    print("每日重啟次數：")
    for date in sorted(by_date.keys(), reverse=True):
        count = by_date[date]
        print(f"  {date}: {count} 次")

    print()

    # 按操作者分組
    by_user = defaultdict(int)
    for reboot in all_reboots:
        by_user[reboot['user']] += 1

    print("按操作者統計：")
    for user in sorted(by_user.keys(), key=lambda x: by_user[x], reverse=True):
        count = by_user[user]
        print(f"  {user}: {count} 次")

    print()
    print("=" * 100)

if __name__ == '__main__':
    main()

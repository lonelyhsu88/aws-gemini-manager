#!/usr/bin/env python3
"""
查詢特定時間範圍內的 Top SQL
使用 AWS Performance Insights API
"""

import boto3
import json
from datetime import datetime, timedelta
import sys

# AWS 配置
AWS_PROFILE = 'gemini-pro_ck'
REGION = 'ap-east-1'
DB_INSTANCE_ID = 'bingo-prd-backstage-replica1'

# 時間範圍（香港時間 2025-10-29 09:20-09:30 = UTC 01:20-01:30）
START_TIME = datetime(2025, 10, 29, 1, 20, 0)  # UTC
END_TIME = datetime(2025, 10, 29, 1, 30, 0)    # UTC

# 初始化 boto3
session = boto3.Session(profile_name=AWS_PROFILE, region_name=REGION)
pi_client = session.client('pi')
rds_client = session.client('rds')

def get_db_resource_id(db_instance_id):
    """取得 RDS Resource ID"""
    try:
        response = rds_client.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        return response['DBInstances'][0]['DbiResourceId']
    except Exception as e:
        print(f"❌ 錯誤：{e}")
        sys.exit(1)

def get_top_sql_queries(resource_id, start_time, end_time):
    """查詢指定時間範圍的 Top SQL"""

    print("\n" + "="*100)
    print(f"🔍 查詢時間範圍：{start_time.strftime('%Y-%m-%d %H:%M:%S')} ~ {end_time.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print(f"   (香港時間：{(start_time + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S')} ~ {(end_time + timedelta(hours=8)).strftime('%Y-%m-%d %H:%M:%S')} HKT)")
    print("="*100)

    try:
        # 查詢 Top SQL by DB Load
        response = pi_client.get_resource_metrics(
            ServiceType='RDS',
            Identifier=resource_id,
            MetricQueries=[
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {
                        'Group': 'db.sql',
                        'Limit': 20  # 取前 20 個查詢
                    }
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=60  # 每分鐘一個數據點
        )

        if 'MetricList' not in response or len(response['MetricList']) == 0:
            print("\n⚠️  沒有找到查詢數據")
            print("可能原因：")
            print("1. Performance Insights 數據已過期（默認保留 7 天）")
            print("2. 該時段沒有活動查詢")
            print("3. Performance Insights 數據收集延遲")
            return

        metric_data = response['MetricList'][0]

        if 'DataPoints' not in metric_data or len(metric_data['DataPoints']) == 0:
            print("\n⚠️  該時段沒有數據點")
            return

        # 收集所有 SQL 的統計信息
        sql_stats = {}

        for datapoint in metric_data['DataPoints']:
            timestamp = datapoint['Timestamp']

            if 'Dimensions' not in datapoint:
                continue

            for dimension in datapoint['Dimensions']:
                sql_id = dimension.get('Value', 'Unknown')
                load_value = dimension.get('Limit', 0)

                if sql_id not in sql_stats:
                    sql_stats[sql_id] = {
                        'total_load': 0,
                        'max_load': 0,
                        'count': 0,
                        'timestamps': []
                    }

                sql_stats[sql_id]['total_load'] += load_value
                sql_stats[sql_id]['max_load'] = max(sql_stats[sql_id]['max_load'], load_value)
                sql_stats[sql_id]['count'] += 1
                sql_stats[sql_id]['timestamps'].append((timestamp, load_value))

        if not sql_stats:
            print("\n⚠️  沒有找到 SQL 查詢數據")
            return

        # 按總負載排序
        sorted_sqls = sorted(sql_stats.items(), key=lambda x: x[1]['total_load'], reverse=True)

        print(f"\n📊 找到 {len(sorted_sqls)} 個不同的 SQL 查詢")
        print("\n" + "="*100)
        print("🔥 Top SQL Queries (按總負載排序)")
        print("="*100)

        for idx, (sql_id, stats) in enumerate(sorted_sqls[:10], 1):
            avg_load = stats['total_load'] / stats['count'] if stats['count'] > 0 else 0

            print(f"\n{idx}. SQL ID: {sql_id}")
            print(f"   {'─'*90}")
            print(f"   總負載 (Total Load):     {stats['total_load']:.2f}")
            print(f"   平均負載 (Avg Load):      {avg_load:.2f}")
            print(f"   峰值負載 (Max Load):      {stats['max_load']:.2f}")
            print(f"   出現次數 (Occurrences):  {stats['count']}")

            # 顯示每個時間點的負載
            print(f"   時間點分布:")
            for ts, load in sorted(stats['timestamps']):
                ts_hkt = ts + timedelta(hours=8)
                print(f"     - {ts.strftime('%H:%M:%S')} UTC ({ts_hkt.strftime('%H:%M:%S')} HKT): {load:.2f}")

            # 取得 SQL 文本
            get_sql_text(resource_id, sql_id)

    except Exception as e:
        print(f"\n❌ 查詢錯誤：{e}")
        import traceback
        traceback.print_exc()

def get_sql_text(resource_id, sql_id):
    """取得 SQL 語句文本"""
    try:
        response = pi_client.get_dimension_key_details(
            ServiceType='RDS',
            Identifier=resource_id,
            Group='db.sql',
            GroupIdentifier=sql_id
        )

        if 'Dimensions' in response:
            for key, value in response['Dimensions'].items():
                if key == 'db.sql.statement':
                    print(f"\n   📝 SQL 語句:")
                    # 格式化 SQL 輸出
                    sql_lines = value.split('\n')
                    for line in sql_lines[:15]:  # 最多顯示 15 行
                        print(f"      {line}")
                    if len(sql_lines) > 15:
                        print(f"      ... (共 {len(sql_lines)} 行，已截斷)")

                elif key == 'db.sql.db_id':
                    print(f"   數據庫: {value}")
                elif key == 'db.user.name':
                    print(f"   用戶: {value}")

    except Exception as e:
        print(f"   ⚠️  無法取得 SQL 文本：{e}")

def get_wait_events(resource_id, start_time, end_time):
    """查詢等待事件"""

    print("\n" + "="*100)
    print("⏱️  Top Wait Events")
    print("="*100)

    try:
        response = pi_client.get_resource_metrics(
            ServiceType='RDS',
            Identifier=resource_id,
            MetricQueries=[
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {
                        'Group': 'db.wait_event',
                        'Limit': 10
                    }
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=60
        )

        if 'MetricList' in response and len(response['MetricList']) > 0:
            wait_data = response['MetricList'][0]

            if 'DataPoints' in wait_data:
                wait_stats = {}

                for datapoint in wait_data['DataPoints']:
                    if 'Dimensions' in datapoint:
                        for dimension in datapoint['Dimensions']:
                            wait_event = dimension.get('Value', 'Unknown')
                            load_value = dimension.get('Limit', 0)

                            if wait_event not in wait_stats:
                                wait_stats[wait_event] = 0
                            wait_stats[wait_event] += load_value

                sorted_waits = sorted(wait_stats.items(), key=lambda x: x[1], reverse=True)

                if sorted_waits:
                    print()
                    for idx, (wait_event, total_load) in enumerate(sorted_waits[:10], 1):
                        print(f"{idx:2d}. {wait_event:<50} 總負載: {total_load:>10.2f}")
                else:
                    print("  沒有等待事件數據")
            else:
                print("  沒有等待事件數據")

    except Exception as e:
        print(f"  查詢等待事件失敗：{e}")

def main():
    print("\n" + "="*100)
    print("🔍 RDS Performance Insights - Top SQL 查詢工具")
    print("="*100)

    # 取得 Resource ID
    resource_id = get_db_resource_id(DB_INSTANCE_ID)
    print(f"\n✅ RDS Instance: {DB_INSTANCE_ID}")
    print(f"✅ Resource ID: {resource_id}")

    # 查詢 Top SQL
    get_top_sql_queries(resource_id, START_TIME, END_TIME)

    # 查詢等待事件
    get_wait_events(resource_id, START_TIME, END_TIME)

    print("\n" + "="*100)
    print("✅ 查詢完成")
    print("="*100 + "\n")

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
RDS Performance Insights Query Analyzer
分析 RDS 實例的查詢活動，找出高負載查詢和來源 IP
"""

import boto3
import json
from datetime import datetime, timedelta
from collections import defaultdict
import sys

# AWS 配置
AWS_PROFILE = 'gemini-pro_ck'
REGION = 'ap-east-1'
DB_INSTANCE_ID = 'bingo-prd-backstage-replica1'

# 初始化 boto3 session
session = boto3.Session(profile_name=AWS_PROFILE, region_name=REGION)
pi_client = session.client('pi')
rds_client = session.client('rds')

def get_db_resource_id(db_instance_id):
    """取得 RDS 實例的 Resource ID（Performance Insights 需要）"""
    try:
        response = rds_client.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        resource_id = response['DBInstances'][0]['DbiResourceId']
        return resource_id
    except Exception as e:
        print(f"❌ 錯誤：無法取得 Resource ID - {e}")
        sys.exit(1)

def analyze_performance_insights(resource_id, start_time, end_time):
    """分析 Performance Insights 數據"""

    print(f"\n📊 分析時段：{start_time.strftime('%Y-%m-%d %H:%M')} ~ {end_time.strftime('%Y-%m-%d %H:%M')} UTC")
    print("=" * 80)

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
                        'Limit': 10
                    }
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=3600  # 1小時
        )

        print("\n🔍 Top 10 SQL Queries by Database Load:\n")

        if 'MetricList' in response and len(response['MetricList']) > 0:
            metric_data = response['MetricList'][0]

            if 'DataPoints' in metric_data:
                # 收集所有時間點的數據
                sql_stats = defaultdict(lambda: {'total_load': 0, 'max_load': 0, 'count': 0})

                for datapoint in metric_data['DataPoints']:
                    timestamp = datapoint['Timestamp']
                    if 'Dimensions' in datapoint:
                        for dimension in datapoint['Dimensions']:
                            sql_id = dimension.get('Value', 'Unknown')
                            load_value = dimension.get('Limit', 0)

                            sql_stats[sql_id]['total_load'] += load_value
                            sql_stats[sql_id]['max_load'] = max(sql_stats[sql_id]['max_load'], load_value)
                            sql_stats[sql_id]['count'] += 1

                # 排序並顯示
                sorted_sqls = sorted(sql_stats.items(), key=lambda x: x[1]['total_load'], reverse=True)

                for idx, (sql_id, stats) in enumerate(sorted_sqls[:10], 1):
                    avg_load = stats['total_load'] / stats['count'] if stats['count'] > 0 else 0
                    print(f"{idx}. SQL ID: {sql_id}")
                    print(f"   總負載: {stats['total_load']:.2f}")
                    print(f"   平均負載: {avg_load:.2f}")
                    print(f"   峰值負載: {stats['max_load']:.2f}")
                    print()

                    # 取得 SQL 文本
                    get_sql_text(resource_id, sql_id)

        # 查詢 Top Waits
        print("\n⏱️  Top Wait Events:\n")
        response_waits = pi_client.get_resource_metrics(
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
            PeriodInSeconds=3600
        )

        if 'MetricList' in response_waits and len(response_waits['MetricList']) > 0:
            wait_data = response_waits['MetricList'][0]
            if 'DataPoints' in wait_data:
                wait_stats = defaultdict(float)

                for datapoint in wait_data['DataPoints']:
                    if 'Dimensions' in datapoint:
                        for dimension in datapoint['Dimensions']:
                            wait_event = dimension.get('Value', 'Unknown')
                            load_value = dimension.get('Limit', 0)
                            wait_stats[wait_event] += load_value

                sorted_waits = sorted(wait_stats.items(), key=lambda x: x[1], reverse=True)

                for idx, (wait_event, total_load) in enumerate(sorted_waits[:10], 1):
                    print(f"{idx}. {wait_event}: {total_load:.2f}")

    except Exception as e:
        print(f"❌ 分析錯誤：{e}")
        import traceback
        traceback.print_exc()

def get_sql_text(resource_id, sql_id):
    """取得 SQL 語句的完整文本"""
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
                    # 截斷過長的 SQL
                    sql_text = value if len(value) <= 200 else value[:200] + '...'
                    print(f"   SQL: {sql_text}")
                    print()
    except Exception as e:
        print(f"   無法取得 SQL 文本：{e}")
        print()

def query_current_connections():
    """
    注意：這個函數需要直接連接到數據庫
    需要 psycopg2 套件和數據庫憑證
    """
    print("\n💡 提示：要查詢當前連接和來源 IP，需要直接連接到數據庫")
    print("請執行以下 SQL 查詢：")
    print("""
    -- 查看當前所有連接和來源 IP
    SELECT
        pid,
        usename,
        application_name,
        client_addr,
        client_port,
        backend_start,
        state,
        state_change,
        query_start,
        LEFT(query, 100) as query_preview
    FROM pg_stat_activity
    WHERE state != 'idle'
    ORDER BY query_start DESC;

    -- 統計每個 IP 的連接數
    SELECT
        client_addr,
        count(*) as connection_count,
        count(*) FILTER (WHERE state = 'active') as active_connections
    FROM pg_stat_activity
    WHERE client_addr IS NOT NULL
    GROUP BY client_addr
    ORDER BY connection_count DESC;
    """)

def main():
    print("\n" + "="*80)
    print("🔍 RDS Performance Insights Query Analyzer")
    print("="*80)

    # 取得 Resource ID
    resource_id = get_db_resource_id(DB_INSTANCE_ID)
    print(f"\n✅ RDS Instance: {DB_INSTANCE_ID}")
    print(f"✅ Resource ID: {resource_id}")

    # 分析昨天的高峰時段 (2025-10-29 00:00 - 02:00 UTC)
    # 根據之前的數據，問題發生在 00:51 UTC
    start_time = datetime(2025, 10, 29, 0, 0, 0)
    end_time = datetime(2025, 10, 29, 2, 0, 0)

    analyze_performance_insights(resource_id, start_time, end_time)

    # 顯示如何查詢當前連接
    query_current_connections()

    print("\n" + "="*80)
    print("✅ 分析完成")
    print("="*80)

if __name__ == '__main__':
    main()

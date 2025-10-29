#!/usr/bin/env python3
"""
RDS Database Connections Analysis for bingo-prd
Analyzes DatabaseConnections metric over the past 7 days and provides alarm threshold recommendations.
"""

import boto3
from datetime import datetime, timedelta
import statistics
from collections import defaultdict
import json

# Configuration
AWS_PROFILE = 'gemini-pro_ck'
AWS_REGION = 'ap-east-1'
DB_INSTANCE = 'bingo-prd'
MAX_CONNECTIONS = 901
CURRENT_ALARM = 675
ALARM_PERCENTAGE = 75

def get_cloudwatch_metrics(session, db_instance, days=7):
    """Query CloudWatch for DatabaseConnections metric."""
    cloudwatch = session.client('cloudwatch', region_name=AWS_REGION)

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=days)

    print(f"查詢時間範圍: {start_time.strftime('%Y-%m-%d %H:%M:%S')} UTC 到 {end_time.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print(f"查詢資料庫實例: {db_instance}\n")

    # Get data points with 5-minute period for detailed analysis
    # CloudWatch limit: max 1440 datapoints
    # 7 days * 24 hours * 60 minutes / 5 min period = 2016 datapoints (too many)
    # Using 10-minute period: 7 days * 24 hours * 6 = 1008 datapoints (within limit)
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[
            {
                'Name': 'DBInstanceIdentifier',
                'Value': db_instance
            }
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=600,  # 10 minutes (7 days = 1008 datapoints, within 1440 limit)
        Statistics=['Average', 'Maximum', 'Minimum']
    )

    datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
    return datapoints

def analyze_overall_stats(datapoints):
    """Calculate overall statistics."""
    if not datapoints:
        return None

    averages = [dp['Average'] for dp in datapoints]
    maximums = [dp['Maximum'] for dp in datapoints]
    minimums = [dp['Minimum'] for dp in datapoints]

    return {
        'total_datapoints': len(datapoints),
        'avg_connections': statistics.mean(averages),
        'median_connections': statistics.median(averages),
        'min_connections': min(minimums),
        'max_connections': max(maximums),
        'stddev': statistics.stdev(averages) if len(averages) > 1 else 0,
        'p50': statistics.median(averages),
        'p75': statistics.quantiles(averages, n=4)[2] if len(averages) >= 4 else None,
        'p90': statistics.quantiles(averages, n=10)[8] if len(averages) >= 10 else None,
        'p95': statistics.quantiles(averages, n=20)[18] if len(averages) >= 20 else None,
        'p99': statistics.quantiles(averages, n=100)[98] if len(averages) >= 100 else None,
    }

def analyze_daily_patterns(datapoints):
    """Analyze daily patterns."""
    daily_data = defaultdict(lambda: {'averages': [], 'maximums': [], 'timestamps': []})

    for dp in datapoints:
        # Convert to local time (UTC+8 for Hong Kong)
        local_time = dp['Timestamp'] + timedelta(hours=8)
        date_key = local_time.strftime('%Y-%m-%d')

        daily_data[date_key]['averages'].append(dp['Average'])
        daily_data[date_key]['maximums'].append(dp['Maximum'])
        daily_data[date_key]['timestamps'].append(local_time)

    daily_stats = {}
    for date, data in sorted(daily_data.items()):
        if data['averages']:
            daily_stats[date] = {
                'avg': statistics.mean(data['averages']),
                'max': max(data['maximums']),
                'min': min(data['averages']),
                'peak_time': data['timestamps'][data['maximums'].index(max(data['maximums']))].strftime('%H:%M:%S'),
                'datapoints': len(data['averages']),
                'weekday': data['timestamps'][0].strftime('%A')
            }

    return daily_stats

def analyze_hourly_patterns(datapoints):
    """Analyze hourly patterns to identify peak hours."""
    hourly_data = defaultdict(lambda: {'averages': [], 'maximums': []})

    for dp in datapoints:
        # Convert to local time (UTC+8)
        local_time = dp['Timestamp'] + timedelta(hours=8)
        hour_key = local_time.hour

        hourly_data[hour_key]['averages'].append(dp['Average'])
        hourly_data[hour_key]['maximums'].append(dp['Maximum'])

    hourly_stats = {}
    for hour, data in sorted(hourly_data.items()):
        if data['averages']:
            hourly_stats[hour] = {
                'avg': statistics.mean(data['averages']),
                'max': max(data['maximums']),
                'min': min(data['averages']),
                'datapoints': len(data['averages'])
            }

    return hourly_stats

def analyze_weekly_patterns(datapoints):
    """Analyze weekday vs weekend patterns."""
    weekday_connections = []
    weekend_connections = []

    for dp in datapoints:
        local_time = dp['Timestamp'] + timedelta(hours=8)
        if local_time.weekday() < 5:  # Monday-Friday (0-4)
            weekday_connections.append(dp['Average'])
        else:  # Saturday-Sunday (5-6)
            weekend_connections.append(dp['Average'])

    return {
        'weekday_avg': statistics.mean(weekday_connections) if weekday_connections else 0,
        'weekend_avg': statistics.mean(weekend_connections) if weekend_connections else 0,
        'weekday_max': max(weekday_connections) if weekday_connections else 0,
        'weekend_max': max(weekend_connections) if weekend_connections else 0,
    }

def identify_anomalies(datapoints, threshold_multiplier=2.0):
    """Identify anomalous spikes."""
    if not datapoints:
        return []

    averages = [dp['Average'] for dp in datapoints]
    mean = statistics.mean(averages)
    stddev = statistics.stdev(averages) if len(averages) > 1 else 0
    threshold = mean + (threshold_multiplier * stddev)

    anomalies = []
    for dp in datapoints:
        if dp['Average'] > threshold:
            local_time = dp['Timestamp'] + timedelta(hours=8)
            anomalies.append({
                'timestamp': local_time.strftime('%Y-%m-%d %H:%M:%S'),
                'connections': dp['Average'],
                'deviation': dp['Average'] - mean
            })

    return anomalies

def calculate_alarm_percentile(datapoints, alarm_value):
    """Calculate what percentile the current alarm threshold represents."""
    if not datapoints:
        return None

    averages = sorted([dp['Average'] for dp in datapoints])
    count_below = sum(1 for x in averages if x <= alarm_value)
    percentile = (count_below / len(averages)) * 100

    return percentile

def recommend_thresholds(overall_stats, max_connections):
    """Provide threshold recommendations based on analysis."""
    recommendations = {}

    # P0 (Critical) - Should be very rare, near max capacity
    p0_threshold = min(overall_stats['p99'] * 1.1 if overall_stats['p99'] else max_connections * 0.90,
                       max_connections * 0.90)

    # P1 (High) - Based on P95
    p1_threshold = overall_stats['p95'] * 1.05 if overall_stats['p95'] else max_connections * 0.80

    # P2 (Medium) - Based on P90
    p2_threshold = overall_stats['p90'] * 1.1 if overall_stats['p90'] else max_connections * 0.70

    # P3 (Low/Warning) - Based on P75
    p3_threshold = overall_stats['p75'] * 1.2 if overall_stats['p75'] else max_connections * 0.60

    recommendations['P0_Critical'] = {
        'threshold': int(p0_threshold),
        'percentage': round((p0_threshold / max_connections) * 100, 1),
        'description': '緊急告警 - 接近最大容量，需立即處理'
    }

    recommendations['P1_High'] = {
        'threshold': int(p1_threshold),
        'percentage': round((p1_threshold / max_connections) * 100, 1),
        'description': '高優先級告警 - 連接數異常高，需要關注'
    }

    recommendations['P2_Medium'] = {
        'threshold': int(p2_threshold),
        'percentage': round((p2_threshold / max_connections) * 100, 1),
        'description': '中優先級告警 - 連接數偏高，建議檢查'
    }

    recommendations['P3_Warning'] = {
        'threshold': int(p3_threshold),
        'percentage': round((p3_threshold / max_connections) * 100, 1),
        'description': '低優先級告警 - 預警通知'
    }

    return recommendations

def print_report(overall_stats, daily_stats, hourly_stats, weekly_stats, anomalies,
                 alarm_percentile, recommendations):
    """Print comprehensive analysis report."""

    print("=" * 80)
    print("bingo-prd RDS 資料庫連接數分析報告")
    print("=" * 80)
    print(f"分析時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"資料庫實例: {DB_INSTANCE}")
    print(f"實例規格: db.m6g.large")
    print(f"最大連接數: {MAX_CONNECTIONS}")
    print(f"當前告警閾值: {CURRENT_ALARM} ({ALARM_PERCENTAGE}%)")
    print("=" * 80)

    # Overall Statistics
    print("\n📊 七天整體統計摘要")
    print("-" * 80)
    print(f"資料點總數: {overall_stats['total_datapoints']:,}")
    print(f"平均連接數: {overall_stats['avg_connections']:.2f}")
    print(f"中位數連接數: {overall_stats['median_connections']:.2f}")
    print(f"最小連接數: {overall_stats['min_connections']:.2f}")
    print(f"最大連接數: {overall_stats['max_connections']:.2f}")
    print(f"標準差: {overall_stats['stddev']:.2f}")
    print(f"\n百分位數分析:")
    print(f"  P50 (中位數): {overall_stats['p50']:.2f}")
    if overall_stats['p75']:
        print(f"  P75: {overall_stats['p75']:.2f}")
    if overall_stats['p90']:
        print(f"  P90: {overall_stats['p90']:.2f}")
    if overall_stats['p95']:
        print(f"  P95: {overall_stats['p95']:.2f}")
    if overall_stats['p99']:
        print(f"  P99: {overall_stats['p99']:.2f}")

    # Daily Breakdown
    print("\n📅 每日詳細分析")
    print("-" * 80)
    print(f"{'日期':<12} {'星期':<10} {'平均':<10} {'峰值':<10} {'最低':<10} {'峰值時間':<12}")
    print("-" * 80)
    for date, stats in daily_stats.items():
        print(f"{date:<12} {stats['weekday']:<10} {stats['avg']:>8.2f}  {stats['max']:>8.2f}  "
              f"{stats['min']:>8.2f}  {stats['peak_time']:<12}")

    # Hourly Patterns
    print("\n⏰ 每小時使用模式分析")
    print("-" * 80)
    print(f"{'時段':<8} {'平均連接數':<15} {'峰值連接數':<15} {'資料點數':<10}")
    print("-" * 80)

    # Sort by average to identify peak hours
    sorted_hours = sorted(hourly_stats.items(), key=lambda x: x[1]['avg'], reverse=True)
    for hour, stats in sorted_hours[:24]:  # Show all 24 hours
        print(f"{hour:02d}:00    {stats['avg']:>10.2f}      {stats['max']:>10.2f}      {stats['datapoints']:>8}")

    # Identify peak hours
    peak_hours = sorted_hours[:3]
    print(f"\n🔥 最繁忙時段 (Top 3):")
    for hour, stats in peak_hours:
        print(f"   {hour:02d}:00 - 平均 {stats['avg']:.2f} 連接，峰值 {stats['max']:.2f}")

    # Weekly Patterns
    print("\n📈 工作日 vs 週末分析")
    print("-" * 80)
    print(f"工作日平均: {weekly_stats['weekday_avg']:.2f} 連接")
    print(f"週末平均: {weekly_stats['weekend_avg']:.2f} 連接")
    print(f"工作日峰值: {weekly_stats['weekday_max']:.2f} 連接")
    print(f"週末峰值: {weekly_stats['weekend_max']:.2f} 連接")

    diff_percentage = ((weekly_stats['weekday_avg'] - weekly_stats['weekend_avg']) /
                       weekly_stats['weekend_avg'] * 100) if weekly_stats['weekend_avg'] > 0 else 0
    if abs(diff_percentage) > 10:
        if diff_percentage > 0:
            print(f"\n💡 觀察: 工作日流量比週末高 {abs(diff_percentage):.1f}%")
        else:
            print(f"\n💡 觀察: 週末流量比工作日高 {abs(diff_percentage):.1f}%")
    else:
        print(f"\n💡 觀察: 工作日與週末流量相近 (差異 {abs(diff_percentage):.1f}%)")

    # Anomalies
    if anomalies:
        print("\n⚠️  異常峰值檢測 (超過平均值 + 2倍標準差)")
        print("-" * 80)
        print(f"檢測到 {len(anomalies)} 個異常峰值:")
        for anomaly in anomalies[:10]:  # Show top 10
            print(f"  {anomaly['timestamp']} - {anomaly['connections']:.2f} 連接 "
                  f"(偏離 +{anomaly['deviation']:.2f})")
        if len(anomalies) > 10:
            print(f"  ... 及其他 {len(anomalies) - 10} 個異常點")
    else:
        print("\n✅ 未檢測到顯著異常峰值")

    # Current Alarm Evaluation
    print("\n🎯 當前告警閾值評估")
    print("-" * 80)
    print(f"當前設定: {CURRENT_ALARM} 連接 ({ALARM_PERCENTAGE}%)")
    if alarm_percentile:
        print(f"百分位數: P{alarm_percentile:.1f}")
        print(f"解釋: 當前閾值高於 {alarm_percentile:.1f}% 的觀測值")

        if alarm_percentile > 95:
            print(f"評估: ⚠️  閾值設定偏高，可能會錯過重要告警")
        elif alarm_percentile > 85:
            print(f"評估: ✅ 閾值設定合理，能有效捕捉異常情況")
        else:
            print(f"評估: ⚠️  閾值設定偏低，可能產生過多告警")

    # Trends Analysis
    print("\n📊 趨勢分析")
    print("-" * 80)

    # Calculate trend from first 2 days vs last 2 days
    dates = sorted(daily_stats.keys())
    if len(dates) >= 4:
        early_avg = statistics.mean([daily_stats[d]['avg'] for d in dates[:2]])
        late_avg = statistics.mean([daily_stats[d]['avg'] for d in dates[-2:]])
        trend_change = ((late_avg - early_avg) / early_avg * 100) if early_avg > 0 else 0

        if abs(trend_change) < 5:
            print(f"使用量趨勢: 穩定 (變化 {trend_change:+.1f}%)")
            print("💡 建議: 當前容量規劃適當")
        elif trend_change > 0:
            print(f"使用量趨勢: 上升 (增加 {trend_change:.1f}%)")
            print("💡 建議: 需要監控增長趨勢，評估是否需要擴容")
        else:
            print(f"使用量趨勢: 下降 (減少 {abs(trend_change):.1f}%)")
            print("💡 建議: 可考慮優化資源配置")

    # Recommendations
    print("\n💡 告警閾值建議")
    print("=" * 80)

    for level, rec in recommendations.items():
        print(f"\n{level}:")
        print(f"  閾值: {rec['threshold']} 連接 ({rec['percentage']}%)")
        print(f"  說明: {rec['description']}")

    # Capacity Planning
    print("\n📈 容量規劃建議")
    print("=" * 80)

    utilization = (overall_stats['max_connections'] / MAX_CONNECTIONS) * 100
    print(f"當前最大使用率: {utilization:.1f}%")

    if utilization > 80:
        print("⚠️  警告: 峰值使用率超過 80%，建議考慮升級實例")
        print("   建議: 升級至 db.m6g.xlarge 或優化應用連接池")
    elif utilization > 60:
        print("⚠️  注意: 峰值使用率超過 60%，需要持續監控")
        print("   建議: 優化應用連接池配置，減少不必要的連接")
    else:
        print("✅ 良好: 當前容量充足")

    # Final Summary
    print("\n" + "=" * 80)
    print("總結建議")
    print("=" * 80)

    print(f"\n1. 告警配置建議:")
    print(f"   - 建議將主要告警閾值從 {CURRENT_ALARM} 調整為 {recommendations['P1_High']['threshold']}")
    print(f"   - 配置多層級告警: P3({recommendations['P3_Warning']['threshold']}) -> "
          f"P2({recommendations['P2_Medium']['threshold']}) -> "
          f"P1({recommendations['P1_High']['threshold']}) -> "
          f"P0({recommendations['P0_Critical']['threshold']})")

    print(f"\n2. 監控重點時段:")
    peak_hours_str = ", ".join([f"{h:02d}:00" for h, _ in peak_hours])
    print(f"   - 重點監控: {peak_hours_str}")

    print(f"\n3. 行動建議:")
    if utilization > 70:
        print(f"   - 優先: 檢查應用程式連接池配置")
        print(f"   - 優先: 調查是否有連接洩漏問題")
        print(f"   - 考慮: 評估實例升級需求")
    else:
        print(f"   - 持續監控連接數趨勢")
        print(f"   - 定期檢查應用連接使用效率")

    print("\n" + "=" * 80)

def main():
    """Main execution function."""
    try:
        # Initialize AWS session
        session = boto3.Session(profile_name=AWS_PROFILE)

        # Get CloudWatch metrics
        print("正在查詢 CloudWatch 指標數據...")
        datapoints = get_cloudwatch_metrics(session, DB_INSTANCE, days=7)

        if not datapoints:
            print("❌ 錯誤: 未能獲取 CloudWatch 數據")
            print("請確認:")
            print(f"  1. 資料庫實例名稱正確: {DB_INSTANCE}")
            print(f"  2. AWS Region 正確: {AWS_REGION}")
            print(f"  3. AWS Profile 有權限訪問 CloudWatch")
            return

        print(f"✅ 成功獲取 {len(datapoints)} 個數據點\n")

        # Perform analysis
        overall_stats = analyze_overall_stats(datapoints)
        daily_stats = analyze_daily_patterns(datapoints)
        hourly_stats = analyze_hourly_patterns(datapoints)
        weekly_stats = analyze_weekly_patterns(datapoints)
        anomalies = identify_anomalies(datapoints)
        alarm_percentile = calculate_alarm_percentile(datapoints, CURRENT_ALARM)
        recommendations = recommend_thresholds(overall_stats, MAX_CONNECTIONS)

        # Print comprehensive report
        print_report(overall_stats, daily_stats, hourly_stats, weekly_stats,
                    anomalies, alarm_percentile, recommendations)

        # Save raw data for further analysis
        output_file = f'/Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/rds/bingo-prd-analysis-{datetime.now().strftime("%Y%m%d-%H%M%S")}.json'
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump({
                'analysis_time': datetime.now().isoformat(),
                'db_instance': DB_INSTANCE,
                'max_connections': MAX_CONNECTIONS,
                'current_alarm': CURRENT_ALARM,
                'overall_stats': overall_stats,
                'daily_stats': daily_stats,
                'hourly_stats': {str(k): v for k, v in hourly_stats.items()},
                'weekly_stats': weekly_stats,
                'anomalies': anomalies,
                'alarm_percentile': alarm_percentile,
                'recommendations': recommendations
            }, f, indent=2, ensure_ascii=False)

        print(f"\n✅ 詳細數據已保存至: {output_file}")

    except Exception as e:
        print(f"❌ 執行錯誤: {str(e)}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()

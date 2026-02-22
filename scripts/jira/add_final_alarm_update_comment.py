#!/usr/bin/env python3
"""
添加所有 PROD RDS 實例告警配置完成記錄到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_final_alarm_update_comment():
    """添加最終告警配置完成記錄到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("All PROD RDS Storage Alarms Configuration Complete", 3) +
        "\n" +
        fmt.bold("Completed at:") + " 2026-01-08 16:15 GMT+8\n\n" +

        fmt.heading("Final Configuration Status", 4) +
        fmt.table(
            ['Instance', 'Storage', 'Warning (15%)', 'Autoscaling (11%)', 'Critical', 'Slack'],
            [
                ['bingo-prd', '2750 GB', '✅ 412.5 GB', '✅ 302.5 GB', '✅ 20 GB', '✅ All levels'],
                ['bingo-prd-replica1', '2929 GB', '✅ 439.35 GB', '✅ 322.19 GB', '✅ 20 GB', '✅ All levels'],
                ['bingo-prd-backstage', '5024 GB', fmt.bold('✅ 753.6 GB'), fmt.bold('✅ 552.64 GB'), '✅ 20 GB', fmt.bold('✅ All levels')],
                ['bingo-prd-backstage-replica1', '1465 GB', fmt.bold('✅ 219.75 GB'), fmt.bold('✅ 161.15 GB'), '✅ 20 GB', fmt.bold('✅ All levels')],
                ['bingo-prd-loyalty', '200 GB', fmt.bold('✅ 30 GB'), fmt.bold('✅ 22 GB'), '✅ 10 GB', fmt.bold('✅ All levels')]
            ]
        ) +
        "\n" +

        fmt.heading("Changes Summary", 4) +
        fmt.bold("Instances Updated (2026-01-08 16:10):") +
        fmt.unordered_list([
            fmt.bold("bingo-prd-backstage:") + " Warning threshold 50 GB → 753.6 GB (15%), added Autoscaling alert (552.64 GB), added Slack notifications to all levels",
            fmt.bold("bingo-prd-backstage-replica1:") + " Warning threshold 50 GB → 219.75 GB (15%), added Autoscaling alert (161.15 GB), added Slack notifications to all levels",
            fmt.bold("bingo-prd-loyalty:") + " Warning threshold 50 GB → 30 GB (15%), added Autoscaling alert (22 GB), added Slack notifications to all levels"
        ]) +
        "\n" +
        fmt.bold("Previously Updated (2026-01-08 15:20):") +
        fmt.unordered_list([
            fmt.bold("bingo-prd:") + " Warning threshold updated to 15%, Autoscaling alert added (16:00), Slack notifications enabled",
            fmt.bold("bingo-prd-replica1:") + " Warning threshold updated to 15%, Autoscaling alert added (16:00), Slack notifications enabled"
        ]) +
        "\n" +

        fmt.heading("Alarm Hierarchy (All Instances)", 4) +
        "All PROD RDS instances now follow the same 4-tier monitoring strategy:\n\n" +
        fmt.ordered_list([
            fmt.bold("Warning (15%):") + " Early warning for capacity planning - 2 periods of 5 min evaluation",
            fmt.bold("Autoscaling Alert (11%):") + " Imminent autoscaling notification - 1 period of 5 min for faster response",
            fmt.bold("Autoscaling Trigger (10%):") + " RDS automatic storage expansion (AWS managed)",
            fmt.bold("Critical (20 GB or 10 GB):") + " Emergency low space alert - 1 period of 5 min"
        ]) +
        "\n" +

        fmt.heading("Notification Configuration", 4) +
        fmt.unordered_list([
            fmt.bold("SNS Topic:") + " Cloudwatch-Slack-Notification",
            fmt.bold("Destination:") + " Slack channel (via Lambda integration)",
            fmt.bold("Events:") + " Alarm triggers (ALARM state) and recoveries (OK state)",
            fmt.bold("Coverage:") + " All alarm levels across all 5 PROD instances",
            fmt.bold("Total Alarms:") + " 20 alarms (5 instances × 4 levels each)"
        ]) +
        "\n" +

        fmt.heading("Current Storage Status (All Instances)", 4) +
        fmt.table(
            ['Instance', 'Free Space', 'Usage %', 'Autoscale (10%)', 'Status'],
            [
                ['bingo-prd', '~326 GB', '88.1%', '275 GB', '⚠️ Near autoscaling'],
                ['bingo-prd-replica1', '~530 GB', '81.9%', '292.9 GB', '✅ Healthy'],
                ['bingo-prd-backstage', '~3672 GB', '26.9%', '502.4 GB', '✅ Healthy'],
                ['bingo-prd-backstage-replica1', '~175 GB', '88.0%', '146.5 GB', '✅ Healthy'],
                ['bingo-prd-loyalty', '~69 GB', '65.3%', '20 GB', '✅ Healthy']
            ]
        ) +
        "\n" +

        fmt.heading("Expected Behavior", 4) +
        fmt.bold("When storage decreases:") +
        fmt.ordered_list([
            "Warning alarm triggers at 15% (Slack notification)",
            "Autoscaling Imminent alarm triggers at 11% (Slack notification)",
            "RDS autoscaling activates at 10% (automatic storage expansion)",
            "Instance enters storage-optimization state (several hours)",
            "Storage expanded, alarms return to OK (Slack notification)"
        ]) +
        "\n" +
        fmt.bold("Immediate attention:") +
        fmt.unordered_list([
            fmt.bold("bingo-prd:") + " Currently at 11.8% free space, expected to trigger Autoscaling Imminent alarm within hours",
            "Monitor Slack channel for notifications",
            "Autoscaling will handle capacity expansion automatically"
        ]) +
        "\n" +

        fmt.heading("Maintenance Commands", 4) +
        fmt.bold("Alarm Configuration Audit:") +
        fmt.code_block("bash scripts/cloudwatch/check-all-rds-alarms.sh", language="bash") +
        "\n" +
        fmt.bold("Current Free Space Check:") +
        fmt.code_block("bash scripts/cloudwatch/get-rds-free-space.sh", language="bash") +
        "\n" +

        fmt.heading("Benefits Achieved", 4) +
        fmt.unordered_list([
            "✅ Consistent monitoring across all PROD RDS instances",
            "✅ Early warning (15%) before autoscaling triggers (10%)",
            "✅ Imminent notification (11%) provides additional heads-up",
            "✅ All alerts route to Slack for team visibility",
            "✅ Automatic storage expansion with monitoring",
            "✅ Reduced risk of storage exhaustion incidents",
            "✅ Better capacity planning with advance notifications"
        ]) +
        "\n" +

        fmt.heading("Console Links", 4) +
        fmt.unordered_list([
            fmt.link(
                "CloudWatch Alarms Dashboard",
                "https://console.aws.amazon.com/cloudwatch/home?region=ap-east-1#alarmsV2:"
            ),
            fmt.link(
                "RDS Instances Console",
                "https://console.aws.amazon.com/rds/home?region=ap-east-1"
            )
        ]) +
        "\n" +
        fmt.divider() +
        fmt.italic("All PROD RDS storage monitoring configuration completed - 2026-01-08 16:15 GMT+8") +
        "\n" +
        fmt.italic("Total alarms configured: 20 (5 instances × 4 alarm levels)")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_final_alarm_update_comment()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

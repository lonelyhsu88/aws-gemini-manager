#!/usr/bin/env python3
"""
添加告警配置更新到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_alarm_setup_comment():
    """添加告警配置到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("CloudWatch Alarm Configuration Updated", 3) +
        "\n" +
        fmt.bold("Updated at:") + " 2026-01-08 15:20 GMT+8\n\n" +

        fmt.heading("Updated Alarms", 4) +
        fmt.table(
            ['Instance', 'Alarm Level', 'Old Threshold', 'New Threshold', 'Slack Notification'],
            [
                ['bingo-prd', 'Warning', '50 GB', fmt.bold('412.5 GB (15%)'), '✅ Yes'],
                ['bingo-prd', 'Critical', '20 GB', '20 GB (unchanged)', '✅ Yes'],
                ['bingo-prd-replica1', 'Warning', '50 GB', fmt.bold('439.35 GB (15%)'), fmt.bold('✅ Added')],
                ['bingo-prd-replica1', 'Critical', '20 GB', '20 GB', fmt.bold('✅ Added')]
            ]
        ) +
        "\n" +

        fmt.heading("Notification Setup", 4) +
        fmt.unordered_list([
            fmt.bold("SNS Topic:") + " Cloudwatch-Slack-Notification",
            fmt.bold("Destination:") + " Slack channel (via Lambda integration)",
            fmt.bold("Trigger:") + " Alarms will send notifications when entering ALARM or OK state",
            fmt.bold("Evaluation:") + " 2 consecutive periods of 5 minutes (10 minutes total)"
        ]) +
        "\n" +

        fmt.heading("Alert Thresholds vs Autoscaling", 4) +
        fmt.table(
            ['Threshold Type', 'bingo-prd', 'bingo-prd-replica1', 'Purpose'],
            [
                ['Warning (15%)', '412.5 GB', '439.35 GB', 'Early warning before autoscaling'],
                ['Autoscaling (10%)', '275 GB', '292.9 GB', 'RDS automatic trigger'],
                ['Critical (20 GB)', '20 GB', '20 GB', 'Emergency low space']
            ]
        ) +
        "\n" +

        fmt.heading("Current Status", 4) +
        fmt.unordered_list([
            fmt.bold("bingo-prd:") + " ~325 GB free (11.8%) " + fmt.bold("⚠️ WILL TRIGGER WARNING ALARM"),
            fmt.bold("bingo-prd-replica1:") + " ~530 GB free (18.1%) ✅ Above warning threshold",
            "Warning alarm for bingo-prd expected to trigger within hours",
            "Slack notification will be sent automatically"
        ]) +
        "\n" +

        fmt.heading("Expected Alert Flow", 4) +
        fmt.ordered_list([
            fmt.bold("Warning Alert (15%):") + " Advance notice to review capacity planning",
            fmt.bold("Autoscaling Trigger (10%):") + " RDS automatically expands storage",
            fmt.bold("Storage Optimization:") + " Instance enters optimization state for several hours",
            fmt.bold("OK State:") + " Notification when free space returns above threshold"
        ]) +
        "\n" +

        fmt.heading("Action Items", 4) +
        fmt.unordered_list([
            "✅ CloudWatch alarms updated with 15% early warning threshold",
            "✅ Slack notifications enabled for both instances",
            "⏳ Monitor for bingo-prd warning alarm (expected soon)",
            "⏳ Wait for storage optimization to complete on replica1",
            "📋 Plan capacity review when primary instance triggers autoscaling"
        ]) +
        "\n" +

        fmt.heading("Console Links", 4) +
        fmt.unordered_list([
            fmt.link(
                "CloudWatch Alarms Dashboard",
                "https://console.aws.amazon.com/cloudwatch/home?region=ap-east-1#alarmsV2:"
            ),
            fmt.link(
                "RDS bingo-prd Console",
                "https://console.aws.amazon.com/rds/home?region=ap-east-1#database:id=bingo-prd"
            ),
            fmt.link(
                "RDS bingo-prd-replica1 Console",
                "https://console.aws.amazon.com/rds/home?region=ap-east-1#database:id=bingo-prd-replica1"
            )
        ]) +
        "\n" +
        fmt.divider() +
        fmt.italic("Alarm configuration completed by DevOps automation")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_alarm_setup_comment()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

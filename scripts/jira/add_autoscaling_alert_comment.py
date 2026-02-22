#!/usr/bin/env python3
"""
添加 Autoscaling 觸發告警配置到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_autoscaling_alert_comment():
    """添加 autoscaling 觸發告警到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("Autoscaling Trigger Alert Configuration", 3) +
        "\n" +
        fmt.bold("Updated at:") + " 2026-01-08 16:00 GMT+8\n\n" +

        fmt.heading("New Alert Level Added", 4) +
        "Created new alarm to notify when autoscaling is about to trigger (11% threshold).\n\n" +

        fmt.table(
            ['Instance', 'Alarm Name', 'Threshold', 'Purpose', 'Slack'],
            [
                ['bingo-prd', 'RDS-bingo-prd-Autoscaling-Imminent', '302.5 GB (11%)', 'Notify before autoscaling triggers', '✅ Yes'],
                ['bingo-prd-replica1', 'RDS-bingo-prd-replica1-Autoscaling-Imminent', '322.19 GB (11%)', 'Notify before autoscaling triggers', '✅ Yes']
            ]
        ) +
        "\n" +

        fmt.heading("Complete Alert Hierarchy", 4) +
        fmt.bold("bingo-prd (2750 GB):") +
        fmt.unordered_list([
            "⚠️  Warning (15% / 412.5 GB) - Early warning for capacity planning",
            "🔔 " + fmt.bold("Autoscaling Alert (11% / 302.5 GB)") + " - Imminent autoscaling notification " + fmt.bold("← NEW"),
            "⚙️  Autoscaling Trigger (10% / 275 GB) - RDS automatic expansion",
            "🔴 Critical (20 GB) - Emergency low space alert"
        ]) +
        "\n" +
        fmt.bold("bingo-prd-replica1 (2929 GB):") +
        fmt.unordered_list([
            "⚠️  Warning (15% / 439.35 GB) - Early warning for capacity planning",
            "🔔 " + fmt.bold("Autoscaling Alert (11% / 322.19 GB)") + " - Imminent autoscaling notification " + fmt.bold("← NEW"),
            "⚙️  Autoscaling Trigger (10% / 292.9 GB) - RDS automatic expansion",
            "🔴 Critical (20 GB) - Emergency low space alert"
        ]) +
        "\n" +

        fmt.heading("Current Status", 4) +
        fmt.unordered_list([
            fmt.bold("bingo-prd:") + " ~326 GB free (11.8%)",
            "✅ Warning alarm already triggered (< 412.5 GB)",
            "⏳ Autoscaling alert will trigger soon (needs to drop below 302.5 GB)",
            "⏳ Autoscaling will activate at 275 GB (10%)",
            fmt.bold("Expected:") + " Autoscaling Imminent alarm will trigger within hours"
        ]) +
        "\n" +

        fmt.heading("Alert Timeline (Expected)", 4) +
        fmt.ordered_list([
            fmt.bold("Now:") + " Warning alarm active (15% threshold breached)",
            fmt.bold("Soon (~few hours):") + " Autoscaling Imminent alarm triggers (11% threshold)",
            fmt.bold("Shortly after:") + " RDS autoscaling activates (10% threshold)",
            fmt.bold("During expansion:") + " Instance enters storage-optimization state",
            fmt.bold("After completion:") + " All alarms return to OK state"
        ]) +
        "\n" +

        fmt.heading("Notification Behavior", 4) +
        fmt.unordered_list([
            fmt.bold("Alarm Trigger:") + " Slack notification when threshold breached",
            fmt.bold("OK Recovery:") + " Slack notification when free space returns above threshold",
            fmt.bold("Evaluation:") + " 1 period of 5 minutes for faster notification",
            fmt.bold("SNS Topic:") + " Cloudwatch-Slack-Notification"
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
            )
        ]) +
        "\n" +
        fmt.divider() +
        fmt.italic("Autoscaling alert configuration completed - 2026-01-08 16:00 GMT+8")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_autoscaling_alert_comment()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

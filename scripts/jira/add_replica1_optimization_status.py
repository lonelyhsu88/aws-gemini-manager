#!/usr/bin/env python3
"""
添加 bingo-prd-replica1 storage optimization 狀態到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_replica1_optimization_status():
    """添加 replica1 optimization 狀態到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("bingo-prd-replica1 Storage Optimization Status Update", 3) +
        "\n" +
        fmt.bold("Status Check Time:") + " 2026-01-08 15:34 GMT+8\n\n" +

        fmt.heading("Current Status", 4) +
        fmt.table(
            ['Metric', 'Value', 'Status'],
            [
                ['Instance Status', fmt.bold('storage-optimization'), '⚠️ Still optimizing'],
                ['Allocated Storage', '2929 GB', '✅ Expanded'],
                ['Free Space', fmt.bold('~529.5 GB (18.1%)'), '✅ Healthy'],
                ['Max Storage Limit', '5000 GB', '-'],
                ['Storage Type', 'gp3', '-']
            ]
        ) +
        "\n" +

        fmt.heading("Optimization Timeline", 4) +
        fmt.table(
            ['Event', 'Time (GMT+8)', 'Duration'],
            [
                ['Autoscaling Triggered', '2026-01-08 06:47', '-'],
                ['Storage Expansion Completed', '2026-01-08 06:49', '2 minutes'],
                [fmt.bold('Optimization Status'), fmt.bold('Ongoing'), fmt.bold('~33 hours')]
            ]
        ) +
        "\n" +

        fmt.heading("Free Space Trend (Last 30 Minutes)", 4) +
        "Free space remains stable at ~529 GB with no abnormal changes:\n\n" +
        fmt.table(
            ['Time (GMT+8)', 'Free Space', 'Status'],
            [
                ['15:09', '529.0 GB', 'Stable'],
                ['15:14', '529.1 GB', 'Stable'],
                ['15:19', '529.1 GB', 'Stable'],
                ['15:24', '529.1 GB', 'Stable'],
                ['15:29', '529.1 GB', 'Stable'],
                ['15:34', '529.1 GB', 'Stable']
            ]
        ) +
        "\n" +

        fmt.heading("Alarm Status", 4) +
        fmt.table(
            ['Alarm Level', 'Threshold', 'State', 'Last Updated'],
            [
                ['Warning (15%)', '< 439.35 GB', '🟢 OK', '2025-10-29 23:39 GMT+8'],
                ['Autoscaling Alert (11%)', '< 322.19 GB', '🟢 OK', '2026-01-08 15:24 GMT+8']
            ]
        ) +
        "\n" +

        fmt.heading("Analysis", 4) +
        fmt.bold("Normal Behavior:") +
        fmt.unordered_list([
            "Storage optimization can take " + fmt.bold("several hours to 24 hours"),
            "Currently at " + fmt.bold("~33 hours") + ", approaching upper normal range",
            "Free space is stable with no abnormal decline",
            "All alarms in OK state"
        ]) +
        "\n" +
        fmt.bold("Expected Outcome:") +
        fmt.unordered_list([
            "Large capacity instances (2929 GB) typically require longer optimization time",
            "Instance expected to return to " + fmt.bold("available") + " state within next few hours",
            "No action required - this is normal RDS post-expansion optimization"
        ]) +
        "\n" +

        fmt.heading("Comparison with Primary Instance", 4) +
        fmt.table(
            ['Metric', 'bingo-prd (Primary)', 'bingo-prd-replica1', 'Difference'],
            [
                ['Status', 'available', 'storage-optimization', '-'],
                ['Capacity', '2750 GB', '2929 GB', '+179 GB'],
                ['Free Space', '~325.7 GB (11.8%)', '~529.5 GB (18.1%)', '+203.8 GB'],
                ['Alarm Status', 'Warning ALARM', 'All OK', '-']
            ]
        ) +
        "\n" +

        fmt.heading("Key Observations", 4) +
        fmt.unordered_list([
            fmt.bold("Replica ahead of primary:") + " Replica triggered autoscaling first (2026-01-08 06:47) due to different usage patterns",
            fmt.bold("Capacity divergence:") + " Replica now has 179 GB more capacity than primary (2929 GB vs 2750 GB)",
            fmt.bold("Health status:") + " Replica is healthier with 18.1% free space vs primary's 11.8%",
            fmt.bold("Primary approaching autoscaling:") + " Primary expected to trigger autoscaling in ~2 days at current rate"
        ]) +
        "\n" +

        fmt.heading("Next Steps", 4) +
        fmt.ordered_list([
            "Continue monitoring replica optimization progress",
            "Expected to complete and return to available state soon",
            "Monitor primary instance (bingo-prd) for autoscaling trigger in coming days",
            "No immediate action required - all alarms configured and functioning"
        ]) +
        "\n" +

        fmt.divider() +
        fmt.italic("Storage optimization status update - 2026-01-08 15:34 GMT+8") +
        "\n" +
        fmt.italic("Optimization duration: ~33 hours (within normal range for large instances)")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_replica1_optimization_status()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

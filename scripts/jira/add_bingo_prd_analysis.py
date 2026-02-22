#!/usr/bin/env python3
"""
檢查 bingo-prd 主實例並將結果添加到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_bingo_prd_analysis():
    """添加 bingo-prd 分析到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("bingo-prd Primary Instance Storage Analysis", 3) +
        "\n" +
        fmt.bold("Checked at:") + " 2026-01-08 06:10 UTC (14:10 GMT+8)\n\n" +

        fmt.heading("Current Configuration", 4) +
        fmt.table(
            ['Parameter', 'Value', 'Status'],
            [
                ['Instance ID', 'bingo-prd', '✅ Primary'],
                ['Status', 'available', '✅ Normal'],
                ['Storage Type', 'gp3', '-'],
                ['Allocated Storage', '2750 GB', '⚠️ Lower than replica'],
                ['Max Allocated Storage', '5000 GB', '-'],
                ['IOPS', '12000', '-'],
                ['Storage Throughput', '500 MB/s', '-'],
                ['Instance Class', 'db.m6g.large', '-']
            ]
        ) +
        "\n" +

        fmt.heading("Free Storage Space Trend (Last 10 Hours)", 4) +
        fmt.code_block(
            "2026-01-07 21:06 UTC - 349,431,565,721 bytes (~325 GB)\n" +
            "2026-01-07 22:06 UTC - 349,612,214,408 bytes (~325 GB)\n" +
            "2026-01-07 23:06 UTC - 349,934,305,553 bytes (~326 GB)\n" +
            "2026-01-08 00:06 UTC - 349,964,185,190 bytes (~326 GB)\n" +
            "2026-01-08 01:06 UTC - 349,664,230,400 bytes (~325 GB)\n" +
            "2026-01-08 02:06 UTC - 348,761,374,173 bytes (~324 GB)\n" +
            "2026-01-08 03:06 UTC - 349,113,992,465 bytes (~325 GB)\n" +
            "2026-01-08 04:06 UTC - 349,374,005,794 bytes (~325 GB)\n" +
            "2026-01-08 05:06 UTC - 349,564,101,290 bytes (~325 GB)\n" +
            "2026-01-08 06:06 UTC - 349,357,497,958 bytes (~325 GB)",
            "text"
        ) +
        "\n" +

        fmt.heading("Key Findings", 4) +
        fmt.unordered_list([
            fmt.bold("Free Space:") + " ~325 GB / 2750 GB = " + fmt.bold("11.8% available"),
            fmt.bold("Threshold:") + " Approaching 10% autoscaling trigger threshold",
            fmt.bold("Trend:") + " Stable at ~325 GB over last 10 hours",
            fmt.bold("Recent Events:") + " No storage autoscaling events in last 7 days"
        ]) +
        "\n" +

        fmt.heading("Primary vs Replica Comparison", 4) +
        fmt.table(
            ['Metric', 'bingo-prd (Primary)', 'bingo-prd-replica1', 'Difference'],
            [
                ['Allocated Storage', '2750 GB', '2929 GB', '+179 GB (6.5%)'],
                ['Free Space', '~325 GB', '~530 GB', '+205 GB'],
                ['Free Space %', '11.8%', '18.1%', '+6.3%'],
                ['Status', 'available', 'storage-optimization', '-'],
                ['Last Autoscaling', 'None (7 days)', '2026-01-07 22:47 UTC', '-']
            ]
        ) +
        "\n" +

        fmt.heading("Risk Assessment", 4) +
        "⚠️ " + fmt.bold("MODERATE RISK") + "\n\n" +
        fmt.unordered_list([
            "Primary instance at 11.8% free space, only 1.8% above autoscaling threshold",
            "Could trigger autoscaling within hours if storage usage increases",
            "Replica already triggered autoscaling, indicating growing storage demand",
            "Both instances have same MaxAllocatedStorage (5000 GB) with room to grow"
        ]) +
        "\n" +

        fmt.heading("Recommendations", 4) +
        fmt.ordered_list([
            fmt.bold("Monitor Closely:") + " Watch primary instance free space, expect autoscaling trigger soon",
            fmt.bold("Set Alert:") + " CloudWatch alarm for FreeStorageSpace < 15% (412.5 GB)",
            fmt.bold("Capacity Planning:") + " Analyze storage growth rate to predict when MaxAllocatedStorage (5000 GB) will be reached",
            fmt.bold("Consider Proactive Action:") + " Evaluate data archival or cleanup strategies if growth rate is high"
        ]) +
        "\n" +

        fmt.heading("Next Steps", 4) +
        fmt.unordered_list([
            "Continue monitoring both instances for 24 hours",
            "Wait for bingo-prd-replica1 to complete storage-optimization",
            "Set up CloudWatch dashboard for storage metrics",
            "Schedule capacity planning review if primary triggers autoscaling"
        ]) +
        "\n" +
        fmt.divider() +
        fmt.italic("Analysis completed by DevOps automation script")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_bingo_prd_analysis()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

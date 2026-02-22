#!/usr/bin/env python3
"""
添加 RDS 告警稽核結果到 OPS-1033 comment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def add_alarm_audit_comment():
    """添加告警稽核結果到 JIRA comment"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建 comment
    comment = (
        fmt.heading("PROD RDS Storage Alarm Configuration Audit", 3) +
        "\n" +
        fmt.bold("Audit Date:") + " 2026-01-08 15:45 GMT+8\n\n" +

        fmt.heading("Audit Results Summary", 4) +
        fmt.table(
            ['Instance', 'Storage', 'Warning Alarm', 'Threshold', 'Critical Alarm', 'Threshold', 'Slack Notify'],
            [
                ['bingo-prd', '2750 GB', '✅ Configured', fmt.bold('412.5 GB (15%)'), '✅ Configured', '20 GB', fmt.bold('✅ Yes')],
                ['bingo-prd-replica1', '2929 GB', '✅ Configured', fmt.bold('439.35 GB (15%)'), '✅ Configured', '20 GB', fmt.bold('✅ Yes')],
                ['bingo-prd-backstage', '5024 GB', '⚠️ Needs Update', fmt.bold('50 GB (1%)'), '✅ Configured', '20 GB', fmt.bold('❌ Missing')],
                ['bingo-prd-backstage-replica1', '1465 GB', '⚠️ Needs Update', fmt.bold('50 GB (3.4%)'), '✅ Configured', '20 GB', fmt.bold('❌ Missing')],
                ['bingo-prd-loyalty', '200 GB', '⚠️ Needs Update', fmt.bold('50 GB (25%)'), '✅ Configured', '20 GB', fmt.bold('❌ Missing')]
            ]
        ) +
        "\n" +

        fmt.heading("Current Storage Status", 4) +
        fmt.table(
            ['Instance', 'Total Storage', 'Current Free Space', 'Usage %', 'Status'],
            [
                ['bingo-prd', '2750 GB', '~326 GB', '88.1%', '⚠️ Approaching 15% threshold'],
                ['bingo-prd-replica1', '2929 GB', '~530 GB', '81.9%', '✅ Healthy'],
                ['bingo-prd-backstage', '5024 GB', '~3672 GB', '26.9%', '✅ Healthy'],
                ['bingo-prd-backstage-replica1', '1465 GB', '~175 GB', '88.0%', '✅ Healthy'],
                ['bingo-prd-loyalty', '200 GB', '~69 GB', '65.3%', '✅ Healthy']
            ]
        ) +
        "\n" +

        fmt.heading("Identified Issues", 4) +
        fmt.bold("3 instances missing Slack notifications:") +
        fmt.unordered_list([
            fmt.bold("bingo-prd-backstage:") + " Warning threshold too low (50 GB = 1% vs recommended 15% = 753.6 GB), no Slack notification",
            fmt.bold("bingo-prd-backstage-replica1:") + " Warning threshold too low (50 GB = 3.4% vs recommended 15% = 219.75 GB), no Slack notification",
            fmt.bold("bingo-prd-loyalty:") + " Warning threshold too low (50 GB = 25% vs recommended 15% = 30 GB), acceptable threshold but no Slack notification"
        ]) +
        "\n" +

        fmt.heading("Risk Assessment", 4) +
        fmt.table(
            ['Instance', 'Autoscaling Threshold (10%)', 'Current Free Space', 'Risk Level', 'Notification Status'],
            [
                ['bingo-prd', '275 GB', '~326 GB', fmt.bold('🔴 High') + ' - Will trigger soon', '✅ Slack enabled'],
                ['bingo-prd-replica1', '292.9 GB', '~530 GB', '🟢 Low', '✅ Slack enabled'],
                ['bingo-prd-backstage', '502.4 GB', '~3672 GB', '🟢 Low', fmt.bold('❌ No notification')],
                ['bingo-prd-backstage-replica1', '146.5 GB', '~175 GB', '🟡 Medium', fmt.bold('❌ No notification')],
                ['bingo-prd-loyalty', '20 GB', '~69 GB', '🟢 Low', fmt.bold('❌ No notification')]
            ]
        ) +
        "\n" +

        fmt.heading("Recommended Actions", 4) +
        fmt.bold("Priority 1 (Urgent):") +
        fmt.unordered_list([
            "✅ bingo-prd and bingo-prd-replica1 already fixed (completed 2026-01-08 15:20)",
            "⏳ Monitor bingo-prd for imminent autoscaling event (currently at 11.8% free space)"
        ]) +
        "\n" +
        fmt.bold("Priority 2 (High):") +
        fmt.unordered_list([
            "Update bingo-prd-backstage-replica1 warning threshold to 219.75 GB (15%) and add Slack notification",
            "Add Slack notification to bingo-prd-backstage warning alarm (consider updating threshold to 753.6 GB)"
        ]) +
        "\n" +
        fmt.bold("Priority 3 (Medium):") +
        fmt.unordered_list([
            "Add Slack notification to bingo-prd-loyalty warning alarm (current 50 GB threshold is acceptable at 25%)"
        ]) +
        "\n" +

        fmt.heading("Recommended Threshold Configuration", 4) +
        fmt.table(
            ['Instance', 'Current Warning', 'Recommended Warning (15%)', 'Current Critical', 'Recommended Critical'],
            [
                ['bingo-prd', '412.5 GB', '✅ Already set', '20 GB', '✅ Keep as is'],
                ['bingo-prd-replica1', '439.35 GB', '✅ Already set', '20 GB', '✅ Keep as is'],
                ['bingo-prd-backstage', '50 GB', fmt.bold('753.6 GB'), '20 GB', '50 GB (1%)'],
                ['bingo-prd-backstage-replica1', '50 GB', fmt.bold('219.75 GB'), '20 GB', '50 GB (3.4%)'],
                ['bingo-prd-loyalty', '50 GB', '30 GB (15%)', '20 GB', '10 GB (5%)']
            ]
        ) +
        "\n" +

        fmt.heading("Next Steps", 4) +
        fmt.ordered_list([
            fmt.bold("Immediate:") + " Monitor bingo-prd for autoscaling trigger (expected within hours)",
            fmt.bold("Within 24 hours:") + " Update alarms for backstage-replica1 and add Slack notifications",
            fmt.bold("Within 48 hours:") + " Complete alarm configuration for all remaining instances",
            fmt.bold("Weekly:") + " Run alarm audit script to verify all instances have proper monitoring"
        ]) +
        "\n" +

        fmt.heading("Audit Script", 4) +
        fmt.code_block("bash scripts/cloudwatch/check-all-rds-alarms.sh", language="bash") +
        "\n" +

        fmt.divider() +
        fmt.italic("Audit completed by DevOps automation - 2026-01-08 15:45 GMT+8")
    )

    # 添加 comment
    result = jira.add_comment(
        ticket_id='OPS-1033',
        comment=comment
    )

    return result

if __name__ == '__main__':
    result = add_alarm_audit_comment()

    if result.get('success'):
        print(f"\n✅ JIRA comment 添加成功!")
        print(f"   Ticket: OPS-1033")
        print(f"   Comment ID: {result.get('comment_id')}")
        print(f"   URL: https://jira.ftgaming.cc/browse/OPS-1033")
    else:
        print(f"\n❌ 添加 comment 失敗:")
        print(f"   錯誤: {result.get('raw_response', result.get('raw_output', 'Unknown error'))}")
        sys.exit(1)

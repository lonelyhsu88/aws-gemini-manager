#!/usr/bin/env python3
"""
更新 JIRA OPS-1131 標題為英文版本
"""

import sys
import os

# 添加 scripts/jira 目錄到 Python path
sys.path.insert(0, os.path.dirname(__file__))

from jira_api import JiraAPI


def update_ticket_title():
    """更新 OPS-1131 票券標題為英文"""

    jira = JiraAPI()

    # 新的英文標題
    new_summary = "n8n Host Maintenance - OS Update and Version Upgrade Evaluation (2026-01-23)"

    print(f"正在更新 JIRA ticket OPS-1131 標題...")
    print(f"新標題: {new_summary}")

    # 更新票券
    result = jira.update_issue(
        ticket_id='OPS-1131',
        summary=new_summary
    )

    if result.get('success'):
        print(f"\n✅ JIRA Ticket 標題更新成功！")
        print(f"Ticket URL: https://jira.ftgaming.cc/browse/OPS-1131")
        return result
    else:
        print(f"\n❌ JIRA Ticket 標題更新失敗")
        print(f"錯誤訊息: {result.get('error_messages', result.get('errors', 'Unknown error'))}")
        print(f"\n詳細輸出:")
        print(result)
        return None


if __name__ == '__main__':
    update_ticket_title()

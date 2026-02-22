#!/usr/bin/env python3
"""
更新 OPS-1033 標題為英文
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI

def update_title():
    """更新 ticket 標題為英文"""

    jira = JiraAPI()

    # 更新標題
    result = jira.update_issue(
        ticket_id='OPS-1033',
        summary='bingo-prd-replica1 RDS Storage Autoscaling Event Record'
    )

    return result

if __name__ == '__main__':
    result = update_title()

    if result.get('success'):
        print(f"\n✅ JIRA ticket 標題更新成功!")
        print(f"   Ticket ID: {result['ticket_id']}")
        print(f"   URL: {result['ticket_url']}")
        print(f"   新標題: bingo-prd-replica1 RDS Storage Autoscaling Event Record")
    else:
        print(f"\n❌ 更新失敗:")
        print(f"   原始輸出: {result.get('raw_output', 'Unknown error')}")
        sys.exit(1)

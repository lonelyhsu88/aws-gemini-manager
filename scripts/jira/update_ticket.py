#!/usr/bin/env python3
"""
更新 JIRA Ticket

使用範例:
    # 更新標題
    python3 update_ticket.py --ticket OPS-814 --summary "新的標題"

    # 更新描述
    python3 update_ticket.py --ticket OPS-814 --description "新的描述內容"

    # 更新優先級
    python3 update_ticket.py --ticket OPS-814 --priority High

    # 添加評論
    python3 update_ticket.py --ticket OPS-814 --comment "升級已完成"

    # 同時更新多個欄位
    python3 update_ticket.py --ticket OPS-814 --summary "新標題" --priority High --comment "已更新"
"""

import argparse
import sys
from jira_api import JiraAPI


def main():
    parser = argparse.ArgumentParser(description='更新 JIRA Ticket')

    parser.add_argument('--ticket', required=True, help='Ticket ID (如: OPS-814)')
    parser.add_argument('--summary', help='新標題')
    parser.add_argument('--description', help='新描述 (JIRA Wiki Markup)')
    parser.add_argument('--priority', help='新優先級 (Highest/High/Medium/Low/Lowest)')
    parser.add_argument('--assignee', help='新負責人 username')
    parser.add_argument('--labels', help='新標籤 (逗號分隔)', type=str)
    parser.add_argument('--comment', help='添加評論')

    args = parser.parse_args()

    # 初始化 API
    jira = JiraAPI()

    # 檢查是否有要更新的欄位
    has_updates = any([
        args.summary,
        args.description,
        args.priority,
        args.assignee,
        args.labels
    ])

    if not has_updates and not args.comment:
        print("❌ 錯誤: 沒有要更新的內容")
        parser.print_help()
        sys.exit(1)

    # 更新 ticket
    if has_updates:
        print(f"🔄 更新 JIRA ticket {args.ticket}...\n")

        if args.summary:
            print(f"📝 新標題: {args.summary}")
        if args.description:
            print(f"📄 更新描述")
        if args.priority:
            print(f"⚡ 新優先級: {args.priority}")
        if args.assignee:
            print(f"👤 新負責人: {args.assignee}")
        if args.labels:
            print(f"🏷️  新標籤: {args.labels}")

        labels = args.labels.split(',') if args.labels else None

        result = jira.update_issue(
            ticket_id=args.ticket,
            summary=args.summary,
            description=args.description,
            priority=args.priority,
            assignee=args.assignee,
            labels=labels
        )

        if result['success']:
            print(f"\n✅ JIRA Ticket {args.ticket} 更新成功！")
            print(f"🔗 URL: {result['ticket_url']}")
        else:
            print(f"\n❌ 更新失敗")
            print(result.get('raw_output', ''))
            sys.exit(1)

    # 添加評論
    if args.comment:
        print(f"\n💬 添加評論到 {args.ticket}...")
        print(f"   內容: {args.comment}")

        result = jira.add_comment(args.ticket, args.comment)

        if result['success']:
            print(f"✅ 評論添加成功 (Comment ID: {result['comment_id']})")
        else:
            print(f"❌ 添加評論失敗")
            print(result.get('raw_output', ''))


if __name__ == '__main__':
    main()

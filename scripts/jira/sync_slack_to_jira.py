#!/usr/bin/env python3
"""
從 Slack #gemini-rd需求溝通處理群 同步「商戶無法登入遊戲」討論到 JIRA SEG-2

使用範例:
    python3 sync_slack_to_jira.py
    python3 sync_slack_to_jira.py --days-back 3  # 檢查最近3天
"""

import argparse
import sys
from datetime import datetime
from jira_api import SlackAPI, JiraAPI, JiraFormatter


def get_latest_merchant_login_issues(channel_id: str, days_back: int = 1) -> list:
    """
    從 Slack 頻道獲取最新的商戶無法登入問題

    Args:
        channel_id: Slack channel ID
        days_back: 往前搜尋天數

    Returns:
        相關訊息列表
    """
    slack = SlackAPI()
    messages = slack.get_channel_history(channel_id, limit=100, days_back=days_back)

    # 過濾包含關鍵字的訊息
    keywords = ['商戶無法登入', '無法登入遊戲', 'login issue', 'SEG-2']
    relevant_msgs = []

    for msg in messages:
        text = msg.get('text', '')
        if any(keyword in text for keyword in keywords):
            relevant_msgs.append(msg)

    return relevant_msgs


def format_slack_message_for_jira(msg: dict) -> str:
    """
    格式化 Slack 訊息為 JIRA 評論格式

    Args:
        msg: Slack 訊息字典

    Returns:
        JIRA Wiki Markup 格式的評論
    """
    fmt = JiraFormatter()

    # 提取訊息資訊
    text = msg.get('text', '')
    ts = msg.get('ts', '')
    user = msg.get('user', 'Unknown')

    # 轉換時間戳
    dt = datetime.fromtimestamp(float(ts))
    time_str = dt.strftime('%Y-%m-%d %H:%M:%S CST')

    # 建立評論
    comment = fmt.heading('Slack 更新', 3)
    comment += f"{fmt.bold('時間')}: {time_str}\n"
    comment += f"{fmt.bold('用戶')}: {user}\n"
    comment += fmt.divider()

    # 解析訊息內容
    lines = text.split('\n')
    parsed_info = {}
    description = []
    in_description = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith('<@'):
            continue

        # 解析欄位
        if '：' in line or ':' in line:
            parts = line.split('：', 1) if '：' in line else line.split(':', 1)
            if len(parts) == 2:
                key = parts[0].strip()
                value = parts[1].strip()

                # 跳過特殊格式
                if key.startswith('```') or value.startswith('```'):
                    continue

                parsed_info[key] = value
        else:
            in_description = True
            description.append(line)

    # 輸出解析的資訊
    if parsed_info:
        comment += fmt.heading('問題資訊', 4)
        info_list = [f"{fmt.bold(k)}: {v}" for k, v in parsed_info.items()]
        comment += fmt.unordered_list(info_list)
        comment += fmt.divider()

    # 輸出描述
    if description:
        comment += fmt.heading('詳細內容', 4)
        comment += '\n'.join(description) + '\n'
        comment += fmt.divider()

    # 原始訊息（用於參考）
    comment += fmt.heading('原始訊息', 4)
    comment += fmt.code_block(text)

    return comment


def main():
    parser = argparse.ArgumentParser(description='同步 Slack 討論到 JIRA SEG-2')
    parser.add_argument('--days-back', type=int, default=1, help='往前搜尋天數（預設1天）')
    parser.add_argument('--ticket', default='SEG-2', help='JIRA ticket ID（預設 SEG-2）')
    parser.add_argument('--dry-run', action='store_true', help='只顯示不實際更新 JIRA')

    args = parser.parse_args()

    # Slack channel ID
    channel_id = 'C07KEDS4W8N'  # gemini-rd需求溝通處理群

    print(f'🔍 檢查 Slack #gemini-rd需求溝通處理群 (最近 {args.days_back} 天)')
    print(f'📝 目標 JIRA: {args.ticket}\n')

    # 獲取最新訊息
    messages = get_latest_merchant_login_issues(channel_id, args.days_back)

    if not messages:
        print('✅ 沒有找到新的相關訊息')
        return

    print(f'找到 {len(messages)} 則相關訊息\n')

    # 處理每則訊息
    jira = JiraAPI()

    for i, msg in enumerate(messages, 1):
        ts = msg.get('ts', '')
        dt = datetime.fromtimestamp(float(ts))
        time_str = dt.strftime('%Y-%m-%d %H:%M:%S')

        print(f'{i}. {time_str}')
        print(f'   內容預覽: {msg.get("text", "")[:100]}...')

        if args.dry_run:
            print('   [DRY-RUN] 跳過更新')
            continue

        # 格式化並更新到 JIRA
        comment = format_slack_message_for_jira(msg)
        result = jira.add_comment(args.ticket, comment)

        if result:
            print(f'   ✅ 已更新到 JIRA')
        else:
            print(f'   ❌ 更新失敗')

    print(f'\n完成！查看 JIRA: https://jira.ftgaming.cc/browse/{args.ticket}')


if __name__ == '__main__':
    main()

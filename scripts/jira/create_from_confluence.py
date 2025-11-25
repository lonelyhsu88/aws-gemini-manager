#!/usr/bin/env python3
"""
從 Confluence Release Note 創建 JIRA Ticket

使用範例:
    python3 create_from_confluence.py --page-title "20251117_PROD_V1_Release_Note"
    python3 create_from_confluence.py --page-id 223143753
"""

import argparse
import sys
from jira_api import JiraAPI, ConfluenceAPI, JiraFormatter


def extract_release_info(page_content: dict) -> dict:
    """從 Confluence 頁面提取 Release 資訊"""
    title = page_content.get('title', '')
    space = page_content.get('space', {}).get('name', '')
    version = page_content.get('version', {}).get('number', '')

    # 提取頁面 URL
    base_url = "https://confluence.ftgaming.cc"
    page_url = f"{base_url}/display/{page_content.get('space', {}).get('key', '')}/{title}"

    return {
        'title': title,
        'space': space,
        'version': version,
        'url': page_url,
        'page_id': page_content.get('id')
    }


def format_jira_description(page_info: dict) -> str:
    """格式化 JIRA 描述"""
    fmt = JiraFormatter()

    description = (
        fmt.heading("Release 資訊", 2) +
        "\n" +
        fmt.unordered_list([
            f"{fmt.bold('Release Date')}: 2025/11/17",
            f"{fmt.bold('Confluence 頁面')}: {fmt.link(page_info['title'], page_info['url'])}",
            f"{fmt.bold('Space')}: {page_info['space']}",
            f"{fmt.bold('Version')}: {page_info['version']}"
        ]) +
        "\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("升級內容 & 修正問題", 2) +
        "\n" +
        fmt.heading("✅ Arcade 系列處理記憶體問題", 3) +
        "\n" +
        fmt.unordered_list([
            "已於 2025/11/17 Production 環境完成升級",
            "參考 " + fmt.link("Gemini 團隊同步會議記錄", "https://jira.ftgaming.cc/browse/OPS-813")
        ]) +
        "\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("升級項目", 2) +
        "\n" +
        fmt.heading("後端升級項目", 3) +
        "\n" +
        fmt.table(
            ['項目', 'Stage'],
            [
                ['arcade-forestteapartygame-stage', '134'],
                ['arcade-scratchcardgame-stage', '133'],
                ['rng-multiboomersgame-stage', '135']
            ]
        ) +
        "\n" +
        fmt.heading("前端升級項目", 3) +
        "\n待補充\n\n" +
        fmt.heading("Devops 升級項目", 3) +
        "\n無 (-)\n\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("資料庫作業", 2) +
        "\n" +
        fmt.heading("SQL 執行說明", 3) +
        "\n" +
        fmt.table(
            ['資料庫', '執行身份', '重啟要求'],
            [
                ['Bingo DB', 'bingo', '重開 center 和所有 game server'],
                ['Mgmt DB', 'mgmt', '重開 mgmtapi'],
                ['Cash DB', 'cash', '重開 mgmtapi'],
                ['Combined DB', 'migrateuser', '無'],
                ['Loyalty DB', 'loyalty', '無'],
                ['Hash DB', 'hash', '無'],
                ['Rng DB', 'rng', '無'],
                ['Crashseed DB', 'crashseed', '無']
            ]
        ) +
        "\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("防火牆開通", 2) +
        "\n" +
        fmt.heading("Gate 配置", 3) +
        "\n" +
        fmt.table(['Name', 'PORT'], [['待補充', '待補充']]) +
        "\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("商戶配置", 2) +
        "\n待補充\n\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("檢核表", 2) +
        "\n請參考 Confluence 頁面完整檢核表：\n" +
        fmt.link(page_info['title'], page_info['url']) +
        "\n\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("相關連結", 2) +
        "\n" +
        fmt.unordered_list([
            f"Confluence Release Note: {fmt.link(page_info['title'], page_info['url'])}",
            f"Gemini 團隊同步會議: {fmt.link('OPS-813', 'https://jira.ftgaming.cc/browse/OPS-813')}"
        ]) +
        "\n" +
        fmt.divider() +
        "\n" +
        fmt.heading("OPS 追蹤事項", 2) +
        "\n" +
        fmt.ordered_list([
            "確認 Arcade 系列記憶體問題已解決",
            "驗證後端服務升級成功",
            "檢查資料庫 SQL 執行狀態",
            "確認相關服務重啟完成",
            "監控 Production 環境穩定性"
        ])
    )

    return description


def create_jira_from_confluence(
    page_title: str = None,
    page_id: str = None,
    project: str = 'OPS',
    priority: str = 'High',
    assignee: str = 'lonely.h'
):
    """從 Confluence 頁面創建 JIRA ticket"""

    # 初始化 API
    confluence = ConfluenceAPI()
    jira = JiraAPI()

    # 搜尋或獲取頁面
    if page_id:
        print(f"📄 使用頁面 ID: {page_id}")
        page = confluence.get_page_content(page_id)
        if not page:
            print(f"❌ 找不到頁面 ID: {page_id}")
            return None
    elif page_title:
        print(f"🔍 搜尋 Confluence 頁面: {page_title}")
        pages = confluence.search_pages(f'title~"{page_title}"')
        if not pages:
            print(f"❌ 找不到頁面: {page_title}")
            return None
        page = confluence.get_page_content(pages[0]['id'])
    else:
        print("❌ 必須提供 --page-title 或 --page-id")
        return None

    # 提取資訊
    page_info = extract_release_info(page)
    print(f"✅ 找到頁面: {page_info['title']}")
    print(f"   Space: {page_info['space']}")
    print(f"   URL: {page_info['url']}\n")

    # 格式化描述
    description = format_jira_description(page_info)

    # 創建 JIRA ticket
    print(f"📤 創建 JIRA {project} ticket...")

    # 從頁面標題提取日期
    date_str = page_title.split('_')[0] if page_title else ''

    result = jira.create_issue(
        project=project,
        summary=f"{date_str} PROD 升級作業",
        description=description,
        issue_type='Task',
        priority=priority,
        assignee=assignee,
        labels=['release', 'production', 'arcade', 'memory-fix', date_str, 'gemini']
    )

    if result['success']:
        print(f"\n✅ JIRA Ticket 創建成功！")
        print(f"🎫 Ticket ID: {result['ticket_id']}")
        print(f"🔗 URL: {result['ticket_url']}")

        # 創建本地文檔
        create_local_documentation(result['ticket_id'], page_info, description)

        return result
    else:
        print(f"\n❌ 創建失敗")
        if 'error_messages' in result:
            for msg in result['error_messages']:
                print(f"   - {msg}")
        if 'errors' in result:
            for field, msg in result['errors'].items():
                print(f"   - {field}: {msg}")
        return None


def create_local_documentation(ticket_id: str, page_info: dict, description: str):
    """創建本地文檔"""
    import os

    doc_filename = f"JIRA_RELEASE_NOTE_{page_info['title'].split('_')[0]}.md"
    doc_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
        doc_filename
    )

    content = f"""# JIRA OPS Ticket - Production Release {page_info['title']}

**JIRA Ticket**: [{ticket_id}](https://jira.ftgaming.cc/browse/{ticket_id})
**Created**: {page_info.get('created_date', '2025-11-17')}
**Status**: Open
**來源**: [Confluence Release Note]({page_info['url']})

---

## Summary (標題)

```
{page_info['title']}
```

---

## Description (詳細描述)

{description}

---

## 相關連結

* Confluence Release Note: [{page_info['title']}]({page_info['url']})
* JIRA Ticket: [{ticket_id}](https://jira.ftgaming.cc/browse/{ticket_id})

---

## 文件歷史

- **{page_info.get('created_date', '2025-11-17')}**: 創建文檔，從 Confluence Release Note 提取內容並創建 JIRA ticket {ticket_id}
- **Confluence 頁面 ID**: {page_info['page_id']}
- **Confluence 版本**: {page_info['version']}
"""

    with open(doc_path, 'w') as f:
        f.write(content)

    print(f"\n📝 本地文檔已創建: {doc_filename}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='從 Confluence Release Note 創建 JIRA Ticket')
    parser.add_argument('--page-title', help='Confluence 頁面標題')
    parser.add_argument('--page-id', help='Confluence 頁面 ID')
    parser.add_argument('--project', default='OPS', help='JIRA 專案 (預設: OPS)')
    parser.add_argument('--priority', default='High', help='優先級 (預設: High)')
    parser.add_argument('--assignee', default='lonely.h', help='負責人 (預設: lonely.h)')

    args = parser.parse_args()

    if not args.page_title and not args.page_id:
        print("❌ 錯誤: 必須提供 --page-title 或 --page-id")
        parser.print_help()
        sys.exit(1)

    create_jira_from_confluence(
        page_title=args.page_title,
        page_id=args.page_id,
        project=args.project,
        priority=args.priority,
        assignee=args.assignee
    )

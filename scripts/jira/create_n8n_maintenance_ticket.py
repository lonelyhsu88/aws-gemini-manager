#!/usr/bin/env python3
"""
創建 JIRA OPS Ticket - n8n 主機維護作業記錄

記錄內容：
1. n8n 主機 OS 更新
2. n8n 版本升級評估（1.123.5 → 2.4.5）
3. 決策與原因
"""

import sys
import os
from datetime import datetime

# 添加 scripts/jira 目錄到 Python path
sys.path.insert(0, os.path.dirname(__file__))

from jira_api import JiraAPI, JiraFormatter


def create_n8n_maintenance_ticket():
    """創建 n8n 維護作業 JIRA ticket"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 獲取當前日期
    today = datetime.now().strftime('%Y-%m-%d')

    # 構建描述內容
    description = (
        fmt.heading("作業概述", 2) +
        "今日針對 n8n 主機（gemini-n8n-01）進行系統更新和版本升級評估作業。\n\n" +

        fmt.heading("主機資訊", 2) +
        fmt.unordered_list([
            fmt.bold("實例名稱:") + " gemini-n8n-01",
            fmt.bold("實例 ID:") + " i-06ff53ed9ffb2e1de",
            fmt.bold("公網 IP:") + " 16.162.121.174",
            fmt.bold("部署方式:") + " Docker Compose",
            fmt.bold("當前 n8n 版本:") + " 1.123.5",
            fmt.bold("資料庫:") + " PostgreSQL 16"
        ]) +
        "\n" +

        fmt.divider() +
        fmt.heading("執行作業", 2) +

        fmt.heading("1. OS 系統更新", 3) +
        fmt.unordered_list([
            "執行系統套件更新",
            "檢查安全性補丁",
            "驗證系統服務運行狀態"
        ]) +
        "\n" +

        fmt.heading("2. n8n 版本升級評估", 3) +
        fmt.table(
            ['項目', '內容'],
            [
                ['當前版本', '1.123.5'],
                ['最新版本', '2.4.5'],
                ['版本差距', '主要版本升級 (1.x → 2.x)'],
                ['評估結果', '維持現狀，定期監控']
            ]
        ) +
        "\n" +

        fmt.divider() +
        fmt.heading("評估結論", 2) +

        fmt.heading("不升級原因", 3) +
        fmt.ordered_list([
            fmt.bold("破壞性變更風險:") + " n8n 2.0 引入重大架構變更，可能影響現有工作流程",
            fmt.bold("數據庫遷移風險:") + " PostgreSQL schema 可能需要升級，需要完整備份計劃",
            fmt.bold("API 兼容性:") + " 外部整合的 API 可能改變，需要驗證",
            fmt.bold("當前版本穩定:") + " 1.123.5 為 2024年底版本，相對穩定且功能足夠"
        ]) +
        "\n" +

        fmt.heading("後續計劃", 3) +
        fmt.unordered_list([
            fmt.bold("定期檢查:") + " 每月第一個週一檢查安全更新",
            fmt.bold("小版本更新:") + " 每季度評估 1.x 系列的小版本更新",
            fmt.bold("主版本升級:") + " 等待 2.x 穩定 3-6 個月後再評估",
            fmt.bold("緊急升級條件:") + " 發現嚴重安全漏洞（CVE 高危）時立即升級"
        ]) +
        "\n" +

        fmt.divider() +
        fmt.heading("參考連結", 2) +
        fmt.unordered_list([
            "n8n GitHub Releases: " + fmt.link("releases", "https://github.com/n8n-io/n8n/releases"),
            "n8n Security Advisories: " + fmt.link("security", "https://github.com/n8n-io/n8n/security/advisories")
        ]) +
        "\n" +

        fmt.divider() +
        fmt.heading("執行時間", 2) +
        fmt.unordered_list([
            fmt.bold("執行日期:") + f" {today}",
            fmt.bold("執行人員:") + " lonely.h"
        ])
    )

    # 創建 JIRA issue
    print("正在創建 JIRA OPS ticket...")
    result = jira.create_issue(
        project='OPS',
        summary=f'n8n 主機維護作業 - OS 更新與版本評估 ({today})',
        description=description,
        issue_type='Task',
        priority='Medium',
        assignee='lonely.h',
        labels=['n8n', 'maintenance', 'version-assessment', 'os-update', today.replace('-', '')]
    )

    if result.get('success'):
        print(f"\n✅ JIRA Ticket 創建成功！")
        print(f"Ticket ID: {result['ticket_id']}")
        print(f"Ticket URL: {result['ticket_url']}")
        print(f"\n請前往以下連結查看：")
        print(f"  {result['ticket_url']}")
        return result
    else:
        print(f"\n❌ JIRA Ticket 創建失敗")
        print(f"錯誤訊息: {result.get('error_messages', result.get('errors', 'Unknown error'))}")
        print(f"\n詳細輸出:")
        print(result)
        return None


if __name__ == '__main__':
    create_n8n_maintenance_ticket()

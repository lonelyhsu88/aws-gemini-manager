#!/usr/bin/env python3
"""
創建 bingo-prd-replica1 Storage Optimization 事件的 JIRA OPS ticket
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jira_api import JiraAPI, JiraFormatter

def create_storage_optimization_ticket():
    """創建 storage optimization 事件 ticket"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # 構建詳細描述
    description = (
        fmt.heading("事件摘要", 2) +
        fmt.unordered_list([
            "事件時間: 2026-01-07 22:47 UTC (2026-01-08 06:47 GMT+8)",
            "實例: bingo-prd-replica1",
            "事件類型: RDS Storage Autoscaling",
            "當前狀態: storage-optimization",
            "區域: ap-east-1 (香港)"
        ]) +
        "\n" +
        fmt.heading("儲存容量變化", 2) +
        fmt.table(
            ['項目', '數值', '說明'],
            [
                ['擴展前容量', '~2750 GB', '觸發前容量'],
                ['擴展後容量', '2929 GB', '當前容量'],
                ['增加容量', '+179 GB', '單次擴展'],
                ['最大容量限制', '5000 GB', 'MaxAllocatedStorage'],
                ['剩餘擴展空間', '2071 GB', '可繼續擴展']
            ]
        ) +
        "\n" +
        fmt.heading("觸發原因分析", 2) +
        "RDS Storage Autoscaling 在以下條件下自動觸發:\n\n" +
        fmt.ordered_list([
            "可用空間不足 10% (當時約 286 GB / 2750 GB ≈ 10.4%)",
            "持續 5 分鐘以上的低空間狀態",
            "距離上次擴展至少 6 小時"
        ]) +
        "\n" +
        fmt.heading("可用空間趨勢", 2) +
        fmt.table(
            ['時間 (UTC)', '可用空間', '狀態'],
            [
                ['22:58 之前', '~286-323 GB', '觸發擴展'],
                ['22:58 之後', '~569 GB', '擴展完成 ⬆️']
            ]
        ) +
        "\n擴展後可用空間增加約 240-280 GB\n\n" +
        fmt.heading("Storage Optimization 狀態", 2) +
        fmt.bold("storage-optimization") + " 是 RDS 在完成儲存擴展後的正常狀態:\n\n" +
        fmt.unordered_list([
            "AWS 正在優化新增的儲存空間",
            "通常持續數小時到 24 小時",
            "期間實例仍然可以正常運作",
            "效能可能略有波動（通常不明顯）"
        ]) +
        "\n" +
        fmt.heading("Replica vs Primary 比較", 2) +
        fmt.table(
            ['實例', '當前容量', '狀態', '差異'],
            [
                ['bingo-prd (主實例)', '2750 GB', 'available', '-'],
                ['bingo-prd-replica1', '2929 GB', 'storage-optimization', '+179 GB']
            ]
        ) +
        "\n" +
        fmt.heading("事件時間線", 2) +
        fmt.code_block(
            "2026-01-07 22:47:14 UTC - 開始應用自動擴展修改\n" +
            "2026-01-07 22:49:36 UTC - 完成自動擴展修改\n" +
            "2026-01-07 22:58:00 UTC - 可用空間增加至 ~569 GB",
            "text"
        ) +
        "\n" +
        fmt.heading("建議與後續行動", 2) +
        fmt.ordered_list([
            "監控 storage-optimization 完成狀態（預計 24 小時內）",
            "檢查主實例 bingo-prd 儲存使用情況（目前 2750 GB，可能也接近擴展閾值）",
            "評估容量規劃：當前最大容量 5000 GB，如成長速度快需要調整",
            "考慮設定 CloudWatch 告警監控可用空間低於 15%"
        ]) +
        "\n" +
        fmt.heading("參考連結", 2) +
        fmt.unordered_list([
            fmt.link(
                "AWS RDS Console - bingo-prd-replica1",
                "https://console.aws.amazon.com/rds/home?region=ap-east-1#database:id=bingo-prd-replica1"
            ),
            fmt.link(
                "RDS Storage Autoscaling 文檔",
                "https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.StorageTypes.html#USER_PIOPS.Autoscaling"
            )
        ])
    )

    # 創建 ticket
    print("正在創建 JIRA OPS ticket...")
    result = jira.create_issue(
        project='OPS',
        summary='bingo-prd-replica1 RDS Storage Autoscaling 事件記錄',
        description=description,
        issue_type='Task',
        priority='Medium',
        labels=['rds', 'storage', 'autoscaling', 'bingo-prd-replica1', 'monitoring']
    )

    return result

if __name__ == '__main__':
    result = create_storage_optimization_ticket()

    if result.get('success'):
        print(f"\n✅ JIRA ticket 創建成功!")
        print(f"   Ticket ID: {result['ticket_id']}")
        print(f"   URL: {result['ticket_url']}")
    else:
        print(f"\n❌ JIRA ticket 創建失敗:")
        print(f"   錯誤: {result.get('error', result.get('errors', result.get('error_messages', 'Unknown error')))}")
        if 'raw_output' in result:
            print(f"   原始輸出: {result['raw_output'][:500]}")
        sys.exit(1)

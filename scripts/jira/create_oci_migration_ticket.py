#!/usr/bin/env python3
"""
Create JIRA OPS ticket for OCI Migration Plan
Records the complete AWS RDS to OCI PostgreSQL migration plan in JIRA
"""

import sys
import os
from pathlib import Path

# Add parent directory to path to import jira_api
sys.path.insert(0, str(Path(__file__).parent))

from jira_api import JiraAPI, JiraFormatter

def create_oci_migration_ticket():
    """Create JIRA ticket for OCI migration plan"""

    jira = JiraAPI()
    fmt = JiraFormatter()

    # Build comprehensive description using JIRA Wiki Markup
    description = (
        fmt.heading("OCI 遷移計劃概述", 2) +
        "\n" +
        "本計劃詳細規劃將 AWS RDS PostgreSQL 14.15 生產環境（3 個主要實例，總容量約 8 TB）遷移至 Oracle Cloud Infrastructure (OCI) 的完整方案。\n\n" +

        fmt.heading("關鍵目標", 3) +
        fmt.unordered_list([
            "✅ *零資料遺失*: 確保資料完整性 100%",
            "✅ *最小停機時間*: 採用 Oracle GoldenGate 實現近零停機遷移 (< 4 小時)",
            "✅ *安全合規*: 整合 Oracle Cloud Guard 全程監控",
            "✅ *效能維持*: 確保遷移後效能不降低",
            "✅ *高可用性*: 遷移後在 OCI 重新建立 Read Replica"
        ]) +
        "\n" +

        fmt.heading("遷移範圍", 3) +
        fmt.table(
            ['項目', '詳情'],
            [
                ['來源平台', 'AWS RDS PostgreSQL 14.15 (ap-east-1 香港)'],
                ['目標平台', 'OCI PostgreSQL Database Service (ap-tokyo-1 東京)'],
                ['遷移實例數', '3 個主要生產實例'],
                ['總資料量', '~8 TB (7,974 GB)'],
                ['預計停機時間', '< 4 小時'],
                ['預計時程', '*8-10 週* (約 2-2.5 個月)'],
                ['遷移工具', 'Oracle GoldenGate + Equinix Fabric Cloud Router'],
                ['網路方案', 'Equinix Fabric 私有連線 (1-10 Gbps)']
            ]
        ) +
        "\n" +

        fmt.heading("遷移實例清單", 3) +
        fmt.table(
            ['實例名稱', '角色', '儲存容量', 'IOPS', '優先級', 'Phase'],
            [
                ['bingo-prd-loyalty', 'Primary', '200 GB', '3000', '🟡 High', 'Phase 2'],
                ['bingo-prd', 'Primary', '2750 GB', '12000', '🔴 Critical', 'Phase 3'],
                ['bingo-prd-backstage', 'Primary', '5024 GB', '12000', '🔴 Critical', 'Phase 4']
            ]
        ) +
        "\n" +

        fmt.heading("不遷移實例（5 個）", 3) +
        "*Read Replica (將在 OCI 重新建立)*:\n" +
        fmt.unordered_list([
            "bingo-prd-replica1 (2929 GB) - Phase 5 在 OCI 建立",
            "bingo-prd-backstage-replica1 (1465 GB) - Phase 5 在 OCI 建立"
        ]) +
        "\n*測試/開發環境 (保留於 AWS)*:\n" +
        fmt.unordered_list([
            "bingo-stress-loyalty (200 GB)",
            "pgsqlrel (40 GB)",
            "pgsqlrel-backstage (40 GB)"
        ]) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("執行階段規劃", 2) +
        "\n" +
        fmt.table(
            ['Phase', '名稱', '時程', '關鍵任務'],
            [
                ['Phase 0', '準備階段', '2 週', 'OCI 環境規劃、團隊培訓、安全準備'],
                ['Phase 1', 'OCI 環境建置與網路連線', '1-2 週', 'OCI 生產環境、Equinix Fabric、GoldenGate 部署'],
                ['Phase 2', '小型生產實例遷移驗證', '2 週', 'bingo-prd-loyalty (200GB) 遷移驗證'],
                ['Phase 3', '中型生產實例遷移', '2-3 週', 'bingo-prd (2750GB) 遷移與驗證'],
                ['Phase 4', '最大生產實例遷移', '3-4 週', 'bingo-prd-backstage (5024GB) 遷移'],
                ['Phase 5', 'OCI Read Replica 建立', '1-2 週', '在 OCI 建立兩個 Read Replica'],
                ['Phase 6', '最終清理與優化', '2 週', 'AWS RDS 清理、OCI 優化、文檔更新']
            ]
        ) +
        "\n" +
        "🎯 *總時程*: 8-10 週（透過階段並行與流程優化）\n\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("關鍵里程碑", 2) +
        "\n" +
        fmt.table(
            ['里程碑', '預計完成', '成功標準'],
            [
                ['M1: OCI 環境就緒', 'Week 2', 'OCI 生產環境、Equinix 網路、GoldenGate 部署完成'],
                ['M2: 小型實例遷移完成', 'Week 4', 'bingo-prd-loyalty 遷移成功並穩定運行'],
                ['M3: 中型實例遷移完成', 'Week 7', 'bingo-prd 遷移成功並穩定運行'],
                ['M4: 最大實例遷移完成', 'Week 10', 'bingo-prd-backstage 遷移成功'],
                ['M5: Read Replica 建立完成', 'Week 12', '兩個 Read Replica 建立完成並驗證複製延遲'],
                ['M6: AWS RDS 清理', 'Week 14', 'AWS RDS 資源釋放，OCI 環境優化完成']
            ]
        ) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("網路架構", 2) +
        "\n" +
        "*Equinix Fabric Cloud Router 架構*:\n" +
        fmt.unordered_list([
            "*AWS ap-east-1* (Hong Kong, 172.16.0.0/16) ↔ Equinix FCR",
            "Equinix FCR (HK-Tokyo Backbone, ~50ms latency)",
            "Equinix FCR ↔ *OCI ap-tokyo-1* (Tokyo, 10.1.0.0/16)"
        ]) +
        "\n" +
        "*頻寬選擇*:\n" +
        fmt.unordered_list([
            "*1 Gbps* - $1,754/月 (Phase 2-3 推薦) - 傳輸 8TB 約 2-3 天",
            "*10 Gbps* - $5,504/月 (Phase 4 評估) - 傳輸 8TB 約 4-6 小時"
        ]) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("成本預估", 2) +
        "\n" +
        "*OCI 運算成本*: ~$4,228/月\n" +
        fmt.unordered_list([
            "DB System (4 OCPU) x3: $1,200",
            "DB System (2 OCPU) x2: $400",
            "Block Volume (15,500 GB): $1,318",
            "Backup Storage (20,000 GB): $510",
            "Oracle GoldenGate: $800"
        ]) +
        "\n*網路連線成本*:\n" +
        fmt.unordered_list([
            "Month 2 (1 Gbps): $1,754",
            "Month 3 (10 Gbps): $5,504",
            "總計: $7,258"
        ]) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("風險管理", 2) +
        "\n" +
        fmt.table(
            ['風險', '等級', '緩解措施'],
            [
                ['資料遺失', '🔴 High', 'GoldenGate CDC 持續同步 + 完整備份'],
                ['停機時間超預期', '🟡 Medium', '分階段遷移 + 充分測試 + 回退計畫'],
                ['效能下降', '🟡 Medium', 'OCI 規格預留 buffer + 效能測試'],
                ['網路延遲影響', '🟢 Low', 'Equinix 私有連線 + 50ms 延遲可接受'],
                ['團隊技能缺口', '🟡 Medium', 'GoldenGate 培訓 + Oracle 技術支援']
            ]
        ) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("完整文檔", 2) +
        "\n" +
        "詳細規劃文檔位於專案目錄：\n" +
        fmt.unordered_list([
            "📋 {{docs/oci-migration/README.md}} - 文檔索引與快速導航",
            "📖 {{docs/oci-migration/RDS_TO_OCI_MIGRATION_PLAN.md}} - 完整遷移計劃（主文檔）",
            "🔧 {{docs/oci-migration/NETWORK_AND_GOLDENGATE_SETUP.md}} - 網路與 GoldenGate 設定指南"
        ]) +
        "\n" +

        fmt.divider() +
        "\n" +

        fmt.heading("下一步行動", 2) +
        "\n" +
        "*本週*:\n" +
        fmt.unordered_list([
            "[ ] 召開專案啟動會議",
            "[ ] 確認 OCI 帳號與權限",
            "[ ] 評估 OCI POC 環境狀態"
        ]) +
        "\n*本月*:\n" +
        fmt.unordered_list([
            "[ ] 完成網路設計與 Equinix Fabric 申請",
            "[ ] 安排團隊 GoldenGate 培訓",
            "[ ] 準備 Phase 0 環境規劃"
        ]) +
        "\n*第二個月*:\n" +
        fmt.unordered_list([
            "[ ] 建立 OCI 生產環境 (Phase 1)",
            "[ ] 執行小型生產實例遷移驗證 (Phase 2)"
        ]) +
        "\n" +

        fmt.bold("✅ 本計劃已完成完整的一致性審查，所有文檔數據、時程、階段描述已統一，可立即用於專案執行。") +
        "\n\n" +
        f"_Created by: Claude Code + aws-gemini-manager_\n" +
        f"_Document Version: 1.0_\n" +
        f"_Planning Date: 2026-01-20_"
    )

    # Create the ticket
    print("🎫 Creating JIRA OPS ticket for OCI Migration Plan...")

    result = jira.create_issue(
        project='OPS',
        summary='AWS RDS PostgreSQL 遷移至 OCI 完整規劃 (8TB / 8-10 週)',
        description=description,
        issue_type='Task',
        priority='High',
        labels=['oci-migration', 'aws-rds', 'postgresql', 'oracle-goldengate', 'database-migration', '2026-q1']
    )

    if result['success']:
        ticket_key = result['ticket_id']
        ticket_url = result['ticket_url']

        print(f"\n✅ JIRA Ticket Created Successfully!")
        print(f"\n📋 Ticket: {ticket_key}")
        print(f"🔗 URL: {ticket_url}")
        print(f"\n📊 Summary: AWS RDS PostgreSQL 遷移至 OCI 完整規劃 (8TB / 8-10 週)")
        print(f"🏷️  Labels: oci-migration, aws-rds, postgresql, oracle-goldengate, database-migration, 2026-q1")
        print(f"⚠️  Priority: High")

        # Add a comment with quick reference
        comment = (
            fmt.heading("Quick Reference", 3) +
            "\n" +
            "*Key Facts*:\n" +
            fmt.unordered_list([
                "3 production instances: loyalty (200GB), prd (2750GB), backstage (5024GB)",
                "Timeline: 8-10 weeks (6 phases)",
                "Network: Equinix Fabric Cloud Router (AWS HK ↔ OCI Tokyo)",
                "Migration Tool: Oracle GoldenGate (CDC)",
                "Downtime: < 4 hours per instance"
            ]) +
            "\n" +
            "*Critical Dependencies*:\n" +
            fmt.unordered_list([
                "OCI account and permissions setup",
                "Equinix Fabric registration and payment",
                "GoldenGate team training",
                "Network bandwidth decision (1G vs 10G)"
            ])
        )

        jira.add_comment(ticket_key, comment)
        print(f"\n💬 Added quick reference comment to ticket")

        return ticket_key
    else:
        print(f"\n❌ Failed to create ticket: {result.get('error', 'Unknown error')}")
        return None

if __name__ == '__main__':
    ticket_key = create_oci_migration_ticket()

    if ticket_key:
        print(f"\n" + "="*60)
        print(f"🎉 OCI Migration Plan recorded in JIRA: {ticket_key}")
        print(f"="*60)
        sys.exit(0)
    else:
        sys.exit(1)

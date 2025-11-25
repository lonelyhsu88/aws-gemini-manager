#!/usr/bin/env python3
"""
創建 JIRA ticket 記錄 Docker 日誌清理部署任務
"""

import sys
import json
sys.path.insert(0, '/Users/lonelyhsu/gemini/claude-project/aws-gemini-manager/scripts/jira')

from jira_api import JiraAPI, JiraFormatter

def main():
    # 初始化
    jira = JiraAPI()
    fmt = JiraFormatter()

    # 準備描述內容
    description = fmt.heading("任務概述", 2)
    description += "在 Zabbix Server (gemini-monitor-01) 上部署 Docker 容器日誌自動清理機制，防止磁碟空間被容器日誌佔滿。\n\n"

    description += fmt.heading("部署內容", 2)
    description += fmt.unordered_list([
        "Docker Daemon 日誌輪替配置 (max-size: 10MB, max-file: 3)",
        "自動清理腳本部署到 /home/ec2-user/toolkits/",
        "Cron Job 設定：每天凌晨 4 點自動執行清理",
        "清理閾值：大於 100MB 的容器日誌"
    ])
    description += "\n"

    description += fmt.heading("部署結果", 2)
    description += fmt.unordered_list([
        "✅ 腳本已安裝：/home/ec2-user/toolkits/docker-log-cleanup.sh",
        "✅ Cron Job 已設定：每天凌晨 4 點執行 (ec2-user)",
        "✅ Docker daemon 配置已更新",
        "✅ 日誌目錄已創建：/home/ec2-user/toolkits/logs/",
        "✅ 測試執行成功，無權限錯誤"
    ])
    description += "\n"

    description += fmt.heading("系統狀態", 2)
    description += fmt.table(
        ['項目', '當前狀態'],
        [
            ['磁碟使用率', '20% (健康)'],
            ['可用空間', '49 GB / 60 GB'],
            ['容器日誌', '無大於 100MB 的日誌'],
            ['運行容器', 'Grafana, Zabbix Server, Zabbix Web, MariaDB']
        ]
    )
    description += "\n"

    description += fmt.heading("部署檔案", 2)
    description += fmt.code_block("""
/home/ec2-user/toolkits/
├── docker-log-cleanup.sh (5.5K)
└── logs/
    ├── docker-log-cleanup.log
    └── docker-log-cleanup-cron.log

/etc/docker/daemon.json
""", "")
    description += "\n"

    description += fmt.heading("維護命令", 2)
    description += fmt.code_block("""
# 查看清理日誌
tail -f /home/ec2-user/toolkits/logs/docker-log-cleanup.log

# 手動執行清理
sudo /home/ec2-user/toolkits/docker-log-cleanup.sh

# 檢查 Cron 設定
sudo -u ec2-user crontab -l

# 檢查磁碟使用
df -h /
""", "bash")
    description += "\n"

    description += fmt.heading("注意事項", 2)
    description += fmt.bold("⚠️ 重要提醒") + "\n"
    description += fmt.unordered_list([
        "現有容器需要重啟才會使用新的日誌輪替設定",
        "建議在維護時段執行：sudo systemctl restart docker",
        "下次自動執行時間：2025-11-26 04:00 (每天凌晨 4 點)"
    ])
    description += "\n"

    description += fmt.heading("相關文檔", 2)
    description += fmt.unordered_list([
        "DEPLOY_GUIDE.md - 部署指南",
        "DOCKER_GRAFANA_GUIDE.md - 快速指南",
        "DOCKER_LOG_ROTATION_GUIDE.md - 完整文檔"
    ])
    description += "\n"

    description += fmt.divider()
    description += "\n🤖 Generated with [Claude Code](https://claude.com/claude-code)\n"
    description += "\nCo-Authored-By: Claude <noreply@anthropic.com>"

    # 創建 JIRA ticket
    print("正在創建 JIRA ticket...")
    result = jira.create_issue(
        project='OPS',
        summary='Zabbix Server Docker 日誌自動清理機制部署',
        description=description,
        issue_type='Task',
        priority='Medium',
        labels=['docker', 'zabbix', 'automation', 'disk-management', '20251125']
    )

    print(json.dumps(result, indent=2, ensure_ascii=False))

    if result.get('success'):
        print(f"\n✅ JIRA ticket 創建成功！")
        print(f"Ticket ID: {result['ticket_id']}")
        print(f"URL: {result['ticket_url']}")
    else:
        print(f"\n❌ 創建失敗：{result}")
        sys.exit(1)

if __name__ == '__main__':
    main()

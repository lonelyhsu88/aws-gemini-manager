#!/usr/bin/env python3
"""
JIRA/Confluence/Slack API Integration Library

提供可重用的 API 函數，用於與自架 JIRA、Confluence 和 Slack 整合。

使用範例:
    from jira_api import JiraAPI, ConfluenceAPI, SlackAPI

    jira = JiraAPI()
    ticket = jira.create_issue(
        project='OPS',
        summary='測試 ticket',
        description='這是測試',
        issue_type='Task',
        priority='Medium'
    )
"""

import json
import subprocess
import os
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta


class APIConfig:
    """API 配置管理"""

    # 從 daily-report/.env 讀取的配置
    JIRA_URL = "https://jira.ftgaming.cc"
    CONFLUENCE_URL = "https://confluence.ftgaming.cc"

    # Token 應該從環境變數或 daily-report/.env 讀取
    @staticmethod
    def get_jira_token() -> str:
        """從 daily-report/.env 獲取 JIRA token"""
        env_path = "/Users/lonelyhsu/gemini/claude-project/daily-report/.env"
        token = os.getenv('JIRA_API_TOKEN')
        if not token and os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    if line.startswith('JIRA_API_TOKEN='):
                        token = line.split('=', 1)[1].strip()
                        break
        return token or ""  # Set JIRA_API_TOKEN environment variable

    @staticmethod
    def get_confluence_token() -> str:
        """從 daily-report/.env 獲取 Confluence token"""
        env_path = "/Users/lonelyhsu/gemini/claude-project/daily-report/.env"
        token = os.getenv('CONFLUENCE_API_TOKEN')
        if not token and os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    if line.startswith('CONFLUENCE_API_TOKEN='):
                        token = line.split('=', 1)[1].strip()
                        break
        return token or ""  # Set CONFLUENCE_API_TOKEN environment variable

    @staticmethod
    def get_slack_token() -> str:
        """從 daily-report/.env 獲取 Slack token"""
        env_path = "/Users/lonelyhsu/gemini/claude-project/daily-report/.env"
        token = os.getenv('SLACK_BOT_TOKEN')
        if not token and os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    if line.startswith('SLACK_BOT_TOKEN='):
                        token = line.split('=', 1)[1].strip().strip('"')
                        break
        return token


class JiraAPI:
    """JIRA REST API v2 客戶端"""

    def __init__(self):
        self.base_url = APIConfig.JIRA_URL
        self.token = APIConfig.get_jira_token()
        self.headers = {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }

    def create_issue(
        self,
        project: str,
        summary: str,
        description: str,
        issue_type: str = 'Task',
        priority: str = 'Medium',
        assignee: str = 'lonely.h',
        labels: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        創建 JIRA issue

        Args:
            project: 專案 key (如: OPS)
            summary: 標題
            description: 描述 (JIRA Wiki Markup 格式)
            issue_type: 類型 (Task/Bug/Story)
            priority: 優先級 (Highest/High/Medium/Low/Lowest)
            assignee: 負責人 username
            labels: 標籤列表

        Returns:
            創建成功的 issue 資訊 (包含 key, id, self)
        """
        payload = {
            "fields": {
                "project": {"key": project},
                "issuetype": {"name": issue_type},
                "summary": summary,
                "description": description,
                "priority": {"name": priority},
                "assignee": {"name": assignee}
            }
        }

        if labels:
            payload["fields"]["labels"] = labels

        result = subprocess.run([
            'curl', '-X', 'POST',
            f'{self.base_url}/rest/api/2/issue',
            '-H', 'Content-Type: application/json',
            '-H', 'Accept: application/json',
            '-H', f'Authorization: Bearer {self.token}',
            '-d', json.dumps(payload),
            '-s'
        ], capture_output=True, text=True)

        try:
            response = json.loads(result.stdout)
            if 'key' in response:
                return {
                    'success': True,
                    'ticket_id': response['key'],
                    'ticket_url': f"{self.base_url}/browse/{response['key']}",
                    'raw_response': response
                }
            else:
                return {
                    'success': False,
                    'errors': response.get('errors', {}),
                    'error_messages': response.get('errorMessages', []),
                    'raw_response': response
                }
        except json.JSONDecodeError as e:
            return {
                'success': False,
                'error': f'JSON decode error: {e}',
                'raw_output': result.stdout[:500]
            }

    def update_issue(
        self,
        ticket_id: str,
        summary: Optional[str] = None,
        description: Optional[str] = None,
        priority: Optional[str] = None,
        assignee: Optional[str] = None,
        labels: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        更新 JIRA issue

        Args:
            ticket_id: Ticket ID (如: OPS-814)
            summary: 新標題 (可選)
            description: 新描述 (可選)
            priority: 新優先級 (可選)
            assignee: 新負責人 (可選)
            labels: 新標籤列表 (可選)

        Returns:
            更新結果
        """
        fields = {}

        if summary:
            fields["summary"] = summary
        if description:
            fields["description"] = description
        if priority:
            fields["priority"] = {"name": priority}
        if assignee:
            fields["assignee"] = {"name": assignee}
        if labels is not None:
            fields["labels"] = labels

        if not fields:
            return {'success': False, 'error': 'No fields to update'}

        payload = {"fields": fields}

        result = subprocess.run([
            'curl', '-X', 'PUT',
            f'{self.base_url}/rest/api/2/issue/{ticket_id}',
            '-H', 'Content-Type: application/json',
            '-H', 'Accept: application/json',
            '-H', f'Authorization: Bearer {self.token}',
            '-d', json.dumps(payload),
            '-w', '\nHTTP_STATUS:%{http_code}',
            '-s'
        ], capture_output=True, text=True)

        # 檢查 HTTP 狀態碼
        if 'HTTP_STATUS:204' in result.stdout or 'HTTP_STATUS:200' in result.stdout:
            return {
                'success': True,
                'ticket_id': ticket_id,
                'ticket_url': f"{self.base_url}/browse/{ticket_id}"
            }
        else:
            return {
                'success': False,
                'raw_output': result.stdout
            }

    def add_comment(self, ticket_id: str, comment: str) -> Dict[str, Any]:
        """
        添加評論到 JIRA issue

        Args:
            ticket_id: Ticket ID
            comment: 評論內容 (JIRA Wiki Markup)

        Returns:
            添加結果
        """
        payload = {"body": comment}

        result = subprocess.run([
            'curl', '-X', 'POST',
            f'{self.base_url}/rest/api/2/issue/{ticket_id}/comment',
            '-H', 'Content-Type: application/json',
            '-H', 'Accept: application/json',
            '-H', f'Authorization: Bearer {self.token}',
            '-d', json.dumps(payload),
            '-s'
        ], capture_output=True, text=True)

        try:
            response = json.loads(result.stdout)
            if 'id' in response:
                return {'success': True, 'comment_id': response['id']}
            else:
                return {'success': False, 'raw_response': response}
        except json.JSONDecodeError:
            return {'success': False, 'raw_output': result.stdout[:500]}


class ConfluenceAPI:
    """Confluence REST API 客戶端"""

    def __init__(self):
        self.base_url = APIConfig.CONFLUENCE_URL
        self.token = APIConfig.get_confluence_token()
        self.headers = {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }

    def search_pages(self, cql: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        使用 CQL 搜尋 Confluence 頁面

        Args:
            cql: Confluence Query Language (如: 'title~"20251117"')
            limit: 結果數量限制

        Returns:
            搜尋結果列表
        """
        result = subprocess.run([
            'curl', '-G',
            f'{self.base_url}/rest/api/content/search',
            '-H', f'Authorization: Bearer {self.token}',
            '-H', 'Accept: application/json',
            '--data-urlencode', f'cql={cql}',
            '--data-urlencode', f'limit={limit}',
            '-s'
        ], capture_output=True, text=True)

        try:
            response = json.loads(result.stdout)
            return response.get('results', [])
        except json.JSONDecodeError:
            return []

    def get_page_content(
        self,
        page_id: str,
        expand: str = 'body.storage,version,space,history'
    ) -> Optional[Dict[str, Any]]:
        """
        獲取 Confluence 頁面完整內容

        Args:
            page_id: 頁面 ID
            expand: 要展開的欄位 (逗號分隔)

        Returns:
            頁面內容
        """
        result = subprocess.run([
            'curl', '-G',
            f'{self.base_url}/rest/api/content/{page_id}',
            '-H', f'Authorization: Bearer {self.token}',
            '-H', 'Accept: application/json',
            '--data-urlencode', f'expand={expand}',
            '-s'
        ], capture_output=True, text=True)

        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None


class SlackAPI:
    """Slack API 客戶端"""

    # 常用頻道 ID 映射
    CHANNEL_MAP = {
        'gemini-專案討論': 'C07K81AM9EE',
        'ops-alerts': 'C01234567',  # 範例
    }

    def __init__(self):
        self.token = APIConfig.get_slack_token()
        self.headers = {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        }

    def get_channel_id(self, channel_name: str) -> Optional[str]:
        """獲取頻道 ID"""
        return self.CHANNEL_MAP.get(channel_name)

    def get_channel_history(
        self,
        channel_id: str,
        limit: int = 100,
        days_back: int = 7
    ) -> List[Dict[str, Any]]:
        """
        獲取頻道歷史訊息

        Args:
            channel_id: 頻道 ID
            limit: 訊息數量限制
            days_back: 往前搜尋天數

        Returns:
            訊息列表
        """
        oldest_ts = str((datetime.now() - timedelta(days=days_back)).timestamp())

        result = subprocess.run([
            'curl', '-G',
            'https://slack.com/api/conversations.history',
            '-H', f'Authorization: Bearer {self.token}',
            '--data-urlencode', f'channel={channel_id}',
            '--data-urlencode', f'limit={limit}',
            '--data-urlencode', f'oldest={oldest_ts}',
            '-s'
        ], capture_output=True, text=True)

        try:
            response = json.loads(result.stdout)
            if response.get('ok'):
                return response.get('messages', [])
            else:
                print(f"Slack API error: {response.get('error')}")
                return []
        except json.JSONDecodeError:
            return []

    def get_user_info(self, user_id: str) -> Optional[Dict[str, Any]]:
        """獲取用戶資訊"""
        result = subprocess.run([
            'curl', '-G',
            'https://slack.com/api/users.info',
            '-H', f'Authorization: Bearer {self.token}',
            '--data-urlencode', f'user={user_id}',
            '-s'
        ], capture_output=True, text=True)

        try:
            response = json.loads(result.stdout)
            if response.get('ok'):
                return response.get('user')
            return None
        except json.JSONDecodeError:
            return None


class JiraFormatter:
    """JIRA Wiki Markup 格式化工具"""

    @staticmethod
    def heading(text: str, level: int = 2) -> str:
        """標題"""
        return f"h{level}. {text}\n"

    @staticmethod
    def divider() -> str:
        """分隔線"""
        return "----\n"

    @staticmethod
    def link(text: str, url: str) -> str:
        """連結"""
        return f"[{text}|{url}]"

    @staticmethod
    def bold(text: str) -> str:
        """粗體"""
        return f"*{text}*"

    @staticmethod
    def italic(text: str) -> str:
        """斜體"""
        return f"_{text}_"

    @staticmethod
    def ordered_list(items: List[str]) -> str:
        """有序列表"""
        return '\n'.join([f"# {item}" for item in items]) + '\n'

    @staticmethod
    def unordered_list(items: List[str]) -> str:
        """無序列表"""
        return '\n'.join([f"* {item}" for item in items]) + '\n'

    @staticmethod
    def table(headers: List[str], rows: List[List[str]]) -> str:
        """表格"""
        header_row = '|| ' + ' || '.join(headers) + ' ||\n'
        data_rows = '\n'.join(['| ' + ' | '.join(row) + ' |' for row in rows])
        return header_row + data_rows + '\n'

    @staticmethod
    def code_block(code: str, language: str = '') -> str:
        """程式碼區塊"""
        lang = f":{language}" if language else ""
        return f"{{code{lang}}}\n{code}\n{{code}}\n"


# 使用範例
if __name__ == '__main__':
    # JIRA 範例
    jira = JiraAPI()

    # 創建 issue
    result = jira.create_issue(
        project='OPS',
        summary='測試 ticket',
        description='這是測試描述\n\nh2. 測試標題\n\n* 測試項目 1\n* 測試項目 2',
        priority='Low',
        labels=['test', 'automation']
    )
    print(f"JIRA 創建結果: {result}")

    # Confluence 範例
    confluence = ConfluenceAPI()
    pages = confluence.search_pages('title~"20251117"')
    print(f"找到 {len(pages)} 個頁面")

    # Slack 範例
    slack = SlackAPI()
    channel_id = slack.get_channel_id('gemini-專案討論')
    if channel_id:
        messages = slack.get_channel_history(channel_id, limit=10)
        print(f"找到 {len(messages)} 則訊息")

    # 格式化工具範例
    formatter = JiraFormatter()
    description = (
        formatter.heading("Release 資訊", 2) +
        formatter.unordered_list(["Release Date: 2025/11/17", "Environment: Production"]) +
        formatter.divider() +
        formatter.heading("升級項目", 2) +
        formatter.table(
            ['服務名稱', 'Stage'],
            [['arcade-game', '134'], ['scratch-game', '133']]
        )
    )
    print(description)

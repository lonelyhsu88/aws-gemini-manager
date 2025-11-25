# JIRA Integration Quick Reference

## 🚀 快速開始

### 從 Confluence 創建 JIRA

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager

python3 scripts/jira/create_from_confluence.py \
  --page-title "20251117_PROD_V1_Release_Note"
```

### 更新 JIRA Ticket

```bash
# 更新標題
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --summary "新的標題"

# 更新優先級並添加評論
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --priority High \
  --comment "升級已完成"
```

---

## 🔑 認證配置

### Token 位置

所有 API tokens 存放在:
```
/Users/lonelyhsu/gemini/claude-project/daily-report/.env
```

### 環境變數

```bash
# JIRA Token (Self-hosted Server/Data Center)
JIRA_API_TOKEN=your_jira_api_token_here

# Confluence Token (Self-hosted Server/Data Center)
CONFLUENCE_API_TOKEN=your_confluence_api_token_here

# Slack Bot Token
SLACK_BOT_TOKEN=xoxb-...
```

### API 端點

```python
JIRA_URL = "https://jira.ftgaming.cc"
CONFLUENCE_URL = "https://confluence.ftgaming.cc"
```

---

## 📋 常用操作

### 1. 從 Confluence Release Note 創建 JIRA

**場景**: Production 升級、Release tracking

```bash
python3 scripts/jira/create_from_confluence.py \
  --page-title "YYYYMMDD_PROD_V1_Release_Note" \
  --project OPS \
  --priority High \
  --assignee lonely.h
```

**或使用頁面 ID**:
```bash
python3 scripts/jira/create_from_confluence.py \
  --page-id 223143753 \
  --project OPS
```

### 2. 更新 JIRA Ticket 標題

```bash
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --summary "20251117 PROD 升級作業"
```

### 3. 添加評論

```bash
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --comment "升級已於 2025-11-17 15:00 完成"
```

### 4. 更新多個欄位

```bash
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --summary "新標題" \
  --priority High \
  --labels "release,production,completed" \
  --comment "所有項目已完成"
```

---

## 📝 Python API 使用

### 基本範例

```python
from jira_api import JiraAPI, ConfluenceAPI, JiraFormatter

# 初始化 API
jira = JiraAPI()
confluence = ConfluenceAPI()
fmt = JiraFormatter()

# 創建 JIRA ticket
result = jira.create_issue(
    project='OPS',
    summary='20251117 PROD 升級作業',
    description='Release 說明...',
    priority='High',
    labels=['release', 'production']
)

if result['success']:
    print(f"Created: {result['ticket_url']}")
```

### 搜尋 Confluence 頁面

```python
confluence = ConfluenceAPI()

# 使用 CQL 搜尋
pages = confluence.search_pages('title~"20251117"')

for page in pages:
    print(f"{page['title']} - {page['id']}")
```

### 格式化 JIRA 描述

```python
fmt = JiraFormatter()

description = (
    fmt.heading("Release 資訊", 2) +
    fmt.unordered_list([
        "Release Date: 2025/11/17",
        "Environment: Production"
    ]) +
    fmt.divider() +
    fmt.heading("升級項目", 2) +
    fmt.table(
        ['服務名稱', 'Stage'],
        [['arcade-game', '134'], ['scratch-game', '133']]
    )
)
```

---

## 🎯 JIRA Field 標準

### Project: OPS

### Issue Type
- **Task** - 一般任務、會議記錄、升級作業
- **Bug** - 系統問題、故障修復
- **Story** - 新功能開發

### Priority
- **Highest** - 嚴重 Production 問題
- **High** - Production 升級、重要修復
- **Medium** - 會議記錄、例行任務
- **Low** - 文檔更新、優化建議

### 常用 Labels

**系統相關**:
```
gemini, arcade, bingo, hash, rng
eks-prd, eks-stage
production, staging
```

**類型相關**:
```
release, upgrade, deployment
meeting-notes, investigation
performance, memory-fix, optimization
```

**日期標記**:
```
20251117, 2025-11
```

### Assignee
```
lonely.h      # DevOps/Infrastructure
PM-Ryan       # Product Manager
BE-Jack       # Backend Development
```

---

## 📁 文檔同步

### 命名規範

```
JIRA_{主題}_{日期}.md
```

### 範例

```markdown
JIRA_STEAMPUNK2_RESTART_ISSUE.md       (OPS-812)
JIRA_GEMINI_MEETING_20251117.md        (OPS-813)
JIRA_RELEASE_NOTE_20251117.md          (OPS-814)
```

### 文檔模板

```markdown
# JIRA OPS Ticket - {標題}

**JIRA Ticket**: [OPS-XXX](https://jira.ftgaming.cc/browse/OPS-XXX)
**Created**: YYYY-MM-DD
**Status**: Open/In Progress/Done
**來源**: [Confluence/Slack/...]

---

## Summary (標題)

```
{標題內容}
```

---

## Description (詳細描述)

{詳細內容...}

---

## 相關連結

* JIRA Ticket: [OPS-XXX](https://jira.ftgaming.cc/browse/OPS-XXX)
* Confluence: [...]
```

---

## 🔧 故障排除

### 問題 1: 401 Unauthorized

**原因**: 使用了錯誤的認證方式

**解決**:
- ✅ 使用 Bearer Token: `Authorization: Bearer {token}`
- ❌ 不要使用 Basic Auth

### 問題 2: Field 不支援

**錯誤訊息**:
```
"environment": "Field 'environment' cannot be set..."
```

**解決**: 移除該 field，改用 labels

### 問題 3: Confluence 頁面找不到

**原因**: CQL 查詢語法錯誤

**正確範例**:
```python
pages = confluence.search_pages('title~"20251117"')
```

---

## 📚 相關資源

### 文檔
- **完整指南**: `scripts/jira/README.md`
- **API 函數庫**: `scripts/jira/jira_api.py`
- **CLAUDE.md**: 專案整合說明

### 範例 Tickets
- [OPS-812](https://jira.ftgaming.cc/browse/OPS-812) - Steampunk2 重啟問題
- [OPS-813](https://jira.ftgaming.cc/browse/OPS-813) - Gemini 團隊同步會議
- [OPS-814](https://jira.ftgaming.cc/browse/OPS-814) - 20251117 PROD 升級作業

### API 文檔
- [JIRA REST API v2](https://docs.atlassian.com/software/jira/docs/api/REST/latest/)
- [Confluence REST API](https://docs.atlassian.com/ConfluenceServer/rest/latest/)

---

**Last Updated**: 2025-11-17
**Maintainer**: lonely.h

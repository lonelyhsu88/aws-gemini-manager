# JIRA Integration Guide

## 概述

本指南記錄了與自架 JIRA Server/Confluence Server 整合的完整流程和方法。

## 🔑 認證方式

### 重要發現

**Self-hosted JIRA/Confluence 使用 Bearer Token 認證**（與 Cloud 版本不同）

```python
headers = {
    'Authorization': f'Bearer {api_token}',
    'Content-Type': 'application/json',
    'Accept': 'application/json'
}
```

### Token 來源

從 `daily-report` 專案的 `.env` 文件獲取：

```bash
# JIRA Token
JIRA_API_TOKEN=your_jira_api_token_here

# Confluence Token
CONFLUENCE_API_TOKEN=your_confluence_api_token_here
```

**路徑**: `/Users/lonelyhsu/gemini/claude-project/daily-report/.env`

### 錯誤認證方式 ❌

```python
# ❌ Basic Auth (僅適用於 Cloud 版本)
auth = base64.b64encode(f'{email}:{token}'.encode()).decode()
headers = {'Authorization': f'Basic {auth}'}
```

## 🌐 API 端點

### JIRA REST API v2

```
Base URL: https://jira.ftgaming.cc/rest/api/2
```

**常用端點**:
- 創建 Issue: `POST /issue`
- 更新 Issue: `PUT /issue/{issueIdOrKey}`
- 獲取 Issue: `GET /issue/{issueIdOrKey}`
- 搜尋 Issue: `POST /search`

### Confluence REST API

```
Base URL: https://confluence.ftgaming.cc/rest/api
```

**常用端點**:
- 搜尋頁面: `GET /content/search?cql={query}`
- 獲取頁面: `GET /content/{id}?expand={fields}`
- 創建頁面: `POST /content`
- 更新頁面: `PUT /content/{id}`

### Slack API

```
Base URL: https://slack.com/api
```

**常用端點**:
- 頻道歷史: `GET /conversations.history?channel={id}`
- 用戶資訊: `GET /users.info?user={id}`

**Token 來源**: `daily-report/.env` 的 `SLACK_BOT_TOKEN`

## 📋 標準操作流程

### 1. 從 Slack 會議記錄創建 JIRA

**使用場景**: Gemini 團隊同步會議、技術討論會議

**步驟**:
1. 確認頻道 ID（如：`C07K81AM9EE` = #gemini-專案討論）
2. 使用 `conversations.history` API 搜尋關鍵字
3. 提取會議內容和參與者
4. 轉換為 JIRA Wiki Markup 格式
5. 創建 JIRA Task（通常為 Medium priority）
6. 在 `aws-gemini-manager/` 創建對應的 `.md` 文檔

**範例**: OPS-813

### 2. 從 Confluence Release Note 創建 JIRA

**使用場景**: Production 升級、Release tracking

**步驟**:
1. 使用 CQL 搜尋頁面：`title~"20251117"`
2. 獲取頁面完整內容（expand: `body.storage,version,space,history`）
3. 提取升級項目、檢核表、資料庫作業等資訊
4. 轉換為 JIRA Wiki Markup
5. 創建 JIRA Task（通常為 High priority）
6. 添加 labels: `release`, `production`, 相關系統名稱
7. 在 `aws-gemini-manager/` 創建對應的 `.md` 文檔

**範例**: OPS-814

### 3. 更新 JIRA Ticket

**常見操作**:
- 更新標題 (summary)
- 更新描述 (description)
- 更新狀態 (status)
- 添加評論 (comment)

**API 方法**: `PUT /rest/api/2/issue/{ticket-id}`

**範例**: 更新 OPS-814 標題

### 4. 文檔同步規範

**每個 JIRA ticket 都應該在 aws-gemini-manager 創建對應文檔**

**命名規範**:
```
JIRA_{主題}_{日期}.md
```

**範例**:
- `JIRA_STEAMPUNK2_RESTART_ISSUE.md` (OPS-812)
- `JIRA_GEMINI_MEETING_20251117.md` (OPS-813)
- `JIRA_RELEASE_NOTE_20251117.md` (OPS-814)

**文檔開頭必須包含**:
```markdown
**JIRA Ticket**: [OPS-XXX](https://jira.ftgaming.cc/browse/OPS-XXX)
**Created**: YYYY-MM-DD
**Status**: Open/In Progress/Done
```

## 🔧 使用工具腳本

### jira_api.py - 可重用的 API 函數庫

提供以下功能:
- ✅ 創建 JIRA ticket
- ✅ 更新 JIRA ticket
- ✅ 搜尋 Confluence 頁面
- ✅ 獲取 Confluence 內容
- ✅ 搜尋 Slack 訊息
- ✅ 格式化為 JIRA Wiki Markup

### create_from_slack.py - 從 Slack 創建 JIRA

**使用方式**:
```bash
python3 scripts/jira/create_from_slack.py \
  --channel "gemini-專案討論" \
  --keywords "團隊同步會議" "2025-11-17" \
  --project OPS \
  --priority Medium \
  --assignee lonely.h
```

### create_from_confluence.py - 從 Confluence 創建 JIRA

**使用方式**:
```bash
python3 scripts/jira/create_from_confluence.py \
  --page-title "20251117_PROD_V1_Release_Note" \
  --project OPS \
  --priority High \
  --assignee lonely.h
```

### update_ticket.py - 更新 JIRA ticket

**使用方式**:
```bash
# 更新標題
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --summary "20251117 PROD 升級作業"

# 更新描述
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --description "新的描述內容"

# 添加評論
python3 scripts/jira/update_ticket.py \
  --ticket OPS-814 \
  --comment "升級已完成"
```

## 📝 JIRA Wiki Markup 語法

### 標題
```
h1. 最大標題
h2. 次標題
h3. 小標題
```

### 列表
```
# 有序列表項目 1
# 有序列表項目 2

* 無序列表項目 1
* 無序列表項目 2
```

### 連結
```
[顯示文字|URL]
[OPS-813|https://jira.ftgaming.cc/browse/OPS-813]
```

### 表格
```
|| 標題1 || 標題2 || 標題3 ||
| 資料1 | 資料2 | 資料3 |
| 資料4 | 資料5 | 資料6 |
```

### 分隔線
```
----
```

### 粗體/斜體
```
*粗體*
_斜體_
```

### 程式碼
```
{code:python}
print("Hello World")
{code}
```

## 🎯 JIRA Field 規範

### Project: OPS

**Issue Types**:
- Task: 一般任務、會議記錄、升級作業
- Bug: 系統問題、故障修復
- Story: 新功能開發

### Priority

- **Highest**: 嚴重 Production 問題
- **High**: Production 升級、重要修復
- **Medium**: 會議記錄、例行任務
- **Low**: 文檔更新、優化建議

### Common Labels

**系統相關**:
- `gemini`, `arcade`, `bingo`, `hash`, `rng`
- `eks-prd`, `eks-stage`
- `production`, `staging`

**類型相關**:
- `release`, `upgrade`, `deployment`
- `meeting-notes`, `investigation`
- `performance`, `memory-fix`, `optimization`

**日期標記**:
- `20251117`, `2025-11` (年月日或年月)

### Assignee

常用負責人:
- `lonely.h` (DevOps/Infrastructure)
- `PM-Ryan` (Product Manager)
- `BE-Jack` (Backend Development)

## ⚠️ 常見錯誤

### 1. Field 不支援

**錯誤訊息**:
```
"environment": "Field 'environment' cannot be set. It is not on the appropriate screen, or unknown."
```

**解決方案**: 移除該 field，改用 labels

### 2. 認證失敗 401

**原因**: 使用了錯誤的認證方式（Basic Auth）

**解決方案**: 改用 Bearer Token

### 3. Confluence 頁面找不到

**原因**: CQL 查詢語法錯誤

**正確範例**:
```python
params = {'cql': 'title~"20251117"', 'limit': 10}
```

### 4. Slack 訊息搜尋失敗

**原因**: `search.messages` 需要額外權限

**解決方案**: 使用 `conversations.history` 替代

## 📚 參考資源

### API 文檔

- [JIRA REST API](https://docs.atlassian.com/software/jira/docs/api/REST/latest/)
- [Confluence REST API](https://docs.atlassian.com/ConfluenceServer/rest/latest/)
- [Slack API](https://api.slack.com/methods)

### 內部專案

- **daily-report**: `/Users/lonelyhsu/gemini/claude-project/daily-report/`
  - 認證方式參考來源
  - Token 配置位置

### 範例 Tickets

- **OPS-812**: Steampunk2 重啟問題
- **OPS-813**: Gemini 團隊同步會議記錄
- **OPS-814**: 20251117 PROD 升級作業

## 🔄 工作流程總結

1. **確認來源** → Slack 會議 / Confluence Release Note / 問題報告
2. **提取資訊** → 使用相應 API 獲取完整內容
3. **格式轉換** → 轉為 JIRA Wiki Markup 格式
4. **創建 Ticket** → 使用 Bearer Token 認證，POST 到 JIRA API
5. **創建文檔** → 在 aws-gemini-manager 創建 `.md` 文檔
6. **驗證** → 確認 JIRA ticket 和文檔內容一致

## 💡 最佳實踐

1. ✅ **使用 Bearer Token** - Self-hosted JIRA/Confluence 必須使用
2. ✅ **完整的 description** - 包含完整背景、技術細節、相關連結
3. ✅ **適當的 labels** - 便於搜尋和分類
4. ✅ **文檔同步** - 每個 ticket 都要有對應的 .md 文檔
5. ✅ **連結追蹤** - ticket 之間互相引用（如：參考 OPS-813）
6. ✅ **量化資訊** - 包含時間、版本、數量等具體數據

---

**Last Updated**: 2025-11-17
**Maintainer**: lonely.h

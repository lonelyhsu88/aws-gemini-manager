# JIRA OPS Ticket - Production Release 20251117_PROD_V1

**JIRA Ticket**: [OPS-814](https://jira.ftgaming.cc/browse/OPS-814)
**Created**: 2025-11-17
**Status**: Open
**來源**: [Confluence Release Note](https://confluence.ftgaming.cc/display/DT20/20251117_PROD_V1_Release_Note)

---

## Summary (標題)

```
20251117 PROD 升級作業
```

---

## Issue Type (問題類型)

```
Task
```

---

## Priority (優先級)

```
High
```

---

## Assignee (負責人)

```
lonely.h
```

---

## Labels (標籤)

```
release, production, arcade, memory-fix, 20251117, gemini
```

---

## Description (詳細描述)

### Release 資訊

* **Release Date**: 2025/11/17
* **Confluence 頁面**: [20251117_PROD_V1_Release_Note](https://confluence.ftgaming.cc/display/DT20/20251117_PROD_V1_Release_Note)
* **Space**: 專案服務配置
* **Version**: 11

---

### 升級內容 & 修正問題

#### ✅ Arcade 系列處理記憶體問題

* 已於 2025/11/17 Production 環境完成升級
* 參考 [Gemini 團隊同步會議記錄 OPS-813](https://jira.ftgaming.cc/browse/OPS-813)

---

### 升級項目

#### 後端升級項目

| 項目 | Stage |
|------|-------|
| arcade-forestteapartygame-stage | 134 |
| arcade-scratchcardgame-stage | 133 |
| rng-multiboomersgame-stage | 135 |

#### 前端升級項目

待補充

#### Devops 升級項目

無 (-)

---

### 資料庫作業

#### SQL 執行說明

| 資料庫 | 執行身份 | 重啟要求 |
|--------|----------|----------|
| Bingo DB | bingo | 重開 center 和所有 game server |
| Mgmt DB | mgmt | 重開 mgmtapi |
| Cash DB | cash | 重開 mgmtapi |
| Combined DB | migrateuser | 無 |
| Loyalty DB | loyalty | 無 |
| Hash DB | hash | 無 |
| Rng DB | rng | 無 |
| Crashseed DB | crashseed | 無 |

---

### 防火牆開通

#### Gate 配置

| Name | PORT |
|------|------|
| 待補充 | 待補充 |

---

### 商戶配置

待補充

---

### 檢核表

請參考 Confluence 頁面完整檢核表：
[20251117_PROD_V1_Release_Note](https://confluence.ftgaming.cc/display/DT20/20251117_PROD_V1_Release_Note)

---

### 相關連結

* Confluence Release Note: [20251117_PROD_V1_Release_Note](https://confluence.ftgaming.cc/display/DT20/20251117_PROD_V1_Release_Note)
* Gemini 團隊同步會議: [OPS-813](https://jira.ftgaming.cc/browse/OPS-813)
* Steampunk2 重啟問題: [OPS-812](https://jira.ftgaming.cc/browse/OPS-812)

---

### OPS 追蹤事項

1. 確認 Arcade 系列記憶體問題已解決
2. 驗證後端服務升級成功
3. 檢查資料庫 SQL 執行狀態
4. 確認相關服務重啟完成
5. 監控 Production 環境穩定性

---

## 技術細節

### Confluence API Integration

成功使用 Confluence REST API 獲取 Release Note 頁面內容：

```python
# 使用 Bearer Token 認證 (自架 Confluence)
headers = {
    'Authorization': f'Bearer {CONFLUENCE_API_TOKEN}',
    'Accept': 'application/json',
    'Content-Type': 'application/json'
}

# 搜尋頁面
response = requests.get(
    f'{CONFLUENCE_URL}/rest/api/content/search',
    headers=headers,
    params={'cql': 'title~"20251117"'}
)

# 獲取頁面內容
response = requests.get(
    f'{CONFLUENCE_URL}/rest/api/content/{PAGE_ID}',
    headers=headers,
    params={'expand': 'body.storage,version,space,history'}
)
```

### 關鍵發現

從 daily-report 專案學到的認證方式：

**自架 Confluence 使用 Bearer Token**，與 Cloud 版本的 Basic Auth 不同：

```javascript
// daily-report/src/confluence-client.js (line 27-28)
// Self-hosted Confluence uses Bearer token
headers['Authorization'] = `Bearer ${config.confluenceApiToken}`;
```

**注意**: 之前使用 Basic Auth 失敗是因為 Confluence Server/Data Center 版本使用不同的認證機制。

---

## 文件歷史

- **2025-11-17**: 創建文檔，從 Confluence Release Note 提取內容並創建 JIRA ticket OPS-814
- **Confluence 頁面 ID**: 223143753
- **Confluence 版本**: 11

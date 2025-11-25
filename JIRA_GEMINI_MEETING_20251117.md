# JIRA OPS Ticket - Gemini 團隊同步會議記錄 2025-11-17

**JIRA Ticket**: [OPS-813](https://jira.ftgaming.cc/browse/OPS-813)
**Created**: 2025-11-17
**Status**: Open
**來源**: Slack #gemini-專案討論 channel
**會議日期**: 2025-11-17 09:59

---

## Summary (標題)

```
Gemini 團隊同步會議記錄 - 2025-11-17
```

---

## Issue Type (問題類型)

```
Task
```

---

## Priority (優先級)

```
Medium
```

---

## Assignee (負責人)

```
lonely.h
```

---

## Labels (標籤)

```
gemini, meeting-notes, arcade, game-deployment, merchant-pid, 2025-11
```

---

## Description (詳細描述)

### 會議資訊

* **日期**: 2025-11-17 09:59
* **來源**: Slack #gemini-專案討論 channel
* **主持人**: PM-Ryan

---

### 11/17 Production 升級完成項目

#### ✅ Arcade 系列記憶體問題處理
* **狀態**: 升級完畢
* **影響範圍**: Arcade 系列遊戲
* **說明**: 其餘遊戲不影響正常運作

---

### 進行中專案與排程

#### 11/05 stg → 11/27 rel → 12/1 prod
* 耶誕賓果 - 測試完畢
* 遊戲倍率改為小數點以下兩位 (11/14 下午兩點先升到 rel)

#### 11/17 rel & prod
* [GM-7632](https://jira.ftgaming.cc/browse/GM-7632) REL、PRD 新增商戶 PID (GMM4765~GMM4897)
* [GM-7633](https://jira.ftgaming.cc/browse/GM-7633) 創建商戶帳號 MA_tcgs1gcuat、MA_tcgs1scuat

#### 11/25 stg → 12/11 rel → 12/15 prod
* 板球mines

#### 12/8 stg → 12/24 rel → 12/29 prod
* 小雞過馬路
* Sky Mission (12/12 stg)

#### 12/24 stg → 1/02 rel → 1/05 prod
* Golden Bingo (12/17 提早進 Stg)
* 最高倍率限制

---

### 待安排事項

| # | 項目 | 期限/說明 |
|---|------|----------|
| 1 | AM需求：遊戲內公告 | 待安排 |
| 2 | 十二月 TCG 積分活動 | 12月 |
| 3 | 星城串接問題編修 | 待安排 |
| 4 | 馬來西亞 Aviator2 | 一月上線 |
| 5 | 耶誕節卡片 | 12/05 前提供 |
| 6 | 商戶 PID 新創建 122 個 | 11/26 提供 |

---

### 遊戲開發排程詳情

#### 1. 小雞過馬路
* 美術：10/14 ~ 11/11
* Backend：10/21 ~ 11/4
* Frontend：11/11 ~ 12/8
* QA：12/9 ~ 12/22
* 上版時間：
  - STG：12/8
  - REL：12/24
  - PROD：12/29

#### 2. 換皮遊戲#1 - 板球mines
* 美術：10/22 ~ 11/11
* Backend：10/22 ~ 10/27
* Frontend：11/11 ~ 11/25（四天員旅）
* QA：11/25 ~ 12/11
* 上版時間：
  - STG：11/25
  - REL：12/11
  - PROD：12/15

#### 3. 換皮遊戲#2 - 板球crash
* 待排程

#### 4. 新遊戲#3 - Sky Mission
* 美術：11/17 切圖素材、動畫
* FGUI：11/26
* 後端：待確認
* 前端：12/12 進 Stg

#### 5. 黃金賓果
* STG：12/17
* REL：1/02
* PROD：1/05

---

### 相關連結

* Slack訊息: [gemini-專案討論 channel](https://app.slack.com/client/T80KN2L2D/C07K81AM9EE)
* 相關JIRA:
  - [GM-7632](https://jira.ftgaming.cc/browse/GM-7632) - REL、PRD 新增商戶 PID
  - [GM-7633](https://jira.ftgaming.cc/browse/GM-7633) - 創建商戶帳號

---

### 後續追蹤

需要 OPS 團隊協助追蹤以下事項：
1. Arcade 系列記憶體問題的後續監控
2. 商戶 PID 新增作業的執行確認
3. 待安排事項的優先級評估和排程
4. 各遊戲上版時程的環境準備和部署支援

---

## 技術細節

### Slack API Integration
本次使用 Slack REST API 直接讀取 `#gemini-專案討論` channel (C07K81AM9EE) 的訊息歷史，搜尋關鍵字 "團隊同步會議" 和 "1117" 找到會議記錄。

### JIRA API Authentication
使用 **Bearer Token** 認證方式創建 ticket：
```bash
Authorization: Bearer {token}
```

**注意**：自架 JIRA Server/Data Center 使用 Bearer Token，不同於 JIRA Cloud 的 Basic Auth。

---

## 文件歷史

- **2025-11-17**: 創建文檔，記錄 Gemini 團隊同步會議內容並創建 JIRA ticket OPS-813

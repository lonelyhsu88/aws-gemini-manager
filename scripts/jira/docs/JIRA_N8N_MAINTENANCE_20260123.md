# n8n 主機維護作業 - OS 更新與版本評估

**JIRA Ticket**: [OPS-1131](https://jira.ftgaming.cc/browse/OPS-1131)
**Created**: 2026-01-23
**Status**: Open
**Priority**: Medium
**Assignee**: lonely.h

---

## 作業概述

今日針對 n8n 主機（gemini-n8n-01）進行系統更新和版本升級評估作業。

## 主機資訊

| 項目 | 內容 |
|------|------|
| 實例名稱 | gemini-n8n-01 |
| 實例 ID | i-06ff53ed9ffb2e1de |
| 公網 IP | 16.162.121.174 |
| 私有 IP | 172.31.8.119 |
| 部署方式 | Docker Compose |
| 當前 n8n 版本 | 1.123.5 |
| 資料庫 | PostgreSQL 16 |

---

## 執行作業

### 1. OS 系統更新

- ✅ 執行系統套件更新
- ✅ 檢查安全性補丁
- ✅ 驗證系統服務運行狀態

### 2. n8n 版本升級評估

| 項目 | 內容 |
|------|------|
| 當前版本 | 1.123.5 |
| 最新版本 | 2.4.5 |
| 版本差距 | 主要版本升級 (1.x → 2.x) |
| 評估結果 | **維持現狀，定期監控** |

---

## 評估結論

### ❌ 不升級原因

1. **破壞性變更風險**: n8n 2.0 引入重大架構變更，可能影響現有工作流程
2. **數據庫遷移風險**: PostgreSQL schema 可能需要升級，需要完整備份計劃
3. **API 兼容性**: 外部整合的 API 可能改變，需要驗證
4. **當前版本穩定**: 1.123.5 為 2024年底版本，相對穩定且功能足夠

### 📋 後續計劃

- **定期檢查**: 每月第一個週一檢查安全更新
- **小版本更新**: 每季度評估 1.x 系列的小版本更新（如 1.124.x, 1.125.x）
- **主版本升級**: 等待 2.x 穩定 3-6 個月後再評估
- **緊急升級條件**: 發現嚴重安全漏洞（CVE 高危）時立即升級

---

## 升級決策矩陣

| 情況 | 版本差異 | 升級決策 | 時間表 |
|------|---------|---------|--------|
| 🔴 嚴重安全漏洞 | 任何 | 立即升級 | 24-48小時內 |
| 🟡 影響業務的重大 Bug | 任何 | 優先升級 | 1週內 |
| 🟢 小版本更新 | 1.123.x → 1.124.x | 季度評估 | 每季度 |
| 🟢 次要版本更新 | 1.x → 1.y | 半年評估 | 每半年 |
| 🔵 主要版本更新 | 1.x → 2.x | 謹慎評估 | 等待 3-6 個月穩定 |

---

## 技術細節

### Docker 容器狀態

```bash
# 當前運行容器
CONTAINER ID   IMAGE                          STATUS
n8n-n8n-1      docker.n8n.io/n8nio/n8n:1.123.5   Up 4 seconds
n8n-postgres-1 postgres:16                       Up 4 seconds (health: starting)
```

### 檢查方式

```bash
# SSH 連接
ssh -i ~/.ssh/hk-devops.pem ec2-user@16.162.121.174

# 查看 n8n 版本
docker exec n8n-n8n-1 n8n --version

# 查看容器狀態
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

---

## 參考連結

- [n8n GitHub Releases](https://github.com/n8n-io/n8n/releases)
- [n8n Security Advisories](https://github.com/n8n-io/n8n/security/advisories)
- [n8n Documentation](https://docs.n8n.io/)
- [n8n 2.0 Migration Guide](https://docs.n8n.io/hosting/upgrading/)

---

## 執行資訊

- **執行日期**: 2026-01-23
- **執行人員**: lonely.h
- **預計下次檢查**: 2026-02-24 (每月第一個週一)

---

## 附註

- n8n 工作流程數量：待統計
- 外部整合服務：待確認
- 備份策略：需要建立完整的備份計劃（包含 PostgreSQL 和 Docker volumes）

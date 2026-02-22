# OCI 遷移文檔目錄

**專案**: AWS RDS PostgreSQL → OCI Database Migration
**狀態**: 規劃階段
**建立日期**: 2026-01-20

---

## 📁 文檔結構

本目錄包含 AWS RDS PostgreSQL 遷移至 Oracle Cloud Infrastructure (OCI) 的完整技術文檔。

### 核心文檔

1. **[RDS_TO_OCI_MIGRATION_PLAN.md](./RDS_TO_OCI_MIGRATION_PLAN.md)** ⭐️ **主要規劃文檔**
   - 完整的遷移策略與計畫
   - 環境清單與現況分析
   - 分階段執行時間表
   - 風險管理與應急計畫
   - 成本分析與 ROI
   - 團隊組織與 RACI 矩陣
   - **建議優先閱讀此文檔**

2. **[NETWORK_AND_GOLDENGATE_SETUP.md](./NETWORK_AND_GOLDENGATE_SETUP.md)** 🔧 **技術實施指南**
   - Equinix Fabric Cloud Router 詳細配置
   - AWS Direct Connect 設定步驟
   - OCI FastConnect 配置流程
   - Oracle GoldenGate 完整設定
   - BGP 路由配置參考
   - 監控與驗證腳本
   - **執行階段必備參考**

---

## 🎯 快速導航

### 依角色選擇文檔

| 角色 | 推薦閱讀順序 | 重點章節 |
|------|------------|---------|
| **專案經理** | 1️⃣ Migration Plan → 2️⃣ 成本分析 | 執行摘要、時間表、風險管理、團隊職責 |
| **DBA** | 1️⃣ Migration Plan → 2️⃣ GoldenGate Setup | 資料遷移方法、驗證計畫、GoldenGate 配置 |
| **網路工程師** | 1️⃣ Network Setup → 2️⃣ BGP 配置 | Equinix FCR、AWS/OCI 網路配置、BGP 路由 |
| **DevOps** | 1️⃣ Migration Plan → 2️⃣ Network Setup → 3️⃣ 監控腳本 | 自動化部署、監控告警、Terraform 配置 |
| **安全團隊** | 1️⃣ 安全與合規 → 2️⃣ Cloud Guard 整合 | IAM 權限、加密方案、稽核日誌 |
| **管理層** | 1️⃣ 執行摘要 → 2️⃣ 成本分析 → 3️⃣ 風險評估 | 目標、投資回報、關鍵里程碑 |

---

## 📊 遷移概覽

### 基本資訊

| 項目 | 詳情 |
|------|------|
| **來源平台** | AWS RDS PostgreSQL 14.15 (ap-east-1 Hong Kong) |
| **目標平台** | OCI Database with PostgreSQL (ap-tokyo-1) |
| **資料總量** | ~8 TB (3 個主要生產實例) |
| **遷移工具** | Oracle GoldenGate |
| **網路方案** | Equinix Fabric Cloud Router |
| **預計停機** | < 4 小時 (使用 GoldenGate CDC) |
| **預計時程** | 8-10 週 (約 2-2.5 個月) |

### 環境清單

#### ✅ 需要遷移的生產實例 (3 個)
- **bingo-prd-loyalty** (200 GB) - Phase 2 🟡
- **bingo-prd** (2750 GB) - Phase 3 核心業務 🔴
- **bingo-prd-backstage** (5024 GB) - Phase 4 最大實例 🔴

#### ❌ 不遷移的實例 (5 個)

**Read Replica (將在 OCI 重新建立)**:
- **bingo-prd-replica1** (2929 GB) - Phase 5 在 OCI 建立
- **bingo-prd-backstage-replica1** (1465 GB) - Phase 5 在 OCI 建立

**測試/開發環境 (保留於 AWS)**:
- **bingo-stress-loyalty** (200 GB) 🟢
- **pgsqlrel** (40 GB) 🟢
- **pgsqlrel-backstage** (40 GB) 🟢

---

## 🗓️ 執行階段指南

### Phase 0: 準備階段 (2 週)
**閱讀**: Migration Plan - Section "Phase 0"
- OCI 環境規劃與申請
- 容量與效能評估
- 團隊技能培訓
- 安全與合規準備

### Phase 1: OCI 環境建置與網路連線 (1-2 週)
**閱讀**: Network Setup - Complete Guide
- OCI 生產環境建置
- Equinix Fabric 設定
- FastConnect 私有連線
- GoldenGate 部署準備

### Phase 2: 小型生產實例遷移驗證 (2 週)
**閱讀**: Migration Plan - Section "Phase 2"
- **遷移**: bingo-prd-loyalty (200 GB)
- 完整遷移流程驗證
- 應用相容性測試
- 監控與告警設定

### Phase 3: 中型生產實例遷移 (2-3 週)
**閱讀**: Migration Plan - Section "Phase 3"
- **遷移**: bingo-prd (2750 GB)
- 核心業務資料庫
- 完整驗證流程
- 回退演練

### Phase 4: 最大生產實例遷移 (3-4 週)
**閱讀**: Migration Plan - Section "Phase 4"
- **遷移**: bingo-prd-backstage (5024 GB)
- 最大實例遷移
- 持續監控

### Phase 5: OCI Read Replica 建立 (1-2 週)
**閱讀**: Migration Plan - Section "Phase 5"
- 在 OCI 重新建立 Read Replica
- 高可用架構恢復
- 複製延遲驗證

### Phase 6: 最終清理與優化 (2 週)
**閱讀**: Migration Plan - Section "Phase 6"
- RDS 資源清理
- OCI 優化
- 文檔更新
- 監控完善

---

## 💡 關鍵決策點

### 網路頻寬選擇

| 方案 | 成本 | 8TB 傳輸時間 | 適用場景 |
|------|------|-------------|---------|
| **1 Gbps** | $1,754/月 | 2-3 天 | 預算優先、時間彈性 ✅ **推薦** |
| **10 Gbps** | $5,504/月 | 4-6 小時 | 停機敏感、業務關鍵 |

**建議**:
- **Phase 2-3**: 使用 1 Gbps (較小實例，成本效益高)
- **Phase 4**: 評估是否升級為 10 Gbps (最大實例 5TB)

### 遷移方法

| 方法 | 停機時間 | 複雜度 | 推薦度 |
|------|---------|--------|--------|
| **pg_dump** | 6-8 小時 | 低 | ❌ 不推薦 (8TB 仍過大) |
| **Oracle GoldenGate** | < 4 小時 | 中 | ✅ **強烈推薦** (CDC 持續同步) |

---

## 🔗 相關連結

### Oracle 官方文檔
- [PostgreSQL Import/Export/Migrate](https://docs.oracle.com/en-us/iaas/Content/postgresql/import-export-migrate.htm)
- [Oracle GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- [Oracle Cloud Guard](https://www.oracle.com/security/cloud-security/cloud-guard/)
- [OCI FastConnect](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/fastconnect.htm)

### 內部文檔
- [RDS 管理工具](../../scripts/rds/)
- [CloudWatch 監控](../../scripts/cloudwatch/)
- [JIRA OPS-1033: Storage Autoscaling](../JIRA_BINGO_PRD_REPLICA1_STORAGE_20260108.md)

### 外部資源
- [Equinix Fabric Portal](https://fabric.equinix.com)
- [AWS Direct Connect Console](https://console.aws.amazon.com/directconnect/)
- [OCI Console](https://cloud.oracle.com/)

---

## 🚀 快速開始

### 1. 環境準備檢查清單

```bash
# 檢查 AWS CLI
aws --profile gemini-pro_ck sts get-caller-identity

# 檢查 RDS 實例
aws --profile gemini-pro_ck rds describe-db-instances \
  --query 'DBInstances[?Engine==`postgres`].[DBInstanceIdentifier,AllocatedStorage]' \
  --output table

# 檢查現有參數組
aws --profile gemini-pro_ck rds describe-db-parameter-groups \
  --query 'DBParameterGroups[?contains(DBParameterGroupName, `postgresql14`)]'
```

### 2. OCI 帳號準備

- [ ] 申請 OCI 帳號
- [ ] 建立專案 Compartment
- [ ] 設定 IAM 使用者與權限
- [ ] 準備付款方式

### 3. Equinix Fabric 準備

- [ ] 註冊 Equinix Fabric 帳號
- [ ] 驗證身份與企業資訊
- [ ] 準備信用卡或企業付款帳戶

---

## 📞 支援與協助

### 內部團隊

| 角色 | 聯絡方式 | 負責範圍 |
|------|---------|---------|
| 專案經理 | - | 整體協調、進度追蹤 |
| DBA 主管 | - | 資料庫遷移、GoldenGate |
| DevOps 主管 | - | 網路、自動化、監控 |
| 應用團隊 | - | 應用切換、測試 |

### 外部支援

| 服務 | 聯絡方式 |
|------|---------|
| Equinix Support | cs@equinix.com |
| AWS Support | 透過 AWS Console |
| OCI Support | 透過 OCI Console |

---

## 📝 文檔更新記錄

| 日期 | 版本 | 變更摘要 | 作者 |
|------|------|---------|------|
| 2026-01-20 | 1.0 | 初始版本，建立完整規劃 | Claude + lonely.h |

---

## ✅ 下一步行動

1. **本週**:
   - 閱讀完整規劃文檔
   - 召開專案啟動會議
   - 確認 OCI POC 環境狀態

2. **本月**:
   - 確認 OCI 帳號與權限
   - 完成網路設計與 Equinix Fabric 申請
   - 安排團隊 GoldenGate 培訓

3. **第二個月**:
   - 建立 OCI 生產環境 (Phase 1)
   - 執行小型生產實例遷移驗證 (Phase 2)
   - 開始中型生產實例遷移 (Phase 3)

4. **第三個月內完成** (8-10 週總時程):
   - 完成中型與最大生產實例遷移 (Phase 3-4)
   - 建立 OCI Read Replica (Phase 5)
   - 執行最終清理與優化 (Phase 6)

---

**問題回報**: 請在 [GitHub Issues](https://github.com/your-repo/issues) 或 Slack #ops-migration 頻道反映

**文檔維護**: DevOps Team + DBA Team

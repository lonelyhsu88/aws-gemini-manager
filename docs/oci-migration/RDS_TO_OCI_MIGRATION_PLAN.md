# AWS RDS PostgreSQL 遷移至 OCI 完整規劃

**文檔版本**: 1.0
**建立日期**: 2026-01-20
**專案**: aws-gemini-manager RDS to OCI Migration
**狀態**: 規劃階段 (Planning)

---

## 📋 執行摘要

本文檔規劃將 AWS RDS PostgreSQL 14.15 生產環境（3 個主要實例，總容量約 8 TB）遷移至 Oracle Cloud Infrastructure (OCI) 的完整方案。

### 關鍵目標
- ✅ **零資料遺失**: 確保資料完整性 100%
- ✅ **最小停機時間**: 採用 Oracle GoldenGate 實現近零停機遷移
- ✅ **安全合規**: 整合 Oracle Cloud Guard 全程監控
- ✅ **效能維持**: 確保遷移後效能不降低
- ✅ **高可用性**: 遷移後在 OCI 重新建立 Read Replica

### 規劃基準
- **來源平台**: AWS RDS PostgreSQL 14.15 (ap-east-1 香港)
- **目標平台**: OCI PostgreSQL Database Service (ap-tokyo-1 東京)
- **遷移範圍**: 3 個主要生產實例 (不包含 Read Replica 和測試環境)
- **總資料量**: ~8 TB (7,974 GB)
- **預計停機時間**: < 4 小時 (使用 GoldenGate)
- **遷移策略**: 分階段遷移 (由小至大，先驗證後擴展)

---

## 📊 現有環境清單

### 1. 需要遷移的生產實例 (3 個)

#### 核心業務資料庫

| 實例名稱 | 角色 | 實例類型 | 儲存容量 | IOPS | 可用空間 | 優先級 | 遷移狀態 |
|---------|------|----------|---------|------|---------|--------|---------|
| **bingo-prd** | Primary | db.m6g.large | 2750 GB | 12000 | 325 GB (11.8%) | 🔴 Critical | ✅ **遷移** |
| **bingo-prd-backstage** | Primary | db.m6g.large | 5024 GB | 12000 | N/A | 🔴 Critical | ✅ **遷移** |
| **bingo-prd-loyalty** | Primary | db.t4g.medium | 200 GB | 3000 | N/A | 🟡 High | ✅ **遷移** |

**遷移資料總量**: 7,974 GB (~8 TB)

### 2. 不遷移的實例 (5 個)

#### Read Replica (將在 OCI 重新建立)

| 實例名稱 | 角色 | 儲存容量 | IOPS | 處理策略 |
|---------|------|---------|------|---------|
| **bingo-prd-replica1** | Read Replica | 2929 GB | 12000 | ❌ 不遷移，遷移後在 OCI 建立新 Replica |
| **bingo-prd-backstage-replica1** | Read Replica | 1465 GB | 12000 | ❌ 不遷移，遷移後在 OCI 建立新 Replica |

#### 測試/開發環境

| 實例名稱 | 角色 | 儲存容量 | IOPS | 處理策略 |
|---------|------|----------|------|---------|
| **bingo-stress-loyalty** | Test | 200 GB | 3000 | ❌ 不遷移，保留於 AWS |
| **pgsqlrel** | Dev | 40 GB | 3000 | ❌ 不遷移，保留於 AWS |
| **pgsqlrel-backstage** | Dev | 40 GB | 3000 | ❌ 不遷移，保留於 AWS |

**理由**:
- **Read Replica**: 在 OCI 重新建立可確保最佳效能和架構一致性
- **測試/開發環境**: 保留於 AWS 降低遷移複雜度，未來可視需求決定

### 3. 環境特徵分析

#### 儲存使用趨勢
- **bingo-prd**: 接近 autoscaling 閾值 (11.8% 可用)
- **bingo-prd-replica1**: 最近完成 autoscaling (+179 GB)
- **成長率**: 月均約 6-8% 容量增長
- **峰值 IOPS**: 讀取峰值 5886 IOPS (平均 714 IOPS)

#### 架構特點
- ✅ 讀寫分離: 主實例 + 讀取副本
- ✅ 高可用性監控: 完整的 CloudWatch 告警 (20+ 告警)
- ✅ 自動擴展: MaxAllocatedStorage 設定為 5000 GB
- ✅ 效能調優: 已完成參數組優化 (postgresql14-monitoring-params)

---

## 🎯 遷移策略與方法

### 方案選擇: Oracle GoldenGate (建議)

基於 Oracle 官方文檔和環境特性分析，**強烈建議採用 Oracle GoldenGate** 進行遷移。

#### 選擇理由

| 評估項目 | pg_dump | **Oracle GoldenGate** |
|---------|---------|----------------------|
| **停機時間** | 8-12 小時 | **< 4 小時** ✅ |
| **資料量適用性** | < 1 TB | **> 10 TB** ✅ |
| **風險等級** | 中高 | **低** ✅ |
| **回退能力** | 困難 | **容易** ✅ |
| **持續複製** | ❌ | **✅** |
| **增量同步** | ❌ | **✅** |
| **技術複雜度** | 低 | 中 |
| **成本** | 低 | 中 |

#### 決策依據
1. **資料量龐大**: 主實例實際使用量 7,974 GB（約 7.8 TB），pg_dump 停機時間過長
2. **業務連續性**: 24/7 線上服務，無法接受長時間停機
3. **讀寫分離架構**: GoldenGate 支援複雜拓撲
4. **風險控制**: 可先同步再切換，回退容易

---

## 🔧 Oracle GoldenGate 遷移架構

### 整體流程圖

```
┌─────────────────────────────────────────────────────────────────┐
│                     Phase 1: 準備階段                            │
│  ┌──────────┐      ┌──────────┐      ┌──────────────────┐      │
│  │ 架構轉儲  │ ───> │ OCI 配置 │ ───> │ GoldenGate 部署  │      │
│  └──────────┘      └──────────┘      └──────────────────┘      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Phase 2: 初始資料載入 (INI)                     │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐              │
│  │ Extract  │ ───> │ Snapshot │ ───> │ Replicat │              │
│  │  (INI)   │      │  Load    │      │  (OCI)   │              │
│  └──────────┘      └──────────┘      └──────────┘              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              Phase 3: 持續資料捕獲 (CDC)                         │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐              │
│  │ Extract  │ ───> │ Trail    │ ───> │ Replicat │              │
│  │  (CDC)   │      │  Files   │      │  (OCI)   │              │
│  └──────────┘      └──────────┘      └──────────┘              │
│       ↓                                                          │
│  WAL Logical                                                     │
│  Replication                                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Phase 4: 驗證與切換                           │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐              │
│  │ 資料驗證  │ ───> │ 應用切換 │ ───> │ DNS更新  │              │
│  └──────────┘      └──────────┘      └──────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

### 技術元件說明

#### 1. Extract (資料提取)

**INI Extract** - 初始完整載入
```properties
# extract_ini.prm
EXTRACT INIT_LOAD
SOURCEDB <rds_endpoint>, USERIDALIAS rds_user
EXTTRAIL ./dirdat/in
INITIALLOADOPTIONS USESNAPSHOT
TABLE public.*;
```

**CDC Extract** - 增量變更捕獲
```properties
# extract_cdc.prm
EXTRACT CDC_LOAD
SOURCEDB <rds_endpoint>, USERIDALIAS rds_user
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT
EXTTRAIL ./dirdat/cd
TRANLOGOPTIONS FILTERTABLE public.*
TABLE public.*;
```

#### 2. Replicat (資料應用)

```properties
# replicat.prm
REPLICAT REP_OCI
TARGETDB <oci_endpoint>, USERIDALIAS oci_user
DISCARDFILE ./dirrpt/rep_oci.dsc, PURGE
MAP public.*, TARGET public.*;
```

---

## 🗓️ 分階段遷移計畫

### Phase 0: 評估與準備 (2 週)

#### Week 1-2: 環境評估與資源準備

**任務清單**:

1. **OCI 環境規劃**
   - [ ] 申請 OCI 帳號與專案空間
   - [ ] 設計網路架構 (VCN, Subnet, Security List)
   - [ ] 規劃 IAM 權限與存取控制
   - [ ] 評估 OCI 區域選擇 (建議: ap-tokyo-1 或 ap-osaka-1)

2. **容量與效能規劃**
   - [ ] 計算 OCI 實例大小 (對應 AWS 實例類型)
   - [ ] 評估儲存需求 (Block Volume + 20% buffer)
   - [ ] IOPS 與吞吐量需求評估
   - [ ] 成本預估與預算審批

3. **RDS 環境準備**
   - [ ] 備份所有實例 (pg_dump 備份保留)
   - [ ] 記錄所有配置 (參數、使用者、權限)
   - [ ] 啟用 WAL logical replication
   - [ ] 建立遷移專用使用者

**關鍵配置變更 (RDS)**:
```sql
-- postgresql.conf (透過參數組修改)
wal_level = logical
max_replication_slots = 5
max_wal_senders = 5
track_commit_timestamp = on
```

**AWS RDS 參數組設定**:
```bash
# 建立新的參數組
aws --profile gemini-pro_ck rds create-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --db-parameter-group-family postgres14 \
  --description "Parameters for GoldenGate migration"

# 設定 logical replication
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot"

# 授予複製權限
psql -h <rds-endpoint> -U postgres -c "GRANT REPLICATION TO migration_user;"
```

4. **安全與合規準備**
   - [ ] 資料加密方案 (TDE)
   - [ ] 網路連線方案 (VPN/Direct Connect)
   - [ ] 稽核日誌規劃
   - [ ] 合規性檢查清單

---

### Phase 1: OCI 環境建置與網路連線 (1-2 週)

#### 目標: 建立 OCI 基礎設施與驗證連線

**任務清單**:

1. **OCI 生產環境建置**
   - [ ] 建立 OCI Database 實例 (3 個主要實例規格)
   - [ ] 設定 VCN 與 Subnet 架構
   - [ ] 配置 Security Lists 與 Network Security Groups
   - [ ] 設定 Equinix Fabric Cloud Router 連線
   - [ ] 建立 FastConnect 私有連線

2. **網路連線驗證**
   - [ ] 測試 AWS → OCI 網路連通性
   - [ ] 驗證延遲與頻寬 (應 < 50ms, ≥ 1 Gbps)
   - [ ] 設定 BGP 路由
   - [ ] 測試資料庫端口連線 (5432)

3. **GoldenGate 部署準備**
   - [ ] 部署 Oracle GoldenGate 實例
   - [ ] 配置 GoldenGate 連線參數
   - [ ] 測試 RDS → GoldenGate 連線
   - [ ] 測試 GoldenGate → OCI 連線
   - [ ] 驗證權限與複製使用者

4. **安全與監控設定**
   - [ ] 設定 Cloud Guard 監控
   - [ ] 配置 IAM 權限
   - [ ] 建立稽核日誌
   - [ ] 設定告警通知 (Slack 整合)

**預期結果**:
- OCI 環境完全就緒
- 網路連線穩定可靠
- GoldenGate 工具可正常運作
- 監控與告警系統上線

---

### Phase 2: 小型生產實例遷移驗證 (2 週)

#### 目標: 使用最小生產實例驗證完整遷移流程

**遷移實例**: bingo-prd-loyalty (200 GB) - 最小生產實例

**時間規劃**:
- **Week 1**: 架構準備與 GoldenGate 設定
- **Week 2**: 初始載入、CDC 同步與驗證

**重點驗證**:
1. **遷移流程驗證**
   - 架構轉換與修改流程
   - GoldenGate 配置正確性
   - 初始載入效能 (GB/hour)
   - CDC 同步延遲 (應 < 5 秒)

2. **生產環境相容性**
   - 應用連線字串調整
   - SQL 語法相容性測試
   - 使用者權限驗證
   - 效能基準對比

3. **監控與告警驗證**
   - OCI Monitoring Dashboard
   - Cloud Guard 安全監控
   - 告警通知測試 (Slack)
   - 效能指標追蹤

**成功標準**:
- 資料完整性 100% 一致
- CDC 延遲 < 5 秒
- 應用正常運作無錯誤
- 效能符合或優於 RDS

---

### Phase 3: 中型生產實例遷移 (2-3 週)

#### 目標: 遷移第二個生產實例

**遷移實例**: bingo-prd (2750 GB) - 核心業務資料庫

**時間規劃**:
- **Week 1**: 準備與 GoldenGate 設定
- **Week 2**: INI 初始載入 (週末執行)
- **Week 3**: CDC 同步、驗證與切換

**執行步驟**:

1. **準備階段 (2-3 天)**
   ```bash
   # 1. 架構轉儲
   pg_dump -h bingo-prd-loyalty.<rds-endpoint> \
     -U postgres -s -C -E 'UTF8' \
     -d loyalty -f loyalty_schema.sql

   # 2. 修改架構 (移除不相容語法)
   sed -i 's/WITH SUPERUSER//g' loyalty_schema.sql
   sed -i 's/NOREPLICATION//g' loyalty_schema.sql

   # 3. 在 OCI 建立架構
   psql -h <oci-endpoint> -U postgres -d postgres -f loyalty_schema.sql
   ```

2. **GoldenGate 設定 (1-2 天)**
   - 部署 GoldenGate 實例
   - 配置 Extract (INI + CDC)
   - 配置 Replicat
   - 測試連線

3. **初始載入 (週末執行, ~6-8 小時)**
   ```bash
   # 啟動 INI Extract
   GGSCI> START EXTRACT INIT_LOAD

   # 監控進度
   GGSCI> INFO EXTRACT INIT_LOAD, DETAIL
   ```

4. **持續複製 (1 週)**
   ```bash
   # 啟動 CDC Extract
   GGSCI> START EXTRACT CDC_LOAD

   # 啟動 Replicat
   GGSCI> START REPLICAT REP_OCI

   # 監控 lag
   GGSCI> LAG REPLICAT REP_OCI
   ```

5. **驗證與切換 (1-2 天)**
   - 資料完整性驗證
   - 效能測試
   - 應用切換 (低流量時段)
   - DNS 更新
   - 監控 24 小時

**回退計畫**:
- CDC 保持運行，可隨時切回 RDS
- 保留 RDS 實例 2 週

---

### Phase 4: 最大生產實例遷移 (3-4 週)

#### 目標: 遷移最大的生產資料庫實例

**遷移實例**: bingo-prd-backstage (5024 GB) - **最大實例**

**時間規劃**:
- **Week 1**: 架構準備與驗證
- **Week 2**: GoldenGate 部署與測試
- **Week 3**: INI 初始載入 (週末執行，預計 12-18 小時)
- **Week 4**: CDC 同步、驗證與切換

**時間窗口**: 週末凌晨 2:00-6:00 (4 小時)

**詳細步驟**:
```
T-7 days:  架構準備與驗證
T-3 days:  GoldenGate 部署與測試
T-1 day:   INI 初始載入 (週六凌晨開始)
T-0:       CDC 同步與驗證 (週日)
T+1 hour:  應用切換 (週一凌晨 2:00)
T+4 hours: 監控與驗證 (週一上午 6:00 前)
```

**特別注意**:
- 此為最大實例，初始載入時間較長
- 建議在前面兩個實例遷移完全穩定後再執行
- 準備完整的回退方案
- 預留充足的驗證時間

**每個實例的遷移檢查清單**:

- [ ] **準備階段**
  - [ ] 完整備份 (pg_dump)
  - [ ] 架構轉儲與修改
  - [ ] OCI 實例建立與配置
  - [ ] 網路連線測試
  - [ ] GoldenGate 部署

- [ ] **初始載入階段**
  - [ ] INI Extract 啟動
  - [ ] 監控載入進度
  - [ ] 初步資料驗證

- [ ] **持續同步階段**
  - [ ] CDC Extract 啟動
  - [ ] Replicat 啟動
  - [ ] Lag 監控 (< 5 秒)
  - [ ] 錯誤日誌檢查

- [ ] **驗證階段**
  - [ ] 行數對比 (每張表)
  - [ ] Checksum 驗證
  - [ ] 隨機抽樣驗證
  - [ ] 索引與約束驗證
  - [ ] 效能基準測試

- [ ] **切換階段**
  - [ ] 停止應用寫入 (RDS)
  - [ ] 等待 CDC 同步完成 (lag = 0)
  - [ ] 最終驗證
  - [ ] 應用重新指向 OCI
  - [ ] 驗證應用正常運作

- [ ] **監控階段**
  - [ ] 連續監控 24 小時
  - [ ] 效能指標對比
  - [ ] 錯誤日誌檢查
  - [ ] 使用者回饋收集

---

### Phase 5: OCI Read Replica 建立 (1-2 週)

#### 目標: 在 OCI 重新建立高可用架構

**Read Replica 規格對應表**:

| AWS RDS Replica | 主實例 | 儲存容量 | IOPS | OCI 目標配置 | OCPU | Memory | Storage |
|----------------|--------|---------|------|-------------|------|--------|---------|
| **bingo-prd-replica1** | bingo-prd | 2929 GB | 12000 | VM.Standard.E4.Flex | 4 | 32 GB | 3200 GB |
| **bingo-prd-backstage-replica1** | bingo-prd-backstage | 1465 GB | 12000 | VM.Standard.E4.Flex | 2 | 16 GB | 1600 GB |

**設計考量**:
- ✅ **儲存配置**: 預留 ~10% 成長空間 (3200GB vs 2929GB, 1600GB vs 1465GB)
- ✅ **效能對等**: OCI OCPU 配置對應 AWS m6g.large 效能 (4 OCPU ≈ 2 vCPU ARM)
- ✅ **高可用性**: 啟用自動備份與 Point-in-Time Recovery
- ✅ **監控設定**: 配置複製延遲告警 (閾值: 1 秒)

**建立 Read Replica**:

1. **bingo-prd-replica1** (對應 bingo-prd)
   - [ ] 在 OCI 建立 Read Replica Database System
   - [ ] 配置規格: 4 OCPU, 32 GB Memory, 3200 GB Storage
   - [ ] 啟用自動備份與 Point-in-Time Recovery
   - [ ] 驗證複製延遲 (應 < 1 秒)
   - [ ] 測試應用讀取分流

2. **bingo-prd-backstage-replica1** (對應 bingo-prd-backstage)
   - [ ] 在 OCI 建立 Read Replica Database System
   - [ ] 配置規格: 2 OCPU, 16 GB Memory, 1600 GB Storage
   - [ ] 啟用自動備份
   - [ ] 驗證複製延遲
   - [ ] 測試應用讀取分流

**OCI Read Replica 配置步驟**:

```bash
# 使用 OCI CLI 建立 Read Replica
oci db system launch-from-database \
  --source-database-id <primary-db-ocid> \
  --display-name "bingo-prd-replica1" \
  --availability-domain <ad> \
  --subnet-id <subnet-ocid> \
  --shape "VM.Standard.E4.Flex" \
  --cpu-core-count 4 \
  --data-storage-size-in-gbs 3200 \
  --edition "ENTERPRISE_EDITION"

# 驗證複製狀態
oci db autonomous-database get \
  --autonomous-database-id <replica-ocid> \
  | jq '.data."lifecycle-state"'
```

**驗證項目**:
- [ ] 複製延遲監控 (< 1 秒)
- [ ] 資料一致性驗證
- [ ] 讀取效能測試
- [ ] 自動故障轉移測試
- [ ] 應用連線配置更新

**理由**:
- OCI 原生 Read Replica 提供更好的效能與穩定性
- 與 OCI 平台深度整合，管理更簡便
- 確保高可用架構完整性

---

### Phase 6: 最終清理與優化 (2 週)

#### 任務清單

1. **RDS 資源清理**
   - [ ] 確認所有主實例遷移完成
   - [ ] 確認 Read Replica 在 OCI 建立完成
   - [ ] 保留 RDS 快照備份
   - [ ] 停止 RDS 實例 (非刪除)
   - [ ] 監控期 1 個月後刪除 RDS 與 Read Replica

2. **OCI 優化**
   - [ ] 執行 VACUUM ANALYZE (所有實例)
   - [ ] 索引重建與優化
   - [ ] 統計資訊更新
   - [ ] 效能調校與參數優化
   - [ ] 確認 Auto-scaling 正常運作

3. **監控與告警完善**
   - [ ] 複製所有 CloudWatch 告警到 OCI Monitoring
   - [ ] 設定 Cloud Guard 持續監控
   - [ ] 整合 Slack 通知
   - [ ] 建立完整監控 Dashboard
   - [ ] 設定 Read Replica 延遲告警

4. **文檔與知識轉移**
   - [ ] 更新架構文檔 (包含 OCI Read Replica)
   - [ ] 操作手冊編寫
   - [ ] 團隊培訓
   - [ ] 經驗總結報告
   - [ ] 災難恢復計畫更新

---

## 🔒 安全與合規方案

### Oracle Cloud Guard 整合

#### 自動化安全監控

Cloud Guard 提供以下關鍵功能保護遷移過程:

1. **實時威脅偵測**
   - 監控異常資料庫存取行為
   - 偵測非授權的配置變更
   - 識別可疑的資料傳輸模式

2. **自動化修正**
   ```yaml
   # Cloud Guard 偵測器配置範例
   detector:
     name: "Database Configuration Monitoring"
     rules:
       - rule: "Detect Public Database Access"
         action: "Alert + Auto-Remediate"
         remediation: "Remove public IP assignment"

       - rule: "Detect Unencrypted Connections"
         action: "Alert"
         notification: "Security Team + Slack"
   ```

3. **合規性稽核**
   - 自動產生稽核日誌
   - 符合 GDPR/HIPAA/SOC2 要求
   - 匯出到 SIEM 工具 (Splunk, QRadar)

#### 資料保護措施

| 保護層級 | 技術方案 | 實施階段 |
|---------|---------|---------|
| **傳輸加密** | TLS 1.3 | 全程 |
| **靜態加密** | OCI Block Volume Encryption | OCI 建置時 |
| **存取控制** | IAM Policies + Database Roles | 準備階段 |
| **網路隔離** | Private Subnet + Security Lists | OCI 建置時 |
| **稽核日誌** | Cloud Guard + Audit Logs | 全程 |

---

## 📈 效能與容量規劃

### OCI 實例規格對應

#### 生產環境實例對應表（主實例）

| RDS 實例 | AWS 規格 | OCI 建議規格 | OCPU | Memory | Storage | IOPS | 遷移優先序 |
|---------|---------|-------------|------|--------|---------|------|-----------|
| **bingo-prd-loyalty** | db.t4g.medium | VM.Standard.E4.Flex | 2 OCPU | 16 GB | 250 GB | 3000 | Phase 2 (第一) |
| **bingo-prd** | db.m6g.large | VM.Standard.E4.Flex | 4 OCPU | 32 GB | 3000 GB | 25000 | Phase 3 (第二) |
| **bingo-prd-backstage** | db.m6g.large | VM.Standard.E4.Flex | 4 OCPU | 32 GB | 5500 GB | 25000 | Phase 4 (第三) |

#### OCI Read Replica 規格（Phase 5 建立）

| Replica 名稱 | 對應主實例 | OCI 建議規格 | OCPU | Memory | Storage | IOPS |
|-------------|-----------|-------------|------|--------|---------|------|
| **bingo-prd-replica1** | bingo-prd | VM.Standard.E4.Flex | 4 OCPU | 32 GB | 3200 GB | 25000 |
| **bingo-prd-backstage-replica1** | bingo-prd-backstage | VM.Standard.E4.Flex | 2 OCPU | 16 GB | 1600 GB | 15000 |

**規格選擇理由**:
- **VM.Standard.E4.Flex**: OCI 最新 AMD EPYC 處理器，效能優於 AWS Graviton2
- **OCPU 對應**: 1 OCPU ≈ 2 vCPU (AWS)
- **Memory**: 8 GB per OCPU (OCI 標準比例)
- **IOPS**: OCI Block Volume 提供更高 IOPS 上限 (25000 vs 12000)

#### 儲存規劃

**主實例遷移 (Phase 2-4)**:
```
主實例總儲存: 7,974 GB (當前使用) + 20% buffer = 9,569 GB

分配方案:
├── Block Volume (High Performance): 9,750 GB
│   ├── bingo-prd-loyalty: 250 GB
│   ├── bingo-prd: 3,000 GB
│   └── bingo-prd-backstage: 5,500 GB
├── Backup Storage: 12,000 GB (1.5x capacity)
└── Archive Storage: 8,000 GB (舊備份保留)
```

**Read Replica 建立 (Phase 5)**:
```
Replica 總儲存: 4,800 GB

額外配置:
├── bingo-prd-replica1: 3,200 GB
├── bingo-prd-backstage-replica1: 1,600 GB
└── Replica Backup: 7,200 GB (1.5x capacity)
```

**總計儲存需求**:
- 主實例 + Replica: ~12,750 GB
- 備份儲存: ~19,200 GB

---

## 🧪 測試與驗證計畫

### 資料完整性驗證

#### 自動化驗證腳本

```bash
#!/bin/bash
# validate-migration.sh

SOURCE_DB="<rds-endpoint>"
TARGET_DB="<oci-endpoint>"

echo "=== 資料完整性驗證 ==="

# 1. 行數驗證
psql -h $SOURCE_DB -U postgres -d loyalty -t -c "
SELECT schemaname, tablename,
       (SELECT count(*) FROM loyalty.tablename) as row_count
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
" > /tmp/source_rowcounts.txt

psql -h $TARGET_DB -U postgres -d loyalty -t -c "
SELECT schemaname, tablename,
       (SELECT count(*) FROM loyalty.tablename) as row_count
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
" > /tmp/target_rowcounts.txt

diff /tmp/source_rowcounts.txt /tmp/target_rowcounts.txt
if [ $? -eq 0 ]; then
  echo "✅ 行數驗證: PASS"
else
  echo "❌ 行數驗證: FAIL"
  exit 1
fi

# 2. Checksum 驗證 (抽樣 10% 資料)
# 3. 索引與約束驗證
# 4. 外鍵關係驗證
```

### 效能基準測試

```bash
# pgbench 效能測試
pgbench -h $SOURCE_DB -U postgres -d loyalty -c 50 -j 10 -T 300
pgbench -h $TARGET_DB -U postgres -d loyalty -c 50 -j 10 -T 300

# 對比報告
- 每秒事務數 (TPS)
- 平均延遲 (Latency)
- 95th percentile 延遲
```

---

## 🔄 回退與災難恢復計畫

### 回退策略

#### 回退決策樹

```
遷移後出現問題
    │
    ├─ 資料不一致?
    │   └─> 立即回退到 RDS (GoldenGate reverse replication)
    │
    ├─ 效能問題?
    │   ├─ 可調校? ──> 調整參數後繼續
    │   └─ 無法調校? ──> 回退到 RDS
    │
    └─ 應用相容性問題?
        ├─ 可修復? ──> 修復應用後繼續
        └─ 無法修復? ──> 回退到 RDS
```

#### 回退時間窗口

| 遷移後時間 | 回退難度 | 回退時間 | 說明 |
|-----------|---------|---------|------|
| 0-4 小時 | 簡單 | < 30 分鐘 | DNS 切換即可 |
| 4-24 小時 | 中等 | 1-2 小時 | 可能需要資料同步 |
| 1-7 天 | 困難 | 4-6 小時 | 需要反向複製 |
| > 7 天 | 非常困難 | 不建議 | 考慮前滾修復 |

#### 回退執行步驟

```bash
# 緊急回退 SOP (Standard Operating Procedure)

# 1. 立即暫停應用寫入 OCI
kubectl scale deployment app --replicas=0

# 2. 驗證 RDS 資料狀態
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd --query 'DBInstances[0].DBInstanceStatus'

# 3. DNS 切換回 RDS
# (執行 DNS 更新腳本)

# 4. 恢復應用連線
kubectl scale deployment app --replicas=5

# 5. 驗證應用正常運作
curl -I https://api.ftgaming.cc/health

# 6. 通知團隊與相關人員
# (Slack 通知)
```

---

## 📋 時間表與檢查點

### Gantt Chart 概覽

```
Phase 0: 準備階段                [========] 2 週
Phase 1: OCI 環境建置與網路連線   [====]     1-2 週
Phase 2: 小型生產實例遷移驗證     [====]     2 週
Phase 3: 中型生產實例遷移         [======]   2-3 週
Phase 4: 最大生產實例遷移         [========] 3-4 週
Phase 5: OCI Read Replica 建立    [===]      1-2 週
Phase 6: 最終清理與優化          [====]     2 週
--------------------------------------------------------------
總時間: 8-10 週 (約 2-2.5 個月) 🎯 優化後時程
註：透過階段並行與流程優化，實際執行時間可控制在 8-10 週內
```

### 關鍵里程碑

| 里程碑 | 預計完成時間 | 成功標準 | 負責人 |
|-------|------------|---------|--------|
| **M1: OCI 環境就緒** | Week 2 | OCI 生產環境、Equinix 網路、GoldenGate 部署完成 | DevOps Team |
| **M2: 小型實例遷移完成** | Week 4 | bingo-prd-loyalty (200GB) 遷移成功並穩定運行 | DBA Team |
| **M3: 中型實例遷移完成** | Week 7 | bingo-prd (2750GB) 遷移成功並穩定運行 | Migration Team |
| **M4: 最大實例遷移完成** | Week 10 | bingo-prd-backstage (5024GB) 遷移成功 | All Teams |
| **M5: Read Replica 建立完成** | Week 12 | 兩個 Read Replica 建立完成並驗證複製延遲 | DBA Team |
| **M6: AWS RDS 清理** | Week 14 | AWS RDS 資源釋放，OCI 環境優化完成 | DevOps + Management |

---

## 💰 成本分析

### 初步成本估算 (每月)

#### OCI 運算成本

| 資源類型 | 規格 | 數量 | 單價 (USD/月) | 小計 |
|---------|------|-----|-------------|------|
| DB System (4 OCPU) | VM.Standard.E4.Flex | 3 | $400 | $1,200 |
| DB System (2 OCPU) | VM.Standard.E4.Flex | 2 | $200 | $400 |
| Block Volume | High Performance 15,500 GB | 1 | $0.085/GB | $1,318 |
| Backup Storage | 20,000 GB | 1 | $0.0255/GB | $510 |
| Oracle GoldenGate | Standard | 1 | $800 | $800 |
| **總計** | | | | **$4,228/月** |

#### AWS RDS 當前成本 (估算)

| 實例類型 | 數量 | 估算成本 (USD/月) |
|---------|-----|---------------|
| db.m6g.large | 3 | $3,600 |
| db.t4g.medium | 3 | $900 |
| db.t3.small/micro | 2 | $100 |
| Storage (gp3) | 12,608 GB | $1,260 |
| IOPS (額外) | | $400 |
| **總計** | | **$6,260/月** |

#### 成本節省

```
年度節省: ($6,260 - $4,228) × 12 = $24,384 USD
投資回報率 (ROI): 38.9% annual savings
```

**額外考量**:
- 一次性遷移成本: $15,000-25,000 (人力 + GoldenGate 授權)
- 回本期: 8-12 個月

---

## 👥 團隊與職責

### 專案組織架構

```
專案總監 (Project Sponsor)
    │
專案經理 (Project Manager)
    │
    ├─ 技術組長 (Technical Lead)
    │   ├─ DBA Team (3 人)
    │   │   ├─ RDS 專家
    │   │   ├─ OCI 專家
    │   │   └─ GoldenGate 專家
    │   │
    │   ├─ DevOps Team (2 人)
    │   │   ├─ 網路與安全
    │   │   └─ CI/CD 與自動化
    │   │
    │   └─ 應用團隊 (2 人)
    │       ├─ 後端開發
    │       └─ 前端開發
    │
    └─ QA Team (2 人)
        ├─ 測試規劃
        └─ 驗證執行
```

### RACI 矩陣

| 任務 | 專案經理 | DBA | DevOps | 應用團隊 | QA |
|------|---------|-----|--------|---------|-----|
| 遷移計畫審批 | **A** | C | C | C | I |
| OCI 環境建置 | A | C | **R** | I | I |
| GoldenGate 部署 | A | **R** | C | I | I |
| 資料遷移執行 | A | **R** | C | I | C |
| 應用切換 | A | C | **R** | **R** | C |
| 驗證測試 | A | C | C | C | **R** |
| 問題排查 | A | **R** | **R** | C | C |

**圖例**: R=Responsible, A=Accountable, C=Consulted, I=Informed

---

## 📞 溝通計畫

### 例行會議

| 會議 | 頻率 | 參與者 | 目的 |
|------|------|--------|------|
| **專案啟動會議** | 一次 | 全員 | 對齊目標與期望 |
| **每週進度會議** | 週一 | 技術團隊 | 進度追蹤與風險管理 |
| **每日站立會議** | 每天 (遷移期) | DBA + DevOps | 快速同步 |
| **階段審查會議** | 每階段結束 | 全員 + 管理層 | 里程碑驗收 |

### 通知機制

```yaml
# Slack 通知策略
channels:
  - name: "#ops-migration"
    notifications:
      - 遷移進度更新
      - 重要里程碑完成
      - 問題與風險報告

  - name: "#ops-alerts"
    notifications:
      - CloudWatch/OCI 告警
      - GoldenGate 錯誤
      - 效能異常

  - name: "#ops-oncall"
    notifications:
      - 緊急事件 (P1/P0)
      - 回退決策
```

---

## 🚨 風險管理

### 風險矩陣

| 風險 | 可能性 | 影響 | 風險等級 | 緩解策略 |
|------|--------|------|---------|---------|
| **資料遺失** | 低 | 極高 | 🔴 高 | • GoldenGate 持續複製<br>• 多重備份<br>• 分階段驗證 |
| **停機時間超出預期** | 中 | 高 | 🟡 中 | • 充分測試<br>• 快速回退機制<br>• 週末執行 |
| **效能下降** | 中 | 中 | 🟡 中 | • 基準測試<br>• 資源緩衝 20%<br>• 持續監控 |
| **應用相容性問題** | 中 | 中 | 🟡 中 | • 測試環境先行<br>• SQL 語法審查<br>• 應用程式碼檢視 |
| **成本超出預算** | 低 | 低 | 🟢 低 | • 詳細成本估算<br>• 分階段投入<br>• 費用監控 |
| **團隊技能不足** | 中 | 中 | 🟡 中 | • Oracle 培訓<br>• 顧問支援<br>• 知識轉移 |

### 應急計畫

#### P0 緊急事件 (資料遺失/服務中斷)

```
1. 立即啟動戰情室 (War Room)
2. 通知所有關鍵人員 (電話 + Slack)
3. 評估影響範圍
4. 決策: 回退 or 前滾修復
5. 執行應急方案
6. 持續溝通與更新
7. 事後檢討 (Post-Mortem)
```

---

## 📚 參考資源

### Oracle 官方文檔
- [PostgreSQL Import/Export/Migrate](https://docs.oracle.com/en-us/iaas/Content/postgresql/import-export-migrate.htm)
- [Oracle GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- [Oracle Cloud Guard](https://www.oracle.com/security/cloud-security/cloud-guard/)
- [OCI Database Service](https://docs.oracle.com/en-us/iaas/Content/Database/home.htm)

### 內部文檔
- [RDS 實例清單與配置](../README.md)
- [CloudWatch 監控設定](../CLOUDWATCH_BINGO_STRESS_ANALYSIS.md)
- [JIRA OPS-1033: Storage Autoscaling](../JIRA_BINGO_PRD_REPLICA1_STORAGE_20260108.md)
- [JIRA OPS-1110: ReadIOPS 告警調整](../RDS_BINGO_BACKSTAGE_REPLICA1_READIOPS_THRESHOLD_UPDATE.md)

### 工具與腳本
- [RDS 管理腳本](../../scripts/rds/)
- [CloudWatch 腳本](../../scripts/cloudwatch/)
- [CloudFormation 模板](../../cloudformation/rds/)

---

## 📝 附錄

### A. GoldenGate 配置檔完整範例

#### Extract 配置 (INI)
```properties
-- extract_ini.prm
EXTRACT INIT_LOAD
SOURCEDB bingo-prd.<rds-endpoint>:5432, USERID migration_user, PASSWORD <password>
EXTTRAIL ./dirdat/in
INITIALLOADOPTIONS USESNAPSHOT, NOUSEDEFAULTS
DBOPTIONS CONNECTIONRETRYCOUNT 10, CONNECTIONRETRYWAIT 30
FETCHOPTIONS USESNAPSHOT, FETCHPKUPDATECOLS
TABLE public.*;
```

#### Extract 配置 (CDC)
```properties
-- extract_cdc.prm
EXTRACT CDC_LOAD
SOURCEDB bingo-prd.<rds-endpoint>:5432, USERID migration_user, PASSWORD <password>
EXTTRAIL ./dirdat/cd
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT
GETUPDATEBEFORES
TRANLOGOPTIONS FILTERTABLE public.*
TRANLOGOPTIONS EXCLUDEUSER migration_user
TABLE public.*;
```

#### Replicat 配置
```properties
-- replicat.prm
REPLICAT REP_OCI
TARGETDB <oci-endpoint>:5432, USERID replication_user, PASSWORD <password>
DISCARDFILE ./dirrpt/rep_oci.dsc, PURGE
ASSUMETARGETDEFS
MAP public.*, TARGET public.*;
REPERROR DEFAULT, DISCARD
DBOPTIONS DEFERREFCONST
```

### B. 網路連線配置

#### AWS VPN 設定
```bash
# Customer Gateway 配置
aws --profile gemini-pro_ck ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip <OCI-VPN-Public-IP> \
  --bgp-asn 65000

# VPN Connection 建立
aws --profile gemini-pro_ck ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id cgw-xxx \
  --vpn-gateway-id vgw-xxx \
  --options TunnelOptions=[{PreSharedKey=<strong-psk>}]
```

#### OCI IPSec VPN 配置
```hcl
# OCI Terraform 配置範例
resource "oci_core_ipsec" "aws_vpn" {
  compartment_id = var.compartment_id
  cpe_id         = oci_core_cpe.aws_cpe.id
  drg_id         = oci_core_drg.main.id
  static_routes  = ["10.0.0.0/16"]  # AWS VPC CIDR
}
```

### C. 監控告警模板

#### OCI Monitoring Query (MQL)
```sql
-- CPU 使用率告警
CpuUtilization[1m]{resourceId = "ocid1.dbsystem.xxx"}.mean() > 80

-- 儲存使用率告警
StorageUtilization[5m]{resourceId = "ocid1.dbsystem.xxx"}.mean() > 85

-- Active Sessions 告警
ActiveSessions[1m]{resourceId = "ocid1.dbsystem.xxx"}.sum() > 100
```

---

## 📋 快速參考檢查清單

### 遷移前檢查 (Pre-Migration Checklist)

#### 環境準備
- [ ] OCI 帳號與專案建立完成
- [ ] 網路連線 (VPN/Direct Connect) 測試通過
- [ ] OCI 實例建立與配置完成
- [ ] IAM 權限與存取控制設定完成
- [ ] 所有 RDS 實例完整備份

#### RDS 配置變更
- [ ] `wal_level = logical` 設定完成
- [ ] `max_replication_slots` 增加到 5
- [ ] `max_wal_senders` 增加到 5
- [ ] 遷移專用使用者建立與授權
- [ ] 參數組變更已重啟生效

#### GoldenGate 準備
- [ ] GoldenGate 實例部署完成
- [ ] Extract/Replicat 配置檔準備就緒
- [ ] 連線測試通過 (RDS ↔ GoldenGate ↔ OCI)
- [ ] Trail 檔案目錄空間充足
- [ ] Checkpoint 與錯誤日誌監控設定完成

### 遷移中檢查 (During Migration Checklist)

#### INI 階段
- [ ] Extract INIT_LOAD 啟動成功
- [ ] 監控載入進度 (INFO EXTRACT DETAIL)
- [ ] 檢查錯誤日誌 (ggserr.log)
- [ ] 資料行數初步驗證

#### CDC 階段
- [ ] Extract CDC_LOAD 啟動成功
- [ ] Replicat 啟動成功
- [ ] Lag 監控 < 5 秒
- [ ] 無 ABENDED 狀態
- [ ] 增量資料正確複製

### 遷移後檢查 (Post-Migration Checklist)

#### 資料驗證
- [ ] 所有表格行數一致
- [ ] Checksum 驗證通過
- [ ] 索引與約束完整
- [ ] 外鍵關係正確
- [ ] 隨機抽樣驗證通過

#### 效能驗證
- [ ] 基準測試達標
- [ ] 查詢效能無明顯下降
- [ ] IOPS 與吞吐量符合預期
- [ ] 連線數與併發處理正常

#### 應用驗證
- [ ] 應用連線成功
- [ ] 所有 API 端點正常
- [ ] 使用者功能測試通過
- [ ] 錯誤日誌無異常

#### 監控與告警
- [ ] OCI Monitoring Dashboard 設定完成
- [ ] Cloud Guard 監控啟用
- [ ] 所有告警規則複製到 OCI
- [ ] Slack 通知整合測試通過

---

## 🎯 下一步行動

### 立即行動 (本週)
1. **專案啟動會議**: 召集所有相關人員，對齊目標與期望
2. **OCI 帳號申請**: 開始 OCI 註冊與專案設定流程
3. **技能評估**: 評估團隊 OCI 與 GoldenGate 技能缺口
4. **成本預算審批**: 提交成本估算給管理層審批

### 短期行動 (本月)
1. **Oracle 培訓**: 安排 OCI 與 GoldenGate 培訓課程
2. **OCI 網路設計**: 完成 VCN、Subnet、Security List 設計
3. **風險評估工作坊**: 與團隊一起識別更多潛在風險
4. **測試環境建置**: 開始建置 OCI 測試環境

### 中期行動 (下季)
1. **測試遷移執行**: 完成 pgsqlrel 測試實例遷移
2. **GoldenGate POC**: 驗證 GoldenGate 在真實環境的表現
3. **應用相容性測試**: 測試應用在 OCI 上的相容性
4. **回退流程演練**: 執行至少 1 次完整回退演練

---

**文檔維護**
- **負責人**: DevOps Team + DBA Team
- **審查週期**: 每 2 週更新一次
- **版本管理**: Git repository (docs/oci-migration/)
- **變更通知**: Slack #ops-migration 頻道

---

**批准簽名**

| 角色 | 姓名 | 簽名 | 日期 |
|------|------|------|------|
| 專案經理 | | | |
| 技術組長 | | | |
| DBA 主管 | | | |
| DevOps 主管 | | | |
| CTO | | | |

---

**版本歷史**

| 版本 | 日期 | 變更摘要 | 作者 |
|------|------|---------|------|
| 1.0 | 2026-01-20 | 初始版本，完整遷移規劃 | Claude + lonely.h |

---

*此文檔為 aws-gemini-manager RDS to OCI Migration 專案的核心規劃文件*

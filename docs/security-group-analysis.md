# AWS Security Groups 詳細分析報告

**分析日期**: 2025-10-28 17:08:34
**AWS Region**: ap-east-1
**VPC**: vpc-086d3d02c471379fa

---

## 執行摘要

### 判斷結果: **是，中等混亂** 🟡

**混亂程度**: 中等 (評分: 5/10)

**主要問題**:
- 中等未使用率: 29.8%
- 存在高風險安全群組: 4 個
- 命名模式過多: 34 種

### 關鍵指標

| 指標 | 數值 | 狀態 |
|------|------|------|
| 總 Security Groups 數量 | 161 | ℹ️ |
| 已使用 | 111 (68.9%) | ⚠️ |
| 未使用 | 48 (29.8%) | ⚠️ |
| 高風險 | 4 | 🔴 |
| 中風險 | 7 | 🟡 |
| SSH 暴露於網際網路 | 3 | 🔴 |
| 資料庫端口暴露 | 1 | 🔴 |

---

## 1. Security Group 清單與分類

### 1.1 總體統計

- **總數**: 161 個 Security Groups
- **已使用**: 111 個
- **未使用**: 48 個
- **使用率**: 68.9%

### 1.2 VPC 分布

- **vpc-086d3d02c471379fa**: 160 個 Security Groups
- **vpc-0eba0aa238499be53**: 1 個 Security Groups

### 1.3 命名規範檢查

發現 **34** 種不同的命名模式，顯示缺乏統一的命名規範。

#### Top 15 命名前綴:

| 前綴 | 數量 | 說明 |
|------|------|------|
| Hash | 40 | ✅ 服務相關 |
| ELS | 16 | ✅ 服務相關 |
| Bingo | 16 | ✅ 服務相關 |
| launch | 9 | ⚠️ 自動產生 |
| hash | 8 | ℹ️ |
| bingo | 7 | ℹ️ |
| ec2 | 6 | ℹ️ |
| rds | 6 | ℹ️ |
| Prd | 6 | ℹ️ |
| eksctl | 6 | ⚠️ 自動產生 |
| CyberGame | 4 | ℹ️ |
| no-prefix | 4 | ❌ 無前綴 |
| rng | 4 | ℹ️ |
| arcade | 3 | ℹ️ |
| pgsqlrel | 3 | ℹ️ |

**觀察**:
- 存在大小寫不一致問題 (Hash vs hash, Bingo vs bingo)
- 包含自動產生的 launch-wizard 和 eksctl 安全群組
- 缺乏統一的命名規範和前綴策略

---

## 2. 規則配置分析

### 2.1 規則統計

| 類型 | 數量 | 平均值 |
|------|------|--------|
| Inbound 規則總數 | 494 | 3.1 /SG |
| Outbound 規則總數 | 154 | 1.0 /SG |
| 開放 0.0.0.0/0 規則 | 25 | - |

### 2.2 規則複雜度分析

#### Top 10 規則最複雜的 Security Groups:

| Security Group | Inbound | Outbound | 使用中 | 風險等級 |
|----------------|---------|----------|--------|----------|
| Bingo-Rel-Srv-01-SG<br>`sg-04ad34d55b120b90c` | 10 | 1 | ✅ | 🟢 LOW |
| ELS-Deploy-Srv-01-SG<br>`sg-0e43417b61c5b2b11` | 9 | 1 | ✅ | 🟢 LOW |
| Bingo-Prd-Steampunk2-Game-01-sg<br>`sg-0b793ab578baddb92` | 9 | 1 | ✅ | 🟢 LOW |
| hash-prd-minessc-game-01-sg<br>`sg-03dce49708b3c12ae` | 8 | 1 | ✅ | 🟢 LOW |
| Hash-Prd-MinesPM-Game-01-sg<br>`sg-097264cbb7506e214` | 8 | 1 | ✅ | 🟢 LOW |
| hash-prd-luckydropcoc2-game-01-sg<br>`sg-0d8b3d96b06eed173` | 8 | 1 | ✅ | 🟢 LOW |
| hash-prd-aviator2xin-game-01-sg<br>`sg-02e453056d5a92bc7` | 8 | 1 | ✅ | 🟢 LOW |
| hash-prd-egypthilo-game-01-sg<br>`sg-0158682c503fd433d` | 8 | 1 | ✅ | 🟢 LOW |
| hash-prd-aviator2-game-01-sg<br>`sg-0a5c47c1b7b316b74` | 8 | 1 | ✅ | 🟢 LOW |
| arcade-prd-goldenclover-game-01-sg<br>`sg-0c582bafd1d923ab6` | 8 | 1 | ✅ | 🟢 LOW |

---

## 3. 安全性評估

### 🔴 3.1 高風險項目

⚠️ 發現 **4** 個高風險 Security Groups:

#### launch-wizard-8 (`sg-05898bd6e3161be6f`)

- **VPC**: vpc-086d3d02c471379fa
- **使用狀態**: ❌ 未使用
- **Inbound 規則**: 1
- **Outbound 規則**: 1
- **風險原因**:
  - SSH (22) exposed to 0.0.0.0/0
  - Poor naming or missing description

#### launch-wizard-4 (`sg-03b1fdabc1df23f8d`)

- **VPC**: vpc-086d3d02c471379fa
- **使用狀態**: ❌ 未使用
- **Inbound 規則**: 2
- **Outbound 規則**: 1
- **風險原因**:
  - SSH (22) exposed to 0.0.0.0/0
  - Poor naming or missing description

#### launch-wizard-3 (`sg-06083c987e193d5c2`)

- **VPC**: vpc-086d3d02c471379fa
- **使用狀態**: ❌ 未使用
- **Inbound 規則**: 1
- **Outbound 規則**: 1
- **風險原因**:
  - SSH (22) exposed to 0.0.0.0/0
  - Poor naming or missing description

#### default (`sg-0b61e76dc9f88d6ba`)

- **VPC**: vpc-086d3d02c471379fa
- **使用狀態**: ❌ 未使用
- **Inbound 規則**: 1
- **Outbound 規則**: 1
- **風險原因**:
  - Database port 5432 exposed to 0.0.0.0/0

#### SSH 端口暴露詳情

以下 Security Groups 的 SSH (22) 端口暴露於網際網路 (0.0.0.0/0):

| Security Group ID | 名稱 | 使用者 |
|-------------------|------|--------|
| `sg-05898bd6e3161be6f` | launch-wizard-8 | N/A |
| `sg-03b1fdabc1df23f8d` | launch-wizard-4 | N/A |
| `sg-06083c987e193d5c2` | launch-wizard-3 | N/A |

#### 資料庫端口暴露詳情

以下 Security Groups 的資料庫端口暴露於網際網路:

| Security Group ID | 名稱 | 端口 | 使用者 |
|-------------------|------|------|--------|
| `sg-0b61e76dc9f88d6ba` | default | 5432 | N/A |

### 🟡 3.2 中風險項目

發現 **7** 個中風險 Security Groups:

| Security Group | 使用狀態 | Inbound | 主要問題 |
|----------------|----------|---------|----------|
| launch-wizard-2<br>`sg-031cc340e48782c54` | ❌ | 3 | Poor naming or missing description |
| launch-wizard-9<br>`sg-071d1b5cadfa470c8` | ❌ | 1 | Poor naming or missing description |
| launch-wizard-7<br>`sg-0a140c00b7db077ba` | ❌ | 1 | Poor naming or missing description |
| launch-wizard-6<br>`sg-020f2f378a827b5c1` | ❌ | 1 | Poor naming or missing description |
| launch-wizard-5<br>`sg-06c0ec9552ab4c101` | ❌ | 1 | Poor naming or missing description |
| hash-prd<br>`sg-0f958b367be5db131` | ❌ | 24 | Too many inbound rules (24) |
| launch-wizard-1<br>`sg-0bdf1660fd193b9b3` | ❌ | 1 | Poor naming or missing description |

### 🟢 3.3 良好實踐

有 **150** 個 Security Groups 符合基本安全標準:

- 無敏感端口暴露於網際網路
- 規則數量合理
- 配置相對安全

---

## 4. 組織結構評估

### 4.1 整體組織性

❌ 大量未使用的 Security Groups (48 個，佔 29.8%)
❌ 命名模式過多 (34 種)，缺乏統一規範
❌ 存在大量自動產生的 launch-wizard Security Groups (9 個)

### 4.2 未使用的 Security Groups

發現 **48** 個未使用的 Security Groups，建議清理:

| ID | 名稱 | VPC |
|----|------|-----|
| `sg-07871900a6abcf39a` | CyberGame-Rel-Srv-01-SG | vpc-086d3d02c471379fa |
| `sg-0c4cf0cc210452f34` | CyberGame-Dev-MW-Srv-01-SG | vpc-086d3d02c471379fa |
| `sg-0930a92b410571fa0` | rds-ec2-6 | vpc-086d3d02c471379fa |
| `sg-0884f3055ef410a80` | k8s-traffic-geminigameprd-7d00461c40 | vpc-086d3d02c471379fa |
| `sg-05898bd6e3161be6f` | launch-wizard-8 | vpc-086d3d02c471379fa |
| `sg-03b1fdabc1df23f8d` | launch-wizard-4 | vpc-086d3d02c471379fa |
| `sg-08b990a8dba4113f1` | Gitlab-Oauth-in | vpc-086d3d02c471379fa |
| `sg-09780edcfc7e58aaf` | n8n | vpc-086d3d02c471379fa |
| `sg-07192c23a6f10489b` | Common-RDS-Service-SG | vpc-086d3d02c471379fa |
| `sg-07fa35ac8c8d451a6` | ec2-rds-1 | vpc-086d3d02c471379fa |
| `sg-047ad54207bdd8ec8` | dev-mks-cluster-sg | vpc-086d3d02c471379fa |
| `sg-03261a53a1cacd5a9` | From-ELS-Jenkins-Slave-Builder-02 | vpc-086d3d02c471379fa |
| `sg-06083c987e193d5c2` | launch-wizard-3 | vpc-086d3d02c471379fa |
| `sg-0ed422844a9fd0d1a` | pgsqlrel-replica1-SG | vpc-086d3d02c471379fa |
| `sg-06c926c920314ea25` | rng-stg-srv-01-sg | vpc-086d3d02c471379fa |
| `sg-0a12d9bdcc9984884` | ALB-eks-prd-argocd | vpc-086d3d02c471379fa |
| `sg-02c7b9efb8b1b46ef` | bingo-prd-steampunk2-game-01 | vpc-086d3d02c471379fa |
| `sg-0758000ec313985e5` | rds-ec2-2 | vpc-086d3d02c471379fa |
| `sg-0658bbf397befa9cc` | Prd-Nginx-Srv-01-SG | vpc-086d3d02c471379fa |
| `sg-031cc340e48782c54` | launch-wizard-2 | vpc-086d3d02c471379fa |
| ... | ... | ... |
| | *還有 28 個未列出* | |

---

## 5. 改善建議摘要

### 優先級分類

#### 🔴 P0 - 立即處理 (安全風險)
1. 修復 3 個 SSH 端口暴露問題
2. 修復 1 個資料庫端口暴露問題

#### 🟡 P1 - 短期改善 (30 天內)
1. 清理 48 個未使用的 Security Groups
2. 處理 7 個中風險項目
3. 建立統一的命名規範

#### 🟢 P2 - 長期優化 (90 天內)
1. 整合和簡化過於複雜的規則
2. 為所有 Security Groups 添加有意義的描述
3. 建立定期審查機制
4. 實施基礎設施即代碼 (IaC) 管理

---

## 附錄

### 資源分布統計

- EC2 使用的 Security Groups: 100
- RDS 使用的 Security Groups: 11
- 未使用的 Security Groups: 48

### 分析方法

本報告使用 AWS CLI 和 Python 分析腳本自動生成，分析範圍包括:

- 所有 Security Groups 的基本資訊和規則配置
- EC2 和 RDS 實例的 Security Group 關聯
- 規則安全性評估 (基於業界最佳實踐)
- 組織結構和命名規範分析

---

*報告生成時間: 2025-10-28 17:08:34*

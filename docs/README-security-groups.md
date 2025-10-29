# Security Groups 分析與優化指南

## 概述

本目錄包含針對 AWS ap-east-1 區域 Security Groups 配置的完整分析報告和優化計畫。

## 分析結果摘要

**判斷**: 是，中等混亂 🟡

**混亂評分**: 5/10

### 關鍵發現

- **總 Security Groups**: 161 個
- **使用率**: 68.9% (111 個使用中，48 個未使用)
- **高風險項目**: 4 個
- **中風險項目**: 7 個
- **SSH 暴露**: 3 個 Security Groups
- **資料庫端口暴露**: 1 個 Security Group
- **命名模式**: 34 種不同模式（缺乏統一規範）

### 主要問題

1. 未使用率偏高 (29.8%)
2. 存在安全風險（SSH 和資料庫端口暴露於網際網路）
3. 命名規範不統一
4. 包含大量自動產生的 launch-wizard Security Groups

## 文檔結構

```
docs/
├── README-security-groups.md              # 本文件
├── security-group-analysis.md             # 詳細分析報告
└── security-group-optimization-plan.md    # 優化行動計畫

scripts/
└── check-sg-risks.sh                      # 快速風險檢查腳本
```

## 文檔說明

### 1. security-group-analysis.md

**詳細分析報告**，包含：

- 執行摘要和混亂度判斷
- Security Group 清單與分類
- 規則配置分析
- 安全性評估（高/中/低風險分類）
- 組織結構評估
- 改善建議摘要

**適用對象**: DevOps 團隊、安全團隊、管理層

### 2. security-group-optimization-plan.md

**優化行動計畫**，包含：

- 分階段優化步驟
- 具體執行命令
- 風險評估和回滾計畫
- 成功指標和檢查清單
- Terraform 範例和自動化建議

**適用對象**: DevOps 工程師、實際執行優化的人員

### 3. check-sg-risks.sh

**快速風險檢查腳本**，用於：

- 即時檢查 SSH 端口暴露
- 檢查 RDP 端口暴露
- 檢查資料庫端口暴露
- 統計未使用的 Security Groups
- 計算風險評分

## 使用方式

### 快速風險檢查

```bash
# 執行風險檢查腳本
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager
./scripts/check-sg-risks.sh
```

輸出範例：
```
========================================
Security Group Risk Assessment
========================================

🔍 Checking for SSH (22) exposed to 0.0.0.0/0...
  🔴 WARNING: Found SSH exposed to internet:
    - sg-xxxxx launch-wizard-8

Overall Risk Score: 5/10
🟡 MEDIUM RISK - Action recommended
```

### 查看詳細分析

```bash
# 使用您偏好的 Markdown 閱讀器
cat docs/security-group-analysis.md

# 或在瀏覽器中查看
open docs/security-group-analysis.md
```

### 執行優化計畫

1. **閱讀優化計畫**
   ```bash
   cat docs/security-group-optimization-plan.md
   ```

2. **階段 0: 緊急安全修復（立即執行）**
   - 修復 SSH 端口暴露
   - 修復資料庫端口暴露
   - 時程: 1-2 天

3. **階段 1: 清理未使用資源（1-2 週）**
   - 備份當前配置
   - 驗證未使用狀態
   - 批量刪除未使用的 Security Groups

4. **階段 2: 標準化和規範（2-4 週）**
   - 建立命名規範
   - 重新命名或標記現有 Security Groups
   - 簡化過於複雜的規則

5. **階段 3: 自動化和持續改善（1-3 個月）**
   - 遷移到 Terraform IaC
   - 建立自動化審查流程
   - 實施變更管理流程

## 優先處理項目

### 🔴 P0 - 立即處理（安全風險）

1. **修復 SSH 端口暴露** (3 個 Security Groups)
   - `sg-05898bd6e3161be6f` (launch-wizard-8)
   - `sg-03b1fdabc1df23f8d` (launch-wizard-4)
   - `sg-09b3efc0a2e8b95bd` (launch-wizard-11)

2. **修復資料庫端口暴露** (1 個 Security Group)
   - 檢查並限制資料庫端口存取

### 🟡 P1 - 短期改善（30 天內）

1. **清理未使用的 Security Groups** (48 個)
2. **處理中風險項目** (7 個)
3. **建立統一命名規範**

### 🟢 P2 - 長期優化（90 天內）

1. **整合和簡化規則**
2. **添加描述和標籤**
3. **建立定期審查機制**
4. **實施 IaC 管理**

## 常用命令

### 查詢特定 Security Group

```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-ids sg-xxxxx
```

### 查詢使用特定 SG 的 EC2 實例

```bash
aws ec2 describe-instances \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --filters "Name=instance.group-id,Values=sg-xxxxx" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table
```

### 備份所有 Security Groups

```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --output json > sg-backup-$(date +%Y%m%d).json
```

### 檢查 SSH 暴露

```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --filters "Name=ip-permission.from-port,Values=22" \
            "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output table
```

## 建議的命名規範

```
<環境>-<服務類型>-<用途>-sg

環境: prd (生產), stg (測試), dev (開發)
服務類型: ec2, rds, elb, eks, etc.
用途: web, api, db, cache, etc.

範例:
  prd-ec2-web-sg        # 生產環境 Web 服務器
  prd-rds-mysql-sg      # 生產環境 MySQL 資料庫
  prd-elb-public-sg     # 生產環境公開負載平衡器
  stg-ec2-api-sg        # 測試環境 API 服務器
```

## 成功指標

| 指標 | 當前值 | 目標值 | 達成時間 |
|------|--------|--------|----------|
| 高風險 Security Groups | 4 | 0 | 1 週內 |
| 中風險 Security Groups | 7 | < 3 | 1 個月內 |
| 未使用 Security Groups | 48 | < 10 | 2 週內 |
| 命名模式數量 | 34 | < 10 | 2 個月內 |
| SSH 公開暴露 | 3 | 0 | 立即 |
| 資料庫端口暴露 | 1 | 0 | 立即 |

## 風險管理

### 執行前準備

1. ✅ 完整備份所有 Security Groups 配置
2. ✅ 與團隊確認變更時間窗口
3. ✅ 準備回滾計畫
4. ✅ 通知相關團隊成員

### 執行中監控

1. 監控服務健康狀態
2. 檢查應用程式連線
3. 觀察告警系統
4. 保持溝通管道暢通

### 執行後驗證

1. 重新執行風險檢查腳本
2. 驗證所有服務正常運作
3. 更新文檔
4. 記錄經驗教訓

## 相關資源

- [AWS Security Groups Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [Terraform AWS Security Group Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS CLI Security Group Commands](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/index.html#cli-aws-ec2)

## 定期維護

建議每月執行一次風險檢查：

```bash
# 設定 cron job
0 9 1 * * /path/to/check-sg-risks.sh | mail -s "Monthly SG Audit" devops@example.com
```

## 聯絡資訊

如有問題或需要協助，請聯絡 DevOps 團隊。

---

**最後更新**: 2025-10-28
**分析工具**: AWS CLI + Python 自動化腳本
**下次審查**: 2025-11-28

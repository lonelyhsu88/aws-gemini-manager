# AWS Security Groups 優化行動計畫

**制定日期**: 2025-10-28
**目標環境**: AWS ap-east-1 / vpc-086d3d02c471379fa

---

## 執行摘要

根據詳細分析報告，當前 Security Groups 配置處於 **中等混亂** 狀態，需要進行系統性優化。
本計畫提供分階段的改善步驟，確保在提升安全性的同時不影響現有服務運行。

### 優化目標

- 🎯 消除所有高風險安全問題
- 🧹 清理 48 個未使用的 Security Groups
- 📋 建立統一的命名和管理規範
- 📊 降低配置複雜度，提高可維護性

---

## 階段 0: 緊急安全修復 (立即執行)

**時程**: 1-2 天

**目標**: 修復所有高風險安全問題

### 步驟 0.1: 修復 SSH 端口暴露

發現 3 個 Security Groups 將 SSH (22) 暴露於網際網路。

#### 1. launch-wizard-8 (`sg-05898bd6e3161be6f`)

**檢查命令**:
```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-ids sg-05898bd6e3161be6f \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

**修復選項**:

**選項 A: 限制為特定 IP (推薦)**
```bash
# 1. 先添加新的限制規則 (替換為您的辦公室 IP)
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-05898bd6e3161be6f \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_OFFICE_IP/32 \
  --description 'SSH from office'

# 2. 再移除 0.0.0.0/0 規則
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-05898bd6e3161be6f \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**選項 B: 透過堡壘機/VPN 存取 (最安全)**
```bash
# 完全移除公開的 SSH 存取
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-05898bd6e3161be6f \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# 只允許來自堡壘機的 SSH
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-05898bd6e3161be6f \
  --protocol tcp \
  --port 22 \
  --source-group BASTION_SG_ID \
  --description 'SSH from bastion only'
```

⚠️ **注意**: 執行前請確認您有其他方式可以存取這些實例！

#### 2. launch-wizard-4 (`sg-03b1fdabc1df23f8d`)

**檢查命令**:
```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-ids sg-03b1fdabc1df23f8d \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

**修復選項**:

**選項 A: 限制為特定 IP (推薦)**
```bash
# 1. 先添加新的限制規則 (替換為您的辦公室 IP)
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-03b1fdabc1df23f8d \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_OFFICE_IP/32 \
  --description 'SSH from office'

# 2. 再移除 0.0.0.0/0 規則
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-03b1fdabc1df23f8d \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**選項 B: 透過堡壘機/VPN 存取 (最安全)**
```bash
# 完全移除公開的 SSH 存取
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-03b1fdabc1df23f8d \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# 只允許來自堡壘機的 SSH
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-03b1fdabc1df23f8d \
  --protocol tcp \
  --port 22 \
  --source-group BASTION_SG_ID \
  --description 'SSH from bastion only'
```

⚠️ **注意**: 執行前請確認您有其他方式可以存取這些實例！

#### 3. launch-wizard-3 (`sg-06083c987e193d5c2`)

**檢查命令**:
```bash
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-ids sg-06083c987e193d5c2 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

**修復選項**:

**選項 A: 限制為特定 IP (推薦)**
```bash
# 1. 先添加新的限制規則 (替換為您的辦公室 IP)
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-06083c987e193d5c2 \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_OFFICE_IP/32 \
  --description 'SSH from office'

# 2. 再移除 0.0.0.0/0 規則
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-06083c987e193d5c2 \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**選項 B: 透過堡壘機/VPN 存取 (最安全)**
```bash
# 完全移除公開的 SSH 存取
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-06083c987e193d5c2 \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# 只允許來自堡壘機的 SSH
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-06083c987e193d5c2 \
  --protocol tcp \
  --port 22 \
  --source-group BASTION_SG_ID \
  --description 'SSH from bastion only'
```

⚠️ **注意**: 執行前請確認您有其他方式可以存取這些實例！

### 步驟 0.2: 修復資料庫端口暴露

發現 1 個資料庫端口暴露問題。

#### 1. default - Port 5432

```bash
# 移除公開存取
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-0b61e76dc9f88d6ba \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0

# 只允許應用層存取
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-0b61e76dc9f88d6ba \
  --protocol tcp \
  --port 5432 \
  --source-group APP_SERVER_SG_ID \
  --description 'Database access from app servers only'
```

⚠️ **注意**: 請先確認應用服務器的 Security Group ID！

### 步驟 0.3: 驗證修復

```bash
# 重新掃描高風險項目
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`] && (FromPort==`22` || FromPort==`3306` || FromPort==`5432`)]].[GroupId,GroupName]' \
  --output table
```

---

## 階段 1: 清理未使用資源 (1-2 週)

**目標**: 刪除未使用的 Security Groups，降低管理複雜度

### 步驟 1.1: 備份當前配置

```bash
# 匯出所有 Security Groups 配置
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --output json > sg-backup-$(date +%Y%m%d).json
```

### 步驟 1.2: 驗證未使用狀態

刪除前務必再次確認這些 Security Groups 確實未被使用:

```bash
# 檢查 Security Group 是否被使用
check_sg_usage() {
  SG_ID=$1
  echo "Checking $SG_ID..."
  
  # 檢查 EC2
  EC2_COUNT=$(aws ec2 describe-instances \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --filters "Name=instance.group-id,Values=$SG_ID" \
    --query 'length(Reservations[].Instances[])')
  
  # 檢查 RDS
  RDS_COUNT=$(aws rds describe-db-instances \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query "length(DBInstances[?VpcSecurityGroups[?VpcSecurityGroupId=='$SG_ID']])")
  
  # 檢查 ELB
  ELB_COUNT=$(aws elb describe-load-balancers \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query "length(LoadBalancerDescriptions[?SecurityGroups[?contains(@, '$SG_ID')]])" || echo 0)
  
  # 檢查 Network Interfaces
  ENI_COUNT=$(aws ec2 describe-network-interfaces \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --filters "Name=group-id,Values=$SG_ID" \
    --query 'length(NetworkInterfaces[])')
  
  TOTAL=$((EC2_COUNT + RDS_COUNT + ELB_COUNT + ENI_COUNT))
  echo "  EC2: $EC2_COUNT, RDS: $RDS_COUNT, ELB: $ELB_COUNT, ENI: $ENI_COUNT"
  echo "  Total usage: $TOTAL"
  
  if [ $TOTAL -eq 0 ]; then
    echo "  ✅ Safe to delete"
    return 0
  else
    echo "  ⚠️  Still in use!"
    return 1
  fi
}
```

### 步驟 1.3: 批量刪除未使用的 Security Groups

以下是 48 個可以刪除的 Security Groups:

```bash
# 批量刪除腳本
# ⚠️ 執行前請仔細檢查！

UNUSED_SGS=(
  "sg-07871900a6abcf39a"  # CyberGame-Rel-Srv-01-SG
  "sg-0c4cf0cc210452f34"  # CyberGame-Dev-MW-Srv-01-SG
  "sg-0930a92b410571fa0"  # rds-ec2-6
  "sg-0884f3055ef410a80"  # k8s-traffic-geminigameprd-7d00461c40
  "sg-05898bd6e3161be6f"  # launch-wizard-8
  "sg-03b1fdabc1df23f8d"  # launch-wizard-4
  "sg-08b990a8dba4113f1"  # Gitlab-Oauth-in
  "sg-09780edcfc7e58aaf"  # n8n
  "sg-07192c23a6f10489b"  # Common-RDS-Service-SG
  "sg-07fa35ac8c8d451a6"  # ec2-rds-1
  "sg-047ad54207bdd8ec8"  # dev-mks-cluster-sg
  "sg-03261a53a1cacd5a9"  # From-ELS-Jenkins-Slave-Builder-02
  "sg-06083c987e193d5c2"  # launch-wizard-3
  "sg-0ed422844a9fd0d1a"  # pgsqlrel-replica1-SG
  "sg-06c926c920314ea25"  # rng-stg-srv-01-sg
  "sg-0a12d9bdcc9984884"  # ALB-eks-prd-argocd
  "sg-02c7b9efb8b1b46ef"  # bingo-prd-steampunk2-game-01
  "sg-0758000ec313985e5"  # rds-ec2-2
  "sg-0658bbf397befa9cc"  # Prd-Nginx-Srv-01-SG
  "sg-031cc340e48782c54"  # launch-wizard-2
  # ... 還有 28 個
)

for SG_ID in "${UNUSED_SGS[@]}"; do
  echo "Checking and deleting $SG_ID..."
  
  # 再次驗證
  if check_sg_usage "$SG_ID"; then
    aws ec2 delete-security-group \
      --profile gemini-pro_ck \
      --region ap-east-1 \
      --group-id "$SG_ID" && \
    echo "  ✅ Deleted" || \
    echo "  ❌ Failed to delete"
  fi
  
  sleep 1  # 避免 API 限流
done
```

**預期結果**: 刪除後 Security Groups 總數將降為 ~113 個

---

## 階段 2: 標準化和規範 (2-4 週)

### 步驟 2.1: 建立命名規範

**建議的命名規範**:

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

### 步驟 2.2: 重新命名現有 Security Groups

AWS 不支援直接重新命名 Security Group，需要採用以下策略:

**選項 A: 更新標籤 (推薦快速方案)**
```bash
# 為現有 SG 添加標準化的標籤
aws ec2 create-tags \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --resources sg-xxxxx \
  --tags \
    Key=Name,Value=prd-ec2-web-sg \
    Key=Environment,Value=production \
    Key=Service,Value=web \
    Key=ManagedBy,Value=terraform
```

**選項 B: 建立新的標準化 SG 並遷移 (長期方案)**

1. 建立符合命名規範的新 Security Group
2. 複製規則到新 SG
3. 更新資源使用新 SG
4. 刪除舊 SG

### 步驟 2.3: 簡化過於複雜的規則

針對規則數量超過 20 的 Security Groups，考慮:

1. **合併相似規則**: 使用 CIDR 範圍代替多個單獨 IP
2. **使用 Security Group 引用**: 用 SG ID 替代 IP 地址
3. **拆分職責**: 將多用途 SG 拆分為專用 SG

範例:
```bash
# 不好: 為每個應用服務器添加單獨的規則
# Rule 1: 10.0.1.10/32
# Rule 2: 10.0.1.11/32
# Rule 3: 10.0.1.12/32
# ...

# 好: 使用應用服務器的 Security Group
aws ec2 authorize-security-group-ingress \
  --group-id sg-database \
  --source-group sg-app-servers \
  --protocol tcp \
  --port 3306
```

---

## 階段 3: 自動化和持續改善 (1-3 個月)

### 步驟 3.1: 遷移到基礎設施即代碼 (IaC)

**推薦: 使用 Terraform 管理 Security Groups**

```hcl
# terraform/security-groups.tf

resource "aws_security_group" "web" {
  name        = "prd-ec2-web-sg"
  description = "Security group for production web servers"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "prd-ec2-web-sg"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### 步驟 3.2: 建立自動化審查流程

```bash
#!/bin/bash
# scripts/security-group-audit.sh

# 每週執行的 Security Group 審查腳本

echo "=== Security Group Audit Report ==="
echo "Date: $(date)"
echo ""

# 檢查公開的 SSH
echo "🔍 Checking for public SSH access..."
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --filters "Name=ip-permission.from-port,Values=22" \
            "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output table

# 檢查未使用的 SG
echo ""
echo "🔍 Checking for unused Security Groups..."
# (加入檢查邏輯)

# 發送通知
# (整合 Slack/Email 通知)
```

**設定定期執行**:
```bash
# 使用 cron 每週一早上 9 點執行
0 9 * * 1 /path/to/security-group-audit.sh | mail -s "Security Group Audit" team@example.com
```

### 步驟 3.3: 實施變更管理流程

1. **所有 Security Group 變更必須通過 Pull Request**
2. **使用 Terraform Plan 預覽變更**
3. **需要至少一位 DevOps 成員審核**
4. **記錄變更原因和影響範圍**

---

## 風險評估與回滾計畫

### 潛在風險

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|--------|------|----------|
| 刪除錯誤的 SG 導致服務中斷 | 中 | 高 | 1. 執行前完整備份<br>2. 分批執行<br>3. 在非營業時間操作 |
| 修改規則導致連線中斷 | 中 | 高 | 1. 先添加新規則再刪舊規則<br>2. 保持現有連線<br>3. 準備回滾腳本 |
| API 限流導致操作失敗 | 低 | 低 | 1. 批次操作間加入延遲<br>2. 使用指數退避重試 |
| 未發現的依賴關係 | 中 | 中 | 1. 詳細記錄每個變更<br>2. 監控服務健康狀態<br>3. 保留備份至少 30 天 |

### 回滾計畫

**如果發生問題，立即執行以下步驟:**

```bash
# 1. 停止所有正在進行的變更

# 2. 從備份恢復 Security Group
BACKUP_FILE="sg-backup-YYYYMMDD.json"

# 3. 重新建立被刪除的 Security Group
aws ec2 create-security-group \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-name "recovered-sg-name" \
  --description "Recovered from backup" \
  --vpc-id vpc-086d3d02c471379fa

# 4. 恢復規則 (從備份 JSON 提取)
# ... (依據備份檔案內容)

# 5. 重新附加到受影響的資源
aws ec2 modify-instance-attribute \
  --instance-id i-xxxxx \
  --groups sg-xxxxx sg-yyyyy
```

**回滾後檢查清單**:
- [ ] 所有服務恢復正常運作
- [ ] 應用程式可以正常連線資料庫
- [ ] 負載平衡器健康檢查通過
- [ ] 監控系統無異常告警

---

## 成功指標

### 量化目標

| 指標 | 當前值 | 目標值 | 達成時間 |
|------|--------|--------|----------|
| 高風險 Security Groups | 4 | 0 | 1 週內 |
| 中風險 Security Groups | 7 | < 3 | 1 個月內 |
| 未使用 Security Groups | 48 | < 10 | 2 週內 |
| 命名模式數量 | 34 | < 10 | 2 個月內 |
| SSH 公開暴露 | 3 | 0 | 立即 |
| 資料庫端口暴露 | 1 | 0 | 立即 |

### 質化目標

- ✅ 所有 Security Groups 都有清楚的命名和描述
- ✅ 所有變更都通過 IaC (Terraform) 管理
- ✅ 建立自動化審查和告警機制
- ✅ 團隊成員了解並遵循新的規範

---

## 執行檢查清單

### 階段 0: 緊急修復 (1-2 天)
- [ ] 備份所有 Security Groups 配置
- [ ] 修復 SSH 端口暴露
- [ ] 修復資料庫端口暴露
- [ ] 驗證修復結果
- [ ] 更新文檔

### 階段 1: 清理 (1-2 週)
- [ ] 驗證未使用的 Security Groups 清單
- [ ] 與團隊確認可以刪除
- [ ] 執行刪除操作
- [ ] 驗證刪除結果

### 階段 2: 標準化 (2-4 週)
- [ ] 制定並發布命名規範
- [ ] 為現有 SG 添加標準標籤
- [ ] 簡化複雜規則
- [ ] 更新文檔和訓練材料

### 階段 3: 自動化 (1-3 個月)
- [ ] 設定 Terraform 專案
- [ ] 遷移關鍵 SG 到 Terraform
- [ ] 建立 CI/CD 流程
- [ ] 實施自動審查腳本
- [ ] 設定定期審查排程

---

## 附錄

### 有用的命令參考

```bash
# 查詢特定 Security Group 的詳細資訊
aws ec2 describe-security-groups \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-ids sg-xxxxx

# 查詢使用特定 Security Group 的所有 EC2 實例
aws ec2 describe-instances \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --filters "Name=instance.group-id,Values=sg-xxxxx" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table

# 匯出 Security Group 為 Terraform 格式
terraformer import aws \
  --resources=sg \
  --regions=ap-east-1 \
  --profile=gemini-pro_ck

# 檢查 Security Group 依賴關係
aws ec2 describe-security-group-references \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-xxxxx
```

### 相關資源

- [AWS Security Groups Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [Terraform AWS Security Group Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
- [AWS CLI Security Group Commands](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ec2/index.html#cli-aws-ec2)

---

*計畫制定時間: 2025-10-28 17:08:34*

**下一步**: 安排與團隊的審查會議，討論執行時程和資源分配。

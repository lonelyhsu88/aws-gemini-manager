# 📊 EC2 實例 SSM Agent 安裝狀態報告

**檢查日期**: 2025-11-15
**檢查方式**: AWS Systems Manager API
**總實例數**: 30 個（running）

---

## 📈 統計摘要

| 狀態 | 數量 | 百分比 |
|------|------|--------|
| ✅ 已安裝 SSM Agent | 18 | 60.0% |
| ❌ 未安裝 SSM Agent | 12 | 40.0% |

---

## ✅ 已安裝 SSM Agent 的實例 (18 個)

| Instance ID | 名稱 | 狀態 | 平台 |
|-------------|------|------|------|
| i-022db9e62aa313419 | els-deploy-srv-01 | Online | Ubuntu 22.04 |
| i-0e978ccf37bfa3b8b | gemini-confluence | Online | Amazon Linux 2 |
| i-0283c28d4f94b8f68 | gemini-elk-prd-01 | Online | Amazon Linux 2 |
| i-0743f603627230870 | gemini-elk-rel-01 | Online | Amazon Linux 2 |
| i-0cf2aa664d4740c7e | gemini-game-prd-gemini-arcade-Node | Online | Amazon Linux 2023 |
| i-09e3955191da6ce1f | gemini-game-prd-gemini-base-Node | Online | Amazon Linux 2023 |
| i-00e6a6f8c67e5eeba | gemini-game-prd-gemini-base-Node | Online | Amazon Linux 2023 |
| i-0eb6f2ce976d14cf6 | gemini-game-prd-gemini-base-Node | Online | Amazon Linux 2023 |
| i-0ef679b8b2cf01861 | gemini-game-prd-gemini-bg-Node | Online | Amazon Linux 2023 |
| i-00b4fa9eb95440011 | gemini-game-prd-gemini-bg-Node | Online | Amazon Linux 2023 |
| i-0a767b5cf0c79ec7f | gemini-game-prd-gemini-hash-Node | Online | Amazon Linux 2023 |
| i-04caa23f94167266f | gemini-game-prd-gemini-hash-Node | Online | Amazon Linux 2023 |
| i-0022ff0301db0bf1f | gemini-jenkins-slave-01 | Online | Amazon Linux 2 |
| i-0418777b5635d6e76 | gemini-jenkins-slave-02 | Online | Ubuntu 22.04 |
| i-06597e04448a24b6c | gemini-jira | Online | Amazon Linux 2 |
| i-040c741a76a42169b | **gemini-monitor-01 (Zabbix)** | Online | Amazon Linux 2 |
| i-06ff53ed9ffb2e1de | gemini-n8n-01 | Online | Amazon Linux 2 |
| i-0b3f2551636dfdbf1 | gemini-prd-logstash-01 | Online | Amazon Linux 2 |

---

## ❌ 未安裝 SSM Agent 的實例 (12 個)

| Instance ID | 名稱 | 類型 | 優先級 | 說明 |
|-------------|------|------|--------|------|
| i-0aba4c4530ac573e8 | **gemini-jenkins-master** | c5a.xlarge | 🔴 高 | 關鍵基礎設施 |
| i-00b89a08e62a762a9 | **gemini-gitlab** | c5a.xlarge | 🔴 高 | 關鍵基礎設施 |
| i-08d21e97ba490faf6 | **gemini-jump-srv-01** | t3.medium | 🔴 高 | Jump Server - 建議安裝 |
| i-0156659c38fa6ee66 | bingo-rel-srv-01 | t3.xlarge | 🟡 中 | Release 環境 |
| i-09f5b89a51db5cb7e | hash-rel-srv-01 | t3.large | 🟡 中 | Release 環境 |
| i-0845e488b033a51b2 | arcade-rel-srv-01 | t3.small | 🟡 中 | Release 環境 |
| i-016649263fc5505b0 | prod-mgmt-srv-01 | t3.small | 🟡 中 | 管理伺服器 |
| i-04f10fb3a2f51a349 | bingo-prd-ngx-01 | t3.small | 🟢 低 | Nginx（可選） |
| i-02a6f07f20bba42a6 | hash-prd-ngx-01 | t3.small | 🟢 低 | Nginx（可選） |
| i-0b7bbb281d86883f2 | gemini-common-ngx-01 | t3.small | 🟢 低 | Nginx（可選） |
| i-0a6facecc6646989e | portal-demo-ngx-01 | t3.micro | 🟢 低 | Demo 環境 |
| i-0cb4becd6ecc52aeb | gemini-vpn | t3.micro | 🟢 低 | VPN（可選） |

---

## 🎯 安裝建議

### 優先級分類

#### 🔴 高優先級（建議立即安裝）

**這些是關鍵基礎設施，強烈建議安裝 SSM Agent**：

1. **gemini-jenkins-master** (i-0aba4c4530ac573e8)
   - 原因: Jenkins Master，CI/CD 核心
   - 建議: 立即安裝，方便遠端維護

2. **gemini-gitlab** (i-00b89a08e62a762a9)
   - 原因: GitLab，程式碼倉庫
   - 建議: 立即安裝，方便遠端維護

3. **gemini-jump-srv-01** (i-08d21e97ba490faf6)
   - 原因: Jump Server，遠端存取入口
   - 建議: 立即安裝，增強管理能力

#### 🟡 中優先級（建議安裝）

**Release 環境和管理伺服器**：

4. **bingo-rel-srv-01** (i-0156659c38fa6ee66)
5. **hash-rel-srv-01** (i-09f5b89a51db5cb7e)
6. **arcade-rel-srv-01** (i-0845e488b033a51b2)
7. **prod-mgmt-srv-01** (i-016649263fc5505b0)

#### 🟢 低優先級（可選）

**Nginx 和 Demo 環境（可透過 SSH 管理）**：

8-12. Nginx 實例和 Demo/VPN 實例

---

## 💰 SSM Agent 費用

### ✅ 完全免費！

- **SSM Agent 軟體**: 免費
- **安裝**: 免費
- **Session Manager**: 免費
- **Run Command**: 免費
- **Patch Manager**: 免費

### 唯一可能費用

- **CloudWatch Logs**（如果啟用 session logging）: 可選，預設不啟用

---

## 🔧 安裝方式

### 方式 1: 自動化安裝腳本（推薦）

我們提供了自動化安裝腳本：

```bash
# 安裝到所有未安裝的實例
./scripts/ec2/install-ssm-agent-batch.sh

# 或安裝到特定實例
./scripts/ec2/install-ssm-agent-single.sh <instance-id>
```

### 方式 2: 手動安裝（透過 SSH）

#### Amazon Linux 2 / Amazon Linux 2023

```bash
# SSH 登入實例
ssh -i <key.pem> ec2-user@<instance-ip>

# 安裝 SSM Agent
sudo yum install -y amazon-ssm-agent

# 啟動服務
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

# 檢查狀態
sudo systemctl status amazon-ssm-agent
```

#### Ubuntu

```bash
# SSH 登入實例
ssh -i <key.pem> ubuntu@<instance-ip>

# 下載並安裝
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
sudo dpkg -i amazon-ssm-agent.deb

# 啟動服務
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

# 檢查狀態
sudo systemctl status amazon-ssm-agent
```

---

## ⚠️ 安裝前檢查

### 1. IAM Role 檢查

**SSM Agent 需要實例有正確的 IAM Role**：

```bash
# 檢查實例是否有 IAM Role
aws --profile gemini-pro_ck ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'
```

**必要的 IAM Policy**：
- `AmazonSSMManagedInstanceCore`（最小權限）
- 或 `AmazonEC2RoleforSSM`（舊版）

### 2. 網路連線檢查

SSM Agent 需要連線到這些 AWS 端點：
- `ssm.<region>.amazonaws.com`
- `ssmmessages.<region>.amazonaws.com`
- `ec2messages.<region>.amazonaws.com`

**解決方案**：
- 確保 Security Group 允許 HTTPS (443) 出站
- 或使用 VPC Endpoint（私有子網）

---

## 📋 安裝後驗證

### 檢查 SSM Agent 狀態

```bash
# 在實例上檢查
sudo systemctl status amazon-ssm-agent

# 從 AWS CLI 檢查
aws --profile gemini-pro_ck ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=<instance-id>"
```

### 測試 Session Manager

```bash
# 透過 Session Manager 連線（無需 SSH key）
aws --profile gemini-pro_ck ssm start-session \
  --target <instance-id>
```

---

## 🎁 SSM Agent 的好處

### 1. ✅ 無需 SSH Key

- 透過 IAM 權限控制存取
- 不需要管理 SSH private keys
- 更安全的連線方式

### 2. ✅ 遠端命令執行

```bash
# 一鍵在多個實例上執行命令
aws ssm send-command \
  --instance-ids i-xxx i-yyy i-zzz \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["df -h","free -m"]'
```

### 3. ✅ 自動化補丁管理

- 自動更新作業系統補丁
- 排程維護窗口
- 合規性報告

### 4. ✅ 審計和日誌

- 所有 session 可記錄到 CloudWatch Logs
- 符合審計要求
- 追蹤誰在何時執行了什麼命令

### 5. ✅ 參數存儲

- 安全存儲配置和密碼
- 版本控制
- 加密存儲

---

## 🔍 常見問題

### Q1: 安裝 SSM Agent 會重啟實例嗎？

**A**: ❌ **不會**。只是安裝一個背景服務，不會中斷現有服務。

### Q2: SSM Agent 會影響效能嗎？

**A**: ❌ **不會**。SSM Agent 非常輕量，CPU 和記憶體使用極低。

### Q3: 如果沒有 IAM Role 怎麼辦？

**A**: 需要先為實例附加 IAM Role：

```bash
# 1. 建立 IAM Role（如果不存在）
# 2. 將 Role 附加到實例
aws ec2 associate-iam-instance-profile \
  --instance-id <instance-id> \
  --iam-instance-profile Name=<ssm-role-name>

# 3. 重啟實例（讓 IAM Role 生效）
aws ec2 reboot-instances --instance-ids <instance-id>
```

### Q4: 私有子網的實例可以使用 SSM 嗎？

**A**: ✅ **可以**，但需要 VPC Endpoint：

```bash
# 建立必要的 VPC Endpoints
- com.amazonaws.ap-east-1.ssm
- com.amazonaws.ap-east-1.ssmmessages
- com.amazonaws.ap-east-1.ec2messages
```

---

## 📞 後續步驟

1. **檢查 IAM Roles**: 確保實例有正確的 IAM Role
2. **安裝優先級實例**: 從高優先級開始安裝
3. **測試驗證**: 安裝後測試 Session Manager 連線
4. **文件化**: 更新運維文件，記錄 SSM 使用方式

---

**報告產生時間**: 2025-11-15
**下次檢查**: 建議每季度檢查一次
**相關工具**: `scripts/ec2/check-ssm-status.sh`

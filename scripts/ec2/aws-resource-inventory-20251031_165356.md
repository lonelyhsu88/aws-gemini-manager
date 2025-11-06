# AWS 資源使用狀況完整報告

**生成時間**: 2025-10-31 16:52:01
**AWS Profile**: gemini-pro_ck
**主要區域**: ap-east-1 (Hong Kong)

---

## 📊 資源統計總覽

### 核心計算資源
| 資源類型 | 數量 | 狀態 |
|---------|------|------|
| 📦 **EC2 實例** | **95 台** | 全部運行中 |
| 🗄️ **RDS 資料庫** | **10 個** | 全部可用 |
| ⚖️ **負載均衡器** | **5 個** | ALB/NLB |
| 💾 **EBS 卷** | **101 個** | 全部使用中 |

### 儲存與網路
| 資源類型 | 數量 |
|---------|------|
| 🪣 **S3 儲存桶** | **26 個** |
| 🌐 **CloudFront 分發** | **3 個** |
| ⚡ **Lambda 函數** | **3 個** |

### 網路與安全
| 資源類型 | 數量 |
|---------|------|
| 🔒 **VPC** | **2 個** |
| 📡 **子網路** | **15 個** |
| 🛡️ **安全組** | **162 個** |

### IAM 資源
| 資源類型 | 數量 |
|---------|------|
| 👤 **IAM 用戶** | **26 個** |
| 👥 **IAM 群組** | **4 個** |
| 🎭 **IAM 角色** | **84 個** |

---

## 📦 EC2 實例詳細分析

### 按類型分類

#### 🎮 遊戲服務器 (約 60+ 台)
**Hash Games** (25+ 台):
- Mines 系列: 7 台 (ma/ne/cl/gr/pm/sc/ca/raider)
- Hilo 系列: 5 台 (ne/cl/gr/lucky/multi/egypt)
- Crash 系列: 4 台 (ne/cl/gr/main)
- Limbo 系列: 4 台 (ne/cl/gr/main)
- Plinko 系列: 4 台 (ne/cl/gr/main)
- LuckyDrop 系列: 4 台 (main/coc/coc2/gx)
- 其他: Aviator (2), Wheel, Keno, Video Poker, Diamonds, Dragon Tower

**Bingo Games** (15+ 台):
- Cave, Caribbean, Odin, Steampunk (2), Lost Ruins
- Magic, Bonus, Arcade, Maple, Egg Hunt
- Stress 測試: 3 台 (srv-01, srv-02, caribbean)

**Arcade Games** (4 台):
- MultiBoomers, ForestTeaParty, WildDiggr, GoldenClover

#### 🔧 基礎設施服務器 (35+ 台)
**開發與部署**:
- Jenkins: Master + 2 Slaves
- GitLab: 1 台
- Deploy 服務: 1 台

**監控與日誌**:
- ELK Stack: 2 台 (prd + rel)
- Prometheus + N8N: 1 台
- Monitor: 1 台
- Logstash: 1 台

**管理與協作**:
- Jira: 1 台
- Confluence: 1 台

**遊戲支援**:
- Nginx 閘道: 3 台 (bingo/hash/common)
- Backend API: 2 台 (prd + stress)
- Gate: 3 台 (bingo-prd, hash-prd, arcade-prd, bingo-stress)
- Management: 1 台
- Loyalty: 1 台
- Sync Service: 1 台
- Redis: 1 台

**Kubernetes 節點** (4 台):
- gemini-base-Node (2 台)
- gemini-hash-Node (1 台)
- gemini-arcade-Node (1 台)
- gemini-bg-Node (1 台)

**其他**:
- Jump Server: 1 台
- VPN: 1 台
- Portal Demo: 1 台
- Release 服務: 2 台 (bingo/hash/arcade)

### 按實例類型分類

| 實例類型 | 數量 | 主要用途 |
|---------|------|---------|
| **t3.micro** | ~15 台 | 小型遊戲服務 |
| **t3.small** | ~40 台 | 標準遊戲服務 |
| **t3.medium** | ~8 台 | 中型服務 |
| **t3.large** | ~5 台 | 大型服務 |
| **t3.xlarge** | ~2 台 | 高負載服務 |
| **c5a.xlarge** | ~6 台 | 計算密集型 (Jenkins, GitLab, Jira, K8s) |
| **c5a.2xlarge** | 1 台 | ELK |
| **c5.xlarge** | 1 台 | Stress 測試 |
| **c5a.xlarge** | 1 台 | Stress Gate |

---

## 🗄️ RDS 資料庫分析

### 生產環境 (6 個)
1. **bingo-prd** (db.m6g.large, 2750 GB)
   - 主資料庫
   - Replica: bingo-prd-replica1 (db.m6g.large, 2662 GB)

2. **bingo-prd-backstage** (db.m6g.large, 5024 GB)
   - 後台資料庫
   - Replica: bingo-prd-backstage-replica1 (db.t4g.medium, 1465 GB)

3. **bingo-prd-loyalty** (db.t4g.medium, 200 GB)
   - 忠誠度系統

### 壓測環境 (3 個)
1. **bingo-stress** (db.t4g.medium, 2750 GB)
2. **bingo-stress-backstage** (db.t4g.medium, 5024 GB)
3. **bingo-stress-loyalty** (db.t4g.medium, 200 GB)

### 開發環境 (1 個)
1. **pgsqlrel** (db.t3.small, 40 GB)
2. **pgsqlrel-backstage** (db.t3.micro, 40 GB)

**總儲存容量**: ~19,655 GB (約 19.2 TB)

---

## ⚖️ 負載均衡器

### Kubernetes Ingress (5 個)
1. **k8s-ingressn-nginxing** (Network LB) - Nginx Ingress
2. **k8s-istiosys-gatesvc** (ALB) - Istio Gateway
3. **k8s-istiosys-backenda** (ALB) - Backend API
4. **k8s-istiosys-openapi** (ALB) - OpenAPI
5. **k8s-argocd-argocd** (ALB) - ArgoCD

---

## 🪣 S3 儲存桶分類

### 應用儲存 (8 個)
- `img.elsgame.cc` - 圖片資源
- `vp-image.elsgame.cc`, `vp-img` - VP 圖片
- `amvua2lucy1nc29j.elsgame.cc`, `uts7rai5u7vv0q08.elsgame.cc`, `y3v9nommdvep3az` - 遊戲資源
- `s3.ftgaming-rel.cc`, `s3.geminigame.cc` - 靜態資源

### 部署與構建 (5 個)
- `production-webui` - 生產環境 UI
- `release-webui` - 發布環境 UI
- `deploy-webui-bucket` - 部署 UI
- `jenkins-build-artfs` - Jenkins 構建產物
- `s3-web-ui`, `s3-demo-web` - Demo 環境

### 日誌與監控 (3 個)
- `aws-waf-logs-470013648166-71c5f840` - WAF 日誌
- `games-svc-log` - 遊戲服務日誌
- `gemini-prometheus-thanos` - Prometheus 長期儲存

### 備份與遷移 (3 個)
- `gemini-svc-backup` - 服務備份
- `rds-snap-backups` - RDS 快照備份
- `dms-serverless-premigration-results-ei6abykjl1` - DMS 遷移結果

### 其他 (7 個)
- `gemini-campaigns-landing-pages` - 活動落地頁
- `gemini-comfyui` - ComfyUI
- `gemini-daily-reports` - 每日報告
- `els-devops` - DevOps 工具
- `renew-ssl-certification` - SSL 證書
- `ovpn.ftgaming.cc` - VPN 配置

---

## 💰 成本估算 (月度)

### EC2 實例成本
基於標準定價（香港區域）:

| 類型 | 數量 | 單價/月 | 小計/月 |
|------|------|---------|---------|
| t3.micro | 15 | $7 | $105 |
| t3.small | 40 | $15 | $600 |
| t3.medium | 8 | $30 | $240 |
| t3.large | 5 | $60 | $300 |
| t3.xlarge | 2 | $120 | $240 |
| c5a.xlarge | 6 | $124 | $744 |
| c5a.2xlarge | 1 | $248 | $248 |
| c5.xlarge | 1 | $146 | $146 |
| c5a.xlarge (gate) | 1 | $124 | $124 |
| **EC2 總計** | **95** | - | **$2,747/月** |

### RDS 資料庫成本
| 類型 | 數量 | 估算/月 | 小計/月 |
|------|------|---------|---------|
| db.m6g.large | 3 | $180 | $540 |
| db.t4g.medium | 5 | $60 | $300 |
| db.t3.small | 1 | $30 | $30 |
| db.t3.micro | 1 | $15 | $15 |
| **RDS 總計** | **10** | - | **$885/月** |

### EBS 儲存成本
- 101 個 EBS 卷，假設平均 100 GB/卷
- 總容量: ~10 TB
- 成本: $0.10/GB/月 × 10,000 GB = **$1,000/月**

### 其他服務估算
| 服務 | 估算/月 |
|------|---------|
| S3 儲存 + 傳輸 | $200 |
| 負載均衡器 (5 個) | $100 |
| CloudFront | $150 |
| 資料傳輸 | $500 |
| 其他 (Lambda, 監控等) | $100 |
| **其他總計** | **$1,050/月** |

### 📊 總成本估算

| 類別 | 月度成本 |
|------|---------|
| EC2 實例 | $2,747 |
| RDS 資料庫 | $885 |
| EBS 儲存 | $1,000 |
| 其他服務 | $1,050 |
| **總計** | **~$5,682/月** |

**年度成本**: ~$68,184

> **注意**: 這是粗略估算，實際成本可能因使用量、資料傳輸、Reserved Instances 折扣等因素而有所不同。

---

## 🎯 優化建議

### 成本優化
1. **預留實例 (Reserved Instances)**
   - 長期運行的 EC2 可節省 40-60%
   - 建議購買 1 年期 RI

2. **Savings Plans**
   - 適用於彈性工作負載
   - 可節省 20-40%

3. **Spot 實例**
   - 開發/測試環境可使用 Spot
   - 可節省 70-90%

4. **Right-Sizing**
   - 檢查 CPU/記憶體使用率
   - 降級未充分利用的實例

5. **EBS 優化**
   - 刪除未附加的 EBS 卷
   - 使用 gp3 替代 gp2
   - 壓縮快照

### 架構優化
1. **Auto Scaling**
   - 遊戲服務器實現自動擴展
   - 根據流量動態調整

2. **容器化**
   - 更多服務遷移到 Kubernetes
   - 提高資源利用率

3. **Serverless**
   - 適合的服務遷移到 Lambda
   - 降低閒置成本

### 安全優化
1. **安全組清理**
   - 162 個安全組偏多
   - 合併相似規則

2. **IAM 角色**
   - 審核 84 個角色的必要性
   - 實施最小權限原則

---

## 📈 監控建議

### 關鍵指標
1. **EC2 CPU/記憶體使用率**
2. **RDS 連接數與查詢性能**
3. **ELB 請求率與延遲**
4. **S3 存儲容量與請求數**
5. **成本與預算告警**

### 工具
- ✅ 已部署: Prometheus, ELK, CloudWatch
- 🔄 建議加強: Cost Explorer, Trusted Advisor

---

**報告結束**

# AWS Operations Log

此文件記錄所有 AWS 管理操作的歷史，供 Claude Code 在新對話時參考。

---

## 2025-10-28

### 項目初始化
- 創建 aws-gemini-manager 項目
- 設定 AWS Profile: `gemini-pro_ck`
- 創建配置文檔：CLAUDE.md, README.md, .claude/context.json

### RDS 查詢

**任務**: 查詢目前有多少 RDS instances

**執行命令**:
```bash
aws --profile gemini-pro_ck rds describe-db-instances
```

**查詢結果**:
- **總數**: 10 個 RDS 實例
- **狀態**: 全部 available
- **引擎**: 全部使用 PostgreSQL
- **區域**: ap-east-1

**實例清單**:
1. `bingo-prd` - db.m6g.large (生產主庫)
2. `bingo-prd-replica1` - db.m6g.large (生產只讀副本)
3. `bingo-prd-backstage` - db.m6g.large (生產後台)
4. `bingo-prd-backstage-replica1` - db.t4g.medium (生產後台副本)
5. `bingo-prd-loyalty` - db.t4g.medium (生產忠誠度系統)
6. `bingo-stress` - db.t4g.medium (壓測環境)
7. `bingo-stress-backstage` - db.t4g.medium (壓測後台)
8. `bingo-stress-loyalty` - db.t4g.medium (壓測忠誠度)
9. `pgsqlrel` - db.t3.small (關聯式資料庫)
10. `pgsqlrel-backstage` - db.t3.micro (關聯式資料庫後台)

**重要發現**:
- 生產環境使用較大規格 (m6g.large)
- 有設定 read replica 提升讀取效能
- 壓測環境使用較小規格 (t4g.medium)

### 用戶需求確認
- **管理方式**: 透過 Claude Code 直接查詢和管理 AWS 資源
- **不需要**: 自動創建管理腳本（除非明確要求）
- **需要**: 記錄所有操作歷史，避免下次對話遺忘
- **實作策略**: 混合使用 Shell Script (AWS CLI) 和 Python (Boto3)
  - 簡單查詢 → AWS CLI
  - 複雜操作 → Boto3

### EC2 CPU 負載查詢

**任務**: 查詢所有 EC2 instances 負載最高的

**執行命令**:
```bash
# 1. 列出所有運行中的實例 (91 個)
aws --profile gemini-pro_ck ec2 describe-instances --filters "Name=instance-state-name,Values=running"

# 2. 查詢每個實例的 CloudWatch CPU 指標（過去 15 分鐘平均）
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance_id> \
  --start-time <15min_ago> \
  --end-time <now> \
  --period 900 \
  --statistics Average
```

**查詢結果** - CPU 使用率 Top 10:
1. 🔴 `hash-rel-srv-01` (i-09f5b89a51db5cb7e) - t3.large - **41.34%** ⚠️
2. 🟠 `els-elk-prd-01` (i-0283c28d4f94b8f68) - c5a.2xlarge - 28.35%
3. 🟠 `els-elk-rel-01` (i-0743f603627230870) - t3.xlarge - 24.84%
4. 🟡 `hash-prd-gate-01` (i-038d9e1c293587c56) - t3.large - 23.52%
5. 🟡 `prd-backend-api-01` (i-0bc1598c8f115d2cf) - t3.medium - 14.55%
6. 🟡 `prd-loyalty-srv-01` (i-0adfbe22ab0170c10) - t3.large - 14.40%
7. 🟢 `Bingo-Rel-Srv-01` (i-0156659c38fa6ee66) - t3.xlarge - 11.96%
8. 🟢 `els-prometheus-n8n-01` (i-06ff53ed9ffb2e1de) - t3.medium - 11.31%
9. 🟢 `els-prd-logstash-01` (i-0b3f2551636dfdbf1) - t3.large - 10.19%
10. 🟢 `els-jenkins-slave-01` (i-0022ff0301db0bf1f) - t3.small - 9.43%

**重要發現**:
- `hash-rel-srv-01` CPU 負載最高，達 41.34%，需要關注
- ELK 相關服務（elk-prd, elk-rel）負載較高（24-28%）
- 大部分實例 CPU 使用率正常（< 15%）

### RDS 空間使用狀況查詢

**任務**: 查詢所有 RDS 資料庫的空間使用狀況

**執行命令**:
```bash
# 1. 查詢配置的儲存空間
aws --profile gemini-pro_ck rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,AllocatedStorage]'

# 2. 查詢實際使用狀況（CloudWatch FreeStorageSpace 指標）
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=<db_id> \
  --start-time <1h_ago> \
  --end-time <now> \
  --period 3600 \
  --statistics Average
```

**查詢結果** - 空間使用率 Top 5:
1. 🔴 `bingo-prd-replica1` - 2662 GB / 已用 2231 GB - **83%** ⚠️⚠️
2. 🔴 `bingo-prd` - 2750 GB / 已用 2264 GB - **82%** ⚠️⚠️
3. 🔴 `bingo-prd-backstage-replica1` - 1465 GB / 已用 1214 GB - **82%** ⚠️⚠️
4. 🟠 `bingo-stress` - 2750 GB / 已用 2219 GB - **80%** ⚠️
5. 🟠 `pgsqlrel` - 40 GB / 已用 28.53 GB - **71%**

**重要發現**:
- ⚠️ **緊急**: 3 個生產資料庫使用率超過 80%，接近容量上限
- `bingo-prd-replica1` 剩餘空間僅 430 GB
- `bingo-prd-backstage-replica1` 剩餘空間僅 250 GB
- 需要考慮擴充儲存空間或清理舊資料

**建議後續動作**:
1. 監控 `bingo-prd` 系列資料庫的空間增長趨勢
2. 檢查是否有大型表格可以歸檔
3. 設定 CloudWatch 告警（85% 閾值）
4. 評估擴充儲存空間的必要性

### RDS 儲存空間 2025 年完整趨勢分析

**任務**: 查詢所有 RDS 實例過去 300 天（2025-01-01 至今）的儲存空間變化趨勢

**執行方法**: 使用 Python + Boto3 查詢 CloudWatch 指標

**關鍵發現**:

1. **兩次大規模資料清理事件**
   - `bingo-prd-backstage`: 從 4,819 GB (96%) 降至 1,278 GB (25%) - 減少 3,541 GB
   - `bingo-stress-backstage`: 從 4,742 GB (94%) 降至 1,265 GB (25%) - 減少 3,477 GB
   - 清理時間點: 主要在 10月22-23日

2. **狀態分類**:
   - 🔴 CRITICAL (4個): bingo-prd (82%), bingo-prd-replica1 (84%), bingo-prd-backstage-replica1 (83%), bingo-stress (81%)
     - 但都呈現穩定下降趨勢，暫時安全
   - 🟠 WARNING (1個): pgsqlrel (71%) - 預計 2026-06-01 滿載
   - 🟡 MODERATE (3個): 使用率 58-64%
   - 🟢 GOOD (2個): 過度配置，使用率僅 25%

3. **成本優化機會** - 年節省潛力 $6,000-7,200
   - `bingo-prd-backstage`: 5,024 GB → 2,000 GB 建議 (節省 $302/月)
   - `bingo-stress-backstage`: 5,024 GB → 2,000 GB 建議 (節省 $302/月)
   - 合計: **$604/月 = $7,248/年**

### 三項深度分析任務（使用 Agent 並行執行）

#### 1. RDS 縮減儲存空間方法研究

**任務**: 研究所有可行的 RDS 儲存空間縮減方法並比較

**分析結果**:
- 研究了 8 種方法
- **第一推薦**: Blue/Green Deployment（AWS 2024年11月新功能）
  - 停機時間: < 1 分鐘
  - 成本: $150-350
  - 需確認 ap-east-1 區域支援
- **第二推薦**: PostgreSQL 邏輯複製
  - 停機時間: < 5 分鐘
  - 無額外服務成本
- ❌ 快照還原: AWS 不支援還原到較小儲存空間

**生成文檔**:
- `docs/rds-resize-methods-comparison.md` - 詳細方法比較

#### 2. RDS 健康度全面分析

**任務**: 分析所有 10 個 RDS 實例的健康狀況

**關鍵發現**:
- **整體健康評分**: 65/100 (🟡 需要優化)
- **緊急問題**:
  - `pgsqlrel-backstage`: 記憶體僅 50 MB 可用 (5%) - 需立即升級
  - `pgsqlrel`: 記憶體僅 520 MB 可用 (26%)
  - **IOPS 嚴重過度配置**: 6個實例使用率僅 0.5-3.8%，浪費 $5,750/月
- **安全性問題**:
  - 所有實例未啟用 Multi-AZ
  - 所有實例開放公開訪問
  - 備份保留天數不足（1-3天）
- **成本優化潛力**:
  - 當前成本: $10,232/月 ($122,784/年)
  - 優化後可節省: $6,350/月 ($76,200/年)
  - 節省比例: **57%**

**優化建議優先序**:
1. 第1週: pgsqlrel 記憶體升級 (+$40/月) + IOPS 降級 (-$5,750/月)
2. 第2-3週: 分階段執行 IOPS 優化
3. 第4週: 啟用 Multi-AZ 關鍵實例
4. 長期: Reserved Instances、安全性加固

**生成文檔**:
- `docs/rds-health-report.md` - 詳細健康報告
- `docs/rds-health-summary.md` - 執行摘要
- `docs/rds-health-visual-summary.txt` - 視覺化總覽

#### 3. Security Group 配置分析

**任務**: 分析 Security Group 是否混亂並提供優化建議

**判斷結果**: **是，中等混亂** (🟡 評分 5/10)

**統計數據**:
- 總數: 161 個 Security Groups
- 使用率: 68.9% (111個使用中，50個未使用)
- 高風險: 4個 (SSH/DB 端口暴露於網際網路)
- 命名模式: 34種不同模式，存在大小寫不一致

**主要問題**:
1. **安全風險**:
   - 3個 SG 將 SSH (22) 暴露於 0.0.0.0/0
   - 1個 SG 將資料庫端口暴露於網際網路
2. **資源浪費**: 48個 (29.8%) Security Groups 未使用
3. **管理混亂**: 命名不規範 (Hash/hash, Bingo/bingo)
4. **規則統計**: 494條 Inbound，154條 Outbound，25條開放 0.0.0.0/0

**優化建議**:
- 階段0 (緊急): 修復 SSH/DB 端口暴露 (1-2天)
- 階段1: 清理 48個未使用 Security Groups (1-2週)
- 階段2: 標準化命名和規範 (2-4週)
- 階段3: Terraform IaC 和自動化 (1-3個月)

**生成文檔**:
- `docs/security-group-analysis.md` - 詳細分析報告
- `docs/security-group-optimization-plan.md` - 優化行動計畫
- `docs/security-group-visual-summary.txt` - 視覺化摘要
- `scripts/check-sg-risks.sh` - 自動風險檢查腳本

---

## 操作記錄格式

### YYYY-MM-DD

#### 任務標題
- **任務**: 描述要做什麼
- **執行命令**: 實際執行的 AWS CLI 命令
- **查詢結果**: 簡要結果摘要
- **重要發現**: 需要注意的事項
- **後續動作**: 如有需要的後續處理

---

## 待辦事項

- 無

---

## 重要備註

1. 所有 AWS 操作使用 profile: `gemini-pro_ck`
2. 主要管理的資源：RDS, S3, EC2, CloudWatch
3. 所有操作需記錄在此文件
4. 新對話時先讀取此文件了解歷史上下文

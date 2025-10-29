# RDS 儲存空間縮減標準作業程序 (SOP) - 可靠方案

**文檔版本**: 2.0 (修訂版)
**建立日期**: 2025-10-28
**最後更新**: 2025-10-28
**適用對象**: bingo-prd-backstage (可套用至其他 RDS 實例)
**AWS Profile**: gemini-pro_ck
**AWS Region**: ap-east-1

---

## ⚠️ 重要說明

**AWS RDS 基本限制**：
- ❌ RDS **不支持**直接縮減已分配的儲存空間
- ❌ 快照還原**不支持**還原到較小容量
- ✅ 唯一可行方法：**創建新實例 + 資料遷移**

本 SOP 只包含**經過驗證、可靠的方法**。

---

## 執行摘要

**目標**: 將 `bingo-prd-backstage` 從 5024 GB 縮減到 2000 GB
**當前使用**: 1278 GB (25.4%)
**預期節省**: $302/月 ($3,624/年)
**推薦方案**: PostgreSQL 邏輯複製
**備選方案**: AWS DMS

---

## 目錄

1. [方案選擇](#方案選擇)
2. [前置準備檢查清單](#前置準備檢查清單)
3. [方案 A: PostgreSQL 邏輯複製（推薦）](#方案-a-postgresql-邏輯複製推薦)
4. [方案 B: AWS DMS（備選）](#方案-b-aws-dms備選)
5. [驗證與監控](#驗證與監控)
6. [回滾程序](#回滾程序)
7. [常見問題](#常見問題)

---

## 方案選擇

### 方案對比

| 特性 | PostgreSQL 邏輯複製 | AWS DMS | pg_dump/restore |
|------|-------------------|---------|-----------------|
| **可靠性** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **停機時間** | < 5 分鐘 | < 5 分鐘 | 18-36 小時 |
| **複雜度** | 中 | 中 | 低 |
| **額外成本** | $0 | ~$50 | $0 |
| **技術要求** | PostgreSQL 知識 | AWS 服務熟悉度 | 基本 |
| **資料同步** | 持續（CDC） | 持續（CDC） | 單次 |
| **推薦度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐☆ | ⭐⭐☆☆☆ |

### 決策樹

```
開始
  │
  ├─ 可接受 5 分鐘停機？
  │   │
  │   ├─ 是 → 有 PostgreSQL 專業知識？
  │   │   │
  │   │   ├─ 是 → 【方案 A】PostgreSQL 邏輯複製 ⭐⭐⭐⭐⭐
  │   │   │        - 停機最短
  │   │   │        - 無額外成本
  │   │   │        - 完全可控
  │   │   │
  │   │   └─ 否 → 【方案 B】AWS DMS ⭐⭐⭐⭐☆
  │   │            - 更自動化
  │   │            - AWS 原生服務
  │   │            - 額外成本 ~$50
  │   │
  │   └─ 否 → 業務無法接受任何停機
  │       │
  │       └─ 【方案 B】AWS DMS
  │            - 接近零停機
  │            - 但需要更多規劃
```

**建議**: 優先使用方案 A（PostgreSQL 邏輯複製）

---

## 前置準備檢查清單

### 1. 環境確認

**執行人員**: DevOps/DBA
**預估時間**: 30 分鐘

#### 1.1 檢查當前配置

```bash
# 查詢資料庫詳細資訊
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage \
  --region ap-east-1 \
  --output json > /tmp/rds-current-config.json

# 查看關鍵資訊
cat /tmp/rds-current-config.json | jq '.DBInstances[0] | {
  DBInstanceIdentifier,
  AllocatedStorage,
  StorageType,
  Iops,
  DBInstanceClass,
  Engine,
  EngineVersion,
  MultiAZ,
  VpcId: .DBSubnetGroup.VpcId,
  SecurityGroups: [.VpcSecurityGroups[].VpcSecurityGroupId],
  BackupRetentionPeriod,
  PreferredMaintenanceWindow,
  Endpoint: .Endpoint.Address
}'
```

**檢查項目**:
- ✅ 配置空間: 5024 GB
- ✅ 當前使用: 約 1278 GB (25%)
- ✅ 引擎版本: PostgreSQL 14.15
- ✅ 儲存類型: gp3

#### 1.2 檢查應用程式連線

```bash
# 查詢當前連線數
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --region ap-east-1
```

**記錄資訊**:
- 應用程式列表: _______________
- 連線字串位置: _______________
- 平均連線數: _______________
- 尖峰連線數: _______________

### 2. 風險評估

#### 2.1 業務影響評估

| 風險項目 | 影響程度 | 發生機率 | 緩解措施 |
|---------|---------|---------|---------|
| 短暫停機（5分鐘） | 中 | 高 | 選擇低流量時段執行 |
| 資料不一致 | 高 | 極低 | 事前完整備份 + 驗證複製延遲 |
| 應用程式無法連線 | 高 | 低 | 準備快速回滾計畫 |
| 新實例效能問題 | 中 | 極低 | 保留舊實例 7 天 |

#### 2.2 前置準備檢查表

**必須完成** (☐ 未完成 / ✅ 已完成):

- ☐ 已獲得變更管理批准（CAB Approval）
- ☐ 已通知相關團隊（開發、測試、產品）
- ☐ 已選定執行時間窗口（建議：週末或低流量時段）
- ☐ 已備份所有相關文檔和配置
- ☐ 已準備回滾計畫
- ☐ 已設定監控告警
- ☐ 技術團隊待命（至少 2 人）
- ☐ 已確認資料庫密碼和存取權限

### 3. 備份準備

#### 3.1 創建手動快照

```bash
# 創建快照（作為最後安全網）
SNAPSHOT_ID="bingo-prd-backstage-before-resize-$(date +%Y%m%d-%H%M%S)"

aws --profile gemini-pro_ck rds create-db-snapshot \
  --db-instance-identifier bingo-prd-backstage \
  --db-snapshot-identifier ${SNAPSHOT_ID} \
  --region ap-east-1 \
  --tags Key=Purpose,Value=BeforeStorageResize \
         Key=Date,Value=$(date +%Y-%m-%d) \
         Key=CreatedBy,Value=DevOps

# 等待快照完成
echo "等待快照建立完成..."
aws --profile gemini-pro_ck rds wait db-snapshot-completed \
  --db-snapshot-identifier ${SNAPSHOT_ID} \
  --region ap-east-1

echo "✅ 快照已建立: ${SNAPSHOT_ID}"
```

**預估時間**: 15-30 分鐘（視資料量而定）

#### 3.2 匯出配置

```bash
# 匯出當前所有配置
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage \
  --region ap-east-1 > backup-config-$(date +%Y%m%d).json

# 匯出參數群組
PARAM_GROUP=$(aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text \
  --region ap-east-1)

aws --profile gemini-pro_ck rds describe-db-parameters \
  --db-parameter-group-name ${PARAM_GROUP} \
  --region ap-east-1 > backup-params-$(date +%Y%m%d).json

echo "✅ 配置已備份"
```

---

## 方案 A: PostgreSQL 邏輯複製（推薦）

**停機時間**: < 5 分鐘
**總執行時間**: 2-3 天
**複雜度**: 中
**成本**: 僅雙倍 RDS 成本期間（2-3天 × $10/天 = $20-30）
**可靠性**: ⭐⭐⭐⭐⭐

### 優點
- ✅ PostgreSQL 原生功能，經過充分驗證
- ✅ 停機時間極短（< 5 分鐘）
- ✅ 無額外服務成本
- ✅ 持續資料同步（CDC）
- ✅ 完全可控，可隨時暫停或回滾

### 缺點
- ⚠️ 需要修改 `wal_level` 參數（可能需要重啟一次）
- ⚠️ 需要一定的 PostgreSQL 專業知識
- ⚠️ DDL 變更不會自動複製，需手動處理

### 前置要求

1. PostgreSQL 版本 >= 10（✅ 已滿足：14.15）
2. `wal_level` 設定為 `logical`
3. 足夠的複製插槽（replication slots）
4. 資料庫使用者有複製權限

---

### 階段 1: 準備工作 (第 0 天，4-6 小時)

#### 1.1 檢查並修改 wal_level

```bash
# 連線到資料庫檢查 wal_level
SOURCE_HOST="bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com"
DB_NAME="your_database_name"  # 替換為實際資料庫名稱
DB_USER="postgres"

psql -h ${SOURCE_HOST} -U ${DB_USER} -d ${DB_NAME} -c "SHOW wal_level;"
```

**如果不是 'logical'，需要修改參數群組**:

```bash
# 1. 獲取當前參數群組
PARAM_GROUP=$(aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text \
  --region ap-east-1)

echo "當前參數群組: ${PARAM_GROUP}"

# 2. 如果是默認參數群組（default.*），需要創建自訂參數群組
if [[ ${PARAM_GROUP} == default.* ]]; then
    NEW_PARAM_GROUP="bingo-backstage-logical-replication"

    aws --profile gemini-pro_ck rds create-db-parameter-group \
      --db-parameter-group-name ${NEW_PARAM_GROUP} \
      --db-parameter-group-family postgres14 \
      --description "Parameter group for logical replication" \
      --region ap-east-1

    echo "✅ 已創建新參數群組: ${NEW_PARAM_GROUP}"
    PARAM_GROUP=${NEW_PARAM_GROUP}
fi

# 3. 修改 wal_level 為 logical
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name ${PARAM_GROUP} \
  --parameters "ParameterName=wal_level,ParameterValue=logical,ApplyMethod=pending-reboot" \
  --region ap-east-1

echo "✅ wal_level 已修改為 logical（需要重啟生效）"

# 4. 套用參數群組（如果是新建的）
if [ "${PARAM_GROUP}" != "$(aws --profile gemini-pro_ck rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
    --output text --region ap-east-1)" ]; then

    aws --profile gemini-pro_ck rds modify-db-instance \
      --db-instance-identifier bingo-prd-backstage \
      --db-parameter-group-name ${PARAM_GROUP} \
      --apply-immediately \
      --region ap-east-1
fi

# 5. 重啟資料庫（會有停機，約 3-5 分鐘）
echo "⚠️  準備重啟資料庫以套用參數變更..."
read -p "確認要重啟嗎？(yes/no): " CONFIRM

if [ "$CONFIRM" == "yes" ]; then
    aws --profile gemini-pro_ck rds reboot-db-instance \
      --db-instance-identifier bingo-prd-backstage \
      --region ap-east-1

    echo "⏳ 資料庫重啟中，預計 3-5 分鐘..."
    aws --profile gemini-pro_ck rds wait db-instance-available \
      --db-instance-identifier bingo-prd-backstage \
      --region ap-east-1

    echo "✅ 資料庫已重啟"

    # 驗證 wal_level
    psql -h ${SOURCE_HOST} -U ${DB_USER} -d ${DB_NAME} -c "SHOW wal_level;"
else
    echo "❌ 已取消重啟，請稍後在維護窗口執行"
    exit 1
fi
```

#### 1.2 創建目標 RDS 實例

```bash
# 創建新的 2000 GB 實例
NEW_DB_ID="bingo-prd-backstage-new"
DB_PASSWORD="YOUR_SECURE_PASSWORD_HERE"  # ⚠️ 請使用強密碼

aws --profile gemini-pro_ck rds create-db-instance \
  --db-instance-identifier ${NEW_DB_ID} \
  --db-instance-class db.m6g.large \
  --engine postgres \
  --engine-version 14.15 \
  --allocated-storage 2000 \
  --storage-type gp3 \
  --iops 12000 \
  --storage-encrypted \
  --master-username postgres \
  --master-user-password "${DB_PASSWORD}" \
  --vpc-security-group-ids sg-033740b002dbeffa1 sg-07e81967b01448b01 \
  --db-subnet-group-name default-vpc-086d3d02c471379fa \
  --db-parameter-group-name ${PARAM_GROUP} \
  --backup-retention-period 3 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --port 5432 \
  --no-publicly-accessible \
  --region ap-east-1

echo "⏳ 創建新資料庫實例，預計 10-15 分鐘..."
aws --profile gemini-pro_ck rds wait db-instance-available \
  --db-instance-identifier ${NEW_DB_ID} \
  --region ap-east-1

# 獲取新實例端點
NEW_ENDPOINT=$(aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier ${NEW_DB_ID} \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region ap-east-1)

echo "✅ 新資料庫已創建"
echo "📍 新端點: ${NEW_ENDPOINT}"
```

**預估時間**: 10-15 分鐘

---

### 階段 2: 初始資料遷移 (第 1 天，6-10 小時)

#### 2.1 使用 pg_dump 匯出資料

```bash
SOURCE_HOST="bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com"
TARGET_HOST=${NEW_ENDPOINT}
DB_NAME="your_database_name"
DUMP_FILE="/tmp/db_dump_$(date +%Y%m%d).backup"

echo "📦 開始匯出資料（Schema + Data）..."
echo "⏰ 開始時間: $(date)"

# 使用 pg_dump 匯出
pg_dump -h ${SOURCE_HOST} \
        -U postgres \
        -d ${DB_NAME} \
        -Fc \
        -v \
        -f ${DUMP_FILE}

echo "✅ 匯出完成"
echo "⏰ 完成時間: $(date)"
echo "📊 檔案大小: $(du -h ${DUMP_FILE})"
```

**預估時間**: 3-6 小時（1278 GB 資料）

#### 2.2 匯入資料到新資料庫

```bash
echo "📥 開始匯入資料到新資料庫..."
echo "⏰ 開始時間: $(date)"

# 先創建資料庫（如果不存在）
psql -h ${TARGET_HOST} -U postgres -d postgres -c "CREATE DATABASE ${DB_NAME};"

# 使用 pg_restore 匯入
pg_restore -h ${TARGET_HOST} \
           -U postgres \
           -d ${DB_NAME} \
           --no-owner \
           --no-acl \
           --verbose \
           --jobs=4 \
           ${DUMP_FILE}

echo "✅ 匯入完成"
echo "⏰ 完成時間: $(date)"

# 執行 ANALYZE 更新統計資訊
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "ANALYZE;"
```

**預估時間**: 3-6 小時

---

### 階段 3: 設定邏輯複製 (第 1 天，1 小時)

#### 3.1 在源資料庫創建 Publication

```sql
-- 連線到源資料庫
psql -h ${SOURCE_HOST} -U postgres -d ${DB_NAME}

-- 創建 publication（發布所有資料表）
CREATE PUBLICATION full_publication FOR ALL TABLES;

-- 驗證
SELECT * FROM pg_publication;

-- 查看包含哪些資料表
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'full_publication'
ORDER BY schemaname, tablename;

\q
```

**注意事項**:
- 如果只想複製特定資料表，使用：
  ```sql
  CREATE PUBLICATION full_publication FOR TABLE table1, table2, table3;
  ```
- 邏輯複製不會複製 DDL，只複製 DML（INSERT/UPDATE/DELETE）

#### 3.2 在目標資料庫創建 Subscription

```sql
-- 連線到目標資料庫
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME}

-- 創建 subscription
-- ⚠️ 注意：這裡的密碼會顯示在 pg_subscription 中，請使用專用的複製帳號
CREATE SUBSCRIPTION full_subscription
CONNECTION 'host=bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com port=5432 dbname=your_database_name user=postgres password=YOUR_PASSWORD'
PUBLICATION full_publication
WITH (copy_data = false);  -- 已經用 pg_dump 複製過了，設為 false

-- 驗證
SELECT * FROM pg_subscription;

-- 查看複製狀態
SELECT
    subname,
    pid,
    received_lsn,
    latest_end_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_time,
    CASE
        WHEN latest_end_time IS NOT NULL
        THEN EXTRACT(EPOCH FROM (now() - latest_end_time))::INTEGER
        ELSE NULL
    END AS lag_seconds
FROM pg_stat_subscription;

\q
```

**預期結果**:
- `lag_seconds` 應該很快降到 < 10 秒
- 如果一直很高，檢查網路和資源

---

### 階段 4: 持續同步與測試 (第 1-2 天)

#### 4.1 監控複製延遲

```bash
# 創建監控腳本
cat > /tmp/monitor-replication.sh << 'SCRIPT'
#!/bin/bash

TARGET_HOST="YOUR_NEW_ENDPOINT"  # 替換為實際端點
DB_NAME="your_database_name"

echo "======================================"
echo "邏輯複製監控"
echo "======================================"
echo "按 Ctrl+C 停止監控"
echo ""

while true; do
    clear
    echo "⏰ 監控時間: $(date)"
    echo "======================================"

    psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} << 'EOF'
\x on
SELECT
    subname AS "訂閱名稱",
    pid AS "進程ID",
    received_lsn AS "接收LSN",
    latest_end_lsn AS "最新LSN",
    last_msg_send_time AS "最後發送時間",
    last_msg_receipt_time AS "最後接收時間",
    latest_end_time AS "最新時間",
    CASE
        WHEN latest_end_time IS NOT NULL
        THEN EXTRACT(EPOCH FROM (now() - latest_end_time))::INTEGER || ' 秒'
        ELSE 'N/A'
    END AS "複製延遲"
FROM pg_stat_subscription;
\x off

-- 查看複製插槽狀態
SELECT
    slot_name,
    slot_type,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS "複製滯後"
FROM pg_replication_slots
WHERE slot_type = 'logical';
EOF

    echo ""
    echo "======================================"
    echo "下次更新: 30 秒後"
    sleep 30
done
SCRIPT

chmod +x /tmp/monitor-replication.sh

# 執行監控（在另一個終端或背景）
# /tmp/monitor-replication.sh
```

**健康指標**:
- ✅ `lag_seconds` < 5 秒：非常健康
- ⚠️ `lag_seconds` < 60 秒：正常
- 🔴 `lag_seconds` > 300 秒：需要調查

#### 4.2 驗證資料一致性

```bash
# 比較資料筆數
echo "📊 比較資料筆數..."

# 源資料庫
psql -h ${SOURCE_HOST} -U postgres -d ${DB_NAME} << 'EOF' > /tmp/source_counts.txt
SELECT
    schemaname,
    tablename,
    n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY schemaname, tablename;
EOF

# 目標資料庫
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} << 'EOF' > /tmp/target_counts.txt
SELECT
    schemaname,
    tablename,
    n_live_tup AS row_count
FROM pg_stat_user_tables
ORDER BY schemaname, tablename;
EOF

# 比較結果
echo "🔍 比較結果:"
diff /tmp/source_counts.txt /tmp/target_counts.txt

if [ $? -eq 0 ]; then
    echo "✅ 資料筆數一致"
else
    echo "⚠️  發現差異，執行 ANALYZE 更新統計資訊"
    psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "ANALYZE;"
    echo "請重新執行比較"
fi
```

#### 4.3 測試新資料庫

```bash
# 功能測試檢查清單
cat > /tmp/functional_test_checklist.md << 'EOF'
# 新資料庫功能測試檢查清單

## 連線測試
- [ ] 可以從應用服務器連線
- [ ] SSL/TLS 連線正常
- [ ] 連線池設定正確

## 資料完整性
- [ ] 所有資料表存在
- [ ] 索引已建立
- [ ] 約束條件正確
- [ ] 觸發器正常運作
- [ ] 序列（Sequences）值正確

## 查詢效能
- [ ] 常用查詢執行時間正常
- [ ] EXPLAIN ANALYZE 顯示使用正確索引
- [ ] 沒有全表掃描（除非預期）

## 寫入測試（在低流量時段）
- [ ] INSERT 正常
- [ ] UPDATE 正常
- [ ] DELETE 正常
- [ ] 交易（Transactions）正常

## 複製狀態
- [ ] 複製延遲 < 5 秒
- [ ] 沒有複製錯誤
- [ ] WAL 滯後正常

## 監控
- [ ] CloudWatch 指標顯示正常
- [ ] CPU 使用率正常
- [ ] 記憶體使用率正常
- [ ] IOPS 使用率正常
EOF

cat /tmp/functional_test_checklist.md
```

---

### 階段 5: 執行切換 (第 2-3 天，執行窗口)

#### 5.1 切換前最後檢查

```bash
echo "==================================="
echo "切換前最後檢查"
echo "==================================="

# 1. 確認複製延遲 < 5 秒
echo "1️⃣ 檢查複製延遲..."
LAG=$(psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -t -c "
SELECT
    COALESCE(
        EXTRACT(EPOCH FROM (now() - latest_end_time))::INTEGER,
        999
    ) AS lag_seconds
FROM pg_stat_subscription
LIMIT 1;
" | xargs)

echo "   複製延遲: ${LAG} 秒"

if [ "$LAG" -gt 5 ]; then
    echo "   ⚠️  延遲過高，建議等待降低後再切換"
    read -p "   是否繼續？(yes/no): " CONTINUE
    if [ "$CONTINUE" != "yes" ]; then
        echo "   ❌ 已取消切換"
        exit 1
    fi
fi

# 2. 確認資料一致性
echo "2️⃣ 確認資料一致性..."
# (執行上一步的驗證腳本)

# 3. 確認應用程式狀態正常
echo "3️⃣ 請手動確認："
echo "   - 應用程式運行正常"
echo "   - 沒有進行中的重要交易"
echo "   - 團隊已就位"
read -p "   確認所有項目無誤？(yes/no): " READY

if [ "$READY" != "yes" ]; then
    echo "   ❌ 已取消切換"
    exit 1
fi

echo "✅ 前置檢查通過，準備執行切換"
```

#### 5.2 執行切換

```bash
# 切換腳本
cat > /tmp/execute_switchover.sh << 'SCRIPT'
#!/bin/bash

set -e

SOURCE_HOST="bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com"
TARGET_HOST="YOUR_NEW_ENDPOINT"  # 替換
DB_NAME="your_database_name"

echo "🚨 切換開始 - $(date)"
START_TIME=$(date +%s)

# ========================================
# 步驟 1: 停止應用程式寫入
# ========================================
echo "1️⃣ 停止應用程式寫入..."
echo "   請應用程式團隊執行以下操作："
echo "   - 停止寫入服務"
echo "   - 或設定資料庫為唯讀模式"
echo ""
read -p "   應用程式已停止寫入？(yes): " CONFIRM1
[ "$CONFIRM1" != "yes" ] && echo "❌ 已取消" && exit 1

STEP1_TIME=$(date +%s)
echo "   ✅ 步驟 1 完成 (耗時: $((STEP1_TIME - START_TIME)) 秒)"

# ========================================
# 步驟 2: 等待複製同步完成
# ========================================
echo "2️⃣ 等待最後的資料同步..."
for i in {1..60}; do
    LAG=$(psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -t -c "
    SELECT
        COALESCE(
            EXTRACT(EPOCH FROM (now() - latest_end_time))::INTEGER,
            999
        ) AS lag_seconds
    FROM pg_stat_subscription
    LIMIT 1;
    " | xargs)

    echo "   [${i}/60] 複製延遲: ${LAG} 秒"

    if [ "$LAG" -lt 2 ]; then
        echo "   ✅ 複製已同步"
        break
    fi

    if [ $i -eq 60 ]; then
        echo "   ⚠️  等待超時，延遲仍為 ${LAG} 秒"
        read -p "   是否繼續？(yes/no): " CONTINUE
        [ "$CONTINUE" != "yes" ] && echo "❌ 已取消" && exit 1
    fi

    sleep 2
done

STEP2_TIME=$(date +%s)
echo "   ✅ 步驟 2 完成 (耗時: $((STEP2_TIME - STEP1_TIME)) 秒)"

# ========================================
# 步驟 3: 停止邏輯複製
# ========================================
echo "3️⃣ 停止邏輯複製..."
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "
DROP SUBSCRIPTION IF EXISTS full_subscription;
"

# 同時清理源資料庫的 publication（可選）
# psql -h ${SOURCE_HOST} -U postgres -d ${DB_NAME} -c "
# DROP PUBLICATION IF EXISTS full_publication;
# "

STEP3_TIME=$(date +%s)
echo "   ✅ 步驟 3 完成 (耗時: $((STEP3_TIME - STEP2_TIME)) 秒)"

# ========================================
# 步驟 4: 更新應用程式連線字串
# ========================================
echo "4️⃣ 更新應用程式連線字串..."
echo "   舊端點: ${SOURCE_HOST}"
echo "   新端點: ${TARGET_HOST}"
echo ""
echo "   請應用程式團隊執行以下操作："
echo "   - 更新環境變數或配置檔"
echo "   - 更新連線池配置"
echo ""
read -p "   連線字串已更新？(yes): " CONFIRM4
[ "$CONFIRM4" != "yes" ] && echo "❌ 已取消" && exit 1

STEP4_TIME=$(date +%s)
echo "   ✅ 步驟 4 完成 (耗時: $((STEP4_TIME - STEP3_TIME)) 秒)"

# ========================================
# 步驟 5: 重啟應用程式
# ========================================
echo "5️⃣ 重啟應用程式..."
echo "   請應用程式團隊執行以下操作："
echo "   - 重啟應用服務"
echo "   - 驗證連線到新資料庫"
echo ""
read -p "   應用程式已重啟並連線到新資料庫？(yes): " CONFIRM5
[ "$CONFIRM5" != "yes" ] && echo "❌ 已取消" && exit 1

STEP5_TIME=$(date +%s)
echo "   ✅ 步驟 5 完成 (耗時: $((STEP5_TIME - STEP4_TIME)) 秒)"

# ========================================
# 完成
# ========================================
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo ""
echo "======================================"
echo "✅ 切換成功完成！"
echo "======================================"
echo "⏰ 切換完成時間: $(date)"
echo "⏱️  總停機時間: ${TOTAL_TIME} 秒 ($(echo "scale=2; $TOTAL_TIME / 60" | bc) 分鐘)"
echo ""
echo "各階段耗時:"
echo "  - 停止寫入: $((STEP1_TIME - START_TIME)) 秒"
echo "  - 等待同步: $((STEP2_TIME - STEP1_TIME)) 秒"
echo "  - 停止複製: $((STEP3_TIME - STEP2_TIME)) 秒"
echo "  - 更新配置: $((STEP4_TIME - STEP3_TIME)) 秒"
echo "  - 重啟服務: $((STEP5_TIME - STEP4_TIME)) 秒"
echo ""
echo "📍 新資料庫端點: ${TARGET_HOST}"
echo "💾 新資料庫配置: 2000 GB"
echo "======================================"
SCRIPT

chmod +x /tmp/execute_switchover.sh

# 執行切換
echo "準備執行切換..."
echo "請確認所有團隊成員已就位"
read -p "按 Enter 開始切換，或 Ctrl+C 取消..."

/tmp/execute_switchover.sh
```

**預期停機時間**: 60-300 秒（取決於應用程式重啟時間）

#### 5.3 立即驗證

```bash
# 切換後立即驗證腳本
cat > /tmp/post_switchover_verification.sh << 'SCRIPT'
#!/bin/bash

TARGET_HOST="YOUR_NEW_ENDPOINT"
DB_NAME="your_database_name"

echo "======================================"
echo "切換後驗證"
echo "======================================"

# 1. 檢查資料庫連線
echo "1️⃣ 測試資料庫連線..."
if psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "SELECT now(), version();" > /dev/null 2>&1; then
    echo "   ✅ 資料庫可連線"
else
    echo "   ❌ 資料庫連線失敗"
    exit 1
fi

# 2. 檢查儲存空間
echo "2️⃣ 檢查儲存空間..."
aws --profile gemini-pro_ck rds describe-db-instances \
  --db-instance-identifier bingo-prd-backstage-new \
  --query 'DBInstances[0].{Storage:AllocatedStorage,Type:StorageType,IOPS:Iops}' \
  --region ap-east-1

# 3. 檢查應用程式連線數
echo "3️⃣ 檢查連線數..."
sleep 30  # 等待連線恢復
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "
SELECT
    datname,
    numbackends AS active_connections,
    xact_commit AS transactions
FROM pg_stat_database
WHERE datname = '${DB_NAME}';
"

# 4. 檢查寫入是否正常
echo "4️⃣ 檢查最近的寫入活動..."
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "
SELECT
    schemaname,
    tablename,
    n_tup_ins AS recent_inserts,
    n_tup_upd AS recent_updates,
    n_tup_del AS recent_deletes,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_tup_ins > 0 OR n_tup_upd > 0 OR n_tup_del > 0
ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC
LIMIT 10;
"

# 5. 檢查 CloudWatch 指標
echo "5️⃣ 檢查 CloudWatch 指標..."
aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-new \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region ap-east-1 \
  --query 'Datapoints[0].Average'

echo ""
echo "======================================"
echo "✅ 驗證完成"
echo "======================================"
SCRIPT

chmod +x /tmp/post_switchover_verification.sh
/tmp/post_switchover_verification.sh
```

---

### 階段 6: 監控與清理 (第 3-10 天)

#### 6.1 密集監控期（前 24 小時）

```bash
# 創建 24 小時監控腳本
cat > /tmp/monitor_new_db_24h.sh << 'SCRIPT'
#!/bin/bash

PROFILE="gemini-pro_ck"
REGION="ap-east-1"
DB_ID="bingo-prd-backstage-new"
TARGET_HOST="YOUR_NEW_ENDPOINT"
DB_NAME="your_database_name"

while true; do
    clear
    echo "======================================"
    echo "RDS 監控 - $(date)"
    echo "======================================"
    echo ""

    # CPU
    echo "📊 CPU 使用率:"
    aws --profile ${PROFILE} cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name CPUUtilization \
      --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
      --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --region ${REGION} \
      --query 'Datapoints[0].Average' \
      --output text
    echo "%"

    # 記憶體
    echo ""
    echo "💾 可用記憶體:"
    aws --profile ${PROFILE} cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name FreeableMemory \
      --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
      --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --region ${REGION} \
      --query 'Datapoints[0].Average / 1024 / 1024 / 1024' \
      --output text
    echo "GB"

    # 連線數
    echo ""
    echo "🔗 資料庫連線數:"
    psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -t -c "
    SELECT count(*) FROM pg_stat_activity WHERE datname = '${DB_NAME}';
    "

    # 儲存空間
    echo ""
    echo "💽 剩餘儲存空間:"
    aws --profile ${PROFILE} cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name FreeStorageSpace \
      --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
      --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --region ${REGION} \
      --query 'Datapoints[0].Average / 1024 / 1024 / 1024' \
      --output text
    echo "GB"

    # IOPS
    echo ""
    echo "📈 讀寫 IOPS:"
    echo -n "  讀取: "
    aws --profile ${PROFILE} cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name ReadIOPS \
      --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
      --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --region ${REGION} \
      --query 'Datapoints[0].Average' \
      --output text

    echo -n "  寫入: "
    aws --profile ${PROFILE} cloudwatch get-metric-statistics \
      --namespace AWS/RDS \
      --metric-name WriteIOPS \
      --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
      --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --region ${REGION} \
      --query 'Datapoints[0].Average' \
      --output text

    echo ""
    echo "======================================"
    echo "下次更新: 5 分鐘後"
    sleep 300
done
SCRIPT

chmod +x /tmp/monitor_new_db_24h.sh

# 在背景或另一個終端執行
# /tmp/monitor_new_db_24h.sh &
```

#### 6.2 重命名資料庫（保持原名稱）

**等待 2-3 天穩定運行後執行**:

```bash
# 1. 重命名舊資料庫
OLD_DB_ID="bingo-prd-backstage"
BACKUP_DB_ID="bingo-prd-backstage-old-$(date +%Y%m%d)"

echo "1️⃣ 重命名舊資料庫..."
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier ${OLD_DB_ID} \
  --new-db-instance-identifier ${BACKUP_DB_ID} \
  --apply-immediately \
  --region ap-east-1

echo "⏳ 等待重命名完成..."
aws --profile gemini-pro_ck rds wait db-instance-available \
  --db-instance-identifier ${BACKUP_DB_ID} \
  --region ap-east-1

# 2. 重命名新資料庫為原名稱
NEW_DB_ID="bingo-prd-backstage-new"

echo "2️⃣ 重命名新資料庫為原名稱..."
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier ${NEW_DB_ID} \
  --new-db-instance-identifier ${OLD_DB_ID} \
  --apply-immediately \
  --region ap-east-1

echo "⏳ 等待重命名完成..."
aws --profile gemini-pro_ck rds wait db-instance-available \
  --db-instance-identifier ${OLD_DB_ID} \
  --region ap-east-1

echo "✅ 資料庫已重命名"
echo "   新資料庫現在使用原名稱: ${OLD_DB_ID}"
echo "   舊資料庫已重命名為: ${BACKUP_DB_ID}"
```

#### 6.3 清理舊資料庫

**⚠️ 保留至少 7 天後再刪除**:

```bash
# 7-14 天後，確認一切正常，刪除舊資料庫
BACKUP_DB_ID="bingo-prd-backstage-old-20251028"  # 使用實際日期

echo "⚠️  準備刪除舊資料庫: ${BACKUP_DB_ID}"
echo "   請確認:"
echo "   - 新資料庫運行穩定超過 7 天"
echo "   - 沒有發現任何問題"
echo "   - 不需要回滾"
echo ""
read -p "確認刪除？(yes/no): " CONFIRM

if [ "$CONFIRM" == "yes" ]; then
    # 選項 1: 不創建最後快照（如果已有足夠備份）
    aws --profile gemini-pro_ck rds delete-db-instance \
      --db-instance-identifier ${BACKUP_DB_ID} \
      --skip-final-snapshot \
      --region ap-east-1

    # 或選項 2: 創建最後快照（更安全）
    # aws --profile gemini-pro_ck rds delete-db-instance \
    #   --db-instance-identifier ${BACKUP_DB_ID} \
    #   --final-db-snapshot-identifier ${BACKUP_DB_ID}-final-snapshot \
    #   --region ap-east-1

    echo "✅ 舊資料庫已提交刪除"
    echo "   刪除過程約需 5-10 分鐘"
else
    echo "❌ 已取消刪除"
fi
```

---

## 方案 B: AWS DMS（備選）

**停機時間**: < 5 分鐘
**總執行時間**: 2-3 天
**複雜度**: 中
**成本**: DMS 複製實例 ~$50 + 雙倍 RDS 成本
**可靠性**: ⭐⭐⭐⭐⭐

### 優點
- ✅ AWS 原生服務，穩定可靠
- ✅ 接近零停機時間
- ✅ 自動化程度高
- ✅ 支持多種資料庫引擎

### 缺點
- ⚠️ 需要額外成本（DMS 複製實例）
- ⚠️ 設定相對複雜
- ⚠️ 需要測試和驗證資料一致性

### 簡要步驟

由於 DMS 設定較複雜，這裡僅提供概要步驟。如需詳細 SOP，請另外生成。

1. **創建目標 RDS 實例**（2000 GB）
2. **創建 DMS 複製實例**（dms.c5.xlarge，$0.28/小時）
3. **配置源和目標端點**
4. **創建 DMS 任務**（Full Load + CDC）
5. **監控資料遷移**（3-6 小時全量遷移）
6. **啟用 CDC持續同步**（可運行數天測試）
7. **執行最終切換**（停止寫入 → 等待同步 → 切換）
8. **清理 DMS 資源**

**建議**: 如果您對 DMS 不熟悉，建議使用方案 A（PostgreSQL 邏輯複製）。

---

## 驗證與監控

### 切換後 24 小時監控清單

#### 1. 資料庫效能基準對比

```bash
# 記錄切換前的基準值（在切換前執行）
cat > /tmp/performance_baseline_before.txt << EOF
=== 效能基準值（切換前）===
記錄時間: $(date)

CPU 平均: $(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Average --region ap-east-1 \
  --query 'Datapoints[0].Average' --output text)%

連線數平均: $(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Average --region ap-east-1 \
  --query 'Datapoints[0].Average' --output text)

讀取 IOPS: $(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name ReadIOPS \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Average --region ap-east-1 \
  --query 'Datapoints[0].Average' --output text)

寫入 IOPS: $(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name WriteIOPS \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Average --region ap-east-1 \
  --query 'Datapoints[0].Average' --output text)
EOF

cat /tmp/performance_baseline_before.txt
```

#### 2. CloudWatch 告警設定

```bash
# 創建告警
DB_ID="bingo-prd-backstage-new"

# 高 CPU 告警
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name "${DB_ID}-high-cpu" \
  --alarm-description "RDS CPU usage > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
  --region ap-east-1

# 低儲存空間告警
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name "${DB_ID}-low-storage" \
  --alarm-description "RDS free storage < 200 GB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 214748364800 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
  --region ap-east-1

# 高連線數告警
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name "${DB_ID}-high-connections" \
  --alarm-description "RDS connections > 80% of max" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=${DB_ID} \
  --region ap-east-1

echo "✅ CloudWatch 告警已設定"
```

---

## 回滾程序

### 情境 1: 切換過程中發現問題（尚未完成切換）

**症狀**: 在等待同步或更新配置時發現異常

**回滾步驟**:

```bash
# 1. 停止切換流程（Ctrl+C 中斷腳本）
echo "1️⃣ 停止切換流程"

# 2. 恢復應用程式寫入
echo "2️⃣ 恢復應用程式寫入"
# （應用程式團隊執行）

# 3. 清理邏輯複製（如果已創建）
psql -h ${TARGET_HOST} -U postgres -d ${DB_NAME} -c "
DROP SUBSCRIPTION IF EXISTS full_subscription;
"

psql -h ${SOURCE_HOST} -U postgres -d ${DB_NAME} -c "
DROP PUBLICATION IF EXISTS full_publication;
"

echo "✅ 已回滾，應用程式繼續使用原資料庫"
```

**預估時間**: < 2 分鐘
**影響**: 無資料遺失

### 情境 2: 切換後發現問題（應用程式已切換）

**症狀**: 切換完成但應用程式出現錯誤或效能問題

**回滾步驟**:

```bash
# 1. 停止應用程式
echo "1️⃣ 停止應用程式..."
# （應用程式團隊執行）

# 2. 更新連線字串回舊資料庫
SOURCE_HOST="bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com"
echo "2️⃣ 更新連線字串回: ${SOURCE_HOST}"
# （應用程式團隊執行）

# 3. ⚠️ 處理在新資料庫上的資料（重要！）
echo "3️⃣ 處理新資料庫上的資料..."
echo "   如果新資料庫有新的寫入，需要手動處理："
echo "   - 匯出新資料: pg_dump -t specific_tables"
echo "   - 匯入回舊資料庫"
# （根據實際情況處理）

# 4. 重啟應用程式
echo "4️⃣ 重啟應用程式..."
# （應用程式團隊執行）

echo "✅ 已回滾到原資料庫"
```

**預估時間**: 5-15 分鐘
**影響**: 在新資料庫上的資料需要手動處理

### 情境 3: 嚴重資料損壞

**症狀**: 發現資料遺失或嚴重不一致

**回滾步驟**:

```bash
# 1. 立即停止所有寫入
echo "🚨 停止所有寫入！"

# 2. 從備份快照還原
SNAPSHOT_ID="your-snapshot-id"  # 之前創建的快照

aws --profile gemini-pro_ck rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier bingo-prd-backstage-restored \
  --db-snapshot-identifier ${SNAPSHOT_ID} \
  --db-instance-class db.m6g.large \
  --vpc-security-group-ids sg-033740b002dbeffa1 sg-07e81967b01448b01 \
  --db-subnet-group-name default-vpc-086d3d02c471379fa \
  --publicly-accessible false \
  --region ap-east-1

echo "⏳ 從快照還原中，預計 30-60 分鐘..."
aws --profile gemini-pro_ck rds wait db-instance-available \
  --db-instance-identifier bingo-prd-backstage-restored \
  --region ap-east-1

# 3. 驗證資料完整性
# 4. 切換應用程式到還原的實例

echo "✅ 已從快照還原"
```

**預估時間**: 30-90 分鐘
**影響**: 會遺失快照後到發現問題期間的資料

---

## 常見問題 (FAQ)

### Q1: 為什麼一定要創建新實例才能縮減儲存空間？

**A**: 這是 AWS RDS 的核心設計限制。為了避免資料遺失風險，RDS 不允許直接縮減已分配的儲存空間。這個限制適用於所有 RDS 引擎。

### Q2: 停機時間可以更短嗎？

**A**: 理論上可以，取決於：
- 應用程式重啟速度（最大因素）
- 複製延遲同步速度（通常 < 10 秒）
- 團隊執行效率

實務上 2-5 分鐘是合理預期。

### Q3: 2000 GB 夠用嗎？

**A**: 根據當前使用情況：
- 當前使用：1278 GB
- 配置 2000 GB 使用率：64%
- 剩餘空間：722 GB
- 以每天 1 GB 增長計算，可用約 2 年

建議啟用儲存自動擴展（上限 3000 GB）。

### Q4: 邏輯複製會影響源資料庫效能嗎？

**A**: 影響很小：
- WAL 生成：正常業務操作就會產生
- 網路傳輸：使用非尖峰頻寬
- CPU 開銷：約 2-5%
- 記憶體開銷：複製插槽約 10-50 MB

### Q5: 如果切換後效能變差怎麼辦？

**A**:
1. 立即檢查 CloudWatch 指標
2. 執行 `ANALYZE` 更新統計資訊
3. 檢查是否有缺失的索引
4. 如果嚴重，執行回滾（2-5 分鐘）

新實例配置相同，理論上效能應該一致。

### Q6: 需要修改應用程式嗎？

**A**: 取決於您的選擇：
- **需要**：更新連線字串（如果不重命名）
- **不需要**：如果執行了資料庫重命名（第 6.2 步）
- **配置變更**：無需修改應用程式代碼

### Q7: 可以在營業時間執行嗎？

**A**: **強烈不建議**
- 雖然停機時間 < 5 分鐘
- 但如果出現問題，影響面大
- 建議選擇：
  - 週末凌晨
  - 節假日
  - 已公告的維護窗口

### Q8: 如果某個步驟失敗了怎麼辦？

**A**:
- **階段 1-3**: 可以安全重試，不影響生產
- **階段 4（測試）**: 可以刪除新實例重新開始
- **階段 5（切換）**: 按回滾程序處理
- 關鍵：保持舊資料庫可用至少 7 天

### Q9: 成本會增加嗎？

**A**:
- **短期**（2-3 天）：雙倍 RDS 成本 = $20-30
- **長期**（每年）：節省 $3,624
- **投資回報期**: < 2 週
- **淨收益**（3年）: $10,800

### Q10: 需要多少人力？

**A**:
- **準備階段**：1 人 × 4 小時
- **執行階段**：2 人 × 8 小時（包含監控）
- **切換窗口**：3 人 × 1 小時（DBA + 應用團隊 + 運維）
- **監控期**：1 人 × 每天 30 分鐘 × 3 天

---

## 檢查清單總結

### 執行前檢查 (Go/No-Go)

**所有項目必須為 ✅ 才能繼續**:

- ☐ CAB 批准已獲得
- ☐ 相關團隊已通知並確認參與
- ☐ 執行時間窗口已確定（建議週末或低流量時段）
- ☐ 技術團隊待命（DBA、應用團隊、運維，至少 3 人）
- ☐ 完整備份快照已創建並驗證（< 24 小時內）
- ☐ 監控告警已設定並測試
- ☐ 回滾計畫已準備並演練
- ☐ 應用程式團隊已準備好配置更新
- ☐ `wal_level` 已設定為 `logical`
- ☐ 所有執行腳本已準備並測試（在測試環境）
- ☐ 新資料庫實例已創建並驗證
- ☐ 邏輯複製已設定並運行至少 24 小時
- ☐ 複製延遲穩定在 < 5 秒
- ☐ 資料一致性已驗證
- ☐ 業務團隊已批准停機窗口

### 執行中檢查點

**階段 1 完成後**:
- ☐ `wal_level` 已修改為 `logical`
- ☐ 資料庫已重啟並穩定
- ☐ 新實例已創建並可連線

**階段 2 完成後**:
- ☐ 初始資料已完整遷移
- ☐ 主要資料表筆數一致
- ☐ 索引和約束已建立

**階段 3 完成後**:
- ☐ Publication 已創建
- ☐ Subscription 已創建
- ☐ 邏輯複製正常運行

**階段 4 完成後**:
- ☐ 複製延遲 < 5 秒
- ☐ 資料一致性驗證通過
- ☐ 功能測試通過
- ☐ 效能測試通過

### 執行後驗證

**切換完成後立即**:
- ☐ 新資料庫端點可連線
- ☐ 應用程式成功連線到新資料庫
- ☐ 資料庫版本正確 (PostgreSQL 14.15)
- ☐ 儲存空間為 2000 GB
- ☐ 連線數恢復正常
- ☐ 寫入操作正常

**24 小時後**:
- ☐ 無錯誤日誌
- ☐ 效能指標正常（CPU、記憶體、IOPS）
- ☐ 應用程式無異常
- ☐ 業務功能測試通過
- ☐ 監控顯示正常

**7 天後**:
- ☐ 長期穩定運行無問題
- ☐ 成本節省已反映在帳單
- ☐ 團隊確認可以刪除舊資料庫
- ☐ 文檔已更新

---

## 聯絡資訊

**遇到問題時聯絡**:

- **DBA 負責人**: _______________
- **應用程式負責人**: _______________
- **運維負責人**: _______________
- **AWS Support**: _______________

**升級路徑**:
1. 團隊內部討論（0-15 分鐘）
2. 聯絡技術負責人（15-30 分鐘）
3. 聯絡 AWS Support（30+ 分鐘）

---

## 附錄

### A. 腳本清單

所有腳本已保存至 `/tmp/` 目錄：

| 腳本名稱 | 用途 | 路徑 |
|---------|------|------|
| `monitor-replication.sh` | 監控邏輯複製狀態 | `/tmp/monitor-replication.sh` |
| `execute_switchover.sh` | 執行切換 | `/tmp/execute_switchover.sh` |
| `post_switchover_verification.sh` | 切換後驗證 | `/tmp/post_switchover_verification.sh` |
| `monitor_new_db_24h.sh` | 24 小時監控 | `/tmp/monitor_new_db_24h.sh` |
| `functional_test_checklist.md` | 功能測試清單 | `/tmp/functional_test_checklist.md` |

### B. 參考資料

- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/14/logical-replication.html)
- [AWS RDS PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/)

### C. 時間線範例

**PostgreSQL 邏輯複製完整時間線**:
```
Day 0 (4-6小時):
  - 準備: 修改 wal_level（可能需重啟）
  - 創建新實例（10-15 分鐘）

Day 1 (8-12小時):
  - 初始資料遷移（6-10 小時）
  - 設定邏輯複製（1 小時）
  - 開始持續同步

Day 1-2 (持續):
  - 監控複製狀態
  - 驗證資料一致性
  - 功能測試

Day 2-3 (執行窗口, < 5分鐘停機):
  - 執行切換
  - 立即驗證

Day 3-10 (監控期):
  - 24 小時密集監控
  - 持續監控 7 天
  - 保留舊實例

Day 10+ (清理):
  - 重命名資料庫（可選）
  - 刪除舊實例
  - 更新文檔
```

### D. 成本明細

| 項目 | 金額 | 說明 |
|------|------|------|
| 新 RDS 實例（2-3 天） | $20-30 | 與舊實例並存期間 |
| 舊 RDS 實例（保留 7 天） | $70 | 保留作為回滾選項 |
| **短期總成本** | **$90-100** | 遷移期間額外成本 |
| | | |
| 每月節省 | -$302 | 縮減後節省 |
| 每年節省 | -$3,624 | 年度節省 |
| 3 年總節省 | -$10,872 | 長期收益 |
| | | |
| **淨收益（3年）** | **$10,772** | 扣除遷移成本 |
| **ROI** | **10,772%** | 投資報酬率 |

---

## 版本歷史

| 版本 | 日期 | 變更說明 |
|------|------|---------|
| 1.0 | 2025-10-28 | 初始版本（包含不可靠的 Blue/Green 方案）|
| 2.0 | 2025-10-28 | **重大修訂**：移除 Blue/Green Deployment 方案，只保留可靠方法 |

---

## 重要聲明

本 SOP 只包含經過驗證、可靠的 RDS 儲存空間縮減方法：
- ✅ **PostgreSQL 邏輯複製**（推薦）
- ✅ **AWS DMS**（備選）

**不包含的方法及原因**:
- ❌ Blue/Green Deployment 儲存縮減：未經充分驗證，不確定是否支援
- ❌ 快照還原到小容量：AWS 明確不支援
- ❌ 直接縮減 RDS 儲存：違反 RDS 基本限制

**準備好開始執行了嗎？**

請選擇方案 A（PostgreSQL 邏輯複製）並按照步驟執行！

---

**文檔結束**

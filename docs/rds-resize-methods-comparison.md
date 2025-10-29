# AWS RDS 儲存空間縮減方案詳細分析報告

## 執行摘要

本報告針對生產環境 RDS PostgreSQL 資料庫 `bingo-prd-backstage` 的儲存空間縮減需求（從 5024 GB 縮減到 2000 GB，當前使用量為 1278 GB），進行全面的可行性分析與方案比較。

**關鍵發現：**
- AWS 於 2024 年 11 月推出 Blue/Green Deployment 儲存縮減功能，為當前最佳解決方案
- 傳統快照還原方法因 AWS 限制無法直接縮減儲存空間
- 所有方案均需要仔細規劃與測試，建議停機時間為數小時到數天不等

---

## 目錄

1. [環境資訊](#環境資訊)
2. [所有可行方案概覽](#所有可行方案概覽)
3. [方案詳細分析](#方案詳細分析)
4. [詳細比較表格](#詳細比較表格)
5. [推薦方案](#推薦方案)
6. [執行計畫範例](#執行計畫範例)
7. [風險評估與應對策略](#風險評估與應對策略)
8. [參考資料](#參考資料)

---

## 環境資訊

| 項目 | 詳細資訊 |
|------|----------|
| **資料庫實例名稱** | bingo-prd-backstage |
| **當前儲存空間** | 5024 GB (已配置) |
| **實際使用量** | 1278 GB (25%) |
| **目標儲存空間** | 2000 GB |
| **縮減幅度** | 3024 GB (60%) |
| **資料庫引擎** | PostgreSQL 14.15 |
| **AWS Region** | ap-east-1 (香港) |
| **AWS Profile** | gemini-pro_ck |
| **環境類型** | 生產環境 (Production) |

---

## 所有可行方案概覽

### 1. ✅ Blue/Green Deployment 儲存縮減（推薦）
AWS 最新功能，專為儲存縮減設計，支援近零停機時間切換。

### 2. ✅ AWS Database Migration Service (DMS)
使用 AWS DMS 進行持續複製，最小化停機時間。

### 3. ✅ PostgreSQL 邏輯複製（Logical Replication）
原生 PostgreSQL 功能，支援近零停機時間遷移。

### 4. ✅ pg_dump / pg_restore 手動遷移
傳統方法，適合可接受較長停機時間的情況。

### 5. ✅ Read Replica 提升法
創建較小儲存空間的唯讀副本後提升為獨立實例。

### 6. ❌ 快照還原（Snapshot Restore）
**不可行**：AWS 不允許從快照還原到較小的儲存空間。

### 7. ❌ AWS Backup 還原
**不可行**：與快照還原相同限制。

### 8. 部分可行：第三方工具
- **Bucardo**：PostgreSQL 多主複製工具
- **SymmetricDS**：跨資料庫複製平台
- **DBConvert**：商業遷移工具
- **Attunity Replicate**：企業級資料複製

---

## 方案詳細分析

### 方案 1：Blue/Green Deployment 儲存縮減 ⭐ 推薦

#### 簡介
AWS 於 2024 年 11 月推出的新功能，專門用於 RDS 儲存空間縮減。透過創建一個 Green 環境（較小儲存空間），並保持與 Blue 環境（生產環境）同步，最後進行快速切換。

#### 技術原理
- Blue/Green Deployments 創建完全託管的暫存環境（Green 資料庫）
- 使用物理複製（Physical Replication）保持 Blue 和 Green 同步
- 在 Green 環境中執行儲存縮減操作（I/O 密集型，涉及物理資料區塊複製）
- 切換時間少於 1 分鐘

#### 適用條件
- PostgreSQL 12 及更高版本（✅ 符合：PostgreSQL 14.15）
- 支援 Blue/Green Deployment 的 AWS Region（需確認 ap-east-1）
- 不使用 RDS Proxy
- 實例大小至少為 db.t3.medium 或更大

#### 執行步驟

```bash
# 1. 準備階段
# 停用儲存自動擴展（重要！）
aws rds modify-db-instance \
    --db-instance-identifier bingo-prd-backstage \
    --max-allocated-storage 0 \
    --no-apply-immediately \
    --profile gemini-pro_ck \
    --region ap-east-1

# 2. 監控 WAL 生成量（建議監控 24 小時以上）
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name TransactionLogsGeneration \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time 2025-10-27T00:00:00Z \
    --end-time 2025-10-28T00:00:00Z \
    --period 3600 \
    --statistics Sum \
    --profile gemini-pro_ck \
    --region ap-east-1

# 3. 創建 Blue/Green Deployment
aws rds create-blue-green-deployment \
    --blue-green-deployment-name bingo-storage-reduction \
    --source-arn arn:aws:rds:ap-east-1:<account-id>:db:bingo-prd-backstage \
    --target-db-instance-class <current-instance-class> \
    --target-engine-version 14.15 \
    --target-allocated-storage 2000 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 4. 監控 Blue/Green Deployment 狀態
aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier <deployment-id> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 5. 執行切換（當 Green 環境準備就緒時）
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier <deployment-id> \
    --switchover-timeout 300 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 6. 切換後驗證
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1

# 7. 刪除 Blue/Green Deployment（保留舊的 Blue 環境作為備份或直接刪除）
aws rds delete-blue-green-deployment \
    --blue-green-deployment-identifier <deployment-id> \
    --delete-target no \
    --profile gemini-pro_ck \
    --region ap-east-1
```

#### 優點
- ✅ 停機時間極短（< 1 分鐘）
- ✅ AWS 原生支援，無需第三方工具
- ✅ 自動化程度高
- ✅ 可在切換前進行測試
- ✅ 支援快速回滾
- ✅ 資料完整性由 AWS 保證

#### 缺點
- ⚠️ 需要額外儲存成本（Green 環境執行期間）
- ⚠️ 儲存縮減過程可能需要數天（取決於資料量和 IOPS）
- ⚠️ 必須停用儲存自動擴展，否則可能失敗
- ⚠️ 需要額外 WAL 空間（建議至少 24 小時峰值 WAL 生成量）
- ⚠️ 不支援所有 Region（需確認 ap-east-1）

#### 成本估算
- **Green 環境成本**：與當前 Blue 環境相同的運算成本 + 2000 GB 儲存成本
- **執行期間**：假設儲存縮減需要 3-7 天
- **額外成本**：約 USD $150-350（假設 db.r6g.xlarge + gp3 儲存）
- **節省成本**：完成後每月節省約 3000 GB × USD $0.138/GB = USD $414/月

#### 時間估算
- **準備階段**：1-2 天（監控 WAL、停用自動擴展）
- **Green 環境創建**：6-12 小時
- **儲存縮減執行**：3-7 天（取決於資料量和 IOPS）
- **切換時間**：< 1 分鐘
- **總時間**：4-10 天（但只有 < 1 分鐘停機）

#### 風險等級：低-中

---

### 方案 2：AWS Database Migration Service (DMS)

#### 簡介
使用 AWS DMS 創建一個新的 RDS 實例（2000 GB），並透過持續複製將資料從舊實例遷移到新實例。

#### 技術原理
- 使用 Change Data Capture (CDC) 持續複製資料變更
- 分為 Full Load（全量載入）和 Ongoing Replication（持續複製）兩個階段
- 支援過濾器和轉換規則

#### 執行步驟

```bash
# 1. 創建目標 RDS 實例（2000 GB）
aws rds create-db-instance \
    --db-instance-identifier bingo-prd-backstage-new \
    --db-instance-class <current-instance-class> \
    --engine postgres \
    --engine-version 14.15 \
    --allocated-storage 2000 \
    --storage-type gp3 \
    --master-username <master-username> \
    --master-user-password <master-password> \
    --vpc-security-group-ids <security-group-ids> \
    --db-subnet-group-name <subnet-group-name> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 2. 創建 DMS Replication Instance
aws dms create-replication-instance \
    --replication-instance-identifier bingo-migration-instance \
    --replication-instance-class dms.c5.2xlarge \
    --allocated-storage 200 \
    --vpc-security-group-ids <security-group-ids> \
    --replication-subnet-group-identifier <subnet-group> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 3. 創建 Source Endpoint
aws dms create-endpoint \
    --endpoint-identifier bingo-source \
    --endpoint-type source \
    --engine-name postgres \
    --server-name <source-endpoint> \
    --port 5432 \
    --database-name <database-name> \
    --username <username> \
    --password <password> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 4. 創建 Target Endpoint
aws dms create-endpoint \
    --endpoint-identifier bingo-target \
    --endpoint-type target \
    --engine-name postgres \
    --server-name <target-endpoint> \
    --port 5432 \
    --database-name <database-name> \
    --username <username> \
    --password <password> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 5. 測試連接
aws dms test-connection \
    --replication-instance-arn <replication-instance-arn> \
    --endpoint-arn <source-endpoint-arn> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 6. 創建 Replication Task（Full Load + CDC）
aws dms create-replication-task \
    --replication-task-identifier bingo-migration-task \
    --source-endpoint-arn <source-endpoint-arn> \
    --target-endpoint-arn <target-endpoint-arn> \
    --replication-instance-arn <replication-instance-arn> \
    --migration-type full-load-and-cdc \
    --table-mappings file://table-mappings.json \
    --replication-task-settings file://task-settings.json \
    --profile gemini-pro_ck \
    --region ap-east-1

# 7. 啟動 Replication Task
aws dms start-replication-task \
    --replication-task-arn <task-arn> \
    --start-replication-task-type start-replication \
    --profile gemini-pro_ck \
    --region ap-east-1

# 8. 監控進度
aws dms describe-replication-tasks \
    --filters Name=replication-task-arn,Values=<task-arn> \
    --profile gemini-pro_ck \
    --region ap-east-1
```

**table-mappings.json 範例：**
```json
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
```

#### 優點
- ✅ 支援最小停機時間（通常 5-15 分鐘）
- ✅ AWS 原生服務
- ✅ 支援過濾和轉換
- ✅ 可監控複製進度
- ✅ 支援驗證資料一致性

#### 缺點
- ⚠️ 需要額外的 DMS Replication Instance 成本
- ⚠️ 配置相對複雜
- ⚠️ 需要手動切換應用程式連接字串
- ⚠️ 對於 1278 GB 資料，Full Load 可能需要 12-24 小時
- ⚠️ 需要處理 DDL 變更（DMS 不自動複製 DDL）

#### 成本估算
- **DMS Replication Instance**：dms.c5.2xlarge（8 vCPU, 16 GB RAM）約 USD $0.48/小時
- **目標 RDS 實例**：與當前實例相同（但儲存空間 2000 GB）
- **執行期間**：假設 3-5 天（包含測試和驗證）
- **DMS 成本**：3-5 天 × 24 小時 × USD $0.48 = USD $35-58
- **額外儲存成本**：執行期間需同時維護兩個 RDS 實例

#### 時間估算
- **準備階段**：1 天（創建目標實例、DMS 配置）
- **Full Load**：12-24 小時（1278 GB 資料）
- **CDC 同步追趕**：2-4 小時
- **測試驗證**：4-8 小時
- **切換時間**：5-15 分鐘（停止寫入、最後同步、切換連接）
- **總時間**：2-3 天（停機時間 5-15 分鐘）

#### 風險等級：中

---

### 方案 3：PostgreSQL 邏輯複製（Logical Replication）

#### 簡介
使用 PostgreSQL 原生的邏輯複製功能，在不停機的情況下將資料從舊實例複製到新實例。

#### 技術原理
- 基於 Publish-Subscribe 模型
- 透過解碼 Write-Ahead Log (WAL) 轉換為資料變更流
- 支援持續複製直到切換

#### 先決條件
```sql
-- 檢查 wal_level 設定
SHOW wal_level;  -- 必須為 'logical'

-- 如果不是 logical，需要修改參數群組
-- 注意：修改 wal_level 需要重啟資料庫
```

#### 執行步驟

```bash
# 1. 創建目標 RDS 實例（2000 GB）
aws rds create-db-instance \
    --db-instance-identifier bingo-prd-backstage-new \
    --db-instance-class <current-instance-class> \
    --engine postgres \
    --engine-version 14.15 \
    --allocated-storage 2000 \
    --storage-type gp3 \
    --master-username <master-username> \
    --master-user-password <master-password> \
    --vpc-security-group-ids <security-group-ids> \
    --db-subnet-group-name <subnet-group-name> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 2. 確認 wal_level 設定為 logical（如果不是，需要修改參數群組並重啟）

# 3. 在來源資料庫創建初始結構（schema only）
pg_dump -h <source-endpoint> \
        -U <username> \
        -d <database-name> \
        --schema-only \
        -f schema.sql

psql -h <target-endpoint> \
     -U <username> \
     -d <database-name> \
     -f schema.sql

# 4. 在來源資料庫創建 Publication
psql -h <source-endpoint> -U <username> -d <database-name>
```

```sql
-- 為所有資料表創建 Publication
CREATE PUBLICATION bingo_pub FOR ALL TABLES;

-- 或為特定資料表創建
-- CREATE PUBLICATION bingo_pub FOR TABLE table1, table2, table3;
```

```bash
# 5. 在目標資料庫創建 Subscription
psql -h <target-endpoint> -U <username> -d <database-name>
```

```sql
-- 創建 Subscription（會自動開始複製資料）
CREATE SUBSCRIPTION bingo_sub
CONNECTION 'host=<source-endpoint> port=5432 dbname=<database-name> user=<username> password=<password>'
PUBLICATION bingo_pub;

-- 監控複製狀態
SELECT * FROM pg_stat_subscription;

-- 檢查複製延遲
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS replication_lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

```bash
# 6. 等待初始同步完成（監控 pg_stat_subscription）

# 7. 驗證資料一致性
# 可使用工具如 pgcmp 或自定義查詢比較資料

# 8. 切換階段（停機時間 < 5 分鐘）
psql -h <source-endpoint> -U <username> -d <database-name>
```

```sql
-- a. 停止應用程式寫入或設定資料庫為唯讀
ALTER DATABASE <database-name> SET default_transaction_read_only = on;

-- b. 等待最後的複製完成（檢查 lag 為 0）

-- c. 停用 Subscription
ALTER SUBSCRIPTION bingo_sub DISABLE;

-- d. 在目標資料庫重建序列值
SELECT 'SELECT setval(''' ||
       quote_ident(PGT.schemaname) || '.' || quote_ident(S.relname) ||
       ''', COALESCE(MAX(' || quote_ident(C.attname) || '), 1) ) FROM ' ||
       quote_ident(PGT.schemaname) || '.' || quote_ident(T.relname) || ';'
FROM pg_class AS S,
     pg_depend AS D,
     pg_class AS T,
     pg_attribute AS C,
     pg_tables AS PGT
WHERE S.relkind = 'S'
  AND S.oid = D.objid
  AND D.refobjid = T.oid
  AND D.refobjid = C.attrelid
  AND D.refobjsubid = C.attnum
  AND T.relname = PGT.tablename
ORDER BY S.relname;

-- e. 切換應用程式連接到新資料庫

-- f. 清理 Publication（在舊資料庫）
DROP PUBLICATION bingo_pub;
```

#### 優點
- ✅ 停機時間極短（< 5 分鐘）
- ✅ PostgreSQL 原生功能，無需第三方工具
- ✅ 支援持續複製
- ✅ 可選擇性複製特定資料表
- ✅ 無需額外的 AWS 服務成本（只有 RDS 實例成本）

#### 缺點
- ⚠️ 需要 wal_level = logical（修改需要重啟資料庫，會有短暫停機）
- ⚠️ 不複製 DDL（需要手動處理結構變更）
- ⚠️ 不複製 Sequences、Large Objects
- ⚠️ 不複製 TRUNCATE 操作
- ⚠️ 需要手動處理 Sequences 的值同步
- ⚠️ 配置和監控需要 PostgreSQL 知識
- ⚠️ 複製期間會產生額外的 WAL，增加儲存使用

#### 成本估算
- **目標 RDS 實例**：與當前實例相同（但儲存空間 2000 GB）
- **執行期間**：假設 3-5 天（包含測試和驗證）
- **額外成本**：只有 RDS 實例成本，無其他服務費用
- **WAL 儲存**：複製期間 WAL 增加，可能需要 50-100 GB 額外空間

#### 時間估算
- **準備階段**：1 天（創建目標實例、檢查 wal_level、複製 schema）
- **如果需要修改 wal_level**：重啟時間約 5-10 分鐘（停機）
- **初始同步**：12-24 小時（1278 GB 資料）
- **追趕延遲**：2-4 小時
- **測試驗證**：4-8 小時
- **切換時間**：< 5 分鐘（停止寫入、最後同步、切換連接）
- **總時間**：2-3 天（停機時間 < 5 分鐘，如需修改 wal_level 則額外 5-10 分鐘）

#### 風險等級：中

---

### 方案 4：pg_dump / pg_restore 手動遷移

#### 簡介
使用 PostgreSQL 原生工具 pg_dump 和 pg_restore 進行傳統的備份還原遷移。

#### 技術原理
- pg_dump 創建資料庫的邏輯備份
- 支援多種格式（custom、directory、plain text、tar）
- pg_restore 將備份還原到新實例

#### 執行步驟

```bash
# 1. 創建目標 RDS 實例（2000 GB）
aws rds create-db-instance \
    --db-instance-identifier bingo-prd-backstage-new \
    --db-instance-class <current-instance-class> \
    --engine postgres \
    --engine-version 14.15 \
    --allocated-storage 2000 \
    --storage-type gp3 \
    --master-username <master-username> \
    --master-user-password <master-password> \
    --vpc-security-group-ids <security-group-ids> \
    --db-subnet-group-name <subnet-group-name> \
    --profile gemini-pro_ck \
    --region ap-east-1

# 2. 準備執行機器（建議使用同一 VPC 內的 EC2，網路延遲最低）
# 機器規格建議：至少 8 vCPU, 16 GB RAM, 200 GB 儲存空間（用於暫存 dump 檔案）

# 3. 安裝 PostgreSQL 客戶端工具（版本應與資料庫版本相符）
sudo yum install -y postgresql14

# 4. 停止應用程式寫入（重要！）
# 設定資料庫為唯讀模式
psql -h <source-endpoint> -U <username> -d <database-name> \
     -c "ALTER DATABASE <database-name> SET default_transaction_read_only = on;"

# 5. 執行 pg_dump（使用 directory 格式以支援並行）
pg_dump -h <source-endpoint> \
        -U <username> \
        -d <database-name> \
        -Fd \
        -j 8 \
        -f /path/to/dump/directory \
        --verbose

# 或使用 custom 格式（單檔案，支援壓縮）
pg_dump -h <source-endpoint> \
        -U <username> \
        -d <database-name> \
        -Fc \
        -f /path/to/dump/backup.dump \
        --verbose

# 6. 驗證 dump 檔案完整性
# 檢查檔案大小和完整性

# 7. 執行 pg_restore（使用並行提升速度）
pg_restore -h <target-endpoint> \
           -U <username> \
           -d <database-name> \
           -Fd \
           -j 8 \
           /path/to/dump/directory \
           --verbose

# 或從 custom 格式還原
pg_restore -h <target-endpoint> \
           -U <username> \
           -d <database-name> \
           -Fc \
           -j 8 \
           /path/to/dump/backup.dump \
           --verbose

# 8. 還原後處理
psql -h <target-endpoint> -U <username> -d <database-name>
```

```sql
-- 更新統計資訊
ANALYZE;

-- 重建索引（如果需要）
REINDEX DATABASE <database-name>;

-- 檢查資料完整性
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

```bash
# 9. 驗證資料一致性
# 比較資料表數量、行數、關鍵資料

# 10. 切換應用程式連接到新資料庫

# 11. 移除舊資料庫的唯讀限制（如果需要保留作為備份）
psql -h <source-endpoint> -U <username> -d <database-name> \
     -c "ALTER DATABASE <database-name> SET default_transaction_read_only = off;"
```

#### 優點
- ✅ 最簡單、最直接的方法
- ✅ PostgreSQL 原生工具，穩定可靠
- ✅ 無需額外的 AWS 服務
- ✅ 支援並行操作（-j 參數）
- ✅ 產生的備份可長期保存
- ✅ 適合非高可用性需求的場景

#### 缺點
- ⚠️ 需要較長停機時間（數小時到一天以上）
- ⚠️ 對於 > 100 GB 的資料庫，AWS 不推薦此方法
- ⚠️ 需要足夠的暫存空間存放 dump 檔案
- ⚠️ 網路頻寬影響執行時間
- ⚠️ 無法增量複製，必須完整備份還原
- ⚠️ 應用程式必須完全停止寫入

#### 成本估算
- **目標 RDS 實例**：與當前實例相同（但儲存空間 2000 GB）
- **EC2 執行機器**：c5.2xlarge（8 vCPU, 16 GB RAM）約 USD $0.34/小時
- **EC2 儲存**：200 GB gp3，約 USD $20
- **執行期間**：假設 2-3 天（包含測試和驗證）
- **EC2 成本**：3 天 × 24 小時 × USD $0.34 = USD $24.48
- **總額外成本**：約 USD $45

#### 時間估算
- **準備階段**：1 天（創建目標實例、準備執行機器）
- **停止應用程式**：10-30 分鐘
- **pg_dump 執行**：6-12 小時（1278 GB，使用 -j 8）
- **傳輸時間**：如果 dump 到本機再 restore，無額外傳輸時間；如果透過網路，取決於頻寬
- **pg_restore 執行**：8-16 小時（1278 GB，使用 -j 8）
- **還原後處理**：2-4 小時（ANALYZE, REINDEX）
- **驗證**：2-4 小時
- **總停機時間**：18-36 小時
- **總時間**：2-3 天

#### 風險等級：中-高

---

### 方案 5：Read Replica 提升法

#### 簡介
創建一個較小儲存空間的唯讀副本（Read Replica），然後將其提升為獨立的 RDS 實例，最後將應用程式切換到新實例。

#### 技術原理
- RDS Read Replica 使用物理複製保持與主實例同步
- 提升（Promote）後變為獨立的讀寫實例
- **關鍵限制**：創建 Read Replica 時，儲存空間必須 ≥ 主實例

#### 可行性評估
❌ **此方法不適用於縮減儲存空間**

根據 AWS 文件和最佳實踐：
- 創建 Read Replica 時，AWS 會複製主實例的儲存設定
- 無法創建比主實例儲存空間更小的 Read Replica
- 即使實際使用量只有 1278 GB，Read Replica 的儲存空間仍會是 5024 GB

#### 替代思路
如果您希望使用 Read Replica，可以考慮：
1. 先使用其他方法（如 Blue/Green 或 DMS）將資料遷移到 2000 GB 的新實例
2. 然後從新實例創建 Read Replica 用於讀取分流

#### 結論
此方法**不適合**用於縮減儲存空間的場景。

---

### 方案 6：快照還原（Snapshot Restore）❌ 不可行

#### 為何不可行
AWS RDS 的快照包含分配儲存空間的元資料，還原時會自動使用相同的儲存空間設定。根據 AWS 官方文件和政策：

- ❌ 無法從快照還原到較小的儲存空間
- ❌ 還原時的最小儲存空間 = 原始實例曾經使用的最大儲存空間
- ❌ 這是 AWS RDS 的設計限制，無法繞過

#### AWS 官方說明
> "When restoring from a snapshot, the minimum allocated storage size is determined by the maximum storage size ever used by the original instance."

#### 結論
此方法**完全不可行**用於縮減儲存空間。

---

### 方案 7：AWS Backup 還原 ❌ 不可行

#### 為何不可行
AWS Backup 本質上使用 RDS 快照作為備份機制，因此具有相同的限制：

- ❌ 無法還原到較小的儲存空間
- ❌ 還原行為與快照還原相同

#### 結論
此方法**完全不可行**用於縮減儲存空間。

---

### 方案 8：第三方工具

#### 8.1 Bucardo
- **類型**：PostgreSQL 多主複製工具
- **特點**：支援異步複製、衝突解決
- **停機時間**：極短（< 5 分鐘）
- **複雜度**：高
- **成本**：開源免費，但需要自行維護
- **風險**：需要深入了解工具和 PostgreSQL

#### 8.2 SymmetricDS
- **類型**：跨資料庫複製平台
- **特點**：支援多種資料庫、雙向複製
- **停機時間**：極短（< 5 分鐘）
- **複雜度**：中-高
- **成本**：開源免費，企業版收費
- **風險**：配置複雜，需要測試

#### 8.3 DBConvert / Spectral Core
- **類型**：商業資料庫遷移工具
- **特點**：GUI 介面、支援多種資料庫
- **停機時間**：視工具而定（5 分鐘 - 數小時）
- **複雜度**：中
- **成本**：授權費用（數百到數千美元）
- **風險**：依賴第三方供應商

#### 8.4 Attunity Replicate (Qlik Replicate)
- **類型**：企業級資料複製平台
- **特點**：高效能、支援大規模遷移
- **停機時間**：極短（< 5 分鐘）
- **複雜度**：高
- **成本**：企業授權（昂貴）
- **風險**：需要專業支援

#### 評估
對於當前場景（1278 GB PostgreSQL 生產環境），**不建議**使用第三方工具，原因：
1. AWS 原生方案（Blue/Green, DMS）已足夠強大
2. 第三方工具增加複雜度和風險
3. 需要額外的學習曲線和維護成本
4. 可能缺乏 AWS RDS 的深度整合

---

## 詳細比較表格

### 主要比較表

| 方案 | 停機時間 | 技術複雜度 | 成本 | 風險等級 | 資料完整性 | 回滾能力 | 適用場景 |
|------|----------|-----------|------|---------|-----------|---------|---------|
| **1. Blue/Green Deployment** | < 1 分鐘 | 低-中 | USD $150-350 | 低-中 | 極高 (AWS 保證) | 優秀 (可保留 Blue) | ✅ **最佳選擇** - 生產環境、需要最小停機時間 |
| **2. AWS DMS** | 5-15 分鐘 | 中 | USD $35-58 + RDS | 中 | 高 (需驗證) | 良好 (保留原實例) | ✅ 生產環境、可接受短暫停機、需要靈活配置 |
| **3. 邏輯複製** | < 5 分鐘 | 中-高 | 僅 RDS 成本 | 中 | 高 (需驗證) | 良好 (保留原實例) | ✅ 生產環境、PostgreSQL 專業團隊、無額外服務成本 |
| **4. pg_dump/restore** | 18-36 小時 | 低 | USD $45 + RDS | 中-高 | 高 (原生工具) | 良好 (有備份檔案) | ⚠️ 非關鍵業務、可接受長時間停機 |
| **5. Read Replica** | N/A | N/A | N/A | N/A | N/A | N/A | ❌ **不適用於縮減儲存** |
| **6. 快照還原** | N/A | N/A | N/A | N/A | N/A | N/A | ❌ **AWS 不支援** |
| **7. AWS Backup** | N/A | N/A | N/A | N/A | N/A | N/A | ❌ **AWS 不支援** |
| **8. 第三方工具** | < 5 分鐘 - 數小時 | 高 | 授權費用 | 中-高 | 視工具而定 | 視工具而定 | ⚠️ 有特殊需求時考慮 |

### 詳細特性比較

| 特性 | Blue/Green | DMS | 邏輯複製 | pg_dump/restore |
|------|-----------|-----|---------|----------------|
| **AWS 原生支援** | ✅ 是 | ✅ 是 | ⚠️ 部分（RDS 支援邏輯複製但需手動配置） | ⚠️ 工具原生，需自行操作 |
| **自動化程度** | ✅ 高 | ✅ 高 | ⚠️ 中（需手動配置複製） | ❌ 低（全手動） |
| **需要額外服務** | ❌ 否 | ✅ 是（DMS Replication Instance） | ❌ 否 | ⚠️ 是（EC2 執行機器） |
| **支援並行處理** | ✅ 是（AWS 內部） | ✅ 是 | ⚠️ 有限（PostgreSQL worker 數量） | ✅ 是（-j 參數） |
| **支援增量複製** | ✅ 是（持續同步） | ✅ 是（CDC） | ✅ 是（持續複製） | ❌ 否（全量複製） |
| **需要修改 wal_level** | ❌ 否 | ❌ 否 | ✅ 是（如果當前不是 logical） | ❌ 否 |
| **支援 DDL 複製** | ✅ 是（完整複製） | ❌ 否（需手動處理） | ❌ 否（需手動處理） | ✅ 是（包含在 dump） |
| **網路頻寬需求** | ⚠️ 中-高（AWS 內部網路） | ⚠️ 中-高 | ⚠️ 中-高 | ⚠️ 高（如跨區域） |
| **暫存空間需求** | ✅ 無（AWS 管理） | ✅ 最小（50-100 GB） | ✅ 最小（WAL 空間） | ⚠️ 高（需存放 dump 檔案） |
| **監控和報告** | ✅ CloudWatch 整合 | ✅ DMS 控制台 + CloudWatch | ⚠️ 需手動查詢 | ❌ 無（需自行監控） |
| **錯誤處理** | ✅ 自動重試和恢復 | ✅ 自動重試 | ⚠️ 需手動處理 | ❌ 需手動重試 |
| **切換複雜度** | ✅ 低（自動切換） | ⚠️ 中（需手動切換連接） | ⚠️ 中（需手動切換連接） | ⚠️ 中（需手動切換連接） |
| **適合資料庫大小** | ✅ 任意大小 | ✅ > 100 GB | ✅ > 100 GB | ⚠️ < 100 GB（AWS 建議） |

### 時間線比較（以 1278 GB 資料為例）

| 階段 | Blue/Green | DMS | 邏輯複製 | pg_dump/restore |
|------|-----------|-----|---------|----------------|
| **準備** | 1-2 天 | 1 天 | 1 天 | 1 天 |
| **資料同步** | 3-7 天（背景執行） | 12-24 小時 | 12-24 小時 | N/A |
| **追趕延遲** | 自動 | 2-4 小時 | 2-4 小時 | N/A |
| **停機開始** | 切換前 | 停止寫入 | 停止寫入 | 停止應用程式 |
| **最後同步** | < 1 分鐘 | 5-10 分鐘 | 2-5 分鐘 | N/A |
| **備份** | 6-12 小時 | N/A | N/A | 6-12 小時 |
| **還原** | N/A | N/A | N/A | 8-16 小時 |
| **還原後處理** | 自動 | 1-2 小時 | 1-2 小時 | 2-4 小時 |
| **驗證** | 2-4 小時 | 2-4 小時 | 2-4 小時 | 2-4 小時 |
| **切換連接** | 自動 | 10-30 分鐘 | 10-30 分鐘 | 10-30 分鐘 |
| **停機結束** | 切換後 | 切換後 | 切換後 | 切換後 |
| **總停機時間** | **< 1 分鐘** | **5-15 分鐘** | **< 5 分鐘** | **18-36 小時** |
| **總執行時間** | **4-10 天** | **2-3 天** | **2-3 天** | **2-3 天** |

### 成本比較（以 db.r6g.xlarge + gp3 為例）

| 成本項目 | Blue/Green | DMS | 邏輯複製 | pg_dump/restore |
|---------|-----------|-----|---------|----------------|
| **新 RDS 實例（2000 GB）** | 執行期間（3-7 天） | 執行期間（2-3 天） | 執行期間（2-3 天） | 執行期間（2-3 天） |
| **額外服務成本** | Green 環境 (USD $150-350) | DMS Instance (USD $35-58) | 無 | EC2 (USD $25) |
| **儲存成本（執行期間）** | 2000 GB × 3-7 天 | 2000 GB × 2-3 天 | 2000 GB × 2-3 天 | 2000 GB × 2-3 天 |
| **網路傳輸** | 無（AWS 內部） | 無（同 Region） | 無（同 Region） | 無（同 Region） |
| **總額外成本（估算）** | **USD $150-350** | **USD $35-58** | **僅 RDS 成本** | **USD $45** |
| **完成後月度節省** | USD $414/月 | USD $414/月 | USD $414/月 | USD $414/月 |
| **投資回報期** | < 1 個月 | < 1 個月 | 立即 | < 1 個月 |

---

## 推薦方案

### 第一推薦：Blue/Green Deployment 儲存縮減 ⭐⭐⭐⭐⭐

#### 推薦理由
1. **停機時間最短**：< 1 分鐘，幾乎不影響業務
2. **AWS 原生支援**：2024 年 11 月新功能，專為此場景設計
3. **自動化程度高**：無需複雜的手動配置
4. **風險可控**：可在切換前充分測試，支援快速回滾
5. **資料完整性保證**：AWS 內部機制保證資料一致性

#### 適用情況
- ✅ 生產環境，對停機時間要求極高
- ✅ 希望使用 AWS 原生功能，減少自行管理的複雜度
- ✅ 可接受數天的儲存縮減準備時間
- ✅ 預算允許短期額外成本（USD $150-350）

#### 關鍵注意事項
1. **確認 Region 支援**：需確認 ap-east-1 (香港) 是否支援此功能
   ```bash
   # 檢查方法：嘗試創建 Blue/Green Deployment
   aws rds create-blue-green-deployment --help
   # 查看是否有 --target-allocated-storage 參數
   ```

2. **必須停用儲存自動擴展**：這是**最關鍵**的步驟，否則可能失敗

3. **監控 WAL 生成量**：確保有足夠的額外儲存空間（建議至少 24 小時峰值 WAL 量）

4. **執行時間不確定**：儲存縮減可能需要 3-7 天，需提前規劃

#### 執行前檢查清單
- [ ] 確認 ap-east-1 支援 Blue/Green Deployment 儲存縮減
- [ ] 確認當前 PostgreSQL 版本 ≥ 12（✅ 14.15 符合）
- [ ] 確認當前實例類型 ≥ db.t3.medium
- [ ] 監控 24-48 小時的 TransactionLogsGeneration 指標
- [ ] 計算所需額外儲存空間（當前 5024 GB + 至少 24 小時 WAL 量）
- [ ] 停用儲存自動擴展
- [ ] 準備回滾計畫（保留舊的 Blue 環境作為備份）
- [ ] 通知利益相關者執行時間和可能的影響

---

### 第二推薦：PostgreSQL 邏輯複製 ⭐⭐⭐⭐

#### 推薦理由
1. **停機時間極短**：< 5 分鐘
2. **無額外服務成本**：只需新 RDS 實例成本
3. **PostgreSQL 原生功能**：穩定可靠
4. **控制能力強**：可精確控制複製過程和切換時間

#### 適用情況
- ✅ 有 PostgreSQL 專業團隊
- ✅ 希望節省額外服務成本
- ✅ 需要對遷移過程有精細控制
- ✅ 如果 Blue/Green Deployment 在 ap-east-1 不可用

#### 關鍵注意事項
1. **檢查 wal_level**：如果不是 `logical`，需要修改並重啟（短暫停機）
   ```sql
   SHOW wal_level;
   ```

2. **不複製 DDL**：執行期間的結構變更需要手動同步

3. **Sequences 需要手動處理**：切換前需要同步序列值

4. **監控複製延遲**：確保切換時延遲為 0

#### 執行前檢查清單
- [ ] 檢查 wal_level 設定（是否為 logical）
- [ ] 如需修改 wal_level，規劃重啟時間（5-10 分鐘停機）
- [ ] 測試 Publication 和 Subscription 創建
- [ ] 準備監控腳本（複製延遲、錯誤）
- [ ] 準備 Sequences 同步腳本
- [ ] 準備切換手冊（詳細步驟）
- [ ] 測試回滾流程

---

### 第三推薦：AWS DMS ⭐⭐⭐

#### 推薦理由
1. **停機時間短**：5-15 分鐘
2. **AWS 原生服務**：穩定可靠
3. **自動化程度高**：配置後自動執行
4. **監控完善**：DMS 控制台提供詳細進度

#### 適用情況
- ✅ 希望使用 AWS 原生服務但 Blue/Green 不可用
- ✅ 可接受短暫停機（5-15 分鐘）
- ✅ 希望有 GUI 介面管理遷移過程
- ✅ 預算允許額外 DMS 服務成本

#### 關鍵注意事項
1. **不複製 DDL**：需要手動處理結構變更

2. **配置相對複雜**：需要創建 Endpoints、Replication Instance、Task

3. **Full Load 時間較長**：對於 1278 GB 可能需要 12-24 小時

#### 執行前檢查清單
- [ ] 設計 DMS Replication Instance 規格（建議 dms.c5.2xlarge）
- [ ] 準備 Table Mappings 配置
- [ ] 準備 Task Settings 配置
- [ ] 測試連接（Source 和 Target Endpoints）
- [ ] 準備監控腳本
- [ ] 規劃切換時間和步驟
- [ ] 測試回滾流程

---

### 不推薦：pg_dump / pg_restore ⭐⭐

#### 為何不推薦
1. **停機時間過長**：18-36 小時，對生產環境影響太大
2. **AWS 不推薦**：對於 > 100 GB 的資料庫
3. **風險較高**：全手動操作，容易出錯

#### 可考慮使用的情況
- ⚠️ 非關鍵業務系統
- ⚠️ 可接受長時間停機
- ⚠️ 團隊對其他方案不熟悉，只會使用原生工具
- ⚠️ 預算極度有限（最低成本方案）

---

## 執行計畫範例

### 針對 bingo-prd-backstage 的推薦執行計畫（使用 Blue/Green Deployment）

#### 階段 1：準備與驗證（第 1-2 天）

##### 1.1 確認技術可行性
```bash
# 檢查 ap-east-1 是否支援 Blue/Green Deployment 儲存縮減
aws rds create-blue-green-deployment help | grep target-allocated-storage

# 檢查當前實例配置
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].[DBInstanceClass,Engine,EngineVersion,AllocatedStorage,StorageType]'
```

##### 1.2 監控 WAL 生成量（至少 24 小時，建議 48 小時）
```bash
# 查詢過去 48 小時的 WAL 生成量
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name TransactionLogsGeneration \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time $(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 3600 \
    --statistics Sum Maximum \
    --profile gemini-pro_ck \
    --region ap-east-1

# 計算所需額外儲存空間
# 當前: 5024 GB
# 使用: 1278 GB
# 可用: 3746 GB
# 需要: 至少 24 小時峰值 WAL 量（假設為 100 GB）
# 結論: 3746 GB > 100 GB，空間充足
```

##### 1.3 停用儲存自動擴展（關鍵步驟！）
```bash
# 停用儲存自動擴展
aws rds modify-db-instance \
    --db-instance-identifier bingo-prd-backstage \
    --max-allocated-storage 0 \
    --apply-immediately \
    --profile gemini-pro_ck \
    --region ap-east-1

# 驗證修改結果
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].MaxAllocatedStorage'
# 應該返回 0
```

##### 1.4 創建最終快照作為備份
```bash
# 創建手動快照
aws rds create-db-snapshot \
    --db-instance-identifier bingo-prd-backstage \
    --db-snapshot-identifier bingo-prd-backstage-before-resize-$(date +%Y%m%d) \
    --profile gemini-pro_ck \
    --region ap-east-1

# 等待快照完成
aws rds wait db-snapshot-completed \
    --db-snapshot-identifier bingo-prd-backstage-before-resize-$(date +%Y%m%d) \
    --profile gemini-pro_ck \
    --region ap-east-1
```

##### 1.5 準備監控腳本
```bash
# 創建監控腳本 monitor-blue-green.sh
cat > monitor-blue-green.sh << 'EOF'
#!/bin/bash

DEPLOYMENT_ID=$1
PROFILE="gemini-pro_ck"
REGION="ap-east-1"

if [ -z "$DEPLOYMENT_ID" ]; then
    echo "Usage: $0 <blue-green-deployment-id>"
    exit 1
fi

while true; do
    STATUS=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text)

    echo "$(date): Blue/Green Deployment Status: $STATUS"

    if [ "$STATUS" == "AVAILABLE" ]; then
        echo "Green environment is ready for switchover!"
        break
    elif [ "$STATUS" == "INVALID" ] || [ "$STATUS" == "DELETING" ]; then
        echo "Error: Deployment failed or is being deleted!"
        exit 1
    fi

    sleep 300  # 每 5 分鐘檢查一次
done
EOF

chmod +x monitor-blue-green.sh
```

#### 階段 2：創建 Blue/Green Deployment（第 2-3 天）

##### 2.1 獲取當前實例配置
```bash
# 獲取詳細配置
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 > bingo-current-config.json

# 提取關鍵資訊
INSTANCE_CLASS=$(jq -r '.DBInstances[0].DBInstanceClass' bingo-current-config.json)
ENGINE_VERSION=$(jq -r '.DBInstances[0].EngineVersion' bingo-current-config.json)
INSTANCE_ARN=$(jq -r '.DBInstances[0].DBInstanceArn' bingo-current-config.json)

echo "Instance Class: $INSTANCE_CLASS"
echo "Engine Version: $ENGINE_VERSION"
echo "Instance ARN: $INSTANCE_ARN"
```

##### 2.2 創建 Blue/Green Deployment
```bash
# 創建 Blue/Green Deployment
aws rds create-blue-green-deployment \
    --blue-green-deployment-name bingo-storage-reduction-$(date +%Y%m%d) \
    --source-arn "$INSTANCE_ARN" \
    --target-db-instance-class "$INSTANCE_CLASS" \
    --target-engine-version "$ENGINE_VERSION" \
    --target-allocated-storage 2000 \
    --target-storage-type gp3 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 記錄 Deployment ID
DEPLOYMENT_ID=$(aws rds describe-blue-green-deployments \
    --filters Name=blue-green-deployment-name,Values=bingo-storage-reduction-$(date +%Y%m%d) \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].BlueGreenDeploymentIdentifier' \
    --output text)

echo "Blue/Green Deployment ID: $DEPLOYMENT_ID"
echo "$DEPLOYMENT_ID" > deployment-id.txt
```

##### 2.3 監控 Green 環境創建進度
```bash
# 啟動監控腳本
./monitor-blue-green.sh "$DEPLOYMENT_ID" > blue-green-monitor.log 2>&1 &

# 或手動檢查
aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1
```

#### 階段 3：等待儲存縮減完成（第 3-9 天）

##### 3.1 持續監控
```bash
# 每天檢查一次狀態
aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].[Status,StatusDetails]'

# 監控 Green 環境的儲存使用量
GREEN_INSTANCE_ID=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].Target.DBInstanceIdentifier' \
    --output text)

aws rds describe-db-instances \
    --db-instance-identifier "$GREEN_INSTANCE_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].[AllocatedStorage,DBInstanceStatus]'
```

##### 3.2 驗證 Green 環境（當 Status 為 AVAILABLE 時）
```bash
# 獲取 Green 環境連接端點
GREEN_ENDPOINT=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].Target.Endpoint' \
    --output text)

echo "Green Endpoint: $GREEN_ENDPOINT"

# 連接到 Green 環境進行驗證
psql -h "$GREEN_ENDPOINT" -U <username> -d <database-name>
```

```sql
-- 檢查資料庫大小
SELECT pg_size_pretty(pg_database_size(current_database()));

-- 檢查資料表數量
SELECT count(*) FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema');

-- 檢查關鍵資料表的行數
SELECT schemaname, tablename, n_tup_ins, n_tup_upd, n_tup_del
FROM pg_stat_user_tables
ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC
LIMIT 10;

-- 檢查複製延遲（應為 0 或非常小）
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

#### 階段 4：規劃切換（第 9-10 天）

##### 4.1 通知利益相關者
```text
主旨：bingo-prd-backstage 儲存空間縮減維護通知

親愛的團隊：

我們將執行 bingo-prd-backstage 資料庫的儲存空間縮減維護。

維護時間：[日期] [時間]（預計停機時間：< 1 分鐘）
影響範圍：bingo-prd-backstage 資料庫
預期停機時間：少於 1 分鐘

維護內容：
- 使用 AWS Blue/Green Deployment 將儲存空間從 5024 GB 縮減到 2000 GB
- 資料完整性由 AWS 保證
- 維護期間，應用程式可能短暫無法連接資料庫

回滾計畫：
- 如果切換失敗，將立即切換回原 Blue 環境
- Blue 環境將保留 7 天作為備份

如有疑問，請聯繫 DevOps 團隊。

謝謝！
```

##### 4.2 準備切換檢查清單
```markdown
### 切換前檢查清單

- [ ] Green 環境狀態為 AVAILABLE
- [ ] Green 環境連接測試成功
- [ ] Green 環境資料驗證通過
- [ ] 複製延遲為 0 或極小（< 1 秒）
- [ ] 備份已完成並驗證
- [ ] 監控系統準備就緒
- [ ] 通知已發送給所有利益相關者
- [ ] 回滾計畫已準備
- [ ] 團隊成員待命

### 切換步驟

1. [ ] 停止或暫停非關鍵的批次作業
2. [ ] 執行切換命令
3. [ ] 監控切換進度
4. [ ] 驗證應用程式連接
5. [ ] 檢查關鍵業務功能
6. [ ] 監控錯誤日誌
7. [ ] 確認切換成功
8. [ ] 通知利益相關者

### 切換後驗證

- [ ] 資料庫連接正常
- [ ] 應用程式功能正常
- [ ] 無錯誤日誌
- [ ] 儲存空間為 2000 GB
- [ ] 效能指標正常
```

#### 階段 5：執行切換（第 10 天）

##### 5.1 最後檢查
```bash
# 檢查 Green 環境狀態
aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1

# 檢查複製延遲
psql -h "$GREEN_ENDPOINT" -U <username> -d <database-name> -c \
    "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

##### 5.2 執行切換
```bash
# 執行切換（switchover-timeout 設為 5 分鐘 = 300 秒）
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --switchover-timeout 300 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 即時監控切換進度
watch -n 5 "aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier $DEPLOYMENT_ID \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].Status'"
```

##### 5.3 驗證切換結果
```bash
# 檢查實例狀態
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].[DBInstanceStatus,AllocatedStorage,Endpoint.Address]'

# 連接並驗證
CURRENT_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

psql -h "$CURRENT_ENDPOINT" -U <username> -d <database-name>
```

```sql
-- 驗證資料庫
SELECT pg_size_pretty(pg_database_size(current_database()));
SELECT count(*) FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema');

-- 檢查最近的寫入
SELECT schemaname, tablename, n_tup_ins, n_tup_upd, n_tup_del, last_autovacuum
FROM pg_stat_user_tables
ORDER BY greatest(n_tup_ins, n_tup_upd, n_tup_del) DESC
LIMIT 10;
```

##### 5.4 應用程式驗證
```bash
# 檢查應用程式日誌（假設使用 CloudWatch）
aws logs tail /aws/rds/instance/bingo-prd-backstage/postgresql \
    --since 5m \
    --follow \
    --profile gemini-pro_ck \
    --region ap-east-1

# 測試關鍵 API 端點
curl -X POST https://<your-api-endpoint>/health-check
```

##### 5.5 監控關鍵指標（切換後 1 小時）
```bash
# CPU 使用率
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Average \
    --profile gemini-pro_ck \
    --region ap-east-1

# 資料庫連接數
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Average \
    --profile gemini-pro_ck \
    --region ap-east-1

# 讀寫 IOPS
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ReadIOPS \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Average \
    --profile gemini-pro_ck \
    --region ap-east-1
```

#### 階段 6：清理和最佳化（第 11-14 天）

##### 6.1 保留 Blue 環境 7 天作為備份
```bash
# 檢查舊 Blue 環境的 ID
OLD_BLUE_ID=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].Source.DBInstanceIdentifier' \
    --output text)

echo "Old Blue Instance ID: $OLD_BLUE_ID"

# 設定提醒，7 天後刪除
echo "Reminder: Delete old Blue instance on $(date -d '+7 days' '+%Y-%m-%d')" >> cleanup-reminder.txt
```

##### 6.2 重新啟用儲存自動擴展（如果需要）
```bash
# 重新啟用儲存自動擴展，最大值設為 3000 GB（預留緩衝）
aws rds modify-db-instance \
    --db-instance-identifier bingo-prd-backstage \
    --max-allocated-storage 3000 \
    --apply-immediately \
    --profile gemini-pro_ck \
    --region ap-east-1
```

##### 6.3 清理 Blue/Green Deployment（7 天後）
```bash
# 刪除 Blue/Green Deployment（保留舊的 Blue 環境或一起刪除）
aws rds delete-blue-green-deployment \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --delete-target yes \
    --profile gemini-pro_ck \
    --region ap-east-1

# 如果選擇保留舊的 Blue 環境，稍後單獨刪除
# aws rds delete-db-instance \
#     --db-instance-identifier "$OLD_BLUE_ID" \
#     --skip-final-snapshot \
#     --profile gemini-pro_ck \
#     --region ap-east-1
```

##### 6.4 最佳化新資料庫
```sql
-- 連接到新資料庫
psql -h <endpoint> -U <username> -d <database-name>

-- 更新統計資訊
ANALYZE;

-- 檢查是否需要 VACUUM
SELECT schemaname, tablename,
       n_dead_tup,
       n_live_tup,
       round(n_dead_tup * 100.0 / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 20;

-- 如果 dead_ratio 很高，執行 VACUUM（可能需要較長時間）
-- VACUUM ANALYZE;
```

##### 6.5 更新文件和記錄
```bash
# 記錄最終配置
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 > bingo-final-config.json

# 生成報告
cat > resize-completion-report.md << EOF
# bingo-prd-backstage 儲存空間縮減完成報告

## 執行摘要
- **執行日期**：$(date +%Y-%m-%d)
- **原儲存空間**：5024 GB
- **新儲存空間**：2000 GB
- **縮減幅度**：3024 GB (60%)
- **停機時間**：< 1 分鐘
- **資料完整性**：100% 保留

## 關鍵指標
- **切換時間**：[填入實際時間]
- **資料驗證**：通過
- **應用程式驗證**：通過
- **效能影響**：無明顯影響

## 成本節省
- **每月節省**：約 USD $414
- **年度節省**：約 USD $4,968

## 經驗總結
- [填入實際經驗]

## 建議
- [填入未來建議]

EOF

echo "Resize completed successfully!"
```

---

## 風險評估與應對策略

### 風險矩陣

| 風險 | 可能性 | 影響程度 | 風險等級 | 應對策略 |
|------|-------|---------|---------|---------|
| **Blue/Green 在 ap-east-1 不可用** | 中 | 高 | 高 | 事前確認；準備備選方案（邏輯複製或 DMS） |
| **儲存縮減時間超過預期（> 7 天）** | 中 | 中 | 中 | 提前規劃；持續監控；與利益相關者溝通 |
| **切換時應用程式無法連接** | 低 | 高 | 中 | 事前測試；準備快速回滾；監控應用程式日誌 |
| **資料不一致或損壞** | 極低 | 極高 | 中 | 事前備份；切換後立即驗證；保留 Blue 環境 7 天 |
| **效能下降** | 低 | 中 | 低-中 | 監控關鍵指標；準備擴展計畫；必要時回滾 |
| **儲存自動擴展未停用導致失敗** | 中 | 高 | 高 | **關鍵**：執行前確認已停用；文件化此步驟 |
| **WAL 空間不足導致複製失敗** | 低 | 高 | 中 | 監控 24-48 小時 WAL 生成量；確保足夠緩衝空間 |
| **切換超時（> 5 分鐘）** | 低 | 中 | 低-中 | 增加 switchover-timeout；選擇低流量時段執行 |
| **舊 Blue 環境意外刪除** | 極低 | 高 | 低-中 | 設定 7 天保留期；使用 AWS Backup；標記為重要資源 |
| **應用程式配置未更新** | 低 | 中 | 低-中 | 自動切換使用相同端點；驗證應用程式連接 |

### 關鍵風險詳細分析

#### 1. Blue/Green Deployment 在 ap-east-1 不可用

**症狀**：
- 執行 `aws rds create-blue-green-deployment` 時返回錯誤
- AWS 文件顯示 ap-east-1 不在支援 Region 列表中

**預防措施**：
```bash
# 執行計畫前確認
aws rds create-blue-green-deployment help | grep target-allocated-storage

# 查詢 AWS 支援
aws support create-case \
    --subject "Confirm Blue/Green Deployment availability in ap-east-1" \
    --service-code "amazon-rds" \
    --category-code "general-inquiry" \
    --communication-body "Please confirm if Blue/Green Deployment with storage shrink is available in ap-east-1 region." \
    --profile gemini-pro_ck
```

**應對策略**：
- 如果不可用，切換到**備選方案 2：PostgreSQL 邏輯複製**
- 或使用**備選方案 3：AWS DMS**

---

#### 2. 儲存自動擴展未停用導致失敗

**症狀**：
- Blue/Green Deployment 創建失敗或儲存空間沒有縮減
- Green 環境的儲存空間自動擴展回 5024 GB

**預防措施**：
```bash
# 執行前確認（多次確認！）
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].MaxAllocatedStorage'

# 應該返回 0，如果不是，立即修改
aws rds modify-db-instance \
    --db-instance-identifier bingo-prd-backstage \
    --max-allocated-storage 0 \
    --apply-immediately \
    --profile gemini-pro_ck \
    --region ap-east-1
```

**應對策略**：
- 在創建 Blue/Green Deployment **之前**停用
- 在創建 Blue/Green Deployment **之後**再次確認
- 文件化此步驟為**關鍵必要步驟**

---

#### 3. 切換時應用程式無法連接

**症狀**：
- 切換後應用程式報告資料庫連接錯誤
- 大量 "could not connect to server" 錯誤

**預防措施**：
- 選擇低流量時段執行（如凌晨 2-4 AM）
- 事前測試應用程式的資料庫連接重試邏輯
- 準備監控腳本即時檢測連接問題

**應對策略**：
```bash
# 立即回滾（如果在 switchover-timeout 內）
# Blue/Green Deployment 支援快速回滾

# 檢查 Green 環境狀態
aws rds describe-db-instances \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBInstances[0].DBInstanceStatus'

# 如果需要，手動重啟應用程式或資料庫連接池
```

---

#### 4. 資料不一致或損壞

**症狀**：
- 切換後發現資料表行數不一致
- 關鍵資料遺失或損壞
- 應用程式報告業務邏輯錯誤

**預防措施**：
```bash
# 切換前創建最終快照
aws rds create-db-snapshot \
    --db-instance-identifier bingo-prd-backstage \
    --db-snapshot-identifier bingo-prd-backstage-before-resize-$(date +%Y%m%d) \
    --profile gemini-pro_ck \
    --region ap-east-1

# 切換後立即驗證
psql -h <endpoint> -U <username> -d <database-name>
```

```sql
-- 驗證資料表數量
SELECT count(*) FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema');

-- 驗證關鍵資料表行數
SELECT 'users' AS table_name, count(*) FROM users
UNION ALL
SELECT 'orders', count(*) FROM orders
UNION ALL
SELECT 'transactions', count(*) FROM transactions;

-- 檢查最近的寫入
SELECT max(created_at) FROM orders;
SELECT max(updated_at) FROM users;
```

**應對策略**：
1. **立即回滾到 Blue 環境**
2. 保留 Blue 環境 7 天作為備份
3. 從快照還原（如果 Blue 環境已刪除）
4. 調查原因，重新執行

---

#### 5. WAL 空間不足導致複製失敗

**症狀**：
- Green 環境創建過程中報告儲存空間不足
- 複製延遲不斷增加，無法追趕

**預防措施**：
```bash
# 監控 24-48 小時 WAL 生成量
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name TransactionLogsGeneration \
    --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage \
    --start-time $(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 3600 \
    --statistics Sum Maximum \
    --profile gemini-pro_ck \
    --region ap-east-1

# 確保至少有 24 小時峰值 WAL 量的額外空間
# 當前可用: 5024 - 1278 = 3746 GB
# 假設峰值 WAL: 100 GB/day
# 結論: 充足
```

**應對策略**：
- 如果空間不足，考慮暫時增加儲存空間或清理舊資料
- 選擇低峰時段執行，減少 WAL 生成
- 監控並在需要時調整計畫

---

### 回滾計畫

#### Blue/Green Deployment 回滾

**場景 1：切換前發現問題**
```bash
# 直接刪除 Blue/Green Deployment
aws rds delete-blue-green-deployment \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --delete-target yes \
    --profile gemini-pro_ck \
    --region ap-east-1

# Blue 環境（生產環境）不受影響，繼續運行
```

**場景 2：切換中或切換後發現問題（< 24 小時）**
```bash
# Blue/Green Deployment 支援快速回滾
# 但需要 AWS Support 協助

# 聯繫 AWS Support
aws support create-case \
    --subject "Urgent: Rollback Blue/Green Deployment" \
    --service-code "amazon-rds" \
    --category-code "general-inquiry" \
    --severity-code "urgent" \
    --communication-body "Need to rollback Blue/Green Deployment $DEPLOYMENT_ID. Details: [填入問題描述]" \
    --profile gemini-pro_ck

# 臨時解決方案：手動切換應用程式連接到舊的 Blue 環境
# 修改應用程式配置或 DNS 指向舊的 Blue 環境端點
```

**場景 3：切換後多日發現問題（Blue 環境仍存在）**
```bash
# 1. 獲取舊 Blue 環境 ID
OLD_BLUE_ID=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'BlueGreenDeployments[0].Source.DBInstanceIdentifier' \
    --output text)

# 2. 修改應用程式配置，指向舊 Blue 環境
# 或使用 Route 53 / Load Balancer 切換流量

# 3. 驗證舊 Blue 環境狀態
aws rds describe-db-instances \
    --db-instance-identifier "$OLD_BLUE_ID" \
    --profile gemini-pro_ck \
    --region ap-east-1

# 4. 如果舊 Blue 環境可用，直接切換
# 如果不可用，從快照還原
```

**場景 4：Blue 環境已刪除**
```bash
# 從快照還原
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier bingo-prd-backstage-restored \
    --db-snapshot-identifier bingo-prd-backstage-before-resize-20251028 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 等待還原完成
aws rds wait db-instance-available \
    --db-instance-identifier bingo-prd-backstage-restored \
    --profile gemini-pro_ck \
    --region ap-east-1

# 切換應用程式連接到還原的實例
```

---

### 災難恢復計畫

#### 完全失敗場景（極端情況）

**情況**：Blue 環境和 Green 環境都不可用，且沒有有效備份

**預防措施**（執行前必須做到）：
1. ✅ 創建最終快照：`bingo-prd-backstage-before-resize-20251028`
2. ✅ 驗證快照可還原
3. ✅ 啟用自動備份（保留期 7-35 天）
4. ✅ 考慮跨區域快照複製（如果預算允許）

**恢復步驟**：
```bash
# 1. 列出所有可用快照
aws rds describe-db-snapshots \
    --db-instance-identifier bingo-prd-backstage \
    --profile gemini-pro_ck \
    --region ap-east-1 \
    --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
    --output table

# 2. 從最新的有效快照還原
aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier bingo-prd-backstage-disaster-recovery \
    --db-snapshot-identifier <latest-valid-snapshot> \
    --db-instance-class <original-instance-class> \
    --storage-type gp3 \
    --profile gemini-pro_ck \
    --region ap-east-1

# 3. 等待還原完成（可能需要數小時）
aws rds wait db-instance-available \
    --db-instance-identifier bingo-prd-backstage-disaster-recovery \
    --profile gemini-pro_ck \
    --region ap-east-1

# 4. 驗證還原的資料
# 5. 切換應用程式連接
# 6. 通知所有利益相關者
# 7. 調查災難原因
```

---

## 總結

### 最佳推薦方案總結

對於 `bingo-prd-backstage` 資料庫（1278 GB 使用量，從 5024 GB 縮減到 2000 GB）：

1. **第一選擇：Blue/Green Deployment 儲存縮減**
   - 停機時間：< 1 分鐘
   - 執行時間：4-10 天
   - 成本：USD $150-350
   - **前提**：確認 ap-east-1 支援此功能

2. **第二選擇：PostgreSQL 邏輯複製**
   - 停機時間：< 5 分鐘
   - 執行時間：2-3 天
   - 成本：僅 RDS 成本
   - **前提**：團隊有 PostgreSQL 專業知識

3. **第三選擇：AWS DMS**
   - 停機時間：5-15 分鐘
   - 執行時間：2-3 天
   - 成本：USD $35-58 + RDS 成本
   - **適用**：希望使用 AWS 原生服務但需要更多控制

### 關鍵成功因素

1. ✅ **事前充分規劃**：至少提前 2 週開始準備
2. ✅ **詳細的檢查清單**：確保每個步驟都按順序執行
3. ✅ **持續監控**：在整個過程中密切監控各項指標
4. ✅ **完善的備份**：在執行前創建多個備份點
5. ✅ **明確的回滾計畫**：確保可以快速恢復到原狀態
6. ✅ **團隊協作**：確保所有相關團隊都了解計畫和時間表
7. ✅ **測試驗證**：切換後立即進行全面驗證

### 後續建議

1. **定期審查儲存使用**：每季度審查 RDS 儲存使用情況
2. **監控自動擴展**：設定 CloudWatch 告警，當儲存增長過快時通知
3. **資料歸檔策略**：考慮將歷史資料歸檔到 S3，進一步減少儲存需求
4. **效能最佳化**：定期 VACUUM 和 ANALYZE，保持資料庫健康
5. **容量規劃**：預測未來 1-2 年的儲存需求，提前規劃

---

## 參考資料

### AWS 官方文件
1. [Shrink storage volumes for your RDS databases](https://aws.amazon.com/blogs/database/shrink-storage-volumes-for-your-rds-databases-and-optimize-your-infrastructure-costs/)
2. [Amazon RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html)
3. [AWS Database Migration Service Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
4. [Decrease the storage size of an Amazon RDS DB Instance](https://repost.aws/knowledge-center/rds-db-storage-size)

### PostgreSQL 文件
1. [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
2. [pg_dump Documentation](https://www.postgresql.org/docs/current/app-pgdump.html)
3. [pg_restore Documentation](https://www.postgresql.org/docs/current/app-pgrestore.html)

### 技術文章
1. [How can we make pg_dump and pg_restore 5 times faster?](https://blog.peerdb.io/how-can-we-make-pgdump-and-pgrestore-5-times-faster)
2. [Zero Downtime Data Migration using PostgreSQL Logical Replication](https://dreamix.eu/insights/zero-downtime-data-migration-using-postgresql-logical-replication/)
3. [Migrating a Terabyte-Scale PostgreSQL Database](https://www.tigerdata.com/blog/migrating-a-terabyte-scale-postgresql-database-to-timescale-with-zero-downtime)

### Stack Overflow / AWS re:Post
1. [How to reduce storage (scale down) my AWS RDS instance?](https://stackoverflow.com/questions/36746475/how-to-reduce-storage-scale-down-my-aws-rds-instance)
2. [Reducing Allocated Storage for RDS Instance](https://repost.aws/questions/QU_kYC920lQGidl1zXCzCT9A/reducing-allocated-storage-for-rds-instance-to-optimize-costs-caused-by-storage-autoscaling)

---

## 附錄

### A. 術語表

| 術語 | 定義 |
|------|------|
| **Blue/Green Deployment** | AWS RDS 功能，創建一個獨立的暫存環境（Green），與生產環境（Blue）保持同步，用於測試變更或執行維護 |
| **WAL (Write-Ahead Log)** | PostgreSQL 的交易日誌，記錄所有資料變更，用於複製和恢復 |
| **Logical Replication** | PostgreSQL 功能，透過解碼 WAL 將資料變更複製到其他資料庫 |
| **CDC (Change Data Capture)** | 捕獲和追蹤資料變更的技術，用於即時複製或同步 |
| **IOPS** | Input/Output Operations Per Second，儲存效能指標 |
| **gp3** | AWS 第三代通用 SSD 儲存類型，提供基準效能和成本效益 |
| **Switchover** | 將流量從一個資料庫實例切換到另一個的過程 |
| **Replication Lag** | 複製延遲，指主資料庫和副本資料庫之間的時間差 |

### B. 常用命令速查

```bash
# 檢查 RDS 實例狀態
aws rds describe-db-instances \
    --db-instance-identifier <instance-id> \
    --profile <profile> \
    --region <region>

# 創建快照
aws rds create-db-snapshot \
    --db-instance-identifier <instance-id> \
    --db-snapshot-identifier <snapshot-id> \
    --profile <profile> \
    --region <region>

# 修改 RDS 實例
aws rds modify-db-instance \
    --db-instance-identifier <instance-id> \
    --max-allocated-storage <value> \
    --apply-immediately \
    --profile <profile> \
    --region <region>

# 創建 Blue/Green Deployment
aws rds create-blue-green-deployment \
    --blue-green-deployment-name <name> \
    --source-arn <source-arn> \
    --target-allocated-storage <value> \
    --profile <profile> \
    --region <region>

# 檢查 Blue/Green Deployment 狀態
aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier <deployment-id> \
    --profile <profile> \
    --region <region>

# 執行 Blue/Green 切換
aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier <deployment-id> \
    --switchover-timeout <seconds> \
    --profile <profile> \
    --region <region>

# 查詢 CloudWatch 指標
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name <metric-name> \
    --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
    --start-time <start-time> \
    --end-time <end-time> \
    --period <seconds> \
    --statistics <statistic> \
    --profile <profile> \
    --region <region>
```

### C. PostgreSQL 驗證查詢

```sql
-- 資料庫大小
SELECT pg_size_pretty(pg_database_size(current_database()));

-- 所有資料表大小
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
       pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 資料表統計
SELECT schemaname, tablename, n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;

-- 檢查連接數
SELECT count(*), state
FROM pg_stat_activity
GROUP BY state;

-- 檢查長時間運行的查詢
SELECT pid, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

-- 檢查複製延遲（邏輯複製）
SELECT slot_name,
       plugin,
       slot_type,
       database,
       active,
       restart_lsn,
       confirmed_flush_lsn
FROM pg_replication_slots;

-- 檢查 WAL 設定
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;

-- 檢查資料庫年齡（防止 transaction ID wraparound）
SELECT datname, age(datfrozenxid), datfrozenxid
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

---

**報告版本**：1.0
**創建日期**：2025-10-28
**作者**：Claude (Anthropic)
**目標資料庫**：bingo-prd-backstage (PostgreSQL 14.15, ap-east-1)
**報告目的**：AWS RDS 儲存空間縮減方案評估與執行計畫

---

*此報告基於 2025 年 10 月的 AWS 功能和最佳實踐。AWS 服務持續更新，執行前請確認最新的官方文件和功能可用性。*

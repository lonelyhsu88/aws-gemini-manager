# 網路與 GoldenGate 詳細設定指南

**基於**: PostgreSQL Migration SOP v1.0
**整合至**: RDS_TO_OCI_MIGRATION_PLAN.md
**更新日期**: 2026-01-20

---

## 📡 網路架構與連線方案

### 架構選擇: Equinix Fabric Cloud Router

本專案採用 **Equinix Fabric Cloud Router (FCR)** 作為 AWS 與 OCI 之間的私有連線方案，提供高頻寬、低延遲的網路環境。

#### 架構優勢

| 優勢 | 說明 |
|------|------|
| **私有連線** | 不經過公網，安全性高 |
| **低延遲** | Hong Kong ↔ Tokyo ~50ms |
| **可擴展** | 支援 1G → 10G 線上升級 |
| **靈活性** | 按月計費，完成後即可終止 |
| **穩定性** | SLA 99.99% 可用性 |

---

## 🌐 網路拓撲圖

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Equinix Fabric                                   │
│                                                                             │
│     Hong Kong (HK1)                              Tokyo (TY2)                │
│    ┌─────────────┐        Remote Virtual        ┌─────────────┐            │
│    │     FCR     │        Connection            │     FCR     │            │
│    │  (ASN 65000)│◄────────────────────────────►│  (ASN 65001)│            │
│    └──────┬──────┘         ~50ms latency        └──────┬──────┘            │
│           │                                            │                   │
└───────────┼────────────────────────────────────────────┼───────────────────┘
            │                                            │
            ▼                                            ▼
┌───────────────────────┐                   ┌───────────────────────┐
│    AWS ap-east-1      │                   │   OCI ap-tokyo-1      │
│       (香港)          │                   │       (東京)          │
│                       │                   │                       │
│  ┌─────────────────┐  │                   │  ┌─────────────────┐  │
│  │      VPC        │  │                   │  │       VCN       │  │
│  │ 172.16.0.0/16   │  │                   │  │  10.1.0.0/16    │  │
│  │                 │  │                   │  │                 │  │
│  │  ┌───────────┐  │  │     7.8TB CDC     │  │  ┌───────────┐  │  │
│  │  │    RDS    │  │──┼──────────────────►│  │  │GoldenGate │  │  │
│  │  │ PostgreSQL│  │  │                   │  │  │ OCI PgSQL │  │  │
│  │  │   7.8TB   │  │  │                   │  │  └───────────┘  │  │
│  │  └───────────┘  │  │                   │  │                 │  │
│  └─────────────────┘  │                   │  └─────────────────┘  │
└───────────────────────┘                   └───────────────────────┘
```

### 優化架構: 單一 FCR (Tokyo)

**成本優化方案**: 使用單一 FCR 於 Tokyo，減少複雜度與成本

```
                      Equinix Fabric
                    +-------------+
                    | FCR (Tokyo) |
                    |  ASN: 65000 |
                    +------+------+
              +------------+------------+
              |                        |
       Remote VC (HK)            Local VC
       1G or 10G                 1G or 10G
              |                        |
              v                        v
    +-------------------+   +-------------------+
    |  AWS ap-east-1    |   |  OCI ap-tokyo-1   |
    |  (Hong Kong)      |   |  (Tokyo)          |
    |  172.16.0.0/16    |   |  10.1.0.0/16      |
    +-------------------+   +-------------------+
```

**成本節省**: 單一 FCR 可節省 ~$300-500/月

---

## 🔧 網路配置詳細步驟

### CIDR 規劃

| 雲端平台 | 區域 | 位置 | CIDR | 用途 |
|---------|------|------|------|------|
| **AWS** | ap-east-1 | Hong Kong | 172.16.0.0/16 | 現有 RDS VPC |
| **OCI** | ap-tokyo-1 | Tokyo | 10.1.0.0/16 | 新建 OCI VCN |

**BGP 對等 IP 分配**:

| 連線 | 本地 IP | 對端 IP | 本地 ASN | 對端 ASN |
|------|---------|---------|---------|---------|
| FCR Tokyo ↔ OCI | 192.168.100.1/30 | 192.168.100.2/30 | 65001 | 31898 (OCI) |
| FCR HK ↔ AWS | 192.168.200.1/30 | 192.168.200.2/30 | 65000 | 7224 (AWS) |
| FCR HK ↔ FCR Tokyo | 192.168.50.1/30 | 192.168.50.2/30 | 65000 | 65001 |

---

## 📋 Phase 1: OCI 網路配置 (Tokyo)

**預估時間**: 1-2 小時

### Step 1: 建立 VCN

```bash
# 使用 OCI CLI 建立 VCN
oci network vcn create \
  --compartment-id <compartment-ocid> \
  --display-name vcn-migration \
  --cidr-block 10.1.0.0/16 \
  --dns-label migration \
  --region ap-tokyo-1
```

**或使用 Terraform**:
```hcl
resource "oci_core_vcn" "migration_vcn" {
  compartment_id = var.compartment_id
  cidr_block     = "10.1.0.0/16"
  display_name   = "vcn-migration"
  dns_label      = "migration"
}
```

### Step 2: 建立 Dynamic Routing Gateway (DRG)

```bash
# 建立 DRG
oci network drg create \
  --compartment-id <compartment-ocid> \
  --display-name drg-equinix \
  --region ap-tokyo-1

# 將 DRG 連接到 VCN
oci network drg-attachment create \
  --drg-id <drg-ocid> \
  --vcn-id <vcn-ocid> \
  --display-name drg-vcn-attachment
```

### Step 3: 建立 FastConnect

```bash
# 建立 FastConnect Private Virtual Circuit
oci network virtual-circuit create \
  --compartment-id <compartment-ocid> \
  --type PRIVATE \
  --bandwidth-shape-name "1 Gbps" \
  --display-name fc-equinix-tokyo \
  --gateway-id <drg-ocid> \
  --provider-name "Equinix" \
  --provider-service-name "Fabric" \
  --customer-bgp-asn 65001 \
  --region ap-tokyo-1
```

**關鍵參數**:
| 參數 | 值 |
|------|-----|
| Connection Type | FastConnect Partner |
| Partner | Equinix: Fabric |
| Bandwidth | 1 Gbps (或 10 Gbps) |
| Customer BGP ASN | 65001 |
| Customer BGP IP | 192.168.100.1/30 |
| Oracle BGP IP | 192.168.100.2/30 |

⚠️ **重要**: 記錄建立後的 OCID (ocid1.virtualcircuit.oc1.ap-tokyo-1...)

### Step 4: 更新路由表

```bash
# 新增路由規則指向 AWS VPC
oci network route-table update \
  --rt-id <route-table-ocid> \
  --route-rules '[
    {
      "destination": "172.16.0.0/16",
      "destinationType": "CIDR_BLOCK",
      "networkEntityId": "<drg-ocid>"
    }
  ]'
```

### Step 5: 更新安全列表 (Security List)

**Ingress Rules**:
```bash
# 允許來自 AWS VPC 的流量
oci network security-list update \
  --security-list-id <security-list-ocid> \
  --ingress-security-rules '[
    {
      "source": "172.16.0.0/16",
      "protocol": "6",
      "isStateless": false,
      "tcpOptions": {
        "destinationPortRange": {
          "min": 5432,
          "max": 5432
        }
      }
    }
  ]'
```

**Egress Rules**:
```bash
# 允許往 AWS VPC 的流量
oci network security-list update \
  --security-list-id <security-list-ocid> \
  --egress-security-rules '[
    {
      "destination": "172.16.0.0/16",
      "protocol": "6",
      "isStateless": false
    }
  ]'
```

---

## 🌐 Phase 2: Equinix Fabric 配置

**預估時間**: 1-2 小時

### Step 1: 建立 Tokyo FCR

**Equinix Portal → Fabric → Cloud Routers → Create Cloud Router**

| 設定 | 值 |
|------|-----|
| Location | Tokyo (TY2) |
| Name | fcr-tokyo |
| Package | Standard (或 Advanced for 10G) |
| ASN | 65001 |
| BGP Peering | Enabled |

### Step 2: 建立 Hong Kong FCR

| 設定 | 值 |
|------|-----|
| Location | Hong Kong (HK1) |
| Name | fcr-hongkong |
| Package | Standard (或 Advanced for 10G) |
| ASN | 65000 |
| BGP Peering | Enabled |

**成本考量**: 可選擇只建立 Tokyo FCR (單一 FCR 架構)

### Step 3: 連接 Tokyo FCR 到 OCI

**Equinix Portal → Connections → Create Connection**

| 設定 | 值 |
|------|-----|
| OCID | (貼上 FastConnect OCID) |
| Origin Asset Type | Cloud Router |
| Select Cloud Router | fcr-tokyo |
| Connection Name | conn-oci-tokyo |
| Bandwidth | 1 Gbps (或 10 Gbps) |
| Your IP (BGP) | 192.168.100.1/30 |
| Peer IP (BGP) | 192.168.100.2/30 |
| Peer ASN | 31898 (OCI fixed) |

### Step 4: 連接 Hong Kong FCR 到 AWS

**AWS Console → Direct Connect → Accept Equinix Connection**

| 設定 | 值 |
|------|-----|
| AWS Account ID | (您的 12 位數帳號 ID) |
| Origin Asset Type | Cloud Router |
| Select Cloud Router | fcr-hongkong |
| Connection Name | conn-aws-hk |
| Bandwidth | 1 Gbps (或 10 Gbps) |
| Destination Metro | Hong Kong |

### Step 5: 建立 HK-Tokyo Backbone

**Equinix Portal → Remote Connections → Create**

| 設定 | 值 |
|------|-----|
| A-End | fcr-hongkong |
| Z-End | fcr-tokyo |
| Connection Name | hk-tokyo-backbone |
| Bandwidth | 1 Gbps (或 10 Gbps) |

**BGP Routing (HK side)**:
| 設定 | 值 |
|------|-----|
| Your IP | 192.168.50.1/30 |
| Peer IP | 192.168.50.2/30 |
| Peer ASN | 65001 |

**BGP Routing (Tokyo side)**:
| 設定 | 值 |
|------|-----|
| Your IP | 192.168.50.2/30 |
| Peer IP | 192.168.50.1/30 |
| Peer ASN | 65000 |

---

## ☁️ Phase 3: AWS 配置 (Hong Kong)

**預估時間**: 30-60 分鐘

### Step 1: 接受 Direct Connect

```bash
# AWS Console → Direct Connect → Connections
# 找到 Equinix connection → Accept
```

### Step 2: 建立 Virtual Private Gateway

```bash
aws --profile gemini-pro_ck ec2 create-vpn-gateway \
  --type ipsec.1 \
  --amazon-side-asn 64512 \
  --region ap-east-1

# 連接到 VPC
aws --profile gemini-pro_ck ec2 attach-vpn-gateway \
  --vpn-gateway-id vgw-xxx \
  --vpc-id vpc-xxx \
  --region ap-east-1
```

**或使用 Terraform**:
```hcl
resource "aws_vpn_gateway" "vgw_equinix" {
  vpc_id          = aws_vpc.main.id
  amazon_side_asn = 64512

  tags = {
    Name = "vgw-equinix"
  }
}
```

### Step 3: 建立 Private Virtual Interface

```bash
aws --profile gemini-pro_ck directconnect create-private-virtual-interface \
  --connection-id dxcon-xxx \
  --new-private-virtual-interface \
    virtualInterfaceName=vif-oci,\
    vlan=100,\
    asn=65000,\
    customerAddress=192.168.200.1/30,\
    amazonAddress=192.168.200.2/30,\
    virtualGatewayId=vgw-xxx
```

### Step 4: 配置 Equinix AWS BGP

**返回 Equinix Portal → Connections → conn-aws-hk → Routing Details**

| 設定 | 值 |
|------|-----|
| Your IP | 192.168.200.1/30 |
| Peer IP | 192.168.200.2/30 |
| Peer ASN | 7224 (或 AWS 顯示的 ASN) |

### Step 5: 更新路由表

```bash
# 新增路由規則指向 OCI VCN
aws --profile gemini-pro_ck ec2 create-route \
  --route-table-id rtb-xxx \
  --destination-cidr-block 10.1.0.0/16 \
  --gateway-id vgw-xxx \
  --region ap-east-1
```

### Step 6: 更新 RDS Security Group

```bash
# 允許來自 OCI VCN 的連線
aws --profile gemini-pro_ck ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 5432 \
  --cidr 10.1.0.0/16 \
  --region ap-east-1
```

---

## 🔄 Phase 4: Oracle GoldenGate 配置

**預估時間**: 2-4 小時

### 4.1 AWS RDS 來源配置

#### Step 1: 修改參數組

```bash
# 建立新的參數組用於 GoldenGate
aws --profile gemini-pro_ck rds create-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --db-parameter-group-family postgres14 \
  --description "PostgreSQL 14 parameters for GoldenGate migration" \
  --region ap-east-1

# 啟用 logical replication
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region ap-east-1

# 增加 replication slots
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --parameters "ParameterName=max_replication_slots,ParameterValue=10,ApplyMethod=pending-reboot" \
  --region ap-east-1

# 增加 wal senders
aws --profile gemini-pro_ck rds modify-db-parameter-group \
  --db-parameter-group-name postgresql14-goldengate \
  --parameters "ParameterName=max_wal_senders,ParameterValue=10,ApplyMethod=pending-reboot" \
  --region ap-east-1

# 套用參數組到實例
aws --profile gemini-pro_ck rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --db-parameter-group-name postgresql14-goldengate \
  --apply-immediately \
  --region ap-east-1

# 重啟實例套用變更
aws --profile gemini-pro_ck rds reboot-db-instance \
  --db-instance-identifier bingo-prd \
  --region ap-east-1
```

⚠️ **重要**: 參數組變更需要重啟 RDS 實例才能生效

#### Step 2: 建立遷移使用者

```sql
-- 連線到 RDS
psql -h bingo-prd.<rds-endpoint> -U postgres -d postgres

-- 建立 GoldenGate 遷移使用者
CREATE USER gg_migration WITH REPLICATION LOGIN PASSWORD 'SecurePassword123!';

-- 授予所有資料庫的 SELECT 權限
\c bingo_prd
GRANT SELECT ON ALL TABLES IN SCHEMA public TO gg_migration;
GRANT USAGE ON SCHEMA public TO gg_migration;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO gg_migration;

-- AWS RDS 專用: 授予複製角色
GRANT rds_replication TO gg_migration;

-- 驗證權限
\du gg_migration
```

---

### 4.2 OCI GoldenGate 部署

#### Step 1: 建立 GoldenGate 部署

**OCI Console → GoldenGate → Deployments → Create Deployment**

| 設定 | 值 | 說明 |
|------|-----|------|
| Name | goldengate-migration | 部署名稱 |
| Technology | PostgreSQL | 資料庫類型 |
| License Type | BYOL 或 License Included | 授權模式 |
| OCPU | 4+ | **建議 4-8 OCPU** (7,974 GB 資料) |
| Storage | 500 GB | Trail 檔案儲存 |
| Auto Scaling | Enabled | 自動擴展 |
| Admin Username | oggadmin | 管理員帳號 |
| Admin Password | (強密碼) | 至少 12 字元 |
| VCN | vcn-migration | 與 OCI PostgreSQL 相同 VCN |
| Subnet | Private Subnet | 私有子網路 |

**Terraform 配置**:
```hcl
resource "oci_golden_gate_deployment" "migration_deployment" {
  compartment_id          = var.compartment_id
  display_name            = "goldengate-migration"
  deployment_type         = "OGG"
  subnet_id               = oci_core_subnet.private_subnet.id
  license_model           = "BYOL"
  cpu_core_count          = 4
  is_auto_scaling_enabled = true
  freeform_tags = {
    "Project" = "RDS-to-OCI-Migration"
  }

  ogg_data {
    deployment_name = "goldengate-migration"
    admin_username  = "oggadmin"
    admin_password  = var.gg_admin_password
  }
}
```

#### Step 2: 建立來源連線 (AWS RDS)

**GoldenGate Console → Connections → Create Connection**

| 設定 | 值 |
|------|-----|
| Connection Type | PostgreSQL Server |
| Name | conn-rds-source |
| Description | AWS RDS PostgreSQL Source |
| Technology | PostgreSQL |
| Host | bingo-prd.<rds-endpoint> |
| Port | 5432 |
| Database | bingo_prd |
| Username | gg_migration |
| Password | (遷移使用者密碼) |
| Security Protocol | Require (SSL) |
| Network | Dedicated endpoint |

**測試連線**:
```bash
# 在 GoldenGate 部署中測試連線
Test Connection → Should return "Success"
```

#### Step 3: 建立目標連線 (OCI PostgreSQL)

| 設定 | 值 |
|------|-----|
| Connection Type | OCI Database with PostgreSQL |
| Name | conn-oci-target |
| Description | OCI PostgreSQL Target |
| Database System | (選擇您的 OCI PostgreSQL DB System) |
| Database | bingo_prd |
| Username | admin |
| Password | (OCI PostgreSQL admin 密碼) |
| Security Protocol | Require (SSL) |

---

### 4.3 初始載入 (Initial Load)

#### Extract 配置 (IL - Initial Load)

**GoldenGate Console → Extracts → Create Extract**

| 設定 | 值 |
|------|-----|
| Extract Type | Initial Load |
| Name | EXT_IL_BINGO |
| Description | Initial Load Extract for bingo_prd |
| Source Connection | conn-rds-source |
| Trail Name | il |
| Begin | Now |

**參數檔案** (`EXT_IL_BINGO.prm`):
```properties
EXTRACT EXT_IL_BINGO
SOURCEDB bingo-prd.<rds-endpoint>:5432, USERIDALIAS rds_source
EXTTRAIL ./dirdat/il
INITIALLOADOPTIONS USESNAPSHOT, NOUSEDEFAULTS
DBOPTIONS CONNECTIONRETRYCOUNT 10, CONNECTIONRETRYWAIT 30
FETCHOPTIONS USESNAPSHOT, FETCHPKUPDATECOLS
TABLE public.*;
```

#### Replicat 配置 (IL)

**GoldenGate Console → Replicats → Create Replicat**

| 設定 | 值 |
|------|-----|
| Replicat Type | Nonintegrated |
| Name | REP_IL_BINGO |
| Description | Initial Load Replicat for bingo_prd |
| Target Connection | conn-oci-target |
| Trail Name | il |
| Checkpoint Table | public.gg_checkpoint |

**參數檔案** (`REP_IL_BINGO.prm`):
```properties
REPLICAT REP_IL_BINGO
TARGETDB <oci-pg-endpoint>:5432, USERIDALIAS oci_target
DISCARDFILE ./dirrpt/rep_il_bingo.dsc, PURGE
ASSUMETARGETDEFS
MAP public.*, TARGET public.*;
DBOPTIONS DEFERREFCONST
BATCHSQL BATCHSIZE 1000
```

#### 啟動初始載入

```bash
# GGSCI 命令
GGSCI> START EXTRACT EXT_IL_BINGO
GGSCI> START REPLICAT REP_IL_BINGO

# 監控進度
GGSCI> INFO EXTRACT EXT_IL_BINGO, DETAIL
GGSCI> STATS EXTRACT EXT_IL_BINGO, LATEST
GGSCI> INFO REPLICAT REP_IL_BINGO, DETAIL
```

**預期時間**:
- 1 Gbps: ~24-32 小時 (7,974 GB)
- 10 Gbps: ~2-4 小時 (7,974 GB)

✓ **記錄 LSN**: 初始載入完成後，記錄 LSN (Log Sequence Number) 用於 CDC

---

### 4.4 持續資料捕獲 (CDC - Change Data Capture)

#### Extract 配置 (CDC)

**GoldenGate Console → Extracts → Create Extract**

| 設定 | 值 |
|------|-----|
| Extract Type | Change Data Capture |
| Name | EXT_CDC_BINGO |
| Description | CDC Extract for bingo_prd |
| Source Connection | conn-rds-source |
| Trail Name | cd |
| Begin | At CSN → (輸入 Initial Load 的 LSN) |

**參數檔案** (`EXT_CDC_BINGO.prm`):
```properties
EXTRACT EXT_CDC_BINGO
SOURCEDB bingo-prd.<rds-endpoint>:5432, USERIDALIAS rds_source
EXTTRAIL ./dirdat/cd
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT
GETUPDATEBEFORES
TRANLOGOPTIONS FILTERTABLE public.*
TRANLOGOPTIONS EXCLUDEUSER gg_migration
TRANLOGOPTIONS EXCLUDEUSER postgres
TABLE public.*;
```

#### Replicat 配置 (CDC)

**GoldenGate Console → Replicats → Create Replicat**

| 設定 | 值 |
|------|-----|
| Replicat Type | Nonintegrated |
| Name | REP_CDC_BINGO |
| Description | CDC Replicat for bingo_prd |
| Target Connection | conn-oci-target |
| Trail Name | cd |
| Checkpoint Table | public.gg_checkpoint |

**參數檔案** (`REP_CDC_BINGO.prm`):
```properties
REPLICAT REP_CDC_BINGO
TARGETDB <oci-pg-endpoint>:5432, USERIDALIAS oci_target
DISCARDFILE ./dirrpt/rep_cdc_bingo.dsc, PURGE
ASSUMETARGETDEFS
MAP public.*, TARGET public.*;
REPERROR DEFAULT, DISCARD
DBOPTIONS DEFERREFCONST
BATCHSQL BATCHSIZE 1000
GROUPTRANSOPS 10000
```

#### 啟動 CDC

```bash
# GGSCI 命令
GGSCI> START EXTRACT EXT_CDC_BINGO
GGSCI> START REPLICAT REP_CDC_BINGO

# 監控 Lag
GGSCI> LAG EXTRACT EXT_CDC_BINGO
GGSCI> LAG REPLICAT REP_CDC_BINGO

# 檢查錯誤
GGSCI> VIEW REPORT EXT_CDC_BINGO
GGSCI> VIEW REPORT REP_CDC_BINGO
```

**監控重點**:
- **Lag < 5 秒**: CDC 同步正常
- **無 ABENDED 狀態**: 沒有異常中止
- **Trail 檔案清理**: 定期清理舊的 trail 檔案

---

## 💰 成本分析與頻寬選擇

### 方案 A: 1 Gbps (經濟型)

**適合場景**: 預算優先、時間彈性

#### 月度成本明細

| 項目 | 月費 (USD) | 說明 |
|------|-----------|------|
| Equinix FCR Tokyo (Single) | $300 | 單一 FCR 優化架構 |
| AWS VXC 1Gbps (Remote to HK) | $600 | AWS Direct Connect 1G |
| OCI VXC 1Gbps (Local) | $350 | OCI FastConnect 1G Local |
| **月度總計** | **$1,250** | |
| AWS Data Transfer (7,974 GB) | $319 | 7,974 GB × $0.04/GB |
| **第一個月總成本** | **$1,569** | |

#### 時間估算

| 指標 | 時間 |
|------|------|
| 7,974 GB 傳輸 (理論) | ~18 小時 |
| 7,974 GB 傳輸 (實際) | **24-32 小時** |
| 總遷移時間 | **2-4 天** |

---

### 方案 B: 10 Gbps (快速型)

**適合場景**: 停機時間敏感、業務關鍵

#### 月度成本明細

| 項目 | 月費 (USD) | 說明 |
|------|-----------|------|
| Equinix FCR Tokyo (Advanced) | $500 | Advanced package for 10G |
| AWS VXC 10Gbps (Remote to HK) | $3,000 | AWS Direct Connect 10G |
| OCI VXC 10Gbps (Local) | $1,500 | OCI FastConnect 10G Local |
| **月度總計** | **$5,000** | |
| AWS Data Transfer (7,974 GB) | $319 | 7,974 GB × $0.04/GB |
| **第一個月總成本** | **$5,319** | |

#### 時間估算

| 指標 | 時間 |
|------|------|
| 7,974 GB 傳輸 (理論) | ~1.8 小時 |
| 7,974 GB 傳輸 (實際) | **2-4 小時** |
| 總遷移時間 | **< 1 天** |

---

### 成本效益分析

| 指標 | 1 Gbps | 10 Gbps | 差異 |
|------|--------|---------|------|
| 月度成本 | $1,569 | $5,319 | +$3,750 |
| 遷移時間 | 2-4 天 | < 1 天 | 節省 1-3 天 |
| 每天成本 | ~$390-$785 | ~$5,319 | - |
| 每節省一天的成本 | - | ~$1,250-$3,750/天 | - |

**決策建議**:

1. **選擇 1 Gbps 如果**:
   - 可以接受 2-4 天遷移時間
   - 預算有限
   - 非業務高峰期執行

2. **選擇 10 Gbps 如果**:
   - 需要最小化停機時間
   - 業務關鍵系統
   - 無法接受長時間切換窗口

3. **混合策略**:
   - 測試/開發環境使用 1 Gbps
   - 生產環境升級到 10 Gbps
   - Equinix 支援線上頻寬升級

---

### 實際吞吐量考量

**網路頻寬並非唯一瓶頸**，需考慮以下因素:

| 瓶頸 | 影響 | 緩解措施 |
|------|------|---------|
| **RDS IOPS** | 讀取速度受限於儲存層 | 使用 Provisioned IOPS (12000+) |
| **GoldenGate Extract CPU** | 處理速度受限 | 增加 GoldenGate OCPU (4-8) |
| **OCI PostgreSQL Write** | 寫入速度受限 | 優化 batch size, BATCHSQL |
| **網路延遲 (~50ms)** | 影響小型交易 | 批次操作, GROUPTRANSOPS |
| **WAL 生成速度** | CDC lag | 監控 `wal_keep_segments` |

**優化建議**:
```properties
# GoldenGate Replicat 效能調校
BATCHSQL BATCHSIZE 1000
GROUPTRANSOPS 10000
MAP public.*, TARGET public.*, THREAD (4);
```

---

## 🔍 監控與驗證

### GoldenGate 監控腳本

```bash
#!/bin/bash
# gg-monitor.sh - GoldenGate 監控腳本

GGSCI_CMD="ggsci"

echo "=== GoldenGate 狀態監控 ==="
echo "時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Extract 狀態
echo "--- Extract 狀態 ---"
$GGSCI_CMD << EOF
INFO EXTRACT *
LAG EXTRACT *
STATS EXTRACT *, LATEST
EXIT
EOF

echo ""

# Replicat 狀態
echo "--- Replicat 狀態 ---"
$GGSCI_CMD << EOF
INFO REPLICAT *
LAG REPLICAT *
STATS REPLICAT *, LATEST
EXIT
EOF

echo ""

# 檢查錯誤
echo "--- 錯誤檢查 ---"
if grep -q "ERROR" /path/to/gg/ggserr.log; then
  echo "⚠️ 發現錯誤，請檢查 ggserr.log"
  tail -20 /path/to/gg/ggserr.log
else
  echo "✅ 無錯誤"
fi
```

### 連線測試腳本

```bash
#!/bin/bash
# test-connectivity.sh - 網路連線測試

echo "=== 網路連線測試 ==="

# 測試 RDS 連線
echo "測試 AWS RDS..."
pg_isready -h bingo-prd.<rds-endpoint> -p 5432 -U gg_migration
if [ $? -eq 0 ]; then
  echo "✅ RDS 連線正常"
else
  echo "❌ RDS 連線失敗"
fi

# 測試 OCI PostgreSQL 連線
echo "測試 OCI PostgreSQL..."
pg_isready -h <oci-pg-endpoint> -p 5432 -U admin
if [ $? -eq 0 ]; then
  echo "✅ OCI PostgreSQL 連線正常"
else
  echo "❌ OCI PostgreSQL 連線失敗"
fi

# 測試網路延遲
echo "測試網路延遲..."
LATENCY=$(ping -c 5 <oci-pg-endpoint> | tail -1 | awk -F '/' '{print $5}')
echo "平均延遲: ${LATENCY}ms"

if (( $(echo "$LATENCY < 100" | bc -l) )); then
  echo "✅ 延遲正常 (< 100ms)"
else
  echo "⚠️ 延遲偏高 (> 100ms)"
fi
```

---

## 📚 附錄: BGP 配置快速參考

### 完整 BGP 配置表

| 連線 | 本地 IP | 對端 IP | 本地 ASN | 對端 ASN | 用途 |
|------|---------|---------|---------|---------|------|
| **FCR Tokyo ↔ OCI** | 192.168.100.1/30 | 192.168.100.2/30 | 65001 | 31898 | OCI FastConnect |
| **FCR HK ↔ AWS** | 192.168.200.1/30 | 192.168.200.2/30 | 65000 | 7224 | AWS Direct Connect |
| **FCR HK ↔ FCR Tokyo** | 192.168.50.1/30 | 192.168.50.2/30 | 65000 | 65001 | Equinix Backbone |

### BGP 驗證命令

```bash
# Equinix FCR 檢查
show bgp summary
show bgp neighbors
show ip route

# AWS 檢查
aws --profile gemini-pro_ck directconnect describe-virtual-interfaces
aws --profile gemini-pro_ck ec2 describe-vpn-gateways

# OCI 檢查
oci network virtual-circuit get --virtual-circuit-id <vc-ocid>
oci network drg-attachment list --drg-id <drg-ocid>
```

---

## 🎯 關鍵聯絡人

### Equinix 支援
- **Email**: cs@equinix.com
- **Portal**: https://fabric.equinix.com
- **支援時間**: 24/7

### AWS 支援
- **Console**: AWS Support Center
- **文檔**: https://docs.aws.amazon.com/directconnect/
- **票務**: 透過 AWS Console 開立支援工單

### OCI 支援
- **Console**: OCI Support → Create Support Request
- **文檔**: https://docs.oracle.com/en-us/iaas/Content/Network/home.htm
- **票務**: Support Request Portal

---

**文檔維護**
- **版本**: 1.0
- **負責人**: DevOps Team
- **審查日期**: 2026-01-20
- **下次審查**: 遷移執行後

---

*本文檔整合自 PostgreSQL Migration SOP 與 RDS to OCI Migration Plan*

# RDS 實例健康度詳細報告

**分析日期**: 2025-10-28
**分析期間**: 2025-10-21 至 2025-10-28 (7天)
**AWS Region**: ap-east-1 (Hong Kong)
**AWS Profile**: gemini-pro_ck

---

## 目錄

1. [總體概覽](#總體概覽)
2. [實例詳細分析](#實例詳細分析)
3. [效能指標分析](#效能指標分析)
4. [安全性評估](#安全性評估)
5. [儲存健康度](#儲存健康度)
6. [成本分析](#成本分析)
7. [建議與行動計劃](#建議與行動計劃)

---

## 總體概覽

### 實例清單

| 編號 | 實例名稱 | 實例類型 | 儲存空間 | 狀態 | 環境 | 健康度 |
|------|----------|----------|----------|------|------|--------|
| 1 | bingo-prd | db.m6g.large | 2750 GB | Available | Production | 🟢 健康 |
| 2 | bingo-prd-backstage | db.m6g.large | 5024 GB | Available | Production | 🟢 健康 |
| 3 | bingo-prd-backstage-replica1 | db.t4g.medium | 1465 GB | Available | Production | 🟢 健康 |
| 4 | bingo-prd-loyalty | db.t4g.medium | 200 GB | Available | Production | 🟢 健康 |
| 5 | bingo-prd-replica1 | db.m6g.large | 2662 GB | Available | Production | 🟢 健康 |
| 6 | bingo-stress | db.t4g.medium | 2750 GB | Available | Stress Test | 🟡 注意 |
| 7 | bingo-stress-backstage | db.t4g.medium | 5024 GB | Available | Stress Test | 🟡 注意 |
| 8 | bingo-stress-loyalty | db.t4g.medium | 200 GB | Available | Stress Test | 🟢 健康 |
| 9 | pgsqlrel | db.t3.small | 40 GB | Available | Development | 🔴 警告 |
| 10 | pgsqlrel-backstage | db.t3.micro | 40 GB | Available | Development | 🔴 警告 |

### 健康度評級說明
- 🟢 **健康**: 所有指標正常，無需立即處理
- 🟡 **注意**: 部分指標需要關注，建議優化
- 🔴 **警告**: 存在嚴重問題，需要立即處理

---

## 實例詳細分析

### 1. bingo-prd 🟢

#### 基本配置
- **實例類型**: db.m6g.large (2 vCPU, 8 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 2750 GB
  - 最大自動擴展: 5000 GB
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-12-18

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 16.22% | 36.21% | 🟢 良好 |
| 資料庫連線數 | 145 | 162 | 🟢 正常 |
| 可用記憶體 | 4.21 GB | - | 🟢 充足 |
| 可用儲存空間 | 490.12 GB | - | 🟢 充足 (18% 使用率) |
| Read IOPS | 178 | 7,422 | 🟡 配置過高 |
| Write IOPS | 275 | 5,902 | 🟡 配置過高 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 453 IOPS (Read + Write)
- 使用率: 3.8%
- **建議**: 降至 3,000-5,000 IOPS

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用 (7天保留)
- ⚠️ 公開訪問已啟用 (需檢查是否必要)
- ❌ IAM 資料庫認證未啟用
- ❌ Multi-AZ 未啟用
- ❌ Enhanced Monitoring 未啟用
- ⚠️ 自動次要版本升級已停用

#### 備份配置
- 備份保留期: 3 天
- 備份窗口: 21:00-22:00 UTC
- 維護窗口: Thursday 02:00-02:30 UTC
- 最後可恢復時間: 2025-10-28 08:54:07

#### Read Replica
- 有一個 Read Replica: bingo-prd-replica1
- Replication 狀態: Normal

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 5,000 (節省 ~$800/月)
2. 🟡 **建議處理**: 考慮啟用 Multi-AZ 以提高可用性
3. 🟡 **優化**: 啟用 Enhanced Monitoring
4. 🟢 **考慮**: 購買 Reserved Instance (節省 40-60%)

---

### 2. bingo-prd-backstage 🟢

#### 基本配置
- **實例類型**: db.m6g.large (2 vCPU, 8 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 5024 GB
  - 最大自動擴展: 10,000 GB
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-09-22

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 5.40% | 11.24% | 🟢 優秀 |
| 資料庫連線數 | 11 | 12 | 🟢 正常 |
| 可用記憶體 | 4.36 GB | - | 🟢 充足 |
| 可用儲存空間 | 3049.18 GB | - | 🟢 充足 (39% 使用率) |
| Read IOPS | 74 | 3,341 | 🟡 嚴重過度配置 |
| Write IOPS | 47 | 4,354 | 🟡 嚴重過度配置 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 121 IOPS (Read + Write)
- 使用率: 1.0%
- **建議**: 降至 3,000 IOPS (基準配置)

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用 (465天保留 - Advanced模式)
- ⚠️ 公開訪問已啟用
- ❌ IAM 資料庫認證未啟用
- ❌ Multi-AZ 未啟用
- ❌ Enhanced Monitoring 未啟用

#### 備份配置
- 備份保留期: 3 天
- 備份窗口: 20:00-21:00 UTC
- 維護窗口: Wednesday 07:50-08:20 UTC

#### Read Replica
- 有一個 Read Replica: bingo-prd-backstage-replica1

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 3,000 (節省 ~$1,035/月)
2. 🟡 **優化**: 啟用 Enhanced Monitoring
3. 🟢 **考慮**: 購買 Reserved Instance (節省 40-60%)

---

### 3. bingo-prd-backstage-replica1 🟢

#### 基本配置
- **實例類型**: db.t4g.medium (2 vCPU, 4 GB RAM - ARM Graviton2)
- **角色**: Read Replica of bingo-prd-backstage
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 1465 GB
  - 最大自動擴展: 5,000 GB
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-10-02

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 8.04% | 33.77% | 🟢 良好 |
| 資料庫連線數 | 6 | 12 | 🟢 低 |
| 可用記憶體 | 1.97 GB | - | 🟢 正常 |
| 可用儲存空間 | 256.09 GB | - | 🟢 充足 |
| Read IOPS | 31 | 5,895 | 🟡 嚴重過度配置 |
| Write IOPS | 31 | 1,791 | 🟡 嚴重過度配置 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 62 IOPS
- 使用率: 0.5%
- **建議**: 降至 3,000 IOPS

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用
- ⚠️ 公開訪問已啟用
- ❌ 備份保留期: 0 天 (Read Replica 不進行備份)
- ✅ Replication 狀態: Normal

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 3,000 (節省 ~$1,035/月)
2. 🟡 **評估**: 連線數極低(平均6)，確認使用需求

---

### 4. bingo-prd-loyalty 🟢

#### 基本配置
- **實例類型**: db.t4g.medium (2 vCPU, 4 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 200 GB
  - 最大自動擴展: 5,000 GB
  - Provisioned IOPS: 3,000 (基準配置)
  - 吞吐量: 125 MB/s (基準配置)
- **可用區**: ap-east-1c
- **創建日期**: 2024-01-25

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 6.28% | 9.06% | 🟢 優秀 |
| 資料庫連線數 | 4 | 6 | 🟢 低 |
| 可用記憶體 | 1.94 GB | - | 🟢 正常 |
| 可用儲存空間 | 79.35 GB | - | 🟢 充足 (60% 使用率) |
| Read IOPS | 2 | 556 | 🟢 適當配置 |
| Write IOPS | 12 | 340 | 🟢 適當配置 |

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用
- ✅ Enhanced Monitoring 已啟用 (60s)
- ⚠️ 公開訪問已啟用
- ❌ IAM 資料庫認證未啟用
- ❌ Multi-AZ 未啟用

#### 備份配置
- 備份保留期: 3 天
- 備份窗口: 18:00-19:00 UTC
- 維護窗口: Thursday 10:21-10:51 UTC

#### 建議
1. 🟢 **配置良好**: IOPS 配置適當，無需調整
2. 🟢 **監控完善**: 已啟用 Enhanced Monitoring

---

### 5. bingo-prd-replica1 🟢

#### 基本配置
- **實例類型**: db.m6g.large (2 vCPU, 8 GB RAM - ARM Graviton2)
- **角色**: Read Replica of bingo-prd
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 2662 GB
  - 最大自動擴展: 5,000 GB
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-12-18

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 5.96% | 11.87% | 🟢 優秀 |
| 資料庫連線數 | 102 | 124 | 🟢 正常 |
| 可用記憶體 | 4.38 GB | - | 🟢 充足 |
| 可用儲存空間 | 436.06 GB | - | 🟢 充足 |
| Read IOPS | 76 | 2,445 | 🟡 過度配置 |
| Write IOPS | 273 | 5,687 | 🟡 過度配置 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 349 IOPS
- 使用率: 2.9%
- **建議**: 降至 3,000-5,000 IOPS

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用
- ✅ Replication 狀態: Normal
- ⚠️ 公開訪問已啟用
- ❌ 備份保留期: 0 天 (Read Replica)

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 5,000 (節省 ~$800/月)
2. 🟢 **考慮**: 購買 Reserved Instance (與主實例一起)

---

### 6. bingo-stress 🟡

#### 基本配置
- **實例類型**: db.t4g.medium (2 vCPU, 4 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 2750 GB
  - 最大自動擴展: 未設定
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-12-14

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 6.94% | 76.50% | 🟡 峰值高 |
| 資料庫連線數 | 59 | 286 | 🟡 波動大 |
| 可用記憶體 | 1.99 GB | - | 🟢 正常 |
| 可用儲存空間 | 530.74 GB | - | 🟢 充足 |
| Read IOPS | 48 | 6,059 | 🟡 過度配置 |
| Write IOPS | 19 | 4,509 | 🟡 過度配置 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 67 IOPS
- 使用率: 0.6%
- **建議**: 降至 3,000 IOPS

#### 安全性配置
- ✅ 儲存加密已啟用
- ⚠️ 公開訪問已啟用
- ❌ 刪除保護**未啟用** (壓測環境可能是刻意的)
- ❌ Performance Insights 未啟用
- ❌ Enhanced Monitoring 未啟用
- ❌ Multi-AZ 未啟用

#### 備份配置
- 備份保留期: 3 天
- 備份窗口: 18:00-19:00 UTC
- 維護窗口: Thursday 08:00-08:30 UTC

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 3,000 (節省 ~$1,035/月)
2. 🟡 **評估**: CPU 峰值達 76%，確認是否為壓測期間
3. 🟡 **評估**: 確認是否需要啟用刪除保護
4. 🟡 **優化**: 啟用 Performance Insights 以便分析
5. ⚠️ **配置**: 未設定儲存自動擴展上限

---

### 7. bingo-stress-backstage 🟡

#### 基本配置
- **實例類型**: db.t4g.medium (2 vCPU, 4 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 5024 GB
  - 最大自動擴展: 未設定
  - Provisioned IOPS: 12,000
  - 吞吐量: 500 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-12-14

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 22.48% | 78.62% | 🔴 峰值非常高 |
| 資料庫連線數 | 7 | 13 | 🟢 低 |
| 可用記憶體 | 1.88 GB | - | 🟡 偏低 |
| 可用儲存空間 | 3742.93 GB | - | 🟢 充足 (25% 使用率) |
| Read IOPS | 134 | 3,018 | 🟡 過度配置 |
| Write IOPS | 39 | 5,453 | 🟡 過度配置 |

**IOPS 使用率分析**:
- 配置: 12,000 IOPS
- 實際平均使用: 173 IOPS
- 使用率: 1.4%
- **建議**: 降至 3,000 IOPS

#### 安全性配置
- ✅ 儲存加密已啟用
- ⚠️ 公開訪問已啟用
- ❌ 刪除保護未啟用
- ❌ Performance Insights 未啟用
- ❌ Enhanced Monitoring 未啟用

#### 備份配置
- 備份保留期: 3 天

#### 建議
1. 🔴 **立即處理**: 降低 IOPS 至 3,000 (節省 ~$1,035/月)
2. 🔴 **警告**: CPU 峰值達 79%，建議監控或升級實例
3. 🟡 **評估**: 連線數低但 CPU 高，可能有長查詢或批次作業
4. 🟡 **優化**: 啟用 Performance Insights 以分析效能瓶頸
5. ⚠️ **配置**: 未設定儲存自動擴展上限

---

### 8. bingo-stress-loyalty 🟢

#### 基本配置
- **實例類型**: db.t4g.medium (2 vCPU, 4 GB RAM - ARM Graviton2)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 200 GB
  - 最大自動擴展: 未設定
  - Provisioned IOPS: 3,000
  - 吞吐量: 125 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2024-01-25

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 5.48% | 35.40% | 🟢 良好 |
| 資料庫連線數 | 1 | 3 | 🟡 極低 |
| 可用記憶體 | 2.03 GB | - | 🟢 正常 |
| 可用儲存空間 | 84.86 GB | - | 🟢 充足 |
| Read IOPS | 1 | 607 | 🟢 適當 |
| Write IOPS | 3 | 24 | 🟢 適當 |

#### 安全性配置
- ✅ 儲存加密已啟用
- ⚠️ 公開訪問已啟用
- ❌ 刪除保護未啟用
- ❌ Performance Insights 未啟用
- ❌ Enhanced Monitoring 未啟用

#### 備份配置
- 備份保留期: 3 天

#### 建議
1. 🟡 **評估**: 平均連線數僅 1，確認是否仍需要此實例
2. 🟢 **配置良好**: IOPS 配置適當
3. 🟡 **考慮**: 如果使用率持續低迷，考慮刪除或按需啟動

---

### 9. pgsqlrel 🔴

#### 基本配置
- **實例類型**: db.t3.small (2 vCPU, 2 GB RAM - Intel)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 40 GB
  - 最大自動擴展: 1,000 GB
  - Provisioned IOPS: 3,000
  - 吞吐量: 125 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-08-14

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 6.25% | 11.18% | 🟢 良好 |
| 資料庫連線數 | 54 | 71 | 🟢 正常 |
| 可用記憶體 | 0.52 GB | - | 🔴 **嚴重不足** |
| 可用儲存空間 | 11.68 GB | - | 🟡 偏低 (71% 使用率) |
| Read IOPS | 4 | 648 | 🟢 適當 |
| Write IOPS | 10 | 208 | 🟢 適當 |

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用
- ⚠️ 公開訪問已啟用
- ⚠️ 備份保留期僅 1 天

#### 建議
1. 🔴 **緊急**: 可用記憶體僅 0.52 GB (26%)，強烈建議升級至 db.t3.medium (4 GB RAM)
2. 🟡 **注意**: 儲存空間使用率 71%，監控增長趨勢
3. 🟡 **改善**: 增加備份保留期至 3-7 天
4. 🟡 **優化**: 考慮遷移至 db.t4g.small (ARM Graviton2，性能更好且成本更低)

---

### 10. pgsqlrel-backstage 🔴

#### 基本配置
- **實例類型**: db.t3.micro (2 vCPU, 1 GB RAM - Intel)
- **引擎版本**: PostgreSQL 14.15
- **儲存配置**:
  - 類型: gp3
  - 已分配: 40 GB
  - 最大自動擴展: 200 GB
  - Provisioned IOPS: 3,000
  - 吞吐量: 125 MB/s
- **可用區**: ap-east-1c
- **創建日期**: 2023-08-14

#### 效能指標 (7天平均)
| 指標 | 平均值 | 最大值 | 評估 |
|------|--------|--------|------|
| CPU 使用率 | 5.33% | 8.79% | 🟢 優秀 |
| 資料庫連線數 | 10 | 13 | 🟢 正常 |
| 可用記憶體 | 0.05 GB | - | 🔴 **極度不足** |
| 可用儲存空間 | 14.62 GB | - | 🟡 偏低 (63% 使用率) |
| Read IOPS | 8 | 809 | 🟢 適當 |
| Write IOPS | 6 | 831 | 🟢 適當 |

#### 安全性配置
- ✅ 儲存加密已啟用
- ✅ 刪除保護已啟用
- ✅ Performance Insights 已啟用
- ⚠️ 公開訪問已啟用
- ⚠️ 備份保留期僅 1 天

#### 建議
1. 🔴 **緊急**: 可用記憶體僅 50 MB (5%)，**立即升級**至 db.t3.small (2 GB RAM) 或 db.t4g.small
2. 🟡 **注意**: 儲存空間使用率 63%
3. 🟡 **改善**: 增加備份保留期
4. 🟡 **優化**: 考慮遷移至 ARM Graviton2 實例以獲得更好的性價比

---

## 效能指標分析

### CPU 使用率總結

| 實例 | 平均 CPU | 最大 CPU | 狀態 |
|------|---------|---------|------|
| bingo-prd | 16.22% | 36.21% | 🟢 正常 |
| bingo-prd-backstage | 5.40% | 11.24% | 🟢 優秀 (可能過度配置) |
| bingo-prd-backstage-replica1 | 8.04% | 33.77% | 🟢 正常 |
| bingo-prd-loyalty | 6.28% | 9.06% | 🟢 優秀 |
| bingo-prd-replica1 | 5.96% | 11.87% | 🟢 優秀 |
| bingo-stress | 6.94% | 76.50% | 🟡 峰值高 |
| bingo-stress-backstage | 22.48% | 78.62% | 🔴 峰值很高 |
| bingo-stress-loyalty | 5.48% | 35.40% | 🟢 正常 |
| pgsqlrel | 6.25% | 11.18% | 🟢 正常 |
| pgsqlrel-backstage | 5.33% | 8.79% | 🟢 優秀 |

**關鍵發現**:
- 大部分實例 CPU 使用率健康
- bingo-stress-backstage 峰值達 79%，需關注
- 生產環境實例有充足的 CPU 容量

### 記憶體使用率總結

| 實例 | 實例記憶體 | 可用記憶體 | 使用率 | 狀態 |
|------|-----------|-----------|--------|------|
| bingo-prd | 8 GB | 4.21 GB | 47% | 🟢 健康 |
| bingo-prd-backstage | 8 GB | 4.36 GB | 46% | 🟢 健康 |
| bingo-prd-backstage-replica1 | 4 GB | 1.97 GB | 51% | 🟢 健康 |
| bingo-prd-loyalty | 4 GB | 1.94 GB | 52% | 🟢 健康 |
| bingo-prd-replica1 | 8 GB | 4.38 GB | 45% | 🟢 健康 |
| bingo-stress | 4 GB | 1.99 GB | 50% | 🟢 健康 |
| bingo-stress-backstage | 4 GB | 1.88 GB | 53% | 🟢 健康 |
| bingo-stress-loyalty | 4 GB | 2.03 GB | 49% | 🟢 健康 |
| pgsqlrel | 2 GB | 0.52 GB | 74% | 🔴 **壓力大** |
| pgsqlrel-backstage | 1 GB | 0.05 GB | 95% | 🔴 **危險** |

**關鍵發現**:
- pgsqlrel-backstage 記憶體嚴重不足 (95% 使用率)
- pgsqlrel 記憶體使用率過高 (74%)
- 其他實例記憶體使用率健康

### IOPS 使用率總結

| 實例 | 配置 IOPS | 實際平均使用 | 使用率 | 評估 |
|------|----------|-------------|--------|------|
| bingo-prd | 12,000 | 453 | 3.8% | 🔴 嚴重過度配置 |
| bingo-prd-backstage | 12,000 | 121 | 1.0% | 🔴 嚴重過度配置 |
| bingo-prd-backstage-replica1 | 12,000 | 62 | 0.5% | 🔴 嚴重過度配置 |
| bingo-prd-loyalty | 3,000 | 14 | 0.5% | 🟢 適當 |
| bingo-prd-replica1 | 12,000 | 349 | 2.9% | 🔴 嚴重過度配置 |
| bingo-stress | 12,000 | 67 | 0.6% | 🔴 嚴重過度配置 |
| bingo-stress-backstage | 12,000 | 173 | 1.4% | 🔴 嚴重過度配置 |
| bingo-stress-loyalty | 3,000 | 4 | 0.1% | 🟢 適當 |
| pgsqlrel | 3,000 | 14 | 0.5% | 🟢 適當 |
| pgsqlrel-backstage | 3,000 | 14 | 0.5% | 🟢 適當 |

**關鍵發現**:
- 6 個實例配置了 12,000 IOPS 但使用率不到 4%
- IOPS 過度配置是最大的成本浪費源
- 建議將 12,000 IOPS 降至 3,000-5,000

### 連線數分析

| 實例 | 平均連線數 | 最大連線數 | 評估 |
|------|-----------|-----------|------|
| bingo-prd | 145 | 162 | 🟢 穩定 |
| bingo-prd-backstage | 11 | 12 | 🟢 穩定 |
| bingo-prd-backstage-replica1 | 6 | 12 | 🟡 低 |
| bingo-prd-loyalty | 4 | 6 | 🟢 低但穩定 |
| bingo-prd-replica1 | 102 | 124 | 🟢 穩定 |
| bingo-stress | 59 | 286 | 🟡 波動大 |
| bingo-stress-backstage | 7 | 13 | 🟢 低 |
| bingo-stress-loyalty | 1 | 3 | 🔴 極低 |
| pgsqlrel | 54 | 71 | 🟢 穩定 |
| pgsqlrel-backstage | 10 | 13 | 🟢 穩定 |

---

## 安全性評估

### 公開訪問分析

**所有 10 個實例都啟用了公開訪問** ⚠️

雖然實例配置了 VPC 安全群組，但公開訪問增加了攻擊面。

**建議**:
1. 審查是否真的需要公開訪問
2. 如果需要，確保安全群組規則嚴格限制來源 IP
3. 考慮使用 VPN 或 AWS PrivateLink
4. 啟用 VPC Flow Logs 監控流量

### 加密狀態

✅ **所有實例都啟用了儲存加密** - 優秀

- KMS Key: arn:aws:kms:ap-east-1:470013648166:key/c026ed81-c3d0-43bf-95b9-b78216797ca2

### IAM 資料庫認證

❌ **所有實例都未啟用 IAM 資料庫認證**

**建議**: 啟用 IAM 認證以提高安全性，避免使用長期密碼

### Multi-AZ 配置

❌ **所有實例都未啟用 Multi-AZ**

對於生產環境，這是一個重大風險。

**建議**:
- 優先為 bingo-prd 和 bingo-prd-backstage 啟用 Multi-AZ
- Read Replicas 可提供部分高可用性，但無自動故障轉移

### 刪除保護

| 實例 | 刪除保護 | 評估 |
|------|---------|------|
| bingo-prd | ✅ 啟用 | 🟢 |
| bingo-prd-backstage | ✅ 啟用 | 🟢 |
| bingo-prd-backstage-replica1 | ✅ 啟用 | 🟢 |
| bingo-prd-loyalty | ✅ 啟用 | 🟢 |
| bingo-prd-replica1 | ✅ 啟用 | 🟢 |
| bingo-stress | ❌ 未啟用 | 🟡 測試環境可接受 |
| bingo-stress-backstage | ❌ 未啟用 | 🟡 測試環境可接受 |
| bingo-stress-loyalty | ❌ 未啟用 | 🟡 測試環境可接受 |
| pgsqlrel | ✅ 啟用 | 🟢 |
| pgsqlrel-backstage | ✅ 啟用 | 🟢 |

### 備份配置

| 實例 | 備份保留期 | 評估 |
|------|-----------|------|
| bingo-prd | 3 天 | 🟡 建議 7 天 |
| bingo-prd-backstage | 3 天 | 🟡 建議 7 天 |
| bingo-prd-backstage-replica1 | 0 天 | 🟢 Replica 正常 |
| bingo-prd-loyalty | 3 天 | 🟡 建議 7 天 |
| bingo-prd-replica1 | 0 天 | 🟢 Replica 正常 |
| bingo-stress | 3 天 | 🟢 測試環境適當 |
| bingo-stress-backstage | 3 天 | 🟢 測試環境適當 |
| bingo-stress-loyalty | 3 天 | 🟢 測試環境適當 |
| pgsqlrel | 1 天 | 🔴 太短 |
| pgsqlrel-backstage | 1 天 | 🔴 太短 |

**建議**:
- 生產環境實例: 增加至 7-14 天
- 開發環境實例: 增加至 3-7 天

### Performance Insights

| 實例 | Performance Insights | 保留期 | 評估 |
|------|---------------------|--------|------|
| bingo-prd | ✅ Standard | 7 天 | 🟢 |
| bingo-prd-backstage | ✅ Advanced | 465 天 | 🟢 優秀 |
| bingo-prd-backstage-replica1 | ✅ Standard | 7 天 | 🟢 |
| bingo-prd-loyalty | ✅ Standard | 7 天 | 🟢 |
| bingo-prd-replica1 | ✅ Standard | 7 天 | 🟢 |
| bingo-stress | ❌ 未啟用 | - | 🔴 建議啟用 |
| bingo-stress-backstage | ❌ 未啟用 | - | 🔴 建議啟用 |
| bingo-stress-loyalty | ❌ 未啟用 | - | 🟡 |
| pgsqlrel | ✅ Standard | 7 天 | 🟢 |
| pgsqlrel-backstage | ✅ Standard | 7 天 | 🟢 |

### Enhanced Monitoring

只有 **bingo-prd-loyalty** 啟用了 Enhanced Monitoring (60秒間隔)

**建議**: 為生產環境的關鍵實例啟用 Enhanced Monitoring

---

## 儲存健康度

### 儲存空間使用率

| 實例 | 已分配 | 已使用 | 可用 | 使用率 | 自動擴展上限 | 評估 |
|------|-------|-------|------|--------|-------------|------|
| bingo-prd | 2750 GB | 2260 GB | 490 GB | 82% | 5000 GB | 🟢 |
| bingo-prd-backstage | 5024 GB | 1975 GB | 3049 GB | 39% | 10000 GB | 🟢 |
| bingo-prd-backstage-replica1 | 1465 GB | 1209 GB | 256 GB | 83% | 5000 GB | 🟢 |
| bingo-prd-loyalty | 200 GB | 121 GB | 79 GB | 60% | 5000 GB | 🟢 |
| bingo-prd-replica1 | 2662 GB | 2226 GB | 436 GB | 84% | 5000 GB | 🟢 |
| bingo-stress | 2750 GB | 2219 GB | 531 GB | 81% | 未設定 | 🟡 |
| bingo-stress-backstage | 5024 GB | 1281 GB | 3743 GB | 25% | 未設定 | 🟡 |
| bingo-stress-loyalty | 200 GB | 115 GB | 85 GB | 58% | 未設定 | 🟡 |
| pgsqlrel | 40 GB | 28 GB | 12 GB | 71% | 1000 GB | 🟡 |
| pgsqlrel-backstage | 40 GB | 25 GB | 15 GB | 63% | 200 GB | 🟡 |

**關鍵發現**:
- 大部分實例儲存使用健康
- Stress 環境實例未設定自動擴展上限，建議配置
- pgsqlrel 系列使用率偏高，需監控

### 儲存類型與 IOPS

所有實例都使用 **gp3** 儲存類型 ✅ - 這是最新且成本效益最好的選擇

**IOPS 配置問題** (已在效能指標中詳述):
- 6 個實例配置 12,000 IOPS，但實際使用率不到 4%
- 這是最大的成本優化機會

### 儲存吞吐量

| 配置 | 實例數量 | 評估 |
|------|---------|------|
| 500 MB/s | 6 | 可能過高 |
| 125 MB/s | 4 | 基準配置，適當 |

---

## 成本分析

### 當前月度成本估算

| 實例 | 計算 | 儲存 | IOPS | 吞吐量 | 月度總計 |
|------|------|------|------|--------|---------|
| bingo-prd | $220 | $379 | $1,035 | $26 | **$1,660** |
| bingo-prd-backstage | $220 | $693 | $1,035 | $26 | **$1,974** |
| bingo-prd-backstage-replica1 | $73 | $202 | $1,035 | $26 | **$1,336** |
| bingo-prd-loyalty | $73 | $28 | $0 | $0 | **$101** |
| bingo-prd-replica1 | $220 | $367 | $1,035 | $26 | **$1,648** |
| bingo-stress | $73 | $379 | $1,035 | $26 | **$1,513** |
| bingo-stress-backstage | $73 | $693 | $1,035 | $26 | **$1,827** |
| bingo-stress-loyalty | $73 | $28 | $0 | $0 | **$101** |
| pgsqlrel | $40 | $6 | $0 | $0 | **$46** |
| pgsqlrel-backstage | $20 | $6 | $0 | $0 | **$26** |

**當前總成本**:
- **月度**: ~$10,232
- **年度**: ~$122,784

### 成本分解

- **計算 (Instance)**: $1,085/月 (10.6%)
- **儲存 (Storage)**: $2,781/月 (27.2%)
- **IOPS (over baseline)**: $6,210/月 (60.7%)
- **吞吐量 (over baseline)**: $156/月 (1.5%)

**最大成本來源: IOPS 過度配置 (60.7%)**

---

## 建議與行動計劃

### 🔴 緊急優先 (立即處理)

#### 1. 記憶體不足問題
**實例**: pgsqlrel, pgsqlrel-backstage

**問題**:
- pgsqlrel-backstage: 可用記憶體僅 50 MB (5%)
- pgsqlrel: 可用記憶體僅 520 MB (26%)

**行動**:
```bash
# pgsqlrel-backstage: db.t3.micro (1GB) → db.t3.small (2GB)
aws rds modify-db-instance \
  --db-instance-identifier pgsqlrel-backstage \
  --db-instance-class db.t3.small \
  --apply-immediately

# pgsqlrel: db.t3.small (2GB) → db.t3.medium (4GB)
aws rds modify-db-instance \
  --db-instance-identifier pgsqlrel \
  --db-instance-class db.t3.medium \
  --apply-immediately
```

**影響**: 需要重啟，選擇維護窗口
**成本增加**: ~$40/月
**效益**: 防止 OOM 和效能問題

#### 2. IOPS 過度配置優化
**實例**: 6 個配置 12,000 IOPS 的實例

**問題**: IOPS 使用率僅 0.5%-3.8%

**行動**:
```bash
# 範例: bingo-prd 降至 5000 IOPS
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --iops 5000 \
  --no-apply-immediately

# bingo-prd-backstage, bingo-prd-replica1 等可降至 3000 IOPS
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd-backstage \
  --iops 3000 \
  --no-apply-immediately
```

**推薦配置**:
- bingo-prd: 12000 → 5000 IOPS (節省 $805/月)
- bingo-prd-backstage: 12000 → 3000 IOPS (節省 $1,035/月)
- bingo-prd-backstage-replica1: 12000 → 3000 IOPS (節省 $1,035/月)
- bingo-prd-replica1: 12000 → 5000 IOPS (節省 $805/月)
- bingo-stress: 12000 → 3000 IOPS (節省 $1,035/月)
- bingo-stress-backstage: 12000 → 3000 IOPS (節省 $1,035/月)

**總節省**: ~$5,750/月 (~$69,000/年)
**影響**: 線上修改，無需重啟
**風險**: 低 (當前使用率極低)

### 🟡 高優先 (1-2週內處理)

#### 3. Reserved Instances 購買
**實例**: bingo-prd, bingo-prd-backstage, bingo-prd-replica1

**目標**: 降低計算成本

**選項**:
- **1年期無預付**: ~40% 折扣, $396/月節省
- **1年期全額預付**: ~45% 折扣, $446/月節省
- **3年期全額預付**: ~60% 折扣, $594/月節省

**建議**: 1年期無預付 (靈活性與節省的平衡)

**節省**: $400-600/月

#### 4. 啟用 Multi-AZ (高可用性)
**實例**: bingo-prd, bingo-prd-backstage

**行動**:
```bash
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --multi-az \
  --no-apply-immediately
```

**影響**: 需要短暫停機
**成本增加**: 實例成本翻倍 (~$440/月)
**效益**: 自動故障轉移, 99.95% SLA

#### 5. 增加備份保留期
**實例**: 所有生產實例

**行動**:
```bash
# 生產環境增加至 7 天
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --backup-retention-period 7 \
  --no-apply-immediately

# 開發環境增加至 3 天
aws rds modify-db-instance \
  --db-instance-identifier pgsqlrel \
  --backup-retention-period 3 \
  --no-apply-immediately
```

**影響**: 線上修改
**成本增加**: 小幅增加儲存成本

#### 6. 啟用 Enhanced Monitoring
**實例**: 生產環境關鍵實例

**行動**:
```bash
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd \
  --monitoring-interval 60 \
  --monitoring-role-arn arn:aws:iam::470013648166:role/rds-monitoring-role \
  --no-apply-immediately
```

**成本**: ~$3/月/實例
**效益**: 更詳細的作業系統層級監控

#### 7. 啟用 Performance Insights (Stress環境)
**實例**: bingo-stress, bingo-stress-backstage

**行動**:
```bash
aws rds modify-db-instance \
  --db-instance-identifier bingo-stress \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --no-apply-immediately
```

**成本**: 免費 (7天保留)
**效益**: 效能分析和問題診斷

### 🟢 中優先 (1個月內處理)

#### 8. 檢討 Stress 環境使用率
**實例**: bingo-stress-loyalty

**問題**: 平均連線數僅 1

**行動**:
1. 確認是否仍需要此實例
2. 如果不需要，考慮刪除
3. 如果需要但使用率低，考慮按需啟動/停止

**潛在節省**: ~$100/月

#### 9. 啟用儲存自動擴展 (Stress環境)
**實例**: bingo-stress, bingo-stress-backstage, bingo-stress-loyalty

**行動**:
```bash
aws rds modify-db-instance \
  --db-instance-identifier bingo-stress \
  --max-allocated-storage 5000 \
  --no-apply-immediately
```

**影響**: 線上修改
**效益**: 防止儲存空間不足

#### 10. 審查公開訪問設定
**實例**: 所有實例

**行動**:
1. 審查每個實例的訪問需求
2. 檢查安全群組規則
3. 考慮使用 VPN 或 PrivateLink
4. 啟用 VPC Flow Logs

**效益**: 提高安全性

#### 11. 考慮 ARM Graviton2 遷移
**實例**: pgsqlrel, pgsqlrel-backstage (目前使用 Intel t3)

**目標**:
- pgsqlrel: db.t3.small → db.t4g.small
- pgsqlrel-backstage: db.t3.micro → db.t4g.micro 或 db.t4g.small

**效益**:
- 更好的性價比 (~20% 成本節省)
- 更好的效能

### 🔵 低優先 (3個月內處理)

#### 12. PostgreSQL 版本升級規劃
**當前**: PostgreSQL 14.15
**最新**: PostgreSQL 17.x

**行動**:
1. 測試環境先升級至 PostgreSQL 15
2. 評估相容性和效能
3. 規劃生產環境升級路徑

**效益**: 新功能、效能改進、安全更新

#### 13. 參數群組優化
**問題**: 所有實例的參數群組狀態為 "pending-reboot"

**行動**:
1. 檢查待套用的參數變更
2. 規劃維護窗口重啟實例
3. 優化參數以符合工作負載

#### 14. 建立 RDS 監控儀表板
**行動**:
1. 使用 CloudWatch Dashboards 建立統一監控
2. 設定關鍵指標告警:
   - CPU > 80%
   - 可用記憶體 < 500 MB
   - 可用儲存空間 < 10%
   - 連線數接近上限
   - Replication Lag > 30 秒

#### 15. 災難復原計劃
**行動**:
1. 測試跨區域快照複製
2. 建立 RTO/RPO 目標
3. 定期演練復原程序

---

## 優化效益總結

### 立即可實現的節省

| 優化項目 | 月度節省 | 年度節省 | 實施難度 | 風險 |
|---------|---------|---------|---------|------|
| IOPS 降級 | $5,750 | $69,000 | 低 | 低 |
| Reserved Instances (1年) | $500 | $6,000 | 低 | 無 |
| 刪除低使用率實例 | $100 | $1,200 | 中 | 中 |
| **總計** | **$6,350** | **$76,200** | - | - |

### 成本優化前後對比

| 項目 | 當前成本 | 優化後成本 | 節省 | 節省比例 |
|------|---------|-----------|------|---------|
| 月度成本 | $10,232 | $3,882 | $6,350 | 62% |
| 年度成本 | $122,784 | $46,584 | $76,200 | 62% |

### 額外成本 (提升穩定性和安全性)

| 項目 | 月度成本 | 說明 |
|------|---------|------|
| pgsqlrel 升級 | +$40 | 緊急記憶體升級 |
| Multi-AZ (2實例) | +$440 | 高可用性 |
| Enhanced Monitoring | +$15 | 5實例 × $3 |
| **總額外成本** | **+$495/月** | - |

### 最終淨節省

**月度淨節省**: $6,350 - $495 = **$5,855/月**
**年度淨節省**: **$70,260/年**
**淨節省比例**: 57%

---

## 下一步行動

### 第1週: 緊急處理
- [ ] 升級 pgsqlrel-backstage 至 db.t3.small
- [ ] 升級 pgsqlrel 至 db.t3.medium
- [ ] 準備 IOPS 降級計劃並獲得批准

### 第2週: IOPS 優化
- [ ] 降低 bingo-prd IOPS 至 5000
- [ ] 降低 bingo-prd-backstage IOPS 至 3000
- [ ] 降低 bingo-prd-backstage-replica1 IOPS 至 3000
- [ ] 監控效能影響

### 第3週: IOPS 優化 (續)
- [ ] 降低 bingo-prd-replica1 IOPS 至 5000
- [ ] 降低 bingo-stress IOPS 至 3000
- [ ] 降低 bingo-stress-backstage IOPS 至 3000

### 第4週: 高可用性和監控
- [ ] 啟用 bingo-prd Multi-AZ
- [ ] 啟用 bingo-prd-backstage Multi-AZ
- [ ] 啟用 Enhanced Monitoring
- [ ] 增加備份保留期至 7 天

### 第2個月: Reserved Instances 和安全性
- [ ] 購買 Reserved Instances
- [ ] 審查並優化安全群組
- [ ] 評估公開訪問需求
- [ ] 啟用 IAM 資料庫認證

### 第3個月: 長期優化
- [ ] 遷移至 Graviton2 (開發實例)
- [ ] 建立監控儀表板
- [ ] 建立災難復原計劃
- [ ] 規劃 PostgreSQL 版本升級

---

## 附錄

### A. 實例規格對照表

| 實例類型 | vCPU | 記憶體 | 架構 | 適用場景 |
|---------|------|--------|------|---------|
| db.t3.micro | 2 | 1 GB | Intel | 極小型開發/測試 |
| db.t3.small | 2 | 2 GB | Intel | 小型開發/測試 |
| db.t3.medium | 2 | 4 GB | Intel | 中型開發/測試 |
| db.t4g.small | 2 | 2 GB | ARM | 小型生產/開發 |
| db.t4g.medium | 2 | 4 GB | ARM | 中型生產 |
| db.m6g.large | 2 | 8 GB | ARM | 大型生產 |

### B. gp3 儲存定價

- **基準配置**:
  - 儲存: $0.138/GB/月
  - IOPS: 3,000 (免費)
  - 吞吐量: 125 MB/s (免費)

- **額外配置**:
  - IOPS (超過3000): $0.115/IOPS/月
  - 吞吐量 (超過125 MB/s): $0.069/MB/s/月

### C. 監控指標閾值建議

| 指標 | 警告 | 嚴重 |
|------|------|------|
| CPU 使用率 | > 70% | > 85% |
| 可用記憶體 | < 1 GB | < 500 MB |
| 可用儲存空間 | < 20% | < 10% |
| 資料庫連線數 | > 80% max | > 95% max |
| Replication Lag | > 30秒 | > 60秒 |
| Read Latency | > 10ms | > 50ms |
| Write Latency | > 20ms | > 100ms |

### D. 維護窗口建議

建議將維護窗口設定在業務低峰期:
- **週間**: 週二或週三
- **時間**: 凌晨 2:00-4:00 (本地時間)
- **避免**: 週一 (週末可能有積壓) 和週五 (週末前的風險)

### E. 備份策略建議

| 環境 | 自動備份保留 | 手動快照頻率 | 跨區域備份 |
|------|------------|-------------|-----------|
| 生產 | 7-14 天 | 每週 | 是 |
| 壓測 | 3-7 天 | 每月 | 否 |
| 開發 | 1-3 天 | 按需 | 否 |

---

**報告產生時間**: 2025-10-28 17:00:00 UTC+8
**下次審查建議**: 2025-11-28 (每月一次)

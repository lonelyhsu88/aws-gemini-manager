# bingo-prd-replica1 RDS Storage Autoscaling 事件記錄

**JIRA Ticket**: [OPS-1033](https://jira.ftgaming.cc/browse/OPS-1033)
**Created**: 2026-01-08
**Status**: Open
**Priority**: Medium

---

## 事件摘要

- **事件時間**: 2026-01-07 22:47 UTC (2026-01-08 06:47 GMT+8)
- **實例**: bingo-prd-replica1
- **事件類型**: RDS Storage Autoscaling
- **當前狀態**: storage-optimization
- **區域**: ap-east-1 (香港)

## 儲存容量變化

| 項目 | 數值 | 說明 |
|------|------|------|
| 擴展前容量 | ~2750 GB | 觸發前容量 |
| 擴展後容量 | 2929 GB | 當前容量 |
| 增加容量 | +179 GB | 單次擴展 |
| 最大容量限制 | 5000 GB | MaxAllocatedStorage |
| 剩餘擴展空間 | 2071 GB | 可繼續擴展 |

## 觸發原因分析

RDS Storage Autoscaling 在以下條件下自動觸發:

1. **可用空間不足 10%** (當時約 286 GB / 2750 GB ≈ 10.4%)
2. **持續 5 分鐘以上的低空間狀態**
3. **距離上次擴展至少 6 小時**

## 可用空間趨勢

從 CloudWatch 指標可以看到明顯的變化：

| 時間 (UTC) | 可用空間 | 狀態 |
|-----------|---------|------|
| 22:58 之前 | ~286-323 GB | 觸發擴展 |
| **22:58 之後** | **~569 GB** | **擴展完成 ⬆️** |

擴展後可用空間增加約 **240-280 GB**

## Storage Optimization 狀態

**storage-optimization** 是 RDS 在完成儲存擴展後的正常狀態:

- 🔄 AWS 正在優化新增的儲存空間
- ⏱️ 通常持續**數小時到 24 小時**
- ✅ 期間實例仍然可以正常運作
- 📊 效能可能略有波動（通常不明顯）

## Replica vs Primary 比較

| 實例 | 當前容量 | 狀態 | 差異 |
|------|---------|------|------|
| bingo-prd (主實例) | 2750 GB | available | - |
| bingo-prd-replica1 | 2929 GB | storage-optimization | +179 GB |

⚠️ **Replica 比主實例多 179 GB**

## 事件時間線

```
2026-01-07 22:47:14 UTC - 開始應用自動擴展修改
2026-01-07 22:49:36 UTC - 完成自動擴展修改
2026-01-07 22:58:00 UTC - 可用空間增加至 ~569 GB
```

## AWS 事件記錄

```bash
aws --profile gemini-pro_ck rds describe-events \
  --source-identifier bingo-prd-replica1 \
  --source-type db-instance \
  --region ap-east-1

# 輸出:
2026-01-07T22:47:14.026000+00:00 | Applying autoscaling-initiated modification to allocated storage.
2026-01-07T22:49:36.790000+00:00 | Finished applying autoscaling-initiated modification to allocated storage.
```

## 技術細節

### 實例配置

```json
{
  "Identifier": "bingo-prd-replica1",
  "Status": "storage-optimization",
  "StorageType": "gp3",
  "AllocatedStorage": 2929,
  "Iops": 12000,
  "StorageThroughput": 500,
  "MaxAllocatedStorage": 5000,
  "InstanceClass": "db.m6g.large",
  "SourceInstance": "bingo-prd"
}
```

### CloudWatch 可用空間數據 (最近 10 小時)

```
2026-01-07 20:58:00 UTC - 285,950,311,014 bytes (~266 GB)
2026-01-07 21:58:00 UTC - 323,606,909,405 bytes (~301 GB)
2026-01-07 22:58:00 UTC - 569,054,512,059 bytes (~530 GB) ⬆️
2026-01-07 23:58:00 UTC - 569,177,305,224 bytes (~530 GB)
2026-01-08 00:58:00 UTC - 569,070,825,062 bytes (~530 GB)
2026-01-08 01:58:00 UTC - 568,974,401,536 bytes (~530 GB)
2026-01-08 02:58:00 UTC - 568,958,375,799 bytes (~530 GB)
2026-01-08 03:58:00 UTC - 568,909,833,557 bytes (~530 GB)
2026-01-08 04:58:00 UTC - 568,904,034,713 bytes (~530 GB)
2026-01-08 05:58:00 UTC - 568,876,598,886 bytes (~530 GB)
```

## 建議與後續行動

### 立即行動

1. ✅ **監控 storage-optimization 完成狀態**
   - 預計 24 小時內完成
   - 檢查實例恢復到 `available` 狀態

2. 🔍 **檢查主實例儲存使用**
   ```bash
   aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
     --namespace AWS/RDS \
     --metric-name FreeStorageSpace \
     --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
     --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 3600 \
     --statistics Average \
     --region ap-east-1
   ```

### 中期規劃

3. 📊 **容量規劃評估**
   - 當前最大容量: 5000 GB
   - 已使用: 2929 GB (58.6%)
   - 如成長速度快，考慮調整 MaxAllocatedStorage

4. 🔔 **設定監控告警**
   - CloudWatch 告警: 可用空間 < 15%
   - SNS 通知: ops-alerts@ftgaming.cc

### 長期建議

5. 📈 **儲存成長趨勢分析**
   - 建立儲存成長率報告
   - 預測未來 3-6 個月容量需求
   - 評估是否需要資料歸檔或清理策略

## 參考連結

- [AWS RDS Console - bingo-prd-replica1](https://console.aws.amazon.com/rds/home?region=ap-east-1#database:id=bingo-prd-replica1)
- [RDS Storage Autoscaling 文檔](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.StorageTypes.html#USER_PIOPS.Autoscaling)
- [CloudWatch Metrics for RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)

## 相關腳本

檢查所有 RDS 實例儲存狀態:

```bash
# 列出所有 bingo 相關實例
aws --profile gemini-pro_ck rds describe-db-instances \
  --region ap-east-1 \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `bingo`)].[DBInstanceIdentifier,DBInstanceStatus,StorageType,AllocatedStorage,MaxAllocatedStorage]' \
  --output table

# 檢查儲存可用空間
./scripts/rds/check-storage-usage.sh  # TODO: 建立此腳本
```

## bingo-prd Primary Instance 分析

**檢查時間**: 2026-01-08 14:10 GMT+8 (06:10 UTC)

### 當前配置

| Parameter | Value | Status |
|-----------|-------|--------|
| Instance ID | bingo-prd | ✅ Primary |
| Status | available | ✅ Normal |
| Storage Type | gp3 | - |
| Allocated Storage | 2750 GB | ⚠️ Lower than replica |
| Max Allocated Storage | 5000 GB | - |
| IOPS | 12000 | - |
| Storage Throughput | 500 MB/s | - |
| Instance Class | db.m6g.large | - |

### 可用空間趨勢 (最近 10 小時)

```
2026-01-08 05:06 GMT+8 - 349,431,565,721 bytes (~325 GB)
2026-01-08 06:06 GMT+8 - 349,612,214,408 bytes (~325 GB)
2026-01-08 07:06 GMT+8 - 349,934,305,553 bytes (~326 GB)
2026-01-08 08:06 GMT+8 - 349,964,185,190 bytes (~326 GB)
2026-01-08 09:06 GMT+8 - 349,664,230,400 bytes (~325 GB)
2026-01-08 10:06 GMT+8 - 348,761,374,173 bytes (~324 GB)
2026-01-08 11:06 GMT+8 - 349,113,992,465 bytes (~325 GB)
2026-01-08 12:06 GMT+8 - 349,374,005,794 bytes (~325 GB)
2026-01-08 13:06 GMT+8 - 349,564,101,290 bytes (~325 GB)
2026-01-08 14:06 GMT+8 - 349,357,497,958 bytes (~325 GB)
```

### 關鍵發現

- **可用空間**: ~325 GB / 2750 GB = **11.8% available**
- **閾值**: 接近 10% autoscaling 觸發閾值
- **趨勢**: 過去 10 小時穩定在 ~325 GB
- **近期事件**: 最近 7 天無 storage autoscaling 事件

### Primary vs Replica 詳細對比

| 指標 | bingo-prd (Primary) | bingo-prd-replica1 | 差異 |
|------|---------------------|-------------------|------|
| Allocated Storage | 2750 GB | 2929 GB | +179 GB (6.5%) |
| Free Space | ~325 GB | ~530 GB | +205 GB |
| Free Space % | 11.8% | 18.1% | +6.3% |
| Status | available | storage-optimization | - |
| Last Autoscaling | None (7 days) | 2026-01-08 06:47 GMT+8 | - |

### 風險評估

⚠️ **中度風險 (MODERATE RISK)**

- Primary 實例可用空間 11.8%，僅高於 autoscaling 閾值 1.8%
- 如果儲存使用量增加，可能在數小時內觸發 autoscaling
- Replica 已觸發 autoscaling，顯示儲存需求正在增長
- 兩實例 MaxAllocatedStorage 皆為 5000 GB，仍有擴展空間

### 建議行動

1. **密切監控**: 監控主實例可用空間，預期即將觸發 autoscaling
2. **設定告警**: CloudWatch alarm for FreeStorageSpace < 15% (412.5 GB)
3. **容量規劃**: 分析儲存成長率，預測何時達到 MaxAllocatedStorage (5000 GB)
4. **主動措施**: 如成長率高，評估資料歸檔或清理策略

### 後續步驟

- 持續監控兩實例 24 小時
- 等待 bingo-prd-replica1 完成 storage-optimization
- 建立 CloudWatch dashboard 監控儲存指標
- 如主實例觸發 autoscaling，安排容量規劃審查

---

## 更新記錄

| 日期 | 更新內容 | 更新人 |
|------|---------|--------|
| 2026-01-08 16:15 GMT+8 | 完成所有 PROD RDS 告警配置更新 (20 個告警) | lonely.h |
| 2026-01-08 16:00 GMT+8 | 添加 autoscaling 觸發告警 (11% 閾值) | lonely.h |
| 2026-01-08 15:20 GMT+8 | 更新 bingo-prd 和 replica1 告警閾值到 15% | lonely.h |
| 2026-01-08 14:10 GMT+8 | 添加 bingo-prd 主實例分析 | lonely.h |
| 2026-01-08 06:50 GMT+8 | 初始事件記錄 | lonely.h |

---

## 告警配置完成記錄

### 配置範圍
已為所有 5 個 PROD RDS 實例完成四層告警配置:

| 實例 | 容量 | Warning (15%) | Autoscaling (11%) | Critical | Slack 通知 |
|------|------|---------------|-------------------|----------|-----------|
| bingo-prd | 2750 GB | 412.5 GB | 302.5 GB | 20 GB | ✅ 所有等級 |
| bingo-prd-replica1 | 2929 GB | 439.35 GB | 322.19 GB | 20 GB | ✅ 所有等級 |
| bingo-prd-backstage | 5024 GB | 753.6 GB | 552.64 GB | 20 GB | ✅ 所有等級 |
| bingo-prd-backstage-replica1 | 1465 GB | 219.75 GB | 161.15 GB | 20 GB | ✅ 所有等級 |
| bingo-prd-loyalty | 200 GB | 30 GB | 22 GB | 10 GB | ✅ 所有等級 |

### 告警階層設計

所有實例遵循統一的四層監控策略：

1. **Warning (15%)**: 早期預警，用於容量規劃
   - 評估週期: 2 × 5 分鐘
   - 通知: Slack

2. **Autoscaling Alert (11%)**: 即將觸發 autoscaling 的提醒
   - 評估週期: 1 × 5 分鐘 (快速響應)
   - 通知: Slack

3. **Autoscaling Trigger (10%)**: RDS 自動擴展觸發點
   - AWS 自動管理

4. **Critical (20 GB 或 10 GB)**: 緊急低空間告警
   - 評估週期: 1 × 5 分鐘
   - 通知: Slack

### 配置腳本

- `scripts/cloudwatch/update-storage-alarms.sh` - 更新 bingo-prd 和 replica1
- `scripts/cloudwatch/setup-autoscaling-alerts.sh` - 添加 11% autoscaling 告警
- `scripts/cloudwatch/update-remaining-alarms.sh` - 更新其他 3 個實例
- `scripts/cloudwatch/check-all-rds-alarms.sh` - 告警配置稽核工具

### 通知配置

- **SNS Topic**: Cloudwatch-Slack-Notification
- **目的地**: Slack 頻道 (透過 Lambda 整合)
- **事件**: ALARM 和 OK 狀態變更
- **覆蓋範圍**: 5 個實例 × 4 個等級 = 20 個告警

### 預期效益

1. **早期預警**: 在 autoscaling 觸發前提供充足的通知時間
2. **即時告警**: 11% 閾值確保在 autoscaling 前獲得提醒
3. **統一標準**: 所有實例使用一致的監控策略
4. **團隊可見性**: 所有告警路由到 Slack 供團隊檢視
5. **自動化處理**: Autoscaling 自動擴展，減少手動介入
6. **容量規劃**: 早期預警支援更好的容量規劃

---

**維護人員**: DevOps Team
**文檔版本**: 2.0
**最後更新**: 2026-01-08 16:15 GMT+8
**告警狀態**: 已完成所有 PROD 實例配置 (20/20 告警)

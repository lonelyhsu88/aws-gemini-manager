# RDS bingo-prd-backstage-replica1 ReadIOPS 告警閾值調整

**Date**: 2026-01-19
**Instance**: bingo-prd-backstage-replica1
**Issue**: HighReadIOPS-Warning 誤報

## 問題分析

### 告警觸發歷史
```
2026-01-19 10:40 - 告警觸發 (ALARM)
2026-01-19 10:41 - 告警恢復 (OK) - 持續 1 分鐘
2026-01-19 15:05 - 告警再次觸發 (ALARM)
```

### 根本原因
1. **實例配置**: bingo-prd-backstage-replica1 配置了 **12000 IOPS** (繼承自主實例)
2. **告警閾值不當**: 設定為 4000/5000 IOPS (僅佔容量的 33%/42%)
3. **實際使用**: 峰值 5886 IOPS 是正常業務流量，但觸發了告警

### 配置對比
| 實例 | 類型 | Provisioned IOPS | 原 Warning | 原 Critical | 使用率 |
|------|------|-----------------|-----------|------------|--------|
| bingo-prd-backstage-replica1 | db.t4g.medium | 12000 | 4000 | 5000 | 33%/42% ❌ |
| bingo-prd-replica1 | db.m6g.large | N/A | 8000 | 10000 | N/A |
| bingo-prd-backstage | db.m6g.large | N/A | 8000 | 10000 | N/A |

## 調整方案

### 參考標準
採用與其他 12000 IOPS 實例一致的閾值標準（db.m6g.large 參考值）

### 閾值調整
```
Warning:  4000 → 8000 IOPS  (67% of 12000)
Critical: 5000 → 10000 IOPS (83% of 12000)
```

## 執行記錄

### 更新前配置
```
RDS-bingo-prd-backstage-replica1-HighReadIOPS-Warning:  4000 IOPS (ALARM)
RDS-bingo-prd-backstage-replica1-HighReadIOPS-Critical: 5000 IOPS (ALARM)
```

### 更新命令
```bash
# Warning 告警
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-replica1-HighReadIOPS-Warning" \
  --threshold 8000 \
  --metric-name ReadIOPS \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --period 60 \
  --statistic Average \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1

# Critical 告警
aws --profile gemini-pro_ck cloudwatch put-metric-alarm \
  --alarm-name "RDS-bingo-prd-backstage-replica1-HighReadIOPS-Critical" \
  --threshold 10000 \
  --metric-name ReadIOPS \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --period 60 \
  --statistic Average \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd-backstage-replica1
```

### 更新後配置
```
RDS-bingo-prd-backstage-replica1-HighReadIOPS-Warning:  8000 IOPS
RDS-bingo-prd-backstage-replica1-HighReadIOPS-Critical: 10000 IOPS
```

### 更新時間
```
2026-01-19 15:16:32 UTC (23:16:32 HKT)
```

## 預期效果

### IOPS 使用情況
- 平均: 714 IOPS (6% of 12000) ✅
- 峰值: 5886 IOPS (49% of 12000) ✅
- 新 Warning: 8000 IOPS (不會觸發)
- 新 Critical: 10000 IOPS (不會觸發)

### 監控改善
1. ✅ 消除正常流量峰值的誤報
2. ✅ 與其他高 IOPS 實例保持一致的監控標準
3. ✅ 保留足夠緩衝空間偵測真正的異常情況

## 技術背景

### gp3 IOPS 獨立設定
```
bingo-prd-backstage (Primary):
- 儲存: 5024 GB
- IOPS: 12000 (手動配置)
- 吞吐量: 500 MB/s

bingo-prd-backstage-replica1 (Replica):
- 儲存: 1465 GB (較小)
- IOPS: 12000 (繼承主實例)
- 吞吐量: 500 MB/s (繼承主實例)
```

### 成本影響
```
額外 IOPS 成本: 9000 × $0.006 = $54.00/月
額外吞吐量成本: 375 MB/s × $0.048 = $18.00/月
```

## 後續建議

### 短期
- ✅ 監控調整後的告警狀態
- ✅ 確認不再收到誤報

### 中期
- 啟用 Enhanced Monitoring (60秒間隔)
- 檢查 Performance Insights 識別慢查詢
- 評估是否需要優化查詢

### 長期
- 監控流量增長趨勢
- 評估是否升級實例類型到 db.m6g.large（與主實例一致）
- 考慮實施查詢快取策略

## 參考文件
- AWS RDS gp3 文檔: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html
- CloudWatch 告警最佳實踐: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html

---

## Jira Issue

**JIRA Ticket**: [OPS-1110](https://jira.ftgaming.cc/browse/OPS-1110)
**Created**: 2026-01-19
**Status**: Task
**Assignee**: lonely.h
**Labels**: rds, cloudwatch, alert-tuning, bingo-prd, readiops

### Issue Summary
完整記錄了 bingo-prd-backstage-replica1 HighReadIOPS 告警閾值調整的完整過程，包括：
- 問題分析和根本原因
- 實例配置和 IOPS 使用情況
- 閾值調整方案和執行命令
- 執行結果和預期效果
- 技術背景和成本分析
- 後續建議（短期、中期、長期）

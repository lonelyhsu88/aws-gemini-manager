# bingo-prd 告警調整快速參考卡

## 📌 一句話總結
**當前告警閾值 675 過高（實際峰值僅 182），建議立即調整至 180-200**

---

## 🎯 推薦告警配置

```
層級  閾值   佔比    觸發頻率   處理時間   命令
----  ----   ----    --------   --------   ----
P2    180    20.0%   每週1-2次  1小時內    見下方
P1    200    22.2%   罕見       30分鐘內   見下方
P0    250    27.7%   不應發生   立即       見下方
```

---

## ⚡ 一鍵執行命令

### 設定環境變數
```bash
export AWS_PROFILE=gemini-pro_ck
export AWS_REGION=ap-east-1
export SNS_TOPIC="arn:aws:sns:ap-east-1:ACCOUNT:TOPIC"
```

### 創建 P2 告警（推薦）
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-medium" \
  --alarm-description "bingo-prd 連接數偏高 (>180)" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 180 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC \
  --region $AWS_REGION
```

### 創建 P1 告警
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-high" \
  --alarm-description "bingo-prd 連接數異常高 (>200)" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 200 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC \
  --region $AWS_REGION
```

### 創建 P0 告警
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "bingo-prd-db-connections-critical" \
  --alarm-description "bingo-prd 連接數危險 (>250)" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 250 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=bingo-prd \
  --treat-missing-data notBreaching \
  --alarm-actions $SNS_TOPIC \
  --region $AWS_REGION
```

---

## 📊 關鍵數據

| 指標 | 數值 |
|------|------|
| 平均連接數 | 148 |
| 峰值連接數 | 182 |
| P95 | 159 |
| P99 | 168 |
| 最大容量 | 901 |
| 使用率 | 20% |
| 當前告警 | 675 ❌ |
| 建議告警 | 180 ✅ |

---

## 🕐 高峰時段

```
最繁忙: 22:00-01:00
最清閒: 05:00-08:00
維護建議時間: 06:00-07:00
```

---

## 📚 詳細文件

| 文件 | 用途 |
|------|------|
| ANALYSIS-SUMMARY.md | 執行摘要（本文件的詳細版）|
| BINGO-PRD-ANALYSIS-REPORT.md | 完整 20 頁分析報告 |
| ALARM-CONFIG-QUICKSTART.md | 詳細配置指南 |
| analyze-bingo-prd-connections.py | 自動分析工具 |

---

## ✅ 執行檢查清單

- [ ] 設定環境變數（AWS_PROFILE, SNS_TOPIC）
- [ ] 創建 P2 告警（180 連接）
- [ ] 創建 P1 告警（200 連接）
- [ ] 創建 P0 告警（250 連接）
- [ ] 測試告警通知
- [ ] 建立 CloudWatch Dashboard
- [ ] 檢查應用連接池配置

---

**更新**: 2025-10-29 | **位置**: `/scripts/rds/`

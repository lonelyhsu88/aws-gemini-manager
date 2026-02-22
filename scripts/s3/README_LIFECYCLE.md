# S3 Lifecycle Configuration for jenkins-build-artfs

## 📋 配置概述

**Bucket**: `jenkins-build-artfs`
**配置文件**: `scripts/s3/jenkins-build-artfs-lifecycle.json`
**套用日期**: 2026-01-19
**AWS Profile**: `gemini-pro_ck`

## 🎯 配置規則

### Rule 1: cleanup-builds-90days
- **狀態**: ✅ Enabled
- **適用範圍**: 所有物件（Prefix: ""）
- **規則內容**:
  - **當前版本**: 90 天後自動刪除
  - **非當前版本**: 30 天後自動刪除

## 💡 配置目的

1. **自動清理舊建置產物**
   - 保留最近 90 天的建置歷史
   - 超過 90 天的建置自動刪除

2. **版本控制管理**
   - 因為 bucket 已啟用版本控制
   - 非當前版本（被覆蓋的舊版本）30 天後刪除
   - 避免版本歷史無限增長

3. **成本優化**
   - 預期可減少 70-80% 的儲存成本
   - 無需手動清理舊檔案

## 📊 預期效果

### 刪除前（2026-01-19）
- 共有 2025 年檔案 781 個（約 12.3 GB）已手動刪除
- 當前保留 2026 年建置 + 2015 年測試檔案

### 刪除後（持續運作）
- 自動保持最近 90 天的建置
- 自動清理超過 30 天的非當前版本
- 儲存空間維持在合理範圍

## 🔧 管理命令

### 查看當前配置
```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket jenkins-build-artfs \
  --profile gemini-pro_ck
```

### 更新配置
```bash
# 1. 修改配置文件
vim scripts/s3/jenkins-build-artfs-lifecycle.json

# 2. 套用新配置
aws s3api put-bucket-lifecycle-configuration \
  --bucket jenkins-build-artfs \
  --lifecycle-configuration file://scripts/s3/jenkins-build-artfs-lifecycle.json \
  --profile gemini-pro_ck
```

### 移除配置（不建議）
```bash
aws s3api delete-bucket-lifecycle \
  --bucket jenkins-build-artfs \
  --profile gemini-pro_ck
```

## 📝 配置調整建議

### 如果需要保留更久
修改 `Days` 參數：
```json
{
  "Expiration": {
    "Days": 180  // 改為 180 天
  }
}
```

### 如果需要儲存類別轉換
新增 `Transitions` 規則（降低成本但保留更久）：
```json
{
  "Transitions": [
    {
      "Days": 30,
      "StorageClass": "STANDARD_IA"
    },
    {
      "Days": 90,
      "StorageClass": "GLACIER"
    }
  ],
  "Expiration": {
    "Days": 180
  }
}
```

## ⚠️ 注意事項

1. **刪除是永久的**
   - Lifecycle 刪除的檔案無法復原
   - 確保 90 天保留期符合需求

2. **非當前版本**
   - 因為啟用了版本控制
   - 覆蓋檔案會產生非當前版本
   - 30 天後自動清理

3. **費用影響**
   - 刪除物件不會產生額外費用
   - 版本控制會增加一些儲存成本（30 天內）
   - 整體仍可大幅降低儲存成本

## 📈 監控建議

定期檢查 bucket 大小：
```bash
# 列出所有檔案並統計大小
aws s3 ls s3://jenkins-build-artfs/ --recursive --profile gemini-pro_ck \
  | awk '{sum+=$3} END {print "Total: " sum/1024/1024/1024 " GB"}'

# 查看當前目錄
aws s3 ls s3://jenkins-build-artfs/ --profile gemini-pro_ck
```

## 🔗 相關資源

- AWS S3 Lifecycle 文檔: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html
- 配置文件: `scripts/s3/jenkins-build-artfs-lifecycle.json`
- 專案文檔: `CLAUDE.md`

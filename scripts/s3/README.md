# S3 Scripts

S3 管理相關腳本工具集。

## 📜 可用腳本

### check-ssl-certificates.sh

檢查 S3 bucket `renew-ssl-certification` 中所有 SSL 憑證的狀態。

#### 功能特色

- ✅ 自動檢查所有域名的憑證
- 📊 按照剩餘天數分類（健康/注意/警告/緊急）
- 🎨 彩色輸出，易於識別狀態
- 📈 統計分析和建議行動
- 🔧 多種輸出格式

#### 使用方法

```bash
# 預設表格格式（顯示所有憑證）
./scripts/s3/check-ssl-certificates.sh

# 僅顯示摘要統計
./scripts/s3/check-ssl-certificates.sh --format=summary

# 僅顯示需要關注的憑證
./scripts/s3/check-ssl-certificates.sh --format=alert
```

#### 輸出範例

**表格格式**:
```
==================================================
SSL 憑證狀況檢查
檢查時間: 2026-01-20 18:00:00
S3 Bucket: s3://renew-ssl-certification/
總域名數: 28
==================================================

狀態 | 域名                        | 剩餘天數 | 到期日期      | 憑證機構
-----|----------------------------|---------|--------------|-------------
✅ | elsgame-dev.cc              |  89 天  | 19 Apr 2026 | Let's Encrypt E7
✅ | elsgame.cc                  |  89 天  | 19 Apr 2026 | Let's Encrypt E8
⚠️  | geminigaming.io             |  38 天  | 27 Feb 2026 | Let's Encrypt E8
⚠️  | shuangzi6666.com            |  30 天  | 19 Feb 2026 | Let's Encrypt E8
...

==================================================
統計摘要
==================================================
✅ 健康 (>45天):    17 個域名 (60.7%)
⚠️  注意 (30-45天): 11 個域名 (39.3%)
⚠️  警告 (14-30天):  0 個域名 (0.0%)
🔴 緊急 (<14天):     0 個域名 (0.0%)
```

**Alert 格式**（僅顯示需要關注的憑證）:
```
需要關注的憑證：

⚠️  geminigaming.io               剩餘:  38 天  到期: 27 Feb 2026
⚠️  shuangzi6666.com              剩餘:  30 天  到期: 19 Feb 2026
⚠️  shuangzi6666.net              剩餘:  30 天  到期: 19 Feb 2026
...
```

#### 狀態分類

| 狀態 | 剩餘天數 | 說明 | 建議行動 |
|------|---------|------|----------|
| ✅ 健康 | > 45 天 | 憑證狀態良好 | 定期監控 |
| ⚠️ 注意 | 30-45 天 | 需要規劃更新 | 本月內更新 |
| ⚠️ 警告 | 14-30 天 | 即將到期 | 本週內更新 |
| 🔴 緊急 | < 14 天 | 緊急狀態 | 立即更新 |

#### 設定定期檢查

可以使用 cron 設定定期自動檢查：

```bash
# 編輯 crontab
crontab -e

# 每週一早上 9:00 檢查並發送郵件報告
0 9 * * 1 /path/to/aws-gemini-manager/scripts/s3/check-ssl-certificates.sh --format=alert | mail -s "SSL Certificate Alert" admin@example.com

# 或將結果保存到日誌文件
0 9 * * 1 /path/to/aws-gemini-manager/scripts/s3/check-ssl-certificates.sh >> /var/log/ssl-cert-check.log 2>&1
```

#### 需求

- AWS CLI (配置 `gemini-pro_ck` profile)
- OpenSSL
- Bash 4.0+

#### 故障排除

**問題**: `aws: command not found`
```bash
# 安裝 AWS CLI
brew install awscli  # macOS
# 或
pip install awscli  # Python
```

**問題**: `Permission denied`
```bash
# 設定執行權限
chmod +x scripts/s3/check-ssl-certificates.sh
```

**問題**: `Profile 'gemini-pro_ck' not found`
```bash
# 確認 AWS profile 設定
aws configure list-profiles | grep gemini-pro_ck

# 測試 profile
aws --profile gemini-pro_ck sts get-caller-identity
```

## 📋 其他相關文檔

- [完整憑證狀況報告](../../docs/SSL_CERTIFICATE_DETAILED_STATUS_20260120.md)
- [AWS 管理指南](../../CLAUDE.md)

---

**最後更新**: 2026-01-20

# Lambda 測試快速參考

**用途**: Lambda 函數測試快速檢查清單
**完整文檔**: 請參閱 `TESTING_BEST_PRACTICES.md`

---

## ⚡ 快速檢查清單

### 測試前必做 ✅

```bash
# 1. 確認環境
echo "測試環境: TEST 還是 PRODUCTION?"

# 2. 確認 Slack 目標
echo "Slack 頻道: #aws-cloudwatch-test (測試) 還是 #aws-cloudwatch (生產)?"

# 3. 標記測試消息
echo "測試事件是否包含 'test_mode': true ?"

# 4. 通知團隊
echo "是否已通知相關人員？"
```

---

## 🔧 測試流程三步驟

### Step 1: 本地測試（不發送）
```bash
cd /tmp/lambda-deploy
python3 << 'EOF'
import json
from lambda_function import format_cloudwatch_notification

# 載入測試事件
with open('test-event.json') as f:
    event = json.load(f)

sns_msg = json.loads(event['Records'][0]['Sns']['Message'])
result = format_cloudwatch_notification(sns_msg)

print(json.dumps(result, indent=2, ensure_ascii=False))
print("\n✅ 格式正確，未發送")
EOF
```

### Step 2: 測試環境測試（發送到測試頻道）
```bash
# 使用包含 test_mode 的事件
aws lambda invoke \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --cli-binary-format raw-in-base64-out \
  --payload file://test-event-with-test-flag.json \
  response.json

# 檢查測試頻道確認收到 [TEST] 標記的消息
```

### Step 3: 生產部署（真實告警）
```bash
# 更新 Lambda
aws lambda update-function-code \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --zip-file fileb://lambda-deployment.zip

# 監控日誌
aws logs tail /aws/lambda/Cloudwatch-Slack-Notification \
  --profile gemini-pro_ck \
  --follow
```

---

## 🚨 關鍵原則

### ✅ 必須做
1. **隔離測試** - 使用測試頻道或本地測試
2. **標記測試** - 所有測試消息包含 [TEST]
3. **事先通知** - 告知團隊測試計劃
4. **階段測試** - 本地 → 測試環境 → 生產

### ❌ 禁止做
1. **直接生產測試** - 不要用生產 webhook 測試格式
2. **無標記測試** - 不要發送未標記的測試消息
3. **跳過步驟** - 不要跳過本地測試
4. **高峰測試** - 不要在業務高峰期測試

---

## 📝 測試事件模板

### 安全的測試事件（包含 test_mode）
```json
{
  "test_mode": true,
  "Records": [{
    "Sns": {
      "Message": "{\"AlarmName\":\"[P1] TEST-bingo-prd-RDS-Connections-High\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"[TEST] This is a test message\",\"StateChangeTime\":\"2025-10-29T08:35:45.456+0000\",\"OldStateValue\":\"OK\",\"Trigger\":{\"MetricName\":\"DatabaseConnections\",\"Namespace\":\"AWS/RDS\",\"Threshold\":675.0,\"Dimensions\":[{\"value\":\"bingo-prd-test\",\"name\":\"DBInstanceIdentifier\"}]}}"
    }
  }]
}
```

**關鍵點**:
- ✅ `"test_mode": true` - 啟用測試模式
- ✅ `AlarmName` 包含 "TEST"
- ✅ `NewStateReason` 包含 "[TEST]"
- ✅ `Dimensions.value` 使用 "test" 後綴

---

## 🛠️ 緊急回滾

如果測試出錯需要立即回滾：

```bash
# 1. 停止當前測試
# 在 Slack 發送停止通知

# 2. 檢查 Lambda 版本
aws lambda list-versions-by-function \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification

# 3. 回滾到上一版本
aws lambda update-function-code \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --zip-file fileb://lambda-deployment-backup.zip

# 4. 驗證
aws lambda invoke \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --cli-binary-format raw-in-base64-out \
  --payload file://test-event.json \
  response.json
```

---

## 📞 聯絡人

**測試問題**: DevOps Team
**Slack 頻道**: #devops
**緊急聯絡**: 參考 on-call 輪值表

---

## 🔗 相關資源

- **完整指南**: `TESTING_BEST_PRACTICES.md`
- **Lambda 代碼**: `/tmp/lambda-deploy/lambda_function.py`
- **測試事件**: `/tmp/lambda-test-events.json`
- **部署包**: `/tmp/lambda-deployment-fixed.zip`

---

**記住**: 測試時永遠問自己三個問題：
1. 這會發送到生產頻道嗎？ 🤔
2. 消息有 [TEST] 標記嗎？ 🏷️
3. 我通知團隊了嗎？ 📢

**最後更新**: 2025-10-29

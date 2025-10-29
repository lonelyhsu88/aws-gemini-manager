# Lambda 函數與告警測試最佳實踐

**創建日期**: 2025-10-29
**原因**: Lambda 測試時誤發告警到生產 Slack 頻道
**目的**: 防止測試消息影響生產環境監控

---

## 📋 事件記錄

### 發生的問題

**日期**: 2025-10-29 17:33
**事件**: 優化 Slack 通知 Lambda 函數時，使用測試事件發送到生產 Slack 頻道

**測試消息內容**:
```
🟠 [P1] HIGH - ALARM
Alarm Name: [P1] bingo-prd-RDS-Connections-High
State Change: OK → ALARM
Time (UTC+8): 2025-10-29 16:35:45
Instance: bingo-prd
Metric: DatabaseConnections
Threshold: 675.00
Details: Threshold Crossed: 2 datapoints [690.0, 682.0] were greater than threshold
```

**實際情況**:
- 真實連線數: 140-145 (正常)
- 告警狀態: OK (未觸發)
- 690 和 682 是測試數據，不是真實指標

**影響**:
- ❌ 用戶收到虛假告警通知
- ❌ 可能引起不必要的緊急響應
- ❌ 降低監控系統的可信度

---

## ✅ 改進措施

### 1. 測試環境隔離

#### 方案 A: 使用測試 Slack 頻道（推薦）

**實施步驟**:

1. **創建測試 Webhook**
   ```bash
   # 在 Slack 中創建新的 Incoming Webhook
   # 頻道: #aws-cloudwatch-test (或 #dev-testing)
   # 獲取測試 webhook URL
   ```

2. **Lambda 環境變量**
   ```bash
   # 生產環境
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T7ZUQSX88/B07KEL70ET0/...
   ENVIRONMENT=production

   # 測試環境
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T7ZUQSX88/B07KEL70ET0/TEST_WEBHOOK
   ENVIRONMENT=test
   ```

3. **代碼修改**
   ```python
   import os

   def lambda_handler(event, context):
       # 獲取環境配置
       environment = os.environ.get('ENVIRONMENT', 'production')
       webhook_url = os.environ.get('SLACK_WEBHOOK_URL')

       # 測試環境添加前綴
       if environment == 'test':
           msg['text'] = f"[TEST] {msg.get('text', '')}"
           msg['attachments'][0]['color'] = '#808080'  # 灰色
   ```

#### 方案 B: 本地測試（無 Slack 發送）

**測試腳本**:
```python
# test_lambda_locally.py
import json
from lambda_function import format_cloudwatch_notification

# 載入測試事件
with open('test-events.json') as f:
    test_event = json.load(f)['p1_alarm_event']

# 解析 SNS 消息
sns_message = json.loads(test_event['Records'][0]['Sns']['Message'])

# 格式化（不發送）
attachment = format_cloudwatch_notification(sns_message)

# 輸出到控制台
print(json.dumps(attachment, indent=2, ensure_ascii=False))
print("\n✅ 格式化成功，未發送到 Slack")
```

**執行測試**:
```bash
cd /tmp/lambda-deploy
python3 test_lambda_locally.py
```

---

### 2. 測試消息明確標註

所有測試消息必須包含明確標識：

#### Lambda 函數修改
```python
def lambda_handler(event, context):
    # 檢查是否為測試調用
    is_test = event.get('test_mode', False) or \
              os.environ.get('ENVIRONMENT') == 'test'

    if is_test:
        # 在標題添加 [TEST] 標記
        attachment['title'] = f"[🧪 TEST] {attachment['title']}"

        # 修改顏色為灰色
        attachment['color'] = '#808080'

        # 在 footer 標註
        attachment['footer'] = "⚠️ THIS IS A TEST MESSAGE - AWS CloudWatch"
```

#### 測試事件添加標記
```json
{
  "test_mode": true,
  "Records": [...]
}
```

---

### 3. 測試前通知機制

#### 測試檢查清單

在執行 Lambda 測試前，必須完成以下檢查：

```markdown
## Lambda 測試前檢查清單

- [ ] 確認 Lambda 函數名稱（是否為測試版本？）
- [ ] 確認 Slack Webhook URL（是否為測試頻道？）
- [ ] 確認環境變量設置（ENVIRONMENT=test?）
- [ ] 測試消息是否包含 [TEST] 標記？
- [ ] 是否已通知相關人員測試進行中？
- [ ] 是否準備好回滾計劃？

測試執行人: __________
通知對象: __________
預計測試時間: __________
```

#### Slack 通知範例

**測試開始前** (發送到 #dev-team):
```
🧪 Lambda 測試通知

將在接下來30分鐘內測試 CloudWatch Slack 通知功能：
• Lambda: Cloudwatch-Slack-Notification
• 測試頻道: #aws-cloudwatch-test
• 預計測試: 3-5 次
• 測試人員: @your-name

如有問題請聯繫我
```

**測試完成後**:
```
✅ Lambda 測試完成

結果: 成功
測試次數: 5
問題: 無
已部署到生產環境: 是
```

---

### 4. 版本管理策略

#### Lambda 函數版本

```bash
# 創建測試版本
aws lambda publish-version \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --description "Test version for Slack format testing"

# 創建測試別名
aws lambda create-alias \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --name test \
  --function-version 2 \
  --description "Test alias for development"

# 創建生產別名
aws lambda create-alias \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --name prod \
  --function-version 1 \
  --description "Production alias"
```

#### SNS 訂閱分離

```bash
# 生產 SNS Topic → 生產 Lambda (prod alias)
arn:aws:lambda:ap-east-1:ACCOUNT:function:Cloudwatch-Slack-Notification:prod

# 測試 SNS Topic → 測試 Lambda (test alias)
arn:aws:lambda:ap-east-1:ACCOUNT:function:Cloudwatch-Slack-Notification:test
```

---

## 📝 測試流程標準程序

### 階段 1: 本地開發測試

```bash
# 1. 在本地測試格式化邏輯
python3 test_lambda_locally.py

# 2. 驗證輸出格式
# 確認 JSON 結構正確
# 確認中文顯示正常
# 確認顏色代碼正確
```

### 階段 2: Lambda 測試環境測試

```bash
# 1. 更新測試 Lambda 函數
aws lambda update-function-code \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --zip-file fileb://lambda-deployment.zip \
  --publish

# 2. 使用測試事件調用（發送到測試頻道）
aws lambda invoke \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification:test \
  --cli-binary-format raw-in-base64-out \
  --payload file://test-event-with-flag.json \
  response.json

# 3. 檢查測試頻道的消息
# 確認 [TEST] 標記存在
# 確認格式正確
# 確認顏色和字段顯示
```

### 階段 3: 生產環境部署

```bash
# 1. 通知團隊
# 在 Slack 發送部署通知

# 2. 更新生產 Lambda
aws lambda update-function-code \
  --profile gemini-pro_ck \
  --function-name Cloudwatch-Slack-Notification \
  --zip-file fileb://lambda-deployment.zip

# 3. 監控 CloudWatch Logs
aws logs tail \
  --profile gemini-pro_ck \
  --follow \
  /aws/lambda/Cloudwatch-Slack-Notification

# 4. 等待真實告警觸發驗證
# 或在低峰時段手動觸發一次測試告警
```

---

## 🔧 實用測試工具

### 1. 本地測試腳本

**文件**: `scripts/rds/test-lambda-notification.py`

```python
#!/usr/bin/env python3
"""
本地測試 Lambda 通知格式（不發送到 Slack）
"""
import json
import sys

# 導入 Lambda 函數（需要複製 lambda_function.py 到本地）
sys.path.insert(0, '/tmp/lambda-deploy')
from lambda_function import format_cloudwatch_notification

def test_notification(test_name, event_file):
    """測試單個通知格式"""
    print(f"\n{'='*80}")
    print(f"測試: {test_name}")
    print('='*80)

    # 載入測試事件
    with open(event_file) as f:
        event = json.load(f)

    # 解析 SNS 消息
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])

    # 格式化通知
    attachment = format_cloudwatch_notification(sns_message)

    # 顯示結果
    print(f"\n標題: {attachment['title']}")
    print(f"顏色: {attachment['color']}")
    print(f"\n字段:")
    for field in attachment['fields']:
        print(f"  • {field['title']}: {field['value']}")

    print(f"\n✅ {test_name} 格式化成功")
    return attachment

# 執行測試
if __name__ == '__main__':
    tests = [
        ('P0 Critical Alarm', 'test-events/p0-alarm.json'),
        ('P1 High Priority Alarm', 'test-events/p1-alarm.json'),
        ('P2 Medium Priority Alarm', 'test-events/p2-alarm.json'),
        ('Alarm Recovery (OK)', 'test-events/ok-state.json')
    ]

    results = []
    for name, file in tests:
        try:
            result = test_notification(name, file)
            results.append((name, '✅ PASS'))
        except Exception as e:
            results.append((name, f'❌ FAIL: {e}'))

    # 總結
    print(f"\n{'='*80}")
    print("測試總結")
    print('='*80)
    for name, status in results:
        print(f"{status:12} {name}")
```

### 2. 測試事件生成器

**文件**: `scripts/rds/generate-test-events.py`

```python
#!/usr/bin/env python3
"""
生成各種優先級的測試事件
"""
import json
from datetime import datetime

def generate_test_event(priority, alarm_name, metric, threshold, current_value):
    """生成測試用的 SNS 事件"""

    event = {
        "Records": [{
            "Sns": {
                "Message": json.dumps({
                    "AlarmName": f"[P{priority}] {alarm_name}",
                    "NewStateValue": "ALARM",
                    "NewStateReason": f"[TEST] Simulated alarm for testing. Current: {current_value}, Threshold: {threshold}",
                    "StateChangeTime": datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f+0000'),
                    "OldStateValue": "OK",
                    "Trigger": {
                        "MetricName": metric,
                        "Namespace": "AWS/RDS",
                        "Threshold": threshold,
                        "Dimensions": [{
                            "value": "bingo-prd-test",
                            "name": "DBInstanceIdentifier"
                        }]
                    }
                })
            }
        }],
        "test_mode": True  # 標記為測試模式
    }

    return event

# 生成測試事件
test_events = {
    "p0_test": generate_test_event(0, "test-RDS-FreeStorageSpace-Low", "FreeStorageSpace", 214748364800, 180000000000),
    "p1_test": generate_test_event(1, "test-RDS-Connections-High", "DatabaseConnections", 675, 690),
    "p2_test": generate_test_event(2, "test-RDS-ReadLatency-High", "ReadLatency", 0.01, 0.012)
}

# 保存
with open('test-events-safe.json', 'w') as f:
    json.dump(test_events, f, indent=2)

print("✅ 測試事件已生成: test-events-safe.json")
print("⚠️  這些事件包含 test_mode 標記，會在消息中顯示 [TEST]")
```

---

## 📚 相關文檔

### 內部文檔
- `lambda_function_optimized.py` - 優化後的 Lambda 函數代碼
- `lambda-test-events.json` - 標準測試事件
- `lambda-optimization-comparison.md` - 優化前後對比

### AWS 文檔
- [Lambda 版本和別名](https://docs.aws.amazon.com/lambda/latest/dg/configuration-aliases.html)
- [Lambda 測試最佳實踐](https://docs.aws.amazon.com/lambda/latest/dg/testing-functions.html)
- [CloudWatch Alarms 測試](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ConsoleAlarms.html)

---

## 🎯 關鍵要點

### ✅ DO (應該做的)

1. **隔離測試環境**
   - 使用獨立的 Slack 測試頻道
   - 使用 Lambda 別名區分生產/測試
   - 使用環境變量控制行為

2. **明確標記測試**
   - 所有測試消息必須包含 [TEST] 或 🧪
   - 使用不同的顏色（灰色）
   - 在 footer 標註測試消息

3. **測試前通知**
   - 通知相關團隊成員
   - 說明測試範圍和時間
   - 準備回滾計劃

4. **階段性測試**
   - 本地測試 → 測試環境 → 生產環境
   - 每個階段驗證通過才進入下一階段

### ❌ DON'T (不應該做的)

1. **直接在生產環境測試**
   - ❌ 不要用真實的 webhook 測試格式
   - ❌ 不要發送未標記的測試消息
   - ❌ 不要在業務高峰期測試

2. **跳過測試步驟**
   - ❌ 不要跳過本地測試直接部署
   - ❌ 不要不通知就執行測試
   - ❌ 不要沒有回滾計劃

3. **使用生產數據**
   - ❌ 不要用真實的告警數據測試
   - ❌ 不要在測試中使用真實的閾值
   - ❌ 不要讓測試影響真實監控

---

## 📋 快速檢查清單

複製此清單用於每次 Lambda 測試：

```markdown
## Lambda 函數測試檢查清單

### 測試前準備
- [ ] 測試目的明確
- [ ] 測試計劃已撰寫
- [ ] 相關人員已通知
- [ ] 測試環境已準備（測試頻道/Lambda 別名）
- [ ] 測試事件已準備（包含 test_mode 標記）
- [ ] 回滾計劃已準備

### 本地測試
- [ ] 代碼格式化測試通過
- [ ] 單元測試通過
- [ ] 測試事件格式驗證通過
- [ ] 輸出格式符合預期

### 測試環境測試
- [ ] 部署到測試 Lambda
- [ ] 發送測試消息到測試頻道
- [ ] 驗證消息格式正確
- [ ] 驗證 [TEST] 標記存在
- [ ] 驗證顏色和優先級正確

### 生產部署
- [ ] 測試環境驗證通過
- [ ] 代碼審查完成
- [ ] 部署通知已發送
- [ ] CloudWatch Logs 監控已啟動
- [ ] 部署成功確認
- [ ] 功能驗證通過

### 測試後
- [ ] 測試結果已記錄
- [ ] 測試消息已清理（如需要）
- [ ] 測試完成通知已發送
- [ ] 文檔已更新（如需要）

測試人員: __________
日期: __________
```

---

## 📊 事件後檢討（Post-Mortem）

### 本次事件 (2025-10-29)

**發生什麼**:
- Lambda 函數優化測試時，測試消息發送到生產 Slack 頻道
- 測試數據 (690 connections) 讓用戶以為是真實告警

**根本原因**:
1. 未使用獨立的測試頻道
2. 測試消息未標記 [TEST]
3. 使用了看似真實的數據
4. 未事先通知用戶

**影響**:
- 用戶收到虛假告警
- 降低監控系統信任度
- 可能觸發不必要的緊急響應

**學到的教訓**:
1. ✅ 必須使用測試環境隔離
2. ✅ 所有測試必須明確標記
3. ✅ 測試前必須通知相關人員
4. ✅ 建立完整的測試流程

**行動項目**:
- [x] 創建此測試最佳實踐文檔
- [ ] 設置專用測試 Slack 頻道
- [ ] 創建 Lambda 測試別名
- [ ] 編寫自動化測試腳本
- [ ] 在團隊分享此經驗

---

**文檔版本**: 1.0
**最後更新**: 2025-10-29
**維護者**: DevOps Team
**審核狀態**: ✅ 已審核

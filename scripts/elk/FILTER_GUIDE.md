# Elastalert 過濾規則指南

## 🎯 目標

過濾掉成功訊息，避免產生不必要的告警：
```
Msg: [SendCustomItem] SendWebApi GetResp: {Error:{Code:0 Message:Success}}
```

## 🚀 快速執行

### 方法 1: 使用自動化腳本（推薦）

```bash
./scripts/elk/filter-success-message.sh
```

**腳本會自動：**
1. 🔍 搜索相關規則文件
2. 📄 顯示當前規則內容
3. 💡 提供過濾方法建議
4. 🔧 自動備份並修改規則（可選）
5. 🔄 重啟容器套用變更

### 方法 2: 手動修改（完全控制）

參考下方的「手動修改步驟」。

## 📝 過濾方法

### ✅ 推薦方法 1: Query String 過濾

**語法：**
```yaml
filter:
  - query:
      query_string:
        query: 'NOT (message: "Error:{Code:0 Message:Success}")'
```

**優點：**
- 簡單直觀
- 適用於大多數規則類型
- 效能好

**更精確的過濾：**
```yaml
filter:
  - query:
      query_string:
        query: 'NOT (message: "SendCustomItem" AND message: "Code:0" AND message: "Message:Success")'
```

### ✅ 方法 2: Must Not 布林查詢

**語法：**
```yaml
filter:
  - bool:
      must_not:
        - match:
            message: "Error:{Code:0 Message:Success}"
```

**優點：**
- 更靈活
- 可組合多個條件
- 適合複雜過濾場景

**組合多個條件：**
```yaml
filter:
  - bool:
      must_not:
        - match:
            message: "Code:0"
        - match:
            message: "Message:Success"
```

### ✅ 方法 3: Blacklist（僅適用於 blacklist 類型規則）

**語法：**
```yaml
type: blacklist
compare_key: message
blacklist:
  - "Error:{Code:0 Message:Success}"
```

**限制：**
- 只能用於 `type: blacklist` 的規則
- 檢查規則類型：`grep "^type:" rule.yaml`

## 🔧 手動修改步驟

### 1️⃣ 找到相關規則

```bash
# SSH 進入主機
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177

# 搜索包含關鍵字的規則
cd /opt/elastalert2/rules
grep -l "SendCustomItem\|SendWebApi\|GetResp" *.yaml

# 或列出所有規則
ls -1 *.yaml | head -30
```

### 2️⃣ 備份規則文件

```bash
# 創建備份（重要！）
sudo cp rule-name.yaml rule-name.yaml.backup.$(date +%Y%m%d_%H%M%S)
```

### 3️⃣ 查看當前規則

```bash
cat rule-name.yaml
```

**規則範例：**
```yaml
name: Example Alert Rule
type: any
index: logstash-*

filter:
  - term:
      service: "my-service"

alert:
  - slack

slack_webhook_url: "https://hooks.slack.com/..."
```

### 4️⃣ 添加過濾條件

**情況 A: 規則已有 `filter:` 區塊**

在現有 filter 中添加 NOT 條件：

```yaml
filter:
  - term:
      service: "my-service"
  - query:                              # ← 新增
      query_string:                     # ← 新增
        query: 'NOT (message: "Error:{Code:0 Message:Success}")'  # ← 新增
```

**情況 B: 規則沒有 `filter:` 區塊**

在 `type:` 後面添加新的 filter：

```yaml
name: Example Alert Rule
type: any
index: logstash-*
filter:                                  # ← 新增
  - query:                               # ← 新增
      query_string:                      # ← 新增
        query: 'NOT (message: "Error:{Code:0 Message:Success}")'  # ← 新增

alert:
  - slack
```

### 5️⃣ 編輯規則文件

```bash
# 使用 vim 編輯
sudo vim rule-name.yaml

# 或使用 nano
sudo nano rule-name.yaml
```

**Vim 快速操作：**
- 按 `i` 進入插入模式
- 編輯內容
- 按 `Esc` 退出插入模式
- 輸入 `:wq` 保存並退出

### 6️⃣ 測試規則語法（可選但建議）

```bash
docker exec elastalert2 elastalert-test-rule \
  --config /opt/elastalert/elastalert.yaml \
  /opt/elastalert/rules/rule-name.yaml
```

**預期輸出：**
```
Successfully loaded rule-name.yaml
```

**如果有錯誤：**
- 檢查 YAML 縮排（必須用空格，不能用 Tab）
- 檢查引號是否正確
- 使用在線 YAML validator 驗證語法

### 7️⃣ 重啟容器套用變更

```bash
cd /opt/elastalert2
docker-compose restart
```

### 8️⃣ 驗證修改

```bash
# 查看容器狀態
docker ps --filter name=elastalert

# 查看啟動日誌
docker logs --tail 100 elastalert2

# 監控即時日誌
docker logs -f elastalert2
```

**正常輸出應包含：**
```
Elastalert started
Loaded rule: rule-name.yaml
```

**如果有錯誤：**
```
Error loading rule rule-name.yaml: ...
```
→ 檢查規則語法，修正後再次重啟

## 🧪 測試過濾效果

### 方法 1: 等待實際觸發

- 等待系統產生包含成功訊息的日誌
- 檢查是否還收到 Slack 告警
- 預期：不再收到包含 `Code:0 Message:Success` 的告警

### 方法 2: 手動觸發測試（進階）

```bash
# 使用 elastalert-test-rule 測試
docker exec elastalert2 elastalert-test-rule \
  --config /opt/elastalert/elastalert.yaml \
  /opt/elastalert/rules/rule-name.yaml \
  --days 1
```

## 🔍 監控與驗證

### 檢查規則是否正常運作

```bash
# 查看 Elastalert 狀態索引
curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?v

# 查看最近的告警
curl -s http://172.31.33.84:9200/elastalert_status/_search?size=10 | jq '.'
```

### 查看容器日誌

```bash
# 最近 100 行
docker logs --tail 100 elastalert2

# 即時監控
docker logs -f elastalert2

# 搜索特定規則
docker logs elastalert2 2>&1 | grep "rule-name"
```

## 🚨 故障排除

### 問題 1: 修改後容器無法啟動

**原因：** YAML 語法錯誤

**解決：**
```bash
# 回滾到備份
sudo cp rule-name.yaml.backup.20260119_120000 rule-name.yaml

# 重啟容器
docker-compose restart
```

### 問題 2: 過濾不生效，仍然收到告警

**可能原因：**
1. 過濾條件不夠精確
2. 訊息格式有變化
3. 有多個規則匹配同樣的事件

**檢查：**
```bash
# 查看實際的日誌訊息格式
curl -s "http://172.31.33.84:9200/logstash-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": {
        "message": "SendCustomItem"
      }
    },
    "size": 1
  }' | jq '.hits.hits[0]._source'

# 比對實際格式與過濾條件是否匹配
```

**調整過濾條件：**
```yaml
# 使用更寬鬆的匹配
filter:
  - query:
      query_string:
        query: 'NOT (message: *Success* AND message: *Code:0*)'
```

### 問題 3: 找不到應該修改哪個規則

**解決步驟：**

1. 檢查 Slack 告警訊息，找到規則名稱
2. 搜索規則文件：
   ```bash
   cd /opt/elastalert2/rules
   grep -r "SendCustomItem" .
   grep -r "SendWebApi" .
   ```
3. 列出最近修改的規則：
   ```bash
   ls -lt *.yaml | head -20
   ```

## 📊 進階過濾範例

### 過濾多個成功訊息

```yaml
filter:
  - query:
      query_string:
        query: 'NOT (
          (message: "Error:{Code:0 Message:Success}") OR
          (message: "Status:OK") OR
          (message: "Result:Success")
        )'
```

### 只過濾特定服務的成功訊息

```yaml
filter:
  - bool:
      must:
        - term:
            service: "payment-service"
      must_not:
        - match:
            message: "Code:0"
```

### 使用正則表達式過濾

```yaml
filter:
  - query:
      query_string:
        query: 'NOT message: /Error:\\{Code:0.*Success\\}/'
```

## 📚 參考資料

- [Elastalert2 Filter 文檔](https://elastalert2.readthedocs.io/en/latest/ruletypes.html#filters)
- [Elasticsearch Query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)
- [YAML 語法驗證器](https://www.yamllint.com/)

## 💡 最佳實踐

1. **永遠先備份規則文件**
   ```bash
   sudo cp rule.yaml rule.yaml.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **使用明確的過濾條件**
   - 避免過於寬鬆的匹配（如只過濾 "Success"）
   - 包含足夠的上下文（如 "Code:0" + "Message:Success"）

3. **測試規則語法**
   ```bash
   docker exec elastalert2 elastalert-test-rule --config /opt/elastalert/elastalert.yaml /opt/elastalert/rules/rule.yaml
   ```

4. **監控修改效果**
   - 修改後至少監控 24 小時
   - 確認沒有漏掉重要告警
   - 確認成功訊息確實被過濾

5. **文檔化變更**
   - 在規則文件中添加註解說明過濾原因
   - 記錄修改日期和修改者
   ```yaml
   # 2026-01-19: 過濾 SendCustomItem 成功訊息 (Code:0)
   # 原因: 這是正常的成功回應，不需要告警
   filter:
     - query:
         query_string:
           query: 'NOT (message: "Error:{Code:0 Message:Success}")'
   ```

## 🔄 回滾步驟

如果過濾造成問題，需要回滾：

```bash
# 1. SSH 進入主機
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177

# 2. 找到備份文件
ls -lt /opt/elastalert2/rules/*.backup.* | head -5

# 3. 回滾
sudo cp /opt/elastalert2/rules/rule-name.yaml.backup.20260119_120000 \
        /opt/elastalert2/rules/rule-name.yaml

# 4. 重啟容器
cd /opt/elastalert2
docker-compose restart

# 5. 驗證
docker logs --tail 100 elastalert2
```

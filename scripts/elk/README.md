# Elastalert2 管理工具

管理和查看 pro-elk (gemini-elk-prd) 主機上的 Elastalert2 配置。

## 📋 主機信息

- **主機名稱**: gemini-elk-prd-01
- **Instance ID**: i-0283c28d4f94b8f68
- **Public IP**: 18.163.127.177
- **Private IP**: 172.31.33.84
- **用戶**: ec2-user
- **SSH 密鑰**: ~/.ssh/hk-devops.pem

## 🛠️ 可用工具

### 1. 互動式選單（推薦）

```bash
./scripts/elk/elastalert-menu.sh
```

**功能：**
- 📊 查看容器狀態和資源使用
- 📁 列出所有規則文件
- 📄 查看主配置文件
- 🔍 搜索並查看特定規則
- 📈 查看 Elasticsearch 索引狀態
- 📝 查看 Docker 日誌
- 🔄 重啟容器
- 📊 規則統計分析
- 🚪 直接 SSH 進入主機

### 2. 完整配置檢查

```bash
./scripts/elk/check-elastalert-config.sh
```

**輸出內容：**
1. 主機信息和運行時間
2. Docker 容器狀態
3. 配置文件結構
4. 主配置文件內容
5. 規則文件統計
6. 規則目錄內容
7. Elasticsearch 索引狀態
8. 最近 Docker 日誌

### 3. 查看特定規則

```bash
# 列出所有可用規則
./scripts/elk/view-elastalert-rule.sh

# 查看特定規則
./scripts/elk/view-elastalert-rule.sh rule-name.yaml
```

## 📁 Elastalert2 目錄結構

```
/opt/elastalert2/
├── elastalert.yaml              # 主配置文件
├── docker-compose.yml           # Docker Compose 配置
├── rules/                       # 規則目錄（291個規則）
│   ├── danger-*.yaml           # Critical 規則（164個，realert: 5分鐘）
│   ├── warning-*.yaml          # Warning 規則（7個，realert: 10分鐘）
│   └── info-*.yaml             # Info 規則（120個，realert: 60分鐘）
└── rules.backup.20251110_100800/  # 備份目錄
```

## ⚙️ 配置標準

### Realert 間隔

| 嚴重性 | 間隔 | 規則數量 | 用途 |
|--------|------|---------|------|
| **Critical/Danger** | 5 分鐘 | 164 | 高危告警，需要及時處理 |
| **Warning** | 10 分鐘 | 7 | 警告級別，需要關注 |
| **Info/Good** | 60 分鐘 | 120 | 一般資訊，定期通知 |

### 禁止配置

```yaml
# ❌ 禁止使用（會造成 Slack rate limiting）
realert:
   minutes: 0
```

**原因：**
- 每個匹配事件都會觸發 Slack 通知
- Slack webhook 限制：1 request/minute/webhook
- 導致 429 (Too Many Requests) 錯誤
- 告警積壓、資源耗盡、容器崩潰

## 📊 監控指令

### 檢查索引大小

```bash
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177 \
  "curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?v"
```

### 檢查 429 錯誤

```bash
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177 \
  "docker logs --tail 1000 elastalert2 2>&1 | grep '429' | wc -l"
```

### 查看容器狀態

```bash
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177 \
  "docker ps --filter name=elastalert"
```

### 查看容器資源使用

```bash
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177 \
  "docker stats --no-stream elastalert2"
```

## 🐳 Docker 配置

### Log Rotation

配置文件：`/etc/docker/daemon.json`

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

- **最大 log 大小**: 300MB (100MB × 3 files)
- **自動輪轉**: 防止磁碟溢位

### 重啟服務

```bash
# 重啟容器
cd /opt/elastalert2
docker-compose restart

# 重建容器（套用新配置）
docker-compose down
docker-compose up -d
```

## 🔍 常見任務

### 1. 查看特定遊戲的告警規則

```bash
./scripts/elk/elastalert-menu.sh
# 選擇 4 > 輸入遊戲名稱（如 "crazy-time"）
```

### 2. 檢查規則配置是否正確

```bash
./scripts/elk/check-elastalert-config.sh | grep -A 5 "Realert 間隔分佈"
```

應該顯示：
```
Realert 間隔分佈:
    164   minutes: 5
    120   minutes: 60
      7   minutes: 10
      0   minutes: 0      # 應該是 0！
```

### 3. 修改規則文件

```bash
# SSH 進入主機
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177

# 編輯規則
cd /opt/elastalert2/rules
sudo vim some-rule.yaml

# 重啟容器套用變更
cd /opt/elastalert2
docker-compose restart
```

### 4. 清理告警積壓

```bash
# SSH 進入主機
ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177

# 刪除積壓的告警索引
curl -X DELETE "http://172.31.33.84:9200/elastalert_status*"

# 重啟容器
cd /opt/elastalert2
docker-compose restart
```

## 🚨 故障排除

### 容器無法啟動

**檢查日誌：**
```bash
docker logs elastalert2
```

**常見原因：**
1. 配置文件語法錯誤
2. Elasticsearch 連接失敗
3. 規則文件格式錯誤

### 告警未送達 Slack

**檢查：**
```bash
# 查看最近日誌
docker logs --tail 100 elastalert2

# 搜索錯誤
docker logs elastalert2 2>&1 | grep -i "error\|fail\|429"
```

**常見原因：**
1. Slack webhook URL 錯誤
2. Rate limiting (429 錯誤)
3. 規則 filter 條件不匹配

### 告警積壓過多

**檢查索引大小：**
```bash
curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?v
```

**如果超過 1GB，考慮：**
1. 調整 realert 間隔（增加等待時間）
2. 優化規則 filter（減少匹配數量）
3. 清理積壓告警（參考上面的清理步驟）

## 📚 參考資料

### 官方文檔
- [Elastalert2 文檔](https://elastalert2.readthedocs.io/)
- [Slack Rate Limits](https://api.slack.com/docs/rate-limits)
- [Elasticsearch Query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)

### 內部文檔
- [修復記錄](../../ELASTALERT_FIX_RECORD_20251110.md) - 2025-11-10 故障排除完整記錄

## 📝 變更歷史

- **2025-11-10**: 修復 realert 配置、清理積壓告警、配置 log rotation
- **2026-01-19**: 創建管理工具和文檔

## 🔐 安全注意事項

1. **SSH 密鑰**: 妥善保管 `~/.ssh/hk-devops.pem`，權限必須是 600
2. **Elasticsearch 訪問**: 僅限內網訪問（172.31.33.84）
3. **Slack Webhook**: 不要在規則文件中暴露完整 URL
4. **安全組**: 僅允許必要的 IP 訪問（已配置 61.218.59.85）

## 💡 最佳實踐

1. **修改規則前先備份**
   ```bash
   cp -r /opt/elastalert2/rules /opt/elastalert2/rules.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **測試規則語法**
   ```bash
   docker exec elastalert2 elastalert-test-rule --config /opt/elastalert/config.yaml /opt/elastalert/rules/test-rule.yaml
   ```

3. **定期檢查告警積壓**
   ```bash
   # 加入 crontab，每小時檢查
   0 * * * * curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?h=docs.count | awk '$1 > 1000000 {print "Alert backlog detected"}'
   ```

4. **監控容器狀態**
   ```bash
   # 檢查容器是否正常運行
   docker ps --filter name=elastalert --filter status=running
   ```

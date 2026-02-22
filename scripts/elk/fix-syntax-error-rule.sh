#!/usr/bin/env bash
# 修改 syntax-error.yaml 規則，過濾成功訊息
# 目標: Msg: [SendCustomItem] SendWebApi GetResp: {Error:{Code:0 Message:Success}}

set -euo pipefail

RULE_FILE="syntax-error/syntax-error.yaml"

ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177 << 'ENDSSH'
set -euo pipefail

RULE_FILE="syntax-error/syntax-error.yaml"

cd /opt/elastalert2/rules

echo "========================================"
echo "  修改 Elastalert 規則"
echo "  規則: $RULE_FILE"
echo "========================================"
echo

# 1. 備份
echo "📦 步驟 1: 創建備份..."
BACKUP_FILE="${RULE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
sudo cp "$RULE_FILE" "$BACKUP_FILE"
echo "   ✅ 備份完成: $BACKUP_FILE"
echo

# 2. 查看當前規則
echo "📄 步驟 2: 當前規則內容"
echo "----------------------------------------"
cat "$RULE_FILE"
echo "----------------------------------------"
echo

# 3. 添加過濾條件
echo "🔧 步驟 3: 添加過濾條件..."

# 檢查是否已有 filter
if grep -q "^filter:" "$RULE_FILE"; then
    echo "   檢測到已有 filter 區塊，將添加 NOT 條件..."

    # 在 filter: 下面添加新的過濾條件
    sudo sed -i '/^filter:/a\  - query:\n      query_string:\n        query: '\''NOT (message: "Error:{Code:0 Message:Success}")'\''' "$RULE_FILE"

    echo "   ✅ 已添加到現有 filter 區塊"
else
    echo "   未檢測到 filter 區塊，創建新的..."

    # 在 type: 行之後添加 filter
    sudo sed -i '/^type:/a\filter:\n  - query:\n      query_string:\n        query: '\''NOT (message: "Error:{Code:0 Message:Success}")'\''' "$RULE_FILE"

    echo "   ✅ 已創建新 filter 區塊"
fi
echo

# 4. 顯示修改後的規則
echo "📄 步驟 4: 修改後的規則"
echo "----------------------------------------"
cat "$RULE_FILE"
echo "----------------------------------------"
echo

# 5. 重啟容器
echo "🔄 步驟 5: 重啟 Elastalert 容器..."
cd /opt/elastalert2
docker-compose restart
echo "   ✅ 容器已重啟"
echo

# 6. 等待容器啟動
echo "⏳ 等待容器啟動..."
sleep 5

# 7. 檢查容器狀態
echo "📊 步驟 6: 驗證容器狀態"
echo "----------------------------------------"
docker ps --filter name=elastalert --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo

# 8. 檢查日誌
echo "📝 步驟 7: 檢查最近日誌（確認無錯誤）"
echo "----------------------------------------"
docker logs --tail 30 elastalert2
echo

echo "========================================"
echo "  ✅ 修改完成！"
echo "========================================"
echo
echo "📋 後續步驟:"
echo "   1. 監控日誌確認無錯誤:"
echo "      docker logs -f elastalert2"
echo
echo "   2. 等待觸發，確認成功訊息不再產生告警"
echo
echo "   3. 如需回滾:"
echo "      sudo cp $BACKUP_FILE $RULE_FILE"
echo "      cd /opt/elastalert2 && docker-compose restart"
echo

ENDSSH

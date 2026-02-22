#!/usr/bin/env bash
# Filter success message from Elastalert rules
# Target: Msg: [SendCustomItem] SendWebApi GetResp: {Error:{Code:0 Message:Success}}

set -euo pipefail

USER="ec2-user"
SERVER="18.163.127.177"
KEY="~/.ssh/hk-devops.pem"

echo "========================================"
echo "  過濾成功訊息 - Elastalert 規則修改"
echo "========================================"
echo
echo "目標訊息: Msg: [SendCustomItem] SendWebApi GetResp: {Error:{Code:0 Message:Success}}"
echo

# Function to run remote command
run_remote() {
    ssh -i "$KEY" "$USER@$SERVER" "$@"
}

echo "🔍 步驟 1: 搜索包含 'SendCustomItem' 或 'SendWebApi' 的規則"
echo "----------------------------------------"
rules=$(run_remote "cd /opt/elastalert2/rules && grep -l 'SendCustomItem\|SendWebApi' *.yaml 2>/dev/null || true")

if [[ -z "$rules" ]]; then
    echo "❌ 未找到相關規則，嘗試搜索其他關鍵字..."
    echo
    echo "🔍 搜索包含 'GetResp' 的規則:"
    rules=$(run_remote "cd /opt/elastalert2/rules && grep -l 'GetResp' *.yaml 2>/dev/null || true")
fi

if [[ -z "$rules" ]]; then
    echo "❌ 未找到包含關鍵字的規則"
    echo
    echo "💡 建議: 請提供更多資訊"
    echo "   - 這個訊息是從哪個服務/應用產生的？"
    echo "   - 在 Slack 告警中看到的標題是什麼？"
    echo "   - 規則可能的名稱關鍵字？"
    echo
    echo "📋 顯示前 30 個規則文件供參考:"
    run_remote "ls -1 /opt/elastalert2/rules/ | head -30"
    exit 0
fi

echo "✅ 找到以下規則文件:"
echo "$rules" | nl
echo

# Ask user to select rule
rule_count=$(echo "$rules" | wc -l | tr -d ' ')
if [[ $rule_count -gt 1 ]]; then
    echo -n "請選擇要修改的規則編號 [1-$rule_count]: "
    read -r selection
    rule_file=$(echo "$rules" | sed -n "${selection}p")
else
    rule_file="$rules"
fi

echo
echo "📄 選擇的規則: $rule_file"
echo "----------------------------------------"

echo
echo "🔍 步驟 2: 查看當前規則內容"
echo "----------------------------------------"
run_remote "cat /opt/elastalert2/rules/$rule_file"

echo
echo "========================================"
echo "  建議的過濾方法"
echo "========================================"
echo
echo "方法 1: 使用 query 過濾 (推薦)"
echo "----------------------------------------"
cat << 'EOF'
filter:
  - query:
      query_string:
        query: 'NOT (message: "Error:{Code:0 Message:Success}")'

# 或更精確的過濾
filter:
  - query:
      query_string:
        query: 'NOT (message: "SendCustomItem" AND message: "Code:0" AND message: "Message:Success")'
EOF

echo
echo "方法 2: 使用 blacklist (如果規則使用 any/blacklist type)"
echo "----------------------------------------"
cat << 'EOF'
blacklist:
  - "Error:{Code:0 Message:Success}"
EOF

echo
echo "方法 3: 使用 must_not 在 filter 中"
echo "----------------------------------------"
cat << 'EOF'
filter:
  - bool:
      must_not:
        - match:
            message: "Error:{Code:0 Message:Success}"
EOF

echo
echo "========================================"
echo "  修改步驟"
echo "========================================"
echo
echo "1️⃣ SSH 進入主機:"
echo "   ssh -i ~/.ssh/hk-devops.pem ec2-user@18.163.127.177"
echo
echo "2️⃣ 備份原規則:"
echo "   sudo cp /opt/elastalert2/rules/$rule_file /opt/elastalert2/rules/$rule_file.backup.\$(date +%Y%m%d_%H%M%S)"
echo
echo "3️⃣ 編輯規則:"
echo "   sudo vim /opt/elastalert2/rules/$rule_file"
echo
echo "4️⃣ 添加過濾條件 (在 filter 區塊中):"
echo "   filter:"
echo "     - query:"
echo "         query_string:"
echo "           query: 'NOT (message: \"Error:{Code:0 Message:Success}\")'"
echo
echo "5️⃣ 測試規則語法 (可選):"
echo "   docker exec elastalert2 elastalert-test-rule --config /opt/elastalert/elastalert.yaml /opt/elastalert/rules/$rule_file"
echo
echo "6️⃣ 重啟容器套用變更:"
echo "   cd /opt/elastalert2 && docker-compose restart"
echo
echo "7️⃣ 驗證修改:"
echo "   docker logs --tail 100 elastalert2"
echo

echo "========================================"
echo "  自動化修改選項"
echo "========================================"
echo
echo "是否要自動添加過濾規則？"
echo "警告: 這會修改規則文件，請確保已了解影響"
echo -n "[y/N]: "
read -r auto_modify

if [[ "$auto_modify" =~ ^[Yy]$ ]]; then
    echo
    echo "🔧 執行自動修改..."

    # Create backup
    echo "1. 創建備份..."
    backup_name="${rule_file}.backup.$(date +%Y%m%d_%H%M%S)"
    run_remote "sudo cp /opt/elastalert2/rules/$rule_file /opt/elastalert2/rules/$backup_name"
    echo "   ✅ 備份完成: $backup_name"

    # Add filter
    echo "2. 添加過濾規則..."

    # Check if filter section exists
    has_filter=$(run_remote "grep -c '^filter:' /opt/elastalert2/rules/$rule_file || true")

    if [[ "$has_filter" -gt 0 ]]; then
        echo "   ℹ️  檢測到現有 filter 區塊，將添加 NOT 條件"

        # Add to existing filter
        run_remote "sudo sed -i '/^filter:/a\  - query:\n      query_string:\n        query: '\''NOT (message: \"Error:{Code:0 Message:Success}\")'\''' /opt/elastalert2/rules/$rule_file"
    else
        echo "   ℹ️  未檢測到 filter 區塊，將創建新的"

        # Add new filter section after type
        run_remote "sudo sed -i '/^type:/a\filter:\n  - query:\n      query_string:\n        query: '\''NOT (message: \"Error:{Code:0 Message:Success}\")'\''' /opt/elastalert2/rules/$rule_file"
    fi

    echo "   ✅ 過濾規則已添加"

    # Show modified rule
    echo
    echo "3. 查看修改後的規則:"
    echo "----------------------------------------"
    run_remote "cat /opt/elastalert2/rules/$rule_file"

    # Restart container
    echo
    echo "4. 重啟 Elastalert 容器..."
    run_remote "cd /opt/elastalert2 && docker-compose restart"
    echo "   ✅ 容器已重啟"

    # Verify
    echo
    echo "5. 驗證容器狀態..."
    sleep 3
    run_remote "docker ps --filter name=elastalert --format 'table {{.Names}}\t{{.Status}}'"

    echo
    echo "✅ 修改完成！"
    echo
    echo "📝 後續步驟:"
    echo "   - 監控日誌確認無錯誤: docker logs -f elastalert2"
    echo "   - 等待下次觸發，確認不再產生告警"
    echo "   - 如需回滾: sudo cp /opt/elastalert2/rules/$backup_name /opt/elastalert2/rules/$rule_file"
else
    echo
    echo "ℹ️  已取消自動修改，請手動執行上述步驟"
fi

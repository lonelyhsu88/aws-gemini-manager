#!/bin/bash

# 完整測試：遊戲加載 + MTR + API 測速
# 三個區域：東京、孟買、新加坡

set -e

INSTANCE_TYPE="t3.small"  # 使用稍大的實例以運行 Puppeteer
KEY_NAME="complete-test-key"

echo "=============================================="
echo "完整性能測試：東京 vs 孟買 vs 新加坡"
echo "測試項目："
echo "  1. 遊戲加載速度（5個遊戲）"
echo "  2. MTR 網路路徑追蹤"
echo "  3. API 延遲測試"
echo "=============================================="
echo ""

# 獲取本機 IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "本機 IP: $MY_IP"
echo ""

# 為每個區域創建密鑰對
create_key_in_region() {
    local REGION=$1
    local KEY_FILE=~/.ssh/${KEY_NAME}-${REGION}.pem

    if [ ! -f "$KEY_FILE" ]; then
        echo "創建 $REGION 的密鑰對..."
        aws --profile gemini-pro_ck ec2 create-key-pair \
            --region "$REGION" \
            --key-name "${KEY_NAME}-${REGION}" \
            --query 'KeyMaterial' \
            --output text > "$KEY_FILE" 2>/dev/null || {
            echo "密鑰對可能已存在於 $REGION"
            return 1
        }
        chmod 400 "$KEY_FILE"
        echo "已保存: $KEY_FILE"
    else
        echo "使用現有密鑰: $KEY_FILE"
    fi
}

echo "準備 SSH 密鑰..."
create_key_in_region "ap-northeast-1"
create_key_in_region "ap-south-1"
create_key_in_region "ap-southeast-1"

echo ""

# 先在本地獲取遊戲 URL
echo "======================================"
echo "步驟 1: 獲取遊戲 URL（本地執行）"
echo "======================================"

if [ ! -f "./fetch-game-urls.sh" ]; then
    echo "錯誤: fetch-game-urls.sh 不存在"
    echo "請確保在 scripts/ec2 目錄下執行"
    exit 1
fi

if [ ! -f "game-urls-list.txt" ]; then
    echo "執行 fetch-game-urls.sh..."
    bash ./fetch-game-urls.sh
else
    echo "使用現有的 game-urls-list.txt"
fi

echo ""

# 創建遠端測試腳本
create_test_scripts() {
    # API 測試腳本
    cat > test-api.sh <<'EOF'
#!/bin/bash
echo "=== API 延遲測試 ==="
echo "測試時間: $(date)"
echo ""

API1="https://ds-r.geminiservice.cc/domains?type=Hash"
API2="https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"

for api in "$API1" "$API2"; do
  echo "測試: $api"
  total=0
  for i in {1..5}; do
    time=$(curl -w "%{time_total}" -o /dev/null -s "$api" 2>/dev/null)
    echo "  第 $i 次: ${time}s"
    total=$(awk "BEGIN {print $total + $time}")
  done
  avg=$(awk "BEGIN {print $total / 5}")
  echo "  平均: ${avg}s"
  echo ""
done
EOF

    # MTR 測試腳本
    cat > test-mtr.sh <<'EOF'
#!/bin/bash
echo "=== MTR 網路路徑測試 ==="
echo "測試時間: $(date)"
echo ""

TARGETS=(
  "a23-55-244-43.deploy.static.akamaitechnologies.com"
  "ds-r.geminiservice.cc.edgesuite.net"
  "gameinfo-api.geminiservice.cc.edgesuite.net"
)

for target in "${TARGETS[@]}"; do
  echo "======================================"
  echo "目標: $target"
  echo "======================================"
  sudo mtr --report --report-cycles 30 --no-dns "$target"
  echo ""
done
EOF

    # 遊戲測試腳本（使用預先獲取的 URL）
    cat > test-games.sh <<'EOF'
#!/bin/bash
echo "=== 遊戲加載速度測試 ==="
echo "測試時間: $(date)"
echo ""

GAME_URLS_FILE="game-urls-list.txt"

if [ ! -f "$GAME_URLS_FILE" ]; then
    echo "錯誤: $GAME_URLS_FILE 不存在"
    exit 1
fi

# 讀取前5個遊戲
mapfile -t GAME_LINES < <(head -5 "$GAME_URLS_FILE")

RESULTS_DIR="game-test-results-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

for line in "${GAME_LINES[@]}"; do
    game_name=$(echo "$line" | cut -d'|' -f1)
    game_url=$(echo "$line" | cut -d'|' -f2)

    echo "測試遊戲: $game_name"
    echo "URL: $game_url"

    # 執行兩次訪問測試
    OUTPUT_JSON="$RESULTS_DIR/${game_name}_result.json"

    node puppeteer_game_test.js "$game_url" \
        --cache \
        --double-visit \
        --wait=30000 \
        --output="$OUTPUT_JSON" 2>&1 | tee "$RESULTS_DIR/${game_name}_log.txt"

    echo ""
done

# 生成摘要
echo "======================================"
echo "測試摘要"
echo "======================================"

total_first=0
total_second=0
count=0

for json_file in $RESULTS_DIR/*_result.json; do
    if [ -f "$json_file" ]; then
        game=$(basename "$json_file" | sed 's/_result.json//')
        first=$(jq -r '.visits[0].metrics.totalTime // "N/A"' "$json_file" 2>/dev/null)
        second=$(jq -r '.visits[1].metrics.totalTime // "N/A"' "$json_file" 2>/dev/null)

        echo "遊戲: $game"
        echo "  首次: ${first}s"
        echo "  第二次: ${second}s"

        if [ "$first" != "N/A" ] && [ "$second" != "N/A" ]; then
            total_first=$(awk "BEGIN {print $total_first + $first}")
            total_second=$(awk "BEGIN {print $total_second + $second}")
            count=$((count + 1))
        fi
    fi
done

if [ $count -gt 0 ]; then
    avg_first=$(awk "BEGIN {print $total_first / $count}")
    avg_second=$(awk "BEGIN {print $total_second / $count}")
    improvement=$(awk "BEGIN {print (($avg_first - $avg_second) / $avg_first) * 100}")

    echo ""
    echo "平均結果:"
    echo "  首次訪問: ${avg_first}s"
    echo "  第二次訪問: ${avg_second}s"
    echo "  改善: ${improvement}%"
fi
EOF

    chmod +x test-api.sh test-mtr.sh test-games.sh
}

create_test_scripts

# 函數：部署並執行完整測試
deploy_and_test() {
    local LOCATION=$1
    local REGION=$2
    local AMI=$3
    local NAME=$4

    echo ""
    echo "=============================================="
    echo "部署並測試: $NAME ($REGION)"
    echo "=============================================="

    # 創建安全組
    SG_NAME="complete-test-sg-${LOCATION}"
    SG_ID=$(aws --profile gemini-pro_ck ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SG_NAME" \
        --description "Complete test SG" \
        --query 'GroupId' \
        --output text 2>/dev/null || \
        aws --profile gemini-pro_ck ec2 describe-security-groups \
            --region "$REGION" \
            --group-names "$SG_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)

    echo "安全組 ID: $SG_ID"

    # 添加 SSH 規則
    aws --profile gemini-pro_ck ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${MY_IP}/32" 2>/dev/null || true

    # User Data - 安裝所有需要的工具
    USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

# 更新系統
apt-get update

# 安裝基礎工具
apt-get install -y curl bc dnsutils mtr-tiny

# 安裝 Node.js 和 npm
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# 安裝 Chromium 和依賴
apt-get install -y chromium-browser chromium-chromedriver
apt-get install -y libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 \
  libxi6 libxtst6 libnss3 libcups2 libxss1 libxrandr2 libasound2 \
  libpangocairo-1.0-0 libatk1.0-0 libatk-bridge2.0-0 libgtk-3-0

# 安裝 Puppeteer（全局）
npm install -g puppeteer --unsafe-perm=true --allow-root

# 安裝 jq 用於 JSON 處理
apt-get install -y jq

echo "Setup complete"
USERDATA
)

    # 使用區域特定的密鑰
    REGION_KEY_NAME="${KEY_NAME}-${REGION}"
    REGION_KEY_FILE=~/.ssh/${REGION_KEY_NAME}.pem

    # 啟動實例
    echo "啟動 EC2 實例..."
    INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$REGION_KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=complete-test-${LOCATION}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "實例 ID: $INSTANCE_ID"
    echo "等待實例啟動..."

    aws --profile gemini-pro_ck ec2 wait instance-running \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"

    PUBLIC_IP=$(aws --profile gemini-pro_ck ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo "公共 IP: $PUBLIC_IP"
    echo "等待 SSH 就緒..."

    for i in {1..36}; do
        if ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} "echo ready" 2>/dev/null; then
            break
        fi
        sleep 5
    done

    echo "等待軟體安裝完成..."
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "cloud-init status --wait" 2>/dev/null || true

    # 確認安裝
    echo "確認環境..."
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "
        echo 'Node.js version:' && node --version
        echo 'Puppeteer installed:' && npm list -g puppeteer
        echo 'MTR installed:' && mtr --version
        echo 'jq installed:' && jq --version
    "

    # 上傳所有測試腳本和數據
    echo "上傳測試腳本和數據..."
    scp -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
        test-api.sh test-mtr.sh test-games.sh \
        game-urls-list.txt \
        ubuntu@${PUBLIC_IP}:~/

    # 上傳 Puppeteer 測試腳本（從工具包目錄）
    if [ -f "/Users/lonelyhsu/gemini/toolkits/game_login/game-test/puppeteer_game_test.js" ]; then
        scp -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
            /Users/lonelyhsu/gemini/toolkits/game_login/game-test/puppeteer_game_test.js \
            ubuntu@${PUBLIC_IP}:~/
    else
        echo "警告: puppeteer_game_test.js 未找到"
    fi

    # 創建結果目錄
    RESULT_DIR="${LOCATION}-complete-results-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$RESULT_DIR"

    # 執行測試 1: API 測速
    echo ""
    echo "======================================"
    echo "執行 API 測速..."
    echo "======================================"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "bash test-api.sh" | tee "$RESULT_DIR/api-results.txt"

    # 執行測試 2: MTR 網路追蹤
    echo ""
    echo "======================================"
    echo "執行 MTR 網路追蹤..."
    echo "======================================"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "bash test-mtr.sh" | tee "$RESULT_DIR/mtr-results.txt"

    # 執行測試 3: 遊戲加載測試
    echo ""
    echo "======================================"
    echo "執行遊戲加載測試（這可能需要幾分鐘）..."
    echo "======================================"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "bash test-games.sh" | tee "$RESULT_DIR/game-results.txt"

    # 下載遊戲測試詳細結果
    echo "下載測試結果..."
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "ls -dt game-test-results-* | head -1" | xargs -I {} \
        scp -r -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
        ubuntu@${PUBLIC_IP}:~/{} "$RESULT_DIR/" 2>/dev/null || echo "無遊戲詳細結果"

    echo ""
    echo "======================================"
    echo "$NAME 測試完成！"
    echo "結果保存在: $RESULT_DIR"
    echo "======================================"
    echo ""

    # 返回實例信息
    echo "$LOCATION|$REGION|$INSTANCE_ID|$PUBLIC_IP|$RESULT_DIR"
}

# 執行三個區域的測試（並行）
echo ""
echo "======================================"
echo "開始完整測試（三個區域並行執行）..."
echo "======================================"

# 創建臨時文件存儲結果
TOKYO_RESULT_FILE=$(mktemp)
MUMBAI_RESULT_FILE=$(mktemp)
SINGAPORE_RESULT_FILE=$(mktemp)

# 並行執行三個區域的測試
deploy_and_test "tokyo" "ap-northeast-1" "ami-0d52744d6551d851e" "東京" > "$TOKYO_RESULT_FILE" &
TOKYO_PID=$!

deploy_and_test "mumbai" "ap-south-1" "ami-0c2af51e265bd5e0e" "孟買" > "$MUMBAI_RESULT_FILE" &
MUMBAI_PID=$!

deploy_and_test "singapore" "ap-southeast-1" "ami-0497a974f8d5dcef8" "新加坡" > "$SINGAPORE_RESULT_FILE" &
SINGAPORE_PID=$!

echo "三個區域正在並行測試..."
echo "  - 東京 (PID: $TOKYO_PID)"
echo "  - 孟買 (PID: $MUMBAI_PID)"
echo "  - 新加坡 (PID: $SINGAPORE_PID)"
echo ""
echo "請等待所有測試完成（預計 15-20 分鐘）..."

# 等待所有測試完成
wait $TOKYO_PID
echo "✅ 東京測試完成"

wait $MUMBAI_PID
echo "✅ 孟買測試完成"

wait $SINGAPORE_PID
echo "✅ 新加坡測試完成"

echo ""
echo "所有區域測試完成！"
echo ""

# 讀取結果
TOKYO_INFO=$(tail -1 "$TOKYO_RESULT_FILE")
MUMBAI_INFO=$(tail -1 "$MUMBAI_RESULT_FILE")
SINGAPORE_INFO=$(tail -1 "$SINGAPORE_RESULT_FILE")

# 顯示測試輸出
echo "======================================"
echo "東京測試輸出:"
echo "======================================"
cat "$TOKYO_RESULT_FILE"
echo ""

echo "======================================"
echo "孟買測試輸出:"
echo "======================================"
cat "$MUMBAI_RESULT_FILE"
echo ""

echo "======================================"
echo "新加坡測試輸出:"
echo "======================================"
cat "$SINGAPORE_RESULT_FILE"
echo ""

# 清理臨時文件
rm -f "$TOKYO_RESULT_FILE" "$MUMBAI_RESULT_FILE" "$SINGAPORE_RESULT_FILE"

# 解析信息
TOKYO_INSTANCE_ID=$(echo "$TOKYO_INFO" | cut -d'|' -f3)
TOKYO_RESULT_DIR=$(echo "$TOKYO_INFO" | cut -d'|' -f5)

MUMBAI_INSTANCE_ID=$(echo "$MUMBAI_INFO" | cut -d'|' -f3)
MUMBAI_RESULT_DIR=$(echo "$MUMBAI_INFO" | cut -d'|' -f5)

SINGAPORE_INSTANCE_ID=$(echo "$SINGAPORE_INFO" | cut -d'|' -f3)
SINGAPORE_RESULT_DIR=$(echo "$SINGAPORE_INFO" | cut -d'|' -f5)

# 生成綜合報告
FINAL_REPORT="complete-comparison-report-$(date +%Y%m%d_%H%M%S).md"

cat > "$FINAL_REPORT" <<EOF
# 完整性能測試報告：東京 vs 孟買 vs 新加坡

**測試時間**: $(date)
**測試項目**:
1. 遊戲加載速度（5個遊戲，雙次訪問）
2. MTR 網路路徑追蹤（3個目標）
3. API 延遲測試（2個 API，各5次）

---

## 📊 測試結果總覽

### 1. API 延遲測試

#### API 1: ds-r.geminiservice.cc/domains

| 位置 | 平均延遲 | 相對新加坡 |
|------|---------|-----------|
| 新加坡 | $(grep -A 7 "ds-r.geminiservice.cc/domains" "$SINGAPORE_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | 基準 |
| 東京 | $(grep -A 7 "ds-r.geminiservice.cc/domains" "$TOKYO_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | - |
| 孟買 | $(grep -A 7 "ds-r.geminiservice.cc/domains" "$MUMBAI_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | - |

#### API 2: gameinfo-api.geminiservice.cc

| 位置 | 平均延遲 | 相對新加坡 |
|------|---------|-----------|
| 新加坡 | $(grep -A 7 "gameinfo-api.geminiservice.cc" "$SINGAPORE_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | 基準 |
| 東京 | $(grep -A 7 "gameinfo-api.geminiservice.cc" "$TOKYO_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | - |
| 孟買 | $(grep -A 7 "gameinfo-api.geminiservice.cc" "$MUMBAI_RESULT_DIR/api-results.txt" 2>/dev/null | grep "平均" | awk '{print $2}' || echo "N/A") | - |

---

### 2. 遊戲加載測試

#### 平均加載時間

| 位置 | 首次訪問 | 第二次訪問 | 改善% | 狀態 |
|------|---------|-----------|-------|------|
| 新加坡 | - | - | - | - |
| 東京 | - | - | - | - |
| 孟買 | - | - | - | - |

*詳細數據請查看各區域結果目錄*

---

### 3. MTR 網路路徑

#### 最終節點延遲

| 位置 | 靜態資源 CDN | 域名 API CDN | 遊戲信息 API CDN |
|------|-------------|-------------|----------------|
| 新加坡 | - | - | - |
| 東京 | - | - | - |
| 孟買 | - | - | - |

*詳細路徑請查看 mtr-results.txt*

---

## 📁 詳細結果目錄

### 東京
- 目錄: \`$TOKYO_RESULT_DIR\`
- API 測試: \`$TOKYO_RESULT_DIR/api-results.txt\`
- MTR 測試: \`$TOKYO_RESULT_DIR/mtr-results.txt\`
- 遊戲測試: \`$TOKYO_RESULT_DIR/game-results.txt\`

### 孟買
- 目錄: \`$MUMBAI_RESULT_DIR\`
- API 測試: \`$MUMBAI_RESULT_DIR/api-results.txt\`
- MTR 測試: \`$MUMBAI_RESULT_DIR/mtr-results.txt\`
- 遊戲測試: \`$MUMBAI_RESULT_DIR/game-results.txt\`

### 新加坡
- 目錄: \`$SINGAPORE_RESULT_DIR\`
- API 測試: \`$SINGAPORE_RESULT_DIR/api-results.txt\`
- MTR 測試: \`$SINGAPORE_RESULT_DIR/mtr-results.txt\`
- 遊戲測試: \`$SINGAPORE_RESULT_DIR/game-results.txt\`

---

## 💡 優化建議

### 基於測試結果的建議

1. **API 緩存**: 啟用 \`Cache-Control: public, max-age=300\`
2. **區域路由**: 亞洲用戶優先路由到新加坡
3. **CDN 配置**: 確認所有 API 都啟用 CDN 緩存

---

**報告生成時間**: $(date)
**測試工具**: Puppeteer, MTR, curl
**AWS 區域**: ap-northeast-1, ap-south-1, ap-southeast-1
EOF

echo ""
echo "=============================================="
echo "所有測試完成！"
echo "=============================================="
echo ""
echo "綜合報告: $FINAL_REPORT"
echo ""
cat "$FINAL_REPORT"

echo ""
echo "======================================"
echo "清理資源"
echo "======================================"

read -p "是否終止所有實例? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "終止東京實例..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-northeast-1 --instance-ids "$TOKYO_INSTANCE_ID"

    echo "終止孟買實例..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-south-1 --instance-ids "$MUMBAI_INSTANCE_ID"

    echo "終止新加坡實例..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-southeast-1 --instance-ids "$SINGAPORE_INSTANCE_ID"

    echo "所有實例已終止"
else
    echo "保留實例，請手動清理:"
    echo "  東京: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-northeast-1 --instance-ids $TOKYO_INSTANCE_ID"
    echo "  孟買: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-south-1 --instance-ids $MUMBAI_INSTANCE_ID"
    echo "  新加坡: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-southeast-1 --instance-ids $SINGAPORE_INSTANCE_ID"
fi

echo ""
echo "完成！"
echo ""
echo "結果摘要:"
echo "  - 東京結果: $TOKYO_RESULT_DIR"
echo "  - 孟買結果: $MUMBAI_RESULT_DIR"
echo "  - 新加坡結果: $SINGAPORE_RESULT_DIR"
echo "  - 綜合報告: $FINAL_REPORT"

# 清理本地腳本
rm -f test-api.sh test-mtr.sh test-games.sh

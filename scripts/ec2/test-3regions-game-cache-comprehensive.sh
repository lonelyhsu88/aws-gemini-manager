#!/bin/bash

################################################################################
# 三地區綜合測試：遊戲緩存對比 + API 延遲 + MTR 網路追蹤
# 地區：東京、孟買、新加坡
#
# 測試流程：
# 1. 本地獲取遊戲 URLs（避免重複 API 調用）
# 2. 並行部署三個區域的 EC2 實例
# 3. 每個實例執行：
#    - 遊戲緩存對比測試（雙重訪問）
#    - API 延遲測試
#    - MTR 網路路徑追蹤
# 4. 收集結果並生成綜合報告
################################################################################

set -e

# 配置
NUM_GAMES="${1:-5}"
WAIT_TIME="${2:-15000}"
INSTANCE_TYPE="t3.medium"  # 使用稍大的實例以運行 Puppeteer
KEY_NAME="3region-test-key"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║     三地區綜合性能測試：遊戲緩存 + API 延遲 + MTR 追蹤             ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${CYAN}測試配置:${NC}"
echo "  • 測試遊戲數量: $NUM_GAMES"
echo "  • 頁面等待時間: $WAIT_TIME ms"
echo "  • EC2 實例類型: $INSTANCE_TYPE"
echo "  • 測試地區: 東京、孟買、新加坡"
echo ""
echo -e "${CYAN}測試項目:${NC}"
echo "  1. 遊戲緩存對比測試（首次訪問 vs 第二次訪問）"
echo "  2. API 延遲測試（3個主要 API）"
echo "  3. MTR 網路路徑追蹤（4個目標）"
echo ""

# 獲取本機 IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo -e "${CYAN}本機 IP:${NC} $MY_IP"
echo ""

################################################################################
# 步驟 1: 本地獲取遊戲 URLs
################################################################################

echo "════════════════════════════════════════════════════════════════"
echo "步驟 1: 本地獲取遊戲 URLs（避免在每個 EC2 重複調用 API）"
echo "════════════════════════════════════════════════════════════════"
echo ""

# API 配置
API_URL="https://wallet-api.geminiservice.cc/api/v1/operator/game/launch"
USERNAME="optest01"
PRODUCT_ID="ELS"
LANG="zh-CN"

# 可用遊戲列表
ALL_GAMES=(
    "ArcadeBingo"
    "BonusBingo"
    "CaribbeanBingo"
    "MagicBingo"
    "MultiPlayerAviator"
    "MultiPlayerCrash"
    "StandAlonePlinko"
    "StandAloneMines"
    "StandAloneDice"
    "StandAloneHilo"
)

# MD5 hash 函數
get_md5() {
    local input="$1"
    if command -v md5 &> /dev/null; then
        echo -n "$input" | md5 -q
    else
        echo -n "$input" | md5sum | cut -d' ' -f1
    fi
}

# 獲取遊戲 URL
get_game_url() {
    local game="$1"
    local seq="$(date +%s)$(( RANDOM % 1000 ))"
    local payload="{\"seq\":\"$seq\",\"product_id\":\"$PRODUCT_ID\",\"username\":\"$USERNAME\",\"gametype\":\"$game\",\"lang\":\"$LANG\"}"
    local md5_hash=$(get_md5 "xdr56yhn${payload}")

    local response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "els-access-key: $md5_hash" \
        -d "$payload")

    local url=$(echo "$response" | grep -o '"url":"[^"]*"' | sed 's/"url":"//;s/"$//' | sed 's/\\u0026/\&/g')
    echo "$url" | sed 's|jump.shuangzi6666.com|www.shuangzi6688.com|'
}

# 隨機選擇遊戲
echo -e "${YELLOW}隨機選擇 $NUM_GAMES 個遊戲...${NC}"
SELECTED_GAMES=()
TEMP_GAMES=("${ALL_GAMES[@]}")

for ((i=0; i<NUM_GAMES && i<${#ALL_GAMES[@]}; i++)); do
    idx=$(( RANDOM % ${#TEMP_GAMES[@]} ))
    SELECTED_GAMES+=("${TEMP_GAMES[$idx]}")
    TEMP_GAMES=("${TEMP_GAMES[@]:0:$idx}" "${TEMP_GAMES[@]:$((idx+1))}")
done

echo -e "${GREEN}✓${NC} 已選擇遊戲:"
for ((i=0; i<${#SELECTED_GAMES[@]}; i++)); do
    echo "  $((i+1)). ${SELECTED_GAMES[$i]}"
done
echo ""

# 獲取 URLs
echo -e "${YELLOW}獲取遊戲 URLs...${NC}"
GAME_URLS_FILE="game-urls-$(date +%Y%m%d_%H%M%S).txt"
> "$GAME_URLS_FILE"

GAME_COUNT=0
for game in "${SELECTED_GAMES[@]}"; do
    echo -n "  獲取 $game..."
    url=$(get_game_url "$game")

    if [ -n "$url" ]; then
        echo "$game|$url" >> "$GAME_URLS_FILE"
        echo -e " ${GREEN}✓${NC}"
        ((GAME_COUNT++))
    else
        echo -e " ${RED}✗${NC}"
    fi
    sleep 1
done

echo ""
echo -e "${GREEN}✓${NC} 成功獲取 $GAME_COUNT 個遊戲 URL"
echo -e "${CYAN}URL 列表文件:${NC} $GAME_URLS_FILE"
echo ""

if [ $GAME_COUNT -eq 0 ]; then
    echo -e "${RED}錯誤: 沒有獲取到任何遊戲 URL${NC}"
    exit 1
fi

################################################################################
# 步驟 2: 準備測試腳本和密鑰
################################################################################

echo "════════════════════════════════════════════════════════════════"
echo "步驟 2: 準備測試腳本和 SSH 密鑰"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 為每個區域創建密鑰對
create_key_in_region() {
    local REGION=$1
    local KEY_FILE=~/.ssh/${KEY_NAME}-${REGION}.pem

    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${YELLOW}創建 $REGION 的密鑰對...${NC}"
        aws --profile gemini-pro_ck ec2 create-key-pair \
            --region "$REGION" \
            --key-name "${KEY_NAME}-${REGION}" \
            --query 'KeyMaterial' \
            --output text > "$KEY_FILE" 2>/dev/null || {
            echo -e "${YELLOW}密鑰對可能已存在於 $REGION${NC}"
            return 1
        }
        chmod 400 "$KEY_FILE"
        echo -e "${GREEN}✓${NC} 已保存: $KEY_FILE"
    else
        echo -e "${GREEN}✓${NC} 使用現有密鑰: $KEY_FILE"
    fi
}

echo -e "${YELLOW}準備 SSH 密鑰...${NC}"
create_key_in_region "ap-northeast-1"
create_key_in_region "ap-south-1"
create_key_in_region "ap-southeast-1"
echo ""

# 檢查必要的腳本
echo -e "${YELLOW}檢查測試腳本...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/remote-game-url-test.sh" ]; then
    echo -e "${RED}錯誤: remote-game-url-test.sh 不存在${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/remote-api-mtr-test.sh" ]; then
    echo -e "${RED}錯誤: remote-api-mtr-test.sh 不存在${NC}"
    exit 1
fi

# 檢查 Puppeteer 測試腳本
PUPPETEER_SCRIPT="/Users/lonelyhsu/gemini/toolkits/game_login/game-test/puppeteer_game_test.js"
if [ ! -f "$PUPPETEER_SCRIPT" ]; then
    echo -e "${RED}錯誤: puppeteer_game_test.js 不存在${NC}"
    echo "  預期位置: $PUPPETEER_SCRIPT"
    exit 1
fi

echo -e "${GREEN}✓${NC} 所有測試腳本就緒"
echo ""

################################################################################
# 步驟 3: 部署並測試函數（單一區域）
################################################################################

deploy_and_test() {
    local LOCATION=$1
    local REGION=$2
    local AMI=$3
    local NAME=$4

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "${BLUE}部署並測試: $NAME ($REGION)${NC}"
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    # 創建安全組
    SG_NAME="3region-test-sg-${LOCATION}"
    echo -e "${YELLOW}創建安全組...${NC}"
    SG_ID=$(aws --profile gemini-pro_ck ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SG_NAME" \
        --description "3-Region comprehensive test SG" \
        --query 'GroupId' \
        --output text 2>/dev/null || \
        aws --profile gemini-pro_ck ec2 describe-security-groups \
            --region "$REGION" \
            --group-names "$SG_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)

    echo -e "${GREEN}✓${NC} 安全組 ID: $SG_ID"

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
set -xe

apt-get update
apt-get install -y curl bc dnsutils mtr-tiny jq

# 安裝 Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# 安裝 Chromium 和所有依賴
apt-get install -y chromium-browser \
  libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 \
  libxi6 libxtst6 libnss3 libcups2 libxss1 libxrandr2 libasound2 \
  libpangocairo-1.0-0 libatk1.0-0 libatk-bridge2.0-0 libgtk-3-0 libgbm1

# 在 ubuntu 用戶目錄下本地安裝 Puppeteer（增加超時和重試）
echo "Installing Puppeteer..."
su - ubuntu -c "cd ~ && npm install puppeteer --unsafe-perm=true --timeout=300000"

# 驗證 Puppeteer 安裝
echo "Verifying Puppeteer installation..."
if su - ubuntu -c "node -e \"require('puppeteer')\" && echo 'Puppeteer OK'"; then
    echo "Puppeteer installation verified successfully"
    echo "done" > /tmp/cloud-init-done
else
    echo "Puppeteer installation failed!" >&2
    exit 1
fi

echo "Setup complete"
USERDATA
)

    REGION_KEY_NAME="${KEY_NAME}-${REGION}"
    REGION_KEY_FILE=~/.ssh/${REGION_KEY_NAME}.pem

    # 啟動實例
    echo -e "${YELLOW}啟動 EC2 實例...${NC}"
    INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$REGION_KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=3region-test-${LOCATION}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo -e "${GREEN}✓${NC} 實例 ID: $INSTANCE_ID"

    echo -e "${YELLOW}等待實例啟動...${NC}"
    aws --profile gemini-pro_ck ec2 wait instance-running \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"

    PUBLIC_IP=$(aws --profile gemini-pro_ck ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo -e "${GREEN}✓${NC} 公共 IP: $PUBLIC_IP"

    echo -e "${YELLOW}等待 SSH 就緒...${NC}"
    for i in {1..40}; do
        if ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} "echo ready" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} SSH 已就緒"
            break
        fi
        sleep 5
    done

    echo -e "${YELLOW}等待軟體安裝完成...${NC}"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "cloud-init status --wait" 2>/dev/null || true

    # 驗證 Puppeteer 是否安裝成功
    echo -e "${YELLOW}驗證 Puppeteer 安裝...${NC}"
    PUPPETEER_CHECK=$(ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "node -e \"require('puppeteer')\" && echo 'OK'" 2>/dev/null || echo "FAILED")

    if [ "$PUPPETEER_CHECK" != "OK" ]; then
        echo -e "${RED}✗ Puppeteer 未安裝，手動安裝中...${NC}"
        ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
            "cd ~ && npm install puppeteer --unsafe-perm=true --timeout=300000"

        # 再次驗證
        PUPPETEER_CHECK=$(ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
            "node -e \"require('puppeteer')\" && echo 'OK'" 2>/dev/null || echo "FAILED")

        if [ "$PUPPETEER_CHECK" != "OK" ]; then
            echo -e "${RED}✗ Puppeteer 安裝失敗，跳過此區域${NC}"
            return 1
        fi
    fi
    echo -e "${GREEN}✓${NC} Puppeteer 已安裝並驗證"

    echo -e "${YELLOW}上傳測試腳本和數據...${NC}"
    scp -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR/remote-game-url-test.sh" \
        "$SCRIPT_DIR/remote-api-mtr-test.sh" \
        "$GAME_URLS_FILE" \
        "$PUPPETEER_SCRIPT" \
        ubuntu@${PUBLIC_IP}:~/

    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "mv game-urls-*.txt game-urls.txt && chmod +x *.sh"

    echo -e "${GREEN}✓${NC} 上傳完成"

    # 創建結果目錄
    RESULT_DIR="${LOCATION}-results-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$RESULT_DIR"

    # 執行測試
    echo ""
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo -e "${CYAN}開始執行測試: $NAME${NC}"
    echo -e "${CYAN}══════════════════════════════════════${NC}"
    echo ""

    # 測試 1: 遊戲緩存對比
    echo -e "${BLUE}[測試 1/2] 遊戲緩存對比測試${NC}"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "bash remote-game-url-test.sh $WAIT_TIME game-urls.txt" | tee "$RESULT_DIR/game-test.log"

    # 測試 2: API + MTR
    echo ""
    echo -e "${BLUE}[測試 2/2] API 延遲 + MTR 網路追蹤${NC}"
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "bash remote-api-mtr-test.sh" | tee "$RESULT_DIR/api-mtr-test.log"

    # 下載結果
    echo ""
    echo -e "${YELLOW}下載測試結果...${NC}"

    # 獲取遊戲測試結果目錄
    GAME_RESULTS_DIR=$(ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "ls -dt game-cache-test-* 2>/dev/null | head -1" || echo "")

    if [ -n "$GAME_RESULTS_DIR" ]; then
        scp -r -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
            ubuntu@${PUBLIC_IP}:~/${GAME_RESULTS_DIR} "$RESULT_DIR/" 2>/dev/null || true
    fi

    # 獲取 API/MTR 測試結果目錄
    API_RESULTS_DIR=$(ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} \
        "ls -dt api-mtr-test-* 2>/dev/null | head -1" || echo "")

    if [ -n "$API_RESULTS_DIR" ]; then
        scp -r -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no \
            ubuntu@${PUBLIC_IP}:~/${API_RESULTS_DIR} "$RESULT_DIR/" 2>/dev/null || true
    fi

    echo -e "${GREEN}✓${NC} 結果已下載到: $RESULT_DIR"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}$NAME 測試完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""

    # 返回實例信息
    echo "$LOCATION|$REGION|$INSTANCE_ID|$PUBLIC_IP|$RESULT_DIR"
}

################################################################################
# 步驟 4: 並行執行三個區域的測試
################################################################################

echo "════════════════════════════════════════════════════════════════"
echo "步驟 3: 並行部署並測試三個區域"
echo "════════════════════════════════════════════════════════════════"
echo ""

# 創建臨時文件存儲結果
TOKYO_RESULT_FILE=$(mktemp)
MUMBAI_RESULT_FILE=$(mktemp)
SINGAPORE_RESULT_FILE=$(mktemp)

# 並行執行
echo -e "${CYAN}並行啟動三個區域的測試...${NC}"
echo ""

deploy_and_test "tokyo" "ap-northeast-1" "ami-0d52744d6551d851e" "東京" > "$TOKYO_RESULT_FILE" 2>&1 &
TOKYO_PID=$!

deploy_and_test "mumbai" "ap-south-1" "ami-0c2af51e265bd5e0e" "孟買" > "$MUMBAI_RESULT_FILE" 2>&1 &
MUMBAI_PID=$!

deploy_and_test "singapore" "ap-southeast-1" "ami-0497a974f8d5dcef8" "新加坡" > "$SINGAPORE_RESULT_FILE" 2>&1 &
SINGAPORE_PID=$!

echo -e "${YELLOW}三個區域正在並行測試...${NC}"
echo "  • 東京 (PID: $TOKYO_PID)"
echo "  • 孟買 (PID: $MUMBAI_PID)"
echo "  • 新加坡 (PID: $SINGAPORE_PID)"
echo ""
echo -e "${CYAN}預計完成時間: 15-20 分鐘${NC}"
echo ""

# 等待所有測試完成
wait $TOKYO_PID
echo -e "${GREEN}✅ 東京測試完成${NC}"

wait $MUMBAI_PID
echo -e "${GREEN}✅ 孟買測試完成${NC}"

wait $SINGAPORE_PID
echo -e "${GREEN}✅ 新加坡測試完成${NC}"

echo ""
echo -e "${GREEN}所有區域測試完成！${NC}"
echo ""

# 讀取結果
TOKYO_INFO=$(tail -1 "$TOKYO_RESULT_FILE")
MUMBAI_INFO=$(tail -1 "$MUMBAI_RESULT_FILE")
SINGAPORE_INFO=$(tail -1 "$SINGAPORE_RESULT_FILE")

# 顯示每個區域的測試輸出
echo "════════════════════════════════════════════════════════════════"
echo "東京測試輸出"
echo "════════════════════════════════════════════════════════════════"
cat "$TOKYO_RESULT_FILE"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "孟買測試輸出"
echo "════════════════════════════════════════════════════════════════"
cat "$MUMBAI_RESULT_FILE"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "新加坡測試輸出"
echo "════════════════════════════════════════════════════════════════"
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

################################################################################
# 步驟 5: 生成綜合報告
################################################################################

echo "════════════════════════════════════════════════════════════════"
echo "步驟 4: 生成綜合報告"
echo "════════════════════════════════════════════════════════════════"
echo ""

FINAL_REPORT="comprehensive-report-$(date +%Y%m%d_%H%M%S).md"

cat > "$FINAL_REPORT" << EOF
# 三地區綜合性能測試報告

**測試時間**: $(date)
**測試遊戲數**: $GAME_COUNT
**頁面等待時間**: $WAIT_TIME ms

---

## 📊 測試概覽

### 測試地區
- 🇯🇵 東京 (ap-northeast-1)
- 🇮🇳 孟買 (ap-south-1)
- 🇸🇬 新加坡 (ap-southeast-1)

### 測試項目
1. ✅ 遊戲緩存對比測試（雙重訪問模式）
2. ✅ API 延遲測試（3個主要 API）
3. ✅ MTR 網路路徑追蹤（4個目標）

---

## 📁 結果目錄

### 🇯🇵 東京
- 目錄: \`$TOKYO_RESULT_DIR\`
- 遊戲測試: \`$TOKYO_RESULT_DIR/game-test.log\`
- API/MTR 測試: \`$TOKYO_RESULT_DIR/api-mtr-test.log\`

### 🇮🇳 孟買
- 目錄: \`$MUMBAI_RESULT_DIR\`
- 遊戲測試: \`$MUMBAI_RESULT_DIR/game-test.log\`
- API/MTR 測試: \`$MUMBAI_RESULT_DIR/api-mtr-test.log\`

### 🇸🇬 新加坡
- 目錄: \`$SINGAPORE_RESULT_DIR\`
- 遊戲測試: \`$SINGAPORE_RESULT_DIR/game-test.log\`
- API/MTR 測試: \`$SINGAPORE_RESULT_DIR/api-mtr-test.log\`

---

## 🎮 遊戲緩存測試結果

詳細結果請查看各地區的 \`game-test.log\` 和 \`summary.csv\`

---

## 🌐 API 延遲測試結果

詳細結果請查看各地區的 \`api-mtr-test.log\`

---

## 🔍 MTR 網路追蹤結果

詳細結果請查看各地區的 \`mtr-traceroute.txt\`

---

## 💡 後續步驟

1. 分析各地區的遊戲加載時間差異
2. 比較 API 延遲（三個地區）
3. 檢查 MTR 路徑是否有異常跳躍
4. 基於數據決定優化策略

---

**報告生成時間**: $(date)
**測試工具**: Puppeteer, curl, MTR
EOF

echo -e "${GREEN}✓${NC} 綜合報告已生成: $FINAL_REPORT"
echo ""

cat "$FINAL_REPORT"

################################################################################
# 步驟 6: 清理資源
################################################################################

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "清理資源"
echo "════════════════════════════════════════════════════════════════"
echo ""

read -p "是否終止所有 EC2 實例? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}終止東京實例...${NC}"
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-northeast-1 --instance-ids "$TOKYO_INSTANCE_ID"

    echo -e "${YELLOW}終止孟買實例...${NC}"
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-south-1 --instance-ids "$MUMBAI_INSTANCE_ID"

    echo -e "${YELLOW}終止新加坡實例...${NC}"
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-southeast-1 --instance-ids "$SINGAPORE_INSTANCE_ID"

    echo -e "${GREEN}✓${NC} 所有實例已終止"
else
    echo -e "${YELLOW}保留實例，請手動清理:${NC}"
    echo "  東京: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-northeast-1 --instance-ids $TOKYO_INSTANCE_ID"
    echo "  孟買: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-south-1 --instance-ids $MUMBAI_INSTANCE_ID"
    echo "  新加坡: aws --profile gemini-pro_ck ec2 terminate-instances --region ap-southeast-1 --instance-ids $SINGAPORE_INSTANCE_ID"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                         測試完成！                                  ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}結果摘要:${NC}"
echo "  • 東京結果: $TOKYO_RESULT_DIR"
echo "  • 孟買結果: $MUMBAI_RESULT_DIR"
echo "  • 新加坡結果: $SINGAPORE_RESULT_DIR"
echo "  • 綜合報告: $FINAL_REPORT"
echo "  • URL 列表: $GAME_URLS_FILE"
echo ""

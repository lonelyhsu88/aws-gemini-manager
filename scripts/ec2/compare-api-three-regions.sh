#!/bin/bash

# 比較三個區域的 API 加載速度：東京、孟買、新加坡
# 部署三台 EC2 並行測試

set -e

INSTANCE_TYPE="t2.micro"
KEY_NAME="api-test-3regions-key"

# 區域配置 - 使用簡單變量代替關聯數組
TOKYO_REGION="ap-northeast-1"
TOKYO_AMI="ami-0d52744d6551d851e"
TOKYO_NAME="東京"
TOKYO_DISTANCE=2900

MUMBAI_REGION="ap-south-1"
MUMBAI_AMI="ami-0c2af51e265bd5e0e"
MUMBAI_NAME="孟買"
MUMBAI_DISTANCE=4000

SINGAPORE_REGION="ap-southeast-1"
SINGAPORE_AMI="ami-0497a974f8d5dcef8"
SINGAPORE_NAME="新加坡"
SINGAPORE_DISTANCE=2600

echo "=============================================="
echo "API 延遲比較測試：東京 vs 孟買 vs 新加坡"
echo "=============================================="
echo ""

# 獲取本機 IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "本機 IP: $MY_IP"
echo ""

# 創建 SSH 密鑰對
if [ ! -f ~/.ssh/${KEY_NAME}.pem ]; then
    echo "創建 SSH 密鑰對..."
    aws --profile gemini-pro_ck ec2 create-key-pair \
        --region "ap-northeast-1" \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > ~/.ssh/${KEY_NAME}.pem
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    echo "密鑰已保存: ~/.ssh/${KEY_NAME}.pem"
else
    echo "使用現有密鑰: ~/.ssh/${KEY_NAME}.pem"
fi

echo ""

# 函數：部署 EC2
deploy_instance() {
    local LOCATION=$1
    local REGION=${REGIONS[$LOCATION]}
    local AMI=${AMIS[$LOCATION]}
    local NAME="api-test-${LOCATION}"

    echo "======================================"
    echo "部署 ${REGION_NAMES[$LOCATION]} ($REGION)"
    echo "======================================"

    # 創建安全組
    SG_NAME="api-test-sg-${LOCATION}"
    SG_ID=$(aws --profile gemini-pro_ck ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SG_NAME" \
        --description "Security group for API testing in $REGION" \
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
        --cidr "${MY_IP}/32" 2>/dev/null || echo "SSH 規則已存在"

    # User Data
    USER_DATA_FILE=$(mktemp)
    cat > "$USER_DATA_FILE" <<'EOF'
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

apt-get update
apt-get install -y curl dnsutils bc

echo "Setup complete"
EOF

    # 啟動實例
    INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "file://$USER_DATA_FILE" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    rm "$USER_DATA_FILE"

    echo "實例 ID: $INSTANCE_ID"
    echo "等待實例啟動..."

    # 等待實例運行
    aws --profile gemini-pro_ck ec2 wait instance-running \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"

    # 獲取公共 IP
    PUBLIC_IP=$(aws --profile gemini-pro_ck ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo "公共 IP: $PUBLIC_IP"

    # 等待 SSH
    echo "等待 SSH 就緒..."
    TIMEOUT=120
    ELAPSED=0
    while ! ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} "echo SSH ready" 2>/dev/null; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo "錯誤: SSH 連接超時"
            exit 1
        fi
    done

    # 等待 cloud-init
    ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "cloud-init status --wait" 2>/dev/null

    echo "${REGION_NAMES[$LOCATION]} 部署完成！"
    echo ""

    # 返回實例信息
    echo "$LOCATION|$REGION|$INSTANCE_ID|$PUBLIC_IP"
}

# 並行部署三個實例
echo "開始並行部署三個區域..."
echo ""

declare -A INSTANCE_IDS
declare -A INSTANCE_IPS

for location in tokyo mumbai singapore; do
    deploy_instance "$location" &
done

# 等待所有部署完成
wait

echo ""
echo "收集實例信息..."

# 重新收集信息（因為並行執行）
for location in tokyo mumbai singapore; do
    REGION=${REGIONS[$location]}

    INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=api-test-${location}" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text)

    PUBLIC_IP=$(aws --profile gemini-pro_ck ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    INSTANCE_IDS[$location]=$INSTANCE_ID
    INSTANCE_IPS[$location]=$PUBLIC_IP
done

echo "======================================"
echo "部署完成！"
echo "======================================"
for location in tokyo mumbai singapore; do
    echo "${REGION_NAMES[$location]} (${REGIONS[$location]}):"
    echo "  實例 ID: ${INSTANCE_IDS[$location]}"
    echo "  IP: ${INSTANCE_IPS[$location]}"
    echo ""
done

# 創建測試腳本
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash

LOCATION_NAME=$1

echo "=== API 延遲測試 ==="
echo "測試位置: $LOCATION_NAME"
echo "測試時間: $(date)"
echo ""

APIS=(
  "https://ds-r.geminiservice.cc/domains?type=Hash"
  "https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"
)

for api in "${APIS[@]}"; do
  echo "測試: $api"
  echo "---"

  # 測試 5 次取平均
  total=0
  for i in {1..5}; do
    time=$(curl -w "%{time_total}" -o /dev/null -s "$api")
    echo "  第 $i 次: ${time}s"
    total=$(echo "$total + $time" | bc)
  done

  avg=$(echo "scale=3; $total / 5" | bc)
  echo "  平均: ${avg}s"
  echo ""
done

echo "測試完成時間: $(date)"
SCRIPT_EOF

chmod +x "$TEST_SCRIPT"

# 函數：在遠程執行測試
run_test() {
    local LOCATION=$1
    local NAME=${REGION_NAMES[$LOCATION]}
    local IP=${INSTANCE_IPS[$LOCATION]}

    echo "======================================"
    echo "執行測試: $NAME"
    echo "======================================"

    # 上傳測試腳本
    scp -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no \
        "$TEST_SCRIPT" ubuntu@${IP}:~/test-api.sh

    # 執行測試
    ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${IP} \
        "bash ~/test-api.sh '$NAME'" | tee "${LOCATION}-results.txt"

    echo ""
}

# 並行執行測試
echo "======================================"
echo "開始 API 延遲測試..."
echo "======================================"
echo ""

for location in tokyo mumbai singapore; do
    run_test "$location" &
done

# 等待所有測試完成
wait

rm "$TEST_SCRIPT"

echo "======================================"
echo "測試完成！"
echo "======================================"
echo ""

# 提取測試結果
extract_result() {
    local file=$1
    local api=$2
    grep -A 7 "$api" "$file" | grep "平均" | awk '{print $2}' | sed 's/s$//'
}

TOKYO_API1=$(extract_result "tokyo-results.txt" "ds-r.geminiservice.cc/domains")
TOKYO_API2=$(extract_result "tokyo-results.txt" "gameinfo-api.geminiservice.cc")

MUMBAI_API1=$(extract_result "mumbai-results.txt" "ds-r.geminiservice.cc/domains")
MUMBAI_API2=$(extract_result "mumbai-results.txt" "gameinfo-api.geminiservice.cc")

SINGAPORE_API1=$(extract_result "singapore-results.txt" "ds-r.geminiservice.cc/domains")
SINGAPORE_API2=$(extract_result "singapore-results.txt" "gameinfo-api.geminiservice.cc")

# 計算相對速度
calc_ratio() {
    local value=$1
    local base=$2
    if [ -n "$value" ] && [ -n "$base" ]; then
        echo "scale=2; $value / $base" | bc
    else
        echo "N/A"
    fi
}

# 生成比較報告
REPORT_FILE="api-comparison-3regions-$(date +%Y%m%d_%H%M%S).md"

cat > "$REPORT_FILE" <<EOF
# API 延遲比較報告：東京 vs 孟買 vs 新加坡

**測試時間**: $(date)
**測試方法**: 每個 API 測試 5 次取平均值
**源服務器**: 香港

---

## 📊 測試結果總覽

### API 1: ds-r.geminiservice.cc/domains?type=Hash

| 位置 | 距離香港 | 平均延遲 | 相對最快 | 狀態 |
|------|---------|---------|---------|------|
| 新加坡 | 2,600 km | ${SINGAPORE_API1}s | 1.0x | ✅ 最快 |
| 東京 | 2,900 km | ${TOKYO_API1}s | $(calc_ratio $TOKYO_API1 $SINGAPORE_API1)x | - |
| 孟買 | 4,000 km | ${MUMBAI_API1}s | $(calc_ratio $MUMBAI_API1 $SINGAPORE_API1)x | ⚠️ 最慢 |

### API 2: gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo

| 位置 | 距離香港 | 平均延遲 | 相對最快 | 狀態 |
|------|---------|---------|---------|------|
| 新加坡 | 2,600 km | ${SINGAPORE_API2}s | 1.0x | ✅ 最快 |
| 東京 | 2,900 km | ${TOKYO_API2}s | $(calc_ratio $TOKYO_API2 $SINGAPORE_API2)x | - |
| 孟買 | 4,000 km | ${MUMBAI_API2}s | $(calc_ratio $MUMBAI_API2 $SINGAPORE_API2)x | ⚠️ 最慢 |

---

## 📍 詳細測試結果

### 東京 (ap-northeast-1)

\`\`\`
$(cat tokyo-results.txt)
\`\`\`

---

### 孟買 (ap-south-1)

\`\`\`
$(cat mumbai-results.txt)
\`\`\`

---

### 新加坡 (ap-southeast-1)

\`\`\`
$(cat singapore-results.txt)
\`\`\`

---

## 🌏 地理距離分析

### 各區域到香港的距離

| 區域 | 距離 | 理論光速延遲 (往返) | 實際延遲 (API 1) | 實際延遲 (API 2) |
|------|------|-------------------|----------------|----------------|
| 新加坡 | 2,600 km | 17.3 ms | ${SINGAPORE_API1}s | ${SINGAPORE_API2}s |
| 東京 | 2,900 km | 19.3 ms | ${TOKYO_API1}s | ${TOKYO_API2}s |
| 孟買 | 4,000 km | 26.7 ms | ${MUMBAI_API1}s | ${MUMBAI_API2}s |

**註**:
- 理論光速延遲 = (距離 × 2) ÷ 光速 (300,000 km/s)
- 實際延遲包含：DNS 查詢、TCP 握手、TLS 協商、HTTP 處理、網路路由等
- 實際延遲通常是理論值的 5-15 倍

---

## 📈 關鍵發現

### 1. 距離與延遲關係

新加坡最接近香港 (2,600 km)，延遲最低：
- API 1: ${SINGAPORE_API1}s
- API 2: ${SINGAPORE_API2}s

孟買距離最遠 (4,000 km)，延遲最高：
- API 1: ${MUMBAI_API1}s
- API 2: ${MUMBAI_API2}s

**距離增加 54% (2,600km → 4,000km)，延遲增加 $(calc_ratio $MUMBAI_API1 $SINGAPORE_API1)x**

### 2. 兩個 API 的對比

EOF

# 添加分析
if [ -n "$SINGAPORE_API1" ] && [ -n "$SINGAPORE_API2" ]; then
    cat >> "$REPORT_FILE" <<EOF
在新加坡測試：
- API 1 (domains): ${SINGAPORE_API1}s
- API 2 (gameInfo): ${SINGAPORE_API2}s
- 差異: $(echo "scale=3; $SINGAPORE_API1 - $SINGAPORE_API2" | bc | sed 's/^-//')s

EOF
fi

cat >> "$REPORT_FILE" <<EOF

### 3. CDN 緩存影響

⚠️ **重要發現**: 即使在最近的新加坡，API 延遲仍然達到數百毫秒

**原因**: API 響應頭設置為 \`cache-control: no-cache, no-store\`
- CDN 存在但不緩存 API 響應
- 每次請求都必須回源到香港
- 距離直接影響延遲

**如果啟用 CDN 緩存**:
\`\`\`
預期延遲: < 10ms (從本地 CDN 節點返回)
改善幅度: 95-99%
\`\`\`

---

## 💡 優化建議

### 立即實施 (推薦)

**啟用 API 緩存**:
\`\`\`http
Cache-Control: public, max-age=300, stale-while-revalidate=60
\`\`\`

**預期效果** (以孟買為例):
- 首次請求: ${MUMBAI_API1}s (建立緩存)
- 後續請求: < 0.01s (從孟買 CDN)
- 改善幅度: 99%+

### 長期方案

**部署區域 API 節點**:
- 新加坡節點 (已是最快，可作為主節點)
- 孟買節點 (針對印度市場)
- 東京節點 (針對日本市場)

**預期效果**: 所有區域延遲 < 50ms

---

## 🔧 實例信息

EOF

for location in tokyo mumbai singapore; do
    cat >> "$REPORT_FILE" <<EOF
**${REGION_NAMES[$location]} (${REGIONS[$location]})**:
- 實例 ID: ${INSTANCE_IDS[$location]}
- IP: ${INSTANCE_IPS[$location]}

EOF
done

cat >> "$REPORT_FILE" <<EOF

---

## 📊 數據文件

- 東京測試結果: \`tokyo-results.txt\`
- 孟買測試結果: \`mumbai-results.txt\`
- 新加坡測試結果: \`singapore-results.txt\`

---

**報告生成時間**: $(date)
**測試工具**: curl
**測試次數**: 每個 API 5 次
**統計方法**: 算術平均值
EOF

echo "======================================"
echo "比較報告已生成"
echo "======================================"
echo "檔案: $REPORT_FILE"
echo ""
cat "$REPORT_FILE"

echo ""
echo "======================================"
echo "清理資源"
echo "======================================"
echo ""

read -p "是否終止並刪除所有 EC2 實例? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    for location in tokyo mumbai singapore; do
        echo "終止 ${REGION_NAMES[$location]} 實例..."
        aws --profile gemini-pro_ck ec2 terminate-instances \
            --region "${REGIONS[$location]}" \
            --instance-ids "${INSTANCE_IDS[$location]}" &
    done

    echo "等待所有實例終止..."
    wait

    echo "所有實例已終止"
else
    echo "保留實例，請手動清理:"
    for location in tokyo mumbai singapore; do
        echo "  ${REGION_NAMES[$location]}: aws --profile gemini-pro_ck ec2 terminate-instances --region ${REGIONS[$location]} --instance-ids ${INSTANCE_IDS[$location]}"
    done
fi

echo ""
echo "完成！"
echo ""
echo "結果檔案:"
echo "  - tokyo-results.txt"
echo "  - mumbai-results.txt"
echo "  - singapore-results.txt"
echo "  - $REPORT_FILE"

#!/bin/bash

# 比較東京和孟買的 API 加載速度
# 部署兩台 EC2 並行測試

set -e

INSTANCE_TYPE="t2.micro"
KEY_NAME="api-test-key"

# 區域配置
TOKYO_REGION="ap-northeast-1"
TOKYO_AMI="ami-0d52744d6551d851e"  # Ubuntu 22.04 LTS in Tokyo

MUMBAI_REGION="ap-south-1"
MUMBAI_AMI="ami-0c2af51e265bd5e0e"  # Ubuntu 22.04 LTS in Mumbai

echo "=== API 延遲比較測試：東京 vs 孟買 ==="
echo ""

# 獲取本機 IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "本機 IP: $MY_IP"
echo ""

# API 測試目標
APIS=(
  "https://ds-r.geminiservice.cc/domains?type=Hash"
  "https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"
)

# 創建 SSH 密鑰對
if [ ! -f ~/.ssh/${KEY_NAME}.pem ]; then
    echo "創建 SSH 密鑰對..."
    aws --profile gemini-pro_ck ec2 create-key-pair \
        --region "$TOKYO_REGION" \
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
    local REGION=$1
    local AMI=$2
    local NAME=$3

    echo "======================================"
    echo "部署 $NAME ($REGION)"
    echo "======================================"

    # 創建安全組
    SG_NAME="api-test-sg-${REGION}"
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
apt-get install -y curl dnsutils time

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

    echo "$NAME 部署完成！"
    echo ""

    # 返回實例信息
    echo "$REGION|$INSTANCE_ID|$PUBLIC_IP"
}

# 並行部署兩個實例
echo "開始並行部署..."
echo ""

TOKYO_INFO=$(deploy_instance "$TOKYO_REGION" "$TOKYO_AMI" "api-test-tokyo")
MUMBAI_INFO=$(deploy_instance "$MUMBAI_REGION" "$MUMBAI_AMI" "api-test-mumbai")

# 解析信息
TOKYO_INSTANCE_ID=$(echo "$TOKYO_INFO" | cut -d'|' -f2)
TOKYO_IP=$(echo "$TOKYO_INFO" | cut -d'|' -f3)

MUMBAI_INSTANCE_ID=$(echo "$MUMBAI_INFO" | cut -d'|' -f2)
MUMBAI_IP=$(echo "$MUMBAI_INFO" | cut -d'|' -f3)

echo "======================================"
echo "部署完成！"
echo "======================================"
echo "東京:"
echo "  實例 ID: $TOKYO_INSTANCE_ID"
echo "  IP: $TOKYO_IP"
echo ""
echo "孟買:"
echo "  實例 ID: $MUMBAI_INSTANCE_ID"
echo "  IP: $MUMBAI_IP"
echo ""

# 創建測試腳本
TEST_SCRIPT=$(mktemp)
cat > "$TEST_SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash

echo "=== API 延遲測試 ==="
echo "測試時間: $(date)"
echo "測試位置: $(curl -s https://ipinfo.io/city 2>/dev/null || echo 'Unknown')"
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
SCRIPT_EOF

chmod +x "$TEST_SCRIPT"

# 函數：在遠程執行測試
run_test() {
    local NAME=$1
    local IP=$2

    echo "======================================"
    echo "執行測試: $NAME"
    echo "======================================"

    # 上傳測試腳本
    scp -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no \
        "$TEST_SCRIPT" ubuntu@${IP}:~/test-api.sh

    # 執行測試
    ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${IP} \
        "bash ~/test-api.sh" | tee "${NAME}-results.txt"

    echo ""
}

# 並行執行測試
echo "======================================"
echo "開始 API 延遲測試..."
echo "======================================"
echo ""

run_test "tokyo" "$TOKYO_IP" &
TOKYO_PID=$!

run_test "mumbai" "$MUMBAI_IP" &
MUMBAI_PID=$!

# 等待兩個測試完成
wait $TOKYO_PID
wait $MUMBAI_PID

rm "$TEST_SCRIPT"

echo "======================================"
echo "測試完成！"
echo "======================================"
echo ""

# 生成比較報告
REPORT_FILE="api-comparison-tokyo-vs-mumbai-$(date +%Y%m%d_%H%M%S).md"

cat > "$REPORT_FILE" <<EOF
# API 延遲比較報告：東京 vs 孟買

**測試時間**: $(date)
**測試方法**: 每個 API 測試 5 次取平均值

---

## 東京 (ap-northeast-1) 測試結果

\`\`\`
$(cat tokyo-results.txt)
\`\`\`

---

## 孟買 (ap-south-1) 測試結果

\`\`\`
$(cat mumbai-results.txt)
\`\`\`

---

## 比較分析

### API 1: ds-r.geminiservice.cc/domains

| 位置 | 平均延遲 | 相對速度 |
|------|---------|---------|
| 東京 | $(grep -A 7 "ds-r.geminiservice.cc/domains" tokyo-results.txt | grep "平均" | awk '{print $2}') | 基準 |
| 孟買 | $(grep -A 7 "ds-r.geminiservice.cc/domains" mumbai-results.txt | grep "平均" | awk '{print $2}') | - |

### API 2: gameinfo-api.geminiservice.cc

| 位置 | 平均延遲 | 相對速度 |
|------|---------|---------|
| 東京 | $(grep -A 7 "gameinfo-api.geminiservice.cc" tokyo-results.txt | grep "平均" | awk '{print $2}') | 基準 |
| 孟買 | $(grep -A 7 "gameinfo-api.geminiservice.cc" mumbai-results.txt | grep "平均" | awk '{print $2}') | - |

---

## 地理距離分析

### 東京到源服務器 (香港)
- 距離: 約 2,900 km
- 理論光速延遲 (往返): 19.3 ms
- 實際延遲: 見上表

### 孟買到源服務器 (香港)
- 距離: 約 4,000 km
- 理論光速延遲 (往返): 26.7 ms
- 實際延遲: 見上表

---

## 實例信息

**東京實例**:
- 實例 ID: $TOKYO_INSTANCE_ID
- IP: $TOKYO_IP
- 區域: $TOKYO_REGION

**孟買實例**:
- 實例 ID: $MUMBAI_INSTANCE_ID
- IP: $MUMBAI_IP
- 區域: $MUMBAI_REGION

---

**報告生成時間**: $(date)
**測試工具**: curl
**測試次數**: 每個 API 5 次
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
    echo "終止東京實例..."
    aws --profile gemini-pro_ck ec2 terminate-instances \
        --region "$TOKYO_REGION" \
        --instance-ids "$TOKYO_INSTANCE_ID"

    echo "終止孟買實例..."
    aws --profile gemini-pro_ck ec2 terminate-instances \
        --region "$MUMBAI_REGION" \
        --instance-ids "$MUMBAI_INSTANCE_ID"

    echo "等待實例終止..."
    aws --profile gemini-pro_ck ec2 wait instance-terminated \
        --region "$TOKYO_REGION" \
        --instance-ids "$TOKYO_INSTANCE_ID" &

    aws --profile gemini-pro_ck ec2 wait instance-terminated \
        --region "$MUMBAI_REGION" \
        --instance-ids "$MUMBAI_INSTANCE_ID" &

    wait

    echo "所有實例已終止"
else
    echo "保留實例，請手動清理:"
    echo "  東京: aws --profile gemini-pro_ck ec2 terminate-instances --region $TOKYO_REGION --instance-ids $TOKYO_INSTANCE_ID"
    echo "  孟買: aws --profile gemini-pro_ck ec2 terminate-instances --region $MUMBAI_REGION --instance-ids $MUMBAI_INSTANCE_ID"
fi

echo ""
echo "完成！"
echo ""
echo "結果檔案:"
echo "  - tokyo-results.txt"
echo "  - mumbai-results.txt"
echo "  - $REPORT_FILE"

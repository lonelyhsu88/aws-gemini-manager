#!/bin/bash

# API 延遲比較測試：東京、孟買、新加坡
# 簡化版本，不使用關聯數組

set -e

INSTANCE_TYPE="t2.micro"
KEY_NAME="api-test-3regions-key"

echo "=============================================="
echo "API 延遲比較測試：東京 vs 孟買 vs 新加坡"
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
            # 密鑰可能已存在但文件丟失
            echo "密鑰對可能已存在於 $REGION"
            return 1
        }
        chmod 400 "$KEY_FILE"
        echo "已保存: $KEY_FILE"
    else
        echo "使用現有密鑰: $KEY_FILE"
    fi
}

create_key_in_region "ap-northeast-1"
create_key_in_region "ap-south-1"
create_key_in_region "ap-southeast-1"

echo ""

# 創建測試腳本
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

chmod +x test-api.sh

# 函數：部署和測試
deploy_and_test() {
    local LOCATION=$1
    local REGION=$2
    local AMI=$3
    local NAME=$4

    echo "======================================"
    echo "部署 $NAME ($REGION)"
    echo "======================================"

    # 創建安全組
    SG_NAME="api-test-sg-${LOCATION}"
    SG_ID=$(aws --profile gemini-pro_ck ec2 create-security-group \
        --region "$REGION" \
        --group-name "$SG_NAME" \
        --description "API test SG" \
        --query 'GroupId' \
        --output text 2>/dev/null || \
        aws --profile gemini-pro_ck ec2 describe-security-groups \
            --region "$REGION" \
            --group-names "$SG_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text)

    # 添加 SSH 規則
    aws --profile gemini-pro_ck ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${MY_IP}/32" 2>/dev/null || true

    # User Data
    USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
apt-get update
apt-get install -y curl bc
USERDATA
)

    # 使用區域特定的密鑰
    REGION_KEY_NAME="${KEY_NAME}-${REGION}"
    REGION_KEY_FILE=~/.ssh/${REGION_KEY_NAME}.pem

    # 啟動實例
    INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$REGION_KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=api-test-${LOCATION}}]" \
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
    echo "等待 SSH..."

    for i in {1..24}; do
        if ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} "echo ready" 2>/dev/null; then
            break
        fi
        sleep 5
    done

    # 等待 cloud-init
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "cloud-init status --wait" 2>/dev/null || true

    echo "上傳測試腳本..."
    scp -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no test-api.sh ubuntu@${PUBLIC_IP}:~/

    echo "執行測試..."
    ssh -i "$REGION_KEY_FILE" -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "bash test-api.sh" | tee "${LOCATION}-results.txt"

    echo ""
    echo "$LOCATION|$REGION|$INSTANCE_ID|$PUBLIC_IP"
}

# 依序部署和測試三個區域
echo "開始測試..."
echo ""

TOKYO_INFO=$(deploy_and_test "tokyo" "ap-northeast-1" "ami-0d52744d6551d851e" "東京")
MUMBAI_INFO=$(deploy_and_test "mumbai" "ap-south-1" "ami-0c2af51e265bd5e0e" "孟買")
SINGAPORE_INFO=$(deploy_and_test "singapore" "ap-southeast-1" "ami-0497a974f8d5dcef8" "新加坡")

# 解析信息
TOKYO_INSTANCE_ID=$(echo "$TOKYO_INFO" | cut -d'|' -f3)
TOKYO_IP=$(echo "$TOKYO_INFO" | cut -d'|' -f4)

MUMBAI_INSTANCE_ID=$(echo "$MUMBAI_INFO" | cut -d'|' -f3)
MUMBAI_IP=$(echo "$MUMBAI_INFO" | cut -d'|' -f4)

SINGAPORE_INSTANCE_ID=$(echo "$SINGAPORE_INFO" | cut -d'|' -f3)
SINGAPORE_IP=$(echo "$SINGAPORE_INFO" | cut -d'|' -f4)

# 提取結果
extract_avg() {
    local file=$1
    local api=$2
    grep -A 7 "$api" "$file" 2>/dev/null | grep "平均" | awk '{print $2}' | sed 's/s$//' || echo "N/A"
}

TOKYO_API1=$(extract_avg "tokyo-results.txt" "ds-r.geminiservice.cc")
TOKYO_API2=$(extract_avg "tokyo-results.txt" "gameinfo-api.geminiservice.cc")

MUMBAI_API1=$(extract_avg "mumbai-results.txt" "ds-r.geminiservice.cc")
MUMBAI_API2=$(extract_avg "mumbai-results.txt" "gameinfo-api.geminiservice.cc")

SINGAPORE_API1=$(extract_avg "singapore-results.txt" "ds-r.geminiservice.cc")
SINGAPORE_API2=$(extract_avg "singapore-results.txt" "gameinfo-api.geminiservice.cc")

# 生成報告
REPORT_FILE="api-comparison-3regions-$(date +%Y%m%d_%H%M%S).md"

cat > "$REPORT_FILE" <<EOF
# API 延遲比較報告：東京 vs 孟買 vs 新加坡

**測試時間**: $(date)
**源服務器**: 香港

---

## 📊 測試結果

### API 1: ds-r.geminiservice.cc/domains

| 位置 | 距離香港 | 平均延遲 | 狀態 |
|------|---------|---------|------|
| 新加坡 | 2,600 km | ${SINGAPORE_API1}s | ✅ |
| 東京 | 2,900 km | ${TOKYO_API1}s | - |
| 孟買 | 4,000 km | ${MUMBAI_API1}s | ⚠️ |

### API 2: gameinfo-api.geminiservice.cc

| 位置 | 距離香港 | 平均延遲 | 狀態 |
|------|---------|---------|------|
| 新加坡 | 2,600 km | ${SINGAPORE_API2}s | ✅ |
| 東京 | 2,900 km | ${TOKYO_API2}s | - |
| 孟買 | 4,000 km | ${MUMBAI_API2}s | ⚠️ |

---

## 詳細結果

### 東京
\`\`\`
$(cat tokyo-results.txt)
\`\`\`

### 孟買
\`\`\`
$(cat mumbai-results.txt)
\`\`\`

### 新加坡
\`\`\`
$(cat singapore-results.txt)
\`\`\`

---

## 實例信息

- 東京: $TOKYO_INSTANCE_ID ($TOKYO_IP)
- 孟買: $MUMBAI_INSTANCE_ID ($MUMBAI_IP)
- 新加坡: $SINGAPORE_INSTANCE_ID ($SINGAPORE_IP)

---

生成時間: $(date)
EOF

echo "======================================"
echo "測試完成！"
echo "======================================"
echo ""
cat "$REPORT_FILE"

echo ""
echo "======================================"
echo "清理資源"
echo "======================================"

read -p "是否終止所有實例? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "終止東京..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-northeast-1 --instance-ids "$TOKYO_INSTANCE_ID"

    echo "終止孟買..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-south-1 --instance-ids "$MUMBAI_INSTANCE_ID"

    echo "終止新加坡..."
    aws --profile gemini-pro_ck ec2 terminate-instances --region ap-southeast-1 --instance-ids "$SINGAPORE_INSTANCE_ID"

    echo "已終止所有實例"
else
    echo "保留實例"
fi

echo ""
echo "結果檔案:"
echo "  - $REPORT_FILE"
echo "  - tokyo-results.txt"
echo "  - mumbai-results.txt"
echo "  - singapore-results.txt"

rm -f test-api.sh

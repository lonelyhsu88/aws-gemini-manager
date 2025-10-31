#!/bin/bash

# 部署孟買 EC2 進行 MTR 測試
# 測試 API CDN 端點的網路路徑

set -e

REGION="ap-south-1"
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-0c2af51e265bd5e0e"  # Ubuntu 22.04 LTS in ap-south-1
KEY_NAME="mtr-test-mumbai-key"
SG_NAME="mtr-test-sg"

echo "=== 部署孟買 MTR 測試 EC2 ==="
echo ""

# 獲取本機 IP
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "本機 IP: $MY_IP"

# 創建 SSH 密鑰對
if [ ! -f ~/.ssh/${KEY_NAME}.pem ]; then
    echo "創建 SSH 密鑰對..."
    aws --profile gemini-pro_ck ec2 create-key-pair \
        --region "$REGION" \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > ~/.ssh/${KEY_NAME}.pem
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    echo "密鑰已保存: ~/.ssh/${KEY_NAME}.pem"
else
    echo "使用現有密鑰: ~/.ssh/${KEY_NAME}.pem"
fi

# 創建安全組
echo "創建安全組..."
SG_ID=$(aws --profile gemini-pro_ck ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "Security group for MTR testing" \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws --profile gemini-pro_ck ec2 describe-security-groups \
        --region "$REGION" \
        --group-names "$SG_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

echo "安全組 ID: $SG_ID"

# 添加 SSH 規則
echo "配置安全組規則..."
aws --profile gemini-pro_ck ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "${MY_IP}/32" 2>/dev/null || echo "SSH 規則已存在"

# 準備 User Data
USER_DATA_FILE=$(mktemp)
cat > "$USER_DATA_FILE" <<'EOF'
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

echo "=== 開始安裝 MTR ==="
apt-get update
apt-get install -y mtr-tiny dnsutils curl

echo "=== 安裝完成 ==="
echo "MTR version: $(mtr --version)"
echo "Ready for testing"
EOF

# 啟動 EC2 實例
echo "啟動 EC2 實例..."
INSTANCE_ID=$(aws --profile gemini-pro_ck ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --user-data "file://$USER_DATA_FILE" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=mtr-test-mumbai}]" \
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

echo ""
echo "======================================"
echo "EC2 實例已啟動！"
echo "======================================"
echo "實例 ID: $INSTANCE_ID"
echo "公共 IP: $PUBLIC_IP"
echo "區域: $REGION"
echo ""

# 等待 SSH 就緒
echo "等待 SSH 服務啟動 (最多 120 秒)..."
TIMEOUT=120
ELAPSED=0
while ! ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@${PUBLIC_IP} "echo SSH ready" 2>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "錯誤: SSH 連接超時"
        exit 1
    fi
    echo "等待中... ($ELAPSED/$TIMEOUT 秒)"
done

echo "SSH 連接成功！"
echo ""

# 等待 cloud-init 完成
echo "等待軟體安裝完成..."
ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "
    echo '等待 cloud-init 完成...'
    cloud-init status --wait
    echo 'Cloud-init 完成！'
    echo ''
    echo 'MTR 版本:'
    mtr --version
"

echo ""
echo "======================================"
echo "上傳測試腳本..."
echo "======================================"

# 上傳 MTR 測試腳本
scp -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no \
    ./mtr-cdn-endpoints.sh \
    ubuntu@${PUBLIC_IP}:~/

echo "腳本已上傳"
echo ""

# 執行 MTR 測試
echo "======================================"
echo "執行 MTR 測試..."
echo "======================================"
echo ""

ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "
    chmod +x ~/mtr-cdn-endpoints.sh
    ./mtr-cdn-endpoints.sh
"

echo ""
echo "======================================"
echo "下載測試結果..."
echo "======================================"

# 獲取結果目錄名稱
RESULT_DIR=$(ssh -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} "ls -dt mtr-results-* | head -1")

echo "結果目錄: $RESULT_DIR"

# 下載結果
LOCAL_RESULT_DIR="mtr-cdn-results-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOCAL_RESULT_DIR"

scp -i ~/.ssh/${KEY_NAME}.pem -o StrictHostKeyChecking=no -r \
    ubuntu@${PUBLIC_IP}:~/${RESULT_DIR}/* \
    "$LOCAL_RESULT_DIR/"

echo ""
echo "======================================"
echo "測試完成！"
echo "======================================"
echo ""
echo "結果已下載到: $LOCAL_RESULT_DIR"
echo ""
echo "結果檔案:"
ls -lh "$LOCAL_RESULT_DIR"
echo ""

# 顯示摘要
if [ -f "$LOCAL_RESULT_DIR/SUMMARY.md" ]; then
    echo "======================================"
    echo "測試摘要:"
    echo "======================================"
    cat "$LOCAL_RESULT_DIR/SUMMARY.md"
fi

echo ""
echo "======================================"
echo "清理資源"
echo "======================================"

read -p "是否終止並刪除 EC2 實例? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "終止實例 $INSTANCE_ID..."
    aws --profile gemini-pro_ck ec2 terminate-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"

    echo "等待實例終止..."
    aws --profile gemini-pro_ck ec2 wait instance-terminated \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"

    echo "實例已終止"
else
    echo "保留實例，請手動清理:"
    echo "  實例 ID: $INSTANCE_ID"
    echo "  終止指令: aws --profile gemini-pro_ck ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID"
fi

echo ""
echo "完成！"

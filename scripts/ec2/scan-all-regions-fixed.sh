#!/bin/bash

PROFILE="gemini-pro_ck"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         AWS 全球區域資源掃描 - 尋找被遺忘的測試資源              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "⏱️  掃描開始時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 定義所有 AWS 區域
REGIONS=(
    "us-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
    "ap-east-1"
    "ap-south-1"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-northeast-3"
    "ap-southeast-1"
    "ap-southeast-2"
    "ap-southeast-3"
    "eu-central-1"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    "eu-north-1"
    "ca-central-1"
    "sa-east-1"
    "me-south-1"
    "af-south-1"
)

echo "📍 總共掃描 ${#REGIONS[@]} 個區域"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""

# 用於統計
TOTAL_EC2=0
TOTAL_RDS=0
TOTAL_NAT=0
REGIONS_WITH_RESOURCES=0

for region in "${REGIONS[@]}"; do
    echo -n "🔍 掃描 $region ... "

    # EC2 實例計數
    ec2_output=$(aws --profile $PROFILE ec2 describe-instances \
        --region $region \
        --filters "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null)
    ec2_count=$(echo "$ec2_output" | wc -w | tr -d ' ')

    # RDS 實例計數
    rds_output=$(aws --profile $PROFILE rds describe-db-instances \
        --region $region \
        --query 'DBInstances[*].DBInstanceIdentifier' \
        --output text 2>/dev/null)
    rds_count=$(echo "$rds_output" | wc -w | tr -d ' ')

    # NAT Gateway 計數
    nat_output=$(aws --profile $PROFILE ec2 describe-nat-gateways \
        --region $region \
        --filter "Name=state,Values=available,pending" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text 2>/dev/null)
    nat_count=$(echo "$nat_output" | wc -w | tr -d ' ')

    # 計算總資源數
    total_resources=$((ec2_count + rds_count + nat_count))

    if [ $total_resources -gt 0 ]; then
        echo "✅ 找到資源"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌍 區域: $region"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [ $ec2_count -gt 0 ]; then
            echo "  📦 EC2 實例: $ec2_count 台"
            # 顯示 EC2 詳細資訊
            aws --profile $PROFILE ec2 describe-instances \
                --region $region \
                --filters "Name=instance-state-name,Values=running,stopped,stopping,pending" \
                --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
                --output table 2>/dev/null | grep -v "^---" | grep -v "^|.*|$" | head -20
        fi

        if [ $rds_count -gt 0 ]; then
            echo "  🗄️  RDS 資料庫: $rds_count 個"
            # 顯示 RDS 詳細資訊
            aws --profile $PROFILE rds describe-db-instances \
                --region $region \
                --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,AllocatedStorage]' \
                --output table 2>/dev/null | grep -v "^---" | grep -v "^|.*|$"
        fi

        if [ $nat_count -gt 0 ]; then
            echo "  🌐 NAT Gateway: $nat_count 個 (每小時 ~$0.045)"
        fi

        echo ""

        REGIONS_WITH_RESOURCES=$((REGIONS_WITH_RESOURCES + 1))
        TOTAL_EC2=$((TOTAL_EC2 + ec2_count))
        TOTAL_RDS=$((TOTAL_RDS + rds_count))
        TOTAL_NAT=$((TOTAL_NAT + nat_count))
    else
        echo "○ 無資源"
    fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "📊 全球資源統計總覽"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  有資源的區域: $REGIONS_WITH_RESOURCES 個"
echo "  總 EC2 實例: $TOTAL_EC2 台"
echo "  總 RDS 資料庫: $TOTAL_RDS 個"
echo "  總 NAT Gateway: $TOTAL_NAT 個"
echo ""

# 檢查是否有非香港區域的資源
if [ $REGIONS_WITH_RESOURCES -gt 1 ] || ([ $REGIONS_WITH_RESOURCES -eq 1 ] && [ $TOTAL_EC2 -gt 0 ]); then
    echo "⚠️  提醒："
    echo ""
    # 檢查是否有除了香港以外的區域有資源
    for region in "${REGIONS[@]}"; do
        if [ "$region" != "ap-east-1" ]; then
            test_count=$(aws --profile $PROFILE ec2 describe-instances \
                --region $region \
                --filters "Name=instance-state-name,Values=running,stopped" \
                --query 'Reservations[*].Instances[*].InstanceId' \
                --output text 2>/dev/null | wc -w | tr -d ' ')

            if [ $test_count -gt 0 ]; then
                echo "  ⚠️  在 $region 發現 $test_count 台實例（非生產區域）"
                echo "     → 建議檢查是否為遺忘的測試資源"
                echo ""
            fi
        fi
    done
fi

echo "════════════════════════════════════════════════════════════════"
echo "✅ 掃描完成！"
echo "⏱️  完成時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════"

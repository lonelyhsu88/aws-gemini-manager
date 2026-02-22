#!/usr/bin/env bash
# SSL Certificate Status Checker
# Checks all SSL certificates stored in S3 bucket: renew-ssl-certification
#
# Usage: ./check-ssl-certificates.sh [--format=table|summary|alert]
#
# Options:
#   --format=table    Show detailed table format (default)
#   --format=summary  Show summary statistics only
#   --format=alert    Show only certificates that need attention

set -euo pipefail

# Configuration
S3_BUCKET="s3://renew-ssl-certification/"
AWS_PROFILE="gemini-pro_ck"
TEMP_DIR="/tmp/ssl-certs-$$"

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default format
FORMAT="table"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --format=*)
            FORMAT="${arg#*=}"
            ;;
    esac
done

# Create temp directory
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Get all domains
domains=$(aws --profile "$AWS_PROFILE" s3 ls "$S3_BUCKET" | awk '{print $2}' | sed 's/\///' | sort)
total_domains=$(echo "$domains" | wc -l | xargs)

# Initialize counters
healthy=0
attention=0
warning=0
critical=0

echo "=================================================="
echo "SSL 憑證狀況檢查"
echo "檢查時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo "S3 Bucket: $S3_BUCKET"
echo "總域名數: $total_domains"
echo "=================================================="
echo ""

# Array to store certificate info
declare -a cert_info

# Check each domain
for domain in $domains; do
    # Download certificate
    aws --profile "$AWS_PROFILE" s3 cp \
        "${S3_BUCKET}${domain}/fullchain.pem" \
        "${TEMP_DIR}/${domain}.pem" > /dev/null 2>&1

    if [ -f "${TEMP_DIR}/${domain}.pem" ]; then
        # Get certificate details
        not_after=$(openssl x509 -in "${TEMP_DIR}/${domain}.pem" -noout -enddate | sed 's/notAfter=//')
        issuer=$(openssl x509 -in "${TEMP_DIR}/${domain}.pem" -noout -issuer | grep -o 'CN=[^,]*' | sed 's/CN=//')

        # Calculate days until expiry
        expiry_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" "+%s" 2>/dev/null || echo "0")
        current_epoch=$(date "+%s")
        days_remaining=$(( ($expiry_epoch - $current_epoch) / 86400 ))

        # Format expiry date
        expiry_date=$(echo "$not_after" | awk '{print $2" "$1" "$4}')

        # Determine status
        if [ $days_remaining -lt 14 ]; then
            status="🔴"
            status_text="緊急"
            color=$RED
            critical=$((critical + 1))
        elif [ $days_remaining -lt 30 ]; then
            status="⚠️ "
            status_text="警告"
            color=$YELLOW
            warning=$((warning + 1))
        elif [ $days_remaining -lt 45 ]; then
            status="⚠️ "
            status_text="注意"
            color=$YELLOW
            attention=$((attention + 1))
        else
            status="✅"
            status_text="健康"
            color=$GREEN
            healthy=$((healthy + 1))
        fi

        # Store certificate info
        cert_info+=("$status|$domain|$days_remaining|$expiry_date|$issuer|$color|$status_text")
    fi
done

# Display based on format
case $FORMAT in
    table)
        echo "狀態 | 域名                        | 剩餘天數 | 到期日期      | 憑證機構"
        echo "-----|----------------------------|---------|--------------|-------------"
        for info in "${cert_info[@]}"; do
            IFS='|' read -r status domain days expiry issuer color status_text <<< "$info"
            printf "${color}%-3s | %-30s | %3d 天  | %s | Let's Encrypt %s${NC}\n" \
                "$status" "$domain" "$days" "$expiry" "$issuer"
        done
        ;;

    alert)
        echo "需要關注的憑證："
        echo ""
        for info in "${cert_info[@]}"; do
            IFS='|' read -r status domain days expiry issuer color status_text <<< "$info"
            if [ $days -lt 45 ]; then
                printf "${color}%-3s %-30s 剩餘: %3d 天  到期: %s${NC}\n" \
                    "$status" "$domain" "$days" "$expiry"
            fi
        done
        ;;

    summary)
        # Summary is printed below
        ;;
esac

# Always show summary
echo ""
echo "=================================================="
echo "統計摘要"
echo "=================================================="
printf "${GREEN}✅ 健康 (>45天):    %2d 個域名 (%.1f%%)${NC}\n" \
    $healthy $(echo "scale=1; $healthy * 100 / $total_domains" | bc)
printf "${YELLOW}⚠️  注意 (30-45天): %2d 個域名 (%.1f%%)${NC}\n" \
    $attention $(echo "scale=1; $attention * 100 / $total_domains" | bc)
printf "${YELLOW}⚠️  警告 (14-30天): %2d 個域名 (%.1f%%)${NC}\n" \
    $warning $(echo "scale=1; $warning * 100 / $total_domains" | bc)
printf "${RED}🔴 緊急 (<14天):    %2d 個域名 (%.1f%%)${NC}\n" \
    $critical $(echo "scale=1; $critical * 100 / $total_domains" | bc)

echo ""
echo "=================================================="
echo "建議行動"
echo "=================================================="

if [ $critical -gt 0 ]; then
    echo "🔴 緊急: 立即更新 $critical 個憑證（不到 14 天）"
fi

if [ $warning -gt 0 ]; then
    echo "⚠️  警告: 本週內更新 $warning 個憑證（不到 30 天）"
fi

if [ $attention -gt 0 ]; then
    echo "⚠️  注意: 本月內規劃更新 $attention 個憑證（30-45 天）"
fi

if [ $critical -eq 0 ] && [ $warning -eq 0 ] && [ $attention -eq 0 ]; then
    echo "✅ 所有憑證狀態良好"
fi

echo ""
echo "下次檢查建議: $(date -v+7d '+%Y-%m-%d')"
echo "=================================================="

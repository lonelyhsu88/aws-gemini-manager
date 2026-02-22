#!/usr/bin/env bash
# Search WAF logs for specific IP address
# Usage: ./search-waf-logs.sh <IP_ADDRESS> [HOURS_BACK]

set -euo pipefail

# Configuration
PROFILE="gemini-pro_ck"
BUCKET="aws-waf-logs-eks-waf-ap-east-1"
IP_ADDRESS="${1:-61.218.59.85}"
HOURS_BACK="${2:-24}"
TEMP_DIR="/tmp/waf-logs-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Searching WAF logs for IP: ${IP_ADDRESS}${NC}"
echo -e "${YELLOW}📅 Time range: Last ${HOURS_BACK} hours${NC}"
echo ""

# Create temp directory
mkdir -p "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

# Calculate time range
if date --version >/dev/null 2>&1; then
    # GNU date (Linux)
    START_TIME=$(date -u -d "${HOURS_BACK} hours ago" "+%Y/%m/%d/%H")
    END_TIME=$(date -u "+%Y/%m/%d/%H")
else
    # BSD date (macOS)
    START_TIME=$(date -u -v-"${HOURS_BACK}"H "+%Y/%m/%d/%H")
    END_TIME=$(date -u "+%Y/%m/%d/%H")
fi

echo -e "${YELLOW}Start time: ${START_TIME}${NC}"
echo -e "${YELLOW}End time: ${END_TIME}${NC}"
echo ""

# List all log files in the time range
echo -e "${GREEN}📦 Listing log files...${NC}"
aws --profile "$PROFILE" s3 ls "s3://${BUCKET}/AWSLogs/470013648166/WAFLogs/ap-east-1/eks-waf/" \
    --recursive | \
    awk '{print $4}' | \
    grep -E "\.log\.gz$" > "$TEMP_DIR/all_files.txt"

# Filter files by time range (extract YYYY/MM/DD/HH from path)
echo -e "${YELLOW}Filtering files by time range...${NC}"
awk -v start="$START_TIME" -v end="$END_TIME" '
{
    # Extract date/hour from path: AWSLogs/.../YYYY/MM/DD/HH/...
    if (match($0, /[0-9]{4}\/[0-9]{2}\/[0-9]{2}\/[0-9]{2}/)) {
        timestamp = substr($0, RSTART, RLENGTH)
        if (timestamp >= start && timestamp <= end) {
            print $0
        }
    }
}' "$TEMP_DIR/all_files.txt" > "$TEMP_DIR/log_files.txt"

TOTAL_FILES=$(wc -l < "$TEMP_DIR/log_files.txt")
echo -e "${YELLOW}Found ${TOTAL_FILES} log files to search${NC}"
echo ""

# Search for IP in logs
FOUND_COUNT=0
echo -e "${GREEN}🔎 Searching for IP ${IP_ADDRESS}...${NC}"
echo ""

while IFS= read -r log_file; do
    # Download and decompress log file
    aws --profile "$PROFILE" s3 cp "s3://${BUCKET}/${log_file}" "$TEMP_DIR/current.log.gz" --quiet

    # Search for IP in the log
    if gunzip -c "$TEMP_DIR/current.log.gz" | grep -q "$IP_ADDRESS"; then
        ((FOUND_COUNT++))

        # Extract timestamp from filename
        TIMESTAMP=$(echo "$log_file" | grep -oE '[0-9]{8}T[0-9]{4}Z')

        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}✓ Found in: ${log_file}${NC}"
        echo -e "${RED}⏰ Timestamp: ${TIMESTAMP}${NC}"
        echo ""

        # Show matching records
        gunzip -c "$TEMP_DIR/current.log.gz" | grep "$IP_ADDRESS" | while IFS= read -r line; do
            # Pretty print JSON if possible
            if command -v jq >/dev/null 2>&1; then
                echo "$line" | jq -C '.' 2>/dev/null || echo "$line"
            else
                echo "$line" | python3 -m json.tool 2>/dev/null || echo "$line"
            fi
            echo ""
        done
    fi

    # Clean up temp file
    rm -f "$TEMP_DIR/current.log.gz"
done < "$TEMP_DIR/log_files.txt"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}📊 Summary:${NC}"
echo -e "${YELLOW}  • Total files searched: ${TOTAL_FILES}${NC}"
echo -e "${YELLOW}  • Files with IP ${IP_ADDRESS}: ${FOUND_COUNT}${NC}"
echo ""

if [ "$FOUND_COUNT" -eq 0 ]; then
    echo -e "${RED}⚠️  No records found for IP ${IP_ADDRESS}${NC}"
    echo ""
    echo -e "${YELLOW}Possible reasons:${NC}"
    echo "  1. IP is no longer being blocked (WAF rule changed)"
    echo "  2. IP stopped sending requests"
    echo "  3. Logs have been rotated/deleted (check S3 lifecycle policy)"
    echo "  4. Time range is too narrow (try increasing --hours-back)"
    echo ""
else
    echo -e "${GREEN}✅ Found ${FOUND_COUNT} log files containing IP ${IP_ADDRESS}${NC}"
fi

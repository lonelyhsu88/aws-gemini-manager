#!/bin/bash
#
# List CloudWatch metrics for bingo-stress instances
#
# Usage: ./list-bingo-stress-metrics.sh [--verbose]
#

PROFILE="gemini-pro_ck"
REGION="ap-east-1"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "CloudWatch Metrics: bingo-stress instances"
echo "========================================================================"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "Date: $(date)"
echo ""

# Get unique instance identifiers
echo -e "${BLUE}Extracting unique instance identifiers...${NC}"
INSTANCES=$(aws cloudwatch list-metrics \
    --profile "$PROFILE" \
    --region "$REGION" \
    --output json | \
    jq -r '.Metrics[] | select(.Dimensions[]?.Value | contains("bingo-stress")) | .Dimensions[] | select(.Name == "DBInstanceIdentifier") | .Value' | \
    sort -u)

INSTANCE_COUNT=$(echo "$INSTANCES" | wc -l | tr -d ' ')
echo -e "${GREEN}Found $INSTANCE_COUNT unique instances with metrics${NC}"
echo ""

# Check which instances still exist
echo -e "${BLUE}Checking RDS for active instances...${NC}"
ACTIVE_INSTANCES=$(aws rds describe-db-instances \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output json | \
    jq -r '.[]' | \
    grep "bingo-stress" | \
    sort -u)

ACTIVE_COUNT=$(echo "$ACTIVE_INSTANCES" | wc -l | tr -d ' ')
echo -e "${GREEN}Found $ACTIVE_COUNT active RDS instances${NC}"
echo ""

# Compare and categorize
echo "========================================================================"
echo "Instance Status Summary"
echo "========================================================================"
echo ""

echo -e "${GREEN}✅ ACTIVE INSTANCES (still exist in RDS):${NC}"
echo "$ACTIVE_INSTANCES" | while read -r instance; do
    echo "   🟢 $instance"
done
echo ""

echo -e "${YELLOW}⚠️  DELETED INSTANCES (metrics only, no RDS instance):${NC}"
DELETED=0
echo "$INSTANCES" | while read -r instance; do
    if ! echo "$ACTIVE_INSTANCES" | grep -q "^${instance}$"; then
        echo "   ❌ $instance"
        DELETED=$((DELETED + 1))
    fi
done
echo ""

# Check for alarms
echo -e "${BLUE}Checking for CloudWatch Alarms...${NC}"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --profile "$PROFILE" \
    --region "$REGION" \
    --output json | \
    jq '[.MetricAlarms[] | select(.Dimensions[]?.Value | contains("bingo-stress"))] | length')

if [ "$ALARM_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ No alarms configured for bingo-stress instances${NC}"
else
    echo -e "${RED}⚠️  Found $ALARM_COUNT alarms${NC}"
fi
echo ""

# Verbose mode - list all metrics
if [ "$1" = "--verbose" ] || [ "$1" = "-v" ]; then
    echo "========================================================================"
    echo "All Metrics (Verbose Mode)"
    echo "========================================================================"
    echo ""

    echo "$INSTANCES" | while read -r instance; do
        # Check if active
        if echo "$ACTIVE_INSTANCES" | grep -q "^${instance}$"; then
            echo -e "${GREEN}🟢 $instance${NC} (ACTIVE)"
        else
            echo -e "${YELLOW}❌ $instance${NC} (DELETED)"
        fi

        # List metrics for this instance
        METRIC_NAMES=$(aws cloudwatch list-metrics \
            --profile "$PROFILE" \
            --region "$REGION" \
            --output json | \
            jq -r ".Metrics[] | select(.Dimensions[]?.Value == \"$instance\") | .MetricName" | \
            sort -u | \
            head -10)

        METRIC_COUNT=$(echo "$METRIC_NAMES" | wc -l | tr -d ' ')
        echo "   Metrics: $METRIC_COUNT (showing first 10)"
        echo "$METRIC_NAMES" | while read -r metric; do
            echo "      - $metric"
        done
        echo ""
    done
fi

echo "========================================================================"
echo "Summary"
echo "========================================================================"
echo "Total instances with metrics: $INSTANCE_COUNT"
echo "Active RDS instances: $ACTIVE_COUNT"
echo "Deleted instances (stale metrics): $((INSTANCE_COUNT - ACTIVE_COUNT))"
echo "CloudWatch Alarms: $ALARM_COUNT"
echo ""
echo "💡 Tip: Run with --verbose flag to see all metrics for each instance"
echo "💡 CloudWatch metrics auto-expire after 15 months of no new data"
echo ""
echo "📚 For detailed analysis, see:"
echo "   CLOUDWATCH_BINGO_STRESS_ANALYSIS.md"
echo "========================================================================"

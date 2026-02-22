#!/usr/bin/env bash
#
# Check all PROD RDS instances for CloudWatch alarms
#

set -euo pipefail

PROFILE="gemini-pro_ck"
REGION="ap-east-1"

INSTANCES=(
  "bingo-prd:2750"
  "bingo-prd-backstage:5024"
  "bingo-prd-backstage-replica1:1465"
  "bingo-prd-loyalty:200"
  "bingo-prd-replica1:2929"
)

echo "========================================="
echo "PROD RDS Alarm Configuration Check"
echo "========================================="
echo ""

printf "%-30s | %-8s | %-7s | %-15s | %-8s | %-16s | %-7s\n" \
  "Instance" "Storage" "Warning" "W-Threshold" "Critical" "C-Threshold" "Slack"
echo "--------------------------------------------------------------------------------------------------------------"

for ENTRY in "${INSTANCES[@]}"; do
  INSTANCE="${ENTRY%:*}"
  STORAGE="${ENTRY#*:}"

  WARNING_ALARM="RDS-${INSTANCE}-LowDiskSpace-Warning"
  CRITICAL_ALARM="RDS-${INSTANCE}-LowDiskSpace-Critical"

  # Check Warning alarm
  WARNING_EXISTS=$(aws --profile "${PROFILE}" cloudwatch describe-alarms \
    --alarm-names "${WARNING_ALARM}" \
    --region "${REGION}" \
    --query 'MetricAlarms[0]' \
    --output json 2>/dev/null || echo "null")

  if [ "${WARNING_EXISTS}" != "null" ]; then
    WARNING_THRESHOLD=$(echo "${WARNING_EXISTS}" | jq -r '.Threshold // 0')
    WARNING_THRESHOLD_GB=$(echo "scale=1; ${WARNING_THRESHOLD} / 1073741824" | bc)
    WARNING_HAS_SNS=$(echo "${WARNING_EXISTS}" | jq -r '.AlarmActions | length > 0')
    WARNING_STATUS="✅"
  else
    WARNING_THRESHOLD_GB="N/A"
    WARNING_HAS_SNS="false"
    WARNING_STATUS="❌"
  fi

  # Check Critical alarm
  CRITICAL_EXISTS=$(aws --profile "${PROFILE}" cloudwatch describe-alarms \
    --alarm-names "${CRITICAL_ALARM}" \
    --region "${REGION}" \
    --query 'MetricAlarms[0]' \
    --output json 2>/dev/null || echo "null")

  if [ "${CRITICAL_EXISTS}" != "null" ]; then
    CRITICAL_THRESHOLD=$(echo "${CRITICAL_EXISTS}" | jq -r '.Threshold // 0')
    CRITICAL_THRESHOLD_GB=$(echo "scale=1; ${CRITICAL_THRESHOLD} / 1073741824" | bc)
    CRITICAL_HAS_SNS=$(echo "${CRITICAL_EXISTS}" | jq -r '.AlarmActions | length > 0')
    CRITICAL_STATUS="✅"
  else
    CRITICAL_THRESHOLD_GB="N/A"
    CRITICAL_HAS_SNS="false"
    CRITICAL_STATUS="❌"
  fi

  # Check if has Slack notification
  if [ "${WARNING_HAS_SNS}" == "true" ] || [ "${CRITICAL_HAS_SNS}" == "true" ]; then
    SLACK_STATUS="✅"
  else
    SLACK_STATUS="❌"
  fi

  printf "%-30s | %-8s | %-7s | %-15s | %-8s | %-16s | %-7s\n" \
    "${INSTANCE}" "${STORAGE} GB" "${WARNING_STATUS}" "${WARNING_THRESHOLD_GB} GB" \
    "${CRITICAL_STATUS}" "${CRITICAL_THRESHOLD_GB} GB" "${SLACK_STATUS}"
done

echo ""
echo "Legend:"
echo "  ✅ = Alarm exists"
echo "  ❌ = Alarm missing"
echo ""

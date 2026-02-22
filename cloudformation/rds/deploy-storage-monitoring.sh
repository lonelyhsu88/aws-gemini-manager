#!/usr/bin/env bash
#
# Deploy RDS Storage Monitoring CloudFormation Stack
#
# Usage:
#   ./deploy-storage-monitoring.sh [email]
#
# Example:
#   ./deploy-storage-monitoring.sh lonely.h@jvd.tw

set -euo pipefail

PROFILE="gemini-pro_ck"
REGION="ap-east-1"
STACK_NAME="bingo-rds-storage-monitoring"
TEMPLATE_FILE="$(dirname "$0")/bingo-storage-monitoring.yaml"

# Alert email from parameter or default
ALERT_EMAIL="${1:-lonely.h@jvd.tw}"

echo "========================================="
echo "Deploying RDS Storage Monitoring Stack"
echo "========================================="
echo ""
echo "Stack Name: ${STACK_NAME}"
echo "Template: ${TEMPLATE_FILE}"
echo "Region: ${REGION}"
echo "Alert Email: ${ALERT_EMAIL}"
echo ""

# Check if stack exists
STACK_STATUS=$(aws --profile "${PROFILE}" cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "${STACK_STATUS}" == "DOES_NOT_EXIST" ]; then
  echo "Creating new stack..."
  ACTION="create-stack"
else
  echo "Updating existing stack (current status: ${STACK_STATUS})..."
  ACTION="update-stack"
fi

# Deploy stack
aws --profile "${PROFILE}" cloudformation ${ACTION} \
  --stack-name "${STACK_NAME}" \
  --template-body "file://${TEMPLATE_FILE}" \
  --parameters \
    ParameterKey=AlertEmail,ParameterValue="${ALERT_EMAIL}" \
    ParameterKey=BingoPrdStorageGB,ParameterValue=2750 \
    ParameterKey=BingoPrdReplica1StorageGB,ParameterValue=2929 \
    ParameterKey=AlertThresholdPercent,ParameterValue=15 \
  --tags \
    Key=Environment,Value=Production \
    Key=Service,Value=RDS \
    Key=ManagedBy,Value=CloudFormation \
  --region "${REGION}"

if [ "${ACTION}" == "create-stack" ]; then
  echo ""
  echo "Waiting for stack creation to complete..."
  aws --profile "${PROFILE}" cloudformation wait stack-create-complete \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"
  echo "✅ Stack created successfully!"
else
  echo ""
  echo "Waiting for stack update to complete..."
  aws --profile "${PROFILE}" cloudformation wait stack-update-complete \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" 2>/dev/null || true
  echo "✅ Stack updated successfully!"
fi

# Get outputs
echo ""
echo "========================================="
echo "Stack Outputs"
echo "========================================="
aws --profile "${PROFILE}" cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. ⚠️  Check your email (${ALERT_EMAIL}) and confirm SNS subscription"
echo "2. 📊 View alarms in CloudWatch console:"
echo "   https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:"
echo ""
echo "3. 🔔 Alarms will trigger when:"
echo "   - bingo-prd free storage < 412.5 GB (15%)"
echo "   - bingo-prd-replica1 free storage < 439.35 GB (15%)"
echo ""
echo "4. ⚡ Current status:"
echo "   - bingo-prd: ~325 GB free (11.8%) ⚠️ WILL TRIGGER SOON"
echo "   - bingo-prd-replica1: ~530 GB free (18.1%) ✅ OK"
echo ""

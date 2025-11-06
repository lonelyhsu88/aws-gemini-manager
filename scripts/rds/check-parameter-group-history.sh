#!/bin/bash

# RDS Parameter Group History Checker
# 检查参数组的修改历史和待重启状态

set -euo pipefail

AWS_PROFILE="gemini-pro_ck"
PARAM_GROUP="postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2"

echo "================================================================"
echo "RDS Parameter Group History Analysis"
echo "================================================================"
echo ""

# 1. 参数组基本信息
echo "1. Parameter Group Information:"
echo "----------------------------------------------------------------"
aws --profile "$AWS_PROFILE" rds describe-db-parameter-groups \
    --db-parameter-group-name "$PARAM_GROUP" \
    --query 'DBParameterGroups[0].{Name:DBParameterGroupName,Family:DBParameterGroupFamily,Description:Description}' \
    --output table

echo ""
echo "2. CloudFormation Stack Information:"
echo "----------------------------------------------------------------"
aws --profile "$AWS_PROFILE" cloudformation describe-stacks \
    --stack-name postgresql14-monitoring-params \
    --query 'Stacks[0].{Created:CreationTime,Updated:LastUpdatedTime,Status:StackStatus}' \
    --output table 2>/dev/null || echo "No CloudFormation stack found or error occurred"

echo ""
echo "3. All RDS Instances using this Parameter Group:"
echo "----------------------------------------------------------------"
aws --profile "$AWS_PROFILE" rds describe-db-instances \
    --query "DBInstances[?DBParameterGroups[0].DBParameterGroupName=='$PARAM_GROUP'].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,ParamStatus:DBParameterGroups[0].ParameterApplyStatus,Engine:Engine}" \
    --output table

echo ""
echo "4. Instances with pending-reboot status:"
echo "----------------------------------------------------------------"
aws --profile "$AWS_PROFILE" rds describe-db-instances \
    --query "DBInstances[?DBParameterGroups[0].DBParameterGroupName=='$PARAM_GROUP' && DBParameterGroups[0].ParameterApplyStatus=='pending-reboot'].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus,ParamStatus:DBParameterGroups[0].ParameterApplyStatus}" \
    --output table

echo ""
echo "5. Recent CloudTrail Events (Last 90 days):"
echo "----------------------------------------------------------------"
echo "Looking for ModifyDBInstance events for instances with pending-reboot..."

PENDING_INSTANCES=$(aws --profile "$AWS_PROFILE" rds describe-db-instances \
    --query "DBInstances[?DBParameterGroups[0].DBParameterGroupName=='$PARAM_GROUP' && DBParameterGroups[0].ParameterApplyStatus=='pending-reboot'].DBInstanceIdentifier" \
    --output text)

if [ -n "$PENDING_INSTANCES" ]; then
    for instance in $PENDING_INSTANCES; do
        echo ""
        echo "Events for instance: $instance"
        echo "............................................................"
        aws --profile "$AWS_PROFILE" cloudtrail lookup-events \
            --lookup-attributes AttributeKey=ResourceName,AttributeValue="$instance" \
            --max-results 20 \
            --query 'Events[*].[EventTime,EventName,Username]' \
            --output table || echo "No events found for $instance"
    done
else
    echo "No instances with pending-reboot status"
fi

echo ""
echo "6. Parameter Group Modification History:"
echo "----------------------------------------------------------------"
echo "Looking for ModifyDBParameterGroup events..."
aws --profile "$AWS_PROFILE" cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=ModifyDBParameterGroup \
    --max-results 20 \
    --query 'Events[*].[EventTime,EventName,Username]' \
    --output table || echo "No ModifyDBParameterGroup events found in last 90 days"

echo ""
echo "7. CloudFormation Stack Update Events:"
echo "----------------------------------------------------------------"
aws --profile "$AWS_PROFILE" cloudformation describe-stack-events \
    --stack-name postgresql14-monitoring-params \
    --max-items 20 \
    --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]' \
    --output table 2>/dev/null || echo "No stack events found or error occurred"

echo ""
echo "================================================================"
echo "Analysis Complete"
echo "================================================================"
echo ""
echo "Summary:"
echo "- If ParameterApplyStatus shows 'pending-reboot', a reboot is required"
echo "- Use 'aws rds reboot-db-instance --db-instance-identifier <name>' to apply changes"
echo "- Check CloudTrail events above to determine when parameters were modified"
echo ""

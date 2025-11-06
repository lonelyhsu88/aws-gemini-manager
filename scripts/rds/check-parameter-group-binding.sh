#!/bin/bash

# Check when parameter group was bound to bingo-prd instances

set -euo pipefail

AWS_PROFILE="gemini-pro_ck"
TARGET_PARAM_GROUP="postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2"

echo "================================================================"
echo "Checking Parameter Group Binding History for bingo-prd-* instances"
echo "================================================================"
echo ""
echo "Target Parameter Group: $TARGET_PARAM_GROUP"
echo "Parameter Group Created: 2024-11-13 21:39 (UTC+8)"
echo ""
echo "================================================================"
echo ""

INSTANCES=("bingo-prd" "bingo-prd-backstage" "bingo-prd-loyalty" "bingo-prd-replica1" "bingo-prd-backstage-replica1")

for instance in "${INSTANCES[@]}"; do
    echo "----------------------------------------"
    echo "Instance: $instance"
    echo "----------------------------------------"

    # Get all ModifyDBInstance events
    EVENTS=$(aws --profile "$AWS_PROFILE" cloudtrail lookup-events \
        --lookup-attributes AttributeKey=ResourceName,AttributeValue="$instance" \
        --max-results 100 \
        --query 'Events[?EventName==`ModifyDBInstance`]' \
        --output json)

    # Check for parameter group changes
    echo "$EVENTS" | python3 << 'PYTHON_EOF'
import json, sys

events = json.load(sys.stdin)
found = False

for event in events:
    event_data = json.loads(event['CloudTrailEvent'])
    req_params = event_data['requestParameters']

    if 'dBParameterGroupName' in req_params:
        print(f"✅ Parameter Group Changed:")
        print(f"   Time: {event['EventTime']}")
        print(f"   User: {event['Username']}")
        print(f"   New Parameter Group: {req_params['dBParameterGroupName']}")
        print(f"   Apply Immediately: {req_params.get('applyImmediately', 'N/A')}")
        found = True
        break

if not found:
    print("❌ No parameter group changes found in last 90 days")
    print("   (Parameter group binding may have occurred before CloudTrail retention period)")

PYTHON_EOF

    echo ""
done

echo "================================================================"
echo ""
echo "📋 Summary:"
echo ""
echo "1. Parameter Group创建时间: 2024-11-13 21:39 (UTC+8)"
echo "2. bingo-prd-*实例在 2025-11-03 08:08-08:12 被重启"
echo "3. 如果没有找到参数组绑定记录，说明绑定发生在90天前（CloudTrail保留期限外）"
echo ""
echo "结论："
echo "- 参数组可能是在创建时（2024-11-13）就立即绑定到所有实例"
echo "- bingo-prd-*实例在 11月3日重启后应用了参数组变更"
echo "- pgsqlrel实例没有重启，所以状态仍为 pending-reboot"
echo ""
echo "================================================================"

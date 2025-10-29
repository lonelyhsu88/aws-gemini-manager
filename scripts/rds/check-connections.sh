#!/bin/bash

# RDS instances list
instances=(
  "bingo-prd:db.m6g.large:901"
  "bingo-prd-backstage:db.m6g.large:901"
  "bingo-prd-backstage-replica1:db.t4g.medium:450"
  "bingo-prd-loyalty:db.t4g.medium:450"
  "bingo-prd-replica1:db.m6g.large:901"
  "bingo-stress:db.t4g.medium:450"
  "bingo-stress-backstage:db.t4g.medium:450"
  "bingo-stress-loyalty:db.t4g.medium:450"
  "pgsqlrel:db.t3.small:225"
  "pgsqlrel-backstage:db.t3.micro:112"
)

echo "RDS Database Connections Report"
echo "================================"
echo ""
printf "%-35s %-20s %-15s %-15s %-10s\n" "Instance" "Type" "Max Conn" "Avg Conn (5m)" "Usage %"
printf "%-35s %-20s %-15s %-15s %-10s\n" "--------" "----" "--------" "--------------" "-------"

for instance_info in "${instances[@]}"; do
  IFS=':' read -r instance_id instance_type max_conn <<< "$instance_info"
  
  # Get CloudWatch metrics for last 5 minutes
  avg_conn=$(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
    --statistics Average \
    --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 300 \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null)
  
  if [ "$avg_conn" == "None" ] || [ -z "$avg_conn" ]; then
    avg_conn="N/A"
    usage="N/A"
  else
    avg_conn=$(printf "%.0f" "$avg_conn")
    usage=$(awk "BEGIN {printf \"%.1f\", ($avg_conn / $max_conn) * 100}")
  fi
  
  printf "%-35s %-20s %-15s %-15s %-10s\n" "$instance_id" "$instance_type" "$max_conn" "$avg_conn" "$usage%"
done

echo ""
echo "Note: Max connections calculated using formula: LEAST(DBInstanceClassMemory/9531392, 5000)"

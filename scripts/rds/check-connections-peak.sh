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

echo "RDS Database Connections Report (Last 24 Hours)"
echo "================================================"
echo ""
printf "%-35s %-15s %-15s %-15s %-15s %-10s\n" "Instance" "Max Conn" "Current Avg" "Peak (24h)" "Min (24h)" "Peak %"
printf "%-35s %-15s %-15s %-15s %-15s %-10s\n" "--------" "--------" "-----------" "-----------" "----------" "------"

for instance_info in "${instances[@]}"; do
  IFS=':' read -r instance_id instance_type max_conn <<< "$instance_info"
  
  # Get current (last 5 min)
  current=$(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
    --statistics Average \
    --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 300 \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null)
  
  # Get peak (last 24h)
  peak=$(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
    --statistics Maximum \
    --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 3600 \
    --query 'max(Datapoints[].Maximum)' \
    --output text 2>/dev/null)
  
  # Get minimum (last 24h)
  min=$(aws --profile gemini-pro_ck cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value="$instance_id" \
    --statistics Minimum \
    --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S)Z \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
    --period 3600 \
    --query 'min(Datapoints[].Minimum)' \
    --output text 2>/dev/null)
  
  if [ "$current" == "None" ] || [ -z "$current" ]; then
    current="N/A"
  else
    current=$(printf "%.0f" "$current")
  fi
  
  if [ "$peak" == "None" ] || [ -z "$peak" ]; then
    peak="N/A"
    peak_pct="N/A"
  else
    peak=$(printf "%.0f" "$peak")
    peak_pct=$(awk "BEGIN {printf \"%.1f\", ($peak / $max_conn) * 100}")
  fi
  
  if [ "$min" == "None" ] || [ -z "$min" ]; then
    min="N/A"
  else
    min=$(printf "%.0f" "$min")
  fi
  
  printf "%-35s %-15s %-15s %-15s %-15s %-10s\n" "$instance_id" "$max_conn" "$current" "$peak" "$min" "$peak_pct%"
done

echo ""
echo "Memory-based max_connections formula: LEAST(DBInstanceClassMemory/9531392, 5000)"
echo ""
echo "Instance Type Memory:"
echo "  db.m6g.large  = 8 GB  → max_connections = 901"
echo "  db.t4g.medium = 4 GB  → max_connections = 450"
echo "  db.t3.small   = 2 GB  → max_connections = 225"
echo "  db.t3.micro   = 1 GB  → max_connections = 112"

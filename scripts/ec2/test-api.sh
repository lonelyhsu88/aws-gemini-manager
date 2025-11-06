#!/bin/bash
echo "=== API 延遲測試 ==="
echo "測試時間: $(date)"
echo ""

API1="https://ds-r.geminiservice.cc/domains?type=Hash"
API2="https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"

for api in "$API1" "$API2"; do
  echo "測試: $api"
  total=0
  for i in {1..5}; do
    time=$(curl -w "%{time_total}" -o /dev/null -s "$api" 2>/dev/null)
    echo "  第 $i 次: ${time}s"
    total=$(awk "BEGIN {print $total + $time}")
  done
  avg=$(awk "BEGIN {print $total / 5}")
  echo "  平均: ${avg}s"
  echo ""
done

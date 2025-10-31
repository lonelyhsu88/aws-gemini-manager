#!/bin/bash

echo "=== API 延遲測試 (從台北) ==="
echo ""

APIs=(
  "https://ds-r.geminiservice.cc/domains?type=Hash"
  "https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"
  "https://www.shuangzi6688.com/"
  "https://hash.shuangzi6688.com/"
)

for api in "${APIs[@]}"; do
  echo "測試: $api"
  curl -w "總時間: %{time_total}s | DNS: %{time_namelookup}s | 連接: %{time_connect}s | TLS: %{time_appconnect}s | 首字節: %{time_starttransfer}s\n" \
    -o /dev/null -s "$api"
  echo ""
  sleep 1
done

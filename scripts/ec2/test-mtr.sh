#!/bin/bash
echo "=== MTR 網路路徑測試 ==="
echo "測試時間: $(date)"
echo ""

TARGETS=(
  "a23-55-244-43.deploy.static.akamaitechnologies.com"
  "ds-r.geminiservice.cc.edgesuite.net"
  "gameinfo-api.geminiservice.cc.edgesuite.net"
)

for target in "${TARGETS[@]}"; do
  echo "======================================"
  echo "目標: $target"
  echo "======================================"
  sudo mtr --report --report-cycles 30 --no-dns "$target"
  echo ""
done

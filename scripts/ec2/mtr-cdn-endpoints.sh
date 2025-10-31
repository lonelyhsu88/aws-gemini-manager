#!/bin/bash

# MTR 測試 Akamai CDN 端點
# 測試 API 域名的 CDN 節點網路路徑

set -e

echo "=== MTR 測試 - API CDN 端點 ==="
echo "測試時間: $(date)"
echo ""

# 測試目標
TARGETS=(
  "ds-r.geminiservice.cc.edgesuite.net"
  "gameinfo-api.geminiservice.cc.edgesuite.net"
)

# MTR 參數
PACKET_COUNT=60
REPORT_CYCLES=1

# 創建結果目錄
RESULT_DIR="mtr-results-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "結果將保存到: $RESULT_DIR"
echo ""

# 對每個目標執行 MTR
for target in "${TARGETS[@]}"; do
    echo "======================================"
    echo "測試目標: $target"
    echo "======================================"

    # 先解析 DNS
    echo "DNS 解析:"
    dig +short "$target" | head -5
    echo ""

    # 執行 MTR 測試
    echo "執行 MTR 測試 (60 封包)..."
    OUTPUT_FILE="$RESULT_DIR/${target}-60packets.txt"

    sudo mtr \
      --report \
      --report-cycles "$PACKET_COUNT" \
      --no-dns \
      "$target" | tee "$OUTPUT_FILE"

    echo ""
    echo "結果已保存到: $OUTPUT_FILE"
    echo ""

    # 等待 2 秒再測試下一個
    if [ "$target" != "${TARGETS[-1]}" ]; then
        echo "等待 2 秒..."
        sleep 2
    fi
done

echo "======================================"
echo "所有測試完成！"
echo "======================================"
echo ""
echo "結果摘要:"
ls -lh "$RESULT_DIR"
echo ""

# 生成摘要報告
SUMMARY_FILE="$RESULT_DIR/SUMMARY.md"
cat > "$SUMMARY_FILE" <<EOF
# MTR 測試摘要報告

**測試時間**: $(date)
**測試位置**: 孟買 (AWS ap-south-1)
**測試目標**: API CDN 端點

## 測試結果

EOF

for target in "${TARGETS[@]}"; do
    cat >> "$SUMMARY_FILE" <<EOF
### $target

\`\`\`
$(cat "$RESULT_DIR/${target}-60packets.txt")
\`\`\`

---

EOF
done

echo "摘要報告已生成: $SUMMARY_FILE"

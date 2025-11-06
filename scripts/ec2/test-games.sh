#!/bin/bash
echo "=== 遊戲加載速度測試 ==="
echo "測試時間: $(date)"
echo ""

GAME_URLS_FILE="game-urls-list.txt"

if [ ! -f "$GAME_URLS_FILE" ]; then
    echo "錯誤: $GAME_URLS_FILE 不存在"
    exit 1
fi

# 讀取前5個遊戲
mapfile -t GAME_LINES < <(head -5 "$GAME_URLS_FILE")

RESULTS_DIR="game-test-results-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

for line in "${GAME_LINES[@]}"; do
    game_name=$(echo "$line" | cut -d'|' -f1)
    game_url=$(echo "$line" | cut -d'|' -f2)

    echo "測試遊戲: $game_name"
    echo "URL: $game_url"

    # 執行兩次訪問測試
    OUTPUT_JSON="$RESULTS_DIR/${game_name}_result.json"

    node puppeteer_game_test.js "$game_url" \
        --cache \
        --double-visit \
        --wait=30000 \
        --output="$OUTPUT_JSON" 2>&1 | tee "$RESULTS_DIR/${game_name}_log.txt"

    echo ""
done

# 生成摘要
echo "======================================"
echo "測試摘要"
echo "======================================"

total_first=0
total_second=0
count=0

for json_file in $RESULTS_DIR/*_result.json; do
    if [ -f "$json_file" ]; then
        game=$(basename "$json_file" | sed 's/_result.json//')
        first=$(jq -r '.visits[0].metrics.totalTime // "N/A"' "$json_file" 2>/dev/null)
        second=$(jq -r '.visits[1].metrics.totalTime // "N/A"' "$json_file" 2>/dev/null)

        echo "遊戲: $game"
        echo "  首次: ${first}s"
        echo "  第二次: ${second}s"

        if [ "$first" != "N/A" ] && [ "$second" != "N/A" ]; then
            total_first=$(awk "BEGIN {print $total_first + $first}")
            total_second=$(awk "BEGIN {print $total_second + $second}")
            count=$((count + 1))
        fi
    fi
done

if [ $count -gt 0 ]; then
    avg_first=$(awk "BEGIN {print $total_first / $count}")
    avg_second=$(awk "BEGIN {print $total_second / $count}")
    improvement=$(awk "BEGIN {print (($avg_first - $avg_second) / $avg_first) * 100}")

    echo ""
    echo "平均結果:"
    echo "  首次訪問: ${avg_first}s"
    echo "  第二次訪問: ${avg_second}s"
    echo "  改善: ${improvement}%"
fi

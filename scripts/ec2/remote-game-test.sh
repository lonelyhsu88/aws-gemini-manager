#!/bin/bash

################################################################################
# 遠端遊戲緩存測試腳本 (EC2 上執行)
# 測試 N 個遊戲的緩存效果（雙重訪問模式）
################################################################################

set -e

NUM_GAMES="${1:-5}"
LANG="${2:-zh-CN}"
WAIT_TIME="${3:-15000}"

echo "=============================================="
echo "遊戲緩存對比測試"
echo "=============================================="
echo "測試遊戲數量: $NUM_GAMES"
echo "語言: $LANG"
echo "等待時間: $WAIT_TIME ms"
echo "測試時間: $(date)"
echo ""

# API 配置
API_URL="https://wallet-api.geminiservice.cc/api/v1/operator/game/launch"
USERNAME="optest01"
PRODUCT_ID="ELS"

# 可用遊戲列表（精簡版）
ALL_GAMES=(
    "ArcadeBingo"
    "BonusBingo"
    "CaribbeanBingo"
    "MultiPlayerAviator"
    "StandAlonePlinko"
    "StandAloneMines"
    "StandAloneDice"
    "StandAloneHilo"
    "MultiPlayerCrash"
    "MagicBingo"
)

# 生成 MD5 hash
get_md5() {
    local input="$1"
    if command -v md5 &> /dev/null; then
        echo -n "$input" | md5 -q
    else
        echo -n "$input" | md5sum | cut -d' ' -f1
    fi
}

# 獲取遊戲 URL
get_game_url() {
    local game="$1"
    local lang="$2"
    local seq="$(date +%s)$(( RANDOM % 1000 ))"
    local payload="{\"seq\":\"$seq\",\"product_id\":\"$PRODUCT_ID\",\"username\":\"$USERNAME\",\"gametype\":\"$game\",\"lang\":\"$lang\"}"
    local md5_hash=$(get_md5 "xdr56yhn${payload}")

    local response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "els-access-key: $md5_hash" \
        -d "$payload")

    # 提取 URL
    local url=$(echo "$response" | grep -o '"url":"[^"]*"' | sed 's/"url":"//;s/"$//' | sed 's/\\u0026/\&/g')

    # 轉換域名
    echo "$url" | sed 's|jump.shuangzi6666.com|www.shuangzi6688.com|'
}

# 隨機選擇遊戲
echo "======================================"
echo "步驟 1: 隨機選擇 $NUM_GAMES 個遊戲"
echo "======================================"

SELECTED_GAMES=()
TEMP_GAMES=("${ALL_GAMES[@]}")

for ((i=0; i<NUM_GAMES && i<${#ALL_GAMES[@]}; i++)); do
    idx=$(( RANDOM % ${#TEMP_GAMES[@]} ))
    SELECTED_GAMES+=("${TEMP_GAMES[$idx]}")
    # 移除已選擇的遊戲
    TEMP_GAMES=("${TEMP_GAMES[@]:0:$idx}" "${TEMP_GAMES[@]:$((idx+1))}")
done

echo "已選擇遊戲:"
for ((i=0; i<${#SELECTED_GAMES[@]}; i++)); do
    echo "  $((i+1)). ${SELECTED_GAMES[$i]}"
done
echo ""

# 獲取遊戲 URLs
echo "======================================"
echo "步驟 2: 獲取遊戲 URLs"
echo "======================================"

GAME_URLS=()
GAME_NAMES=()

for game in "${SELECTED_GAMES[@]}"; do
    echo "獲取 $game 的 URL..."
    url=$(get_game_url "$game" "$LANG")

    if [ -n "$url" ]; then
        echo "  ✓ 成功"
        GAME_URLS+=("$url")
        GAME_NAMES+=("$game")
    else
        echo "  ✗ 失敗"
    fi
done

echo ""
echo "成功獲取 ${#GAME_URLS[@]} 個遊戲 URL"
echo ""

if [ ${#GAME_URLS[@]} -eq 0 ]; then
    echo "錯誤: 沒有獲取到任何遊戲 URL"
    exit 1
fi

# 創建結果目錄
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="game-cache-test-${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# 執行遊戲測試
echo "======================================"
echo "步驟 3: 執行緩存對比測試"
echo "======================================"
echo ""

for ((i=0; i<${#GAME_URLS[@]}; i++)); do
    game="${GAME_NAMES[$i]}"
    url="${GAME_URLS[$i]}"

    echo "----------------------------------------"
    echo "測試 [$((i+1))/${#GAME_URLS[@]}]: $game"
    echo "----------------------------------------"

    OUTPUT_JSON="$RESULTS_DIR/${game}.json"

    # 使用 Puppeteer 測試（雙重訪問模式）
    node puppeteer_game_test.js "$url" \
        --cache \
        --double-visit \
        --wait="$WAIT_TIME" \
        --output="$OUTPUT_JSON" || echo "測試失敗: $game"

    echo ""
    sleep 2
done

# 生成摘要報告
echo "======================================"
echo "步驟 4: 生成摘要報告"
echo "======================================"

cat > "$RESULTS_DIR/analyze.js" << 'EOF'
const fs = require('fs');
const resultsDir = process.argv[2];

const gameFiles = fs.readdirSync(resultsDir).filter(f => f.endsWith('.json'));
const results = [];

gameFiles.forEach(file => {
    try {
        const data = JSON.parse(fs.readFileSync(`${resultsDir}/${file}`, 'utf8'));

        if (data.firstVisit && data.secondVisit && data.comparison) {
            results.push({
                name: file.replace('.json', ''),
                firstVisit: data.firstVisit.totalTime || 0,
                secondVisit: data.secondVisit.totalTime || 0,
                improvement: data.comparison.timeImprovement || 0,
                cacheHitRate: data.comparison.cacheHitRate || 0
            });
        }
    } catch (e) {
        console.error(`Error: ${file} - ${e.message}`);
    }
});

if (results.length === 0) {
    console.log('沒有有效的測試結果');
    process.exit(1);
}

console.log('');
console.log('═══════════════════════════════════════════════════════════════');
console.log('                     遊戲緩存測試結果摘要');
console.log('═══════════════════════════════════════════════════════════════');
console.log('');
console.log('遊戲名稱'.padEnd(30) + '首次(s)'.padStart(10) + '第2次(s)'.padStart(10) + '改善%'.padStart(10) + '緩存率%'.padStart(10));
console.log('─'.repeat(70));

results.forEach(r => {
    const first = (r.firstVisit / 1000).toFixed(2);
    const second = (r.secondVisit / 1000).toFixed(2);
    console.log(
        r.name.padEnd(30) +
        first.padStart(10) +
        second.padStart(10) +
        r.improvement.toFixed(1).padStart(10) +
        r.cacheHitRate.toFixed(1).padStart(10)
    );
});

console.log('─'.repeat(70));

const avgFirst = results.reduce((a, b) => a + b.firstVisit, 0) / results.length / 1000;
const avgSecond = results.reduce((a, b) => a + b.secondVisit, 0) / results.length / 1000;
const avgImprovement = results.reduce((a, b) => a + b.improvement, 0) / results.length;
const avgCacheHitRate = results.reduce((a, b) => a + b.cacheHitRate, 0) / results.length;

console.log(
    '平均'.padEnd(30) +
    avgFirst.toFixed(2).padStart(10) +
    avgSecond.toFixed(2).padStart(10) +
    avgImprovement.toFixed(1).padStart(10) +
    avgCacheHitRate.toFixed(1).padStart(10)
);

console.log('');
console.log('關鍵指標:');
console.log('  • 測試遊戲數: ' + results.length);
console.log('  • 平均改善: ' + avgImprovement.toFixed(1) + '%');
console.log('  • 平均緩存率: ' + avgCacheHitRate.toFixed(1) + '%');
console.log('  • 平均首次加載: ' + avgFirst.toFixed(2) + ' 秒');
console.log('  • 平均第2次加載: ' + avgSecond.toFixed(2) + ' 秒');
console.log('  • 平均節省時間: ' + (avgFirst - avgSecond).toFixed(2) + ' 秒');
console.log('');

// 保存 CSV
const csv = 'Game,FirstVisit(s),SecondVisit(s),Improvement(%),CacheHitRate(%)\n' +
    results.map(r => `${r.name},${(r.firstVisit/1000).toFixed(2)},${(r.secondVisit/1000).toFixed(2)},${r.improvement.toFixed(1)},${r.cacheHitRate.toFixed(1)}`).join('\n') +
    `\n平均,${avgFirst.toFixed(2)},${avgSecond.toFixed(2)},${avgImprovement.toFixed(1)},${avgCacheHitRate.toFixed(1)}`;

fs.writeFileSync(`${resultsDir}/summary.csv`, csv);
console.log('📁 結果已保存: ' + resultsDir + '/summary.csv');
console.log('');
EOF

node "$RESULTS_DIR/analyze.js" "$RESULTS_DIR" | tee "$RESULTS_DIR/summary.txt"

echo ""
echo "=============================================="
echo "測試完成！"
echo "=============================================="
echo "結果目錄: $RESULTS_DIR"
echo "最新結果: $RESULTS_DIR"
ls -lh "$RESULTS_DIR"
echo ""

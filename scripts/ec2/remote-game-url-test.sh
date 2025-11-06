#!/bin/bash

################################################################################
# 遠端遊戲 URL 測試腳本 (EC2 上執行)
# 接受預先獲取的遊戲 URL 列表，進行緩存對比測試
################################################################################

set -e

WAIT_TIME="${1:-15000}"
URL_LIST_FILE="${2:-game-urls.txt}"

echo "=============================================="
echo "遊戲緩存對比測試 (使用預先獲取的 URLs)"
echo "=============================================="
echo "等待時間: $WAIT_TIME ms"
echo "URL 列表文件: $URL_LIST_FILE"
echo "測試時間: $(date)"
echo ""

# 檢查 URL 列表文件是否存在
if [ ! -f "$URL_LIST_FILE" ]; then
    echo "錯誤: URL 列表文件不存在: $URL_LIST_FILE"
    exit 1
fi

# 讀取 URL 列表
echo "======================================"
echo "讀取遊戲 URL 列表"
echo "======================================"

GAME_NAMES=()
GAME_URLS=()

while IFS='|' read -r name url; do
    # 跳過空行和註釋
    [[ -z "$name" || "$name" =~ ^# ]] && continue

    GAME_NAMES+=("$name")
    GAME_URLS+=("$url")
    echo "  ✓ $name"
done < "$URL_LIST_FILE"

echo ""
echo "讀取到 ${#GAME_URLS[@]} 個遊戲 URL"
echo ""

if [ ${#GAME_URLS[@]} -eq 0 ]; then
    echo "錯誤: 沒有有效的遊戲 URL"
    exit 1
fi

# 檢查 puppeteer_game_test.js 是否存在
if [ ! -f "puppeteer_game_test.js" ]; then
    echo "錯誤: puppeteer_game_test.js 不存在"
    exit 1
fi

# 創建結果目錄
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="game-cache-test-${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

# 執行遊戲測試
echo "======================================"
echo "執行緩存對比測試 (雙重訪問模式)"
echo "======================================"
echo ""

for ((i=0; i<${#GAME_URLS[@]}; i++)); do
    game="${GAME_NAMES[$i]}"
    url="${GAME_URLS[$i]}"

    echo "----------------------------------------"
    echo "測試 [$((i+1))/${#GAME_URLS[@]}]: $game"
    echo "----------------------------------------"
    echo "URL: $url"
    echo ""

    OUTPUT_JSON="$RESULTS_DIR/${game}.json"

    # 使用 Puppeteer 測試（雙重訪問模式）
    if node puppeteer_game_test.js "$url" \
        --cache \
        --double-visit \
        --wait="$WAIT_TIME" \
        --output="$OUTPUT_JSON"; then
        echo "  ✓ 測試成功"
    else
        echo "  ✗ 測試失敗"
    fi

    echo ""
    sleep 2
done

# 生成摘要報告
echo "======================================"
echo "生成摘要報告"
echo "======================================"

cat > "$RESULTS_DIR/analyze.js" << 'ANALYZE_EOF'
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
                cacheHitRate: data.comparison.cacheHitRate || 0,
                timeSaved: data.comparison.timeSaved || 0
            });
        }
    } catch (e) {
        console.error(`Error processing ${file}: ${e.message}`);
    }
});

if (results.length === 0) {
    console.log('❌ 沒有有效的測試結果');
    process.exit(1);
}

console.log('');
console.log('═══════════════════════════════════════════════════════════════════════');
console.log('                       遊戲緩存測試結果摘要');
console.log('═══════════════════════════════════════════════════════════════════════');
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
const avgTimeSaved = results.reduce((a, b) => a + b.timeSaved, 0) / results.length / 1000;

console.log(
    '平均'.padEnd(30) +
    avgFirst.toFixed(2).padStart(10) +
    avgSecond.toFixed(2).padStart(10) +
    avgImprovement.toFixed(1).padStart(10) +
    avgCacheHitRate.toFixed(1).padStart(10)
);

console.log('');
console.log('╔════════════════════════════════════════════════════════════════════╗');
console.log('║                          關鍵指標                                   ║');
console.log('╚════════════════════════════════════════════════════════════════════╝');
console.log('');
console.log('  測試遊戲數量:     ' + results.length);
console.log('  平均改善幅度:     ' + avgImprovement.toFixed(1) + '%');
console.log('  平均緩存命中率:   ' + avgCacheHitRate.toFixed(1) + '%');
console.log('  平均首次加載:     ' + avgFirst.toFixed(2) + ' 秒');
console.log('  平均第2次加載:    ' + avgSecond.toFixed(2) + ' 秒');
console.log('  平均節省時間:     ' + avgTimeSaved.toFixed(2) + ' 秒');
console.log('');

// 性能評估
if (avgCacheHitRate > 70) {
    console.log('  ✅ 緩存效能: 優秀 (>70% 命中率)');
} else if (avgCacheHitRate > 50) {
    console.log('  ⚠️  緩存效能: 良好 (50-70% 命中率)');
} else if (avgCacheHitRate > 0) {
    console.log('  ⚠️  緩存效能: 需改善 (<50% 命中率)');
} else {
    console.log('  ❌ 緩存未生效');
}
console.log('');

// 保存 CSV
const csv = 'Game,FirstVisit(s),SecondVisit(s),Improvement(%),CacheHitRate(%),TimeSaved(s)\n' +
    results.map(r =>
        `${r.name},${(r.firstVisit/1000).toFixed(2)},${(r.secondVisit/1000).toFixed(2)},${r.improvement.toFixed(1)},${r.cacheHitRate.toFixed(1)},${(r.timeSaved/1000).toFixed(2)}`
    ).join('\n') +
    `\n平均,${avgFirst.toFixed(2)},${avgSecond.toFixed(2)},${avgImprovement.toFixed(1)},${avgCacheHitRate.toFixed(1)},${avgTimeSaved.toFixed(2)}`;

fs.writeFileSync(`${resultsDir}/summary.csv`, csv);
console.log('📁 結果已保存至: ' + resultsDir + '/summary.csv');
console.log('');
ANALYZE_EOF

node "$RESULTS_DIR/analyze.js" "$RESULTS_DIR" | tee "$RESULTS_DIR/summary.txt"

echo ""
echo "=============================================="
echo "測試完成！"
echo "=============================================="
echo ""
echo "結果目錄: $RESULTS_DIR"
echo ""
echo "文件列表:"
ls -lh "$RESULTS_DIR"
echo ""

# 輸出結果目錄路徑供主腳本使用
echo "RESULTS_DIR=$RESULTS_DIR"

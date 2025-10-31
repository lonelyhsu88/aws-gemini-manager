#!/usr/bin/env bash

################################################################################
# Game Load Test with Pre-fetched URLs
#
# Usage: ./test-with-urls.sh [NUMBER_OF_GAMES] [URLS_FILE]
# Example: ./test-with-urls.sh 10 game-urls-list.txt
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
WAIT_TIME="${WAIT_TIME:-10000}"

# Print functions
print_header() {
    local title="$1"
    local color="${2:-$BLUE}"
    echo -e "\n${color}╔════════════════════════════════════════════════════════╗${NC}"
    printf "${color}║   %-52s ║${NC}\n" "$title"
    echo -e "${color}╚════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }
print_separator() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
}

# Argument parsing
if [ $# -eq 0 ]; then
    print_error "必須指定遊戲數量"
    echo ""
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  $0 <遊戲數量> [URL文件]"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0 5                        # 測試 5 款遊戲（使用默認 URL 文件）"
    echo "  $0 10 game-urls-list.txt   # 測試 10 款遊戲（指定 URL 文件）"
    echo ""
    exit 1
fi

NUM_GAMES=$1
URLS_FILE="${2:-game-urls-list.txt}"

# Validate input
if ! [[ "$NUM_GAMES" =~ ^[0-9]+$ ]] || [ "$NUM_GAMES" -lt 1 ]; then
    print_error "遊戲數量必須是正整數"
    exit 1
fi

# Check if URLs file exists
if [ ! -f "$URLS_FILE" ]; then
    print_error "URL 文件不存在: $URLS_FILE"
    exit 1
fi

# Check if node is available
if ! command -v node &> /dev/null; then
    print_error "Node.js 未安裝"
    exit 1
fi

# Check if puppeteer test script exists
PUPPETEER_SCRIPT="$SCRIPT_DIR/puppeteer_game_test.js"
if [ ! -f "$PUPPETEER_SCRIPT" ]; then
    print_error "Puppeteer 測試腳本不存在: $PUPPETEER_SCRIPT"
    exit 1
fi

################################################################################
# Main Process
################################################################################

print_header "Game Load Test with Pre-fetched URLs"

# Load URLs from file (skip comments and empty lines)
mapfile -t ALL_URL_LINES < <(grep -v '^#' "$URLS_FILE" | grep -v '^$')

TOTAL_AVAILABLE=${#ALL_URL_LINES[@]}
print_info "從 $URLS_FILE 載入了 $TOTAL_AVAILABLE 個遊戲 URL"

if [ "$NUM_GAMES" -gt "$TOTAL_AVAILABLE" ]; then
    print_warning "請求 $NUM_GAMES 個遊戲，但只有 $TOTAL_AVAILABLE 個可用"
    NUM_GAMES=$TOTAL_AVAILABLE
    print_warning "將測試所有 $NUM_GAMES 個遊戲"
fi
echo ""

# Randomly select N games
echo -e "${YELLOW}[Step 1] 隨機選擇 ${NUM_GAMES} 個遊戲...${NC}"
TEMP_INDICES=($(seq 0 $((TOTAL_AVAILABLE - 1))))
SELECTED_GAMES=()
SELECTED_URLS=()

for ((i=0; i<NUM_GAMES; i++)); do
    if [ ${#TEMP_INDICES[@]} -eq 0 ]; then
        break
    fi
    idx=$(( RANDOM % ${#TEMP_INDICES[@]} ))
    selected_idx=${TEMP_INDICES[$idx]}

    # Parse game name and URL from line (format: GameName|URL)
    line="${ALL_URL_LINES[$selected_idx]}"
    game_name=$(echo "$line" | cut -d'|' -f1)
    game_url=$(echo "$line" | cut -d'|' -f2)

    SELECTED_GAMES+=("$game_name")
    SELECTED_URLS+=("$game_url")

    # Remove selected index
    TEMP_INDICES=("${TEMP_INDICES[@]:0:$idx}" "${TEMP_INDICES[@]:$((idx+1))}")
done

print_success "選擇了 ${#SELECTED_GAMES[@]} 個遊戲:"
for ((i=0; i<${#SELECTED_GAMES[@]}; i++)); do
    echo "  $((i+1)). ${SELECTED_GAMES[$i]}"
done
echo ""

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="./puppeteer_results/${NUM_GAMES}_games_mumbai_${TIMESTAMP}"
RESULTS_CSV="./puppeteer_results/${NUM_GAMES}_games_mumbai_${TIMESTAMP}.csv"

mkdir -p "$RESULTS_DIR"

################################################################################
# Run Tests
################################################################################

print_header "開始測試 (雙重訪問模式)" "$MAGENTA"
echo ""
echo -e "${YELLOW}測試方法:${NC}"
echo "  • 第一次訪問: 使用空緩存加載頁面（填充緩存）"
echo "  • 第二次訪問: 使用緩存資源重新加載"
echo "  • 比較加載時間以測量緩存效果"
echo ""
echo -e "${CYAN}測試位置: ap-south-1 (孟買)${NC}"
echo ""

for ((i=0; i<${#SELECTED_GAMES[@]}; i++)); do
    game=${SELECTED_GAMES[$i]}
    url=${SELECTED_URLS[$i]}

    print_separator
    echo -e "${CYAN}測試 [$((i+1))/${#SELECTED_GAMES[@]}]: $game${NC}"
    print_separator
    echo ""

    OUTPUT_JSON="$RESULTS_DIR/${game}.json"

    # Run test with double-visit mode
    if node "$PUPPETEER_SCRIPT" "$url" \
        --cache \
        --double-visit \
        --wait="$WAIT_TIME" \
        --output="$OUTPUT_JSON"; then
        print_success "測試完成"
    else
        print_error "測試失敗"
    fi
    echo ""
    sleep 2
done

################################################################################
# Generate Analysis
################################################################################

print_header "生成分析報告"

# Create analysis script
ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_games.XXXXXX.js)

cat > "$ANALYSIS_SCRIPT" << 'ANALYSIS_EOF'
const fs = require('fs');

const resultsDir = process.argv[2];
const csvFile = process.argv[3];
const numGames = parseInt(process.argv[4]);

// Get all game files
const gameFiles = fs.readdirSync(resultsDir)
    .filter(f => f.endsWith('.json'))
    .sort();

console.log('╔═══════════════════════════════════════════════════════════════════════════╗');
console.log('║      ' + numGames + '款遊戲緩存對比測試結果 - ap-south-1 (孟買)' + ' '.repeat(35 - numGames.toString().length) + '║');
console.log('╚═══════════════════════════════════════════════════════════════════════════╝');
console.log('');

const results = [];

gameFiles.forEach(file => {
    const gameName = file.replace('.json', '');
    const gamePath = `${resultsDir}/${file}`;

    try {
        const data = JSON.parse(fs.readFileSync(gamePath, 'utf8'));

        if (!data.firstVisit || !data.secondVisit || !data.comparison) {
            console.log(`⚠️  跳過 ${gameName} - 非雙重訪問格式`);
            return;
        }

        const firstVisit = data.firstVisit;
        const secondVisit = data.secondVisit;
        const comparison = data.comparison;

        results.push({
            name: gameName,
            firstVisitTime: firstVisit.totalTime || 0,
            secondVisitTime: secondVisit.totalTime || 0,
            improvement: comparison.timeImprovement || 0,
            cacheHitRate: comparison.cacheHitRate || 0,
            timeSaved: comparison.timeSaved || 0,
            totalRequests: firstVisit.totalRequests || 0,
            cachedCount: secondVisit.fromCacheCount || 0
        });
    } catch (error) {
        console.error(`處理 ${gameName} 時出錯: ${error.message}`);
    }
});

if (results.length === 0) {
    console.log('❌ 沒有找到有效的測試結果！');
    process.exit(1);
}

// Summary table
console.log('遊戲名稱'.padEnd(30) + '首次訪問'.padStart(12) + '第2次訪問'.padStart(12) + '改善'.padStart(10) + '緩存率'.padStart(10));
console.log(''.padEnd(74, '-'));

results.forEach(r => {
    const firstSec = (r.firstVisitTime / 1000).toFixed(2);
    const secondSec = (r.secondVisitTime / 1000).toFixed(2);

    console.log(
        r.name.padEnd(30) +
        (firstSec + 's').padStart(12) +
        (secondSec + 's').padStart(12) +
        (r.improvement.toFixed(1) + '%').padStart(10) +
        (r.cacheHitRate.toFixed(1) + '%').padStart(10)
    );
});

console.log(''.padEnd(74, '-'));

// Calculate averages
const avgFirstVisit = results.reduce((a, b) => a + b.firstVisitTime, 0) / results.length / 1000;
const avgSecondVisit = results.reduce((a, b) => a + b.secondVisitTime, 0) / results.length / 1000;
const avgImprovement = results.reduce((a, b) => a + b.improvement, 0) / results.length;
const avgCacheHitRate = results.reduce((a, b) => a + b.cacheHitRate, 0) / results.length;

console.log(
    '平均'.padEnd(30) +
    (avgFirstVisit.toFixed(2) + 's').padStart(12) +
    (avgSecondVisit.toFixed(2) + 's').padStart(12) +
    (avgImprovement.toFixed(1) + '%').padStart(10) +
    (avgCacheHitRate.toFixed(1) + '%').padStart(10)
);

console.log('');
console.log('關鍵發現:');
console.log(''.padEnd(74, '='));
console.log('');
console.log('🌏 測試位置: ap-south-1 (孟買, 印度)');
console.log('📊 測試遊戲數量: ' + results.length + ' 款');
console.log('⚡ 平均改善幅度: ' + avgImprovement.toFixed(1) + '%');
console.log('💾 平均緩存命中率: ' + avgCacheHitRate.toFixed(1) + '%');
console.log('⏱️  平均加載時間:');
console.log('   • 首次訪問（無緩存）: ' + avgFirstVisit.toFixed(2) + ' 秒');
console.log('   • 第2次訪問（有緩存）: ' + avgSecondVisit.toFixed(2) + ' 秒');
console.log('   • 平均節省時間: ' + (avgFirstVisit - avgSecondVisit).toFixed(2) + ' 秒');
console.log('');

// Performance evaluation
if (avgCacheHitRate > 70) {
    console.log('✅ 緩存效能：優秀 (>70% 緩存命中率)');
} else if (avgCacheHitRate > 50) {
    console.log('⚠️  緩存效能：良好 (50-70% 緩存命中率)');
} else if (avgCacheHitRate > 0) {
    console.log('⚠️  緩存效能：需改善 (<50% 緩存命中率)');
} else {
    console.log('❌ 緩存未生效 (0% 緩存命中率)');
}
console.log('');

// Save CSV
const csvContent = '遊戲名稱,首次訪問(秒),第2次訪問(秒),改善(%),緩存率(%),節省時間(秒)\n' +
    results.map(r => {
        return `${r.name},${(r.firstVisitTime/1000).toFixed(2)},${(r.secondVisitTime/1000).toFixed(2)},${r.improvement.toFixed(1)},${r.cacheHitRate.toFixed(1)},${(r.timeSaved/1000).toFixed(2)}`;
    }).join('\n') +
    `\n平均,${avgFirstVisit.toFixed(2)},${avgSecondVisit.toFixed(2)},${avgImprovement.toFixed(1)},${avgCacheHitRate.toFixed(1)},${(avgFirstVisit - avgSecondVisit).toFixed(2)}`;

try {
    fs.writeFileSync(csvFile, csvContent);
    console.log('📁 結果已保存至: ' + csvFile);
} catch (error) {
    console.error('保存 CSV 時出錯: ' + error.message);
}
console.log('');
ANALYSIS_EOF

# Run analysis
node "$ANALYSIS_SCRIPT" "$RESULTS_DIR" "$RESULTS_CSV" "$NUM_GAMES"

# Cleanup
rm -f "$ANALYSIS_SCRIPT"

################################################################################
# Summary
################################################################################

print_header "測試完成"

echo "結果保存至:"
echo -e "  測試數據:  ${GREEN}$RESULTS_DIR${NC}"
echo -e "  匯總 CSV: ${GREEN}$RESULTS_CSV${NC}"
echo ""

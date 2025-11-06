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

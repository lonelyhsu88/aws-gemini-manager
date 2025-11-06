#!/bin/bash

#######################################################
# API 緩存可行性測試腳本
# 目的：驗證 API 是否適合啟用 CDN 緩存
#######################################################

set -e

# 配置
API1="https://ds-r.geminiservice.cc/domains?type=Hash"
API2="https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"

RESULT_DIR="api-cache-analysis-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

echo "======================================"
echo "API 緩存可行性測試"
echo "測試時間: $(date)"
echo "結果目錄: $RESULT_DIR"
echo "======================================"
echo ""

#######################################################
# 測試 1: 響應一致性測試
#######################################################
test_response_consistency() {
    local api_url=$1
    local api_name=$2

    echo "=========================================="
    echo "測試 1: $api_name - 響應一致性"
    echo "=========================================="
    echo "URL: $api_url"
    echo ""

    # 連續請求 5 次，間隔 3 秒
    echo "連續請求 5 次（間隔 3 秒）..."
    for i in {1..5}; do
        curl -s "$api_url" > "$RESULT_DIR/${api_name}_response_${i}.json"
        echo "  第 $i 次請求完成"
        if [ $i -lt 5 ]; then
            sleep 3
        fi
    done

    echo ""
    echo "比較響應差異..."

    # 計算 MD5
    echo "MD5 哈希值:"
    for i in {1..5}; do
        hash=$(md5sum "$RESULT_DIR/${api_name}_response_${i}.json" | cut -d' ' -f1)
        echo "  第 $i 次: $hash"
    done

    # 比較響應
    echo ""
    echo "響應內容差異分析:"
    all_same=true
    for i in {2..5}; do
        diff_result=$(diff "$RESULT_DIR/${api_name}_response_1.json" "$RESULT_DIR/${api_name}_response_${i}.json" || true)
        if [ -z "$diff_result" ]; then
            echo "  ✅ 第 1 次 vs 第 $i 次: 完全相同"
        else
            echo "  ⚠️  第 1 次 vs 第 $i 次: 有差異"
            echo "$diff_result" > "$RESULT_DIR/${api_name}_diff_1_vs_${i}.txt"
            all_same=false
        fi
    done

    echo ""
    if [ "$all_same" = true ]; then
        echo "🎯 結論: 響應完全一致 → ✅ 適合緩存"
        echo "   建議: 可以使用長 TTL (5-10 分鐘)"
    else
        echo "⚠️  結論: 響應有差異 → 需要進一步分析"
        echo "   請查看差異文件: $RESULT_DIR/${api_name}_diff_*.txt"
        echo ""
        echo "   常見差異類型："
        echo "   1. timestamp 字段 → 可緩存（源服務器移除時間戳）"
        echo "   2. token/session → 可緩存（拆分 API）"
        echo "   3. userId/balance → 不可緩存（包含用戶數據）"
    fi

    echo ""
    echo "=========================================="
    echo ""
}

#######################################################
# 測試 2: 響應大小分析
#######################################################
test_response_size() {
    local api_url=$1
    local api_name=$2

    echo "=========================================="
    echo "測試 2: $api_name - 響應大小"
    echo "=========================================="

    response_file="$RESULT_DIR/${api_name}_response_1.json"

    # 原始大小
    raw_size=$(wc -c < "$response_file")

    # 壓縮後大小
    gzip -c "$response_file" > "$RESULT_DIR/${api_name}_response.json.gz"
    compressed_size=$(wc -c < "$RESULT_DIR/${api_name}_response.json.gz")

    # 計算壓縮率
    compression_ratio=$(awk "BEGIN {printf \"%.1f\", (1 - $compressed_size / $raw_size) * 100}")

    echo "原始大小: $raw_size bytes"
    echo "壓縮大小: $compressed_size bytes (gzip)"
    echo "壓縮率: $compression_ratio%"

    echo ""
    echo "緩存價值估算："
    echo "假設每秒 10 個請求，TTL = 5 分鐘 (300 秒)："

    total_requests=$((10 * 300))
    cache_hits=$((total_requests - 1))

    no_cache_bandwidth=$((raw_size * total_requests))
    with_cache_bandwidth=$((raw_size + compressed_size * cache_hits))
    bandwidth_saving=$(awk "BEGIN {printf \"%.1f\", (1 - $with_cache_bandwidth / $no_cache_bandwidth) * 100}")

    echo "  - 總請求數: $total_requests"
    echo "  - 緩存命中: $cache_hits 次 (99.97%)"
    echo "  - 無緩存帶寬: $(numfmt --to=iec-i --suffix=B $no_cache_bandwidth)"
    echo "  - 有緩存帶寬: $(numfmt --to=iec-i --suffix=B $with_cache_bandwidth)"
    echo "  - 節省帶寬: $bandwidth_saving%"

    echo ""
    echo "=========================================="
    echo ""
}

#######################################################
# 測試 3: 性能測試
#######################################################
test_performance() {
    local api_url=$1
    local api_name=$2

    echo "=========================================="
    echo "測試 3: $api_name - 性能測試"
    echo "=========================================="

    echo "執行 10 次請求，測試延遲..."

    total_time=0
    min_time=999999
    max_time=0

    for i in {1..10}; do
        time_taken=$(curl -w "%{time_total}" -o /dev/null -s "$api_url")
        echo "  第 $i 次: ${time_taken}s"

        # 計算統計
        total_time=$(awk "BEGIN {print $total_time + $time_taken}")

        # 更新最小值
        is_min=$(awk "BEGIN {print ($time_taken < $min_time) ? 1 : 0}")
        if [ "$is_min" -eq 1 ]; then
            min_time=$time_taken
        fi

        # 更新最大值
        is_max=$(awk "BEGIN {print ($time_taken > $max_time) ? 1 : 0}")
        if [ "$is_max" -eq 1 ]; then
            max_time=$time_taken
        fi

        sleep 1
    done

    avg_time=$(awk "BEGIN {printf \"%.3f\", $total_time / 10}")

    echo ""
    echo "統計結果："
    echo "  - 平均延遲: ${avg_time}s"
    echo "  - 最小延遲: ${min_time}s"
    echo "  - 最大延遲: ${max_time}s"

    echo ""
    echo "緩存後預期改善："
    echo "  - CDN 緩存命中延遲: ~0.001s (假設本地 CDN 節點)"
    echo "  - 改善幅度: $(awk "BEGIN {printf \"%.1f\", (1 - 0.001 / $avg_time) * 100}")%"

    echo ""
    echo "=========================================="
    echo ""
}

#######################################################
# 測試 4: 檢查響應頭
#######################################################
test_response_headers() {
    local api_url=$1
    local api_name=$2

    echo "=========================================="
    echo "測試 4: $api_name - 響應頭分析"
    echo "=========================================="

    headers_file="$RESULT_DIR/${api_name}_headers.txt"
    curl -I -s "$api_url" > "$headers_file"

    echo "當前響應頭："
    cat "$headers_file"

    echo ""
    echo "關鍵頭檢查："

    # Cache-Control
    cache_control=$(grep -i "cache-control:" "$headers_file" || echo "未設置")
    echo "  Cache-Control: $cache_control"

    if echo "$cache_control" | grep -qi "no-cache\|no-store"; then
        echo "    ⚠️  當前禁止緩存"
    elif echo "$cache_control" | grep -qi "max-age"; then
        echo "    ✅ 已啟用緩存"
    else
        echo "    ⚠️  未明確設置緩存策略"
    fi

    # ETag
    etag=$(grep -i "etag:" "$headers_file" || echo "未設置")
    echo "  ETag: $etag"

    if [ "$etag" != "未設置" ]; then
        echo "    ✅ 支持條件請求（可使用 304 Not Modified）"
    else
        echo "    ⚠️  不支持條件請求"
    fi

    # Vary
    vary=$(grep -i "vary:" "$headers_file" || echo "未設置")
    echo "  Vary: $vary"

    if echo "$vary" | grep -qi "authorization\|cookie"; then
        echo "    ⚠️  響應可能依賴用戶認證"
    fi

    echo ""
    echo "=========================================="
    echo ""
}

#######################################################
# 測試 5: 檢查是否包含用戶特定數據
#######################################################
test_user_specific_data() {
    local api_name=$1

    echo "=========================================="
    echo "測試 5: $api_name - 用戶特定數據檢查"
    echo "=========================================="

    response_file="$RESULT_DIR/${api_name}_response_1.json"

    # 檢查常見的用戶特定字段
    user_fields=(
        "userId"
        "user_id"
        "username"
        "balance"
        "credit"
        "point"
        "token"
        "session"
        "authorization"
        "email"
        "phone"
    )

    echo "檢查常見用戶特定字段..."
    found_user_data=false

    for field in "${user_fields[@]}"; do
        if grep -qi "\"$field\"" "$response_file"; then
            echo "  ⚠️  發現字段: $field"
            found_user_data=true
        fi
    done

    echo ""
    if [ "$found_user_data" = true ]; then
        echo "🔴 警告: 響應可能包含用戶特定數據"
        echo "   建議:"
        echo "   1. 如果這些字段對所有用戶相同 → 可以公共緩存"
        echo "   2. 如果這些字段因用戶而異 → 必須使用私有緩存或不緩存"
        echo "   3. 最佳方案: 拆分 API（配置 vs 用戶數據）"
    else
        echo "✅ 未發現明顯的用戶特定字段"
        echo "   響應可能是純配置數據，適合公共緩存"
    fi

    echo ""
    echo "完整響應內容（前 50 行）："
    head -50 "$response_file"

    echo ""
    echo "=========================================="
    echo ""
}

#######################################################
# 生成最終報告
#######################################################
generate_final_report() {
    report_file="$RESULT_DIR/CACHE_FEASIBILITY_REPORT.md"

    echo "生成最終報告..."

    cat > "$report_file" << 'EOF'
# API 緩存可行性測試報告

## 測試執行信息

- **測試時間**: $(date)
- **測試位置**: $(hostname) ($(curl -s ifconfig.me))
- **結果目錄**: $(basename "$RESULT_DIR")

---

## 測試 API

1. **域名配置 API**: `https://ds-r.geminiservice.cc/domains?type=Hash`
2. **遊戲信息 API**: `https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko`

---

## 測試結果摘要

### API 1: 域名配置 API

查看詳細結果文件：
- 響應一致性: `domains_response_*.json`
- 差異分析: `domains_diff_*.txt`
- 響應頭: `domains_headers.txt`

### API 2: 遊戲信息 API

查看詳細結果文件：
- 響應一致性: `gameInfo_response_*.json`
- 差異分析: `gameInfo_diff_*.txt`
- 響應頭: `gameInfo_headers.txt`

---

## 決策建議

根據測試結果，請按以下流程決策：

### 判斷流程

1. **響應一致性測試（測試 1）**
   - ✅ 5 次響應完全相同 → 進入步驟 2
   - ⚠️ 只有時間戳不同 → 建議源服務器移除時間戳 → 進入步驟 2
   - ⚠️ 包含動態 Token → 考慮拆分 API → 進入步驟 2
   - ❌ 內容頻繁變化 → 不適合緩存或使用極短 TTL

2. **用戶特定數據檢查（測試 5）**
   - ✅ 不包含用戶數據 → 進入步驟 3
   - ⚠️ 包含 Token（但配置相同）→ 拆分 API → 進入步驟 3
   - ❌ 包含用戶餘額/ID → 必須使用私有緩存或不緩存

3. **性能測試（測試 3）**
   - ✅ 平均延遲 > 100ms → 緩存價值高
   - ⚠️ 平均延遲 10-100ms → 緩存價值中等
   - ❌ 平均延遲 < 10ms → 緩存價值低（已經很快）

### 推薦配置

#### 場景 A: 適合公共緩存（最理想）

**條件**:
- 響應一致
- 不包含用戶數據
- 平均延遲 > 100ms

**推薦配置**:
```http
Cache-Control: public, max-age=300, stale-while-revalidate=60
Vary: Accept-Encoding
```

**預期改善**:
- API 延遲: 99%+ 改善（350ms → 1ms）
- 服務器負載: 97%+ 減少
- 帶寬成本: 97%+ 節省

---

#### 場景 B: 需要拆分 API

**條件**:
- 響應包含動態 Token 或用戶數據

**推薦方案**:
1. 拆分為配置 API（可緩存）+ 用戶 API（不緩存）
2. 客戶端並行請求

**配置 API**:
```http
Cache-Control: public, max-age=600
```

**用戶 API**:
```http
Cache-Control: private, max-age=60
```

---

#### 場景 C: 不適合緩存

**條件**:
- 包含用戶特定數據且無法拆分
- 內容頻繁變化（秒級）

**推薦配置**:
```http
Cache-Control: no-cache, no-store
# 或
Cache-Control: private, max-age=30
```

---

## 下一步行動

1. **查看詳細測試結果**: 檢查 `$(basename "$RESULT_DIR")` 目錄下的所有文件
2. **根據結果決策**: 使用上述判斷流程
3. **實施 A/B 測試**: 如果決定啟用緩存，建議先進行小規模測試
4. **配置 Akamai**: 根據推薦配置修改 CDN 設置

---

**報告生成時間**: $(date)
EOF

    echo "✅ 報告已生成: $report_file"
}

#######################################################
# 主程序
#######################################################
main() {
    # API 1: 域名配置 API
    test_response_consistency "$API1" "domains"
    test_response_size "$API1" "domains"
    test_performance "$API1" "domains"
    test_response_headers "$API1" "domains"
    test_user_specific_data "domains"

    echo ""
    echo "======================================"
    echo ""

    # API 2: 遊戲信息 API
    test_response_consistency "$API2" "gameInfo"
    test_response_size "$API2" "gameInfo"
    test_performance "$API2" "gameInfo"
    test_response_headers "$API2" "gameInfo"
    test_user_specific_data "gameInfo"

    # 生成報告
    generate_final_report

    echo ""
    echo "======================================"
    echo "測試完成！"
    echo "======================================"
    echo ""
    echo "結果目錄: $RESULT_DIR"
    echo ""
    echo "關鍵文件:"
    echo "  - 測試報告: $RESULT_DIR/CACHE_FEASIBILITY_REPORT.md"
    echo "  - API 響應: $RESULT_DIR/*_response_*.json"
    echo "  - 差異分析: $RESULT_DIR/*_diff_*.txt"
    echo ""
    echo "建議: 查看報告並根據決策流程確定是否啟用緩存"
}

# 執行主程序
main

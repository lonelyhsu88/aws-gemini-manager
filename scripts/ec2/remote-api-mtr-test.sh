#!/bin/bash

################################################################################
# 遠端 API 延遲和 MTR 網路測試腳本 (EC2 上執行)
################################################################################

set -e

echo "=============================================="
echo "API 延遲 + MTR 網路路徑測試"
echo "=============================================="
echo "測試時間: $(date)"
echo "主機名: $(hostname)"
echo "本機 IP: $(curl -s https://api.ipify.org || echo 'N/A')"
echo ""

# 創建結果目錄
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="api-mtr-test-${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

################################################################################
# 測試 1: API 延遲測試
################################################################################

echo "======================================"
echo "測試 1: API 延遲測試"
echo "======================================"

API_RESULT_FILE="$RESULTS_DIR/api-latency.txt"

{
    echo "=== API 延遲測試結果 ==="
    echo "測試時間: $(date)"
    echo ""

    # API 1: 域名服務
    API1="https://ds-r.geminiservice.cc/domains?type=Hash"
    echo "測試 API 1: $API1"
    echo "----------------------------------------"

    total=0
    for i in {1..5}; do
        time=$(curl -w "%{time_total}" -o /dev/null -s "$API1" 2>/dev/null || echo "0")
        echo "  請求 $i: ${time}s"
        total=$(awk "BEGIN {print $total + $time}")
    done
    avg=$(awk "BEGIN {print $total / 5}")
    echo "  平均延遲: ${avg}s"
    echo ""

    # API 2: 遊戲信息服務
    API2="https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko"
    echo "測試 API 2: $API2"
    echo "----------------------------------------"

    total=0
    for i in {1..5}; do
        time=$(curl -w "%{time_total}" -o /dev/null -s "$API2" 2>/dev/null || echo "0")
        echo "  請求 $i: ${time}s"
        total=$(awk "BEGIN {print $total + $time}")
    done
    avg=$(awk "BEGIN {print $total / 5}")
    echo "  平均延遲: ${avg}s"
    echo ""

    # API 3: 錢包 API
    API3="https://wallet-api.geminiservice.cc/api/v1/operator/game/launch"
    echo "測試 API 3: $API3 (POST)"
    echo "----------------------------------------"

    total=0
    for i in {1..5}; do
        time=$(curl -w "%{time_total}" -o /dev/null -s -X POST "$API3" \
            -H "Content-Type: application/json" \
            -d '{"test":"latency"}' 2>/dev/null || echo "0")
        echo "  請求 $i: ${time}s"
        total=$(awk "BEGIN {print $total + $time}")
    done
    avg=$(awk "BEGIN {print $total / 5}")
    echo "  平均延遲: ${avg}s"
    echo ""

} | tee "$API_RESULT_FILE"

echo "✓ API 延遲測試完成"
echo ""

################################################################################
# 測試 2: MTR 網路路徑追蹤
################################################################################

echo "======================================"
echo "測試 2: MTR 網路路徑追蹤"
echo "======================================"

MTR_RESULT_FILE="$RESULTS_DIR/mtr-traceroute.txt"

{
    echo "=== MTR 網路路徑追蹤結果 ==="
    echo "測試時間: $(date)"
    echo ""

    # 檢查是否有 sudo 權限
    if ! sudo -n true 2>/dev/null; then
        echo "警告: 沒有 sudo 權限，MTR 結果可能不完整"
        echo ""
    fi

    # 目標主機列表
    TARGETS=(
        "a23-55-244-43.deploy.static.akamaitechnologies.com"
        "ds-r.geminiservice.cc.edgesuite.net"
        "gameinfo-api.geminiservice.cc.edgesuite.net"
        "wallet-api.geminiservice.cc"
    )

    for target in "${TARGETS[@]}"; do
        echo "======================================"
        echo "目標: $target"
        echo "======================================"

        # 先解析 DNS
        echo "DNS 解析:"
        nslookup "$target" 2>/dev/null | grep -A 2 "Name:" || echo "  解析失敗"
        echo ""

        # 執行 MTR
        echo "MTR 追蹤 (30 次循環):"
        if command -v mtr &> /dev/null; then
            sudo mtr --report --report-cycles 30 --no-dns "$target" 2>/dev/null || \
            mtr --report --report-cycles 30 --no-dns "$target" 2>/dev/null || \
            echo "  MTR 執行失敗"
        else
            echo "  MTR 未安裝，使用 traceroute 替代"
            traceroute -m 20 "$target" 2>/dev/null || echo "  traceroute 執行失敗"
        fi

        echo ""
        echo ""
    done

} | tee "$MTR_RESULT_FILE"

echo "✓ MTR 測試完成"
echo ""

################################################################################
# 測試 3: 簡單的網路診斷
################################################################################

echo "======================================"
echo "測試 3: 網路診斷"
echo "======================================"

DIAG_RESULT_FILE="$RESULTS_DIR/network-diagnostics.txt"

{
    echo "=== 網路診斷結果 ==="
    echo "測試時間: $(date)"
    echo ""

    # 測試 DNS 解析速度
    echo "DNS 解析速度測試:"
    echo "----------------------------------------"

    DOMAINS=(
        "ds-r.geminiservice.cc"
        "gameinfo-api.geminiservice.cc"
        "wallet-api.geminiservice.cc"
        "www.shuangzi6688.com"
    )

    for domain in "${DOMAINS[@]}"; do
        start=$(date +%s%N)
        nslookup "$domain" > /dev/null 2>&1
        end=$(date +%s%N)
        duration=$(( (end - start) / 1000000 ))
        echo "  $domain: ${duration}ms"
    done

    echo ""

    # 測試連接性
    echo "連接性測試 (HTTPS):"
    echo "----------------------------------------"

    HTTPS_TARGETS=(
        "https://ds-r.geminiservice.cc"
        "https://gameinfo-api.geminiservice.cc"
        "https://wallet-api.geminiservice.cc"
    )

    for target in "${HTTPS_TARGETS[@]}"; do
        if curl -s --connect-timeout 5 --max-time 10 -I "$target" > /dev/null 2>&1; then
            echo "  $target: ✓ 可連接"
        else
            echo "  $target: ✗ 連接失敗"
        fi
    done

    echo ""

    # 地理位置信息
    echo "地理位置信息:"
    echo "----------------------------------------"
    MY_IP=$(curl -s https://api.ipify.org)
    curl -s "http://ip-api.com/json/${MY_IP}" | \
        grep -E '"(country|regionName|city|isp|lat|lon)"' | \
        sed 's/[",]//g' || echo "  獲取失敗"

    echo ""

} | tee "$DIAG_RESULT_FILE"

echo "✓ 網路診斷完成"
echo ""

################################################################################
# 生成摘要
################################################################################

echo "======================================"
echo "測試摘要"
echo "======================================"

SUMMARY_FILE="$RESULTS_DIR/SUMMARY.txt"

{
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║         API 延遲 + MTR 測試結果摘要                     ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "測試時間: $(date)"
    echo "測試位置: $(curl -s http://ip-api.com/json/ | grep -o '"city":"[^"]*"' | cut -d'"' -f4 || echo 'Unknown')"
    echo ""

    echo "1. API 延遲測試結果:"
    echo "   ├─ ds-r.geminiservice.cc"
    grep -A 1 "測試 API 1" "$API_RESULT_FILE" | grep "平均延遲" | sed 's/^/   │  /'
    echo "   ├─ gameinfo-api.geminiservice.cc"
    grep -A 1 "測試 API 2" "$API_RESULT_FILE" | grep "平均延遲" | sed 's/^/   │  /'
    echo "   └─ wallet-api.geminiservice.cc"
    grep -A 1 "測試 API 3" "$API_RESULT_FILE" | grep "平均延遲" | sed 's/^/      /'

    echo ""
    echo "2. MTR 測試結果: 詳見 $MTR_RESULT_FILE"
    echo "3. 網路診斷結果: 詳見 $DIAG_RESULT_FILE"
    echo ""

    echo "完整結果目錄: $RESULTS_DIR"
    echo ""

} | tee "$SUMMARY_FILE"

echo ""
echo "=============================================="
echo "所有測試完成！"
echo "=============================================="
echo ""
echo "結果文件:"
echo "  • 摘要: $SUMMARY_FILE"
echo "  • API 延遲: $API_RESULT_FILE"
echo "  • MTR 路徑: $MTR_RESULT_FILE"
echo "  • 網路診斷: $DIAG_RESULT_FILE"
echo ""
echo "結果目錄: $RESULTS_DIR"
ls -lh "$RESULTS_DIR"
echo ""

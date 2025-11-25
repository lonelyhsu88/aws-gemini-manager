#!/bin/bash
# Zabbix Server Docker 容器日誌清理腳本
# 自動找到正確的容器並清理日誌

set -e

echo "======================================"
echo "🔍 Docker 容器日誌診斷與清理"
echo "======================================"
echo ""

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. 檢查 Docker 運行狀態
echo "📊 檢查 Docker 容器狀態..."
echo "--------------------------------------"
docker ps --format "table {{.Names}}\t{{.ID}}\t{{.Status}}\t{{.Size}}"
echo ""

# 2. 找出所有容器的日誌大小
echo "📂 檢查容器日誌大小..."
echo "--------------------------------------"

DOCKER_ROOT=$(docker info -f '{{.DockerRootDir}}')
CONTAINERS_DIR="${DOCKER_ROOT}/containers"

echo "Docker Root: ${DOCKER_ROOT}"
echo ""

# 找出大於 100MB 的日誌文件
echo "🔍 尋找大於 100MB 的日誌文件..."
echo ""

LARGE_LOGS=$(find ${CONTAINERS_DIR} -name "*-json.log" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -hr)

if [ -z "$LARGE_LOGS" ]; then
    echo -e "${GREEN}✅ 沒有發現大於 100MB 的容器日誌${NC}"
    exit 0
fi

echo "$LARGE_LOGS"
echo ""

# 3. 顯示哪些容器佔用空間
echo "📊 容器日誌詳細分析..."
echo "--------------------------------------"

declare -A container_logs

while IFS= read -r line; do
    LOG_FILE=$(echo "$line" | awk '{print $9}')
    LOG_SIZE=$(echo "$line" | awk '{print $5}')
    CONTAINER_ID=$(basename $(dirname "$LOG_FILE"))

    # 獲取容器名稱
    CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER_ID" 2>/dev/null | sed 's/^\/*//' || echo "unknown")

    printf "%-30s %-15s %-15s\n" "$CONTAINER_NAME" "$CONTAINER_ID" "$LOG_SIZE"

    container_logs["$LOG_FILE"]="$CONTAINER_NAME ($LOG_SIZE)"
done <<< "$LARGE_LOGS"

echo ""

# 4. 詢問是否清理
read -p "❓ 是否清理這些日誌？ (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 取消清理"
    exit 0
fi

# 5. 執行清理
echo ""
echo "🧹 開始清理日誌..."
echo "--------------------------------------"

TOTAL_FREED=0

while IFS= read -r line; do
    LOG_FILE=$(echo "$line" | awk '{print $9}')
    LOG_SIZE_STR=$(echo "$line" | awk '{print $5}')
    CONTAINER_ID=$(basename $(dirname "$LOG_FILE"))
    CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER_ID" 2>/dev/null | sed 's/^\/*//' || echo "unknown")

    # 獲取清理前大小（bytes）
    SIZE_BEFORE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)

    echo -n "  清理 ${CONTAINER_NAME} (${LOG_SIZE_STR})... "

    # 清理日誌
    if truncate -s 0 "$LOG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✅ 完成${NC}"
        TOTAL_FREED=$((TOTAL_FREED + SIZE_BEFORE))
    else
        echo -e "${RED}❌ 失敗${NC}"
    fi
done <<< "$LARGE_LOGS"

echo ""
echo "======================================"
echo -e "${GREEN}✅ 清理完成！${NC}"
echo "======================================"

# 轉換為人類可讀格式
FREED_GB=$(echo "scale=2; $TOTAL_FREED / 1024 / 1024 / 1024" | bc)
echo "📊 釋放空間: ${FREED_GB} GB"
echo ""

# 6. 顯示清理後的磁碟使用情況
echo "💾 當前磁碟使用情況:"
echo "--------------------------------------"
df -h / | tail -1
echo ""

# 7. 建議設定日誌輪替
echo "======================================"
echo "💡 建議設定日誌輪替以防止再次發生"
echo "======================================"
echo ""
echo "方式 1: 編輯 /etc/docker/daemon.json"
echo "--------------------------------------"
cat <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
echo ""
echo "然後執行: sudo systemctl restart docker"
echo ""
echo "方式 2: 設定 Cron 定期清理"
echo "--------------------------------------"
echo "0 2 * * 0 find /var/lib/docker/containers -name '*-json.log' -size +1G -exec truncate -s 500M {} \;"
echo ""

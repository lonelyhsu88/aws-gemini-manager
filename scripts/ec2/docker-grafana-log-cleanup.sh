#!/bin/bash
# ========================================
# Docker Grafana 日誌清理腳本
# ========================================
# 清理 Docker 容器日誌並設定日誌輪替
# 適用於: Zabbix Server (gemini-monitor-01)

set -e

echo "========================================"
echo "🐳 Docker Grafana 日誌清理"
echo "========================================"
echo ""

# 檢查是否為 root 或有 sudo 權限
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "❌ 需要 sudo 權限執行此腳本"
    exit 1
fi

# ========================================
# Step 1: 顯示當前狀況
# ========================================
echo "📊 當前磁碟使用情況："
df -h / | grep -v Filesystem
echo ""

echo "📦 Docker 容器狀態："
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}"
echo ""

# ========================================
# Step 2: 檢查容器日誌大小
# ========================================
echo "📋 Docker 容器日誌大小："
echo "----------------------------------------"

GRAFANA_CONTAINER=$(docker ps --filter "name=grafana" --format "{{.ID}}")
ZABBIX_WEB_CONTAINER=$(docker ps --filter "name=zabbix-web" --format "{{.ID}}")
ZABBIX_SERVER_CONTAINER=$(docker ps --filter "name=zabbix-server" --format "{{.ID}}")

if [ -n "$GRAFANA_CONTAINER" ]; then
    GRAFANA_LOG="/var/lib/docker/containers/${GRAFANA_CONTAINER}/${GRAFANA_CONTAINER}-json.log"
    if [ -f "$GRAFANA_LOG" ]; then
        GRAFANA_SIZE=$(du -sh "$GRAFANA_LOG" | awk '{print $1}')
        echo "  Grafana:       $GRAFANA_SIZE"
    fi
fi

if [ -n "$ZABBIX_WEB_CONTAINER" ]; then
    ZABBIX_WEB_LOG="/var/lib/docker/containers/${ZABBIX_WEB_CONTAINER}/${ZABBIX_WEB_CONTAINER}-json.log"
    if [ -f "$ZABBIX_WEB_LOG" ]; then
        ZABBIX_WEB_SIZE=$(du -sh "$ZABBIX_WEB_LOG" | awk '{print $1}')
        echo "  Zabbix Web:    $ZABBIX_WEB_SIZE"
    fi
fi

if [ -n "$ZABBIX_SERVER_CONTAINER" ]; then
    ZABBIX_SERVER_LOG="/var/lib/docker/containers/${ZABBIX_SERVER_CONTAINER}/${ZABBIX_SERVER_CONTAINER}-json.log"
    if [ -f "$ZABBIX_SERVER_LOG" ]; then
        ZABBIX_SERVER_SIZE=$(du -sh "$ZABBIX_SERVER_LOG" | awk '{print $1}')
        echo "  Zabbix Server: $ZABBIX_SERVER_SIZE"
    fi
fi

echo ""

# ========================================
# Step 3: 詢問清理方式
# ========================================
echo "========================================"
echo "清理方式選擇："
echo "========================================"
echo ""
echo "方式 1: 清空日誌（推薦 - 服務不中斷）"
echo "  - 使用 truncate 清空日誌檔案"
echo "  - Grafana 和其他服務繼續運行"
echo "  - 立即釋放空間"
echo ""
echo "方式 2: 重啟容器（會短暫中斷服務）"
echo "  - 重啟 Docker 容器"
echo "  - 日誌檔案會自動輪替"
echo "  - 中斷時間: 5-10 秒"
echo ""
read -p "請選擇 (1/2): " -n 1 -r CHOICE
echo ""
echo ""

if [ "$CHOICE" = "1" ]; then
    # ========================================
    # 方式 1: Truncate 日誌
    # ========================================
    echo "🧹 執行方式 1: 清空日誌檔案..."
    echo ""

    if [ -f "$GRAFANA_LOG" ]; then
        echo "清理 Grafana 日誌..."
        BEFORE=$(du -sh "$GRAFANA_LOG" | awk '{print $1}')
        sudo truncate -s 0 "$GRAFANA_LOG"
        echo "  ✅ Grafana 日誌已清空（原大小: $BEFORE）"
    fi

    if [ -f "$ZABBIX_WEB_LOG" ]; then
        echo "清理 Zabbix Web 日誌..."
        BEFORE=$(du -sh "$ZABBIX_WEB_LOG" | awk '{print $1}')
        sudo truncate -s 0 "$ZABBIX_WEB_LOG"
        echo "  ✅ Zabbix Web 日誌已清空（原大小: $BEFORE）"
    fi

    if [ -f "$ZABBIX_SERVER_LOG" ]; then
        echo "清理 Zabbix Server 日誌..."
        BEFORE=$(du -sh "$ZABBIX_SERVER_LOG" | awk '{print $1}')
        sudo truncate -s 0 "$ZABBIX_SERVER_LOG"
        echo "  ✅ Zabbix Server 日誌已清空（原大小: $BEFORE）"
    fi

elif [ "$CHOICE" = "2" ]; then
    # ========================================
    # 方式 2: 重啟容器
    # ========================================
    echo "🔄 執行方式 2: 重啟容器..."
    echo ""

    read -p "⚠️  這會短暫中斷 Grafana 和 Zabbix 服務，確定要繼續嗎？ (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -n "$GRAFANA_CONTAINER" ]; then
            echo "重啟 Grafana..."
            docker restart grafana
            echo "  ✅ Grafana 已重啟"
        fi

        if [ -n "$ZABBIX_WEB_CONTAINER" ]; then
            echo "重啟 Zabbix Web..."
            docker restart zabbix-web-apache-mysql
            echo "  ✅ Zabbix Web 已重啟"
        fi

        # 等待容器啟動
        sleep 5

        echo ""
        echo "📦 容器狀態："
        docker ps --format "table {{.Names}}\t{{.Status}}"
    else
        echo "❌ 取消重啟"
        exit 0
    fi
else
    echo "❌ 無效的選擇"
    exit 1
fi

# ========================================
# Step 4: 顯示清理後狀態
# ========================================
echo ""
echo "========================================"
echo "✅ 清理完成！"
echo "========================================"
echo ""

echo "📊 清理後磁碟使用情況："
df -h / | grep -v Filesystem
echo ""

echo "📋 清理後容器日誌大小："
if [ -f "$GRAFANA_LOG" ]; then
    echo "  Grafana:       $(du -sh "$GRAFANA_LOG" | awk '{print $1}')"
fi
if [ -f "$ZABBIX_WEB_LOG" ]; then
    echo "  Zabbix Web:    $(du -sh "$ZABBIX_WEB_LOG" | awk '{print $1}')"
fi
if [ -f "$ZABBIX_SERVER_LOG" ]; then
    echo "  Zabbix Server: $(du -sh "$ZABBIX_SERVER_LOG" | awk '{print $1}')"
fi

echo ""
echo "========================================"
echo "⚠️  重要：設定日誌輪替防止再次發生"
echo "========================================"
echo ""
echo "請執行以下命令設定 Docker 日誌輪替："
echo ""
echo "  sudo bash -c 'cat > /etc/docker/daemon.json <<EOF"
echo '  {'
echo '    "log-driver": "json-file",'
echo '    "log-opts": {'
echo '      "max-size": "10m",'
echo '      "max-file": "3"'
echo '    }'
echo '  }'
echo "  EOF'"
echo ""
echo "  sudo systemctl restart docker"
echo ""
echo "或執行自動化腳本："
echo "  sudo ./docker-log-rotation-setup.sh"
echo ""

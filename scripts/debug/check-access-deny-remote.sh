#!/usr/bin/env bash
#############################################
# 遠端查詢 hash nginx 日誌 - 商戶訪問被拒絕問題
# 自動 SSH 連接並查詢日誌
#############################################

set -euo pipefail

# SSH 連接配置
_USER=ec2-user
_SRV=16.163.175.42
# _SRV=172.31.20.213  # 私有 IP (需要 VPN)
_KEY=~/.ssh/hash-prd.pem

# 問題資訊
PID="GMM3823"
CLIENT_IP="35.201.199.6"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${CYAN}=====================================${NC}"
echo -e "${BOLD}${CYAN}商戶遊戲訪問問題 - 遠端日誌查詢${NC}"
echo -e "${BOLD}${CYAN}=====================================${NC}"
echo ""
echo -e "${YELLOW}目標伺服器：${NC}$_SRV"
echo -e "${YELLOW}SSH 用戶：${NC}$_USER"
echo -e "${YELLOW}SSH 金鑰：${NC}$_KEY"
echo -e "${YELLOW}查詢 IP：${NC}$CLIENT_IP (Google Cloud Platform 台灣)"
echo -e "${YELLOW}查詢 PID：${NC}$PID"
echo ""

# 檢查 SSH 金鑰是否存在
if [ ! -f "$_KEY" ]; then
    echo -e "${RED}錯誤：SSH 金鑰不存在: $_KEY${NC}"
    exit 1
fi

echo -e "${BOLD}${BLUE}步驟 1: 測試 SSH 連接${NC}"
if ssh -i $_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=no $_USER@$_SRV "echo 'SSH 連接成功'" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH 連接正常${NC}"
    echo ""
else
    echo -e "${RED}✗ SSH 連接失敗${NC}"
    echo -e "${YELLOW}提示：請確認${NC}"
    echo -e "  1. VPN 連接是否正常"
    echo -e "  2. SSH 金鑰權限正確: chmod 400 $_KEY"
    echo -e "  3. 伺服器 IP 是否正確"
    exit 1
fi

# 創建遠端查詢腳本
REMOTE_SCRIPT=$(cat <<'EOF'
#!/bin/bash

PID="$1"
CLIENT_IP="$2"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 1: 此 IP 的所有訪問記錄（最近 50 條）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep "$CLIENT_IP" /var/log/nginx/access.log 2>/dev/null | tail -50 || echo "無記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 2: 此 PID 的所有訪問記錄（最近 50 條）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep "$PID" /var/log/nginx/access.log 2>/dev/null | tail -50 || echo "無記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 3: 同時包含 IP 和 PID 的記錄${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep "$CLIENT_IP" /var/log/nginx/access.log 2>/dev/null | grep "$PID" || echo "無匹配記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 4: HTTP 狀態碼統計（此 IP）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${CYAN}狀態碼分佈：${NC}"
grep "$CLIENT_IP" /var/log/nginx/access.log 2>/dev/null | awk '{print $9}' | sort | uniq -c | sort -rn || echo "無記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 5: 403 Forbidden 錯誤（此 IP）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep "$CLIENT_IP" /var/log/nginx/access.log 2>/dev/null | grep " 403 " | tail -20 || echo "無 403 錯誤記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 6: 請求路徑統計（此 IP）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${CYAN}訪問的 URL 路徑：${NC}"
grep "$CLIENT_IP" /var/log/nginx/access.log 2>/dev/null | awk '{print $7}' | sort | uniq -c | sort -rn | head -10 || echo "無記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 7: nginx error log（此 IP 相關）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep "$CLIENT_IP" /var/log/nginx/error.log 2>/dev/null | tail -20 || echo "無錯誤記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 8: nginx error log（denied 關鍵字）${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep -i "denied" /var/log/nginx/error.log 2>/dev/null | tail -20 || echo "無 denied 記錄"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 9: nginx 配置 - IP 白名單規則${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${CYAN}主配置文件中的 allow/deny 規則：${NC}"
grep -n "allow\|deny" /etc/nginx/nginx.conf 2>/dev/null | grep -v "^#" | head -20 || echo "無規則"
echo ""
echo -e "${CYAN}conf.d 目錄中的 allow/deny 規則：${NC}"
grep -rn "allow\|deny" /etc/nginx/conf.d/ 2>/dev/null | grep -v "^#" | head -20 || echo "無規則"
echo ""

echo -e "${BOLD}${BLUE}=====================================${NC}"
echo -e "${BOLD}${BLUE}查詢 10: nginx 配置 - GeoIP 限制${NC}"
echo -e "${BOLD}${BLUE}=====================================${NC}"
grep -rn "geoip\|geo" /etc/nginx/ 2>/dev/null | grep -v "^#" | head -20 || echo "無 GeoIP 配置"
echo ""

echo -e "${BOLD}${GREEN}=====================================${NC}"
echo -e "${BOLD}${GREEN}日誌查詢完成${NC}"
echo -e "${BOLD}${GREEN}=====================================${NC}"
EOF
)

echo -e "${BOLD}${BLUE}步驟 2: 執行遠端日誌查詢${NC}"
echo ""

# 執行遠端腳本
ssh -i $_KEY -o StrictHostKeyChecking=no $_USER@$_SRV "bash -s $PID $CLIENT_IP" <<< "$REMOTE_SCRIPT"

SSH_EXIT_CODE=$?

echo ""
echo -e "${BOLD}${CYAN}=====================================${NC}"
echo -e "${BOLD}${CYAN}查詢結果分析建議${NC}"
echo -e "${BOLD}${CYAN}=====================================${NC}"
echo ""

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ 日誌查詢成功完成${NC}"
    echo ""
    echo -e "${YELLOW}請根據以上查詢結果判斷問題原因：${NC}"
    echo ""
    echo -e "${BOLD}1. 如果看到 403 狀態碼：${NC}"
    echo -e "   → 可能原因：IP 白名單限制"
    echo -e "   → 解決方案：新增 IP 到白名單 (allow $CLIENT_IP;)"
    echo ""
    echo -e "${BOLD}2. 如果看到 'access forbidden by rule'：${NC}"
    echo -e "   → 確定原因：IP 被 deny 規則阻擋"
    echo -e "   → 解決方案：移除 deny 規則或新增 allow 規則"
    echo ""
    echo -e "${BOLD}3. 如果沒有任何記錄：${NC}"
    echo -e "   → 可能原因：請求未到達 nginx"
    echo -e "   → 檢查項目：防火牆、安全組、負載均衡器"
    echo ""
    echo -e "${BOLD}4. 如果看到其他錯誤：${NC}"
    echo -e "   → 502/503: 後端服務異常"
    echo -e "   → 499: 客戶端超時"
    echo -e "   → 404: 路徑錯誤"
    echo ""
    echo -e "${CYAN}如需修改 nginx 配置，請執行：${NC}"
    echo -e "  ssh -i $_KEY $_USER@$_SRV"
    echo -e "  sudo vim /etc/nginx/conf.d/whitelist.conf"
    echo -e "  # 新增: allow $CLIENT_IP;"
    echo -e "  sudo nginx -t"
    echo -e "  sudo systemctl reload nginx"
    echo ""
else
    echo -e "${RED}✗ 日誌查詢失敗 (退出碼: $SSH_EXIT_CODE)${NC}"
    exit 1
fi

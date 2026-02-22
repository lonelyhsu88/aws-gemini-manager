#!/usr/bin/env bash
#############################################
# 調查商戶遊戲訪問被拒絕問題
# 問題：葛格商戶無法進入遊戲【馬到成功】
# 錯誤：Access Deny
#############################################

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# 問題資訊
MERCHANT="葛格"
GAME="馬到成功"
PID="GMM3823"
CLIENT_IP="35.201.199.6"
BRAND="Gemini"
ENV="正式環境"

echo -e "${BOLD}${CYAN}=====================================${NC}"
echo -e "${BOLD}${CYAN}商戶遊戲訪問問題調查${NC}"
echo -e "${BOLD}${CYAN}=====================================${NC}"
echo ""
echo -e "${YELLOW}商戶：${NC}${MERCHANT}"
echo -e "${YELLOW}遊戲：${NC}${GAME}"
echo -e "${YELLOW}PID：${NC}${PID}"
echo -e "${YELLOW}來源 IP：${NC}${CLIENT_IP}"
echo -e "${YELLOW}IP 來源：${NC}Google Cloud Platform (台灣台北)"
echo -e "${YELLOW}錯誤訊息：${NC}${RED}Access Deny${NC}"
echo ""

echo -e "${BOLD}${BLUE}步驟 1: SSH 連接到 hash nginx 伺服器${NC}"
echo ""
echo -e "${CYAN}請執行以下命令之一：${NC}"
echo ""
echo -e "${GREEN}# 方法 1: 使用 SSH 配置檔連接${NC}"
echo -e "ssh hash-prd-ngx-01"
echo ""
echo -e "${GREEN}# 方法 2: 使用完整命令${NC}"
echo -e "ssh -i ~/.ssh/hash-prd.pem ec2-user@172.31.29.104"
echo ""
echo -e "${YELLOW}注意：需要透過 VPN 或 bastion 連接私有 IP${NC}"
echo ""

echo -e "${BOLD}${BLUE}步驟 2: 查詢 nginx access log${NC}"
echo ""
echo -e "${CYAN}登入後執行以下命令：${NC}"
echo ""

echo -e "${GREEN}# 2.1 根據來源 IP 過濾日誌${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/access.log | tail -20'
echo ""

echo -e "${GREEN}# 2.2 根據 PID 過濾日誌${NC}"
echo -e 'grep "GMM3823" /var/log/nginx/access.log | tail -20'
echo ""

echo -e "${GREEN}# 2.3 同時過濾 IP 和 PID${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/access.log | grep "GMM3823"'
echo ""

echo -e "${GREEN}# 2.4 查看狀態碼分佈${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/access.log | awk '\''{print $9}'\'' | sort | uniq -c'
echo ""

echo -e "${GREEN}# 2.5 查看完整請求路徑${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/access.log | awk '\''{print $7}'\'' | sort | uniq'
echo ""

echo -e "${GREEN}# 2.6 查看最近的 403 錯誤${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/access.log | grep " 403 "'
echo ""

echo -e "${BOLD}${BLUE}步驟 3: 查詢 nginx error log${NC}"
echo ""
echo -e "${GREEN}# 3.1 查看與此 IP 相關的錯誤${NC}"
echo -e 'grep "35.201.199.6" /var/log/nginx/error.log | tail -20'
echo ""

echo -e "${GREEN}# 3.2 查看最近的 access denied 錯誤${NC}"
echo -e 'grep -i "denied" /var/log/nginx/error.log | tail -20'
echo ""

echo -e "${GREEN}# 3.3 查看最近的所有錯誤${NC}"
echo -e 'tail -50 /var/log/nginx/error.log'
echo ""

echo -e "${BOLD}${BLUE}步驟 4: 檢查 nginx 配置（IP 白名單）${NC}"
echo ""
echo -e "${GREEN}# 4.1 查看 nginx 主配置${NC}"
echo -e 'cat /etc/nginx/nginx.conf | grep -A 10 "allow\|deny"'
echo ""

echo -e "${GREEN}# 4.2 查看遊戲相關的 server 配置${NC}"
echo -e 'find /etc/nginx -name "*.conf" -exec grep -l "hash\|game" {} \;'
echo ""

echo -e "${GREEN}# 4.3 查看特定遊戲配置中的 allow/deny 規則${NC}"
echo -e 'grep -r "allow\|deny" /etc/nginx/conf.d/ /etc/nginx/sites-enabled/'
echo ""

echo -e "${GREEN}# 4.4 檢查是否有 GeoIP 限制${NC}"
echo -e 'grep -r "geoip\|geo" /etc/nginx/'
echo ""

echo -e "${BOLD}${BLUE}步驟 5: 檢查應用層權限配置${NC}"
echo ""
echo -e "${GREEN}# 5.1 查看遊戲服務日誌${NC}"
echo -e 'journalctl -u hash-game -n 50 --no-pager | grep -E "(GMM3823|35.201.199.6|denied)"'
echo ""

echo -e "${GREEN}# 5.2 查看應用程式日誌目錄${NC}"
echo -e 'ls -lh /var/log/apps/ /var/log/game/ /opt/game/logs/ 2>/dev/null'
echo ""

echo -e "${BOLD}${BLUE}步驟 6: 測試連接性${NC}"
echo ""
echo -e "${GREEN}# 6.1 測試從 nginx 連接到遊戲後端${NC}"
echo -e 'curl -v http://localhost:8080/health 2>&1 | grep -E "(200|500|403)"'
echo ""

echo -e "${GREEN}# 6.2 檢查防火牆規則${NC}"
echo -e 'sudo iptables -L -n | grep -E "(35.201.199.6|REJECT|DROP)"'
echo ""

echo -e "${BOLD}${BLUE}步驟 7: 實時監控（如果問題持續發生）${NC}"
echo ""
echo -e "${GREEN}# 7.1 實時監控 access log${NC}"
echo -e 'tail -f /var/log/nginx/access.log | grep --line-buffered "35.201.199.6"'
echo ""

echo -e "${GREEN}# 7.2 實時監控 error log${NC}"
echo -e 'tail -f /var/log/nginx/error.log'
echo ""

echo -e "${BOLD}${CYAN}=====================================${NC}"
echo -e "${BOLD}${CYAN}預期發現的關鍵信息${NC}"
echo -e "${BOLD}${CYAN}=====================================${NC}"
echo ""
echo -e "${YELLOW}1. HTTP 狀態碼：${NC}"
echo -e "   - ${RED}403 Forbidden${NC} → IP 白名單或權限問題"
echo -e "   - ${RED}404 Not Found${NC} → 路徑錯誤或遊戲不存在"
echo -e "   - ${RED}502/503${NC} → 後端服務異常"
echo -e "   - ${RED}499${NC} → 客戶端超時斷開"
echo ""
echo -e "${YELLOW}2. nginx error log 可能的訊息：${NC}"
echo -e "   - ${RED}access forbidden by rule${NC} → IP 被 deny 規則阻擋"
echo -e "   - ${RED}no resolver defined to resolve${NC} → DNS 問題"
echo -e "   - ${RED}upstream timed out${NC} → 後端超時"
echo ""
echo -e "${YELLOW}3. 可能的解決方案：${NC}"
echo -e "   - ${GREEN}新增 IP 到白名單${NC}：allow 35.201.199.6;"
echo -e "   - ${GREEN}檢查商戶權限${NC}：確認 PID GMM3823 有遊戲權限"
echo -e "   - ${GREEN}檢查地區限制${NC}：確認台灣地區可訪問"
echo -e "   - ${GREEN}檢查 GCP IP 範圍${NC}：可能需要允許整個 GCP 台灣區段"
echo ""

echo -e "${BOLD}${GREEN}=====================================${NC}"
echo -e "${BOLD}${GREEN}完成調查後的後續步驟${NC}"
echo -e "${BOLD}${GREEN}=====================================${NC}"
echo ""
echo -e "1. 將日誌查詢結果保存到本地："
echo -e "   ${CYAN}scp hash-prd-ngx-01:/tmp/investigation.log ./${NC}"
echo ""
echo -e "2. 如需要修改 nginx 配置："
echo -e "   ${CYAN}sudo vim /etc/nginx/conf.d/game.conf${NC}"
echo -e "   ${CYAN}sudo nginx -t  # 測試配置${NC}"
echo -e "   ${CYAN}sudo systemctl reload nginx  # 重載配置${NC}"
echo ""
echo -e "3. 如需要新增 IP 白名單："
echo -e "   ${CYAN}echo 'allow 35.201.199.6;' | sudo tee -a /etc/nginx/conf.d/whitelist.conf${NC}"
echo ""

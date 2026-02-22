#!/usr/bin/env bash
# Elastalert2 Management Menu
# Interactive menu for managing Elastalert on pro-elk

set -euo pipefail

USER="ec2-user"
SERVER="18.163.127.177"
KEY="~/.ssh/hk-devops.pem"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to run remote command
run_remote() {
    ssh -i "$KEY" "$USER@$SERVER" "$@"
}

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Elastalert2 Management Menu${NC}"
    echo -e "${BLUE}  Server: gemini-elk-prd (18.163.127.177)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo "1. 📊 查看容器狀態"
    echo "2. 📁 列出所有規則文件"
    echo "3. 📄 查看主配置文件"
    echo "4. 🔍 查看特定規則文件"
    echo "5. 📈 查看 Elasticsearch 索引狀態"
    echo "6. 📝 查看最近 Docker 日誌"
    echo "7. 🔄 重啟 Elastalert 容器"
    echo "8. 📊 規則統計分析"
    echo "9. 🚪 SSH 進入主機"
    echo "0. ❌ 退出"
    echo
    echo -n "請選擇操作 [0-9]: "
}

# 1. Container status
check_container() {
    echo -e "${YELLOW}📊 容器狀態${NC}"
    echo "----------------------------------------"
    run_remote "docker ps --filter name=elastalert --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
    echo
    run_remote "docker stats --no-stream elastalert2"
}

# 2. List rules
list_rules() {
    echo -e "${YELLOW}📁 規則文件列表${NC}"
    echo "----------------------------------------"
    run_remote "cd /opt/elastalert2/rules && ls -lh *.yaml | wc -l | xargs echo '總數:'"
    echo
    echo "規則文件（前50個）:"
    run_remote "ls -1 /opt/elastalert2/rules/ | head -50"
}

# 3. View config
view_config() {
    echo -e "${YELLOW}📄 主配置文件 (elastalert.yaml)${NC}"
    echo "----------------------------------------"
    run_remote "cat /opt/elastalert2/elastalert.yaml"
}

# 4. View specific rule
view_rule() {
    echo -e "${YELLOW}🔍 查看特定規則${NC}"
    echo "----------------------------------------"
    echo -n "請輸入規則文件名（或部分名稱搜索）: "
    read -r rule_name

    if [[ -z "$rule_name" ]]; then
        echo -e "${RED}❌ 未輸入規則名稱${NC}"
        return
    fi

    # Search for matching rules
    matches=$(run_remote "ls -1 /opt/elastalert2/rules/ | grep -i '$rule_name' || true")

    if [[ -z "$matches" ]]; then
        echo -e "${RED}❌ 未找到匹配的規則: $rule_name${NC}"
        return
    fi

    count=$(echo "$matches" | wc -l | tr -d ' ')

    if [[ $count -gt 1 ]]; then
        echo "找到 $count 個匹配的規則:"
        echo "$matches" | nl
        echo
        echo -n "請選擇編號 [1-$count]: "
        read -r selection
        rule_file=$(echo "$matches" | sed -n "${selection}p")
    else
        rule_file="$matches"
    fi

    if [[ -n "$rule_file" ]]; then
        echo
        echo -e "${GREEN}查看規則: $rule_file${NC}"
        echo "----------------------------------------"
        run_remote "cat /opt/elastalert2/rules/$rule_file"
    fi
}

# 5. ES indices
check_indices() {
    echo -e "${YELLOW}📈 Elasticsearch 索引狀態${NC}"
    echo "----------------------------------------"
    run_remote "curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?v&s=index"
}

# 6. Docker logs
view_logs() {
    echo -e "${YELLOW}📝 Docker 日誌${NC}"
    echo "----------------------------------------"
    echo -n "顯示最近幾行？[預設 100]: "
    read -r lines
    lines=${lines:-100}

    run_remote "docker logs --tail $lines elastalert2"

    echo
    echo -e "${BLUE}檢查 429 錯誤:${NC}"
    run_remote "docker logs --tail 1000 elastalert2 2>&1 | grep -c '429' || echo '0'"
}

# 7. Restart container
restart_container() {
    echo -e "${YELLOW}🔄 重啟 Elastalert 容器${NC}"
    echo "----------------------------------------"
    echo -e "${RED}警告: 將重啟 Elastalert2 容器${NC}"
    echo -n "確定要繼續嗎？ [y/N]: "
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "正在重啟..."
        run_remote "cd /opt/elastalert2 && docker-compose restart"
        echo -e "${GREEN}✅ 重啟完成${NC}"
        sleep 2
        check_container
    else
        echo "已取消"
    fi
}

# 8. Rule statistics
rule_stats() {
    echo -e "${YELLOW}📊 規則統計分析${NC}"
    echo "----------------------------------------"

    echo "總規則數量:"
    run_remote "find /opt/elastalert2/rules -name '*.yaml' -type f | wc -l"
    echo

    echo "Realert 間隔分佈:"
    run_remote "grep -h 'minutes:' /opt/elastalert2/rules/*.yaml 2>/dev/null | sed 's/^[[:space:]]*//' | sort | uniq -c | sort -rn | head -10"
    echo

    echo "Alert 類型分佈:"
    run_remote "grep -h 'type:' /opt/elastalert2/rules/*.yaml 2>/dev/null | sed 's/^[[:space:]]*//' | sort | uniq -c | sort -rn"
}

# 9. SSH into server
ssh_into_server() {
    echo -e "${YELLOW}🚪 SSH 進入主機${NC}"
    echo "----------------------------------------"
    echo "正在連接到 $SERVER..."
    ssh -i "$KEY" "$USER@$SERVER"
}

# Main loop
while true; do
    show_menu
    read -r choice

    case $choice in
        1) clear; check_container; echo; read -p "按 Enter 繼續..." ;;
        2) clear; list_rules; echo; read -p "按 Enter 繼續..." ;;
        3) clear; view_config; echo; read -p "按 Enter 繼續..." ;;
        4) clear; view_rule; echo; read -p "按 Enter 繼續..." ;;
        5) clear; check_indices; echo; read -p "按 Enter 繼續..." ;;
        6) clear; view_logs; echo; read -p "按 Enter 繼續..." ;;
        7) clear; restart_container; echo; read -p "按 Enter 繼續..." ;;
        8) clear; rule_stats; echo; read -p "按 Enter 繼續..." ;;
        9) ssh_into_server; ;;
        0) echo -e "${GREEN}再見！${NC}"; exit 0 ;;
        *) echo -e "${RED}無效的選擇，請重試${NC}"; sleep 1 ;;
    esac
done

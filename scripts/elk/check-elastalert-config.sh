#!/usr/bin/env bash
# Check Elastalert2 configuration on pro-elk (gemini-elk-prd)
# Usage: ./check-elastalert-config.sh

set -euo pipefail

USER="ec2-user"
SERVER="18.163.127.177"
KEY="~/.ssh/hk-devops.pem"

echo "========================================"
echo "  Elastalert2 Configuration Check"
echo "  Server: gemini-elk-prd ($SERVER)"
echo "========================================"
echo

# Function to run remote command
run_remote() {
    ssh -i "$KEY" "$USER@$SERVER" "$@"
}

echo "📋 1. 主機信息"
echo "----------------------------------------"
run_remote "hostname && uptime"
echo

echo "🐳 2. Elastalert Docker 容器狀態"
echo "----------------------------------------"
run_remote "docker ps --filter name=elastalert --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'"
echo

echo "📁 3. Elastalert 配置文件結構"
echo "----------------------------------------"
run_remote "ls -lh /opt/elastalert2/"
echo

echo "📄 4. 主配置文件 (elastalert.yaml)"
echo "----------------------------------------"
run_remote "cat /opt/elastalert2/elastalert.yaml"
echo

echo "📊 5. 規則文件統計"
echo "----------------------------------------"
run_remote "echo '總規則數量:' && find /opt/elastalert2/rules -name '*.yaml' -type f | wc -l"
echo
run_remote "echo 'Realert 間隔分佈:' && grep -h 'minutes:' /opt/elastalert2/rules/*.yaml 2>/dev/null | sort | uniq -c | sort -rn || echo '無法統計'"
echo

echo "🔍 6. 規則目錄內容（前20個）"
echo "----------------------------------------"
run_remote "ls -1 /opt/elastalert2/rules/ | head -20"
echo

echo "📈 7. Elasticsearch 索引狀態"
echo "----------------------------------------"
run_remote "curl -s http://172.31.33.84:9200/_cat/indices/elastalert*?v&s=index"
echo

echo "📝 8. Docker 日誌（最近50行）"
echo "----------------------------------------"
run_remote "docker logs --tail 50 elastalert2"
echo

echo "✅ 完成！"

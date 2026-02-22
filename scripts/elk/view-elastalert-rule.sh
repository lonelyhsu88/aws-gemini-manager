#!/usr/bin/env bash
# View specific Elastalert2 rule file
# Usage: ./view-elastalert-rule.sh [rule-name]

set -euo pipefail

USER="ec2-user"
SERVER="18.163.127.177"
KEY="~/.ssh/hk-devops.pem"

# Function to run remote command
run_remote() {
    ssh -i "$KEY" "$USER@$SERVER" "$@"
}

if [ $# -eq 0 ]; then
    echo "用法: $0 <規則文件名>"
    echo
    echo "可用的規則文件（前30個）:"
    echo "----------------------------------------"
    run_remote "ls -1 /opt/elastalert2/rules/ | head -30"
    echo
    echo "範例: $0 some-rule.yaml"
    exit 1
fi

RULE_FILE="$1"

echo "========================================"
echo "  查看 Elastalert 規則: $RULE_FILE"
echo "========================================"
echo

# Check if rule exists
if ! run_remote "test -f /opt/elastalert2/rules/$RULE_FILE"; then
    echo "❌ 錯誤: 規則文件不存在: $RULE_FILE"
    echo
    echo "搜索類似的規則:"
    run_remote "ls -1 /opt/elastalert2/rules/ | grep -i '${RULE_FILE%.yaml}' || echo '無匹配結果'"
    exit 1
fi

# Display rule content
run_remote "cat /opt/elastalert2/rules/$RULE_FILE"

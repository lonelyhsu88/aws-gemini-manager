#!/bin/bash
# ========================================
# 快速備份 Zabbix Server EBS Volumes
# ========================================
# Instance: gemini-monitor-01 (i-040c741a76a42169b)
# Usage: ./quick-backup-zabbix.sh

set -e

export AWS_PROFILE=gemini-pro_ck
INSTANCE_ID="i-040c741a76a42169b"
INSTANCE_NAME="gemini-monitor-01"
SYSTEM_VOLUME="vol-009d7af16c7120d50"
DATA_VOLUME="vol-04386deecccee2560"
DATE=$(date +%Y%m%d-%H%M%S)

echo "========================================"
echo "🔄 Zabbix Server Emergency Backup"
echo "========================================"
echo "實例: $INSTANCE_NAME ($INSTANCE_ID)"
echo "時間: $(date)"
echo ""

# 建立系統碟 snapshot
echo "📸 建立系統碟 snapshot (60 GB)..."
SNAPSHOT_SYS=$(aws ec2 create-snapshot \
  --volume-id $SYSTEM_VOLUME \
  --description "Emergency backup - $INSTANCE_NAME system disk - $DATE" \
  --tag-specifications "ResourceType=snapshot,Tags=[
    {Key=Name,Value=zabbix-emergency-system-$DATE},
    {Key=Instance,Value=$INSTANCE_NAME},
    {Key=VolumeType,Value=system},
    {Key=Purpose,Value=emergency-backup},
    {Key=Date,Value=$(date +%Y%m%d)}
  ]" \
  --query 'SnapshotId' \
  --output text)

if [ $? -eq 0 ]; then
    echo "✅ 系統碟 Snapshot: $SNAPSHOT_SYS"
else
    echo "❌ 系統碟 Snapshot 建立失敗！"
    exit 1
fi

# 建立資料碟 snapshot
echo ""
echo "📸 建立資料碟 snapshot (100 GB)..."
SNAPSHOT_DATA=$(aws ec2 create-snapshot \
  --volume-id $DATA_VOLUME \
  --description "Emergency backup - $INSTANCE_NAME data disk - $DATE" \
  --tag-specifications "ResourceType=snapshot,Tags=[
    {Key=Name,Value=zabbix-emergency-data-$DATE},
    {Key=Instance,Value=$INSTANCE_NAME},
    {Key=VolumeType,Value=data},
    {Key=Purpose,Value=emergency-backup},
    {Key=Date,Value=$(date +%Y%m%d)}
  ]" \
  --query 'SnapshotId' \
  --output text)

if [ $? -eq 0 ]; then
    echo "✅ 資料碟 Snapshot: $SNAPSHOT_DATA"
else
    echo "❌ 資料碟 Snapshot 建立失敗！"
    exit 1
fi

echo ""
echo "========================================"
echo "✅ Backup 建立完成"
echo "========================================"
echo "系統碟 Snapshot: $SNAPSHOT_SYS"
echo "資料碟 Snapshot: $SNAPSHOT_DATA"
echo ""
echo "⏳ Snapshot 正在背景建立中，通常需要 10-30 分鐘"
echo ""
echo "📊 查看 snapshot 狀態："
echo "   aws --profile gemini-pro_ck ec2 describe-snapshots \\"
echo "     --snapshot-ids $SNAPSHOT_SYS $SNAPSHOT_DATA \\"
echo "     --query 'Snapshots[*].[SnapshotId,State,Progress]' \\"
echo "     --output table"
echo ""
echo "🔍 或使用此命令持續監控："
echo "   watch -n 10 'aws --profile gemini-pro_ck ec2 describe-snapshots \\"
echo "     --snapshot-ids $SNAPSHOT_SYS $SNAPSHOT_DATA \\"
echo "     --query \"Snapshots[*].[SnapshotId,State,Progress]\" \\"
echo "     --output table'"
echo ""
echo "========================================"

# 檢查初始狀態
echo ""
echo "📊 初始狀態："
aws ec2 describe-snapshots \
  --snapshot-ids $SNAPSHOT_SYS $SNAPSHOT_DATA \
  --query 'Snapshots[*].[SnapshotId,VolumeId,State,Progress,StartTime]' \
  --output table

echo ""
echo "💡 下一步："
echo "   1. 等待 snapshot 完成（State: completed）"
echo "   2. 執行磁碟清理或擴充操作"
echo "   3. 如需恢復，可從這些 snapshot 建立新的 volume"
echo ""

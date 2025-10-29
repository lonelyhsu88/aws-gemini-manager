#!/bin/bash
#
# Create Release-RDS-Dashboard for release environment
# This dashboard monitors: pgsqlrel, pgsqlrel-backstage
#
# Usage: ./create-release-dashboard.sh
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# AWS Configuration
AWS_PROFILE="gemini-pro_ck"
REGION="ap-east-1"
DASHBOARD_NAME="Release-RDS-Dashboard"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}📊 创建 Release-RDS-Dashboard${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "Profile: ${YELLOW}${AWS_PROFILE}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Dashboard: ${YELLOW}${DASHBOARD_NAME}${NC}"
echo ""
echo -e "${CYAN}监控实例:${NC}"
echo "  - pgsqlrel (db.t3.small)"
echo "  - pgsqlrel-backstage (db.t3.micro)"
echo ""

# Check if dashboard already exists
echo -e "${CYAN}检查现有 dashboard...${NC}"
EXISTING_DASHBOARD=$(aws --profile "$AWS_PROFILE" cloudwatch list-dashboards \
    --query "DashboardEntries[?DashboardName=='${DASHBOARD_NAME}'].DashboardName" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_DASHBOARD" ]; then
    echo -e "${YELLOW}⚠️  Dashboard '${DASHBOARD_NAME}' 已存在${NC}"
    echo ""
    read -p "是否覆盖现有 dashboard？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ Dashboard 不存在，将创建新的${NC}"
fi
echo ""

# Create dashboard JSON
cat > /tmp/release-rds-dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 24,
            "height": 1,
            "properties": {
                "markdown": "# 🚀 Release Environment RDS Dashboard\n\n监控环境: **Release** | 实例: `pgsqlrel` (db.t3.small), `pgsqlrel-backstage` (db.t3.micro) | 📍 ap-east-1\n\n---"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 1,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "CPUUtilization", { "stat": "Average", "label": "pgsqlrel" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ "...", { "stat": "Average", "label": "pgsqlrel-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "CPU Utilization (%)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "Warning (70%)",
                            "value": 70,
                            "fill": "above",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Critical (85%)",
                            "value": 85,
                            "fill": "above",
                            "color": "#d62728"
                        }
                    ]
                }
            }
        },
        {
            "type": "metric",
            "x": 8,
            "y": 1,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "DBLoad", { "stat": "Average", "label": "pgsqlrel" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ "...", { "stat": "Average", "label": "pgsqlrel-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "Database Load (DBLoad)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "Warning (1.5x vCPUs = 3)",
                            "value": 3,
                            "fill": "above",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Critical (2x vCPUs = 4)",
                            "value": 4,
                            "fill": "above",
                            "color": "#d62728"
                        }
                    ]
                }
            }
        },
        {
            "type": "metric",
            "x": 16,
            "y": 1,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "DatabaseConnections", { "stat": "Average", "label": "pgsqlrel" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ "...", { "stat": "Average", "label": "pgsqlrel-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "Database Connections",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "pgsqlrel Warning (70% of 225 = 158)",
                            "value": 158,
                            "fill": "above",
                            "color": "#ff9900"
                        },
                        {
                            "label": "pgsqlrel Critical (85% of 225 = 191)",
                            "value": 191,
                            "fill": "above",
                            "color": "#d62728"
                        }
                    ]
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 7,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "ReadIOPS", { "stat": "Average", "label": "pgsqlrel Read" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ ".", "WriteIOPS", { "stat": "Average", "label": "pgsqlrel Write" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ ".", "ReadIOPS", { "stat": "Average", "label": "pgsqlrel-backstage Read" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ],
                    [ ".", "WriteIOPS", { "stat": "Average", "label": "pgsqlrel-backstage Write" }, { "id": "m4", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "IOPS (Read/Write)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 7,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "FreeableMemory", { "stat": "Average", "label": "pgsqlrel" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ "...", { "stat": "Average", "label": "pgsqlrel-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "Freeable Memory (Bytes)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "Warning (< 1GB)",
                            "value": 1073741824,
                            "fill": "below",
                            "color": "#ff9900"
                        }
                    ]
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 13,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "FreeStorageSpace", { "stat": "Average", "label": "pgsqlrel" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ "...", { "stat": "Average", "label": "pgsqlrel-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "Free Storage Space (Bytes)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "Warning (< 10GB)",
                            "value": 10737418240,
                            "fill": "below",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Critical (< 5GB)",
                            "value": 5368709120,
                            "fill": "below",
                            "color": "#d62728"
                        }
                    ]
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 13,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "ReadLatency", { "stat": "Average", "label": "pgsqlrel Read" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ ".", "WriteLatency", { "stat": "Average", "label": "pgsqlrel Write" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel" } } ],
                    [ ".", "ReadLatency", { "stat": "Average", "label": "pgsqlrel-backstage Read" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ],
                    [ ".", "WriteLatency", { "stat": "Average", "label": "pgsqlrel-backstage Write" }, { "id": "m4", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "pgsqlrel-backstage" } } ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "ap-east-1",
                "title": "Latency (Seconds)",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                },
                "annotations": {
                    "horizontal": [
                        {
                            "label": "Read Warning (> 5ms)",
                            "value": 0.005,
                            "fill": "above",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Write Warning (> 10ms)",
                            "value": 0.010,
                            "fill": "above",
                            "color": "#ff9900"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

echo -e "${CYAN}正在创建 dashboard...${NC}"
if aws --profile "$AWS_PROFILE" cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body file:///tmp/release-rds-dashboard.json \
    2>&1; then
    echo -e "${GREEN}✅ Dashboard 创建成功${NC}"
    echo ""
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${GREEN}${BOLD}📊 Dashboard 创建总结${NC}"
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "Dashboard 名称: ${YELLOW}${DASHBOARD_NAME}${NC}"
    echo -e "监控指标:"
    echo "  ✓ CPU Utilization"
    echo "  ✓ Database Load (DBLoad)"
    echo "  ✓ Database Connections"
    echo "  ✓ IOPS (Read/Write)"
    echo "  ✓ Freeable Memory"
    echo "  ✓ Free Storage Space"
    echo "  ✓ Latency (Read/Write)"
    echo ""
    echo -e "${CYAN}监控实例:${NC}"
    echo "  • pgsqlrel (db.t3.small, 2 vCPUs, max_conn: 225)"
    echo "  • pgsqlrel-backstage (db.t3.micro, 2 vCPUs, max_conn: 112)"
    echo ""
    echo -e "${YELLOW}💡 提示:${NC}"
    echo -e "  - 访问 CloudWatch Console 查看 dashboard:"
    echo -e "    ${CYAN}https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=${DASHBOARD_NAME}${NC}"
    echo ""
    echo -e "  - 下一步: 创建 CloudWatch 告警（无 SNS 通知）:"
    echo -e "    ${CYAN}./create-release-alarms.sh${NC}"
    echo ""
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${GREEN}✅ 完成${NC}"
    echo -e "${BLUE}================================================================================================${NC}"
else
    echo -e "${RED}❌ Dashboard 创建失败${NC}"
    exit 1
fi

# Cleanup
rm -f /tmp/release-rds-dashboard.json

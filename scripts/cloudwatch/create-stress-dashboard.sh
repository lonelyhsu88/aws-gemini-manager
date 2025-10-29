#!/bin/bash
#
# Create Stress-RDS-Dashboard for stress environment
# This dashboard monitors: bingo-stress, bingo-stress-backstage, bingo-stress-loyalty
#
# Usage: ./create-stress-dashboard.sh
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
DASHBOARD_NAME="Stress-RDS-Dashboard"

echo -e "${BLUE}================================================================================================${NC}"
echo -e "${CYAN}${BOLD}📊 创建 Stress-RDS-Dashboard${NC}"
echo -e "${BLUE}================================================================================================${NC}"
echo -e "Profile: ${YELLOW}${AWS_PROFILE}${NC}"
echo -e "Region: ${YELLOW}${REGION}${NC}"
echo -e "Dashboard: ${YELLOW}${DASHBOARD_NAME}${NC}"
echo ""
echo -e "${CYAN}监控实例:${NC}"
echo "  - bingo-stress"
echo "  - bingo-stress-backstage"
echo "  - bingo-stress-loyalty"
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
cat > /tmp/stress-rds-dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 24,
            "height": 1,
            "properties": {
                "markdown": "# 🔧 Stress Environment RDS Dashboard\n\n监控环境: **Stress** | 实例: `bingo-stress`, `bingo-stress-backstage`, `bingo-stress-loyalty` | 📍 ap-east-1\n\n---"
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
                    [ "AWS/RDS", "CPUUtilization", { "stat": "Average", "label": "bingo-stress" }, { "id": "m1", "region": "ap-east-1" } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-backstage" }, { "id": "m2", "region": "ap-east-1" } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-loyalty" }, { "id": "m3", "region": "ap-east-1" } ]
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
                    [ "AWS/RDS", "DBLoad", { "stat": "Average", "label": "bingo-stress" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-loyalty" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
                    [ "AWS/RDS", "DatabaseConnections", { "stat": "Average", "label": "bingo-stress" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-loyalty" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
                            "label": "Warning (70% of 450 = 315)",
                            "value": 315,
                            "fill": "above",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Critical (85% of 450 = 383)",
                            "value": 383,
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
                    [ "AWS/RDS", "ReadIOPS", { "stat": "Average", "label": "bingo-stress Read" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ ".", "WriteIOPS", { "stat": "Average", "label": "bingo-stress Write" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ ".", "ReadIOPS", { "stat": "Average", "label": "bingo-stress-backstage Read" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ ".", "WriteIOPS", { "stat": "Average", "label": "bingo-stress-backstage Write" }, { "id": "m4", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ ".", "ReadIOPS", { "stat": "Average", "label": "bingo-stress-loyalty Read" }, { "id": "m5", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ],
                    [ ".", "WriteIOPS", { "stat": "Average", "label": "bingo-stress-loyalty Write" }, { "id": "m6", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
                    [ "AWS/RDS", "FreeableMemory", { "stat": "Average", "label": "bingo-stress" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-loyalty" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
                    [ "AWS/RDS", "FreeStorageSpace", { "stat": "Average", "label": "bingo-stress" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-backstage" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ "...", { "stat": "Average", "label": "bingo-stress-loyalty" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
                            "label": "Warning (< 50GB)",
                            "value": 53687091200,
                            "fill": "below",
                            "color": "#ff9900"
                        },
                        {
                            "label": "Critical (< 20GB)",
                            "value": 21474836480,
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
                    [ "AWS/RDS", "ReadLatency", { "stat": "Average", "label": "bingo-stress Read" }, { "id": "m1", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ ".", "WriteLatency", { "stat": "Average", "label": "bingo-stress Write" }, { "id": "m2", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress" } } ],
                    [ ".", "ReadLatency", { "stat": "Average", "label": "bingo-stress-backstage Read" }, { "id": "m3", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ ".", "WriteLatency", { "stat": "Average", "label": "bingo-stress-backstage Write" }, { "id": "m4", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-backstage" } } ],
                    [ ".", "ReadLatency", { "stat": "Average", "label": "bingo-stress-loyalty Read" }, { "id": "m5", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ],
                    [ ".", "WriteLatency", { "stat": "Average", "label": "bingo-stress-loyalty Write" }, { "id": "m6", "region": "ap-east-1", "dimensions": { "DBInstanceIdentifier": "bingo-stress-loyalty" } } ]
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
    --dashboard-body file:///tmp/stress-rds-dashboard.json \
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
    echo "  • bingo-stress"
    echo "  • bingo-stress-backstage"
    echo "  • bingo-stress-loyalty"
    echo ""
    echo -e "${YELLOW}💡 提示:${NC}"
    echo -e "  - 访问 CloudWatch Console 查看 dashboard:"
    echo -e "    ${CYAN}https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=${DASHBOARD_NAME}${NC}"
    echo ""
    echo -e "  - 下一步: 创建 CloudWatch 告警（无 SNS 通知）:"
    echo -e "    ${CYAN}./create-stress-alarms.sh${NC}"
    echo ""
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${GREEN}✅ 完成${NC}"
    echo -e "${BLUE}================================================================================================${NC}"
else
    echo -e "${RED}❌ Dashboard 创建失败${NC}"
    exit 1
fi

# Cleanup
rm -f /tmp/stress-rds-dashboard.json

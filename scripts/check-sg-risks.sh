#!/bin/bash
# Security Group Risk Assessment Script
# Quick check for high-risk security configurations

PROFILE="gemini-pro_ck"
REGION="ap-east-1"

echo "========================================"
echo "Security Group Risk Assessment"
echo "========================================"
echo ""
echo "Date: $(date)"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo ""

# Check for SSH exposed to internet
echo "🔍 Checking for SSH (22) exposed to 0.0.0.0/0..."
SSH_EXPOSED=$(aws ec2 describe-security-groups \
  --profile $PROFILE \
  --region $REGION \
  --filters "Name=ip-permission.from-port,Values=22" \
            "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output text)

if [ -z "$SSH_EXPOSED" ]; then
  echo "  ✅ No SSH ports exposed to internet"
else
  echo "  🔴 WARNING: Found SSH exposed to internet:"
  echo "$SSH_EXPOSED" | while read line; do
    echo "    - $line"
  done
fi
echo ""

# Check for RDP exposed to internet
echo "🔍 Checking for RDP (3389) exposed to 0.0.0.0/0..."
RDP_EXPOSED=$(aws ec2 describe-security-groups \
  --profile $PROFILE \
  --region $REGION \
  --filters "Name=ip-permission.from-port,Values=3389" \
            "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output text)

if [ -z "$RDP_EXPOSED" ]; then
  echo "  ✅ No RDP ports exposed to internet"
else
  echo "  🔴 WARNING: Found RDP exposed to internet:"
  echo "$RDP_EXPOSED" | while read line; do
    echo "    - $line"
  done
fi
echo ""

# Check for common database ports exposed to internet
echo "🔍 Checking for database ports exposed to 0.0.0.0/0..."
DB_PORTS=(3306 5432 1433 27017 6379)
DB_EXPOSED=false

for PORT in "${DB_PORTS[@]}"; do
  RESULT=$(aws ec2 describe-security-groups \
    --profile $PROFILE \
    --region $REGION \
    --filters "Name=ip-permission.from-port,Values=$PORT" \
              "Name=ip-permission.cidr,Values=0.0.0.0/0" \
    --query 'SecurityGroups[].[GroupId,GroupName]' \
    --output text)

  if [ ! -z "$RESULT" ]; then
    if [ "$DB_EXPOSED" = false ]; then
      echo "  🔴 WARNING: Found database ports exposed to internet:"
      DB_EXPOSED=true
    fi
    echo "    Port $PORT:"
    echo "$RESULT" | while read line; do
      echo "      - $line"
    done
  fi
done

if [ "$DB_EXPOSED" = false ]; then
  echo "  ✅ No database ports exposed to internet"
fi
echo ""

# Count unused security groups
echo "🔍 Checking for unused Security Groups..."
TOTAL_SG=$(aws ec2 describe-security-groups \
  --profile $PROFILE \
  --region $REGION \
  --query 'length(SecurityGroups[])' \
  --output text)

# Get all used SG IDs from EC2 instances
USED_BY_EC2=$(aws ec2 describe-instances \
  --profile $PROFILE \
  --region $REGION \
  --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \
  --output text | tr '\t' '\n' | sort -u)

# Get all used SG IDs from RDS instances
USED_BY_RDS=$(aws rds describe-db-instances \
  --profile $PROFILE \
  --region $REGION \
  --query 'DBInstances[].VpcSecurityGroups[].VpcSecurityGroupId' \
  --output text | tr '\t' '\n' | sort -u)

# Get all used SG IDs from network interfaces
USED_BY_ENI=$(aws ec2 describe-network-interfaces \
  --profile $PROFILE \
  --region $REGION \
  --query 'NetworkInterfaces[].Groups[].GroupId' \
  --output text | tr '\t' '\n' | sort -u)

# Combine all used SG IDs
ALL_USED=$(echo -e "$USED_BY_EC2\n$USED_BY_RDS\n$USED_BY_ENI" | sort -u | grep -v '^$')
USED_COUNT=$(echo "$ALL_USED" | wc -l | tr -d ' ')

UNUSED_COUNT=$((TOTAL_SG - USED_COUNT))

echo "  Total Security Groups: $TOTAL_SG"
echo "  Used: $USED_COUNT"
echo "  Unused: $UNUSED_COUNT"

if [ $UNUSED_COUNT -gt 0 ]; then
  UNUSED_RATE=$(echo "scale=1; $UNUSED_COUNT * 100 / $TOTAL_SG" | bc)
  echo "  Unused rate: ${UNUSED_RATE}%"

  if (( $(echo "$UNUSED_RATE > 30" | bc -l) )); then
    echo "  🔴 High unused rate - cleanup recommended"
  elif (( $(echo "$UNUSED_RATE > 10" | bc -l) )); then
    echo "  🟡 Moderate unused rate - consider cleanup"
  else
    echo "  🟢 Low unused rate - acceptable"
  fi
fi
echo ""

# Summary
echo "========================================"
echo "Summary"
echo "========================================"

RISK_SCORE=0

if [ ! -z "$SSH_EXPOSED" ]; then
  RISK_SCORE=$((RISK_SCORE + 3))
fi

if [ ! -z "$RDP_EXPOSED" ]; then
  RISK_SCORE=$((RISK_SCORE + 3))
fi

if [ "$DB_EXPOSED" = true ]; then
  RISK_SCORE=$((RISK_SCORE + 3))
fi

if [ $UNUSED_COUNT -gt $((TOTAL_SG * 30 / 100)) ]; then
  RISK_SCORE=$((RISK_SCORE + 2))
elif [ $UNUSED_COUNT -gt $((TOTAL_SG * 10 / 100)) ]; then
  RISK_SCORE=$((RISK_SCORE + 1))
fi

echo "Overall Risk Score: $RISK_SCORE/10"
echo ""

if [ $RISK_SCORE -ge 6 ]; then
  echo "🔴 HIGH RISK - Immediate action required"
  echo "   Please review the detailed analysis report and optimization plan:"
  echo "   - docs/security-group-analysis.md"
  echo "   - docs/security-group-optimization-plan.md"
elif [ $RISK_SCORE -ge 3 ]; then
  echo "🟡 MEDIUM RISK - Action recommended"
  echo "   Please review the optimization plan:"
  echo "   - docs/security-group-optimization-plan.md"
else
  echo "🟢 LOW RISK - Configuration is acceptable"
  echo "   Continue monitoring and regular audits"
fi

echo ""
echo "========================================"

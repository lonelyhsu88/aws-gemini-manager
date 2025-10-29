#!/bin/bash

# List all RDS instances using gemini-pro_ck profile
# Usage: ./list-instances.sh

set -e

AWS_PROFILE=gemini-pro_ck

echo "==================================="
echo "RDS Instances (Profile: ${AWS_PROFILE})"
echo "==================================="
echo ""

# Get detailed instance information
aws --profile ${AWS_PROFILE} rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Engine,DBInstanceClass,AvailabilityZone,AllocatedStorage]' \
  --output table

echo ""
echo "-----------------------------------"

# Count total instances
TOTAL=$(aws --profile ${AWS_PROFILE} rds describe-db-instances --query 'length(DBInstances)')
echo "Total RDS Instances: ${TOTAL}"

# Count by status
AVAILABLE=$(aws --profile ${AWS_PROFILE} rds describe-db-instances \
  --query 'length(DBInstances[?DBInstanceStatus==`available`])')
echo "Available: ${AVAILABLE}"

# Count by engine
PG_COUNT=$(aws --profile ${AWS_PROFILE} rds describe-db-instances \
  --query 'length(DBInstances[?Engine==`postgres`])')
echo "PostgreSQL: ${PG_COUNT}"

echo "==================================="

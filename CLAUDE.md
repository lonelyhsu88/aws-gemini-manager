# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this AWS management project.

## Project Overview

**aws-gemini-manager** is an AWS resource management tool that uses the AWS CLI profile `gemini-pro_ck` to manage and automate AWS operations.

## AWS Configuration

### AWS Profile
- **Profile Name**: `gemini-pro_ck`
- **Usage**: All AWS CLI commands and SDK calls should use this profile

### Common AWS Commands

```bash
# List AWS resources using the profile
aws --profile gemini-pro_ck s3 ls
aws --profile gemini-pro_ck ec2 describe-instances
aws --profile gemini-pro_ck rds describe-db-instances
aws --profile gemini-pro_ck cloudwatch get-metric-statistics

# Verify profile configuration
aws --profile gemini-pro_ck sts get-caller-identity

# Export profile for scripts
export AWS_PROFILE=gemini-pro_ck
```

## Implementation Approach

**混合使用策略** - 根據任務複雜度選擇合適的工具：

### 🔧 使用 Shell Script + AWS CLI 的場景
- ✅ 簡單的資源查詢（列出 EC2、RDS、S3）
- ✅ 一次性操作（啟動/停止實例）
- ✅ 快速驗證和測試
- ✅ 單一命令就能完成的任務

**範例**:
```bash
aws --profile gemini-pro_ck ec2 describe-instances
aws --profile gemini-pro_ck s3 ls
```

### 🐍 使用 Python + Boto3 的場景
- ✅ 複雜的數據處理和分析
- ✅ 需要錯誤處理和重試邏輯
- ✅ 批量操作多個資源
- ✅ 需要整合其他系統或 API
- ✅ 產生報表或視覺化

**範例**:
```python
import boto3
session = boto3.Session(profile_name='gemini-pro_ck')
ec2 = session.client('ec2')
# 複雜的邏輯處理...
```

## Development Setup

### Prerequisites
- AWS CLI installed and configured
- Profile `gemini-pro_ck` configured in `~/.aws/credentials` and `~/.aws/config`
- Node.js (if using AWS SDK for JavaScript)
- Python 3.x + boto3 (for complex operations): `pip install boto3`

### Verify AWS Profile Setup
```bash
# Check if profile exists
aws configure list-profiles | grep gemini-pro_ck

# Test profile access
aws --profile gemini-pro_ck sts get-caller-identity
```

## Project Structure

```
aws-gemini-manager/
├── CLAUDE.md                           # This file - Claude Code guidance
├── README.md                           # Project documentation
├── CLOUDWATCH_BINGO_STRESS_ANALYSIS.md # CloudWatch metrics analysis
├── check_metrics_activity.py           # Python script for metric activity analysis
├── scripts/                            # Management scripts
│   ├── s3/                            # S3 management scripts
│   ├── ec2/                           # EC2 management scripts
│   ├── rds/                           # RDS management scripts
│   └── cloudwatch/                    # CloudWatch monitoring scripts
│       └── list-bingo-stress-metrics.sh
├── .claude/                           # Claude-specific configuration
│   └── context.json                   # Structured project context
└── config/                            # Configuration files
    └── aws-config.json                # AWS resource configurations
```

## Common Tasks

### S3 Management
```bash
# List buckets
aws --profile gemini-pro_ck s3 ls

# Sync files
aws --profile gemini-pro_ck s3 sync ./local-dir s3://bucket-name/path/
```

### EC2 Management
```bash
# List instances
aws --profile gemini-pro_ck ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0]]' --output table

# Start/Stop instances
aws --profile gemini-pro_ck ec2 start-instances --instance-ids i-xxxxx
aws --profile gemini-pro_ck ec2 stop-instances --instance-ids i-xxxxx
```

### RDS Management
```bash
# List databases
aws --profile gemini-pro_ck rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Engine]' --output table

# Check database connections (current status)
./scripts/rds/check-connections.sh

# Check database connections (with 24h peak analysis)
./scripts/rds/check-connections-peak.sh

# List all RDS instances
./scripts/rds/list-instances.sh

# Create snapshot
aws --profile gemini-pro_ck rds create-db-snapshot --db-instance-identifier mydb --db-snapshot-identifier mydb-snapshot-$(date +%Y%m%d)
```

**RDS Scripts**:
- `scripts/rds/check-connections.sh` - 快速檢查當前連接數
- `scripts/rds/check-connections-peak.sh` - 詳細連接數分析（含24小時峰值）
- `scripts/rds/list-instances.sh` - 列出所有 RDS 實例

詳細說明請參考: `scripts/rds/README.md`

### CloudWatch Management
```bash
# List all bingo-stress CloudWatch metrics
./scripts/cloudwatch/list-bingo-stress-metrics.sh

# Detailed metric activity analysis (Python)
python3 check_metrics_activity.py
```

**CloudWatch Scripts**:
- `scripts/cloudwatch/list-bingo-stress-metrics.sh` - 列出 bingo-stress 實例的 CloudWatch 指標
- `check_metrics_activity.py` - 詳細分析指標活動狀態（Python）

詳細分析報告: `CLOUDWATCH_BINGO_STRESS_ANALYSIS.md`

## Environment Variables

When writing scripts, ensure the AWS profile is set:

```bash
export AWS_PROFILE=gemini-pro_ck
export AWS_DEFAULT_REGION=us-east-1  # or your preferred region
```

For Node.js scripts:
```javascript
const AWS = require('aws-sdk');
AWS.config.credentials = new AWS.SharedIniFileCredentials({profile: 'gemini-pro_ck'});
```

For Python scripts:
```python
import boto3
session = boto3.Session(profile_name='gemini-pro_ck')
client = session.client('s3')
```

## Security Best Practices

1. **Never commit AWS credentials** to the repository
2. Use the profile for all operations - don't hardcode credentials
3. Implement least-privilege IAM policies
4. Enable MFA for sensitive operations
5. Regularly rotate access keys

## Development Workflow

When working on this project:
1. Always verify the AWS profile is correctly set (`gemini-pro_ck`)
2. Test scripts in development/staging before production
3. Log all operations for audit trails
4. Use AWS resource tags for organization
5. Document new scripts in this file

## Monitoring and Logging

- CloudWatch logs location: (to be configured)
- Script execution logs: `./logs/`
- Error handling: All scripts should log errors to both console and log files

## Notes for Claude Code

- When generating AWS CLI commands, ALWAYS include `--profile gemini-pro_ck`
- When creating SDK code, ensure the profile is configured
- Prefer using AWS SDK over CLI for complex operations
- Include error handling and logging in all scripts
- Test resource availability before operations

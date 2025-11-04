# CloudWatch Dashboard Read-Only Policy for OP Team

## Overview

Created a minimal IAM policy to grant OP team members read-only access to CloudWatch Dashboards.

## Policy Details

- **Policy Name**: `CloudWatchDashboardReadOnlyForOPTeam`
- **Policy ARN**: `arn:aws:iam::470013648166:policy/CloudWatchDashboardReadOnlyForOPTeam`
- **Created**: 2025-11-04
- **Attached To**: `op-team` group

## Permissions Granted

The policy grants only two permissions:
- `cloudwatch:GetDashboard` - View specific dashboards
- `cloudwatch:ListDashboards` - List all available dashboards

## Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchDashboardReadOnly",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetDashboard",
                "cloudwatch:ListDashboards"
            ],
            "Resource": "*"
        }
    ]
}
```

## Rationale

This policy was created to resolve the permission error:
```
arn:aws:iam::470013648166:user/op-james.z is not authorized to perform:
cloudwatch:GetDashboard on resource: arn:aws:cloudwatch::470013648166:dashboard/WAF-Monitoring-Dashboard
```

Initially considered using the AWS managed `CloudWatchReadOnlyAccess` policy, but it grants excessive permissions including:
- CloudWatch Logs access
- CloudWatch Metrics access
- CloudWatch Alarms access
- SNS, X-Ray, Synthetics access

Following the principle of least privilege, a custom policy was created with only the minimum required permissions for viewing dashboards.

## Usage

To attach this policy to additional groups or users:

```bash
# Attach to a group
aws --profile gemini-pro_ck iam attach-group-policy \
  --group-name <group-name> \
  --policy-arn arn:aws:iam::470013648166:policy/CloudWatchDashboardReadOnlyForOPTeam

# Attach to a user
aws --profile gemini-pro_ck iam attach-user-policy \
  --user-name <user-name> \
  --policy-arn arn:aws:iam::470013648166:policy/CloudWatchDashboardReadOnlyForOPTeam
```

## Current Group Policies

The `op-team` group now has the following policies attached:

1. AWSCertificateManagerForOP
2. AmazonS3ReadOnelyAccessForOPTeam
3. AmazonSecurityGroupReadOnelyAccessForOPTeam
4. **CloudWatchDashboardReadOnlyForOPTeam** (new)
5. AmazonRDSReadOnelyAccessForOPTeam
6. AmazonRoute53ForOPAccess
7. AmazonEC2ReadOnelyAccessForOPTeam
8. AmazonRDSReadOnlyAccess (AWS managed)

## Verification

Members of the `op-team` group should now be able to:
- ✅ View all CloudWatch dashboards in the AWS Console
- ✅ Access the WAF-Monitoring-Dashboard
- ✅ List all available dashboards

They cannot:
- ❌ Create, modify, or delete dashboards
- ❌ View CloudWatch Metrics directly
- ❌ Access CloudWatch Logs
- ❌ Manage CloudWatch Alarms

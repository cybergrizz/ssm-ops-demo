# Runbook: Session Manager & IAM Access Troubleshooting

**Document Type:** Operational Runbook  
**Maintained By:** Platform Engineering  
**Last Updated:** 2025  
**Applies To:** Amazon Linux 2 instances managed via AWS Systems Manager  

---

## Purpose

This runbook covers how to start and manage Session Manager sessions, use port forwarding for secure access, and troubleshoot the most common IAM-related issues that prevent instances from appearing in SSM Fleet Manager.

Session Manager replaces SSH and bastion host access. All sessions are encrypted, logged, and auditable without opening inbound ports.

---

## Prerequisites

- AWS CLI installed and configured (`aws configure`)
- Session Manager plugin installed locally:

```bash
# Install Session Manager plugin (Linux/Mac)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb

# Verify installation
session-manager-plugin --version
```

- Target instance must be Online in SSM Fleet Manager
- Your IAM user/role must have `ssm:StartSession` permission

---

## Starting a Session

### Basic Shell Session

```bash
aws ssm start-session \
  --target <instance-id>
```

This opens an interactive shell on the target instance. No SSH key required. No inbound port 22 required.

### Session to a Specific User

By default, sessions open as `ssm-user`. To start as a different user, configure the Session Manager preferences document in the AWS Console under Systems Manager > Session Manager > Preferences.

### List Active Sessions

```bash
aws ssm describe-sessions \
  --state Active \
  --output table
```

### Terminate a Session

```bash
aws ssm terminate-session \
  --session-id <session-id>
```

---

## Port Forwarding

Port forwarding allows secure access to services running on an instance (databases, internal web apps) without opening security group rules.

### Forward a Remote Port to Local

```bash
# Forward instance port 3306 (MySQL) to local port 13306
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=3306,localPortNumber=13306
```

Then connect locally:

```bash
mysql -h 127.0.0.1 -P 13306 -u <user> -p
```

### Forward to a Remote Host via Instance (Jump Host Pattern)

```bash
# Forward to an RDS instance accessible only from the EC2 instance
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=<rds-endpoint>,portNumber=5432,localPortNumber=15432
```

---

## Session Logging

All sessions should be logged for audit purposes. Confirm logging is configured:

```bash
# View current Session Manager preferences
aws ssm get-document \
  --name SSM-SessionManagerRunShell \
  --query "Content" \
  --output text
```

If logging is not configured, update Session Manager preferences in the console:

- **Systems Manager → Session Manager → Preferences**
- Enable CloudWatch Logs: set log group (e.g. `/ssm/session-logs`)
- Enable S3 logging: set bucket and prefix

> **Why this matters:** Session logs are an audit control. In compliance-aware environments, unlogged sessions are a finding.

---

## IAM Troubleshooting

The most common cause of SSM access issues is IAM misconfiguration. Work through these steps in order before escalating.

### Step 1: Confirm Instance Appears in Fleet Manager

```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]" \
  --output table
```

**If instance is missing entirely** → proceed to Step 2.  
**If instance appears but PingStatus is ConnectionLost** → proceed to Step 4.  
**If instance appears and is Online** → IAM is not the issue, check security groups or Session Manager plugin.

---

### Step 2: Verify IAM Instance Profile is Attached

```bash
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query "Reservations[*].Instances[*].IamInstanceProfile" \
  --output table
```

If no profile is returned, attach one:

```bash
aws ec2 associate-iam-instance-profile \
  --instance-id <instance-id> \
  --iam-instance-profile Name=SSMInstanceProfile
```

> **Note:** After attaching an instance profile, allow 2–3 minutes for the SSM Agent to register the instance.

---

### Step 3: Verify the IAM Role Has Required Permissions

The instance role must include the following permissions at minimum for SSM core functions:

| Permission | Purpose |
|---|---|
| `ssm:UpdateInstanceInformation` | Instance registration with SSM |
| `ssm:ListAssociations` | Receive association configurations |
| `ssm:ListInstanceAssociations` | Retrieve applied associations |
| `ssmmessages:CreateControlChannel` | Session Manager communication |
| `ssmmessages:CreateDataChannel` | Session Manager data transfer |
| `ssmmessages:OpenControlChannel` | Open session channel |
| `ssmmessages:OpenDataChannel` | Open session data channel |
| `ec2messages:AcknowledgeMessage` | Run Command message handling |
| `ec2messages:DeleteMessage` | Run Command cleanup |
| `ec2messages:FailMessage` | Run Command error reporting |
| `ec2messages:GetEndpoint` | Run Command endpoint resolution |
| `ec2messages:GetMessages` | Run Command message polling |
| `ec2messages:SendReply` | Run Command response |

The simplest path is attaching the AWS managed policy:

```bash
aws iam attach-role-policy \
  --role-name SSMInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

To verify what policies are currently attached:

```bash
aws iam list-attached-role-policies \
  --role-name SSMInstanceRole \
  --output table
```

---

### Step 4: Check SSM Agent Status on the Instance

If you have an alternative access path (EC2 console, another session), check the agent directly:

```bash
# Check SSM Agent service status
sudo systemctl status amazon-ssm-agent

# Restart if stopped
sudo systemctl restart amazon-ssm-agent

# View agent logs
sudo tail -100 /var/log/amazon/ssm/amazon-ssm-agent.log
```

Common agent log error patterns:

| Log Message | Meaning |
|---|---|
| `Unable to load instance info` | IAM role not attached or permissions missing |
| `Error occurred fetching the seelog config` | Agent config file issue — reinstall agent |
| `Failed to refresh credentials` | Metadata service unreachable or role misconfigured |
| `AccessDeniedException` | Specific permission missing in IAM policy |

---

### Step 5: Verify VPC Endpoint or Internet Access

SSM Agent requires outbound HTTPS access to three endpoints. In private VPCs with no internet gateway, VPC endpoints must be configured.

Required endpoints:
- `ssm.<region>.amazonaws.com`
- `ssmmessages.<region>.amazonaws.com`
- `ec2messages.<region>.amazonaws.com`

Check connectivity from the instance (requires alternative access):

```bash
curl -sf --max-time 5 https://ssm.us-east-1.amazonaws.com
curl -sf --max-time 5 https://ssmmessages.us-east-1.amazonaws.com
curl -sf --max-time 5 https://ec2messages.us-east-1.amazonaws.com
```

If these fail in a private VPC:

```bash
# Create VPC endpoint for SSM (repeat for ssmmessages and ec2messages)
aws ec2 create-vpc-endpoint \
  --vpc-id <vpc-id> \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.ssm \
  --subnet-ids <subnet-id> \
  --security-group-ids <sg-id>
```

---

## Quick Reference: IAM Issue Decision Tree

```
Instance missing from Fleet Manager?
│
├── No IAM profile attached?
│   └── → Attach SSMInstanceProfile to EC2 instance
│
├── Profile attached but role missing permissions?
│   └── → Attach AmazonSSMManagedInstanceCore policy
│
├── Permissions correct but agent not connecting?
│   ├── Agent stopped?
│   │   └── → Restart amazon-ssm-agent service
│   └── No outbound HTTPS?
│       └── → Create VPC endpoints or verify internet gateway
│
└── All of above OK but still offline?
    └── → Check agent logs, consider reinstalling SSM Agent
```

---

## Related Documents

- `runbook-patching.md` — Patch operations that depend on Session Manager access
- `runbook-run-command.md` — Bulk command execution across instances
- `iam/ssm-instance-profile.json` — Reference IAM policy for SSM access

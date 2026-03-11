# Runbook: Run Command Operations

**Document Type:** Operational Runbook  
**Maintained By:** Platform Engineering  
**Last Updated:** 2025  
**Applies To:** Amazon Linux 2 instances managed via AWS Systems Manager  

---

## Purpose

This runbook covers how to execute commands at scale across SSM-managed instances using Run Command, target instances effectively, review output, and handle failures. Run Command is the primary mechanism for running custom SSM documents and operational tasks across the fleet without requiring direct instance access.

---

## Prerequisites

- Target instances are Online in SSM Fleet Manager
- Instance IAM role includes `ec2messages:*` permissions (via `AmazonSSMManagedInstanceCore`)
- Your IAM user/role has `ssm:SendCommand` and `ssm:GetCommandInvocation` permissions
- AWS CLI configured locally

---

## Core Concepts

| Concept | Description |
|---|---|
| **Document** | The SSM document defining what to run (AWS-managed or custom) |
| **Target** | The set of instances to run the command on (by ID, tag, or resource group) |
| **CommandId** | Unique identifier for a Run Command execution — used to track status |
| **Invocation** | A single instance's execution of a command |
| **MaxConcurrency** | How many instances run the command simultaneously |
| **MaxErrors** | How many instance failures before the command stops executing on remaining targets |

---

## Targeting Instances

Run Command supports four targeting methods. Use the most specific method appropriate for the task.

### By Instance ID (single or small group)

```bash
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=instanceids,Values=i-0abc123,i-0def456" \
  --comment "Targeted health check"
```

### By Tag (recommended for fleet operations)

```bash
# All instances tagged Environment=prod
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=tag:Environment,Values=prod" \
  --comment "Prod fleet health check"
```

### By Patch Group

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters Operation=Scan \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard" \
  --comment "Patch group scan"
```

### All Managed Instances (use with caution)

```bash
# Target all online instances — use only for low-risk read operations
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=instanceids,Values=*" \
  --max-concurrency 10 \
  --max-errors 5 \
  --comment "Fleet-wide health check"
```

> **Caution:** Targeting all instances with write or install operations requires explicit change approval.

---

## Executing Custom SSM Documents

### Run the Health Check Document

```bash
aws ssm send-command \
  --document-name "health-check" \
  --parameters Services="httpd,crond,amazon-ssm-agent",DiskThresholdPercent="85" \
  --targets "Key=tag:Environment,Values=dev" \
  --comment "Dev environment health check" \
  --output text \
  --query "Command.CommandId"
```

### Run the Log Collector Document

```bash
aws ssm send-command \
  --document-name "log-collector" \
  --parameters \
    LogPaths="/var/log/httpd/*.log /var/log/messages",\
    S3BucketName="my-log-bucket",\
    S3KeyPrefix="incident-response/2025-01-15",\
    MaxLogAgeDays="1" \
  --targets "Key=instanceids,Values=<instance-id>" \
  --comment "Incident response log collection - INC-1234" \
  --output text \
  --query "Command.CommandId"
```

### Run the Compliance Scan Document

```bash
aws ssm send-command \
  --document-name "compliance-scan" \
  --parameters \
    AllowedOpenPorts="22,443,8080",\
    CheckSSHConfig="true",\
    CheckFilePermissions="true" \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard" \
  --comment "Monthly compliance scan" \
  --output text \
  --query "Command.CommandId"
```

---

## Monitoring Command Execution

### Check Overall Command Status

```bash
aws ssm list-commands \
  --command-id <command-id> \
  --query "Commands[*].[CommandId,Status,StatusDetails,TargetCount,CompletedCount,ErrorCount]" \
  --output table
```

**Command Status Values:**

| Status | Meaning |
|---|---|
| Pending | Command queued, not yet delivered to instances |
| InProgress | Running on one or more instances |
| Success | Completed successfully on all targets |
| Failed | One or more instances returned a non-zero exit code |
| TimedOut | Command exceeded timeout window |
| Cancelled | Manually cancelled |
| DeliveryTimedOut | Agent did not receive command within delivery timeout |

### Check Per-Instance Invocation Status

```bash
# List all invocations for a command
aws ssm list-command-invocations \
  --command-id <command-id> \
  --details \
  --query "CommandInvocations[*].[InstanceId,Status,StatusDetails]" \
  --output table
```

### View Command Output for a Specific Instance

```bash
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id> \
  --query "[Status,StatusDetails,StandardOutputContent,StandardErrorContent]" \
  --output text
```

> **Tip:** `StandardErrorContent` is the first place to look when a command fails. It often contains the exact shell error.

---

## Controlling Blast Radius

For any command running across multiple instances, always set `--max-concurrency` and `--max-errors` explicitly.

```bash
aws ssm send-command \
  --document-name "compliance-scan" \
  --targets "Key=tag:Environment,Values=prod" \
  --max-concurrency "25%" \   # Run on 25% of targets at a time
  --max-errors "2" \          # Stop if 2 instances fail
  --comment "Prod compliance scan - controlled rollout"
```

**Guidance on values:**

| Scenario | MaxConcurrency | MaxErrors |
|---|---|---|
| Read-only operations (scans, health checks) | 50% or higher | 10% |
| Write operations (installs, config changes) | 1–25% | 1–2 |
| Emergency single-instance operations | 1 | 0 |
| Patch installs via maintenance window | 2 (absolute) | 1 |

---

## Handling Failures

### Step 1: Identify Which Instances Failed

```bash
aws ssm list-command-invocations \
  --command-id <command-id> \
  --filters "Key=Status,Values=Failed,TimedOut,DeliveryTimedOut" \
  --output table
```

### Step 2: Pull Error Output

```bash
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <failed-instance-id> \
  --query "StandardErrorContent" \
  --output text
```

### Step 3: Diagnose Common Failure Patterns

| Failure Pattern | Likely Cause | Resolution |
|---|---|---|
| `exit code 1` with no stderr | Script logic failure | Review stdout for WARNING lines |
| `Permission denied` | Script requires elevated privileges | Check if `runAs` config is needed in SSM preferences |
| `command not found` | Package not installed on instance | Verify AMI baseline includes required packages |
| `DeliveryTimedOut` | SSM Agent unreachable | Check agent status via Session Manager or console |
| `AccessDeniedException` | IAM role missing permissions | Review instance profile policy |
| `S3 upload failed` (log-collector) | Missing `s3:PutObject` in instance role | Add S3 permission to instance profile |

### Step 4: Retry on Failed Instances Only

Rather than re-running across all targets, retry only on failed instances:

```bash
# Collect failed instance IDs from previous run
FAILED_IDS=$(aws ssm list-command-invocations \
  --command-id <command-id> \
  --filters "Key=Status,Values=Failed" \
  --query "CommandInvocations[*].InstanceId" \
  --output text | tr '\t' ',')

# Retry on failed instances only
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=instanceids,Values=$FAILED_IDS" \
  --comment "Retry after failure - original CommandId <command-id>"
```

---

## Cancelling a Running Command

If a command is causing unintended behavior, cancel it immediately:

```bash
aws ssm cancel-command \
  --command-id <command-id>
```

> **Note:** Cancellation stops delivery to pending instances but does not interrupt commands already in progress on active instances.

---

## Audit and History

Run Command history is retained in SSM for 30 days by default. For longer retention, configure command output to write to S3 or CloudWatch Logs when sending commands:

```bash
aws ssm send-command \
  --document-name "compliance-scan" \
  --targets "Key=tag:Environment,Values=prod" \
  --cloud-watch-output-config \
    CloudWatchOutputEnabled=true,CloudWatchLogGroupName=/ssm/run-command/compliance-scan \
  --comment "Compliance scan with audit logging"
```

---

## Related Documents

- `runbook-session-manager.md` — Access instances directly when Run Command is insufficient
- `runbook-patching.md` — Patch operations that use Run Command under the hood
- `ssm-documents/health-check.yaml` — Document executed for health validation
- `ssm-documents/log-collector.yaml` — Document executed for incident log collection
- `ssm-documents/compliance-scan.yaml` — Document executed for compliance posture review

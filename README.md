# ssm-ops-demo

A portfolio project demonstrating enterprise-grade AWS Systems Manager (SSM) operations, patching automation, and IAM access management. Built to reflect real-world platform engineering responsibilities in compliance-aware environments.

---

## Purpose

This project simulates the operational ownership a platform/DevOps engineer holds over SSM-based infrastructure. It covers four core competencies drawn directly from enterprise job requirements:

| Competency | What This Project Demonstrates |
|---|---|
| Patch Manager Automation | Automated patching with custom baselines, maintenance windows, and compliance reporting |
| Custom SSM Documents | Reusable operational documents for app team use (health checks, log collection, compliance scans) |
| IAM Access Troubleshooting | Least-privilege IAM role design for SSM access with documented troubleshooting patterns |
| Run Command / Session Manager | Secure, auditable remote execution and shell access without SSH or bastion hosts |

---

## Architecture Overview

```
AWS Account
├── EC2 Instances (SSM Agent installed)
│   ├── SSM Instance Profile (IAM Role attached)
│   └── Managed by Systems Manager
│
├── Systems Manager
│   ├── Patch Manager
│   │   ├── Custom Patch Baseline (patch-baseline.json)
│   │   └── Maintenance Window (scheduled patching)
│   ├── Run Command
│   │   └── Executes custom SSM documents on target instances
│   ├── Session Manager
│   │   └── Encrypted, auditable shell sessions (no SSH required)
│   └── Documents (ssm-documents/)
│       ├── health-check.yaml
│       ├── log-collector.yaml
│       └── compliance-scan.yaml
│
└── IAM
    └── ssm-instance-profile.json (least-privilege role for SSM)
```

---

## Repository Structure

```
ssm-ops-demo/
├── README.md                        # This file
├── docs/
│   ├── runbook-patching.md          # Patch Manager operational runbook
│   ├── runbook-session-manager.md   # Session Manager + IAM troubleshooting runbook
│   └── runbook-run-command.md       # Run Command execution runbook
├── ssm-documents/
│   ├── health-check.yaml            # App health check document
│   ├── log-collector.yaml           # Log gathering for app teams
│   └── compliance-scan.yaml         # Lightweight compliance scan
├── iam/
│   └── ssm-instance-profile.json    # IAM role and policy for SSM access
└── patch-policies/
    ├── patch-baseline.json          # Custom patch baseline configuration
    └── approval-rules.json          # Patch approval rules (used during baseline registration)
```

---

## GRC Alignment

This project is framed with compliance and governance considerations embedded into operations — not bolted on afterward. Key design decisions reflect this:

**Least Privilege IAM**
The SSM instance profile grants only the permissions required for SSM core functions. No `*` actions, no over-broad resource scopes. Every permission is documented with its operational justification in `iam/ssm-instance-profile.json`.

**Audit Trail by Default**
Session Manager logs all sessions to CloudWatch Logs and S3. Run Command executions are tracked in SSM command history. This satisfies common audit and change control requirements without additional tooling.

**Patch Compliance Visibility**
Patch Manager is configured with a custom baseline that enforces severity thresholds and generates compliance reports. This gives security teams a direct line of sight into patch posture without manual reporting.

**Runbook-Driven Operations**
All operational procedures are documented as runbooks before being executed. This supports change control practices and creates reusable institutional knowledge for on-call rotations.

---

## Prerequisites

- AWS account with free tier access
- IAM user or role with permissions to create SSM resources, EC2 instances, and IAM roles
- AWS CLI configured locally (`aws configure`)
- Amazon Linux 2 EC2 instance with SSM Agent installed (pre-installed on Amazon Linux 2 AMIs)
- Session Manager plugin installed locally for shell session access

### Recommended AMI

Use the SSM Parameter Store path to always resolve the latest Amazon Linux 2 AMI:

```
ami = "resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
```

> **Note:** This project targets Amazon Linux 2 specifically. Amazon Linux 2023 (`al2023`) uses a different package manager and service structure — the SSM documents and patch baseline in this repo are not tested against AL2023.

### Verify SSM Agent

After launching your instance, confirm it is registered with Systems Manager:

**Linux / macOS:**
```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]" \
  --output table
```

**PowerShell:**
```powershell
aws ssm describe-instance-information `
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]" `
  --output table
```

If your instance does not appear, see `docs/runbook-session-manager.md` for IAM troubleshooting steps.

---

## Quick Start

> **PowerShell users:** This project was implemented and validated using AWS CLI on PowerShell. All commands below include both Linux/macOS and PowerShell syntax where they differ. Key differences: use backtick `` ` `` for line continuation instead of `\`, and use `file://` with forward slashes for file paths.

### 1. Apply the IAM Instance Profile

**Linux / macOS:**
```bash
aws iam create-role \
  --role-name SSMInstanceRole \
  --assume-role-policy-document file://iam/trust-policy.json

aws iam attach-role-policy \
  --role-name SSMInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name SSMInstanceProfile

aws iam add-role-to-instance-profile \
  --instance-profile-name SSMInstanceProfile \
  --role-name SSMInstanceRole
```

**PowerShell:**
```powershell
aws iam create-role `
  --role-name SSMInstanceRole `
  --assume-role-policy-document file://iam/trust-policy.json

aws iam attach-role-policy `
  --role-name SSMInstanceRole `
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name SSMInstanceProfile

aws iam add-role-to-instance-profile `
  --instance-profile-name SSMInstanceProfile `
  --role-name SSMInstanceRole
```

### 2. Register Custom SSM Documents

Register each document individually. The `file://` path approach is the most reliable across platforms.

**Linux / macOS:**
```bash
for doc in health-check log-collector compliance-scan; do
  aws ssm create-document \
    --name "$doc" \
    --document-type "Command" \
    --document-format YAML \
    --content "file://ssm-documents/$doc.yaml"
  echo "Registered: $doc"
done
```

**PowerShell:**
```powershell
foreach ($doc in @("health-check", "log-collector", "compliance-scan")) {
  aws ssm create-document `
    --name $doc `
    --document-type "Command" `
    --document-format YAML `
    --content "file://ssm-documents/$doc.yaml"
  Write-Host "Registered: $doc"
}
```

Verify all three are registered:
```powershell
aws ssm list-documents `
  --filters "Key=Owner,Values=Self" `
  --query "DocumentIdentifiers[*].[Name,Status]" `
  --output table
```

### 3. Apply Patch Baseline

The approval rules are stored separately in `patch-policies/approval-rules.json` for cross-platform compatibility:

```powershell
aws ssm create-patch-baseline `
  --name "custom-linux-baseline" `
  --operating-system "AMAZON_LINUX_2" `
  --description "Custom patch baseline for Amazon Linux 2" `
  --approval-rules "file://patch-policies/approval-rules.json"
```

Save the returned `BaselineId`, then set it as default and register your patch group:

```powershell
aws ssm register-default-patch-baseline `
  --baseline-id <your-baseline-id>

aws ssm register-patch-baseline-for-patch-group `
  --baseline-id <your-baseline-id> `
  --patch-group "AmazonLinux2-Standard"
```

Tag your instance with the patch group:

```powershell
aws ec2 create-tags `
  --resources <your-instance-id> `
  --tags "Key=Patch Group,Value=AmazonLinux2-Standard"
```

### 4. Run a Health Check

```powershell
aws ssm send-command `
  --document-name "health-check" `
  --targets "Key=instanceids,Values=<your-instance-id>" `
  --comment "Health check" `
  --query "Command.CommandId" `
  --output text
```

### 5. Retrieve Command Output

SSM documents with multiple steps require the `--plugin-name` flag to retrieve per-step output. Querying without it returns an empty response.

```powershell
foreach ($step in @("CheckUptime","CheckCPULoad","CheckMemory","CheckDiskUsage","CheckServices","CheckNetworkConnectivity","SummaryReport")) {
  Write-Host "=== $step ===" -ForegroundColor Cyan
  aws ssm get-command-invocation `
    --command-id "<your-command-id>" `
    --instance-id "<your-instance-id>" `
    --plugin-name $step `
    --query "[Status,StandardOutputContent]" `
    --output text
}
```

Use the same pattern for `compliance-scan` with these step names:
`ScanHeader`, `CheckOpenPorts`, `CheckSSHConfiguration`, `CheckFilePermissions`, `CheckSudoersEntries`, `CheckOSPatching`, `ScanFooter`

---

## Runbooks

| Runbook | Description |
|---|---|
| [runbook-patching.md](docs/runbook-patching.md) | End-to-end patching lifecycle: baseline configuration, maintenance windows, compliance review, and escalation steps |
| [runbook-session-manager.md](docs/runbook-session-manager.md) | Starting sessions, port forwarding, IAM troubleshooting when instances don't appear in Fleet Manager |
| [runbook-run-command.md](docs/runbook-run-command.md) | Executing commands at scale, targeting by tag, reviewing output, and handling failures |

---

## Custom SSM Documents

| Document | Purpose | Intended User |
|---|---|---|
| `health-check.yaml` | Checks service status, disk usage, memory, CPU, and network connectivity | App teams, on-call engineers |
| `log-collector.yaml` | Collects and compresses application logs from defined paths and uploads to S3 | App teams during incident response |
| `compliance-scan.yaml` | Validates OS-level settings against a defined baseline (open ports, SSH config, file permissions, sudoers) | Security team, platform engineers |

---

## Expected Compliance Scan Findings on Amazon Linux 2

When running `compliance-scan` against a default Amazon Linux 2 instance, the following findings are expected and reflect AWS platform defaults rather than misconfigurations:

| Finding | Explanation |
|---|---|
| `NOPASSWD entry found in /etc/sudoers.d/90-cloud-init-users` | AWS sets `ec2-user ALL=(ALL) NOPASSWD:ALL` by default to enable instance management. Expected on all AWS-managed instances. |
| `NOPASSWD entry found in /etc/sudoers` | The default sudoers file includes a commented-out `%wheel NOPASSWD` example. This is not active but triggers the scan. |
| `/etc/shadow permissions are 0 — expected 000` | The `stat -c %a` command omits leading zeros on some Linux versions. A result of `0` is equivalent to `000`. Not a real finding. |
| `Port 25 open` | Postfix is installed by default on Amazon Linux 2 for local mail delivery. Expected unless your baseline excludes it. |
| `Port 111 open` | RPC portmapper runs by default. Disable with `systemctl disable rpcbind` if not needed. |
| `PermitRootLogin not explicitly set` | Amazon Linux 2 does not set this in sshd_config by default. Add `PermitRootLogin no` to harden. |
| `X11Forwarding set to yes` | AWS enables X11 forwarding by default. Add `X11Forwarding no` to harden. |

These findings are documented here to demonstrate the difference between true positives and expected platform behavior — a critical distinction in real compliance work.

---

## IAM Troubleshooting Reference

The most common reason instances don't appear in SSM Fleet Manager is a missing or misconfigured instance profile. Quick reference:

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Instance not in Fleet Manager | No IAM instance profile attached | Attach `SSMInstanceProfile` to EC2 instance |
| Instance shows offline | SSM Agent not running | See `runbook-session-manager.md` |
| Session Manager connection refused | Missing `ssmmessages` permissions in IAM role | Review IAM policy in `iam/ssm-instance-profile.json` |
| Patch scan shows no data | Instance not tagged correctly | Verify `Patch Group` tag matches baseline |
| Command returns `Failed None None` | Document execution failing before shell runs | Query individual steps using `--plugin-name` |
| `InvalidDocumentContent` on register | YAML parsing issue with special characters | Wrap affected lines in a block scalar using `\|` |

Full troubleshooting procedures are in `docs/runbook-session-manager.md`.

---

## Skills Demonstrated

- AWS Systems Manager (Patch Manager, Run Command, Session Manager, Documents)
- IAM role design with least-privilege principles
- Operational documentation (runbooks, architecture overview)
- Compliance-aware infrastructure patterns
- AWS CLI scripting across Linux and PowerShell environments
- Cross-team tooling (app team-facing SSM documents)
- Distinguishing expected platform behavior from true compliance findings

---

## Author

Kevin | [LinkedIn](#) | [Portfolio](#)

*Built as part of a DevOps/GRC portfolio demonstrating enterprise platform engineering capabilities.*

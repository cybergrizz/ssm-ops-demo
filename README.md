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
    └── patch-baseline.json          # Custom patch baseline configuration
```

---

## GRC Alignment

This project is framed with compliance and governance considerations embedded into operations — not bolted on afterward. Key design decisions reflect this:

**Least Privilege IAM**
The SSM instance profile grants only the permissions required for SSM core functions. No `*` actions, no over-broad resource scopes. Every permission is documented with its operational justification in `iam/ssm-instance-profile.json`.

**Audit Trail by Default**
Session Manager is configured to log all sessions to CloudWatch Logs and S3. Run Command executions are tracked in SSM command history. This satisfies common audit and change control requirements without additional tooling.

**Patch Compliance Visibility**
Patch Manager is configured with a custom baseline that enforces severity thresholds and generates compliance reports. This gives security teams a direct line of sight into patch posture without manual reporting.

**Runbook-Driven Operations**
All operational procedures are documented as runbooks before being executed. This supports change control practices and creates reusable institutional knowledge for on-call rotations.

---

## Prerequisites

- AWS Account with free tier access
- IAM user or role with permissions to create SSM resources, EC2 instances, and IAM roles
- AWS CLI configured locally (`aws configure`)
- At least one EC2 instance with SSM Agent installed (Amazon Linux 2 or Windows Server 2019 recommended)

### Verify SSM Agent

```bash
# Check if instance is visible in SSM Fleet Manager
aws ssm describe-instance-information --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]" --output table
```

If your instance does not appear, see `docs/runbook-session-manager.md` for IAM troubleshooting steps.

---

## Quick Start

### 1. Apply the IAM Instance Profile

```bash
# Create the IAM role
aws iam create-role \
  --role-name SSMInstanceRole \
  --assume-role-policy-document file://iam/ssm-instance-profile.json

# Attach AWS managed SSM policy
aws iam attach-role-policy \
  --role-name SSMInstanceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Create instance profile and attach role
aws iam create-instance-profile --instance-profile-name SSMInstanceProfile
aws iam add-role-to-instance-profile \
  --instance-profile-name SSMInstanceProfile \
  --role-name SSMInstanceRole
```

### 2. Register Custom SSM Documents

```bash
# Register all custom documents
for doc in ssm-documents/*.yaml; do
  name=$(basename "$doc" .yaml)
  aws ssm create-document \
    --name "$name" \
    --document-type "Command" \
    --document-format YAML \
    --content "file://$doc"
  echo "Registered: $name"
done
```

### 3. Apply Patch Baseline

```bash
aws ssm create-patch-baseline \
  --name "custom-linux-baseline" \
  --cli-input-json file://patch-policies/patch-baseline.json
```

### 4. Run a Health Check

```bash
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=tag:Environment,Values=dev" \
  --comment "Portfolio demo health check"
```

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
| `health-check.yaml` | Checks service status, disk usage, and memory on target instances | App teams, on-call engineers |
| `log-collector.yaml` | Collects and compresses application logs from defined paths | App teams during incident response |
| `compliance-scan.yaml` | Validates OS-level settings against a defined baseline (open ports, running services, file permissions) | Security team, platform engineers |

---

## IAM Troubleshooting Reference

The most common reason instances don't appear in SSM Fleet Manager is a missing or misconfigured instance profile. Quick reference:

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Instance not in Fleet Manager | No IAM instance profile attached | Attach `SSMInstanceProfile` to EC2 instance |
| Instance shows offline | SSM Agent not running | See runbook-session-manager.md |
| Session Manager connection refused | Missing `ssmmessages` permissions in IAM role | Review IAM policy in `iam/ssm-instance-profile.json` |
| Patch scan shows no data | Instance not tagged correctly | Verify patch group tag matches baseline |

Full troubleshooting procedures are in `docs/runbook-session-manager.md`.

---

## Skills Demonstrated

- AWS Systems Manager (Patch Manager, Run Command, Session Manager, Documents)
- IAM role design with least-privilege principles
- Operational documentation (runbooks, architecture overview)
- Compliance-aware infrastructure patterns
- AWS CLI scripting for resource management
- Cross-team tooling (app team-facing SSM documents)

---

## Author

Kevin | [LinkedIn](#) | [Portfolio](#)

*Built as part of a DevOps/GRC portfolio demonstrating enterprise platform engineering capabilities.*

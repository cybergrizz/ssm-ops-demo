# Runbook: Patch Manager Operations

**Document Type:** Operational Runbook  
**Maintained By:** Platform Engineering  
**Last Updated:** 2025  
**Applies To:** Amazon Linux 2 instances managed via AWS Systems Manager  

---

## Purpose

This runbook covers the end-to-end lifecycle for managing patches across SSM-managed instances using AWS Patch Manager. It is intended for platform engineers, on-call responders, and anyone participating in the patching rotation.

Following this runbook ensures patching operations are consistent, auditable, and aligned with security team requirements.

---

## Prerequisites

Before executing any patching operation, confirm the following:

- Target instances are visible in SSM Fleet Manager (ping status: Online)
- The instance IAM role includes `AmazonSSMManagedInstanceCore`
- A custom patch baseline has been applied (`patch-baseline.json`)
- A maintenance window exists and is associated with the target patch group
- You have AWS CLI access or Console access with sufficient IAM permissions

---

## Patch Lifecycle Overview

```
1. Baseline Configuration
        ↓
2. Instance Tagging (Patch Group assignment)
        ↓
3. Scan (assess patch posture — no changes)
        ↓
4. Review Compliance Report
        ↓
5. Schedule via Maintenance Window
        ↓
6. Install (automated or manual trigger)
        ↓
7. Post-Patch Validation
        ↓
8. Escalation (if failures occur)
```

---

## Step 1: Verify Patch Baseline

The custom patch baseline controls which patches are approved for installation. Confirm the baseline is registered and set as default for the Linux operating system.

```bash
# List all patch baselines
aws ssm describe-patch-baselines \
  --query "BaselineIdentities[*].[BaselineId,BaselineName,OperatingSystem,DefaultBaseline]" \
  --output table

# Describe the custom baseline in detail
aws ssm get-patch-baseline \
  --baseline-id <your-baseline-id>
```

**Expected output:** Your custom baseline (`custom-linux-baseline`) should appear with `DefaultBaseline: true` for Amazon Linux 2.

If the baseline is not set as default:

```bash
aws ssm register-default-patch-baseline \
  --baseline-id <your-baseline-id>
```

---

## Step 2: Assign Instances to a Patch Group

Patch groups are controlled via EC2 instance tags. Instances must be tagged before they can be targeted by a maintenance window.

```bash
# Tag an instance with a patch group
aws ec2 create-tags \
  --resources <instance-id> \
  --tags Key=Patch Group,Value=AmazonLinux2-Standard
```

> **Note:** The tag key must be exactly `Patch Group` (with a space) — this is an AWS requirement for Patch Manager integration.

Verify the tag was applied:

```bash
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=<instance-id>" "Name=key,Values=Patch Group" \
  --output table
```

---

## Step 3: Run a Patch Scan (No Changes)

Before scheduling installs, run a scan to assess current patch posture. This does not install anything.

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters Operation=Scan \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard" \
  --comment "Patch posture scan - pre-window assessment" \
  --output text \
  --query "Command.CommandId"
```

Save the returned `CommandId` for the next step.

---

## Step 4: Review Patch Compliance Report

After the scan completes (typically 2–5 minutes), review compliance results.

```bash
# Summary compliance by instance
aws ssm list-compliance-summaries \
  --filters "Key=ComplianceType,Values=Patch" \
  --output table

# Detailed patch state for a specific instance
aws ssm describe-instance-patch-states \
  --instance-ids <instance-id> \
  --output table

# List non-compliant patches on a specific instance
aws ssm describe-instance-patches \
  --instance-id <instance-id> \
  --filters "Key=State,Values=Missing,Failed" \
  --output table
```

**Compliance States:**

| State | Meaning |
|---|---|
| Compliant | All required patches installed |
| NonCompliant | Missing or failed patches exist |
| InsufficientData | Scan has not run or agent is unreachable |

Escalate to the security team if Critical or High severity patches are in a `Missing` state beyond the SLA window.

---

## Step 5: Schedule via Maintenance Window

Patching should be executed within a registered maintenance window to control blast radius and ensure change control traceability.

```bash
# List existing maintenance windows
aws ssm describe-maintenance-windows \
  --output table

# View targets for a specific window
aws ssm describe-maintenance-window-targets \
  --window-id <window-id> \
  --output table
```

If a maintenance window does not exist for the target patch group, create one:

```bash
# Create a maintenance window (Sunday 02:00 UTC, 2 hour duration)
aws ssm create-maintenance-window \
  --name "AmazonLinux2-PatchWindow" \
  --schedule "cron(0 2 ? * SUN *)" \
  --duration 2 \
  --cutoff 1 \
  --allow-unassociated-targets false

# Register patch group as target
aws ssm register-target-with-maintenance-window \
  --window-id <window-id> \
  --resource-type INSTANCE \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard"

# Register the patching task
aws ssm register-task-with-maintenance-window \
  --window-id <window-id> \
  --targets "Key=WindowTargetIds,Values=<target-id>" \
  --task-arn "arn:aws:ssm:us-east-1::document/AWS-RunPatchBaseline" \
  --task-type RUN_COMMAND \
  --task-invocation-parameters '{"RunCommand":{"Parameters":{"Operation":["Install"]}}}' \
  --max-concurrency 2 \
  --max-errors 1
```

> **Why max-errors 1?** Stopping after one failure prevents a bad patch from cascading across all instances in the window.

---

## Step 6: Manual Patch Install (Out-of-Band)

For critical/emergency patches outside the maintenance window, patches can be installed manually. This should be documented as an exception in your change management system.

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters Operation=Install \
  --targets "Key=instanceids,Values=<instance-id>" \
  --comment "Emergency patch - CVE-XXXX-XXXX - approved by <name>" \
  --output text \
  --query "Command.CommandId"
```

Monitor command execution:

```bash
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id> \
  --query "[Status,StatusDetails,StandardOutputContent]" \
  --output text
```

---

## Step 7: Post-Patch Validation

After patching, run the health check document to confirm instance stability.

```bash
aws ssm send-command \
  --document-name "health-check" \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard" \
  --comment "Post-patch health validation"
```

Then re-run compliance scan to confirm patch state is now Compliant:

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters Operation=Scan \
  --targets "Key=tag:Patch Group,Values=AmazonLinux2-Standard" \
  --comment "Post-patch compliance verification"
```

---

## Step 8: Escalation Procedure

| Condition | Action |
|---|---|
| Instance fails to patch after 2 attempts | Open incident ticket, notify security team, isolate instance if Critical CVE |
| Patch causes service disruption | Execute rollback procedure, notify app team, document in post-incident review |
| Critical/High CVE with no available patch | Notify security team immediately, apply compensating controls per security guidance |
| Compliance scan shows NonCompliant after install | Check command output for errors, verify baseline approval rules, re-scan |

---

## Common Errors and Resolutions

| Error | Likely Cause | Resolution |
|---|---|---|
| `InvalidInstanceId` | Instance not registered with SSM | Verify IAM role, SSM Agent status |
| `AccessDeniedException` | IAM role missing patch permissions | Review instance profile policy |
| `Timeout` on patch command | Instance under heavy load or unreachable | Check system health, retry during low-traffic period |
| Patch marked `Failed` in compliance | Package conflict or disk space issue | Review command output, check disk with health-check document |
| Maintenance window missed | Window duration too short or cutoff too aggressive | Review window settings, extend duration |

---

## Related Documents

- `runbook-session-manager.md` — Access instances for manual investigation
- `runbook-run-command.md` — Execute ad-hoc commands during patch troubleshooting
- `ssm-documents/health-check.yaml` — Post-patch instance validation
- `ssm-documents/compliance-scan.yaml` — Post-patch security posture review
- `patch-policies/patch-baseline.json` — Patch baseline configuration reference

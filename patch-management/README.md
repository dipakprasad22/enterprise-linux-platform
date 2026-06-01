# Patch Management

Generates an HTML patch compliance report for a Linux server, suitable for use in monitoring pipelines or scheduled audits.

## Files

| File | Description |
|------|-------------|
| `patch-compliance-report.sh` | Main script — detects package manager, collects patch state, and writes an HTML report |

## Features

- Cross-platform support: `dnf`, `yum`, `apt`
- Detects and counts pending **security** patches only (not all upgrades)
- Identifies whether a **reboot is required** (`needs-restarting` / `/var/run/reboot-required`)
- Outputs a self-contained **dark-themed HTML report** with:
  - Compliance status banner (COMPLIANT / NON-COMPLIANT / REBOOT PENDING)
  - Summary cards: pending patches, reboot status, package manager, last update
  - Enterprise SLA policy table (CVSS score → remediation deadline)
  - List of pending security packages
  - Copy-paste remediation commands
- **Monitoring-friendly exit codes** — integrate directly with Nagios, Zabbix, or CI checks

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Bash 4+ | Standard on RHEL 7+, Ubuntu 18.04+ |
| `dnf` or `yum` or `apt-get` | One must be present |
| `needs-restarting` *(optional)* | RPM-based systems; provided by `yum-utils` / `dnf-utils` |
| Write access to `/var/lib/elap/reports/patch` | Falls back to `/tmp` automatically |

## Usage

```bash
# Run with defaults
sudo bash patch-compliance-report.sh

# Override output and log directories
REPORT_DIR=/opt/reports LOG=/var/log/myapp/patch.log \
  sudo bash patch-compliance-report.sh
```

The report path is printed to stdout on completion:

```
Patch compliance report: /var/lib/elap/reports/patch/patch-compliance-20260601-143022.html
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `REPORT_DIR` | `/var/lib/elap/reports/patch` | Directory where HTML reports are written |
| `LOG` | `/var/log/elap/patch-compliance.log` | Log file path |

Both fall back to `/tmp` if the default path is not writable.

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Compliant — no pending security patches, no reboot required |
| `1` | Non-compliant or reboot pending |
| `2` | No supported package manager found |

## SLA Policy

The report embeds the enterprise remediation SLA used to evaluate compliance:

| Severity | CVSS Range | Remediation Target | Exception Authority |
|----------|------------|--------------------|---------------------|
| Critical | 9.0 – 10.0 | 24–48 hours | CISO approval |
| High | 7.0 – 8.9 | 7 days | Manager approval |
| Medium | 4.0 – 6.9 | 30 days | Team lead approval |
| Low | 0 – 3.9 | 90 days | Self-service |

## Integration Examples

**Cron job (daily at 03:00):**
```cron
0 3 * * * root /opt/elap/patch-management/patch-compliance-report.sh
```

**Nagios / NRPE check:**
```bash
# Returns 0 (OK) or 1 (CRITICAL) — maps directly to Nagios exit codes
command[check_patch_compliance]=/opt/elap/patch-management/patch-compliance-report.sh
```

**CI/CD gate:**
```yaml
- name: Patch compliance check
  run: sudo bash patch-management/patch-compliance-report.sh
```

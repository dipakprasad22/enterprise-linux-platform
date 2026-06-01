# Centralized Log Analysis and Health Tool

A Bash diagnostic script for Linux systems that audits logging infrastructure health, analyzes log volume, extracts security events, and validates centralized logging configuration. Designed for use within the **Enterprise Linux Administration Platform (ELAP)**.

---

## Features

| Module | Description |
|---|---|
| **Logging Health Check** | Validates journald persistence, rsyslog status, config integrity, and logrotate activity |
| **Log Volume Analysis** | Reports total `/var/log` disk usage, top consumers, filesystem saturation risk, and unrotated large files |
| **Security Event Summary** | Extracts failed SSH logins, brute-force indicators, sudo activity, error-level messages, and service failures from the last 24 hours |
| **Centralized Logging Validation** | Detects whether the host forwards logs to a remote collector or acts as a collector itself |

---

## Requirements

- Linux with `systemd` / `journald`
- `rsyslog` (optional — checked, not required)
- `logrotate` (optional — checked, not required)
- Root or `sudo` privileges (required for `journalctl` and `/var/log` access)
- Bash 4.2+

---

## Usage

```bash
sudo bash log-analyzer.sh
```

By default, reports are written to `/var/lib/elap/reports/logging/`. If that path is not writable, the report falls back to `/tmp/`.

### Override report directory

```bash
REPORT_DIR=/opt/audit/logs sudo bash log-analyzer.sh
```

---

## Output

The script produces color-coded terminal output and saves a plain-text report simultaneously via `tee`.

### Status indicators

| Tag | Meaning |
|---|---|
| `[OK]` | Check passed — no action required |
| `[WARN]` | Degraded state — review recommended |
| `[CRIT]` | Critical issue — immediate action required |

### Report file

```
/var/lib/elap/reports/logging/log-analysis-<YYYYMMDD-HHMMSS>.txt
```

---

## Checks in Detail

### Logging Health
- Confirms journald writes to persistent storage (`/var/log/journal`) and survives reboots
- Reports journald disk usage
- Verifies rsyslog is active and its configuration passes validation (`rsyslogd -N1`)
- Checks that logrotate ran within the last 2 days

### Log Volume Analysis
- Displays total size of `/var/log`
- Lists the 10 largest files/directories under `/var/log`
- Flags when the filesystem hosting `/var/log` exceeds 80% or 90% capacity
- Identifies files larger than 50 MB and checks whether each has a logrotate configuration

### Security Events (last 24 hours)
- Counts failed SSH password attempts; flags counts above 50 as a potential brute-force attack
- Lists the top 5 source IPs contributing to failed logins
- Reports total `sudo` command executions
- Counts `error`-priority journal entries and warns when they exceed 100
- Detects `Failed to start` and `entered failed state` service events

### Centralized Logging
- Parses `rsyslog.conf` and `rsyslog.d/` for forwarding rules (`@@`, `omrelp`, `omfwd`)
- Warns when no forwarding is configured and logs are local-only
- Detects whether the host is listening on standard syslog ports (514, 2514, 6514), indicating it serves as a log collector

---

## Security Considerations

- Run as root or with `sudo` — the script reads protected journal and system log files
- Report files are written with default `umask`; restrict the report directory if the output contains sensitive security data
- The script is read-only; it does not modify any logs, services, or configuration files

---

## Related Modules

This script is part of the [Enterprise Linux Administration Platform](../README.md). See the project root for the full list of available diagnostic modules.

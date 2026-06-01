# Storage Services & Certificate Health Monitor

A Bash health-check script for Linux storage infrastructure and SSL/TLS certificate expiry. Designed as part of the [Enterprise Linux Administration Platform (ELAP)](../ELAP).

---

## What It Monitors

| Component | Checks |
|---|---|
| **RAID Arrays** | Degraded/failed arrays, rebuild/resync in progress |
| **NFS** | Server export count, client mount responsiveness (stale handle detection) |
| **Samba** | Service status, config validation, active connections, AD trust |
| **SSL/TLS (files)** | Certificate expiry from files in standard cert directories |
| **SSL/TLS (live)** | Certificate expiry by connecting to live host:port endpoints |

---

## Usage

```bash
# Basic run
sudo bash storage-cert-monitor.sh

# Override report output directory
REPORT_DIR=/tmp/my-reports sudo bash storage-cert-monitor.sh

# Check live endpoints (space-separated host:port pairs)
LIVE_ENDPOINTS="example.com:443 internal.corp:8443" sudo bash storage-cert-monitor.sh

# Tune certificate warning thresholds (days)
CERT_WARN_DAYS=60 CERT_CRIT_DAYS=14 sudo bash storage-cert-monitor.sh
```

---

## Configuration

All configuration is via environment variables — no file edits required.

| Variable | Default | Description |
|---|---|---|
| `REPORT_DIR` | `/var/lib/elap/reports/storage-cert` | Directory where timestamped reports are saved |
| `CERT_WARN_DAYS` | `30` | Days-until-expiry threshold for a WARN alert |
| `CERT_CRIT_DAYS` | `7` | Days-until-expiry threshold for a CRIT alert |
| `LIVE_ENDPOINTS` | *(none)* | Space-separated `host:port` pairs to probe for live cert expiry |

**Certificate file scan directories** (hardcoded, edit the script to change):
```
/etc/pki/tls/certs
/etc/ssl/certs
/etc/nginx/ssl
/etc/letsencrypt/live
```

---

## Output

The script prints color-coded status to stdout and writes an identical plain-text report to `REPORT_DIR`.

```
[OK]    /dev/md0 is healthy (clean)
[WARN]  Expires in 22 days: *.example.com (/etc/nginx/ssl/server.crt)
[CRIT]  /dev/md1 is DEGRADED: active, degraded
[CRIT]  NFS mount UNRESPONSIVE (possible stale handle): /mnt/data
```

Exit code `0` = all healthy. Exit code `1` = one or more issues found.

---

## Requirements

| Tool | Required for |
|---|---|
| `mdadm` | RAID array inspection |
| `exportfs` | NFS export enumeration |
| `systemctl` | Service status checks |
| `testparm`, `smbstatus`, `wbinfo` | Samba/AD checks |
| `openssl` | Certificate parsing and live endpoint probing |

Missing tools are handled gracefully — checks that cannot run are skipped with an informational message rather than failing.

---

## Scheduling with Cron

```bash
# Run daily at 06:00, append to syslog
0 6 * * * root REPORT_DIR=/var/lib/elap/reports/storage-cert /opt/elap/storage-services/storage-cert-monitor.sh | logger -t elap-storage
```

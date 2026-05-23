#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Boot and System Health Analysis Tool
# Version: 1.0.0
# Author: Dipak
# Usage: ./boot-health-report.sh [--json] [--quiet]
# Output: Detailed report to stdout and /var/log/boot-health/
# Exit code: 0 = all healthy, 1 = warnings found, 2 = critical issues
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuration ────────────────────────────────────────────
REPORT_DIR="/var/log/boot-health"
REPORT_FILE="$REPORT_DIR/report-$(date +%Y%m%d-%H%M%S).txt"
BOOT_TIME_WARNING=60      # seconds
BOOT_TIME_CRITICAL=120    # seconds
FAILED_SERVICES_CRITICAL=1

# ── Color codes ──────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Track overall status ─────────────────────────────────────
OVERALL_STATUS=0   # 0=ok, 1=warning, 2=critical

warn()     { echo -e "${YELLOW}[WARN]${NC}     $*"; OVERALL_STATUS=$((OVERALL_STATUS > 1 ? OVERALL_STATUS : 1)); }
critical() { echo -e "${RED}[CRITICAL]${NC} $*"; OVERALL_STATUS=2; }
ok()       { echo -e "${GREEN}[OK]${NC}       $*"; }
info()     { echo -e "${BLUE}[INFO]${NC}     $*"; }
header()   { echo -e "\n${BOLD}══════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}══════════════════════════════════════${NC}"; }

# ── Setup ────────────────────────────────────────────────────
mkdir -p "$REPORT_DIR"
exec > >(tee "$REPORT_FILE") 2>&1

echo "═══════════════════════════════════════════════════════"
echo "  ENTERPRISE BOOT AND SYSTEM HEALTH REPORT"
echo "  Generated:  $(date)"
echo "  Hostname:   $(hostname -f)"
echo "  OS:         $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo "  Kernel:     $(uname -r)"
echo "  Uptime:     $(uptime -p)"
echo "═══════════════════════════════════════════════════════"

# ── Section 1: Boot timing ────────────────────────────────────
header "BOOT TIMING ANALYSIS"

BOOT_LINE=$(systemd-analyze 2>/dev/null | head -1)
echo "$BOOT_LINE"

# Extract total boot time in seconds
TOTAL_BOOT=$(systemd-analyze 2>/dev/null | grep "Startup finished" | \
    grep -oP '\d+\.\d+s$' | tr -d 's' | awk '{print int($1+0.5)}' || echo "0")

if [ "$TOTAL_BOOT" -ge "$BOOT_TIME_CRITICAL" ]; then
    critical "Boot time ${TOTAL_BOOT}s exceeds critical threshold (${BOOT_TIME_CRITICAL}s)"
elif [ "$TOTAL_BOOT" -ge "$BOOT_TIME_WARNING" ]; then
    warn "Boot time ${TOTAL_BOOT}s exceeds warning threshold (${BOOT_TIME_WARNING}s)"
elif [ "$TOTAL_BOOT" -gt 0 ]; then
    ok "Boot time ${TOTAL_BOOT}s is within acceptable limits"
fi

echo ""
echo "Top 10 slowest services:"
systemd-analyze blame 2>/dev/null | head -10 | while read line; do
    TIME=$(echo "$line" | awk '{print $1}' | tr -d 'ms')
    echo "  $line"
done

# ── Section 2: Failed services ────────────────────────────────
header "SERVICE STATUS"

FAILED_COUNT=$(systemctl --failed --no-legend 2>/dev/null | wc -l)

if [ "$FAILED_COUNT" -ge "$FAILED_SERVICES_CRITICAL" ]; then
    critical "$FAILED_COUNT failed service(s) detected:"
    systemctl --failed --no-legend | while read line; do
        echo "    → $line"
    done
else
    ok "No failed services"
fi

# Check critical services are running
CRITICAL_SERVICES=("sshd" "rsyslog" "chronyd")
# Add more based on your environment

echo ""
echo "Critical service status:"
for svc in "${CRITICAL_SERVICES[@]}"; do
    if systemctl list-units --type=service | grep -q "${svc}.service"; then
        if systemctl is-active --quiet "$svc"; then
            ok "$svc is running"
        else
            critical "$svc is NOT running"
        fi
    else
        info "$svc not installed (skipping)"
    fi
done

# ── Section 3: Boot errors ────────────────────────────────────
header "BOOT LOG ERRORS"

ERROR_COUNT=$(journalctl -b -p err --no-pager 2>/dev/null | grep -v "^--" | wc -l)

if [ "$ERROR_COUNT" -gt 0 ]; then
    warn "$ERROR_COUNT error(s) found in boot log:"
    journalctl -b -p err --no-pager 2>/dev/null | grep -v "^--" | \
        tail -10 | while read line; do
        echo "    $line"
    done
else
    ok "No errors in boot log"
fi

# ── Section 4: Kernel messages ───────────────────────────────
header "KERNEL HEALTH"

KERN_ERRORS=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | wc -l)
if [ "$KERN_ERRORS" -gt 0 ]; then
    warn "$KERN_ERRORS kernel error/warning message(s):"
    dmesg --level=err,crit,alert,emerg 2>/dev/null | head -10 | \
        while read line; do echo "    $line"; done
else
    ok "No kernel errors detected"
fi

KERNEL_VERSION=$(uname -r)
ok "Running kernel: $KERNEL_VERSION"

# ── Section 5: System resources ──────────────────────────────
header "RESOURCE BASELINE"

# Memory
MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
MEM_USED=$(free -m | grep Mem | awk '{print $3}')
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
if   [ "$MEM_PCT" -ge 90 ]; then critical "Memory usage: ${MEM_PCT}% (${MEM_USED}M / ${MEM_TOTAL}M)"
elif [ "$MEM_PCT" -ge 75 ]; then warn "Memory usage: ${MEM_PCT}% (${MEM_USED}M / ${MEM_TOTAL}M)"
else ok "Memory usage: ${MEM_PCT}% (${MEM_USED}M / ${MEM_TOTAL}M)"
fi

# Load average
LOAD_1=$(cat /proc/loadavg | awk '{print $1}')
CORES=$(nproc)
ok "Load average (1min): $LOAD_1 on $CORES cores"

# Disk space
echo ""
echo "Filesystem usage:"
df -h --output=target,pcent,size,used,avail | grep -v "tmpfs\|devtmpfs" | \
    tail -n +2 | while read target pct size used avail; do
    PCT_NUM=${pct//%/}
    if   [ "$PCT_NUM" -ge 90 ]; then critical "$target is ${pct} full (${used}/${size})"
    elif [ "$PCT_NUM" -ge 80 ]; then warn "$target is ${pct} full (${used}/${size})"
    else ok "$target is ${pct} full (${used}/${size})"
    fi
done

# ── Section 6: Security checks ───────────────────────────────
header "SECURITY SNAPSHOT"

# Recent auth failures
AUTH_FAIL=$(journalctl -b --no-pager 2>/dev/null | \
    grep -c "Failed password\|authentication failure" || echo 0)
if [ "$AUTH_FAIL" -gt 10 ]; then
    warn "$AUTH_FAIL authentication failures this boot"
else
    ok "$AUTH_FAIL authentication failures this boot"
fi

# Root login attempts via SSH
ROOT_LOGIN=$(journalctl -b --no-pager 2>/dev/null | \
    grep -c "Failed password for root" || echo 0)
[ "$ROOT_LOGIN" -gt 0 ] && \
    warn "$ROOT_LOGIN failed root SSH login attempts" || \
    ok "No failed root SSH login attempts"

# ── Final summary ─────────────────────────────────────────────
header "SUMMARY"

case $OVERALL_STATUS in
    0) echo -e "${GREEN}${BOLD}STATUS: ALL SYSTEMS HEALTHY${NC}" ;;
    1) echo -e "${YELLOW}${BOLD}STATUS: WARNINGS DETECTED — Review items above${NC}" ;;
    2) echo -e "${RED}${BOLD}STATUS: CRITICAL ISSUES FOUND — Immediate action required${NC}" ;;
esac

echo ""
echo "Full report saved to: $REPORT_FILE"
echo "═══════════════════════════════════════════════════════"

exit $OVERALL_STATUS
#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Centralized Log Analysis and Health Tool
#
# Features:
#   - Log volume analysis (which logs grow fastest)
#   - Logging health check (journald persistence, rotation status)
#   - Security event extraction (failed logins, sudo, errors)
#   - Disk space risk assessment for /var/log
#   - Centralized logging configuration validation
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly REPORT_DIR="${REPORT_DIR:-/var/lib/elap/reports/logging}"
readonly REPORT="${REPORT_DIR}/log-analysis-${TIMESTAMP}.txt"

mkdir -p "$REPORT_DIR" 2>/dev/null || REPORT="/tmp/log-analysis-${TIMESTAMP}.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

section() { echo ""; printf "${CYAN}══ %s ══${NC}\n" "$*"; }
pass() { printf "${GREEN}[OK]${NC}   %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
crit() { printf "${RED}[CRIT]${NC} %s\n" "$*"; }
info() { printf "       %s\n" "$*"; }

# ── Logging health check ──────────────────────────────────────
check_logging_health() {
    section "Logging Health Check"

    # journald persistence:
    if [[ -d /var/log/journal ]] && \
       journalctl --list-boots 2>/dev/null | wc -l | \
       awk '{exit !($1>1)}'; then
        pass "journald is persistent (survives reboots)"
    else
        warn "journald may be volatile — logs lost on reboot"
        info "Fix: mkdir /var/log/journal && systemctl restart systemd-journald"
    fi

    # journald disk usage:
    local jusage
    jusage=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[A-Z]' | head -1)
    info "journald disk usage: ${jusage:-unknown}"

    # rsyslog running:
    if systemctl is-active --quiet rsyslog 2>/dev/null; then
        pass "rsyslog is running"
        # Validate config:
        if rsyslogd -N1 2>&1 | grep -qi "error"; then
            crit "rsyslog config has errors!"
            rsyslogd -N1 2>&1 | grep -i error | head -3 | sed 's/^/       /'
        else
            pass "rsyslog config is valid"
        fi
    else
        warn "rsyslog is not running"
    fi

    # logrotate present and recent:
    local lr_status="/var/lib/logrotate/logrotate.status"
    [[ -f "$lr_status" ]] || lr_status="/var/lib/logrotate.status"
    if [[ -f "$lr_status" ]]; then
        local last_run
        last_run=$(stat -c '%y' "$lr_status" 2>/dev/null | cut -d' ' -f1)
        local days_ago=$(( ($(date +%s) - $(stat -c '%Y' "$lr_status")) / 86400 ))
        if [[ $days_ago -le 2 ]]; then
            pass "logrotate ran recently (last: $last_run)"
        else
            warn "logrotate last ran $days_ago days ago ($last_run)"
        fi
    else
        warn "No logrotate status file found"
    fi
}

# ── Log volume analysis ───────────────────────────────────────
analyze_log_volume() {
    section "Log Volume Analysis (/var/log)"

    # Total /var/log size:
    local total
    total=$(du -sh /var/log 2>/dev/null | cut -f1)
    info "Total /var/log size: $total"

    echo ""
    info "Largest log files/directories:"
    du -sh /var/log/* 2>/dev/null | sort -rh | head -10 | \
        awk '{printf "       %-10s %s\n", $1, $2}'

    # Disk space risk:
    echo ""
    local var_usage
    var_usage=$(df /var/log 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [[ "${var_usage:-0}" -ge 90 ]]; then
        crit "/var/log filesystem is ${var_usage}% full — IMMEDIATE RISK"
    elif [[ "${var_usage:-0}" -ge 80 ]]; then
        warn "/var/log filesystem is ${var_usage}% full"
    else
        pass "/var/log filesystem is ${var_usage}% full"
    fi

    # Find logs growing without rotation (large + not in logrotate.d):
    echo ""
    info "Large logs (>50MB) — verify they are being rotated:"
    find /var/log -type f -size +50M 2>/dev/null | while read -r logfile; do
        local size
        size=$(du -h "$logfile" | cut -f1)
        local base
        base=$(basename "$logfile")
        if grep -rql "$base\|$(dirname "$logfile")" /etc/logrotate.d/ 2>/dev/null; then
            info "  $size  $logfile (rotation configured)"
        else
            warn "  $size  $logfile (NO rotation config found)"
        fi
    done
}

# ── Security event extraction ─────────────────────────────────
extract_security_events() {
    section "Security Event Summary (last 24 hours)"

    # Failed SSH logins:
    local failed_ssh
    failed_ssh=$(journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null | \
        grep -c "Failed password" || echo 0)
    if [[ "${failed_ssh:-0}" -gt 50 ]]; then
        crit "Failed SSH logins: $failed_ssh (possible brute force)"
    elif [[ "${failed_ssh:-0}" -gt 0 ]]; then
        info "Failed SSH logins: $failed_ssh"
    else
        pass "No failed SSH logins"
    fi

    # Top source IPs for failed logins:
    if [[ "${failed_ssh:-0}" -gt 0 ]]; then
        info "Top sources of failed logins:"
        journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null | \
            grep "Failed password" | \
            grep -oE 'from [0-9.]+' | awk '{print $2}' | \
            sort | uniq -c | sort -rn | head -5 | \
            awk '{printf "         %4d attempts from %s\n", $1, $2}'
    fi

    # sudo usage:
    local sudo_count
    sudo_count=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | \
        grep -c "sudo.*COMMAND" || echo 0)
    info "sudo command executions: $sudo_count"

    # Errors and criticals:
    local error_count
    error_count=$(journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | \
        wc -l || echo 0)
    if [[ "${error_count:-0}" -gt 100 ]]; then
        warn "Error-level messages: $error_count (review recommended)"
    else
        info "Error-level messages: $error_count"
    fi

    # Service failures:
    local svc_failures
    svc_failures=$(journalctl --since "24 hours ago" --no-pager 2>/dev/null | \
        grep -c "Failed to start\|entered failed state" || echo 0)
    [[ "${svc_failures:-0}" -gt 0 ]] && \
        warn "Service failure events: $svc_failures" || \
        pass "No service failures"
}

# ── Centralized logging check ─────────────────────────────────
check_central_logging() {
    section "Centralized Logging Configuration"

    # Is this server forwarding logs anywhere?
    if grep -rhE "@@?[a-zA-Z0-9.]+:[0-9]+|omrelp|omfwd" \
       /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null | grep -v "^#" | head -1 \
       &>/dev/null; then
        pass "Log forwarding is configured:"
        grep -rhE "@@?[a-zA-Z0-9.]+:[0-9]+|target=" \
            /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null | \
            grep -v "^#" | head -3 | sed 's/^/       /'
    else
        warn "No log forwarding configured — logs are LOCAL ONLY"
        info "Risk: logs lost if server is compromised or destroyed"
        info "Recommendation: forward to a central log server"
    fi

    # Is this server RECEIVING logs (is it a collector)?
    if ss -tlnp 2>/dev/null | grep -qE ':514|:2514|:6514'; then
        pass "This server is configured as a log collector (listening)"
    fi
}

# ── Main ──────────────────────────────────────────────────────
main() {
    {
        echo "════════════════════════════════════════════════"
        echo "  LOGGING INFRASTRUCTURE ANALYSIS"
        echo "  $(date)"
        echo "  Host: $(hostname -f)"
        echo "════════════════════════════════════════════════"

        check_logging_health
        analyze_log_volume
        extract_security_events
        check_central_logging

        echo ""
        echo "════════════════════════════════════════════════"
        echo "  Analysis complete: $(date)"
        echo "════════════════════════════════════════════════"
    } 2>&1 | tee "$REPORT"

    echo ""
    echo "Full report: $REPORT"
}

main "$@"
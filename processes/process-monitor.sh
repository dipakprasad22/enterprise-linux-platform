#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Process Monitor and Auto-Remediation Tool
# Features:
#   - Monitor critical processes and restart if dead
#   - Detect and alert on high CPU processes
#   - Zombie process detection and cleanup
#   - OOM kill detection from kernel logs
#   - Resource usage baseline per process
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

CONFIG="/etc/process-monitor.conf"
LOG="/var/log/process-monitor.log"
ALERT_LOG="/var/log/process-monitor-alerts.log"

# Default thresholds
CPU_ALERT_THRESHOLD=80         # alert if process > 80% CPU
MEM_ALERT_THRESHOLD=85         # alert if process > 85% memory
ZOMBIE_ALERT_THRESHOLD=5       # alert if > 5 zombie processes
CHECK_INTERVAL=60              # check every 60 seconds

# Critical processes to monitor (can be overridden by config):
CRITICAL_SERVICES=(
    "nginx"
    "sshd"
    "rsyslog"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
alert() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: $*" | \
          tee -a "$ALERT_LOG" | tee -a "$LOG"; }

# ── Load config if exists ──────────────────────────────────────
[ -f "$CONFIG" ] && source "$CONFIG"

# ── Function: Check critical processes ────────────────────────
check_critical_processes() {
    local issues=0

    for service in "${CRITICAL_SERVICES[@]}"; do
        if systemctl list-units --type=service | grep -q "${service}.service"; then
            if ! systemctl is-active --quiet "${service}.service"; then
                alert "Service $service is NOT running — attempting restart"
                if systemctl start "${service}.service" 2>/dev/null; then
                    log "Successfully restarted $service"
                else
                    alert "FAILED to restart $service — manual intervention needed"
                    ((issues++))
                fi
            fi
        else
            if ! pgrep -x "$service" > /dev/null 2>&1; then
                alert "Process $service not found — not managed by systemd"
                ((issues++))
            fi
        fi
    done
    return $issues
}

# ── Function: Check for high CPU processes ────────────────────
check_high_cpu() {
    local found=0

    while IFS= read -r line; do
        cpu=$(echo "$line" | awk '{print $3}' | cut -d. -f1)
        pid=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $11}')

        if [ "${cpu:-0}" -ge "$CPU_ALERT_THRESHOLD" ]; then
            runtime=$(ps -p "$pid" -o etimes= 2>/dev/null | tr -d ' ')
            mem=$(ps -p "$pid" -o pmem= 2>/dev/null | tr -d ' ')
            alert "High CPU: $cmd (PID $pid) using ${cpu}% CPU for ${runtime}s, ${mem}% MEM"
            ((found++))
        fi
    done < <(ps aux --no-headers --sort=-%cpu 2>/dev/null | head -20)

    return 0
}

# ── Function: Check for high memory processes ─────────────────
check_high_memory() {
    while IFS= read -r line; do
        mem=$(echo "$line" | awk '{print $4}' | cut -d. -f1)
        pid=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $11}')

        if [ "${mem:-0}" -ge "$MEM_ALERT_THRESHOLD" ]; then
            rss=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')
            rss_mb=$((${rss:-0} / 1024))
            alert "High MEM: $cmd (PID $pid) using ${mem}% memory (${rss_mb}MB RSS)"
        fi
    done < <(ps aux --no-headers --sort=-%mem 2>/dev/null | head -10)

    return 0
}

# ── Function: Check for zombie processes ──────────────────────
check_zombies() {
    local zombie_count
    zombie_count=$(ps aux 2>/dev/null | awk '$8 == "Z"' | wc -l)

    if [ "$zombie_count" -gt "$ZOMBIE_ALERT_THRESHOLD" ]; then
        alert "High zombie count: $zombie_count zombie processes"
        log "Zombie processes:"
        ps aux 2>/dev/null | awk '$8 == "Z" {print "  PID:"$2,"PPID:"$3,"CMD:"$11}' \
            | head -10 | tee -a "$LOG"

        # Try to reap by finding and signaling parents:
        ps aux 2>/dev/null | awk '$8 == "Z" {print $3}' | \
            sort -u | while read -r ppid; do
            [ "$ppid" -eq 1 ] && continue   # do not signal init
            pcomm=$(cat /proc/$ppid/comm 2>/dev/null || echo "?")
            log "Sending SIGCHLD to parent PID $ppid ($pcomm) to reap zombies"
            kill -CHLD "$ppid" 2>/dev/null || true
        done
    else
        log "Zombie processes: $zombie_count (OK)"
    fi
}

# ── Function: Check OOM kill events ───────────────────────────
check_oom_events() {
    # Check for OOM kills in last 5 minutes:
    local oom_events
    oom_events=$(journalctl -k --since "5 minutes ago" --no-pager 2>/dev/null | \
        grep -c "Killed process\|Out of memory" 2>/dev/null || echo 0)

    if [ "${oom_events:-0}" -gt 0 ]; then
        alert "OOM KILL detected: $oom_events event(s) in last 5 minutes"
        journalctl -k --since "5 minutes ago" --no-pager 2>/dev/null | \
            grep -i "killed process\|out of memory" | \
            tee -a "$ALERT_LOG"
    fi
}

# ── Function: System resource summary ─────────────────────────
resource_summary() {
    local load cpu_idle mem_used_pct

    load=$(cat /proc/loadavg | awk '{print $1}')
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
    cpu_used=$((100 - ${cpu_idle:-100}))

    mem_total=$(free | grep Mem | awk '{print $2}')
    mem_used=$(free | grep Mem | awk '{print $3}')
    mem_used_pct=$((mem_used * 100 / mem_total))

    log "System: Load=${load} CPU=${cpu_used}% MEM=${mem_used_pct}%"
}

# ── Function: Generate report ─────────────────────────────────
generate_report() {
    echo "════════════════════════════════════════════════"
    echo "  PROCESS HEALTH REPORT"
    echo "  $(date) | $(hostname -f)"
    echo "════════════════════════════════════════════════"
    echo ""

    echo "TOP 10 PROCESSES BY CPU:"
    ps aux --no-headers --sort=-%cpu | head -10 | \
        awk '{printf "  %-20s PID:%-8s CPU:%-6s MEM:%-6s\n", $11, $2, $3, $4}'

    echo ""
    echo "TOP 10 PROCESSES BY MEMORY:"
    ps aux --no-headers --sort=-%mem | head -10 | \
        awk '{printf "  %-20s PID:%-8s MEM:%-6s VSZ:%-10s RSS:%s\n",
              $11, $2, $4, $5, $6}'

    echo ""
    echo "PROCESS STATE COUNTS:"
    ps aux --no-headers | awk '{print $8}' | \
        sort | uniq -c | sort -rn | \
        while read -r count state; do
            printf "  %-15s %s\n" "$state" "$count"
        done

    echo ""
    echo "CRITICAL SERVICE STATUS:"
    for svc in "${CRITICAL_SERVICES[@]}"; do
        if systemctl list-units --type=service 2>/dev/null | \
           grep -q "${svc}.service"; then
            status=$(systemctl is-active "${svc}.service" 2>/dev/null)
            [ "$status" = "active" ] && \
                echo -e "  ${GREEN}[OK]${NC}  $svc" || \
                echo -e "  ${RED}[FAIL]${NC} $svc ($status)"
        fi
    done

    echo ""
    echo "OOM KILL EVENTS (last hour):"
    oom_count=$(journalctl -k --since "1 hour ago" --no-pager 2>/dev/null | \
        grep -c "Killed process" 2>/dev/null || echo 0)
    [ "${oom_count:-0}" -gt 0 ] && \
        echo -e "  ${RED}WARNING: $oom_count OOM kill(s) detected${NC}" || \
        echo "  None"

    echo ""
    echo "════════════════════════════════════════════════"
}

# ── Main dispatcher ────────────────────────────────────────────
case "${1:-report}" in
    report)
        generate_report
        ;;
    check)
        log "Starting process health check"
        resource_summary
        check_critical_processes || true
        check_high_cpu
        check_high_memory
        check_zombies
        check_oom_events
        log "Check complete"
        ;;
    watch)
        log "Starting continuous monitoring (interval: ${CHECK_INTERVAL}s)"
        while true; do
            "$0" check
            sleep "$CHECK_INTERVAL"
        done
        ;;
    *)
        echo "Usage: $0 {report|check|watch}"
        exit 1
        ;;
esac
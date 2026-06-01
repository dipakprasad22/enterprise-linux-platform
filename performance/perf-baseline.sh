#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Performance Baseline and Tuning Report
#
# Usage:
#   ./perf-baseline.sh             # generate baseline report
#   ./perf-baseline.sh --tune      # apply recommended tuning
#   ./perf-baseline.sh --compare   # compare to previous baseline
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly BASELINE_DIR="/var/lib/perf-baseline"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly REPORT="${BASELINE_DIR}/baseline-${TIMESTAMP}.json"
readonly LOG="/var/log/perf-baseline.log"
readonly MODE="${1:---report}"

mkdir -p "$BASELINE_DIR"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

# ── Collect CPU metrics ────────────────────────────────────────
collect_cpu() {
    local cores load_1 load_5 load_15 cpu_idle cpu_iowait

    cores=$(nproc)
    read -r load_1 load_5 load_15 _ < /proc/loadavg
    cpu_idle=$(top -bn1 | grep "Cpu" | awk '{print $8}' | tr -d '%,' | head -1)
    cpu_iowait=$(top -bn1 | grep "Cpu" | awk '{print $10}' | tr -d '%,' | head -1)

    cat << EOF
  "cpu": {
    "cores": $cores,
    "load_1min": $load_1,
    "load_5min": $load_5,
    "load_15min": $load_15,
    "load_ratio": $(echo "scale=2; ${load_1}/${cores}" | bc 2>/dev/null || echo 0),
    "cpu_idle_pct": ${cpu_idle:-0},
    "cpu_iowait_pct": ${cpu_iowait:-0},
    "status": "$(
        LOAD_INT="${load_1%.*}"
        [[ "${LOAD_INT:-0}" -gt "$cores" ]] && echo "saturated" || echo "healthy"
    )"
  }
EOF
}

# ── Collect memory metrics ─────────────────────────────────────
collect_memory() {
    local total free available swap_total swap_used

    total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    free=$(grep MemFree /proc/meminfo | awk '{print $2}')
    available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    swap_used=$(( swap_total - $(grep SwapFree /proc/meminfo | awk '{print $2}') ))
    avail_pct=$((available * 100 / total))

    cat << EOF
  "memory": {
    "total_mb": $((total/1024)),
    "available_mb": $((available/1024)),
    "free_mb": $((free/1024)),
    "available_pct": $avail_pct,
    "swap_total_mb": $((swap_total/1024)),
    "swap_used_mb": $((swap_used/1024)),
    "status": "$(
        [[ $avail_pct -lt 10 ]] && echo "critical" || \
        [[ $avail_pct -lt 25 ]] && echo "warning" || \
        echo "healthy"
    )"
  }
EOF
}

# ── Collect disk metrics ───────────────────────────────────────
collect_disk() {
    echo '  "disk": ['

    local first=true
    df -h --output=target,pcent,size,used,avail,fstype | \
        grep -v tmpfs | grep -v devtmpfs | \
        tail -n +2 | while IFS= read -r line; do
            mount=$(echo "$line" | awk '{print $1}')
            pct=$(echo "$line" | awk '{print $2}' | tr -d '%')
            size=$(echo "$line" | awk '{print $3}')
            fstype=$(echo "$line" | awk '{print $6}')

            [[ "$first" == "false" ]] && echo ","
            first=false

            cat << EOF
    {
      "mount": "$mount",
      "filesystem": "$fstype",
      "size": "$size",
      "used_pct": ${pct:-0},
      "status": "$(
          [[ ${pct:-0} -ge 90 ]] && echo "critical" || \
          [[ ${pct:-0} -ge 80 ]] && echo "warning" || \
          echo "healthy"
      )"
    }
EOF
    done

    echo '  ]'
}

# ── Collect network metrics ────────────────────────────────────
collect_network() {
    local established time_wait close_wait

    established=$(ss -tan state established 2>/dev/null | wc -l)
    time_wait=$(ss -tan state time-wait 2>/dev/null | wc -l)
    close_wait=$(ss -tan state close-wait 2>/dev/null | wc -l)

    cat << EOF
  "network": {
    "tcp_established": $established,
    "tcp_time_wait": $time_wait,
    "tcp_close_wait": $close_wait,
    "status": "$(
        [[ $time_wait -gt 10000 ]] && echo "warning" || \
        [[ $close_wait -gt 1000 ]] && echo "warning" || \
        echo "healthy"
    )"
  }
EOF
}

# ── Collect kernel tuning parameters ──────────────────────────
collect_kernel_params() {
    cat << EOF
  "kernel_params": {
    "vm_swappiness": $(sysctl -n vm.swappiness 2>/dev/null || echo "unknown"),
    "vm_dirty_ratio": $(sysctl -n vm.dirty_ratio 2>/dev/null || echo "unknown"),
    "net_somaxconn": $(sysctl -n net.core.somaxconn 2>/dev/null || echo "unknown"),
    "tcp_fin_timeout": $(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo "unknown"),
    "aslr": $(sysctl -n kernel.randomize_va_space 2>/dev/null || echo "unknown"),
    "ip_local_port_range": "$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null || echo "unknown")"
  }
EOF
}

# ── Generate recommendations ────────────────────────────────────
generate_recommendations() {
    local recs=()

    local load_1 cores avail_pct swap_used time_wait swappiness
    load_1=$(cat /proc/loadavg | awk '{print $1}' | cut -d. -f1)
    cores=$(nproc)
    avail_pct=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') * 100 / \
                  $(grep MemTotal /proc/meminfo | awk '{print $2}') ))
    swap_used=$(( $(grep SwapTotal /proc/meminfo | awk '{print $2}') - \
                  $(grep SwapFree /proc/meminfo | awk '{print $2}') ))
    time_wait=$(ss -tan state time-wait 2>/dev/null | wc -l)
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo 60)

    [[ "${load_1:-0}" -gt "$cores" ]] && \
        recs+=("CPU saturated: investigate top processes, consider vertical scaling")

    [[ "$avail_pct" -lt 20 ]] && \
        recs+=("Memory pressure: available ${avail_pct}%, consider increasing RAM")

    [[ "${swap_used:-0}" -gt 0 ]] && \
        recs+=("Swap in use: $(( swap_used/1024 ))MB — investigate memory consumers")

    [[ "${time_wait:-0}" -gt 5000 ]] && \
        recs+=("High TIME_WAIT ($time_wait): set net.ipv4.tcp_tw_reuse=1")

    [[ "${swappiness:-60}" -gt 20 ]] && \
        recs+=("vm.swappiness=$swappiness: reduce to 10 for application servers")

    echo '  "recommendations": ['
    local first=true
    for rec in "${recs[@]:-}"; do
        [[ "$first" == "false" ]] && echo ","
        first=false
        echo "    \"$rec\""
    done
    echo '  ]'
}

# ── Apply recommended tuning ───────────────────────────────────
apply_tuning() {
    log "Applying recommended performance tuning..."

    local tuning_file="/etc/sysctl.d/99-perf-baseline-tuning.conf"

    cat > "$tuning_file" << 'EOF'
# Applied by perf-baseline.sh
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.somaxconn = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
fs.file-max = 2097152
EOF

    sysctl --system > /dev/null
    log "Tuning applied: $tuning_file"
    log "Run ./perf-baseline.sh to generate a new baseline"
}

# ── Main ──────────────────────────────────────────────────────
main() {
    log "Collecting performance baseline..."

    # Generate JSON report:
    {
        echo "{"
        echo "  \"timestamp\": \"$TIMESTAMP\","
        echo "  \"hostname\": \"$(hostname -f)\","
        echo "  \"os\": \"$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')\","
        echo "  \"kernel\": \"$(uname -r)\","
        collect_cpu; echo ","
        collect_memory; echo ","
        collect_disk; echo ","
        collect_network; echo ","
        collect_kernel_params; echo ","
        generate_recommendations
        echo "}"
    } > "$REPORT"

    log "Baseline saved: $REPORT"

    # Human-readable output:
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  PERFORMANCE BASELINE REPORT"
    echo "  $(date) | $(hostname -f)"
    echo "════════════════════════════════════════════════"

    # Parse and display key metrics:
    python3 -c "
import json,sys
data = json.load(open('$REPORT'))
cpu = data['cpu']
mem = data['memory']
net = data['network']

print(f\"\\nCPU: Load={cpu['load_1min']} ratio={cpu['load_ratio']} iowait={cpu['cpu_iowait_pct']}% [{cpu['status'].upper()}]\")
print(f\"Memory: Available={mem['available_mb']}MB ({mem['available_pct']}%) Swap={mem['swap_used_mb']}MB [{mem['status'].upper()}]\")
print(f\"Network: EST={net['tcp_established']} TIME_WAIT={net['tcp_time_wait']} CLOSE_WAIT={net['tcp_close_wait']}\")

if data['recommendations']:
    print('\\nRecommendations:')
    for r in data['recommendations']:
        print(f'  ⚠  {r}')
else:
    print('\\n✓ No immediate tuning recommendations')
" 2>/dev/null || cat "$REPORT" | head -40

    echo ""
    echo "Full baseline: $REPORT"
    echo "════════════════════════════════════════════════"
}

case "$MODE" in
    --report|-r) main ;;
    --tune|-t)   apply_tuning ;;
    *)           echo "Usage: $0 [--report|--tune]"; exit 1 ;;
esac
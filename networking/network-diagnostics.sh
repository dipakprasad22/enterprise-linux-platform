#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Network Diagnostics and Security Checker
# File: networking/network-diagnostics.sh
# Part of: enterprise-linux-platform
# Features:
#   - Layer-by-layer connectivity diagnosis
#   - Firewall rule audit
#   - DNS resolution testing
#   - Network performance baseline
#   - Security port scan detection
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

LOG="/var/log/network-diagnostics.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

ok()       { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()     { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()     { echo -e "${RED}[FAIL]${NC}  $*"; }
info()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
header()   { echo -e "\n${BOLD}══ $* ══${NC}"; }

log_result() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# ── Section 1: Interface Health ────────────────────────────────
check_interfaces() {
    header "NETWORK INTERFACES"

    while IFS= read -r line; do
        iface=$(echo "$line" | awk -F': ' '{print $2}' | awk '{print $1}')
        state=$(echo "$line" | grep -o 'state [A-Z]*' | awk '{print $2}')

        [ -z "$iface" ] && continue

        case "$state" in
            UP)     ok "$iface — UP" ;;
            DOWN)   fail "$iface — DOWN — check cable or run: ip link set $iface up" ;;
            *)      warn "$iface — state: ${state:-UNKNOWN}" ;;
        esac
    done < <(ip link show | grep "^[0-9]")

    # Check for interfaces with errors:
    echo ""
    info "Interface error counts:"
    ip -s link show | awk '
        /^[0-9]+:/ { iface=$2 }
        /RX:/ { getline; if ($3>0 || $4>0) 
            printf "  %s RX errors:%s dropped:%s\n", iface, $3, $4 }
        /TX:/ { getline; if ($3>0 || $4>0) 
            printf "  %s TX errors:%s dropped:%s\n", iface, $3, $4 }
    ' || true
}

# ── Section 2: IP and Routing ──────────────────────────────────
check_routing() {
    header "IP ADDRESSES AND ROUTING"

    echo "Configured IPs:"
    ip addr show | grep "inet " | grep -v "127.0.0.1" | \
        awk '{printf "  %-20s on %s\n", $2, $NF}'

    echo ""
    echo "Default gateway:"
    GW=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -n "$GW" ]; then
        echo "  Gateway: $GW"
        if ping -c 1 -W 2 "$GW" > /dev/null 2>&1; then
            ok "Gateway $GW is reachable"
        else
            fail "Gateway $GW is NOT reachable"
        fi
    else
        fail "No default gateway configured"
    fi

    echo ""
    echo "Routing table:"
    ip route show | while read -r line; do
        echo "  $line"
    done
}

# ── Section 3: DNS Resolution ──────────────────────────────────
check_dns() {
    header "DNS RESOLUTION"

    # Check resolv.conf
    echo "Configured DNS servers:"
    grep "^nameserver" /etc/resolv.conf | while read -r _ ns; do
        echo -n "  $ns — "
        if dig +short +time=3 google.com @"$ns" > /dev/null 2>&1; then
            ok "responding"
        else
            fail "NOT responding"
        fi
    done

    echo ""
    echo "DNS resolution tests:"
    for target in google.com github.com; do
        result=$(dig +short +time=3 "$target" A 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            ok "$target → $result"
        else
            fail "$target → FAILED to resolve"
        fi
    done

    # DNS performance:
    echo ""
    info "DNS response time:"
    NS=$(grep "^nameserver" /etc/resolv.conf | head -1 | awk '{print $2}')
    if [ -n "$NS" ]; then
        TIME=$(dig +stats google.com @"$NS" 2>/dev/null | \
            grep "Query time" | awk '{print $4}')
        if [ "${TIME:-999}" -lt 100 ]; then
            ok "DNS response: ${TIME}ms"
        else
            warn "DNS response: ${TIME}ms — high latency"
        fi
    fi
}

# ── Section 4: Listening Services ──────────────────────────────
check_services() {
    header "LISTENING SERVICES"

    echo "All listening TCP ports:"
    ss -tlnp | tail -n +2 | while read -r state recvq sendq local remote proc; do
        port=$(echo "$local" | awk -F: '{print $NF}')
        process=$(echo "$proc" | grep -o 'comm="[^"]*"' | \
            cut -d'"' -f2 2>/dev/null || echo "unknown")
        addr=$(echo "$local" | sed 's/:[^:]*$//')

        if [ "$addr" = "0.0.0.0" ] || [ "$addr" = "[::]" ] || \
           [ "$addr" = "*" ]; then
            echo "  Port $port — $process — listening on ALL interfaces"
        else
            echo "  Port $port — $process — listening on $addr only"
        fi
    done
}

# ── Section 5: Firewall Audit ──────────────────────────────────
check_firewall() {
    header "FIREWALL SECURITY AUDIT"

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        info "firewalld is active"
        echo ""
        echo "Active zones:"
        firewall-cmd --get-active-zones 2>/dev/null
        echo ""
        echo "Allowed services in default zone:"
        firewall-cmd --list-services 2>/dev/null | tr ' ' '\n' | \
            while read -r svc; do echo "  - $svc"; done
        echo ""
        echo "Allowed ports in default zone:"
        firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | \
            while read -r port; do echo "  - $port"; done
    else
        info "iptables rules:"
        RULES=$(iptables -L INPUT -n --line-numbers 2>/dev/null | wc -l)
        if [ "$RULES" -le 3 ]; then
            warn "INPUT chain appears empty — server may be unfiltered"
        else
            ok "INPUT chain has $((RULES-2)) rule(s)"
        fi

        # Check for dangerous rules:
        if iptables -L INPUT -n 2>/dev/null | grep -q "0.0.0.0/0.*ACCEPT"; then
            warn "ACCEPT ALL rule found — review security posture"
        fi

        echo ""
        iptables -L INPUT -n --line-numbers 2>/dev/null
    fi

    # Check for unexpected listeners (common ports only):
    echo ""
    header "UNEXPECTED OPEN PORTS CHECK"
    UNEXPECTED_PORTS=(23 25 53 111 135 139 445 512 513 514 3389)
    for port in "${UNEXPECTED_PORTS[@]}"; do
        if ss -tlnp | grep -q ":${port} "; then
            warn "Port $port is open — verify this is intentional"
            log_result "SECURITY: Port $port unexpectedly open"
        fi
    done
    ok "Unexpected port scan complete"
}

# ── Section 6: Connectivity Tests ─────────────────────────────
check_connectivity() {
    header "OUTBOUND CONNECTIVITY"

    TARGETS=(
        "8.8.8.8:ICMP:Internet ICMP"
        "8.8.8.8:53:DNS UDP would be here"
        "1.1.1.1:443:Cloudflare HTTPS"
        "github.com:443:GitHub HTTPS"
    )

    for target_info in "${TARGETS[@]}"; do
        IFS=: read -r ip port label <<< "$target_info"
        if nc -zw 3 "$ip" "$port" > /dev/null 2>&1; then
            ok "$label ($ip:$port)"
        else
            warn "$label ($ip:$port) — not reachable"
        fi
    done
}

# ── Section 7: Network Performance ─────────────────────────────
check_performance() {
    header "NETWORK PERFORMANCE BASELINE"

    echo "Connection state summary:"
    ss -tan 2>/dev/null | awk 'NR>1{print $1}' | \
        sort | uniq -c | sort -rn | \
        while read -r count state; do
            if [ "$state" = "TIME_WAIT" ] && [ "$count" -gt 1000 ]; then
                warn "$count connections in $state (high — consider tcp_tw_reuse)"
            else
                info "$count connections in $state"
            fi
        done

    echo ""
    echo "Key network kernel parameters:"
    for param in \
        net.core.somaxconn \
        net.ipv4.tcp_fin_timeout \
        net.ipv4.ip_local_port_range \
        net.ipv4.tcp_tw_reuse \
        net.ipv4.ip_forward; do
        value=$(sysctl -n "$param" 2>/dev/null)
        echo "  $param = $value"
    done
}

# ── Main ────────────────────────────────────────────────────────
main() {
    echo "════════════════════════════════════════════════"
    echo "  ENTERPRISE NETWORK DIAGNOSTICS REPORT"
    echo "  $(date) | $(hostname -f)"
    echo "════════════════════════════════════════════════"

    check_interfaces
    check_routing
    check_dns
    check_services
    check_firewall
    check_connectivity
    check_performance

    echo ""
    echo "════════════════════════════════════════════════"
    echo "  REPORT COMPLETE"
    echo "  Full log: $LOG"
    echo "════════════════════════════════════════════════"
}

main "$@"
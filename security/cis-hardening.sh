#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise CIS Benchmark Hardening Tool
# File: security/cis-hardening.sh
# Part of: enterprise-linux-platform
#
# Modes:
#   audit   = check compliance, do not change anything
#   harden  = apply hardening controls
#   report  = generate compliance report
#
# Usage:
#   ./cis-hardening.sh audit         # check only
#   ./cis-hardening.sh harden        # apply hardening
#   DRY_RUN=true ./cis-hardening.sh harden  # simulate
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

readonly SCRIPT_NAME=$(basename "$0")
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG="/var/log/cis-hardening-${TIMESTAMP}.log"
readonly REPORT="/var/log/cis-compliance-${TIMESTAMP}.txt"
readonly DRY_RUN="${DRY_RUN:-false}"
readonly MODE="${1:-audit}"

PASS=0; FAIL=0; APPLIED=0; SKIPPED=0

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()   { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
pass()  { echo -e "${GREEN}[PASS]${NC}  $*"; ((PASS++));    log "PASS: $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; ((FAIL++));    log "FAIL: $*"; }
apply() { echo -e "${BLUE}[APPLY]${NC} $*"; ((APPLIED++)); log "APPLIED: $*"; }
skip()  { echo -e "${YELLOW}[SKIP]${NC}  $*"; ((SKIPPED++)); log "SKIPPED: $*"; }
info()  { echo -e "        $*"; }

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $*"
    else
        eval "$@"
    fi
}

# ── Check and optionally fix a sysctl value ────────────────────
check_sysctl() {
    local param="$1"
    local expected="$2"
    local description="$3"
    local actual
    actual=$(sysctl -n "$param" 2>/dev/null || echo "MISSING")

    if [[ "$actual" == "$expected" ]]; then
        pass "$description ($param=$actual)"
    else
        fail "$description ($param=$actual, want $expected)"
        if [[ "$MODE" == "harden" ]]; then
            run_cmd "sysctl -w '${param}=${expected}'"
            run_cmd "echo '${param} = ${expected}' >> /etc/sysctl.d/99-cis-hardening.conf"
            apply "Set $param=$expected"
        fi
    fi
}

# ── Check a service is disabled ────────────────────────────────
check_service_disabled() {
    local service="$1"
    local description="${2:-$service}"

    if ! systemctl list-unit-files 2>/dev/null | \
       grep -q "^${service}.service"; then
        pass "$description not installed"
        return
    fi

    if systemctl is-enabled --quiet "$service" 2>/dev/null || \
       systemctl is-active --quiet "$service" 2>/dev/null; then
        fail "$description is enabled/running"
        if [[ "$MODE" == "harden" ]]; then
            run_cmd "systemctl disable --now '$service'"
            apply "Disabled $service"
        fi
    else
        pass "$description is disabled"
    fi
}

# ── Check SSH config parameter ─────────────────────────────────
check_ssh_param() {
    local param="$1"
    local expected="$2"
    local description="$3"

    local actual
    actual=$(grep -r "^${param}" \
        /etc/ssh/sshd_config \
        /etc/ssh/sshd_config.d/ \
        2>/dev/null | \
        awk '{print $2}' | head -1)

    if [[ "${actual,,}" == "${expected,,}" ]]; then
        pass "$description ($param=$actual)"
    else
        fail "$description ($param=${actual:-not set}, want $expected)"
        if [[ "$MODE" == "harden" ]]; then
            run_cmd "echo '${param} ${expected}' >> /etc/ssh/sshd_config.d/99-cis-hardening.conf"
            apply "Set SSH $param=$expected"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# HARDENING CHECKS
# ═══════════════════════════════════════════════════════════════

section() { echo ""; echo "── $* ──"; }

section "1. Kernel Security Parameters"
check_sysctl "kernel.randomize_va_space"              "2" "ASLR enabled"
check_sysctl "kernel.dmesg_restrict"                  "1" "dmesg restricted to root"
check_sysctl "net.ipv4.tcp_syncookies"                "1" "SYN cookie protection"
check_sysctl "net.ipv4.conf.all.accept_redirects"     "0" "ICMP redirects disabled"
check_sysctl "net.ipv4.conf.all.send_redirects"       "0" "Send redirects disabled"
check_sysctl "net.ipv4.conf.all.accept_source_route"  "0" "Source routing disabled"
check_sysctl "net.ipv4.conf.all.log_martians"         "1" "Martian packet logging"
check_sysctl "net.ipv4.icmp_echo_ignore_broadcasts"   "1" "Broadcast ping ignored"
check_sysctl "fs.suid_dumpable"                       "0" "SUID core dumps disabled"
check_sysctl "fs.protected_symlinks"                  "1" "Symlink protection"
check_sysctl "fs.protected_hardlinks"                 "1" "Hardlink protection"

section "2. SSH Hardening"
check_ssh_param "PermitRootLogin"          "no"  "Root SSH login disabled"
check_ssh_param "PasswordAuthentication"   "no"  "Password auth disabled"
check_ssh_param "PermitEmptyPasswords"     "no"  "Empty passwords denied"
check_ssh_param "MaxAuthTries"             "3"   "Max auth tries set to 3"
check_ssh_param "X11Forwarding"            "no"  "X11 forwarding disabled"
check_ssh_param "AllowTcpForwarding"       "no"  "TCP forwarding disabled"

section "3. Unnecessary Services"
check_service_disabled "telnet"       "Telnet service"
check_service_disabled "rsh"          "RSH service"
check_service_disabled "avahi-daemon" "Avahi mDNS daemon"
check_service_disabled "cups"         "CUPS printing"
check_service_disabled "bluetooth"    "Bluetooth service"

section "4. User Account Security"
# UID 0 check:
UID0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
[[ -z "$UID0" ]] && pass "No unauthorized UID 0 accounts" || \
    fail "Unauthorized UID 0: $UID0"

# Password policy:
MAX_DAYS=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
[[ "${MAX_DAYS:-99999}" -le 90 ]] && \
    pass "Password max age: $MAX_DAYS days" || \
    fail "Password max age too high: ${MAX_DAYS:-not configured}"

if [[ "$MODE" == "harden" && "${MAX_DAYS:-99999}" -gt 90 ]]; then
    run_cmd "sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs"
    apply "Set PASS_MAX_DAYS=90"
fi

section "5. Audit Framework"
systemctl is-active --quiet auditd 2>/dev/null && \
    pass "auditd is running" || {
    fail "auditd is NOT running"
    [[ "$MODE" == "harden" ]] && \
        run_cmd "systemctl enable --now auditd" && apply "Started auditd"
}

RULE_COUNT=$(auditctl -l 2>/dev/null | grep -v "^-D\|^No rules" | wc -l)
[[ "${RULE_COUNT:-0}" -ge 5 ]] && \
    pass "Audit rules: $RULE_COUNT configured" || \
    fail "Insufficient audit rules: $RULE_COUNT"

section "6. SELinux"
SELINUX=$(getenforce 2>/dev/null)
[[ "$SELINUX" == "Enforcing" ]] && \
    pass "SELinux: Enforcing" || {
    fail "SELinux: $SELINUX (should be Enforcing)"
    [[ "$MODE" == "harden" && "$SELINUX" == "Permissive" ]] && \
        run_cmd "setenforce 1" && apply "Set SELinux to Enforcing"
}

section "7. World-Writable Files"
WW_COUNT=$(find / -xdev -perm -0002 \
    -not -path "/tmp/*" \
    -not -path "/proc/*" \
    -not -path "/sys/*" \
    -type f 2>/dev/null | wc -l)
[[ "$WW_COUNT" -eq 0 ]] && \
    pass "No unexpected world-writable files" || \
    fail "$WW_COUNT world-writable file(s) found outside /tmp"

# ═══════════════════════════════════════════════════════════════
# FINAL REPORT
# ═══════════════════════════════════════════════════════════════

TOTAL=$((PASS + FAIL))
PCT=0
[[ $TOTAL -gt 0 ]] && PCT=$((PASS * 100 / TOTAL))

{
    echo ""
    echo "════════════════════════════════════════════════"
    echo "  CIS COMPLIANCE REPORT"
    echo "  Generated: $(date)"
    echo "  Hostname:  $(hostname -f)"
    echo "  OS:        $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    echo "  Mode:      $MODE"
    echo "  Dry run:   $DRY_RUN"
    echo ""
    echo "  Checks passed:  $PASS"
    echo "  Checks failed:  $FAIL"
    [[ "$MODE" == "harden" ]] && echo "  Controls applied: $APPLIED"
    echo "  Compliance:     ${PCT}%"
    echo ""
    if [[ $PCT -ge 90 ]]; then
        echo -e "  ${GREEN}STATUS: COMPLIANT (${PCT}% ≥ 90% threshold)${NC}"
    elif [[ $PCT -ge 70 ]]; then
        echo -e "  ${YELLOW}STATUS: PARTIALLY COMPLIANT (${PCT}%)${NC}"
    else
        echo -e "  ${RED}STATUS: NON-COMPLIANT (${PCT}% < 70% threshold)${NC}"
    fi
    echo ""
    echo "  Full log:  $LOG"
    echo "════════════════════════════════════════════════"
} | tee "$REPORT"

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
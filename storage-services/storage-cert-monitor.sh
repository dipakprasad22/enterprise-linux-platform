#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Storage, File Service, and Certificate Health Monitor
#
# Monitors:
#   - RAID array health (degraded/failed arrays)
#   - NFS exports and mounts
#   - Samba service and shares
#   - SSL/TLS certificate expiry (files AND live endpoints)
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly REPORT_DIR="${REPORT_DIR:-/var/lib/elap/reports/storage-cert}"
readonly REPORT="${REPORT_DIR}/storage-cert-${TIMESTAMP}.txt"
readonly CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"
readonly CERT_CRIT_DAYS="${CERT_CRIT_DAYS:-7}"

# Endpoints to check (host:port) — customize per environment:
LIVE_ENDPOINTS=("${LIVE_ENDPOINTS[@]:-}")
# Cert file locations to scan:
CERT_DIRS=("/etc/pki/tls/certs" "/etc/ssl/certs" "/etc/nginx/ssl" "/etc/letsencrypt/live")

mkdir -p "$REPORT_DIR" 2>/dev/null || REPORT="/tmp/storage-cert-${TIMESTAMP}.txt"

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

section() { echo ""; printf "${CYAN}══ %s ══${NC}\n" "$*"; }
pass() { printf "${GREEN}[OK]${NC}   %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
crit() { printf "${RED}[CRIT]${NC} %s\n" "$*"; }
info() { printf "       %s\n" "$*"; }

ISSUES=0

# ── RAID health ───────────────────────────────────────────────
check_raid() {
    section "RAID Array Health"

    if [[ ! -f /proc/mdstat ]] || ! grep -q "^md" /proc/mdstat 2>/dev/null; then
        info "No software RAID arrays detected"
        return
    fi

    # Check each array:
    for array in /dev/md*; do
        [[ -b "$array" ]] || continue
        local state
        state=$(mdadm --detail "$array" 2>/dev/null | \
            grep "State :" | head -1 | awk -F: '{print $2}' | xargs)

        case "$state" in
            *clean*|*active*)
                if echo "$state" | grep -qiE "degraded|recovering"; then
                    crit "$array is DEGRADED: $state"
                    ((ISSUES++))
                    mdadm --detail "$array" 2>/dev/null | \
                        grep -E "faulty|removed|spare" | sed 's/^/       /'
                else
                    pass "$array is healthy ($state)"
                fi
                ;;
            *)
                crit "$array state: $state"
                ((ISSUES++))
                ;;
        esac
    done

    # Show /proc/mdstat status line:
    echo ""
    info "Array status:"
    grep -A1 "^md" /proc/mdstat | grep -E "\[.*\]" | sed 's/^/       /'

    # Any rebuild in progress?
    if grep -q "recovery\|resync" /proc/mdstat; then
        warn "Array rebuild/resync in progress:"
        grep -E "recovery|resync" /proc/mdstat | sed 's/^/       /'
    fi
}

# ── NFS health ────────────────────────────────────────────────
check_nfs() {
    section "NFS Service and Mounts"

    # NFS server exports:
    if systemctl is-active --quiet nfs-server 2>/dev/null || \
       systemctl is-active --quiet nfs-kernel-server 2>/dev/null; then
        pass "NFS server is running"
        local exports
        exports=$(exportfs -v 2>/dev/null | wc -l)
        info "Active exports: $exports"
        exportfs -v 2>/dev/null | head -5 | sed 's/^/       /'
    else
        info "NFS server not running (may be intentional)"
    fi

    # NFS client mounts:
    local nfs_mounts
    nfs_mounts=$(mount -t nfs,nfs4 2>/dev/null | wc -l)
    if [[ "$nfs_mounts" -gt 0 ]]; then
        info "NFS client mounts: $nfs_mounts"
        # Check each is responsive:
        mount -t nfs,nfs4 2>/dev/null | awk '{print $3}' | while read -r mp; do
            if timeout 5 stat "$mp" &>/dev/null; then
                pass "NFS mount responsive: $mp"
            else
                crit "NFS mount UNRESPONSIVE (possible stale handle): $mp"
            fi
        done
    fi
}

# ── Samba health ──────────────────────────────────────────────
check_samba() {
    section "Samba Service"

    if systemctl is-active --quiet smb 2>/dev/null || \
       systemctl is-active --quiet smbd 2>/dev/null; then
        pass "Samba (smbd) is running"
        # Validate config:
        if testparm -s &>/dev/null; then
            pass "Samba config is valid"
        else
            crit "Samba config has errors (run testparm)"
            ((ISSUES++))
        fi
        # Active connections:
        local conns
        conns=$(smbstatus -b 2>/dev/null | grep -c "^[0-9]" || echo 0)
        info "Active Samba connections: $conns"
        # AD trust (if domain-joined):
        if command -v wbinfo &>/dev/null; then
            wbinfo -t &>/dev/null && \
                pass "AD trust relationship OK" || \
                info "Not domain-joined or trust check N/A"
        fi
    else
        info "Samba not running (may be intentional)"
    fi
}

# ── Certificate expiry ────────────────────────────────────────
check_cert_file() {
    local cert="$1"
    # Skip if not a certificate:
    openssl x509 -in "$cert" -noout &>/dev/null || return

    local enddate days_left subject
    enddate=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
    [[ -z "$enddate" ]] && return
    days_left=$(( ($(date -d "$enddate" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
    subject=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | \
        sed 's/.*CN *= *//' | cut -d, -f1)

    if [[ $days_left -lt 0 ]]; then
        crit "EXPIRED ${days_left#-} days ago: $subject ($cert)"
        ((ISSUES++))
    elif [[ $days_left -lt $CERT_CRIT_DAYS ]]; then
        crit "Expires in $days_left days: $subject ($cert)"
        ((ISSUES++))
    elif [[ $days_left -lt $CERT_WARN_DAYS ]]; then
        warn "Expires in $days_left days: $subject ($cert)"
    else
        pass "Valid $days_left more days: $subject"
    fi
}

check_certificates() {
    section "SSL/TLS Certificate Expiry (files)"

    local found=0
    for dir in "${CERT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r cert; do
            check_cert_file "$cert"
            ((found++))
        done < <(find "$dir" -type f \( -name "*.crt" -o -name "*.pem" -o -name "fullchain*.pem" \) 2>/dev/null | head -50)
    done
    [[ "$found" -eq 0 ]] && info "No certificate files found in standard locations"
}

check_live_endpoints() {
    [[ ${#LIVE_ENDPOINTS[@]} -eq 0 || -z "${LIVE_ENDPOINTS[0]:-}" ]] && return

    section "SSL/TLS Certificate Expiry (live endpoints)"
    for endpoint in "${LIVE_ENDPOINTS[@]}"; do
        [[ -z "$endpoint" ]] && continue
        local host="${endpoint%:*}" port="${endpoint#*:}"
        [[ "$host" == "$port" ]] && port=443

        local enddate
        enddate=$(echo | timeout 10 openssl s_client -connect "${host}:${port}" \
            -servername "$host" 2>/dev/null | \
            openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

        if [[ -z "$enddate" ]]; then
            crit "$endpoint: could not retrieve certificate"
            ((ISSUES++))
            continue
        fi

        local days_left=$(( ($(date -d "$enddate" +%s) - $(date +%s)) / 86400 ))
        if [[ $days_left -lt $CERT_CRIT_DAYS ]]; then
            crit "$endpoint: expires in $days_left days"
            ((ISSUES++))
        elif [[ $days_left -lt $CERT_WARN_DAYS ]]; then
            warn "$endpoint: expires in $days_left days"
        else
            pass "$endpoint: valid $days_left more days"
        fi
    done
}

# ── Main ──────────────────────────────────────────────────────
main() {
    {
        echo "════════════════════════════════════════════════"
        echo "  STORAGE, FILE SERVICE, AND CERTIFICATE HEALTH"
        echo "  $(date)"
        echo "  Host: $(hostname -f)"
        echo "════════════════════════════════════════════════"

        check_raid
        check_nfs
        check_samba
        check_certificates
        check_live_endpoints

        echo ""
        echo "════════════════════════════════════════════════"
        if [[ $ISSUES -eq 0 ]]; then
            echo "  STATUS: ALL HEALTHY"
        else
            echo "  STATUS: $ISSUES ISSUE(S) REQUIRING ATTENTION"
        fi
        echo "  Completed: $(date)"
        echo "════════════════════════════════════════════════"
    } 2>&1 | tee "$REPORT"

    echo ""
    echo "Report: $REPORT"
    exit "$([[ $ISSUES -eq 0 ]] && echo 0 || echo 1)"
}

main "$@"
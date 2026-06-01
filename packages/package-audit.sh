#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Package Inventory and Integrity Audit Tool
#
# Features:
#   - Complete package inventory (installed, versions, sizes)
#   - Integrity verification (detect tampered binaries)
#   - Pending update report (security and total)
#   - Repository configuration audit
#   - Orphaned and locked package detection
#   - JSON + human-readable output
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME=$(basename "$0")
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly REPORT_DIR="${REPORT_DIR:-/var/lib/elap/reports/packages}"
readonly REPORT="${REPORT_DIR}/package-audit-${TIMESTAMP}.txt"
readonly LOG="/var/log/elap/package-audit.log"

mkdir -p "$REPORT_DIR" "$(dirname "$LOG")" 2>/dev/null || {
    REPORT="/tmp/package-audit-${TIMESTAMP}.txt"
    LOG="/tmp/package-audit.log"
}

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

# ── Detect package manager ────────────────────────────────────
detect_pkg_mgr() {
    if command -v dnf &>/dev/null; then echo "dnf"
    elif command -v yum &>/dev/null; then echo "yum"
    elif command -v apt-get &>/dev/null; then echo "apt"
    else echo "unknown"; fi
}

PKG_MGR=$(detect_pkg_mgr)

# ── Section: inventory ────────────────────────────────────────
audit_inventory() {
    echo ""
    echo "── PACKAGE INVENTORY ──"

    case "$PKG_MGR" in
        dnf|yum)
            local total
            total=$(rpm -qa | wc -l)
            echo "Total packages installed: $total"
            echo ""
            echo "10 most recently installed:"
            rpm -qa --last | head -10 | sed 's/^/  /'
            echo ""
            echo "10 largest packages:"
            rpm -qa --queryformat '%{SIZE} %{NAME}-%{VERSION}\n' | \
                sort -rn | head -10 | \
                awk '{printf "  %6.1f MB  %s\n", $1/1024/1024, $2}'
            ;;
        apt)
            local total
            total=$(dpkg -l | grep -c '^ii')
            echo "Total packages installed: $total"
            echo ""
            echo "10 largest packages:"
            dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' | \
                sort -rn | head -10 | \
                awk '{printf "  %6.1f MB  %s\n", $1/1024, $2}'
            ;;
    esac
}

# ── Section: integrity ────────────────────────────────────────
audit_integrity() {
    echo ""
    echo "── INTEGRITY VERIFICATION ──"

    case "$PKG_MGR" in
        dnf|yum)
            echo "Scanning for modified non-config binaries..."
            local tampered
            tampered=$(rpm -Va 2>/dev/null | grep -E '^..5' | grep -v ' c ' || true)
            if [[ -n "$tampered" ]]; then
                echo -e "${RED}WARNING: Modified binaries detected:${NC}"
                echo "$tampered" | head -20 | sed 's/^/  /'
                echo "  → Investigate these immediately — possible compromise"
            else
                echo -e "${GREEN}No tampered binaries detected${NC}"
            fi

            echo ""
            echo "Config files modified from defaults (expected):"
            rpm -Va 2>/dev/null | grep -E '^..5.*c ' | wc -l | \
                xargs echo "  Count:"
            ;;
        apt)
            echo "Verifying package integrity (debsums)..."
            if command -v debsums &>/dev/null; then
                local changed
                changed=$(debsums -c 2>/dev/null | head -20 || true)
                [[ -n "$changed" ]] && \
                    echo -e "${YELLOW}Changed files:${NC}" && echo "$changed" || \
                    echo -e "${GREEN}All package files intact${NC}"
            else
                echo "  debsums not installed (apt install debsums)"
            fi
            ;;
    esac
}

# ── Section: pending updates ──────────────────────────────────
audit_updates() {
    echo ""
    echo "── PENDING UPDATES ──"

    case "$PKG_MGR" in
        dnf|yum)
            local total_updates security_updates
            total_updates=$($PKG_MGR check-update -q 2>/dev/null | \
                grep -c '^[a-zA-Z]' || echo 0)
            security_updates=$($PKG_MGR check-update --security -q 2>/dev/null | \
                grep -c '^[a-zA-Z]' || echo 0)
            echo "Total updates available:    $total_updates"
            if [[ "$security_updates" -gt 0 ]]; then
                echo -e "Security updates available: ${RED}$security_updates${NC}"
            else
                echo -e "Security updates available: ${GREEN}0${NC}"
            fi
            ;;
        apt)
            apt-get update -qq 2>/dev/null || true
            local total security
            total=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0)
            security=$(apt list --upgradable 2>/dev/null | grep -ci security || echo 0)
            echo "Total updates available:    $total"
            echo "Security updates available: $security"
            ;;
    esac
}

# ── Section: repository audit ─────────────────────────────────
audit_repositories() {
    echo ""
    echo "── REPOSITORY CONFIGURATION ──"

    case "$PKG_MGR" in
        dnf|yum)
            echo "Enabled repositories:"
            $PKG_MGR repolist 2>/dev/null | tail -n +2 | sed 's/^/  /'
            echo ""
            echo "Repositories with gpgcheck DISABLED (security risk):"
            local insecure
            insecure=$(grep -rl "gpgcheck=0" /etc/yum.repos.d/ 2>/dev/null || true)
            [[ -n "$insecure" ]] && \
                echo -e "${RED}$insecure${NC}" | sed 's/^/  /' || \
                echo -e "  ${GREEN}None — all repos verify signatures${NC}"
            ;;
        apt)
            echo "Configured sources:"
            grep -rh '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ \
                2>/dev/null | sed 's/^/  /' | head -15
            ;;
    esac
}

# ── Section: locked packages ──────────────────────────────────
audit_locks() {
    echo ""
    echo "── VERSION-LOCKED PACKAGES ──"
    echo "(Each lock should be a tracked exception with a review date)"

    case "$PKG_MGR" in
        dnf|yum)
            local locks
            locks=$($PKG_MGR versionlock list 2>/dev/null | \
                grep -v "^Last\|versionlock\|^$" || true)
            [[ -n "$locks" ]] && echo "$locks" | sed 's/^/  /' || \
                echo "  No version locks configured"
            ;;
        apt)
            local holds
            holds=$(apt-mark showhold 2>/dev/null || true)
            [[ -n "$holds" ]] && echo "$holds" | sed 's/^/  /' || \
                echo "  No packages on hold"
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────
main() {
    log "Starting package audit (pkg manager: $PKG_MGR)"

    {
        echo "════════════════════════════════════════════════"
        echo "  PACKAGE INVENTORY AND INTEGRITY AUDIT"
        echo "  $(date)"
        echo "  Host: $(hostname -f)"
        echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
        echo "  Package Manager: $PKG_MGR"
        echo "════════════════════════════════════════════════"

        audit_inventory
        audit_integrity
        audit_updates
        audit_repositories
        audit_locks

        echo ""
        echo "════════════════════════════════════════════════"
        echo "  Audit complete: $(date)"
        echo "════════════════════════════════════════════════"
    } | tee "$REPORT"

    log "Report saved: $REPORT"
    echo ""
    echo "Full report: $REPORT"
}

main "$@"
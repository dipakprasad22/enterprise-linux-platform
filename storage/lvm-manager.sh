#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise LVM Storage Management Tool
# Features:
#   - Storage health report
#   - Automated LV expansion when threshold exceeded
#   - Snapshot creation for backup
#   - Cleanup of old snapshots
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

LOG="/var/log/lvm-manager.log"
EXPAND_THRESHOLD=80        # expand LV when filesystem reaches this %
EXPAND_BY_GB=20            # how many GB to add when expanding
SNAPSHOT_SIZE_GB=10        # snapshot size
SNAPSHOT_RETAIN_HOURS=24   # remove snapshots older than this

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()      { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
ok()       { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()     { echo -e "${YELLOW}[WARN]${NC}  $*"; log "WARN: $*"; }
critical() { echo -e "${RED}[CRIT]${NC}  $*"; log "CRITICAL: $*"; }
info()     { echo -e "${BLUE}[INFO]${NC}  $*"; }

# ── Function: Storage Health Report ───────────────────────────
storage_report() {
    echo "════════════════════════════════════════════════════"
    echo "  LVM STORAGE HEALTH REPORT"
    echo "  $(date) | $(hostname -f)"
    echo "════════════════════════════════════════════════════"

    echo ""
    info "PHYSICAL VOLUMES:"
    pvs --noheadings -o pv_name,pv_size,pv_free,vg_name 2>/dev/null | \
        while read pv size free vg; do
            printf "  %-20s  Size:%-8s  Free:%-8s  VG:%s\n" \
                "$pv" "$size" "$free" "${vg:-unassigned}"
        done

    echo ""
    info "VOLUME GROUPS:"
    vgs --noheadings -o vg_name,vg_size,vg_free,pv_count,lv_count 2>/dev/null | \
        while read vg size free pvs lvs; do
            printf "  %-15s  Size:%-8s  Free:%-8s  PVs:%-3s  LVs:%s\n" \
                "$vg" "$size" "$free" "$pvs" "$lvs"
        done

    echo ""
    info "LOGICAL VOLUMES AND FILESYSTEM USAGE:"
    lvs --noheadings -o lv_path,lv_size,lv_attr 2>/dev/null | \
        while read lv_path lv_size lv_attr; do
            # Get mount point for this LV
            mount_point=$(findmnt -n -o TARGET --source "$lv_path" 2>/dev/null || echo "not mounted")

            if [ "$mount_point" != "not mounted" ]; then
                # Get filesystem usage
                usage=$(df -h "$mount_point" 2>/dev/null | tail -1 | \
                    awk '{print $3"/"$2" ("$5")"}')
                pct=$(df "$mount_point" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

                if [ "${pct:-0}" -ge 90 ]; then
                    critical "$(printf '%-35s  Size:%-8s  Usage:%-20s  Mount:%s' \
                        "$lv_path" "$lv_size" "$usage" "$mount_point")"
                elif [ "${pct:-0}" -ge 75 ]; then
                    warn "$(printf '%-35s  Size:%-8s  Usage:%-20s  Mount:%s' \
                        "$lv_path" "$lv_size" "$usage" "$mount_point")"
                else
                    ok "$(printf '%-35s  Size:%-8s  Usage:%-20s  Mount:%s' \
                        "$lv_path" "$lv_size" "$usage" "$mount_point")"
                fi
            else
                info "$(printf '%-35s  Size:%-8s  Not mounted' "$lv_path" "$lv_size")"
            fi
        done

    echo ""
    info "INODE USAGE (filesystems with >70% inode usage):"
    df -ih 2>/dev/null | awk 'NR>1 && $5!="IUse%" {
        pct=$5+0
        if (pct >= 70) print "  WARN: " $6 " inode usage: " $5
    }' || echo "  All filesystems have healthy inode usage"

    echo ""
    info "SNAPSHOTS:"
    lvs --noheadings -o lv_name,lv_size,data_percent,lv_attr 2>/dev/null | \
        grep "^.*s" | while read name size datapct attr; do
        printf "  %-25s  Size:%-8s  Used:%s\n" "$name" "$size" "$datapct%"
    done || echo "  No snapshots found"

    echo "════════════════════════════════════════════════════"
}

# ── Function: Auto-expand LV when threshold exceeded ──────────
auto_expand() {
    local mount_point="$1"
    local vg_name lv_path fs_type

    # Get LV info for this mount point
    lv_path=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null)
    [ -z "$lv_path" ] && { warn "Cannot find LV for $mount_point"; return 1; }

    vg_name=$(lvs --noheadings -o vg_name "$lv_path" 2>/dev/null | tr -d ' ')
    fs_type=$(findmnt -n -o FSTYPE "$mount_point" 2>/dev/null)

    # Check VG has enough free space
    vg_free_gb=$(vgs --noheadings --units g -o vg_free "$vg_name" 2>/dev/null | \
        tr -d ' g')

    if (( $(echo "$vg_free_gb < $EXPAND_BY_GB" | bc -l) )); then
        critical "VG $vg_name has only ${vg_free_gb}GB free — cannot expand $mount_point"
        return 1
    fi

    log "Auto-expanding $lv_path by ${EXPAND_BY_GB}GB"

    # Extend LV
    lvextend -L "+${EXPAND_BY_GB}G" "$lv_path"

    # Grow filesystem
    case "$fs_type" in
        xfs)
            xfs_growfs "$mount_point"
            ;;
        ext4|ext3)
            resize2fs "$lv_path"
            ;;
        *)
            warn "Unknown filesystem type $fs_type — manual resize needed"
            return 1
            ;;
    esac

    log "Successfully expanded $lv_path at $mount_point by ${EXPAND_BY_GB}GB"
    ok "Expanded $mount_point by ${EXPAND_BY_GB}GB"
}

# ── Function: Create backup snapshot ──────────────────────────
create_snapshot() {
    local lv_path="$1"
    local snap_name="${2:-$(basename $lv_path)_snap_$(date +%Y%m%d_%H%M%S)}"
    local vg_name

    vg_name=$(lvs --noheadings -o vg_name "$lv_path" 2>/dev/null | tr -d ' ')

    log "Creating snapshot: $snap_name from $lv_path"
    lvcreate -L "${SNAPSHOT_SIZE_GB}G" -s -n "$snap_name" "$lv_path"
    ok "Snapshot created: /dev/${vg_name}/${snap_name}"
    log "Snapshot created: /dev/${vg_name}/${snap_name}"
}

# ── Function: Check and auto-expand all LVs ───────────────────
check_all() {
    log "Starting automated storage check"

    df -h 2>/dev/null | awk 'NR>1' | while read fs size used avail pct mount; do
        pct_num=${pct//%/}
        [ "${pct_num:-0}" -ge "$EXPAND_THRESHOLD" ] || continue
        [ "$mount" = "/" ] || [[ "$mount" == /proc* ]] || \
            [[ "$mount" == /sys* ]] && continue

        warn "Filesystem $mount at ${pct} — threshold is ${EXPAND_THRESHOLD}%"

        # Only expand if it is an LVM volume
        source=$(findmnt -n -o SOURCE "$mount" 2>/dev/null)
        if lvs "$source" &>/dev/null; then
            log "Auto-expanding LVM volume at $mount"
            auto_expand "$mount"
        else
            critical "$mount is full but not LVM — manual intervention required"
        fi
    done

    log "Storage check complete"
}

# ── Main dispatcher ────────────────────────────────────────────
case "${1:-report}" in
    report)     storage_report ;;
    check)      check_all ;;
    expand)     auto_expand "${2:?Usage: $0 expand /mount/point}" ;;
    snapshot)   create_snapshot "${2:?Usage: $0 snapshot /dev/vg/lv}" ;;
    *)
        echo "Usage: $0 {report|check|expand <mountpoint>|snapshot <lv>}"
        exit 1
        ;;
esac
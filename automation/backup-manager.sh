#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Backup and Log Rotation System
#
# Features:
#   - Configurable backup targets (dirs, databases)
#   - Retention policy (keep N days)
#   - Compression and checksums
#   - Log rotation with archival
#   - Backup verification
#   - Email/webhook notification on failure
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_VERSION="1.0.0"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# ── Configuration (override via environment or config file) ────
BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
LOG_FILE="${LOG_FILE:-/var/log/backup-manager.log}"
LOCK_FILE="/var/run/backup-manager.lock"
NOTIFY_WEBHOOK="${NOTIFY_WEBHOOK:-}"         # optional Slack/Teams webhook
CHECKSUM_ALGO="sha256"

# ── Backup targets ─────────────────────────────────────────────
BACKUP_DIRS=(
    "/etc"
    "/opt/enterprise-linux-platform"
)

# ── Logging ───────────────────────────────────────────────────
log() {
    local level="$1"; shift
    printf '[%s] [%-5s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" \
        | tee -a "$LOG_FILE"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_ok()    { log "OK"    "$@"; }

# ── Lock management ───────────────────────────────────────────
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Backup already running (PID: $lock_pid)"
            exit 1
        fi
        log_warn "Removing stale lock"
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

# ── Notification ──────────────────────────────────────────────
notify() {
    local status="$1"
    local message="$2"
    log_info "Notification: [$status] $message"

    if [[ -n "$NOTIFY_WEBHOOK" ]]; then
        local emoji="✅"
        [[ "$status" == "FAILURE" ]] && emoji="🚨"
        curl -sf -X POST "$NOTIFY_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$emoji *Backup $status* on $(hostname): $message\"}" \
            2>/dev/null || log_warn "Webhook notification failed"
    fi
}

# ── Cleanup ───────────────────────────────────────────────────
BACKUP_STATS=(0 0)  # (success, failed)

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    log_info "Cleanup complete (exit: $exit_code)"
    if [[ $exit_code -ne 0 ]]; then
        notify "FAILURE" "Backup failed with exit code $exit_code"
    fi
}
trap cleanup EXIT
trap 'log_error "Interrupted"; exit 130' INT TERM

# ── Backup a directory ────────────────────────────────────────
backup_directory() {
    local source_dir="$1"
    local dir_name
    dir_name=$(echo "$source_dir" | tr '/' '_' | sed 's/^_//')
    local backup_name="${dir_name}_${TIMESTAMP}.tar.gz"
    local backup_path="${BACKUP_ROOT}/${backup_name}"
    local checksum_file="${backup_path}.${CHECKSUM_ALGO}"

    log_info "Backing up: $source_dir → $backup_path"

    if [[ ! -d "$source_dir" ]]; then
        log_warn "Source directory not found: $source_dir (skipping)"
        return 0
    fi

    # Create backup:
    if tar czf "$backup_path" \
        --exclude="*.pyc" \
        --exclude="__pycache__" \
        --exclude=".git" \
        "$source_dir" 2>/dev/null; then

        # Create checksum:
        ${CHECKSUM_ALGO}sum "$backup_path" > "$checksum_file"

        local size
        size=$(du -sh "$backup_path" | cut -f1)
        log_ok "Backup created: $backup_name ($size)"
        ((BACKUP_STATS[0]++))
        return 0
    else
        log_error "Backup FAILED: $source_dir"
        rm -f "$backup_path"
        ((BACKUP_STATS[1]++))
        return 1
    fi
}

# ── Verify backups ────────────────────────────────────────────
verify_backups() {
    log_info "Verifying recent backups..."
    local verified=0
    local failed=0

    while IFS= read -r checksum_file; do
        backup_file="${checksum_file%.${CHECKSUM_ALGO}}"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Backup file missing: $backup_file"
            ((failed++))
            continue
        fi

        if ${CHECKSUM_ALGO}sum -c "$checksum_file" &>/dev/null; then
            log_ok "Verified: $(basename $backup_file)"
            ((verified++))
        else
            log_error "Checksum FAILED: $(basename $backup_file)"
            ((failed++))
        fi
    done < <(find "$BACKUP_ROOT" -name "*.${CHECKSUM_ALGO}" \
        -newer "$LOCK_FILE" 2>/dev/null)

    log_info "Verification: $verified passed, $failed failed"
    return $failed
}

# ── Apply retention policy ────────────────────────────────────
apply_retention() {
    log_info "Applying retention policy: ${BACKUP_RETENTION_DAYS} days"

    local count=0
    while IFS= read -r old_backup; do
        rm -f "$old_backup" "${old_backup}.${CHECKSUM_ALGO}"
        log_info "Removed old backup: $(basename "$old_backup")"
        ((count++))
    done < <(find "$BACKUP_ROOT" \
        -name "*.tar.gz" \
        -mtime +"$BACKUP_RETENTION_DAYS" \
        2>/dev/null)

    log_info "Retention cleanup: removed $count old backup(s)"
}

# ── Rotate logs ───────────────────────────────────────────────
rotate_logs() {
    local max_size_mb="${1:-100}"
    log_info "Checking logs for rotation (max: ${max_size_mb}MB)"

    while IFS= read -r logfile; do
        local size_mb
        size_mb=$(du -m "$logfile" | cut -f1)
        if [[ $size_mb -ge $max_size_mb ]]; then
            local rotated="${logfile}.${TIMESTAMP}.gz"
            gzip -c "$logfile" > "$rotated"
            : > "$logfile"    # truncate (not delete — process may have it open)
            log_ok "Rotated: $logfile → $(basename $rotated) (${size_mb}MB)"
        fi
    done < <(find /var/log -name "*.log" -size +"${max_size_mb}M" 2>/dev/null \
        | grep -v "$LOG_FILE")
}

# ── Generate report ───────────────────────────────────────────
generate_report() {
    cat << EOF

════════════════════════════════════════════════
  BACKUP MANAGER REPORT
  $(date)
  Host: $(hostname -f)
════════════════════════════════════════════════

Backup Results:
  Successful: ${BACKUP_STATS[0]}
  Failed:     ${BACKUP_STATS[1]}

Backup Storage:
$(du -sh "${BACKUP_ROOT}"/* 2>/dev/null | sort -rh | head -10 | \
    awk '{printf "  %-10s %s\n", $1, $2}')

Total backup storage used:
  $(du -sh "${BACKUP_ROOT}" 2>/dev/null | cut -f1)

════════════════════════════════════════════════
EOF
}

# ── Main ──────────────────────────────────────────────────────
main() {
    log_info "Starting backup manager v${SCRIPT_VERSION}"
    log_info "Backup root: ${BACKUP_ROOT}"

    # Setup
    acquire_lock
    mkdir -p "$BACKUP_ROOT"

    # Backup directories
    log_info "=== Backing up directories ==="
    for dir in "${BACKUP_DIRS[@]}"; do
        backup_directory "$dir" || true  # continue on failure
    done

    # Verify
    log_info "=== Verifying backups ==="
    verify_backups || log_warn "Some verifications failed"

    # Retention
    log_info "=== Applying retention ==="
    apply_retention

    # Log rotation
    log_info "=== Rotating logs ==="
    rotate_logs 100

    # Report
    generate_report | tee -a "$LOG_FILE"

    # Notification
    local success="${BACKUP_STATS[0]}"
    local failed="${BACKUP_STATS[1]}"
    if [[ $failed -eq 0 ]]; then
        notify "SUCCESS" "$success backup(s) completed successfully"
        log_info "Backup manager completed successfully"
    else
        notify "PARTIAL" "$success succeeded, $failed failed"
        log_warn "Backup manager completed with $failed failure(s)"
        exit 1
    fi
}

main "$@"
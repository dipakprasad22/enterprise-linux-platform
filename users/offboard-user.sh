#!/bin/bash
# Secure user offboarding — preserves data for compliance
set -euo pipefail

USERNAME="$1"
REASON="${2:-departed}"
LOG="/var/log/user-offboarding.log"
ARCHIVE_DIR="/archive/users"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

id "$USERNAME" &>/dev/null || { log "ERROR: User $USERNAME does not exist"; exit 1; }

log "Offboarding user: $USERNAME (Reason: $REASON)"

# Step 1: Immediately lock account
passwd -l "$USERNAME"
usermod -s /sbin/nologin "$USERNAME"
log "Account locked and shell removed"

# Step 2: Kill active sessions
pkill -u "$USERNAME" 2>/dev/null && log "Active sessions terminated" || true

# Step 3: Archive home directory
mkdir -p "$ARCHIVE_DIR"
ARCHIVE="$ARCHIVE_DIR/${USERNAME}-$(date +%Y%m%d).tar.gz"
tar czf "$ARCHIVE" /home/"$USERNAME"/ 2>/dev/null
chmod 400 "$ARCHIVE"    # read-only archive
log "Home directory archived to: $ARCHIVE"

# Step 4: Find and document all owned files
find / -xdev -user "$USERNAME" 2>/dev/null | \
    tee "/var/log/offboard-${USERNAME}-files.txt"
log "Owned files documented"

# Step 5: Remove cron jobs
crontab -r -u "$USERNAME" 2>/dev/null && \
    log "Cron jobs removed" || log "No cron jobs found"

# Step 6: Remove SSH keys from authorized_keys on this server
# (In enterprise: centralized SSH CA handles this automatically)
> /home/"$USERNAME"/.ssh/authorized_keys
log "SSH authorized_keys cleared"

# Step 7: Final report
log "Offboarding complete for $USERNAME"
log "Archive: $ARCHIVE"
log "Files list: /var/log/offboard-${USERNAME}-files.txt"
log "NEXT STEPS: Remove from AD groups, revoke VPN, disable email"
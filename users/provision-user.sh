#!/bin/bash
# enterprise-user-provision.sh
# Provision a new user following enterprise security standards

set -euo pipefail

# Usage: ./enterprise-user-provision.sh username "Full Name" role
# Roles: devops, developer, readonly, dba

USERNAME="$1"
FULLNAME="$2"
ROLE="$3"
LOG="/var/log/user-provisioning.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# Validate inputs
[[ "$USERNAME" =~ ^[a-z][a-z0-9_-]{2,31}$ ]] || \
    { log "ERROR: Invalid username format"; exit 1; }
id "$USERNAME" &>/dev/null && \
    { log "ERROR: User $USERNAME already exists"; exit 1; }

log "Provisioning user: $USERNAME ($FULLNAME) with role: $ROLE"

# Create user
useradd -m \
        -s /bin/bash \
        -c "$FULLNAME" \
        "$USERNAME"

# Assign groups based on role
case "$ROLE" in
    devops)
        usermod -aG devops-team,developers,wheel "$USERNAME"
        log "Added to groups: devops-team, developers, wheel"
        ;;
    developer)
        usermod -aG developers,dev-team "$USERNAME"
        log "Added to groups: developers, dev-team"
        ;;
    dba)
        usermod -aG dba-team "$USERNAME"
        log "Added to groups: dba-team"
        ;;
    readonly)
        usermod -aG readonly "$USERNAME"
        log "Added to groups: readonly"
        ;;
    *)
        log "ERROR: Unknown role $ROLE"
        userdel -r "$USERNAME"
        exit 1
        ;;
esac

# Set secure temporary password
TEMP_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
echo "$USERNAME:$TEMP_PASS" | chpasswd
chage -d 0 "$USERNAME"    # force change at first login

# Set password policy
chage -M 90 "$USERNAME"   # max 90 days (PCI-DSS)
chage -W 14 "$USERNAME"   # warn 14 days before
chage -I 7  "$USERNAME"   # lock 7 days after expiry

# Set up SSH directory
mkdir -p /home/"$USERNAME"/.ssh
chmod 700 /home/"$USERNAME"/.ssh
touch /home/"$USERNAME"/.ssh/authorized_keys
chmod 600 /home/"$USERNAME"/.ssh/authorized_keys
chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"/.ssh

# Set secure shell config (custom PS1, aliases, security)
cat > /home/"$USERNAME"/.bash_profile << 'BASHEOF'
# Enterprise bash profile
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "    # timestamp every command
export HISTCONTROL=ignoredups
shopt -s histappend               # append to history, never overwrite
PROMPT_COMMAND='history -a'       # write history after every command
alias ll='ls -alF'
alias grep='grep --color=auto'
umask 027
BASHEOF

chown "$USERNAME":"$USERNAME" /home/"$USERNAME"/.bash_profile

log "User $USERNAME provisioned successfully"
log "Temporary password: $TEMP_PASS (communicate via secure channel)"
log "User must change password at next login"
log ""
log "Summary:"
log "  Username: $USERNAME"
log "  Full Name: $FULLNAME"
log "  Role: $ROLE"
log "  Groups: $(id $USERNAME)"
log "  Home: /home/$USERNAME"
log "  Password expires: 90 days"
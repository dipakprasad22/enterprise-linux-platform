#!/bin/bash
# linux-user-security-audit.sh
# Produces a security audit report of user accounts and permissions

set -euo pipefail
REPORT="/var/log/security-audit-$(date +%Y%m%d).txt"

header() { echo -e "\n╔══════════════════════════════════╗"; \
           echo "║ $* ║"; \
           echo -e "╚══════════════════════════════════╝"; }

{
echo "LINUX USER SECURITY AUDIT REPORT"
echo "Generated: $(date)"
echo "Hostname: $(hostname -f)"
echo "Auditor: $(whoami)"

header "ACCOUNTS WITH LOGIN SHELLS"
grep -v -e '/nologin' -e '/false' /etc/passwd | \
    awk -F: '{print $1, "UID:"$3, "Shell:"$7}'

header "UID 0 ACCOUNTS (CRITICAL — only root expected)"
awk -F: '$3 == 0 {print "ALERT: " $1 " has UID 0"}' /etc/passwd

header "ACCOUNTS WITH EMPTY PASSWORDS"
awk -F: '$2 == "" {print "CRITICAL: " $1 " has no password"}' /etc/passwd \
    || echo "None found (good)"

header "LOCKED ACCOUNTS"
awk -F: '$2 ~ /^!/ {print $1 " is locked"}' /etc/shadow

header "PASSWORD AGING — ACCOUNTS EXPIRING WITHIN 30 DAYS"
while IFS=: read -r user pass last min max warn; do
    [ "$max" == "" ] || [ "$max" -eq 99999 ] && continue
    [ "$last" == "" ] && continue
    days_left=$(( last + max - $(date +%s)/86400 ))
    [ "$days_left" -le 30 ] 2>/dev/null && \
        echo "$user: expires in $days_left days"
done < /etc/shadow

header "SUDO ACCESS — USERS WITH FULL SUDO"
grep -r "ALL.*ALL.*ALL" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | \
    grep -v "^#\|^%"

header "SUID BINARIES (REVIEW FOR UNEXPECTED ENTRIES)"
find /usr/bin /usr/sbin /bin /sbin -perm -4000 -ls 2>/dev/null | \
    awk '{print $NF, "owner:"$(5)}'

header "WORLD-WRITABLE FILES (EXCLUDING /tmp AND /proc)"
find / -xdev -perm -0002 -not -path "/tmp/*" \
       -not -path "/proc/*" \
       -not -path "/sys/*" \
       -type f -ls 2>/dev/null | head -20

header "SSH AUTHORIZED KEYS SUMMARY"
for home in /home/* /root; do
    keyfile="$home/.ssh/authorized_keys"
    [ -f "$keyfile" ] || continue
    user=$(basename "$home")
    count=$(grep -c "^ssh-\|^ecdsa\|^sk-" "$keyfile" 2>/dev/null || echo 0)
    perms=$(stat -c "%a" "$keyfile")
    [ "$perms" != "600" ] && flag="⚠ WRONG PERMISSIONS" || flag="OK"
    echo "$user: $count key(s) | permissions: $perms $flag"
done

header "RECENT AUTH FAILURES (LAST 24H)"
journalctl --since "24 hours ago" --no-pager 2>/dev/null | \
    grep -i "failed password\|authentication failure" | \
    awk '{print $1,$2,$3,$11,$13}' | sort | uniq -c | sort -rn | head -10

header "AUDIT COMPLETE"
echo "Full report: $REPORT"
} | tee "$REPORT"
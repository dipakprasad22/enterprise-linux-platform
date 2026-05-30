# Enterprise Backup and Log Rotation System

A professional automation utility for enterprise Linux environments, designed to manage backups, log rotation, retention, and alerting consistently.

## Overview

This directory contains the `backup-manager.sh` script, which is designed to:

- Back up directories and databases using configurable targets
- Enforce retention policies and remove outdated snapshots
- Compress backup data and verify integrity with checksums
- Rotate and archive logs automatically
- Validate backups to ensure recoverability
- Send notifications on failure via email or webhook

## Features

- Configurable backup targets for directories and databases
- Retention policy support for automatic cleanup
- Compression and checksum verification
- Automated log rotation and archival
- Backup validation and recovery checks
- Notification support for failures

## Deploy as a systemd timer

### Install
```bash
mkdir -p /opt/enterprise-linux-platform/automation
cp backup-manager.sh /opt/enterprise-linux-platform/automation/
chmod +x /opt/enterprise-linux-platform/automation/backup-manager.sh
mkdir -p /backup
```

### Test
```bash
BACKUP_ROOT=/tmp/test-backup \
    /opt/enterprise-linux-platform/automation/backup-manager.sh
ls /tmp/test-backup/
```

### Create daily backup timer
```bash
cat > /etc/systemd/system/backup-manager.timer << 'EOF'
[Unit]
Description=Daily Backup Timer

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/backup-manager.service << 'EOF'
[Unit]
Description=Enterprise Backup Manager
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/enterprise-linux-platform/automation/backup-manager.sh
StandardOutput=journal
SyslogIdentifier=backup-manager
EOF
```
```bash
systemctl daemon-reload
systemctl enable backup-manager.timer
```
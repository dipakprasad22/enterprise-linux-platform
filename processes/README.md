# Enterprise Process Monitor and Auto-Remediation Tool

A lightweight, systemd-driven process monitoring utility for enterprise Linux environments.

## Overview

This tool monitors critical processes and performs automatic remediation when issues are detected. It also identifies high CPU usage, zombie processes, and OOM events for proactive system health management.

## Key features

- Monitor essential services and restart them if they are not running
- Detect processes with elevated CPU usage and log alerts
- Identify and clean up zombie processes
- Inspect kernel logs for OOM kill events
- Maintain baseline resource usage metrics per monitored process

## Installation

1. Create the deployment directory:

   mkdir -p /opt/enterprise-linux-platform/processes

2. Copy the monitor script:

   cp process-monitor.sh /opt/enterprise-linux-platform/processes/

3. Make the script executable:

   chmod +x /opt/enterprise-linux-platform/processes/process-monitor.sh

## Systemd integration

Create the following systemd service unit:

cat > /etc/systemd/system/process-monitor.service << 'EOF'
[Unit]
Description=Enterprise Process Health Monitor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/enterprise-linux-platform/processes/process-monitor.sh check
StandardOutput=journal
SyslogIdentifier=process-monitor
EOF

Create the timer unit to run the monitor every 5 minutes:

cat > /etc/systemd/system/process-monitor.timer << 'EOF'
[Unit]
Description=Run Enterprise Process Monitor every 5 minutes

[Timer]
OnBootSec=60s
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

Reload systemd and enable the timer:

systemctl daemon-reload
systemctl enable --now process-monitor.timer

## Validation

Run the report mode to confirm the installation:

/opt/enterprise-linux-platform/processes/process-monitor.sh report

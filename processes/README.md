# Enterprise Process Monitor and Auto-Remediation Tool

A lightweight, systemd-driven process monitoring solution for enterprise Linux environments.

## Overview

This utility monitors essential services and performs automated remediation when failures are detected. It also detects elevated CPU usage, zombie processes, and OOM kill events to support proactive system health management.

## Features

- Monitor critical services and restart them when they are not running
- Detect processes with high CPU usage and log alerts
- Identify zombie processes and support cleanup
- Inspect kernel logs for OOM kill events
- Maintain baseline resource usage metrics for monitored processes

## Installation

1. Create the deployment directory:

   ```bash
   mkdir -p /opt/enterprise-linux-platform/processes
   ```

2. Copy the monitoring script:

   ```bash
   cp process-monitor.sh /opt/enterprise-linux-platform/processes/
   ```

3. Make the script executable:

   ```bash
   chmod +x /opt/enterprise-linux-platform/processes/process-monitor.sh
   ```

## Systemd Integration

Create the systemd service unit:

```bash
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
```

Create the timer unit to run the monitor every 5 minutes:

```bash
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
```

Reload systemd and enable the timer:

```bash
systemctl daemon-reload
systemctl enable --now process-monitor.timer
```

## Validation

Verify installation by running the report mode:

```bash
/opt/enterprise-linux-platform/processes/process-monitor.sh report
```

## Notes

- Adjust monitored services and thresholds in the script as needed for your environment.
- Ensure the service user has appropriate permissions to manage the monitored processes.

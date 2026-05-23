# Enterprise Boot and System Health Analysis Tool

A lightweight shell-based utility to analyze system boot health, generate diagnostics, and provide a concise status report.

## Overview

This tool inspects system boot events, service status, and health indicators. It prints a detailed report to standard output and saves results under `/var/log/boot-health/`.

## Features

- Boot health summary
- Service status checks
- JSON output support
- Quiet mode for reduced output
- Exit codes for automated monitoring

## Usage

```bash
./boot-health-report.sh [--json] [--quiet]
```

## Exit Codes

- `0` - All checks passed
- `1` - Warnings detected
- `2` - Critical issues detected

## Installation

1. Copy the script to `/opt/scripts/`.
2. Make it executable:

```bash
chmod +x /opt/scripts/boot-health-report.sh
```

3. Run the script manually:

```bash
/opt/scripts/boot-health-report.sh
```

4. Verify the exit code:

```bash
echo "Exit code: $?"
```

## Configure Automatic Execution at Boot

Create a systemd service to run the report on every boot:

```bash
cat > /etc/systemd/system/boot-health-report.service << 'EOF'
[Unit]
Description=Boot Health Analysis Report
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/scripts/boot-health-report.sh
StandardOutput=journal
SyslogIdentifier=boot-health

[Install]
WantedBy=multi-user.target
EOF
```

Then enable the service:

```bash
systemctl daemon-reload
systemctl enable boot-health-report.service
```

## Optional Command Shortcut

Create a symbolic link to make the tool available as a system command:

```bash
ln -s /opt/scripts/boot-health-report.sh /usr/local/bin/boot-health-report
```

## Log Location

Reports are written to:

- `/var/log/boot-health/`

## Notes

- Ensure the script has the correct permissions and ownership.
- Confirm the target path `/opt/scripts/` exists before installation.
- Adjust service dependencies if the environment requires a different boot target.

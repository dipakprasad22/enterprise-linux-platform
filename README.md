### Enterprise Boot and System Health Analysis Tool

# Usage: ./boot-health-report.sh [--json] [--quiet]
# Output: Detailed report to stdout and /var/log/boot-health/
# Exit code: 0 = all healthy, 1 = warnings found, 2 = critical issues

# Save the script
chmod +x /opt/scripts/boot-health-report.sh

# Run it
/opt/scripts/boot-health-report.sh

# Check the exit code
echo "Exit code: $?"

# Schedule it to run on every boot:
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

systemctl daemon-reload
systemctl enable boot-health-report.service

# Also make it available as a command:
ln -s /opt/scripts/boot-health-report.sh /usr/local/bin/boot-health-report

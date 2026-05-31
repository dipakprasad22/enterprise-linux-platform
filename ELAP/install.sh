#!/bin/bash
# ELAP Installer
set -euo pipefail

INSTALL_DIR="/opt/enterprise-linux-platform"
echo "Installing ELAP to $INSTALL_DIR..."

# Copy files:
cp -r . "$INSTALL_DIR/"
chmod -R 755 "$INSTALL_DIR/bin/"
chmod 644 "$INSTALL_DIR/lib/"*.sh
chmod 644 "$INSTALL_DIR/config/"*

# Create directories:
mkdir -p /var/log/elap /var/lib/elap/reports /etc/elap /var/run/elap

# Install config:
[[ -f /etc/elap/elap.conf ]] || cp "$INSTALL_DIR/config/elap.conf" /etc/elap/

# Create symlink:
ln -sf "$INSTALL_DIR/bin/elap" /usr/local/bin/elap

# Install systemd units:
cp "$INSTALL_DIR/systemd/"* /etc/systemd/system/
systemctl daemon-reload
systemctl enable elap-backup.timer elap-compliance.timer
systemctl start  elap-backup.timer elap-compliance.timer

# Write version:
echo "1.0.0" > "$INSTALL_DIR/VERSION"

echo ""
echo "ELAP installed successfully"
echo "Run: elap status"

# Enterprise LVM Storage Management

Elegant, minimal, and production-ready tooling for managing LVM on enterprise Linux systems.

## Overview

This repository contains lvm-manager.sh — a lightweight shell utility to:

- Generate storage health reports
- Automatically expand logical volumes when thresholds are exceeded
- Create snapshots for backups
- Clean up old snapshots

## Installation

Install to /opt and make executable:

mkdir -p /opt/enterprise-linux-platform/storage
cp lvm-manager.sh /opt/enterprise-linux-platform/storage/
chmod +x /opt/enterprise-linux-platform/storage/lvm-manager.sh

# Run the report:
/opt/enterprise-linux-platform/storage/lvm-manager.sh report

# Schedule automated checks every 15 minutes:
echo "*/15 * * * * root /opt/enterprise-linux-platform/storage/lvm-manager.sh check" \
    > /etc/cron.d/lvm-manager
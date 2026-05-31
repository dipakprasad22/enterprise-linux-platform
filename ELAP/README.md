# Enterprise Linux Automation Platform (ELAP)

A production-grade Linux server management platform built entirely in bash, implementing enterprise operations workflows across provisioning, security hardening, monitoring, storage management, and compliance reporting.

## What This Platform Does

ELAP automates the complete lifecycle of Linux server management:

| Capability | What It Does |
|---|---|
| **Provision** | Configures new servers with enterprise defaults — limits, kernel params, services |
| **Harden** | Applies CIS Level 1 benchmark controls — 30+ security checks and remediations |
| **Monitor** | Continuous health monitoring — CPU, memory, disk, services, security events |
| **Storage** | LVM volume management — auto-expansion, snapshots, backup with verification |
| **Network** | Layer-by-layer network diagnostics and firewall auditing |
| **Users** | Enterprise user lifecycle — provisioning, offboarding, access auditing |
| **Performance** | System baseline collection, bottleneck identification, kernel tuning |
| **Report** | Comprehensive HTML reports with colour-coded status for all platform areas |

## Architecture
bin/
├── elap              # Main CLI orchestrator — single entry point
├── elap-status       # Quick platform health overview
├── elap-provision    # Server provisioning component
├── elap-harden       # CIS security hardening component
├── elap-monitor      # Health monitoring component
├── elap-storage      # Storage management component
├── elap-network      # Network diagnostics component
├── elap-users        # User lifecycle component
├── elap-performance  # Performance baseline component
└── elap-report       # HTML report generator
lib/
└── common.sh         # Shared library: logging, locking, retry, notifications
config/
├── elap.conf         # Default configuration (all thresholds configurable)
└── server-inventory.txt
systemd/
├── elap-monitor.service     # Continuous monitoring daemon
├── elap-backup.timer/.service    # Daily backups at 2am
└── elap-compliance.timer/.service # Daily CIS audit at 6am
tests/
└── test-elap.sh      # Full test suite (syntax + unit tests)

## Installation

```bash
git clone https://github.com/dipakprasad22/enterprise-linux-platform
cd enterprise-linux-platform
sudo bash install.sh
```

## Usage

```bash
# Quick health overview:
elap status

# Provision a new server:
elap provision --hostname web01.prod --env production --role web

# Apply CIS Level 1 hardening:
elap harden --level 1

# Audit security compliance (no changes):
elap harden --audit

# Run health check:
elap monitor --once

# Generate HTML report:
elap report --format html

# Storage health and expansion:
elap storage --report
elap storage --expand

# Performance baseline:
elap performance --baseline
elap performance --tune

# Dry-run mode (simulate without changes):
ELAP_DRY_RUN=true elap harden --level 1
```

## Design Principles

**Idempotent** — Every operation produces the same result when run multiple times.
No duplicate entries, no conflicting changes, safe to run repeatedly.

**Observable** — Every action is logged with timestamp, component, and result.
Logs ship to journald automatically when running as a systemd service.

**Safe** — All scripts use `set -euo pipefail`. Lock files prevent concurrent
execution. Dry-run mode available for every operation. Backups created before changes.

**Testable** — Complete test suite validates structure, syntax, and core library
functions. Run with `bash tests/test-elap.sh`.

## Technologies Demonstrated

- Advanced bash scripting with error handling, traps, and parallel execution
- Linux process management via systemd unit files, timers, and cgroups
- Storage management via LVM — online expansion, snapshots, automated backup
- Network diagnostics at each OSI layer
- Security hardening against CIS Linux Benchmark Level 1
- SELinux policy validation and auditd rule management
- Performance analysis using iostat, vmstat, sar, and /proc
- PAM and sudoers configuration for enterprise access control

## Target Environments

Tested on: RHEL 8/9, CentOS Stream 8/9, Ubuntu 20.04 LTS, Ubuntu 22.04 LTS,
Amazon Linux 2, Amazon Linux 2023

## Author

Dipak Prasad — Senior Infrastructure Engineer

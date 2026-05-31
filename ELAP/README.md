# Enterprise Linux Automation Platform (ELAP)

A production-grade Linux server management platform implemented in Bash, automating the complete operational lifecycle across provisioning, security hardening, health monitoring, storage management, and compliance reporting.

---

## Table of Contents

- [Overview](#overview)
- [Capabilities](#capabilities)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Design Principles](#design-principles)
- [Technologies](#technologies)
- [Supported Platforms](#supported-platforms)
- [Author](#author)

---

## Overview

ELAP provides a unified CLI interface for managing Linux infrastructure at scale. Each operational domain — provisioning, hardening, monitoring, storage, networking, user management, and performance analysis — is encapsulated in a discrete, testable component. All components share a common library for logging, locking, retry logic, and alerting, ensuring consistent behavior across the platform.

---

## Capabilities

| Module | Description |
|---|---|
| **Provision** | Configures new servers with enterprise defaults — system limits, kernel parameters, and service baselines |
| **Harden** | Applies CIS Benchmark Level 1 controls — 30+ automated security checks and remediations |
| **Monitor** | Continuous health monitoring across CPU, memory, disk, running services, and security events |
| **Storage** | LVM volume management including auto-expansion, snapshot creation, and verified backups |
| **Network** | Layer-by-layer network diagnostics and firewall policy auditing |
| **Users** | Enterprise user lifecycle management — provisioning, offboarding, and access auditing |
| **Performance** | System baseline collection, bottleneck identification, and kernel tuning recommendations |
| **Report** | Comprehensive HTML compliance and health reports with colour-coded status indicators |

---

## Architecture

```
enterprise-linux-platform/
├── bin/
│   ├── elap                    # Main CLI orchestrator — single entry point
│   ├── elap-status             # Quick platform health overview
│   ├── elap-provision          # Server provisioning component
│   ├── elap-harden             # CIS security hardening component
│   ├── elap-monitor            # Health monitoring component
│   ├── elap-storage            # Storage management component
│   ├── elap-network            # Network diagnostics component
│   ├── elap-users              # User lifecycle component
│   ├── elap-performance        # Performance baseline component
│   └── elap-report             # HTML report generator
├── lib/
│   └── common.sh               # Shared library: logging, locking, retry, notifications
├── config/
│   ├── elap.conf               # Platform configuration (all thresholds tunable)
│   └── server-inventory.txt    # Managed server inventory
├── systemd/
│   ├── elap-monitor.service              # Continuous monitoring daemon
│   ├── elap-backup.timer / .service      # Daily backup job (2:00 AM)
│   └── elap-compliance.timer / .service  # Daily CIS audit job (6:00 AM)
└── tests/
    └── test-elap.sh            # Full test suite — syntax validation and unit tests
```

---

## Prerequisites

- Linux distribution from the [Supported Platforms](#supported-platforms) list
- `bash` 4.0 or later
- Root or `sudo` access on the target host
- `git` (for installation from source)
- Optional: `lvm2` (storage module), `systemd` (daemon/timer features)

---

## Installation

```bash
git clone https://github.com/dipakprasad22/enterprise-linux-platform
cd enterprise-linux-platform
sudo bash install.sh
```

The installer copies binaries to `/usr/local/bin`, installs the shared library and configuration files, and optionally enables the systemd units for continuous monitoring and scheduled compliance audits.

---

## Usage

```bash
# Platform health overview
elap status

# Provision a new server
elap provision --hostname web01.prod --env production --role web

# Apply CIS Level 1 security hardening
elap harden --level 1

# Audit security compliance without making changes
elap harden --audit

# Run a one-time health check
elap monitor --once

# Generate an HTML compliance and health report
elap report --format html

# Storage health report and automatic volume expansion
elap storage --report
elap storage --expand

# Collect a performance baseline and apply kernel tuning
elap performance --baseline
elap performance --tune

# Dry-run mode — simulate all changes without applying them
ELAP_DRY_RUN=true elap harden --level 1
```

---

## Design Principles

**Idempotent** — Every operation produces the same outcome regardless of how many times it is executed. No duplicate entries, no conflicting changes; operations are safe to run repeatedly as part of automated pipelines.

**Observable** — Every action is recorded with a timestamp, component name, and result code. When running as a systemd service, logs are forwarded automatically to `journald` for centralized collection.

**Safe** — All scripts enforce `set -euo pipefail`. Exclusive lock files prevent concurrent execution of the same operation. Dry-run mode is available for every module. Backups are created automatically before any destructive change is applied.

**Testable** — A complete test suite validates script structure, syntax correctness, and core library functions. Execute with:

```bash
bash tests/test-elap.sh
```

---

## Technologies

- Advanced Bash scripting — error handling, signal traps, and parallel execution
- Linux process management via systemd unit files, timers, and cgroups
- LVM storage management — online volume expansion, snapshots, and automated backup with verification
- Network diagnostics across OSI layers using standard Linux tooling
- Security hardening aligned to the CIS Linux Benchmark Level 1
- SELinux policy validation and `auditd` rule management
- Performance analysis using `iostat`, `vmstat`, `sar`, and `/proc` interfaces
- PAM and `sudoers` configuration for enterprise access control

---

## Supported Platforms

| Distribution | Versions |
|---|---|
| Red Hat Enterprise Linux | 8, 9 |
| CentOS Stream | 8, 9 |
| Ubuntu LTS | 20.04, 22.04 |
| Amazon Linux | 2, 2023 |

---

## Author

**Dipak Prasad** — Senior Infrastructure Engineer

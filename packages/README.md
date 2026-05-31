# Package Audit

Enterprise package inventory and integrity audit tooling for Linux systems.

## Overview

`package-audit.sh` provides a comprehensive audit of the local package environment. It is designed for use in enterprise Linux environments where package hygiene, compliance, and security posture must be tracked and reported consistently.

## Features

- **Package Inventory** — Lists all installed packages with versions and disk sizes
- **Integrity Verification** — Detects tampered or corrupted binaries using package manager checksums
- **Update Reporting** — Separates pending updates into security fixes and general updates
- **Repository Audit** — Reviews enabled repository configuration for unexpected or misconfigured sources
- **Orphan Detection** — Identifies packages with no reverse dependencies
- **Locked Package Detection** — Reports packages held back from updates
- **Dual Output Formats** — Produces both JSON (machine-readable) and human-readable plain text reports

## Usage

```bash
bash package-audit.sh [options]
```

See `package-audit.sh --help` for available options.

## Output

Reports are written to the current directory by default. JSON output is suitable for ingestion into SIEM, CMDB, or compliance tooling.

## Part Of

[enterprise-linux-platform](../README.md) — a collection of hardened automation scripts for enterprise Linux administration.

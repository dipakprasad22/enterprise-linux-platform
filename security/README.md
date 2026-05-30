# Enterprise CIS Benchmark Hardening Tool

A lightweight hardening utility for Enterprise Linux systems that supports audit, remediation, and reporting workflows.

## Overview

This tool is part of the `enterprise-linux-platform` project and provides a simple script-based interface to validate CIS compliance, apply selected hardening controls, and generate compliance reports.

## Modes:
-  audit   = check compliance, do not change anything
- harden  = apply hardening controls
-   report  = generate compliance report

## Usage:
- ./cis-hardening.sh audit         # check only
-  ./cis-hardening.sh harden        # apply hardening
-  DRY_RUN=true ./cis-hardening.sh harden  # simulate

## Deploy it
```bash
mkdir -p /opt/enterprise-linux-platform/security
cp cis-hardening.sh /opt/enterprise-linux-platform/security/
chmod +x /opt/enterprise-linux-platform/security/cis-hardening.sh
```
## Run audit (check only):
```bash
/opt/enterprise-linux-platform/security/cis-hardening.sh audit
```
## Run dry-run hardening (simulate):
```bash
DRY_RUN=true \
    /opt/enterprise-linux-platform/security/cis-hardening.sh harden
```
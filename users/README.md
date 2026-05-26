# Enterprise User Provisioning & Security Audit

A concise, professional toolkit for managing Linux user lifecycles and performing security audits across enterprise systems. The repository focuses on automation, repeatability, and auditability to help operations and security teams maintain consistent user management and compliance.

## Overview

- Automated user provisioning, onboarding and offboarding for Linux systems
- Periodic and on-demand security auditing of user accounts and SSH access
- Clear logging and exit codes for integration with higher-level automation (Ansible, Terraform, CI/CD)

## Included scripts

- users/provision-user.sh — Create and configure user accounts, set home directories, SSH keys, groups, and default permissions.
- users/security-audit.sh — Run checks for weak SSH settings, orphaned accounts, sudoers review, password expiry, and report findings in a concise format.
- users/offboard-user.sh — Disable or remove accounts, archive home directories, revoke SSH keys, and rotate any associated access credentials.

## Usage

1. Review and customize variables inside each script to match your environment (group names, home base path, audit thresholds).
2. Execute with appropriate privileges (typically run as root or via sudo):

	sudo bash users/provision-user.sh --help

3. Integrate scripts into automation pipelines or scheduled jobs for continuous enforcement.

## Security & Best Practices

- Always test scripts in a staging environment before production.
- Use centralized secret management for any credentials.
- Log all automation actions and retain logs per organizational policy.


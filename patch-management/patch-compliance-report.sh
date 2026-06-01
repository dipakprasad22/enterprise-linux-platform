#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Enterprise Linux Patch Compliance Report
#
# Generates an HTML patch compliance report for a server:
#   - Compliance status (compliant / non-compliant / reboot pending)
#   - Pending security patch count and reboot requirement
#   - Enterprise patch SLA policy table (CVSS -> remediation time)
#   - List of pending security packages
#   - Remediation commands appropriate to the package manager
#
# Cross-platform: yum, dnf, apt
# Exit code: 0 if compliant, 1 if non-compliant (for monitoring)
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

REPORT_DIR="${REPORT_DIR:-/var/lib/elap/reports/patch}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="${REPORT_DIR}/patch-compliance-${TIMESTAMP}.html"
LOG="${LOG:-/var/log/elap/patch-compliance.log}"

# Fall back to /tmp if the standard dirs are not writable
mkdir -p "$REPORT_DIR" 2>/dev/null || { REPORT_DIR="/tmp"; REPORT="/tmp/patch-compliance-${TIMESTAMP}.html"; }
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG="/tmp/patch-compliance.log"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

# ── Detect package manager ────────────────────────────────────
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
elif command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
else
    echo "No supported package manager found (need yum, dnf, or apt)" >&2
    exit 2
fi

# ── Collect patch data ────────────────────────────────────────
collect_patch_status() {
    local hostname os kernel last_update security_count pending_reboot
    hostname=$(hostname -f 2>/dev/null || hostname)
    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    kernel=$(uname -r)
    security_count=0
    pending_reboot="No"

    case "$PKG_MGR" in
        dnf|yum)
            security_count=$($PKG_MGR check-update --security -q 2>/dev/null | grep -c '^[a-zA-Z]' || true)
            last_update=$(rpm -qa --last 2>/dev/null | head -1 | awk '{print $(NF-1), $NF}')
            # needs-restarting returns non-zero when a reboot is required
            if command -v needs-restarting &>/dev/null; then
                needs-restarting -r &>/dev/null || pending_reboot="Yes"
            fi
            ;;
        apt)
            apt-get update -qq 2>/dev/null || true
            security_count=$(apt list --upgradable 2>/dev/null | grep -c -i security || true)
            last_update=$(ls -lt /var/cache/apt/archives/*.deb 2>/dev/null | head -1 | awk '{print $6,$7,$8}')
            [[ -f /var/run/reboot-required ]] && pending_reboot="Yes"
            ;;
    esac

    # Default values if anything came back empty
    : "${security_count:=0}"
    : "${last_update:=Unknown}"

    # Determine compliance status
    local status status_color
    status="COMPLIANT"
    status_color="#22c55e"
    if [[ "${security_count:-0}" -gt 0 ]]; then
        status="NON-COMPLIANT"
        status_color="#ef4444"
    fi
    if [[ "$pending_reboot" == "Yes" ]]; then
        [[ "$status" == "COMPLIANT" ]] && status="REBOOT PENDING"
        status_color="#f59e0b"
    fi

    cat << EOF
hostname=$hostname
os=$os
kernel=$kernel
security_pending=$security_count
last_update=$last_update
pending_reboot=$pending_reboot
status=$status
status_color=$status_color
EOF
}

log "Collecting patch compliance data (package manager: $PKG_MGR)"
DATA=$(collect_patch_status)

get_field() { echo "$DATA" | grep "^${1}=" | cut -d= -f2-; }

HOSTNAME=$(get_field hostname)
OS=$(get_field os)
KERNEL=$(get_field kernel)
SECURITY_PENDING=$(get_field security_pending)
LAST_UPDATE=$(get_field last_update)
PENDING_REBOOT=$(get_field pending_reboot)
STATUS=$(get_field status)
STATUS_COLOR=$(get_field status_color)

log "Status: $STATUS | Pending security patches: $SECURITY_PENDING"

# ── Generate HTML report ──────────────────────────────────────
cat > "$REPORT" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Patch Compliance Report — $HOSTNAME</title>
<style>
  body { font-family:'Segoe UI',system-ui,sans-serif;
         background:#0f1117; color:#e2e8f0; padding:24px; margin:0; }
  h1   { color:#60a5fa; font-size:22px; margin-bottom:4px; }
  .meta { color:#64748b; font-size:13px; margin-bottom:24px; }
  .status-card { background:#1e293b; border-radius:10px; padding:20px;
                 border-left:5px solid ${STATUS_COLOR}; margin-bottom:20px; }
  .status-label { font-size:12px; color:#64748b; text-transform:uppercase; }
  .status-value { font-size:28px; font-weight:700;
                  color:${STATUS_COLOR}; margin-top:4px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr));
          gap:14px; margin-bottom:20px; }
  .card { background:#1e293b; border-radius:8px; padding:14px; }
  .card-label { font-size:11px; color:#64748b; text-transform:uppercase; }
  .card-value { font-size:18px; font-weight:600; margin-top:4px; }
  .section { background:#1e293b; border-radius:8px; padding:16px; margin-bottom:16px; }
  .section h2 { font-size:14px; color:#94a3b8; margin-bottom:12px; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th { padding:8px; text-align:left; color:#64748b; font-size:11px;
       text-transform:uppercase; background:#0f172a; }
  td { padding:8px; border-bottom:1px solid #0f172a; }
  .sla-table td:nth-child(2) { color:#ef4444; font-weight:600; }
  .sla-table td:nth-child(3) { color:#f97316; font-weight:600; }
  .sla-table td:nth-child(4) { color:#f59e0b; font-weight:600; }
  .sla-table td:nth-child(5) { color:#22c55e; font-weight:600; }
  pre { background:#0f172a; padding:12px; border-radius:6px;
        font-size:12px; overflow-x:auto; color:#94a3b8; }
</style>
</head>
<body>

<h1>Linux Patch Compliance Report</h1>
<div class="meta">
  Generated: $(date) &nbsp;|&nbsp;
  Host: <strong>$HOSTNAME</strong> &nbsp;|&nbsp;
  OS: $OS &nbsp;|&nbsp;
  Kernel: $KERNEL
</div>

<div class="status-card">
  <div class="status-label">Compliance Status</div>
  <div class="status-value">$STATUS</div>
  <div style="color:#94a3b8;margin-top:8px;font-size:13px;">
    $SECURITY_PENDING pending security patches &nbsp;|&nbsp;
    Reboot required: $PENDING_REBOOT &nbsp;|&nbsp;
    Last update: $LAST_UPDATE
  </div>
</div>

<div class="grid">
  <div class="card">
    <div class="card-label">Security Patches Pending</div>
    <div class="card-value" style="color:$([ "${SECURITY_PENDING:-0}" -gt 0 ] && echo '#ef4444' || echo '#22c55e')">
      $SECURITY_PENDING
    </div>
  </div>
  <div class="card">
    <div class="card-label">Reboot Required</div>
    <div class="card-value" style="color:$([ "$PENDING_REBOOT" = "Yes" ] && echo '#f59e0b' || echo '#22c55e')">
      $PENDING_REBOOT
    </div>
  </div>
  <div class="card">
    <div class="card-label">Package Manager</div>
    <div class="card-value">${PKG_MGR^^}</div>
  </div>
  <div class="card">
    <div class="card-label">Last Update</div>
    <div class="card-value" style="font-size:13px;">$LAST_UPDATE</div>
  </div>
</div>

<div class="section">
  <h2>Patch SLA Policy — Enterprise Standard</h2>
  <table class="sla-table">
    <thead>
      <tr>
        <th>Severity</th>
        <th>Critical (CVSS 9-10)</th>
        <th>High (CVSS 7-8.9)</th>
        <th>Medium (CVSS 4-6.9)</th>
        <th>Low (CVSS 0-3.9)</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>SLA Target</td>
        <td>24-48 hours</td>
        <td>7 days</td>
        <td>30 days</td>
        <td>90 days</td>
      </tr>
      <tr>
        <td>Exception authority</td>
        <td>CISO approval</td>
        <td>Manager approval</td>
        <td>Team lead approval</td>
        <td>Self-service</td>
      </tr>
    </tbody>
  </table>
</div>

<div class="section">
  <h2>Pending Security Packages</h2>
  <pre>$(
    case "$PKG_MGR" in
        dnf|yum) $PKG_MGR check-update --security 2>/dev/null | head -30 || echo "System is up to date" ;;
        apt)     apt list --upgradable 2>/dev/null | grep -i security | head -20 || echo "No security updates pending" ;;
    esac
  )</pre>
</div>

<div class="section">
  <h2>Remediation Actions</h2>
  <pre>$(
    if [[ "${SECURITY_PENDING:-0}" -gt 0 ]]; then
        case "$PKG_MGR" in
            dnf|yum)
                echo "# Apply all security patches:"
                echo "sudo $PKG_MGR update --security -y"
                echo ""
                echo "# Check if a reboot is needed after patching:"
                echo "sudo needs-restarting -r"
                ;;
            apt)
                echo "# Apply security patches:"
                echo "sudo apt-get -y upgrade"
                echo ""
                echo "# Check if a reboot is needed:"
                echo "cat /var/run/reboot-required 2>/dev/null"
                ;;
        esac
    else
        echo "No immediate action required."
        echo "Continue scheduled patch maintenance."
    fi
  )</pre>
</div>

<div style="margin-top:24px;padding-top:16px;border-top:1px solid #1e293b;
     font-size:12px;color:#475569;">
  Generated by ELAP Patch Compliance Tool &nbsp;|&nbsp;
  $(date) &nbsp;|&nbsp;
  Report: $REPORT
</div>

</body>
</html>
HTMLEOF

log "Report generated: $REPORT"
echo ""
echo "Patch compliance report: $REPORT"

# Exit non-zero if non-compliant (useful for monitoring/CI)
[[ "$STATUS" == "COMPLIANT" ]] && exit 0 || exit 1
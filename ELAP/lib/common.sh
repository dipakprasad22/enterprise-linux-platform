#!/bin/bash
# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────
# Purpose: Shared functions used by all ELAP components
# ─────────────────────────────────────────────────────────────
cat > lib/common.sh << 'COMMONEOF'
#!/bin/bash
# ELAP Common Library
# Source this in every ELAP script: source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ── Platform constants ────────────────────────────────────────
readonly ELAP_VERSION="1.0.0"
readonly ELAP_HOME="${ELAP_HOME:-/opt/enterprise-linux-platform}"
readonly ELAP_LOG_DIR="${ELAP_LOG_DIR:-/var/log/elap}"
readonly ELAP_DATA_DIR="${ELAP_DATA_DIR:-/var/lib/elap}"
readonly ELAP_LOCK_DIR="${ELAP_LOCK_DIR:-/var/run/elap}"
readonly ELAP_REPORT_DIR="${ELAP_REPORT_DIR:-/var/lib/elap/reports}"

# ── Color codes ───────────────────────────────────────────────
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_PURPLE='\033[0;35m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_NC='\033[0m'

# ── Logging functions ─────────────────────────────────────────
ELAP_LOG_FILE="${ELAP_LOG_DIR}/elap-$(date +%Y%m%d).log"

elap_log() {
    local level="$1"; shift
    local component="${ELAP_COMPONENT:-elap}"
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Always write to log file:
    mkdir -p "$ELAP_LOG_DIR"
    printf '[%s] [%-8s] [%-15s] %s\n' \
        "$timestamp" "$level" "$component" "$message" \
        >> "$ELAP_LOG_FILE"

    # Write to stdout with color based on level:
    case "$level" in
        INFO)    printf "${C_GREEN}[INFO]${C_NC}  %s\n" "$message" ;;
        WARN)    printf "${C_YELLOW}[WARN]${C_NC}  %s\n" "$message" ;;
        ERROR)   printf "${C_RED}[ERROR]${C_NC} %s\n" "$message" >&2 ;;
        DEBUG)   [[ "${ELAP_DEBUG:-false}" == "true" ]] && \
                     printf "${C_CYAN}[DEBUG]${C_NC} %s\n" "$message" ;;
        PASS)    printf "${C_GREEN}[PASS]${C_NC}  %s\n" "$message" ;;
        FAIL)    printf "${C_RED}[FAIL]${C_NC}  %s\n" "$message" ;;
        APPLY)   printf "${C_BLUE}[APPLY]${C_NC} %s\n" "$message" ;;
        SKIP)    printf "${C_YELLOW}[SKIP]${C_NC}  %s\n" "$message" ;;
    esac
}

log_info()  { elap_log "INFO"  "$@"; }
log_warn()  { elap_log "WARN"  "$@"; }
log_error() { elap_log "ERROR" "$@"; }
log_debug() { elap_log "DEBUG" "$@"; }
log_pass()  { elap_log "PASS"  "$@"; }
log_fail()  { elap_log "FAIL"  "$@"; }
log_apply() { elap_log "APPLY" "$@"; }

# ── Error handling ────────────────────────────────────────────
ELAP_TEMP_FILES=()
ELAP_LOCK_FILES=()

elap_cleanup() {
    local exit_code=$?
    log_debug "Cleanup running (exit: $exit_code)"

    # Remove temp files:
    for f in "${ELAP_TEMP_FILES[@]:-}"; do
        [[ -f "$f" ]] && rm -f "$f" && log_debug "Removed temp: $f"
    done

    # Release locks:
    for f in "${ELAP_LOCK_FILES[@]:-}"; do
        [[ -f "$f" ]] && rm -f "$f" && log_debug "Released lock: $f"
    done

    exit "$exit_code"
}

elap_error_handler() {
    local exit_code=$?
    local line_number="${1:-unknown}"
    log_error "Script failed at line $line_number (exit: $exit_code)"
    log_error "Component: ${ELAP_COMPONENT:-unknown}"
}

# Register handlers:
trap 'elap_cleanup' EXIT
trap 'elap_error_handler $LINENO' ERR

# ── Lock management ───────────────────────────────────────────
elap_acquire_lock() {
    local lock_name="$1"
    local lock_file="${ELAP_LOCK_DIR}/${lock_name}.lock"

    mkdir -p "$ELAP_LOCK_DIR"
    ELAP_LOCK_FILES+=("$lock_file")

    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null || echo "0")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Component '$lock_name' already running (PID: $lock_pid)"
            return 1
        fi
        log_warn "Removing stale lock: $lock_file"
    fi

    echo $$ > "$lock_file"
    log_debug "Lock acquired: $lock_name"
}

# ── Retry logic ───────────────────────────────────────────────
elap_retry() {
    local max_attempts="${1}"
    local delay="${2}"
    local description="${3}"
    shift 3

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            log_debug "Succeeded: $description (attempt $attempt)"
            return 0
        fi
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "$description failed (attempt $attempt/$max_attempts) — retrying in ${delay}s"
            sleep "$delay"
        fi
        ((attempt++))
    done

    log_error "$description failed after $max_attempts attempts"
    return 1
}

# ── Validation helpers ────────────────────────────────────────
elap_require_root() {
    [[ "$EUID" -eq 0 ]] || {
        log_error "This operation requires root privileges"
        exit 1
    }
}

elap_require_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null || {
        log_error "Required command not found: $cmd"
        exit 1
    }
}

elap_require_file() {
    local file="$1"
    [[ -f "$file" ]] || {
        log_error "Required file not found: $file"
        exit 1
    }
}

# ── OS detection ──────────────────────────────────────────────
elap_detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        ELAP_OS_ID="${ID:-unknown}"
        ELAP_OS_VERSION="${VERSION_ID:-unknown}"
        ELAP_OS_FAMILY="${ID_LIKE:-$ID}"
    else
        ELAP_OS_ID="unknown"
        ELAP_OS_VERSION="unknown"
        ELAP_OS_FAMILY="unknown"
    fi

    # Determine package manager:
    if command -v dnf &>/dev/null; then
        ELAP_PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
        ELAP_PKG_MGR="yum"
    elif command -v apt-get &>/dev/null; then
        ELAP_PKG_MGR="apt-get"
    else
        ELAP_PKG_MGR="unknown"
    fi

    log_debug "OS: $ELAP_OS_ID $ELAP_OS_VERSION (family: $ELAP_OS_FAMILY, pkg: $ELAP_PKG_MGR)"
}

# ── Dry run wrapper ───────────────────────────────────────────
elap_run() {
    if [[ "${ELAP_DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $*"
        return 0
    fi
    "$@"
}

# ── Notification ──────────────────────────────────────────────
elap_notify() {
    local status="$1"
    local message="$2"
    local webhook="${ELAP_WEBHOOK:-}"

    log_info "Notification [$status]: $message"

    if [[ -n "$webhook" ]]; then
        local emoji="✅"
        [[ "$status" == "ERROR" ]] && emoji="🚨"
        [[ "$status" == "WARN" ]]  && emoji="⚠️"

        curl -sf -X POST "$webhook" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$emoji *ELAP $status* on $(hostname -s): $message\"}" \
            2>/dev/null || log_warn "Webhook notification failed"
    fi
}

# ── Print section header ──────────────────────────────────────
elap_section() {
    echo ""
    printf "${C_BOLD}══ %s ══${C_NC}\n" "$*"
}

elap_banner() {
    echo ""
    printf "${C_BOLD}${C_CYAN}"
    echo "╔══════════════════════════════════════════════╗"
    printf "║  %-44s║\n" "$1"
    printf "║  %-44s║\n" "ELAP v${ELAP_VERSION} | $(hostname -s) | $(date '+%Y-%m-%d %H:%M')"
    echo "╚══════════════════════════════════════════════╝"
    printf "${C_NC}"
}
COMMONEOF

chmod 644 lib/common.sh
echo "✓ lib/common.sh created"
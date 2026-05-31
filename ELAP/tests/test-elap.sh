#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Test suite
# ─────────────────────────────────────────────────────────────
# ELAP Test Suite
set -euo pipefail
ELAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

assert_exit_code() {
    local desc="$1" expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>/dev/null; echo $?)
    actual="${actual##*$'\n'}"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (expected exit $expected, got $actual)"
        ((FAIL++))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -f "$file" ]]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc (missing: $file)"
        ((FAIL++))
    fi
}

assert_executable() {
    local file="$1"
    if [[ -x "$file" ]]; then
        echo "  PASS: $file is executable"
        ((PASS++))
    else
        echo "  FAIL: $file is NOT executable"
        ((FAIL++))
    fi
}

echo "═══════════════════════════════════════"
echo "  ELAP Test Suite"
echo "═══════════════════════════════════════"

echo ""
echo "── File Structure Tests ──"
assert_file_exists "Main CLI"          "$ELAP_HOME/bin/elap"
assert_file_exists "Common library"    "$ELAP_HOME/lib/common.sh"
assert_file_exists "Status command"    "$ELAP_HOME/bin/elap-status"
assert_file_exists "Monitor command"   "$ELAP_HOME/bin/elap-monitor"
assert_file_exists "Provision command" "$ELAP_HOME/bin/elap-provision"
assert_file_exists "Report command"    "$ELAP_HOME/bin/elap-report"
assert_file_exists "Configuration"     "$ELAP_HOME/config/elap.conf"

echo ""
echo "── Executable Tests ──"
for f in "$ELAP_HOME/bin/"elap*; do
    assert_executable "$f"
done

echo ""
echo "── Syntax Tests ──"
for script in "$ELAP_HOME/bin/"* "$ELAP_HOME/lib/"*; do
    [[ -f "$script" ]] && bash -n "$script" && \
        echo "  PASS: syntax OK: $(basename $script)" && ((PASS++)) || \
        { echo "  FAIL: syntax error: $(basename $script)"; ((FAIL++)); }
done

echo ""
echo "── Library Tests ──"
source "$ELAP_HOME/lib/common.sh"

# Test logging:
LOG_OUTPUT=$(log_info "test message" 2>&1)
[[ "$LOG_OUTPUT" == *"test message"* ]] && \
    { echo "  PASS: log_info works"; ((PASS++)); } || \
    { echo "  FAIL: log_info broken"; ((FAIL++)); }

# Test OS detection:
elap_detect_os
[[ -n "${ELAP_PKG_MGR:-}" ]] && \
    { echo "  PASS: OS detection works ($ELAP_PKG_MGR)"; ((PASS++)); } || \
    { echo "  FAIL: OS detection failed"; ((FAIL++)); }

echo ""
echo "═══════════════════════════════════════"
echo "  Results: $PASS passed · $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "  ALL TESTS PASSED" && exit 0 || \
    { echo "  TESTS FAILED"; exit 1; }

# chmod +x tests/test-elap.sh
# echo "✓ tests/test-elap.sh created"
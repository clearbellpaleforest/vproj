#!/usr/bin/env bash
# Nam -- Vim test runner
# Runs the VimScript test suite. No external dependencies required.
#
# Usage:
#   ./scripts/run_tests_vim82.sh
#   VIM=/opt/vim/bin/vim ./scripts/run_tests_vim82.sh
#
# Exit status: 0 if all tests pass, 1 otherwise.

set -euo pipefail

NAM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly NAM_ROOT

VIM="${VIM:-vim}"
info() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

info "Using Vim: $(command -v "$VIM")"
info "Nam root: $NAM_ROOT"

# Run the VimScript test suite
info "Running tests..."

cd "$NAM_ROOT"
"$VIM" -N -u NONE -S tests/run_tests.vim 2>&1 | tee /tmp/nam-vim-test-output.txt
VIM_EXIT=$?

echo ""
echo "============================================"
echo "  Nam Vim Test Results"
echo "============================================"

OUTPUT_TEXT=$(cat /tmp/nam-vim-test-output.txt)

# Extract pass/fail counts
PASSED=$(echo "$OUTPUT_TEXT" | grep -c "OK" || true)
FAILED=$(echo "$OUTPUT_TEXT" | grep -ci "FAIL" || true)
ERRORS=$(echo "$OUTPUT_TEXT" | grep -ci "ERROR" || true)

echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Errors:  $ERRORS"
echo "============================================"

if [ "$FAILED" -gt 0 ] || [ "$ERRORS" -gt 0 ]; then
    echo ""
    info "Some tests FAILED (see output above for details)."
    exit 1
fi

info "All tests PASSED."
exit 0

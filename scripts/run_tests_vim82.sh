#!/usr/bin/env bash
# Vproj -- Vim test runner
# Runs the VimScript test suite. No external dependencies required.
#
# Usage:
#   ./scripts/run_tests_vim82.sh
#   VIM=/opt/vim/bin/vim ./scripts/run_tests_vim82.sh
#
# Exit status: 0 if all tests pass, 1 otherwise.

set -euo pipefail

VPROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly VPROJ_ROOT

VIM="${VIM:-vim}"
info() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

info "Using Vim: $(command -v "$VIM")"
info "Vproj root: $VPROJ_ROOT"

# Run the VimScript test suite
info "Running tests..."

cd "$VPROJ_ROOT"
"$VIM" -N -u NONE -S tests/run_tests.vim 2>&1 | tee /tmp/vproj-vim-test-output.txt
VIM_EXIT=$?

echo ""
echo "============================================"
echo "  Vproj Vim Test Results"
echo "============================================"

OUTPUT_TEXT=$(cat /tmp/vproj-vim-test-output.txt)

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

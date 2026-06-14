#!/bin/bash
#
# Nam Plugin — Performance Benchmark Runner
#
# Runs all benchmarks via Neovim headless and checks results.
#
# Usage:
#   ./tests/run_benchmarks.sh           # Full benchmark suite
#   ./tests/run_benchmarks.sh --quick   # Quick mode (fewer iterations)
#
# Exit code:
#   0  All performance targets met.
#   1  One or more targets not met, or a benchmark module errored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ---- Parse flags -----------------------------------------------------------

LUA_QUICK="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick|-q)
            LUA_QUICK="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--quick]"
            echo ""
            echo "  --quick   Reduce iterations for faster runs"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--quick]"
            exit 1
            ;;
    esac
done

# ---- Prelude ---------------------------------------------------------------

echo ""
echo "================================================================"
echo "  Nam Plugin — Performance Benchmarks"
echo "================================================================"
echo "  Date:      $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  Host:      $(uname -n -s -m 2>/dev/null || echo 'unknown')"
echo "  Mode:      $([ "$LUA_QUICK" = "true" ] && echo 'QUICK' || echo 'FULL')"
echo "================================================================"
echo ""

# Verify that nvim is available
if ! command -v nvim &>/dev/null; then
    echo "ERROR: nvim is not on PATH.  Cannot run benchmarks."
    exit 1
fi

NVIM_VERSION=$(nvim --version | head -1)
echo "  Neovim:    $NVIM_VERSION"
echo ""

# ---- Run Benchmarks --------------------------------------------------------

cd "$REPO_DIR"

# We set the runtimepath so that `require("nam.*")` and
# `require("tests.bench.*")` resolve relative to the repo root.
set +e  # capture exit code manually
OUTPUT=$(nvim --headless \
    -c "set rtp+=." \
    -c "lua _G.NAM_BENCH_QUICK = $LUA_QUICK" \
    -c "lua require('tests.bench.run_all')" \
    -c "quitall!" \
    2>&1)
EXIT_CODE=$?
set -e

# Print the benchmark output
echo "$OUTPUT"
echo ""

# ---- Parse output for secondary verification -------------------------------

# If the Lua runner exited with code 1, report the failure.
if [ "$EXIT_CODE" -ne 0 ]; then
    echo "================================================================"
    echo "  BENCHMARKS FAILED (exit code $EXIT_CODE)"
    echo "================================================================"
    exit 1
fi

# Double-check: grep for any [FAIL] or [ERROR] markers in the output.
if echo "$OUTPUT" | grep -q "\[FAIL\]"; then
    echo "================================================================"
    echo "  WARNING: [FAIL] lines found despite exit code 0."
    echo "================================================================"
    exit 1
fi

if echo "$OUTPUT" | grep -q "\[ERROR\]"; then
    echo "================================================================"
    echo "  WARNING: [ERROR] lines found despite exit code 0."
    echo "================================================================"
    exit 1
fi

echo "================================================================"
echo "  ALL BENCHMARKS PASSED"
echo "================================================================"
exit 0

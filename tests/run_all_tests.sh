#!/usr/bin/env bash
#
# run_all_tests.sh — Run both Neovim and Vim test suites and report combined
#                    results.
#
# Usage:
#   ./tests/run_all_tests.sh                    # Run all tests on both platforms
#   ./tests/run_all_tests.sh --verbose          # Show full output
#
# Environment:
#   VIM_BIN    Path to Vim binary (default: "vim")
#   NVIM_BIN   Path to Neovim binary (default: "nvim")
#
# Exit code: 0 if both suites pass, 1 otherwise.

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VIM_BIN="${VIM_BIN:-vim}"
NVIM_BIN="${NVIM_BIN:-nvim}"

# ── State ────────────────────────────────────────────────────────────────────
VERBOSE=false
PLENARY_DIR=""
TEMP_DIRS=()

# Counters
NVIM_PASS=0
NVIM_FAIL=0
VIM_PASS=0
VIM_FAIL=0
NVIM_EXIT=0
VIM_EXIT=0

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    for d in "${TEMP_DIRS[@]}"; do [ -d "$d" ] && rm -rf "$d"; done
}
trap cleanup EXIT

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose]"
            echo ""
            echo "Options:"
            echo "  --verbose   Print full test output from both suites"
            echo "  --help      Show this message"
            echo ""
            echo "Environment:"
            echo "  VIM_BIN     Path to Vim binary (default: vim)"
            echo "  NVIM_BIN    Path to Neovim binary (default: nvim)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Usage: $0 [--verbose]" >&2
            exit 1
            ;;
    esac
done

# ── Locate plenary.nvim (shared dependency) ──────────────────────────────────
find_plenary() {
    local paths=(
        "$PROJECT_DIR/../plenary.nvim"
        "$HOME/.local/share/nvim/site/pack/bundle/start/plenary.nvim"
        "$HOME/.vim/pack/bundle/start/plenary.nvim"
        "/usr/share/nvim/site/pack/bundle/start/plenary.nvim"
        "/usr/local/share/nvim/site/pack/bundle/start/plenary.nvim"
    )
    for p in "${paths[@]}"; do
        if [ -d "$p" ] && [ -f "$p/plugin/plenary.vim" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

PLENARY_DIR=$(find_plenary || true)
if [ -z "$PLENARY_DIR" ]; then
    echo "plenary.nvim not found — cloning..."
    TMPDIR=$(mktemp -d)
    TEMP_DIRS+=("$TMPDIR")
    if git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$TMPDIR/plenary.nvim" 2>&1 | tail -1; then
        PLENARY_DIR="$TMPDIR/plenary.nvim"
        echo "  cloned to: $PLENARY_DIR"
    else
        echo "WARNING: Failed to clone plenary.nvim" >&2
    fi
fi

echo "============================================="
echo "  nam — Combined Test Runner"
echo "============================================="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Part 1: Neovim tests (via plenary.nvim BustedDirectory)
# ══════════════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────"
echo " 1. Neovim Tests"
echo "─────────────────────────────────────────────"

if ! command -v "$NVIM_BIN" &>/dev/null; then
    echo ""
    echo " Neovim binary not found: '${NVIM_BIN}'"
    echo " SKIPPED"
    NVIM_EXIT=0  # Not an error to be missing neovim
else
    NVIM_VERSION=$("$NVIM_BIN" --version 2>&1 | head -1)
    echo " Binary: ${NVIM_BIN} ($NVIM_VERSION)"
    echo ""

    # Validate spec directory
    if [ ! -d "$PROJECT_DIR/tests/spec" ]; then
        echo "ERROR: tests/spec directory not found" >&2
        NVIM_EXIT=1
    else
        SPEC_COUNT=0
        for f in "$PROJECT_DIR"/tests/spec/*_spec.lua; do
            [ -f "$f" ] && SPEC_COUNT=$((SPEC_COUNT + 1))
        done
        echo " Spec files: ${SPEC_COUNT}"
        echo ""

        # Build the nvim command
        declare -a NVIM_ARGS
        NVIM_ARGS=(
            "$NVIM_BIN"
            --headless
            -u NONE
            -i NONE
            -N
        )

        if [ -n "$PLENARY_DIR" ]; then
            NVIM_ARGS+=(-c "set rtp+=${PROJECT_DIR}")
            NVIM_ARGS+=(-c "set rtp+=${PLENARY_DIR}")
            NVIM_ARGS+=(-c "runtime! plugin/plenary.vim")
        fi

        if $VERBOSE; then
            echo " Running..."
            echo ""
            set +e
            "${NVIM_ARGS[@]}" \
                -c "PlenaryBustedDirectory ${PROJECT_DIR}/tests/spec/ { minimal_init = '${PROJECT_DIR}/tests/minimal_init.lua' }" \
                -c "qa!" \
                2>&1
            NVIM_EXIT=$?
            set -e
            echo ""
            echo "─────────────────────────────────────────────"
        else
            set +e
            NVIM_OUTPUT=$("${NVIM_ARGS[@]}" \
                -c "PlenaryBustedDirectory ${PROJECT_DIR}/tests/spec/ { minimal_init = '${PROJECT_DIR}/tests/minimal_init.lua' }" \
                -c "qa!" \
                2>&1)
            NVIM_EXIT=$?
            set -e

            # Parse results — look for plenary's summary format
            NVIM_PASS=$(echo "$NVIM_OUTPUT" | grep -oE 'Success:\s*([0-9]+)' | tail -1 | grep -oE '[0-9]+' || echo 0)
            NVIM_FAIL=$(echo "$NVIM_OUTPUT" | grep -oE 'Failure:\s*([0-9]+)' | tail -1 | grep -oE '[0-9]+' || echo 0)

            # Fallback: if plenary didn't output structured results, count dots (pass) and F (failure)
            if [ "$NVIM_PASS" -eq 0 ] && [ "$NVIM_FAIL" -eq 0 ]; then
                NVIM_DOTS=$(echo "$NVIM_OUTPUT" | grep -o '\.' | wc -l || echo 0)
                NVIM_F=$(echo "$NVIM_OUTPUT" | grep -o 'F' | wc -l || echo 0)
                if [ "$NVIM_DOTS" -gt 0 ] || [ "$NVIM_F" -gt 0 ]; then
                    NVIM_PASS=$NVIM_DOTS
                    NVIM_FAIL=$NVIM_F
                fi
            fi

            # Show summary
            if [ "$NVIM_EXIT" -eq 0 ]; then
                if [ "$NVIM_FAIL" -gt 0 ]; then
                    echo " Neovim tests: PASSED  (${NVIM_PASS} passed, ${NVIM_FAIL} failed)"
                else
                    echo " Neovim tests: PASSED  (${NVIM_PASS} passed)"
                fi
            else
                echo " Neovim tests: FAILED  (${NVIM_PASS} passed, ${NVIM_FAIL} failed)"
                echo ""
                echo " Failure output:"
                echo "$NVIM_OUTPUT" | grep -iE 'FAIL|Error|assert' | head -20 | sed 's/^/   /'
                # Force failure count >0 when exit code indicates failure
                [ "$NVIM_FAIL" -eq 0 ] && NVIM_FAIL=1
            fi
        fi
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Part 2: Vim 8.2+ tests (via run_vim_tests.sh)
# ══════════════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────"
echo " 2. Classic Vim Tests"
echo "─────────────────────────────────────────────"

if ! command -v "$VIM_BIN" &>/dev/null; then
    echo ""
    echo " Vim binary not found: '${VIM_BIN}'"
    echo " SKIPPED"
    VIM_EXIT=0  # Not an error to be missing vim
else
    VIM_VERSION=$("$VIM_BIN" --version 2>&1 | head -1)
    echo " Binary: ${VIM_BIN} ($VIM_VERSION)"

    if ! "$VIM_BIN" --version 2>&1 | grep -q '+lua'; then
        echo ""
        echo " ERROR: ${VIM_BIN} does not have +lua"
        echo " SKIPPED"
        VIM_EXIT=0
    else
        echo " +lua: yes"
        echo ""

        if [ ! -f "$SCRIPT_DIR/run_vim_tests.sh" ]; then
            echo " ERROR: tests/run_vim_tests.sh not found" >&2
            VIM_EXIT=1
        else
            set +e
            if $VERBOSE; then
                "$SCRIPT_DIR/run_vim_tests.sh" --verbose 2>&1
                VIM_EXIT=$?
            else
                VIM_OUTPUT=$("$SCRIPT_DIR/run_vim_tests.sh" 2>&1)
                VIM_EXIT=$?
                echo "$VIM_OUTPUT" | grep -E '^(Results|Vim tests:|Failures:| Crashes:|Test files found|plenary\.nvim|Vim version)' || true
            fi
            set -e

            # Parse results
            if [ -n "${VIM_OUTPUT-}" ]; then
                if echo "$VIM_OUTPUT" | grep -q 'FAILED'; then
                    VIM_FAIL=1
                fi
                VIM_PASS=$(echo "$VIM_OUTPUT" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || echo 0)
            fi
        fi
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Part 3: Combined Report
# ══════════════════════════════════════════════════════════════════════════════
echo "============================================="
echo "  Combined Results"
echo "============================================="
echo ""

NEOTOTAL=$((NVIM_PASS + NVIM_FAIL))
VIMTOTAL=$((VIM_PASS + VIM_FAIL))

if command -v "$NVIM_BIN" &>/dev/null; then
    echo " Neovim : ${NVIM_PASS} passed, ${NVIM_FAIL} failed  ($([ "$NVIM_EXIT" -eq 0 ] && echo 'PASS' || echo 'FAIL'))"
else
    echo " Neovim : SKIPPED"
fi

if command -v "$VIM_BIN" &>/dev/null; then
    echo " Vim    : ${VIM_PASS} passed, ${VIM_FAIL} failed  ($([ "$VIM_EXIT" -eq 0 ] && echo 'PASS' || echo 'FAIL'))"
else
    echo " Vim    : SKIPPED"
fi

echo ""

TOTAL_PASS=$((NVIM_PASS + VIM_PASS))
TOTAL_FAIL=$((NVIM_FAIL + VIM_FAIL))

if [ "$NVIM_EXIT" -eq 0 ] && [ "$VIM_EXIT" -eq 0 ]; then
    echo " OVERALL: ALL TESTS PASSED  (${TOTAL_PASS} passed, ${TOTAL_FAIL} failed)"
    exit 0
else
    echo " OVERALL: FAILURES  (${TOTAL_PASS} passed, ${TOTAL_FAIL} failed)"
    exit 1
fi

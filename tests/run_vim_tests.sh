#!/usr/bin/env bash
#
# run_vim_tests.sh — Run vproj Vim-compatible tests (Vim 8.2+ with +lua)
#
# Runs all *.vim test files from tests/vim_spec/ through the Vim test
# infrastructure defined in tests/run_tests.vim.
#
# Usage:
#   ./tests/run_vim_tests.sh                    # Run all Vim tests
#   ./tests/run_vim_tests.sh --verbose          # Show full output
#   ./tests/run_vim_tests.sh --filter cache     # Run only cache-related tests
#
# Environment:
#   VIM_BIN   Path to Vim binary (default: "vim")
#
# Exit code: 0 if all tests pass, 1 otherwise.

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VIM_BIN="${VIM_BIN:-vim}"

# ── State ────────────────────────────────────────────────────────────────────
VERBOSE=false
FILTER=""
TEMP_FILES=()
TEMP_DIRS=()

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    for f in "${TEMP_FILES[@]}"; do [ -f "$f" ] && rm -f "$f"; done
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
        --filter)
            if [ $# -lt 2 ]; then
                echo "ERROR: --filter requires an argument" >&2
                exit 1
            fi
            FILTER="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose] [--filter <pattern>]"
            echo ""
            echo "Options:"
            echo "  --verbose       Print full test output"
            echo "  --filter PAT    Run only tests whose filename matches PAT"
            echo "  --help          Show this message"
            echo ""
            echo "Environment:"
            echo "  VIM_BIN         Path to Vim binary (default: vim)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            echo "Usage: $0 [--verbose] [--filter <pattern>]" >&2
            exit 1
            ;;
    esac
done

# ── 1. Check Vim prerequisites ───────────────────────────────────────────────
echo "=== vproj Vim test runner ==="
echo ""

if ! command -v "$VIM_BIN" &>/dev/null; then
    echo "ERROR: Vim binary not found: '${VIM_BIN}'" >&2
    echo "       Install Vim 8.2+ compiled with +lua, or set VIM_BIN" >&2
    exit 1
fi

VIM_VERSION_HEAD=$("$VIM_BIN" --version 2>&1 | head -1)
echo "$VIM_VERSION_HEAD"

if ! "$VIM_BIN" --version 2>&1 | grep -q '+lua'; then
    echo "ERROR: Vim must be compiled with +lua" >&2
    echo "       Install vim-gtk3, vim-nox, vim-huge, or compile from source" >&2
    exit 1
fi
echo "  +lua: yes"
echo ""

# ── 2. Locate or clone plenary.nvim ──────────────────────────────────────────
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
    echo "plenary.nvim not found — cloning to temporary directory..."
    TMPDIR=$(mktemp -d)
    TEMP_DIRS+=("$TMPDIR")
    if ! git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$TMPDIR/plenary.nvim" 2>&1 | tail -1; then
        echo "WARNING: Failed to clone plenary.nvim. Continuing without it." >&2
        PLENARY_DIR=""
    else
        PLENARY_DIR="$TMPDIR/plenary.nvim"
        echo "  cloned to: $PLENARY_DIR"
    fi
else
    echo "plenary.nvim: $PLENARY_DIR"
fi
echo ""

# ── 3. Validate test directory ────────────────────────────────────────────────
if [ ! -d "$PROJECT_DIR/tests/vim_spec" ]; then
    echo "ERROR: tests/vim_spec directory not found at ${PROJECT_DIR}/tests/vim_spec" >&2
    exit 1
fi

# Count available spec files
SPEC_COUNT=0
for f in "$PROJECT_DIR"/tests/vim_spec/*.vim; do
    [ -f "$f" ] && SPEC_COUNT=$((SPEC_COUNT + 1))
done

if [ "$SPEC_COUNT" -eq 0 ]; then
    echo "ERROR: No .vim spec files found in tests/vim_spec/" >&2
    exit 1
fi
echo "Test files found: ${SPEC_COUNT}"
echo ""

# ── 4. Build the Vim command ────────────────────────────────────────────────
declare -a VIM_ARGS
VIM_ARGS=(
    "$VIM_BIN"
    -u NONE
    -i NONE
    -N
    --not-a-term
    -c "set rtp+=${PROJECT_DIR}"
)

if [ -n "$PLENARY_DIR" ]; then
    VIM_ARGS+=(-c "set rtp+=${PLENARY_DIR}")
    VIM_ARGS+=(-c "runtime! plugin/plenary.vim")
fi

if [ -n "$FILTER" ]; then
    # ── Filtered mode: create a temporary Vim script ─────────────────────────
    # Uses placeholder substitution to avoid heredoc escaping issues.
    TMPFILE=$(mktemp)
    TEMP_FILES+=("$TMPFILE")

    cat > "$TMPFILE" << 'VIMEOF'
set nocompatible

" ── Test infrastructure (replicated from tests/run_tests.vim) ──────────────
"
let g:test_passed = 0
let g:test_failed = 0
let g:test_errors = []

function! g:AssertTrue(cond, msg) abort
  if a:cond
    let g:test_passed += 1
    echohl MoreMsg
    echom "  PASS: " . a:msg
    echohl None
    return 1
  else
    let g:test_failed += 1
    call add(g:test_errors, "FAIL: " . a:msg)
    echohl ErrorMsg
    echom "  FAIL: " . a:msg
    echohl None
    return 0
  endif
endfunction

function! g:AssertFalse(cond, msg) abort
  return g:AssertTrue(!a:cond, a:msg)
endfunction

function! g:AssertEquals(got, expected, msg) abort
  if a:got ==# a:expected
    return g:AssertTrue(1, a:msg)
  else
    echohl WarningMsg
    echom "    expected: " . string(a:expected)
    echom "    got:      " . string(a:got)
    echohl None
    return g:AssertTrue(0, a:msg . " (value mismatch)")
  endif
endfunction

function! g:AssertNotNil(val, msg) abort
  if type(a:val) == v:t_none || type(a:val) == v:t_null
    return g:AssertTrue(0, a:msg . " (was nil)")
  endif
  if a:val is v:null
    return g:AssertTrue(0, a:msg . " (was v:null)")
  endif
  return g:AssertTrue(1, a:msg)
endfunction

function! g:RunTestFile(path) abort
  echom " "
  echom "== Testing: " . a:path
  try
    execute "source " . a:path
  catch
    let g:test_failed += 1
    let msg = "CRASH in " . a:path . ": " . v:exception
    call add(g:test_errors, msg)
    echohl ErrorMsg
    echom msg
    echohl None
    echom "  from: " . v:throwpoint
  endtry
endfunction

function! g:Report() abort
  echom " "
  if g:test_failed == 0
    echohl MoreMsg
    echom "ALL TESTS PASSED  (" . g:test_passed . "/" . (g:test_passed + g:test_failed) . ")"
    echohl None
  else
    echohl ErrorMsg
    echom "FAILURES: " . g:test_failed . "  Passed: " . g:test_passed . "  Total: " . (g:test_passed + g:test_failed)
    echohl None
    echom " "
    echom "Failed tests:"
    for err in g:test_errors
      echohl ErrorMsg
      echom "  " . err
      echohl None
    endfor
  endif
endfunction

" ── Discover and filter test files ──────────────────────────────────────────
"
let s:spec_dir = '__SPEC_DIR__'
let s:all_files = globpath(s:spec_dir, "*.vim", 0, 1)
call sort(s:all_files)

let s:filter_pattern = "__FILTER__"
let s:run_count = 0
for f in s:all_files
  if f =~ s:filter_pattern || fnamemodify(f, ":t") =~ s:filter_pattern
    call g:RunTestFile(f)
    let s:run_count += 1
  endif
endfor

if s:run_count == 0
  echohl WarningMsg
  echom "No test files matched filter: __FILTER__"
  echohl None
endif

call g:Report()

if g:test_failed > 0
  cquit
endif
quit!
VIMEOF

    # Replace placeholders with actual values
    sed -i "s|__SPEC_DIR__|${PROJECT_DIR}/tests/vim_spec|g" "$TMPFILE"

    # Escape filter for inclusion in a VimL double-quoted string.
    # VimL interprets \ and " as special inside double quotes, so escape them.
    # The sed uses | as delimiter (unlikely in a filename filter).
    FILTER_ESC=$(echo "$FILTER" | sed 's|\\|\\\\|g; s|"|\\"|g')
    sed -i "s|__FILTER__|${FILTER_ESC}|g" "$TMPFILE"

    VIM_ARGS+=(-S "$TMPFILE")
else
    # ── Unfiltered mode: use the existing run_tests.vim ──────────────────────
    if [ ! -f "$PROJECT_DIR/tests/run_tests.vim" ]; then
        echo "ERROR: tests/run_tests.vim not found" >&2
        exit 1
    fi
    VIM_ARGS+=(-S "tests/run_tests.vim")
fi

VIM_ARGS+=(-c "qa!")

# ── 5. Execute tests ─────────────────────────────────────────────────────────
cd "$PROJECT_DIR"

set +e
if $VERBOSE; then
    echo "─────────────────────────────────────────────"
    echo " Running Vim tests..."
    echo "─────────────────────────────────────────────"
    "${VIM_ARGS[@]}" 2>&1
    VIM_EXIT=$?
else
    OUTPUT=$("${VIM_ARGS[@]}" 2>&1)
    VIM_EXIT=$?
fi
set -e

# ── 6. Parse results ─────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

# If we captured output (non-verbose mode), parse it
if ! $VERBOSE && [ -n "${OUTPUT-}" ]; then
    PASS_COUNT=$(echo "$OUTPUT" | grep -c '  PASS:' 2>/dev/null || echo 0)
    FAIL_COUNT=$(echo "$OUTPUT" | grep -c '  FAIL:' 2>/dev/null || echo 0)

    echo "─────────────────────────────────────────────"
    echo " Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    echo ""

    # Print failure details if any
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo " Failures:"
        echo "$OUTPUT" | grep '  FAIL:' | sed 's/^  //' | while IFS= read -r line; do
            echo "   - $line"
        done
        echo ""

        # Also show crash lines
        CRASH_COUNT=$(echo "$OUTPUT" | grep -c 'CRASH' 2>/dev/null || echo 0)
        if [ "$CRASH_COUNT" -gt 0 ]; then
            echo " Crashes:"
            echo "$OUTPUT" | grep 'CRASH' | sed 's/^  //' | while IFS= read -r line; do
                echo "   - $line"
            done
        fi
    fi

    echo "─────────────────────────────────────────────"
fi

# ── 7. Determine exit code ───────────────────────────────────────────────────
if [ "$VIM_EXIT" -ne 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "Vim tests: FAILED  (${PASS_COUNT} passed, ${FAIL_COUNT} failed)"
    exit 1
fi

echo ""
echo "Vim tests: PASSED  (${PASS_COUNT} passed, ${FAIL_COUNT} failed)"
exit 0

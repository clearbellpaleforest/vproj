#!/usr/bin/env bash
# Run every automated vproj test file in an isolated environment.
#
#   tests/run_all.sh            # run all files
#   tests/run_all.sh -v         # also print FAIL lines / Vim errors per failing file
#
# Each file runs as:
#   vim --not-a-term -N -u NONE -i NONE -S <file> -c 'cquit!' </dev/null
# (--not-a-term: without it the vim-gtk3 build, which CI installs, makes
# input() return '' for test_feedinput() keys; confirm() is unaffected)
# with HOME, XDG_CACHE_HOME and TMPDIR pointed into a fresh temp dir, so a test
# can never read or write the user's real ~/.cache/vproj/session or ~/.vim.
#
# Pass/fail is decided by Vim's exit code only:
#   - a test that completes ends with its own `qa!` (exit 0) or `cquit!` (exit 1)
#   - a test that aborts mid-script (E-error stops sourcing) falls through to
#     the trailing -c 'cquit!' and exits nonzero
#   - a hang is killed by `timeout` (exit 124; SIGKILL 5 s later if Vim
#     ignores SIGTERM, as it does while blocked on a prompt -> exit 137)
# PASS:/FAIL: line counts are reported for information only.
#
# Not run: tests/demo.vim (interactive walkthrough, no assertions) and
# tests/test_helpers.vim (unused helper library, not a test).
#
# Guard: the repo-root vproj.vproj (per-user, untracked, gitignored) must be
# byte-identical before and after the run (sha256, or present/absent). Any
# change fails the run. Does not depend on git or on the file being tracked.

set -u

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$TESTS_DIR")
cd "$REPO_DIR" || { echo "run_all: cannot cd to $REPO_DIR" >&2; exit 2; }

command -v vim >/dev/null 2>&1 || { echo "run_all: vim not found" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { echo "run_all: timeout not found" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vproj-tests.XXXXXX") || { echo "run_all: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

FILES=(
  tests/smoke.vim
  tests/keybindings.vim
  tests/regression.vim
  tests/final.vim
  tests/gaps.vim
  tests/edge_test.vim
  tests/coverage.vim
  tests/concept_audit.vim
  tests/audit_fixes.vim
)
for f in tests/integration/*.vim tests/unit/*.vim; do
  [ -e "$f" ] && FILES+=("$f")
done

# ── vproj.vproj guard: snapshot ──
vproj_state() {
  if [ -e vproj.vproj ]; then
    sha256sum vproj.vproj | cut -d' ' -f1
  else
    printf '(absent)'
  fi
}
GUARD_BEFORE=$(vproj_state)

strip_term() {
  # Drop CR and terminal escape sequences Vim emits even with stdin redirected.
  tr -d '\r' | sed -E 's/\x1b\[[0-9;?<=>]*[A-Za-z]//g; s/\x1b[()][0-9A-Za-z]//g; s/\x1b[=>]//g'
}

total_pass=0
total_fail=0
files_failed=0

printf '%-44s %6s %6s  %s\n' FILE PASS FAIL STATUS
printf '%-44s %6s %6s  %s\n' "----" "----" "----" "------"

for f in "${FILES[@]}"; do
  run_dir=$(mktemp -d "$WORK/run.XXXXXX")
  mkdir -p "$run_dir/home" "$run_dir/cache" "$run_dir/tmp"
  raw="$run_dir/out.raw"

  HOME="$run_dir/home" XDG_CACHE_HOME="$run_dir/cache" TMPDIR="$run_dir/tmp" \
    timeout -k 5 120 vim --not-a-term -N -u NONE -i NONE -S "$f" -c 'cquit!' </dev/null >"$raw" 2>&1
  rc=$?

  out=$(strip_term <"$raw")
  npass=$(grep -o 'PASS:' <<<"$out" | wc -l)
  nfail=$(grep -o 'FAIL:' <<<"$out" | wc -l)
  total_pass=$((total_pass + npass))
  total_fail=$((total_fail + nfail))

  if [ "$rc" -eq 0 ]; then
    status=ok
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    status="FAILED (timeout)"
  elif grep -q 'Vim: Error reading input' <<<"$out"; then
    # A prompt (input()/confirm()) read EOF from </dev/null and Vim exited.
    status="FAILED (blocked on a prompt, exit $rc)"
  elif [ "$nfail" -eq 0 ] && grep -qE 'E[0-9]+:' <<<"$out"; then
    status="FAILED (aborted, exit $rc)"
  else
    status="FAILED (exit $rc)"
  fi
  [ "$rc" -ne 0 ] && files_failed=$((files_failed + 1))

  printf '%-44s %6d %6d  %s\n' "$f" "$npass" "$nfail" "$status"

  if [ "$rc" -ne 0 ] && [ "$VERBOSE" -eq 1 ]; then
    grep -E 'FAIL:|E[0-9]+:|^line +[0-9]+:|Vim: Error reading input|\[Y\]es|\(y/N\)' <<<"$out" \
      | sed 's/^/    /' | head -40
  fi
done

GUARD_AFTER=$(vproj_state)
guard_ok=1
if [ "$GUARD_BEFORE" != "$GUARD_AFTER" ]; then
  guard_ok=0
fi

echo
printf 'TOTAL: %d files, %d failed; %d PASS lines, %d FAIL lines\n' \
  "${#FILES[@]}" "$files_failed" "$total_pass" "$total_fail"

if [ "$guard_ok" -eq 0 ]; then
  echo "GUARD FAILED: vproj.vproj changed during the test run"
  echo "  before: $GUARD_BEFORE"
  echo "  after:  $GUARD_AFTER"
fi

if [ "$files_failed" -ne 0 ] || [ "$guard_ok" -eq 0 ]; then
  exit 1
fi
exit 0

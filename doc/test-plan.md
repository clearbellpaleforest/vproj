# Test Plan

## Strategy

Tests exercise the public API (`vproj#*` functions, plus `vproj#ai#*` and `vproj#agent#*` for the add-ons). No tests reach into
script-local internals. The API is the contract.

Two layers:
- **Unit tests** — single function invariants, edge cases in isolation
- **Integration tests** — end-to-end behavior through the public API, mode
  switching, multi-step sequences

## Test Files

```
tests/
├── run_all.sh                      # Runs every test file hermetically
├── unit/
│   ├── test_first_selectable.vim   # FirstSelectableLine mode-awareness
│   ├── test_ai.vim                 # AI add-on (fake curl, no network)
│   ├── test_agent.vim              # Agent add-on (fake agent CLI)
│   └── test_ai_credentials.vim     # AI credential handling
├── integration/
│   ├── test_git_mode_full.vim      # Code mode layout, mode switching
│   ├── test_buf_mode.vim           # Buf mode with real buffers
│   ├── test_paging.vim             # Paging with 60-item directory
│   ├── test_qfix_mode.vim          # Qfix mode display, jump-to-entry, empty state
│   ├── test_pane_lifecycle.vim     # Preview, tree view, permanent mode, toggles
│   ├── test_git_full.vim           # Git features: diff, blame, discard
│   ├── test_special_chars.vim      # Special characters in filenames
│   ├── test_file_ops.vim           # :Copy :Delete :Rename :Move, Delete key
│   └── test_audit_2026_11*.vim     # Regressions from the 2026-11 audit (6 files)
├── smoke.vim                       # Basic open/close
├── final.vim                       # Audit fix verification
├── regression.vim                  # Regression checks
├── coverage.vim                    # Comprehensive API coverage
├── edge_test.vim                   # Edge cases, boundary conditions
├── keybindings.vim                 # Keybinding dispatch
├── gaps.vim                        # Gap coverage: session, filter, NavigateUp
├── concept_audit.vim               # Mapping table vs the concept
├── audit_fixes.vim                 # Earlier audit fix verification
├── demo.vim                        # Interactive demo script (not run by run_all.sh)
├── hand_test.md                    # Manual test checklist
└── test_helpers.vim                # Shared helpers (unused, not a test)
```

## Running Tests

```bash
bash tests/run_all.sh          # every automated file; -v prints failing lines
```

`run_all.sh` runs each file as
`vim --not-a-term -N -u NONE -i NONE -S <file> -c 'cquit!'` with HOME,
XDG_CACHE_HOME and TMPDIR pointed at a fresh temp directory, so a test never
touches the real session cache. A file passes only on exit code 0; a script
that aborts falls through to `cquit!` and fails, and a hang is killed by
`timeout`. `PASS:`/`FAIL:` line counts are informational. The script also
checks that the repo-root `vproj.vproj` is byte-identical before and after.
One file by hand:

```bash
vim --not-a-term -N -u NONE -i NONE -S tests/<test_file>.vim -c 'cquit!'
```

Tests run headless; output goes to stdout. Assertions use Vim's built-in
`assert_*()` functions or the files' own PASS/FAIL helpers.

## Coverage Targets

| Category | Target |
|----------|--------|
| Public API functions | 100% |
| Mode switching | All transitions |
| Edge cases | All documented edge cases |
| Keybinding dispatch | All mappings |
| Paging / navigation | Multi-page, boundary wraps |
| Project file I/O | Parse, write, round-trip |
| Binary detection | Regular files, binaries, special files |
| Buffer lifecycle | Open, switch, close, wipe |

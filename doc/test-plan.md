# Test Plan

## Strategy

Tests exercise the public API (`vproj_ai#*` functions). No tests reach into
script-local internals. The API is the contract.

Two layers:
- **Unit tests** — single function invariants, edge cases in isolation
- **Integration tests** — end-to-end behavior through the public API, mode
  switching, multi-step sequences

## Test Files

```
tests/
├── unit/
│   └── test_first_selectable.vim   # FirstSelectableLine mode-awareness
├── integration/
│   ├── test_git_mode_full.vim     # Code mode layout, mode switching
│   ├── test_buf_mode.vim           # Buf mode with real buffers
│   ├── test_paging.vim             # Paging with 60-item directory
│   └── test_qfix_mode.vim          # Qfix mode display, jump-to-entry, empty state
├── smoke.vim                       # Basic open/close
├── final.vim                       # Audit fix verification
├── regression.vim                  # Regression checks
├── coverage.vim                    # Comprehensive API coverage
├── edge_test.vim                   # Edge cases, boundary conditions
├── keybindings.vim                 # Keybinding dispatch
├── demo.vim                        # Interactive demo script
├── hand_test.md                    # Manual test checklist
└── test_helpers.vim                # Shared helpers (legacy Vimscript)
```

## Running Tests

```bash
vim -N -u NONE -S tests/<test_file>.vim
```

Tests run headless. Vim exits after the test completes. Output goes to stdout.
Assertions use Vim's built-in `assert_*()` functions.

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

# Vim 8.2 Test Compatibility Report

Generated: 2026-06-13

Audits all 27 spec files in `/home/aldous/Desktop/vim/tests/spec/` for Vim 8.2 compatibility by counting direct `vim.api.nvim_*` calls vs. compat-layer calls.

---

## Category A: Compatible (no nvim_* calls)

These files use only pure Lua, `vim.fn.*`, `vim.cmd`, `compat.*`, or `os.execute` -- all of which work on Vim 8.2.

| File | Non-compat nvim_* calls | Notes |
|------|--------------------------|-------|
| `cache_spec.lua` | 0 | Pure Lua cache operations. Fully compatible. |
| `config_spec.lua` | 0 | Pure Lua config merge/validation. Fully compatible. |
| `config_edge_spec.lua` | 0 | Pure Lua config edge cases. Fully compatible. |
| `events_spec.lua` | 0 | Pure Lua event bus. Fully compatible. |
| `events_edge_spec.lua` | 0 | Uses `vim.fn.execute` for error logging tests. Compatible on both platforms. |
| `files_mode_spec.lua` | 0 | Mode interface tests, all pure Lua. Fully compatible. |
| `git_mode_spec.lua` | 0 | Uses `vim.cmd("cd")` and `vim.fn.getcwd()`, both compat-safe. |
| `git_adapter_spec.lua` | 0 | Uses `vim.fn.*` and `vim.cmd` only. Compatible. |
| `labels_spec.lua` | 0 | Pure Lua label generation engine. Fully compatible. |
| `labels_edge_spec.lua` | 0 | Pure Lua. Local `tbl_count` helper avoids `vim.tbl_count`. Fully compatible. |
| `modes_spec.lua` | 0 | Pure Lua mode registry tests. Fully compatible. |
| `navigation_edge_spec.lua` | 0 | Uses compat layer exclusively. Global keymap inspection tests guarded by `compat.is_nvim` with `pending()` fallback. |
| `symbols_mode_spec.lua` | 0 | Pure mode interface tests. Fully compatible. |
| `table_spec.lua` | 0 | Pure Lua table utilities (`deep_copy`). Fully compatible. |
| `project_spec.lua` | 0 | Uses `vim.fn.*` and `os.execute` only. Compatible. |

**Total Category A: 15 files**

---

## Category B: Compatible with caveats (minor nvim_* usage)

These files have some direct `vim.api.nvim_*` calls, but the majority of tests are compatible. The problematic calls could be replaced with compat equivalents with minimal effort.

### `buffers_mode_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | 1 |
| compat layer calls | 0 |

- **Problematic calls:** `vim.api.nvim_create_buf(true, false)` at line 36, inside test "select() with valid label navigates to buffer"
- **Fix:** Replace with `compat.create_scratch_buf()` + `compat.buf_set_option(buf, "buflisted", true)`
- **Verdict:** Easy fix. Single call, single test affected.

### `compat_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~10 |
| compat layer calls | ~30 |

- **Problematic calls:** `vim.api.nvim_win_get_option`, `vim.api.nvim_win_set_option`, `vim.api.nvim_create_namespace`, `vim.api.nvim_buf_get_extmarks`, `vim.api.nvim_buf_get_keymap` -- all **guarded by `compat.is_nvim`** with `pending()` fallback
- **Verdict:** Safe on Vim 8.2. Neovim-specific verifications are transparently skipped. No changes needed.

### `git_mode_actions_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | 0 |
| compat layer calls | 6 |

- **Verdict:** Fully compat-based. No changes needed.

### `integration_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | 1 |
| compat layer calls | ~12 |

- **Problematic calls:** `vim.api.nvim_buf_get_keymap(buf, "n")` at line 820, inside test "sidebar buffer has label keymaps after :Vproj command"
- **Fix:** Replace with `compat.buf_get_keymap(buf, "n")` (which returns `{}` on Vim 8.2) -- the assertion would need adjustment from `#maps >= 3` to a weaker check, or the test guarded by `compat.is_nvim`
- **Verdict:** Easy fix. Single call, single test affected.

### `integration_edge_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | 2 |
| compat layer calls | ~10 |

- **Problematic calls:** `vim.api.nvim_buf_get_keymap(buf, "n")` at lines 457, 468
- **Fix:** Same approach as integration_spec.lua
- **Verdict:** Easy fix. Two calls in one describe block.

### `lsp_adapter_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~30 (Neovim section) |
| compat layer calls | 1 (`compat.is_nvim` guard) |

- **Guard:** Lines 6-17: `if not compat.is_nvim then -- stub tests; return end`
- **Verdict:** The guard provides Vim 8.2 stub tests that verify `get_document_symbols` and `get_workspace_symbols` return nil. The Neovim section is completely skipped on Vim 8.2. No changes needed.

### `navigation_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | 4 |
| compat layer calls | 0 |

- **Problematic calls:** `vim.api.nvim_create_buf(false, true)` at lines 50, 63; `vim.api.nvim_buf_get_keymap(buf, "n")` at lines 53, 66
- **Fix:** Replace `nvim_create_buf` with `compat.create_scratch_buf()`. Replace `nvim_buf_get_keymap` with `compat.buf_get_keymap()` (returns `{}` on Vim 8.2; adjust assertions).
- **Verdict:** Easy fix. Affects 2 of 5 tests.

### `persistence_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~6 |
| compat layer calls | ~8 |

- **Problematic calls:** `vim.api.nvim_create_buf(true, false)`, `vim.api.nvim_buf_set_lines`, `vim.api.nvim_buf_set_name`, `vim.api.nvim_set_current_buf`, `vim.api.nvim_buf_delete` at lines 273-286, all inside test "persistence get_state captures cursor position per buffer"
- **Fix:** Replace with `compat.create_scratch_buf()`, `compat.set_buf_lines()`, `compat.get_buf_name()`, `compat.set_current_buf()`, and use `vim.fn.deletebufline` / buffer cleanup via `compat.close_win`
- **Verdict:** Moderate fix. Affects 1 of 21 tests. All other tests in the file are compatible.

### `workspace_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~6 |
| compat layer calls | ~4 |

- **Problematic calls:** `vim.api.nvim_create_buf`, `vim.api.nvim_buf_set_lines`, `vim.api.nvim_buf_set_name`, `vim.api.nvim_set_current_buf`, `vim.api.nvim_win_get_cursor(0)`, `vim.api.nvim_buf_delete` at lines 132-154, all inside test "jump_to_bookmark navigates to correct position"
- **Fix:** Replace with compat equivalents. For `nvim_win_get_cursor`, use `vim.fn.getpos(".")` which works on both platforms.
- **Verdict:** Moderate fix. Affects 1 of ~20 tests. All other tests are pure Lua.

**Total Category B: 9 files**

---

## Category C: Incompatible (heavy nvim_* usage)

These files rely heavily on Neovim-specific APIs and cannot run on Vim 8.2 without significant rewriting.

### `edge_cases_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~30+ |
| compat layer calls | ~5 |

- **Problematic APIs used:**
  - `vim.api.nvim_create_buf` (4+ times)
  - `vim.api.nvim_buf_set_lines` (1)
  - `vim.api.nvim_buf_set_name` (3)
  - `vim.api.nvim_buf_get_keymap` (2)
  - `vim.api.nvim_buf_delete` (4+)
  - `vim.api.nvim_get_current_buf` (1)
  - `vim.api.nvim_set_current_buf` (1)
  - `vim.bo[buf].*` (multiple)
  - `vim.cmd("edit ...")` (1)

- **Compatible sub-tests:** Empty project directory, non-existent file select, special chars in filenames, very long filename, git mode in non-git directory, navigation with unset handler (about 7 of 14 describe blocks are pure Lua)
- **Incompatible sub-tests:** Buffer with no name, readonly buffer, modified buffer, terminal buffer, sidebar double-open, close when already closed, rapid open/close, buffer keymap collision (about 7 of 14)
- **Verdict:** Mixed file with roughly half compatible tests. To run on Vim 8.2, the incompatible tests would need to be extracted into an `if compat.is_nvim` guard, or rewritten with compat layer.

### `outline_mode_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~35+ |
| compat layer calls | ~8 |

- **Problematic APIs used (in EVERY test):**
  - `vim.api.nvim_create_buf` (7+ occurrences)
  - `vim.api.nvim_buf_set_lines` (6+)
  - `vim.api.nvim_get_current_buf` (6+)
  - `vim.api.nvim_set_current_buf` (6+)
  - `vim.api.nvim_buf_delete` (6+)

- **Tests that are compat-safe:** "returns a valid mode interface", "refresh() populates items array", "render() returns lines and label_map", "select() with invalid label returns false", "select() returns false when item has no line number" (5 of 12)
- **Tests that require buffer manipulation:** "select() with valid label navigates to line", "parses markdown headings", "parses lua symbols", "parses vim functions", "parses python defs", "generic fallback shows non-blank lines", "handles empty buffer" (7 of 12)
- **Verdict:** The compat-safe tests use only compat layer and would pass. The buffer-manipulation tests could be rewritten with compat. Moderate rewrite effort.

### `sidebar_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~15 (all guarded by `compat.is_nvim`) |
| compat layer calls | ~30 |

- **Problematic APIs:** `vim.api.nvim_win_get_config()` at lines 167, 264, 270, 310, 319, 329, 370, 440 -- all guarded
- **Fundamental issue:** The sidebar opens via `compat.open_sidebar_win()` which uses `vsplit` on Vim 8.2. In headless mode, vsplit requires a terminal and fails. Without a terminal, `sidebar.open()` is effectively a no-op (pcall catches the error, returns nil window).
- **Consequence:** All tests that assert `is_open() == true` after `open()` will fail on Vim 8.2 in headless mode.
- **Verdict:** Incompatible in headless mode. Would require a terminal (e.g., via `xvfb-run` or `script -c`). Not easily fixable for headless CI.

### `stress_spec.lua`

| Metric | Count |
|--------|-------|
| Direct nvim_* calls | ~50+ (1000+ at scale) |
| compat layer calls | ~15 |

- **Problematic APIs used extensively:**
  - `vim.api.nvim_create_buf` (in loops: 100, 1000 scale)
  - `vim.api.nvim_buf_set_name` (in loops)
  - `vim.api.nvim_buf_delete` (in loops)
  - `vim.api.nvim_buf_get_keymap`
  - `vim.bo[buf].*`
  - `vim.api.nvim_set_current_buf`

- **Compatible sub-tests:** Label engine tests (pure Lua), cache stress tests (pure Lua), event bus stress tests (pure Lua), mode switching stress tests (pure Lua), workspace stress tests (pure Lua), project scan benchmarks (vim.fn.*), ctags symbol tests -- roughly 60% of the file
- **Incompatible sub-tests:** Buffer mode 100-buffer test, 1000-buffer stress test, sidebar create/destroy 500 times, deep directory scanning with io.open
- **Verdict:** The label, cache, event, mode-switching, workspace, and project-scan benchmarks are all compatible. The buffer management and sidebar-heavy tests are not. Could be extracted into compat-guarded blocks.

**Total Category C: 4 files**

---

## Summary

| Category | Count | Vim 8.2 Status |
|----------|-------|-----------------|
| A: Compatible | 15 | Run without changes |
| B: Compatible with caveats | 9 | Run; 1-2 tests per file will error on nvim_* calls |
| C: Incompatible | 4 | Cannot run; needs significant rewrites or terminal |

### Recommended exclude list for Vim 8.2 test runner

For a clean test run on Vim 8.2 in headless mode, exclude the 4 Category C files.

For maximum test coverage, Category B files can be included -- most tests will pass. The 1-2 failing tests per file can be addressed incrementally by replacing direct `vim.api.nvim_*` calls with their `compat.*` equivalents.

### Key compatibility patterns

| Neovim API | Compat replacement |
|------------|-------------------|
| `vim.api.nvim_create_buf(false, true)` | `compat.create_scratch_buf()` |
| `vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)` | `compat.set_buf_lines(buf, 0, -1, lines)` |
| `vim.api.nvim_buf_get_lines(buf, 0, -1, false)` | `compat.get_buf_lines(buf, 0, -1)` |
| `vim.api.nvim_get_current_buf()` | `compat.get_current_buf()` |
| `vim.api.nvim_set_current_buf(buf)` | `compat.set_current_buf(buf)` |
| `vim.api.nvim_buf_get_name(buf)` | `compat.get_buf_name(buf)` |
| `vim.api.nvim_buf_delete(buf, { force = true })` | `compat.close_win(win)` (or `vim.fn.bufdelete(buf)`) |
| `vim.api.nvim_buf_get_keymap(buf, "n")` | `compat.buf_get_keymap(buf, "n")` (returns `{}` on Vim 8.2) |
| `vim.api.nvim_win_get_cursor(0)` | `vim.fn.getpos(".")` |
| `vim.bo[buf].option = value` | `compat.buf_set_option(buf, "option", value)` |
| `vim.bo[buf].option` | `compat.buf_get_option(buf, "option")` |
| `vim.api.nvim_win_get_config(win).width` | Not available on Vim 8.2; test must skip |

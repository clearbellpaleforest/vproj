# Contributing to Nam

## Development Setup

### Prerequisites

- Neovim >= 0.10 with LuaJIT
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (test framework)
- Make sure `PLENARY_PATH` resolves to your plenary installation, or adjust `tests/minimal_init.lua`

### Clone and test

```bash
git clone https://github.com/clearbellpaleforest/nam.git
cd nam

# Run the full test suite
nvim --headless -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"
```

All 50 tests across 11 spec files must pass before opening a pull request.

### Directory structure in brief

```
lua/nam/          -- Source code
plugin/nam.lua    -- Autoload entry point and user commands
tests/spec/       -- Plenary test files
tests/minimal_init.lua -- Minimal VimL init for test isolation
```

---

## Architecture Overview

Nam is built around three pillars.

### 1. Mode System

Every view implements the Mode interface:

```lua
Mode = {
    name    = "",       -- Display name
    icon    = "",       -- Single-character icon
    key     = "",       -- Hotkey to activate this mode
    enabled = true,     -- Whether the mode is active
    refresh = function(),   -- Gather data from buffers, LSP, git, etc.
    render  = function(),   -- Return {lines, label_map} for the sidebar
    select  = function(),   -- Handle label selection (open file, jump to symbol, etc.)
    actions = {},           -- Mode-specific keybindings (e.g., stage/unstage for git)
}
```

Modes are registered in `lua/nam/modes/init.lua`. Adding a new mode means creating a new file in `modes/` and registering it. No core framework code changes are needed.

### 2. Compat Layer

`lua/nam/adapters/compat.lua` provides a unified API for Vim and Neovim. Every platform-specific operation flows through this module. Modes, core modules, and UI components must never branch on `vim.fn.has('nvim')` directly. See the Vim 8.2 compatibility rules below.

### 3. Direct Selection Navigation (DSN) Engine

Labels are generated in four keyboard tiers (36 single-character labels) with two-character overflow for larger lists. Selection is O(1) via a `label_map` hash table. The label engine in `lua/nam/ui/labels.lua` is the single source of truth for label generation -- no other module should produce or parse label strings.

---

## Vim 8.2 Compatibility Rules

Nam targets Vim compiled with `+lua` and Neovim >= 0.10 from a single codebase. Code must not call Neovim-only APIs. The following APIs are **forbidden** outside of `adapters/compat.lua`. If you need one of these, add a compat wrapper instead of calling it directly.

| Forbidden API              | Use Instead                               |
|----------------------------|--------------------------------------------|
| `vim.bo[bufnr]`            | `compat.buf_get_option(bufnr, opt)`        |
| `vim.wo[winid]`            | Compat window option wrapper               |
| `vim.cmd(...)`             | `compat.create_user_command()` or compat helper |
| `vim.api.nvim_open_win()`  | `compat.open_sidebar_win()`                |
| `vim.api.nvim_buf_set_lines()` | `compat.set_buf_lines()`               |
| `vim.api.nvim_set_current_buf()` | `compat.set_current_buf()`          |
| `vim.api.nvim_buf_set_keymap()` | `compat.buf_set_keymap()`             |
| `vim.api.nvim_set_keymap()` | `compat.set_global_keymap()`             |
| `vim.api.nvim_win_set_cursor()` | `compat.set_cursor()`                 |
| `vim.api.nvim_create_user_command()` | `compat.create_user_command()`      |
| `vim.fn.has('nvim')`        | Never branch on platform in modes/core     |
| `vim.lsp.*`                 | Only via `adapters/lsp.lua`               |
| `vim.treesitter.*`          | Only via `adapters/treesitter.lua`         |

**Rule of thumb:** if a function name starts with `vim.api.nvim_`, check if a compat wrapper exists before writing new code. If it doesn't exist, add it to `compat.lua`.

---

## Adding a New Mode

### Step 1: Create the mode module

Create `lua/nam/modes/your_mode.lua`. Implement the full Mode interface:

```lua
local M = {}

M.name = "Your Mode"
M.icon = "Y"
M.key = "y"
M.enabled = true

function M.refresh()
    -- Gather data: buffers, files, git status, LSP symbols, etc.
end

function M.render()
    -- Return {lines = {}, label_map = {}}
    -- lines: array of display strings (with label prefixes)
    -- label_map: table mapping label string to item identifier
end

function M.select(label)
    -- Handle what happens when a user presses a label key
end

M.actions = {
    -- Optional mode-specific key actions
    -- e.g., { key = "s", desc = "Stage", action = function(item) ... end }
}

return M
```

### Step 2: Register in the mode registry

Open `lua/nam/modes/init.lua` and add your mode:

```lua
-- In the registry setup:
local your_mode = require("nam.modes.your_mode")
registry:register(your_mode)
```

### Step 3: Add configuration (optional)

If your mode needs user-configurable options, add defaults in `lua/nam/config.lua` under the `modes` table:

```lua
modes = {
    -- ... existing modes ...
    your_mode = { enabled = true },
}
```

### Step 4: Add tests

Create `tests/spec/your_mode_spec.lua` following the patterns in existing spec files. At minimum, test:

- `refresh()` returns without error
- `render()` returns a table with `lines` and `label_map` keys
- `select()` correctly dispatches the expected action
- Edge cases: empty state, error state, large input

Run the full suite to confirm nothing regresses:

```bash
nvim --headless -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"
```

---

## Testing

### Neovim tests (primary)

```bash
nvim --headless -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"
```

This runs all 11 spec files in the `tests/spec/` directory. The minimal_init.lua bootstrap ensures a clean test environment with minimal plugins loaded.

### Running a single spec file

```bash
nvim --headless -c "PlenaryBustedFile tests/spec/buffers_mode_spec.lua"
```

### Debugging tests

Add `print(vim.inspect(value))` calls in test or source code and check the terminal output. Avoid `error()` calls that could halt the test runner mid-suite.

### Classic Vim testing

If modifying the compat layer, verify the plugin loads under classic Vim:

```bash
vim --cmd "set nocompatible" --cmd "packadd nam" -c "call nam#NamOpen()" -c "q"
```

### Benchmarks

Performance tests live alongside spec files. Run them manually to validate against targets:

| Operation            | Target    |
|----------------------|-----------|
| Sidebar open         | <10 ms    |
| Mode switch          | <20 ms    |
| File open (keypress) | <50 ms    |
| Project scan (cold  100k files) | <2 s |
| Project scan (refresh) | <50 ms |
| User access (DSN)    | <300 ms   |

Benchmarks are not run in CI. They are developer-local validation tools.

---

## Code Style

### Lua conventions

- 120-character line limit. No exceptions.
- Two-space indentation. No tabs.
- `snake_case` for functions and variables.
- `PascalCase` for module-level tables that serve as classes or interfaces.
- UPPER_CASE for constants.
- `local` everywhere. No global assignments except through `require()` or explicit module exports.

### Comments

- Do not write comments that restate the code -- the code is the source of truth.
- Write comments only when the **why** is non-obvious: a subtle edge case, a performance rationale, a cross-module invariant, a platform quirk that is not obvious from the compat layer.
- If you need a comment to explain what a function does, rename the function.
- TODO comments must include a ticket reference or a named owner.

### Module structure

Each module file follows this skeleton:

```lua
local M = {}

-- Module-level state (local, not on M)
local state = {}

--- Public API
function M.some_function()
end

return M
```

### Imports

Order imports from leaf to root: stdlib, adapters, utils, modes, core, ui.

```lua
local compat = require("nam.adapters.compat")
local events = require("nam.utils.events")
```

---

## Pull Request Process

1. **Branch from main.** Use a descriptive name: `fix/git-diff-empty`, `feat/markdown-preview-mode`.
2. **Keep changes focused.** A pull request should address one concern. Refactoring and feature work belong in separate PRs.
3. **All 50 tests must pass.** The CI check runs `PlenaryBustedDirectory` against the full spec suite.
4. **No CI for Vim-only changes.** Classic Vim testing is manual for now.
5. **Update CLAUDE.md** if your change adds a new module, dependency, or modifies the architecture significantly.
6. **No emoji in code, comments, or commit messages.** Professional tone throughout.
7. **Commit messages** should be imperative mood, capitalized, 50-character subject line with a blank line before the body:

```
Add Markdown heading outline mode

Parses `#` through `######` headings in Markdown buffers using a
filetype-based regex. Registers as mode key `m`.
```

8. **A human reviews every PR.** Expect questions about the compat impact of any new API calls.

---

## Performance Targets

These targets are **contractual** -- a change that regresses below these thresholds will not be merged without a documented trade-off.

| Operation                  | Target   | Measurement                         |
|----------------------------|----------|-------------------------------------|
| Sidebar open               | <10 ms   | `vim.loop.hrtime()` around open()   |
| Mode switch                | <20 ms   | `vim.loop.hrtime()` around switch() |
| File open after keypress   | <50 ms   | keypress to buffer visible          |
| Project scan, 100k files   | <2 s     | cold scan, no cache                 |
| Project scan, refresh      | <50 ms   | incremental, cache warm              |
| Label lookup               | O(1)     | hash table access, no iteration     |
| End-to-end file access     | <300 ms  | keypress to file open, cognitive    |

If your change introduces a new data-gathering or rendering step, check its impact against the targets above. Cache aggressively but honor TTLs. Use weak references in caches where possible (`lua/nam/utils/cache.lua`).

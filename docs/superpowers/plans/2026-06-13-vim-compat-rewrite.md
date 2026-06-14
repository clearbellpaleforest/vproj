# Vim Compatibility Rewrite Plan

**Goal:** Rewrite VPN → nam.nvim to target classic Vim primarily, with Neovim supported via a compatibility layer.

**Strategy:** Create `lua/nam/adapters/compat.lua` — a platform abstraction layer that normalizes Vim/Neovim API differences. All other modules call through compat, never `vim.api.*` directly.

## Architecture Diff

```
BEFORE (Neovim-only):
  modes/*.lua → vim.api.nvim_* (direct calls)
  
AFTER (Vim + Neovim):
  modes/*.lua → adapters/compat.lua → vim.fn.* (Vim path)
                                    → vim.api.nvim_* (Neovim path)
```

## Compat Layer API (`adapters/compat.lua`)

```lua
M.is_nvim = vim.fn.has('nvim') == 1

-- Window
M.open_sidebar_win(buf, width) -- split for Vim, floating for Neovim
M.close_win(win)
M.win_is_valid(win)
M.get_win_buf(win)

-- Buffer
M.create_scratch_buf()
M.buf_is_valid(buf)
M.set_buf_lines(buf, start, finish, lines)
M.get_buf_lines(buf, start, finish)
M.buf_line_count(buf)
M.list_bufs()
M.get_buf_name(buf)
M.get_current_buf()
M.set_current_buf(buf)
M.buf_get_option(buf, option)

-- Keymaps
M.buf_set_keymap(buf, mode, lhs, rhs, opts)

-- Cursor
M.set_cursor(line, col)

-- Symbols (ctags for Vim, LSP/TS for Neovim)
M.get_symbols(buf)
```

## Rewrite Tasks

### Task A: Compat Layer
- Create `lua/nam/adapters/compat.lua`
- Implement all API functions for both platforms
- Vim path: `vim.fn.*` + `vim.cmd`
- Neovim path: `vim.api.nvim_*`

### Task B: Rewrite Sidebar
- Replace `nvim_open_win` with compat.open_sidebar_win
- Vim: `leftabove vsplit` + scratch buffer
- Neovim: floating window (existing)

### Task C: Rewrite Renderer
- Replace `nvim_buf_set_lines` with compat
- Drop namespace/extmarks for Vim

### Task D: Rewrite Buffer Mode
- Replace `nvim_list_bufs` with compat
- Replace `nvim_set_current_buf` with compat

### Task E: Rewrite Navigation
- Replace `nvim_buf_get_keymap` with compat keymap setting
- Replace `pairs(vim.api.nvim_buf_get_keymap(...))` with tracked keymap list

### Task F: Rewrite File Mode
- Replace `nvim_buf_set_lines` paths

### Task G: Rewrite Git Mode
- No Neovim-specific API used — minimal changes

### Task H: Rewrite Symbols Mode
- Vim: ctags-based symbol extraction (new adapter)
- Neovim: LSP + tree-sitter (existing)

### Task I: Rewrite Tests
- Replace plenary.nvim with Vim-compatible test approach
- Use `vimcmd` + `assert` pattern

### Task J: Integration & Verify
- Test on classic Vim
- Test on Neovim
- Update CLAUDE.md

## Files Changed
Every file that touches `vim.api.nvim_*` — approximately 12 of 15 source files.
Tests: complete rewrite needed (plenary.nvim is Neovim-only).

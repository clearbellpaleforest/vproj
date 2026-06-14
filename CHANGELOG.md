# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Direct Selection Navigation (DSN) engine** — 4-tier single-character label system (36 keys: `1234567890`, `asdfghjkl`, `qwertyuiop`, `zxcvbnm`) with double-character overflow (`aa`, `ab`, ... `mm` supporting up to 1332 items)
- **Five sidebar modes**:
  - Buffers mode — open buffer list with status indicators (\*, R, T)
  - Files mode — flat labeled project file list with 30-item paging
  - Git mode — staged/unstaged/untracked/conflicts view with stage, unstage, and diff actions
  - Symbols mode — LSP documentSymbol/workspaceSymbol queries with tree-sitter fallback and kind icons
  - Outline mode — file-local structural outline (Markdown headings, Lua/Vim/Python function extraction, generic fallback)
- **Cross-platform compatibility layer** (`adapters/compat.lua`) — unified API over Vim 8.2+ and Neovim 0.10+ covering windows, buffers, keymaps, cursors, file I/O, highlights, and commands
- **Platform-agnostic command execution** — `compat.exe()` wrapper routing to `vim.cmd` on Neovim and `vim.command` on classic Vim
- **Mode registry** — pluggable mode system with register/switch/get_current interface, event-driven mode switching
- **Project root detection** — 12 marker files scanned (`.git`, `package.json`, `Cargo.toml`, `Makefile`, etc.)
- **Recursive file scanner** — incremental, cached, depth-limited with configurable `max_files`
- **Git adapter** — porcelain V2 parser, status categorization, diff display
- **LSP adapter** — `textDocument/documentSymbol` and `workspace/symbol` queries with kind-to-icon mapping
- **Tree-sitter adapter** — fallback symbol extraction for functions, classes, variables
- **Event bus** (`utils/events.lua`) — decoupled emit/on/off with listener isolation
- **TTL-based caching system** (`utils/cache.lua`) — weak-reference cache with configurable time-to-live, force-invalidation support
- **Table utility** (`utils/table.lua`) — deep copy with Vim 8.2 compatibility
- **Workspace persistence module** (`core/persistence.lua`) — JSON session save/restore with auto-save via `VimLeave` autocmd and auto-restore on setup, validation, path under `$XDG_CACHE_HOME/nam/session.json`
- **Sidebar UI** — floating/vertical split window via `compat.open_sidebar_win()`, configurable width (default 35), non-focus-stealing, virtual buffer backing
- **Renderer** — virtual buffer line production, header/tabs, extmarks and highlights, label-aware item rendering
- **User commands** — `:Nam`, `:NamOpen`, `:NamClose` registered via `plugin/nam.lua`
- **Configuration system** — defaults with deep merge, validation, `require("nam").setup({...})` entry point
- **Toggle hotkey** — configurable (default `<F2>`), global keymap via `compat.set_global_keymap()`

### Infrastructure

- **Test suite** — 24 plenary.nvim spec files covering all subsystems
- **Classic Vim test runner** (`tests/run_vim_tests.sh`) — Lua-based test harness for Vim 8.2 and 9.x without plenary dependency
- **Combined test runner** (`tests/run_all_tests.sh`) — aggregates Neovim and Vim results into a single report
- **Stress tests** (`tests/spec/stress_spec.lua`) — 1000 buffers, 100k file scans, 10k symbols, 500 sidebar create/destroy cycles, 1000 rapid mode switches, deep directory trees, 1332-item label overflow
- **Performance benchmarks** (`tests/bench/`) — label generation, cache operations, project scanning, mode switching, event emit timing
- **Edge case tests** (`tests/spec/edge_cases_spec.lua`, `integration_edge_spec.lua`, `labels_edge_spec.lua`, `navigation_edge_spec.lua`, `config_edge_spec.lua`)
- **Git adapter tests** (`git_adapter_spec.lua`, `git_mode_actions_spec.lua`)
- **Vim 8.2 spec files** (`tests/vim_spec/`) — 7 spec files for classic Vim platform
- **GitHub Actions CI** (`.github/workflows/ci.yml`) — Neovim stable + nightly, Vim 8.2 on Ubuntu 22.04, Vim 9.x on Ubuntu 24.04, luacheck lint
- **Install scripts** — `install.sh` (POSIX shell) and `install.vim` (Vimscript) with SHA256 verification
- **Vim help documentation** (`doc/nam.txt`)
- **README** (`README.md`) — installation, usage, mode reference, key bindings
- **SHA256SUMS** — checksums for install artifacts

### Fixed

- **Full Vim 8.2 compatibility** — replaces Neovim-only APIs across all subsystems:
  - `vim.deepcopy` → Lua-native deep copy in config and persistence
  - `vim.cmd` → `vim.command` for dual-platform Ex command execution
  - `vim.bo`/`vim.wo` → `compat.buf_set_option()`/`compat.win_set_option()` wrappers using `setbufvar`/`getbufvar`
  - `vim.fn.systemlist(table_arg)` → shell-escaped string arguments (Lua table args crash Vim 8.2)
  - `vim.fn.readdir`/`getbufinfo`/`getbufline` → `compat.vim_list_to_table` for userdata-to-table conversion
  - `vim.pesc` → manual Lua pattern escape
- **Toggle crash on pre-setup invocation** (C1) — nil guards on `toggle()`, `open()`, `close()` when called before `setup()` completes
- **Dead cache on repeated scans** (C2) — cache module integrated into project file scanner (30s TTL) and git adapter (5s TTL); `force` option for fresh scans; `max_files` added to cache key to prevent stale data leaking between different scan parameters
- **Cross-platform command execution** — all Ex commands routed through `compat.exe()` which selects `vim.cmd` (Neovim) or `vim.command` (Vim) at runtime
- **Git mode cwd nil-safety** — fallback to `getcwd()` when `self.cwd` is nil in stage/unstage/diff
- **Git diff robustness** — guard diff display against empty results and buffer creation failures
- **Missing project root in files mode** — fallback to `getcwd()` when no project marker is found
- **Keymap function storage leak** — function references in keymap callbacks properly scoped to prevent memory accumulation
- **Event listener crash isolation** — individual listener failures wrapped to prevent cascade
- **Git porcelain off-by-one** — filename parsing corrected in porcelain V2 output
- **Various nil-safety improvements** — input validation across sidebar, renderer, mode registry, and navigation

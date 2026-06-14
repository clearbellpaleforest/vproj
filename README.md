# Nam — Direct Selection Navigation for Vim

[![Tests](https://img.shields.io/badge/tests-174%2F174-passing-brightgreen)](#)
[![Version](https://img.shields.io/badge/version-0.2.0-blue)](#)
[![License](https://img.shields.io/badge/license-MIT-green)](#)
[![Vim](https://img.shields.io/badge/vim-%3E%3D8.2-brightgreen)](#)

---

## What is Nam?

Nam replaces cursor-based tree navigation with **Direct Selection Navigation (DSN)** — single-keystroke file access that eliminates cursor traversal. Every file, buffer, symbol, and git status entry is addressed by a keyboard label in a flat sidebar. Press the label, open the file. No cursor movement, no tree expansion, no search.

The sidebar is a command palette disguised as an IDE panel. Selection cost is O(1) regardless of list size.

---

## Screenshot

```
  PROJECT [Files]

  [b]Buf [f]File [s]Sym [g]Git [o]Out
  ─────────────────────────────────────────────
  1 init.vim
  2 config.vim
  3 sidebar.vim
  4 renderer.vim
  5 labels.vim
  6 navigation.vim
  7 handler.vim
  8 project.vim
  9 buffers_mode.vim
  0 files_mode.vim
  a git_mode.vim
  s symbols_mode.vim
  d outline_mode.vim
```

Press `f` for files, `g` for git status, `s` for symbols, `b` for buffers, `o` for outline. Press a label to open that item. Sidebar keeps focus so you can keep browsing. Press `<Esc>` to close.

---

## Features

- **Direct Selection Navigation** — every item is addressed by a single-key label; press it to select, no cursor required
- **Five modes** — Files, Buffers, Git, Symbols, and Outline, each providing a focused project view
- **36 single-key labels** — four keyboard tiers cover dense lists without chord sequences
- **Automatic overflow** — lists beyond 36 items use two-character labels (`aa`, `ab`, `ac`...)
- **Pagination** — file lists page through large directories (30 items per page, `[` and `]` to navigate)
- **Git integration** — view staged, unstaged, untracked, and conflicted files with stage/unstage/diff actions
- **Ctags symbols** — jump to definitions via label using ctags
- **Outline mode** — per-file structural outline with language-aware parsers (Markdown, Lua, Vimscript, Python)
- **Buffer management** — list open buffers with status indicators (modified, read-only, terminal, pinned)
- **Workspace persistence** — auto-save/restore session state, pinned buffers, bookmarks, recent symbols
- **Vim 8.2+** — pure Vim9Script, zero external dependencies
- **TTL-backed caching** — project scans and git status cached with configurable lifetimes
- **Non-intrusive sidebar** — stays open while you edit, keeps focus for rapid file browsing
- **Minimal configuration** — sensible defaults, works out of the box

---

## Requirements

| Platform | Minimum Version |
|----------|-----------------|
| Vim      | >= 8.2          |

Optional but recommended:

- **ctags** — symbol extraction for symbols and outline modes
- **Git** — status, stage, unstage, diff operations

All features degrade gracefully when optional dependencies are absent.

---

## Installation

### Manual

```bash
git clone https://github.com/clearbellpaleforest/nam.git ~/.vim/pack/bundle/start/nam
```

### vim-plug

```vim
Plug 'clearbellpaleforest/nam'
```

---

## Quick Start

No configuration required — the plugin works out of the box:

```vim
" Optional: customize (shown with defaults)
call nam#init#Setup({
    \ 'hotkey': '<F2>',
    \ 'width': 45,
    \ })
```

Press `F2` to open the sidebar. Files mode loads by default. Press a label key to open a file. Press `b` for Buffers, `g` for Git, `s` for Symbols, `o` for Outline. Press `<Esc>` to close.

Use `:NamPin` to pin the current buffer, `:NamBookmark <name>` to bookmark a location, and `:NamWorkspaceSave <name>` to save your entire workspace state.

---

## Usage

### Commands

| Command               | Action                      |
|-----------------------|-----------------------------|
| `:Nam`                | Toggle sidebar              |
| `:NamOpen`            | Open sidebar                |
| `:NamClose`           | Close sidebar               |
| `:NamWorkspace`       | List saved named workspaces |
| `:NamWorkspaceSave`   | Save current state as named workspace |
| `:NamWorkspaceLoad`   | Restore a named workspace   |
| `:NamWorkspaceDelete` | Delete a named workspace    |
| `:NamPin`             | Pin the current buffer      |
| `:NamUnpin`           | Unpin the current buffer    |
| `:NamBookmark`        | Bookmark current position   |
| `:NamBookmarkJump`    | Jump to a named bookmark    |

### Mode hotkeys

| Key | Mode    | Description                      |
|-----|---------|----------------------------------|
| `f` | Files   | Browse project files with paging |
| `b` | Buffers | List open buffers with status    |
| `s` | Symbols | Jump to ctags symbols            |
| `g` | Git     | View Git status, stage/unstage   |
| `o` | Outline | Per-file structural outline      |

### Navigation

- **Single-key labels** — items labeled with the 36 keys from four tiers: `1234567890`, `asdfghjkl`, `qwertyuiop`, `zxcvbnm`
- **Two-character overflow** — beyond 36 items, labels become `aa`, `ab`, `ac`...
- **Paging** — in Files mode, use `[` and `]` to move between pages
- **Mode switching** — press a mode hotkey to switch views immediately
- **Sidebar keeps focus** — after opening a file, focus returns to the sidebar for continued browsing
- **Close** — press `<Esc>` to close the sidebar

---

## Configuration

`call nam#init#Setup({ ... })` accepts a dict that is deep-merged over the defaults.

### Options reference

| Option                   | Type      | Default                          | Description                        |
|--------------------------|-----------|----------------------------------|------------------------------------|
| `hotkey`                 | `string`  | `"<F2>"`                         | Global key mapping to toggle       |
| `width`                  | `number`  | `45`                             | Sidebar width in columns           |
| `auto_open`              | `boolean` | `false`                          | Open sidebar on startup            |
| `labels.tiers`           | `table[]` | (4 tiers, 36 chars)              | Ordered tiers of label keys        |
| `labels.overflow_style`  | `string`  | `"double"`                       | Overflow label style               |
| `modes.*.enabled`        | `boolean` | `true` each                      | Enable or disable a mode           |
| `workspace.auto_save`    | `boolean` | `true`                           | Auto-save workspace on exit        |
| `workspace.auto_restore` | `boolean` | `true`                           | Auto-restore workspace on startup  |
| `workspace.path`         | `string`  | `$XDG_DATA_HOME/nam/workspaces/` | Named workspace storage directory  |
| `cache.project_ttl`      | `number`  | `30`                             | File tree cache TTL (seconds)      |
| `cache.git_ttl`          | `number`  | `5`                              | Git status cache TTL (seconds)     |

### Default configuration

```vim
{
    \ 'hotkey': '<F2>',
    \ 'width': 45,
    \ 'auto_open': v:false,
    \
    \ 'labels': {
    \     'tiers': [
    \         '1234567890',
    \         'asdfghjkl',
    \         'qwertyuiop',
    \         'zxcvbnm',
    \     ],
    \     'overflow_style': 'double',
    \ },
    \
    \ 'modes': {
    \     'files': { 'enabled': v:true },
    \     'buffers': { 'enabled': v:true },
    \     'symbols': { 'enabled': v:true },
    \     'git': { 'enabled': v:true },
    \     'outline': { 'enabled': v:true },
    \ },
    \
    \ 'workspace': {
    \     'auto_save': v:true,
    \     'auto_restore': v:true,
    \ },
    \
    \ 'cache': {
    \     'project_ttl': 30,
    \     'git_ttl': 5,
    \ },
\ }
```

---

## Modes

### Files (`f`)

Scans the project root for files and presents a flat, labeled list. Project root is detected automatically from marker files (`.git`, `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `Makefile`, and others). Directories are sorted first and marked with a trailing `/`. Results are paginated at 30 items per page. Use `[` and `]` to navigate pages. Common noise directories (`.git`, `node_modules`, `build`, `dist`) are excluded by default.

The file tree is cached with a configurable TTL (default 30 seconds).

### Buffers (`b`)

Lists all open, listed buffers. Each entry shows the file name (basename) with status indicators:

| Indicator | Meaning   |
|-----------|-----------|
| `*`       | Modified  |
| `R`       | Read-only |
| `T`       | Terminal  |
| `P`       | Pinned    |

Selecting a buffer switches to it immediately.

### Git (`g`)

Displays the working tree status organized into four categories:

| Prefix | Category    |
|--------|-------------|
| `S`    | Staged      |
| `M`    | Unstaged    |
| `?`    | Untracked   |
| `C`    | Conflict    |

Selecting a label opens the file. Press mode-specific action keys to stage, unstage, or view diffs.

### Symbols (`s`)

Queries the current buffer for document symbols via ctags. Each entry shows the symbol kind icon, name, and line number. Selecting a symbol jumps the cursor to its definition in the main window.

### Outline (`o`)

Provides a per-file structural outline based on the buffer's filetype:

| Filetype    | Parses                              |
|-------------|-------------------------------------|
| Markdown    | `#` through `######` headings       |
| Lua         | `function`, `local function`, `M.*` |
| Vimscript   | `function!`, `command!`, `def`      |
| Python      | `class`, `def`                      |
| Other       | First 50 non-blank lines (truncated)|

Selecting an entry jumps the cursor to that line.

---

## Architecture

Nam is built around a decoupled, event-driven vim9script architecture.

```
autoload/nam/
├── init.vim              Entry point, Setup(), user commands
├── config.vim            Configuration defaults and deep merge
├── sidebar.vim           Window management (open/close/toggle)
├── renderer.vim          Virtual buffer rendering
├── labels.vim            Label engine (tier-based + overflow)
├── navigation.vim        Label dispatch and key handler
├── handler.vim           Legacy bridge for key mappings
├── project.vim           Root detection, file indexer
├── persistence.vim       Session save/restore (JSON)
├── workspace.vim         Pins, bookmarks, recent symbols, named workspaces
├── modes.vim             Mode registry and switching
├── buffers_mode.vim      Open buffer list
├── files_mode.vim        Flat file tree with paging
├── git_mode.vim          Git status and actions
├── git.vim               Git porcelain parser
├── symbols_mode.vim      Ctags-based symbols
├── outline_mode.vim      Per-file structural outline
├── events.vim            Internal event bus (emit/on/off)
└── cache.vim             TTL cache

plugin/
└── nam.vim               Plugin entry, commands
```

### Design decisions

- **No mode performs direct rendering** — the renderer owns all screen updates, enabling minimal redraw
- **Event bus decouples subsystems** — modes emit events without knowing who listens
- **Labels are addresses, not ordering** — the label map is a dictionary; selection is O(1)
- **Sidebar retains focus** — after opening a file, focus returns to the sidebar for uninterrupted browsing
- **TTL-based caching** — project scans and git status cached with configurable lifetimes for responsive mode switching

### Mode interface

Every mode implements this contract:

```vim
" Mode dict:
"   { name, icon, key, enabled, Refresh, Render, Select }
```

### Label engine tiers

| Tier | Keys           | Count |
|------|----------------|-------|
| 1    | `1234567890`   | 10    |
| 2    | `asdfghjkl`    | 9     |
| 3    | `qwertyuiop`   | 10    |
| 4    | `zxcvbnm`      | 7     |
|      |                 |       |
| **Total** |           | **36** |
| Overflow | `aa`, `ab`... | Unlimited |

---

## Performance

| Operation            | Target    |
|----------------------|-----------|
| Sidebar open         | <10 ms    |
| Mode switch          | <20 ms    |
| File open (keypress) | <50 ms    |
| Project scan (cold)  | <2 s      |
| Project scan (refresh)| <50 ms   |
| User access (DSN)    | <300 ms   |

Selection via DSN is O(1) label lookup — no cursor traversal, no tree expansion, no search.

---

## Testing

Tests use Vim's built-in scripting:

```bash
vim -N -u NONE -S tests/run_tests.vim
```

Test specs live in `tests/vim_spec/`. The test runner provides `AssertTrue`, `AssertFalse`, `AssertEquals`, and `AssertNotEquals` functions.

---

## License

MIT. See `LICENSE` for details.

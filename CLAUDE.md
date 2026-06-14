# Nam — CLAUDE.md

## Project Overview

Production-grade Vim plugin providing IDE-class project/workspace management with **Direct Selection Navigation (DSN)** — single-keystroke file access eliminating cursor traversal entirely.

**Core innovation:** Sidebar → Press Label Key → Open File (O(1) navigation cost, target <300ms file access).

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | Vim >= 8.2 | Pure VimScript, zero external dependencies |
| Language | Vim9Script | Native Vim runtime, no compilation |
| Test framework | Vim built-in scripting | No external test dependencies |
| Optional deps | ctags, Git | Graceful degradation when absent |

## Architecture

```
autoload/nam/
├── init.lua              Entry point, setup(), user commands
├── config.lua            Configuration defaults and validation
├── ui/
│   ├── sidebar.lua       Window management (leftabove vsplit)
│   ├── renderer.lua      Virtual buffer rendering
│   └── labels.lua        Direct Selection Navigation label engine
├── core/
│   ├── navigation.lua    Label→action dispatch, key handler
│   └── project.lua       Project root detection, file indexer
├── modes/
│   ├── init.lua          Mode registry and interface
│   ├── buffers.lua       Open buffer list with status indicators
│   ├── files.lua         Project file tree (flat, label-addressed)
│   ├── git.lua           Git status view with stage/unstage/diff
│   └── symbols.lua       Ctags symbol outline
├── adapters/
│   ├── compat.lua        Platform abstraction layer
│   ├── git.lua           Git status parser, porcelain interface
│   └── treesitter.lua    Tree-sitter symbol extraction fallback
└── utils/
    ├── cache.lua         Weak-reference caches for project/git data
    └── events.lua        Internal event bus (emit/on)

plugin/
└── nam.vim  Autoload entry, user commands (:Nam)

tests/
├── spec/
│   ├── events_spec.vim
│   ├── config_spec.vim
│   ├── cache_spec.vim
│   ├── labels_spec.vim
│   ├── modes_spec.vim
│   ├── buffers_mode_spec.vim
│   ├── navigation_spec.vim
│   ├── files_mode_spec.vim
│   ├── git_mode_spec.vim
│   ├── symbols_mode_spec.vim
│   ├── outline_mode_spec.vim
│   ├── workspace_spec.vim
│   ├── persistence_spec.vim
│   └── integration_spec.vim
└── minimal_init.lua      Minimal test runner config
```

## Mode System

All views implement the Mode interface:

```vim
Mode = {
    name = "",           # Display name
    icon = "",           # Single char icon
    key = "",            # Hotkey to activate this mode
    refresh = function() end,  # Gather data
    render = function() end,   # Produce lines + label map
    select = function() end,   # Handle label selection
    actions = {}          # Mode-specific key actions (e.g., stage for git)
}
```

Modes are registered in the mode registry (`modes/init.vim`). New modes are plugins to the system.

### Mode Hotkeys

| Key | Mode |
|-----|------|
| b | Buffers |
| f | Files |
| s | Symbols |
| g | Git |
| o | Outline |

## Direct Selection Navigation (DSN) Engine

### Label Generation — 4 Tiers

| Tier | Keys | Count |
|------|------|-------|
| 1 | 1234567890 | 10 |
| 2 | asdfghjkl | 9 |
| 3 | qwertyuiop | 10 |
| 4 | zxcvbnm | 7 |
| **Total** | | **36 direct** |

Beyond 36 items: `aa`, `ab`, `ac` ... (two-char labels, EasyMotion-style).

### Selection Model

- **Existing trees:** O(n) cursor traversal
- **Nam:** O(1) label lookup via `label_map[label] = item`
- Subsequent open: standard Vim buffer switching (fast but not part of selection)

### Key Handler

```vim
def OnKey(key: string)
    var target = labels[key]
    if !empty(target)
        Open(target)
    endif
enddef
```

No cursor required. The pane is a command palette disguised as an IDE sidebar.

## Sidebar UI

- `leftabove {width}vsplit` vertical split window
- Fixed width (configurable, default 45 cols), left side
- Non-focus-stealing (can remain open while editing)
- Minimal redraw (only changed lines updated)
- Scratch buffer backing (no real file)

## Rendering Pipeline

```
Model (data) → Virtual Buffer (lines) → Renderer (highlights) → Sidebar
```

- No mode performs direct rendering
- Renderer owns all screen updates
- Full buffer replacement on refresh

## Workspace Manager

Equivalent to Eclipse/VSCode workspace concept:

- Stores: open files, window layout, pinned buffers, recent symbols, bookmarks
- Auto-save on exit, auto-restore on open
- Per-project workspace files (`~/.local/share/nam/workspaces/<name>.json`)
- JSON format for portability

## Performance Targets

| Operation | Target |
|-----------|--------|
| Sidebar open | <10ms |
| Mode switch | <20ms |
| File open (after keypress) | <50ms |
| Project scan (100k files, initial) | <2s |
| Project scan (refresh) | <50ms |
| File access (cognitive) | <300ms |

### Caching Strategy

- Project file tree: TTL-based, configurable lifetime
- Git status: TTL-based, configurable lifetime
- Ctags symbols: queried fresh on mode switch
- All caches use the TTL cache module (`utils/cache.vim`)

## Event System

Internal decoupled event bus (`utils/events.vim`):

```
Emit("buffer_changed")
Emit("git_updated")
Emit("project_rescanned")
Emit("mode_changed")
```

Modes subscribe to relevant events. No direct coupling between subsystems.

## Configuration

```vim
call nam#init#Setup({
    \ 'width': 45,
    \ 'hotkey': '<F2>',
    \ 'auto_open': v:false,
    \ 'labels': {
    \     'tiers': [
    \         '1234567890',
    \         'asdfghjkl',
    \         'qwertyuiop',
    \         'zxcvbnm',
    \     ],
    \     'overflow_style': 'double',
    \ },
    \ 'modes': {
    \     'buffers': {'enabled': v:true},
    \     'files': {'enabled': v:true},
    \     'symbols': {'enabled': v:true},
    \     'git': {'enabled': v:true},
    \     'outline': {'enabled': v:true},
    \ },
    \ 'workspace': {
    \     'auto_save': v:true,
    \     'auto_restore': v:true,
    \     'path': expand('~/.local/share/nam/workspaces/'),
    \ },
    \ 'cache': {
    \     'project_ttl': 30,
    \     'git_ttl': 5,
    \     'ctags_ttl': 10,
    \ },
    \ })
```

## Implementation Status

All five phases complete. VimScript codebase in `autoload/nam/`. Tests in `tests/vim_spec/` use Vim's built-in test assertions.

## Testing

```bash
vim -N -u NONE -S tests/run_tests.vim
```

Test specs live in `tests/vim_spec/`. The test runner provides `AssertTrue`, `AssertFalse`, `AssertEquals`, and `AssertNotEquals`.

## GitHub

Target repo: `clearbellpaleforest`
Remote: needs `gh auth login` to configure

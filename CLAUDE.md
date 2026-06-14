# Vproj — CLAUDE.md

Vim project manager. A sidebar pane for browsing files, switching buffers, and managing project structure.

## Codebase

```
src/
├── plugin/vproj.vim           # Entry point — commands, default F4 mapping
└── autoload/vproj.vim         # All logic — Vim9Script
```

Two files. No Lua, no events, no cache layer.

## Architecture

Plain functions. State is script-local variables:

```
pane_bufnr, pane_width, current_mode, selected_line, current_dir, items
project, code_root
```

Commands change state then call `Render()` directly. No event bus, no CQS, no domain model.

## Modes

| Mode | Key | Shows |
|------|-----|-------|
| File | Shift-F | Directory browsing, file sizes, binary detection |
| Doc | Shift-D | Open buffers with flags + line counts |
| Code | Shift-C | Project tree from .vproj, include/exclude with +/- |

Enter on the mode menu line cycles between modes.

## Exported API

| Function | Purpose |
|----------|---------|
| `vproj#PaneToggle()` | Toggle pane open/closed |
| `vproj#PaneOpen()` | Open pane |
| `vproj#PaneClose()` | Close pane |
| `vproj#SwitchMode(key)` | Switch to 'file', 'doc', or 'code' |
| `vproj#SelectNext()` / `vproj#SelectPrev()` | Move selection |
| `vproj#SelectCurrent()` | Activate selected item |
| `vproj#PaneGrow()` / `vproj#PaneShrink()` | Width +/- 1 |
| `vproj#SetPaneWidth(n)` | Set exact width (20-80) |
| `vproj#NavigateUp()` | Parent directory |
| `vproj#Refresh()` | Re-render pane contents |
| `vproj#CloseBuffer()` | Close selected buffer (doc mode) |
| `vproj#ToggleInclude()` | Include/exclude item (code mode) |
| `vproj#RenameProject()` | Rename/create project (code mode) |
| `vproj#IsPaneVisible()` | Query visibility |
| `vproj#GetPaneWidth()` / `vproj#GetCurrentMode()` | Query state |
| `vproj#HandleBufWipeout()` | Cleanup on buffer wipe |
| `vproj#DefineHighlights()` | Define highlight groups |

## Pane Keybindings

Buffer-local (only active in the pane):

| Key | Action |
|-----|--------|
| j/k, Up/Down | Move selection |
| Left/Right | Shrink/grow width |
| Enter | Open file, switch buffer, cycle mode, or rename project |
| Shift-F | File mode |
| Shift-D | Doc mode |
| Shift-C | Code mode |
| r | Refresh pane |
| d | Close selected buffer (doc mode) |
| +/- | Include/exclude item (code mode) |
| q, F4 | Close pane |
| . | Parent directory |

## Commands

`:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`

Default mapping: `<F4>` toggles pane (uses `<Plug>VprojToggle` indirection).

## .vproj File Format

```
Project Name: my-project
Project Root: /home/user/dev/my-project
Included Directories:
src
Included Files:
README.md
Excluded Directories:
.git
node_modules
Excluded Files:
.env
```

## Code Mode Behavior

- No .vproj found: status line shows `* (no project found)`, all items in parentheses
- Enter on status line: rename/create project (inline via `input()`)
- `+` on non-included item: include in project, save .vproj
- `-` on included item: exclude from project, save .vproj
- No ex commands needed for project management

## Testing

```bash
vim --clean --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj.vim'
vim -N -u NONE -S tests/smoke.vim
```

## Vim9Script Notes

- `def` functions are strict: lambda vars must start with capital
- `readdir()` in `def`: no empty string filter argument
- Use `=~ ':$'` and `substitute()` instead of negative string slices
- Use `get(dict, 'key', default)` for optional dict keys
- Mappings use `<Cmd>` modifier to avoid command-line flicker
- ASCII-only for separator characters

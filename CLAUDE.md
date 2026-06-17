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
project, code_root, project_prompted, match_ids, show_info_column, current_page
items_per_page, paging_active, nav_offset, is_interactive
```

Commands change state then call `Render()` directly. No event bus, no CQS, no domain model.

## Modes

| Mode | Key | Shows |
|------|-----|-------|
| File | F | Directory browsing, file sizes, binary detection |
| Doc | D | Open buffers with flags + line counts |
| Code | C | Project tree from .vproj, include/exclude with +/- |

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
| `vproj#IncludeItem()` | Include item (code mode, + key) |
| `vproj#ExcludeItem()` | Exclude item (code mode, - key) |
| `vproj#RenameProject()` | Rename/create project (code mode) |
| `vproj#IsPaneVisible()` | Query visibility |
| `vproj#GetPaneWidth()` / `vproj#GetCurrentMode()` | Query state |
| `vproj#SelectFirst()` / `vproj#SelectLast()` | Jump to first / last item |
| `vproj#NavigateIntoFirstDir()` | Enter first subdirectory |
| `vproj#SelectByNavChar(ch)` | Jump to item by nav character |
| `vproj#ShiftNavForward()` / `vproj#ShiftNavBackward()` | Shift nav indicator range |
| `vproj#GetNavOffset()` | Get current nav offset |
| `vproj#ToggleInfoColumn()` | Toggle info column display |
| `vproj#NextPage()` / `vproj#PrevPage()` | Page through long listings |
| `vproj#OnDirChanged()` | Handle directory change event |
| `vproj#HandleBufWipeout()` | Cleanup on buffer wipe |
| `vproj#DefineHighlights()` | Define highlight groups |

## Pane Keybindings

Buffer-local (only active in the pane):

| Key | Action |
|-----|--------|
| j/k, Up/Down | Move selection |
| h/l | Parent directory / open or enter |
| Left/Right | Shrink/grow width |
| Enter | Open file, switch buffer, cycle mode, or rename project |
| F/D/C | File / Doc / Code mode |
| r | Refresh pane |
| x | Close selected buffer (doc mode) |
| +/- | Include / exclude item (code mode) |
| q, F4 | Close pane |
| . | Parent directory |
| Ctrl-T / Ctrl-B | Jump to first / last item |
| Ctrl-K / Ctrl-J | Parent dir / enter first subdir |
| F1 | Toggle info column |
| Ctrl-N / Ctrl-P | Next / previous page |
| Tab / Shift-Tab | Shift nav indicators |
| a-z, A-Z, 1-9 | Jump by nav character |

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
- `ItemIndex()` extracts the shared `(selected_line - FirstSelectableLine()) + (current_page * items_per_page)` formula used by SelectCurrent, CloseBuffer, and DoToggleInclude
- `getftype()` filters FIFOs/sockets/devices in ReadDir and CodeItems to prevent readblob hangs

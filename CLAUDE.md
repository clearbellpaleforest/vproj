# Vproj — CLAUDE.md

Vim project manager. A single-pane file browser and buffer switcher.

## Codebase

```
src/
├── plugin/vproj.vim           # Entry point — commands, default F4 mapping
└── autoload/vproj.vim         # All logic — ~580 lines Vim9Script
```

Two files. No Lua, no events, no cache layer.

## Architecture

Plain functions. State is script-local variables in `autoload/vproj.vim`:

```
pane_bufnr, pane_width, current_mode, selected_line, current_dir, items
```

Commands change state then call `Render()` directly. No event bus, no CQS, no domain model.

## Modes

| Mode | Key | Shows |
|------|-----|-------|
| File | Shift-F | Directories + files with sizes, `readdir()` |
| Doc | Shift-D | Open buffers with flags + line counts, `getbufinfo()` |
| Code | Shift-C | Not implemented yet |

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
| `vproj#IsPaneVisible()` | Query visibility |
| `vproj#GetPaneWidth()` / `vproj#GetCurrentMode()` | Query state |
| `vproj#HandleBufWipeout()` | Cleanup on buffer wipe |
| `vproj#DefineHighlights()` | Define highlight groups |

## Pane Keybindings

These are buffer-local (only active in the pane):

| Key | Action |
|-----|--------|
| j/k, Up/Down | Move selection |
| Left/Right | Shrink/grow width |
| Enter | Open selected item |
| q, F4 | Close pane |
| . | Parent directory |

## Commands

`:VprojToggle`, `:VprojOpen`, `:VprojClose`

Default mapping: `<F4>` toggles pane (uses `<Plug>VprojToggle` indirection).

## Testing

```bash
vim --clean --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj.vim'
```

Then `:VprojToggle` to open the pane. `:messages` should be clean.

## Vim9Script Notes

- `def` functions are strict: lambda vars must start with capital (`SortFn` not `sortfn`)
- `readdir()` in `def` functions: no empty string filter argument
- `augroup!` pattern: use `augroup Name` / `autocmd!` / ... / `augroup END`
- ASCII-only for separator characters (no Unicode)

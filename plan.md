# vproj Implementation Plan

## Context
vproj is a Vim project manager. Full design in `doc/design.md`. Architecture decisions in `docs/adr/005` through `012`. This plan builds incrementally — each phase produces something testable.

**Target:** Vim 9.0+. `vim9script` throughout autoload. Plugin entry in legacy VimScript for compat.

## Files
- `src/plugin/vproj.vim` — guard, default keymap (F4), `:VprojToggle` command, highlight defines
- `src/autoload/vproj.vim` — all logic behind `vproj#` namespace; organized so it can split into `workspace.vim`, `navigation.vim`, `display.vim`, `project.vim` later

## Core Data Structures

**Script-local** (autoload, the workspace — single source of truth per ADR-005):
```
var ws = {
  pane_bufnr: -1,
  pane_width: 40,
  current_mode: 'file',
  selected_line: 1,
  nav_offset: 0,
  project: {
    name: '',
    root: '',
    display_root: '',
    included_dirs: [],
    included_files: [],
    excluded_dirs: [],
    excluded_files: [],
    vproj_file: '',
  },
}
```
- `ws` owns all runtime state. Nothing outside it may hold a diverging copy (ADR-005).
- Every function that changes `ws` is a Command. Every function that reads `ws` is a Query. Never both (ADR-006).
- Every Command emits exactly one named event on completion (ADR-007).

## Build Phases

### Phase 1: Pane Toggle
- `vproj#PaneToggle()` — if pane is open (bufwinnr > 0) → close; else → open
- `vproj#PaneOpen()` — `topleft vert new`, set buftype=nofile bufhidden=wipe nobuflisted noswapfile nomodifiable nowrap cursorline winfixwidth, `keepalt file VPROJ`, `vert resize` to `ws.pane_width`, store bufnr in `ws.pane_bufnr`
- `vproj#PaneClose()` — close pane window, reset `ws.pane_bufnr` to -1
- `vproj#IsPaneVisible()` — Query: returns bufwinnr(ws.pane_bufnr) > 0
- `vproj#DefineHighlights()` — VprojModeCurrent highlight group (bold,underline), idempotent via hlexists()
- Events emitted: `pane_opened`, `pane_closed`
- **Test:** F4 opens empty 40-col sidebar on left, F4 again closes it, `:VprojToggle` does the same

### Phase 2: Mode Menu Display
- `vproj#Render()` — setbufvar modifiable=1 → deletebufline all → BuildModeMenu + separator line → setbufline → setbufvar modifiable=0. Full redraw per ADR-011 Option A.
- `vproj#BuildModeMenu()` — `[F]ile  [D]oc  [C]ode` joined with two spaces, padded to pane_width with trailing spaces
- Separator: `repeat('─', ws.pane_width)` on line 2
- `vproj#HighlightCurrentMode()` — matchadd('VprojModeCurrent', pattern) for the active mode label on the menu line. Cleared via clearmatches() before re-render.
- `vproj#SetupPaneKeymaps()` — buffer-local nnoremap in the pane buffer:
  - `<Down>/j` → `vproj#SelectNext()`, `<Up>/k` → `vproj#SelectPrev()` (wrapping, skip separator line)
  - `<Right>` → `vproj#PaneGrow()`, `<Left>` → `vproj#PaneShrink()` (clamped 20–80)
  - `<CR>` → `vproj#SelectCurrent()` (dispatch based on cursor position in menu)
  - `<F4>/q` → `vproj#PaneClose()`
  - Block edit keys: i a o O r R c C d D x s p P u U all mapped to `<Nop>`
- `vproj#SwitchMode(key)` — set `ws.current_mode`, re-render, emit `mode_changed`
- `vproj#SelectCurrent()` — if on menu line (line 1), determine mode under cursor by column position and call `vproj#SwitchMode()`
- `vproj#SetupAutocommands()` — BufWipeout autocmd on pane buffer → `vproj#HandleBufWipeout()` resets state
- `vproj#PaneGrow()` / `vproj#PaneShrink()` — adjust `ws.pane_width` ±1, call `win_execute(wid, 'vert resize ' .. width)`, re-render, emit `width_changed`
- **Test:** F4 opens pane showing mode menu line + separator. Up/Down wrap between lines. Left/Right resize. Enter on `[F]ile` vs `[D]oc` vs `[C]ode` changes highlight. F4 closes. Reopen remembers width.

### Phase 3: .vproj File I/O
- `vproj#FindVprojFile(dir)` — glob `*.vproj` in dir, traverse parents, stop at `/home` or `/`. Returns path or empty string.
- `vproj#ParseVprojFile(path)` — readfile, line-oriented parser. State machine matching the format in ADR-008:
  - `Project Name: ...` → `ws.project.name`
  - `Project Root: ...` → `ws.project.root`
  - `Included Directories:` → next lines are dirs until next section
  - `Included Files:` → next lines are files
  - `Excluded Directories:` → next lines are dirs
  - `Excluded Files:` → next lines are files
  - Returns project dict. Malformed file → return empty dict with error logged.
- `vproj#WriteVprojFile(project)` — build line list from project dict, writefile(). Atomic: write to temp file, rename over target.
- `vproj#PromptCreateProject(dir)` — confirm("No .vproj found, create one? y/N"). If yes → input("Create project: ", fnamemodify(dir, ':t')). If non-empty → create .vproj, call ParseVprojFile, re-render.
- Wire into `vproj#PaneOpen()`: after opening pane, call FindVprojFile. If found → parse → set `ws.project`. If not found → PromptCreateProject.
- Events emitted: `project_loaded`, `project_created`
- **Test:** Create a .vproj manually. F4 → confirm parsed (echo ws.project.name). Delete .vproj, F4 in a dir → prompted to create. Create flow writes valid .vproj.

### Phase 4: File Mode
- `vproj#FileModeGetItems()` — Query. readdir(current_dir), filter out `.` and `..`. Classify dirs first (sorted), then files (sorted). For each: `{type, name, path, size, nav_key: ''}`. File sizes via getfsize(), formatted as 5-char right-aligned (e.g. ` 324K`, `  45M`, ` 1023`).
- `vproj#RenderFileMode()` — BuildModeMenu + separator + `..` line + item list + page nav row. Each item line: `a  src/` with nav indicator (cyan), one space, name, right-padded to width minus info column. Info column right-aligned in green.
- Status label: current path, right-aligned if it doesn't fit within pane width.
- `vproj#FileModeEnter()` — dispatch:
  - `..` → `vproj#NavigateUp()` (cd to parent, re-render FileModeGetItems)
  - Dir → `vproj#NavigateInto(name)` (cd into dir, re-render)
  - File → `vproj#OpenFile(path)` (switch to existing buffer or edit, close pane)
  - Binary file → echo status message, don't open
- Ctrl-K → NavigateUp, Ctrl-J → NavigateInto first subdir (no-op if none)
- F1 → toggle info column (set a flag in ws, re-render without the info column)
- Event emitted: `file_opened`, `root_changed`
- **Test:** F4 → File mode shows dir listing with `..` at top. Enter on dir descends. Enter on .. ascends. Enter on file opens it in previous window. Ctrl-K/J work. F1 toggles size column.

### Phase 5: Document Mode
- `vproj#DocModeGetItems()` — Query. getbufinfo() → filter listed buffers. For each: `{type, name, path, bufnr, flags, linecount, nav_key: ''}`. Flags from buffer attributes: `%` (current), `#` (alternate), `a` (active), `h` (hidden), `+` (modified), `-` (modifiable off), `=` (readonly). Linecount from getbufinfo().linecount (only valid when loaded).
- `vproj#RenderDocMode()` — same chrome as File mode. Info column shows flags + line count.
- `vproj#DocModeEnter()` — `execute 'buffer ' .. bufnr`, close pane. Emit `buffer_switched`.
- `vproj#SwitchMode(key)` updated — Shift-D switches to doc mode, calls `vproj#DocModeGetItems()` + `vproj#RenderDocMode()`
- **Test:** Open a few buffers. Shift-D → shows them with flags. Modified buffer shows `+`. Enter switches. Current buffer shows `%`.

### Phase 6: Navigation Indicators
- `vproj#AssignNavIndicators(items, offset)` — build list of 58 keys: `a-z` (26) + `A-Z` minus `F/D/C` (23) + `1-9` (9). Apply starting from offset. Items beyond position 57 get blank indicator. Return items with `nav_key` set.
- BuildItemList updated: first assign `*` to project name row, no indicator to `..` row, then call AssignNavIndicators for remaining items. Apply `ws.nav_offset`.
- `vproj#SetupNavKeymaps()` — buffer-local nnoremap for every lowercase letter a-z, every uppercase A-Z minus F/D/C, every digit 1-9. Each maps to `vproj#SelectByNavKey(key)`. Also `*` → select project name, `.` → NavigateUp.
- `vproj#SelectByNavKey(key)` — find item with matching nav_key in current item list, move cursor to its line, set ws.selected_line. If no match, no-op.
- `vproj#ShiftNavDown()` (TAB) — if total navigable items ≤ 58, no-op. Otherwise increment ws.nav_offset by 58, wrap to 0 if past end. Re-assign indicators, re-render. Emit `nav_shifted`.
- `vproj#ShiftNavUp()` (Shift-TAB) — reverse: decrement ws.nav_offset by 58, wrap to last page if negative.
- Page navigation: Ctrl-N/Ctrl-P adjust a page_offset (visual page, independent of nav_offset). Page nav row shown as last line: `>>> Page 1/4 CTRL-N CTRL-P <<<`. Page height = pane height - 3 (menu + separator + page row, with page row only shown when needed).
- **Test:** Dir with 100+ files. First 58 get a-z, A-Z, 1-9. TAB relabels next 58. Shift-TAB goes back. Wrapping works. Paging and relabeling are independent — Ctrl-N pages through items, TAB shifts labels.

### Phase 7: Code Mode + Include/Exclude
- `vproj#CodeModeGetItems()` — Query. Build tree relative to `ws.project.display_root`. For each dir/file in current root: check against project.included_dirs/files and project.excluded_dirs/files. Included items shown normally. Non-included items listed last with parentheses around name.
- Project name displayed on line 2 (below menu). `.. [dir name]` on line 3 for parent nav (within project root).
- `vproj#CodeModeEnter()` — dispatch: directory → set display_root, re-render. `..` → ascend display_root (stop at project root). File → open.
- `vproj#IncludeItem()` (Shift+I) — if selected item is not in included lists, add to included_dirs or included_files (path relative to project root). Remove from excluded if present. Save .vproj. Re-render. Emit `item_included`.
- `vproj#ExcludeItem()` (Shift+X) — add to excluded_dirs or excluded_files. Remove from included if present. Save .vproj. Re-render. Emit `item_excluded`.
- `vproj#RenameProject()` — `*` key selects project name. Enter → input("Rename project: ", ws.project.name). If non-empty and changed → rename .vproj file, update ws.project.name, re-render. Emit `project_renamed`.
- **Test:** Shift-C → project tree. Non-included items in parens. I on a paren item includes it (moves to normal). X on an included item excludes it (moves to parens). `*` + Enter renames. `..` navigates up. Dir descends change root.

### Phase 8: Configuration + Polish
- `vproj#ReadConfig()` — read environment variables:
  - `VPROJ_pane-width_default` | `VPROJ_pane-width_file` | `VPROJ_pane-width_doc` | `VPROJ_pane-width_code` — each parsed as number, clamped 20–80, defaults to 40
  - `VPROJ_mode-display-location` — "TOP" or "BOTTOM" (case-insensitive, takes `t`/`b` prefix). Controls whether mode menu renders on line 1 or last line.
- `vproj#ApplyModeWidth(mode)` — when switching mode, apply mode-specific width from env vars (fall back to default)
- Handle pane deleted externally: before any pane operation, check bufwinnr(ws.pane_bufnr) and bufexists(). If buffer wiped externally, reset ws.pane_bufnr.
- Handle missing parent window: when closing pane, verify the window we're returning to still exists
- Filter out `.` and `..` from all readdir() calls
- Prevent duplicate entries in project include/exclude lists
- Graceful handling of malformed .vproj files (return partial dict, log warning)
- Add `exists('*vproj#...')` guards where cross-module calls happen (for future file split)

## Verification
After each phase:
1. `vim --clean --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj.vim'`
2. Press F4, test the phase's specific behavior
3. `:messages` — should be clean, no errors
4. All prior phase behavior must still work (no regressions)

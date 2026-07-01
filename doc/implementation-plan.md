# Implementation Plan

## Philosophy

Development proceeds incrementally. Each stage results in a usable system.
At no point should the project require a complete rewrite to continue
development.

## Stages

### Stage 1: Pane Infrastructure

- Script-local state variables
- `PaneToggle()`, `PaneOpen()`, `PaneClose()`
- Scratch buffer creation, window management
- Buffer-local keybindings (`SetupPaneMappings()`)
- `Render()` skeleton
- Mode menu line (cycling via Enter)
- Width control (`PaneGrow()`, `PaneShrink()`, `SetPaneWidth()`)
- Selection movement (`SelectNext()`, `SelectPrev()`)
- Nav indicator assignment and Tab/Shift-Tab relabeling (`nav_offset`)
- Paging (`current_page`, `items_per_page`, NextPage/PrevPage)
- Info column toggle (`ToggleInfoColumn()`)

**Gate:** Pane opens and closes. Selection moves. Nav indicators label and
relabel. Paging works. All width/display options functional.

### Stage 2: File Mode

- `ReadDir()` — directory listing with `readdir()` and `getftype()` filtering
- File size formatting (B/K/M/G)
- Binary detection via `readblob()` null-byte check
- Directory navigation (Enter on dir, ".." parent)
- File opening (Enter on file opens buffer in previous window)
- Status line showing current path with right-alignment
- Parent navigation (Ctrl-K, ".", h)
- First-subdir navigation (Ctrl-J)

**Gate:** Full file browsing. Open files. Navigate directory tree. Sizes and
binary detection work.

### Stage 3: Buffer Mode

- `BufItems()` — buffer list from `getbufinfo()`
- Buffer flag display (%, #, a, h, +)
- Line count for loaded buffers
- Buffer switching (Enter)
- Buffer closing (x, `CloseBuffer()`)
- `HandleBufWipeout()` for cleanup

**Gate:** Switch between buffers. Close buffers. Flags display correctly.

### Stage 4: Project Storage

- .vproj file parsing
- .vproj file writing
- Project creation prompt flow
- Upward search for .vproj files
- `project` dict structure
- `SaveProject()` — atomic overwrite

**Gate:** Parse and write .vproj files. Create new projects. Upward search
finds projects in parent directories.

### Stage 5: Code Mode

- `GitItems()` — project tree from .vproj
- Include/exclude (`ToggleInclude()`, `IncludeItem()`, `ExcludeItem()`)
- Project renaming (`RenameProject()`)
- Parenthetical display for non-included items
- Current root navigation within project
- No-project-found status message

**Gate:** Full project management. Include/exclude saves to .vproj. Rename
works. Tree displays correctly relative to current root.

### Stage 6: Configuration

- `g:vproj_show_dotfiles`
- `g:vproj_pane_width_default`
- Per-mode width overrides
- Graceful fallbacks when vars are unset

**Gate:** User can configure width and mode display position via .vimrc.

### Stage 7: Documentation

- concept.md (source material)
- docs/constraints.md
- docs/architecture.md
- docs/design.md
- docs/implementation-plan.md
- docs/test-plan.md
- docs/test-cases.md
- docs/decisions.md
- README.md (user-facing)

**Gate:** Complete documentation covering all subsystems, modes, and APIs.

### Stage 8: Advanced Features (Future)

- Source control integration
- Semantic search
- Project metrics
- Code analysis
- Workspace history

All implemented by wiring into the named event points defined in the
architecture.

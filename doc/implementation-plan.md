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
- Nav indicator assignment (a-z) and `>` / `<` block relabeling (`nav_offset`)
- Paging (`current_page`, `items_per_page`, NextPage/PrevPage)
- Info column toggle (`ToggleInfoColumn()`)

**Gate:** Pane opens and closes. Selection moves. Nav indicators label and
relabel. Paging works. All width/display options functional.

### Stage 2: File Mode

- `ReadDir()` — directory listing with `readdir()` and `getftype()` filtering
- File size formatting (B/K/M/G)
- Binary detection via `readblob()` null-byte check
- Directory navigation (Enter on dir, ".." parent)
- File opening (Enter on file opens it in the edit window; a temporary pane then closes, a permanent one stays)
- Status line (the pane window's `statusline`) showing current path with right-alignment
- Parent navigation (Ctrl-K, `.`)
- First-subdir navigation (Ctrl-J)

**Gate:** Full file browsing. Open files. Navigate directory tree. Sizes and
binary detection work.

### Stage 3: Buffer Mode

- `BufferList()` — buffer list from `getbufinfo({buflisted: 1})`
- Buffer flag display (`%` shown in a window, `+` modified)
- Line count for loaded buffers
- Buffer switching (Enter)
- Buffer closing (Shift-X, `CloseBuffer()`)
- `HandleBufWipeout()` for cleanup

**Gate:** Switch between buffers. Close buffers. Flags display correctly.

### Stage 4: Project Storage

- .vproj file parsing
- .vproj file writing
- Project creation prompt flow
- Upward search for .vproj files
- `project` dict structure
- `WriteVprojFile()` — atomic overwrite (temp file + rename)

**Gate:** Parse and write .vproj files. Create new projects. Upward search
finds projects in parent directories.

### Stage 5: Code Mode

- `CodeItems()` — project tree from .vproj
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

**Gate:** User can configure width and dotfile visibility via .vimrc. (A mode-display-position option was dropped; the mode menu is always line 1.)

### Stage 7: Documentation

- concept.md (source material)
- doc/constraints.md
- doc/architecture.md
- doc/design.md
- doc/implementation-plan.md
- doc/test-plan.md
- doc/test-cases.md
- doc/decisions.md
- README.md (user-facing)

**Gate:** Complete documentation covering all subsystems, modes, and APIs.

### Stage 8: Advanced Features

- Source control integration — **built**: git status column, `\s \d \D \c \p
  \u \b \z \Z \a`, Ctrl-G changed-only filter (file and code modes)
- Semantic search — future
- Project metrics — future
- Code analysis — future
- Workspace history — future

The remaining items are to be implemented by wiring into the named event points
defined in the architecture.

### Built beyond the original stages

- Tree view (Shift-T), file/buf preview (Shift-P), name filter (/), git grep
  into quickfix (*)
- File operations: `:VprojCopy` `:VprojDelete` `:VprojRename` `:VprojMove`
  (aliases `:Copy` `:Delete` `:Rename` `:Move` when free) and the Delete key
- Opt-in session saving (`$XDG_CACHE_HOME/vproj/session`, written only when `g:vproj_save_session = 1`)
- AI add-on (`autoload/vproj/ai.vim`): terminal chat on `A` in the pane,
  one-shot `:VprojAiPrompt` (see `implementation.md`, Stages 9-10)
- Agent add-on (`autoload/vproj/agent.vim`): `:VprojAgent`
- Log mode was built and later removed; there are four modes (File, Buf, Code,
  Qfix)

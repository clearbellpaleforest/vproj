# Vproj — CLAUDE.md

Vim project manager. A sidebar pane for browsing files, switching buffers,
and managing project structure.

## Rules

1. **Start with data.** Before drawing flows or sequences, draw the data. What
   the program needs to know, what owns it, where it can change, what invariant
   holds. Data structures outlast control flow and are harder to change later.
   Get them right first.

2. **Explicit control flow.** A reader should be able to read the code top to
   bottom and see who calls whom without charting it on paper. Functions call
   functions directly. No dispatchers, no registries, no callback chains whose
   destination you can't find with grep.

3. **One routine, one job.** A function that decides what to do and a function
   that knows how to do it are two functions. When a function does more than one
   thing, split it. When a file does more than one job, split it. But don't
   abstract until the pattern has repeated three times — an abstraction built on
   one example is a guess.

4. **Handle the error where it occurs.** A swallowed error today is a week of
   debugging next year. Check preconditions at every boundary — if caller A
   passes data to callee B, B checks A's inputs anyway, because A might be wrong
   tomorrow. Guard clauses first, happy path second.

5. **The user's machine is not yours.** `writefile()`, `delete()`, `rename()`,
   `mkdir()` — every call that touches the filesystem must trace back to an
   explicit user action. No automatic file creation, no surprise writes.

6. **Vim is not Python.** Look up the help for every builtin. `string()` adds
   quote characters. `getenv()` returns `v:null` for missing vars. `sort()`
   takes a Funcref, not a string name.

7. **Two source files.** `plugin/vproj.vim` is the public surface — commands,
   mappings, `<Plug>` indirections. `autoload/vproj.vim` is the implementation
   — all logic, all state. Plugin calls autoload. Never the reverse. Do not add
   a third file without approval.

## Development Process

1. **Human designs, AI critiques.** Project structure, subsystem boundaries,
   and file layout are designed by the human. AI reviews designs for gaps,
   inconsistencies, and edge cases but does not originate structural decisions.
   The human owns the architecture.

2. **Stage the work in small pieces.** Skeleton first — function signatures,
   data structures, comments explaining intent. Then fill in one piece at a
   time, testing at each step. A `plan.md` drives the build sequence. Never
   build more than one layer ahead of what is tested.

3. **Validate every input.** Assume nothing about input. Environment variables
   may be unset (`getenv()` returns `v:null`). Files may be missing. User input
   may be empty or malformed. Negative-path first — handle the failure case
   before the happy path. A program that fails cleanly is better than one that
   silently corrupts.

4. **Filesystem writes are dangerous.** A mistake with `writefile()`,
   `delete()`, or `rename()` can damage the user's machine. AI-generated code
   often mishandles these calls — `string()` adds quote characters in Vim,
   `getenv()` returns `v:null` for missing vars, and concatenating either into
   a path produces garbage. Every filesystem call must be explicit, justified,
   and correct before it ships. When in doubt, read-only.

## Documentation Structure

CONCEPT.MD is the source material living in docs/. Each docs/ file extracts
and elaborates one dimension. The docs/ directory is gitignored — design
documents are living references, not shipped artifacts.

```
docs/
├── CONCEPT.MD                 # Source material — vision, modes, navigation, architecture
├── constraints.md             # Hard boundaries — cross-platform, no deps, ASCII-only
├── architecture.md            # How the parts fit together — subsystems, data flow
├── design.md                  # Detailed behavioral spec — state, events, edge cases
├── implementation-plan.md     # Build order, staged milestones, stage gates
├── test-plan.md               # Testing strategy, coverage targets, categories
├── test-cases.md              # Concrete test vectors (TC001-N)
└── decisions.md               # Design decisions + rationale, especially divergences
```

## .gitignore

```
*.swp
*.swo
*~
.claude/
docs/
```

Swap files and backups are editor noise. `.claude/` is Claude Code internal
state. `docs/` is design reference material — not shipped with the plugin.

## Codebase

```
src/
├── plugin/vproj.vim           # Entry point — commands, default F4 mapping
├── autoload/vproj.vim         # All logic — Vim9Script
└── doc/
    ├── vproj.txt               # Help file
    └── tags                    # Help tag index
docs/                          # Per the 7-doc structure above
tests/
├── unit/
│   └── test_first_selectable.vim
├── integration/
│   ├── test_code_mode_full.vim
│   ├── test_doc_mode.vim
│   └── test_paging.vim
├── smoke.vim
├── final.vim
├── regression.vim
├── coverage.vim
├── edge_test.vim
├── keybindings.vim
├── demo.vim
├── hand_test.md
└── test_helpers.vim
```

Two source files. The plugin file declares the public surface. The autoload file
owns all logic and state. Nothing else.

## Architecture

Explicit imperative flow. State lives in script-local variables at the top of
the autoload file:

```
pane_bufnr, pane_width, current_mode, selected_line, current_dir, items
project, git_root, project_prompted, match_ids, show_info_column, current_page
items_per_page, paging_active, nav_offset, is_interactive
```

Commands change state then call `Render()`. The display is always a pure
function of current state — call Render at any time and you get an accurate
picture of the workspace. You can trace every state transition to its source by
reading the file top to bottom.

## Implementing a Feature

When adding a feature, follow this sequence:

1. **Identify the state.** What new information must the program remember? Add
   it to the script-local variable block at the top of the autoload file. If it
   needs initialization, set it there.

2. **Write the command.** Add a function to the autoload file. The function:
   validates inputs, changes state, calls `Render()`. That's it. Display logic
   lives in the render path, not in the command.

3. **Expose the entry point.** If the function is called from a mapping,
   command, or external plugin, add it to the Exported API table in
   `plugin/vproj.vim`. The plugin file is a table of contents — it declares
   what's public. The implementation stays in autoload. Plugin calls autoload.
   Never the reverse.

4. **Update the display.** `Render()` rebuilds the entire pane buffer from
   state. Add the rendering logic for any new visible information there. The
   display reads state. It never modifies it.

5. **Add keybindings.** If the feature gets a key, add it to the buffer-local
   mappings in `MapKeys()`. Keep the mapping table sorted by key so a reader can
   find bindings without scanning the whole file.

6. **Test.** Unit tests in `tests/unit/` for function invariants. Integration
   tests in `tests/integration/` for end-to-end behavior through the public API.

## Modes

| Mode | Key | Shows |
|------|-----|-------|
| File | f | Directory browsing, file sizes, binary detection |
| Buf | b | Open buffers with flags + line counts |
| Git | g | Project tree from .vproj, include/exclude with +/- |
| Qfix | q | Quickfix list — filename:lnum, entry text |

Enter on the mode menu line cycles between modes.

## Exported API

| Function | Purpose |
|----------|---------|
| `vproj#PaneToggle()` | Toggle pane open/closed |
| `vproj#PaneOpen()` | Open pane |
| `vproj#PaneClose()` | Close pane |
| `vproj#SwitchMode(key)` | Switch to 'file', 'buf', 'git', or 'qfix' |
| `vproj#SelectNext()` / `vproj#SelectPrev()` | Move selection |
| `vproj#SelectCurrent()` | Activate selected item |
| `vproj#PaneGrow()` / `vproj#PaneShrink()` | Width +/- 1 |
| `vproj#SetPaneWidth(n)` | Set exact width (20-80) |
| `vproj#NavigateUp()` | Parent directory |
| `vproj#Refresh()` | Re-render pane contents |
| `vproj#CloseBuffer()` | Close selected buffer (buf mode) |
| `vproj#ToggleInclude()` | Include/exclude item (git mode) |
| `vproj#IncludeItem()` | Include item (git mode, + key) |
| `vproj#ExcludeItem()` | Exclude item (git mode, - key) |
| `vproj#RenameProject()` | Rename/create project (git mode) |
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
| f/b/g/q | File / Buf / Git / Qfix mode |
| r | Refresh pane |
| x | Close selected buffer (buf mode) |
| +/- | Include / exclude item (git mode) |
| Q, F4 | Close pane |
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

## Git Mode Behavior

- No .vproj found: status line shows `* (no project found)`, all items in parentheses
- Enter on status line: rename/create project (inline via `input()`)
- `+` on non-included item: include in project, save .vproj
- `-` on included item: exclude from project, save .vproj
- No ex commands needed for project management

## Testing

```
tests/
├── unit/
│   └── test_first_selectable.vim   # FirstSelectableLine mode-awareness
├── integration/
│   ├── test_git_mode_full.vim     # Git mode layout, mode switching
│   ├── test_buf_mode.vim           # Buf mode with real buffers
│   ├── test_paging.vim             # Paging with 60-item directory
│   └── test_qfix_mode.vim          # Qfix mode display, jump-to-entry, empty state
├── smoke.vim                       # Basic open/close
├── final.vim                       # Audit fix verification
├── regression.vim                  # Regression checks
├── coverage.vim                    # Comprehensive API coverage
├── edge_test.vim                   # Edge cases, boundary conditions
├── keybindings.vim                 # Keybinding dispatch
├── demo.vim                        # Interactive demo script
├── hand_test.md                    # Manual test checklist
└── test_helpers.vim                # Shared helpers (legacy Vimscript, unused)
```

Run all: `vim -N -u NONE -S tests/<test_file>.vim`

## Vim9Script Notes

- `def` functions are strict: lambda vars must start with capital
- `readdir()` in `def`: no empty string filter argument
- Use `=~ ':$'` and `substitute()` instead of negative string slices
- Use `get(dict, 'key', default)` for optional dict keys
- Mappings use `<Cmd>` modifier to avoid command-line flicker
- ASCII-only for separator characters
- `ItemIndex()` extracts the shared `(selected_line - FirstSelectableLine()) + (current_page * items_per_page)` formula used by SelectCurrent, CloseBuffer, and DoToggleInclude
- `getftype()` filters FIFOs/sockets/devices in ReadDir and GitItems to prevent readblob hangs

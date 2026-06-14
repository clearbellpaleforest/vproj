# Vproj — Development Plan

## Methodology

1. **Skeleton first** — Design the module structure with human reasoning. Use AI only for
   comments during this phase. Each file gets its interface contract (exports,
   function signatures, type annotations) before any implementation.
2. **Stage by stage** — Fill in one module at a time. Test before moving on.
3. **Validate all input** — Every function that accepts external data (env vars,
   user config, file contents, JSON) must validate before acting. Never assume
   input is well-formed.
4. **Negative paths** — Every code path that can fail must fail gracefully. No
   silent corruption, no crash loops, no `:catch` without a fallback.

## Validation Rule (mandatory)

Every function receiving data from outside the module MUST validate:
- **Type** — is this the Vim type we expect? (v:t_string, v:t_dict, v:t_list, v:t_bool, v:t_number)
- **Shape** — if dict: does it have required keys of correct types? if list: is length bounded?
- **Content** — if a path: does it look like a real path? if a command: does it match a known set?
- **Bounds** — if a count or size: is it within reasonable limits?

Validation failures must abort the operation and return a safe default or error,
never proceed with unvalidated data.

## Architecture Skeleton

```
autoload/vproj/
├── init.vim           Entry point, user commands, setup dispatch
├── config.vim         Configuration defaults, validation, merge
├── labels.vim         DSN label engine (tier system, overflow)
├── renderer.vim       Virtual buffer rendering, highlight groups
├── sidebar.vim        Window management (split, resize, toggle)
├── handler.vim        Key handler dispatch (mode hotkeys, DSN keys)
├── modes.vim          Mode registry (register, switch, get current)
├── project.vim        Project root detection, file tree scanner
├── navigation.vim     Label→action dispatch
├── events.vim         Internal decoupled event bus
├── cache.vim          TTL-based generic caching
├── git.vim            Git porcelain parser, status model
├── workspace.vim      Workspace manager (save/restore session bundle)
├── persistence.vim    Per-project JSON session file I/O
│
├── buffers_mode.vim   Mode: open buffer list with status indicators
├── files_mode.vim     Mode: project file tree with labels
├── git_mode.vim       Mode: git status with stage/unstage/diff
├── symbols_mode.vim   Mode: ctags symbol outline
└── outline_mode.vim   Mode: buffer-local outline (folds, sections)
```

### Interface Contracts

Each module exports a known set of public functions. Internal helpers are
script-local (`def` without `export`). No module may call another module's
internal functions.

| Module | Exports | Dependencies |
|--------|---------|--------------|
| `config.vim` | `Setup()`, `Get()` | none |
| `events.vim` | `Emit()`, `On()` | none |
| `cache.vim` | `New()`, `Get()`, `Set()`, `Invalidate()` | none |
| `sidebar.vim` | `Open()`, `Close()`, `Toggle()`, `IsOpen()` | renderer |
| `labels.vim` | `Generate()`, `Lookup()` | none |
| `renderer.vim` | `Render()`, `Clear()` | none |
| `handler.vim` | `OnKey()`, `OnModeKey()` | labels, navigation, modes |
| `modes.vim` | `Register()`, `Switch()`, `GetCurrent()` | none |
| `project.vim` | `FindRoot()`, `ScanFiles()` | cache |
| `navigation.vim` | `Dispatch()` | labels |
| `git.vim` | `Status()`, `StageFile()`, `UnstageFile()`, `DiffFile()` | none |
| `workspace.vim` | `SaveWorkspace()`, `RestoreWorkspace()` | persistence, project |
| `persistence.vim` | `Setup()`, `Save()`, `Restore()`, `Clear()`, `ClearAll()` | none |
| `*_mode.vim` | Mode interface (`refresh`, `render`, `select`, `actions`) | modes, renderer |

## Development Stages

### Stage 0 — Foundation (skeleton + contracts)
**Goal:** All files exist with correct `vim9script` header, module-level vars,
exported function signatures, and doc comments. Zero implementation.
Functions return stub values (empty dicts, false, empty strings).
**Validation gate:** Every file passes `:source` without errors.

### Stage 1 — Config & Events
**Files:** `config.vim`, `events.vim`
**What:** Configuration validation/merge and the event bus.
**Tests:** `config_spec.vim`, `events_spec.vim`
**Validation checkpoints:**
- `config.Setup()` rejects non-dict, missing required keys, wrong types
- `events.Emit()` no-ops when no listeners registered (no crash)
- `events.On()` validates callback is a Funcref

### Stage 2 — Cache & Project
**Files:** `cache.vim`, `project.vim`
**What:** TTL cache with weak references, project root detection, file scanning.
**Tests:** `cache_spec.vim`, `project_spec.vim` (if test file exists)
**Validation checkpoints:**
- `cache.New()` validates TTL is a positive number
- `project.FindRoot()` handles non-directories, non-git repos, missing ctags
- File scanner handles unreadable directories, symlink loops (depth cap)
- All paths validated before `readdir()`/`glob()` calls

### Stage 3 — Labels & Renderer
**Files:** `labels.vim`, `renderer.vim`
**What:** DSN label generation (4 tiers + overflow), virtual buffer rendering.
**Tests:** `labels_spec.vim`
**Validation checkpoints:**
- Label generator handles 0 items, 1 item, >36 items (overflow)
- Renderer validates bufnum before `setbufline()`/`matchaddpos()`
- Renderer handles empty input list without crash
- Config label tiers validated (each tier is a string, no duplicate chars)

### Stage 4 — Sidebar & Handler
**Files:** `sidebar.vim`, `handler.vim`
**What:** Window management (split, resize, toggle), key dispatch.
**Tests:** Integration with renderer + labels
**Validation checkpoints:**
- `sidebar.Open()` validates width is a positive integer
- `sidebar.Open()` handles already-open (no double split)
- Handler validates key before dispatch (no crash on unknown keys)
- Handler routes mode hotkeys to `modes.Switch()`, DSN keys to `navigation.Dispatch()`

### Stage 5 — Modes Registry & Navigation
**Files:** `modes.vim`, `navigation.vim`
**What:** Mode registration/switching, label→action dispatch.
**Tests:** `modes_spec.vim`, `navigation_spec.vim`
**Validation checkpoints:**
- `modes.Register()` validates mode dict has required fields (name, key, render, select)
- `modes.Switch()` handles unknown mode key gracefully (no-op, not crash)
- `navigation.Dispatch()` validates label exists in label_map before acting
- Navigation handles label_map reload (stale labels after mode switch)

### Stage 6 — Git Adapter
**Files:** `git.vim`
**What:** Git porcelain parser, status model extraction.
**Tests:** `git_mode_spec.vim` (integration)
**Validation checkpoints:**
- Git status parser handles empty repo, detached HEAD, merge conflicts
- Parser validates `git status --porcelain` output line format before indexing
- All git command calls wrapped in try/catch with fallback to empty status
- Handles git-not-installed (returns empty, not crash)

### Stage 7 — Mode Implementations
**Files:** `buffers_mode.vim`, `files_mode.vim`, `git_mode.vim`, `symbols_mode.vim`, `outline_mode.vim`
**What:** Each mode implements the Mode interface (`refresh`, `render`, `select`, `actions`).
**Tests:** `buffers_mode_spec.vim`, `files_mode_spec.vim`, `git_mode_spec.vim`, `symbols_mode_spec.vim`, `outline_mode_spec.vim`
**Validation checkpoints:**
- Every mode's `refresh()` handles no data (empty project, no buffers, no git)
- Every mode's `render()` handles empty refresh results
- Every mode's `select()` validates the label exists before acting
- `files_mode` handles unreadable directories (skip, don't crash)
- `symbols_mode` handles missing ctags (graceful degradation)
- `git_mode` actions (stage/unstage/diff) validate file path before shelling out

### Stage 8 — Persistence & Workspace
**Files:** `persistence.vim`, `workspace.vim`
**What:** Session JSON I/O with atomic writes, workspace save/restore bundle.
**Tests:** `persistence_spec.vim`, `workspace_spec.vim`
**Validation checkpoints:**
- `persistence.Save()` validates state dict before `json_encode()`
- `persistence.Restore()` validates JSON schema before acting on any field
- `persistence.Restore()` caps buffer count (MAX_RESTORE_BUFFERS = 50)
- `persistence.Restore()` validates each buffer path starts with `/` or `~`
- `persistence.Clear()`/`ClearAll()` validate filepath before `delete()`
- `persistence.Setup()` validates cfg is a dict, workspace sub-fields have correct types
- All environment variable reads (`XDG_CACHE_HOME`) fall back gracefully when unset/empty/invalid
- `workspace.RestoreWorkspace()` validates persisted window_layout before `:execute`

### Stage 9 — Init & Integration
**Files:** `init.vim`, `plugin/vproj.vim`
**What:** Entry point wiring, user commands (`:Vproj`), autocmd setup.
**Tests:** `integration_spec.vim`
**Validation checkpoints:**
- `init.Setup()` validates entire config dict before dispatching to subsystems
- User commands validate arguments before forwarding
- All autocmds have guard conditions (don't fire in special buffers)
- Graceful degradation when optional dependencies (ctags, git) are missing

## Test Gate

Before marking any stage complete:

```bash
vim -N -u NONE -S tests/run_tests.vim
```

Must exit 0 with no failures. Each stage adds its own spec files to the test
suite. A stage is not complete until its tests pass.

## Input Validation Patterns

These patterns must appear at every external-data boundary:

```vim
# 1. Type check at function entry
def SomeFunc(data: any): bool
  if type(data) != v:t_dict
    return false
  endif
  # ... proceed with validated data
enddef

# 2. Environment variable with fallback
def GetDir(): string
  var raw: string = getenv('SOME_VAR')
  if empty(raw) || raw ==# ''
    return expand('~') .. '/.local/share/default'
  endif
  var expanded: string = expand(raw)
  if empty(expanded) || expanded !~# '^/\|^~/'
    return expand('~') .. '/.local/share/default'
  endif
  return expanded
enddef

# 3. JSON schema validation before field access
var decoded: any = json_decode(raw)
if type(decoded) != v:t_dict
  return false
endif
var state: dict<any> = decoded
if !has_key(state, 'version') || type(state.version) != v:t_number
  return false
endif

# 4. Path validation before filesystem operations
if filepath !~# '/expected_dir/expected_prefix_'
  return
endif
if filereadable(filepath)
  delete(filepath)
endif

# 5. Bounded iteration over external data
const MAX_ITEMS: number = 50
var count: number = 0
for item in external_list
  if count >= MAX_ITEMS | break | endif
  if type(item) == v:t_string && item != '' && item =~# '^[/~]'
    # ... process item
    count += 1
  endif
endfor
```

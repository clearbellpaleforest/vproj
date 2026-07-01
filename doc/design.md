# Design

## State

All runtime state is script-local in `autoload/vproj_ai.vim`:

```
pane_bufnr, pane_width, current_mode, selected_line, current_dir, items
project, git_root, match_ids, show_info_column, current_page
items_per_page, paging_active, nav_offset, original_cwd, saved_shortmess, cursor_match_id
```

The state block is the workspace. No state lives outside it.

## Control Flow

```
User Input -> Command (validates, changes state) -> Render() (reads state, builds display)
```

Render produces the entire pane buffer from state. It is idempotent — call it
at any time and the display is correct. No incremental updates, no dirty flags,
no partial re-renders. Clear buffer, rebuild from scratch.

## AI State

AI-specific script-local state:

```
ai_api_url, ai_api_key, ai_last_prompt, ai_last_response, ai_history
```

`ai_history` is a list of {prompt, response} dicts, bounded at 5 entries,
providing conversation continuity within a session.

## AI Control Flow

```
User presses A -> GatherContext() -> input() prompt -> AiCall(prompt, context)
-> RouteResponse(text) -> cmdline | diff split | preview split | quickfix
```

Unlike the main Render path, AI calls are not idempotent (network side effects).
The flow is:
1. Gather context (read-only, never modifies state)
2. Prompt user for natural language query
3. Send to API (blocking `system()` call with timeout)
4. Route response to appropriate Vim surface
5. Append to ai_history

AI functions read workspace state but do not modify it. AI responses that
produce code changes go through existing commands (diff preview, buffer
modification) rather than writing directly.

## Pane Lifecycle

1. `PaneToggle()` — opens or closes the pane.
2. On open: determine mode (last used, or file mode on first open).
3. `InitPane()` — create scratch buffer, set buffer-local options, apply
   keybindings via `MapKeys()`.
4. `Render()` — populate buffer contents.
5. `PaneClose()` / `HandleBufWipeout()` — cleanup, restore window layout, restore
   `shortmess`.
6. `OnDirChanged()` — auto-refresh when Vim changes directory.
7. `HandleF1()` — global F1 handler: toggles info column inside pane, opens
   `:help` elsewhere.

## Modes

### File Mode (key: Shift-F)

Items: directories first (sorted, with trailing `/`), then files (sorted).

For each item:
- Nav indicator column (if within current nav window)
- Name column (truncated to fit)
- Info column (file size, 5 chars right-aligned: " 324K", "  45M")

Special lines:
- Line 1: mode menu ("F/D/C")
- Line 2: separator (dashes)
- Line 3: status line showing current path
- Parent directory ".." always present
- Paging row if items exceed pane height

Binary detection: `getftype()` identifies non-files. Non-regular files (FIFOs,
sockets, devices) are excluded from the listing. Binary files identified by
presence of null bytes in first 8KB (`readblob()` + `stridx()`).

Enter on file: open in right panel via `OpenInRightPanel()`, keep pane
visible on the left (two-panel layout). The right panel is reused for
subsequent file opens instead of stacking new splits.
Enter on directory: navigate into it (change `current_dir`, re-render).
Enter on "..": navigate up (parent of `current_dir`).

### Buf Mode (key: Shift-B)

Items: open buffers from `getbufinfo()`. Listed buffers only.

For each buffer:
- Nav indicator
- Buffer name (relative path where possible)
- Info column: flags from `getbufinfo()` — `%` (current), `#` (alternate),
  `a` (active), `h` (hidden), `+` (modified), line count if loaded

Enter on buffer: switch to it — uses `rightbelow split` if only pane window
exists, then `buffer <nr>`, then closes pane (buf mode replaces the layout
since the user is switching editing contexts).
x on buffer: `CloseBuffer()` — `bdelete` the selected buffer.

### Code Mode (key: Shift-C)

Items derived from .vproj_ai project file.

Layout (top to bottom):
1. Mode menu line
2. Separator
3. Project name line (nav indicator: `*`)
4. ".. [current root]" parent navigation
5. Included directories and files (project tree, shown relative to current
   root)
6. Non-included items in current root (shown in parentheses)
7. Paging row if needed

No .vproj_ai found: status line shows `* (no project found)`, all items in
parentheses. Enter on status line triggers project creation wizard: confirmation
prompt ("Create one? y/N"), then name prompt, then .vproj_ai written to disk.

Info column: code mode supports the F1 info column toggle. File sizes are shown
for non-directory items (5-char right-aligned, same format as file mode).

Enter on project name: `RenameProject()` — inline prompt via `input()`. If
renaming, new .vproj_ai is written before old file is deleted (safe against
write failures).
Enter on directory: navigate into it, changing `git_root`.
Enter on file: open in right panel via `OpenInRightPanel()`, keep pane visible
on the left (two-panel layout). Reuses existing right-side window.
`+` on non-included item: `IncludeItem()` — add to .vproj_ai, rewrite file.
`-` on included item: `ExcludeItem()` — remove from .vproj_ai, rewrite file.

### Qfix Mode (key: q)

Items: entries from `getqflist()`.

For each entry:
- Nav indicator (if within current nav window)
- Filename (path relative to CWD — `fnamemodify(..., ':.')`)
- Line number
- Entry text (truncated to fit)

Layout (top to bottom):
1. Mode menu line
2. Separator
3. Qfix entries (or "(no quickfix items)")

Enter on entry: jump to file:line in previous window, close pane.
Quickfix list is populated externally — by `:make`, `:grep`, `:vimgrep`,
`setqflist()`, or AI-driven analysis. VPROJ_AI reads it; it does not write it.

### Log Mode (key: L)

Items: git commit log from `git -C <root> log --oneline -n 30`.

For each commit:
- Nav indicator (if within current nav window)
- 7-char abbreviated hash
- Commit message (truncated to fit)

Layout (top to bottom):
1. Mode menu line (cyan `L` label)
2. Separator
3. Commit entries (or "no commits" if outside a git repo or empty history)

Enter on commit: opens a detailed diff split via `OpenCommitDetail()` showing
`git show --stat --format=fuller`. The commit view uses a vertical split layout:
log pane on the left, commit detail on the right. Both read-only, `q` closes the
detail view.

### Git Actions (file and code modes)

In file, code, and log modes, single-key git operations work on the item under cursor
or the whole repository:

- `s` — Stage/unstage file via `git add` / `git reset HEAD`
- `d` — Open diff preview in vertical split (`git diff` or `git diff --cached`)
- `D` — Discard file changes with confirmation prompt
- `c` — Commit with message prompt (`input()`)
- `P` — Push to remote
- `U` — Pull --ff-only from remote
- `b` — Switch branch (prompt via `input()`)
- `z` — Stash changes with optional message (`git stash push`)
- `Z` — Pop a stash with list preview and index selection (`git stash pop`)
- `a` — Git blame for file under cursor (split window, tracked files only)
- `Ctrl-G` — Toggle showing only git-changed files (file mode)

### Tree View (key: T, file mode only)

Indented directory tree with expand/collapse. T toggles between flat and tree
presentation within file mode. Tree state is independent of mode — switching
modes and returning to file mode restores the tree view state.

### File Preview (key: p, file mode only)

Split preview that shows contents of the file under cursor. Updates
automatically when the cursor moves. `botright vnew` creates the preview
window. Preview closes when the pane closes or p is pressed again.

### Filter and Grep (/ and * keys)

`/` prompts for a name pattern and filters the current listing to matching
items. Clearing the pattern (empty `input()`) restores the full listing.

`*` prompts for a grep pattern and runs `grep -rn` in the project root,
populating the quickfix list. Qfix mode is then available to navigate results.

## Navigation Indicators

Assigned dynamically: a-z, A-Z, 1-9, minus action keys (q/r/s/d/D/c/P/U/b/x/z/Z/a/ +/- /T/p/ / * / / ) and nav shift keys (< >).

The `*` indicator is reserved for the project name in code mode.

Nav offset (`nav_offset`) determines which block of items gets indicators.
Tab increments the offset by the number of visible indicators. Shift-Tab
decrements. Wrap at boundaries.

Paging is separate: Ctrl-N / Ctrl-P change `current_page`. Paging switches
which items are visible. Nav indicators relabel within the current page.

## Keybindings

Buffer-local mappings applied in the pane buffer only:

| Key | Function |
|-----|----------|
| j, Down | SelectNext |
| k, Up | SelectPrev |
| h | NavigateUp |
| l | SelectCurrent |
| Left | PaneShrink |
| Right | PaneGrow |
| Enter | SelectCurrent |
| Shift-F | SwitchMode('file') |
| Shift-B | SwitchMode('buf') |
| Shift-C | SwitchMode('code') |
| q | SwitchMode('qfix') |
| L | SwitchMode('log') |
| r | Refresh |
| x | CloseBuffer |
| + | IncludeItem |
| - | ExcludeItem |
| s | GitStageToggle |
| d | OpenDiffPreview |
| D | DiscardChanges |
| c | GitCommit |
| P | GitPush |
| U | GitPull |
| b | GitBranchSwitch |
| T | ToggleTreeView |
| p | TogglePreview |
| / | PromptFilter |
| * | GrepSearch |
| Q, F4 | PaneClose |
| . | NavigateUp |
| Ctrl-T | SelectFirst |
| Ctrl-B | SelectLast |
| Ctrl-K | NavigateUp |
| Ctrl-J | NavigateIntoFirstDir |
| Ctrl-G | ToggleGitFilter |
| F1 | ToggleInfoColumn |
| Ctrl-N | NextPage |
| Ctrl-P | PrevPage |
| Tab | ShiftNavForward |
| Shift-Tab | ShiftNavBackward |
| a-z, A-Z, 1-9 | SelectByNavChar |

Mappings use `<Cmd>` modifier to avoid command-line flicker, with `<nowait>` on
q to prevent Vim prefix-key timeout (q<register>).

Global `:call` mappings (not `<Cmd>`) for F1/Help — `<Cmd>` forbids
window-changing commands like `:help` in the else branch.

## Highlight Groups

Four mode-specific highlight groups with distinct colors:

| Group | Color | Use |
|-------|-------|-----|
| `VprojAiModeFile` | yellow | File mode label (bold, underline) |
| `VprojAiModeBuf` | green | Buf mode label (bold, underline) |
| `VprojAiModeCode` | blue | Code mode label (bold, underline) |
| `VprojAiModeQfix` | blue | Qfix mode label (bold, underline) |
| `VprojAiModeLog` | cyan | Log mode label (bold, underline) |
| `VprojAiCursorLine` | reverse | Selected line |
| `VprojAiNavIndicator` | cyan | Nav characters |
| `VprojAiInfoColumn` | green | File sizes / buffer info |
| `VprojAiParentDir` | blue | Parent directory entry |
| `VprojAiDirName` | bold | Directory names |
| `VprojAiSeparator` | dark grey | Separator lines |
| `VprojAiStatusLine` | reverse | Code mode status line |

Applied via `matchadd()` with auto-assigned IDs (`-1`). Mode label highlight
priority 10; nav indicators priority 11 (above cursor line at priority 9).
Mode label group is selected dynamically based on `current_mode`.

## .vproj_ai File Format

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

Section headers end with `:`. Items are listed one per line below their
header. Items are paths relative to the project root.

Parsing: read file lines, track current section, accumulate items per section.
Writing: rebuild file from in-memory project state, overwrite atomically.

## Display Layout

Pane width: 40 columns default (20-80 range).

Column layout (left to right):
```
[nav] [item name...            ] [info]
 2ch    variable width            5ch
```

Nav column: 2 characters (indicator + space). Blank if item outside nav window.
Info column: 5 characters, right-aligned. Hidden when `show_info_column` is 0.

Truncation: item name truncated to `pane_width - nav_column - info_column`.
Use `strcharpart()` not `strpart()` for multi-byte safety.

Separators: ASCII dash characters only. No Unicode box-drawing.

## Edge Cases

- Empty directory: show mode menu, separator, status, "..", and "(empty)".
- No buffers: show mode menu, separator, and "(no open buffers)".
- No .vproj_ai: code mode shows project prompt status.
- No quickfix entries: qfix mode shows "(no quickfix items)".
- Qfix entries with invalid bufnr: skip the entry.
- Quickfix list populated by setqflist() externally — VPROJ_AI reads only.
- Buffer wipe while pane open: `HandleBufWipeout()` checks if wiped buffer is
  pane buffer, cleans up if so.
- Directory change outside pane: `OnDirChanged()` refreshes current view.
- Very long filenames: truncated with no ellipsis (tight columns).
- Binary files: detected, Enter shows status message, does not open.
- FIFOs/sockets/devices: filtered by `getftype()` in ReadDir, never listed.
- Git stash: whole-repo operation, optional message. Stash pop lists stashes first.
- Git blame: file-specific only (file mode, regular files, git-tracked). Opens split with `git annotate`.

## Terminal Chat

### Architecture

The AI chat runs in a `:terminal` buffer via `bin/vproj-ai-chat`, a bash
script. Vim passes context (API key, endpoint, model, file info) via
environment variables in `term_start()`'s `env` dict. The bash script
handles the chat loop, JSON building, SSE parsing, and error display.

Why bash instead of Vimscript: `job_start`+`ch_open`+raw channel SSE parsing
is fragile and ~150 lines of complex Vimscript. A bash script with `curl` and
`read` is simpler, more portable, and has no circular dependency with vproj.

### State

Script-local variables in autoload/vproj_ai.vim:

| Variable | Type | Purpose |
|----------|------|---------|
| ai_api_url | string | API endpoint URL |
| ai_api_key | string | API authentication key |
| ai_model | string | Model name (deepseek-chat, gpt-4o-mini, etc.) |

No conversation state in Vimscript. The bash script owns the chat loop
and conversation history entirely. Vim only knows about the terminal buffer.

### AiTerminalChat() Flow

1. AiConfigure() — resolve API key, endpoint, model
2. GatherContext() — capture file, filetype, mode, cursor position
3. Write context dict as JSON to temp file
4. `botright new` + `execute 'resize 15'` — create 15-line split
5. `term_start(['bash', chat_script_path], {env: {...}})` — launch bash
6. Map `<Esc>` in terminal mode to close buffer
7. Log terminal creation to /tmp/vproj-ai-errors.log

### Bash Script (bin/vproj-ai-chat)

- Reads context from $VPROJ_AI_TMPFILE at startup
- Builds system prompt from file, filetype, and mode
- Loops: read prompt → json_escape() → build JSON messages → curl SSE →
  extract_delta() → print token → append to history
- json_escape(): pure bash, handles all JSON control characters
- extract_delta(): char-by-char parser for SSE `"content":"<value>"` extraction
- Fault injection via $VPROJ_AI_TEST_FAIL for testing (api_401, api_500,
  api_timeout, disk_full, empty_response, malformed_sse)

### Error Handling

| Condition | Behavior |
|-----------|----------|
| No API key | Script exits with message |
| API 401 | JSON error body shown, script exits |
| API 500 | JSON error body shown, script exits |
| curl error | ANSI red error with exit code and endpoint URL |
| Empty response | ANSI red message with exit code, endpoint, model |
| Non-SSE response | Raw response dumped (first 20 lines) |
| $VPROJ_AI_TEST=1 | Echo mode, no API call |

### Code Application

When the AI responds with code fences (```), the user can apply that code
via the `A` mapping in the response view. ApplyCodeToFile() extracts the
code block and inserts it into the target file at the appropriate location.

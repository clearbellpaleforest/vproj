# Design

## State

All runtime state is script-local in `autoload/vproj.vim`:

```
pane_bufnr, pane_width, current_mode, pane_open_mode, selected_line,
current_dir, items, show_info_column, current_page, items_per_page,
paging_active, nav_offset, filter_pattern, git_filter_active,
saved_origin_wid, project, code_root, tree_view_active, expanded_dirs,
preview_active, preview_bufnr, match_ids, cursor_match_id,
git_status_map / git_status_xy / git_status_orig, git_branch_cache,
git_root_cache, session_error
```

`current_mode` is one of `file`, `buf`, `code`, `qfix`; `pane_open_mode` is
`temporary` or `permanent`. `nav_offset` is a block number (block 0 letters
items 0-25, block 1 items 26-51, ...). The state block is the workspace. No
state lives outside it.

## Control Flow

```
User Input -> Command (validates, changes state) -> Render() (reads state, builds display)
```

Render produces the entire pane buffer from state. It is idempotent — call it
at any time and the display is correct. No incremental updates, no dirty flags,
no partial re-renders. Clear buffer, rebuild from scratch.

## AI State

The AI add-on (`autoload/vproj/ai.vim`, namespace `vproj#ai#`) keeps its own
script-local state:

```
ai_api_url, ai_api_key, ai_model, ai_url_rejected          (resolved settings)
ai_mode, ai_target_bufnr, ai_target_cursor_line            (per request)
stream_job, stream_accumulated, stream_cancelled, stream_full_response
```

There is no conversation history in Vimscript: the terminal chat's bash script
owns it (see Terminal Chat below), and `:VprojAiPrompt` is one-shot.

## AI Control Flow

Two entry points:

```
A in the pane   -> AiTerminalChat() -> bash chat script in a 15-line terminal
:VprojAiPrompt  -> AiPrompt(prompt) -> DetectMode() -> AiCallStream() (curl job)
                -> code: ApplyCode() after confirm()  |  question: ShowPopup()
```

Unlike the main Render path, AI calls are not idempotent (network side
effects). For `:VprojAiPrompt`:
1. `DetectMode()` classifies the prompt as code or question; a `!` or `?`
   prefix forces it.
2. `GatherContext()` reads the origin window's file, cursor and up to 100 lines
   either side (read-only, never modifies state).
3. `AiCallStream()` runs `curl` as a Vim job; the key and request body go to
   mode-0600 temp files, never the command line.
4. Code mode inserts the first fenced block below the cursor only after
   `confirm()` (Esc = No); a response with no fenced block is shown in a popup.
   Question mode shows a popup.

AI functions read workspace state but do not modify it. Code changes go into
the user's buffer through the normal buffer, so Vim's undo preserves the
pre-apply state.

## Pane Lifecycle

1. Entry points. Each opens the pane in a mode, 'temporary' or 'permanent',
   tracked in `pane_open_mode`:
   - `Tab` (`<Plug>VprojToggle`, `:VprojToggle`, `vproj#PaneToggle()`) is the
     temporary toggle. Pane closed: open in temporary mode. Temporary pane
     open: close it. Permanent pane open: switch it to temporary without
     closing.
   - `Shift-Tab` (`<Plug>VprojTogglePermanent`,
     `vproj#PaneTogglePermanent()`) is the permanent toggle. Pane closed: open
     in permanent mode. Permanent pane open: close it. Temporary pane open:
     switch it to permanent without closing. There is no ex command for it.
   - `:VprojOpen` / `vproj#PaneOpen()` open the pane (temporary mode) and do
     nothing if it is already visible; `:VprojClose` / `vproj#PaneClose()`
     close it in either mode.
   - `Tab` and `Shift-Tab` are only the defaults: they are mapped unless the
     user already maps the matching `<Plug>` name.
   - Mode difference: a temporary pane closes after a file is opened from it
     and on `Esc`. A permanent pane stays open after a file opens (focus
     returns to the pane) and `Esc` does nothing; `Shift-Q` in the pane closes
     a permanent pane (in a temporary pane it switches to qfix mode).
   - `User VprojPaneOpenedTemporary` / `VprojPaneOpenedPermanent` fire on each
     open or mode switch; `VprojPaneReady` fires when the pane is built.
2. On open: determine mode (from the session file if one exists, else file mode).
3. `PaneOpen()` creates the scratch buffer, sets buffer-local options and
   applies keybindings via `SetupPaneMappings()`; a session file is read first
   (`LoadSession()`) if one exists (reading needs no opt-in).
4. `Render()` — populate buffer contents.
5. `PaneClose()` / `HandleBufWipeout()` — if the user opted in with
   `g:vproj_save_session = 1`, save the session (mode, directory, width, info
   column, git filter to `$XDG_CACHE_HOME/vproj/session`; with the option off
   nothing is written); then clean up, restore window layout and `shortmess`.
6. `OnDirChanged()` — on `DirChanged` (global, tabpage, window) the git cache
   is invalidated and, in file/buf/qfix mode, the listing follows the new
   directory; code mode ignores it. A window-local change from another window
   is ignored.
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
- Line 1: mode menu (`[F]ile  [B]uf  [C]ode  [q]fix`)
- Line 2: separator (dashes); the current path and counts are in the pane's
  statusline
- Parent directory ".." always present (nav key `.`), except at filesystem root
- Paging row if items exceed pane height

Binary detection: `getftype()` identifies non-files. Non-regular files (FIFOs,
sockets, devices) are excluded from the listing. Binary files identified by
presence of null bytes in first 8KB (`readblob()` + `stridx()`).

Enter on file: `OpenFile()` shows it in the edit window chosen by
`EditTargetWindow()` (the window the user came from, else the first edit
window, else a new `botright vnew`), reusing it for subsequent opens. A
temporary pane then closes; a permanent pane stays open and keeps focus. An
unsaved buffer asks Yes/No/Cancel first; Cancel keeps the pane.
Enter on directory: navigate into it (change `current_dir`, re-render).
Enter on "..": navigate up (parent of `current_dir`).

### Buf Mode (key: Shift-B)

Items: listed, named buffers from `getbufinfo({buflisted: 1})`.

For each buffer:
- Nav indicator
- Buffer name (relative path where possible)
- Info column: `%` (shown in a window), `+` (modified), line count

Enter on buffer: `OpenBuffer()` switches the edit window to it (same
`EditTargetWindow()` rule as files); a temporary pane then closes, a permanent
one stays. Nav characters only move the cursor in this mode.
Shift-X on buffer: `CloseBuffer()` — closes the selected buffer (offers to
save a modified one).

### Code Mode (key: Shift-C)

Items derived from the project file (`.vproj`, found by `FindVprojFile()`
walking up from the current directory; a hand-named `*.vproj` is also accepted).

Layout (top to bottom):
1. Mode menu line
2. Status line: `* <project name>` (nav key none; `* (no project found)` when
   absent); the current directory is appended when it is below the project root
3. Separator
4. ".. <root>" parent navigation (unless at project root or `/`)
5. Included directories, then included files, then non-included directories
   and files (shown in parentheses), all relative to the current root
6. Paging row if needed

Enter on the status line: `RenameProject()`. With no project it asks
"Create one? (y/N)", then a name, and writes `<name>.vproj` in the current
root. With a project it prompts for a new name; the new file is written
before the old one is deleted (safe against write failures).

Info column: code mode supports the F1 info column toggle.

Enter on directory: navigate into it (`NavigateInto()`).
Enter on file: `OpenFile()`, same edit-window and pane-closing rule as file
mode.
`+` on a non-included item: `IncludeItem()` — add to the project, rewrite the
`.vproj` file. `-` on an included item: `ExcludeItem()` — remove it, rewrite.
Git actions and `Ctrl-G` work in code mode.

### Qfix Mode (key: Shift-Q in temporary mode)

Items: entries from `getqflist()`.

For each entry:
- Nav indicator (if within current nav window)
- Filename (path relative to CWD — `fnamemodify(..., ':.')`); entries with `valid` false are skipped
- Line number
- Entry text (truncated to fit)

Layout (top to bottom):
1. Mode menu line
2. Separator
3. Qfix entries (or "(no quickfix items)")

Enter on entry: `OpenQfixEntry()` jumps to file:line in the edit window; a
temporary pane then closes, a permanent one stays. Nav characters only move the
cursor. The quickfix list is populated by `:make`, `:grep`, `:vimgrep`,
`setqflist()`, or by the pane's own `*` grep. Qfix mode reads it; it does not
write it.

### Log Mode

Removed. There is no Log mode, no `L` key, and no commit-detail view.

### Git Actions (file and code modes)

Git operations act on the item under the cursor or the whole repository. Every
action uses a `\` prefix, because lowercase letters are nav characters:

- `\s` — Stage (`git add`, including untracked files) / unstage a file whose
  changes are only staged
- `\d` — Diff preview in a read-only vertical split (staged, unstaged or both); `q` closes
- `\D` — Discard, after a prompt that says what it will do: delete an untracked
  file, unstage a newly added file (kept), or revert all changes to HEAD
- `\c` — Commit with message prompt (`input()`)
- `\p` — Push; `\u` — Pull `--ff-only` (neither stops to ask for credentials)
- `\b` — Switch branch (prompt via `input()`)
- `\z` — Stash changes with optional message (`git stash push`)
- `\Z` — Pop a stash: lists stashes, prompts for an index (default top)
- `\a` — Git blame (`git annotate`) for the file under cursor, tracked files only
- `Ctrl-G` — Toggle showing only git-changed files

### File Operations (file mode)

`:VprojCopy`, `:VprojDelete`, `:VprojRename`, `:VprojMove` (aliases `:Copy`
`:Delete` `:Rename` `:Move`, defined only when no other plugin owns the name;
the `<Delete>` key does Delete). They act on the selected regular file, not on
directories. Copy writes `name_1.ext`, `name_2.ext`, ... in the same
directory. Delete confirms (default No). Rename prompts for a new name in the
same directory; Move prompts for a destination directory (with completion). Both
refuse an existing target. Delete, Rename and Move refuse while a buffer for the
file has unsaved changes; Rename and Move retarget windows showing it
(`RetargetBuffer()`).

### Tree View (key: Shift-T, file mode only)

Indented directory tree with expand/collapse. T toggles between flat and tree
presentation within file mode. Tree state is independent of mode — switching
modes and returning to file mode restores the tree view state.

### File Preview (key: Shift-P, file and buf modes)

Split preview that shows contents of the file (or directory listing) under the
cursor. Updates automatically when the cursor moves. `botright vnew` creates the
preview window. Preview closes when the pane closes, when switching to code or
qfix mode, or when Shift-P is pressed again.

### Filter and Grep (/ and * keys)

`/` prompts for a name pattern and filters the current listing to matching
items. Clearing the pattern (empty `input()`) restores the full listing.

`*` prompts for a grep pattern and runs `git grep` (case-insensitive) over the
repository, or over the pane's directory outside a repository, populating the
quickfix list; the pane then switches to Qfix mode to show the results. An empty pattern cancels; no match reports "no matches".

## Navigation Indicators

Assigned dynamically from `NAV_CHARS`: the 26 lowercase letters `a`-`z`. The
parent entry is always `.`. All actions are therefore Shift, Ctrl, `\` or
punctuation keys (see Keybindings).

Nav offset (`nav_offset`) is a block number: block 0 letters items 0-25, block
1 items 26-51, and so on. `>` (`ShiftNavForward`) moves to the next block and
`<` (`ShiftNavBackward`) to the previous one.

Paging is separate: Ctrl-N / Ctrl-P change `current_page`. Paging switches
which items are visible. Nav indicators relabel within the current page.

## Keybindings

Buffer-local mappings applied in the pane buffer only (`SetupPaneMappings()`):

| Key | Function |
|-----|----------|
| Down / Up | SelectNext / SelectPrev |
| Left / Right | PaneShrink / PaneGrow |
| Enter | SelectCurrent |
| Shift-F / Shift-B / Shift-C | SwitchMode('file' / 'buf' / 'code') |
| Shift-Q | HandlePaneQ (temporary: Qfix mode; permanent: close pane) |
| Esc | HandleEsc (closes a temporary pane; no-op in permanent) |
| R | Refresh |
| X | CloseBuffer (buf mode) |
| + / - | IncludeItem / ExcludeItem (code mode) |
| T | ToggleTreeView |
| P | TogglePreview |
| / | PromptFilter |
| * | GrepSearch |
| ? | ShowHelp |
| A | AI terminal chat (`vproj#ai#AiTerminalChat`) |
| Delete | DeleteSelected |
| . | parent directory (file and code mode, via VprojKey) |
| Ctrl-T / Ctrl-B | SelectFirst / SelectLast |
| Ctrl-K | NavigateUp |
| Ctrl-J | NavigateIntoFirstDir |
| Ctrl-G | ToggleGitFilter |
| Ctrl-N / Ctrl-P | NextPage / PrevPage |
| > / < | ShiftNavForward / ShiftNavBackward |
| \s \d \D \c \p \u \b \z \Z \a | git actions |
| a-z | SelectByNavChar (via VprojKey) |

Mappings use `<Cmd>` to avoid command-line flicker, with `<nowait>` on the
single-character keys.

Global mappings (`plugin/vproj.vim`): `<Tab>`, `<S-Tab>`, and `<F1>` / `<Help>`
(via `<Plug>VprojF1`). F1 uses `:call`, not `<Cmd>`, because `<Cmd>` forbids
window-changing commands like `:help` in the else branch.

## Highlight Groups

Four mode-specific highlight groups, defined by `DefineHighlights()` with
`highlight default link` so colorschemes can override them:

| Group | Links to | Use |
|-------|----------|-----|
| `VprojModeFile` | Title | File mode label |
| `VprojModeBuf` | Directory | Buf mode label |
| `VprojModeCode` | Special | Code mode label |
| `VprojModeQfix` | Question | Qfix mode label |
| `VprojCursorLine` | CursorLine | Selected line |
| `VprojNavIndicator` | (blue `#569CD6`) | Nav characters |
| `VprojInfoColumn` | Directory | File sizes / buffer info |
| `VprojParentDir` | String | Parent directory entry |
| `VprojDirName` | Directory | Directory names |
| `VprojSeparator` | Comment | Separator lines |
| `VprojStatusLine` | StatusLine | Code mode status line |

Git status groups (`VprojGitModified`, `...Added`, `...Deleted`, `...Renamed`,
`...Untracked`, `...Conflict`, `...Ignored`) link to diff/semantic groups.
Applied via `matchadd()` with auto-assigned IDs (`-1`). Mode label highlight
priority 10; nav indicators priority 11 (above cursor line at priority 9).
The mode label group is selected dynamically based on `current_mode`;
`ColorScheme` re-runs `DefineHighlights()`.

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

Section headers end with `:`. Items are listed one per line below their
header. Items are paths relative to the project root. `*` and `?` make a glob
entry; a trailing `/` on a directory is ignored; `#` lines before the first
section are comments and are kept on save. See `|vproj-file-format|` in the
help file for the full rules.

Parsing: `ParseVprojFile()` reads lines, tracks the current section, accumulates
items per section. Writing: `WriteVprojFile()` rebuilds the file from in-memory
project state.

## Display Layout

Pane width: 40 columns default (20-80 range).

Column layout (left to right):
```
[nav] [item name...            ] [info]
 2ch    variable width            5ch
```

Nav column: 2 characters (indicator + space). Blank if item outside nav block.
Info column: 5 characters, right-aligned. Hidden when `show_info_column` is 0.

Truncation: item name truncated to `pane_width - nav_column - info_column`.
Use `strcharpart()` not `strpart()` for multi-byte safety.

All text vproj prints is ASCII (rules are `-`/`=`, no Unicode box-drawing, arrows or
glyphs); comments may be UTF-8. See constraints.md "ASCII-Only Output".

## Edge Cases

- Empty directory: show mode menu, separator, "..", and "(empty)".
- No buffers: show mode menu, separator, and "(no open buffers)".
- No .vproj: code mode shows `* (no project found)`; Enter on it offers to create one.
- No quickfix entries: qfix mode shows "(no quickfix items)".
- Qfix entry whose buffer no longer exists: Enter reports "Cannot open".
- Quickfix entries with `valid` false are skipped.
- Buffer wipe while pane open: `HandleBufWipeout()` checks if wiped buffer is
  pane buffer, cleans up if so.
- Directory change outside pane: `OnDirChanged()` refreshes the file-mode view (code mode ignores it).
- Very long filenames: truncated with no ellipsis (tight columns).
- Binary files: detected, Enter shows an error, does not open.
- FIFOs/sockets/devices: filtered by `getftype()` in ReadDir, never listed.
- Git stash: whole-repo operation, optional message. Stash pop lists stashes first.
- Git blame: file-specific only (file and code mode, regular files, git-tracked). Opens split with `git annotate`.

## Terminal Chat

### Architecture

The AI chat runs in a `:terminal` buffer via `bin/vproj-ai-chat`, a bash
script. Vim passes the endpoint and model in environment variables, and the
API key and a JSON-encoded system message (including up to 100 lines of the
file around the cursor) as paths to mode-0600 temp files
(`VPROJ_AI_KEYFILE`, `VPROJ_AI_TMPFILE`), so no secret is in the environment
or on a command line. The bash script handles the chat loop, JSON building,
SSE parsing, and error display, and deletes the temp files (Vim deletes them
again on exit).

Why bash instead of Vimscript: `job_start`+`ch_open`+raw channel SSE parsing
is fragile and ~150 lines of complex Vimscript. A bash script with `curl` and
`read` is simpler, more portable, and has no circular dependency with vproj.

### State

Resolved settings are script-local in `autoload/vproj/ai.vim`: `ai_api_url`,
`ai_api_key`, `ai_model` (see AI State). No conversation state in Vimscript.
The bash script owns the chat loop and conversation history entirely. Vim only
knows about the terminal buffer.

### AiTerminalChat() Flow

1. Check `has('terminal')`, the chat script, `bash` and `curl`.
2. `ConfigureOrRefuse()` — resolve API key, endpoint (must be `https://`), model.
3. `GatherContext(OriginWindow())` — file, filetype, cursor, surrounding lines.
4. Write the system message and key to 0600 temp files.
5. `botright new` + `resize 15` — a 15-line split, reused by `term_start()`.
6. `term_start(['bash', chat_script_path], opts)` with `term_finish: 'close'`.
7. Map `<Esc>` in the terminal to `job_stop(..., 'term')`, which ends the chat
   and closes the window. `/exit`, `/q` or Ctrl-D also quit.

### Bash Script (bin/vproj-ai-chat)

- Reads the system message from `$VPROJ_AI_TMPFILE` and the key from
  `$VPROJ_AI_KEYFILE` at startup
- Loops: read prompt -> json_escape() -> build JSON messages -> curl SSE ->
  extract_delta() -> print token -> append to history
- json_escape(): pure bash, handles all JSON control characters
- extract_delta(): char-by-char parser for SSE `"content":"<value>"` extraction
- Fault injection via `$VPROJ_AI_TEST_FAIL` for testing (api_401, api_500,
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

The terminal chat only displays the conversation. Applying code is done by
`:VprojAiPrompt` (see AI Control Flow): in code mode `ApplyCode()` inserts the
first fenced block of the response below the cursor in the origin window's
buffer after a `confirm()`; `ExtractCodeBlocks()` finds the fences.

## Agent Add-on

`:VprojAgent` (`<Plug>VprojAgent`, no default key) calls `vproj#agent#AgentOpen()`,
which opens a terminal split running `g:vproj_agent_cmd`, or else the first of
`claude`, `codex` found on PATH. A configured command that cannot run is an
error; nothing else is substituted. The agent gets file context through
`$VPROJ_AGENT_CTX_FILE`, a private (0600) JSON file deleted when the agent
exits. Esc goes to the agent; the split closes when the agent exits.

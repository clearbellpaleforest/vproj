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
- Buffer-local keybindings (`MapKeys()`)
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

- .vproj_ai file parsing
- .vproj_ai file writing
- Project creation prompt flow
- Upward search for .vproj_ai files
- `project` dict structure
- `SaveProject()` — atomic overwrite

**Gate:** Parse and write .vproj_ai files. Create new projects. Upward search
finds projects in parent directories.

### Stage 5: Code Mode

- `CodeItems()` — project tree from .vproj_ai
- Include/exclude (`ToggleInclude()`, `IncludeItem()`, `ExcludeItem()`)
- Project renaming (`RenameProject()`)
- Parenthetical display for non-included items
- Current root navigation within project
- No-project-found status message

**Gate:** Full project management. Include/exclude saves to .vproj_ai. Rename
works. Tree displays correctly relative to current root.

### Stage 6: Configuration

- `g:vproj_ai_pane_width` default
- `g:vproj_ai_mode_display_location` (TOP/BOTTOM)
- Per-mode width overrides
- Graceful fallbacks when vars are unset

**Gate:** User can configure width and mode display position via .vimrc.

### Stage 7: Documentation

- CONCEPT.MD (source material)
- docs/constraints.md
- docs/architecture.md
- docs/design.md
- docs/implementation-plan.md
- docs/test-plan.md
- docs/test-cases.md
- docs/decisions.md
- README.md (user-facing)

**Gate:** Complete documentation covering all subsystems, modes, and APIs.

### Stage 9: AI Integration (vproj_ai)

**9a: API Layer**
- `g:vproj_ai_api_url` and `g:vproj_ai_api_key` configuration variables
- `AiCall(prompt, context)` — sends request to OpenAI-compatible API via `system()` with `curl`
- Graceful degradation when `curl` is unavailable
- Timeout handling and error surfacing
- Provider-agnostic: works with DeepSeek, OpenAI, any compatible endpoint
- `AiConfigure()` — resolves API key from g:vars and env vars, infers model from endpoint
- `BuildRequestBody()` — builds JSON with JsonEscape(), returns string for curl -d @file
- `JsonEscape()` — Vim9Script JSON string escaper (returns quoted string)

**Gate:** API call returns text from the model. Errors surface cleanly to user.

**9b: Context Gathering**
- `GatherContext(target_bufnr)` — assembles context dict from current state
- Editing buffer: file path, cursor position, filetype, file lines ±100
- Pane: selected item, current mode, project structure
- Context written to temp file as JSON for terminal chat (via `AiTerminalChat()`)

**Gate:** Context dict contains all relevant information without exceeding prompt budget.

**9c: AI Prompt Modes**
- `A` key in vproj pane opens terminal chat (`AiTerminalChat()`)
- `A` key in editing buffers opens floating popup (`AiPrompt(prompt, 'code')`)
- `:VprojAi` command for terminal chat
- Loading indicator via `echo` while waiting for response (popup mode)
- Cancel via Esc (popup mode)

**Gate:** User presses A, types query, sees streaming response in terminal.

**9d: Response Routing**
- `ApplyCodeToFile(code_text, target_bufnr)` — inserts code into target file
- Code blocks (``` fences) detected in response view, `A` maps to apply
- Vim's undo history preserves pre-apply state

**Gate:** Each response type routes to correct Vim surface.

**9e: Polish**
- Error states: network failure, API error, empty response
- API key not configured: prompt user to set `g:vproj_ai_api_key`
- All AI functions follow existing conventions: guard clauses, return '' on error

**Gate:** End-to-end flow works. Error states handled. Existing vproj features unaffected.

### Stage 10: Terminal Chat (vproj_ai)

**10a: Bash Chat Script (bin/vproj-ai-chat)**
- Pure bash SSE streaming chat loop (~210 lines)
- `json_escape()` for JSON-safe string escaping (all control characters)
- `extract_delta()` char-by-char parser for SSE content extraction
- Conversation history maintained in bash (JSON message array)
- Multi-turn with context from $VPROJ_AI_TMPFILE env var
- Fault injection via $VPROJ_AI_TEST_FAIL for testability
- Curl exit code capture and detailed error diagnostics

**10b: Vim Terminal Integration**
- `AiTerminalChat()` in autoload/vproj_ai.vim
- `botright new` + `execute 'resize 15'` for 15-line terminal
- `term_start(['bash', script_path], {env: {...}})` with env dict
- `<Esc>` maps to buffer close in terminal mode
- Temp file lifecycle managed with trap in bash script

**Gate:** Full multi-turn AI chat in terminal. SSE streaming works. All tests pass.

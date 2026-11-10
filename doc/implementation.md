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

### Stage 9: AI Integration (built; `autoload/vproj/ai.vim`, `vproj#ai#`)

**9a: API Layer**
- `g:vproj_ai_api_url`, `g:vproj_ai_api_key` and `g:vproj_ai_model` configuration variables (key also from `$DEEPSEEK_API_KEY` / `$OPENAI_API_KEY`; URL must be `https://`)
- `AiCall(prompt, context)` — blocking request to an OpenAI-compatible API via `curl` (key and body in 0600 temp files); `AiCallStream()` is the streaming `job_start` variant used by `:VprojAiPrompt`
- Graceful degradation when `curl` is unavailable
- Timeout handling and error surfacing
- Provider-agnostic: works with DeepSeek, OpenAI, any compatible endpoint
- `AiConfigure()` — resolves API key from g:vars and env vars, infers model from endpoint
- `BuildRequestBody()` — builds JSON with JsonEscape(), returns string for curl -d @file
- `JsonEscape()` — Vim9Script JSON string escaper (returns quoted string)

**Gate:** API call returns text from the model. Errors surface cleanly to user.

**9b: Context Gathering**
- `GatherContext(winid)` — assembles context dict for the origin window (script-local)
- Editing buffer: file path, cursor position, filetype, file lines ±100
- Current vproj mode and working directory
- The system message built from the context is written (JSON-encoded) to a 0600 temp file for the terminal chat (via `AiTerminalChat()`)

**Gate:** Context dict contains all relevant information without exceeding prompt budget.

**9c: AI Prompt Modes**
- `A` key in vproj pane opens terminal chat (`AiTerminalChat()`)
- `:VprojAiPrompt [prompt]` (`<Plug>VprojAiPrompt`, no default key) runs a one-shot prompt via `AiPrompt()`; code mode applies the first fenced block after a `confirm()`, question mode (or a response with no fence) shows a popup. `!` / `?` prefixes force the mode. There is no `A` mapping outside the pane and no `:VprojAi` command.
- Streaming progress via `echom`; a new request cancels one in flight
- Popup closes with q or Esc

**Gate:** User presses A, types query, sees streaming response in terminal.

**9d: Response Routing**
- `ApplyCode(target_bufnr, blocks, cursor_line)` (script-local) — inserts the first fenced block (found by `ExtractCodeBlocks()`) below the cursor in the target buffer, after `confirm()`
- No fenced block: nothing is applied; the response goes to a popup
- Vim's undo history preserves pre-apply state

**Gate:** Each response type routes to correct Vim surface.

**9e: Polish**
- Error states: network failure, API error, empty response
- API key not configured: prompt user to set `g:vproj_ai_api_key`
- All AI functions follow existing conventions: guard clauses, return '' on error

**Gate:** End-to-end flow works. Error states handled. Existing vproj features unaffected.

### Stage 10: Terminal Chat (built; `vproj#ai#AiTerminalChat()`)

**10a: Bash Chat Script (bin/vproj-ai-chat)**
- Pure bash SSE streaming chat loop (~210 lines)
- `json_escape()` for JSON-safe string escaping (all control characters)
- `extract_delta()` char-by-char parser for SSE content extraction
- Conversation history maintained in bash (JSON message array)
- Multi-turn with the system message read from the file named by $VPROJ_AI_TMPFILE (key from $VPROJ_AI_KEYFILE)
- Fault injection via $VPROJ_AI_TEST_FAIL for testability
- Curl exit code capture and detailed error diagnostics

**10b: Vim Terminal Integration**
- `AiTerminalChat()` in autoload/vproj/ai.vim
- `botright new` + `execute 'resize 15'` for 15-line terminal
- `term_start(['bash', script_path], {env: {...}})` with env dict
- `<Esc>` in the terminal maps to `job_stop(..., 'term')`; `term_finish: 'close'` closes the window
- Temp file lifecycle managed with a trap in bash script and an `exit_cb` in Vim

**Gate:** Full multi-turn AI chat in terminal. SSE streaming works. All tests pass.

### Stage 11: Agent Add-on (built)

- `autoload/vproj/agent.vim` (`vproj#agent#AgentOpen()`), approved 2026-11-09
- `:VprojAgent` / `<Plug>VprojAgent` (no default key) open a coding-agent CLI
  (`g:vproj_agent_cmd`, else `claude`, else `codex`) in a terminal split
- File context passed via `$VPROJ_AGENT_CTX_FILE` (0600 JSON file, deleted on exit)

Also built after this plan: git actions (`\s \d \D \c \p \u \b \z \Z \a`,
Ctrl-G filter), file operations (`:VprojCopy/Delete/Rename/Move`), tree view,
preview, filter/grep, and opt-in session saving (`g:vproj_save_session`). See `implementation-plan.md`.

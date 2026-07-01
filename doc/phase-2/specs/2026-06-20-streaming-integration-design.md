# vproj_ai Streaming Integration — Design Spec

**Date:** 2026-06-20
**Status:** draft
**Scope:** Replace blocking `system()` with async `job_start` streaming, add mode-aware context extraction, add side-car response buffer.

## Motivation

vproj_ai currently blocks Vim for 10–60 seconds during `AiCall()` via `system('curl ...')`.
Users stare at a frozen editor. The previous streaming attempt was removed (Task #108)
because callbacks didn't fire — root cause was `<Cmd>` in nnoremap + `mode: 'nl'` +
missing `redraw`. A minimal working example (MWE) at `tests/stream_mwe.vim` proves
the pattern works: `job_start` + `mode: 'raw'` + SSE accumulator + `redraw` delivers
token-by-token rendering with focus preserved on the user's working buffer.

Second gap: `GatherContext()` always reads the alternate buffer's file, ignoring the
pane mode. In Log mode, the AI should know about the commit under cursor. In Qfix mode,
the error entry. In Buf mode, the target buffer's content.

## Architecture

Three changes to the existing 2-file structure (no new files, no global remaps):

### 1. Mode-aware context extraction (`GatherContext` enhancement)

| Pane Mode | Context captured |
|-----------|-----------------|
| File      | Absolute path under cursor + file ±100 lines (unchanged) |
| Git       | Absolute path under cursor + file ±100 lines (unchanged) |
| Log       | Commit hash under cursor + `git log --stat <hash>` output |
| Qfix      | Filename:lnum + entry text from quickfix item |
| Buf       | Target buffer's full text (capped at 2000 lines) |

Implementation: `GatherContext()` checks `vproj#GetCurrentMode()` and reads the
cursor item accordingly. In Log mode, extracts the commit hash from the selected
line (7-char hex prefix). In Qfix mode, captures the entry filename, line number,
and text. In Buf mode, reads the target buffer instead of the alternate buffer.

### 2. Async streaming engine (new `StreamAiCall`, `AiCall` removed)

```
user prompt → BuildRequestBody → curl -N → job_start(mode:raw) → SSE accumulator → AppendToken → redraw
```

**New script-local state:**
- `stream_job: job` — handle for cancel (`S-Tab` in conversation buffer)
- `stream_accum: string` — SSE frame reassembly buffer
- `stream_bufnr: number` — side buffer receiving tokens
- `stream_cur_line: number` — current append line (avoids `getbufline` stale reads)
- `stream_cur_text: string` — current line content accumulator

**Callback chain:**
1. `out_cb`: `(chan, msg) => ProcessChunk(chan, msg)` — accumulates bytes, splits
   on `\n\n`, extracts `data:` lines, calls `json_decode()`, dispatches tokens to
   `AppendToken()`. Ignores partial frames. On `[DONE]`, sets `stream_done = true`.
2. `exit_cb`: `JobExit(job, status)` — flushes accumulator, sets final state.
3. `err_cb`: same handler as `out_cb` — Anthropic sends errors on stderr.

**Key invariants (from MWE verification):**
- Lambda wrapper `(chan, msg) => ProcessChunk(...)` binds context — avoids Vim9
  `def` lookup failure that killed the previous attempt
- `mode: 'raw'` only — `nl` splits JSON mid-object on newline characters in tokens
- `redraw` after every `setbufline`/`appendbufline` — without it, Vim batches all
  screen updates until job exit
- Script-local vars for line state — `getbufline` after `setbufline` returns stale
  data in headless Vim; track `stream_cur_line`/`stream_cur_text` instead

### 3. Side-car response buffer

```
┌──────────┬──────────────────────────────────────┐
│  vproj   │                                      │
│  pane    │         Code / working buffer         │
│  (40col) │                                      │
│          │                                      │
│ A→prompt │                                      │
│          ├──────────────────────────────────────┤
│          │  __AI_Response__  (streaming, 50col)  │
└──────────┴──────────────────────────────────────┘
```

**Create/Reuse pattern:**
- `PrepareResponseBuffer()`: if `__AI_Response__` buffer exists, clear it and
  reuse; otherwise `botright vsplit | vertical resize 50 | enew | file __AI_Response__`
- Set `buftype=nofile bufhidden=wipe noswapfile buflisted=0 modifiable=0 syntax=markdown wrap`
- Save `origin_win = win_getid()` before split, restore with `win_gotoid(origin_win)`
  after buffer is ready — user never leaves their working window
- Stream populates the buffer in the background while user continues working

**Buffer mappings:**
- `q` — close buffer
- `<CR>` — `SendFollowup()` (command-line `input('> ')`, streams response)
- `S-Tab` — cancel active stream (`job_stop(stream_job)`)
- `a` / `A` — `AiApplyCode()` (unchanged)

### Flow

```
A in pane → AiPrompt()
  → bwipeout! old conversation
  → GatherContext(pane_mode)       ← mode-aware (NEW)
  → input('AI: ')
  → PrepareResponseBuffer()        ← side buffer (NEW)
  → win_gotoid(pane_win)           ← bounce back (NEW)
  → BuildRequestBody(prompt, ctx)
  → StreamApiCall(body, bufnr)     ← job_start replaces system() (NEW)
    → out_cb: ProcessChunk → AppendToken → redraw
    → exit_cb: JobExit
  → follow-up loop (unchanged):
    → input('> ')
    → StreamApiCall(followup, ctx)
    → RenderConversation(bufnr)
```

## What does NOT change

- Mappings: `A` in pane buffer only (buffer-local, not global)
- File structure: plugin/vproj_ai.vim + autoload/vproj_ai.vim (no new files)
- `AiApplyCode()`, `GatherContext()` (enhanced but same signature)
- `BuildRequestBody()`, `ExtractJsonField()` (unchanged — response JSON is
  still collected and returned by the streaming engine, not parsed from SSE)
- Conversation history: `ai_conversation_history` list unchanged
- Credential/config: `AiConfigure()` unchanged

## Streaming vs. non-streaming API call

The streaming engine uses `stream: true` in the API request body (changed from
`false`). The curl command changes from `-s -f` to `-N -s -f`:
```
curl -N -s -f --connect-timeout 10 -m 120 -X POST <url> \
  -H 'Content-Type: application/json' \
  --header @<hdrfile> \
  -d @<tmpfile>
```

`-N` disables curl's output buffering (critical — without it, curl buffers
until the connection closes, defeating streaming). Timeout raised from 60s
to 120s since streaming responses take longer end-to-end.

## Error handling

- `job_start` returns `-1` → `echoerr`, fall back to blocking `system()` as degraded mode
- curl HTTP error → `exit_cb` status non-zero → append error message to buffer
- Buffer wiped mid-stream → `bufexists()` guard in `AppendToken`, `job_stop()` in
  `HandleConvBufWipeout`
- Partial JSON in SSE frame → `try/catch` around `json_decode()`, ignore frame
- Stalled stream → `timeout: 120000` in job options, `exit_cb` fires on timeout

## Test plan

1. **Streaming engine unit test** (`tests/stream_mwe.vim` — already passing):
   mock SSE → verify token-by-token buffer output
2. **Real API integration test** (`tests/integration/test_streaming.vim`):
   requires API key; sends one prompt, verifies response buffer is populated
3. **Cancel test**: start stream, wipe buffer, verify job is stopped
4. **Existing test suites must still pass**: `tests/smoke.vim`, `tests/integration/test_ai_addon.vim`
5. **Manual interactive test**: open pane, `A`, type prompt, verify:
   - Focus returns to pane immediately
   - Response streams token-by-token in side buffer
   - Follow-ups work via `input('> ')`
   - `S-Tab` cancels active stream
   - Pane is in normal mode after flow completes

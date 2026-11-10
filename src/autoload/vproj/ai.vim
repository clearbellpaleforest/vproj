vim9script

# autoload/vproj/ai.vim — AI add-on for vproj.
# Requires vproj. Adds AI prompt (A key in pane) for natural-language
# coding assistance via OpenAI-compatible API with streaming responses.
#
# Two modes:
#   Code mode (default) — the first fenced code block of the response is
#     inserted into the file you were editing, after a confirm() prompt.
#     A response without a ``` fenced block is never inserted.
#   Question mode (?, what, how, why, etc.) — response in floating popup
#
# Force code mode with ! prefix. Force question mode with ? prefix.
#
# Secrets (API key, request body) never go on a command line or in the
# environment. They go to tempname() files created with mode 0600 before
# the secret is written, and every such file is deleted when its job ends
# or when starting the job fails.

# ── Script-level paths (expand('<sfile>') not available in def functions in Vim 9.2) ──
# This file is <repo>/src/autoload/vproj/ai.vim; the chat script is <repo>/bin/.
var chat_script_path: string = expand('<sfile>:p:h:h:h:h') .. '/bin/vproj-ai-chat'
var ai_api_url: string = ''
var ai_api_key: string = ''
var ai_model: string = ''
var ai_url_rejected: bool = false

# ── Per-request State ──
var ai_mode: string = 'code'
var ai_target_bufnr: number = -1
var ai_target_cursor_line: number = 1

# ── Streaming State ──
var stream_job: any = v:null
var stream_accumulated: string = ''
var stream_cancelled: bool = false
var stream_full_response: string = ''

# Path of the terminal chat script (exported for tests).
export def ChatScriptPath(): string
  return chat_script_path
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Secret temp files
# ══════════════════════════════════════════════════════════════════════════════

# Create {path} empty, restrict it to 0600, then write {lines} (no trailing
# newline). The secret is never on disk with wider permissions.
# On any failure the file is removed and false is returned.
def WriteSecretFile(path: string, lines: list<string>): bool
  if empty(path)
    return false
  endif
  if writefile([], path, 'b') != 0
    return false
  endif
  if !setfperm(path, 'rw-------')
    delete(path)
    return false
  endif
  if writefile(lines, path, 'b') != 0
    delete(path)
    return false
  endif
  return true
enddef

def DeleteFiles(paths: list<string>): void
  for p in paths
    if !empty(p) && filereadable(p)
      delete(p)
    endif
  endfor
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Origin window — the file window the user was editing
# ══════════════════════════════════════════════════════════════════════════════

def PaneBufnr(): number
  return exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
enddef

# Window ID of the file window the user is working in: the current window,
# or the previous window when the current one is the vproj pane.
# Returns 0 when there is no normal file window to act on.
def OriginWindow(): number
  var pane: number = PaneBufnr()
  var winid: number = win_getid()
  if winbufnr(winid) == pane
    var prev: number = winnr('#')
    if prev <= 0
      return 0
    endif
    winid = win_getid(prev)
  endif
  if winid <= 0
    return 0
  endif
  var bufnr: number = winbufnr(winid)
  if bufnr <= 0 || bufnr == pane || !empty(getbufvar(bufnr, '&buftype'))
    return 0
  endif
  return winid
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Terminal chat
# ══════════════════════════════════════════════════════════════════════════════

export def AiTerminalChat(): void
  if !has('terminal')
    echohl ErrorMsg | echom 'vproj-ai: terminal support required (Vim 8.0+)' | echohl None
    return
  endif
  if !filereadable(chat_script_path)
    echohl ErrorMsg | echom 'vproj-ai: chat script not found at ' .. chat_script_path | echohl None
    return
  endif
  if !executable('bash')
    echohl ErrorMsg | echom 'vproj-ai: bash is required but not found' | echohl None
    return
  endif
  if !executable('curl')
    echohl ErrorMsg | echom 'vproj-ai: curl is required but not found' | echohl None
    return
  endif

  # Cancel any in-progress stream
  if stream_job != v:null && job_status(stream_job) == 'run'
    StreamCancel()
  endif

  if !ConfigureOrRefuse()
    return
  endif

  # The chat script reads the system message (already JSON-encoded, one
  # line) from VPROJ_AI_TMPFILE and the key from VPROJ_AI_KEYFILE. It
  # deletes both; the exit_cb below deletes them again in case it did not.
  var ctx: dict<any> = GatherContext(OriginWindow())
  var sysfile: string = tempname()
  if !WriteSecretFile(sysfile, [json_encode(BuildSystemMessage(ctx))])
    echohl ErrorMsg | echom 'vproj-ai: failed to write request (disk full?)' | echohl None
    return
  endif
  var keyfile: string = tempname()
  if !WriteSecretFile(keyfile, [ai_api_key])
    DeleteFiles([sysfile])
    echohl ErrorMsg | echom 'vproj-ai: failed to write key file' | echohl None
    return
  endif

  var files: list<string> = [keyfile, sysfile]
  var opts: dict<any> = {
    curwin: true,
    term_finish: 'close',
    # SIGTERM (not SIGKILL) if Vim exits while the chat runs, so the
    # script's EXIT trap removes its auth-header and body temp files.
    term_kill: 'term',
    env: {
      VPROJ_AI_KEYFILE: keyfile,
      VPROJ_AI_API_URL: ai_api_url,
      VPROJ_AI_MODEL: ai_model,
      VPROJ_AI_TMPFILE: sysfile,
      # The script's own mktemp files (auth header, body) go in Vim's
      # private temp directory, which Vim removes on exit.
      TMPDIR: fnamemodify(sysfile, ':h'),
    },
    exit_cb: (_, _) => DeleteFiles(files),
  }
  # One 15-line window at the bottom; term_start() reuses it (curwin) and
  # the placeholder buffer is wiped, so no empty window or buffer is left.
  botright new
  setlocal bufhidden=wipe
  resize 15
  var termbuf: number = term_start(['bash', chat_script_path], opts)
  if termbuf == 0
    DeleteFiles(files)
    if winnr('$') > 1
      close
    endif
    echohl ErrorMsg | echom 'vproj-ai: failed to start terminal' | echohl None
    return
  endif
  # Esc ends the chat with SIGTERM; term_finish closes the window. (A
  # :bdelete! would SIGKILL bash and skip its EXIT-trap cleanup.)
  tnoremap <buffer> <nowait> <Esc> <Cmd>call job_stop(term_getjob(bufnr()), 'term')<CR>
enddef

def UrlValid(url: string): bool
  return url =~# '^https://'
enddef

# Resolve the key, endpoint and default model from the settings and the
# environment. Both ai_api_key and ai_api_url are cleared first and set only
# when a complete, valid pair was found, so a key or URL the user has since
# unset or broken is never reused: callers check ConfigureOrRefuse().
export def AiConfigure(): void
  ai_api_key = ''
  ai_api_url = ''
  ai_url_rejected = false
  var g_key: any = get(g:, 'vproj_ai_api_key', '')
  var g_url: any = get(g:, 'vproj_ai_api_url', '')

  # Validate URL before use (prevent SSRF/credential forwarding)
  if type(g_url) == v:t_string && !empty(g_url) && !UrlValid(g_url)
    ai_url_rejected = true
    echohl ErrorMsg | echom 'vproj-ai: only HTTPS URLs allowed for API endpoint' | echohl None
    return
  endif

  # The default model follows the source that was selected.
  var key: string = ''
  var url: string = ''
  var default_model: string = 'deepseek-chat'
  if type(g_key) == v:t_string && !empty(g_key)
    key = g_key
    url = (type(g_url) == v:t_string && !empty(g_url)) ? g_url : 'https://api.deepseek.com/v1/chat/completions'
    if url =~# '^https://api\.openai\.com/'
      default_model = 'gpt-4o-mini'
    endif
  else
    var dk: any = getenv('DEEPSEEK_API_KEY')
    if type(dk) == v:t_string && !empty(dk)
      key = dk
      url = 'https://api.deepseek.com/v1/chat/completions'
    else
      var ok: any = getenv('OPENAI_API_KEY')
      if type(ok) == v:t_string && !empty(ok)
        key = ok
        default_model = 'gpt-4o-mini'
        var base: any = getenv('OPENAI_API_BASE')
        if type(base) == v:t_string && !empty(base)
          var base_str: string = base
          if !UrlValid(base_str)
            ai_url_rejected = true
            echohl ErrorMsg | echom 'vproj-ai: only HTTPS URLs allowed for OPENAI_API_BASE' | echohl None
            return
          endif
          if base_str !~ '/chat/completions$'
            base_str = substitute(base_str, '/$', '', '') .. '/chat/completions'
          endif
          url = base_str
        else
          url = 'https://api.openai.com/v1/chat/completions'
        endif
      endif
    endif
  endif
  ai_api_key = key
  ai_api_url = url

  # Select model: explicit override > source-based default
  var g_model: any = get(g:, 'vproj_ai_model', '')
  if type(g_model) == v:t_string && !empty(g_model)
    ai_model = g_model
  else
    ai_model = default_model
  endif
enddef

# Configure, then check that a key and an endpoint were both found. Prints
# why not and returns false: the caller must not send anything.
def ConfigureOrRefuse(): bool
  AiConfigure()
  if ai_url_rejected
    echohl ErrorMsg | echom 'vproj-ai: request not sent -- fix the API endpoint (see the message above)' | echohl None
    return false
  endif
  if empty(ai_api_key) || empty(ai_api_url)
    echohl ErrorMsg | echom 'vproj-ai: no API key. Set g:vproj_ai_api_key or $DEEPSEEK_API_KEY.' | echohl None
    return false
  endif
  return true
enddef

# Context of the file shown in window {winid} (0 = no file): path,
# filetype, cursor, and up to 100 lines either side of the cursor.
def GatherContext(winid: number): dict<any>
  var ctx: dict<any> = {}
  ctx.cwd = getcwd()
  ctx.mode = exists('*vproj#GetCurrentMode') ? vproj#GetCurrentMode() : 'file'
  if winid <= 0
    return ctx
  endif
  var bufnr: number = winbufnr(winid)
  if bufnr <= 0 || bufnr == PaneBufnr()
    return ctx
  endif
  var pos: list<number> = getcurpos(winid)
  ctx.file = fnamemodify(bufname(bufnr), ':p')
  ctx.filetype = getbufvar(bufnr, '&filetype', '')
  ctx.cursor_line = pos[1] > 0 ? pos[1] : 1
  ctx.cursor_col = pos[2] > 0 ? pos[2] : 1
  var total: number = get(getbufinfo(bufnr)[0], 'linecount', 0)
  var ctx_start: number = max([1, ctx.cursor_line - 100])
  var ctx_end: number = min([total, ctx.cursor_line + 100])
  ctx.file_lines = getbufline(bufnr, ctx_start, ctx_end)
  ctx.file_line_offset = ctx_start
  ctx.file_total_lines = total
  return ctx
enddef

# System message text built from a GatherContext() dict, including the
# gathered file lines.
def BuildSystemMessage(ctx: dict<any>): string
  var msg: string = 'You are a coding assistant embedded in Vim. '
  var ctx_file: string = get(ctx, 'file', '')
  var ft: string = get(ctx, 'filetype', '')
  if empty(ctx_file)
    msg ..= 'No file is open. '
  else
    msg ..= 'The user is editing ' .. fnamemodify(ctx_file, ':t')
    msg ..= empty(ft) ? '. ' : ' (' .. ft .. '). '
  endif
  msg ..= 'Current mode: ' .. get(ctx, 'mode', 'file') .. '. '
  msg ..= 'Be concise. ALWAYS wrap code in ``` fences with a language tag (```python, ```vim, etc). '
  msg ..= 'The user needs ``` fences to extract and apply your code. '
  msg ..= 'Never output code without ``` fences.'

  var lines: any = get(ctx, 'file_lines', [])
  if type(lines) != v:t_list || empty(lines)
    return msg
  endif
  var first: number = get(ctx, 'file_line_offset', 1)
  var last: number = first + len(lines) - 1
  msg ..= ' The file has ' .. get(ctx, 'file_total_lines', 0) .. ' lines;'
  msg ..= ' the cursor is on line ' .. get(ctx, 'cursor_line', 1) .. '.'
  msg ..= ' Lines ' .. first .. '-' .. last .. " of the file:\n"
  msg ..= '```' .. ft .. "\n" .. join(lines, "\n") .. "\n```"
  return msg
enddef

export def BuildRequestBody(prompt: string, ctx: dict<any>, stream: bool): string
  return json_encode({
    model: ai_model,
    messages: [
      {role: 'system', content: BuildSystemMessage(ctx)},
      {role: 'user', content: prompt},
    ],
    stream: stream ? v:true : v:false,
  })
enddef

# ── Synchronous API call (fallback, used by tests) ──
export def AiCall(prompt: string, ctx: dict<any>): string
  if !executable('curl')
    echohl ErrorMsg | echom 'vproj-ai: curl is required but not found' | echohl None
    return ''
  endif

  if !ConfigureOrRefuse()
    return ''
  endif

  var bodyfile: string = tempname()
  var hdrfile: string = tempname()
  var result: string = ''
  try
    if !WriteSecretFile(bodyfile, [BuildRequestBody(prompt, ctx, false)])
      echohl ErrorMsg | echom 'vproj-ai: failed to write request body (disk full? permissions?)' | echohl None
      return ''
    endif
    if !WriteSecretFile(hdrfile, ['Authorization: Bearer ' .. ai_api_key])
      echohl ErrorMsg | echom 'vproj-ai: failed to write header file' | echohl None
      return ''
    endif
    var cmd: string = 'curl -s -f --connect-timeout 10 -m 60 -X POST ' .. shellescape(ai_api_url)
    cmd ..= ' -H ' .. shellescape('Content-Type: application/json')
    cmd ..= ' -H @' .. shellescape(hdrfile)
    cmd ..= ' --data-binary @' .. shellescape(bodyfile)

    var output: string = system(cmd)
    var shell_err: number = v:shell_error

    if shell_err != 0
      var truncated: string = substitute(output, '\n', ' ', 'g')
      if strchars(truncated) > 200
        truncated = strcharpart(truncated, 0, 200) .. '...'
      endif
      echohl ErrorMsg | echom 'vproj-ai: curl error ' .. shell_err .. ' -- ' .. truncated | echohl None
      return ''
    endif

    var decoded: any = DecodeJson(output)
    var content: string = ResponseContent(decoded)
    if empty(content)
      var err: string = ExtractJsonField(output, 'message')
      var err_truncated: string = empty(err) ? 'empty or malformed response' : err
      if strchars(err_truncated) > 200
        err_truncated = strcharpart(err_truncated, 0, 200) .. '...'
      endif
      echohl ErrorMsg | echom 'vproj-ai: API error -- ' .. err_truncated | echohl None
      return ''
    endif
    result = content
  catch
    echohl ErrorMsg | echom 'vproj-ai: request failed -- ' .. v:exception | echohl None
  finally
    DeleteFiles([bodyfile, hdrfile])
  endtry
  return result
enddef

# choices[0].message.content of a decoded chat-completions response, or ''.
def ResponseContent(decoded: any): string
  if type(decoded) != v:t_dict
    return ''
  endif
  var choices: any = get(decoded, 'choices', [])
  if type(choices) != v:t_list || empty(choices) || type(choices[0]) != v:t_dict
    return ''
  endif
  var message: any = get(choices[0], 'message', {})
  if type(message) != v:t_dict
    return ''
  endif
  var content: any = get(message, 'content', '')
  return type(content) == v:t_string ? content : ''
enddef

# JSON string literal for {s}, including the surrounding quotes.
export def JsonEscape(s: string): string
  return json_encode(s)
enddef

# json_decode() that returns v:none instead of throwing on malformed input.
def DecodeJson(json: string): any
  if empty(trim(json))
    return v:none
  endif
  var decoded: any = v:none
  try
    decoded = json_decode(json)
  catch /E474:\|E491:\|E938:/
    decoded = v:none
  endtry
  return decoded
enddef

# Search {value} for key {field}: the dict's own key first, then nested
# values depth-first. Returns [found, value].
def FindField(value: any, field: string): list<any>
  if type(value) == v:t_dict
    if has_key(value, field)
      return [true, value[field]]
    endif
    for v in values(value)
      var hit: list<any> = FindField(v, field)
      if hit[0]
        return hit
      endif
    endfor
  elseif type(value) == v:t_list
    for v in value
      var hit: list<any> = FindField(v, field)
      if hit[0]
        return hit
      endif
    endfor
  endif
  return [false, v:none]
enddef

# Value of the first {field} key in {json} as a string: strings as-is,
# containers re-encoded as JSON, null as '', other scalars via json_encode.
# Returns '' for a missing field or malformed JSON.
export def ExtractJsonField(json: string, field: string): string
  var hit: list<any> = FindField(DecodeJson(json), field)
  if !hit[0]
    return ''
  endif
  var value: any = hit[1]
  if type(value) == v:t_string
    return value
  endif
  if type(value) == v:t_none
    return ''
  endif
  return json_encode(value)
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Streaming API via job_start + SSE
# ══════════════════════════════════════════════════════════════════════════════

def ProcessStreamChunk(chan: channel, msg: string): void
  # Output from a cancelled or superseded job must not leak into the
  # current request's response.
  if stream_cancelled || stream_job == v:null || ch_getjob(chan) != stream_job
    return
  endif
  # Servers may frame with CRLF. Normalize the whole buffer, not just {msg}:
  # a CR at the end of one read and its LF at the start of the next must
  # still be joined.
  stream_accumulated = substitute(stream_accumulated .. msg, "\r\n", "\n", 'g')

  while stridx(stream_accumulated, "\n\n") >= 0
    var parts: list<string> = split(stream_accumulated, "\n\n", 1)
    var frame: string = parts[0]
    stream_accumulated = join(parts[1 : ], "\n\n")

    for line in split(frame, "\n")
      if line !~ '^data:\s*'
        continue
      endif
      var json_str: string = substitute(line, '^data:\s*', '', '')
      if json_str == '[DONE]'
        return
      endif
      var data: any = DecodeJson(json_str)
      if type(data) != v:t_dict
        continue
      endif
      var choices: any = get(data, 'choices', [])
      if type(choices) != v:t_list || empty(choices) || type(choices[0]) != v:t_dict
        continue
      endif
      var delta: any = get(choices[0], 'delta', {})
      if type(delta) != v:t_dict
        continue
      endif
      var content: any = get(delta, 'content', '')
      if type(content) == v:t_string && !empty(content)
        stream_full_response ..= content
      endif
    endfor
  endwhile
enddef

# exit_cb of one curl job. {files} are that job's secret temp files; they
# are deleted first, whether or not the job is still the current one.
def StreamJobExit(exited: job, status: number, files: list<string>): void
  DeleteFiles(files)
  if exited != stream_job
    return
  endif

  var response: string = stream_full_response
  var cancelled: bool = stream_cancelled
  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  if cancelled
    echom 'vproj-ai: cancelled'
    return
  endif
  if status != 0
    echohl ErrorMsg | echom 'vproj-ai: API call failed -- status ' .. status | echohl None
    return
  endif
  if ai_mode == 'question'
    ShowPopup(response)
    return
  endif

  var blocks: list<dict<any>> = ExtractCodeBlocks(response)
  if empty(blocks)
    echohl WarningMsg | echom 'vproj-ai: response has no ``` fenced code block -- nothing applied' | echohl None
    ShowPopup(response)
    return
  endif
  ApplyCode(ai_target_bufnr, blocks, ai_target_cursor_line)
enddef

export def AiCallStream(prompt: string, ctx: dict<any>): bool
  # Guard: reject if a stream is already running
  if stream_job != v:null && job_status(stream_job) == 'run'
    echohl ErrorMsg | echom 'vproj-ai: a request is already in progress -- wait or press Ctrl-C to cancel' | echohl None
    return false
  endif

  if !ConfigureOrRefuse()
    return false
  endif
  if !executable('curl')
    echohl ErrorMsg | echom 'vproj-ai: curl required' | echohl None
    return false
  endif

  # Body and auth header go to 0600 files so neither the key nor the
  # prompt is visible in /proc/<pid>/cmdline, and a long body cannot hit
  # the argv size limit (E2BIG).
  var bodyfile: string = tempname()
  if !WriteSecretFile(bodyfile, [BuildRequestBody(prompt, ctx, true)])
    echohl ErrorMsg | echom 'vproj-ai: failed to write request body' | echohl None
    return false
  endif
  var hdrfile: string = tempname()
  if !WriteSecretFile(hdrfile, ['Authorization: Bearer ' .. ai_api_key])
    DeleteFiles([bodyfile])
    echohl ErrorMsg | echom 'vproj-ai: failed to write header file' | echohl None
    return false
  endif
  var files: list<string> = [bodyfile, hdrfile]

  var cmd: list<string> = ['curl', '--no-buffer', '-s', '-f',
    '--connect-timeout', '10', '-m', '120',
    '-X', 'POST',
    '-H', 'Content-Type: application/json',
    '-H', '@' .. hdrfile,
    '--data-binary', '@' .. bodyfile,
    ai_api_url]

  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  var opts: dict<any> = {}
  opts.mode = 'raw'
  opts.out_cb = (chan, msg) => ProcessStreamChunk(chan, msg)
  opts.exit_cb = (j, st) => StreamJobExit(j, st, files)
  opts.timeout = 120000

  var new_job: job = job_start(cmd, opts)
  if job_status(new_job) == 'fail'
    DeleteFiles(files)
    echohl ErrorMsg | echom 'vproj-ai: failed to start API request' | echohl None
    return false
  endif
  stream_job = new_job
  return true
enddef

def StreamCancel(): void
  if stream_job == v:null || job_status(stream_job) != 'run'
    return
  endif
  stream_cancelled = true
  job_stop(stream_job)
enddef

export def StreamCancelCmd(): void
  if stream_job != v:null
    StreamCancel()
    echom 'vproj-ai: stream cancelled'
  endif
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Mode Detection
# ══════════════════════════════════════════════════════════════════════════════

# Classify a prompt as 'code' (apply to the file) or 'question' (popup).
# The LEADING intent decides, in this order:
#   1. empty / whitespace-only            -> code
#   2. first char '!'                     -> code      (explicit override)
#   3. first char '?'                     -> question  (explicit override)
#   4. begins with a code verb            -> code      (even if a question
#      word or a '?' appears later: "add a retry when it times out")
#   5. begins with a question word/phrase -> question
#   6. ends with '?' (after trimming)     -> question
#   7. anything else                      -> code
# A '?' inside the text (a regex such as /a?/) never counts by itself.
# Leading words match whole words only ("however" is not "how").
def DetectMode(prompt: string): string
  var text: string = trim(prompt)
  if empty(text)
    return 'code'
  endif
  if prompt[0] == '!'
    return 'code'
  endif
  if prompt[0] == '?'
    return 'question'
  endif
  var lower: string = tolower(text)
  var code_verbs: list<string> = ['add', 'write', 'create', 'make', 'implement', 'fix', 'refactor', 'rename', 'remove', 'delete', 'convert', 'generate', 'insert', 'replace', 'change', 'update', 'modify', 'extract', 'rewrite', 'append', 'wrap', 'move', 'simplify', 'optimize', 'optimise', 'sort', 'build', 'turn', 'put', 'use', 'apply', 'edit', 'comment', 'document', 'format', 'reformat', 'split', 'merge', 'inline', 'swap', 'reverse', 'complete', 'finish', 'port', 'translate', 'type', 'test']
  for v in code_verbs
    if lower =~# '^' .. v .. '\>'
      return 'code'
    endif
  endfor
  var question_words: list<string> = ['what', 'how', 'why', 'explain', 'describe', 'where', 'when', 'who', 'which', 'can you', 'could you', 'would you', 'is it', 'are there', 'does', 'do you', 'show me', 'tell me', 'find']
  for w in question_words
    if lower =~# '^' .. w .. '\>'
      return 'question'
    endif
  endfor
  if text[strlen(text) - 1] == '?'
    return 'question'
  endif
  return 'code'
enddef

# Strip mode-forcing prefix (! or ?) from prompt.
def StripPrefix(prompt: string): string
  if empty(prompt)
    return prompt
  endif
  if prompt[0] == '!' || prompt[0] == '?'
    var stripped: string = prompt[1 : ]
    return substitute(stripped, '^\s*', '', '')
  endif
  return prompt
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Code Extraction & Application
# ══════════════════════════════════════════════════════════════════════════════

export def ExtractCodeBlocks(text: string): list<dict<any>>
  var blocks: list<dict<any>> = []
  var lines: list<string> = split(text, "\n")
  var i: number = 0
  while i < len(lines)
    if lines[i] =~ '^```'
      var lang: string = substitute(lines[i], '^```\s*', '', '')
      i += 1
      var code_lines: list<string> = []
      while i < len(lines)
        if lines[i] =~ '^```'
          var code: string = join(code_lines, "\n")
          if !empty(code)
            blocks->add({language: lang, code: code})
          endif
          break
        endif
        code_lines->add(lines[i])
        i += 1
      endwhile
    endif
    i += 1
  endwhile
  return blocks
enddef

# Insert the first code block into {target_bufnr} below {cursor_line},
# after the user confirms. Esc / Ctrl-C at the prompt mean No.
def ApplyCode(target_bufnr: number, blocks: list<dict<any>>, cursor_line: number): void
  if empty(blocks)
    echom 'vproj-ai: no code in response'
    return
  endif
  if target_bufnr <= 0 || !bufexists(target_bufnr) || !bufloaded(target_bufnr)
    echohl ErrorMsg | echom 'vproj-ai: target buffer no longer exists' | echohl None
    return
  endif
  if !empty(getbufvar(target_bufnr, '&buftype'))
    echohl ErrorMsg | echom 'vproj-ai: target buffer is not a file buffer' | echohl None
    return
  endif
  if !getbufvar(target_bufnr, '&modifiable')
    echohl ErrorMsg | echom 'vproj-ai: target buffer not modifiable' | echohl None
    return
  endif

  var code_lines: list<string> = split(blocks[0].code, "\n")
  if empty(code_lines)
    echom 'vproj-ai: no code in response'
    return
  endif
  var lang: string = get(blocks[0], 'language', '')
  var total: number = get(getbufinfo(target_bufnr)[0], 'linecount', 0)
  var insert_at: number = min([max([cursor_line, 0]), total])
  var name: string = bufname(target_bufnr)
  var fname: string = empty(name) ? '[No Name] (buffer ' .. target_bufnr .. ')' : fnamemodify(name, ':t')
  var label: string = empty(lang) ? '' : ' (' .. lang .. ')'

  const PREVIEW_LINES: number = 8
  var preview: list<string> = code_lines[: PREVIEW_LINES - 1]
  if len(code_lines) > PREVIEW_LINES
    preview->add('... (' .. (len(code_lines) - PREVIEW_LINES) .. ' more)')
  endif
  var question: string = printf('vproj-ai: insert %d line(s)%s into %s after line %d?',
    len(code_lines), label, fname, insert_at)
  if len(blocks) > 1
    question ..= printf(' (first of %d code blocks)', len(blocks))
  endif
  question ..= "\n\n" .. join(preview, "\n")
  if confirm(question, "&Yes\n&No", 2) != 1
    echom 'vproj-ai: not applied'
    return
  endif

  if appendbufline(target_bufnr, insert_at, code_lines) != 0
    echohl ErrorMsg | echom 'vproj-ai: failed to insert into ' .. fname | echohl None
    return
  endif
  echom 'vproj-ai: applied ' .. len(code_lines) .. ' lines to ' .. fname .. label .. ' (u to undo)'
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Floating Popup for Question Mode
# ══════════════════════════════════════════════════════════════════════════════

def PopupFilter(winid: number, key: string): bool
  if key == 'q' || key == "\<Esc>" || key == "\<C-C>"
    popup_close(winid)
    return true
  endif
  return false
enddef

def ShowPopup(text: string): void
  var lines: list<string> = split(text, "\n")
  if empty(lines)
    echom 'vproj-ai: empty response'
    return
  endif

  var opts: dict<any> = {
    title: ' vproj_ai (q/Esc to close) ',
    # pos 'center' centers on screen; line/col are ignored ('center' is
    # not a valid col value and made popup_create() fail with E475).
    pos: 'center',
    wrap: true,
    close: 'button',
    padding: [1, 1, 1, 1],
    border: [1, 1, 1, 1],
    borderchars: ['-', '|', '-', '|', '+', '+', '+', '+'],
    filter: PopupFilter,
    mapping: false,
    scrollbar: true,
    maxheight: 20,
    minwidth: 40,
    maxwidth: 80,
    cursorline: 0,
  }

  popup_create(lines, opts)
  echom 'vproj-ai: response in popup (q or Esc to close)'
enddef

# ══════════════════════════════════════════════════════════════════════════════
# Public API — AI Prompt
# ══════════════════════════════════════════════════════════════════════════════

# Entry point from A key mapping. Uses input() to get the prompt.
# Safe because <Cmd> mappings don't consume typeahead.
export def AiPromptFromKey(): void
  var prompt: string = input('vproj-ai: ')
  redraw
  if empty(prompt)
    return
  endif
  AiPrompt(prompt)
enddef

export def AiPrompt(prompt_from_cmdline: string = ''): void
  var prompt: string = prompt_from_cmdline
  if empty(trim(prompt))
    return
  endif

  # Detect mode and strip prefix before sending to API
  var mode: string = DetectMode(prompt)
  prompt = StripPrefix(prompt)
  if empty(prompt)
    return
  endif

  # Target: the file window the user is editing now (or came from, when
  # the prompt is issued from the vproj pane) — never the alternate buffer.
  var origin: number = OriginWindow()
  if mode == 'code' && origin == 0
    echohl ErrorMsg | echom 'vproj-ai: no file window to apply code to (use ?prompt to ask a question)' | echohl None
    return
  endif

  # Cancel any in-progress stream; its exit_cb still cleans up its files.
  if stream_job != v:null && job_status(stream_job) == 'run'
    StreamCancel()
  endif
  stream_job = v:null
  stream_accumulated = ''
  stream_full_response = ''
  stream_cancelled = false

  var ctx: dict<any> = GatherContext(origin)
  ai_mode = mode
  ai_target_bufnr = origin > 0 ? winbufnr(origin) : -1
  ai_target_cursor_line = get(ctx, 'cursor_line', 1)

  var ctx_file: string = get(ctx, 'file', '')
  var display_file: string = empty(ctx_file) ? 'unknown' : fnamemodify(ctx_file, ':t')
  var mode_label: string = ai_mode == 'question' ? ' (question)' : ''
  echom 'vproj-ai: streaming' .. mode_label .. ' for ' .. display_file .. '...'

  if !AiCallStream(prompt, ctx)
    echohl ErrorMsg | echom 'vproj-ai: failed to start stream' | echohl None
  endif
enddef

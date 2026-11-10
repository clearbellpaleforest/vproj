vim9script
# Regression tests for the AI credential/endpoint state, SSE framing, and the
# agent's origin window (2026-11 audit, third pass).
# Run:
#   vim -N -u NONE -i NONE --not-a-term -S tests/unit/test_ai_credentials.vim \
#     -c 'cquit!' </dev/null
# Exits with :qa! when every assertion passes, :cquit! otherwise.
#
# Hermetic: HOME and XDG_CACHE_HOME are under tempname(); curl and the agent
# CLI are fakes on PATH that record what they received; keys are fake; there
# is no network. Each block names what used to happen.

$HOME = tempname()
mkdir($HOME, 'p')
$XDG_CACHE_HOME = $HOME .. '/cache'
set nomore
set hidden
set ttimeout ttimeoutlen=0 timeoutlen=0
set columns=160 lines=40

var failures: number = 0
var log: list<string> = []

def Assert(cond: bool, msg: string): void
  if cond
    log->add('PASS: ' .. msg)
  else
    log->add('FAIL: ' .. msg)
    failures += 1
  endif
enddef

def RunSection(name: string, F: func(): void): void
  try
    F()
  catch
    Assert(false, name .. ' threw: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
enddef

var repo: string = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h')
execute 'set rtp^=' .. fnameescape(repo .. '/src')

log->add('=== test_ai_credentials.vim ===')

# ── Fakes ──
var fake_dir: string = tempname()
mkdir(fake_dir, 'p')
# Fake curl: records argv, the -H @file header contents, and the body; prints
# a canned reply. $FAKE_DIR/split makes it emit the SSE reply in two halves
# with a pause between them (a frame boundary can straddle two reads).
writefile([
  '#!/bin/bash',
  'd="$FAKE_DIR"',
  'n=$(date +%s%N)',
  'printf "%s\n" "$@" > "$d/argv.$n"',
  'prev=""',
  'for a in "$@"; do',
  '  if [ "$prev" = "-H" ] && [ "${a:0:1}" = "@" ]; then cat "${a#@}" > "$d/hdr.$n"; fi',
  '  if [ "$prev" = "--data-binary" ]; then cat "${a#@}" > "$d/body.$n"; fi',
  '  prev="$a"',
  'done',
  'if grep -qs "\"stream\":false" "$d/body.$n"; then cat "$d/reply.json"; exit 0; fi',
  'if [ -f "$d/split" ]; then cat "$d/reply.sse.1"; sleep 0.4; cat "$d/reply.sse.2"; exit 0; fi',
  'cat "$d/reply.sse"',
], fake_dir .. '/curl')
setfperm(fake_dir .. '/curl', 'rwx------')
$FAKE_DIR = fake_dir
$PATH = fake_dir .. ':' .. $PATH
$DEEPSEEK_API_KEY = ''
$OPENAI_API_KEY = ''
$OPENAI_API_BASE = ''

var URL_OK: string = 'https://example.invalid/v1/chat/completions'
var DEEPSEEK_URL: string = 'https://api.deepseek.com/v1/chat/completions'

def ResetFake(): void
  for prefix in ['argv', 'hdr', 'body', 'reply', 'split']
    for f in glob(fake_dir .. '/' .. prefix .. '*', 0, 1)
      delete(f)
    endfor
  endfor
enddef

# One entry per curl invocation, oldest first: {url, hdr, model}.
def Calls(): list<dict<any>>
  var out: list<dict<any>> = []
  for f in sort(glob(fake_dir .. '/argv.*', 0, 1))
    var n: string = substitute(f, '.*argv\.', '', '')
    var rec: dict<any> = {url: '', hdr: '', model: ''}
    for a in readfile(f)
      if a =~# '^https\?://'
        rec.url = a
      endif
    endfor
    if filereadable(fake_dir .. '/hdr.' .. n)
      rec.hdr = join(readfile(fake_dir .. '/hdr.' .. n), '')
    endif
    if filereadable(fake_dir .. '/body.' .. n)
      var body: any = json_decode(join(readfile(fake_dir .. '/body.' .. n), "\n"))
      rec.model = type(body) == v:t_dict ? get(body, 'model', '') : ''
    endif
    out->add(rec)
  endfor
  return out
enddef

def SetReply(text: string): void
  writefile([json_encode({choices: [{message: {role: 'assistant', content: text}}]})], fake_dir .. '/reply.json')
  var sse: list<string> = []
  sse->add('data: ' .. json_encode({choices: [{delta: {content: text}}]}))
  sse->add('')
  sse->add('data: [DONE]')
  sse->add('')
  writefile(sse, fake_dir .. '/reply.sse')
enddef

def WaitFor(F: func(): bool, ms: number = 30000): bool
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < ms
    if F()
      return true
    endif
    sleep 20m
  endwhile
  return F()
enddef

def Messages(): string
  return execute('messages')
enddef

def UnsetAll(): void
  unlet! g:vproj_ai_api_key g:vproj_ai_api_url g:vproj_ai_model
  $DEEPSEEK_API_KEY = ''
  $OPENAI_API_KEY = ''
  $OPENAI_API_BASE = ''
enddef

# Stop any terminal a misbehaving call started, so the suite can finish.
def KillTerminals(): void
  for b in term_list()
    var j: any = term_getjob(b)
    if j != v:null
      job_stop(j, 'kill')
    endif
  endfor
  sleep 200m
enddef

# Call AiTerminalChat and report whether it started a terminal.
def ChatStartsTerminal(): bool
  var wins_before: number = winnr('$')
  var terms_before: number = len(term_list())
  vproj#ai#AiTerminalChat()
  var started: bool = len(term_list()) > terms_before
  KillTerminals()
  while winnr('$') > wins_before
    close!
  endwhile
  return started
enddef

# ── 1A: unsetting the key must stop the old key being sent ──
# Used to: ai_api_key was never cleared, so the previous key kept being sent.
def Section1A(): void
  UnsetAll()
  ResetFake()
  SetReply('first')
  g:vproj_ai_api_key = 'sk-OLD-FAKE'
  g:vproj_ai_api_url = URL_OK
  g:vproj_ai_model = 'm1'
  var r1: string = vproj#ai#AiCall('p1', {})
  var calls: list<dict<any>> = Calls()
  Assert(r1 == 'first', '1A: first call returns the reply (' .. r1 .. ')')
  Assert(len(calls) == 1 && calls[0].hdr == 'Authorization: Bearer sk-OLD-FAKE' && calls[0].url == URL_OK,
    '1A: first call sent sk-OLD-FAKE to ' .. URL_OK)

  unlet g:vproj_ai_api_key
  var r2: string = vproj#ai#AiCall('p2', {})
  Assert(r2 == '', '1A: AiCall after unset returns empty (' .. r2 .. ')')
  Assert(len(Calls()) == 1, '1A: AiCall after unset did not run curl (calls=' .. len(Calls()) .. ')')
  Assert(Messages() =~# 'vproj-ai: no API key', '1A: AiCall after unset reports no API key')

  Assert(vproj#ai#AiCallStream('p3', {}) == false, '1A: AiCallStream after unset refuses')
  Assert(len(Calls()) == 1, '1A: AiCallStream after unset did not run curl')
  Assert(!ChatStartsTerminal(), '1A: AiTerminalChat after unset starts no terminal')
enddef
RunSection('1A', Section1A)

# ── 1B: an invalid URL must abort, not reuse the previous key+URL ──
# Used to: AiConfigure returned early, and the caller sent the request with
# the previous key and URL.
def Section1B(): void
  UnsetAll()
  ResetFake()
  SetReply('ok')
  g:vproj_ai_api_key = 'sk-GOOD-FAKE'
  g:vproj_ai_api_url = URL_OK
  g:vproj_ai_model = 'm1'
  Assert(vproj#ai#AiCall('p1', {}) == 'ok', '1B: valid config works')
  Assert(len(Calls()) == 1, '1B: one call recorded')

  g:vproj_ai_api_url = 'http://evil.invalid/steal'
  var r: string = vproj#ai#AiCall('p2', {})
  Assert(r == '', '1B: AiCall with http URL returns empty (' .. r .. ')')
  Assert(len(Calls()) == 1, '1B: AiCall with http URL did not run curl (calls=' .. len(Calls()) .. ')')
  Assert(Messages() =~# 'only HTTPS URLs allowed', '1B: user told only HTTPS is allowed')
  Assert(vproj#ai#AiCallStream('p3', {}) == false, '1B: AiCallStream with http URL refuses')
  Assert(len(Calls()) == 1, '1B: AiCallStream with http URL did not run curl')
  for c in Calls()
    Assert(c.url !~# 'evil', '1B: nothing was sent to the http URL')
  endfor
  Assert(!ChatStartsTerminal(), '1B: AiTerminalChat with http URL starts no terminal')

  # Recovery: a valid URL works again.
  g:vproj_ai_api_url = URL_OK
  Assert(vproj#ai#AiCall('p4', {}) == 'ok', '1B: valid URL after the bad one works again')

  # Invalid OPENAI_API_BASE with only the OpenAI key must also abort.
  UnsetAll()
  ResetFake()
  SetReply('ok')
  $OPENAI_API_KEY = 'sk-OPENAI-FAKE'
  Assert(vproj#ai#AiCall('p5', {}) == 'ok', '1B: OpenAI env key works')
  var n: number = len(Calls())
  $OPENAI_API_BASE = 'http://evil.invalid/v1'
  Assert(vproj#ai#AiCall('p6', {}) == '' && len(Calls()) == n, '1B: invalid OPENAI_API_BASE aborts the request')
enddef
RunSection('1B', Section1B)

# ── 2: default model follows the selected key source ──
# Used to: OPENAI_API_KEY set and DEEPSEEK_API_KEY empty gave gpt-4o-mini even
# when g:vproj_ai_api_key + the DeepSeek default URL was the selected source.
def Section2(): void
  UnsetAll()
  ResetFake()
  SetReply('x')
  $OPENAI_API_KEY = 'sk-OPENAI-FAKE'
  g:vproj_ai_api_key = 'sk-G-FAKE'
  vproj#ai#AiCall('p', {})
  var c: list<dict<any>> = Calls()
  Assert(len(c) == 1 && c[0].hdr == 'Authorization: Bearer sk-G-FAKE' && c[0].url == DEEPSEEK_URL,
    '2: g key + default URL selected (' .. string(c) .. ')')
  Assert(len(c) == 1 && c[0].model == 'deepseek-chat', '2: model is deepseek-chat, not gpt-4o-mini (' .. (len(c) == 1 ? c[0].model : '?') .. ')')

  # Explicit model still wins.
  ResetFake()
  g:vproj_ai_model = 'my-model'
  vproj#ai#AiCall('p', {})
  c = Calls()
  Assert(len(c) == 1 && c[0].model == 'my-model', '2: explicit g:vproj_ai_model wins')

  # OpenAI env key as the selected source keeps gpt-4o-mini + OpenAI URL.
  UnsetAll()
  ResetFake()
  $OPENAI_API_KEY = 'sk-OPENAI-FAKE'
  vproj#ai#AiCall('p', {})
  c = Calls()
  Assert(len(c) == 1 && c[0].model == 'gpt-4o-mini' && c[0].url == 'https://api.openai.com/v1/chat/completions'
    && c[0].hdr == 'Authorization: Bearer sk-OPENAI-FAKE', '2: OpenAI env source keeps gpt-4o-mini')

  # DeepSeek env key wins over OpenAI env key; model deepseek-chat.
  ResetFake()
  $DEEPSEEK_API_KEY = 'sk-DS-FAKE'
  vproj#ai#AiCall('p', {})
  c = Calls()
  Assert(len(c) == 1 && c[0].model == 'deepseek-chat' && c[0].hdr == 'Authorization: Bearer sk-DS-FAKE',
    '2: DeepSeek env source gives deepseek-chat')
enddef
RunSection('2', Section2)

# ── 3: CRLF-framed SSE must complete ──
# Used to: only "\n\n" ended a frame, so a "\r\n\r\n" stream never produced text.
def PopupText(): string
  var out: list<string> = []
  for id in popup_list()
    out += getbufline(winbufnr(id), 1, '$')
  endfor
  return join(out, "\n")
enddef

def Section3(): void
  UnsetAll()
  g:vproj_ai_api_key = 'sk-SSE-FAKE'
  g:vproj_ai_api_url = URL_OK
  g:vproj_ai_model = 'm1'

  # (a) whole stream CRLF-framed.
  popup_clear()
  ResetFake()
  var frames: string = 'data: ' .. json_encode({choices: [{delta: {content: 'crlf-'}}]}) .. "\r\n\r\n"
  frames ..= 'data: ' .. json_encode({choices: [{delta: {content: 'works'}}]}) .. "\r\n\r\n"
  frames ..= "data: [DONE]\r\n\r\n"
  writefile([frames], fake_dir .. '/reply.sse', 'b')
  vproj#ai#AiPrompt('?q')
  Assert(WaitFor(() => PopupText() =~# 'crlf-works', 30000), '3a: CRLF stream shows "crlf-works" (popup: ' .. PopupText() .. ')')
  popup_clear()

  # (b) the terminating CRLF CRLF split across two reads, between the second
  # CR and its LF: a per-read substitute() would leave "\n\r" + "\n".
  ResetFake()
  var part1: string = 'data: ' .. json_encode({choices: [{delta: {content: 'split-ok'}}]}) .. "\r\n\r"
  var part2: string = "\n"
  writefile([part1], fake_dir .. '/reply.sse.1', 'b')
  writefile([part2], fake_dir .. '/reply.sse.2', 'b')
  writefile([''], fake_dir .. '/split')
  vproj#ai#AiPrompt('?q2')
  Assert(WaitFor(() => PopupText() =~# 'split-ok', 30000), '3b: CRLF split across reads shows "split-ok" (popup: ' .. PopupText() .. ')')
  popup_clear()

  # (c) plain LF framing still works.
  ResetFake()
  SetReply('lf-ok')
  vproj#ai#AiPrompt('?q3')
  Assert(WaitFor(() => PopupText() =~# 'lf-ok', 30000), '3c: LF stream still works (popup: ' .. PopupText() .. ')')
  popup_clear()
enddef
RunSection('3', Section3)

# ── 4: the agent gets the file window's context from the vproj pane ──
# Used to: GatherAgentContext read the CURRENT buffer, so from the pane it
# reported no file; and it accepted nofile/terminal/help buffers as files.
var agent_dir: string = tempname()
mkdir(agent_dir, 'p')
# Published with cp + mv (atomic): the test polls for agent.ctx and reads it at
# once, and a plain cp makes the file visible before it holds its content.
writefile([
  '#!/bin/bash',
  'cp "$VPROJ_AGENT_CTX_FILE" "$FAKE_DIR/agent.ctx.tmp"',
  'mv "$FAKE_DIR/agent.ctx.tmp" "$FAKE_DIR/agent.ctx"',
], agent_dir .. '/fakeagent')
setfperm(agent_dir .. '/fakeagent', 'rwx------')

def RunAgent(): any
  delete(fake_dir .. '/agent.ctx')
  vproj#agent#AgentOpen()
  if !WaitFor(() => filereadable(fake_dir .. '/agent.ctx'), 30000)
    return v:null
  endif
  return json_decode(join(readfile(fake_dir .. '/agent.ctx'), "\n"))
enddef

# Leave the agent terminal window (and any other split it made) behind.
def CloseAgentWindows(keep: number): void
  KillTerminals()
  for w in range(winnr('$'), 1, -1)
    if getwinvar(w, '&buftype') == 'terminal' && win_getid(w) != keep
      execute w .. 'close!'
    endif
  endfor
enddef

def Section4(): void
  UnsetAll()
  g:vproj_agent_cmd = agent_dir .. '/fakeagent'
  var src_file: string = $HOME .. '/agent_src.txt'
  writefile(map(range(1, 20), (_, n) => 'line ' .. n), src_file)
  var proj: string = $HOME .. '/proj'
  mkdir(proj, 'p')
  writefile(['x'], proj .. '/a.txt')
  execute 'cd ' .. fnameescape(proj)
  execute 'edit ' .. fnameescape(src_file)
  cursor(7, 3)
  var file_win: number = win_getid()
  vproj#PaneOpen()
  var pane_win: number = win_findbuf(vproj#GetPaneBufnr())->get(0, 0)
  Assert(pane_win > 0 && pane_win != file_win, '4: vproj pane is open in its own window')
  win_gotoid(pane_win)
  Assert(bufnr('%') == vproj#GetPaneBufnr(), '4: current window is the pane')
  # The agent terminal opens in a new window and makes it current; the
  # alternate window ('#') at the time of the call is what matters, so
  # AgentOpen must read the context BEFORE splitting (it does).

  var ctx: any = RunAgent()
  Assert(type(ctx) == v:t_dict, '4: agent ran and wrote context')
  if type(ctx) == v:t_dict
    Assert(get(ctx, 'file', '') == src_file, '4: from the pane, ctx.file is the file window (' .. get(ctx, 'file', '<none>') .. ')')
    Assert(get(ctx, 'cursor_line', 0) == 7 && get(ctx, 'cursor_col', 0) == 3, '4: cursor comes from the file window')
    Assert(get(ctx, 'file_total_lines', 0) == 20 && len(get(ctx, 'file_lines', [])) == 20, '4: file lines come from the file buffer')
  endif
  CloseAgentWindows(0)

  # A nofile buffer is not a file.
  win_gotoid(file_win)
  enew
  setlocal buftype=nofile
  ctx = RunAgent()
  Assert(type(ctx) == v:t_dict && !has_key(ctx, 'file'), '4: nofile buffer is not reported as a file (' .. string(ctx) .. ')')
  CloseAgentWindows(0)
  win_gotoid(file_win)
  bwipeout!

  # Neither is a help buffer.
  help
  Assert(&buftype == 'help', '4: setup: current buffer is help')
  ctx = RunAgent()
  Assert(type(ctx) == v:t_dict && !has_key(ctx, 'file'), '4: help buffer is not reported as a file (' .. string(ctx) .. ')')
  CloseAgentWindows(0)
  helpclose

  # From the file window itself it still works.
  win_gotoid(file_win)
  execute 'edit ' .. fnameescape(src_file)
  cursor(12, 1)
  ctx = RunAgent()
  Assert(type(ctx) == v:t_dict && get(ctx, 'file', '') == src_file && get(ctx, 'cursor_line', 0) == 12,
    '4: from the file window, ctx is that window (' .. string(ctx) .. ')')
  CloseAgentWindows(0)
  vproj#PaneClose()
enddef
RunSection('4', Section4)

# ── Report ──
delete(fake_dir, 'rf')
delete(agent_dir, 'rf')
log->add('---')
log->add('AI credential tests: ' .. (failures == 0 ? 'ALL PASSED' : failures .. ' FAILURES'))
for line in log
  echom line
endfor
var result_file: any = getenv('VPROJ_TEST_RESULT')
if type(result_file) == v:t_string && !empty(result_file)
  writefile(log, result_file)
endif
if failures > 0
  cquit!
endif
qa!

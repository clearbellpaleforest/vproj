vim9script
# Test suite for vproj AI module (autoload/vproj/ai.vim)
# Run (isolate HOME; no real keys, no network — curl is a fake on PATH):
#   HOME=$T XDG_CACHE_HOME=$T/cache vim -N -u NONE -i NONE --not-a-term \
#     -S tests/unit/test_ai.vim </dev/null
# Exits with :qa! when every assertion passes, :cquit! otherwise.
# Results also go to $VPROJ_TEST_RESULT when that is set.

# Isolate the cache dir before anything is loaded.
$XDG_CACHE_HOME = tempname()
set nomore
set ttimeout ttimeoutlen=0 timeoutlen=0
set hidden   # keep the alternate buffer loaded so its lines can be checked

g:failures = 0
var log: list<string> = []

def Assert(cond: bool, msg: string): void
  if cond
    log->add('PASS: ' .. msg)
  else
    log->add('FAIL: ' .. msg)
    g:failures += 1
  endif
enddef

var repo: string = expand('<sfile>:p:h:h:h')

# Load vproj first (ai.vim depends on vproj functions)
execute 'source' repo .. '/src/autoload/vproj.vim'
execute 'source' repo .. '/src/autoload/vproj/ai.vim'

log->add('=== test_ai.vim ===')

# ── Fakes: curl on PATH, fake key, unroutable https URL ──
var fake_dir: string = tempname()
mkdir(fake_dir, 'p')
writefile([
  '#!/bin/bash',
  'd="$FAKE_DIR"',
  'n=$(date +%s%N)',
  'printf "%s\n" "$@" > "$d/argv.$n"',
  'for a in "$@"; do case "$a" in @*) f="${a#@}"; stat -c %a "$f" >> "$d/perms.$n"; echo "$f" >> "$d/files.$n"; cat "$f" > "$d/data.$n.$(basename "$f")";; esac; done',
  'if [ -f "$d/slow" ]; then rm -f "$d/slow"; sleep 3; fi',
  'if grep -qs "\"stream\":false" "$d"/data.$n.*; then cat "$d/reply.json"; exit 0; fi',
  'cat "$d/reply.sse"',
], fake_dir .. '/curl')
setfperm(fake_dir .. '/curl', 'rwx------')
$FAKE_DIR = fake_dir
$PATH = fake_dir .. ':' .. $PATH
$DEEPSEEK_API_KEY = ''
$OPENAI_API_KEY = ''
g:vproj_ai_api_key = 'sk-test-FAKE'
g:vproj_ai_api_url = 'https://example.invalid/v1/chat/completions'
g:vproj_ai_model = 'test-model'

def SetReply(text: string): void
  var sse: list<string> = []
  # Two chunks, split mid-text, to exercise accumulation.
  var half: number = strchars(text) / 2
  for chunk in [strcharpart(text, 0, half), strcharpart(text, half)]
    sse->add('data: ' .. json_encode({choices: [{delta: {content: chunk}}]}))
    sse->add('')
  endfor
  sse->add('data: [DONE]')
  sse->add('')
  writefile(sse, fake_dir .. '/reply.sse')
  writefile([json_encode({choices: [{message: {role: 'assistant', content: text}}]})], fake_dir .. '/reply.json')
enddef

# All files the fake curl received via @path, across every call so far.
def CurlFiles(): list<string>
  var files: list<string> = []
  for f in glob(fake_dir .. '/files.*', 0, 1)
    files += readfile(f)
  endfor
  return files
enddef

def CurlPerms(): list<string>
  var perms: list<string> = []
  for f in glob(fake_dir .. '/perms.*', 0, 1)
    perms += readfile(f)
  endfor
  return perms
enddef

def CurlArgv(): string
  var text: string = ''
  for f in glob(fake_dir .. '/argv.*', 0, 1)
    text ..= join(readfile(f), "\n") .. "\n"
  endfor
  return text
enddef

# Clear the fake curl's records. One glob per prefix: a {a,b} pattern is
# expanded by 'shell', and dash (/bin/sh on Debian/Ubuntu) has no brace
# expansion, so it matched nothing there and stale records leaked between
# sections.
def ResetFake(): void
  for prefix in ['argv', 'perms', 'files', 'data']
    for f in glob(fake_dir .. '/' .. prefix .. '.*', 0, 1)
      delete(f)
    endfor
  endfor
enddef

# Wait (processing callbacks) until a message containing {needle} appears.
def WaitMessage(needle: string, ms: number = 5000): bool
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < ms
    if stridx(execute('messages'), needle) >= 0
      return true
    endif
    sleep 20m
  endwhile
  return false
enddef

def WaitGone(files: list<string>, ms: number = 5000): bool
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < ms
    if empty(filter(copy(files), (_, f) => filereadable(f)))
      return true
    endif
    sleep 20m
  endwhile
  return false
enddef

# Shared fixtures (used across sections).
var ctx: dict<any> = {
  file: '/x/notes', filetype: '', mode: 'file', cursor_line: 2,
  file_lines: ['alpha', 'béta', 'gamma'], file_line_offset: 1, file_total_lines: 3,
}
var file_a: string = tempname() .. '_a.txt'
var file_b: string = tempname() .. '_b.txt'
var buf_a: number = -1
var buf_b: number = -1

# Run one section; an exception counts as a failure instead of aborting
# the whole suite.
def RunSection(name: string, F: func(): void): void
  try
    F()
  catch
    Assert(false, name .. ' threw: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
enddef

# ── Defect 2: chat script path resolves to <repo>/bin/vproj-ai-chat ──
def Section1(): void
  var chat_path: string = vproj#ai#ChatScriptPath()
  Assert(filereadable(chat_path), 'ChatScriptPath: filereadable (' .. chat_path .. ')')
  Assert(resolve(chat_path) == resolve(repo .. '/bin/vproj-ai-chat'), 'ChatScriptPath: is <repo>/bin/vproj-ai-chat')
enddef
RunSection('Defect 2: chat script path resolves to <repo>/bin/vproj-ai-chat', Section1)

# ── JsonEscape ──
def Section2(): void
  var je_plain: string = vproj#ai#JsonEscape('hello')
  Assert(je_plain =~ '^".*"$', 'JsonEscape: wraps in quotes')
  Assert(stridx(je_plain, 'hello') > 0, 'JsonEscape: contains input')
  Assert(stridx(vproj#ai#JsonEscape('he"llo'), '\"') > 0, 'JsonEscape: escapes double quote')
  Assert(stridx(vproj#ai#JsonEscape('he\llo'), '\\') > 0, 'JsonEscape: escapes backslash')
  Assert(stridx(vproj#ai#JsonEscape("line1\nline2"), '\n') > 0, 'JsonEscape: escapes newline')
  Assert(stridx(vproj#ai#JsonEscape("tab\there"), '\t') > 0, 'JsonEscape: escapes tab')
  Assert(vproj#ai#JsonEscape('') == '""', 'JsonEscape: empty string → ""')
  # Defect 4: non-ASCII must survive (old code injected \u0000)
  var nonascii: string = "café 日本 😀 \x01 \"q\""
  var je_utf: string = vproj#ai#JsonEscape(nonascii)
  Assert(stridx(je_utf, '\u0000') < 0, 'JsonEscape: no \u0000 injected for non-ASCII')
  Assert(json_decode(je_utf) == nonascii, 'JsonEscape: non-ASCII round-trips through json_decode')
enddef
RunSection('JsonEscape', Section2)

# ── ExtractJsonField ──
def Section3(): void
  Assert(vproj#ai#ExtractJsonField('{"key":"value"}', 'key') == 'value', 'ExtractJsonField: simple field')
  Assert(vproj#ai#ExtractJsonField('{"key": "value"}', 'key') == 'value', 'ExtractJsonField: spaced field')
  Assert(vproj#ai#ExtractJsonField('{"a":1,"b":2}', 'b') == '2', 'ExtractJsonField: second field')
  Assert(vproj#ai#ExtractJsonField('{"deep":{"nested":"x"}}', 'deep') == '{"nested":"x"}', 'ExtractJsonField: nested object')
  Assert(vproj#ai#ExtractJsonField('{"key":"value"}', 'missing') == '', 'ExtractJsonField: missing field')
  Assert(vproj#ai#ExtractJsonField('not json', 'key') == '', 'ExtractJsonField: non-JSON')
  Assert(vproj#ai#ExtractJsonField('', 'key') == '', 'ExtractJsonField: empty input')
  # Defect 4: byte offsets vs char slicing — non-ASCII before the field
  Assert(vproj#ai#ExtractJsonField('{"pre":"日本語éé","key":"vé日"}', 'key') == 'vé日', 'ExtractJsonField: non-ASCII before and in value')
  Assert(vproj#ai#ExtractJsonField('{"choices":[{"message":{"content":"xé"}}]}', 'content') == 'xé', 'ExtractJsonField: nested field, \u escape decoded')
  Assert(vproj#ai#ExtractJsonField('{"key":"unterminated', 'key') == '', 'ExtractJsonField: truncated JSON')
enddef
RunSection('ExtractJsonField', Section3)

# ── ExtractCodeBlocks ──
def Section4(): void
  var single: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```vim\necho 'hi'\n```")
  Assert(len(single) == 1, 'ExtractCodeBlocks: single block count')
  Assert(get(single[0], 'language', '') == 'vim', 'ExtractCodeBlocks: language tag')
  Assert(get(single[0], 'code', '') == "echo 'hi'", 'ExtractCodeBlocks: code content')
  var multi: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```python\nx=1\n```\n```vim\necho 'y'\n```")
  Assert(len(multi) == 2, 'ExtractCodeBlocks: multi block count')
  Assert(get(multi[1], 'language', '') == 'vim', 'ExtractCodeBlocks: second language')
  Assert(len(vproj#ai#ExtractCodeBlocks("just some text\nno code here")) == 0, 'ExtractCodeBlocks: no fences returns empty')
  Assert(len(vproj#ai#ExtractCodeBlocks("```\n\n```")) == 0, 'ExtractCodeBlocks: empty fence block')
  var no_lang: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```\ncode\n```")
  Assert(len(no_lang) == 1, 'ExtractCodeBlocks: no lang tag')
  Assert(get(no_lang[0], 'code', '') == 'code', 'ExtractCodeBlocks: code without lang')
enddef
RunSection('ExtractCodeBlocks', Section4)

# ── Defect 10: BuildRequestBody sends file content; no "()" for empty filetype ──
def Section5(): void
  vproj#ai#AiConfigure()
  var body: dict<any> = json_decode(vproj#ai#BuildRequestBody('do it', ctx, true))
  var sys: string = body.messages[0].content
  Assert(body.model == 'test-model' && body.stream == v:true, 'BuildRequestBody: valid JSON, model + stream')
  Assert(body.messages[1].content == 'do it', 'BuildRequestBody: user prompt')
  Assert(stridx(sys, 'béta') >= 0 && stridx(sys, 'alpha') >= 0, 'BuildRequestBody: includes gathered file lines')
  Assert(stridx(sys, '()') < 0 && stridx(sys, 'editing notes.') >= 0, 'BuildRequestBody: empty filetype omitted')
  ctx.filetype = 'python'
  sys = json_decode(vproj#ai#BuildRequestBody('x', ctx, false)).messages[0].content
  Assert(stridx(sys, 'editing notes (python).') >= 0, 'BuildRequestBody: filetype shown when set')
enddef
RunSection('Defect 10: BuildRequestBody sends file content; no "()" for empty filetype', Section5)

# ── AiCall (sync): body via file, content decoded ──
def Section6(): void
  ResetFake()
  SetReply('réponse 日本')
  var sync_result: string = vproj#ai#AiCall('sync prompt SECRET-PROMPT', ctx)
  Assert(sync_result == 'réponse 日本', 'AiCall: non-ASCII content decoded (' .. sync_result .. ')')
  Assert(stridx(CurlArgv(), 'SECRET-PROMPT') < 0 && stridx(CurlArgv(), 'sk-test-FAKE') < 0, 'AiCall: prompt and key not in argv')
  Assert(!empty(CurlFiles()) && empty(filter(CurlFiles(), (_, f) => filereadable(f))), 'AiCall: temp files deleted')
  Assert(!empty(CurlPerms()) && empty(filter(CurlPerms(), (_, p) => p != '600')), 'AiCall: temp files were 0600')
enddef
RunSection('AiCall (sync): body via file, content decoded', Section6)

# ── Defect 3: code mode targets the CURRENT buffer, not the alternate ──
def Section7(): void
  writefile(['a1', 'a2'], file_a)
  writefile(['b1', 'b2', 'b3'], file_b)
  execute 'edit ' .. fnameescape(file_a)
  execute 'edit ' .. fnameescape(file_b)
  buf_a = bufnr(file_a)
  buf_b = bufnr(file_b)
  cursor(2, 1)
  Assert(bufnr('#') == buf_a && bufnr('%') == buf_b, 'setup: alternate is A, current is B')

  # 3a: confirm Yes → applied to B after cursor line, A untouched
  ResetFake()
  SetReply("Sure:\n```text\nNEW1\nNEW2\n```\n")
  messages clear
  feedkeys('y', 'L')
  vproj#ai#AiPrompt('!insert SECRET-STREAM-PROMPT lines')
  Assert(WaitMessage('vproj-ai: applied'), 'AiPrompt code: applied after Yes')
  Assert(getbufline(buf_b, 1, '$') == ['b1', 'b2', 'NEW1', 'NEW2', 'b3'], 'AiPrompt code: inserted into current buffer after cursor')
  Assert(getbufline(buf_a, 1, '$') == ['a1', 'a2'], 'AiPrompt code: alternate buffer untouched')
  # Defects 7/8: stream body + header passed as 0600 files, deleted after exit
  var stream_files: list<string> = CurlFiles()
  Assert(len(stream_files) == 2, 'AiCallStream: body and header passed as @files')
  Assert(WaitGone(stream_files), 'AiCallStream: temp files deleted on exit')
  Assert(empty(filter(CurlPerms(), (_, p) => p != '600')), 'AiCallStream: temp files were 0600')
  Assert(stridx(CurlArgv(), 'SECRET-STREAM-PROMPT') < 0 && stridx(CurlArgv(), 'sk-test-FAKE') < 0, 'AiCallStream: prompt and key not in argv')

  # 3b: confirm Esc → not applied
  ResetFake()
  messages clear
  feedkeys("\<Esc>", 'L')
  vproj#ai#AiPrompt('!insert again')
  Assert(WaitMessage('vproj-ai: not applied'), 'AiPrompt code: Esc means No')
  Assert(getbufline(buf_b, 1, '$') == ['b1', 'b2', 'NEW1', 'NEW2', 'b3'], 'AiPrompt code: buffer unchanged after Esc')

  # 3c: no ``` fence → refused, prose never inserted, no confirm asked
  ResetFake()
  SetReply('Just prose, no code fence here.')
  messages clear
  vproj#ai#AiPrompt('!make it better')
  Assert(WaitMessage('nothing applied'), 'AiPrompt code: response without fence refused')
  Assert(getbufline(buf_b, 1, '$') == ['b1', 'b2', 'NEW1', 'NEW2', 'b3'], 'AiPrompt code: prose not inserted')
  popup_clear()

  # 3d: code mode with no file window → refused before any request
  ResetFake()
  var origin_win: number = win_getid()
  botright new
  setlocal buftype=nofile
  messages clear
  vproj#ai#AiPrompt('!insert something')
  Assert(stridx(execute('messages'), 'no file window') >= 0, 'AiPrompt code: refused without a file window')
  Assert(empty(glob(fake_dir .. '/argv.*', 0, 1)), 'AiPrompt code: no request sent without a target')
  close
  win_gotoid(origin_win)
enddef
RunSection('Defect 3: code mode targets the CURRENT buffer, not the alternate', Section7)

# ── Defect 7: superseded (stale) job still deletes its temp files ──
def Section8(): void
  ResetFake()
  SetReply('answer')
  writefile([], fake_dir .. '/slow')
  messages clear
  vproj#ai#AiPrompt('?first question')
  var start: list<any> = reltime()
  while len(glob(fake_dir .. '/files.*', 0, 1)) < 1 && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  vproj#ai#AiPrompt('?second question')
  Assert(WaitMessage('response in popup'), 'stale job: second request completes')
  start = reltime()
  while len(CurlFiles()) < 4 && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  var all_files: list<string> = CurlFiles()
  Assert(len(all_files) == 4, 'stale job: both requests passed two @files (' .. len(all_files) .. ')')
  Assert(WaitGone(all_files), 'stale job: temp files of cancelled AND current job deleted')
  popup_clear()
enddef
RunSection('Defect 7: superseded (stale) job still deletes its temp files', Section8)

# ── Defects 5 / 9: terminal chat opens ONE 15-line window, no log write ──
def Section9(): void
  var errlog: string = '/tmp/vproj-ai-errors.log'
  var errlog_time: number = getftime(errlog)
  only
  var wins_before: number = winnr('$')
  var bufs_before: number = len(getbufinfo())
  var vim_tmpdir: string = fnamemodify(tempname(), ':h')
  var tmp_before: list<string> = readdir(vim_tmpdir)
  vproj#ai#AiTerminalChat()
  var termbuf: number = bufnr('%')
  Assert(getbufvar(termbuf, '&buftype') == 'terminal', 'AiTerminalChat: current window is the terminal')
  Assert(winnr('$') == wins_before + 1, 'AiTerminalChat: exactly one new window (' .. winnr('$') .. ')')
  Assert(winheight(0) == 15, 'AiTerminalChat: terminal window is 15 lines (' .. winheight(0) .. ')')
  Assert(len(getbufinfo()) == bufs_before + 1, 'AiTerminalChat: no orphan empty buffer')
  Assert(getftime(errlog) == errlog_time, 'AiTerminalChat: does not write ' .. errlog)
  var chat_job: job = term_getjob(termbuf)
  var start: list<any> = reltime()
  while stridx(term_getline(termbuf, 1) .. term_getline(termbuf, 2), 'vproj_ai') < 0 && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  term_sendkeys(termbuf, "/exit\r")
  start = reltime()
  while job_status(chat_job) == 'run' && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  sleep 100m
  Assert(job_status(chat_job) == 'dead', 'AiTerminalChat: chat exits on /exit')
  var leaked: list<string> = filter(readdir(vim_tmpdir), (_, f) => index(tmp_before, f) < 0)
  Assert(empty(leaked), 'AiTerminalChat: key/system/header/body temp files removed (' .. string(leaked) .. ')')

  # Esc path: the mapping stops the job with SIGTERM (not :bdelete!, which
  # SIGKILLs bash and skips its EXIT trap). Run the mapping's command.
  vproj#ai#AiTerminalChat()
  termbuf = bufnr('%')
  var esc_rhs: string = maparg('<Esc>', 't')
  Assert(stridx(esc_rhs, "job_stop(term_getjob(bufnr()), 'term')") >= 0, 'AiTerminalChat: Esc mapped to SIGTERM job_stop (' .. esc_rhs .. ')')
  chat_job = term_getjob(termbuf)
  start = reltime()
  while len(filter(readdir(vim_tmpdir), (_, f) => index(tmp_before, f) < 0)) < 4 && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  job_stop(term_getjob(bufnr()), 'term')
  start = reltime()
  while job_status(chat_job) == 'run' && reltimefloat(reltime(start)) < 5.0
    sleep 20m
  endwhile
  sleep 100m
  leaked = filter(readdir(vim_tmpdir), (_, f) => index(tmp_before, f) < 0)
  Assert(empty(leaked), 'AiTerminalChat: temp files removed after Esc (' .. string(leaked) .. ')')
  Assert(winnr('$') == wins_before, 'AiTerminalChat: window closed after Esc')
enddef
RunSection('Defects 5 / 9: terminal chat opens ONE 15-line window, no log write', Section9)

# ── Function existence checks ──
def Section10(): void
  Assert(exists('*vproj#ai#AiTerminalChat'), 'Export: AiTerminalChat')
  Assert(exists('*vproj#ai#AiCall'), 'Export: AiCall')
  Assert(exists('*vproj#ai#AiPrompt'), 'Export: AiPrompt')
  Assert(exists('*vproj#ai#AiPromptFromKey'), 'Export: AiPromptFromKey')
  Assert(exists('*vproj#ai#StreamCancelCmd'), 'Export: StreamCancelCmd')
  Assert(exists('*vproj#ai#JsonEscape'), 'Export: JsonEscape')
  Assert(exists('*vproj#ai#ExtractJsonField'), 'Export: ExtractJsonField')
  Assert(exists('*vproj#ai#BuildRequestBody'), 'Export: BuildRequestBody')
  Assert(exists('*vproj#ai#ExtractCodeBlocks'), 'Export: ExtractCodeBlocks')
  Assert(exists('*vproj#ai#AiConfigure'), 'Export: AiConfigure')
  Assert(exists('*vproj#ai#AiCallStream'), 'Export: AiCallStream')
enddef
RunSection('Function existence checks', Section10)

# ── Cleanup and report ──
delete(fake_dir, 'rf')
delete(file_a)
delete(file_b)
log->add('---')
log->add('AI module tests: ' .. (g:failures == 0 ? 'ALL PASSED' : g:failures .. ' FAILURES'))
for line in log
  echom line
endfor
var result_file: any = getenv('VPROJ_TEST_RESULT')
if type(result_file) == v:t_string && !empty(result_file)
  writefile(log, result_file)
endif
if g:failures > 0
  cquit!
endif
qa!

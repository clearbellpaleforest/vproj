vim9script

# Regression tests for the sixth 2026-11 audit, "misc2" group. Each block pins
# one reproduced defect; the comment names what used to happen.
#   1. ai.vim DetectMode: WORD_END counted every non-ASCII char as a word char,
#      so "what<U+2019>s this" was code.
#   2. ai.vim StripPrefix/DetectMode disagreed about NBSP.
#   3. ai.vim: an API {"error":...} frame was dropped silently.
#   4. ai.vim test gaps: FindField depth limit, ApplyStreamFrame guards.
#   5. TruncateToWidth was quadratic on zero-width runs.
#   6. EntryRegex under 'regexpengine'=1 was exponential; engines must agree.
#   7. WriteVprojFile overwrote a read-only .vproj.
#   8. Unloaded buffers showed "1" as their line count.
#   9. Vim 8.2.3995 compatibility: no isabsolutepath() call, no "for _ in" in src.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/unit/test_audit_2026_11f_misc.vim -c 'cquit!' </dev/null
#
# Hermetic: the session cache and every fixture live under tempname(); curl is
# a fake on PATH, so no network and no real key.

$XDG_CACHE_HOME = tempname()
var repo: string = fnamemodify(expand('<script>:p'), ':h:h:h')
execute 'set rtp^=' .. fnameescape(repo .. '/src')
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0 timeoutlen=0
set hidden

var failures: number = 0
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit6f'
mkdir(root, 'p')
var is_utf8: bool = &encoding == 'utf-8'

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# A section that throws is a failure, not an aborted script.
def RunSection(name: string, F: func(): void): void
  try
    F()
  catch
    Assert(false, name .. ' threw: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
enddef

# ══════════════════════════════════════════════════════════════════════════
# AI module, through a fake curl (as tests/unit/test_audit_2026_11e_misc.vim)
# ══════════════════════════════════════════════════════════════════════════
var fake_dir: string = root .. '/fake'
mkdir(fake_dir, 'p')
writefile([
  '#!/bin/bash',
  'd="$FAKE_DIR"',
  'n=$(date +%s%N)',
  'for a in "$@"; do case "$a" in @*) f="${a#@}"; cat "$f" > "$d/data.$n.$(basename "$f").tmp" && mv "$d/data.$n.$(basename "$f").tmp" "$d/data.$n.$(basename "$f")";; esac; done',
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

def ResetFake(): void
  for prefix in ['data', 'reply']
    for f in glob(fake_dir .. '/' .. prefix .. '.*', 0, 1)
      delete(f)
    endfor
  endfor
enddef

def PopupText(): string
  var out: list<string> = []
  for id in popup_list()
    out += getbufline(winbufnr(id), 1, '$')
  endfor
  return join(out, "\n")
enddef

def Frame(s: string): string
  return 'data: ' .. json_encode({choices: [{delta: {content: s}}]})
enddef

# Serve {sse} to the fake curl (published atomically).
def Serve(sse: list<string>): void
  ResetFake()
  writefile(sse, fake_dir .. '/reply.sse.tmp')
  rename(fake_dir .. '/reply.sse.tmp', fake_dir .. '/reply.sse')
enddef

# Poll {cond} for at most 30 s.
def WaitFor(Cond: func(): bool): bool
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < 30000
    if Cond()
      return true
    endif
    sleep 20m
  endwhile
  return false
enddef

# The stream has ended once one of the terminal messages is in :messages.
def StreamEnded(): bool
  var m: string = execute('messages')
  return stridx(m, 'response in popup') >= 0 || stridx(m, 'empty response') >= 0
    || stridx(m, 'API call failed') >= 0 || stridx(m, 'API error') >= 0
    || stridx(m, 'no ``` fenced') >= 0
enddef

# Run {prompt} against {sse}; returns the popup text and :messages.
def RunPrompt(prompt: string, sse: list<string>): dict<any>
  Serve(sse)
  popup_clear()
  messages clear
  v:errmsg = ''
  vproj#ai#AiPrompt(prompt)
  WaitFor(StreamEnded)
  return {popup: PopupText(), messages: execute('messages'), errmsg: v:errmsg}
enddef

# Mode DetectMode chose for {prompt}, read from the "streaming" message. The
# request is cancelled at once; only the verdict matters.
def ModeOf(prompt: string): string
  Serve([Frame('r'), '', 'data: [DONE]', ''])
  messages clear
  vproj#ai#AiPrompt(prompt)
  var m: string = execute('messages')
  vproj#ai#StreamCancelCmd()
  if stridx(m, 'vproj-ai: streaming (question) for') >= 0
    return 'question'
  elseif stridx(m, 'vproj-ai: streaming for') >= 0
    return 'code'
  endif
  return 'none'
enddef

# What was sent: the last request body's user message.
def SentText(prompt: string): string
  Serve([Frame('r'), '', 'data: [DONE]', ''])
  messages clear
  vproj#ai#AiPrompt(prompt)
  var files: list<string> = []
  WaitFor(() => {
    files = filter(glob(fake_dir .. '/data.*', 0, 1), (_, f) => f !~ '\.tmp$' && readfile(f)->join('') =~ '"messages"')
    return !empty(files)
  })
  var content: string = '<nothing sent>'
  if !empty(files)
    content = json_decode(join(readfile(files[0]), '')).messages[-1].content
  endif
  vproj#ai#StreamCancelCmd()
  return content
enddef

# ── 1 + 2: mode detection ──
def Section1(): void
  var file_m: string = root .. '/m.txt'
  writefile(['m1', 'm2'], file_m)
  execute 'edit ' .. fnameescape(file_m)

  # Used to: [^\x00-\x7f] made EVERY non-ASCII char a word char, so a question
  # whose leading word was followed by non-ASCII punctuation or a no-break
  # space was classified as code.
  var cases: list<list<string>> = []
  if is_utf8
    cases = [
      ['what' .. nr2char(0x2019) .. 's this', 'question'],
      ['explain' .. nr2char(0x2026) .. ' it', 'question'],
      ['why' .. nr2char(0xff1f), 'question'],
      ['how' .. nr2char(0x3001), 'question'],
      ['explain' .. nr2char(0xa0) .. 'this', 'question'],
      ['why' .. nr2char(0x201c) .. 'x' .. nr2char(0x201d), 'question'],
      ['where' .. nr2char(0x2014) .. 'is it', 'question'],
      ['why' .. nr2char(0xe9) .. ' x', 'code'],
      ['how' .. nr2char(0x4e2d) .. ' x', 'code'],
      ['whatever', 'code'],
      ['add' .. nr2char(0x2019) .. 'x', 'code'],
      ['fix' .. nr2char(0xa0) .. 'it', 'code'],
    ]
  else
    echom 'SKIP: encoding is ' .. &encoding .. ', not utf-8: the U+2019/U+2026/U+FF1F/U+3001 cases need utf-8'
    cases = [
      ['explain' .. nr2char(0xa0) .. 'this', 'question'],
      ['why' .. nr2char(0xbf) .. 'x', 'question'],
      ['why' .. nr2char(0xe9) .. ' x', 'code'],
      ['whatever', 'code'],
      ['fix' .. nr2char(0xa0) .. 'it', 'code'],
    ]
  endif
  for re in [0, 1, 2]
    execute 'set regexpengine=' .. re
    for c in cases
      var got: string = ModeOf(c[0])
      Assert(got == c[1], 'regexpengine=' .. re .. ' enc=' .. &encoding .. ': "' .. strtrans(c[0]) .. '" is ' .. c[1] .. ' (got ' .. got .. ')')
    endfor
  endfor
  set regexpengine=0

  # Used to: StripPrefix used substitute('^\s*'), which leaves a no-break
  # space, while DetectMode used trim(), which strips it: " ?why" (NBSP first)
  # was a question whose '?' was sent to the API.
  var nbsp: string = nr2char(0xa0)
  var sent: string = SentText(nbsp .. '?why')
  Assert(sent == 'why', 'NBSP-led "?why" is stripped to "why" (sent "' .. strtrans(sent) .. '")')
  sent = SentText(nbsp .. '!add x')
  Assert(sent == 'add x', 'NBSP-led "!add x" is stripped to "add x" (sent "' .. strtrans(sent) .. '")')
  sent = SentText('?' .. nbsp .. 'why')
  Assert(sent == 'why', '"?" + NBSP + "why" drops the NBSP too (sent "' .. strtrans(sent) .. '")')
  Assert(ModeOf(nbsp .. '?why') == 'question', 'NBSP-led "?why" is still a question')
  popup_clear()
  silent! bwipeout!
enddef
RunSection('1', Section1)

# ── 3: API error frames ──
def Section3(): void
  var file_m: string = root .. '/m3.txt'
  writefile(['m1', 'm2'], file_m)
  execute 'edit ' .. fnameescape(file_m)

  # Used to: the frame has no "choices", so it was skipped and the user got an
  # empty popup / "no fenced code block", never the API's message.
  var r: dict<any> = RunPrompt('?q', ['data: {"error":{"message":"rate limited","type":"x"}}', ''])
  Assert(r.messages =~ 'vproj-ai: API error -- rate limited', 'question: the API message is shown (' .. substitute(r.messages, "\n", '|', 'g') .. ')')
  Assert(empty(r.popup), 'question: no popup on an API error')
  r = RunPrompt('add a line', ['data: {"error":{"message":"quota exceeded"}}', ''])
  Assert(r.messages =~ 'vproj-ai: API error -- quota exceeded' && r.messages !~ 'no ``` fenced', 'code: the API message replaces "no fenced code block" (' .. substitute(r.messages, "\n", '|', 'g') .. ')')
  r = RunPrompt('?q', ['data: {"error":"boom"}', ''])
  Assert(r.messages =~ 'vproj-ai: API error -- boom', 'a plain-string error is shown (' .. substitute(r.messages, "\n", '|', 'g') .. ')')
  r = RunPrompt('?q', ['data: {"error":{"code":42}}', ''])
  Assert(r.messages =~ 'vproj-ai: API error -- .*42', 'an error without a message shows the frame (' .. substitute(r.messages, "\n", '|', 'g') .. ')')

  # Everything vproj prints is ASCII: a server's non-ASCII text is sanitised.
  var cafe: string = 'caf' .. nr2char(0xe9) .. ' ' .. (is_utf8 ? nr2char(0x2019) : '') .. 'x'
  r = RunPrompt('?q', ['data: ' .. json_encode({error: {message: cafe}}), ''])
  var line: string = matchstr(r.messages, 'vproj-ai: API error -- [^' .. "\n" .. ']*')
  Assert(!empty(line) && line !~ '[^\x20-\x7e]', 'non-ASCII server text is not printed raw (' .. strtrans(line) .. ')')

  # Content wins: an error AFTER content is not the response.
  r = RunPrompt('?q', [Frame('GOOD'), '', 'data: {"error":{"message":"late"}}', '', 'data: [DONE]', ''])
  Assert(r.popup == 'GOOD' && r.messages !~ 'API error', 'content then error: the content is shown (popup "' .. r.popup .. '")')

  # The next stream starts clean.
  r = RunPrompt('?q', ['data: {"error":{"message":"stale"}}', ''])
  Assert(r.messages =~ 'API error -- stale', 'precondition: error recorded')
  r = RunPrompt('?q', ['data: [DONE]', ''])
  Assert(r.messages =~ 'empty response' && r.messages !~ 'API error', 'an old error does not leak into the next stream (' .. substitute(r.messages, "\n", '|', 'g') .. ')')

  # Malformed frames are still skipped quietly.
  r = RunPrompt('?q', ['data: {"error":', '', Frame('OK'), '', 'data: [DONE]', ''])
  Assert(r.popup == 'OK' && r.messages !~ 'API error', 'a malformed frame is skipped, not reported (popup "' .. r.popup .. '")')
  popup_clear()
  silent! bwipeout!
enddef
RunSection('3', Section3)

# ── 4: test gaps ──
def Section4(): void
  # (a) FindField depth. json_decode itself fails at 100 levels, so the only
  # depths that reach FindField are < 100. Used to: 150 levels (never reached
  # it). Unlimited recursion throws E132 near 95-99; the limit is 50.
  var deep_throw: string = ''
  var r: string = 'unset'
  for depth in [95, 99]
    deep_throw = ''
    r = 'unset'
    var j: string = repeat('{"x":', depth) .. '{"k":"found"}' .. repeat('}', depth)
    try
      r = vproj#ai#ExtractJsonField(j, 'k')
    catch
      deep_throw = v:exception
    endtry
    Assert(deep_throw == '' && r == '', depth .. '-deep JSON: "" and no E132 (got "' .. r .. '" / ' .. deep_throw .. ')')
  endfor
  # Limit semantics: nesting 50 is found, 51 is not.
  for [depth, want] in [[10, 'found'], [45, 'found'], [50, 'found'], [51, ''], [60, '']]
    var j: string = repeat('{"x":', depth) .. '{"k":"found"}' .. repeat('}', depth)
    r = vproj#ai#ExtractJsonField(j, 'k')
    Assert(r == want, 'field at nesting ' .. depth .. ' gives "' .. want .. '" (got "' .. r .. '")')
  endfor
  # The same through lists.
  var lj: string = repeat('[', 49) .. '{"k":"L"}' .. repeat(']', 49)
  Assert(vproj#ai#ExtractJsonField(lj, 'k') == 'L', 'a field under 49 lists is found')
  lj = repeat('[', 60) .. '{"k":"L"}' .. repeat(']', 60)
  Assert(vproj#ai#ExtractJsonField(lj, 'k') == '', 'a field under 60 lists is not found')

  # (b) ApplyStreamFrame guards. Used to be untested: a frame with an empty
  # choices list, a non-dict choice or a non-dict delta must be skipped
  # without an error, and the good frames around it must arrive.
  var file_m: string = root .. '/m4.txt'
  writefile(['m1'], file_m)
  execute 'edit ' .. fnameescape(file_m)
  var bad_sets: list<list<string>> = [
    ['data: {"choices":[]}'],
    ['data: {"choices":[1]}'],
    ['data: {"choices":[{"delta":"x"}]}'],
    ['data: {"choices":"x"}'],
    ['data: {"choices":[{"delta":{"content":5}}]}'],
    ['data: {"choices":[{"delta":[1]}]}'],
    ['data: {"choices":[null]}'],
    ['data: [1,2]'],
    ['data: 7'],
  ]
  for bad in bad_sets
    var d: dict<any> = RunPrompt('?q', [Frame('A'), '', bad[0], '', Frame('B'), '', 'data: [DONE]', ''])
    Assert(d.popup == 'AB', bad[0] .. ': good frames around it arrive (popup "' .. d.popup .. '")')
    Assert(d.messages !~ '\<E\d\+:' && d.errmsg !~ '\<E\d\+:', bad[0] .. ': no error recorded (' .. substitute(d.messages, "\n", '|', 'g') .. ' / ' .. d.errmsg .. ')')
  endfor
  popup_clear()
  silent! bwipeout!
enddef
RunSection('4', Section4)

# ══════════════════════════════════════════════════════════════════════════
# vproj.vim: pane
# ══════════════════════════════════════════════════════════════════════════
runtime! plugin/vproj.vim

def PaneWid(): number
  var wins = win_findbuf(bufnr('VPROJ'))
  return empty(wins) ? 0 : wins[0]
enddef

def PaneLines(): list<string>
  var pbuf = bufnr('VPROJ')
  return pbuf <= 0 ? [] : getbufline(pbuf, 1, '$')
enddef

def PaneCursorText(): string
  var wid = PaneWid()
  var lnum = wid == 0 ? -1 : line('.', wid)
  return lnum < 1 ? '' : get(PaneLines(), lnum - 1, '')
enddef

def SelectName(name: string): bool
  vproj#SelectFirst()
  for i in range(80)
    if PaneCursorText() =~ '\V' .. escape(name, '\')
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

def Reset(dir: string): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  execute 'cd ' .. fnameescape(dir)
enddef

def Fresh(dir: string, mode: string): void
  Reset(dir)
  vproj#PaneOpen()
  vproj#SwitchMode(mode)
enddef

def Elapsed(start: list<any>): float
  return reltimefloat(reltime(start))
enddef

# ── 5: TruncateToWidth ──
def Section5(): void
  if !is_utf8
    echom 'SKIP: section 5 needs utf-8 (combining marks and wide characters)'
    return
  endif
  var d: string = root .. '/trunc'
  mkdir(d, 'p')
  var comb: string = nr2char(0x301)
  var wide: string = nr2char(0x4e2d)

  # Used to: 30 'x' + 50,000 U+0301 + 'y' took 12.8 s (a prefix measured per
  # character, so quadratic). qfix text goes through TruncateToWidth.
  # The run of marks must come BEFORE the cut, or the scan stops early.
  var long_text: string = repeat('x', 10) .. repeat(comb, 50000) .. repeat('y', 60)
  Reset(d)
  setqflist([{filename: d .. '/f.txt', lnum: 1, col: 1, text: long_text, valid: true}])
  vproj#PaneOpen()
  var start: list<any> = reltime()
  vproj#SwitchMode('qfix')
  var secs: float = Elapsed(start)
  Assert(secs < 1.0, 'qfix row with 50,000 combining marks renders in < 1 s (took ' .. printf('%.2f', secs) .. ' s)')
  var w: number = vproj#GetPaneWidth()
  for l in PaneLines()
    Assert(strdisplaywidth(l) == w, 'row is exactly ' .. w .. ' cells (' .. strdisplaywidth(l) .. ')')
  endfor

  # The old properties, on a mixed sample: the row never exceeds the pane, the
  # visible text is a prefix of the entry, no wide character is split.
  var entry_prefix: string = 'f.txt:1  '
  var samples: list<string> = [
    repeat('e' .. comb, 40),
    repeat(wide, 40),
    repeat('a' .. wide, 20),
    repeat('ab', 5) .. repeat(wide .. comb, 30),
    repeat(comb, 200),
    'plain ' .. repeat('z', 100),
    repeat('x', 10) .. repeat(comb, 300) .. repeat('y', 60),
  ]
  for wd in [20, 33, 40]
    for text in samples
      Reset(d)
      setqflist([{filename: d .. '/f.txt', lnum: 1, col: 1, text: text, valid: true}])
      vproj#PaneOpen()
      vproj#SetPaneWidth(wd)
      vproj#SwitchMode('qfix')
      var pw: number = vproj#GetPaneWidth()
      var ri: number = match(PaneLines(), 'f\.txt:1')
      var row: string = ri >= 0 ? PaneLines()[ri] : ''
      var shown: string = substitute(strcharpart(row, 2), ' *$', '', '')
      var full: string = entry_prefix .. text
      Assert(strdisplaywidth(row) == pw && strwidth(shown) <= pw - 2,
        'w=' .. wd .. ' "' .. strtrans(strcharpart(text, 0, 8)) .. '..": width within the pane (' .. strwidth(shown) .. ' <= ' .. (pw - 2) .. ')')
      Assert(stridx(full, shown) == 0, 'w=' .. wd .. ': the shown text is a prefix of the entry')
      # Maximal: one more character would not fit.
      var next: string = strcharpart(full, strchars(shown), 1)
      var more: string = shown .. next
      Assert(empty(next) || strwidth(more) > pw - 2, 'w=' .. wd .. ': no more characters would have fit')
    endfor
  endfor
  Reset(d)
enddef
RunSection('5', Section5)

# ── 6: EntryRegex / EntryMatches ──
def Section6(): void
  # Used to: with 'regexpengine'=1 the entry "*a*a*a*a*b" against a 100-char
  # name took 0.74 s and 400 chars never finished. Now the NFA engine is forced.
  var d: string = root .. '/entries'
  mkdir(d, 'p')
  var long_name: string = repeat('a', 120)
  writefile(['x'], d .. '/' .. long_name)
  writefile(['x'], d .. '/ok.txt')
  writefile(['Project Name: p', 'Project Root: ', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:', '*a*a*a*a*b'], d .. '/p.vproj')
  set regexpengine=1
  var start: list<any> = reltime()
  Fresh(d, 'code')
  var secs: float = Elapsed(start)
  set regexpengine=0
  Assert(secs < 1.0, "regexpengine=1: '*a*a*a*a*b' against a 120-char name renders in < 1 s (took " .. printf('%.2f', secs) .. ' s)')
  Assert(match(PaneLines(), 'ok\.txt') >= 0, 'the listing still renders')

  # (c) identical across engines on a mixed sample. Excluded entries make the
  # row set depend on every match.
  var d2: string = root .. '/entries2'
  mkdir(d2 .. '/sub', 'p')
  var names: list<string> = ['a.swp', 'sub/x.swp', '[id].tsx', 'x.y', 'xay', 'ab', 'aab', 'a b', 'q.go', 'sub/q.go', 'a.b.c', '$(x).txt', 'ba']
  for n in names
    writefile(['x'], d2 .. '/' .. n)
  endfor
  var entries: list<string> = ['*.swp', '?.y', '[id].tsx', 'a*b', 'x?y', '$(x).txt', 'sub/q*', '?a', 'a.b.?']
  writefile(['Project Name: p', 'Project Root: ', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:'] + entries, d2 .. '/p.vproj')
  var by_engine: dict<list<string>> = {}
  for re in [0, 1, 2]
    execute 'set regexpengine=' .. re
    Fresh(d2, 'code')
    by_engine[string(re)] = PaneLines()
    vproj#ToggleTreeView()
    by_engine[string(re)] += PaneLines()
  endfor
  set regexpengine=0
  Assert(by_engine['0'] == by_engine['1'] && by_engine['1'] == by_engine['2'],
    "pane rows are identical for 'regexpengine' 0/1/2")
  var rows: string = join(by_engine['0'], "\n")
  Assert(rows =~ 'q\.go' && rows =~ 'xay' && rows =~ 'a\.b\.c', 'sample is not vacuous: unmatched files are listed')
  Reset(d2)
enddef
RunSection('6', Section6)

# ── 7: read-only .vproj ──
def Section7(): void
  var d: string = root .. '/ro'
  mkdir(d, 'p')
  writefile(['a'], d .. '/a.txt')
  writefile(['b'], d .. '/b.txt')
  var orig: list<string> = ['Project Name: p', 'Project Root: ', 'Included Directories:', 'Included Files:', 'a.txt', 'Excluded Directories:', 'Excluded Files:']
  var vp: string = d .. '/p.vproj'
  writefile(orig, vp)
  setfperm(vp, 'r--r--r--')
  if filewritable(vp) == 1
    echom 'SKIP: section 7: filewritable() says a 0444 file is writable here (running as root?)'
    setfperm(vp, 'rw-r--r--')
    return
  endif
  Fresh(d, 'code')
  Assert(SelectName('b.txt'), 'b.txt is listed')
  messages clear
  vproj#IncludeItem()
  var m: string = execute('messages')
  Assert(readfile(vp) == orig, 'a read-only .vproj is not rewritten (got ' .. string(readfile(vp)) .. ')')
  Assert(getfperm(vp) == 'r--r--r--', 'its mode is untouched (' .. getfperm(vp) .. ')')
  Assert(m =~ 'is read-only -- not changed' && m =~ 'p\.vproj', 'the error names the file (' .. substitute(m, "\n", '|', 'g') .. ')')
  Assert(match(PaneLines(), '+ b\.txt') < 0, 'the toggle is reverted: b.txt is not shown as included')
  Assert(empty(filter(readdir(d), (_, f) => f =~ 'vproj-tmp')), 'no temp file is left behind')
  # Writable again: the same toggle now works.
  setfperm(vp, 'rw-r--r--')
  Assert(SelectName('b.txt'), 'b.txt is listed again')
  vproj#IncludeItem()
  Assert(index(readfile(vp), 'b.txt') >= 0, 'once writable the toggle is written')
  Reset(d)
enddef
RunSection('7', Section7)

# ── 8: unloaded buffers ──
def Section8(): void
  var d: string = root .. '/bufs'
  mkdir(d, 'p')
  writefile(['1', '2', '3'], d .. '/three.txt')
  writefile([], d .. '/empty.txt')
  writefile(['1', '2'], d .. '/loaded2.txt')
  Reset(d)
  execute 'silent edit ' .. fnameescape(d .. '/loaded2.txt')
  execute 'silent badd ' .. fnameescape(d .. '/three.txt')
  execute 'silent badd ' .. fnameescape(d .. '/empty.txt')
  Assert(!bufloaded(d .. '/three.txt'), 'precondition: three.txt is not loaded')
  vproj#PaneOpen()
  vproj#SwitchMode('buf')
  if !vproj#IsInfoColumnVisible()
    vproj#ToggleInfoColumn()
  endif
  var w: number = vproj#GetPaneWidth()
  var lines: list<string> = PaneLines()
  var i3: number = match(lines, 'three\.txt')
  var ie: number = match(lines, 'empty\.txt')
  var il: number = match(lines, 'loaded2\.txt')
  Assert(i3 >= 0 && lines[i3] =~ ' --$', 'unloaded 3-line file shows a placeholder, not 1 (' .. get(lines, i3, '<none>') .. ')')
  Assert(ie >= 0 && lines[ie] =~ ' --$', 'unloaded empty file shows a placeholder (' .. get(lines, ie, '<none>') .. ')')
  Assert(il >= 0 && lines[il] =~ ' 2$', 'a loaded buffer keeps its real count (' .. get(lines, il, '<none>') .. ')')
  for l in lines
    Assert(strdisplaywidth(l) == w, 'row is exactly ' .. w .. ' cells: ' .. l)
  endfor
  Assert(i3 >= 0 && ie >= 0 && strlen(lines[i3]) == strlen(lines[il]), 'placeholder cell is as wide as the count cell')
  # Once loaded, the real count appears.
  execute 'silent buffer ' .. bufnr(d .. '/three.txt')
  vproj#PaneClose()
  vproj#PaneOpen()
  vproj#SwitchMode('buf')
  lines = PaneLines()
  i3 = match(lines, 'three\.txt')
  Assert(i3 >= 0 && lines[i3] =~ ' 3$', 'after loading, the count is 3 (' .. get(lines, i3, '<none>') .. ')')
  Reset(d)
enddef
RunSection('8', Section8)

# ── 9: Vim 8.2.3995 compatibility (read from the source) ──
def Section9(): void
  var src: list<string> = []
  for f in glob(repo .. '/src/**/*.vim', 0, 1)
    src += map(readfile(f), (_, l) => fnamemodify(f, ':t') .. ': ' .. l)
  endfor
  # isabsolutepath() (8.2.4838) only by name, behind exists().
  var direct: list<string> = filter(copy(src), (_, l) => l =~ 'isabsolutepath\s*(' && l !~ "call('isabsolutepath'" && l !~ "exists('\\*isabsolutepath')" && l !~ '^\S\+:\s*#')
  Assert(empty(direct), 'no direct isabsolutepath() call in src (' .. string(direct) .. ')')
  var underscore: list<string> = filter(copy(src), (_, l) => l =~ '^\S\+:\s*for _ in\>')
  Assert(empty(underscore), 'no "for _ in" in src (' .. string(underscore) .. ')')
  # Behaviour of the helper through its callers: an absolute and a relative
  # .vproj root.
  var d: string = root .. '/abs'
  mkdir(d .. '/sub', 'p')
  writefile(['Project Name: p', 'Project Root: ' .. d .. '/sub', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:'], d .. '/p.vproj')
  Fresh(d, 'code')
  writefile(['Project Name: p', 'Project Root: sub', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:'], d .. '/p.vproj')
  writefile(['x'], d .. '/sub/inroot.txt')
  Fresh(d, 'code')
  Assert(match(PaneLines(), 'inroot\.txt') >= 0, 'a relative root is resolved against the .vproj directory')
  Reset(d)
enddef
RunSection('9', Section9)

# ── Report ──
echom '---'
echom 'misc2 audit tests: ' .. (failures == 0 ? 'ALL PASSED' : failures .. ' FAILURES')
delete(root, 'rf')
if failures > 0
  cquit!
endif
qa!

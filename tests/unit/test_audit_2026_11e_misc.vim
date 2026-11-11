vim9script

# Regression tests for the fifth 2026-11 audit, "misc" group. Each block pins
# one reproduced defect; the comment names what used to happen.
#   1. ai.vim JSON/SSE: json_decode E488 escaped DecodeJson; one bad SSE frame
#      lost its neighbours; deep JSON threw E132; an unterminated last frame
#      was never applied.
#   2. ai.vim DetectMode/StripPrefix: leading space, 'iskeyword', empty prompt.
#   3. vproj.vim rows: combining marks, control characters in names, FormatSize.
#   4. plugin/vproj.vim: default <Tab>/<S-Tab> must not clobber a user mapping.
#   5. install.sh: no partial install, never links inside the repo, says so
#      when it re-points a link. Runs ONLY on copies under tempname().
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/unit/test_audit_2026_11e_misc.vim -c 'cquit!' </dev/null
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
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit5e'
mkdir(root, 'p')

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
# 1 + 2: AI module, through a fake curl (as tests/unit/test_ai.vim does)
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

# Serve {sse} (one list item per line, as writefile() writes them) to a
# question-mode stream and return the popup text it produced. Waits for the
# stream to end: either the popup, or the "empty response" message.
def RunStream(sse: list<string>): string
  ResetFake()
  writefile(sse, fake_dir .. '/reply.sse.tmp')
  rename(fake_dir .. '/reply.sse.tmp', fake_dir .. '/reply.sse')
  popup_clear()
  messages clear
  vproj#ai#AiPrompt('?q')
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < 30000
    var m: string = execute('messages')
    if stridx(m, 'response in popup') >= 0 || stridx(m, 'empty response') >= 0 || stridx(m, 'API call failed') >= 0
      break
    endif
    sleep 20m
  endwhile
  return PopupText()
enddef

def Section1(): void
  # ── 1a. ExtractJsonField: trailing characters (E488) must not escape ──
  var thrown: string = ''
  var r: string = 'unset'
  for bad in ['{"a":1}x', '1"a"', '{"a":1} {"b":2}', '[1,2] x']
    thrown = ''
    r = 'unset'
    try
      r = vproj#ai#ExtractJsonField(bad, 'a')
    catch
      thrown = v:exception
    endtry
    Assert(thrown == '' && r == '', 'ExtractJsonField(' .. bad .. ') is "" without throwing (got "' .. r .. '" / ' .. thrown .. ')')
  endfor
  Assert(vproj#ai#ExtractJsonField('{"a":1}', 'a') == '1', 'control: well-formed JSON still decodes')

  # ── 1b. Deep nesting: FindField recursion must not hit E132 ──
  var depth: number = 150
  var deep: string = repeat('{"x":', depth) .. '{"k":"found"}' .. repeat('}', depth)
  thrown = ''
  r = 'unset'
  try
    r = vproj#ai#ExtractJsonField(deep, 'k')
  catch
    thrown = v:exception
  endtry
  Assert(thrown == '' && r == '', 'ExtractJsonField on 150-deep JSON returns "" without throwing (got "' .. r .. '" / ' .. thrown .. ')')
  var shallow: string = repeat('[', 30) .. '{"k":"found"}' .. repeat(']', 30)
  Assert(vproj#ai#ExtractJsonField(shallow, 'k') == 'found', 'control: a field 30 levels deep is still found')

  # ── 1c. One bad SSE frame never drops the others in the same chunk ──
  # Used to: DecodeJson let E488 escape the job callback, the frame was lost
  # and the later frames of that chunk stayed in stream_accumulated.
  var got: string = RunStream([Frame('AAA') .. ' x', '', Frame('BBB'), '', 'data: [DONE]', ''])
  Assert(got == 'BBB', 'bad first frame (trailing junk): later frame kept (got "' .. got .. '")')
  got = RunStream([Frame('G1'), '', 'data: {"bad":1} x', '', 'data: 1"a"', '', Frame('G2'), '', 'data: [DONE]', ''])
  Assert(got == 'G1G2', 'bad frames in the middle: good frames kept (got "' .. got .. '")')

  # ── 1d. An unterminated last frame is applied when the stream ends ──
  # Used to: no blank line after the last frame, so it was never processed.
  got = RunStream([Frame('G1'), '', 'data:' .. substitute(Frame('LAST'), '^data: ', '', '')])
  Assert(got == 'G1LAST', 'unterminated final frame is applied (got "' .. got .. '")')
  got = RunStream([Frame('ONLY')])
  Assert(got == 'ONLY', 'a stream that is one unterminated frame is applied (got "' .. got .. '")')
  popup_clear()
enddef
RunSection('1', Section1)

# ── 2. Mode detection ──
# What was sent: the last request body's user message. Waits for the fake curl
# to have received it (the body is published atomically).
def Sent(prompt: string): dict<any>
  ResetFake()
  writefile([Frame('r'), '', 'data: [DONE]', ''], fake_dir .. '/reply.sse')
  messages clear
  vproj#ai#AiPrompt(prompt)
  var m: string = execute('messages')
  var mode: string = 'none'
  if stridx(m, 'vproj-ai: streaming (question) for') >= 0
    mode = 'question'
  elseif stridx(m, 'vproj-ai: streaming for') >= 0
    mode = 'code'
  endif
  var content: string = ''
  if mode != 'none'
    var start: list<any> = reltime()
    var files: list<string> = []
    while reltimefloat(reltime(start)) * 1000 < 30000
      files = filter(glob(fake_dir .. '/data.*', 0, 1), (_, f) => f !~ '\.tmp$' && readfile(f)->join('') =~ '"messages"')
      if !empty(files)
        break
      endif
      sleep 20m
    endwhile
    if !empty(files)
      var body: any = json_decode(join(readfile(files[0]), ''))
      content = body.messages[-1].content
    endif
  endif
  vproj#ai#StreamCancelCmd()
  return {mode: mode, content: content, messages: m}
enddef

def Section2(): void
  var file_m: string = root .. '/m.txt'
  writefile(['m1', 'm2'], file_m)
  execute 'edit ' .. fnameescape(file_m)
  var e_acute: string = nr2char(233)

  # (a) leading whitespace must not change the verdict, and the prefix is stripped.
  # Used to: DetectMode tested prompt[0] before trimming ('?-' question, ' ?-' code)
  # and StripPrefix(' ?x') did not strip, sending the '?' to the API.
  var s: dict<any> = Sent('?x')
  Assert(s.mode == 'question' && s.content == 'x', 'control: "?x" is a question sending "x" (' .. s.mode .. '/' .. s.content .. ')')
  s = Sent(' ?x')
  Assert(s.mode == 'question' && s.content == 'x', '" ?x" is a question and the ? is stripped (' .. s.mode .. '/' .. s.content .. ')')
  s = Sent("\t  ?-")
  Assert(s.mode == 'question' && s.content == '-', 'blank-led "?-" is a question sending "-" (' .. s.mode .. '/' .. s.content .. ')')
  s = Sent(' !what is this')
  Assert(s.mode == 'code' && s.content == 'what is this', '" !what is this" is code with the ! stripped (' .. s.mode .. '/' .. s.content .. ')')
  s = Sent('  how do I do this')
  Assert(s.mode == 'question' && s.content == '  how do I do this', 'no prefix: text sent unchanged (' .. s.mode .. '/' .. s.content .. ')')

  # (b) word boundaries must not depend on 'iskeyword'.
  # Used to: \> followed the buffer's 'iskeyword', so with ':' or '-' keyword
  # 'explain: this' and 'how-to parse' stopped being questions.
  var cases: list<list<string>> = [
    ['explain: this loop', 'question'],
    ['how-to parse a list', 'question'],
    ['fix-up this loop?', 'code'],
    ['add-on for x', 'code'],
    ['however the loop works, add a break', 'code'],
    ['address the nil case', 'code'],
    ['why' .. e_acute .. ' x', 'code'],
    ['whatever', 'code'],
  ]
  for kw in ['', '-,:']
    execute 'setlocal iskeyword&vim'
    if !empty(kw)
      execute 'setlocal iskeyword+=' .. kw
    endif
    for c in cases
      var got: dict<any> = Sent(c[0])
      Assert(got.mode == c[1], 'iskeyword="' .. &iskeyword .. '": "' .. c[0] .. '" is ' .. c[1] .. ' (got ' .. got.mode .. ')')
    endfor
  endfor
  setlocal iskeyword&vim

  # (c) a prompt that strips to nothing says so.
  # Used to: returned silently.
  for p in ['!', '?', '  !  ', ' ? ', '   ', '']
    var got: dict<any> = Sent(p)
    Assert(got.mode == 'none' && stridx(got.messages, 'vproj-ai: empty prompt') >= 0, 'prompt "' .. p .. '" sends nothing and says "vproj-ai: empty prompt" (' .. got.mode .. ': ' .. substitute(got.messages, "\n", '|', 'g') .. ')')
  endfor
  popup_clear()
  silent! bwipeout!
enddef
RunSection('2', Section2)

# ══════════════════════════════════════════════════════════════════════════
# 3: pane rows
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
  return wid == 0 ? '' : get(PaneLines(), line('.', wid) - 1, '')
enddef

def SelectName(name: string): bool
  vproj#SelectFirst()
  for _ in range(80)
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

def OpenTemp(dir: string, mode: string): void
  Reset(dir)
  vproj#PaneToggle()
  vproj#SwitchMode(mode)
enddef

# Every row must occupy exactly the pane width as DISPLAYED (strdisplaywidth
# expands a Tab, strwidth does not) and hold no control character.
def AssertRows(label: string): void
  var w: number = vproj#GetPaneWidth()
  var bad: list<string> = []
  var ctl: list<string> = []
  for l in PaneLines()
    if strdisplaywidth(l) != w
      bad->add(strdisplaywidth(l) .. ':' .. strtrans(l))
    endif
    if l =~ '[\x00-\x1f\x7f]'
      ctl->add(strtrans(l))
    endif
  endfor
  Assert(empty(bad), label .. ': every row is exactly ' .. w .. ' cells (bad: ' .. string(bad) .. ')')
  Assert(empty(ctl), label .. ': no control character reaches the pane (' .. string(ctl) .. ')')
enddef

def Section3(): void
  var tab_name: string = "tabq\tname_" .. repeat('t', 30) .. '.txt'
  var ctl_name: string = "ctlq\x01name_" .. repeat('c', 30) .. '.txt'
  var short_tab: string = "sh\tort.txt"
  var names: list<string> = [tab_name, ctl_name, short_tab, 'plain.txt']
  var comb: string = ''
  var is_utf8: bool = &encoding == 'utf-8'
  if is_utf8
    comb = repeat('e' .. nr2char(0x301), 60)
    names->add('combq_' .. comb .. '.txt')
  else
    echom 'SKIP: combining-character file name not created (&encoding is ' .. &encoding .. ', not utf-8)'
  endif
  var d: string = root .. '/rows'
  mkdir(d, 'p')
  for n in names
    writefile(['x'], d .. '/' .. n)
  endfor
  # A sparse 10 TiB file for FormatSize (tmpfs/ext4 allow it; it uses no space).
  var big: string = d .. '/zbig.bin'
  system('truncate -s 10995116277759 ' .. shellescape(big))
  var have_big: bool = getfsize(big) == 10995116277759

  for w in [20, 27, 33, 40, 59]
    OpenTemp(d, 'file')
    vproj#SetPaneWidth(w)
    for info in [true, false]
      if vproj#IsInfoColumnVisible() != info
        vproj#ToggleInfoColumn()
      endif
      AssertRows('file w=' .. w .. ' info=' .. info)
      if is_utf8
        var iw: number = info ? 5 : 0
        var nw: number = w - iw - 2
        var li: number = match(PaneLines(), 'combq_')
        if li >= 0
          var letters: number = strchars(substitute(strpart(PaneLines()[li], matchend(PaneLines()[li], 'combq_')), '[ 0-9]*$', '', ''), true)
          # nw cells hold 'combq_' (6) and then letters: every combining mark costs 0.
          Assert(letters == nw - 6, 'file w=' .. w .. ' info=' .. info .. ': combining name keeps ' .. (nw - 6) .. ' letters (got ' .. letters .. ')')
        else
          echom 'SKIP: file w=' .. w .. ' info=' .. info .. ': combining name letter count, the combq_ row is not listed'
        endif
      else
        echom 'SKIP: file w=' .. w .. ' info=' .. info .. ': combining name letter count needs &encoding=utf-8 (is ' .. &encoding .. ')'
      endif
    endfor
    vproj#ToggleTreeView()
    AssertRows('tree w=' .. w)
    vproj#ToggleTreeView()
  endfor

  # FormatSize: the size column is 5 wide. 10 TiB - 1 byte used to give '10239G'.
  if have_big
    OpenTemp(d, 'file')
    if !vproj#IsInfoColumnVisible()
      vproj#ToggleInfoColumn()
    endif
    var bi: number = match(PaneLines(), 'zbig\.bin')
    var brow: string = bi >= 0 ? PaneLines()[bi] : ''
    Assert(bi >= 0 && strdisplaywidth(brow) == vproj#GetPaneWidth(), 'big file: row is exactly the pane width (' .. brow .. ')')
    Assert(bi >= 0 && brow =~ '\s\S\{1,5}$' && brow !~ '\S\{6}$', 'big file: size field is at most 5 chars (' .. brow .. ')')
    Assert(bi >= 0 && brow =~ '\s\+\d\+[KMGT]$' && brow !~ '10239G', 'big file: size reads as a number with a unit (' .. brow .. ')')
  else
    echom 'SKIP: filesystem cannot hold a sparse 10 TiB file'
  endif

  # Opening a file whose name has control characters opens the REAL name.
  OpenTemp(d, 'file')
  Assert(SelectName('tabq?name_'), 'tab name is listed with ? for the tab')
  vproj#SelectCurrent()
  Assert(fnamemodify(bufname('%'), ':t') ==# tab_name, 'opening the tab-named file opens the real name (got ' .. strtrans(fnamemodify(bufname('%'), ':t')) .. ')')
  OpenTemp(d, 'file')
  Assert(SelectName('ctlq?name_'), '^A name is listed with ? for the control char')
  vproj#SelectCurrent()
  Assert(fnamemodify(bufname('%'), ':t') ==# ctl_name, 'opening the ^A-named file opens the real name (got ' .. strtrans(fnamemodify(bufname('%'), ':t')) .. ')')
  Assert(filereadable(d .. '/' .. tab_name) && filereadable(d .. '/' .. ctl_name), 'the real files on disk keep their names')

  # Buffer, quickfix and code rows.
  for w in [20, 33, 59]
    Reset(d)
    for n in [tab_name, ctl_name, short_tab]
      execute 'silent! badd ' .. fnameescape(d .. '/' .. n)
    endfor
    vproj#PaneToggle()
    vproj#SetPaneWidth(w)
    vproj#SwitchMode('buf')
    Assert(match(PaneLines(), 'tabq?name_') >= 0, 'buf w=' .. w .. ': tab-named buffer is listed')
    AssertRows('buf w=' .. w)

    Reset(d)
    setqflist([{filename: d .. '/' .. tab_name, lnum: 1, col: 1, text: "tab\there \x01 text " .. repeat('q', 60), valid: true}])
    vproj#PaneToggle()
    vproj#SetPaneWidth(w)
    vproj#SwitchMode('qfix')
    Assert(match(PaneLines(), 'tabq?name_') >= 0 || w < 25, 'qfix w=' .. w .. ': entry is listed')
    AssertRows('qfix w=' .. w)

    OpenTemp(d, 'code')
    vproj#SetPaneWidth(w)
    Assert(match(PaneLines(), 'tabq?name_') >= 0 || w < 33, 'code w=' .. w .. ': tab-named file is listed')
    AssertRows('code w=' .. w)
  endfor
  # The quickfix entry still opens the real buffer.
  Reset(d)
  setqflist([{filename: d .. '/' .. tab_name, lnum: 1, col: 1, text: 'x', valid: true}])
  vproj#PaneToggle()
  vproj#SwitchMode('qfix')
  vproj#SelectFirst()
  vproj#SelectCurrent()
  Assert(fnamemodify(bufname('%'), ':t') ==# tab_name, 'qfix: Enter opens the real name (got ' .. strtrans(fnamemodify(bufname('%'), ':t')) .. ')')
  Reset(d)
enddef
RunSection('3', Section3)

# ══════════════════════════════════════════════════════════════════════════
# 4: default <Tab>/<S-Tab> mappings never clobber a user mapping
# ══════════════════════════════════════════════════════════════════════════
def AutoloadSourced(): bool
  return !empty(filter(split(execute('scriptnames'), "\n"), (_, v) => v =~ 'autoload/vproj\.vim'))
enddef

def ReloadPlugin(): void
  silent! nunmap <Tab>
  silent! nunmap <S-Tab>
  silent! unlet g:loaded_vproj
  execute 'source ' .. fnameescape(repo .. '/src/plugin/vproj.vim')
enddef

def Section4(): void
  # (a) the user already maps <Tab>: it survives, the <Plug> stays available.
  silent! nunmap <Tab>
  silent! nunmap <S-Tab>
  nnoremap <Tab> :echo 'USER-TAB'<CR>
  ReloadPlugin_KeepUser()
  Assert(maparg('<Tab>', 'n') =~ 'USER-TAB', 'user <Tab> mapping survived the plugin load (got ' .. maparg('<Tab>', 'n') .. ')')
  Assert(maparg('<S-Tab>', 'n') =~ 'VprojTogglePermanent', 'unmapped <S-Tab> still gets the default (got ' .. maparg('<S-Tab>', 'n') .. ')')
  Assert(!empty(maparg('<Plug>VprojToggle', 'n')), '<Plug>VprojToggle is still defined')

  # (b) the user already maps <S-Tab>.
  silent! nunmap <Tab>
  silent! nunmap <S-Tab>
  nnoremap <S-Tab> :echo 'USER-STAB'<CR>
  ReloadPlugin_KeepUser()
  Assert(maparg('<S-Tab>', 'n') =~ 'USER-STAB', 'user <S-Tab> mapping survived (got ' .. maparg('<S-Tab>', 'n') .. ')')
  Assert(maparg('<Tab>', 'n') =~ 'VprojToggle', 'unmapped <Tab> still gets the default (got ' .. maparg('<Tab>', 'n') .. ')')
  Assert(!empty(maparg('<Plug>VprojTogglePermanent', 'n')), '<Plug>VprojTogglePermanent is still defined')

  # (c) nothing mapped: both defaults are installed.
  ReloadPlugin()
  Assert(maparg('<Tab>', 'n') =~ 'VprojToggle' && maparg('<S-Tab>', 'n') =~ 'VprojTogglePermanent', 'no user mapping: both defaults are installed')

  # (d) the documented opt-in works over a user mapping.
  silent! nunmap <Tab>
  nnoremap <Tab> :echo 'USER-TAB'<CR>
  ReloadPlugin_KeepUser()
  nmap <Tab> <Plug>VprojToggle
  Assert(maparg('<Tab>', 'n') =~ 'VprojToggle', 'explicit "nmap <Tab> <Plug>VprojToggle" opts in')
  silent! nunmap <Tab>
  silent! nunmap <S-Tab>
  ReloadPlugin()
enddef

# Like ReloadPlugin() but leaves whatever mapping the test just set.
def ReloadPlugin_KeepUser(): void
  silent! unlet g:loaded_vproj
  execute 'source ' .. fnameescape(repo .. '/src/plugin/vproj.vim')
enddef
RunSection('4', Section4)

# The lazy-load guarantee: a fresh Vim sourcing the plugin does not source autoload.
$LAZYOUT = root .. '/lazy.out'
system('vim -N -u NONE -i NONE --not-a-term -es -c ' .. shellescape('set rtp^=' .. fnameescape(repo .. '/src')) .. ' -c ' .. shellescape('nnoremap <Tab> :echo 1<CR>') .. ' -c ' .. shellescape('runtime! plugin/vproj.vim') .. ' -c ' .. shellescape("call writefile([string(len(filter(split(execute('scriptnames'), \"\\n\"), 'v:val =~ \"autoload/vproj\\\\.vim\"')))], $LAZYOUT)") .. ' -c qa! </dev/null')
Assert(filereadable($LAZYOUT) && readfile($LAZYOUT) == ['0'], 'plugin load with a user <Tab> mapping does not source autoload (' .. string(filereadable($LAZYOUT) ? readfile($LAZYOUT) : []) .. ')')

# ══════════════════════════════════════════════════════════════════════════
# 5: install.sh, on copies only. The real repo is never installed from.
# ══════════════════════════════════════════════════════════════════════════
def Copy(name: string): string
  var c: string = root .. '/' .. name
  mkdir(c, 'p')
  system('cp -R ' .. shellescape(repo .. '/install.sh') .. ' ' .. shellescape(repo .. '/src') .. ' ' .. shellescape(repo .. '/bin') .. ' ' .. shellescape(c) .. '/')
  # A copy of src/doc/tags from a previous helptags run is not wanted.
  delete(c .. '/src/doc/tags')
  return c
enddef

# Run install.sh from copy {c} with HOME in {home}, XDG_CONFIG_HOME unset.
def Install(c: string, home: string): dict<any>
  var out: string = system('cd ' .. shellescape(c) .. ' && env -u XDG_CONFIG_HOME HOME=' .. shellescape(home) .. ' bash install.sh 2>&1')
  return {out: out, rc: v:shell_error}
enddef

# Like Install(), with {env} (shell words, e.g. 'PATH=... XDG_CONFIG_HOME=...')
# added before `bash`, and XDG_CONFIG_HOME left alone unless {env} sets it.
def InstallEnv(c: string, home: string, env: string): dict<any>
  var out: string = system('cd ' .. shellescape(c) .. ' && env -u XDG_CONFIG_HOME HOME=' .. shellescape(home) .. ' ' .. env .. ' bash install.sh 2>&1')
  return {out: out, rc: v:shell_error}
enddef

# A directory holding a `readlink` that, like BSD/macOS before 12.3, rejects
# -m and -f (usage error, rc 1) and otherwise runs the real one, and an `ln`
# that rejects -n. Put it first on PATH.
def StubBin(name: string, real_readlink: string, real_ln: string): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  writefile(['#!/bin/sh', 'for a in "$@"; do case "$a" in -m|-f|-e) echo "usage: readlink [-n] [file ...]" >&2; exit 1;; esac; done', 'exec ' .. shellescape(real_readlink) .. ' "$@"'], d .. '/readlink')
  writefile(['#!/bin/sh', 'for a in "$@"; do case "$a" in -*n*) echo "ln: illegal option -- n" >&2; exit 1;; esac; done', 'exec ' .. shellescape(real_ln) .. ' "$@"'], d .. '/ln')
  setfperm(d .. '/readlink', 'rwxr-xr-x')
  setfperm(d .. '/ln', 'rwxr-xr-x')
  return d
enddef

def Links(path: string): list<string>
  return split(system('find ' .. shellescape(path) .. ' -type l 2>/dev/null | sort'), "\n")
enddef

def Section5(): void
  if !executable('bash') || !executable('find') || !executable('readlink')
    echom 'SKIP: install.sh section needs bash, find, readlink'
    return
  endif

  # (a) a refusal on the 3rd directory must leave NOTHING behind.
  # Used to: plugin and autoload were already linked when doc was refused.
  var c1: string = Copy('inst_partial')
  var home1: string = root .. '/home_partial'
  var t1: string = home1 .. '/.vim/pack/bundle/start/vproj'
  mkdir(t1 .. '/doc', 'p')
  var r: dict<any> = Install(c1, home1)
  Assert(r.rc == 1, 'partial: install refuses (rc ' .. r.rc .. ': ' .. r.out .. ')')
  Assert(r.out =~ 'doc' && r.out =~ 'not a symlink', 'partial: message names the blocking directory')
  Assert(Links(t1) == [], 'partial: no link was created before the refusal (' .. string(Links(t1)) .. ')')
  Assert(!isdirectory(t1 .. '/plugin') && getftype(t1 .. '/plugin') == '', 'partial: no plugin link either')

  # (b) TARGET_DIR is a symlink to the repo itself, or into it.
  # Used to: plugin -> src/plugin etc. were created INSIDE the repo.
  for sub in ['', 'src']
    var c2: string = Copy('inst_selflink' .. (empty(sub) ? '_root' : '_' .. sub))
    var home2: string = root .. '/home_selflink' .. (empty(sub) ? '_root' : '_' .. sub)
    mkdir(home2 .. '/.vim/pack/bundle/start', 'p')
    system('ln -s ' .. shellescape(empty(sub) ? c2 : c2 .. '/' .. sub) .. ' ' .. shellescape(home2 .. '/.vim/pack/bundle/start/vproj'))
    var before: list<string> = Links(c2)
    r = Install(c2, home2)
    Assert(r.rc == 1, 'target symlinked to repo' .. (empty(sub) ? '' : '/' .. sub) .. ': install refuses (rc ' .. r.rc .. ': ' .. r.out .. ')')
    Assert(r.out =~ '\cinside\|repo', 'target symlinked to repo: message explains (' .. r.out .. ')')
    Assert(Links(c2) == before && Links(c2) == [], 'target symlinked to repo: no stray link in the copy (' .. string(Links(c2)) .. ')')
  endfor

  # (c) a plain install, then an idempotent second run.
  var c3: string = Copy('inst_ok')
  var home3: string = root .. '/home_ok'
  var t3: string = home3 .. '/.vim/pack/bundle/start/vproj'
  r = Install(c3, home3)
  Assert(r.rc == 0, 'install: first run succeeds (rc ' .. r.rc .. ': ' .. r.out .. ')')
  var l1: list<string> = Links(t3)
  Assert(len(l1) == 4, 'install: four links (' .. string(l1) .. ')')
  Assert(resolve(t3 .. '/plugin') == resolve(c3 .. '/src/plugin') && resolve(t3 .. '/bin') == resolve(c3 .. '/bin'), 'install: links point into the copy')
  var r2: dict<any> = Install(c3, home3)
  Assert(r2.rc == 0 && Links(t3) == l1, 'install: second run succeeds and changes nothing (rc ' .. r2.rc .. ': ' .. r2.out .. ')')
  Assert(r2.out !~ 're-pointing', 'install: second run says nothing about re-pointing (' .. r2.out .. ')')
  Assert(Links(c3) == [], 'install: the copy holds no link of its own (' .. string(Links(c3)) .. ')')

  # (d) a link that points somewhere else is re-pointed, loudly.
  var c4: string = Copy('inst_repoint')
  var home4: string = root .. '/home_repoint'
  var t4: string = home4 .. '/.vim/pack/bundle/start/vproj'
  var elsewhere: string = root .. '/elsewhere'
  mkdir(elsewhere, 'p')
  mkdir(t4, 'p')
  system('ln -s ' .. shellescape(elsewhere) .. ' ' .. shellescape(t4 .. '/plugin'))
  r = Install(c4, home4)
  Assert(r.rc == 0, 're-point: install succeeds (rc ' .. r.rc .. ': ' .. r.out .. ')')
  Assert(stridx(r.out, 're-pointing plugin: ' .. elsewhere .. ' -> ') >= 0, 're-point: message names the link, old and new target (' .. r.out .. ')')
  Assert(resolve(t4 .. '/plugin') == resolve(c4 .. '/src/plugin'), 're-point: the link now points into the copy')
  Assert(r.out !~ 're-pointing autoload', 're-point: untouched links are not announced')

  # (e) a BSD-like userland: readlink rejects -m and -f, ln rejects -n. Used to:
  # install.sh called `readlink -m`, got a usage error, installed nothing.
  var stub: string = StubBin('stubbin', exepath('readlink'), exepath('ln'))
  var penv: string = 'PATH=' .. shellescape(stub .. ':' .. $PATH)
  Assert(system(penv .. ' readlink -m /tmp 2>&1; echo rc=$?') =~ 'rc=1', 'stub readlink: rejects -m (the stub is in force)')
  var c5: string = Copy('inst_bsd')
  var home5: string = root .. '/home_bsd'
  var t5: string = home5 .. '/.vim/pack/bundle/start/vproj'
  r = InstallEnv(c5, home5, penv)
  Assert(r.rc == 0, 'BSD-like readlink/ln: install succeeds (rc ' .. r.rc .. ': ' .. r.out .. ')')
  Assert(len(Links(t5)) == 4 && resolve(t5 .. '/plugin') == resolve(c5 .. '/src/plugin'), 'BSD-like readlink/ln: four links into the copy (' .. string(Links(t5)) .. ')')
  r2 = InstallEnv(c5, home5, penv)
  Assert(r2.rc == 0 && r2.out !~ 're-pointing' && len(Links(t5)) == 4, 'BSD-like readlink/ln: second run is idempotent (rc ' .. r2.rc .. ': ' .. r2.out .. ')')

  # (f) the same, from another cwd, HOME with spaces and non-ASCII, a
  # trailing-slash XDG_CONFIG_HOME, and a dangling symlink at a destination.
  var c6: string = Copy('inst_bsd_odd')
  var home6: string = root .. "/home odd \u00e9\u00e8"
  var xdg6: string = home6 .. '/xdg/'
  var t6: string = xdg6 .. 'vim/pack/bundle/start/vproj'
  mkdir(t6, 'p')
  system('ln -s ' .. shellescape(home6 .. '/no/such/place') .. ' ' .. shellescape(t6 .. '/plugin'))
  r = {out: system('cd / && env HOME=' .. shellescape(home6) .. ' XDG_CONFIG_HOME=' .. shellescape(xdg6) .. ' ' .. penv .. ' bash ' .. shellescape(c6 .. '/install.sh') .. ' 2>&1'), rc: v:shell_error}
  Assert(r.rc == 0, 'BSD-like, odd HOME, trailing-slash XDG, dangling link, other cwd: install succeeds (rc ' .. r.rc .. ': ' .. r.out .. ')')
  Assert(len(Links(t6)) == 4 && resolve(t6 .. '/plugin') == resolve(c6 .. '/src/plugin'), 'odd HOME: the dangling link was re-pointed, four links (' .. string(Links(t6)) .. ')')
  Assert(stridx(r.out, 're-pointing plugin: ' .. home6 .. '/no/such/place -> ') >= 0, 'odd HOME: re-point message names the dangling target (' .. r.out .. ')')
enddef
RunSection('5', Section5)

# ── Report ──
echom '---'
echom 'misc audit tests: ' .. (failures == 0 ? 'ALL PASSED' : failures .. ' FAILURES')
delete(root, 'rf')
if failures > 0
  cquit!
endif
qa!

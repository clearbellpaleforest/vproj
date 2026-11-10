vim9script

# Regression tests for the fourth 2026-11 audit, render/UX group.
#   1. Pane rows are truncated by display cells, not characters (CJK, emoji).
#   2. Enter on a file/buffer/quickfix entry closes the TEMPORARY pane, as the
#      nav-letter does and as doc/vproj.txt promises; a permanent pane stays.
#   3. Loading the plugin does not source autoload/vproj.vim; highlights are
#      defined when the pane opens and survive :colorscheme.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11d_render.vim -c 'cquit!'

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit4d'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def AutoloadSourced(): bool
  return !empty(filter(split(execute('scriptnames'), "\n"), (_, v) => v =~ 'autoload/vproj\.vim'))
enddef

# ── 3a. Plugin load must not source the autoload file ──
# Used to: plugin/vproj.vim called vproj#DefineHighlights() at load, so the
# whole autoload file was sourced at every startup.
runtime! plugin/vproj.vim
Assert(!AutoloadSourced(), 'plugin load: autoload/vproj.vim is not sourced')
Assert(exists(':VprojToggle') == 2 && maparg('<Tab>', 'n') =~ 'VprojToggle', 'plugin load: command and <Tab> map exist')
# A colorscheme change before the pane was ever used must not load it either.
doautocmd ColorScheme
Assert(!AutoloadSourced(), 'ColorScheme before first use: autoload still not sourced')

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
  if wid == 0
    return ''
  endif
  return get(PaneLines(), line('.', wid) - 1, '')
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

def OpenPerm(dir: string, mode: string): void
  Reset(dir)
  vproj#PaneTogglePermanent()
  vproj#SwitchMode(mode)
enddef

def Fixture(name: string, files: list<string>): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  for f in files
    mkdir(fnamemodify(d .. '/' .. f, ':h'), 'p')
    writefile([f], d .. '/' .. f)
  endfor
  return d
enddef

# ── 3b. Highlights exist once the pane has opened, and survive :colorscheme ──
var hdir: string = Fixture('hl', ['a.txt'])
Assert(!hlexists('VprojCursorLine'), 'before the pane opens: no Vproj highlight yet (lazy)')
OpenTemp(hdir, 'file')
Assert(hlexists('VprojCursorLine') && hlexists('VprojGitModified') && hlexists('VprojNavIndicator'), 'pane open: Vproj highlight groups exist')
# :colorscheme runs `highlight clear`, wiping the groups; the pane's handler
# must redefine them.
highlight clear
Assert(execute('highlight VprojNavIndicator') !~ 'guifg=#569CD6', 'precondition: highlight clear wiped VprojNavIndicator')
doautocmd ColorScheme
Assert(execute('highlight VprojCursorLine') =~ 'links to CursorLine', 'colorscheme change while open: VprojCursorLine link restored')
Assert(execute('highlight VprojNavIndicator') =~ 'guifg=#569CD6', 'colorscheme change while open: VprojNavIndicator restored')

# ── 1. Wide characters: every pane row fits the pane in display cells ──
var cjk: string = '日本語のファイル名がとても長いので切り詰められるはずです.txt'
var emoji: string = '😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀.txt'
var mixed: string = 'a日本語のファイル名のはなしですよ.md'
var long_ascii: string = repeat('x', 80) .. '.txt'
var wdir: string = Fixture('wide', [cjk, emoji, mixed, long_ascii, 'short.txt'])
var wide_sub: string = '日本語ディレクトリ名がとても長いのでこれも切り詰め'
mkdir(wdir .. '/' .. wide_sub, 'p')
writefile(['x'], wdir .. '/' .. wide_sub .. '/内側のファイル名がとても長いのでここも切り詰めるはず.txt')

def AssertFits(label: string): void
  var w: number = vproj#GetPaneWidth()
  var lines: list<string> = PaneLines()
  var bad: list<string> = []
  for l in lines
    if strwidth(l) > w
      bad->add(strwidth(l) .. ':' .. l)
    endif
  endfor
  Assert(empty(bad), label .. ': every row <= ' .. w .. ' cells (over: ' .. string(bad) .. ')')
  Assert(len(lines) >= 3, label .. ': pane has rows')
enddef

for info in [true, false]
  OpenTemp(wdir, 'file')
  if vproj#IsInfoColumnVisible() != info
    vproj#ToggleInfoColumn()
  endif
  AssertFits('file mode info=' .. info)
  # Plain ASCII rows keep their exact pre-change shape: nav letter, the name
  # cut at (pane - info - 2) chars, then the size column.
  var w: number = vproj#GetPaneWidth()
  var iw: number = info ? 5 : 0
  var nw: number = w - iw - 2
  var lines: list<string> = PaneLines()
  var li: number = match(lines, 'x\{10}')
  Assert(li >= 0 && strwidth(lines[li]) == w && lines[li][2 : 2 + nw - 1] == repeat('x', nw), 'file mode info=' .. info .. ': long ASCII row cut at ' .. nw .. ' chars as before')
  var si: number = match(lines, 'short\.txt')
  Assert(si >= 0 && strwidth(lines[si]) == w, 'file mode info=' .. info .. ': short ASCII row padded to pane width')
endfor

OpenTemp(wdir, 'file')
vproj#ToggleTreeView()
AssertFits('tree mode')
Assert(SelectName('日本語ディレクトリ'), 'tree mode: wide dir listed')
vproj#SelectCurrent()
Assert(match(PaneLines(), '内側') >= 0, 'tree mode: the wide dir expanded')
AssertFits('tree mode expanded')

Reset(wdir)
for nm in [cjk, emoji, mixed]
  execute 'silent! badd ' .. fnameescape(wdir .. '/' .. nm)
endfor
vproj#PaneToggle()
vproj#SwitchMode('buf')
Assert(match(PaneLines(), '日本語') >= 0, 'buf mode: wide buffers listed')
AssertFits('buf mode')

Reset(wdir)
setqflist([{filename: wdir .. '/' .. cjk, lnum: 1, col: 1, text: '日本語のテキストがとても長いです日本語のテキストがとても長いです', valid: true}])
vproj#PaneToggle()
vproj#SwitchMode('qfix')
Assert(match(PaneLines(), '日本語') >= 0, 'qfix mode: wide entry listed')
AssertFits('qfix mode')

# ── 2. Enter closes a temporary pane, leaves a permanent one ──
var edir: string = Fixture('enter', ['one.txt', 'two.txt', 'sub/inner.txt'])

OpenTemp(edir, 'file')
Assert(SelectName('one.txt'), 'enter/file: one.txt listed')
vproj#SelectCurrent()
Assert(!vproj#IsPaneVisible(), 'enter/file temp: pane closed after opening a file')
Assert(fnamemodify(bufname('%'), ':t') == 'one.txt', 'enter/file temp: one.txt is open in the editing window')

OpenPerm(edir, 'file')
Assert(SelectName('two.txt'), 'enter/file: two.txt listed')
vproj#SelectCurrent()
Assert(vproj#IsPaneVisible(), 'enter/file perm: pane stays open')
Assert(!empty(win_findbuf(bufnr('two.txt'))), 'enter/file perm: two.txt is shown')

OpenTemp(edir, 'file')
Assert(SelectName('sub/'), 'enter/dir: sub/ listed')
vproj#SelectCurrent()
Assert(vproj#IsPaneVisible(), 'enter/dir temp: pane stays open when entering a directory')
Assert(match(PaneLines(), 'inner\.txt') >= 0, 'enter/dir temp: now listing sub/')

OpenTemp(edir, 'file')
vproj#SelectFirst()
vproj#SelectPrev()
var before_mode: string = vproj#GetCurrentMode()
if PaneCursorText() =~ '\[F\]ile'
  vproj#SelectCurrent()
  Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() != before_mode, 'enter/menu temp: mode cycled, pane stays open')
else
  Assert(false, 'enter/menu: could not reach the mode-menu line (' .. PaneCursorText() .. ')')
endif

OpenTemp(edir, 'file')
execute 'badd ' .. fnameescape(edir .. '/two.txt')
vproj#SwitchMode('buf')
Assert(SelectName('two.txt'), 'enter/buf temp: two.txt listed')
vproj#SelectCurrent()
Assert(!vproj#IsPaneVisible(), 'enter/buf temp: pane closed after switching buffer')
Assert(fnamemodify(bufname('%'), ':t') == 'two.txt', 'enter/buf temp: buffer switched')

OpenPerm(edir, 'file')
execute 'badd ' .. fnameescape(edir .. '/two.txt')
vproj#SwitchMode('buf')
Assert(SelectName('two.txt'), 'enter/buf perm: two.txt listed')
vproj#SelectCurrent()
Assert(vproj#IsPaneVisible(), 'enter/buf perm: pane stays open')

var qf: string = edir .. '/two.txt'
OpenTemp(edir, 'file')
setqflist([{filename: qf, lnum: 1, col: 1, text: 'hit', valid: true}])
vproj#SwitchMode('file')
vproj#SwitchMode('qfix')
Assert(SelectName('two.txt'), 'enter/qfix temp: entry listed')
vproj#SelectCurrent()
Assert(!vproj#IsPaneVisible(), 'enter/qfix temp: pane closed after the jump')
Assert(fnamemodify(bufname('%'), ':t') == 'two.txt', 'enter/qfix temp: jumped to the file')

OpenPerm(edir, 'file')
setqflist([{filename: qf, lnum: 1, col: 1, text: 'hit', valid: true}])
vproj#SwitchMode('file')
vproj#SwitchMode('qfix')
Assert(SelectName('two.txt'), 'enter/qfix perm: entry listed')
vproj#SelectCurrent()
Assert(vproj#IsPaneVisible(), 'enter/qfix perm: pane stays open')

# A failed open (binary file) keeps a temporary pane.
var bdir: string = Fixture('binary', ['plain.txt'])
writefile(0z00010203, bdir .. '/blob.bin')
OpenTemp(bdir, 'file')
Assert(SelectName('blob.bin'), 'enter/binary: blob.bin listed')
silent! vproj#SelectCurrent()
Assert(vproj#IsPaneVisible(), 'enter/binary temp: failed open keeps the pane')

var cdir: string = Fixture('code', ['c1.txt'])
writefile(['Project Name: p', 'Project Root: ', 'Included Directories:', '', 'Included Files:', 'c1.txt', 'Excluded Directories:', 'Excluded Files:'], cdir .. '/p.vproj')
OpenTemp(cdir, 'code')
Assert(vproj#GetCurrentMode() == 'code', 'enter/code: code mode active')
Assert(SelectName('c1.txt'), 'enter/code: c1.txt listed')
vproj#SelectCurrent()
Assert(!vproj#IsPaneVisible(), 'enter/code temp: pane closed after opening a file')

if failures > 0
  echom 'FAILURES: ' .. failures
  cquit!
endif
echom 'ALL PASS'
qa!

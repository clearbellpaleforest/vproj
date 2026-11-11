vim9script

# Regression tests for the 2026-11 layout audit (HEAD 50d4584): terminal
# resize, width clamping, mode-menu truncation, preview / diff on narrow
# terminals, and the help window's focus. Each block names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11e_layout.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname().
# Statusline text is cut to the pane width, so assertions use the window
# geometry and the pane buffer rows, not the statusline.

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_layout'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneWid(): number
  var wins = win_findbuf(bufnr('VPROJ'))
  return empty(wins) ? 0 : wins[0]
enddef

def PaneLines(): list<string>
  var pbuf = bufnr('VPROJ')
  return pbuf <= 0 ? [] : getbufline(pbuf, 1, '$')
enddef

def Widths(): list<number>
  return range(1, winnr('$'))->mapnew((_, n) => winwidth(n))
enddef

def MinWidth(): number
  return min(Widths())
enddef

# Widest row in the pane buffer, in display cells.
def WidestRow(): number
  var w: number = 0
  for l in PaneLines()
    w = max([w, strwidth(l)])
  endfor
  return w
enddef

def Fixture(name: string, n: number): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  for i in range(n)
    writefile(['x'], d .. '/file_' .. printf('%03d', i) .. '.txt')
  endfor
  return d
enddef

def Fresh(dir: string): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  set columns=160 lines=40
  execute 'cd ' .. fnameescape(dir)
  vproj#PaneOpen()
  vproj#SwitchMode('file')
enddef

def Reset(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  set nowinfixwidth
  set columns=160 lines=40
enddef

var d1: string = Fixture('many', 60)

# ── 1. VimResized / WinResized ──
# Used to: nothing was registered, so after a shrink the pane kept stale rows
# until a key was pressed and, after growing back, stayed narrow with the old
# page size.
g:vproj_pane_width_default = 60
Fresh(d1)
Assert(winwidth(PaneWid()) == 60, 'resize: pane starts at 60')
var pages_big: number = vproj#GetTotalPages()
Assert(execute('autocmd VprojPane VimResized') =~ 'VimResized', 'resize: VimResized handler is registered')
if exists('##WinResized')
  Assert(execute('autocmd VprojPane WinResized') =~ 'WinResized', 'resize: WinResized handler is registered')
else
  echom 'SKIP: resize: WinResized handler registration (this Vim has no WinResized event)'
endif
set columns=70 lines=15
doautocmd VimResized
Assert(winwidth(PaneWid()) <= 50, 'resize: pane clamped to the narrow terminal (' .. winwidth(PaneWid()) .. ')')
Assert(winnr('$') == 2, 'resize: precondition, pane and edit window only (' .. winnr('$') .. ')')
Assert(MinWidth() >= 20, 'resize: edit window keeps 20 columns (' .. string(Widths()) .. ')')
Assert(WidestRow() <= winwidth(PaneWid()), 'resize: no row wider than the pane window (' .. WidestRow() .. ' vs ' .. winwidth(PaneWid()) .. ')')
Assert(vproj#GetTotalPages() > pages_big, 'resize: page count follows the shorter terminal (' .. vproj#GetTotalPages() .. ' vs ' .. pages_big .. ')')
set columns=160 lines=40
doautocmd VimResized
Assert(winwidth(PaneWid()) == 60, 'resize: pane back at its configured width (' .. winwidth(PaneWid()) .. ')')
Assert(vproj#GetTotalPages() == pages_big, 'resize: page count back to ' .. pages_big .. ' (' .. vproj#GetTotalPages() .. ')')
Assert(WidestRow() <= winwidth(PaneWid()), 'resize: rows fit after growing back')
# The WinResized handler itself, fired by hand (the event only fires from the
# main loop, which a sourced script never reaches). Only the stable contract:
# after the terminal shrinks, the pane is no wider than the terminal can spare.
if exists('##WinResized')
  set columns=70 lines=15
  var pre_winresized: number = winwidth(PaneWid())
  doautocmd WinResized
  Assert(pre_winresized > 70 - 20 - 1, 'resize: WinResized precondition, Vim alone left the pane wide (' .. pre_winresized .. ')')
  Assert(winwidth(PaneWid()) <= 70 - 20 - 1, 'resize: WinResized refits the pane to the narrow terminal (' .. winwidth(PaneWid()) .. ')')
  set columns=160 lines=40
  doautocmd WinResized
endif
# Closing the pane drops the handlers: no pane, no work.
vproj#PaneClose()
Assert(execute('autocmd VprojPane VimResized') !~ 'vproj#', 'resize: handler cleared on PaneClose')
doautocmd VimResized
unlet g:vproj_pane_width_default
Reset()

# ── 2. SetPaneWidth / PaneGrow clamp ──
# Used to: columns=60, SetPaneWidth(80) gave pane_width 80 on a 58-wide window,
# 80-cell rows, and an edit window of 1 column.
Fresh(d1)
set columns=60
vproj#SetPaneWidth(80)
Assert(vproj#GetPaneWidth() <= 40, 'clamp: SetPaneWidth(80) at 60 columns gives pane_width <= 40 (' .. vproj#GetPaneWidth() .. ')')
Assert(winwidth(PaneWid()) == vproj#GetPaneWidth(), 'clamp: window width equals pane_width (' .. winwidth(PaneWid()) .. ')')
Assert(MinWidth() >= 20, 'clamp: edit window keeps 20 columns (' .. string(Widths()) .. ')')
Assert(WidestRow() <= winwidth(PaneWid()), 'clamp: rows fit the window')
for _ in range(30)
  vproj#PaneGrow()
endfor
Assert(vproj#GetPaneWidth() <= 40, 'clamp: PaneGrow stops at the terminal limit (' .. vproj#GetPaneWidth() .. ')')
Assert(MinWidth() >= 20, 'clamp: edit window keeps 20 columns after PaneGrow (' .. string(Widths()) .. ')')
Reset()

# ── 3. Mode menu keeps the active-state markers ──
# Used to: 29-cell base + ' *' + ' [G]' overflowed below width ~35 and at width
# 20 the [G] marker was clipped away.
def CheckMenu(w: number): void
  Fresh(d1)
  vproj#SetPaneWidth(w)
  test_feedinput("file_00\<CR>")
  vproj#PromptFilter()
  vproj#ToggleGitFilter()
  var row: string = get(PaneLines(), 0, '')
  Assert(vproj#IsGitFilterActive(), 'menu ' .. w .. ': git filter is on')
  Assert(row =~ '\*', 'menu ' .. w .. ': filter marker visible: "' .. row .. '"')
  Assert(row =~ '\[G\]', 'menu ' .. w .. ': git marker visible: "' .. row .. '"')
  Assert(strwidth(row) == vproj#GetPaneWidth(), 'menu ' .. w .. ': row is exactly pane_width (' .. strwidth(row) .. ' vs ' .. vproj#GetPaneWidth() .. ')')
  Reset()
enddef
CheckMenu(20)
CheckMenu(28)
CheckMenu(34)
Fresh(d1)
Assert(get(PaneLines(), 0, '') =~ '^\[F\]ile  \[B\]uf  \[C\]ode  \[q\]fix', 'menu: full form kept when it fits')
Reset()

# ── 4. Preview and diff on narrow terminals ──
# Used to (80x24): widths 37/1/40, edit window 1 column, pane not restored on
# close; global 'set winfixwidth' collapsed the pane to 1 column for good.
def PreviewAt(cols: number, rows: number, gfw: bool): void
  var tag: string = 'preview ' .. cols .. 'x' .. rows .. (gfw ? ' gwfw' : '')
  Fresh(d1)
  execute 'set columns=' .. cols .. ' lines=' .. rows
  if gfw
    set winfixwidth
  endif
  vproj#SetPaneWidth(40)
  var pw: number = vproj#GetPaneWidth()
  var before: number = winnr('$')
  vproj#TogglePreview()
  Assert(MinWidth() >= min([20, cols - 21]), tag .. ': no window ends narrower than its minimum (' .. string(Widths()) .. ')')
  Assert(winwidth(PaneWid()) == pw, tag .. ': pane keeps pane_width ' .. pw .. ' with preview (' .. winwidth(PaneWid()) .. ')')
  vproj#TogglePreview()
  Assert(winnr('$') == before, tag .. ': window count restored after P off (' .. winnr('$') .. ')')
  Assert(winwidth(PaneWid()) == pw, tag .. ': pane width == pane_width after P off (' .. winwidth(PaneWid()) .. ')')
  Reset()
enddef
PreviewAt(80, 24, false)
PreviewAt(50, 10, false)
PreviewAt(40, 8, false)
PreviewAt(80, 24, true)
PreviewAt(160, 40, true)
PreviewAt(120, 30, false)
PreviewAt(120, 30, true)

# The refusal is announced, ASCII, and opens nothing.
Fresh(d1)
set columns=80 lines=24
vproj#SetPaneWidth(40)
var n_before: number = winnr('$')
:messages clear
vproj#TogglePreview()
Assert(winnr('$') == n_before, 'preview refusal: no window opened at 80 columns')
Assert(execute('messages') =~ 'vproj: terminal too narrow for the preview', 'preview refusal: says why')
Reset()

# Roomy terminal: the preview still opens.
Fresh(d1)
vproj#TogglePreview()
Assert(bufwinnr('\[Preview\]') > 0, 'preview opens on a wide terminal: the preview window exists (' .. winnr('$') .. ' windows)')
Assert(winnr('$') == 3, 'preview opens on a wide terminal: pane, edit window and preview (' .. winnr('$') .. ' windows)')
vproj#TogglePreview()
Assert(winwidth(PaneWid()) == vproj#GetPaneWidth(), 'wide terminal: pane width intact after P off')
Reset()

# Diff split (\d): needs a git repo with a change.
var rd: string = root .. '/repo'
mkdir(rd, 'p')
system('git -C ' .. shellescape(rd) .. ' init -q')
writefile(['one'], rd .. '/a.txt')
system('git -C ' .. shellescape(rd) .. ' add -A && git -C ' .. shellescape(rd) .. ' -c user.email=t@t -c user.name=t commit -qm init')
writefile(['one', 'two'], rd .. '/a.txt')
# Note: Vim run without a terminal re-reads its 80x24 size after every
# system() call, so the diff cases run at 80x24 on purpose.
def DiffAt(paneW: number, expect_open: bool): void
  var tag: string = 'diff 80x24 pane ' .. paneW
  Fresh(rd)
  set columns=80 lines=24
  vproj#SetPaneWidth(paneW)
  var pw: number = vproj#GetPaneWidth()
  var n0: number = winnr('$')
  vproj#SelectFirst()
  for _ in range(10)
    if get(PaneLines(), line('.', PaneWid()) - 1, '') =~ 'a\.txt'
      break
    endif
    vproj#SelectNext()
  endfor
  :messages clear
  vproj#OpenDiffPreview()
  Assert(MinWidth() >= 20, tag .. ': no window below 20 columns (' .. string(Widths()) .. ')')
  Assert(winwidth(PaneWid()) == pw, tag .. ': pane keeps pane_width (' .. winwidth(PaneWid()) .. ')')
  if expect_open
    Assert(winnr('$') == n0 + 1, tag .. ': diff split opened')
  else
    Assert(winnr('$') == n0, tag .. ': refused, no split opened')
    Assert(execute('messages') =~ 'vproj: terminal too narrow for the diff', tag .. ': says why')
  endif
  Reset()
enddef
DiffAt(40, false)
DiffAt(20, true)

# ── 5. Help window focus ──
# Used to: after q the focus was in the [No Name] window, the pane one column
# narrower (the help window opens to the LEFT of the pane).
def HelpAt(cols: number): void
  var tag: string = 'help ' .. cols
  Fresh(d1)
  vproj#PaneClose()
  execute 'set columns=' .. cols
  vproj#PaneTogglePermanent()
  var n_help: number = winnr('$')
  var pw_help: number = vproj#GetPaneWidth()
  vproj#ShowHelp()
  Assert(winnr('$') == n_help + 1, tag .. ': opens one window')
  feedkeys('q', 'xt')
  Assert(winnr('$') == n_help, tag .. ': window count restored (' .. winnr('$') .. ')')
  Assert(win_getid() == PaneWid(), tag .. ': focus back on the pane after q')
  Assert(winwidth(PaneWid()) == pw_help, tag .. ': pane width restored (' .. winwidth(PaneWid()) .. ' vs ' .. pw_help .. ')')
  Reset()
enddef
HelpAt(160)
HelpAt(100)
HelpAt(80)

if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
silent! only!
silent! :%bwipeout!
execute 'cd ' .. fnameescape(saved_cwd)
delete(root, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!

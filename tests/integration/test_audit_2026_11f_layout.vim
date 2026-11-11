vim9script

# Regression tests for the 2026-11f layout round: the quit guard no longer
# quits from inside the user's own command, the open-file path always gives
# the pane back its width and never reuses the pane window, a manual resize
# is the user's choice (not reverted by WinResized), and the preview / diff
# splits are sized to the room that is actually there.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11f_layout.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname().

$XDG_CACHE_HOME = tempname()
var src_dir: string = fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src'
execute 'set rtp^=' .. fnameescape(src_dir)
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0
set shortmess+=F

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_layout_f'
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

# Narrowest window that is not the pane.
def MinEditWidth(): number
  var m: number = 9999
  for n in range(1, winnr('$'))
    if win_getid(n) != PaneWid()
      m = min([m, winwidth(n)])
    endif
  endfor
  return m
enddef

def Fixture(name: string, files: list<string>): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  for f in files
    writefile([f], d .. '/' .. f)
  endfor
  return d
enddef

# A terminal-less Vim resets to 80x24 after every system() call (the git
# commands under test run one); $COLUMNS/$LINES make it reset to this size.
def SetTerm(c: number, l: number): void
  $COLUMNS = string(c)
  $LINES = string(l)
  &columns = c
  &lines = l
enddef

def Screen(): void
  SetTerm(160, 40)
enddef

def Reset(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  set nowinfixwidth
  set nohidden
  Screen()
enddef

# Pane (temporary) plus one edit window, permanent, back in the pane.
def Fresh(dir: string): void
  Reset()
  execute 'cd ' .. fnameescape(dir)
  vproj#PaneOpen()
  vproj#SwitchMode('file')
  vproj#PaneTogglePermanent()
  Screen()
enddef

def PaneCursorText(): string
  var wid = PaneWid()
  return wid == 0 ? '' : get(PaneLines(), line('.', wid) - 1, '')
enddef

def SelectName(name: string): bool
  vproj#SelectFirst()
  for _ in range(80)
    if PaneCursorText() =~ '\V\<' .. escape(name, '\') .. '\>'
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

def Wait(ms: number): void
  execute 'sleep ' .. ms .. 'm'
enddef

var d1: string = Fixture('guard', ['x1.txt', 'x2.txt', 'x3.txt'])

# ── 1. The quit guard does not quit from inside the user's command ──
# Used to: `WinEnter * ++nested if PaneIsLastWindow() | quit | endif` ran
# inside `:close`. With a hidden modified buffer the :quit raised E37/E162 in
# the user's command, aborted the rest of their command line (g:r stayed []),
# and the pane window was replaced by the modified buffer.
g:quitpre_count = 0
augroup VprojFTest
  autocmd!
  autocmd QuitPre * g:quitpre_count += 1
augroup END
Fresh(d1)
set hidden
wincmd l
execute 'edit ' .. fnameescape(d1 .. '/x1.txt')
normal! ix
execute 'edit ' .. fnameescape(d1 .. '/x2.txt')
g:r = []
v:errmsg = ''
silent! wincmd h
silent! wincmd l
silent! execute 'legacy let g:r = [] | close | call add(g:r, "AFTER")'
Assert(v:errmsg == '', 'guard: no error raised inside the user command (' .. v:errmsg .. ')')
Assert(g:r == ['AFTER'], 'guard: the user command chain ran to completion (' .. string(g:r) .. ')')
Wait(100)
Assert(winnr('$') == 1 && bufnr('%') == bufnr('VPROJ') && vproj#IsPaneVisible(),
  'guard: the pane is still the pane, not replaced by the hidden buffer (wins ' .. winnr('$') .. ', buf ' .. bufname('%') .. ')')
Assert(g:quitpre_count == 0, 'guard: modified hidden buffer -> no :quit attempted (' .. g:quitpre_count .. ')')

# At most one timer however many WinEnter events arrive.
var before_timers: number = len(timer_info())
for _ in range(6)
  silent! doautocmd <nomodeline> WinEnter
endfor
Assert(len(timer_info()) <= before_timers + 1, 'guard: at most one pending timer (' .. before_timers .. ' -> ' .. len(timer_info()) .. ')')
Wait(100)
Assert(g:quitpre_count == 0 && vproj#IsPaneVisible(), 'guard: still no quit with the modified buffer')

# A timer that is pending when the pane closes finds nothing to do.
silent! doautocmd <nomodeline> WinEnter
vproj#PaneClose()
Wait(100)
Assert(g:quitpre_count == 0, 'guard: pane closed while the check was pending -> no quit')
set nohidden
silent! :%bwipeout!
Reset()

# A clean last window does quit: run it in a child Vim (the quit ends it) and
# read the marker file it leaves.
var marker: string = root .. '/quit_marker'
var child: string = root .. '/child.vim'
writefile([
  'vim9script',
  '$XDG_CACHE_HOME = ' .. string(root .. '/childcache'),
  'execute "set rtp^=" .. fnameescape(' .. string(src_dir) .. ')',
  'runtime! plugin/vproj.vim',
  'set nomore columns=120 lines=30',
  'execute "cd " .. fnameescape(' .. string(d1) .. ')',
  'execute "edit " .. fnameescape(' .. string(d1 .. '/x1.txt') .. ')',
  'vproj#PaneTogglePermanent()',
  'autocmd VimLeavePre * writefile(["quit"], ' .. string(marker) .. ')',
  'wincmd l',
  'close',
  'var n = 0',
  'while n < 100',
  '  sleep 50m',
  '  n += 1',
  'endwhile',
  'writefile(["stuck"], ' .. string(marker) .. ')',
  'qa!',
], child)
system('vim -N -u NONE -i NONE --not-a-term -S ' .. shellescape(child) .. ' </dev/null >/dev/null 2>&1')
Screen()
Assert(filereadable(marker) && readfile(marker) == ['quit'], 'guard: clean pane-only window quits Vim ('
  .. (filereadable(marker) ? string(readfile(marker)) : 'no marker') .. ')')

# ── 2. A file opened from a lone pane gets its own window, pane at pane_width ──
# Used to: after :only from the pane, the new edit window was a plain
# `botright vnew` half of the screen (pane 79 wide, nothing restored it until
# some later resize event). Every opener shares EditTargetWindow.
def LoneAndOpen(tag: string, mode: string, name: string): void
  Fresh(d1)
  if mode == 'buf'
    execute 'badd ' .. fnameescape(d1 .. '/x3.txt')
  elseif mode == 'qfix'
    setqflist([{filename: d1 .. '/x3.txt', lnum: 1, text: 'hit'}])
  endif
  vproj#SwitchMode(mode)
  var pw: number = vproj#GetPaneWidth()
  win_gotoid(PaneWid())
  only
  Assert(winnr('$') == 1 && bufnr('%') == bufnr('VPROJ'), tag .. ': pane is the only window after :only')
  Assert(SelectName(name), tag .. ': found ' .. name)
  vproj#SelectCurrent()
  Assert(winnr('$') == 2, tag .. ': two windows (' .. winnr('$') .. ')')
  Assert(PaneWid() > 0 && winbufnr(PaneWid()) == bufnr('VPROJ'), tag .. ': the pane buffer survives in its window')
  Assert(winwidth(PaneWid()) == pw, tag .. ': pane width is pane_width (' .. winwidth(PaneWid()) .. ' vs ' .. pw .. ')')
  var shown: list<string> = []
  for n in range(1, winnr('$'))
    if win_getid(n) != PaneWid()
      shown->add(fnamemodify(bufname(winbufnr(n)), ':t'))
    endif
  endfor
  Assert(shown == ['x3.txt'], tag .. ': the file shows in a new window (' .. string(shown) .. ')')
enddef
LoneAndOpen('lone file', 'file', 'x3.txt')
LoneAndOpen('lone buf', 'buf', 'x3.txt')
LoneAndOpen('lone qfix', 'qfix', 'x3.txt')
Reset()

# ── 3. A manual resize is the user's choice ──
# Used to: `:vertical resize 55`, then `:vertical resize 30`, then Right gave
# 41: HandleResize (WinResized fires for any size change) refit to the old
# pane_width and discarded both manual resizes.
Fresh(d1)
Assert(vproj#GetPaneWidth() == 40 && winwidth(PaneWid()) == 40, 'manual: starts at 40')
win_execute(PaneWid(), 'vertical resize 55')
redraw
Wait(50)
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) == 55, 'manual: 55 sticks (' .. winwidth(PaneWid()) .. ')')
Assert(vproj#GetPaneWidth() == 55, 'manual: pane_width adopts 55 (' .. vproj#GetPaneWidth() .. ')')
win_execute(PaneWid(), 'vertical resize 30')
redraw
Wait(50)
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) == 30 && vproj#GetPaneWidth() == 30, 'manual: 30 sticks (' .. winwidth(PaneWid()) .. '/' .. vproj#GetPaneWidth() .. ')')
vproj#PaneGrow()
Assert(winwidth(PaneWid()) == 31, 'manual: Right after the drag grows from 30 (' .. winwidth(PaneWid()) .. ')')

# A terminal resize still refits, and growing back restores the remembered width.
win_execute(PaneWid(), 'vertical resize 70')
doautocmd <nomodeline> VimResized
Assert(vproj#GetPaneWidth() == 70, 'manual: 70 adopted')
SetTerm(80, 40)
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) <= 59 && MinEditWidth() >= 20, 'manual: terminal shrink refits (' .. string(Widths()) .. ')')
SetTerm(160, 40)
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) == 70, 'manual: growing back restores the remembered 70 (' .. winwidth(PaneWid()) .. ')')

# Programmatic paths still end at pane_width, also after the events they cause.
vproj#SetPaneWidth(50)
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) == 50 && vproj#GetPaneWidth() == 50, 'manual: SetPaneWidth(50) ends at 50')
vproj#TogglePreview()
Assert(winnr('$') == 3, 'manual: preview opened (' .. winnr('$') .. ' windows)')
doautocmd <nomodeline> VimResized
Assert(winwidth(PaneWid()) == 50, 'manual: preview leaves the pane at 50 (' .. winwidth(PaneWid()) .. ')')
vproj#TogglePreview()
win_gotoid(PaneWid())
vproj#ShowHelp()
doautocmd <nomodeline> VimResized
feedkeys('q', 'xt')
Assert(winwidth(PaneWid()) == 50, 'manual: help leaves the pane at 50 (' .. winwidth(PaneWid()) .. ')')
Reset()

# ── 4. Preview and diff size themselves to the room that is there ──
# Used to: a 60-wide pane at 120x30 refused the preview (120-60-1-41 < 20)
# and the diff split refused when the one target window was < 41 columns even
# though equalising the row left every window 20+.
g:vproj_pane_width_default = 60
Fresh(d1)
SetTerm(120, 30)
Assert(winwidth(PaneWid()) == 60, 'preview: pane 60 at 120 columns (' .. winwidth(PaneWid()) .. ')')
win_gotoid(PaneWid())
SelectName('x1.txt')
vproj#TogglePreview()
Assert(winnr('$') == 3, 'preview: opens with a 60-wide pane at 120x30 (' .. winnr('$') .. ' windows)')
var pwin: number = bufwinid(bufnr('[Preview]'))
Assert(pwin > 0 && winwidth(win_id2win(pwin)) >= 24 && winwidth(win_id2win(pwin)) < 40,
  'preview: reduced width (' .. (pwin > 0 ? winwidth(win_id2win(pwin)) : -1) .. ')')
Assert(MinEditWidth() >= 20 && winwidth(PaneWid()) == 60, 'preview: edit window keeps 20, pane keeps 60 (' .. string(Widths()) .. ')')
vproj#TogglePreview()
unlet g:vproj_pane_width_default

# The default pane at 80x24 still refuses.
Fresh(d1)
SetTerm(80, 24)
win_gotoid(PaneWid())
var nwin: number = winnr('$')
vproj#TogglePreview()
Assert(winnr('$') == nwin && execute('messages') =~ 'terminal too narrow for the preview', 'preview: 80x24 refuses with the message')

# Two edit windows: the preview measures the real edit window.
Fresh(d1)
wincmd l
vsplit
Screen()
win_gotoid(PaneWid())
SelectName('x1.txt')
vproj#TogglePreview()
Assert(winnr('$') == 4, 'preview: opens beside two edit windows at 160 (' .. winnr('$') .. ')')
Assert(MinEditWidth() >= 20, 'preview: every window keeps 20 columns (' .. string(Widths()) .. ')')
vproj#TogglePreview()

# Diff / blame split: two side-by-side edit windows with room for three.
Reset()
var gd: string = Fixture('gitdir', ['a.txt'])
system('git -C ' .. shellescape(gd) .. ' init -q && git -C ' .. shellescape(gd) .. ' -c user.email=t@t -c user.name=t add a.txt && git -C ' .. shellescape(gd) .. ' -c user.email=t@t -c user.name=t commit -q -m i')
writefile(['changed'], gd .. '/a.txt')
Fresh(gd)
SetTerm(120, 30)
wincmd l
vsplit
SetTerm(120, 30)
Assert(MinEditWidth() < 41 && MinEditWidth() >= 38, 'diff: two edit windows each under 41 columns (' .. string(Widths()) .. ')')
win_gotoid(PaneWid())
SelectName('a.txt')
vproj#OpenDiffPreview()
Assert(winnr('$') == 4, 'diff: opens although each edit window is under 41 (' .. winnr('$') .. ' windows)')
Assert(MinEditWidth() >= 20, 'diff: every window keeps 20 columns (' .. string(Widths()) .. ')')

# One narrow edit window still refuses.
Reset()
Fresh(gd)
SetTerm(80, 24)
win_gotoid(PaneWid())
SelectName('a.txt')
nwin = winnr('$')
vproj#OpenDiffPreview()
Assert(winnr('$') == nwin && execute('messages') =~ 'terminal too narrow for the diff', 'diff: one 39-column edit window refuses')

Reset()
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

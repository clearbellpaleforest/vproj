vim9script

# Regression tests (audit 2026-11d, session-misc): tabpage dir changes, session
# save/load edges, help width on a narrow terminal, closing a buffer that
# cannot be written. Each block names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11d_session.vim -c 'cquit!'

$XDG_CACHE_HOME = tempname()
# Session saving is opt-in (CLAUDE.md rule 5); these tests exercise it.
g:vproj_save_session = 1
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0
set hidden

var failures: number = 0
var saved_cwd: string = getcwd()
var saved_cache: string = $XDG_CACHE_HOME
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit3d'
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

def PaneCursorText(): string
  var wid = PaneWid()
  var lnum = wid == 0 ? -1 : line('.', wid)
  return lnum < 1 ? '' : get(PaneLines(), lnum - 1, '')
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

def Fresh(dir: string): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  execute 'cd ' .. fnameescape(dir)
  vproj#PaneOpen()
  vproj#SwitchMode('file')
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

def Modified(nr: number): bool
  var bi = getbufinfo(nr)
  return !empty(bi) && bi[0].changed > 0
enddef

def Msgs(): string
  return execute('messages')
enddef

# ── 1. :tcd moves the pane ──
# Used to: only DirChanged global/window were registered, so after :tcd the
# pane kept listing the old directory.
var d1a: string = Fixture('tcd_a', ['ta.txt'])
var d1b: string = Fixture('tcd_b', ['tb.txt'])
Fresh(d1a)
Assert(match(PaneLines(), 'ta\.txt') >= 0, 'tcd: precondition, pane lists ta.txt')
execute 'tcd ' .. fnameescape(d1b)
Assert(match(PaneLines(), 'tb\.txt') >= 0 && match(PaneLines(), 'ta\.txt') < 0, 'tcd: pane follows :tcd, got ' .. string(PaneLines()))
# and :lcd in a non-pane window still does not move it
var d1c: string = Fixture('tcd_c', ['tc.txt'])
var edit_wid: number = 0
for wnr in range(1, winnr('$'))
  if winbufnr(wnr) != bufnr('VPROJ')
    edit_wid = win_getid(wnr)
  endif
endfor
win_execute(edit_wid, 'lcd ' .. fnameescape(d1c))
Assert(match(PaneLines(), 'tb\.txt') >= 0 && match(PaneLines(), 'tc\.txt') < 0, 'tcd: :lcd in an edit window leaves the pane alone')
win_execute(edit_wid, 'execute "cd " .. fnameescape(d1b)')

# ── 2. SaveSession reports a mkdir failure ──
# Used to: mkdir failure was swallowed with a bare return; the user got no
# message and the session silently was not saved.
var blocker: string = root .. '/blocker_file'
writefile(['x'], blocker)
var d2: string = Fixture('sess_mkdir', ['s.txt'])
Fresh(d2)
$XDG_CACHE_HOME = blocker .. '/sub'
var thrown2: string = ''
# Close the pane as :q does (the wipe handler saves the session). PaneClose()
# would close it inside win_execute(), which discards echom output.
try
  win_gotoid(PaneWid())
  close
catch
  thrown2 = v:exception
endtry
Assert(empty(thrown2), 'mkdir failure: no exception escapes: ' .. thrown2)
var m2: string = Msgs()
Assert(m2 =~ 'vproj: could not create session directory' && stridx(m2, blocker .. '/sub/vproj') >= 0,
  'mkdir failure: the message names the directory')
$XDG_CACHE_HOME = saved_cache

# ── 3. LoadSession falls back to cwd for the project ──
# Used to: session dir=A (no .vproj), cwd=B (has .vproj): SwitchMode found B's
# project, LoadSession showed "no project found".
var d3a: string = Fixture('sess_a', ['a.txt'])
var d3b: string = Fixture('sess_b', ['b.txt'])
writefile(['Project Name: projB', 'Project Root: ' .. d3b, 'Included Directories:', 'Included Files:',
  'b.txt', 'Excluded Directories:', 'Excluded Files:'], d3b .. '/.vproj')
Fresh(d3a)
vproj#SwitchMode('code')
vproj#PaneClose()
silent! only!
silent! :%bwipeout!
execute 'cd ' .. fnameescape(d3b)
vproj#PaneOpen()
Assert(vproj#GetCurrentMode() == 'code', 'session fallback: precondition, session restored code mode')
var all3: string = join(PaneLines(), "\n")
Assert(all3 !~ 'no project found' && all3 =~ 'projB', 'session fallback: code mode found projB, pane: ' .. string(PaneLines()[0 : 3]))
Assert(all3 =~ 'b\.txt' && all3 !~ '\<a\.txt', 'session fallback: pane lists B, not A')

# ── 4. ShowHelp on a narrow terminal ──
# Used to: `vert resize <negative>` is relative, so the help window shrank
# instead of getting a sane width.
var d4: string = Fixture('help', ['h.txt'])
Fresh(d4)
vproj#SetPaneWidth(20)
set columns=22
# What a plain split gives here, with no resize at all.
leftabove vertical new
var natural: number = winwidth(0)
close
var err4: string = ''
try
  vproj#ShowHelp()
catch
  err4 = v:exception
endtry
var hw: number = 0
for info in getbufinfo()
  if fnamemodify(info.name, ':t') == '[vproj-help]' && !empty(info.windows)
    hw = winwidth(info.windows[0])
  endif
endfor
Assert(empty(err4), 'help narrow: no exception: ' .. err4)
Assert(hw >= 1, 'help narrow: help window exists with positive width, got ' .. hw)
Assert(hw == natural, 'help narrow: no negative (relative) resize shrank it: natural ' .. natural .. ', got ' .. hw)
silent! only!
set columns=160
# A roomy terminal still gets the absolute width (min(80, columns - pane - 4)).
Fresh(d4)
vproj#SetPaneWidth(30)
set columns=100
vproj#ShowHelp()
hw = 0
for info in getbufinfo()
  if fnamemodify(info.name, ':t') == '[vproj-help]' && !empty(info.windows)
    hw = winwidth(info.windows[0])
  endif
endfor
Assert(hw == 66, 'help wide: width is columns - pane - 4 = 66, got ' .. hw)
silent! only!
set columns=160

# ── 5. CloseBuffer survives a failed write and leaves no split ──
# Used to: E505/E212 escaped as a raw exception; in the not-displayed branch
# `sbuffer N | write | close` left the split open.
var d5: string = Fixture('closebuf', ['x.txt'])
# A read-only file blocks :write only for a non-root user. As root (typical
# in CI containers) permissions are ignored, so there the write is made to
# fail by removing the file's directory after the buffer is loaded.
var is_root: bool = trim(system('id -u')) == '0'
var ro: string = d5 .. '/rodir/ro5.txt'
mkdir(d5 .. '/rodir', 'p')
writefile(['ro'], ro)
setfperm(ro, 'r--r--r--')
var gone: string = d5 .. '/no_such_dir/gone5.txt'
Fresh(d5)
# 5a: displayed buffer for a read-only file
wincmd p
execute 'edit ' .. fnameescape(ro)
setlocal noreadonly
append(0, 'modified')
var ro_nr: number = bufnr('%')
if is_root
  delete(d5 .. '/rodir', 'rf')
endif
vproj#SwitchMode('buf')
Assert(SelectName('ro5.txt'), 'closebuf displayed: ro5.txt is listed: ' .. string(PaneLines()))
var wn5a: number = winnr('$')
var err5a: string = ''
test_feedinput('y')
try
  vproj#CloseBuffer()
catch
  err5a = v:exception
endtry
Assert(empty(err5a), 'closebuf displayed: no exception escapes: ' .. err5a)
Assert(bufexists(ro_nr) && Modified(ro_nr), 'closebuf displayed: buffer kept and still modified')
Assert(winnr('$') == wn5a, 'closebuf displayed: window count unchanged (' .. wn5a .. ' vs ' .. winnr('$') .. ')')
Assert(Msgs() =~ 'Cannot save.*ro5\.txt', 'closebuf displayed: error names the buffer')

# 5b: hidden buffer whose directory does not exist (fails even as root)
execute 'edit ' .. fnameescape(gone)
append(0, 'modified')
var gone_nr: number = bufnr('%')
execute 'edit ' .. fnameescape(d5 .. '/x.txt')
Assert(empty(win_findbuf(gone_nr)), 'closebuf hidden: precondition, buffer is not displayed')
vproj#SwitchMode('buf')
Assert(SelectName('gone5.txt'), 'closebuf hidden: gone5.txt is listed')
var wn5b: number = winnr('$')
var err5b: string = ''
test_feedinput('y')
try
  vproj#CloseBuffer()
catch
  err5b = v:exception
endtry
Assert(empty(err5b), 'closebuf hidden: no exception escapes: ' .. err5b)
Assert(bufexists(gone_nr) && Modified(gone_nr), 'closebuf hidden: buffer kept and still modified')
Assert(winnr('$') == wn5b, 'closebuf hidden: no stray split (' .. wn5b .. ' vs ' .. winnr('$') .. ')')
Assert(Msgs() =~ 'Cannot save.*gone5\.txt', 'closebuf hidden: error names the buffer')

# ── Cleanup ──
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
silent! only!
silent! :%bwipeout!
execute 'cd ' .. fnameescape(saved_cwd)
setfperm(ro, 'rw-r--r--')
delete(root, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!

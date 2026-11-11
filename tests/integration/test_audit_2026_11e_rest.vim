vim9script

# Regression tests for the 2026-11e audit, "rest" group: quit-with-only-the-pane,
# cursor clamping, message/statusline width, symlink loops, ' R' git status,
# preview/message cosmetics. Each block names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11e_rest.vim -c 'cquit!'
#
# Hermetic: session cache and fixtures live under tempname().

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit_rest'
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

def PaneCursorLine(): number
  var wid = PaneWid()
  return wid == 0 ? -1 : line('.', wid)
enddef

def PaneCursorText(): string
  var lnum = PaneCursorLine()
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
  set columns=160 lines=40
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

def Git(dir: string, args: string): string
  return system('git -C ' .. shellescape(dir) .. ' -c user.email=t@t -c user.name=t ' .. args)
enddef

def LastMessage(): string
  var m: list<string> = split(execute('messages'), "\n")
  return empty(m) ? '' : m[-1]
enddef

# Run whatever test_feedinput() left unread.
def DrainInput(): void
  feedkeys("\<Esc>", 'xt')
enddef

g:quitpre_count = 0
augroup VprojRestTest
  autocmd!
  autocmd QuitPre * g:quitpre_count += 1
augroup END

# ── 1. Closing the edit window must quit Vim, not strand the pane ──
# Used to: pane + one edit window, the edit window closed with :q left the
# pane as the ONLY window and Vim kept running. The guard runs plain :quit
# (QuitPre fires). A hidden modified buffer makes Vim itself refuse (E162),
# so this headless test survives and the guard is never a :quit!.
var d1: string = Fixture('guard', ['one.txt', 'two.txt'])
Fresh(d1)
vproj#PaneClose()
silent! only!
silent! :%bwipeout!
set hidden
execute 'edit ' .. fnameescape(d1 .. '/one.txt')
vproj#PaneTogglePermanent()
Assert(winnr('$') == 2 && bufname(winbufnr(1)) =~ 'VPROJ', 'guard: pane on the left plus one edit window')
Assert(exists('#VprojPane#WinEnter'), 'guard: a WinEnter autocmd is registered in the pane group')
wincmd l
execute 'edit ' .. fnameescape(d1 .. '/two.txt')
setline(1, 'unsaved edit')
Assert(&modified, 'guard: hidden modified buffer present, so :quit must be refused by Vim')
g:quitpre_count = 0
silent! close
# 2026-11f: the guard no longer quits from inside the user's :close; it
# schedules a check (timer) that stays silent when a buffer is modified. So a
# hidden modified buffer means NO quit attempt and the pane stays (the clean
# quit is covered in test_audit_2026_11f_layout.vim).
sleep 100m
Assert(g:quitpre_count == 0, 'guard: modified hidden buffer -> the deferred check does not quit (QuitPre fired ' .. g:quitpre_count .. 'x)')
Assert(winnr('$') == 1 && vproj#IsPaneVisible() && bufnr('%') == bufnr('VPROJ'), 'guard: the pane stays as the only window, wins ' .. winnr('$') .. ', buf ' .. bufname('%'))
silent! wincmd p
vproj#PaneClose()
silent! only!
silent! write
vproj#PaneOpen()
Assert(vproj#IsPaneVisible() && winnr('$') == 2, 'guard: the pane reopens cleanly afterwards')
set nohidden

# The guard must not fire while the pane opens, closes or toggles.
Fresh(d1)
vproj#PaneClose()
silent! only!
silent! :%bwipeout!
execute 'edit ' .. fnameescape(d1 .. '/one.txt')
g:quitpre_count = 0
for _ in range(3)
  vproj#PaneTogglePermanent()
  vproj#PaneTogglePermanent()
endfor
vproj#PaneOpen()
vproj#PaneClose()
Assert(g:quitpre_count == 0 && winnr('$') == 1, 'guard: Open/Close/TogglePermanent cycles never quit (windows: ' .. winnr('$') .. ')')

# Pane is the last window: PaneClose opens a spare window on purpose.
vproj#PaneTogglePermanent()
wincmd h
only
Assert(winnr('$') == 1 && bufnr('%') == bufnr('VPROJ'), 'guard: only() left the pane alone')
g:quitpre_count = 0
vproj#PaneClose()
Assert(g:quitpre_count == 0 && winnr('$') == 1 && bufname('%') !~ 'VPROJ', 'guard: PaneClose on a lone pane opens a spare window without quitting')

# Not in other tab pages: the pane is the only window of tab 1 while tab 2 exists.
vproj#PaneTogglePermanent()
wincmd h
only
tabnew
g:quitpre_count = 0
tabprevious
Assert(g:quitpre_count == 0 && tabpagenr('$') == 2, 'guard: pane alone in a tab, another tab open -> no quit')
tabonly
vproj#PaneClose()

# ── 2. The pane cursor stays on selectable rows ──
# Used to: G and L went to the '>>> Page' footer, Ctrl-F scrolled so only the
# footer showed, a click could land on the separator. selected_line stayed
# behind, so the next <Down> started from the wrong row.
var many: list<string> = []
for i in range(60)
  add(many, printf('file_%03d.txt', i))
endfor
var d2: string = Fixture('cursor', many)
Fresh(d2)
var plines: list<string> = PaneLines()
Assert(plines[-1] =~ '>>>', 'cursor: paged listing has the footer row (' .. plines[-1] .. ')')
var last_item: number = len(plines) - 1
def GoPane(lnum: number): void
  win_gotoid(PaneWid())
  cursor(lnum, 1)
  doautocmd <nomodeline> CursorMoved
enddef
GoPane(len(plines))
Assert(PaneCursorLine() == last_item, 'cursor: footer row clamps to the last item (row ' .. PaneCursorLine() .. ', want ' .. last_item .. ')')
GoPane(2)
Assert(PaneCursorLine() == 3, 'cursor: separator row clamps to the first item (row ' .. PaneCursorLine() .. ')')
win_gotoid(PaneWid())
normal! G
doautocmd <nomodeline> CursorMoved
Assert(PaneCursorText() !~ '>>>' && PaneCursorLine() == last_item, 'cursor: G ends on the last item, not the footer')
normal! L
doautocmd <nomodeline> CursorMoved
Assert(PaneCursorText() !~ '>>>', 'cursor: L never ends on the footer')
# selected_line follows the cursor: a click on row 6 then <Down> goes to row 7.
GoPane(6)
vproj#SelectNext()
Assert(PaneCursorLine() == 7, 'cursor: selected_line synced with the cursor (SelectNext from row 6 -> ' .. PaneCursorLine() .. ')')
# Ctrl-F then the clamp leaves a window that still shows the menu row.
Fresh(Fixture('cursor_small', ['a.txt', 'b.txt', 'c.txt']))
win_gotoid(PaneWid())
execute "normal! \<C-F>"
doautocmd <nomodeline> CursorMoved
Assert(line('w0', PaneWid()) == 1, 'cursor: Ctrl-F cannot scroll the menu row out of a pane that fits')
Assert(PaneCursorText() !~ '^-\+$', 'cursor: Ctrl-F never leaves the cursor on the separator')

# ── 3. Messages fit the command line; the statusline path keeps its tail ──
# Used to: 'Moved <name> -> /long/dir' wrapped and raised a hit-enter prompt,
# and the statusline showed the HEAD of a long directory path.
var longdir: string = root .. '/' .. repeat('d', 40) .. '/' .. repeat('e', 40) .. '/' .. repeat('f', 40)
mkdir(longdir, 'p')
var d3: string = Fixture('msgs', ['moveme_here.txt'])
Fresh(d3)
set columns=100 lines=40
Assert(SelectName('moveme_here.txt'), 'messages: file listed')
test_feedinput("\<C-U>" .. longdir .. "\<CR>")
Move
DrainInput()
var mv: string = LastMessage()
Assert(filereadable(longdir .. '/moveme_here.txt'), 'messages: the move itself happened')
# 2026-11f: a destructive message (Deleted/Reverted/Moved/Renamed) now keeps its
# FULL text in :messages; the shortened form (columns-12 wide) is only what is
# displayed. So the history line is the full one and the command line height is
# back to its normal value (no hit-enter prompt).
Assert(mv =~ '\V' .. escape(longdir, '\') .. '\$', 'messages: Moved message keeps the full destination in :messages: ' .. mv)
Assert(&cmdheight == 1, 'messages: Moved message leaves cmdheight alone (' .. &cmdheight .. ')')
Assert(mv =~ 'moveme_here.txt' && mv !~ '\.\.\.', 'messages: Moved message keeps the basename and is not cut with ... in :messages: ' .. mv)

var longname: string = repeat('n', 90) .. '_clean_' .. repeat('m', 90) .. '.txt'
var d3b: string = root .. '/msgs2'
mkdir(d3b, 'p')
writefile(['x'], d3b .. '/' .. longname)
Git(d3b, 'init -q')
Git(d3b, 'add -A')
Git(d3b, 'commit -qm init')
# system() resets a terminal-less Vim to 80 columns, so Blame (which runs git
# just before it splits) needs a narrow pane to leave room for the split.
g:vproj_pane_width_default = 25
Fresh(d3b)
set columns=100 lines=40
vproj#SelectFirst()
for _ in range(10)
  if PaneCursorText() =~ 'nnnnnnnnnn'
    break
  endif
  vproj#SelectNext()
endfor
Assert(PaneCursorText() =~ 'nnnnnnnnnn', 'messages: long-name file selected')
vproj#GitStageToggle()
var ng: string = LastMessage()
Assert(ng =~ 'No git changes' && strwidth(ng) <= &columns - 12, 'messages: "No git changes" fits the line (' .. strwidth(ng) .. '): ' .. ng)
Assert(ng =~ 'nnnnnn' && ng =~ 'mmmmm\.txt', 'messages: "No git changes" keeps the start and the end of the name: ' .. ng)
vproj#GitBlame()
var bl: string = LastMessage()
Assert(bl =~ '^Blame' && strwidth(bl) <= &columns - 12, 'messages: Blame message fits the line (' .. strwidth(bl) .. '): ' .. bl)
unlet g:vproj_pane_width_default
silent! only!

# The pane statusline: a directory longer than the pane shows its END.
var deep: string = root .. '/' .. repeat('p', 30) .. '/' .. repeat('q', 30) .. '/final_leaf'
mkdir(deep, 'p')
writefile(['z'], deep .. '/z.txt')
Fresh(deep)
var sl: string = getbufvar(bufnr('VPROJ'), '&statusline', '')
Assert(sl =~ 'final_leaf', 'statusline: long path keeps its last component: ' .. sl)
Assert(sl =~ '\.\.\.', 'statusline: the cut is marked with ...: ' .. sl)
Assert(strwidth(sl) <= vproj#GetPaneWidth() + 2, 'statusline: still no wider than the pane')

# ── 4. A symlink loop must not break the pane ──
# Used to: IsRegularFile -> resolve() threw E655 and Render died with
# "render error": the whole pane was empty.
var d4: string = Fixture('loop', ['real1.txt', 'real2.txt'])
system('ln -s b ' .. shellescape(d4 .. '/a') .. ' && ln -s a ' .. shellescape(d4 .. '/b'))
Assert(getftype(d4 .. '/a') == 'link', 'symlink loop: fixture is a link loop')
try
  Fresh(d4)
catch
  Assert(false, 'symlink loop: opening the pane threw ' .. v:exception)
endtry
var sawerr: bool = false
for l in split(execute('messages'), "\n")
  if l =~ 'render error'
    sawerr = true
  endif
endfor
Assert(!sawerr, 'symlink loop: no render error in :messages')
Assert(match(PaneLines(), 'real1.txt') >= 0 && match(PaneLines(), 'real2.txt') >= 0, 'symlink loop: the normal files are listed')
Assert(len(PaneLines()) > 3, 'symlink loop: the pane has rows (' .. len(PaneLines()) .. ')')

# ── 5. ' R' (intent-to-add rename) consumes its orig-path field ──
# Used to: only X == R/C consumed the extra -z field, so for ' R' the old name
# became a status entry of its own: the parser drops 3 characters of every
# field, so the old name 'Mxyoo.txt' became path 'oo.txt' with xy 'Mx' (shown
# as modified), marking the unrelated clean file oo.txt.
var d5: string = Fixture('irename', ['Mxyoo.txt', 'oo.txt'])
Git(d5, 'init -q')
Git(d5, 'add -A')
Git(d5, 'commit -qm init')
Git(d5, 'mv Mxyoo.txt moved.txt')
Git(d5, 'reset -q')
Git(d5, 'add -N moved.txt')
Assert(system('git -C ' .. shellescape(d5) .. ' status --porcelain')->trim("\n", 2) =~ '^ R ', 'git R: precondition, porcelain reports " R" (' .. trim(system('git -C ' .. shellescape(d5) .. ' status --porcelain')) .. ')')
Fresh(d5)
vproj#ToggleGitFilter()
var shown5: list<string> = PaneLines()
Assert(match(shown5, 'oo.txt') < 0, 'git R: the old name did not turn into a bogus status entry for oo.txt: ' .. string(shown5))
vproj#ToggleGitFilter()

# ── 6. Cosmetic previews and messages ──
var d6: string = Fixture('prev', ['file_031.txt'])
Fresh(d6)
vproj#TogglePreview()
var pv: number = bufnr('\[Preview\]')
Assert(pv > 0, 'preview: buffer exists')
Assert(SelectName('file_031.txt'), 'preview: file selected')
Assert(getbufline(pv, 1, '$') == ['file_031.txt'], 'preview: file preview has no trailing blank line, got ' .. string(getbufline(pv, 1, '$')))
vproj#SelectFirst()
vproj#SelectPrev()
# Clear: select the menu row? Use the directory preview and unreadable dir instead.
var d6b: string = Fixture('prevdirs', ['sub/in.txt'])
mkdir(d6b .. '/locked', 'p')
writefile(['q'], d6b .. '/locked/q.txt')
setfperm(d6b .. '/locked', '---------')
Fresh(d6b)
vproj#TogglePreview()
pv = bufnr('\[Preview\]')
Assert(SelectName('sub'), 'preview: sub/ selected')
Assert(getbufline(pv, 1, '$') == ['-- sub/ --', '', '  in.txt'], 'preview: directory preview layout, got ' .. string(getbufline(pv, 1, '$')))
Assert(SelectName('locked'), 'preview: locked/ selected')
# chmod 000 does not stop root (typical in CI containers), so probe whether the
# directory is really unreadable here instead of assuming it.
var locked_unreadable: bool = false
try
  readdir(d6b .. '/locked')
catch
  locked_unreadable = true
endtry
if locked_unreadable
  Assert(getbufline(pv, 1, '$')[-1] =~ 'cannot read directory', 'preview: unreadable dir says so, got ' .. string(getbufline(pv, 1, '$')))
else
  echom 'SKIP: preview unreadable-dir check needs a directory this user cannot read (running as root?)'
endif
# '(no preview)': buf mode has no preview target.
vproj#SwitchMode('buf')
Assert(bufexists(pv) && getbufline(pv, 1, '$') == ['(no preview)'], 'preview: cleared preview buffer stays and holds one line, got ' .. string(getbufline(pv, 1, '$')))
vproj#SwitchMode('file')
setfperm(d6b .. '/locked', 'rwx------')

# Tree view parent row matches the plain view ('. ../').
Fresh(Fixture('treeparent', ['t.txt']))
var plain_parent: string = trim(PaneLines()[2])
vproj#ToggleTreeView()
var tree_parent: string = trim(PaneLines()[2])
Assert(plain_parent == tree_parent && tree_parent =~ '\.\./$', 'tree: parent row "' .. tree_parent .. '" matches plain "' .. plain_parent .. '"')

# Push/Pull errors carry no carriage returns (:messages shows a CR as ^M): ssh prints CRLF on a failure.
# The remote is an ext:: helper script that writes "boom\r\nline2\r\n" to stderr.
var d6c: string = Fixture('remote', ['r.txt'])
writefile(['#!/bin/sh', 'printf "boom\\r\\nline2\\r\\n" >&2', 'exit 1'], d6c .. '/../failsh.sh')
setfperm(d6c .. '/../failsh.sh', 'rwx------')
Git(d6c, 'init -q')
Git(d6c, 'add -A')
Git(d6c, 'commit -qm init')
Git(d6c, 'config protocol.ext.allow always')
Git(d6c, 'config push.autoSetupRemote true')
Git(d6c, 'remote add origin ' .. shellescape('ext::' .. resolve(d6c .. '/../failsh.sh')))
Fresh(d6c)
vproj#GitPush()
var pushmsg: string = LastMessage()
Assert(pushmsg =~ 'Push failed' && pushmsg =~ 'boom' && pushmsg !~ '\%d13\|\^M', 'git push error has no CR: ' .. strtrans(pushmsg))
vproj#GitPull()
var pullmsg: string = LastMessage()
Assert(pullmsg =~ 'Pull failed' && pullmsg =~ 'boom' && pullmsg !~ '\%d13\|\^M', 'git pull error has no CR: ' .. strtrans(pullmsg))

# ── Cleanup ──
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

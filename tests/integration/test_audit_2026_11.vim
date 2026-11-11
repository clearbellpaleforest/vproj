vim9script

# Regression tests for the 2026-11 audit of the core plugin. Each block pins
# one reproduced defect; the comment names what used to happen.
# Run: vim -N -u NONE -i NONE -S tests/integration/test_audit_2026_11.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname(), so
# nothing outside /tmp is read or written. Prompts are answered with
# test_feedinput() queued before the call that prompts.

$XDG_CACHE_HOME = tempname()
# Session saving is opt-in (CLAUDE.md rule 5); these tests exercise it.
g:vproj_save_session = 1
# Absolute: a test that cd's away must still find autoload/ (the plugin no
# longer sources it at load).
execute 'set rtp+=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
# A fed <Esc> otherwise waits for a possible terminal key code forever.
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit'
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

def SessionText(): list<string>
  var p: string = $XDG_CACHE_HOME .. '/vproj/session'
  return filereadable(p) ? readfile(p) : []
enddef

def Git(dir: string, args: string): string
  return system('git -C ' .. shellescape(dir) .. ' -c user.email=t@t -c user.name=t ' .. args)
enddef

# ── 1. Global A no longer hijacked (used to launch the agent terminal) ──
Assert(maparg('A', 'n') == '', 'normal-mode A is not remapped globally')
Assert(exists(':VprojAgent') == 2, ':VprojAgent command exists')

# ── 2. Paging shows exactly one page of items (used to show one extra) ──
var many: list<string> = []
for i in range(60)
  many->add(printf('file_%02d.txt', i))
endfor
var pagedir: string = Fixture('paging', many)
Fresh(pagedir)
Assert(vproj#IsPagingActive(), 'paging active with 60 files')
Assert(len(PaneLines()) <= winheight(PaneWid()), 'pane lines fit the window (page nav row visible)')
var page1: list<string> = PaneLines()
vproj#NextPage()
var page2: list<string> = PaneLines()
var p1_items: list<string> = filter(copy(page1), (_, l) => l =~ 'file_')
var p2_items: list<string> = filter(copy(page2), (_, l) => l =~ 'file_')
Assert(!empty(p1_items) && !empty(p2_items), 'both pages list files')
Assert(matchstr(p1_items[-1], 'file_\d\+') != matchstr(p2_items[0], 'file_\d\+'), 'last of page 1 is not repeated as first of page 2')

# ── 3. Nav letters reach items past z (">" used to shift letters the wrong way) ──
var thirty: list<string> = []
for i in range(30)
  thirty->add(printf('n%02d.txt', i))
endfor
var navdir: string = Fixture('nav', thirty)
Fresh(navdir)
Assert(!vproj#IsPagingActive(), 'nav fixture fits one page')
Assert(empty(filter(PaneLines(), (_, l) => l =~ '^a \+n26')), 'n26 has no letter in block 0')
vproj#ShiftNavForward()
Assert(vproj#GetNavOffset() == 1, '> moves to block 1')
Assert(!empty(filter(PaneLines(), (_, l) => l =~ '^a n26')), 'after >, n26 is lettered a')
vproj#ShiftNavForward()
Assert(vproj#GetNavOffset() == 0, '> wraps back to block 0')
vproj#ShiftNavBackward()
Assert(vproj#GetNavOffset() == 1, '< wraps to the last block')

# ── 4. Non-number width settings no longer break opening / mode switch ──
g:vproj_pane_width_default = '50'
g:vproj_pane_width_buf = '30'
var smalldir: string = Fixture('small', ['a.txt', 'b.txt', 'c.txt'])
var opened: bool = true
try
  Fresh(smalldir)
catch
  opened = false
endtry
Assert(opened && vproj#IsPaneVisible(), 'string g:vproj_pane_width_default: pane still opens')
var switched: bool = true
try
  vproj#SwitchMode('buf')
catch
  switched = false
endtry
Assert(switched && vproj#GetCurrentMode() == 'buf', 'string g:vproj_pane_width_buf: switch to buf completes')
unlet g:vproj_pane_width_default
unlet g:vproj_pane_width_buf

# ── 5. Session: second close no longer overwrites; :q saves; autocmds cleared ──
Fresh(smalldir)
vproj#SwitchMode('buf')
vproj#PaneClose()
Assert(index(SessionText(), 'mode=buf') >= 0, 'close saves mode=buf')
vproj#PaneClose()
Assert(index(SessionText(), 'mode=buf') >= 0, 'second close does not reset the session')
Assert(empty(filter(SessionText(), (_, l) => l =~ '^open=')), 'session no longer stores open=')

Fresh(smalldir)
vproj#SwitchMode('buf')
win_execute(PaneWid(), 'quit')
Assert(!vproj#IsPaneVisible(), ':q closes the pane')
Assert(index(SessionText(), 'mode=buf') >= 0, ':q in the pane saves the session')
Assert(!exists('#VprojPane#DirChanged') && !exists('#VprojPane#ColorScheme'), ':q clears the pane autocmds')

# ── 6. Restored width is clamped to the terminal ──
writefile(['mode=file', 'width=70'], $XDG_CACHE_HOME .. '/vproj/session')
set columns=80
Fresh(smalldir)
Assert(winwidth(PaneWid()) <= 60, 'session width 70 clamped on an 80-column screen')
vproj#PaneClose()
set columns=160

# ── 7. shortmess: user value and later changes survive ──
set shortmess=
Fresh(smalldir)
set shortmess+=c
vproj#PaneClose()
Assert(&shortmess == 'c', 'shortmess keeps the user change and loses only vproj''s S')
set shortmess&

# ── 8. Mode menu line is reachable and cycles the mode ──
Fresh(smalldir)
vproj#SelectFirst()
vproj#SelectPrev()
Assert(PaneCursorLine() == 1, 'Up from the first item lands on the mode menu')
vproj#SelectCurrent()
Assert(vproj#GetCurrentMode() == 'buf', 'Enter on the mode menu cycles file -> buf')
vproj#SwitchMode('file')
vproj#SelectFirst()
vproj#SelectPrev()
vproj#SelectPrev()
Assert(PaneCursorLine() == len(PaneLines()), 'Up from the menu wraps to the last item')

# ── 9. Total pages reset when paging turns off ──
Fresh(pagedir)
vproj#NextPage()
vproj#SwitchMode('buf')
Assert(!vproj#IsPagingActive() && vproj#GetTotalPages() == 1, 'total pages is 1 when paging is off')

# ── 10. Tab pages: closing removes the pane everywhere ──
Fresh(smalldir)
var pane_bnr: number = bufnr('VPROJ')
tabnew
vproj#PaneOpen()
vproj#PaneClose()
Assert(empty(win_findbuf(pane_bnr)), 'PaneClose closes the pane in every tab')
tabonly!

# ── 11. Esc at the save prompt keeps edits and the pane ──
Fresh(smalldir)
vproj#PaneClose()
execute 'edit ' .. fnameescape(smalldir .. '/a.txt')
setline(1, 'unsaved edit')
var edited_bnr: number = bufnr('%')
vproj#PaneOpen()
vproj#SwitchMode('file')
SelectName('b.txt')
var letter: string = PaneCursorText()[0]
test_feedinput("\<Esc>")
vproj#VprojKey(letter)
Assert(getbufvar(edited_bnr, '&modified') && getbufline(edited_bnr, 1) == ['unsaved edit'], 'Esc at save prompt keeps the unsaved edit')
Assert(vproj#IsPaneVisible(), 'Esc at save prompt keeps the pane open')
setbufvar(edited_bnr, '&modified', false)

# ── 12. Esc at CloseBuffer's save prompt keeps edits ──
Fresh(smalldir)
vproj#PaneClose()
execute 'edit ' .. fnameescape(smalldir .. '/c.txt')
setline(1, 'keep me')
var c_bnr: number = bufnr('%')
vproj#PaneOpen()
vproj#SwitchMode('buf')
SelectName('c.txt')
test_feedinput("\<Esc>")
vproj#CloseBuffer()
Assert(bufexists(c_bnr) && getbufline(c_bnr, 1) == ['keep me'], 'Esc at CloseBuffer prompt keeps the buffer')
setbufvar(c_bnr, '&modified', false)

# ── 13. Opening from a terminal origin does not kill the job ──
if has('terminal')
  Fresh(smalldir)
  vproj#PaneClose()
  var tbuf: number = term_start(['sleep', '30'], {curwin: true})
  vproj#PaneOpen()
  vproj#SwitchMode('file')
  SelectName('b.txt')
  vproj#SelectCurrent()
  Assert(job_status(term_getjob(tbuf)) == 'run', 'terminal job survives opening a file')
  Assert(!empty(filter(range(1, winnr('$')), (_, w) => fnamemodify(bufname(winbufnr(w)), ':t') == 'b.txt')), 'file opened in another window')
  job_stop(term_getjob(tbuf), 'kill')
  sleep 50m
  execute 'bwipeout! ' .. tbuf
endif

# ── 14. Pane alone: files open in a vertical split, not inside the pane column ──
Fresh(smalldir)
# Permanent pane: Enter on a file closes a temporary one (2026-11d audit), and
# this test is about the layout while the pane is open.
vproj#PaneClose()
vproj#PaneTogglePermanent()
vproj#SwitchMode('file')
win_gotoid(PaneWid())
only
SelectName('a.txt')
vproj#SelectCurrent()
Assert(winlayout()[0] == 'row', 'opening with the pane alone keeps a side-by-side layout')

# ── 15. Opening a buffer does not hijack the preview window ──
Fresh(smalldir)
vproj#PaneClose()
execute 'edit ' .. fnameescape(smalldir .. '/a.txt')
execute 'badd ' .. fnameescape(smalldir .. '/b.txt')
vproj#PaneTogglePermanent()  # permanent: Enter would close a temporary pane (and its preview)
vproj#TogglePreview()
var prev_bufs: list<string> = map(range(1, winnr('$')), (_, w) => bufname(winbufnr(w)))
vproj#SwitchMode('buf')
SelectName('b.txt')
vproj#SelectCurrent()
var after_bufs: list<string> = map(range(1, winnr('$')), (_, w) => bufname(winbufnr(w)))
Assert(index(after_bufs, '[Preview]') >= 0 || index(prev_bufs, '[Preview]') < 0, 'preview window not replaced by OpenBuffer')
vproj#TogglePreview()

# ── 16. Git ──
if executable('git')
  var repo: string = root .. '/repo'
  mkdir(repo, 'p')
  Git(repo, 'init -q')
  writefile(['one'], repo .. '/plain.txt')
  writefile(['two'], repo .. '/sp ace.txt')
  writefile(['three'], repo .. '/café.txt')
  writefile(['four'], repo .. '/bang!x.txt')
  writefile(['five'], repo .. '/staged.txt')
  writefile(['needle here'], repo .. '/hay.txt')
  Git(repo, 'add -A')
  Git(repo, 'commit -qm init')
  writefile(['one', 'more'], repo .. '/plain.txt')
  writefile(['two', 'more'], repo .. '/sp ace.txt')
  writefile(['three', 'more'], repo .. '/café.txt')
  writefile(['four', 'more'], repo .. '/bang!x.txt')
  writefile(['five', 'more'], repo .. '/staged.txt')
  Git(repo, 'add -- staged.txt')
  writefile(['new'], repo .. '/untracked.txt')
  Fresh(repo)

  # Quoted names used to be dropped from git status
  vproj#ToggleGitFilter()
  Assert(SelectName('sp ace.txt'), 'git filter lists "sp ace.txt"')
  Assert(SelectName('café.txt'), 'git filter lists "café.txt"')
  vproj#ToggleGitFilter()

  # \s used to "unstage" a worktree-only change
  SelectName('plain.txt')
  vproj#GitStageToggle()
  Assert(Git(repo, 'status --porcelain -- plain.txt') =~ '^M  ', '\s stages a worktree change')
  vproj#GitStageToggle()
  Assert(Git(repo, 'status --porcelain -- plain.txt') =~ '^ M ', '\s again unstages it')

  # \d used to abort on wrap=0, show nothing for " M", and fail for untracked
  var wins_before: number = winnr('$')
  SelectName('plain.txt')
  # A terminal-less Vim is 80x24 after any system() call and a diff split now
  # needs 41 columns in the edit window; a 20-wide pane leaves 59.
  vproj#SetPaneWidth(20)
  vproj#OpenDiffPreview()
  var diff_bnr: number = bufnr('vproj-diff:plain.txt')
  Assert(diff_bnr > 0 && !empty(filter(getbufline(diff_bnr, 1, '$'), (_, l) => l =~ '^+more')), '\d shows the unstaged diff')
  Assert(winnr('$') == wins_before + 1, '\d opens one new split and closes nothing')
  execute 'bwipeout! ' .. diff_bnr
  SelectName('untracked.txt')
  vproj#OpenDiffPreview()
  Assert(bufnr('vproj-diff:untracked.txt') > 0, '\d works for an untracked file')
  silent! execute 'bwipeout! ' .. bufnr('vproj-diff:untracked.txt')

  # A ! in the name used to be expanded by :read ! (shell injection)
  silent! !echo ';touch PWNED;echo '
  SelectName('bang!x.txt')
  vproj#OpenDiffPreview()
  Assert(!filereadable(repo .. '/PWNED') && !filereadable(saved_cwd .. '/PWNED'), '\d on a name with ! runs no extra command')
  Assert(bufnr('vproj-diff:bang!x.txt') > 0 || !empty(filter(map(getbufinfo(), (_, b) => b.name), (_, n) => n =~ 'vproj-diff:bang')), '\d on a name with ! shows the diff')

  # \a (blame) used to abort on wrap=0
  SelectName('hay.txt')
  # Close the diff splits left open above: the blame split needs 41 columns
  # in the edit window and a terminal-less Vim is only 80 wide.
  for b in getbufinfo()
    if b.name =~ 'vproj-diff:'
      execute 'silent! bwipeout! ' .. b.bufnr
    endif
  endfor
  vproj#GitBlame()
  Assert(!empty(filter(map(getbufinfo(), (_, b) => b.name), (_, n) => n =~ 'vproj-blame:hay.txt')), '\a opens a blame split')

  # \D on a staged-only change used to say "Reverted" and do nothing
  SelectName('staged.txt')
  test_feedinput("y\<CR>")
  vproj#DiscardChanges()
  var st_after: string = Git(repo, 'status --porcelain -- staged.txt')
  Assert(st_after == '', '\D discards a staged-only change (status now: ' .. string(st_after) .. ', msgs: ' .. string(split(execute(':3messages'), "\n")) .. ')')

  # * used to never return results
  test_feedinput("needle\<CR>")
  vproj#GrepSearch()
  var qf: list<dict<any>> = getqflist()
  Assert(len(qf) == 1 && fnamemodify(bufname(qf[0].bufnr), ':p') == repo .. '/hay.txt',
    '* finds the match with an absolute path (qf: ' .. string(map(copy(qf), (_, e) => bufname(e.bufnr) .. ':' .. e.lnum)) .. ', msgs: ' .. string(split(execute(':3messages'), "\n")) .. ')')
  vproj#SwitchMode('file')
endif

# ── 17. RenameProject ──
var projdir: string = Fixture('proj', ['src/x.c'])
writefile(['# keep me', 'Project Name: foo', 'Project Root:', 'Included Directories:', 'src/', 'Excluded Files:', '*.swp'], projdir .. '/foo.vproj')
writefile(['precious'], projdir .. '/bar.vproj.other')
Fresh(projdir)
vproj#SwitchMode('code')
Assert(PaneLines()[1] =~ 'foo', 'code mode finds foo.vproj')
# Unchanged name used to delete the project file
vproj#SelectFirst()
vproj#SelectPrev()
vproj#SelectNext()
test_feedinput("\<CR>")
vproj#RenameProject()
Assert(filereadable(projdir .. '/foo.vproj'), 'RenameProject with the same name keeps the file')
Assert(index(readfile(projdir .. '/foo.vproj'), '# keep me') >= 0, 'comments survive a save')
Assert(index(readfile(projdir .. '/foo.vproj'), 'Project Root:') >= 0 || index(readfile(projdir .. '/foo.vproj'), 'Project Root: ') >= 0, 'empty root is written back empty')
# Renaming onto an existing project file used to overwrite it silently
writefile(['Project Name: bar'], projdir .. '/bar.vproj')
test_feedinput("\<C-U>bar\<CR>n\<CR>")
vproj#RenameProject()
Assert(readfile(projdir .. '/bar.vproj') == ['Project Name: bar'], 'rename onto existing .vproj refused when answered n')
Assert(filereadable(projdir .. '/foo.vproj'), 'refused rename keeps the original file')
# Trailing-slash and glob entries used to never match
Assert(!empty(filter(PaneLines(), (_, l) => l =~ 'src' && l !~ '(src')), 'entry "src/" marks src as included')

# ── 18. Qfix opens the entry's own buffer, not a pattern match ──
var qdir: string = Fixture('qf', ['foo.c', 'sub/myfoo.c'])
writefile(['l1', 'l2', 'l3'], qdir .. '/foo.c')
Fresh(qdir)
vproj#PaneClose()
execute 'edit ' .. fnameescape(qdir .. '/sub/myfoo.c')
setqflist([{filename: qdir .. '/foo.c', lnum: 2, text: 'here'}])
vproj#PaneOpen()
vproj#SwitchMode('qfix')
vproj#SelectFirst()
vproj#SelectCurrent()
var opened_names: list<string> = map(range(1, winnr('$')), (_, w) => fnamemodify(bufname(winbufnr(w)), ':t'))
Assert(index(opened_names, 'foo.c') >= 0, 'qfix Enter opens foo.c, not sub/myfoo.c')

# ── 19. Help opens once, a second call reuses it ──
Fresh(smalldir)
vproj#ShowHelp()
var help_err: string = ''
try
  vproj#ShowHelp()
catch
  help_err = v:exception
endtry
var help_wins: number = len(filter(range(1, winnr('$')), (_, w) => bufname(winbufnr(w)) == '[vproj-help]'))
Assert(empty(help_err) && help_wins == 1, 'second ShowHelp reuses the window, no error')

# ── Cleanup ──
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
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

vim9script

# Regression tests for the second 2026-11 audit (222610f..f741582): defects
# the first round of fixes introduced. Each block pins
# one reproduced defect; the comment names what used to happen.
# Run: vim -N -u NONE -i NONE -S tests/integration/test_audit_2026_11b.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname(), so
# nothing outside /tmp is read or written. Prompts are answered with
# test_feedinput() queued before the call that prompts.

$XDG_CACHE_HOME = tempname()
set rtp+=src
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
# A fed <Esc> otherwise waits for a possible terminal key code forever.
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit2'
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

def Repo(name: string, files: list<string>): string
  var d: string = Fixture(name, files)
  Git(d, 'init -q')
  Git(d, 'add -A')
  Git(d, 'commit -qm init')
  return d
enddef

# Run whatever test_feedinput() left unread, so a prompt that (correctly)
# never appeared cannot swallow keys meant for a later test.
def DrainInput(): void
  feedkeys("\<Esc>", 'xt')
enddef

# ── 5. Letters come back after leaving a two-block list ──
# Used to: > then entering a directory left nav_offset at 1 with only one
# block, so no item had a letter and < could not fix it.
# Runs first: it needs 26+ items on one page, and once a test has run
# typeahead (DrainInput) this no-tty Vim falls back to 24 lines.
var nfiles: list<string> = ['sub/s0.txt', 'sub/s1.txt', 'sub/s2.txt']
for i in range(30)
  nfiles->add(printf('f%02d.txt', i))
endfor
var ndir: string = Fixture('navblocks', nfiles)
Fresh(ndir)
var nav_env: string = ' (lines=' .. &lines .. ' pane h=' .. winheight(PaneWid()) .. ' paging=' .. vproj#IsPagingActive() .. ')'
vproj#ShiftNavForward()
Assert(vproj#GetNavOffset() == 1, 'nav: > moves to the second block' .. nav_env)
Assert(SelectName('sub'), 'nav: sub/ is listed')
vproj#SelectCurrent()
Assert(vproj#GetNavOffset() == 0, 'nav: entering a one-block directory resets the block')
Assert(match(PaneLines(), '^a  s0\.txt') >= 0 || match(PaneLines(), '^a s0\.txt') >= 0, 'nav: the first item has letter a again')

# ── 1. The menu line on page 2 is not an item of page 1 ──
# Used to: Up from the first item on page 2 put the cursor on the menu line,
# and Delete / stage then acted on the last-but-one item of page 1.
var pfiles: list<string> = []
for i in range(60)
  pfiles->add(printf('f%02d.txt', i))
endfor
var prepo: string = Repo('menu_page2', pfiles)
for f in pfiles
  writefile(['changed'], prepo .. '/' .. f)
endfor
Fresh(prepo)
vproj#NextPage()
vproj#SelectFirst()
vproj#SelectPrev()
Assert(vproj#GetCurrentPage() == 1 && PaneCursorLine() == 1, 'page 2: Up from the first item lands on the menu line')
win_gotoid(PaneWid())
test_feedinput('y')
vproj#DeleteSelected()
DrainInput()
Assert(len(readdir(prepo, (n) => n =~ '^f\d\d\.txt$')) == 60, 'Delete on the page-2 menu line deletes nothing')
# Re-establish the state: a delete re-renders and may move the cursor.
Fresh(prepo)
vproj#NextPage()
vproj#SelectFirst()
vproj#SelectPrev()
Assert(vproj#GetCurrentPage() == 1 && PaneCursorLine() == 1, 'page 2: back on the menu line before staging')
vproj#GitStageToggle()
Assert(empty(Git(prepo, 'diff --cached --name-only')), 'stage on the page-2 menu line stages nothing')

# ── 2. Discard on a staged rename restores the source ──
# Used to: restore only the new path, which deleted it and left the source
# staged as deleted, while reporting "Reverted to HEAD".
var rrepo: string = Repo('rename', ['a.txt'])
writefile(['precious'], rrepo .. '/a.txt')
Git(rrepo, 'commit -qam precious')
Git(rrepo, 'mv a.txt c.txt')
writefile(['precious', 'edited'], rrepo .. '/c.txt')
Fresh(rrepo)
Assert(SelectName('c.txt'), 'rename: c.txt is listed')
win_gotoid(PaneWid())
test_feedinput("y\r")
vproj#DiscardChanges()
DrainInput()
Assert(filereadable(rrepo .. '/a.txt') && readfile(rrepo .. '/a.txt') == ['precious'], 'rename discard: a.txt is back with its HEAD content')
Assert(!filereadable(rrepo .. '/c.txt'), 'rename discard: c.txt is gone')
Assert(empty(Git(rrepo, 'status --porcelain')), 'rename discard: the worktree matches HEAD')

# ── 3. A list entry with [ ] matches the file of that exact name ──
# Used to: "[id].tsx" was read only as a glob, so it excluded itself and
# included i.tsx.
var bdir: string = Fixture('brackets', ['[id].tsx', 'i.tsx', '[slug]/page.tsx'])
writefile(['Project Name: p', 'Project Root: ', 'Included Directories:', '[slug]',
  'Included Files:', '[id].tsx', 'Excluded Directories:', 'Excluded Files:'], bdir .. '/p.vproj')
Fresh(bdir)
vproj#SwitchMode('code')
var blines: list<string> = PaneLines()
Assert(match(blines, '+ \[id\]\.tsx') >= 0, 'code mode: [id].tsx is included')
Assert(match(blines, '+ \[slug\]/') >= 0, 'code mode: [slug]/ is included')
Assert(match(blines, '- (i\.tsx)') >= 0, 'code mode: i.tsx is not included')

# ── 4. Reopening the pane reloads git status ──
# Used to: the wipeout cleared one of the two caches, so the reopened pane
# kept a stale empty status (the restored git filter showed no files).
var grepo: string = Repo('gitcache', ['a.txt', 'b.txt'])
writefile(['a2'], grepo .. '/a.txt')
Fresh(grepo)
vproj#ToggleGitFilter()
vproj#PaneClose()
writefile(['b2'], grepo .. '/b.txt')
vproj#PaneOpen()
var glines: list<string> = PaneLines()
Assert(vproj#IsGitFilterActive(), 'reopen: the git filter is restored')
Assert(match(glines, 'a\.txt') >= 0 && match(glines, 'b\.txt') >= 0, 'reopen: both modified files are listed')

# ── 6. A per-mode width of 0 keeps the current width ──
# Used to: 0 was clamped to the 20-column minimum, though the help says 0
# means "use default".
g:vproj_pane_width_file = 0
var wdir: string = Fixture('width', ['a.txt'])
Fresh(wdir)
Assert(vproj#GetPaneWidth() == 40, 'width 0: file mode keeps the 40-column default')
vproj#SwitchMode('buf')
vproj#SwitchMode('file')
Assert(vproj#GetPaneWidth() == 40, 'width 0: switching back to file mode keeps 40 columns')
unlet g:vproj_pane_width_file

# ── 7. The short file commands never replace another plugin's ──
# Used to: command! silently replaced vim-eunuch's :Delete and :Move.
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
for c in ['Copy', 'Delete', 'Rename', 'Move', 'VprojCopy', 'VprojDelete', 'VprojRename', 'VprojMove']
  execute 'silent! delcommand ' .. c
endfor
command! -bar Delete echo 'other plugin Delete'
command! -bar -nargs=1 Move echo 'other plugin Move'
unlet g:loaded_vproj
# rtp holds the relative "src" and the cwd is a fixture: source by path.
execute 'source ' .. fnameescape(saved_cwd .. '/src/plugin/vproj.vim')
Assert(execute('command Delete') =~ 'other plugin Delete', ':Delete defined by another plugin is kept')
Assert(execute('command Move') =~ 'other plugin Move', ':Move defined by another plugin is kept')
Assert(execute('command Copy') =~ 'vproj#CopySelected', ':Copy is defined when free')
Assert(exists(':VprojDelete') == 2 && exists(':VprojMove') == 2, ':VprojDelete and :VprojMove always exist')

# ── 8. Including a file that a pattern excludes does not write .vproj ──
# Used to: + added x.swp to Included Files, *.swp still won, and the file
# was rewritten for no visible change.
var xdir: string = Fixture('excl_glob', ['a.txt', 'x.swp'])
var xproj: list<string> = ['Project Name: p', 'Project Root: ', 'Included Directories:',
  'Included Files:', 'a.txt', 'Excluded Directories:', 'Excluded Files:', '*.swp']
writefile(xproj, xdir .. '/p.vproj')
Fresh(xdir)
vproj#SwitchMode('code')
Assert(SelectName('x.swp'), 'excl glob: x.swp is listed')
silent! vproj#IncludeItem()
Assert(readfile(xdir .. '/p.vproj') == xproj, 'excl glob: + on a pattern-excluded file leaves .vproj unchanged')
Assert(match(PaneLines(), '- (x\.swp)') >= 0, 'excl glob: x.swp is still shown excluded')

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

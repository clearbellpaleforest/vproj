vim9script

# Integration test: file operations in file mode —
# :Copy :Delete :Rename :Move and the pane's <Delete> key.
# Run: vim -N -u NONE -S tests/integration/test_file_ops.vim -c 'qall!'
#
# Each answer is queued with test_feedinput() before the call that prompts.
# A refusal must happen before any prompt, so those cases queue nothing:
# a prompt reached by mistake reads EOF from stdin and the run fails.

$XDG_CACHE_HOME = tempname()
# Absolute: a test that cd's away must still find autoload/ (the plugin no
# longer sources it at load).
execute 'set rtp+=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore

var failures: number = 0
var saved_cwd: string = getcwd()

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneLines(): list<string>
  var pbuf = bufnr('VPROJ')
  return pbuf <= 0 ? [] : getbufline(pbuf, 1, '$')
enddef

def PaneCursorText(): string
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  if empty(wins)
    return ''
  endif
  return get(getbufline(pbuf, line('.', wins[0])), 0, '')
enddef

def PaneLists(name: string): bool
  for l in PaneLines()
    if l =~ '\V' .. escape(name, '\') .. '\s' || l =~ '\V' .. escape(name, '\') .. '\$'
      return true
    endif
  endfor
  return false
enddef

# Move the pane selection onto the entry whose line shows `name`, looking
# on every page when the listing is paged.
def SelectName(name: string): bool
  var pages: number = vproj#IsPagingActive() ? vproj#GetTotalPages() : 1
  for _p in range(pages)
    vproj#SelectFirst()
    for _ in range(60)
      if PaneCursorText() =~ '\V\<' .. escape(name, '\') .. '\>'
        return true
      endif
      vproj#SelectNext()
    endfor
    vproj#NextPage()
  endfor
  return false
enddef

def Reopen(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  vproj#PaneOpen()
  vproj#SwitchMode('file')
enddef

# ── Fixture ──
var tmpdir: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_fileops'
mkdir(tmpdir .. '/sub', 'p')
mkdir(tmpdir .. '/other', 'p')
writefile(['alpha'], tmpdir .. '/alpha.txt')
writefile(['bravo'], tmpdir .. '/bravo.txt')
writefile(['make'], tmpdir .. '/Makefile')
writefile(['taken'], tmpdir .. '/taken.txt')
writefile(['in other'], tmpdir .. '/other/bravo.txt')
writefile(['dirty'], tmpdir .. '/dirty.txt')
writefile(['follow'], tmpdir .. '/follow.txt')
execute 'cd ' .. fnameescape(tmpdir)
Reopen()

# ── Surface ──
Assert(exists(':Copy') == 2, ':Copy command defined')
Assert(exists(':Delete') == 2, ':Delete command defined')
Assert(exists(':Rename') == 2, ':Rename command defined')
Assert(exists(':Move') == 2, ':Move command defined')
var pane_wid: number = win_findbuf(bufnr('VPROJ'))[0]
var del_map: string = ''
win_execute(pane_wid, 'del_map = maparg("<Delete>", "n")')
Assert(del_map =~ 'DeleteSelected', '<Delete> mapped in pane buffer')

# ── Copy ──
Assert(SelectName('alpha.txt'), 'select alpha.txt')
Copy
Assert(filereadable(tmpdir .. '/alpha_1.txt'), 'Copy creates alpha_1.txt')
Assert(readfile(tmpdir .. '/alpha_1.txt') == ['alpha'], 'Copy preserves contents')
Assert(PaneLists('alpha_1.txt'), 'pane lists alpha_1.txt after Copy')
Assert(SelectName('alpha.txt'), 'reselect alpha.txt')
Copy
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'second Copy skips taken name → alpha_2.txt')
Assert(readfile(tmpdir .. '/alpha.txt') == ['alpha'], 'Copy leaves source intact')
Assert(SelectName('Makefile'), 'select Makefile')
Copy
Assert(filereadable(tmpdir .. '/Makefile_1'), 'Copy of extensionless file → Makefile_1')

# ── Delete ──
Assert(SelectName('alpha_2.txt'), 'select alpha_2.txt')
test_feedinput('n')
Delete
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'Delete answered No keeps file')
test_feedinput("\<CR>")
Delete
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'Delete default (Enter) is No')
test_feedinput('y')
Delete
Assert(!filereadable(tmpdir .. '/alpha_2.txt'), 'Delete answered Yes removes file')
Assert(!PaneLists('alpha_2.txt'), 'pane drops alpha_2.txt after Delete')

# Delete key routes to the same operation
Assert(SelectName('Makefile_1'), 'select Makefile_1')
test_feedinput('y')
win_execute(pane_wid, 'call vproj#DeleteSelected()')
Assert(!filereadable(tmpdir .. '/Makefile_1'), 'DeleteSelected (Delete key) removes file')

# Unsaved buffer blocks Delete
execute 'badd ' .. fnameescape(tmpdir .. '/dirty.txt')
var dirty_bnr: number = bufnr(tmpdir .. '/dirty.txt')
bufload(dirty_bnr)
setbufline(dirty_bnr, 1, 'changed')
Assert(!!getbufvar(dirty_bnr, '&modified'), 'dirty.txt buffer is modified')
Assert(SelectName('dirty.txt'), 'select dirty.txt')
Delete
Assert(filereadable(tmpdir .. '/dirty.txt'), 'Delete refused while buffer has unsaved changes')
Assert(SelectName('dirty.txt'), 'select dirty.txt again')
Rename
Assert(filereadable(tmpdir .. '/dirty.txt'), 'Rename refused while buffer has unsaved changes')
setbufvar(dirty_bnr, '&modified', false)

# Directory refused
Assert(SelectName('sub'), 'select sub/')
Delete
Assert(isdirectory(tmpdir .. '/sub'), 'Delete refuses a directory')

# ── Rename ──
Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>charlie.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt') && !filereadable(tmpdir .. '/bravo.txt'), 'Rename bravo → charlie')
Assert(readfile(tmpdir .. '/charlie.txt') == ['bravo'], 'Rename keeps contents')
Assert(PaneLists('charlie.txt') && !PaneLists('bravo.txt'), 'pane shows new name only')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>taken.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt'), 'Rename onto existing name refused — source kept')
Assert(readfile(tmpdir .. '/taken.txt') == ['taken'], 'Rename onto existing name refused — target untouched')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>sub/x.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt') && !filereadable(tmpdir .. '/sub/x.txt'), 'Rename with / refused')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt'), 'Rename with empty answer cancels')

# Rename follows a buffer shown in a window
execute 'botright split ' .. fnameescape(tmpdir .. '/follow.txt')
var follow_wid: number = win_getid()
var old_follow_bnr: number = bufnr('%')
win_gotoid(pane_wid)
Assert(SelectName('follow.txt'), 'select follow.txt')
test_feedinput("\<C-U>followed.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/followed.txt'), 'Rename of open file succeeds')
Assert(fnamemodify(bufname(winbufnr(follow_wid)), ':t') == 'followed.txt', 'window follows renamed file')
Assert(!bufexists(old_follow_bnr), 'old buffer wiped after Rename')
win_execute(follow_wid, 'close')

# ── Move ──
Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/sub\<CR>")
Move
Assert(filereadable(tmpdir .. '/sub/charlie.txt') && !filereadable(tmpdir .. '/charlie.txt'), 'Move charlie.txt → sub/')
Assert(!PaneLists('charlie.txt'), 'pane drops moved file')

writefile(['bravo again'], tmpdir .. '/bravo.txt')
vproj#Refresh()
Assert(SelectName('bravo.txt'), 'select new bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/other/\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt'), 'Move onto existing file refused — source kept')
Assert(readfile(tmpdir .. '/other/bravo.txt') == ['in other'], 'Move onto existing file refused — target untouched')

Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/nope\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt'), 'Move to missing directory refused')

Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/taken.txt\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt') && readfile(tmpdir .. '/taken.txt') == ['taken'], 'Move to a file path refused')

# ── Audit 2026-11: symlinks, buffers, relative Move, selection ──
writefile(['target'], tmpdir .. '/target.txt')
system('ln -s target.txt ' .. shellescape(tmpdir .. '/rel.lnk'))
writefile(['scratch'], tmpdir .. '/src.txt')
mkdir(tmpdir .. '/real', 'p')
writefile(['in real'], tmpdir .. '/real/f.txt')
system('ln -s real ' .. shellescape(tmpdir .. '/lnk'))
vproj#Refresh()

# Copy of a symlink used to produce another symlink sharing the content
Assert(SelectName('rel.lnk'), 'select rel.lnk')
Copy
Assert(getftype(tmpdir .. '/rel_1.lnk') == 'file', 'Copy of a symlink makes a regular file')
Assert(readfile(tmpdir .. '/rel_1.lnk') == ['target'], 'Copy of a symlink copies the target content')

# Moving a relative symlink used to leave it dangling and unlisted
Assert(SelectName('rel.lnk'), 'select rel.lnk again')
test_feedinput("\<C-U>" .. tmpdir .. "/sub\<CR>")
Move
Assert(getftype(tmpdir .. '/rel.lnk') == 'link' && getftype(tmpdir .. '/sub/rel.lnk') == '', 'Move refuses a symlink, nothing moved')

# Rename onto a name held by an unwritten buffer used to redirect the window
execute 'badd ' .. fnameescape(tmpdir .. '/ghost.txt')
Assert(SelectName('src.txt'), 'select src.txt')
test_feedinput("\<C-U>ghost.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/src.txt') && !filereadable(tmpdir .. '/ghost.txt'), 'Rename onto a buffer-held name refused')
execute 'bwipeout! ' .. bufnr(tmpdir .. '/ghost.txt')

# A relative Move answer used to resolve against Vim's cwd, not the pane's
# directory. Entering a subdirectory in the pane does not change the cwd.
mkdir(tmpdir .. '/deep/inner', 'p')
writefile(['mv'], tmpdir .. '/deep/mv.txt')
vproj#Refresh()
Assert(SelectName('deep'), 'select deep/')
vproj#SelectCurrent()
Assert(SelectName('mv.txt'), 'select deep/mv.txt (cwd is still the parent)')
test_feedinput("\<C-U>inner\<CR>")
Move
Assert(filereadable(tmpdir .. '/deep/inner/mv.txt'), 'relative Move answer is relative to the file''s directory')
vproj#NavigateUp()

# Unsaved changes reached through a symlinked directory used to be missed
execute 'badd ' .. fnameescape(tmpdir .. '/real/f.txt')
var real_bnr: number = bufnr(tmpdir .. '/real/f.txt')
bufload(real_bnr)
setbufline(real_bnr, 1, 'unsaved')
vproj#Refresh()
Assert(SelectName('lnk'), 'select lnk/')
vproj#SelectCurrent()
Assert(SelectName('f.txt'), 'select f.txt via lnk/')
Delete
Assert(filereadable(tmpdir .. '/real/f.txt'), 'Delete refused for a modified buffer reached via a symlinked dir')
setbufvar(real_bnr, '&modified', false)
execute 'bwipeout! ' .. real_bnr
vproj#NavigateUp()

# After Rename the selection used to stay on the old line (another file)
Assert(SelectName('Makefile'), 'select Makefile')
test_feedinput("\<C-U>zz_last\<CR>")
Rename
Assert(PaneCursorText() =~ 'zz_last', 'selection follows the renamed file')

vproj#SwitchMode('buf')
var before: list<string> = sort(readdir(tmpdir))
Copy
Delete
Rename
Move
Assert(sort(readdir(tmpdir)) == before, 'commands do nothing outside file mode')
vproj#SwitchMode('file')

# ── Pane closed guard ──
vproj#PaneClose()
Copy
Assert(sort(readdir(tmpdir)) == before, 'Copy does nothing with pane closed')

# ── Cleanup ──
execute 'cd ' .. fnameescape(saved_cwd)
delete(tmpdir, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!

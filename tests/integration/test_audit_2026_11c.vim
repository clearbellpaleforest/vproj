vim9script

# Regression tests for the third 2026-11 audit (HEAD 9884e89): defects the first
# two rounds missed. Each block pins one reproduced defect; the comment names
# what used to happen.
# Run: vim -N -u NONE -i NONE -S tests/integration/test_audit_2026_11c.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname(). Prompts
# are answered with test_feedinput() queued before the call that prompts.

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit3'
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

def PaneStatusline(): string
  return getbufvar(bufnr('VPROJ'), '&statusline', '')
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

# readfile() throws on a missing file; on the old code a test of the wrong
# behaviour must fail, not abort the whole script.
def Lines(path: string): list<string>
  return filereadable(path) ? readfile(path) : ['<missing>']
enddef

def Porcelain(dir: string, path: string): string
  return trim(Git(dir, 'status --porcelain -- ' .. shellescape(path)), "\n", 2)
enddef

# Load the pane's git status cache, as a session does long before the user
# presses \D: the git filter reads it. Without this the "stale cache" tests
# would pass on the old code because nothing was cached yet.
def LoadStatusCache(): void
  vproj#ToggleGitFilter()
  vproj#ToggleGitFilter()
enddef

# Run whatever test_feedinput() left unread, so a prompt that (correctly)
# never appeared cannot swallow keys meant for a later test.
def DrainInput(): void
  feedkeys("\<Esc>", 'xt')
enddef

# ── 1. Discard trusts the live status, not the cache ──
# Used to: x.txt untracked when the pane loaded, then committed and edited
# outside Vim. The cache still said '??', so \D asked "Delete untracked file"
# and answering y called delete() on a tracked file with uncommitted work.
var d1: string = Repo('stale_discard', ['base.txt'])
writefile(['x.txt'], d1 .. '/x.txt')
Fresh(d1)
LoadStatusCache()
Assert(SelectName('x.txt'), 'stale discard: x.txt is listed')
Git(d1, 'add x.txt')
Git(d1, 'commit -qm addx')
writefile(['x.txt', 'uncommitted edit'], d1 .. '/x.txt')
test_feedinput("y\<CR>")
vproj#DiscardChanges()
DrainInput()
Assert(filereadable(d1 .. '/x.txt'), 'stale discard: the tracked file was not deleted')
Assert(Lines(d1 .. '/x.txt') == ['x.txt'], 'stale discard: it was restored to HEAD, not removed')

# ── 2. Stage toggle acts on the live status ──
# Used to: y.txt untracked when loaded, staged outside Vim. \s still saw '??',
# ran `git add -A` (a no-op) and reported "Staged" instead of unstaging.
var d2: string = Repo('stale_stage', ['base.txt'])
writefile(['y.txt'], d2 .. '/y.txt')
Fresh(d2)
LoadStatusCache()
Assert(SelectName('y.txt'), 'stale stage: y.txt is listed')
Git(d2, 'add y.txt')
Assert(Porcelain(d2, 'y.txt') =~ '^A ', 'stale stage: precondition, y.txt is staged outside Vim')
vproj#GitStageToggle()
Assert(Porcelain(d2, 'y.txt') == '?? y.txt', 'stale stage: \s unstaged it, got "' .. Porcelain(d2, 'y.txt') .. '"')

# ── 3. Discarding an added file with later edits (AM) ──
# Used to: `git rm --cached` refuses when the index differs from both the
# file and HEAD, so the prompt promised "Unstage new file (the file is kept)"
# and nothing happened.
var d3: string = Repo('am_discard', ['base.txt'])
writefile(['n2'], d3 .. '/n2.txt')
Git(d3, 'add n2.txt')
writefile(['n2', 'later edit'], d3 .. '/n2.txt')
Fresh(d3)
Assert(SelectName('n2.txt'), 'AM discard: n2.txt is listed')
Assert(Porcelain(d3, 'n2.txt') =~ '^AM', 'AM discard: precondition, status is AM')
test_feedinput("y\<CR>")
vproj#DiscardChanges()
DrainInput()
Assert(Porcelain(d3, 'n2.txt') == '?? n2.txt', 'AM discard: unstaged, got "' .. Porcelain(d3, 'n2.txt') .. '"')
Assert(Lines(d3 .. '/n2.txt') == ['n2', 'later edit'], 'AM discard: the file and its edits are kept')

# ── 4. Git follows the directory the pane shows, not getcwd() ──
# Used to: browsing into a nested repo does not chdir, so GitRoot named the
# outer repo. \s said "No git changes" for a change in the inner one, and \z
# stashed the OUTER repo's work.
var d4: string = Repo('nested_outer', ['a.txt'])
var d4in: string = d4 .. '/inner'
mkdir(d4in, 'p')
writefile(['b.txt'], d4in .. '/b.txt')
Git(d4in, 'init -q')
Git(d4in, 'add -A')
Git(d4in, 'commit -qm init')
writefile(['a.txt', 'outer edit'], d4 .. '/a.txt')
writefile(['b.txt', 'inner edit'], d4in .. '/b.txt')
Fresh(d4)
Assert(SelectName('inner'), 'nested: inner/ is listed')
vproj#SelectCurrent()
Assert(getcwd() == d4, 'nested: precondition, navigating in did not chdir')
Assert(SelectName('b.txt'), 'nested: b.txt is listed inside inner/')
vproj#GitStageToggle()
Assert(Porcelain(d4in, 'b.txt') =~ '^M ', 'nested: \s staged b.txt in the INNER repo, got "' .. Porcelain(d4in, 'b.txt') .. '"')
writefile(['b.txt', 'inner edit 2'], d4in .. '/b.txt')
test_feedinput("\<CR>")
vproj#GitStashPush()
DrainInput()
Assert(Lines(d4 .. '/a.txt') == ['a.txt', 'outer edit'], 'nested: \z left the OUTER repo alone')
Assert(Lines(d4in .. '/b.txt') == ['b.txt'], 'nested: \z stashed the INNER repo')

# ── 5. A window-local :lcd elsewhere does not move the pane ──
# Used to: the scope guard read v:event, which is empty inside DirChanged on
# this Vim, so it never fired and the pane re-rendered into the edit window's
# directory.
var d5: string = Fixture('dirchg_pane', ['p5.txt'])
var d5o: string = Fixture('dirchg_other', ['o5.txt'])
Fresh(d5)
Assert(match(PaneLines(), 'p5\.txt') >= 0, 'dirchg: precondition, the pane lists p5.txt')
var edit_wid: number = 0
for wnr in range(1, winnr('$'))
  if winbufnr(wnr) != bufnr('VPROJ')
    edit_wid = win_getid(wnr)
  endif
endfor
Assert(edit_wid != 0, 'dirchg: there is an edit window')
win_execute(edit_wid, 'lcd ' .. fnameescape(d5o))
Assert(match(PaneLines(), 'p5\.txt') >= 0 && match(PaneLines(), 'o5\.txt') < 0, 'dirchg: the pane still lists p5.txt, not o5.txt, after :lcd in an edit window: ' .. string(PaneLines()))

# ── 6. The cursor highlight follows a clamped selection ──
# Used to: Render placed the highlight before clamping selected_line, so
# after the last file was deleted the match stayed on the old line number.
var d6: string = Fixture('clamp', ['c1.txt', 'c2.txt', 'c3.txt', 'c4.txt', 'c5.txt', 'c6.txt'])
Fresh(d6)
vproj#SelectLast()
delete(d6 .. '/c6.txt')
vproj#Refresh()
var hl_line: number = -1
for m in getmatches(PaneWid())
  if m.group == 'VprojCursorLine'
    hl_line = str2nr(matchstr(m.pattern, '\\%\zs\d\+\zel'))
  endif
endfor
Assert(hl_line == PaneCursorLine(), 'clamp: highlight is on line ' .. PaneCursorLine() .. ', got ' .. hl_line)

# ── 7. Ctrl-J enters a directory the filter shows ──
# Used to: it walked every item, so with the filter "zfile" (showing only
# zfile.txt) it entered the hidden directory adir/.
var d7: string = Fixture('ctrlj', ['adir/in.txt', 'zdir/in.txt', 'zfile.txt'])
Fresh(d7)
test_feedinput("zfile\<CR>")
vproj#PromptFilter()
vproj#NavigateIntoFirstDir()
Assert(match(PaneLines(), 'zfile\.txt') >= 0, 'ctrl-j: the pane still lists zfile.txt, so no hidden directory was entered: ' .. string(PaneLines()))

# ── 8. A detached HEAD is named, not called "untracked" ──
# A short path: the statusline is cut to the pane width, so under a long
# TMPDIR the git part would be pushed off the end.
var d8: string = '/tmp/vpd' .. getpid()
mkdir(d8, 'p')
writefile(['t.txt'], d8 .. '/t.txt')
Git(d8, 'init -q')
Git(d8, 'add -A')
Git(d8, 'commit -qm init')
Git(d8, 'checkout -q --detach')
writefile(['Project Name: det', 'Project Root: ' .. d8, 'Included Directories:', 'Included Files:',
  't.txt', 'Excluded Directories:', '.git', 'Excluded Files:'], d8 .. '/det.vproj')
Fresh(d8)
vproj#SwitchMode('code')
Assert(PaneStatusline() =~ '(detached ' && PaneStatusline() !~ 'untracked', 'detached: statusline names the commit, got "' .. PaneStatusline() .. '"')
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
execute 'cd ' .. fnameescape(saved_cwd)
delete(d8, 'rf')

# ── 9. A second diff of the same file gets its own buffer name ──
# Used to: `file vproj-diff:NAME` failed with E95 (swallowed) and the second
# split was an unnamed buffer.
var d9: string = Repo('twodiff', ['z.txt'])
writefile(['z.txt', 'changed'], d9 .. '/z.txt')
Fresh(d9)
Assert(SelectName('z.txt'), 'twodiff: z.txt is listed')
vproj#OpenDiffPreview()
vproj#OpenDiffPreview()
Assert(bufexists('vproj-diff:z.txt') && bufexists('vproj-diff:z.txt (2)'), 'twodiff: both diff buffers are named')

# ── 10. A fresh preview shows the file, and an odd extension does not blank it ──
# Used to: the first P left the preview empty until the cursor moved (it
# updated before preview_active was set); and a file "b.x y" set &filetype to
# an invalid name (E474) and showed "(no preview)".
var d10: string = Fixture('prev', ['p1.txt', 'b.x y'])
Fresh(d10)
Assert(SelectName('p1.txt'), 'preview: p1.txt is listed')
vproj#TogglePreview()
var pv: number = bufnr('\[Preview\]')
Assert(pv > 0 && index(getbufline(pv, 1, '$'), 'p1.txt') >= 0, 'preview: the first toggle already shows the file text')
Assert(SelectName('b.x y'), 'preview: "b.x y" is listed')
Assert(index(getbufline(pv, 1, '$'), 'b.x y') >= 0, 'preview: a file with an invalid filetype extension still previews')

# ── 11. Files inside an untracked directory have a status ──
# Used to: `git status` lists only `?? ud/`, so a file inside got "No git
# changes" for \s, \d and \D.
var d11: string = Repo('untracked_dir', ['base.txt'])
mkdir(d11 .. '/ud', 'p')
writefile(['f'], d11 .. '/ud/f.txt')
Fresh(d11 .. '/ud')
Assert(SelectName('f.txt'), 'untracked dir: f.txt is listed')
vproj#GitStageToggle()
Assert(Porcelain(d11, 'ud/f.txt') =~ '^A ', 'untracked dir: \s staged the file, got "' .. Porcelain(d11, 'ud/f.txt') .. '"')

# ── 12. An inline value on a list header is an entry, not lost ──
# Used to: "Excluded Files: *.swp" parsed to an empty list, and the next
# write (any + or -) erased the line from the file.
var d12: string = Fixture('inline_hdr', ['src/x.txt', 'b.txt'])
writefile(['Project Name: inl', 'Excluded Files: *.swp', 'Included Directories: src', 'Included Files:', 'README.md'], d12 .. '/inl.vproj')
var p12: dict<any> = vproj#ParseVprojFile(d12 .. '/inl.vproj')
Assert(p12.excluded_files == ['*.swp'], 'inline header: Excluded Files value parsed, got ' .. string(p12.excluded_files))
Assert(len(p12.included_dirs) == 1 && p12.included_dirs[0] =~ '^src', 'inline header: Included Directories value parsed, got ' .. string(p12.included_dirs))
Fresh(d12)
vproj#SwitchMode('code')
Assert(SelectName('b.txt'), 'inline header: b.txt is listed in code mode')
silent! vproj#IncludeItem()
var w12: list<string> = Lines(d12 .. '/inl.vproj')
Assert(index(w12, '*.swp') >= 0, 'inline header: the next write keeps *.swp, file is ' .. string(w12))

# ── 13. Writing a symlinked or private .vproj keeps the link and the mode ──
# Used to: the tmp+rename replaced the symlink with a regular file and reset
# 0600 to 0644, leaving the real file stale.
var d13: string = Fixture('symlink_proj', ['b.txt'])
var r13: string = Fixture('symlink_real', [])
writefile(['Project Name: sl', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:'], r13 .. '/p.vproj')
setfperm(r13 .. '/p.vproj', 'rw-------')
system('ln -s ' .. shellescape(r13 .. '/p.vproj') .. ' ' .. shellescape(d13 .. '/.vproj'))
Fresh(d13)
vproj#SwitchMode('code')
Assert(SelectName('b.txt'), 'symlinked .vproj: b.txt is listed')
silent! vproj#IncludeItem()
Assert(getftype(d13 .. '/.vproj') == 'link', 'symlinked .vproj: still a symlink, is ' .. getftype(d13 .. '/.vproj'))
Assert(index(Lines(r13 .. '/p.vproj'), 'b.txt') >= 0, 'symlinked .vproj: the real file was updated')
Assert(getfperm(r13 .. '/p.vproj') == 'rw-------', 'symlinked .vproj: mode kept, is ' .. getfperm(r13 .. '/p.vproj'))

# ── 14. A symlinked name.vproj is found like a symlinked .vproj ──
# Used to: the wildcard search rejected it (getftype() says 'link'), so code
# mode reported "No project" although the exact .vproj name worked.
var d14: string = Fixture('symlink_named', ['b.txt'])
var r14: string = Fixture('symlink_named_real', [])
writefile(['Project Name: named', 'Included Directories:', 'Included Files:', 'Excluded Directories:', 'Excluded Files:'], r14 .. '/r.vproj')
system('ln -s ' .. shellescape(r14 .. '/r.vproj') .. ' ' .. shellescape(d14 .. '/p.vproj'))
Fresh(d14)
vproj#SwitchMode('code')
Assert(match(PaneLines(), 'no project found') < 0, 'symlinked p.vproj: code mode finds the project: ' .. string(PaneLines()[0 : 3]))

# ── 15. A session-save failure is reported when the pane is closed normally ──
# Used to: the save runs from the wipeout autocmd inside win_execute() during
# PaneClose, which discards echom output, so a failed save (here: the cache
# dir cannot be created) was silent for Esc / :VprojClose / Tab.
var d15: string = Fixture('sess_err', ['s.txt'])
var saved_xdg: string = $XDG_CACHE_HOME
writefile(['not a directory'], root .. '/xdg_is_a_file')
$XDG_CACHE_HOME = root .. '/xdg_is_a_file'
g:vproj_save_session = 1
Fresh(d15)
silent! messages clear
vproj#PaneClose()
Assert(execute('messages') =~ 'could not create session directory', 'session error: PaneClose reports a failed session save')
unlet g:vproj_save_session
$XDG_CACHE_HOME = saved_xdg

# ── 18. Session saving is opt-in (CLAUDE.md rule 5: no automatic file creation) ──
# Used to: every pane close created $XDG_CACHE_HOME/vproj/session without the
# user asking. Now nothing is written unless g:vproj_save_session = 1.
var d18: string = Fixture('sess_optin', ['o.txt'])
var cache18: string = root .. '/cache18'
$XDG_CACHE_HOME = cache18
Fresh(d18)
vproj#PaneClose()
Assert(!isdirectory(cache18 .. '/vproj') && !filereadable(cache18 .. '/vproj/session'), 'session opt-in: default writes no session file and creates no directory')
g:vproj_save_session = 0
Fresh(d18)
vproj#PaneClose()
Assert(!filereadable(cache18 .. '/vproj/session'), 'session opt-in: an explicit 0 writes nothing')
g:vproj_save_session = 'yes'
Fresh(d18)
vproj#PaneClose()
Assert(!filereadable(cache18 .. '/vproj/session'), 'session opt-in: a malformed value (string) writes nothing and does not throw')
g:vproj_save_session = 1
Fresh(d18)
vproj#PaneClose()
Assert(filereadable(cache18 .. '/vproj/session'), 'session opt-in: g:vproj_save_session = 1 writes the session file')
unlet g:vproj_save_session
$XDG_CACHE_HOME = saved_xdg

# ── 16. Files inside a NESTED repo do not inherit '??' from the parent ──
# Introduced and caught during this audit: git reports a nested repo as
# `?? sub/`, and treating every file under an untracked directory as
# untracked made \D offer to delete (and delete) a tracked, modified file of
# the inner repo, losing the edit.
var d16: string = Repo('nest_par', ['top.txt'])
var d16in: string = d16 .. '/sub'
mkdir(d16in, 'p')
writefile(['inner.txt'], d16in .. '/inner.txt')
Git(d16in, 'init -q')
Git(d16in, 'add -A')
Git(d16in, 'commit -qm init')
writefile(['inner.txt', 'uncommitted edit'], d16in .. '/inner.txt')
Fresh(d16)
vproj#ToggleTreeView()
Assert(SelectName('sub'), 'nested untracked: sub/ is listed in the tree')
vproj#SelectCurrent()
if SelectName('inner.txt')
  test_feedinput("y\<CR>")
  vproj#DiscardChanges()
  DrainInput()
endif
Assert(Lines(d16in .. '/inner.txt') == ['inner.txt', 'uncommitted edit'], 'nested untracked: the inner repo file was not deleted or reverted by the outer repo, got ' .. string(Lines(d16in .. '/inner.txt')))

# ── 17. Code mode: a long NOT-included name stays inside the pane ──
# Used to: the name was cut to the full name width and then wrapped in "(" and
# ")", so a long excluded name ran two cells past the pane (ASCII too).
var long_ascii: string = repeat('a', 70) .. '.txt'
var long_wide: string = repeat('日', 30) .. '.txt'
var d17: string = Fixture('code_long', [long_ascii, long_wide, 'short.txt'])
writefile(['Project Name: lg', 'Included Directories:', 'Included Files:', 'short.txt', 'Excluded Directories:', 'Excluded Files:'], d17 .. '/lg.vproj')
Fresh(d17)
vproj#SwitchMode('code')
var wide17: number = 0
for ln in PaneLines()
  wide17 = max([wide17, strwidth(ln)])
endfor
Assert(wide17 <= vproj#GetPaneWidth(), 'code long name: widest pane row is ' .. wide17 .. ', pane is ' .. vproj#GetPaneWidth())
Assert(match(PaneLines(), '(a\{10,}') >= 0, 'code long name: the excluded name is still shown in parentheses')

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

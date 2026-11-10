vim9script

# Regression tests for two git defects:
#  1. GrepSearch ran plain `git grep` (tracked files only) though it promises
#     to search the whole worktree: a match in an untracked file was missed.
#  2. GitNoPrompt only disabled GIT_TERMINAL_PROMPT, so an ssh remote that
#     wanted a passphrase / host-key confirmation read /dev/tty and hung Vim.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11d_git.vim -c 'cquit!'

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var saved_path: string = $PATH
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_gitminor'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def Git(dir: string, args: string): string
  return system('git -C ' .. shellescape(dir) .. ' -c user.email=t@t -c user.name=t ' .. args .. ' 2>&1')
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

def QfFiles(): list<string>
  return mapnew(getqflist(), (_, e) => fnamemodify(bufname(e.bufnr), ':t'))
enddef

def Grep(pattern: string): list<string>
  setqflist([], 'f')
  test_feedinput(pattern .. "\<CR>")
  vproj#GrepSearch()
  return QfFiles()
enddef

# ── 1. GrepSearch covers untracked, non-ignored files ──
var g: string = root .. '/grep'
mkdir(g, 'p')
Git(g, 'init -q')
writefile(['needle_tracked here'], g .. '/tracked.txt')
writefile(['ignored.txt'], g .. '/.gitignore')
Git(g, 'add -A')
Git(g, 'commit -qm init')
writefile(['needle_untracked here'], g .. '/fresh.txt')
writefile(['needle_ignored here'], g .. '/ignored.txt')
Fresh(g)
Assert(Grep('needle_tracked') == ['tracked.txt'], 'grep: tracked match still found: ' .. string(QfFiles()))
Assert(Grep('needle_untracked') == ['fresh.txt'], 'grep: untracked file match found: ' .. string(QfFiles()))
Assert(Grep('needle_ignored') == [], 'grep: .gitignore d file stays excluded: ' .. string(QfFiles()))

# Not in a repo: the --no-index path still works.
var plain: string = root .. '/plain'
mkdir(plain, 'p')
writefile(['needle_plain here'], plain .. '/p.txt')
Fresh(plain)
Assert(Grep('needle_plain') == ['p.txt'], 'grep: outside a repo still finds files: ' .. string(QfFiles()))

# ── 2. GitNoPrompt makes ssh non-interactive unless the user configured it ──
var bin: string = root .. '/bin'
mkdir(bin, 'p')
var log: string = root .. '/ssh.log'
var script: list<string> = [
  '#!/bin/sh',
  'echo "ARGS: $*" >> ' .. log,
  'echo "ENV_SSH_COMMAND: ${GIT_SSH_COMMAND-<unset>}" >> ' .. log,
  'exit 255',
]
writefile(script, bin .. '/ssh')
setfperm(bin .. '/ssh', 'rwxr-xr-x')
writefile(script, bin .. '/userssh')
setfperm(bin .. '/userssh', 'rwxr-xr-x')

var r: string = root .. '/remote'
mkdir(r, 'p')
Git(r, 'init -q -b main')
writefile(['x'], r .. '/x.txt')
Git(r, 'add -A')
Git(r, 'commit -qm init')
Git(r, 'remote add origin ssh://nohost.invalid/x')
Git(r, 'config branch.main.remote origin')
Git(r, 'config branch.main.merge refs/heads/main')

def Reset(): void
  delete(log)
  setenv('GIT_SSH_COMMAND', v:null)
  setenv('GIT_SSH', v:null)
enddef

def LogText(): string
  return filereadable(log) ? join(readfile(log), "\n") : '<no ssh call>'
enddef

$PATH = bin .. ':' .. saved_path
Fresh(r)

# Default: neither variable set -> ssh sees BatchMode=yes; env restored to unset.
Reset()
vproj#GitPush()
Assert(LogText() =~ 'BatchMode=yes', 'push: ssh ran with BatchMode=yes: ' .. LogText())
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'push: GIT_SSH_COMMAND restored to unset')
Reset()
vproj#GitPull()
Assert(LogText() =~ 'BatchMode=yes', 'pull: ssh ran with BatchMode=yes: ' .. LogText())
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'pull: GIT_SSH_COMMAND restored to unset')

# User set GIT_SSH: left alone (no override, GIT_SSH_COMMAND not introduced).
Reset()
setenv('GIT_SSH', bin .. '/userssh')
vproj#GitPush()
Assert(LogText() !~ 'BatchMode', 'GIT_SSH user: our override not injected: ' .. LogText())
Assert(LogText() =~ 'ENV_SSH_COMMAND: <unset>', 'GIT_SSH user: GIT_SSH_COMMAND not set for ssh: ' .. LogText())
Assert(getenv('GIT_SSH') == bin .. '/userssh', 'GIT_SSH user: value preserved')
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'GIT_SSH user: GIT_SSH_COMMAND still unset after')

# User set GIT_SSH_COMMAND: used as-is, restored exactly.
Reset()
var mine: string = bin .. '/userssh -o Marker=mine'
setenv('GIT_SSH_COMMAND', mine)
vproj#GitPush()
Assert(LogText() =~ 'Marker=mine' && LogText() !~ 'BatchMode', 'GIT_SSH_COMMAND user: kept, not clobbered: ' .. LogText())
Assert(getenv('GIT_SSH_COMMAND') == mine, 'GIT_SSH_COMMAND user: restored exactly')
Reset()

# ── Cleanup ──
$PATH = saved_path
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

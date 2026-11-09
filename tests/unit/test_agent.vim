vim9script
# Test suite for vproj agent module (autoload/vproj/agent.vim)
# Run (isolate HOME; the agent CLI is a fake on PATH, no real agent runs):
#   HOME=$T XDG_CACHE_HOME=$T/cache vim -N -u NONE -i NONE --not-a-term \
#     -S tests/unit/test_agent.vim </dev/null
# Exits with :qa! when every assertion passes, :cquit! otherwise.
# Results also go to $VPROJ_TEST_RESULT when that is set.

# Isolate the cache dir before anything is loaded.
$XDG_CACHE_HOME = tempname()
set nomore
set hidden

g:failures = 0
var log: list<string> = []

def Assert(cond: bool, msg: string): void
  if cond
    log->add('PASS: ' .. msg)
  else
    log->add('FAIL: ' .. msg)
    g:failures += 1
  endif
enddef

def RunSection(name: string, F: func(): void): void
  try
    F()
  catch
    Assert(false, name .. ' threw: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
enddef

def WaitFor(F: func(): bool, ms: number = 5000): bool
  var start: list<any> = reltime()
  while reltimefloat(reltime(start)) * 1000 < ms
    if F()
      return true
    endif
    sleep 20m
  endwhile
  return F()
enddef

var repo: string = expand('<sfile>:p:h:h:h')
execute 'source' repo .. '/src/autoload/vproj.vim'
execute 'source' repo .. '/src/autoload/vproj/agent.vim'

log->add('=== test_agent.vim ===')

# ── Fake agent CLIs: every name DetectAgent() tries, first on PATH ──
var fake_dir: string = tempname()
mkdir(fake_dir, 'p')
var fake_lines: list<string> = [
  '#!/bin/bash',
  'f="${VPROJ_AGENT_CTX_FILE:-}"',
  '{ echo "ctxfile=$f"; stat -c %a "$f"; echo "inline=${VPROJ_AGENT_CTX:-unset}"; } > "$FAKE_DIR/agent.meta"',
  'cp "$f" "$FAKE_DIR/agent.ctx"',
  'echo FAKE-AGENT-READY',
  'IFS= read -r line',
]
for name in ['claudex', 'aether', 'openheim', 'claude', 'codex']
  writefile(fake_lines, fake_dir .. '/' .. name)
  setfperm(fake_dir .. '/' .. name, 'rwx------')
endfor
$FAKE_DIR = fake_dir
$PATH = fake_dir .. ':' .. $PATH

# A file whose ±50-line context is far larger than one environment string
# may be (MAX_ARG_STRLEN = 128 KiB) — the old VPROJ_AGENT_CTX hit E2BIG.
var src_file: string = tempname() .. '_big.txt'
writefile(map(range(1, 300), (_, n) => n .. ' ' .. repeat('x', 5000)), src_file)

def SectionOpen(): void
  execute 'edit ' .. fnameescape(src_file)
  cursor(150, 1)
  only
  var wins_before: number = winnr('$')
  var bufs_before: number = len(getbufinfo())

  vproj#agent#AgentOpen()
  var termbuf: number = bufnr('%')
  Assert(getbufvar(termbuf, '&buftype') == 'terminal', 'AgentOpen: current window is the terminal')
  Assert(winnr('$') == wins_before + 1, 'AgentOpen: exactly one new window (' .. winnr('$') .. ')')
  Assert(winheight(0) == 20, 'AgentOpen: terminal window is 20 lines (' .. winheight(0) .. ')')
  Assert(len(getbufinfo()) == bufs_before + 1, 'AgentOpen: no orphan empty buffer')
  Assert(empty(maparg('<Esc>', 't')), 'AgentOpen: no Esc mapping stolen from the agent')
  Assert(stridx(execute('messages'), 'running') >= 0, 'AgentOpen: reports running')

  var meta: string = fake_dir .. '/agent.meta'
  Assert(WaitFor(() => filereadable(meta) && len(readfile(meta)) >= 3), 'AgentOpen: fake agent started')
  var lines: list<string> = filereadable(meta) ? readfile(meta) : ['', '', '']
  var ctx_path: string = substitute(lines[0], '^ctxfile=', '', '')
  Assert(!empty(ctx_path), 'AgentOpen: VPROJ_AGENT_CTX_FILE set')
  Assert(lines[1] == '600', 'AgentOpen: context file is 0600 (' .. lines[1] .. ')')
  Assert(lines[2] == 'inline=unset', 'AgentOpen: context not passed inline in the environment')
  var ctx: any = json_decode(join(readfile(fake_dir .. '/agent.ctx'), "\n"))
  Assert(type(ctx) == v:t_dict && len(get(ctx, 'file_lines', [])) == 101, 'AgentOpen: context JSON has the 101 gathered lines')
  Assert(get(ctx, 'cursor_line', 0) == 150, 'AgentOpen: context has cursor line')

  # Agent exits → window closes, context file deleted.
  var agent_job: job = term_getjob(termbuf)
  term_sendkeys(termbuf, "\r")
  Assert(WaitFor(() => job_status(agent_job) == 'dead'), 'AgentOpen: agent exits')
  Assert(WaitFor(() => !filereadable(ctx_path)), 'AgentOpen: context file deleted on exit')
  Assert(WaitFor(() => winnr('$') == wins_before), 'AgentOpen: window closes when the agent exits')
enddef
RunSection('AgentOpen', SectionOpen)

# ── Cleanup and report ──
delete(fake_dir, 'rf')
delete(src_file)
log->add('---')
log->add('Agent module tests: ' .. (g:failures == 0 ? 'ALL PASSED' : g:failures .. ' FAILURES'))
for line in log
  echom line
endfor
var result_file: any = getenv('VPROJ_TEST_RESULT')
if type(result_file) == v:t_string && !empty(result_file)
  writefile(log, result_file)
endif
if g:failures > 0
  cquit!
endif
qa!

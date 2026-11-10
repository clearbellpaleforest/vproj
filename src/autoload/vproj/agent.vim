vim9script

# autoload/vproj/agent.vim — Agent CLI integration for vproj.
# Launches a coding-agent CLI in a vproj-managed terminal split. By default
# it looks for the two official CLIs, claude (Anthropic) then codex (OpenAI).
# Any other agent is launched only when the user names it in
# g:vproj_agent_cmd (a program name, or a list: program + arguments). vproj
# never guesses other program names, because whatever it launches is handed
# the file context.
#
# Context handed to the agent:
#   VPROJ_AGENT_CTX_FILE  path of a JSON file (mode 0600) with keys cwd, and
#                         when a file is open: file, filetype, cursor_line,
#                         cursor_col, file_lines (up to 50 lines either side
#                         of the cursor), file_line_offset, file_total_lines.
#                         The file is deleted when the agent exits.
# (Context used to be passed inline in VPROJ_AGENT_CTX; a large context
# overflowed the environment size limit, so it is now a file.)
#
# The terminal keeps every key, including Esc, for the agent. The window
# closes when the agent exits.

# ── Detection ──

const OFFICIAL_AGENTS: list<string> = ['claude', 'codex']

# The command to run, or [] after telling the user why there is none. A
# configured g:vproj_agent_cmd that cannot run is an error, not a reason to
# fall back to another program.
def AgentCommand(): list<string>
  if has_key(g:, 'vproj_agent_cmd')
    var raw: any = g:vproj_agent_cmd
    var cmd: list<string> = []
    if type(raw) == v:t_string && !empty(raw)
      cmd = [raw]
    elseif type(raw) == v:t_list && !empty(raw)
        && empty(filter(copy(raw), (_, a) => type(a) != v:t_string))
      cmd = copy(raw)
    else
      echohl ErrorMsg
      echom 'vproj-agent: g:vproj_agent_cmd must be a program name or a list of strings'
      echohl None
      return []
    endif
    if !executable(cmd[0])
      echohl ErrorMsg
      echom 'vproj-agent: g:vproj_agent_cmd: ' .. cmd[0] .. ' not found or not executable'
      echohl None
      return []
    endif
    return cmd
  endif
  for bin in OFFICIAL_AGENTS
    if executable(bin)
      return [bin]
    endif
  endfor
  echohl ErrorMsg
  echom 'vproj-agent: no agent CLI found. Install one of:'
  echom '  npm install -g @anthropic-ai/claude-code   (claude)'
  echom '  npm install -g @openai/codex               (codex)'
  echom 'or set g:vproj_agent_cmd to the agent you use.'
  echohl None
  return []
enddef

# ── Context ──

# Window ID of the file window the user is working in: the current window,
# or the previous window when the current one is the vproj pane. 0 when
# there is none, or when it shows a non-file buffer (nofile, terminal,
# quickfix, help ...). ai.vim has the same rule (OriginWindow); it is kept
# here so the two add-ons stay independent of each other.
def OriginWindow(pane: number): number
  var winid: number = win_getid()
  if winbufnr(winid) == pane
    var prev: number = winnr('#')
    if prev <= 0
      return 0
    endif
    winid = win_getid(prev)
  endif
  if winid <= 0
    return 0
  endif
  var bufnr: number = winbufnr(winid)
  if bufnr <= 0 || bufnr == pane || !empty(getbufvar(bufnr, '&buftype'))
    return 0
  endif
  return winid
enddef

def GatherAgentContext(): dict<any>
  var ctx: dict<any> = {}
  ctx.cwd = getcwd()

  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  var winid: number = OriginWindow(pane)
  if winid == 0
    return ctx
  endif
  var bufnr: number = winbufnr(winid)
  var pos: list<number> = getcurpos(winid)
  ctx.file = fnamemodify(bufname(bufnr), ':p')
  ctx.filetype = getbufvar(bufnr, '&filetype', '')
  ctx.cursor_line = pos[1] > 0 ? pos[1] : 1
  ctx.cursor_col = pos[2] > 0 ? pos[2] : 1
  var total: number = get(getbufinfo(bufnr)[0], 'linecount', 0)
  var ctx_start: number = max([1, ctx.cursor_line - 50])
  var ctx_end: number = min([total, ctx.cursor_line + 50])
  ctx.file_lines = getbufline(bufnr, ctx_start, ctx_end)
  ctx.file_line_offset = ctx_start
  ctx.file_total_lines = total
  return ctx
enddef

# Write {text} to a new tempname() file created 0600 before the content is
# written. Returns the path, or '' on failure (nothing left behind).
def WriteContextFile(text: string): string
  var path: string = tempname()
  if writefile([], path, 'b') != 0
    return ''
  endif
  if !setfperm(path, 'rw-------') || writefile([text], path, 'b') != 0
    delete(path)
    return ''
  endif
  return path
enddef

def DeleteContextFile(path: string): void
  if !empty(path) && filereadable(path)
    delete(path)
  endif
enddef

# ── Public API ──

export def AgentOpen(): void
  if !has('terminal')
    echohl ErrorMsg
    echom 'vproj-agent: terminal support required (Vim 8.0+)'
    echohl None
    return
  endif

  var cmd: list<string> = AgentCommand()
  if empty(cmd)
    return
  endif
  var bin: string = cmd[0]

  var ctx_file: string = WriteContextFile(json_encode(GatherAgentContext()))
  if empty(ctx_file)
    echohl ErrorMsg
    echom 'vproj-agent: failed to write context file'
    echohl None
    return
  endif

  var opts: dict<any> = {
    curwin: true,
    term_finish: 'close',
    env: {VPROJ_AGENT_CTX_FILE: ctx_file},
    exit_cb: (_, _) => DeleteContextFile(ctx_file),
  }
  # One 20-line window at the bottom; term_start() reuses it (curwin) and
  # the placeholder buffer is wiped, so no empty window or buffer is left.
  botright new
  setlocal bufhidden=wipe
  resize 20
  var termbuf: number = term_start(cmd, opts)
  var agent_job: any = termbuf > 0 ? term_getjob(termbuf) : v:null
  if termbuf == 0 || agent_job == v:null || job_status(agent_job) == 'fail'
    DeleteContextFile(ctx_file)
    if termbuf == 0 && winnr('$') > 1
      close
    endif
    echohl ErrorMsg
    echom 'vproj-agent: failed to start ' .. bin
    echohl None
    return
  endif

  echom 'vproj-agent: ' .. bin .. ' running -- the window closes when it exits'
enddef

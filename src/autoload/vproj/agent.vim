vim9script

# autoload/vproj/agent.vim — Agent CLI integration for vproj.
# Launches a multi-provider AI agent (claudex, aether, openheim, claude, codex)
# in a vproj-managed terminal split. Provider-agnostic — users configure their
# own CLI (env vars, API keys, model) and vproj just launches it with context.
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

def DetectAgent(): string
  for bin in ['claudex', 'aether', 'openheim', 'claude', 'codex']
    if executable(bin)
      return bin
    endif
  endfor
  return ''
enddef

# ── Context ──

def GatherAgentContext(): dict<any>
  var ctx: dict<any> = {}
  ctx.cwd = getcwd()

  var bufnr: number = bufnr('%')
  var pane: number = exists('*vproj#GetPaneBufnr') ? vproj#GetPaneBufnr() : -1
  if bufnr > 0 && bufnr != pane
    ctx.file = fnamemodify(bufname(bufnr), ':p')
    ctx.filetype = getbufvar(bufnr, '&filetype', '')
    ctx.cursor_line = line('.')
    ctx.cursor_col = col('.')
    var total: number = line('$')
    var ctx_start: number = max([1, ctx.cursor_line - 50])
    var ctx_end: number = min([total, ctx.cursor_line + 50])
    ctx.file_lines = getbufline(bufnr, ctx_start, ctx_end)
    ctx.file_line_offset = ctx_start
    ctx.file_total_lines = total
  endif

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

  var bin: string = DetectAgent()
  if empty(bin)
    echohl ErrorMsg
    echom 'vproj-agent: no agent CLI found'
    echom 'Install one: npm install -g claudex  (recommended — Claude + Codex)'
    echom '           npm install -g aether    (Claude Code fork, multi-provider)'
    echom '           npm install -g @anthropic-ai/claude-code'
    echom '           npm install -g @openai/codex'
    echohl None
    return
  endif

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
  var termbuf: number = term_start(bin, opts)
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

  echom 'vproj-agent: ' .. bin .. ' running — the window closes when it exits'
enddef

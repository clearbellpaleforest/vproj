vim9script

# autoload/vproj/agent.vim — Agent CLI integration for vproj.
# Launches a multi-provider AI agent (claudex, aether, openheim, claude, codex)
# in a vproj-managed terminal split. Provider-agnostic — users configure their
# own CLI (env vars, API keys, model) and vproj just launches it with context.

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

  var ctx: dict<any> = GatherAgentContext()
  var ctx_json: string = json_encode(ctx)

  botright new
  execute 'resize 20'
  var opts: dict<any> = {
    term_finish: 'close',
    env: {VPROJ_AGENT_CTX: ctx_json},
  }
  var termbuf: number = term_start(bin, opts)
  if termbuf == 0
    echohl ErrorMsg
    echom 'vproj-agent: failed to start ' .. bin
    echohl None
    close
    return
  endif

  # Esc closes the agent pane
  tnoremap <buffer> <nowait> <Esc> <C-\><C-n>:close<CR>
  echom 'vproj-agent: ' .. bin .. ' running — Esc to close'
enddef

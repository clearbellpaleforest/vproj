vim9script

# autoload/nam/navigation.vim — vim9script key dispatch and mapping manager
#
# Module-level state
#   TierChars:    list<string>  — all single-char label keys, populated in Setup()
#   HandlerFn:    func(string): any — the current dispatch function, set by SetHandler()
#   CurrentMode:  dict<any>     — reference to the currently active mode (for page controls)
#   EventsMod:    dict<any>     — reference to the events module (for emitting events)

var TierChars: list<string>
var HandlerFn: any = v:null
var CurrentMode: dict<any>
var EventsMod: dict<any>

# Setup(cfg, events_mod):
#   Populate TierChars from cfg.labels.tiers (split each tier string into chars)
#   Store events_mod reference for event emission in page controls
export def Setup(cfg: dict<any>, events_mod: dict<any>)
  TierChars = []
  if has_key(cfg, 'labels') && has_key(cfg.labels, 'tiers')
    for tier in cfg.labels.tiers
      for ch in split(tier, '\zs')
        add(TierChars, ch)
      endfor
    endfor
  endif
  EventsMod = events_mod
enddef

# Attach(buf):
#   Configures a buffer for DSN key dispatch.
#   - Marks the buffer as not modifiable
#   - Creates a buffer-local nnoremap for every tier character,
#     routing through the handler bridge (nam#handler#Handle)
#   - Maps <Esc> to close the sidebar
#   - Maps [ and ] for page-up/page-down through the handler bridge
export def Attach(buf: number)
  if !bufexists(buf)
    return
  endif
  setbufvar(buf, '&modifiable', 0)
  for ch in TierChars
    execute $'nnoremap <buffer> <nowait> {ch} <Cmd>call nam#handler#Handle("{ch}")<CR>'
  endfor
  execute 'nnoremap <buffer> <nowait> <Esc> <Cmd>call nam#handler#HandleClose()<CR>'
  execute 'nnoremap <buffer> <nowait> [ <Cmd>call nam#handler#HandlePagePrev()<CR>'
  execute 'nnoremap <buffer> <nowait> ] <Cmd>call nam#handler#HandlePageNext()<CR>'
enddef

# SetHandler(Fn):
#   Store the active dispatch handler function reference.
#   Accepts any callable (vim9script func or legacy Funcref).
export def SetHandler(Fn: any)
  HandlerFn = Fn
enddef

# Dispatch(label):
#   Invoke the stored handler function.
#   Returns the handler's result on success, or false on error.
export def Dispatch(label: string): any
  if type(HandlerFn) != v:t_func
    return false
  endif
  try
    return HandlerFn(label)
  catch
    echom $'[nam/navigation] Dispatch error: {v:exception}'
    return false
  endtry
enddef

# PagePrev():
#   If the current mode exposes a PrevPage function, call it, then
#   re-render the mode display and emit a mode_rerender event.
export def PagePrev()
  if has_key(CurrentMode, 'PrevPage')
    CurrentMode.PrevPage()
    if has_key(CurrentMode, 'Render')
      CurrentMode.Render()
    endif
    if has_key(EventsMod, 'Emit')
      EventsMod.Emit('mode_rerender', {mode: CurrentMode, result: 'prev'})
    endif
  endif
enddef

# PageNext():
#   If the current mode exposes a NextPage function, call it, then
#   re-render the mode display and emit a mode_rerender event.
export def PageNext()
  if has_key(CurrentMode, 'NextPage')
    CurrentMode.NextPage()
    if has_key(CurrentMode, 'Render')
      CurrentMode.Render()
    endif
    if has_key(EventsMod, 'Emit')
      EventsMod.Emit('mode_rerender', {mode: CurrentMode, result: 'next'})
    endif
  endif
enddef

# SetCurrentMode(mode):
#   Store a reference to the currently active mode (for page-up/page-down controls).
export def SetCurrentMode(mode: dict<any>)
  CurrentMode = mode
enddef

# ResetHandler():
#   Clear the dispatch handler back to null. Useful for testing.
export def ResetHandler()
  HandlerFn = v:null
enddef

vim9script

# autoload/vproj/init.vim — vim9script top-level orchestrator for Nam.
#
# Called by plugin/vproj.vim commands and user setup().
# Exports: Setup, Toggle, Open, Close
#
# Setup flow:
#   1. Merge user options with defaults via vproj#config#Setup
#   2. Clear event bus and create subsystem caches
#   3. Initialize all subsystems (sidebar, renderer, navigation, modes)
#   4. Register each enabled mode (buffers, files, symbols, git, outline)
#   5. Wire event handlers (mode_changed, mode_rerender)
#   6. Initialize persistence and workspace modules
#   7. Set global hotkey and auto-open if configured

# Guard against double-initialization (plugin auto-calls Setup({}) on load;
# the user may also call it with custom opts in their vimrc).
var setup_done: bool = false

# ---------------------------------------------------------------------------
# Setup — full plugin initialization.
# @param user_opts: dict<any> — optional user-override configuration.
# ---------------------------------------------------------------------------
export def Setup(user_opts: dict<any>)
  if setup_done
    return
  endif

  # 1. Merge user options with defaults
  var cfg: dict<any> = vproj#config#Setup(user_opts)

  # 2. Clear event bus
  vproj#events#Clear()

  # 3. Create named caches with configured TTLs
  vproj#cache#Create('project', cfg.cache.project_ttl)
  vproj#cache#Create('git', cfg.cache.git_ttl)

  # 4. Build an events module reference for subsystems that need emit/subscribe
  var events_mod: dict<any> = {
    On: function(vproj#events#On),
    Off: function(vproj#events#Off),
    Emit: function(vproj#events#Emit),
    Clear: function(vproj#events#Clear),
  }

  # 5. Initialize all subsystems
  vproj#sidebar#Setup(cfg)
  vproj#renderer#Setup(cfg)
  vproj#navigation#Setup(cfg, events_mod)
  vproj#modes#Setup(cfg, events_mod)

  # 6. Register each enabled mode.
  #    Mode files follow the naming convention autoload/vproj/{name}_mode.vim and
  #    export a Create(cfg) function that returns a mode dict.
  var mode_names: list<string> = ['files', 'buffers', 'symbols', 'git', 'outline']
  for mode_name in mode_names
    if has_key(cfg.modes, mode_name) && cfg.modes[mode_name]->get('enabled', false)
      try
        var create_fn_name: string = 'vproj#' .. mode_name .. '_mode#Create'
        var CreateFn = function(create_fn_name)
        var mode: dict<any> = CreateFn(cfg)
        vproj#modes#Register(mode)
      catch
        echom $"[vproj] Failed to load mode '{mode_name}': {v:exception}"
      endtry
    endif
  endfor

  # 7. Wire event handlers
  events_mod.On('mode_changed', ModeChangedHandler)
  events_mod.On('mode_rerender', ModeRerenderHandler)

  # 8. Set up persistence and workspace modules
  vproj#persistence#Setup(cfg)
  vproj#workspace#Setup(cfg)

  # 9. Set global hotkey mapping (Normal mode)
  # Validate hotkey to prevent injection via embedded newlines or ex separators
  if type(cfg.hotkey) == v:t_string && cfg.hotkey !~# '[\n\r|"]' && cfg.hotkey =~# '^\(<[^>]\+>\|[^[:cntrl:]]\)$'
    execute 'nnoremap ' .. cfg.hotkey .. ' :<C-U>call vproj#init#Toggle()<CR>'
  endif

  # 10. Auto-open if configured
  if cfg.auto_open
    Open()
  endif

  setup_done = true
enddef

# ---------------------------------------------------------------------------
# Toggle — open the sidebar if closed, close it if open.
# After opening, attaches navigation mappings and switches to the default mode.
# ---------------------------------------------------------------------------
export def Toggle()
  vproj#sidebar#Toggle()
  if vproj#sidebar#IsOpen()
    AttachAndShow()
  endif
enddef

# ---------------------------------------------------------------------------
# Open — open the sidebar and prepare for interaction.
# ---------------------------------------------------------------------------
export def Open()
  vproj#sidebar#Open()
  if vproj#sidebar#IsOpen()
    AttachAndShow()
  endif
enddef

# ---------------------------------------------------------------------------
# Close — close the sidebar and tear down its buffer.
# ---------------------------------------------------------------------------
export def Close()
  vproj#sidebar#Close()
enddef

# ---------------------------------------------------------------------------
# AttachAndShow — helper called after sidebar opens.
# Retrieves the sidebar buffer, attaches navigation keymaps, and switches
# to the first registered (default) mode.
# ---------------------------------------------------------------------------
def AttachAndShow()
  var buf: number = vproj#sidebar#GetBuf()
  if buf <= 0
    return
  endif

  # Attach navigation mappings to the sidebar scratch buffer
  vproj#navigation#Attach(buf)

  # Switch to the default (first registered enabled) mode
  var default_mode: dict<any> = vproj#modes#GetDefault()
  if !empty(default_mode)
    vproj#modes#Switch(default_mode.key)
  endif
enddef

# ---------------------------------------------------------------------------
# ModeChangedHandler — responds to the 'mode_changed' event.
#
# 1. Verifies the sidebar is still open and retrieves the buffer.
# 2. Calls the mode's Refresh() to gather current data.
# 3. Calls the mode's Render() to produce display lines and a label map.
# 4. Delegates full rendering to vproj#renderer#RenderFull.
# 5. Sets the mode as current on the navigation engine.
# 6. Registers a label-dispatch handler that:
#    a. Attempts mode.Select(label).  If it returns a value (truthy or false
#       to signal selection was attempted), the key press is consumed.
#    b. If mode.Select returns v:null, checks whether label matches a
#       registered mode hotkey and switches to that mode.
# ---------------------------------------------------------------------------
def ModeChangedHandler(data: dict<any>)
  if !vproj#sidebar#IsOpen()
    return
  endif

  var mode: dict<any> = get(data, 'mode', {})
  if empty(mode)
    return
  endif

  var buf: number = vproj#sidebar#GetBuf()
  if buf <= 0
    return
  endif

  # Refresh the mode's underlying data
  if has_key(mode, 'Refresh')
    mode.Refresh()
  endif

  # Render the mode to obtain display lines and a label map
  var result: dict<any> = {}
  if has_key(mode, 'Render')
    result = mode.Render()
  elseif has_key(mode, 'RenderSym')
    result = mode.RenderSym()
  endif

  # Push rendered content into the sidebar buffer
  if !empty(result)
    vproj#renderer#RenderFull(buf, mode.name, vproj#modes#All(), get(result, 'lines', []))
  endif

  # Tell the navigation engine which mode is active
  vproj#navigation#SetCurrentMode(mode)

  # Register the label-dispatch handler.
  #   - If mode.Select(label) returns non-null the label was consumed.
  #   - Otherwise the label is checked against mode hotkeys.
  vproj#navigation#SetHandler(HandleLabel)
enddef

# ---------------------------------------------------------------------------
# ModeRerenderHandler — responds to the 'mode_rerender' event.
#
# Re-renders the currently active mode without switching or refreshing data.
# Useful after page-turn operations (prev_page/next_page).
# ---------------------------------------------------------------------------
def ModeRerenderHandler(data: dict<any>)
  if !vproj#sidebar#IsOpen()
    return
  endif

  var mode: dict<any> = vproj#modes#GetCurrent()
  if empty(mode)
    return
  endif

  var buf: number = vproj#sidebar#GetBuf()
  if buf <= 0
    return
  endif

  var result: dict<any> = {}
  if has_key(mode, 'Render')
    result = mode.Render()
  elseif has_key(mode, 'RenderSym')
    result = mode.RenderSym()
  endif

  if !empty(result)
    vproj#renderer#RenderFull(buf, mode.name, vproj#modes#All(), get(result, 'lines', []))
  endif
enddef

# ---------------------------------------------------------------------------
# HandleLabel — label dispatch function registered with vproj#navigation.
#
# @param label: string — the single or multi-character label pressed.
# @returns bool — true if the label was consumed, false otherwise.
#
# Dispatch order:
#   1. Call current mode's Select(label).  Non-null return = consumed.
#   2. If Select returns v:null, check whether label matches a mode hotkey
#      and, if found, switch to that mode.
# ---------------------------------------------------------------------------
def HandleLabel(label: string): bool
  var mode: dict<any> = vproj#modes#GetCurrent()
  if empty(mode)
    return false
  endif

  # Try mode.Select (standard interface) or SelectSym (symbols-mode compat)
  var result: any = v:null
  if has_key(mode, 'Select')
    result = mode.Select(label)
  elseif has_key(mode, 'SelectSym')
    result = mode.SelectSym(label)
  endif

  # If Select returned a non-null value the label was consumed
  if result != v:null
    return true
  endif

  # Label was not consumed by the current mode — check mode hotkeys
  var target_mode: dict<any> = vproj#modes#Get(label)
  if !empty(target_mode)
    vproj#modes#Switch(label)
    return true
  endif

  return false
enddef

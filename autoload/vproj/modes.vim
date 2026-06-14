vim9script

# Mode registry for Nam.
# Manages mode lifecycle: registration, lookup, switching, and event emission.
#
# Module-level state:
#   Modes    - dict<dict<any>> keyed by single-char mode key ('b','f','s','g','o')
#   ModeOrder - list<string> preserving registration order
#   Current  - dict<any> the active mode
#   Events   - dict<any> reference to the events module for emitting mode_changed

var Modes: dict<dict<any>> = {}
var ModeOrder: list<string> = []
var Current: dict<any> = {}
var Events: dict<any> = {}

# Setup resets all module state and stores a reference to the events module.
# cfg is accepted for API consistency with other Setup functions.
export def Setup(cfg: dict<any>, events_mod: dict<any>)
  Modes = {}
  ModeOrder = []
  Current = {}
  Events = events_mod
enddef

# Register adds a mode to the registry.
# The mode dict must have a string 'key' field.
export def Register(mode: dict<any>)
  if !has_key(mode, 'key') || type(mode.key) != v:t_string || empty(mode.key)
    return
  endif
  Modes[mode.key] = mode
  ModeOrder->add(mode.key)
enddef

# Get returns the mode dict for the given key, or an empty dict if not found.
export def Get(key: string): dict<any>
  return get(Modes, key, {})
enddef

# Switch activates the mode identified by key.
# If the mode is not found or not enabled, returns an empty dict.
# Otherwise sets it as Current, calls mode.Refresh() if present,
# emits 'mode_changed' via the events module, and returns the mode.
export def Switch(key: string): dict<any>
  var mode = Get(key)
  if empty(mode)
    return {}
  endif
  if !has_key(mode, 'enabled') || !mode.enabled
    return {}
  endif
  Current = mode
  if has_key(mode, 'Refresh')
    mode.Refresh()
  endif
  if !empty(Events) && has_key(Events, 'Emit')
    Events.Emit('mode_changed', {mode: mode})
  endif
  return mode
enddef

# GetCurrent returns the currently active mode dict.
export def GetCurrent(): dict<any>
  return Current
enddef

# GetDefault iterates ModeOrder and returns the first registered mode
# that exists and is enabled. Returns empty dict if none found.
export def GetDefault(): dict<any>
  for key in ModeOrder
    var mode = get(Modes, key, {})
    if !empty(mode) && has_key(mode, 'enabled') && mode.enabled
      return mode
    endif
  endfor
  return {}
enddef

# All returns a list of all registered mode dicts.
export def All(): list<dict<any>>
  var result: list<dict<any>> = []
  for key in keys(Modes)
    result->add(Modes[key])
  endfor
  return result
enddef

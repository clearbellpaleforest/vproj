vim9script

# Event bus for Vproj plugin.
# Provides decoupled communication between subsystems.
# Listeners dict: event name -> list of {id, fn}
# NextId counter: monotonically increasing unique IDs.

var Listeners: dict<list<dict<any>>> = {}
var NextId: number = 1

# Register a listener for an event.
# @param {string} event - Event name to subscribe to.
# @param {func(dict<any>)} Fn - Callback receiving event data.
# @returns {number} Unique listener ID (use with Off()).
export def On(event: string, Fn: func(dict<any>)): number
  var id = NextId
  NextId += 1
  if !has_key(Listeners, event)
    Listeners[event] = []
  endif
  Listeners[event]->add({id: id, fn: Fn})
  return id
enddef

# Remove a previously registered listener.
# @param {string} event - Event name the listener was registered on.
# @param {number} id - Listener ID returned by On().
export def Off(event: string, id: number): void
  if !has_key(Listeners, event)
    return
  endif
  var idx: number = -1
  for i in range(Listeners[event]->len())
    if Listeners[event][i].id == id
      idx = i
      break
    endif
  endfor
  if idx >= 0
    remove(Listeners[event], idx)
  endif
enddef

# Fire an event, calling all registered listeners in order.
# Errors in individual listeners are caught and reported via echom.
# @param {string} event - Event name to emit.
# @param {dict<any>} data - Data payload passed to each listener.
export def Emit(event: string, data: dict<any>): void
  if !has_key(Listeners, event)
    return
  endif
  var entries = Listeners[event]->copy()
  for entry in entries
    try
      entry.fn(data)
    catch
      echom $"[vproj/events] Error in listener '{event}': {v:exception}"
    endtry
  endfor
enddef

# Remove all listeners across all events and reset ID counter.
export def Clear(): void
  Listeners = {}
  NextId = 1
enddef

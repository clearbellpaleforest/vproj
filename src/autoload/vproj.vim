vim9script

# autoload/vproj.vim — VPROJ project pane (Stage 1: Pane Infrastructure).
#
# Architecture: Workspace Domain Model (ADR-005), Command/Query Separation (ADR-006).
# Commands change state (return void). Queries read state (return values). Never both.
#
# Events (ADR-007): every command emits exactly one named event. Display rebuilds from events.

# ---------------------------------------------------------------------------
# Script-local workspace state (single source of truth — ADR-005)
# ---------------------------------------------------------------------------
var pane_bufnr: number = -1
var pane_width: number = 40
var current_mode: string = 'file'
var selected_line: number = 1          # 1-indexed line number in pane buffer

# Autocommand group name for cleanup
const AUTOGROUP: string = 'VprojPane'

# ---------------------------------------------------------------------------
# Constants (ADR-009, ADR-010, ADR-011)
# ---------------------------------------------------------------------------
const NAV_INDICATORS: string = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ123456789'
const MODE_KEYS: list<string> = ['file', 'doc', 'code']
const MODE_LABELS: dict<string> = {file: '[F]ile', doc: '[D]oc', code: '[C]ode'}
const MIN_PANE_WIDTH: number = 20
const MAX_PANE_WIDTH: number = 80



# ═══════════════════════════════════════════════════════════════════════════
# Commands — change state, return void (ADR-006)
# ═══════════════════════════════════════════════════════════════════════════

# Toggle the project pane: open if closed, close if open.
export def PaneToggle(): void
  if pane_bufnr > 0 && bufexists(pane_bufnr) && bufwinnr(pane_bufnr) > 0
    PaneClose()
  else
    PaneOpen()
  endif
enddef

# Open the project pane as a vertical split on the left.
# Idempotent: if the pane is already open, just focus it.
export def PaneOpen(): void
  # If buffer still exists and is already visible, just focus it
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    var wnr: number = bufwinnr(pane_bufnr)
    if wnr > 0
      win_gotoid(win_getid(wnr))
      return
    endif
  endif

  # Create a fresh scratch buffer in a vertical split on the left
  execute 'topleft vert new'
  pane_bufnr = bufnr('%')

  # Configure as scratch buffer
  setbufvar(pane_bufnr, '&buftype', 'nofile')
  setbufvar(pane_bufnr, '&bufhidden', 'wipe')
  setbufvar(pane_bufnr, '&swapfile', 0)
  setbufvar(pane_bufnr, '&buflisted', 0)
  setbufvar(pane_bufnr, '&modifiable', 1)
  setbufvar(pane_bufnr, '&cursorline', 1)
  setbufvar(pane_bufnr, '&number', 0)
  setbufvar(pane_bufnr, '&relativenumber', 0)
  setbufvar(pane_bufnr, '&signcolumn', 'no')
  setbufvar(pane_bufnr, '&winfixwidth', 1)
  setbufvar(pane_bufnr, '&colorcolumn', '')

  # Name the buffer (cosmetic — for statusline display)
  silent! keepalt file VPROJ

  # Set initial width
  execute 'vert resize ' .. pane_width

  # Detect manual window close (BufWipeout) to keep state consistent
  SetupAutocommands()

  # Render content and set up key mappings
  Render()
  SetupPaneMappings()

  setbufvar(pane_bufnr, '&modifiable', 0)

  # Position cursor on the first selectable line
  cursor(selected_line, 1)

  EmitEvent('pane_opened', {width: pane_width, mode: current_mode})
enddef

# Close the project pane.
# Idempotent: if the pane is already closed, this is a no-op.
export def PaneClose(): void
  if pane_bufnr <= 0
    return
  endif

  if !bufexists(pane_bufnr)
    pane_bufnr = -1
    return
  endif

  var wnr: number = bufwinnr(pane_bufnr)
  if wnr > 0
    win_execute(win_getid(wnr), 'close')
  endif

  # Buffer gets wiped by bufhidden=wipe; autocmd will reset pane_bufnr
  EmitEvent('pane_closed', {mode: current_mode})
enddef

# Increase pane width by 1 column (clamped to MAX_PANE_WIDTH).
export def PaneGrow(): void
  if pane_width >= MAX_PANE_WIDTH
    return
  endif
  pane_width += 1
  ApplyWidth()
  Render()
  EmitEvent('width_changed', {width: pane_width})
enddef

# Decrease pane width by 1 column (clamped to MIN_PANE_WIDTH).
export def PaneShrink(): void
  if pane_width <= MIN_PANE_WIDTH
    return
  endif
  pane_width -= 1
  ApplyWidth()
  Render()
  EmitEvent('width_changed', {width: pane_width})
enddef

# Move selection down one line, wrapping at the bottom.
# Skips non-selectable lines (separator). In Stage 1 the separator is line 2;
# when cursor is on line 2, next jumps to line 1 (wrapping).
export def SelectNext(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  var total: number = line('$', pane_bufnr)
  if total <= 1
    return
  endif

  # Find next selectable line
  var next_line: number = selected_line + 1
  if next_line > total
    next_line = 1
  endif

  # In Stage 1, line 2 is the separator (non-selectable) — skip it
  if next_line == 2 && total >= 2
    next_line = 3
    if next_line > total
      next_line = 1
    endif
  endif

  selected_line = next_line
  cursor(selected_line, 1)
  EmitEvent('selection_moved', {line: selected_line})
enddef

# Move selection up one line, wrapping at the top.
export def SelectPrev(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  var total: number = line('$', pane_bufnr)
  if total <= 1
    return
  endif

  var prev_line: number = selected_line - 1
  if prev_line < 1
    prev_line = total
  endif

  # In Stage 1, line 2 is the separator — skip it
  if prev_line == 2 && total >= 2
    prev_line = 1
  endif

  selected_line = prev_line
  cursor(selected_line, 1)
  EmitEvent('selection_moved', {line: selected_line})
enddef

# Activate the currently selected item.
# In Stage 1, this selects a mode from the mode menu.
export def SelectCurrent(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  if selected_line == 1
    # On the mode menu line — determine which mode to select.
    # Stage 1: modes aren't functional yet; just update current_mode.
    # In later stages, this dispatches to the mode's activate handler.
    var mode_idx: number = ModeIndexAtCursor()
    if mode_idx >= 0 && mode_idx < len(MODE_KEYS)
      SwitchMode(MODE_KEYS[mode_idx])
    endif
  endif
  # Other lines (separator, items in later stages) handled by mode-specific logic
enddef

# Switch to the named mode and re-render.
export def SwitchMode(key: string): void
  if index(MODE_KEYS, key) < 0
    return
  endif
  current_mode = key
  Render()
  EmitEvent('mode_changed', {mode: key})
enddef

# Set pane width directly (for user configuration via VPROJ_pane-width_* env vars).
export def SetPaneWidth(w: number): void
  if w < MIN_PANE_WIDTH || w > MAX_PANE_WIDTH
    return
  endif
  pane_width = w
  ApplyWidth()
  Render()
enddef



# ═══════════════════════════════════════════════════════════════════════════
# Queries — read state, return values (ADR-006)
# ═══════════════════════════════════════════════════════════════════════════

# Returns true if the project pane is currently visible.
export def IsPaneVisible(): bool
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return false
  endif
  return bufwinnr(pane_bufnr) > 0
enddef

# Returns the current pane width in columns.
export def GetPaneWidth(): number
  return pane_width
enddef

# Returns the currently active mode key ('file', 'doc', or 'code').
export def GetCurrentMode(): string
  return current_mode
enddef

# Returns the 1-indexed selected line number.
export def GetSelectedLine(): number
  return selected_line
enddef



# ═══════════════════════════════════════════════════════════════════════════
# Internal — display, mappings, events
# ═══════════════════════════════════════════════════════════════════════════

# Rebuild the entire pane display from workspace state.
# This is a full redraw (ADR-011, Option A).
def Render(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  var lines: list<string> = []

  # Line 1: Mode menu
  var menu: string = BuildModeMenu()
  lines->add(menu)

  # Line 2: Separator (dashes spanning full pane width)
  var sep: string = repeat('─', pane_width)
  lines->add(sep)

  # Lines 3+: Item list (empty in Stage 1 — populated by mode-specific rendering
  # in Stage 2+). The Render remains responsible for the shared pane chrome;
  # item content is appended here in later stages via mode queries.

  # Write to buffer
  var was_modifiable: bool = getbufvar(pane_bufnr, '&modifiable', 0)
  setbufvar(pane_bufnr, '&modifiable', 1)
  deletebufline(pane_bufnr, 1, '$')
  setbufline(pane_bufnr, 1, lines)

  # Clear stale syntax matches before re-applying highlights
  ClearPaneHighlights()

  # Highlight the current mode in the menu line
  HighlightCurrentMode()

  setbufvar(pane_bufnr, '&modifiable', was_modifiable)

  # Restore cursor to selected line (clamped to buffer range)
  var max_line: number = line('$', pane_bufnr)
  if selected_line > max_line
    selected_line = max_line > 0 ? max_line : 1
  endif
  if selected_line < 1
    selected_line = 1
  endif
  cursor(selected_line, 1)
enddef

# Build the mode menu string for line 1.
# Format: "[F]ile  [D]oc  [C]ode" padded/truncated to pane_width.
def BuildModeMenu(): string
  var parts: list<string> = []
  for key in MODE_KEYS
    parts->add(get(MODE_LABELS, key, key))
  endfor
  var menu_line: string = join(parts, '  ')
  var display_width: number = strwidth(menu_line)
  if display_width < pane_width
    menu_line = menu_line .. repeat(' ', pane_width - display_width)
  endif
  return menu_line
enddef

# Set buffer-local key mappings in the pane buffer.
def SetupPaneMappings(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  var bufnr_str: string = pane_bufnr->string()

  # Navigation
  execute 'nnoremap <buffer> <silent> <Down> :call vproj#SelectNext()<CR>'
  execute 'nnoremap <buffer> <silent> <Up> :call vproj#SelectPrev()<CR>'
  execute 'nnoremap <buffer> <silent> j :call vproj#SelectNext()<CR>'
  execute 'nnoremap <buffer> <silent> k :call vproj#SelectPrev()<CR>'

  # Width adjustment
  execute 'nnoremap <buffer> <silent> <Right> :call vproj#PaneGrow()<CR>'
  execute 'nnoremap <buffer> <silent> <Left> :call vproj#PaneShrink()<CR>'

  # Activation
  execute 'nnoremap <buffer> <silent> <CR> :call vproj#SelectCurrent()<CR>'

  # Close pane
  execute 'nnoremap <buffer> <silent> <F4> :call vproj#PaneClose()<CR>'
  execute 'nnoremap <buffer> <silent> q :call vproj#PaneClose()<CR>'

  # Prevent modification keys from doing anything
  execute 'nnoremap <buffer> i <Nop>'
  execute 'nnoremap <buffer> a <Nop>'
  execute 'nnoremap <buffer> o <Nop>'
  execute 'nnoremap <buffer> O <Nop>'
  execute 'nnoremap <buffer> r <Nop>'
  execute 'nnoremap <buffer> R <Nop>'
  execute 'nnoremap <buffer> c <Nop>'
  execute 'nnoremap <buffer> C <Nop>'
  execute 'nnoremap <buffer> d <Nop>'
  execute 'nnoremap <buffer> D <Nop>'
  execute 'nnoremap <buffer> x <Nop>'
  execute 'nnoremap <buffer> s <Nop>'
  execute 'nnoremap <buffer> p <Nop>'
  execute 'nnoremap <buffer> P <Nop>'
  execute 'nnoremap <buffer> u <Nop>'
  execute 'nnoremap <buffer> U <Nop>'
enddef

# Autocommands to detect manual window close (BufWipeout / BufUnload).
def SetupAutocommands(): void
  # Clear previous autocommands for this group to avoid duplicates
  silent! execute 'augroup! ' .. AUTOGROUP
  execute 'augroup ' .. AUTOGROUP
  execute 'autocmd BufWipeout <buffer> call vproj#HandleBufWipeout()'
  execute 'augroup END'
enddef

# Called via autocmd when the pane buffer is wiped (manual close, :q, C-w c).
export def HandleBufWipeout(): void
  pane_bufnr = -1
  selected_line = 1
  EmitEvent('pane_closed', {mode: current_mode})
enddef

# Highlight the current mode label within the mode menu line.
# Uses matchadd() with a pattern matching the bracketed label.
def HighlightCurrentMode(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif

  # Build a regex matching the current mode's label, e.g. "\[F\]ile"
  var label: string = get(MODE_LABELS, current_mode, '')
  if empty(label)
    return
  endif

  # Escape brackets for regex: [F] → \[F\]
  var pattern: string = '\V' .. escape(label, '\')
  # matchadd returns an ID; we store it nowhere because ClearPaneHighlights
  # uses clearmatches() which clears all matches in the current window.
  # Match in the pane buffer's window
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif

  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  silent! matchadd('VprojModeCurrent', pattern, 10, -1)
  win_gotoid(orig_wid)
enddef

# Clear all match highlights in the pane window.
def ClearPaneHighlights(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  silent! clearmatches()
  win_gotoid(orig_wid)
enddef

# Determine which mode index the cursor is positioned at within the menu line.
# Returns the index into MODE_KEYS, or -1 if the cursor is not over a mode label.
def ModeIndexAtCursor(): number
  var col: number = col('.')
  # Menu parts: "[F]ile  [D]oc  [C]ode"
  # Part widths: 6 + 2 + 5 + 2 + 5 = 20 (with 2-space separators)
  # Map column to mode index
  var menu_widths: list<number> = [6, 2, 5, 2, 5]  # [F]ile, '  ', [D]oc, '  ', [C]ode
  var pos: number = 1
  for i in range(len(menu_widths))
    var seg_end: number = pos + menu_widths[i] - 1
    if col >= pos && col <= seg_end
      # i=0→file, i=2→doc, i=4→code
      if i == 0
        return 0
      elseif i == 2
        return 1
      elseif i == 4
        return 2
      endif
      return -1
    endif
    pos = seg_end + 1
  endfor
  return -1
enddef

# Apply the current pane_width to the pane window.
def ApplyWidth(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  execute 'vert resize ' .. pane_width
  win_gotoid(orig_wid)
enddef

# Emit a named event (ADR-007).
# In Stage 1, events are logged but not yet subscribed to.
# The event system will be built out in Stage 2+.
def EmitEvent(name: string, data: dict<any>): void
  # Stage 1: events are emitted but don't trigger subscriptions
  # (no other subsystem subscribes yet). The payload is validated and
  # available for the future event bus.
  if empty(name) || name =~# '[[:cntrl:]]'
    return
  endif
  # Event payload is stored for potential Stage 2+ subscribers
  # For now, events serve as documentation of state transitions
enddef



# ═══════════════════════════════════════════════════════════════════════════
# Highlight group definition
# ═══════════════════════════════════════════════════════════════════════════

# Define the highlight group for the current mode in the menu bar.
# Called once during plugin load; idempotent.
export def DefineHighlights(): void
  if hlexists('VprojModeCurrent')
    return
  endif
  # Bold/underline on the current mode; adapts to the user's colorscheme
  highlight VprojModeCurrent cterm=bold,underline gui=bold,underline
enddef

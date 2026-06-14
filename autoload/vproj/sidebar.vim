vim9script

# autoload/vproj/sidebar.vim — vim9script sidebar window/buffer management
# Uses leftabove {width}vsplit (no floating windows — this is Vim, not Neovim).

# Module-level state
var WinId: number = 0
var BufNr: number = 0
var SidebarWidth: number = 35
var MainWinId: number = 0

# Set SidebarWidth from configuration dict.
export def Setup(cfg: dict<any>): void
  if has_key(cfg, 'width')
    SidebarWidth = cfg.width
  endif
enddef

# Create the scratch buffer and sidebar window.
export def Open(): void
  if IsOpen()
    return
  endif

  # Close orphaned window (buffer was lost but window still exists).
  CleanupOrphan()

  # Create a scratch buffer if we don't have one already.
  if BufNr <= 0 || !bufexists(BufNr)
    BufNr = bufadd('vproj://sidebar')
    if BufNr <= 0
      return
    endif
    setbufvar(BufNr, '&buftype', 'nofile')
    setbufvar(BufNr, '&bufhidden', 'wipe')
    setbufvar(BufNr, '&swapfile', false)
  endif

  # Remember the main editing window before creating the sidebar.
  MainWinId = win_getid(winnr())

  # Open the sidebar window: leftabove split with configured width.
  silent execute 'leftabove vsplit'
  silent execute 'vertical resize ' .. SidebarWidth
  silent execute 'buffer ' .. BufNr
  WinId = win_getid(winnr())

  # Window-local settings.
  setwinvar(WinId, '&winfixwidth', true)
  setwinvar(WinId, '&number', false)
  setwinvar(WinId, '&relativenumber', false)
  setwinvar(WinId, '&signcolumn', 'no')
  setwinvar(WinId, '&wrap', false)
enddef

# Close the sidebar: close the window, wipe the scratch buffer, reset state.
export def Close(): void
  if !IsOpen()
    return
  endif
  var win_id: number = WinId
  var buf: number = BufNr
  BufNr = 0
  WinId = 0

  # Close the window first. bufhidden=wipe will then clean up the buffer.
  if winnr('$') > 1 && win_id2win(win_id) > 0
    win_execute(win_id, 'close!')
  endif

  # Ensure the buffer is wiped even if closing the window didn't trigger it.
  if bufexists(buf)
    silent execute 'bwipeout! ' .. buf
  endif
enddef

# Check whether the sidebar window and buffer are both valid.
export def IsOpen(): bool
  return WinId > 0
      && win_id2win(WinId) > 0
      && BufNr > 0
      && bufexists(BufNr)
enddef

# Close an orphaned window whose scratch buffer was lost.
def CleanupOrphan(): void
  if WinId > 0 && win_id2win(WinId) > 0 && winnr('$') > 1
    win_execute(WinId, 'close!')
  endif
  WinId = 0
  if BufNr > 0 && !bufexists(BufNr)
    BufNr = 0
  endif
enddef

# Return the sidebar buffer number.
export def GetBuf(): number
  return BufNr
enddef

# Return the sidebar window ID.
export def GetWin(): number
  return WinId
enddef

# Return the main editing window ID (saved before sidebar was created).
export def GetMainWin(): number
  return MainWinId
enddef

# Toggle sidebar open/close.
export def Toggle(): void
  if IsOpen()
    Close()
  else
    Open()
  endif
enddef

vim9script

# Integration test: Buf mode — buffers, modification flags, selection
# Run: vim -N -u NONE -S tests/integration/test_buf_mode.vim

set rtp+=src
runtime! plugin/vproj.vim
set nomore
set shortmess+=A

var failures: number = 0

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneCursorLine(): number
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
enddef

def PaneText(lnum: number): string
  var pbuf = bufnr('VPROJ')
  var lines = getbufline(pbuf, lnum)
  return empty(lines) ? '' : lines[0]
enddef

echom '=== Buf Mode Integration Tests ==='

# Clean up stale swap files from previous runs
var test_files = ['/tmp/vproj_test_a.txt', '/tmp/vproj_test_b.txt', '/tmp/vproj_test_c.txt']
for tf in test_files
  var swap = '/tmp/.' .. fnamemodify(tf, ':t') .. '.swp'
  try
    if filereadable(swap)
      delete(swap)
    endif
  catch
  endtry
endfor

# ── Setup: open some buffers first ──
for tf in test_files
  try
    execute 'silent! edit! ' .. fnameescape(tf)
    write!
  catch
  endtry
endfor

# ── Open pane in buf mode ──
vproj#PaneOpen()
vproj#SwitchMode('buf')

Assert(vproj#GetCurrentMode() == 'buf', 'buf mode active')
Assert(PaneCursorLine() == 3, 'buf mode: cursor on first item (line 3)')

# ── Navigate through buffers ──
vproj#SelectNext()
Assert(PaneCursorLine() == 4, 'buf mode: SelectNext to line 4')

vproj#SelectPrev()
Assert(PaneCursorLine() == 3, 'buf mode: SelectPrev to line 3')

# ── Switch to buf mode from another mode ──
vproj#SwitchMode('file')
vproj#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'buf mode after round-trip: cursor on line 3')

# ── Jump to first/last ──
vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'buf mode: SelectFirst to line 3')

# ── NavigateUp in buf mode — verify listing changed, mode unchanged ──
var first_text_before = PaneText(PaneCursorLine())
vproj#NavigateUp()
var first_text_after = PaneText(PaneCursorLine())
Assert(first_text_before != first_text_after, 'NavigateUp in buf: listing changed')
Assert(vproj#IsPaneVisible(), 'NavigateUp in buf: pane stays visible')
Assert(vproj#GetCurrentMode() == 'buf', 'NavigateUp in buf mode: mode stays buf')

	# ── 	# ── CloseBuffer last buffer: verify placeholder appears (gap 3) ──
	# Close all buffers except VPROJ, then reopen in buf mode to see empty state
	vproj#PaneClose()
	# Wipe all test buffers
	for tf in test_files
	  try
	    execute 'bwipeout! ' .. fnameescape(tf)
	  catch
	  endtry
	endfor
	# Reopen in buf mode — should show empty placeholder
	vproj#PaneOpen()
	vproj#SwitchMode('buf')
	var lb_lines = getbufline(bufnr('VPROJ'), 1, '$')
	var has_placeholder = false
	for l in lb_lines
	  if l =~ '(no open buffers)'
	    has_placeholder = true
	    break
	  endif
	endfor
	Assert(has_placeholder, 'CloseBuffer last buf: "(no open buffers)" placeholder appears')
	Assert(vproj#IsPaneVisible(), 'CloseBuffer last buf: pane stays visible')
	vproj#PaneClose()
# ── Cleanup ──
vproj#PaneClose()
for tf in test_files
  try
    execute 'bwipeout! ' .. fnameescape(tf)
  catch
  endtry
endfor

echom ''
if failures == 0
  echom 'ALL BUF MODE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' BUF MODE TEST(S) FAILED.'
  echohl None
  cquit!
endif
call delete(expand('~/.cache/vproj/session'))
qa!

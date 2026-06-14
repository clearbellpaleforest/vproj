" tests/vim_spec/symbols_mode_spec.vim — Pure VimScript tests for vproj#symbols_mode#*
"
" Tests for the Symbols mode: Create, Refresh, RenderSym, SelectSym.

let g:CurrentTest = 'symbols_mode: Create returns mode dict with correct name/key/icon'
let s:mode = vproj#symbols_mode#Create({})
call g:AssertEquals(s:mode.name, 'Symbols', 'mode name is Symbols')
call g:AssertEquals(s:mode.key, 's', 'mode key is s')
call g:AssertEquals(s:mode.icon, 'S', 'mode icon is S')
call g:AssertTrue(s:mode.enabled, 'mode is enabled by default')

let g:CurrentTest = 'symbols_mode: mode dict has Refresh, Render, Select function keys'
call g:AssertTrue(has_key(s:mode, 'Refresh'), 'mode has Refresh key')
call g:AssertTrue(has_key(s:mode, 'Render'), 'mode has Render key')
call g:AssertTrue(has_key(s:mode, 'Select'), 'mode has Select key')

let g:CurrentTest = 'symbols_mode: Refresh handles no file open gracefully'
call vproj#symbols_mode#Refresh()
let s:render_result = vproj#symbols_mode#RenderSym()
call g:AssertTrue(has_key(s:render_result, 'label_map'), 'RenderSym result has label_map')
call g:AssertEquals(len(s:render_result.label_map), 1, 'label_map has 1 entry for fallback item')

let g:CurrentTest = 'symbols_mode: RenderSym returns label_map and lines with source annotation'
call g:AssertTrue(has_key(s:render_result, 'lines'), 'RenderSym result has lines')
call g:AssertEquals(s:render_result.lines[0], 'Source: ctags', 'first line is source annotation')
call g:AssertEquals(len(s:render_result.lines), 3, 'lines has 3 entries (source, blank, label)')

let g:CurrentTest = 'symbols_mode: SelectSym with unknown label returns v:null'
call g:AssertEquals(vproj#symbols_mode#SelectSym('nonexistent'), v:null, 'unknown label returns v:null')

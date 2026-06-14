" tests/vim_spec/outline_mode_spec.vim -- Pure VimScript tests for nam#outline_mode#*
"
" Validates the outline mode lifecycle: Create, Refresh (parsing), RenderOut
" (label generation), and SelectOut (jump dispatch).

" ---------------------------------------------------------------------------
" Test 1: Create returns valid mode dict with correct name/key/icon
" ---------------------------------------------------------------------------

let g:CurrentTest = 'outline: Create returns mode dict with correct name/key/icon'
let s:mode = nam#outline_mode#Create({})
call g:AssertEquals(s:mode.name, 'Outline', 'name should be Outline')
call g:AssertEquals(s:mode.key, 'o', 'key should be o')
call g:AssertEquals(s:mode.icon, 'O', 'icon should be O')

" ---------------------------------------------------------------------------
" Test 2: Mode dict has Refresh, Render, Select function references
" ---------------------------------------------------------------------------

let g:CurrentTest = 'outline: mode dict has Refresh, Render, Select keys'
call g:AssertTrue(has_key(s:mode, 'Refresh'), 'mode should have Refresh key')
call g:AssertTrue(has_key(s:mode, 'Render'), 'mode should have Render key')
call g:AssertTrue(has_key(s:mode, 'Select'), 'mode should have Select key')

" Verify the values are Funcrefs (type 2 in legacy VimScript)
call g:AssertEquals(type(s:mode.Refresh), 2, 'Refresh should be a Funcref')
call g:AssertEquals(type(s:mode.Render), 2, 'Render should be a Funcref')
call g:AssertEquals(type(s:mode.Select), 2, 'Select should be a Funcref')

" ---------------------------------------------------------------------------
" Test 3: Refresh handles empty buffer gracefully
" ---------------------------------------------------------------------------

let g:CurrentTest = 'outline: Refresh on empty buffer completes without error'
let s:ok = v:true
try
  call nam#outline_mode#Refresh()
catch
  let s:ok = v:false
endtry
call g:AssertTrue(s:ok, 'Refresh on empty buffer should not throw')

" ---------------------------------------------------------------------------
" Test 4: RenderOut returns label_map and lines
" ---------------------------------------------------------------------------

let g:CurrentTest = 'outline: RenderOut returns label_map and lines'
let s:result = nam#outline_mode#RenderOut()
call g:AssertTrue(has_key(s:result, 'label_map'), 'RenderOut result should have label_map')
call g:AssertTrue(has_key(s:result, 'lines'), 'RenderOut result should have lines')
call g:AssertEquals(type(s:result.label_map), 4, 'label_map should be a dict')
call g:AssertEquals(type(s:result.lines), 3, 'lines should be a list')

" ---------------------------------------------------------------------------
" Test 5: SelectOut with unknown label returns v:null
" ---------------------------------------------------------------------------

let g:CurrentTest = 'outline: SelectOut with unknown label returns v:null'
let s:rv = nam#outline_mode#SelectOut('ZZ_NONEXISTENT')
call g:AssertEquals(s:rv, v:null, 'unknown label should return v:null')

let g:CurrentTest = 'outline: SelectOut with empty string returns v:null'
let s:rv = nam#outline_mode#SelectOut('')
call g:AssertEquals(s:rv, v:null, 'empty string label should return v:null')

" vim: ts=2 sw=2 et

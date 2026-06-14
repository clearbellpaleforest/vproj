" tests/vim_spec/buffers_mode_spec.vim — Pure VimScript tests for nam#buffers_mode#*

let g:CurrentTest = 'buffers_mode: create returns mode dict with correct values'
let cfg = {'modes': {'buffers': {'enabled': v:true}}}
let mode = nam#buffers_mode#Create(cfg)
call g:AssertEquals(mode.name, 'Buffers', 'mode name is Buffers')
call g:AssertEquals(mode.key, 'b', 'mode key is b')
call g:AssertEquals(mode.icon, 'B', 'mode icon is B')

let g:CurrentTest = 'buffers_mode: mode dict has Refresh, Render, Select'
call g:AssertTrue(has_key(mode, 'Refresh'), 'mode has Refresh key')
call g:AssertTrue(has_key(mode, 'Render'), 'mode has Render key')
call g:AssertTrue(has_key(mode, 'Select'), 'mode has Select key')

let g:CurrentTest = 'buffers_mode: refresh runs without error'
try
  call mode.Refresh()
  call g:AssertTrue(v:true, 'Refresh completed without exception')
catch
  call g:AssertTrue(v:false, 'Refresh threw exception: ' .. v:exception)
endtry

let g:CurrentTest = 'buffers_mode: render returns dict with label_map and lines keys'
let result = mode.Render()
call g:AssertTrue(has_key(result, 'label_map'), 'render result has label_map key')
call g:AssertTrue(has_key(result, 'lines'), 'render result has lines key')

let g:CurrentTest = 'buffers_mode: select with unknown label returns v:null'
let sel_result = mode.Select('ZZ')
call g:AssertTrue(sel_result is v:null, 'unknown label select returns v:null')

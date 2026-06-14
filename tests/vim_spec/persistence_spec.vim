" tests/vim_spec/persistence_spec.vim — Pure VimScript tests for vproj#persistence#*

let g:CurrentTest = 'persistence: Setup without auto_restore or auto_save'
call vproj#persistence#Setup({'workspace': {}})
call g:AssertTrue(1, 'Setup completed without error')

let g:CurrentTest = 'persistence: GetState returns dict with required keys'
let state = vproj#persistence#GetState()
call g:AssertTrue(type(state) == v:t_dict, 'GetState returns a dict')
call g:AssertTrue(has_key(state, 'version'), 'state has key: version')
call g:AssertTrue(has_key(state, 'timestamp'), 'state has key: timestamp')
call g:AssertTrue(has_key(state, 'buffers'), 'state has key: buffers')
call g:AssertTrue(has_key(state, 'cursor_positions'), 'state has key: cursor_positions')

let g:CurrentTest = 'persistence: GetState version is 2'
let state = vproj#persistence#GetState()
call g:AssertEquals(state.version, 2, 'version equals 2')

let g:CurrentTest = 'persistence: GetState buffers is a list'
let state = vproj#persistence#GetState()
call g:AssertTrue(type(state.buffers) == v:t_list, 'buffers is a list')

let g:CurrentTest = 'persistence: Save with empty project_root returns true'
let result = vproj#persistence#Save('')
call g:AssertTrue(result, 'Save returned true')
call vproj#persistence#Clear('')

let g:CurrentTest = 'persistence: Restore with nonexistent session returns false'
let result = vproj#persistence#Restore('/nonexistent/vproj/testing/unused')
call g:AssertFalse(result, 'Restore returned false for nonexistent session')

let g:CurrentTest = 'persistence: Clear with empty project_root does not error'
call vproj#persistence#Clear('')
call g:AssertTrue(1, 'Clear with empty project_root completed without error')

let g:CurrentTest = 'persistence: ClearAll does not error'
call vproj#persistence#ClearAll()
call g:AssertTrue(1, 'ClearAll completed without error')

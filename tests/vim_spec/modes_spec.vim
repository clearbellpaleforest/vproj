" tests/vim_spec/modes_spec.vim — Pure VimScript tests for nam#modes#*

" Setup modes registry with clean state
call nam#modes#Setup({}, {})

let mode1 = {'name': 'Test1', 'key': 't', 'icon': 'T', 'enabled': v:true, 'Refresh': {-> 0}, 'Render': {-> {}}, 'Select': {label -> v:true}}
let mode2 = {'name': 'Test2', 'key': 'u', 'icon': 'U', 'enabled': v:false, 'Refresh': {-> 0}, 'Render': {-> {}}, 'Select': {label -> v:true}}

call nam#modes#Register(mode1)
call nam#modes#Register(mode2)

let g:CurrentTest = 'modes: get returns registered mode'
let m = nam#modes#Get('t')
call g:AssertEquals(m.name, 'Test1', 'get returns correct mode')

let g:CurrentTest = 'modes: get default returns first enabled'
let m = nam#modes#GetDefault()
call g:AssertEquals(m.key, 't', 'default is first enabled mode')

let g:CurrentTest = 'modes: switch returns mode'
let m = nam#modes#Switch('t')
call g:AssertEquals(m.key, 't', 'switch returns mode')
let cur = nam#modes#GetCurrent()
call g:AssertEquals(cur.key, 't', 'get_current matches switched mode')

let g:CurrentTest = 'modes: all returns list'
let all = nam#modes#All()
call g:AssertEquals(len(all), 2, 'all returns 2 modes')

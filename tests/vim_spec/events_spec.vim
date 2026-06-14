" tests/vim_spec/events_spec.vim — Pure VimScript tests for nam#events#*
"
" Uses simple integer-returning lambdas ({data -> 0}) for callback args
" to maintain compatibility with vim9script func(dict<any>) parameter types.

let g:CurrentTest = 'events: On returns positive id'
call nam#events#Clear()
let s:id = nam#events#On('test_emit', {data -> 0})
call g:AssertTrue(s:id > 0, 'On should return positive id')

let g:CurrentTest = 'events: consecutive On calls return different ids'
let s:id2 = nam#events#On('test_emit', {data -> 0})
call g:AssertNotEquals(s:id2, s:id, 'consecutive On calls return different ids')

let g:CurrentTest = 'events: Clear resets ID counter'
call nam#events#Clear()
let s:id3 = nam#events#On('test_clear', {data -> 0})
call g:AssertEquals(s:id3, 1, 'after Clear, On returns 1')

let g:CurrentTest = 'events: Emit with listener does not error'
let s:ok = v:true
try
  call nam#events#Emit('test_emit', {})
catch
  let s:ok = v:false
endtry
call g:AssertTrue(s:ok, 'Emit with listener should not error')

let g:CurrentTest = 'events: Emit with no listeners does not error'
let s:ok = v:true
try
  call nam#events#Emit('nonexistent_event', {})
catch
  let s:ok = v:false
endtry
call g:AssertTrue(s:ok, 'Emit with no listeners should not error')

let g:CurrentTest = 'events: Off removes listener'
call nam#events#Clear()
let s:off_id = nam#events#On('off_test', {data -> 0})
let s:ok = v:true
try
  call nam#events#Off('off_test', s:off_id)
catch
  let s:ok = v:false
endtry
call g:AssertTrue(s:ok, 'Off should not error')

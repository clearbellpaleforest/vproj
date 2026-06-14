" navigation_spec.vim -- VimScript tests for nam#navigation# (Direct Selection Navigation)
"
" Tests: handler dispatch, no-handler fallback, handler replacement, setup, false propagation.

" ---------------------------------------------------------------------------
" Handler definitions (used across tests)
" ---------------------------------------------------------------------------

" Records call and label into globals for assertion
function! s:RecordHandler(label) abort
  let g:handler_called = 1
  let g:handler_label = a:label
  return 1
endfunction

" First handler for replacement test (should NOT be called)
function! s:FirstHandler(label) abort
  let g:first_called = 1
  return 1
endfunction

" Second handler for replacement test (should be called)
function! s:SecondHandler(label) abort
  let g:second_called = 1
  return 1
endfunction

" Always-false handler for false-propagation test
function! s:FalseHandler(label) abort
  return 0
endfunction

" ---------------------------------------------------------------------------
" Test 1: setup() initializes without error
" ---------------------------------------------------------------------------
function! s:TestSetup() abort
  let g:CurrentTest = 'navigation setup'
  let events_mod = {}
  let cfg = {'labels': {'tiers': ['1234567890'], 'overflow_style': 'double'}}
  call nam#navigation#Setup(cfg, events_mod)
  call g:AssertTrue(1, 'navigation.setup() completes without error')
endfunction

" ---------------------------------------------------------------------------
" Test 2: dispatch() returns false with no handler set
" ---------------------------------------------------------------------------
function! s:TestNoHandler() abort
  let g:CurrentTest = 'navigation no handler'
  call nam#navigation#ResetHandler()
  let result = nam#navigation#Dispatch('1')
  call g:AssertFalse(result, 'dispatch() returns false with no handler')
endfunction

" ---------------------------------------------------------------------------
" Test 3: set_handler() and dispatch() work correctly
" ---------------------------------------------------------------------------
function! s:TestHandlerDispatch() abort
  let g:CurrentTest = 'navigation handler dispatch'
  let g:handler_called = 0
  let g:handler_label = ''
  call nam#navigation#SetHandler(function('s:RecordHandler'))
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(g:handler_called, 'dispatch() calls the handler')
  call g:AssertEquals(g:handler_label, '1', 'dispatch() forwards the label to handler')
  call g:AssertTrue(result, 'dispatch() returns handler result')
endfunction

" ---------------------------------------------------------------------------
" Test 4: set_handler() replaces previous handler
" ---------------------------------------------------------------------------
function! s:TestHandlerReplace() abort
  let g:CurrentTest = 'navigation handler replace'
  let g:first_called = 0
  let g:second_called = 0
  call nam#navigation#SetHandler(function('s:FirstHandler'))
  call nam#navigation#SetHandler(function('s:SecondHandler'))
  call nam#navigation#Dispatch('1')
  call g:AssertFalse(g:first_called, 'set_handler() replaces first handler')
  call g:AssertTrue(g:second_called, 'second handler is called after replacement')
endfunction

" ---------------------------------------------------------------------------
" Test 5: dispatch with handler that returns false propagates false
" ---------------------------------------------------------------------------
function! s:TestHandlerReturnsFalse() abort
  let g:CurrentTest = 'navigation handler returns false'
  call nam#navigation#SetHandler(function('s:FalseHandler'))
  let result = nam#navigation#Dispatch('x')
  call g:AssertFalse(result, 'dispatch() returns false when handler returns false')
endfunction

" ---------------------------------------------------------------------------
" Run tests (order matters: no-handler test must run before any SetHandler call)
" ---------------------------------------------------------------------------
call s:TestSetup()
call s:TestNoHandler()
call s:TestHandlerDispatch()
call s:TestHandlerReplace()
call s:TestHandlerReturnsFalse()
" vim: ts=2 sw=2 et

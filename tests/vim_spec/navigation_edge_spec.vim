" navigation_edge_spec.vim -- Pure VimScript edge case tests for nam#navigation#*
"
" Tests: key handling edge cases, dispatch edge cases, mode dispatch
" integration, buffer state and keymap lifecycle, error resilience.
"
" Requires Vim 9.0+ (for vim9script autoload call compatibility).

" ===========================================================================
" Script-level test-state helpers
" ===========================================================================

let s:received = ''
function s:record_label(label) abort
  let s:received = a:label
  return v:true
endfunction

let s:count = 0
function s:count_calls(label) abort
  let s:count += 1
  return v:true
endfunction

let s:first_called = v:false
function s:mark_first(label) abort
  let s:first_called = v:true
  return v:true
endfunction

let s:second_called = v:false
function s:mark_second(label) abort
  let s:second_called = v:true
  return v:true
endfunction

function s:throw_error(label) abort
  throw 'intentional crash'
endfunction

let s:shared_state = {'count': 0, 'last': ''}
function s:update_shared(label) abort
  let s:shared_state.count += 1
  let s:shared_state.last = a:label
  return v:true
endfunction

let s:ok = v:true

" ===========================================================================
" Key handling edge cases
" ===========================================================================

function! s:TestAttachInvalidBuffer() abort
  let g:CurrentTest = 'navigation_attach: invalid buffer'
  let cfg = {'labels': {'tiers': ['1234567890'], 'overflow_style': 'double'}}
  call nam#navigation#Setup(cfg, {})

  " attach with non-existent buffer number should not error
  let s:ok = v:true
  try
    call nam#navigation#Attach(99999)
  catch
    let s:ok = v:false
  endtry
  call g:AssertTrue(s:ok, 'attach(99999) does not error')
endfunction

function! s:TestAttachBeforeSetup() abort
  let g:CurrentTest = 'navigation_attach: before setup'
  " Attach before Setup: TierChars defaults to empty list, so only
  " the non-tier keymaps are created.  Should not error.
  let s:ok = v:true
  try
    call nam#navigation#Attach(1)
  catch
    let s:ok = v:false
  endtry
  call g:AssertTrue(s:ok, 'attach before setup() does not error')
endfunction

function! s:TestAttachNilTiers() abort
  let g:CurrentTest = 'navigation_attach: null tiers'
  " Setup with null tiers iterates over v:null, which errors.  We test
  " that the error is raised (the Lua counterpart handled nil gracefully;
  " the Vim9Script implementation does not iterate over null).
  let s:has_error = v:false
  try
    call nam#navigation#Setup({'labels': {'tiers': v:null, 'overflow_style': 'double'}}, {})
  catch
    let s:has_error = v:true
  endtry
  call g:AssertTrue(s:has_error, 'Setup with null tiers raises an error')
endfunction

function! s:TestAttachEmptyTiers() abort
  let g:CurrentTest = 'navigation_attach: empty tiers'
  call nam#navigation#Setup({'labels': {'tiers': [], 'overflow_style': 'double'}}, {})

  let s:ok = v:true
  try
    call nam#navigation#Attach(1)
  catch
    let s:ok = v:false
  endtry
  call g:AssertTrue(s:ok, 'attach with empty tiers does not error')
endfunction

" ===========================================================================
" Dispatch edge cases
" ===========================================================================

function! s:TestDispatchEdgeCases() abort
  " Use a config with known tiers so TierChars is populated
  let cfg = {'labels': {'tiers': ['1234567890'], 'overflow_style': 'double'}}
  call nam#navigation#Setup(cfg, {})

  " 1. handler receives correct label
  let g:CurrentTest = 'dispatch: correct label forwarding'
  let s:received = ''
  call nam#navigation#SetHandler({label -> s:record_label(label)})
  call nam#navigation#Dispatch('a')
  call g:AssertEquals(s:received, 'a', 'dispatch("a") forwards "a" to handler')

  " 2. handler receives multi-char label
  let g:CurrentTest = 'dispatch: multi-char label'
  let s:received = ''
  call nam#navigation#Dispatch('aa')
  call g:AssertEquals(s:received, 'aa', 'dispatch("aa") forwards "aa" to handler')

  " 3. handler receives empty string
  let g:CurrentTest = 'dispatch: empty string'
  let s:received = ''
  call nam#navigation#Dispatch('')
  call g:AssertEquals(s:received, '', 'dispatch("") forwards empty string to handler')

  " 4. handler returning false through dispatch
  let g:CurrentTest = 'dispatch: handler returns false'
  call nam#navigation#SetHandler({label -> v:false})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:false, 'dispatch returns false when handler returns false')

  " 5. handler returning null through dispatch
  let g:CurrentTest = 'dispatch: handler returns null'
  call nam#navigation#SetHandler({label -> v:null})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:null, 'dispatch returns null when handler returns null')

  " 6. handler returning true through dispatch
  let g:CurrentTest = 'dispatch: handler returns true'
  call nam#navigation#SetHandler({label -> v:true})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:true, 'dispatch returns true when handler returns true')

  " 7. no handler returns false
  let g:CurrentTest = 'dispatch: no handler'
  call nam#navigation#SetHandler(v:null)
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:false, 'dispatch returns false with no handler')

  " 8. handler replacement
  let g:CurrentTest = 'dispatch: handler replacement'
  let s:first_called = v:false
  let s:second_called = v:false
  call nam#navigation#SetHandler({label -> s:mark_first(label)})
  call nam#navigation#SetHandler({label -> s:mark_second(label)})
  call nam#navigation#Dispatch('1')
  call g:AssertFalse(s:first_called, 'set_handler() replaces previous handler')
  call g:AssertTrue(s:second_called, 'replacement handler is called after set_handler()')

  " 9. 50 rapid dispatch calls
  let g:CurrentTest = 'dispatch: 50 rapid calls'
  let s:count = 0
  call nam#navigation#SetHandler({label -> s:count_calls(label)})
  for i in range(50)
    call nam#navigation#Dispatch(string(i))
  endfor
  call g:AssertEquals(s:count, 50, '50 rapid dispatch calls all succeed')
endfunction

" ===========================================================================
" Mode dispatch integration
" ===========================================================================

function! s:TestModeDispatchIntegration() abort
  let g:CurrentTest = 'mode_dispatch: setup'
  call nam#modes#Setup({}, {})
  let cfg = {'labels': {'tiers': ['1234567890'], 'overflow_style': 'double'}}
  call nam#navigation#Setup(cfg, {})

  " Register a mode with a label_map
  let s:mode_t = {'key': 't', 'name': 'Test', 'enabled': v:true,
      \ 'label_map': {'a': {'name': 'item_a'}}}
  call nam#modes#Register(s:mode_t)
  call nam#modes#Switch('t')

  " 1. handler dispatches a label found in the current mode's label_map
  let g:CurrentTest = 'mode_dispatch: valid label'
  call nam#navigation#SetHandler({label ->
      \ has_key(s:mode_t.label_map, label) ? v:true : v:false})
  let result = nam#navigation#Dispatch('a')
  call g:AssertTrue(result is v:true, 'dispatch returns true for valid mode label')

  " 2. handler dispatches an unregistered label
  let g:CurrentTest = 'mode_dispatch: unregistered label'
  let result = nam#navigation#Dispatch('zz')
  call g:AssertTrue(result is v:false, 'dispatch returns false for unregistered label')

  " 3. handler dispatches empty string
  let g:CurrentTest = 'mode_dispatch: empty label'
  let result = nam#navigation#Dispatch('')
  call g:AssertTrue(result is v:false, 'dispatch returns false for empty label')

  " 4. handler dispatches whitespace
  let g:CurrentTest = 'mode_dispatch: whitespace label'
  let result = nam#navigation#Dispatch(' ')
  call g:AssertTrue(result is v:false, 'dispatch returns false for whitespace label')

  " 5. handler falls back to mode registry when current mode returns false
  let g:CurrentTest = 'mode_dispatch: fallback to registry'
  let s:mode_a = {'key': 'a', 'name': 'ModeA', 'enabled': v:true, 'label_map': {}}
  let s:mode_b = {'key': 'b', 'name': 'ModeB', 'enabled': v:true, 'label_map': {}}
  call nam#modes#Register(s:mode_a)
  call nam#modes#Register(s:mode_b)
  call nam#modes#Switch('a')

  call nam#navigation#SetHandler({label ->
      \ has_key(s:mode_a.label_map, label) ? v:true :
      \ !empty(nam#modes#Get(label)) ? v:true : v:false})
  let result = nam#navigation#Dispatch('b')
  call g:AssertTrue(result is v:true, 'fallback: mode key lookup succeeds via registry')

  " 6. mode with no label_map -- missing key gracefully returns false
  let g:CurrentTest = 'mode_dispatch: mode lacks label_map'
  let s:mode_nil = {'key': 'n', 'name': 'Nil', 'enabled': v:true}
  call nam#modes#Register(s:mode_nil)
  call nam#navigation#SetHandler({label ->
      \ has_key(get(s:mode_nil, {}, 'label_map'), label) ? v:true : v:false})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:false,
      \ 'dispatch returns false for mode with no label_map')

  " 7. mode with empty label_map
  let g:CurrentTest = 'mode_dispatch: empty label_map'
  let s:mode_empty = {'key': 'e', 'name': 'Empty', 'enabled': v:true, 'label_map': {}}
  call nam#modes#Register(s:mode_empty)
  call nam#navigation#SetHandler({label ->
      \ has_key(s:mode_empty.label_map, label) ? v:true : v:false})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:false,
      \ 'dispatch returns false for mode with empty label_map')
endfunction

" ===========================================================================
" Error resilience
" ===========================================================================

function! s:TestErrorResilience() abort
  let g:CurrentTest = 'error_resilience: setup'
  let cfg = {'labels': {'tiers': ['1234567890'], 'overflow_style': 'double'}}
  call nam#navigation#Setup(cfg, {})

  " 1. handler errors are caught by Dispatch and return false
  let g:CurrentTest = 'error_resilience: handler error caught'
  call nam#navigation#SetHandler({label -> s:throw_error(label)})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:false,
      \ 'dispatch catches handler error and returns false')

  " 2. dispatch after re-setup with a fresh handler
  let g:CurrentTest = 'error_resilience: after re-setup'
  call nam#navigation#Setup(cfg, {})
  call nam#navigation#SetHandler({label -> v:true})
  let result = nam#navigation#Dispatch('x')
  call g:AssertTrue(result is v:true,
      \ 'dispatch works after re-setup with new handler')

  " 3. dispatch continues to work after a handler error
  let g:CurrentTest = 'error_resilience: dispatch after error'
  call nam#navigation#SetHandler({label ->
      \ label == 'bad' ? s:throw_error(label) : v:true})
  call nam#navigation#Dispatch('bad')
  let result = nam#navigation#Dispatch('good')
  call g:AssertTrue(result is v:true,
      \ 'dispatch works after previous handler error')

  " 4. handler can be replaced after a previous handler error
  let g:CurrentTest = 'error_resilience: handler replacement after error'
  call nam#navigation#SetHandler({label -> v:true})
  let result = nam#navigation#Dispatch('1')
  call g:AssertTrue(result is v:true,
      \ 'set_handler and dispatch work after replacing error-throwing handler')

  " 5. state isolation between dispatch calls
  let g:CurrentTest = 'error_resilience: state isolation'
  call nam#navigation#SetHandler({label -> s:update_shared(label)})
  let s:shared_state = {'count': 0, 'last': ''}
  call nam#navigation#Dispatch('a')
  call nam#navigation#Dispatch('b')
  call g:AssertEquals(s:shared_state.count, 2,
      \ 'handler state: count is 2 after two dispatches')
  call g:AssertEquals(s:shared_state.last, 'b',
      \ 'handler state: last label is "b"')
endfunction

" ===========================================================================
" Run all tests
" ===========================================================================
call s:TestAttachInvalidBuffer()
call s:TestAttachBeforeSetup()
call s:TestAttachNilTiers()
call s:TestAttachEmptyTiers()
call s:TestDispatchEdgeCases()
call s:TestModeDispatchIntegration()
call s:TestErrorResilience()
" vim: ts=2 sw=2 et

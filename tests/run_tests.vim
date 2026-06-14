" tests/run_tests.vim — Simple VimScript test runner for Nam
" Usage: vim -u NONE -S tests/run_tests.vim

set nocompatible
set nomore
set rtp+=.

let g:TestsPassed = 0
let g:TestsFailed = 0
let g:TestsErrors = 0
let g:CurrentTest = ''

function! g:AssertTrue(condition, msg)
  if a:condition
    let g:TestsPassed += 1
    echo '  [OK] ' .. g:CurrentTest .. ' - ' .. a:msg
  else
    let g:TestsFailed += 1
    echo '  [FAIL] ' .. g:CurrentTest .. ' - ' .. a:msg
  endif
endfunction

function! g:AssertFalse(condition, msg)
  if !a:condition
    let g:TestsPassed += 1
    echo '  [OK] ' .. g:CurrentTest .. ' - ' .. a:msg
  else
    let g:TestsFailed += 1
    echo '  [FAIL] ' .. g:CurrentTest .. ' - ' .. a:msg
  endif
endfunction

function! g:AssertEquals(actual, expected, msg)
  if a:actual == a:expected
    let g:TestsPassed += 1
    echo '  [OK] ' .. g:CurrentTest .. ' - ' .. a:msg
  else
    let g:TestsFailed += 1
    echo '  [FAIL] ' .. g:CurrentTest .. ' - ' .. a:msg . ' (expected: ' .. string(a:expected) .. ', got: ' .. string(a:actual) .. ')'
  endif
endfunction

function! g:AssertNotEquals(actual, expected, msg)
  if a:actual != a:expected
    let g:TestsPassed += 1
    echo '  [OK] ' .. g:CurrentTest .. ' - ' .. a:msg
  else
    let g:TestsFailed += 1
    echo '  [FAIL] ' .. g:CurrentTest .. ' - ' .. a:msg
  endif
endfunction

" Source all test spec files
let s:spec_dir = expand('<sfile>:p:h') .. '/vim_spec'
let s:spec_files = split(glob(s:spec_dir .. '/*.vim'), '\n')
for s:file in s:spec_files
  execute 'source ' .. s:file
endfor

echo '========================================'
echo '  Nam VimScript Test Results'
echo '========================================'
echo '  Passed: ' .. g:TestsPassed
echo '  Failed: ' .. g:TestsFailed
echo '  Errors: ' .. g:TestsErrors
echo '========================================'

if g:TestsFailed > 0 || g:TestsErrors > 0
  cquit!
else
  qall!
endif

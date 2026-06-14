" tests/vim_spec/git_mode_spec.vim — Pure VimScript tests for vproj#git_mode#*
"
" Tests: Create returns valid mode dict, Refresh with v:null (not a git repo),
" Create includes action funcrefs, RenderGit in empty state,
" SelectGit with unknown label.

" ============================================================================
" Test 1: Create returns valid mode dict with correct name/key/icon
" ============================================================================
let g:CurrentTest = 'git_mode: Create returns valid mode dict with name, key, icon'
let s:mode = vproj#git_mode#Create({})
call g:AssertEquals(s:mode.name, 'Git', 'mode name should be Git')
call g:AssertEquals(s:mode.key, 'g', 'mode key should be g')
call g:AssertEquals(s:mode.icon, 'G', 'mode icon should be G')
call g:AssertTrue(s:mode.enabled, 'mode enabled should default to true')

" ============================================================================
" Test 2: Refresh when not in git repo sets error item
" ============================================================================
let g:CurrentTest = 'git_mode: Refresh sets error item when not in git repo'
" Mock vproj#git#GetStatus to return v:null (simulating no git repository)
if exists('*vproj#git#GetStatus')
  delfunction! vproj#git#GetStatus
endif
function! vproj#git#GetStatus()
  return v:null
endfunction

call vproj#git_mode#Create({})
call vproj#git_mode#Refresh()
call vproj#git_mode#RenderGit()

" The error item should be selectable by label '1' and return false
let s:select_result = vproj#git_mode#SelectGit('1')
call g:AssertEquals(s:select_result, v:false,
    \ 'SelectGit on error item returns false')

" Delete mock so the next call to GetStatus triggers autoload of the real fn
delfunction! vproj#git#GetStatus

" ============================================================================
" Test 3: Create returns mode with StageFile/UnstageFile/ShowDiff actions
" ============================================================================
let g:CurrentTest =
    \ 'git_mode: Create returns mode with StageFile/UnstageFile/ShowDiff'
let s:mode = vproj#git_mode#Create({})
call g:AssertTrue(type(s:mode.StageFile) == v:t_func,
    \ 'mode.StageFile is a Funcref')
call g:AssertTrue(type(s:mode.UnstageFile) == v:t_func,
    \ 'mode.UnstageFile is a Funcref')
call g:AssertTrue(type(s:mode.ShowDiff) == v:t_func,
    \ 'mode.ShowDiff is a Funcref')
call g:AssertTrue(type(s:mode.Refresh) == v:t_func,
    \ 'mode.Refresh is a Funcref')
call g:AssertTrue(type(s:mode.Render) == v:t_func,
    \ 'mode.Render is a Funcref')
call g:AssertTrue(type(s:mode.Select) == v:t_func,
    \ 'mode.Select is a Funcref')

" ============================================================================
" Test 4: RenderGit in empty state returns label_map and lines
" ============================================================================
let g:CurrentTest =
    \ 'git_mode: RenderGit in empty state returns label_map and lines'
call vproj#git_mode#Create({})
let s:render_result = vproj#git_mode#RenderGit()
call g:AssertTrue(has_key(s:render_result, 'label_map'),
    \ 'render result has label_map')
call g:AssertTrue(has_key(s:render_result, 'lines'),
    \ 'render result has lines')
call g:AssertEquals(len(s:render_result.lines), 1,
    \ 'render produces 1 placeholder line')
call g:AssertEquals(len(keys(s:render_result.label_map)), 1,
    \ 'label_map has 1 entry')

" ============================================================================
" Test 5: SelectGit with unknown label returns v:null
" ============================================================================
let g:CurrentTest =
    \ 'git_mode: SelectGit with unknown label returns v:null'
call vproj#git_mode#Create({})
call vproj#git_mode#Refresh()
call vproj#git_mode#RenderGit()
let s:select_null = vproj#git_mode#SelectGit('__nonexistent_label__')
call g:AssertEquals(s:select_null, v:null,
    \ 'unknown label select returns v:null')
" vim: ts=2 sw=2 et

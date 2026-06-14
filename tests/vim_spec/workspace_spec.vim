" tests/vim_spec/workspace_spec.vim — Pure VimScript tests for vproj#workspace#*

" ──────────────────────────────
" Workspace Setup
" ──────────────────────────────

let g:CurrentTest = 'workspace: Setup initializes pins to empty'
call vproj#workspace#Setup({})
call g:AssertEquals(vproj#workspace#GetPinned(), [], 'pins empty after Setup')

let g:CurrentTest = 'workspace: Setup initializes bookmarks to empty'
call g:AssertEquals(vproj#workspace#GetBookmarks(), [], 'bookmarks empty after Setup')

let g:CurrentTest = 'workspace: Setup initializes recent symbols to empty'
call g:AssertEquals(vproj#workspace#GetRecentSymbols(), [], 'recent symbols empty after Setup')

" ──────────────────────────────
" PinBuffer
" ──────────────────────────────

let g:CurrentTest = 'workspace: PinBuffer returns true'
call vproj#workspace#Setup({})
let s:tmp = tempname()
execute 'edit ' . s:tmp
let s:result = vproj#workspace#PinBuffer()
call g:AssertTrue(s:result, 'PinBuffer returns true for current buffer')
execute 'bwipe! ' . s:tmp
unlet s:tmp s:result

" ──────────────────────────────
" UnpinBuffer
" ──────────────────────────────

let g:CurrentTest = 'workspace: UnpinBuffer on unpinned buffer returns false'
call vproj#workspace#Setup({})
let s:result = vproj#workspace#UnpinBuffer()
call g:AssertFalse(s:result, 'UnpinBuffer returns false when buffer not pinned')
unlet s:result

" ──────────────────────────────
" IsPinned
" ──────────────────────────────

let g:CurrentTest = 'workspace: IsPinned returns true for pinned path'
call vproj#workspace#Setup({})
let s:tmp = tempname()
execute 'edit ' . s:tmp
call vproj#workspace#PinBuffer()
call g:AssertTrue(vproj#workspace#IsPinned(s:tmp), 'IsPinned returns true after PinBuffer')
execute 'bwipe! ' . s:tmp
unlet s:tmp

" ──────────────────────────────
" GetPinned returns copy
" ──────────────────────────────

let g:CurrentTest = 'workspace: GetPinned returns copy not reference'
call vproj#workspace#Setup({})
let s:tmp_a = tempname()
let s:tmp_b = tempname()
execute 'edit ' . s:tmp_a
call vproj#workspace#PinBuffer()
execute 'edit ' . s:tmp_b
call vproj#workspace#PinBuffer()
let s:pins_copy = vproj#workspace#GetPinned()
call remove(s:pins_copy, 0)
call g:AssertEquals(len(vproj#workspace#GetPinned()), 2,
      \ 'internal pins unchanged after modifying returned copy')
execute 'bwipe! ' . s:tmp_a
execute 'bwipe! ' . s:tmp_b
unlet s:tmp_a s:tmp_b s:pins_copy

" ──────────────────────────────
" AddBookmark
" ──────────────────────────────

let g:CurrentTest = 'workspace: AddBookmark returns true'
call vproj#workspace#Setup({})
let s:tmp = tempname()
execute 'edit ' . s:tmp
let s:result = vproj#workspace#AddBookmark('test-bm')
call g:AssertTrue(s:result, 'AddBookmark returns true')
execute 'bwipe! ' . s:tmp
unlet s:tmp s:result

let g:CurrentTest = 'workspace: GetBookmarks includes added bookmark'
let s:bms = vproj#workspace#GetBookmarks()
call g:AssertEquals(len(s:bms), 1, 'one bookmark exists')
call g:AssertEquals(s:bms[0].name, 'test-bm', 'bookmark name matches')
call g:AssertTrue(has_key(s:bms[0], 'path'), 'bookmark has path')
call g:AssertTrue(has_key(s:bms[0], 'line'), 'bookmark has line')
call g:AssertTrue(has_key(s:bms[0], 'col'), 'bookmark has col')
call g:AssertTrue(has_key(s:bms[0], 'timestamp'), 'bookmark has timestamp')
unlet s:bms

" ──────────────────────────────
" JumpToBookmark
" ──────────────────────────────

let g:CurrentTest = 'workspace: JumpToBookmark with unknown name returns false'
call vproj#workspace#Setup({})
let s:result = vproj#workspace#JumpToBookmark('nonexistent')
call g:AssertFalse(s:result, 'JumpToBookmark returns false for unknown bookmark')
unlet s:result

" ──────────────────────────────
" RecordSymbol
" ──────────────────────────────

let g:CurrentTest = 'workspace: RecordSymbol adds to recent list'
call vproj#workspace#Setup({})
let s:sym = {'name': 'myFunc', 'path': '/test/file.py', 'line': 42, 'kind': 'function'}
call vproj#workspace#RecordSymbol(s:sym)
let s:recent = vproj#workspace#GetRecentSymbols()
call g:AssertEquals(len(s:recent), 1, 'one recent symbol after RecordSymbol')
call g:AssertEquals(s:recent[0].name, 'myFunc', 'symbol name matches')
call g:AssertEquals(s:recent[0].path, '/test/file.py', 'symbol path matches')
call g:AssertEquals(s:recent[0].kind, 'function', 'symbol kind matches')
call g:AssertTrue(has_key(s:recent[0], 'timestamp'), 'symbol has timestamp')
unlet s:sym s:recent

" ──────────────────────────────
" GetRecentSymbols limit
" ──────────────────────────────

let g:CurrentTest = 'workspace: GetRecentSymbols respects limit'
call vproj#workspace#Setup({})
for s:i in range(25)
  call vproj#workspace#RecordSymbol(
        \ {'name': 'sym' . s:i, 'path': '/test/file.py', 'line': s:i, 'kind': 'function'})
endfor
let s:recent = vproj#workspace#GetRecentSymbols(20)
call g:AssertEquals(len(s:recent), 20, 'returns at most 20 symbols when limit is 20')
call g:AssertEquals(s:recent[0].name, 'sym24', 'most recently recorded symbol is first')
unlet s:i s:recent

" ──────────────────────────────
" SaveWorkspace
" ──────────────────────────────

let g:CurrentTest = 'workspace: SaveWorkspace with empty name returns false'
call vproj#workspace#Setup({})
call g:AssertFalse(vproj#workspace#SaveWorkspace(''), 'empty name returns false')

" ──────────────────────────────
" ListWorkspaces
" ──────────────────────────────

let g:CurrentTest = 'workspace: ListWorkspaces returns a list'
call vproj#workspace#Setup({})
let s:list = vproj#workspace#ListWorkspaces()
call g:AssertEquals(type(s:list), v:t_list, 'ListWorkspaces returns a list (may be empty)')
unlet s:list

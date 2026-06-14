" tests/vim_spec/files_mode_spec.vim — Pure VimScript tests for nam#files_mode#*

let g:CurrentTest = 'files_mode: Create returns mode dict with name/key/icon'
let mode = nam#files_mode#Create({})
call g:AssertEquals(mode.name, 'Files', 'name should be Files')
call g:AssertEquals(mode.key, 'f', 'key should be f')
call g:AssertEquals(mode.icon, 'F', 'icon should be F')

let g:CurrentTest = 'files_mode: mode dict has enabled default true'
call g:AssertTrue(has_key(mode, 'enabled'), 'mode should have enabled key')
call g:AssertEquals(mode.enabled, v:true, 'enabled should default to true')

let g:CurrentTest = 'files_mode: mode dict has PrevPage and NextPage functions'
call g:AssertTrue(has_key(mode, 'PrevPage'), 'mode should have PrevPage')
call g:AssertTrue(has_key(mode, 'NextPage'), 'mode should have NextPage')
call g:AssertTrue(has_key(mode, 'Refresh'), 'mode should have Refresh')
call g:AssertTrue(has_key(mode, 'Render'), 'mode should have Render')
call g:AssertTrue(has_key(mode, 'Select'), 'mode should have Select')

let g:CurrentTest = 'files_mode: PrevPage at page 0 returns false'
call g:AssertFalse(nam#files_mode#PrevPage(), 'PrevPage at page 0 should return false')

let g:CurrentTest = 'files_mode: NextPage with TotalPages=1 returns false'
call g:AssertFalse(nam#files_mode#NextPage(), 'NextPage with TotalPages=1 should return false')

let g:CurrentTest = 'files_mode: SelectFile with unknown label returns v:null'
call g:AssertEquals(nam#files_mode#SelectFile('zz'), v:null, 'SelectFile with unknown label should return v:null')

" tests/vim_spec/cache_spec.vim — Pure VimScript tests for nam#cache#*

let g:CurrentTest = 'cache: create and set/get'
call nam#cache#Create('test', 60)
call nam#cache#Set('test', 'key1', 'value1')
let val = nam#cache#Get('test', 'key1')
call g:AssertEquals(val, 'value1', 'get returns set value')

let g:CurrentTest = 'cache: missing key returns v:null'
let val = nam#cache#Get('test', 'nonexistent')
call g:AssertEquals(val, v:null, 'missing key returns v:null')

let g:CurrentTest = 'cache: invalid clears all entries'
call nam#cache#Set('test', 'key2', 'value2')
call nam#cache#Invalid('test')
let val = nam#cache#Get('test', 'key2')
call g:AssertEquals(val, v:null, 'after invalid, get returns v:null')

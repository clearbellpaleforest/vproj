" tests/vim_spec/cache_spec.vim — Pure VimScript tests for vproj#cache#*

let g:CurrentTest = 'cache: create and set/get'
call vproj#cache#Create('test', 60)
call vproj#cache#Set('test', 'key1', 'value1')
let val = vproj#cache#Get('test', 'key1')
call g:AssertEquals(val, 'value1', 'get returns set value')

let g:CurrentTest = 'cache: missing key returns v:null'
let val = vproj#cache#Get('test', 'nonexistent')
call g:AssertEquals(val, v:null, 'missing key returns v:null')

let g:CurrentTest = 'cache: invalid clears all entries'
call vproj#cache#Set('test', 'key2', 'value2')
call vproj#cache#Invalid('test')
let val = vproj#cache#Get('test', 'key2')
call g:AssertEquals(val, v:null, 'after invalid, get returns v:null')

" tests/vim_spec/labels_spec.vim — Pure VimScript tests for vproj#labels#*

let g:CurrentTest = 'labels: generate 10 single-char labels'
let s:tiers = ['1234567890', 'asdfghjkl', 'qwertyuiop', 'zxcvbnm']
let result = vproj#labels#Generate(10, s:tiers, 'double')
call g:AssertEquals(len(result), 10, 'should generate exactly 10 labels')
call g:AssertEquals(result[0], '1', 'first label should be 1')
call g:AssertEquals(result[9], '0', 'tenth label should be 0')

let g:CurrentTest = 'labels: generate 36 single-char labels'
let result = vproj#labels#Generate(36, s:tiers, 'double')
call g:AssertEquals(len(result), 36, 'should generate 36 labels')
call g:AssertEquals(result[0], '1', 'first should be 1')
call g:AssertEquals(result[35], 'm', 'last single-char should be m')

let g:CurrentTest = 'labels: overflow to double-char at 37'
let result = vproj#labels#Generate(37, s:tiers, 'double')
call g:AssertEquals(len(result), 37, 'should generate 37 labels')
call g:AssertEquals(result[36], '11', '37th label should be 11')

let g:CurrentTest = 'labels: build map for items'
let items = [{'name': 'main.py'}, {'name': 'server.py'}, {'name': 'config.lua'}]
let result = vproj#labels#BuildMap(items)
call g:AssertTrue(has_key(result, 'label_map'), 'result should have label_map')
call g:AssertTrue(has_key(result, 'lines'), 'result should have lines')
call g:AssertEquals(len(result.lines), 3, 'should have 3 lines')
call g:AssertEquals(result.label_map['1'].name, 'main.py', 'label 1 should map to main.py')

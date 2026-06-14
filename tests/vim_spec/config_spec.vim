" tests/vim_spec/config_spec.vim — Pure VimScript tests for nam#config#*

let g:CurrentTest = 'config: defaults'
let cfg = nam#config#Setup({})
call g:AssertEquals(cfg.hotkey, '<F2>', 'default hotkey is F2')
call g:AssertEquals(cfg.width, 45, 'default width is 45')
call g:AssertEquals(cfg.auto_open, v:false, 'default auto_open is false')
call g:AssertEquals(len(cfg.labels.tiers), 4, 'default has 4 label tiers')
call g:AssertEquals(cfg.modes.buffers.enabled, v:true, 'buffers mode enabled by default')

let g:CurrentTest = 'config: user override'
let user = {'width': 40, 'hotkey': '<F3>'}
let cfg = nam#config#Setup(user)
call g:AssertEquals(cfg.width, 40, 'width overridden')
call g:AssertEquals(cfg.hotkey, '<F3>', 'hotkey overridden')

let g:CurrentTest = 'config: nested merge preserves defaults'
let cfg = nam#config#Setup({'modes': {'git': {'enabled': v:false}}})
call g:AssertEquals(cfg.modes.git.enabled, v:false, 'git mode disabled')
call g:AssertEquals(cfg.modes.buffers.enabled, v:true, 'buffers mode still enabled')

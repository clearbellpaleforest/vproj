" install.vim — NAM plugin installer for Vim/Neovim
"
" In-editor installation — no shell needed beyond :source.
"
" Usage:
"   :source install.vim
"
" Or, from the shell:
"   vim -c 'source install.vim'
"   nvim -c 'source install.vim'
"
" After sourcing, the :VprojInstall command is also available.
"
" This script detects whether you are running Vim or Neovim, determines
" the correct pack directory, clones the plugin from GitHub (or copies
" from the local source tree if run from within the repo), and verifies
" that all required files are present.
"
" SECURITY: Like any installer, verify the contents of this file before
" sourcing it. If you obtained it from the official Vproj repository, you
" can trust it — but verify.

if exists('g:vproj_install_loaded')
    finish
endif
let g:vproj_install_loaded = 1

" ── Configuration ──────────────────────────────────────────────────

let s:plugin_name = "vproj"
let s:plugin_repo = 'https://github.com/clearbellpaleforest/vproj'

" Every plugin file that must exist for a valid installation.
let s:required_files = [
    \ 'lua/vproj/init.lua',
    \ 'lua/vproj/config.lua',
    \ 'lua/vproj/core/navigation.lua',
    \ 'lua/vproj/core/project.lua',
    \ 'lua/vproj/core/persistence.lua',
    \ 'lua/vproj/adapters/compat.lua',
    \ 'lua/vproj/adapters/git.lua',
    \ 'lua/vproj/adapters/lsp.lua',
    \ 'lua/vproj/adapters/treesitter.lua',
    \ 'lua/vproj/modes/init.lua',
    \ 'lua/vproj/modes/buffers.lua',
    \ 'lua/vproj/modes/files.lua',
    \ 'lua/vproj/modes/git.lua',
    \ 'lua/vproj/modes/symbols.lua',
    \ 'lua/vproj/modes/outline.lua',
    \ 'lua/vproj/ui/labels.lua',
    \ 'lua/vproj/ui/renderer.lua',
    \ 'lua/vproj/ui/sidebar.lua',
    \ 'lua/vproj/utils/events.lua',
    \ 'lua/vproj/utils/cache.lua',
    \ 'plugin/vproj.lua',
\]

" ── Internal helpers ───────────────────────────────────────────────

" Determine the target pack directory for the current platform.
function! s:detect_pack_dir() abort
    if has('nvim')
        return stdpath('data') . '/site/pack/bundle/start/' . s:plugin_name
    else
        return expand('~/.vim/pack/bundle/start/') . s:plugin_name
    endif
endfunction

" Report the detected platform to the user.
function! s:report_platform() abort
    if has('nvim')
        echom 'Detected: Neovim'
    elseif has('lua')
        echom 'Detected: Vim with Lua support'
    else
        echohl WarningMsg
        echom 'Warning: Vim without Lua support. Install vim-nox or compile'
        echom 'Vim with --enable-luainterp, then re-run this installer.'
        echohl None
    endif
endfunction

" Find the repo source directory if install.vim is being sourced from
" within the vproj repository tree.
function! s:find_source_dir() abort
    " Check the directory containing this script
    let l:script = expand('<sfile>')
    let l:script_dir = fnamemodify(l:script, ':h')
    if filereadable(l:script_dir . '/lua/vproj/init.lua')
        return l:script_dir
    endif
    " Check the current working directory
    if filereadable(getcwd() . '/lua/vproj/init.lua')
        return getcwd()
    endif
    return ''
endfunction

" Verify that every file in s:required_files exists under dir.
function! s:verify_install(dir) abort
    let l:missing = 0
    for l:f in s:required_files
        let l:full = a:dir . '/' . l:f
        if !filereadable(l:full)
            echohl WarningMsg
            echom 'Missing: ' . l:f
            echohl None
            let l:missing = 1
        endif
    endfor
    if l:missing
        echohl ErrorMsg
        echom 'Installation at ' . a:dir . ' is incomplete.'
        echohl None
        return 0
    endif
    echom 'All plugin files verified at ' . a:dir
    return 1
endfunction

" ── Installation methods ───────────────────────────────────────────

" Copy plugin files from a local source directory to the pack directory.
function! s:install_from_local(src, dest) abort
    echom 'Copying from ' . a:src . ' ...'

    " Ensure target directories exist
    call mkdir(a:dest . '/lua', 'p')
    call mkdir(a:dest . '/plugin', 'p')

    " Recursively copy lua/vproj tree
    let l:cp_lua = 'cp -r ' . shellescape(a:src . '/lua/vproj') . ' ' . shellescape(a:dest . '/lua/')
    silent let l:out = system(l:cp_lua)
    if v:shell_error
        echohl ErrorMsg
        echom 'Failed to copy Lua files: ' . l:out
        echohl None
        return 0
    endif

    " Copy plugin file
    let l:cp_plugin = 'cp ' . shellescape(a:src . '/plugin/vproj.lua') . ' ' . shellescape(a:dest . '/plugin/')
    silent let l:out = system(l:cp_plugin)
    if v:shell_error
        echohl ErrorMsg
        echom 'Failed to copy plugin file: ' . l:out
        echohl None
        return 0
    endif

    return 1
endfunction

" Clone the plugin repository from GitHub into the pack directory.
function! s:install_from_git(dest) abort
    echom 'Cloning from ' . s:plugin_repo . ' ...'
    let l:cmd = 'git clone --depth 1 ' . shellescape(s:plugin_repo) . ' ' . shellescape(a:dest)
    let l:out = system(l:cmd)
    if v:shell_error
        echohl ErrorMsg
        echom 'Clone failed: ' . l:out
        echohl None
        return 0
    endif
    echom 'Repository cloned successfully.'
    return 1
endfunction

" Update an existing git-based installation.
function! s:update_git_install(dir) abort
    echom 'Updating existing installation...'
    let l:cmd = 'git -C ' . shellescape(a:dir) . ' pull --ff-only'
    let l:out = system(l:cmd)
    if v:shell_error
        echohl ErrorMsg
        echom 'Update failed: ' . l:out
        echohl None
        echom 'Try :!rm -rf ' . shellescape(a:dir) . ' then re-source this file.'
        return 0
    endif
    echom 'Installation updated.'
    return 1
endfunction

" ── Post-install message ───────────────────────────────────────────

function! s:print_post_install(dir) abort
    echohl MoreMsg
    echo ''
    echo 'NAM plugin installed!'
    echo '  Location: ' . a:dir
    echo ''
    echo 'Add this to your ~/.vimrc or ~/.config/nvim/init.lua:'
    echo ''
    echo '    require("vproj").setup({ hotkey = "<F2>" })'
    echo ''
    echo 'Then press F2 to open the sidebar.'
    echo 'Press b/f/g/s/o for modes, then a label key to jump.'
    echo 'Press q to close.'
    echohl None
endfunction

" ── Main installer ─────────────────────────────────────────────────

function! s:VprojInstall() abort
    let l:pack_dir = s:detect_pack_dir()

    call s:report_platform()

    " Check for git
    if !executable('git')
        echohl ErrorMsg
        echom 'git is required but not found on your system.'
        echohl None
        return
    endif

    " ── Handle existing installation ──
    if isdirectory(l:pack_dir)
        if s:verify_install(l:pack_dir)
            echom 'NAM is already installed at ' . l:pack_dir
            if confirm('Update existing installation?', "&Yes\n&No", 1) == 1
                if !s:update_git_install(l:pack_dir)
                    return
                endif
            else
                return
            endif
        else
            echohl WarningMsg
            echom 'Installation is incomplete or corrupt. Reinstalling...'
            echohl None
            call mkdir(l:pack_dir, 'p')
            silent call system('rm -rf ' . shellescape(l:pack_dir))
        endif
    endif

    " ── Perform installation ──
    let l:src = s:find_source_dir()
    if !empty(l:src)
        echom 'Local source detected: ' . l:src
        if !s:install_from_local(l:src, l:pack_dir)
            return
        endif
    else
        echom 'No local source found. Installing from GitHub...'
        call mkdir(l:pack_dir, 'p')
        silent call system('rm -rf ' . shellescape(l:pack_dir))
        if !s:install_from_git(l:pack_dir)
            return
        endif
    endif

    " ── Verify ──
    if !s:verify_install(l:pack_dir)
        echohl ErrorMsg
        echom 'Installation verification failed. Please try again.'
        echohl None
        return
    endif

    " ── All done ──
    call s:print_post_install(l:pack_dir)
endfunction

" ── Commands ───────────────────────────────────────────────────────

command! VprojInstall call s:VprojInstall()

" ── Auto-run when sourced ──────────────────────────────────────────

call s:VprojInstall()

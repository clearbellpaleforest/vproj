vim9script

# plugin/vproj.vim — VPROJ entry point.
#
# Loads the project pane and registers commands and default key mappings.
# Stage 1: Pane Infrastructure — toggle, open, close via Tab.
#
# Commands:
#   :VprojToggle  — Toggle the project pane open/closed.
#   :VprojOpen    — Open the project pane.
#   :VprojClose   — Close the project pane.
#   :VprojRefresh — Refresh the pane contents.
#   :VprojCopy :VprojDelete :VprojRename :VprojMove — act on the file
#   selected in the pane. :Copy :Delete :Rename :Move are short aliases,
#   defined only when no other plugin (e.g. vim-eunuch) already owns them.

# Load guard
if exists('g:loaded_vproj')
  finish
endif
g:loaded_vproj = 1

# Highlight groups are defined by vproj#PaneOpen() (and re-defined by the
# pane's own ColorScheme autocmd while it is open), so loading this file does
# not source the autoload file. Nothing here calls into autoload at load time.

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
command! -bar -nargs=0 VprojToggle  vproj#PaneToggle()
command! -bar -nargs=0 VprojOpen    vproj#PaneOpen()
command! -bar -nargs=0 VprojClose   vproj#PaneClose()
command! -bar -nargs=0 VprojRefresh vproj#Refresh()
command! -bar -nargs=0 VprojDiag    call vproj#PaneDiagnose()

# File operations on the file selected in the pane (file mode only)
command! -bar -nargs=0 VprojCopy   vproj#CopySelected()
command! -bar -nargs=0 VprojDelete vproj#DeleteSelected()
command! -bar -nargs=0 VprojRename vproj#RenameSelected()
command! -bar -nargs=0 VprojMove   vproj#MoveSelected()
# Short aliases. Never replace another plugin's command of the same name:
# vim-eunuch's :Delete deletes the current buffer's file, not the pane's.
if exists(':Copy') != 2
  command -bar -nargs=0 Copy   vproj#CopySelected()
endif
if exists(':Delete') != 2
  command -bar -nargs=0 Delete vproj#DeleteSelected()
endif
if exists(':Rename') != 2
  command -bar -nargs=0 Rename vproj#RenameSelected()
endif
if exists(':Move') != 2
  command -bar -nargs=0 Move   vproj#MoveSelected()
endif

# ---------------------------------------------------------------------------
# Default key mapping: Tab toggles the project pane (temporary mode).
# Shift-Tab toggles in permanent mode.
# Uses <Plug> indirection so users can remap in their vimrc without
# clobbering the default.
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>VprojToggle :VprojToggle<CR>
nnoremap <silent> <Plug>VprojTogglePermanent :call vproj#PaneTogglePermanent()<CR>

if !hasmapto('<Plug>VprojToggle', 'n')
  nmap <Tab> <Plug>VprojToggle
endif

if !hasmapto('<Plug>VprojTogglePermanent', 'n')
  nmap <S-Tab> <Plug>VprojTogglePermanent
endif

command! -bar -nargs=? VprojAiPrompt call vproj#ai#AiPrompt(<q-args>)
nnoremap <silent> <Plug>VprojAiPrompt :VprojAiPrompt<CR>

# No default key: <S-A> is the same key as A (append at end of line), so a
# global default would replace a core Vim command in every buffer. Map
# <Plug>VprojAgent yourself, e.g. nmap <Leader>a <Plug>VprojAgent
command! -bar -nargs=0 VprojAgent call vproj#agent#AgentOpen()
nnoremap <silent> <Plug>VprojAgent :VprojAgent<CR>

nnoremap <silent> <Plug>VprojF1 :call vproj#HandleF1()<CR>

if !hasmapto('<Plug>VprojF1', 'n')
  nmap <F1> <Plug>VprojF1
  nmap <Help> <Plug>VprojF1
endif

vim9script

# plugin/vproj.vim — VPROJ entry point.
#
# Loads the project pane and registers commands and default key mappings.
# Stage 1 (ADR-012): Pane Infrastructure — toggle, open, close via F4.
#
# Commands:
#   :VprojToggle  — Toggle the project pane open/closed.
#   :VprojOpen    — Open the project pane.
#   :VprojClose   — Close the project pane.
#   :VprojRefresh — Refresh the pane contents.

# Load guard
if exists('g:loaded_vproj')
  finish
endif
g:loaded_vproj = 1

# Define highlight groups (idempotent — uses highlight default)
vproj#DefineHighlights()

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
command! -bar -nargs=0 VprojToggle  vproj#PaneToggle()
command! -bar -nargs=0 VprojOpen    vproj#PaneOpen()
command! -bar -nargs=0 VprojClose   vproj#PaneClose()
command! -bar -nargs=0 VprojRefresh vproj#Refresh()
command! -bar -nargs=0 VprojDiag    call vproj#PaneDiagnose()

# ---------------------------------------------------------------------------
# Default key mapping: F4 toggles the project pane.
# Uses <Plug> indirection so users can remap in their vimrc without
# clobbering the default.
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>VprojToggle :VprojToggle<CR>

if !hasmapto('<Plug>VprojToggle', 'n')
  nmap <F4> <Plug>VprojToggle
endif

nnoremap <silent> <Plug>VprojF1 :call vproj#HandleF1()<CR>

if !hasmapto('<Plug>VprojF1', 'n')
  nmap <F1> <Plug>VprojF1
  nmap <Help> <Plug>VprojF1
endif

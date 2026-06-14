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

# Load guard
if exists('g:loaded_vproj')
  finish
endif
g:loaded_vproj = 1

# Define highlight groups (idempotent — guards with hlexists)
vproj#DefineHighlights()

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
command! -nargs=0 VprojToggle vproj#PaneToggle()
command! -nargs=0 VprojOpen   vproj#PaneOpen()
command! -nargs=0 VprojClose  vproj#PaneClose()

# ---------------------------------------------------------------------------
# Default key mapping: F4 toggles the project pane.
# Uses <Plug> indirection so users can remap in their vimrc without
# clobbering the default.
# ---------------------------------------------------------------------------
nnoremap <silent> <Plug>VprojToggle :VprojToggle<CR>

if !hasmapto('<Plug>VprojToggle', 'n')
  nmap <F4> <Plug>VprojToggle
endif

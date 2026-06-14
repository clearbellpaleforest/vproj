" plugin/vproj.vim — Legacy Vimscript entry point for Vproj.
"
" Load guard: prevents sourcing this file more than once.
" All commands delegate to vim9script autoload functions in autoload/vproj/.
"
" Commands:
"   :Vproj                — Toggle the sidebar open/closed.
"   :VprojOpen            — Open the sidebar.
"   :VprojClose           — Close the sidebar.
"   :VprojWorkspace       — List all saved workspaces.
"   :VprojWorkspaceSave   — Save the current workspace under a name.
"   :VprojWorkspaceLoad   — Load a named workspace.
"   :VprojWorkspaceDelete — Delete a named workspace.
"   :VprojPin             — Pin the current buffer in the workspace.
"   :VprojUnpin           — Unpin the current buffer.
"   :VprojBookmark        — Add a bookmark with a name.
"   :VprojBookmarkJump    — Jump to a named bookmark.

if exists('g:loaded_vproj')
  finish
endif
let g:loaded_vproj = 1

command! -nargs=0 Vproj          call vproj#init#Toggle()
command! -nargs=0 VprojOpen      call vproj#init#Open()
command! -nargs=0 VprojClose     call vproj#init#Close()
command! -nargs=0 VprojWorkspace   call vproj#workspace#ListWorkspaces()
command! -nargs=1 VprojWorkspaceSave  call vproj#workspace#SaveWorkspace(<q-args>)
command! -nargs=1 VprojWorkspaceLoad  call vproj#workspace#LoadWorkspace(<q-args>)
command! -nargs=1 VprojWorkspaceDelete call vproj#workspace#DeleteWorkspace(<q-args>)
command! -nargs=0 VprojPin       call vproj#workspace#PinBuffer()
command! -nargs=0 VprojUnpin     call vproj#workspace#UnpinBuffer()
command! -nargs=1 VprojBookmark      call vproj#workspace#AddBookmark(<q-args>)
command! -nargs=1 VprojBookmarkJump  call vproj#workspace#JumpToBookmark(<q-args>)

" Auto-setup with defaults so <F2> toggle works out of the box.
" Users who want custom config can call vproj#init#Setup({...}) in their vimrc;
" Setup() guards against double-initialization.
call vproj#init#Setup({})

" plugin/nam.vim — Legacy Vimscript entry point for Nam.
"
" Load guard: prevents sourcing this file more than once.
" All commands delegate to vim9script autoload functions in autoload/nam/.
"
" Commands:
"   :Nam                — Toggle the sidebar open/closed.
"   :NamOpen            — Open the sidebar.
"   :NamClose           — Close the sidebar.
"   :NamWorkspace       — List all saved workspaces.
"   :NamWorkspaceSave   — Save the current workspace under a name.
"   :NamWorkspaceLoad   — Load a named workspace.
"   :NamWorkspaceDelete — Delete a named workspace.
"   :NamPin             — Pin the current buffer in the workspace.
"   :NamUnpin           — Unpin the current buffer.
"   :NamBookmark        — Add a bookmark with a name.
"   :NamBookmarkJump    — Jump to a named bookmark.

if exists('g:loaded_nam')
  finish
endif
let g:loaded_nam = 1

command! -nargs=0 Nam          call nam#init#Toggle()
command! -nargs=0 NamOpen      call nam#init#Open()
command! -nargs=0 NamClose     call nam#init#Close()
command! -nargs=0 NamWorkspace   call nam#workspace#ListWorkspaces()
command! -nargs=1 NamWorkspaceSave  call nam#workspace#SaveWorkspace(<q-args>)
command! -nargs=1 NamWorkspaceLoad  call nam#workspace#LoadWorkspace(<q-args>)
command! -nargs=1 NamWorkspaceDelete call nam#workspace#DeleteWorkspace(<q-args>)
command! -nargs=0 NamPin       call nam#workspace#PinBuffer()
command! -nargs=0 NamUnpin     call nam#workspace#UnpinBuffer()
command! -nargs=1 NamBookmark      call nam#workspace#AddBookmark(<q-args>)
command! -nargs=1 NamBookmarkJump  call nam#workspace#JumpToBookmark(<q-args>)

" Auto-setup with defaults so <F2> toggle works out of the box.
" Users who want custom config can call nam#init#Setup({...}) in their vimrc;
" Setup() guards against double-initialization.
call nam#init#Setup({})

# vproj

Vim project manager. A sidebar pane for browsing files and switching buffers.

## Install

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'clearbellpaleforest/vproj'
```

Or any plugin manager that sources `plugin/` and `autoload/`.

## Usage

`F4` toggles the project pane. Inside the pane:

| Key | Action |
|-----|--------|
| j / k | Move selection |
| Enter | Open file or switch buffer |
| Shift-F | File mode — browse directories |
| Shift-D | Doc mode — switch open buffers |
| r | Refresh |
| d | Close selected buffer (doc mode) |
| Left / Right | Shrink / grow pane |
| . | Parent directory |
| q | Close pane |

Or use commands: `:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`.

## Remap

```vim
" Change the toggle key
nmap <F2> <Plug>VprojToggle

" Disable default F4
nunmap <F4>
```

## Requirements

Vim 9.0 or later.

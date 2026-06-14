" autoload/vproj/handler.vim — legacy vimscript bridge for key mappings
" Mappings call these functions, which dispatch into vim9script autoload.
" Vim mappings cannot directly call vim9script :def functions with string
" arguments via <Cmd> or :call, so this bridge translates the calls.

function vproj#handler#Handle(label) abort
  return vproj#navigation#Dispatch(a:label)
endfunction

function vproj#handler#HandleClose() abort
  call vproj#sidebar#Close()
endfunction

function vproj#handler#HandlePagePrev() abort
  call vproj#navigation#PagePrev()
endfunction

function vproj#handler#HandlePageNext() abort
  call vproj#navigation#PageNext()
endfunction

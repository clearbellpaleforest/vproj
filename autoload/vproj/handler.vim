" autoload/nam/handler.vim — legacy vimscript bridge for key mappings
" Mappings call these functions, which dispatch into vim9script autoload.
" Vim mappings cannot directly call vim9script :def functions with string
" arguments via <Cmd> or :call, so this bridge translates the calls.

function nam#handler#Handle(label) abort
  return nam#navigation#Dispatch(a:label)
endfunction

function nam#handler#HandleClose() abort
  call nam#sidebar#Close()
endfunction

function nam#handler#HandlePagePrev() abort
  call nam#navigation#PagePrev()
endfunction

function nam#handler#HandlePageNext() abort
  call nam#navigation#PageNext()
endfunction

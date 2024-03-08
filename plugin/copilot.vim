if exists('g:loaded_copilot')
  finish
endif
let g:loaded_copilot = 1

scriptencoding utf-8

command! -bang -nargs=? -range=-1 -complete=customlist,copilot#CommandComplete Copilot exe copilot#Command(<line1>, <count>, +"<range>", <bang>0, "<mods>", <q-args>)

if v:version < 800 || !exists('##CompleteChanged')
  finish
endif

function! s:ColorScheme() abort
  if &t_Co == 256
    hi def CopilotSuggestion guifg=#808080 ctermfg=244
  else
    hi def CopilotSuggestion guifg=#808080 ctermfg=8
  endif
  hi def link CopilotAnnotation Normal
endfunction

function! s:Event(type) abort
  try
    call call('copilot#On' . a:type, [])
  catch
    call copilot#logger#Exception('autocmd.' . a:type)
  endtry
endfunction

augroup github_copilot
  autocmd!
  autocmd FileType             * call s:Event('FileType')
  autocmd InsertLeave          * call s:Event('InsertLeave')
  autocmd BufLeave             * if mode() =~# '^[iR]'|call s:Event('InsertLeave')|endif
  autocmd InsertEnter          * call s:Event('InsertEnter')
  autocmd BufEnter             * if mode() =~# '^[iR]'|call s:Event('InsertEnter')|endif
  autocmd BufEnter             * call s:Event('BufEnter')
  autocmd CursorMovedI         * call s:Event('CursorMovedI')
  autocmd CompleteChanged      * call s:Event('CompleteChanged')
  autocmd ColorScheme,VimEnter * call s:ColorScheme()
  if !(get(g:, 'copilot_no_key_map') || get(g:, 'copilot_no_maps'))
    autocmd VimEnter             * call copilot#MapAccept('<Tab>')
  endif
  autocmd VimEnter             * call copilot#Init()
  autocmd BufUnload            * call s:Event('BufUnload')
  autocmd VimLeavePre          * call s:Event('VimLeavePre')
  autocmd BufReadCmd copilot://* setlocal buftype=nofile bufhidden=wipe nobuflisted nomodifiable
  autocmd BufReadCmd copilot:///log call copilot#logger#BufReadCmd() | setfiletype copilotlog
augroup END

call s:ColorScheme()
if !(get(g:, 'copilot_no_key_map') || get(g:, 'copilot_no_maps'))
  call copilot#MapAccept('<Tab>')
endif

inoremap <Plug>(copilot-dismiss)     <Cmd>call copilot#Dismiss()<CR>
if empty(mapcheck('<C-]>', 'i'))
  imap <silent><script><nowait><expr> <C-]> copilot#Dismiss() . "\<C-]>"
endif
inoremap <Plug>(copilot-next)     <Cmd>call copilot#Next()<CR>
inoremap <Plug>(copilot-previous) <Cmd>call copilot#Previous()<CR>
inoremap <Plug>(copilot-suggest)  <Cmd>call copilot#Suggest()<CR>
imap <script><silent><nowait><expr> <Plug>(copilot-accept-word) copilot#AcceptWord()
imap <script><silent><nowait><expr> <Plug>(copilot-accept-line) copilot#AcceptLine()

if !get(g:, 'copilot_no_maps')
  try
    if !has('nvim') && &encoding ==# 'utf-8'
      " avoid 8-bit meta collision with UTF-8 characters
      let s:restore_encoding = 1
      silent noautocmd set encoding=cp949
    endif
    if empty(mapcheck('<M-]>', 'i'))
      imap <M-]> <Plug>(copilot-next)
    endif
    if empty(mapcheck('<M-[>', 'i'))
      imap <M-[> <Plug>(copilot-previous)
    endif
    if empty(mapcheck('<M-Bslash>', 'i'))
      imap <M-Bslash> <Plug>(copilot-suggest)
    endif
    if empty(mapcheck('<M-Right>', 'i'))
      imap <M-Right> <Plug>(copilot-accept-word)
    endif
    if empty(mapcheck('<M-C-Right>', 'i'))
      imap <M-C-Right> <Plug>(copilot-accept-line)
    endif
  finally
    if exists('s:restore_encoding')
      silent noautocmd set encoding=utf-8
    endif
  endtry
endif

let s:dir = expand('<sfile>:h:h')
if getftime(s:dir . '/doc/copilot.txt') > getftime(s:dir . '/doc/tags')
  silent! execute 'helptags' fnameescape(s:dir . '/doc')
endif

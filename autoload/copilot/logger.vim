if exists('g:autoloaded_copilot_log')
  finish
endif
let g:autoloaded_copilot_log = 1

if !exists('s:log_file')
  let s:log_file = tempname() . '-copilot.log'
  try
    call writefile([], s:log_file)
  catch
  endtry
endif

function! copilot#logger#File() abort
  return s:log_file
endfunction

function! s:Write(lines) abort
  let lines = copy(a:lines)
  try
    if !filewritable(s:log_file)
      return
    endif
    call map(lines, { k, L -> type(L) == v:t_func ? call(L, []) : L })
    call writefile(lines, s:log_file, 'a')
  catch
  endtry
endfunction

function! copilot#logger#Trace(...) abort
  if $COPILOT_AGENT_VERBOSE =~# '^\%(1\|true\)$'
    call s:Write(a:000)
  endif
endfunction

function! copilot#logger#Debug(...) abort
  call s:Write(a:000)
endfunction

function! copilot#logger#Info(...) abort
  call s:Write(a:000)
endfunction

function! copilot#logger#Warn(...) abort
  call s:Write(a:000)
endfunction

function! copilot#logger#Error(...) abort
  call s:Write(a:000)
endfunction

function! copilot#logger#Exception() abort
  if !empty(v:exception)
    call copilot#logger#Error('Exception: ' . v:exception . ' @ ' . v:throwpoint)
  endif
endfunction

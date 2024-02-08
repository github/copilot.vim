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

let s:level_prefixes = ['', '[ERROR] ', '[WARN] ', '[INFO] ', '[DEBUG] ', '[TRACE] ']

function! copilot#logger#Raw(level, message) abort
  if $COPILOT_AGENT_VERBOSE !~# '^\%(1\|true\)$' && a:level > 3
    return
  endif
  let lines = type(a:message) == v:t_list ? copy(a:message) : split(a:message, "\n", 1)
  let lines[0] = strftime('[%Y-%m-%dT%H:%M:%S] ') . get(s:level_prefixes, a:level, '[UNKNOWN] ') . get(lines, 0, '')
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
  call copilot#logger#Raw(5, a:000)
endfunction

function! copilot#logger#Debug(...) abort
  call copilot#logger#Raw(4, a:000)
endfunction

function! copilot#logger#Info(...) abort
  call copilot#logger#Raw(3, a:000)
endfunction

function! copilot#logger#Warn(...) abort
  call copilot#logger#Raw(2, a:000)
endfunction

function! copilot#logger#Error(...) abort
  call copilot#logger#Raw(1, a:000)
endfunction

function! copilot#logger#Bare(...) abort
  call copilot#logger#Raw(0, a:000)
endfunction

function! copilot#logger#Exception(...) abort
  if !empty(v:exception) && v:exception !=# 'Vim:Interrupt'
    call copilot#logger#Error('Exception: ' . v:exception . ' @ ' . v:throwpoint)
    let agent = copilot#RunningAgent()
    if !empty(agent)
      let [_, type, code, message; __] = matchlist(v:exception, '^\%(\(^[[:alnum:]_#]\+\)\%((\a\+)\)\=\%(\(:E-\=\d\+\)\)\=:\s*\)\=\(.*\)$')
      let stacklines = []
      for frame in split(substitute(v:throwpoint, ', \S\+ \(\d\+\)$', '[\1]', ''), '\.\@<!\.\.\.\@!')
        let fn_line = matchlist(frame, '^\%(function \)\=\(\S\+\)\[\(\d\+\)\]$')
        if !empty(fn_line)
          call add(stacklines, {'function': substitute(fn_line[1], '^<SNR>\d\+_', '<SID>', ''), 'lineno': +fn_line[2]})
        elseif frame =~# ' Autocmds for "\*"$'
          call add(stacklines, {'function': frame})
        elseif frame =~# ' Autocmds for ".*"$'
          call add(stacklines, {'function': substitute(frame, ' for ".*"$', ' for "[redacted]"', '')})
        else
          call add(stacklines, {'function': '[redacted]'})
        endif
      endfor
      return agent.Request('telemetry/exception', {
            \ 'transaction': a:0 ? a:1 : '',
            \ 'platform': 'other',
            \ 'exception_detail': [{
            \ 'type': type . code,
            \ 'value': message,
            \ 'stacktrace': stacklines}]
            \ })
    endif
  endif
endfunction

let s:deferred = []

function! copilot#util#Defer(fn, ...) abort
  call add(s:deferred, function(a:fn, a:000))
  return timer_start(0, function('s:RunDeferred'))
endfunction

function! s:RunDeferred(...) abort
  if empty(s:deferred)
    return
  endif
  let Fn = remove(s:deferred, 0)
  call timer_start(0, function('s:RunDeferred'))
  call call(Fn, [])
endfunction

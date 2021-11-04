if exists('g:autoloaded_copilot_agent')
  finish
endif
let g:autoloaded_copilot_agent = 1

scriptencoding utf-8

let s:error_exit = -1

let s:root = expand('<sfile>:h:h:h')

let s:jobstop = function(exists('*jobstop') ? 'jobstop' : 'job_stop')
function! s:Kill(agent, ...) abort
  if has_key(a:agent, 'job')
    call s:jobstop(a:agent.job)
  endif
endfunction

function! s:AgentClose() dict abort
  if !has_key(self, 'job')
    return
  endif
  if exists('*chanclose')
    call chanclose(self.job, 'stdin')
  else
    call ch_close_in(self.job)
  endif
  call copilot#logger#Info('agent stopped')
  call timer_start(2000, function('s:Kill', [self]))
endfunction

function! s:LogSend(request, line) abort
  if type(get(a:request, 'params')) == v:t_dict && has_key(a:request.params, 'token')
    let request = deepcopy(a:request)
    let request.params.token = 'REDACTED'
    let line = json_encode(request)
  else
    let line = a:line
  endif
  return '--> ' . line
endfunction

let s:chansend = function(exists('*chansend') ? 'chansend' : 'ch_sendraw')
function! s:Transmit(agent, request) abort
  let request = extend({'jsonrpc': '2.0'}, a:request, 'keep')
  let line = json_encode(request)
  call s:chansend(a:agent.job, line . "\n")
  call copilot#logger#Trace(function('s:LogSend', [request, line]))
  return request
endfunction

function! s:AgentNotify(method, params) dict abort
  return s:Transmit(self, {'method': a:method, 'params': a:params})
endfunction

if !exists('s:id')
  let s:id = 0
endif
function! s:AgentSend(method, params, ...) dict abort
  let s:id += 1
  let request = {'method': a:method, 'params': a:params, 'id': s:id}
  call s:Transmit(self, request)
  call extend(request, {'resolve': [], 'reject': [], 'status': 'running'})
  let self.requests[s:id] = request
  let args = a:000[2:-1]
  if len(args)
    if !empty(a:1)
      call add(request.resolve, { v -> call(a:1, [v] + args)})
    endif
    if !empty(a:2)
      call add(request.reject, { v -> call(a:2, [v] + args)})
    endif
    return request
  endif
  if a:0 && !empty(a:1)
    call add(request.resolve, a:1)
  endif
  if a:0 > 1 && !empty(a:2)
    call add(request.reject, a:2)
  endif
  return request
endfunction

function! s:AgentCall(method, params, ...) dict abort
  let request = call(self.Send, [a:method, a:params] + a:000)
  if a:0
    return request
  endif
  return copilot#agent#Await(request)
endfunction

function! s:AgentCancel(request) dict abort
  if has_key(self.requests, get(a:request, 'id', ''))
    call remove(self.requests, a:request.id)
  endif
  if a:request.status ==# 'running'
    let a:request.status = 'canceled'
  endif
endfunction

function! s:OnOut(agent, line) abort
  call copilot#logger#Trace({ -> '<-- ' . a:line})
  try
    let response = json_decode(a:line)
  catch
    return copilot#logger#Exception()
  endtry
  if type(response) != v:t_dict
    return
  endif

  let id = get(response, 'id', v:null)
  if has_key(response, 'method') && len(id)
    return s:Transmit(a:agent, {"id": id, "code": -32700, "message": "Method not found: " . method})
  endif
  if !has_key(a:agent.requests, id)
    return
  endif
  let request = remove(a:agent.requests, id)
  if request.status ==# 'canceled'
    return
  endif
  let request.waiting = {}
  let resolve = remove(request, 'resolve')
  let reject = remove(request, 'reject')
  if has_key(response, 'result')
    let request.status = 'success'
    let request.result = response.result
    for Cb in resolve
      let request.waiting[timer_start(0, function('s:Callback', [request, 'result', Cb]))] = 1
    endfor
  else
    let request.status = 'error'
    let request.error = response.error
    for Cb in reject
      let request.waiting[timer_start(0, function('s:Callback', [request, 'error', Cb]))] = 1
    endfor
  endif
endfunction

function! s:OnErr(agent, line) abort
  call copilot#logger#Debug('<-! ' . a:line)
endfunction

function! s:OnExit(agent, code) abort
  let a:agent.exit_status = a:code
  call remove(a:agent, 'job')
  for id in sort(keys(a:agent.requests), { a, b -> a > b })
    let request = remove(a:agent.requests, id)
    let request.status = 'error'
    let request.error = {'code': s:error_exit, 'message': 'Agent exited', 'data': {'status': a:code}}
    if !empty(request.reject) && !has_key(request, 'waiting')
      let request.waiting = {}
    endif
    for Cb in request.reject
      let request.waiting[timer_start(0, function('s:Callback', [request, 'error', Cb]))] = 1
    endfor
  endfor
  call copilot#logger#Info('agent exited with status ' . a:code)
endfunction

function! copilot#agent#Close() abort
  if exists('s:instance')
    let instance = remove(s:, 'instance')
    call instance.Close()
  endif
endfunction

function! s:Command() abort
  if !has('nvim-0.5') && v:version < 802
    return [v:null, 'Vim version too old']
  endif
  let node = get(g:, 'copilot_node_command', 'node')
  if type(node) == type('')
    let node = [node]
  endif
  if !executable(get(node, 0, ''))
    if get(node, 0, '') ==# 'node'
      return [v:null, 'Node not found in PATH']
    else
      return [v:null, 'Node executable `' . get(node, 0, '') . "' not found"]
    endif
  endif
  let out = []
  let err = []
  let status = copilot#job#Stream(node + ['--version'], function('add', [out]), function('add', [err]))
  if status != 0
    return [v:null, 'Node exited with status ' . status]
  endif
  let major = +matchstr(get(out, 0, ''), '^v\zs\d\+\ze\.')
  if major < 12
    return [v:null, 'Node v12+ required but found ' . get(out, 0, 'nothing')]
  endif
  let agent = s:root . '/copilot/dist/agent.js'
  if !filereadable(agent)
    let agent = get(g:, 'copilot_agent_command', '')
    if !filereadable(agent)
      return [v:null, 'Could not find agent.js (bad install?)']
    endif
  endif
  return [node + [agent], '']
endfunction

function! s:GetVersionResult(result, agent) abort
  let a:agent.version = get(a:result, 'version', '')
endfunction

function! s:GetVersionError(error, agent) abort
  if a:error.code == s:error_exit
    let a:agent.startup_error = 'Agent exited with status ' . a:error.data.status
  else
    let a:agent.startup_error = 'Unexpected error ' . a:error.code . ' calling agent: ' . a:error.message
    call a:agent.Close()
  endif
endfunction

function! s:New() abort
  let [command, command_error] = s:Command()
  if len(command_error)
    return [v:null, command_error]
  endif
  let instance = {'requests': {},
        \ 'Close': function('s:AgentClose'),
        \ 'Notify': function('s:AgentNotify'),
        \ 'Send': function('s:AgentSend'),
        \ 'Call': function('s:AgentCall'),
        \ 'Cancel': function('s:AgentCancel'),
        \ }
  let instance.job = copilot#job#Stream(command,
        \ function('s:OnOut', [instance]),
        \ function('s:OnErr', [instance]),
        \ function('s:OnExit', [instance]))
  let instance.pid = exists('*jobpid') ? jobpid(instance.job) : job_info(instance.job).process
  let request = instance.Send('getVersion', {}, function('s:GetVersionResult'), function('s:GetVersionError'), instance)
  return [instance, '']
endfunction

function! copilot#agent#Start() abort
  if exists('s:instance.job')
    return
  endif
  let [instance, error] = s:New()
  if len(error)
    let s:startup_error = error
    unlet! s:instance
  else
    let s:instance = instance
    unlet! s:startup_error
  endif
endfunction

function! copilot#agent#New() abort
  let [agent, error] = s:New()
  if empty(error)
    return agent
  endif
  throw 'Copilot: ' . error
endfunction

function! copilot#agent#StartupError() abort
  if !exists('s:instance.job') && !exists('s:startup_error')
    call copilot#agent#Start()
  endif
  if !exists('s:instance.job')
    return get(s:, 'startup_error', 'Something unexpected went wrong spawning the agent')
  endif
  let instance = s:instance
  while has_key(instance, 'job') && !has_key(instance, 'startup_error') && !has_key(instance, 'version')
    sleep 10m
  endwhile
  if has_key(instance, 'version')
    return ''
  else
    return get(instance, 'startup_error', 'Something unexpected went wrong running the agent')
  endif
endfunction

function! copilot#agent#Instance() abort
  let err = copilot#agent#StartupError()
  if empty(err)
    return s:instance
  endif
  throw 'Copilot: ' . err
endfunction

function! copilot#agent#Restart() abort
  call copilot#agent#Close()
  return copilot#agent#Start()
endfunction

function! copilot#agent#Version()
  let instance = copilot#agent#Instance()
  return instance.version
endfunction

function! copilot#agent#Notify(method, params) abort
  let instance = copilot#agent#Instance()
  return instance.Notify(a:method, a:params)
endfunction

function! copilot#agent#Send(method, params, ...) abort
  let instance = copilot#agent#Instance()
  return call(instance.Send, [a:method, a:params] + a:000)
endfunction

function! copilot#agent#Cancel(request) abort
  if exists('s:instance')
    call s:instance.Cancel(a:request)
  endif
  if a:request.status ==# 'running'
    let a:request.status = 'canceled'
  endif
endfunction

function! s:Callback(request, type, callback, timer) abort
  call remove(a:request.waiting, a:timer)
  if has_key(a:request, a:type)
    call a:callback(a:request[a:type])
  endif
endfunction

function! copilot#agent#Result(request, callback) abort
  if has_key(a:request, 'resolve')
    call add(a:request.resolve, a:callback)
  elseif has_key(a:request, 'result')
    let a:request.waiting[timer_start(0, function('s:Callback', [a:request, 'result', a:callback]))] = 1
  endif
endfunction

function! copilot#agent#Error(request, callback) abort
  if has_key(a:request, 'reject')
    call add(a:request.reject, a:callback)
  elseif has_key(a:request, 'error')
    let a:request.waiting[timer_start(0, function('s:Callback', [a:request, 'error', a:callback]))] = 1
  endif
endfunction

function! copilot#agent#Wait(request) abort
  if type(a:request) !=# type({}) || !has_key(a:request, 'status')
    throw string(a:request)
  endif
  while a:request.status ==# 'running'
    sleep 1m
  endwhile
  while !empty(get(a:request, 'waiting', {}))
    sleep 1m
  endwhile
  return a:request
endfunction

function! copilot#agent#Await(request) abort
  call copilot#agent#Wait(a:request)
  if has_key(a:request, 'result')
    return a:request.result
  endif
  throw 'copilot#agent(' . a:request.error.code . '): ' . a:request.error.message
endfunction

function! copilot#agent#Call(method, params, ...) abort
  let instance = copilot#agent#Instance()
  return call(instance.Call, [a:method, a:params] + a:000)
endfunction

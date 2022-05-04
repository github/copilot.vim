if exists('g:autoloaded_copilot_agent')
  finish
endif
let g:autoloaded_copilot_agent = 1

scriptencoding utf-8

let s:plugin_version = '1.2.3'

function! copilot#agent#Version() abort
  return s:plugin_version
endfunction

let s:error_exit = -1

let s:root = expand('<sfile>:h:h:h')

let s:instances = {}

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
  return '--> ' . a:line
endfunction

let s:chansend = function(exists('*chansend') ? 'chansend' : 'ch_sendraw')
function! s:Send(agent, request) abort
  let request = extend({'jsonrpc': '2.0'}, a:request, 'keep')
  let body = json_encode(request)
  call s:chansend(a:agent.job, "Content-Length: " . len(body) . "\r\n\r\n" . body)
  call copilot#logger#Trace(function('s:LogSend', [request, body]))
  return request
endfunction

function! s:AgentNotify(method, params) dict abort
  return s:Send(self, {'method': a:method, 'params': a:params})
endfunction

function! s:RequestWait() dict abort
  while self.status ==# 'running'
    sleep 1m
  endwhile
  while !empty(get(self, 'waiting', {}))
    sleep 1m
  endwhile
  return self
endfunction

function! s:RequestAwait() dict abort
  call self.Wait()
  if has_key(self, 'result')
    return self.result
  endif
  throw 'copilot#agent(' . self.error.code . '): ' . self.error.message
endfunction

function s:RequestAgent() dict abort
  return get(s:instances, self.agent_pid, v:null)
endfunction

if !exists('s:id')
  let s:id = 0
endif
function! s:AgentRequest(method, params, ...) dict abort
  let s:id += 1
  let request = {'method': a:method, 'params': a:params, 'id': s:id}
  call s:Send(self, request)
  call extend(request, {
        \ 'agent_pid': self.pid,
        \ 'Agent': function('s:RequestAgent'),
        \ 'Wait': function('s:RequestWait'),
        \ 'Await': function('s:RequestAwait'),
        \ 'Cancel': function('s:RequestCancel'),
        \ 'resolve': [],
        \ 'reject': [],
        \ 'status': 'running'})
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
  let request = call(self.Request, [a:method, a:params] + a:000)
  if a:0
    return request
  endif
  return request.Await()
endfunction

function! s:AgentCancel(request) dict abort
  if has_key(self.requests, get(a:request, 'id', ''))
    call remove(self.requests, a:request.id)
  endif
  if get(a:request, 'status', '') ==# 'running'
    let a:request.status = 'canceled'
  endif
endfunction

function! s:RequestCancel() dict abort
  let agent = self.Agent()
  if !empty(agent)
    call agent.Cancel(self)
  elseif get(self, 'status', '') ==# 'running'
    let self.status = 'canceled'
  endif
endfunction

function! s:DispatchMessage(agent, handler, id, params, ...) abort
  try
    let response = {'result': call(a:handler, [a:params])}
  catch
    call copilot#logger#Exception()
    let response = {'error': {'code': -32000, 'message': v:exception}}
  endtry
  if !empty(a:id)
    call s:Send(a:agent, extend({'id': a:id}, response))
  endif
endfunction

function! s:OnMessage(agent, body, ...) abort
  call copilot#logger#Trace({ -> '<-- ' . a:body})
  try
    let response = json_decode(a:body)
  catch
    return copilot#logger#Exception()
  endtry
  if type(response) != v:t_dict
    return
  endif

  let id = get(response, 'id', v:null)
  if has_key(response, 'method')
    let params = get(response, 'params', v:null)
    if empty(id)
      if has_key(a:agent.notifications, response.method)
        call timer_start(0, { _ -> a:agent.notifications[response.method](params) })
      elseif response.method ==# 'LogMessage'
        call copilot#logger#Raw(get(params, 'level', 3), get(params, 'message', ''))
        let upgrade_message = matchstr(get(params, 'message', ''), '\<Unhandled status from server:,466,\zs.*')
        if len(upgrade_message)
          let a:agent.upgrade_message = upgrade_message
        endif
      endif
    elseif has_key(a:agent.methods, response.method)
      call timer_start(0, function('s:DispatchMessage', [a:agent, a:agent.methods[response.method], id, params]))
    else
      return s:Send(a:agent, {"id": id, "code": -32700, "message": "Method not found: " . method})
    endif
    return
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

function! s:OnOut(agent, state, data) abort
  let a:state.buffer .= a:data
  while 1
    if a:state.mode ==# 'body'
      let content_length = a:state.headers['content-length']
      if strlen(a:state.buffer) >= content_length
        let headers = remove(a:state, 'headers')
        let a:state.mode = 'headers'
        let a:state.headers = {}
        let body = strpart(a:state.buffer, 0, content_length)
        let a:state.buffer = strpart(a:state.buffer, content_length)
        call timer_start(0, function('s:OnMessage', [a:agent, body]))
      else
        return
      endif
    elseif a:state.mode ==# 'headers' && a:state.buffer =~# "\n"
      let line = matchstr(a:state.buffer, "^.[^\n]*")
      let a:state.buffer = strpart(a:state.buffer, strlen(line) + 1)
      let match = matchlist(line, '^\([^:]\+\): \(.\{-\}\)\r$')
      if len(match)
        let a:state.headers[tolower(match[1])] = match[2]
      elseif line =~# "^\r\\=$"
        let a:state.mode = 'body'
      else
        call copilot#logger#Error("Invalid header: " . line)
        call a:agent.Close()
      endif
    else
      return
    endif
  endwhile
endfunction

function! s:OnErr(agent, line) abort
  call copilot#logger#Debug('<-! ' . a:line)
endfunction

function! s:OnExit(agent, code) abort
  let a:agent.exit_status = a:code
  call remove(a:agent, 'job')
  for id in sort(keys(a:agent.requests), { a, b -> +a > +b })
    let request = remove(a:agent.requests, id)
    if request.status ==# 'canceled'
      return
    endif
    let request.waiting = {}
    call remove(request, 'resolve')
    let reject = remove(request, 'reject')
    let request.status = 'error'
    let code = a:code < 0 || a:code > 255 ? 256 : a:code
    let request.error = {'code': code, 'message': 'Agent exited', 'data': {'status': a:code}}
    for Cb in reject
      let request.waiting[timer_start(0, function('s:Callback', [request, 'error', Cb]))] = 1
    endfor
  endfor
  call timer_start(0, { _ -> get(s:instances, a:agent.pid) is# a:agent ? remove(s:instances, a:agent.pid) : {} })
  call copilot#logger#Info('agent exited with status ' . a:code)
endfunction

unlet! s:is_arm_macos
function! s:IsArmMacOS() abort
  if exists('s:is_arm_macos')
    return s:is_arm_macos
  elseif has('win32') || !isdirectory('/private')
    let s:is_arm_macos = 0
  else
    let out = []
    call copilot#job#Stream(['uname', '-s', '-p'], function('add', [out]), v:null)
    let s:is_arm_macos = join(out, '') =~# '^Darwin arm'
  endif
  return s:is_arm_macos
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
  let major = +matchstr(join(out, ''), '^v\zs\d\+\ze\.')
  if !get(g:, 'copilot_ignore_node_version')
    if major < 16 && s:IsArmMacOS()
      return [v:null, 'Node v16+ required on Apple Silicon but found ' . get(out, 0, 'nothing')]
    elseif major < 12
      return [v:null, 'Node v12+ required but found ' . get(out, 0, 'nothing')]
    endif
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

function! copilot#agent#EditorInfo() abort
  if !exists('s:editor_version')
    if has('nvim')
      let s:editor_version = matchstr(execute('version'), 'NVIM v\zs[^[:space:]]\+')
    else
      let s:editor_version = (v:version / 100) . '.' . (v:version % 100) . (exists('v:versionlong') ? printf('.%04d', v:versionlong % 1000) : '')
    endif
  endif
  return {
        \ 'editorInfo': {'name': has('nvim') ? 'Neovim': 'Vim', 'version': s:editor_version},
        \ 'editorPluginInfo': {'name': 'copilot.vim', 'version': s:plugin_version}}
endfunction

function! s:GetCapabilitiesResult(result, agent) abort
  let a:agent.capabilities = get(a:result, 'capabilities', {})
  call a:agent.Request('setEditorInfo', copilot#agent#EditorInfo())
endfunction

function! s:GetCapabilitiesError(error, agent) abort
  if a:error.code == s:error_exit
    let a:agent.startup_error = 'Agent exited with status ' . a:error.data.status
  else
    let a:agent.startup_error = 'Unexpected error ' . a:error.code . ' calling agent: ' . a:error.message
    call a:agent.Close()
  endif
endfunction

function! s:AgentStartupError() dict abort
  while has_key(self, 'job') && !has_key(self, 'startup_error') && !has_key(self, 'capabilities')
    sleep 10m
  endwhile
  if has_key(self, 'capabilities')
    return ''
  else
    return get(self, 'startup_error', 'Something unexpected went wrong spawning the agent')
  endif
endfunction

function! copilot#agent#New(...) abort
  let opts = a:0 ? a:1 : {}
  let instance = {'requests': {},
        \ 'methods': get(opts, 'methods', {}),
        \ 'notifications': get(opts, 'notifications', {}),
        \ 'Close': function('s:AgentClose'),
        \ 'Notify': function('s:AgentNotify'),
        \ 'Request': function('s:AgentRequest'),
        \ 'Call': function('s:AgentCall'),
        \ 'Cancel': function('s:AgentCancel'),
        \ 'StartupError': function('s:AgentStartupError'),
        \ }
  let [command, command_error] = s:Command()
  if len(command_error)
    let instance.pid = -1
    let instance.startup_error = command_error
    return instance
  endif
  let state = {'headers': {}, 'mode': 'headers', 'buffer': ''}
  let instance.job = copilot#job#Stream(command,
        \ function('s:OnOut', [instance, state]),
        \ function('s:OnErr', [instance]),
        \ function('s:OnExit', [instance]))
  let instance.pid = exists('*jobpid') ? jobpid(instance.job) : job_info(instance.job).process
  let request = instance.Request('initialize', {'capabilities': {}}, function('s:GetCapabilitiesResult'), function('s:GetCapabilitiesError'), instance)
  let s:instances[instance.pid] = instance
  return instance
endfunction

function! copilot#agent#Cancel(request) abort
  if type(a:request) == type({}) && has_key(a:request, 'Cancel')
    call a:request.Cancel()
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

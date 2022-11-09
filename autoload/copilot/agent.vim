if exists('g:autoloaded_copilot_agent')
  finish
endif
let g:autoloaded_copilot_agent = 1

scriptencoding utf-8

let s:plugin_version = '1.6.1'

let s:error_exit = -1

let s:root = expand('<sfile>:h:h:h')

if !exists('s:instances')
  let s:instances = {}
endif

" allow sourcing this file to reload the Lua file too
if has('nvim')
  lua package.loaded._copilot = nil
endif

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
  call s:Send(self, {'method': a:method, 'params': a:params})
  return v:true
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

function! s:RequestAgent() dict abort
  return get(s:instances, self.agent_id, v:null)
endfunction

if !exists('s:id')
  let s:id = 0
endif

function! s:SetUpRequest(agent, id, method, params, ...) abort
  let request = {
        \ 'agent_id': a:agent.id,
        \ 'id': a:id,
        \ 'method': a:method,
        \ 'params': a:params,
        \ 'Agent': function('s:RequestAgent'),
        \ 'Wait': function('s:RequestWait'),
        \ 'Await': function('s:RequestAwait'),
        \ 'Cancel': function('s:RequestCancel'),
        \ 'resolve': [],
        \ 'reject': [],
        \ 'status': 'running'}
  let a:agent.requests[a:id] = request
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

function! s:AgentRequest(method, params, ...) dict abort
  let s:id += 1
  let request = {'method': a:method, 'params': a:params, 'id': s:id}
  call s:Send(self, request)
  return call('s:SetUpRequest', [self, s:id, a:method, a:params] + a:000)
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
    call self.Notify('$/cancelRequest', {'id': a:request.id})
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
  return self
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
  let response = json_decode(a:body)
  if type(response) != v:t_dict
    return
  endif
  return s:OnResponse(a:agent, response)
endfunction

function! s:OnResponse(agent, response, ...) abort
  let response = a:response
  let id = get(response, 'id', v:null)
  if has_key(response, 'method')
    let params = get(response, 'params', v:null)
    if empty(id)
      if has_key(a:agent.notifications, response.method)
        call timer_start(0, { _ -> a:agent.notifications[response.method](params) })
      elseif response.method ==# 'LogMessage'
        call copilot#logger#Raw(get(params, 'level', 3), get(params, 'message', ''))
      endif
    elseif has_key(a:agent.methods, response.method)
      call timer_start(0, function('s:DispatchMessage', [a:agent, a:agent.methods[response.method], id, params]))
    else
      return s:Send(a:agent, {"id": id, "error": {"code": -32700, "message": "Method not found: " . response.method}})
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
  if has_key(a:agent, 'job')
    call remove(a:agent, 'job')
  endif
  if has_key(a:agent, 'client_id')
    call remove(a:agent, 'client_id')
  endif
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
  call timer_start(0, { _ -> get(s:instances, a:agent.id) is# a:agent ? remove(s:instances, a:agent.id) : {} })
  call copilot#logger#Info('agent exited with status ' . a:code)
endfunction

function! copilot#agent#LspInit(agent_id, initialize_result) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  let instance = s:instances[a:agent_id]
  call timer_start(0, { _ -> s:GetCapabilitiesResult(a:initialize_result, instance)})
endfunction

function! copilot#agent#LspExit(agent_id, code, signal) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  let instance = remove(s:instances, a:agent_id)
  call s:OnExit(instance, a:code)
endfunction

function! copilot#agent#LspResponse(agent_id, opts, ...) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  call s:OnResponse(s:instances[a:agent_id], a:opts)
endfunction

function! s:LspRequest(method, params, ...) dict abort
  let id = v:lua.require'_copilot'.lsp_request(self.id, a:method, a:params)
  if id isnot# v:null
    return call('s:SetUpRequest', [self, id, a:method, a:params] + a:000)
  endif
  if has_key(self, 'client_id')
    call copilot#agent#LspExit(self.client_id, -1, -1)
    unlet! self.client_id
  endif
  throw 'copilot#agent: LSP client not available'
endfunction

function! s:LspClose() dict abort
  if !has_key(self, 'client_id')
    return
  endif
  return luaeval('vim.lsp.get_client_by_id(_A).stop()', self.client_id)
endfunction

function! s:LspNotify(method, params) dict abort
  return v:lua.require'_copilot'.rpc_notify(self.id, a:method, a:params)
endfunction

function! copilot#agent#LspHandle(agent_id, response) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  call s:OnResponse(s:instances[a:agent_id], a:response)
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
  if !has('nvim-0.6') && v:version < 802
    return [v:null, '', 'Vim version too old']
  endif
  let node = get(g:, 'copilot_node_command', '')
  if empty(node)
    let node = ['node']
  elseif type(node) == type('')
    let node = [expand(node)]
  endif
  if !executable(get(node, 0, ''))
    if get(node, 0, '') ==# 'node'
      return [v:null, '', 'Node.js not found in PATH']
    else
      return [v:null, '', 'Node.js executable `' . get(node, 0, '') . "' not found"]
    endif
  endif
  let out = []
  let err = []
  let status = copilot#job#Stream(node + ['--version'], function('add', [out]), function('add', [err]))
  if status != 0
    return [v:null, '', 'Node.js exited with status ' . status]
  endif
  let node_version = matchstr(join(out, ''), '^v\zs\d\+\.[^[:space:]]*')
  let major = str2nr(node_version)
  let too_new = major >= 18
  if !get(g:, 'copilot_ignore_node_version')
    if major == 0
      return [v:null, node_version, 'Could not determine Node.js version']
    elseif (major < 16 || too_new) && s:IsArmMacOS()
      return [v:null, node_version, 'Node.js version 16.x or 17.x required on Apple Silicon but found ' . node_version]
    elseif major < 12 || too_new
      return [v:null, node_version, 'Node.js version 12.x–17.x required but found ' . node_version]
    endif
  endif
  let agent = get(g:, 'copilot_agent_command', '')
  if empty(agent) || !filereadable(agent)
    let agent = s:root . '/copilot/dist/agent.js'
    if !filereadable(agent)
      return [v:null, node_version, 'Could not find agent.js (bad install?)']
    endif
  endif
  return [node + [agent], node_version, '']
endfunction

function! s:UrlDecode(str) abort
  return substitute(a:str, '%\(\x\x\)', '\=iconv(nr2char("0x".submatch(1)), "utf-8", "latin1")', 'g')
endfunction

function! copilot#agent#EditorInfo() abort
  if !exists('s:editor_version')
    if has('nvim')
      let s:editor_version = matchstr(execute('version'), 'NVIM v\zs[^[:space:]]\+')
    else
      let s:editor_version = (v:version / 100) . '.' . (v:version % 100) . (exists('v:versionlong') ? printf('.%04d', v:versionlong % 1000) : '')
    endif
  endif
  let info = {
        \ 'editorInfo': {'name': has('nvim') ? 'Neovim': 'Vim', 'version': s:editor_version},
        \ 'editorPluginInfo': {'name': 'copilot.vim', 'version': s:plugin_version}}
  if type(get(g:, 'copilot_proxy')) == v:t_string
    let proxy = g:copilot_proxy
  else
    let proxy = ''
  endif
  let match = matchlist(proxy, '\C^\%([^:]\+://\)\=\%(\([^/:#]\+@\)\)\=\%(\([^/:#]\+\)\|\[\([[:xdigit:]:]\+\)\]\)\%(:\(\d\+\)\)\=\%(/\|$\)')
  if !empty(match)
    let info.networkProxy = {'host': match[2] . match[3], 'port': empty(match[4]) ? 80 : +match[4]}
    if !empty(match[1])
      let info.networkProxy.username = s:UrlDecode(matchstr(match[1], '^[^:]*'))
      let info.networkProxy.password = s:UrlDecode(matchstr(match[1], ':\zs.*'))
    endif
  endif
  return info
endfunction

function! s:GetCapabilitiesResult(result, agent) abort
  let a:agent.capabilities = get(a:result, 'capabilities', {})
  let info = deepcopy(copilot#agent#EditorInfo())
  let info.editorInfo.version .= ' + Node.js ' . a:agent.node_version
  call a:agent.Request('setEditorInfo', extend({'editorConfiguration': a:agent.editorConfiguration}, info))
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
  if has_key(self, 'capabilities') || has_key(self, 'client_id')
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
        \ 'editorConfiguration': get(opts, 'editorConfiguration', {}),
        \ 'Close': function('s:AgentClose'),
        \ 'Notify': function('s:AgentNotify'),
        \ 'Request': function('s:AgentRequest'),
        \ 'Call': function('s:AgentCall'),
        \ 'Cancel': function('s:AgentCancel'),
        \ 'StartupError': function('s:AgentStartupError'),
        \ }
  let [command, node_version, command_error] = s:Command()
  if len(command_error)
    let instance.id = -1
    let instance.startup_error = command_error
    return instance
  endif
  let instance.node_version = node_version
  if has('nvim')
    call extend(instance, {
        \ 'Close': function('s:LspClose'),
        \ 'Notify': function('s:LspNotify'),
        \ 'Request': function('s:LspRequest')})
    let instance.client_id = v:lua.require'_copilot'.lsp_start_client(command, keys(instance.notifications) + keys(instance.methods) + ['LogMessage'])
    let instance.id = instance.client_id
  else
    let state = {'headers': {}, 'mode': 'headers', 'buffer': ''}
    let instance.job = copilot#job#Stream(command,
          \ function('s:OnOut', [instance, state]),
          \ function('s:OnErr', [instance]),
          \ function('s:OnExit', [instance]))
    let instance.id = exists('*jobpid') ? jobpid(instance.job) : job_info(instance.job).process
    let request = instance.Request('initialize', {'capabilities': {'workspace': {'workspaceFolders': v:true}}}, function('s:GetCapabilitiesResult'), function('s:GetCapabilitiesError'), instance)
  endif
  let s:instances[instance.id] = instance
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

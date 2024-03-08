scriptencoding utf-8

let s:plugin_version = copilot#version#String()

let s:error_exit = -1

let s:root = expand('<sfile>:h:h:h')

if !exists('s:instances')
  let s:instances = {}
endif

" allow sourcing this file to reload the Lua file too
if has('nvim')
  lua package.loaded._copilot = nil
endif

function! s:AgentClose() dict abort
  if !has_key(self, 'job')
    return
  endif
  let job = self.job
  if has_key(self, 'kill')
    call job_stop(job, 'kill')
    call copilot#logger#Warn('Agent forcefully terminated')
    return
  endif
  let self.kill = v:true
  let self.shutdown = self.Request('shutdown', {}, function(self.Notify, ['exit']))
  call timer_start(2000, { _ -> job_stop(job, 'kill') })
  call copilot#logger#Debug('Agent shutdown initiated')
endfunction

function! s:LogSend(request, line) abort
  return '--> ' . a:line
endfunction

function! s:RejectRequest(request, error) abort
  if a:request.status ==# 'canceled'
    return
  endif
  let a:request.waiting = {}
  call remove(a:request, 'resolve')
  let reject = remove(a:request, 'reject')
  let a:request.status = 'error'
  let a:request.error = a:error
  for Cb in reject
    let a:request.waiting[timer_start(0, function('s:Callback', [a:request, 'error', Cb]))] = 1
  endfor
  let msg = 'Method ' . a:request.method . ' errored with E' . a:error.code . ': ' . json_encode(a:error.message)
  if empty(reject)
    call copilot#logger#Error(msg)
  else
    call copilot#logger#Warn(msg)
  endif
endfunction

function! s:Send(agent, request) abort
  try
    call ch_sendexpr(a:agent.job, a:request)
    return v:true
  catch /^Vim\%((\a\+)\)\=:E906:/
    let a:agent.kill = v:true
    let job = a:agent.job
    call copilot#logger#Warn('Terminating agent after failed write')
    call job_stop(job)
    call timer_start(2000, { _ -> job_stop(job, 'kill') })
    return v:false
  catch /^Vim\%((\a\+)\)\=:E631:/
    return v:false
  endtry
endfunction

function! s:AgentNotify(method, params) dict abort
  let request = {'method': a:method, 'params': a:params}
  if has_key(self, 'initialization_pending')
    call add(self.initialization_pending, request)
  else
    return s:Send(self, request)
  endif
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
  throw 'Copilot:E' . self.error.code . ': ' . self.error.message
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

function! s:UrlEncode(str) abort
  return substitute(iconv(a:str, 'latin1', 'utf-8'),'[^A-Za-z0-9._~!$&''()*+,;=:@/-]','\="%".printf("%02X",char2nr(submatch(0)))','g')
endfunction

let s:slash = exists('+shellslash') ? '\' : '/'
function! s:UriFromBufnr(bufnr) abort
  let absolute = tr(bufname(a:bufnr), s:slash, '/')
  if absolute !~# '^\a\+:\|^/\|^$' && getbufvar(a:bufnr, 'buftype') =~# '^\%(nowrite\)\=$'
    let absolute = substitute(tr(getcwd(), s:slash, '/'), '/\=$', '/', '') . absolute
  endif
  return s:UriFromPath(absolute)
endfunction

function! s:UriFromPath(absolute) abort
  let absolute = a:absolute
  if has('win32') && absolute =~# '^\a://\@!'
    return 'file:///' . strpart(absolute, 0, 2) . s:UrlEncode(strpart(absolute, 2))
  elseif absolute =~# '^/'
    return 'file://' . s:UrlEncode(absolute)
  elseif absolute =~# '^\a[[:alnum:].+-]*:\|^$'
    return absolute
  else
    return ''
  endif
endfunction

function! s:BufferText(bufnr) abort
  return join(getbufline(a:bufnr, 1, '$'), "\n") . "\n"
endfunction

function! s:SendRequest(agent, request, ...) abort
  if empty(s:Send(a:agent, a:request)) && has_key(a:request, 'id') && has_key(a:agent.requests, a:request.id)
    call s:RejectRequest(remove(a:agent.requests, a:request.id), {'code': 257, 'message': 'Write failed'})
  endif
endfunction

function! s:RegisterWorkspaceFolderForBuffer(agent, buf) abort
  let root = getbufvar(a:buf, 'workspace_folder')
  if type(root) != v:t_string
    return
  endif
  let root = s:UriFromPath(substitute(root, '[\/]$', '', ''))
  if empty(root) || has_key(a:agent.workspaceFolders, root)
    return
  endif
  let a:agent.workspaceFolders[root] = v:true
  call a:agent.Notify('workspace/didChangeWorkspaceFolders', {'event': {'added': [{'uri': root, 'name': fnamemodify(root, ':t')}]}})
endfunction

function! s:PreprocessParams(agent, params) abort
  let bufnr = v:null
  for doc in filter([get(a:params, 'doc', {}), get(a:params, 'textDocument', {})], 'type(get(v:val, "uri", "")) == v:t_number')
    let bufnr = doc.uri
    call s:RegisterWorkspaceFolderForBuffer(a:agent, bufnr)
    let synced = a:agent.Attach(bufnr)
    let doc.uri = synced.uri
    let doc.version = get(synced, 'version', 0)
  endfor
  return bufnr
endfunction

function! s:VimAttach(bufnr) dict abort
  if !bufloaded(a:bufnr)
    return {'uri': '', 'version': 0}
  endif
  let bufnr = a:bufnr
  let doc = {
        \ 'uri': s:UriFromBufnr(bufnr),
        \ 'version': getbufvar(bufnr, 'changedtick', 0),
        \ 'languageId': copilot#doc#LanguageForFileType(getbufvar(bufnr, '&filetype')),
        \ }
  if has_key(self.open_buffers, bufnr) && (
        \ self.open_buffers[bufnr].uri !=# doc.uri ||
        \ self.open_buffers[bufnr].languageId !=# doc.languageId)
    call self.Notify('textDocument/didClose', {'textDocument': {'uri': self.open_buffers[bufnr].uri}})
    call remove(self.open_buffers, bufnr)
  endif
  if !has_key(self.open_buffers, bufnr)
    call self.Notify('textDocument/didOpen', {'textDocument': extend({'text': s:BufferText(bufnr)}, doc)})
    let self.open_buffers[bufnr] = doc
  else
    call self.Notify('textDocument/didChange', {
          \ 'textDocument': {'uri': doc.uri, 'version': doc.version},
          \ 'contentChanges': [{'text': s:BufferText(bufnr)}]})
    let self.open_buffers[bufnr].version = doc.version
  endif
  return doc
endfunction

function! s:VimIsAttached(bufnr) dict abort
  return bufloaded(a:bufnr) && has_key(self.open_buffers, a:bufnr) ? v:true : v:false
endfunction

function! s:AgentRequest(method, params, ...) dict abort
  let s:id += 1
  let params = deepcopy(a:params)
  call s:PreprocessParams(self, params)
  let request = {'method': a:method, 'params': params, 'id': s:id}
  if has_key(self, 'initialization_pending')
    call add(self.initialization_pending, request)
  else
    call copilot#util#Defer(function('s:SendRequest'), self, request)
  endif
  return call('s:SetUpRequest', [self, s:id, a:method, params] + a:000)
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

function! s:DispatchMessage(agent, method, handler, id, params, ...) abort
  try
    let response = {'result': call(a:handler, [a:params])}
    if response.result is# 0
      let response.result = v:null
    endif
  catch
    call copilot#logger#Exception('lsp.request.' . a:method)
    let response = {'error': {'code': -32000, 'message': v:exception}}
  endtry
  if !empty(a:id)
    call s:Send(a:agent, extend({'id': a:id}, response))
  endif
  return response
endfunction

function! s:OnMessage(agent, body, ...) abort
  if !has_key(a:body, 'method')
    return s:OnResponse(a:agent, a:body)
  endif
  let request = a:body
  let id = get(request, 'id', v:null)
  let params = get(request, 'params', v:null)
  if has_key(a:agent.methods, request.method)
    return s:DispatchMessage(a:agent, request.method, a:agent.methods[request.method], id, params)
  elseif id isnot# v:null
    call s:Send(a:agent, {"id": id, "error": {"code": -32700, "message": "Method not found: " . request.method}})
    call copilot#logger#Debug('Unexpected request ' . request.method . ' called with ' . json_encode(params))
  elseif request.method !~# '^\$/'
    call copilot#logger#Debug('Unexpected notification ' . request.method . ' called with ' . json_encode(params))
  endif
endfunction

function! s:OnResponse(agent, response, ...) abort
  let response = a:response
  let id = get(a:response, 'id', v:null)
  if !has_key(a:agent.requests, id)
    return
  endif
  let request = remove(a:agent.requests, id)
  if request.status ==# 'canceled'
    return
  endif
  if has_key(response, 'result')
    let request.waiting = {}
    let resolve = remove(request, 'resolve')
    call remove(request, 'reject')
    let request.status = 'success'
    let request.result = response.result
    for Cb in resolve
      let request.waiting[timer_start(0, function('s:Callback', [request, 'result', Cb]))] = 1
    endfor
  else
    call s:RejectRequest(request, response.error)
  endif
endfunction

function! s:OnErr(agent, ch, line, ...) abort
  if !has_key(a:agent, 'serverInfo')
    call copilot#logger#Bare('<-! ' . a:line)
  endif
endfunction

function! s:OnExit(agent, code, ...) abort
  let a:agent.exit_status = a:code
  if has_key(a:agent, 'job')
    call remove(a:agent, 'job')
  endif
  if has_key(a:agent, 'client_id')
    call remove(a:agent, 'client_id')
  endif
  let code = a:code < 0 || a:code > 255 ? 256 : a:code
  for id in sort(keys(a:agent.requests), { a, b -> +a > +b })
    call s:RejectRequest(remove(a:agent.requests, id), {'code': code, 'message': 'Agent exited', 'data': {'status': a:code}})
  endfor
  call copilot#util#Defer({ -> get(s:instances, a:agent.id) is# a:agent ? remove(s:instances, a:agent.id) : {} })
  call copilot#logger#Info('Agent exited with status ' . a:code)
endfunction

function! copilot#agent#LspInit(agent_id, initialize_result) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  call s:AfterInitialize(a:initialize_result, s:instances[a:agent_id])
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

function! s:NvimAttach(bufnr) dict abort
  if !bufloaded(a:bufnr)
    return {'uri': '', 'version': 0}
  endif
  call luaeval('pcall(vim.lsp.buf_attach_client, _A[1], _A[2])', [a:bufnr, self.id])
  return luaeval('{uri = vim.uri_from_bufnr(_A), version = vim.lsp.util.buf_versions[_A]}', a:bufnr)
endfunction

function! s:NvimIsAttached(bufnr) dict abort
  return bufloaded(a:bufnr) ? luaeval('vim.lsp.buf_is_attached(_A[1], _A[2])', [a:bufnr, self.id]) : v:false
endfunction

function! s:LspRequest(method, params, ...) dict abort
  let params = deepcopy(a:params)
  let bufnr = s:PreprocessParams(self, params)
  let id = eval("v:lua.require'_copilot'.lsp_request(self.id, a:method, params, bufnr)")
  if id isnot# v:null
    return call('s:SetUpRequest', [self, id, a:method, params] + a:000)
  endif
  if has_key(self, 'client_id')
    call copilot#agent#LspExit(self.client_id, -1, -1)
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
  return eval("v:lua.require'_copilot'.rpc_notify(self.id, a:method, a:params)")
endfunction

function! copilot#agent#LspHandle(agent_id, request) abort
  if !has_key(s:instances, a:agent_id)
    return
  endif
  return s:OnMessage(s:instances[a:agent_id], a:request)
endfunction

function! s:GetNodeVersion(command) abort
  let out = []
  let err = []
  let status = copilot#job#Stream(a:command + ['--version'], function('add', [out]), function('add', [err]))
  let string = matchstr(join(out, ''), '^v\zs\d\+\.[^[:space:]]*')
  if status != 0
    let string = ''
  endif
  let major = str2nr(string)
  let minor = str2nr(matchstr(string, '\.\zs\d\+'))
  return {'status': status, 'string': string, 'major': major, 'minor': minor}
endfunction

function! s:Command() abort
  if !has('nvim-0.6') && v:version < 900
    return [v:null, '', 'Vim version too old']
  endif
  let agent = get(g:, 'copilot_agent_command', '')
  if type(agent) == type('')
    let agent = [expand(agent)]
  endif
  if empty(agent) || !filereadable(agent[0])
    let agent = [s:root . '/dist/agent.js']
    if !filereadable(agent[0])
      return [v:null, '', 'Could not find dist/agent.js (bad install?)']
    endif
  elseif agent[0] !~# '\.js$'
    return [agent + ['--stdio'], '', '']
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
  if get(g:, 'copilot_ignore_node_version')
    return [node + agent + ['--stdio'], '', '']
  endif
  let node_version = s:GetNodeVersion(node)
  let warning = ''
  if node_version.major < 18 && get(node, 0, '') !=# 'node' && executable('node')
    let node_version_from_path = s:GetNodeVersion(['node'])
    if node_version_from_path.major >= 18
      let warning = 'Ignoring g:copilot_node_command: Node.js ' . node_version.string . ' is end-of-life'
      let node = ['node']
      let node_version = node_version_from_path
    endif
  endif
  if node_version.status != 0
    return [v:null, '', 'Node.js exited with status ' . node_version.status]
  endif
  if !get(g:, 'copilot_ignore_node_version')
    if node_version.major == 0
      return [v:null, node_version.string, 'Could not determine Node.js version']
    elseif node_version.major < 16 || node_version.major == 16 && node_version.minor < 14 || node_version.major == 17 && node_version.minor < 3
      " 16.14+ and 17.3+ still work for now, but are end-of-life
      return [v:null, node_version.string, 'Node.js version 18.x or newer required but found ' . node_version.string]
    endif
  endif
  return [node + agent + ['--stdio'], node_version.string, warning]
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
  return {'name': has('nvim') ? 'Neovim': 'Vim', 'version': s:editor_version}
endfunction

function! copilot#agent#EditorPluginInfo() abort
  return {'name': 'copilot.vim', 'version': s:plugin_version}
endfunction

function! copilot#agent#Settings() abort
  let settings = {
        \ 'http': {
        \   'proxy': get(g:, 'copilot_proxy', v:null),
        \   'proxyStrictSSL': get(g:, 'copilot_proxy_strict_ssl', v:null)},
        \ 'github-enterprise': {'uri': get(g:, 'copilot_auth_provider_url', v:null)},
        \ }
  if type(settings.http.proxy) ==# v:t_string && settings.http.proxy =~# '^[^/]\+$'
    let settings.http.proxy = 'http://' . settings.http.proxy
  endif
  if type(get(g:, 'copilot_settings')) == v:t_dict
    call extend(settings, g:copilot_settings)
  endif
  return settings
endfunction

function! s:AfterInitialize(result, agent) abort
  let a:agent.serverInfo = get(a:result, 'serverInfo', {})
  if !has_key(a:agent, 'node_version') && has_key(a:result.serverInfo, 'nodeVersion')
    let a:agent.node_version = a:result.serverInfo.nodeVersion
  endif
endfunction

function! s:InitializeResult(result, agent) abort
  call s:AfterInitialize(a:result, a:agent)
  call s:Send(a:agent, {'method': 'initialized', 'params': {}})
  for request in remove(a:agent, 'initialization_pending')
    call copilot#util#Defer(function('s:SendRequest'), a:agent, request)
  endfor
endfunction

function! s:InitializeError(error, agent) abort
  if a:error.code == s:error_exit
    let a:agent.startup_error = 'Agent exited with status ' . a:error.data.status
  else
    let a:agent.startup_error = 'Unexpected error ' . a:error.code . ' calling agent: ' . a:error.message
    call a:agent.Close()
  endif
endfunction

function! s:AgentStartupError() dict abort
  while (has_key(self, 'job') || has_key(self, 'client_id')) && !has_key(self, 'startup_error') && !has_key(self, 'serverInfo')
    sleep 10m
  endwhile
  if has_key(self, 'serverInfo')
    return ''
  else
    return get(self, 'startup_error', 'Something unexpected went wrong spawning the agent')
  endif
endfunction

function! s:Nop(...) abort
  return v:null
endfunction

let s:common_handlers = {
      \ 'featureFlagsNotification': function('s:Nop'),
      \ 'window/logMessage': function('copilot#handlers#window_logMessage'),
      \ }

let s:vim_handlers = {
      \ 'window/showMessageRequest': function('copilot#handlers#window_showMessageRequest'),
      \ 'window/showDocument': function('copilot#handlers#window_showDocument'),
      \ }

let s:vim_capabilities = {
      \ 'workspace': {'workspaceFolders': v:true},
      \ 'window': {'showDocument': {'support': v:true}},
      \ }

function! copilot#agent#New(...) abort
  let opts = a:0 ? a:1 : {}
  let instance = {'requests': {},
        \ 'workspaceFolders': {},
        \ 'Close': function('s:AgentClose'),
        \ 'Notify': function('s:AgentNotify'),
        \ 'Request': function('s:AgentRequest'),
        \ 'Attach': function('s:VimAttach'),
        \ 'IsAttached': function('s:VimIsAttached'),
        \ 'Call': function('s:AgentCall'),
        \ 'Cancel': function('s:AgentCancel'),
        \ 'StartupError': function('s:AgentStartupError'),
        \ }
  let instance.methods = extend(copy(s:common_handlers), get(opts, 'methods', {}))
  let [command, node_version, command_error] = s:Command()
  if len(command_error)
    if empty(command)
      let instance.id = -1
      let instance.startup_error = command_error
      call copilot#logger#Error(command_error)
      return instance
    else
      let instance.node_version_warning = command_error
      call copilot#logger#Warn(command_error)
    endif
  endif
  if !empty(node_version)
    let instance.node_version = node_version
  endif
  let opts = {}
  let opts.initializationOptions = {
        \ 'editorInfo': copilot#agent#EditorInfo(),
        \ 'editorPluginInfo': copilot#agent#EditorPluginInfo(),
        \ }
  let opts.workspaceFolders = []
  let settings = extend(copilot#agent#Settings(), get(opts, 'editorConfiguration', {}))
  if type(get(g:, 'copilot_workspace_folders')) == v:t_list
    for folder in g:copilot_workspace_folders
      if type(folder) == v:t_string && !empty(folder) && folder !~# '\*\*\|^/$'
        for path in glob(folder . '/', 0, 1)
          let uri = s:UriFromPath(substitute(path, '[\/]*$', '', ''))
          call add(opts.workspaceFolders, {'uri': uri, 'name': fnamemodify(uri, ':t')})
        endfor
      elseif type(folder) == v:t_dict && has_key(v:t_dict, 'uri') && !empty(folder.uri) && has_key(folder, 'name')
        call add(opts.workspaceFolders, folder)
      endif
    endfor
  endif
  for folder in opts.workspaceFolders
    let instance.workspaceFolders[folder.uri] = v:true
  endfor
  if has('nvim')
    call extend(instance, {
        \ 'Close': function('s:LspClose'),
        \ 'Notify': function('s:LspNotify'),
        \ 'Request': function('s:LspRequest'),
        \ 'Attach': function('s:NvimAttach'),
        \ 'IsAttached': function('s:NvimIsAttached'),
        \ })
    let instance.client_id = eval("v:lua.require'_copilot'.lsp_start_client(command, keys(instance.methods), opts, settings)")
    let instance.id = instance.client_id
  else
    let state = {'headers': {}, 'mode': 'headers', 'buffer': ''}
    let instance.open_buffers = {}
    let instance.methods = extend(s:vim_handlers, instance.methods)
    let instance.job = job_start(command, {
          \ 'cwd': copilot#job#Cwd(),
          \ 'noblock': 1,
          \ 'stoponexit': '',
          \ 'in_mode': 'lsp',
          \ 'out_mode': 'lsp',
          \ 'out_cb': { j, d -> copilot#util#Defer(function('s:OnMessage'), instance, d) },
          \ 'err_cb': function('s:OnErr', [instance]),
          \ 'exit_cb': { j, d -> copilot#util#Defer(function('s:OnExit'), instance, d) },
          \ })
    let instance.id = job_info(instance.job).process
    let opts.capabilities = s:vim_capabilities
    let opts.processId = getpid()
    let request = instance.Request('initialize', opts, function('s:InitializeResult'), function('s:InitializeError'), instance)
    let instance.initialization_pending = []
    call instance.Notify('workspace/didChangeConfiguration', {'settings': settings})
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

function! s:CloseBuffer(bufnr) abort
  for instance in values(s:instances)
    try
      if has_key(instance, 'job') && has_key(instance.open_buffers, a:bufnr)
        let buffer = remove(instance.open_buffers, a:bufnr)
        call instance.Notify('textDocument/didClose', {'textDocument': {'uri': buffer.uri}})
      endif
    catch
      call copilot#logger#Exception()
    endtry
  endfor
endfunction

augroup copilot_agent
  autocmd!
  if !has('nvim')
    autocmd BufUnload * call s:CloseBuffer(+expand('<abuf>'))
  endif
augroup END

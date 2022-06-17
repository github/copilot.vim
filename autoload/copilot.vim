if exists('g:autoloaded_copilot')
  finish
endif
let g:autoloaded_copilot = 1

scriptencoding utf-8

let s:has_ghost_text = has('nvim-0.6') && exists('*nvim_buf_get_mark')

let s:hlgroup = 'CopilotSuggestion'

if len($XDG_CONFIG_HOME)
  let s:config_root = $XDG_CONFIG_HOME
elseif has('win32')
  let s:config_root = expand('~/AppData/Local')
else
  let s:config_root = expand('~/.config')
endif
let s:config_root .= '/github-copilot'
if !isdirectory(s:config_root)
  call mkdir(s:config_root, 'p', 0700)
endif

let s:config_hosts = s:config_root . '/hosts.json'

function! s:JsonBody(response) abort
  if get(a:response.headers, 'content-type', '') =~# '^application/json\>'
    let body = a:response.body
    return json_decode(type(body) == v:t_list ? join(body) : body)
  else
    throw 'Copilot: expected application/json but got ' . get(a:response.headers, 'content-type', 'no content type')
  endif
endfunction

function! copilot#HttpRequest(url, options, ...) abort
  return call('copilot#Call', ['httpRequest', extend({'url': a:url, 'timeout': 30000}, a:options)] + a:000)
endfunction

function! s:StatusNotification(params, ...) abort
  let status = get(a:params, 'status', '')
  if status ==? 'error'
    let s:agent_error = a:params.message
  else
    unlet! s:agent_error
  endif
endfunction

function! copilot#Init(...) abort
  call timer_start(0, { _ -> s:Start() })
endfunction

function! s:Start() abort
  if exists('s:agent.job') || exists('s:agent.client_id')
    return
  endif
  let s:agent = copilot#agent#New({'notifications': {
        \ 'statusNotification': function('s:StatusNotification'),
        \ 'PanelSolution': function('copilot#panel#Solution'),
        \ 'PanelSolutionsDone': function('copilot#panel#SolutionsDone'),
        \ }})
endfunction

function! s:Stop() abort
  if exists('s:agent')
    let agent = remove(s:, 'agent')
    call agent.Close()
  endif
endfunction

function! copilot#Agent() abort
  call s:Start()
  return s:agent
endfunction

function! copilot#Request(method, params, ...) abort
  let agent = copilot#Agent()
  return call(agent.Request, [a:method, a:params] + a:000)
endfunction

function! copilot#Call(method, params, ...) abort
  let agent = copilot#Agent()
  return call(agent.Call, [a:method, a:params] + a:000)
endfunction

function! copilot#Notify(method, params, ...) abort
  let agent = copilot#Agent()
  return call(agent.Notify, [a:method, a:params] + a:000)
endfunction

function! s:ReadTerms() abort
  let file = s:config_root . '/terms.json'
  try
    if filereadable(file)
      let terms = json_decode(join(readfile(file)))
      if type(terms) == v:t_dict
        return terms
      endif
    endif
  catch
  endtry
  return {}
endfunction

function! copilot#NvimNs() abort
  return nvim_create_namespace('github-copilot')
endfunction

function! copilot#Clear() abort
  if exists('g:_copilot_timer')
    call timer_stop(remove(g:, '_copilot_timer'))
  endif
  if exists('s:uuid')
    call copilot#Request('notifyRejected', {'uuids': [remove(s:, 'uuid')]})
  endif
  if exists('b:_copilot')
    call copilot#agent#Cancel(get(b:_copilot, 'first', {}))
    call copilot#agent#Cancel(get(b:_copilot, 'cycling', {}))
    unlet b:_copilot
  endif
  call s:UpdatePreview()
  return ''
endfunction

function! copilot#Dismiss() abort
  call copilot#Clear()
  return ''
endfunction

let s:filetype_defaults = {
      \ 'yaml': 0,
      \ 'markdown': 0,
      \ 'help': 0,
      \ 'gitcommit': 0,
      \ 'gitrebase': 0,
      \ 'hgcommit': 0,
      \ 'svn': 0,
      \ 'cvs': 0,
      \ '.': 0}

function! s:BufferDisabled() abort
  if exists('b:copilot_disabled')
    return b:copilot_disabled ? 3 : 0
  endif
  if exists('b:copilot_enabled')
    return b:copilot_enabled ? 0 : 4
  endif
  let short = empty(&l:filetype) ? '.' : split(&l:filetype, '\.', 1)[0]
  let config = get(g:, 'copilot_filetypes', {})
  if has_key(config, &l:filetype)
    return empty(config[&l:filetype])
  elseif has_key(config, short)
    return empty(config[short])
  elseif has_key(config, '*')
    return empty(config['*'])
  else
    return get(s:filetype_defaults, short, 1) == 0 ? 2 : 0
  endif
endfunction

function! copilot#Enabled() abort
  return get(g:, 'copilot_enabled', 1)
        \ && empty(s:BufferDisabled())
        \ && empty(copilot#Agent().StartupError())
endfunction

function! copilot#Complete(...) abort
  if exists('g:_copilot_timer')
    call timer_stop(remove(g:, '_copilot_timer'))
  endif
  let params = copilot#doc#Params()
  if !exists('b:_copilot.params') || b:_copilot.params !=# params
    let b:_copilot = {'params': params, 'first':
          \ copilot#Request('getCompletions', params)}
    let g:_copilot_last = b:_copilot
  endif
  let completion = b:_copilot.first
  if !a:0
    return completion.Await()
  else
    call copilot#agent#Result(completion, a:1)
    if a:0 > 1
      call copilot#agent#Error(completion, a:2)
    endif
  endif
endfunction

function! s:HideDuringCompletion() abort
  return get(g:, 'copilot_hide_during_completion', 1)
endfunction

function! s:SuggestionTextWithAdjustments() abort
  try
    if mode() !~# '^[iR]' || (s:HideDuringCompletion() && pumvisible()) || !s:dest || !exists('b:_copilot.suggestions')
      return ['', 0, 0, '']
    endif
    let choice = get(b:_copilot.suggestions, b:_copilot.choice, {})
    if !has_key(choice, 'range') || choice.range.start.line != line('.') - 1
      return ['', 0, 0, '']
    endif
    let line = getline('.')
    let offset = col('.') - 1
    if choice.range.start.character != 0
      call copilot#logger#Warn('unexpected range ' . json_encode(choice.range))
      return ['', 0, 0, '']
    endif
    let typed = strpart(line, 0, offset)
    let delete = strchars(strpart(line, offset))
    let uuid = get(choice, 'uuid', '')
    if typed ==# strpart(choice.text, 0, offset)
      return [strpart(choice.text, offset), 0, delete, uuid]
    elseif typed =~# '^\s*$'
      let leading = matchstr(choice.text, '^\s\+')
      if strpart(typed, 0, len(leading)) == leading
        return [strpart(choice.text, len(leading)), len(typed) - len(leading), delete, uuid]
      endif
    endif
  catch
    call copilot#logger#Exception()
  endtry
  return ['', 0, 0, '']
endfunction


function! s:Advance(count, context, ...) abort
  if a:context isnot# get(b:, '_copilot', {})
    return
  endif
  let a:context.choice += a:count
  if a:context.choice < 0
    let a:context.choice += len(a:context.suggestions)
  endif
  let a:context.choice %= len(a:context.suggestions)
  call s:UpdatePreview()
endfunction

function! s:GetSuggestionsCyclingCallback(context, result) abort
  let callbacks = remove(a:context, 'cycling_callbacks')
  let seen = {}
  for suggestion in a:context.suggestions
    let seen[suggestion.text] = 1
  endfor
  for suggestion in get(a:result, 'completions', [])
    if !has_key(seen, suggestion.text)
      call add(a:context.suggestions, suggestion)
      let seen[suggestion.text] = 1
    endif
  endfor
  for Callback in callbacks
    call Callback(a:context)
  endfor
endfunction

function! s:GetSuggestionsCycling(callback) abort
  if exists('b:_copilot.cycling_callbacks')
    call add(b:_copilot.cycling_callbacks, a:callback)
  elseif exists('b:_copilot.cycling')
    call a:callback(b:_copilot)
  elseif exists('b:_copilot.suggestions')
    let b:_copilot.cycling_callbacks = [a:callback]
    let b:_copilot.cycling = copilot#Request('getCompletionsCycling',
          \ b:_copilot.first.params,
          \ function('s:GetSuggestionsCyclingCallback', [b:_copilot]),
          \ function('s:GetSuggestionsCyclingCallback', [b:_copilot]),
          \ )
    call s:UpdatePreview()
  endif
  return ''
endfunction

function! copilot#Next() abort
  return s:GetSuggestionsCycling(function('s:Advance', [1]))
endfunction

function! copilot#Previous() abort
  return s:GetSuggestionsCycling(function('s:Advance', [-1]))
endfunction

function! copilot#GetDisplayedSuggestion() abort
  let [text, outdent, delete, uuid] = s:SuggestionTextWithAdjustments()

  return {
        \ 'uuid': uuid,
        \ 'text': text,
        \ 'outdentSize': outdent,
        \ 'deleteSize': delete}
endfunction

let s:dest = 0
function! s:WindowPreview(lines, outdent, delete, ...) abort
  try
    if !bufloaded(s:dest)
      let s:dest = -s:has_ghost_text
      return
    endif
    let buf = s:dest
    let winid = bufwinid(buf)
    call setbufvar(buf, '&modifiable', 1)
    let old_lines = getbufline(buf, 1, '$')
    if len(a:lines) < len(old_lines) && old_lines !=# ['']
      silent call deletebufline(buf, 1, '$')
    endif
    if empty(a:lines)
      call setbufvar(buf, '&modifiable', 0)
      if winid > 0
        call setmatches([], winid)
      endif
      return
    endif
    let col = col('.') - a:outdent - 1
    let text = [strpart(getline('.'), 0, col) . a:lines[0]] + a:lines[1:-1]
    if old_lines !=# text
      silent call setbufline(buf, 1, text)
    endif
    call setbufvar(buf, '&tabstop', &tabstop)
    if getbufvar(buf, '&filetype') !=# 'copilot.' . &filetype
      silent! call setbufvar(buf, '&filetype', 'copilot.' . &filetype)
    endif
    call setbufvar(buf, '&modifiable', 0)
    if winid > 0
      if col > 0
        call setmatches([{'group': s:hlgroup, 'id': 4, 'priority': 10, 'pos1': [1, 1, col]}] , winid)
      else
        call setmatches([] , winid)
      endif
    endif
  catch
    call copilot#logger#Exception()
  endtry
endfunction

function! s:ClearPreview() abort
  if exists('*nvim_buf_del_extmark')
    call nvim_buf_del_extmark(0, copilot#NvimNs(), 1)
  endif
endfunction

function! s:UpdatePreview() abort
  try
    let [text, outdent, delete, uuid] = s:SuggestionTextWithAdjustments()
    let text = split(text, "\n", 1)
    if empty(text[-1])
      call remove(text, -1)
    endif
    if s:dest > 0
      call s:WindowPreview(text, outdent, delete)
    endif
    if empty(text) || s:dest >= 0
      return s:ClearPreview()
    endif
    if exists('b:_copilot.cycling_callbacks')
      let annot = [[' '], ['(1/…)', 'CopilotAnnotation']]
    elseif exists('b:_copilot.cycling')
      let annot = [[' '], ['(' . (b:_copilot.choice + 1) . '/' . len(b:_copilot.suggestions) . ')', 'CopilotAnnotation']]
    else
      let annot = []
    endif
    let data = {'id': 1}
    let data.virt_text_win_col = virtcol('.') - 1
    let data.virt_text = [[text[0] . repeat(' ', delete - len(text[0])), s:hlgroup]]
    if len(text) > 1
      let data.virt_lines = map(text[1:-1], { _, l -> [[l, s:hlgroup]] })
      let data.virt_lines[-1] += annot
    else
      let data.virt_text += annot
    endif
    let data.hl_mode = 'combine'
    call nvim_buf_del_extmark(0, copilot#NvimNs(), 1)
    call nvim_buf_set_extmark(0, copilot#NvimNs(), line('.')-1, col('.')-1, data)
    if uuid !=# get(s:, 'uuid', '')
      let s:uuid = uuid
      call copilot#Request('notifyShown', {'uuid': uuid})
    endif
  catch
    return copilot#logger#Exception()
  endtry
endfunction

function! s:HandleTriggerResult(result) abort
  if !exists('b:_copilot')
    return
  endif
  let b:_copilot.suggestions = get(a:result, 'completions', [])
  let b:_copilot.choice = 0
  call s:UpdatePreview()
endfunction

function! s:Trigger(bufnr, timer) abort
  let timer = get(g:, '_copilot_timer', -1)
  unlet! g:_copilot_timer
  if a:bufnr !=# bufnr('') || a:timer isnot# timer || mode() !=# 'i'
    return
  endif
  if exists('s:auth_request')
    let g:_copilot_timer = timer_start(100, function('s:Trigger', [a:bufnr]))
    return
  endif
  call copilot#Complete(function('s:HandleTriggerResult'), function('s:HandleTriggerResult'))
endfunction

function! copilot#IsMapped() abort
  return get(g:, 'copilot_assume_mapped') ||
        \ hasmapto('copilot#Accept(', 'i')
endfunction
let s:is_mapped = copilot#IsMapped()

function! copilot#Schedule(...) abort
  call copilot#Clear()
  if !s:is_mapped || !s:dest || !copilot#Enabled()
    return
  endif
  let delay = a:0 ? a:1 : get(g:, 'copilot_idle_delay', 75)
  let g:_copilot_timer = timer_start(delay, function('s:Trigger', [bufnr('')]))
endfunction

function! copilot#OnInsertLeave() abort
  return copilot#Clear()
endfunction

function! copilot#OnInsertEnter() abort
  let s:is_mapped = copilot#IsMapped()
  let s:dest = bufnr('^copilot://$')
  if s:dest < 0 && !s:has_ghost_text
    let s:dest = 0
  endif
  return copilot#Schedule()
endfunction

function! copilot#OnCompleteChanged() abort
  if s:HideDuringCompletion()
    return copilot#Clear()
  endif
endfunction

function! copilot#OnCursorMovedI() abort
  return copilot#Schedule()
endfunction

function! copilot#TextQueuedForInsertion() abort
  try
    return remove(s:, 'suggestion_text')
  catch
    return ''
  endtry
endfunction

function! copilot#Accept(...) abort
  let s = copilot#GetDisplayedSuggestion()
  if !empty(s.text)
    unlet! b:_copilot
    call copilot#Request('notifyAccepted', {'uuid': s.uuid})
    unlet! s:uuid
    call s:ClearPreview()
    let s:suggestion_text = s.text
    return repeat("\<Left>\<Del>", s.outdentSize) . repeat("\<Del>", s.deleteSize) .
            \ "\<C-R>\<C-O>=copilot#TextQueuedForInsertion()\<CR>"
  endif
  let default = get(g:, 'copilot_tab_fallback', pumvisible() ? "\<C-N>" : "\t")
  if !a:0
    return default
  elseif type(a:1) == v:t_string
    return a:1
  elseif type(a:1) == v:t_func
    try
      return call(a:1, [])
    catch
      call copilot#logger#Exception()
      return default
    endtry
  else
    return default
  endif
endfunction

function! s:BrowserCallback(into, code) abort
  let a:into.code = a:code
endfunction

function! copilot#Browser() abort
  if type(get(g:, 'copilot_browser')) == v:t_list
    return copy(g:copilot_browser)
  elseif has('win32') && executable('rundll32')
    return ['rundll32', 'url.dll,FileProtocolHandler']
  elseif isdirectory('/private') && executable('/usr/bin/open')
    return ['/usr/bin/open']
  elseif executable('gio')
    return ['gio', 'open']
  elseif executable('xdg-open')
    return ['xdg-open']
  else
    return []
  endif
endfunction

let s:commands = {}

function s:NetworkStatusMessage() abort
  let err = copilot#Agent().StartupError()
  if !empty(err)
    return err
  endif
  try
    let info = copilot#agent#EditorInfo()
    let response = copilot#HttpRequest('https://copilot-proxy.githubusercontent.com/_ping',
          \ {'timeout': 5000, 'headers': {
            \ 'Editor-Version': info.editorInfo.name . '/' . info.editorInfo.version,
            \ 'Editor-Plugin-Version': info.editorPluginInfo.name . '/' . info.editorPluginInfo.version,
            \ }})
    if response.status == 466
      return "Server error:\n" . substitute(response.body, "\n$", '', '')
    endif
  catch /\%( timed out after \| getaddrinfo \|ERR_HTTP2_INVALID_SESSION\)/
    call copilot#logger#Exception()
    return 'Server connectivity issue'
  catch
    call copilot#logger#Exception()
  endtry
  return ''
endfunction

function! s:EnabledStatusMessage() abort
  let buf_disabled = s:BufferDisabled()
  if !s:has_ghost_text && bufwinid('copilot://') == -1
    return "Neovim 0.6 required to support ghost text"
  elseif !copilot#IsMapped()
    return '<Tab> map has been disabled or is claimed by another plugin'
  elseif !get(g:, 'copilot_enabled', 1)
    return 'Disabled globally by :Copilot disable'
  elseif buf_disabled is# 4
    return 'Disabled for current buffer by b:copilot_enabled'
  elseif buf_disabled is# 3
    return 'Disabled for current buffer by b:copilot_disabled'
  elseif buf_disabled is# 2
    return 'Disabled for filetype=' . &filetype . ' by internal default'
  elseif buf_disabled
    return 'Disabled for filetype=' . &filetype . ' by g:copilot_filetypes'
  elseif !copilot#Enabled()
    return 'BUG: Something is wrong with enabling/disabling'
  else
    return ''
  endif
endfunction

function! s:VerifySetup() abort
  let error = copilot#Agent().StartupError()
  if !empty(error)
    echo 'Copilot: ' . error
    return
  endif

  let status = copilot#Call('checkStatus', {})

  if !has_key(status, 'user')
    echo 'Copilot: Not authenticated. Invoke :Copilot setup'
    return
  endif

  if status.status ==# 'NoTelemetryConsent'
    echo 'Copilot: Telemetry terms not accepted. Invoke :Copilot setup'
    return
  endif
  return 1
endfunction

function! s:commands.status(opts) abort
  if !s:VerifySetup()
    return
  endif

  let status = s:EnabledStatusMessage()
  if !empty(status)
    echo 'Copilot: ' . status
    return
  endif

  let network_status = s:NetworkStatusMessage()
  if !empty(network_status)
      echo 'Copilot: ' . network_status
      return
  endif

  if exists('s:agent_error')
    echo 'Copilot: ' . s:agent_error
    return
  endif

  echo 'Copilot: Enabled and online'
endfunction

function! s:commands.signout(opts) abort
  let status = copilot#Call('checkStatus', {'options': {'localChecksOnly': v:true}})
  if has_key(status, 'user')
    echo 'Copilot: Signed out as GitHub user ' . status.user
  else
    echo 'Copilot: Not signed in'
  endif
  call copilot#Call('signOut', {})
endfunction

function! s:commands.setup(opts) abort
  let network_status = s:NetworkStatusMessage()
  if !empty(network_status)
    return 'echoerr ' . string('Copilot: ' . network_status)
  endif

  let browser = copilot#Browser()

  let status = copilot#Call('checkStatus', {})
  if has_key(status, 'user')
    let data = {}
  else
    let data = copilot#Call('signInInitiate', {})
  endif

  if has_key(data, 'verificationUri')
    let uri = data.verificationUri
    let @+ = data.userCode
    let @* = data.userCode
    echo "First copy your one-time code: " . data.userCode
    try
      if len(&mouse)
        let mouse = &mouse
        set mouse=
      endif
      if get(a:opts, 'bang')
        echo "In your browser, visit " . uri
      elseif len(browser)
        echo "Press ENTER to open GitHub in your browser"
        let c = getchar()
        while c isnot# 13 && c isnot# 10 && c isnot# 0
          let c = getchar()
        endwhile
        let status = {}
        call copilot#job#Stream(browser + [uri], v:null, v:null, function('s:BrowserCallback', [status]))
        let time = reltime()
        while empty(status) && reltimefloat(reltime(time)) < 5
          sleep 10m
        endwhile
        if get(status, 'code', browser[0] !=# 'xdg-open') != 0
          echo "Failed to open browser.  Visit " . uri
        else
          echo "Opened " . uri
        endif
      else
        echo "Could not find browser.  Visit " . uri
      endif
      echo "Waiting (could take up to 5 seconds)"
      let request = copilot#Request('signInConfirm', {'userCode': data.userCode}).Wait()
    finally
      if exists('mouse')
        let &mouse = mouse
      endif
    endtry
    if request.status ==# 'error'
      return 'echoerr ' . string('Copilot: Authentication failure: ' . request.error.message)
    else
      let status = request.result
    endif
  endif

  let user = get(status, 'user', '<unknown>')

  if status.status ==# 'NoTelemetryConsent'
    let terms_url = "https://github.co/copilot-telemetry-terms"
    echo "I agree to these telemetry terms as part of the GitHub Copilot technical preview."
    echo "<" . terms_url . ">"
    let prompt = '[a]gree/[r]efuse'
    if len(browser)
      let prompt .= '/[o]pen in browser'
    endif
    while 1
      let input = input(prompt . '> ')
      if input =~# '^r'
        redraw
        return 'echoerr ' . string('Copilot: Terms must be accepted.')
      elseif input =~# '^[ob]' && len(browser)
        if copilot#job#Stream(browser + [terms_url], v:null, v:null) != 0
          echo "\nCould not open browser."
        endif
      elseif input =~# '^a'
        break
      else
        echo "\nUnrecognized response."
      endif
    endwhile
    redraw
    call copilot#Call('recordTelemetryConsent', {})
  endif

  echo 'Copilot: Authenticated as GitHub user ' . user
endfunction

let s:commands.auth = s:commands.setup

function! s:commands.help(opts) abort
  return a:opts.mods . ' help ' . (len(a:opts.arg) ? ':Copilot_' . a:opts.arg : 'copilot')
endfunction

let s:feedback_url = 'https://github.com/github/feedback/discussions/categories/copilot-feedback'
function! s:commands.feedback(opts) abort
  echo s:feedback_url
  let browser = copilot#Browser()
  if len(browser)
    call copilot#job#Stream(browser + [s:feedback_url], v:null, v:null, v:null)
  endif
endfunction

function! s:commands.restart(opts) abort
  call s:Stop()
  let err = copilot#Agent().StartupError()
  if !empty(err)
    return 'echoerr ' . string('Copilot: ' . err)
  endif
  echo 'Copilot: Restarting agent.'
endfunction

function! s:commands.disable(opts) abort
  let g:copilot_enabled = 0
endfunction

function! s:commands.enable(opts) abort
  let g:copilot_enabled = 1
endfunction

function! s:commands.panel(opts) abort
  if s:VerifySetup()
    return copilot#panel#Open(a:opts)
  endif
endfunction

function! s:commands.split(opts) abort
  let mods = a:opts.mods
  if mods !~# '\<\%(aboveleft\|belowright\|leftabove\|rightbelow\|topleft\|botright\|tab\)\>'
    let mods = 'topleft ' . mods
  endif
  if a:opts.bang && getwinvar(bufwinid('copilot://'), '&previewwindow')
    if mode() =~# '^[iR]'
      " called from <Cmd> map
      return mods . ' pclose|sil! call copilot#OnInsertEnter()'
    else
      return mods . ' pclose'
    endif
  endif
  return mods . ' pedit copilot://'
endfunction

let s:commands.open = s:commands.split

function! copilot#CommandComplete(arg, lead, pos) abort
  let args = matchstr(strpart(a:lead, 0, a:pos), 'C\%[opilot][! ] *\zs.*')
  if args !~# ' '
    return sort(filter(map(keys(s:commands), { k, v -> tr(v, '_', '-') }),
          \ { k, v -> strpart(v, 0, len(a:arg)) ==# a:arg }))
  else
    return []
  endif
endfunction

function! copilot#Command(line1, line2, range, bang, mods, arg) abort
  let cmd = matchstr(a:arg, '^\%(\\.\|\S\)\+')
  let arg = matchstr(a:arg, '\s\zs\S.*')
  if cmd ==# 'log'
    return a:mods . ' split +$ ' . fnameescape(copilot#logger#File())
  endif
  if !empty(cmd) && !has_key(s:commands, tr(cmd, '-', '_'))
    return 'echoerr ' . string('Copilot: unknown command ' . string(cmd))
  endif
  try
    let err = copilot#Agent().StartupError()
    if !empty(err)
      return 'echo ' . string('Copilot: ' . string(err))
    endif
    let opts = copilot#Call('checkStatus', {'options': {'localChecksOnly': v:true}})
    if empty(cmd)
      if opts.status !=# 'OK' && opts.status !=# 'MaybeOK'
        let cmd = 'setup'
      else
        let cmd = 'panel'
      endif
    endif
    call extend(opts, {'line1': a:line1, 'line2': a:line2, 'range': a:range, 'bang': a:bang, 'mods': a:mods, 'arg': arg})
    let retval = s:commands[tr(cmd, '-', '_')](opts)
    if type(retval) == v:t_string
      return retval
    else
      return ''
    endif
  catch /^Copilot:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

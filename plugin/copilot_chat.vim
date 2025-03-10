scriptencoding utf-8

let s:plugin_dir = expand('<sfile>:p:h:h')
let s:device_token_file = s:plugin_dir . "/.device_token"
let s:chat_token_file = s:plugin_dir . "/.chat_token"
let s:token_headers = [
  \ 'Accept: application/json',
  \ 'User-Agent: GithubCopilot/1.155.0',
  \ 'Accept-Encoding: gzip,deflate,br',
  \ 'Editor-Plugin-Version: copilot.vim/1.16.0',
  \ 'Editor-Version: Neovim/0.6.1',
  \ 'Content-Type: application/json',
  \ ]

function! CopilotChat()
  " Open a new split window for the chat
  split
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nonumber
  setlocal norelativenumber
  setlocal wrap
  set filetype=markdown

  " Set the buffer name to indicate it's a chat window
  file CopilotChat

  call append(0, 'Welcome to Copilot Chat! Type your message below:')

  normal! G
endfunction

function! SubmitChatMessage()
  " TODO: this should be grabbing the full prompt between the separators
  let l:message = getline('$')

  call AsyncRequest(l:message)
endfunction

function HttpIt(method, url, headers, body)
  if has("win32")
    let l:ps_cmd = 'powershell -Command "'
    let l:ps_cmd .= '$headers = @{'
    for header in a:headers
      let [key, value] = split(header, ": ")
      let l:ps_cmd .= "'" . key . "'='" . value . "';"
    endfor
    let l:ps_cmd .= "};"
    if a:method != "GET"
      let l:ps_cmd .= '$body = ConvertTo-Json @{'
      for obj in keys(a:body)
        let l:ps_cmd .= obj . "='" . a:body[obj] . "';"
      endfor
      let l:ps_cmd .= "};"
    endif
    let l:ps_cmd .= "Invoke-WebRequest -Uri '" . a:url . "' -Method " .a:method . " -Headers $headers -Body $body -ContentType 'application/json' | Select-Object -ExpandProperty Content"
    let l:ps_cmd .= '"'
    let l:response = system(l:ps_cmd)
  else
    let l:token_data = json_encode(a:body)

    let l:curl_cmd = 'curl -s -X ' . a:method . ' --compressed '
    for header in a:headers
      let l:curl_cmd .= '-H "' . header . '" '
    endfor
    let l:curl_cmd .= "-d '" . l:token_data . "' " . a:url

    let l:response = system(l:curl_cmd)
    if v:shell_error != 0
      echom 'Error: ' . v:shell_error
      return ''
    endif
  endif
  return l:response
endfunction

function! GetDeviceToken()
  let l:token_url = 'https://github.com/login/device/code'
  let l:headers = [
    \ 'Accept: application/json',
    \ 'User-Agent: GithubCopilot/1.155.0',
    \ 'Accept-Encoding: gzip,deflate,br',
    \ 'Editor-Plugin-Version: copilot.vim/1.16.0',
    \ 'Editor-Version: Neovim/0.6.1',
    \ 'Content-Type: application/json',
    \ ]
  let l:data = {
    \ 'client_id': 'Iv1.b507a08c87ecfe98',
    \ 'scope': 'read:user'
    \ }

  return HttpIt("POST", l:token_url, l:headers, l:data)
endfunction

function! GetBearerToken()
  let l:response = GetDeviceToken()
  let l:json_response = json_decode(l:response)
  let l:device_code = l:json_response.device_code
  let l:user_code = l:json_response.user_code
  let l:verification_uri = l:json_response.verification_uri

  echo 'Please visit ' . l:verification_uri . ' and enter the code: ' . l:user_code
  call input("Press Enter to continue...\n")

  let l:token_poll_url = 'https://github.com/login/oauth/access_token'
  let l:token_poll_data = {
    \ 'client_id': 'Iv1.b507a08c87ecfe98',
    \ 'device_code': l:device_code,
    \ 'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'
    \ }
  let l:access_token_response = HttpIt("POST", l:token_poll_url, s:token_headers, l:token_poll_data)
  let l:json_response = json_decode(l:access_token_response)
  let l:bearer_token = l:json_response.access_token
  call writefile([l:bearer_token], s:device_token_file)

  return l:bearer_token
endfunction

function! GetChatToken(bearer_token)
  let l:token_url = 'https://api.github.com/copilot_internal/v2/token'
  let l:token_headers = [
        \ 'Content-Type: application/json',
        \ 'Editor-Version: vscode/1.80.1',
        \ 'Authorization: token ' . a:bearer_token,
        \ ]
  let l:token_data = {
        \ 'client_id': 'Iv1.b507a08c87ecfe98',
        \ 'scope': 'read:user'
        \ }
  let l:response = HttpIt("GET", l:token_url, l:token_headers, l:token_data)
  let l:json_response = json_decode(l:response)
  return l:json_response.token
endfunction

function! CheckDeviceToken()
    " fetch models
    " if the call fails we should get a new chat token and update the file
endfunction

function! AsyncRequest(message)
    let s:curl_output = []
    let l:url = 'https://api.githubcopilot.com/chat/completions'

    if filereadable(s:device_token_file)
      let l:bearer_token = join(readfile(s:device_token_file), "\n")
    else
      let l:bearer_token = GetBearerToken()
    endif
  
    let l:chat_token = GetChatToken(l:bearer_token)
    let l:messages = [{'content': a:message, 'role': 'user'}]
    let l:data = json_encode({
          \ 'intent': v:false,
          \ 'model': 'gpt-4o',
          \ 'temperature': 0,
          \ 'top_p': 1,
          \ 'n': 1,
          \ 'stream': v:true,
          \ 'messages': l:messages
          \ })
    
    let l:curl_cmd = [
        \ "curl",
        \ "-s",
        \ "-X",
        \ "POST",
        \ "-H",
        \ "Content-Type: application/json",
        \ "-H", "Authorization: Bearer " . l:chat_token,
        \ "-H", "Editor-Version: vscode/1.80.1",
        \ "-d",
        \ l:data,
        \ l:url]
    
    let job = job_start(l:curl_cmd, {'out_cb': function('HandleCurlOutput'), 'exit_cb': function('HandleCurlClose'), 'err_cb': function('HandleCurlError')})
    return job
endfunction

function! HandleCurlError(channel, msg)
    echom "handling curl error"
    echom a:msg
endfunction

function! HandleCurlClose(channel, msg)
    let l:result = ''
    for line in s:curl_output
        if line =~ '^data: {'
          let l:json_completion = json_decode(line[6:])
          try
            let l:result .= l:json_completion.choices[0].delta.content
          catch
            let l:result .= "\n"
          endtry
        endif
      endfor
      call append(line('$'), split(l:result, "\n"))
      normal! G
endfunction

function! HandleCurlOutput(channel, msg)
    call add(s:curl_output, a:msg)
endfunction

command! CopilotChat call CopilotChat()
command! SubmitChatMessage call SubmitChatMessage()

nnoremap <buffer> <leader>cs :SubmitChatMessage<CR>
nnoremap <leader>cc :CopilotChat<CR>
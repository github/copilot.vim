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

  " Set the buffer name to indicate it's a chat window
  file CopilotChat

  " Add initial message
  call append(0, 'Welcome to Copilot Chat! Type your message below:')

  " Move cursor to the end of the buffer
  normal! G
endfunction

function! SubmitChatMessage()
  " Get the last line of the buffer (user's message)
  let l:message = getline('$')

  " Call the CoPilot API to get a response
  let l:response = CopilotAPIRequest(l:message)

  " Append the parsed response to the buffer
  call append(line('$'), 'Copilot: ' . l:response)

  " Move cursor to the end of the buffer
  normal! G
endfunction

function! GetBearerToken()
  " Replace with actual token setup and device registry logic
  let l:token_url = 'https://github.com/login/device/code'
  " headers = {
  "   'accept': 'application/json',
  "   'editor-version': 'Neovim/0.6.1',
  "   'editor-plugin-version': 'copilot.vim/1.16.0',
  "   'content-type': 'application/json',
  "   'user-agent': 'GithubCopilot/1.155.0',
  "   'accept-encoding': 'gzip,deflate,br'
  " }

  let l:token_headers = [
        \ 'Accept: application/json',
        \ 'User-Agent: GithubCopilot/1.155.0',
        \ 'Accept-Encoding: gzip,deflate,br',
        \ 'Editor-Plugin-Version: copilot.vim/1.16.0',
        \ 'Editor-Version: Neovim/0.6.1',
        \ 'Content-Type: application/json',
        \ ]
  let l:token_data = json_encode({
        \ 'client_id': 'Iv1.b507a08c87ecfe98',
        \ 'scope': 'read:user'
        \ })

  " Construct the curl command for token setup
  let l:curl_cmd = 'curl -s -X POST --compressed '
  for header in l:token_headers
    let l:curl_cmd .= '-H "' . header . '" '
  endfor
  let l:curl_cmd .= "-d '" . l:token_data . "' " . l:token_url
  echom l:curl_cmd

  " Execute the curl command
  let l:response = system(l:curl_cmd)

  " Check for errors in the response
  if v:shell_error != 0
    echom 'Error: ' . v:shell_error
    return ''
  endif

  " Parse the response to get the device code and user code
  let l:json_response = json_decode(l:response)
  let l:device_code = l:json_response.device_code
  let l:user_code = l:json_response.user_code
  let l:verification_uri = l:json_response.verification_uri

  " Display the user code and verification URI to the user
  echom 'Please visit ' . l:verification_uri . ' and enter the code: ' . l:user_code

  " Wait for the user to complete the device verification
  sleep 30

  " Poll the token endpoint to get the Bearer token
  let l:token_poll_url = 'https://github.com/login/oauth/access_token'
  let l:token_poll_data = json_encode({
        \ 'client_id': 'Iv1.b507a08c87ecfe98',
        \ 'device_code': l:device_code,
        \ 'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'
        \ })

  " Construct the curl command for token polling
  let l:curl_cmd = 'curl -s -X POST --compressed '
  for header in l:token_headers
    let l:curl_cmd .= '-H "' . header . '" '
  endfor
  let l:curl_cmd .= "-d '" . l:token_poll_data . "' " . l:token_poll_url

  " Execute the curl command
  let l:response = system(l:curl_cmd)

  " Check for errors in the response
  if v:shell_error != 0
    echom 'Error: ' . v:shell_error
    return ''
  endif

  " Parse the response to get the Bearer token
  let l:json_response = json_decode(l:response)
  let l:bearer_token = l:json_response.access_token
  let $COPILOT_BEARER_TOKEN = l:bearer_token

  " Return the Bearer token
  return l:bearer_token
endfunction

function! GetChatToken()
  let l:token_url = 'https://api.github.com/copilot_internal/v2/token'
  let l:token_headers = [
        \ 'Content-Type: application/json',
        \ 'Editor-Version: vscode/1.80.1',
        \ 'Authorization: token ' . $COPILOT_BEARER_TOKEN,
        \ ]
  let l:token_data = json_encode({
        \ 'client_id': 'Iv1.b507a08c87ecfe98',
        \ 'scope': 'read:user'
        \ })

  " Construct the curl command for token setup
  let l:curl_cmd = 'curl -s -X GET '
  for header in l:token_headers
    let l:curl_cmd .= '-H "' . header . '" '
  endfor
  let l:curl_cmd .= "-d '" . l:token_data . "' " . l:token_url

  " Execute the curl command
  let l:response = system(l:curl_cmd)
  echom l:response

  " Check for errors in the response
  if v:shell_error != 0
    echom 'Error: ' . v:shell_error
    return ''
  endif

  " Parse the response to get the device code and user code
  let l:json_response = json_decode(l:response)
  return l:json_response.token
endfunction

function! CopilotAPIRequest(message)
  " Replace with actual API call logic
  let l:url = 'https://api.githubcopilot.com/chat/completions'
  if exists('$COPILOT_BEARER_TOKEN')
    let l:bearer_token = $COPILOT_BEARER_TOKEN
  else
    let l:bearer_token = GetBearerToken()
  endif

  let l:chat_token = GetChatToken()
  let l:headers = [
        \ 'Content-Type: application/json',
        \ 'Authorization: Bearer ' . l:chat_token,
        \ 'Editor-Version: vscode/1.80.1'
        \ ]
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

  " Construct the curl command as a single string
  let l:curl_cmd = 'curl -s -X POST '
  for header in l:headers
    let l:curl_cmd .= '-H "' . header . '" '
  endfor
  let l:curl_cmd .= "-d '" . l:data . "' " . l:url

  " Print the curl command for debugging
  echom l:curl_cmd

  " Execute the curl command
  let l:response = system(l:curl_cmd)

  " Print the raw response for debugging
  echom 'Response: ' . l:response

  " Check for errors in the response
  if v:shell_error != 0
    echom 'Error: ' . v:shell_error
    return 'Error: ' . l:response
  endif

  " Parse the response
  let l:result = ''
  let l:resp_text_lines = split(l:response, "\n")
  for line in l:resp_text_lines
    if line =~ '^data: {'
      let l:json_completion = json_decode(line[6:])
      try
        let l:result .= l:json_completion.choices[0].delta.content
      catch
        let l:result .= '\\n'
      endtry
    endif
  endfor

  " Return the parsed response
  return l:result
endfunction

" Map the command to open the chat
command! CopilotChat call CopilotChat()

" Map the command to submit a chat message
command! SubmitChatMessage call SubmitChatMessage()

" Add key mapping to submit chat message
nnoremap <buffer> <leader>cs :SubmitChatMessage<CR>
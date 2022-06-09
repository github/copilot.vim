if exists('g:autoloaded_copilot_prompt')
  finish
endif
let g:autoloaded_copilot_prompt = 1

scriptencoding utf-8

let s:slash = exists('+shellslash') ? '\' : '/'

function copilot#doc#UTF16Width(str) abort
  return strchars(substitute(a:str, "\\%#=2[^\u0001-\uffff]", "  ", 'g'))
endfunction

let s:language_normalization_map = {
      \ "text":            "plaintext",
      \ "javascriptreact": "javascript",
      \ "jsx":             "javascript",
      \ "typescriptreact": "typescript",
      \ }

function copilot#doc#LanguageForFileType(filetype) abort
  let filetype = substitute(a:filetype, '\..*', '', '')
  return get(s:language_normalization_map, empty(filetype) ? "text" : filetype, filetype)
endfunction

function! s:RelativePath(absolute) abort
  if exists('b:copilot_relative_path')
    return b:copilot_relative_path
  elseif exists('b:copilot_root')
    let root = b:copilot_root
  elseif len(get(b:, 'projectionist', {}))
    let root = sort(keys(b:projectionist), { a, b -> a < b })[0]
  else
    let root = getcwd()
  endif
  let root = tr(root, s:slash, '/') . '/'
  if strpart(tr(a:absolute, 'A-Z', 'a-z'), 0, len(root)) ==# tr(root, 'A-Z', 'a-z')
    return strpart(a:absolute, len(root))
  else
    return fnamemodify(a:absolute, ':t')
  endif
endfunction

function! s:UrlEncode(str) abort
  return substitute(iconv(a:str, 'latin1', 'utf-8'),'[^A-Za-z0-9._~!$&''()*+,;=:@/-]','\="%".printf("%02X",char2nr(submatch(0)))','g')
endfunction

function! copilot#doc#Get() abort
  let absolute = tr(@%, s:slash, '/')
  if absolute !~# '^\a\+:\|^/\|^$' && &buftype =~# '^\%(nowrite\)\=$'
    let absolute = substitute(tr(getcwd(), s:slash, '/'), '/\=$', '/', '') . absolute
  endif
  if has('win32') && absolute =~# '^\a://\@!'
    let uri = 'file:///' . strpart(absolute, 0, 2) . s:UrlEncode(strpart(absolute, 2))
  elseif absolute =~# '^/'
    let uri = 'file://' . s:UrlEncode(absolute)
  elseif absolute =~# '^\a[[:alnum:].+-]*:\|^$'
    let uri = absolute
  else
    let uri = ''
  endif
  let doc = {
        \ 'languageId': copilot#doc#LanguageForFileType(&filetype),
        \ 'path': absolute,
        \ 'uri': uri,
        \ 'relativePath': s:RelativePath(absolute),
        \ 'insertSpaces': &expandtab ? v:true : v:false,
        \ 'tabSize': shiftwidth(),
        \ 'indentSize': shiftwidth(),
        \ }
  let line = getline('.')
  let col_byte = col('.') - (mode() =~# '^[iR]' || empty(line))
  let col_utf16 = copilot#doc#UTF16Width(strpart(line, 0, col_byte))
  let doc.position = {'line': line('.') - 1, 'character': col_utf16}
  let lines = getline(1, '$')
  if &eol
    call add(lines, "")
  endif
  let doc.source = join(lines, "\n")
  return doc
endfunction

function! copilot#doc#Params(...) abort
  let extra = a:0 ? a:1 : {}
  let params = extend({'doc': extend(copilot#doc#Get(), get(extra, 'doc', {}))}, extra, 'keep')
  let params.textDocument = {
        \ 'uri': params.doc.uri,
        \ 'languageId': params.doc.languageId,
        \ 'relativePath': params.doc.relativePath,
        \ }
  let params.position = params.doc.position
  return params
endfunction

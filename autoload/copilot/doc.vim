if exists('g:autoloaded_copilot_prompt')
  finish
endif
let g:autoloaded_copilot_prompt = 1

scriptencoding utf-8

function copilot#doc#UTF16Width(str) abort
  return strchars(substitute(a:str, "[^\u0001-\uffff]", "  ", 'g'))
endfunction

let s:language_normalization_map = {
      \ "javascriptreact": "javascript",
      \ "jsx":             "javascript",
      \ "typescriptreact": "typescript",
      \ }

function copilot#doc#LanguageForFileType(filetype) abort
  let filetype = substitute(a:filetype, '\..*', '', '')
  return get(s:language_normalization_map, filetype, filetype)
endfunction

function! copilot#doc#RelativePath() abort
  if exists('b:copilot_relative_path')
    return b:copilot_relative_path
  elseif exists('b:copilot_root')
    let root = b:copilot_root
  elseif len(get(b:, 'projectionist', {}))
    let root = sort(keys(b:projectionist), { a, b -> a < b })[0]
  else
    let root = getcwd()
  endif
  let root .= '/'
  let absolute = expand('%:p')
  if strpart(tr(absolute, 'A-Z\', 'a-z/'), 0, len(root)) ==# tr(root, 'A-Z\', 'a-z/')
    return strpart(absolute, len(root))
  else
    return expand('%:t')
  endif
endfunction

function! copilot#doc#Get() abort
  let doc = {
        \ 'languageId': copilot#doc#LanguageForFileType(&filetype),
        \ 'path': expand('%:p'),
        \ 'relativePath': copilot#doc#RelativePath(),
        \ 'insertSpaces': &expandtab ? v:true : v:false,
        \ 'tabSize': shiftwidth(),
        \ 'indentSize': shiftwidth(),
        \ }
  let line = getline('.')
  let col_byte = col('.') - (mode() !~# '^[iR]' || empty(line))
  let col_utf16 = copilot#doc#UTF16Width(strpart(line, 0, col_byte))
  let doc.position = {'line': line('.') - 1, 'character': col_utf16}
  let lines = getline(1, '$')
  if &eol
    call add(lines, "")
  endif
  let doc.source = join(lines, "\n")
  return doc
endfunction

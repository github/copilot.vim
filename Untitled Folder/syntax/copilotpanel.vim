scriptencoding utf-8

if exists("b:current_syntax")
  finish
endif

let s:subtype = matchstr(&l:filetype, '\<copilotpanel\.\zs[[:alnum:]_-]\+')
if !empty(s:subtype) && s:subtype !~# 'copilot'
  silent! exe 'syn include @copilotpanelLanguageTop syntax/' . s:subtype . '.vim'
  unlet! b:current_syntax
endif

syn region copilotpanelHeader start="\%^" end="^─\@="
syn region copilotpanelItem matchgroup=copilotpanelSeparator start="^─\{9,}$" end="\%(^─\{9,\}$\)\@=\|\%$" keepend contains=@copilotpanelLanguageTop

hi def link copilotpanelHeader PreProc
hi def link copilotpanelSeparator Comment

let b:current_syntax = "copilotpanel"

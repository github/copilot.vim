# Copilot.vim

GitHub Copilot is an AI pair programmer which suggests line completions and
entire function bodies as you type. GitHub Copilot is powered by the OpenAI
Codex AI system, trained on public Internet text and billions of lines of
code.

Copilot.vim is a Vim plugin for GitHub Copilot.  For now, it requires Neovim
0.6 (for virtual lines support) and a Node.js installation.

To learn more about GitHub Copilot, visit https://copilot.github.com.

## Technical Preview

Access to GitHub Copilot is limited to a small group of testers during the
technical preview of GitHub Copilot. If you don’t have access to the technical
preview, you will see an error when you try to use this extension.

Don’t have access yet? [Sign up for the
waitlist](https://github.com/features/copilot/signup) for your chance to try
it out. GitHub will notify you once you have access.

This technical preview is a Beta Preview under the [GitHub Terms of
Service](https://docs.github.com/en/github/site-policy/github-terms-of-service#j-beta-previews).

## Getting started

1.  Install [Node.js][] 12 or newer. 
(On apple silicon computers is required version 16 or newer.)

2.  Install [Neovim][] 0.6 or newer.

3.  Install `github/copilot.vim` using vim-plug, packer.nvim, or any other
    plugin manager.  Or to install directly:

        git clone https://github.com/github/copilot.vim.git \
          ~/.config/nvim/pack/github/start/copilot.vim

4.  Start Neovim and invoke `:Copilot setup`.

[Node.js]: https://nodejs.org/en/download/
[Neovim]: https://github.com/neovim/neovim/releases/latest

Suggestions are displayed inline and can be accepted by pressing the tab key.
See `:help copilot` for more information.

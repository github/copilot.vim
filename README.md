# Copilot.vim

GitHub Copilot is an AI pair programmer which suggests line completions and
entire function bodies as you type. GitHub Copilot is powered by the OpenAI
Codex AI system, trained on public Internet text and billions of lines of
code.

Copilot.vim is a Vim plugin for GitHub Copilot.  For now, it requires a Neovim
0.6 prerelease and a Node.js installation.

To learn more about GitHub Copilot, visit https://copilot.github.com.

## Getting started

1.  Make sure you have access to GitHub Copilot. You can sign up for an account at https://copilot.github.com. There is a waitlist as of Oct 2021. If you don't have an account, you can't use this plugin.
  
2.  Install [Node.js][] v12 or newer.

3.  Install a [Neovim prerelease build][].  (Note: On macOS, [extra steps][]
    are required to due to lack of notarization. Alternatively, Homebrew users
    can run `brew install neovim --HEAD`).

4.  Install `github/copilot.vim` using vim-plug, packer.nvim, or any other
    plugin manager.  Or to install directly:

        git clone https://github.com/github/copilot.vim.git \
          ~/.config/nvim/pack/github/start/copilot.vim

5.  Start Neovim and invoke `:Copilot setup`.

[Node.js]: https://nodejs.org/en/download/
[Neovim prerelease build]: https://github.com/github/copilot.vim/releases/tag/neovim-nightlies
[extra steps]: https://github.com/neovim/neovim/issues/11011#issuecomment-786413100

Suggestions are displayed inline and can be accepted by pressing the tab key.
See `:help copilot` for more information.

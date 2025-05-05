# GitHub Copilot for Vim and Neovim

GitHub Copilot is an AI pair programmer tool that helps you write code faster
and smarter. Trained on billions of lines of public code, GitHub Copilot turns
natural language prompts including comments and method names into coding
suggestions across dozens of languages.

Copilot.vim is a Vim/Neovim plugin for GitHub Copilot.

To learn more, visit
[https://github.com/features/copilot](https://github.com/features/copilot).

## Getting access to GitHub Copilot

To access GitHub Copilot, an active GitHub Copilot subscription is required.
Sign up for [GitHub Copilot Free](https://github.com/settings/copilot), or
request access from your enterprise admin.

## Getting started

1.  Install [Neovim][] or the latest patch of [Vim][] (9.0.0185 or newer).

2.  Install [Node.js][].

3.  Install `github/copilot.vim` using vim-plug, lazy.nvim, or any other
    plugin manager.  Or to install manually, run one of the following
    commands:

    * Vim, Linux/macOS:

          git clone --depth=1 https://github.com/github/copilot.vim.git \
            ~/.vim/pack/github/start/copilot.vim

    * Neovim, Linux/macOS:

          git clone --depth=1 https://github.com/github/copilot.vim.git \
            ~/.config/nvim/pack/github/start/copilot.vim

    * Vim, Windows (PowerShell command):

          git clone --depth=1 https://github.com/github/copilot.vim.git `
            $HOME/vimfiles/pack/github/start/copilot.vim

    * Neovim, Windows (PowerShell command):

          git clone --depth=1 https://github.com/github/copilot.vim.git `
            $HOME/AppData/Local/nvim/pack/github/start/copilot.vim

4.  Start Vim/Neovim and invoke `:Copilot setup`.

[Node.js]: https://nodejs.org/en/download/
[Neovim]: https://github.com/neovim/neovim/releases/latest
[Vim]: https://github.com/vim/vim

Suggestions are displayed inline and can be accepted by pressing the tab key.
See `:help copilot` for more information.

## Troubleshooting

We’d love to get your help in making GitHub Copilot better!  If you have
feedback or encounter any problems, please reach out on our [feedback
forum](https://github.com/github/copilot.vim/issues).

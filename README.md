# GitHub Copilot for Vim and Neovim

> **GitHub Copilot** is your AI-powered coding companion, helping you write code faster and smarter with context-aware suggestions directly in Vim and Neovim.

Copilot.vim brings the capabilities of GitHub Copilot to Vim/Neovim, turning natural language prompts and comments into code suggestions across dozens of programming languages.

- **Official Site:** [GitHub Copilot Features](https://github.com/features/copilot)
- **Plugin Repository:** [github/copilot.vim](https://github.com/github/copilot.vim)

---

## 🚀 Features

- Inline AI-powered code suggestions as you type.
- Support for Vim (`9.0.0185+`) and Neovim.
- Easy setup and seamless integration.
- Works with popular plugin managers (vim-plug, lazy.nvim, etc.).
- Accept suggestions with the tab key.

---

## 📝 Requirements

- **Vim:** Version `9.0.0185` or newer
- **Neovim:** Latest release
- **Node.js:** [Download here](https://nodejs.org/en/download/)
- **GitHub Copilot Subscription:** [Sign up here](https://github.com/settings/copilot) or request access from your enterprise admin.

---

## 📦 Installation

You can use your favorite plugin manager, or install manually:

### Using vim-plug (example)

```vim
Plug 'github/copilot.vim'
```

### Manual Installation

**For Vim (Linux/macOS):**
```sh
git clone --depth=1 https://github.com/github/copilot.vim.git \
  ~/.vim/pack/github/start/copilot.vim
```

**For Neovim (Linux/macOS):**
```sh
git clone --depth=1 https://github.com/github/copilot.vim.git \
  ~/.config/nvim/pack/github/start/copilot.vim
```

**For Vim (Windows, PowerShell):**
```powershell
git clone --depth=1 https://github.com/github/copilot.vim.git `
  $HOME/vimfiles/pack/github/start/copilot.vim
```

**For Neovim (Windows, PowerShell):**
```powershell
git clone --depth=1 https://github.com/github/copilot.vim.git `
  $HOME/AppData/Local/nvim/pack/github/start/copilot.vim
```

---

## ⚡ Getting Started

1. Install Vim/Neovim and Node.js (see above).
2. Install Copilot.vim using your preferred method.
3. Start Vim or Neovim.
4. Run `:Copilot setup` to configure the plugin.
5. Start coding! Suggestions will appear inline, and you can accept them by pressing the **Tab** key.

See `:help copilot` in Vim/Neovim for detailed usage.

---

## 💡 Troubleshooting & Feedback

If you have questions, feedback, or encounter issues, please visit our [Feedback Forum](https://github.com/github/copilot.vim/issues).

Help us make GitHub Copilot even better!

---

## 📚 Useful Links

- [Node.js Download](https://nodejs.org/en/download/)
- [Neovim Releases](https://github.com/neovim/neovim/releases/latest)
- [Vim Releases](https://github.com/vim/vim)

---

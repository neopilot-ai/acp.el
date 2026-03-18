<!-- omit in toc -->
<div align="center">

# acp.el

### Native Emacs Shell for LLM Agents

[![MELPA][melma-badge]][melpa]
[![License: GPL v3][license-badge]][license]
[![Emacs 29.1+][emacs-badge]][emacs]
[![GitHub stars][stars-badge]][stars]
[![GitHub issues][issues-badge]][issues]

*A native `comint` shell experience to interact with any ACP-powered agent.*

[Overview](#-overview) •
[Features](#-features) •
[Installation](#-installation) •
[Quick Start](#-quick-start) •
[Supported Agents](#-supported-agents) •
[Configuration](#-configuration) •
[Documentation](#-documentation)

</div>

---

## 📚 Overview

`acp.el` is an Emacs package that provides a native shell interface to interact with LLM agents powered by **ACP (Agent Client Protocol)**. Built on top of `comint-mode`, it offers seamless integration with your Emacs workflow.

```
┌─────────────────────────────────────────────────────────────┐
│  acp.el                                                   │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐  │
│  │   Emacs     │───▶│   acp.el      │───▶│   Agent      │  │
│  │   User      │◀───│              │◀───│  (Claude,    │  │
│  └─────────────┘    └──────────────┘    │   Gemini...)  │  │
│                                         └─────────────┘  │
│  Built on comint-mode                        ▲            │
│  Powered by ACP Protocol                     │            │
└──────────────────────────────────────────────┼────────────┘
                                               │
                                        ┌──────┴──────┐
                                        │   acp.el    │
                                        │  (Protocol) │
                                        └─────────────┘
```

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔌 **Multiple Agents** | Claude Code, Gemini CLI, Codex, Goose, Cursor, and more |
| 🐚 **Native Shell** | Built on `comint-mode` for authentic shell experience |
| 📋 **Session Management** | Save, resume, and switch between sessions |
| 🔧 **MCP Support** | Configure Model Context Protocol servers |
| 📦 **Dev Containers** | Run agents inside Docker/ devcontainers |
| 🎨 **Rich UI** | Syntax highlighting, collapsible blocks, tool displays |
| 📝 **Transcript Export** | Save conversations as Markdown |

## 🚀 Installation

### Via MELPA (Recommended)

```elisp
(use-package acp
  :ensure t)
```

### Via straight.el

```elisp
(straight-use-package 'acp)
```

### Manual Installation

```elisp
(add-to-list 'load-path "/path/to/acp.el")
(add-to-list 'load-path "/path/to/acp.el/agents")
(add-to-list 'load-path "/path/to/acp.el/ui")
(add-to-list 'load-path "/path/to/acp.el/features")
(require 'acp)
```

## ⚡ Quick Start

```
M-x acp
```

### Keybindings

| Binding | Action |
|---------|--------|
| `C-c C-c` | Interrupt agent |
| `TAB` / `n` | Next item |
| `S-TAB` / `p` | Previous item |
| `C-c C-v` | Set model |
| `C-c C-o` | Switch buffer |

## 🤖 Supported Agents

```
┌──────────────────────────────────────────────────────────────────┐
│                        Agent Matrix                              │
├─────────────┬─────────────┬──────────────┬─────────────────────┤
│   Agent     │   Company   │    Status    │     Features         │
├─────────────┼─────────────┼──────────────┼─────────────────────┤
│ Claude Code │ Anthropic   │ ✅ Active     │ Files, Edit, Search │
│ Gemini CLI  │ Google      │ ✅ Active     │ Files, Bash, Search │
│ Codex       │ OpenAI      │ ✅ Active     │ Files, Edit         │
│ Goose       │ Block        │ ✅ Active     │ Files, Bash         │
│ Cursor      │ Cursor      │ ✅ Active     │ Files, Edit         │
│ Qwen Code   │ Alibaba     │ ✅ Active     │ Files, Bash         │
│ Mistral     │ Mistral AI  │ ✅ Active     │ Files, Edit         │
│ Kiro CLI    │ Kiro        │ ✅ Active     │ Files, Bash         │
│ Auggie      │ AugmentCode │ ✅ Active     │ Files, Edit         │
│ Droid       │ Factory     │ ✅ Active     │ Files, Bash         │
│ Pi          │ Pi AI       │ ✅ Beta       │ Files, Edit         │
│ OpenCode    │ OpenCode    │ ✅ Beta       │ Files, Bash         │
└─────────────┴─────────────┴──────────────┴─────────────────────┘
```

## ⚙️ Configuration

### Basic Setup

```elisp
(require 'acp)

;; Set preferred agent
(setq acp-preferred-agent-config
      (acp-anthropic-make-claude-code-config))

;; Set authentication
(setq acp-anthropic-authentication
      (acp-anthropic-make-authentication :api-key "your-key-here"))
```

### Environment Variables

```elisp
(setq acp-anthropic-claude-environment
      (acp-make-environment-variables
       "HTTPS_PROXY" "http://proxy:8080"))
```

### MCP Servers

```elisp
(setq acp-mcp-servers
  '(((name . "filesystem")
     (type . file-system))
    ((name . "notion")
     (url . "https://mcp.notion.com/mcp"))))
```

### Dev Container Support

```elisp
(setq acp-command-prefix '("devcontainer" "exec" "--workspace-folder" "."))
(setq acp-path-resolver-function #'acp-devcontainer-resolve-path)
```

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [AGENTS.md][agents] | Project guidelines for contributors |
| [CONTRIBUTING.org][contributing] | How to contribute |
| [GEMINI.md][gemini] | Gemini CLI specific guide |
| [CLAUDE.md][claude] | Claude Code specific guide |

## 🗺️ Roadmap

```
┌────────────────────────────────────────────────────────────────┐
│                        acp.el Roadmap                           │
├────────────────────────────────────────────────────────────────┤
│ v0.50 (Next)                                                   │
│ ├── ✅ Session persistence                                      │
│ ├── 🔄 Multi-agent coordination                                │
│ └── 📊 Usage analytics                                         │
├────────────────────────────────────────────────────────────────┤
│ v0.60 (Planned)                                               │
│ ├── 🌐 Web search integration                                  │
│ ├── 📁 File tree browser                                       │
│ └── 🎨 Theme customization                                     │
├────────────────────────────────────────────────────────────────┤
│ Future                                                         │
│ ├── 🤝 Agent-to-agent communication                            │
│ └── 📱 Mobile companion app                                    │
└────────────────────────────────────────────────────────────────┘
```

## 🙏 Acknowledgments

Built with ❤️ by [NeoPilot AI][author]

Supported by amazing [contributors][contributors] and the Emacs community.

[![Contributors][contributors-badge]][contributors]

---

<div align="center">

**⭐ Star this repo if `acp.el` makes your developer life better!**

*Sponsored by [GitHub Sponsors][sponsor]*

</div>

<!-- omit in toc -->
## Links

[melpa]: https://melpa.org/#/acp
[license]: https://www.gnu.org/licenses/gpl-3.0
[emacs]: https://www.gnu.org/software/emacs/
[stars]: https://github.com/neopilot-ai/acp.el/stargazers
[issues]: https://github.com/neopilot-ai/acp.el/issues
[author]: https://github.com/neopilot-ai
[sponsor]: https://github.com/sponsors/neopilot-ai
[contributors]: https://github.com/neopilot-ai/acp.el/graphs/contributors
[agents]: ./AGENTS.md
[contributing]: ./CONTRIBUTING.org
[gemini]: ./GEMINI.md
[claude]: ./CLAUDE.md

<!-- omit in toc -->
## Badges

[melma-badge]: https://melpa.org/packages/acp-badge.svg
[license-badge]: https://img.shields.io/badge/License-GPL%20v3-blue.svg
[emacs-badge]: https://img.shields.io/badge/Emacs-29.1+-7F5AB6.svg?style=flat-square&logo=gnu-emacs
[stars-badge]: https://img.shields.io/github/stars/neopilot-ai/acp.el?style=social
[issues-badge]: https://img.shields.io/github/issues/neopilot-ai/acp.el
[contributors-badge]: https://contrib.rocks/image?repo=neopilot-ai/acp.el


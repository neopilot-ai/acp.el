<!-- omit in toc -->
<div align="center">

```text
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   ███████╗██████╗  █████╗  ██████╗    ██████╗  █████╗ ██████╗  ║
║   ██╔════╝██╔══██╗██╔══██╗██╔════╝   ██╔═══██╗██╔══██╗██╔══██╗ ║
║   █████╗  ██████╔╝███████║██║        ██║   ██║███████║██████╔╝ ║
║   ██╔══╝  ██╔══██╗██╔══██║██║        ██║   ██║██╔══██║██╔═══╝  ║
║   ███████╗██║  ██║██║  ██║╚██████╗   ╚██████╔╝██║  ██║██║      ║
║   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══════╝    ╚═════╝ ╚═╝  ╚═╝╚═╝      ║
║                         ██████╗ ███████╗                        ║
║                        ██╔════╝ ██╔════╝                        ║
║                        ██║  ███╗█████╗                          ║
║                        ██║   ██║██╔══╝                          ║
║                        ╚██████╔╝███████╗                        ║
║                         ╚═════╝ ╚══════╝                        ║
║                     .el — Emacs LLM Agent Shell                 ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
```

### 🦄 Native Emacs Shell for LLM Agents

[![MELPA][melpa-badge]][melpa]
[![Docker][docker-badge]][docker]
[![License: GPL v3][license-badge]][license]
[![Emacs 29.1+][emacs-badge]][emacs]
[![GitHub stars][stars-badge]][stars]
[![GitHub issues][issues-badge]][issues]
[![Twitter][twitter-badge]][twitter]

*A native `comint` experience for ACP-powered AI agents*

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

`acp.el` brings the power of **Agent Client Protocol (ACP)** directly into Emacs. Interact with Claude Code, Gemini CLI, Codex, and other AI agents through a native shell interface built on `comint-mode`.

```
┌─────────────────────────────────────────────────────────────────┐
│                        acp.el Architecture                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│    ╭──────────────────────────────────────────────────────╮     │
│    │                    Your Emacs                         │     │
│    │  ┌─────────────────────────────────────────────────┐ │     │
│    │  │                  acp.el                        │ │     │
│    │  │  ┌─────────┐  ┌──────────┐  ┌─────────────┐   │ │     │
│    │  │  │  UI     │  │ Sessions │  │   Agents    │   │ │     │
│    │  │  │ Layer   │  │ Manager  │  │   Layer    │   │ │     │
│    │  │  └────┬────┘  └────┬─────┘  └──────┬──────┘   │ │     │
│    │  └────────┼───────────┼────────────────┼──────────┘ │     │
│    ╰──────────┼───────────┼────────────────┼─────────────╯     │
│               │           │                │                    │
│               ▼           ▼                ▼                    │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │                    comint-mode                           │  │
│    │              (Terminal Interface)                        │  │
│    └─────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│    ┌─────────────────────────────────────────────────────────┐  │
│    │                      ACP Protocol                       │  │
│    │            (Agent Client Protocol)                       │  │
│    └─────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌───────┐ │
│    │Claude  │  │Gemini  │  │Codex   │  │Goose   │  │Other  │ │
│    │  Code  │  │  CLI   │  │        │  │        │  │Agents │ │
│    └────────┘  └────────┘  └────────┘  └────────┘  └───────┘ │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## ✨ Features

<div align="center">

| | | |
|:---:|:---:|:---:|
| 🤖 **Multi-Agent** | 🐚 **Native Shell** | 💾 **Sessions** |
| Claude, Gemini, Codex & more | Built on comint-mode | Save, resume, switch |
| 🔧 **MCP Support** | 📦 **Containers** | 🎨 **Rich UI** |
| Model Context Protocol | Docker & devcontainers | Syntax, collapsible blocks |
| 📝 **Transcripts** | ⚡ **Keybindings** | 🔌 **Hot Reload** |
| Export as Markdown | Full Emacs keybindings | Reload without restart |

</div>

---

## 🚀 Installation

### 📦 Via MELPA (Recommended)

```elisp
;; Using use-package
(use-package acp
  :ensure t)

;; Or straight.el
(straight-use-package 'acp)
```

### 🛠️ Manual Installation

```elisp
(add-to-list 'load-path "/path/to/acp.el")
(add-to-list 'load-path "/path/to/acp.el/agents")
(add-to-list 'load-path "/path/to/acp.el/ui")
(add-to-list 'load-path "/path/to/acp.el/features")
(require 'acp-shell)
```

### 📋 Requirements

| Package | Version | Description |
|---------|---------|-------------|
| Emacs | 29.1+ | Core requirement |
| shell-maker | 0.89.2+ | Shell interface |
| acp | 0.11.1+ | ACP protocol |

---

## ⚡ Quick Start

```elisp
;; Basic usage
M-x acp

;; Or start specific agent
M-x acp-anthropic-start-claude-code
M-x acp-google-start-gemini
```

### ⌨️ Keybindings

<div align="center">

| Keys | Action |
|:-----|:-------|
| `C-c C-c` | Interrupt agent |
| `TAB` | Next item |
| `S-TAB` | Previous item |
| `C-c C-v` | Set session model |
| `C-c C-o` | Switch buffer |
| `C-c C-m` | Set session mode |
| `M-p/M-n` | Command history |

</div>

---

## 🤖 Supported Agents

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              Agent Support Matrix                           │
├──────────────────┬───────────────┬────────────────────────────────────────┤
│      Agent       │    Company    │              Features                   │
├──────────────────┼───────────────┼────────────────────────────────────────┤
│ Claude Code      │ 🦄 Anthropic  │ Files, Edit, Bash, Search, Multi-turn  │
│ Gemini CLI       │ 🔵 Google     │ Files, Bash, Search, MCP              │
│ Codex            │ 🟢 OpenAI     │ Files, Edit, Bash, Code execution     │
│ Goose            │ 🦆 Block      │ Files, Bash, Search, MCP              │
│ Cursor           │ 💜 Cursor     │ Files, Edit, Bash, Chat               │
│ Qwen Code        │ � Alibaba    │ Files, Bash, Search                   │
│ Mistral Vibe     │ 🔷 Mistral    │ Files, Edit, Bash                     │
│ Kiro CLI         │ ⚡ Kiro       │ Files, Bash, Search                   │
│ Auggie           │ 💙 Augment    │ Files, Edit, Bash                     │
│ Factory Droid    │ 🤖 Factory    │ Files, Bash, Search                   │
│ Pi               │ 🍌 Pi AI      │ Files, Edit (Beta)                    │
│ OpenCode         │ 📦 OpenCode   │ Files, Bash (Beta)                    │
└──────────────────┴───────────────┴────────────────────────────────────────┘
```

---

## ⚙️ Configuration

### Basic Setup

```elisp
(require 'acp-shell)

;; Set preferred agent
(setq acp-preferred-agent-config
      (acp-anthropic-make-claude-code-config))

;; Authentication (choose one)
(setq acp-anthropic-authentication
      (acp-anthropic-make-authentication :api-key "sk-ant-..."))

;; Or login via browser
(setq acp-anthropic-authentication
      (acp-anthropic-make-authentication :login t))
```

### Environment Variables

```elisp
(setq acp-anthropic-claude-environment
      (acp-make-environment-variables
       "HTTPS_PROXY" "http://proxy.example.com:8080"
       "HTTP_PROXY"  "http://proxy.example.com:8080"))

;; Inherit parent Emacs environment
(setq acp-anthropic-claude-environment
      (acp-make-environment-variables :inherit-env t))
```

### MCP Servers

```elisp
(setq acp-mcp-servers
  '(; Example: Filesystem access
    ((name . "filesystem")
     (type . file-system)
     (config . ((allowedDirectories . ["~/"]))))
    
    ; Example: Notion integration  
    ((name . "notion")
     (type . http)
     (url . "https://mcp.notion.com/mcp"))))
```

### Dev Container Support

```elisp
;; Run agents inside containers
(setq acp-command-prefix '("devcontainer" "exec" "--workspace-folder" "."))

;; Path resolution
(setq acp-path-resolver-function #'acp-devcontainer-resolve-path)
```

---

## 📖 Documentation

<div align="center">

| Guide | Description |
|:------|:------------|
| 📘 [AGENTS.md][agents] | Project guidelines & architecture |
| 📗 [CONTRIBUTING.org][contributing] | How to contribute |
| 📙 [GEMINI.md][gemini] | Gemini CLI setup & tips |
| 📕 [CLAUDE.md][claude] | Claude Code guide |

</div>

---

## 🗺️ Roadmap

```
╔════════════════════════════════════════════════════════════════════════╗
║                           acp.el Roadmap                               ║
╠════════════════════════════════════════════════════════════════════════╣
║                                                                        ║
║  🚧 v0.50 (Next Release)                                              ║
║  ├── 📊 Session persistence & history                                  ║
║  ├── 🔄 Multi-agent orchestration                                     ║
║  └── 📈 Usage analytics dashboard                                      ║
║                                                                        ║
║  📋 v0.60 (Planning)                                                  ║
║  ├── 🌐 Web search integration                                        ║
║  ├── 📁 Integrated file tree browser                                  ║
║  └── 🎨 Theme customization engine                                     ║
║                                                                        ║
║  🔮 Future Ideas                                                      ║
║  ├── 🤝 Agent-to-agent communication                                   ║
║  ├── 📱 Mobile companion app                                          ║
║  └── 🎮 TUI mode for terminal Emacs                                   ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝
```

---

## 🙏 Acknowledgments

<div align="center">

Built with ❤️ by **[NeoPilot AI][author]**

*Thanks to our amazing contributors!*

[![Contributors][contributors-badge]][contributors]

</div>

---

<div align="center">

### ⭐ Like acp.el?

**[Star this repository](https://github.com/neopilot-ai/acp.el/stargazers)** to show your support!

[Sponsor][sponsor] · [Report Bug][issues] · [Request Feature][issues]

*Made possible by the Emacs community*

</div>

<!-- omit in toc -->
## Links

[melpa]: https://melpa.org/#/acp
[docker]: https://github.com/neopilot-ai/acp.pkgs.container.github.com
[license]: https://www.gnu.org/licenses/gpl-3.0
[emacs]: https://www.gnu.org/software/emacs/
[stars]: https://github.com/neopilot-ai/acp.el/stargazers
[issues]: https://github.com/neopilot-ai/acp.el/issues
[author]: https://github.com/neopilot-ai
[sponsor]: https://github.com/sponsors/neopilot-ai
[contributors]: https://github.com/neopilot-ai/acp.el/graphs/contributors
[twitter]: https://twitter.com/neopilot_ai
[agents]: ./AGENTS.md
[contributing]: ./CONTRIBUTING.org
[gemini]: ./GEMINI.md
[claude]: ./CLAUDE.md

<!-- omit in toc -->
## Badges

[melpa-badge]: https://melpa.org/packages/acp-badge.svg
[docker-badge]: https://img.shields.io/badge/Docker-GHCR-2496ED?style=flat-square&logo=docker
[license-badge]: https://img.shields.io/badge/License-GPL%20v3-blue.svg
[emacs-badge]: https://img.shields.io/badge/Emacs-29.1+-7F5AB6.svg?style=flat-square&logo=gnu-emacs
[stars-badge]: https://img.shields.io/github/stars/neopilot-ai/acp.el?style=social&label=Stars
[issues-badge]: https://img.shields.io/github/issues/neopilot-ai/acp.el
[contributors-badge]: https://contrib.rocks/image?repo=neopilot-ai/acp.el&width=120
[twitter-badge]: https://img.shields.io/badge/Follow-@neopilot_ai-1DA1F2?style=flat-square&logo=twitter

;;; acp-github.el --- GitHub Copilot agent configurations -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI

;; Author: NeoPilot AI https://github.com/neopilot-ai
;; URL: https://github.com/neopilot-ai/acp.el

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file includes GitHub Copilot-specific configurations.
;;

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'shell-maker nil t)

(declare-function acp--indent-string "acp")
(declare-function acp-make-agent-config "acp")
(autoload 'acp-make-agent-config "acp")
(declare-function acp--make-acp-client "acp")
(declare-function acp--dwim "acp")

(defcustom acp-github-acp-command
  '("copilot" "--acp")
  "Command and parameters for the GitHub Copilot agent client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-github-default-model-id
  nil
  "Default GitHub Copilot model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-github-default-session-mode-id
  nil
  "Default GitHub Copilot session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-github-environment
  nil
  "Environment variables for the GitHub Copilot agent client.

This should be a list of environment variables to be used when
starting the GitHub Copilot agent process."
  :type '(repeat string)
  :group 'acp)

(defun acp-github-make-copilot-config ()
  "Create a GitHub Copilot agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'copilot
   :mode-line-name "Copilot"
   :buffer-name "Copilot"
   :shell-prompt "Copilot> "
   :shell-prompt-regexp "Copilot> "
   :icon-name "githubcopilot.png"
   :welcome-function #'acp-github--welcome-message
   :client-maker (lambda (buffer)
                   (acp-github-make-client :buffer buffer))
   :default-model-id (lambda () acp-github-default-model-id)
   :default-session-mode-id (lambda () acp-github-default-session-mode-id)
   :install-instructions "See https://github.com/github/copilot-cli for installation."))

(defun acp-github-start-copilot ()
  "Start an interactive GitHub Copilot agent shell."
  (interactive)
  (acp--dwim :config (acp-github-make-copilot-config)
                     :new-shell t))

(cl-defun acp-github-make-client (&key buffer)
  "Create a GitHub Copilot agent ACP client with BUFFER as context."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-github-command) acp-github-command)
    (user-error "Please migrate to use acp-github-acp-command and eval (setq acp-github-command nil)"))
  (acp--make-acp-client :command (car acp-github-acp-command)
                                :command-params (cdr acp-github-acp-command)
                                :environment-variables acp-github-environment
                                :context-buffer buffer))

(defun acp-github--welcome-message (config)
  "Return GitHub Copilot welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-github--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-github--ascii-art ()
  "GitHub Copilot ASCII art matching the official CLI banner."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
  █████┐ █████┐ █████┐ ██┐██┐     █████┐ ██████┐
 ██┌───┘██┌──██┐██┌─██┐██│██│    ██┌──██┐└─██┌─┘
 ██│    ██│  ██│█████┌┘██│██│    ██│  ██│  ██│
 ██│    ██│  ██│██┌──┘ ██│██│    ██│  ██│  ██│
 └█████┐└█████┌┘██│    ██│██████┐└█████┌┘  ██│
  └────┘ └────┘ └─┘    └─┘└─────┘ └────┘   └─┘
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#6e40c9" :inherit fixed-pitch)
                                       '(:foreground "#8250df" :inherit fixed-pitch)))))

(provide 'acp-github)

;;; acp-github.el ends here

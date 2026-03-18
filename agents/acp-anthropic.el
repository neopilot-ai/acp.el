;;; acp-anthropic.el --- Anthropic agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Anthropic-specific configurations.
;;

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'shell-maker nil t)

(declare-function acp--indent-string "acp")
(declare-function acp--make-acp-client "acp")
(declare-function acp-make-agent-config "acp")
(autoload 'acp-make-agent-config "acp")
(declare-function acp--dwim "acp")

(cl-defun acp-anthropic-make-authentication (&key api-key login oauth)
  "Create anthropic authentication configuration.

API-KEY is the Anthropic API key string or a function returning one.
LOGIN when non-nil indicates to use login-based authentication.
OAUTH is an OAuth token string or a function returning one.

Only one of API-KEY, LOGIN, or OAUTH should be provided, never more than one."
  (when (and api-key login)
    (error "Cannot specify both :api-key and :login - choose one"))
  (when (and oauth login)
    (error "Cannot specify both :oauth and :login - choose one"))
  (when (and api-key oauth)
    (error "Cannot specify both :api-key and :oauth - choose one"))
  (unless (or api-key login oauth)
    (error "Must specify either :api-key, :login, or :oauth"))
  (cond
   (oauth `((:oauth . ,oauth)))
   (api-key `((:api-key . ,api-key)))
   (login `((:login . t)))))

(defcustom acp-anthropic-authentication
  (acp-anthropic-make-authentication :login t)
  "Configuration for Anthropic authentication.
For subscription/login (default):

  (setq acp-anthropic-authentication
        (acp-anthropic-make-authentication :login t))

For api key:

  (setq acp-anthropic-authentication
        (acp-anthropic-make-authentication :api-key \"your-key\"))

  or

  (setq acp-anthropic-authentication
        (acp-anthropic-make-authentication :api-key (lambda () ... )))

For OAuth token:

  (setq acp-anthropic-authentication
        (acp-anthropic-make-authentication :oauth \"your-token\"))

  or

  (setq acp-anthropic-authentication
        (acp-anthropic-make-authentication :oauth (lambda () ... )))"
  :type 'alist
  :group 'acp)

(defcustom acp-anthropic-default-model-id
  nil
  "Default Anthropic model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new shell.

Can be set to either a string or a function that returns a string."
  :type '(choice (const nil) string function)
  :group 'acp)

(defcustom acp-anthropic-default-session-mode-id
  nil
  "Default Anthropic session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-anthropic-claude-acp-command
  '("claude-agent-acp")
  "Command and parameters for the Anthropic Claude client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-anthropic-claude-environment
  nil
  "Environment variables for the Anthropic Claude client.

This should be a list of environment variables to be used when
starting the Claude client process.

Example usage to set a custom Anthropic API base URL:

  (setq acp-anthropic-claude-environment
        (`acp-make-environment-variables'
         \"ANTHROPIC_BASE_URL\" \"https://api.moonshot.cn/anthropic/\"
         \"ANTHROPIC_MODEL\" \"moonshot-v1-auto\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-anthropic-make-claude-code-config ()
  "Create a Claude Agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'claude-code
   :mode-line-name "Claude Code"
   :buffer-name "Claude Code"
   :shell-prompt "Claude Code> "
   :shell-prompt-regexp "Claude Code> "
   :icon-name "anthropic.png"
   :welcome-function #'acp-anthropic--claude-code-welcome-message
   :client-maker (lambda (buffer)
                   (acp-anthropic-make-claude-client :buffer buffer))
   :default-model-id (lambda () (if (functionp acp-anthropic-default-model-id)
                                    (funcall acp-anthropic-default-model-id)
                                  acp-anthropic-default-model-id))
   :default-session-mode-id (lambda () acp-anthropic-default-session-mode-id)
   :install-instructions "See https://github.com/zed-industries/claude-agent-acp for installation."))

(defun acp-anthropic-start-claude-code ()
  "Start an interactive Claude Agent shell."
  (interactive)
  (acp--dwim :config (acp-anthropic-make-claude-code-config)
                     :new-shell t))

(cl-defun acp-anthropic-make-claude-client (&key buffer)
  "Create a Claude Code ACP client with BUFFER as context.

See `acp-anthropic-authentication' for authentication
and optionally `acp-anthropic-claude-environment' for
additional environment variables."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-anthropic-key) acp-anthropic-key)
    (user-error "Please migrate to use acp-anthropic-authentication and eval (setq acp-anthropic-key nil)"))
  (when (and (boundp 'acp-anthropic-claude-command) acp-anthropic-claude-command)
    (user-error "Please migrate to use acp-anthropic-claude-acp-command and eval (setq acp-anthropic-claude-command nil)"))
  (let ((env-vars-overrides (cond
                             ((map-elt acp-anthropic-authentication :api-key)
                              (list (format "ANTHROPIC_API_KEY=%s"
                                            (acp-anthropic-key))))
                             ((map-elt acp-anthropic-authentication :login)
                              (list "ANTHROPIC_API_KEY="))
                             ((map-elt acp-anthropic-authentication :oauth)
                              (list (format "CLAUDE_CODE_OAUTH_TOKEN=%s"
                                            (acp-anthropic-oauth-token))))
                             (t
                              (error "Invalid authentication configuration")))))
    (acp--make-acp-client :command (car acp-anthropic-claude-acp-command)
                                  :command-params (cdr acp-anthropic-claude-acp-command)
                                  :environment-variables (append env-vars-overrides
                                                                 acp-anthropic-claude-environment)
                                  :context-buffer buffer)))

(defun acp-anthropic-key ()
  "Get the Anthropic API key."
  (cond ((stringp (map-elt acp-anthropic-authentication :api-key))
         (map-elt acp-anthropic-authentication :api-key))
        ((functionp (map-elt acp-anthropic-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-anthropic-authentication :api-key))
           (error
            "Api key not found.  Check out `acp-anthropic-authentication'")))
        (t
         nil)))

(defun acp-anthropic-oauth-token ()
  "Get the Anthropic OAuth token."
  (cond ((stringp (map-elt acp-anthropic-authentication :oauth))
         (map-elt acp-anthropic-authentication :oauth))
        ((functionp (map-elt acp-anthropic-authentication :oauth))
         (condition-case _err
             (funcall (map-elt acp-anthropic-authentication :oauth))
           (error
            "OAuth token not found.  Check out `acp-anthropic-authentication'")))
        (t
         nil)))

(defun acp-anthropic--claude-code-welcome-message (config)
  "Return Claude Code ASCII art as per own repo using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-anthropic--claude-code-ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-anthropic--claude-code-ascii-art ()
  "Claude Code ASCII art.

Generated by https://github.com/shinshin86/oh-my-logo."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
  ██████╗ ██╗       █████╗  ██╗   ██╗ ██████╗  ███████╗
 ██╔════╝ ██║      ██╔══██╗ ██║   ██║ ██╔══██╗ ██╔════╝
 ██║      ██║      ███████║ ██║   ██║ ██║  ██║ █████╗
 ██║      ██║      ██╔══██║ ██║   ██║ ██║  ██║ ██╔══╝
 ╚██████╗ ███████╗ ██║  ██║ ╚██████╔╝ ██████╔╝ ███████╗
  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝  ╚═════╝  ╚═════╝  ╚══════╝
  ██████╗  ██████╗  ██████╗  ███████╗
 ██╔════╝ ██╔═══██╗ ██╔══██╗ ██╔════╝
 ██║      ██║   ██║ ██║  ██║ █████╗
 ██║      ██║   ██║ ██║  ██║ ██╔══╝
 ╚██████╗ ╚██████╔╝ ██████╔╝ ███████╗
  ╚═════╝  ╚═════╝  ╚═════╝  ╚══════╝
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#d26043" :inherit fixed-pitch)
                                       '(:foreground "#b8431f" :inherit fixed-pitch)))))

(provide 'acp-anthropic)

;;; acp-anthropic.el ends here

;;; acp-opencode.el --- OpenCode agent configurations -*- lexical-binding: t; -*-

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
;; This file includes OpenCode-specific configurations.
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

(cl-defun acp-opencode-make-authentication (&key api-key none)
  "Create OpenCode authentication configuration.

API-KEY is the OpenCode API key string or function that returns it.
NONE when non-nil disables API key authentication.

Only one of API-KEY or NONE should be provided, never both."
  (when (and api-key none)
    (error "Cannot specify both :api-key and :none - choose one"))
  (unless (or api-key none)
    (error "Must specify either :api-key or :none"))
  (cond
   (api-key `((:api-key . ,api-key)))
   (none `((:none . t)))))

(defcustom acp-opencode-authentication
  (acp-opencode-make-authentication :none t)
  "Configuration for OpenCode authentication.
For API key (string):

  (setq acp-opencode-authentication
        (acp-opencode-make-authentication :api-key \"your-key\"))

For API key (function):

  (setq acp-opencode-authentication
        (acp-opencode-make-authentication :api-key (lambda () ...)))

For no authentication (when using `opencode auth login`):

  (setq acp-opencode-authentication
        (acp-opencode-make-authentication :none t))"
  :type 'alist
  :group 'acp)

(defcustom acp-opencode-default-model-id
  nil
  "Default OpenCode model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-opencode-default-session-mode-id
  nil
  "Default OpenCode session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-opencode-acp-command
  '("opencode" "acp")
  "Command and parameters for the OpenCode client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-opencode-environment
  nil
  "Environment variables for the OpenCode client.

This should be a list of environment variables to be used when
starting the OpenCode client process.

Example usage to set custom environment variables:

  (setq acp-opencode-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-opencode-make-agent-config ()
  "Create an OpenCode agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'opencode
   :mode-line-name "OpenCode"
   :buffer-name "OpenCode"
   :shell-prompt "OpenCode> "
   :shell-prompt-regexp "OpenCode> "
   :welcome-function #'acp-opencode--welcome-message
   :client-maker (lambda (buffer)
                   (acp-opencode-make-client :buffer buffer))
   :default-model-id (lambda () acp-opencode-default-model-id)
   :default-session-mode-id (lambda () acp-opencode-default-session-mode-id)
   :install-instructions "See https://opencode.ai/docs for installation."))

(defun acp-opencode-start-agent ()
  "Start an interactive OpenCode agent shell."
  (interactive)
  (acp--dwim :config (acp-opencode-make-agent-config)
                     :new-shell t))

(cl-defun acp-opencode-make-client (&key buffer)
  "Create an OpenCode client using BUFFER as context.

Uses `acp-opencode-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-opencode-command) acp-opencode-command)
    (user-error "Please migrate to use acp-opencode-acp-command and eval (setq acp-opencode-command nil)"))
  (let ((api-key (acp-opencode-key)))
    (acp--make-acp-client :command (car acp-opencode-acp-command)
                                  :command-params (cdr acp-opencode-acp-command)
                                  :environment-variables (append (cond ((map-elt acp-opencode-authentication :none)
                                                                        nil)
                                                                       (api-key
                                                                        (list (format "OPENCODE_API_KEY=%s" api-key)))
                                                                       (t
                                                                        (error "Missing OpenCode authentication (see acp-opencode-authentication)")))
                                                                 acp-opencode-environment)
                                  :context-buffer buffer)))

(defun acp-opencode-key ()
  "Get the OpenCode API key."
  (cond ((stringp (map-elt acp-opencode-authentication :api-key))
         (map-elt acp-opencode-authentication :api-key))
        ((functionp (map-elt acp-opencode-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-opencode-authentication :api-key))
           (error
            (error "API key not found.  Check out `acp-opencode-authentication'"))))
        (t
         nil)))

(defun acp-opencode--welcome-message (config)
  "Return OpenCode welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-opencode--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-opencode--ascii-art ()
  "OpenCode ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
                                  ▄
 █▀▀█ █▀▀█ █▀▀█ █▀▀▄ █▀▀▀ █▀▀█ █▀▀█ █▀▀█
 █░░█ █░░█ █▀▀▀ █░░█ █░░░ █░░█ █░░█ █▀▀▀
 ▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀  ▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#4a9eff" :inherit fixed-pitch)
                                       '(:foreground "#2563eb" :inherit fixed-pitch)))))

(provide 'acp-opencode)

;;; acp-opencode.el ends here

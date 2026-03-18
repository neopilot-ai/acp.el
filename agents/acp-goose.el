;;; acp-goose.el --- Goose agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Goose-specific configurations.
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

(cl-defun acp-make-goose-authentication (&key openai-api-key none)
  "Create Goose authentication configuration.

OPENAI-API-KEY is the OpenAI API key string or function that returns it.
NONE when non-nil disables API key authentication.

Only one of OPENAI-API-KEY or NONE should be provided, never both."
  (when (and openai-api-key none)
    (error "Cannot specify both :openai-api-key and :none - choose one"))
  (unless (or openai-api-key none)
    (error "Must specify either :openai-api-key or :none"))
  (cond
   (openai-api-key `((:openai-api-key . ,openai-api-key)))
   (none `((:none . t)))))

(defcustom acp-goose-authentication nil
  "Configuration for Goose authentication.
For API key (string):

  (setq acp-goose-authentication
        (acp-make-goose-authentication :openai-api-key \"your-key\"))

For API key (function):

  (setq acp-goose-authentication
        (acp-make-goose-authentication :openai-api-key (lambda () ...)))

For no authentication (when using alternative authentication methods):

  (setq acp-goose-authentication
        (acp-make-goose-authentication :none t))"
  :type 'alist
  :group 'acp)

(defcustom acp-goose-acp-command
  '("goose" "acp")
  "Command and parameters for the Goose client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-goose-environment
  nil
  "Environment variables for the Goose client.

This should be a list of environment variables to be used when
starting the Goose client process.

Example usage to set custom environment variables:

  (setq acp-goose-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-goose-make-agent-config ()
  "Create a Goose agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'goose
   :mode-line-name "Goose"
   :buffer-name "Goose"
   :shell-prompt "Goose> "
   :shell-prompt-regexp "Goose> "
   :welcome-function #'acp-goose--welcome-message
   :icon-name "goose.png"
   :client-maker (lambda (buffer)
                   (acp-goose-make-client :buffer buffer))
   :install-instructions "See https://block.github.io/goose/docs/getting-started/installation."))

(defun acp-goose-start-agent ()
  "Start an interactive Goose agent shell."
  (interactive)
  (acp--dwim :config (acp-goose-make-agent-config)
                     :new-shell t))

(cl-defun acp-goose-make-client (&key buffer)
  "Create a Goose client using configured authentication with BUFFER as context.

Uses `acp-goose-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-goose-command) acp-goose-command)
    (user-error "Please migrate to use acp-goose-acp-command and eval (setq acp-goose-command nil)"))
  (let ((api-key (acp-goose-key)))
    (acp--make-acp-client :command (car acp-goose-acp-command)
                                  :command-params (cdr acp-goose-acp-command)
                                  :environment-variables (append (cond ((map-elt acp-goose-authentication :none)
                                                                        nil)
                                                                       (api-key
                                                                        (list (format "OPENAI_API_KEY=%s" api-key)))
                                                                       (t
                                                                        (error "Missing Goose authentication (see acp-goose-authentication)")))
                                                                 acp-goose-environment)
                                  :context-buffer buffer)))

(defun acp-goose-key ()
  "Get the Goose OpenAI API key."
  (cond ((stringp (map-elt acp-goose-authentication :openai-api-key))
         (map-elt acp-goose-authentication :openai-api-key))
        ((functionp (map-elt acp-goose-authentication :openai-api-key))
         (condition-case _err
             (funcall (map-elt acp-goose-authentication :openai-api-key))
           (error
            (error "OpenAI API key not found.  Check out `acp-goose-authentication'"))))
        (t
         nil)))

(defun acp-goose--welcome-message (config)
  "Return Goose welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-goose--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-goose--ascii-art ()
  "Goose ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮ ╭─────╮
│ ╭───╯ │ ╭─╮ │ │ ╭─╮ │ │ ╭───╯ │ ╭───╯
│ │     │ │ │ │ │ │ │ │ │ ╰───╮ │ ╰───╮
│ │ ╭─╮ │ │ │ │ │ │ │ │ ╰───╮ │ │ ╭───╯
│ ╰─╯ │ │ ╰─╯ │ │ ╰─╯ │ ╭───╯ │ │ ╰───╮
╰───╮ │ ╰─────╯ ╰─────╯ ╰─────╯ ╰─────╯
    ╰─╯" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#a0a0a0" :inherit fixed-pitch)
                                       '(:foreground "#505050" :inherit fixed-pitch)))))

(provide 'acp-goose)

;;; acp-goose.el ends here

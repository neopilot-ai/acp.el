;;; acp-mistral.el --- Mistral AI agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Mistral AI-specific configurations.
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

(cl-defun acp-mistral-make-authentication (&key api-key)
  "Create Mistral AI authentication configuration.

API-KEY is the Mistral AI API key string or function that returns it."
  (unless api-key
    (error "Must specify :api-key"))
  `((:api-key . ,api-key)))

(defcustom acp-mistral-authentication
  nil
  "Configuration for Mistral AI authentication.
For API key (string):

  (setq acp-mistral-authentication
        (acp-mistral-make-authentication :api-key \"your-key\"))

For API key (function):

  (setq acp-mistral-authentication
        (acp-mistral-make-authentication :api-key (lambda () ...)))"
  :type 'alist
  :group 'acp)

(defcustom acp-mistral-default-model-id
  nil
  "Default Mistral AI model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-mistral-default-session-mode-id
  nil
  "Default Mistral AI session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-mistral-acp-command
  '("vibe-acp")
  "Command and parameters for the Mistral Vibe client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-mistral-environment
  nil
  "Environment variables for the Mistral Vibe client.

This should be a list of environment variables to be used when
starting the Mistral Vibe client process.

Example usage to set custom environment variables:

  (setq acp-mistral-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-mistral-make-config ()
  "Create a Mistral Vibe agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'mistral-vibe
   :mode-line-name "Mistral Vibe"
   :buffer-name "Mistral Vibe"
   :shell-prompt "Vibe> "
   :shell-prompt-regexp "Vibe> "
   :icon-name "mistral.png"
   :welcome-function #'acp-mistral--welcome-message
   :client-maker (lambda (buffer)
                   (acp-mistral-make-client :buffer buffer))
   :default-model-id (lambda () acp-mistral-default-model-id)
   :default-session-mode-id (lambda () acp-mistral-default-session-mode-id)
   :install-instructions "See https://github.com/mistralai/vibe-acp for installation."))

(defun acp-mistral-start-vibe ()
  "Start an interactive Mistral Vibe agent shell."
  (interactive)
  (acp--dwim :config (acp-mistral-make-config)
                     :new-shell t))

(cl-defun acp-mistral-make-client (&key buffer)
  "Create a Mistral Vibe ACP client with BUFFER as context.

See `acp-mistral-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-mistral-command) acp-mistral-command)
    (user-error "Please migrate to use acp-mistral-acp-command and eval (setq acp-mistral-command nil)"))
  (unless acp-mistral-authentication
    (user-error "Please set `acp-mistral-authentication' with your API key"))
  (let ((api-key (acp-mistral-key)))
    (unless api-key
      (user-error "Please set your `acp-mistral-authentication'"))
    (acp--make-acp-client :command (car acp-mistral-acp-command)
                                  :command-params (cdr acp-mistral-acp-command)
                                  :environment-variables (append (list (format "MISTRAL_API_KEY=%s" api-key))
                                                                 acp-mistral-environment)
                                  :context-buffer buffer)))

(defun acp-mistral-key ()
  "Get the Mistral AI API key."
  (cond ((stringp (map-elt acp-mistral-authentication :api-key))
         (map-elt acp-mistral-authentication :api-key))
        ((functionp (map-elt acp-mistral-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-mistral-authentication :api-key))
           (error
            (error "API key not found.  Check out `acp-mistral-authentication'"))))
        (t
         nil)))

(defun acp-mistral--welcome-message (config)
  "Return Mistral Vibe welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-mistral--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-mistral--ascii-art ()
  "Mistral Vibe ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
 ███╗   ███╗ ██╗ ███████╗ ████████╗ ██████╗   █████╗  ██╗
 ████╗ ████║ ██║ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██║
 ██╔████╔██║ ██║ ███████╗    ██║    ██████╔╝ ███████║ ██║
 ██║╚██╔╝██║ ██║ ╚════██║    ██║    ██╔══██╗ ██╔══██║ ██║
 ██║ ╚═╝ ██║ ██║ ███████║    ██║    ██║  ██║ ██║  ██║ ███████╗
 ╚═╝     ╚═╝ ╚═╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚══════╝
 ██╗   ██╗ ██╗ ██████╗  ███████╗
 ██║   ██║ ██║ ██╔══██╗ ██╔════╝
 ██║   ██║ ██║ ██████╔╝ █████╗
 ╚██╗ ██╔╝ ██║ ██╔══██╗ ██╔══╝
  ╚████╔╝  ██║ ██████╔╝ ███████╗
   ╚═══╝   ╚═╝ ╚═════╝  ╚══════╝
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#ff7000" :inherit fixed-pitch)
                                       '(:foreground "#ff5500" :inherit fixed-pitch)))))

(provide 'acp-mistral)

;;; acp-mistral.el ends here

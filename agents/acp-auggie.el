;;; acp-auggie.el --- Auggie agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Auggie-specific configurations.
;;

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'shell-maker nil t)

(declare-function acp--indent-string "acp")
(declare-function acp-make-agent-config "acp")
(autoload 'acp-make-agent-config "acp")
(declare-function acp--make-acp-client "acp")
(declare-function acp-start "acp")

(cl-defun acp-make-auggie-authentication (&key login none)
  "Create Auggie authentication configuration.

LOGIN when non-nil indicates to use login-based authentication.
NONE when non-nil disables authentication (for local usage).

Only one of LOGIN or NONE should be provided, never both."
  (when (and login none)
    (error "Cannot specify both :login and :none - choose one"))
  (unless (or login none)
    (error "Must specify either :login or :none"))
  (cond
   (login `((:login . t)))
   (none `((:none . t)))))

(defcustom acp-auggie-authentication
  (acp-make-auggie-authentication :login t)
  "Configuration for Auggie authentication.
For login-based authentication (default):

  (setq acp-auggie-authentication
        (acp-make-auggie-authentication :login t))

For no authentication (when using alternative authentication methods):

  (setq acp-auggie-authentication
        (acp-make-auggie-authentication :none t))"
  :type '(choice
          (const :tag "Login authentication" ((:login . t)))
          (const :tag "No authentication" ((:none . t))))
  :group 'acp)
(defcustom acp-auggie-acp-command
  '("auggie" "--acp")
  "Command and parameters for the Auggie client.

The first element is the command name, and the rest are command parameters."
  :type '(cons (string :tag "Command")
               (repeat :tag "Arguments" string))
  :group 'acp)

(defcustom acp-auggie-environment
  nil
  "Environment variables for the Auggie client.

This should be a list of environment variables to be used when
starting the Auggie client process.

Example usage to set custom environment variables:

  (setq acp-auggie-environment
        (acp-make-environment-variables
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))\"
  :type '(repeat string)
  :group 'acp)

(defun acp-auggie-make-agent-config ()
  "Create an Auggie agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'auggie
   :mode-line-name "Auggie"
   :buffer-name "Auggie"
   :shell-prompt "Auggie> "
   :shell-prompt-regexp "Auggie> "
   :welcome-function #'acp-auggie--welcome-message
   :client-maker (lambda (buffer)
                   (acp-auggie-make-client :buffer buffer))
   :install-instructions "See https://docs.augmentcode.com/cli/overview for installation."))

(defun acp-auggie-start-agent ()
  "Start an interactive Auggie agent shell."
  (interactive)
  (acp-start
   :config (acp-auggie-make-agent-config)))

(cl-defun acp-auggie-make-client (&key buffer)
  "Create an Auggie client using configured authentication with BUFFER as context.

Uses `acp-auggie-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-auggie-command) acp-auggie-command)
    (user-error "Please migrate to use acp-auggie-acp-command and eval (setq acp-auggie-command nil)"))
  (acp--make-acp-client :command (car acp-auggie-acp-command)
                                :command-params (cdr acp-auggie-acp-command)
                                :environment-variables (cond ((map-elt acp-auggie-authentication :none)
                                                              acp-auggie-environment)
                                                             ((map-elt acp-auggie-authentication :login)
                                                              acp-auggie-environment)
                                                             (t
                                                              (error "Invalid Auggie authentication configuration")))
                                :context-buffer buffer))

(defun acp-auggie--welcome-message (config)
  "Return Auggie welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-auggie--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-auggie--ascii-art ()
  "Auggie ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
 █████╗ ██╗   ██╗ ██████╗  ██████╗ ██╗███████╗
██╔══██╗██║   ██║██╔════╝ ██╔════╝ ██║██╔════╝
███████║██║   ██║██║  ███╗██║  ███╗██║█████╗
██╔══██║██║   ██║██║   ██║██║   ██║██║██╔══╝
██║  ██║╚██████╔╝╚██████╔╝╚██████╔╝██║███████╗
╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝╚══════╝" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#3D855E")
                                       '(:foreground "#2D6B4A")))))

(provide 'acp-auggie)

;;; acp-auggie.el ends here

;;; acp-droid.el --- Factory Droid agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Factory Droid specific configurations relying on the
;; droid-acp client: https://github.com/yaonyan/droid-acp
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

(cl-defun acp-droid-make-authentication (&key api-key none)
  "Create Factory Droid authentication configuration.

API-KEY is the Droid API key string or function that returns it.
NONE when non-nil disables API key authentication (e.g., when droid-acp
is already logged in or uses an alternative auth flow).

Only one of API-KEY or NONE should be provided, never both."
  (when (and api-key none)
    (error "Cannot specify both :api-key and :none - choose one"))
  (unless (or api-key none)
    (error "Must specify either :api-key or :none"))
  (cond
   (api-key `((:api-key . ,api-key)))
   (none `((:none . t)))))

(defcustom acp-droid-authentication
  (acp-droid-make-authentication :none t)
  "Configuration for Factory Droid authentication.
For API key (string):

  (setq acp-droid-authentication
        (acp-droid-make-authentication :api-key \"your-key\"))

For API key (function):

  (setq acp-droid-authentication
        (acp-droid-make-authentication :api-key (lambda () ...)))

For no authentication (e.g., using `droid-acp` built-in login):

  (setq acp-droid-authentication
        (acp-droid-make-authentication :none t))"
  :type 'alist
  :group 'acp)

(defcustom acp-droid-acp-command
  '("droid-acp")
  "Command and parameters for the Factory Droid ACP client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-droid-environment
  nil
  "Environment variables for the Factory Droid ACP client.

This should be a list of environment variables to be used when
starting the Droid client process.

Example usage to set custom environment variables:

  (setq acp-droid-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-droid-make-agent-config ()
  "Create a Factory Droid agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'droid
   :mode-line-name "Droid"
   :buffer-name "Droid"
   :shell-prompt "Droid> "
   :shell-prompt-regexp "Droid> "
   :icon-name "https://avatars.githubusercontent.com/u/131064358"
   :welcome-function #'acp-droid--welcome-message
   :client-maker (lambda (buffer)
                   (acp-droid-make-client :buffer buffer))
   :install-instructions "See https://github.com/yaonyan/droid-acp for installation."))

(defun acp-droid-start-agent ()
  "Start an interactive Factory Droid agent shell."
  (interactive)
  (acp--dwim :config (acp-droid-make-agent-config)
                     :new-shell t))

(cl-defun acp-droid-make-client (&key buffer)
  "Create a Factory Droid client using BUFFER as context.

Uses `acp-droid-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-droid-command) acp-droid-command)
    (user-error "Please migrate to use acp-droid-acp-command and eval (setq acp-droid-command nil)"))
  (let ((api-key (acp-droid-key)))
    (acp--make-acp-client :command (car acp-droid-acp-command)
                                  :command-params (cdr acp-droid-acp-command)
                                  :environment-variables (append (cond ((map-elt acp-droid-authentication :none)
                                                                        nil)
                                                                       (api-key
                                                                        (list (format "FACTORY_API_KEY=%s" api-key)))
                                                                       (t
                                                                        (error "Missing Factory Droid authentication (see acp-droid-authentication)")))
                                                                 acp-droid-environment)
                                  :context-buffer buffer)))

(defun acp-droid-key ()
  "Get the Factory Droid API key."
  (cond ((stringp (map-elt acp-droid-authentication :api-key))
         (map-elt acp-droid-authentication :api-key))
        ((functionp (map-elt acp-droid-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-droid-authentication :api-key))
           (error
            (error "API key not found.  Check out `acp-droid-authentication'"))))
        (t
         nil)))

(defun acp-droid--welcome-message (config)
  "Return Factory Droid welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-droid--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-droid--ascii-art ()
  "Factory Droid ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
░░░░░░░░░    ░░░░░░░░░     ░░░░░░░░    ░░░   ░░░░░░░░░
░░░    ░░░   ░░░    ░░░   ░░░    ░░░   ░░░   ░░░    ░░░
░░░    ░░░   ░░░    ░░░   ░░░    ░░░   ░░░   ░░░    ░░░
░░░    ░░░   ░░░░░░░░░    ░░░    ░░░   ░░░   ░░░    ░░░
░░░    ░░░   ░░░    ░░░   ░░░    ░░░   ░░░   ░░░    ░░░
░░░    ░░░   ░░░    ░░░   ░░░    ░░░   ░░░   ░░░    ░░░
░░░░░░░░░    ░░░    ░░░    ░░░░░░░░    ░░░   ░░░░░░░░░
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#8b949e" :inherit fixed-pitch)
                                       '(:foreground "#444" :inherit fixed-pitch)))))

(provide 'acp-droid)

;;; acp-droid.el ends here

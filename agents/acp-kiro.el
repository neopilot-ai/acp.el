;;; acp-kiro.el --- Kiro agent configurations -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Zachary Jones

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
;; This file includes Kiro-specific configurations.
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

(defcustom acp-kiro-acp-command
  '("kiro-cli" "acp")
  "Command and parameters for the Kiro CLI client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-kiro-default-model-id
  nil
  "Default Kiro model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new shell.

Can be set to either a string or a function that returns a string."
  :type '(choice (const nil) string function)
  :group 'acp)

(defcustom acp-kiro-default-session-mode-id
  nil
  "Default Kiro session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defcustom acp-kiro-environment
  nil
  "Environment variables for the Kiro CLI client.

This should be a list of environment variables to be used when
starting the Kiro client process."
  :type '(repeat string)
  :group 'acp)

(defun acp-kiro-make-config ()
  "Create a Kiro agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (acp-make-agent-config
   :identifier 'kiro
   :mode-line-name "Kiro"
   :buffer-name "Kiro"
   :shell-prompt "Kiro> "
   :shell-prompt-regexp "Kiro> "
   :welcome-function #'acp-kiro--welcome-message
   :client-maker (lambda (buffer)
                   (acp-kiro-make-client :buffer buffer))
   :default-model-id (lambda () (if (functionp acp-kiro-default-model-id)
                                    (funcall acp-kiro-default-model-id)
                                  acp-kiro-default-model-id))
   :default-session-mode-id (lambda () acp-kiro-default-session-mode-id)
   :install-instructions "See https://kiro.dev/docs/cli/acp/ for installation."))

(defun acp-kiro-start-agent ()
  "Start an interactive Kiro agent shell."
  (interactive)
  (acp--dwim :config (acp-kiro-make-config)
                     :new-shell t))

(cl-defun acp-kiro-make-client (&key buffer)
  "Create a Kiro ACP client with BUFFER as context."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (acp--make-acp-client :command (car acp-kiro-acp-command)
                                :command-params (cdr acp-kiro-acp-command)
                                :environment-variables acp-kiro-environment
                                :context-buffer buffer))

(defun acp-kiro--welcome-message (config)
  "Return Kiro ASCII art using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-kiro--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-kiro--ascii-art ()
  "Kiro ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
 ██╗  ██╗ ██╗ ██████╗   ██████╗
 ██║ ██╔╝ ██║ ██╔══██╗ ██╔═══██╗
 █████╔╝  ██║ ██████╔╝ ██║   ██║
 ██╔═██╗  ██║ ██╔══██╗ ██║   ██║
 ██║  ██╗ ██║ ██║  ██║ ╚██████╔╝
 ╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝  ╚═════╝
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#FF6B35" :inherit fixed-pitch)
                                       '(:foreground "#E55934" :inherit fixed-pitch)))))

(provide 'acp-kiro)

;;; acp-kiro.el ends here

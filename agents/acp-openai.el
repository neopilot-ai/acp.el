;;; acp-openai.el --- OpenAI agent configurations -*- lexical-binding: t; -*-

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
;; This file includes OpenAI-specific configurations.
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

(cl-defun acp-openai-make-authentication (&key api-key codex-api-key login)
  "Create OpenAI authentication configuration.

API-KEY is the OpenAI API key string or function that returns it.
CODEX-API-KEY is the Codex-specific API key.
LOGIN when non-nil indicates to use login-based authentication."
  (when (> (seq-count #'identity (list api-key codex-api-key login)) 1)
    (error "Cannot specify multiple authentication methods - choose one"))
  (unless (> (seq-count #'identity (list api-key codex-api-key login)) 0)
    (error "Must specify one of :api-key, :codex-api-key, :login"))
  (cond
   (api-key `((:api-key . ,api-key)))
   (codex-api-key `((:codex-api-key . ,codex-api-key)))
   (login `((:login . t)))))

(defcustom acp-openai-authentication
  (acp-openai-make-authentication :login t)
  "Configuration for OpenAI authentication.
For login-based authentication (default):

  (setq acp-openai-authentication
        (acp-openai-make-authentication :login t))

For OpenAI API key (string):

  (setq acp-openai-authentication
        (acp-openai-make-authentication :api-key \"your-key\"))

For OpenAI API key (function):

  (setq acp-openai-authentication
        (acp-openai-make-authentication :api-key (lambda () ...)))

For Codex API key (string):

  (setq acp-openai-authentication
        (acp-openai-make-authentication :codex-api-key \"codex-key\"))

For Codex API key (function):

  (setq acp-openai-authentication
        (acp-openai-make-authentication :codex-api-key (lambda () ...)))"
  :type 'alist
  :group 'acp)

(defcustom acp-openai-codex-acp-command
  '("codex-acp")
  "Command and parameters for the OpenAI Codex client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-openai-codex-environment
  nil
  "Environment variables for the OpenAI Codex client.

This should be a list of environment variables to be used when
starting the Codex client process.

Example usage to set custom environment variables:

  (setq acp-openai-codex-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defcustom acp-openai-default-model-id
  nil
  "Default Codex model ID.

Must be one of the model ID's displayed under \"Available models\"
when starting a new Codex shell.

Can be set to either a string or a function that returns a string."
  :type '(choice (const nil) string function)
  :group 'acp)

(defcustom acp-openai-default-session-mode-id
  nil
  "Default Codex session mode ID.

Must be one of the mode ID's displayed under \"Available modes\"
when starting a new Codex shell."
  :type '(choice (const nil) string)
  :group 'acp)

(defun acp-openai-make-codex-config ()
  "Create a Codex agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (when (and (boundp 'acp-openai-key) acp-openai-key)
    (user-error "Please migrate to use acp-openai-authentication and eval (setq acp-openai-key nil)"))
  (acp-make-agent-config
   :identifier 'codex
   :mode-line-name "Codex"
   :buffer-name "Codex"
   :shell-prompt "Codex> "
   :shell-prompt-regexp "Codex> "
   :welcome-function #'acp-openai--codex-welcome-message
   :icon-name "openai.png"
   :needs-authentication t
   :default-model-id (lambda () (if (functionp acp-openai-default-model-id)
                                    (funcall acp-openai-default-model-id)
                                  acp-openai-default-model-id))
   :default-session-mode-id (lambda () acp-openai-default-session-mode-id)
   :authenticate-request-maker (lambda ()
                                 (cond ((map-elt acp-openai-authentication :api-key)
                                        (acp-make-authenticate-request :method-id "openai-api-key"))
                                       ((map-elt acp-openai-authentication :codex-api-key)
                                        (acp-make-authenticate-request :method-id "codex-api-key"))
                                       (t
                                        (acp-make-authenticate-request :method-id "chatgpt"))))
   :client-maker (lambda (buffer)
                   (acp-openai-make-codex-client :buffer buffer))
   :install-instructions "See https://github.com/zed-industries/codex-acp for installation."))

(defun acp-openai-start-codex ()
  "Start an interactive Codex agent shell."
  (interactive)
  (acp--dwim :config (acp-openai-make-codex-config)
                     :new-shell t))

(cl-defun acp-openai-make-codex-client (&key buffer)
  "Create a Codex client using configured authentication with BUFFER as context.

Uses `acp-openai-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-openai-codex-command) acp-openai-codex-command)
    (user-error "Please migrate to use acp-openai-codex-acp-command and eval (setq acp-openai-codex-command nil)"))
  (cond
   ((map-elt acp-openai-authentication :api-key)
    (let ((api-key (acp-openai-key)))
      (unless api-key
        (user-error "Please set your `acp-openai-authentication'"))
      (acp--make-acp-client :command (car acp-openai-codex-acp-command)
                                    :command-params (cdr acp-openai-codex-acp-command)
                                    :environment-variables (append (list (format "OPENAI_API_KEY=%s" api-key))
                                                                   acp-openai-codex-environment)
                                    :context-buffer buffer)))
   ((map-elt acp-openai-authentication :codex-api-key)
    (let ((codex-key (acp-openai-key)))
      (unless codex-key
        (user-error "Please set your `acp-openai-authentication'"))
      (acp--make-acp-client :command (car acp-openai-codex-acp-command)
                                    :command-params (cdr acp-openai-codex-acp-command)
                                    :environment-variables (append (list (format "CODEX_API_KEY=%s" codex-key))
                                                                   acp-openai-codex-environment)
                                    :context-buffer buffer)))
   ((map-elt acp-openai-authentication :login)
    (acp--make-acp-client :command (car acp-openai-codex-acp-command)
                                  :command-params (cdr acp-openai-codex-acp-command)
                                  :environment-variables (append '("OPENAI_API_KEY=")
                                                                 acp-openai-codex-environment)
                                  :context-buffer buffer))
   (t
    (error "Invalid authentication configuration"))))

(defun acp-openai--codex-welcome-message (config)
  "Return Codex welcome message using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-openai--codex-ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun acp-openai--codex-ascii-art ()
  "Codex ASCII art.

From https://github.com/openai/codex/blob/main/codex-rs/tui/frames/slug/frame_1.txt."
  (let* ((text (string-trim "
          d-dcottoottd
      dot5pot5tooeeod dgtd
    tepetppgde   egpegxoxeet
   cpdoppttd            5pecet
  odc5pdeoeoo            g-eoot
 xp te  ep5ceet           p-oeet
tdg-p    poep5ged          g e5e
eedee     t55ecep            gee
eoxpe    ceedoeg-xttttttdtt og e
 dxcp  dcte 5p egeddd-cttte5t5te
 oddgd dot-5e   edpppp dpg5tcd5
  pdt gt e              tp5pde
    doteotd          dodtedtg
      dptodgptccocc-optdtep
        epgpexxdddtdctpg
" "\n")))
    (propertize text 'font-lock-face 'font-lock-doc-face)))

(defun acp-openai-key ()
  "Get the OpenAI API key."
  (cond ((stringp (map-elt acp-openai-authentication :api-key))
         (map-elt acp-openai-authentication :api-key))
        ((functionp (map-elt acp-openai-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-openai-authentication :api-key))
           (error
            (error "Api key not found.  Check out `acp-openai-authentication'"))))
        ((stringp (map-elt acp-openai-authentication :codex-api-key))
         (map-elt acp-openai-authentication :codex-api-key))
        ((functionp (map-elt acp-openai-authentication :codex-api-key))
         (condition-case _err
             (funcall (map-elt acp-openai-authentication :codex-api-key))
           (error
            (error "Codex API key not found.  Check out `acp-openai-authentication'"))))
        (t
         nil)))

(provide 'acp-openai)

;;; acp-openai.el ends here

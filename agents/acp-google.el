;;; acp-google.el --- Google agent configurations -*- lexical-binding: t; -*-

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
;; This file includes Google-specific configurations.
;;

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'shell-maker nil t)

(declare-function acp--indent-string "acp")
(declare-function acp--interpolate-gradient "acp")
(declare-function acp--make-acp-client "acp")
(declare-function acp-make-agent-config "acp")
(autoload 'acp-make-agent-config "acp")
(declare-function acp--dwim "acp")

(cl-defun acp-google-make-authentication (&key api-key login vertex-ai none)
  "Create Google authentication configuration.

API-KEY is the Google API key string or function that returns it.
LOGIN when non-nil indicates to use login-based authentication.
VERTEX-AI when non-nil indicates to use Vertex AI authentication.
NONE when non-nil indicates no authentication method is used.

Only one of API-KEY, LOGIN, VERTEX-AI, or NONE should be provided."
  (when (> (seq-count #'identity (list api-key login vertex-ai)) 1)
    (error "Cannot specify multiple authentication methods - choose one"))
  (unless (> (seq-count #'identity (list api-key login vertex-ai none)) 0)
    (error "Must specify one of :api-key, :login, or :vertex-ai"))
  (cond
   (api-key `((:api-key . ,api-key)))
   (login `((:login . t)))
   (vertex-ai `((:vertex-ai . t)))
   (none `((:none . t)))))

(defcustom acp-google-authentication
  (acp-google-make-authentication :login t)
  "Configuration for Google authentication.

For login-based authentication (default):

  (setq acp-google-authentication
        (acp-google-make-authentication :login t))

For API key (string):

  (setq acp-google-authentication
        (acp-google-make-authentication :api-key \"your-key\"))

For API key (function):

  (setq acp-google-authentication
        (acp-google-make-authentication :api-key (lambda () ...)))

For Vertex AI authentication:

  (setq acp-google-authentication
        (acp-google-make-authentication :vertex-ai t))

For no authentication (when using alternative authentication methods):

  (setq acp-google-authentication
        (acp-google-make-authentication :none t))"
  :type 'alist
  :group 'acp)

(defcustom acp-google-gemini-acp-command
  '("gemini" "--experimental-acp")
  "Command and parameters for the Gemini client.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-google-gemini-environment
  nil
  "Environment variables for the Google Gemini client.

This should be a list of environment variables to be used when
starting the Gemini client process.

Example usage to set custom environment variables:

  (setq acp-google-gemini-environment
        (`acp-make-environment-variables'
         \"MY_VAR\" \"some-value\"
         \"MY_OTHER_VAR\" \"another-value\"))"
  :type '(repeat string)
  :group 'acp)

(defun acp-google-make-gemini-config ()
  "Create a Gemini CLI agent configuration.

Returns an agent configuration alist using `acp-make-agent-config'."
  (when (and (boundp 'acp-google-key) acp-google-key)
    (user-error "Please migrate to use acp-google-authentication and eval (setq acp-google-key nil)"))
  (acp-make-agent-config
   :identifier 'gemini-cli
   :mode-line-name "Gemini CLI"
   :buffer-name "Gemini CLI"
   :shell-prompt "Gemini> "
   :shell-prompt-regexp "Gemini> "
   :icon-name "gemini.png"
   :welcome-function #'acp-google--gemini-welcome-message
   :needs-authentication (not (map-elt acp-google-authentication :none))
   :authenticate-request-maker (lambda ()
                                 (cond ((map-elt acp-google-authentication :api-key)
                                        ;; TODO: Save authentication methods from
                                        ;; initialization and resolve :method-id
                                        ;; to :method which came from the agent.
                                        (acp-make-authenticate-request
                                         :method-id "gemini-api-key"
                                         :method '((id . "gemini-api-key")
                                                   (name . "Use Gemini API key")
                                                   (description . "Requires setting the `GEMINI_API_KEY` environment variable"))))
                                       ((map-elt acp-google-authentication :vertex-ai)
                                        ;; TODO: Save authentication methods from
                                        ;; initialization and resolve :method-id
                                        ;; to :method which came from the agent.
                                        (acp-make-authenticate-request
                                         :method-id "vertex-ai"
                                         :method '((id . "vertex-ai")
                                                   (name . "Vertex AI")
                                                   (description . ""))))
                                       ((map-elt acp-google-authentication :none)
                                        nil)
                                       (t
                                        ;; TODO: Save authentication methods from
                                        ;; initialization and resolve :method-id
                                        ;; to :method which came from the agent.
                                        (acp-make-authenticate-request
                                         :method-id "oauth-personal"
                                         :method '((id . "oauth-personal")
                                                   (name . "Log in with Google")
                                                   (description . ""))))))
   :client-maker (lambda (buffer)
                   (acp-google-make-gemini-client :buffer buffer))
   :install-instructions "See https://github.com/google-gemini/gemini-cli for installation."))

(defun acp-google-start-gemini ()
  "Start an interactive Gemini CLI agent shell."
  (interactive)
  (acp--dwim :config (acp-google-make-gemini-config)
                     :new-shell t))

(cl-defun acp-google-make-gemini-client (&key buffer)
  "Create a Gemini client using configured authentication with BUFFER as context.

Uses `acp-google-authentication' for authentication configuration."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (when (and (boundp 'acp-google-key) acp-google-key)
    (user-error "Please migrate to use acp-google-authentication and eval (setq acp-google-key nil)"))
  (when (and (boundp 'acp-google-gemini-command) acp-google-gemini-command)
    (user-error "Please migrate to use acp-google-gemini-acp-command and eval (setq acp-google-gemini-command nil)"))
  (cond
   ((map-elt acp-google-authentication :api-key)
    (acp--make-acp-client :command (car acp-google-gemini-acp-command)
                                  :command-params (cdr acp-google-gemini-acp-command)
                                  :environment-variables (append (when-let ((api-key (acp-google-key)))
                                                                   (list (format "GEMINI_API_KEY=%s" api-key)))
                                                                 acp-google-gemini-environment)
                                  :context-buffer buffer))
   ((map-elt acp-google-authentication :login)
    (acp--make-acp-client :command (car acp-google-gemini-acp-command)
                                  :command-params (cdr acp-google-gemini-acp-command)
                                  :environment-variables acp-google-gemini-environment
                                  :context-buffer buffer))
   ((map-elt acp-google-authentication :vertex-ai)
    (acp--make-acp-client :command (car acp-google-gemini-acp-command)
                                  :command-params (cdr acp-google-gemini-acp-command)
                                  :environment-variables acp-google-gemini-environment
                                  :context-buffer buffer))
   ((map-elt acp-google-authentication :none)
    (acp--make-acp-client :command (car acp-google-gemini-acp-command)
                                  :command-params (cdr acp-google-gemini-acp-command)
                                  :environment-variables acp-google-gemini-environment
                                  :context-buffer buffer))
   (t
    (error "Invalid authentication configuration"))))

(defun acp-google--gemini-welcome-message (config)
  "Return Gemini CLI ASCII art as per own repo using `shell-maker' CONFIG."
  (let ((art (acp--indent-string 4 (acp-google--gemini-ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n\n"
            art
            "\n\n"
            message)))

(defun acp-google--gemini-ascii-art ()
  "Generate Gemini CLI ASCII art, inspired by its codebase."
  ;; Based on:
  ;; https://github.com/google-gemini/gemini-cli/tree/main/packages/cli/src/ui/components/Header.tsx
  ;; https://github.com/google-gemini/gemini-cli/tree/main/packages/cli/src/ui/components/AsciiArt.ts
  ;; https://github.com/google-gemini/gemini-cli/tree/main/packages/cli/src/ui/themes/theme.ts
  (let* ((text (string-trim "
 ███            █████████  ██████████ ██████   ██████ █████ ██████   █████ █████
░░░███         ███░░░░░███░░███░░░░░█░░██████ ██████ ░░███ ░░██████ ░░███ ░░███
  ░░░███      ███     ░░░  ░███  █ ░  ░███░█████░███  ░███  ░███░███ ░███  ░███
    ░░░███   ░███          ░██████    ░███░░███ ░███  ░███  ░███░░███░███  ░███
     ███░    ░███    █████ ░███░░█    ░███ ░░░  ░███  ░███  ░███ ░░██████  ░███
   ███░      ░░███  ░░███  ░███ ░   █ ░███      ░███  ░███  ░███  ░░█████  ░███
 ███░         ░░█████████  ██████████ █████     █████ █████ █████  ░░█████ █████
░░░            ░░░░░░░░░  ░░░░░░░░░░ ░░░░░     ░░░░░ ░░░░░ ░░░░░    ░░░░░ ░░░░░" "\n"))
         (is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (gradient-colors (if is-dark
                              '("#4796E4" "#847ACE" "#C3677F")
                            '("#3B82F6" "#8B5CF6" "#DD4C4C")))
         (lines (split-string text "\n"))
         (result ""))
    (dolist (line lines)
      (let ((line-length (length line))
            (propertized-line ""))
        (dotimes (i line-length)
          (let* ((char (substring line i (1+ i)))
                 (progress (/ (float i) line-length))
                 (color (acp--interpolate-gradient gradient-colors progress)))
            (setq propertized-line
                  (concat propertized-line
                          (propertize char 'font-lock-face `(:foreground ,color :inherit fixed-pitch))))))
        (setq result (concat result propertized-line "\n"))))
    (string-trim-right result)))

(defun acp-google--gemini-text ()
  "Colorized Gemini text with Google-branded colors."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (colors (if is-dark
                     '("#4796E4" "#6B82D9" "#847ACE" "#9E6FA8" "#B16C93" "#C3677F")
                   '("#3B82F6" "#5F6CF6" "#8B5CF6" "#A757D0" "#C354A0" "#DD4C4C")))
         (text "Gemini")
         (result ""))
    (dotimes (i (length text))
      (setq result (concat result
                           (propertize (substring text i (1+ i))
                                       'font-lock-face `(:foreground ,(nth (mod i (length colors)) colors) :inherit fixed-pitch)))))
    result))

(defun acp-google-key ()
  "Get the Google API key."
  (cond ((stringp (map-elt acp-google-authentication :api-key))
         (map-elt acp-google-authentication :api-key))
        ((functionp (map-elt acp-google-authentication :api-key))
         (condition-case _err
             (funcall (map-elt acp-google-authentication :api-key))
           (error
            "Api key not found.  Check out `acp-google-authentication'")))
        (t
         nil)))

(provide 'acp-google)

;;; acp-google.el ends here

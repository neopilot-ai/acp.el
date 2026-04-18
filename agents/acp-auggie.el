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

(require 'map)
(require 'subr-x)
(require 'shell-maker nil t)

;; External declarations
(declare-function acp--indent-string "acp")
(declare-function acp-make-agent-config "acp")
(declare-function acp--make-acp-client "acp")
(declare-function acp-start "acp")

(autoload 'acp-make-agent-config "acp")

;; ------------------------------------------------------------------
;; Authentication
;; ------------------------------------------------------------------

(cl-defun acp-make-auggie-authentication (&key login none)
  "Create Auggie authentication configuration.

LOGIN enables login auth.
NONE disables authentication (local/dev use)."
  (cond
   ((and login none)
    (error "Cannot use both :login and :none"))
   (login '(:login t))
   (none '(:none t))
   (t
    (error "Must specify either :login or :none"))))

(defcustom acp-auggie-authentication
  (acp-make-auggie-authentication :login t)
  "Auggie authentication configuration."
  :type '(choice
          (const :tag "Login authentication" (:login t))
          (const :tag "No authentication" (:none t)))
  :group 'acp)

;; ------------------------------------------------------------------
;; Command + Environment
;; ------------------------------------------------------------------

(defcustom acp-auggie-acp-command
  '("auggie" "--acp")
  "Command used to start Auggie ACP client."
  :type '(cons string (repeat string))
  :group 'acp)

(defcustom acp-auggie-environment
  nil
  "Environment variables for Auggie process."
  :type '(repeat string)
  :group 'acp)

;; ------------------------------------------------------------------
;; Agent Config
;; ------------------------------------------------------------------

(defun acp-auggie-make-agent-config ()
  "Return Auggie agent configuration."
  (acp-make-agent-config
   :identifier 'auggie
   :mode-line-name "Auggie"
   :buffer-name "Auggie"
   :shell-prompt "Auggie> "
   :shell-prompt-regexp "Auggie> "
   :welcome-function #'acp-auggie--welcome-message
   :client-maker #'acp-auggie-make-client
   :install-instructions
   "https://docs.augmentcode.com/cli/overview"))

(defun acp-auggie-start-agent ()
  "Start Auggie agent."
  (interactive)
  (acp-start :config (acp-auggie-make-agent-config)))

;; ------------------------------------------------------------------
;; Client
;; ------------------------------------------------------------------

(cl-defun acp-auggie-make-client (&key buffer)
  "Create Auggie client using BUFFER."
  (unless buffer
    (error "Missing required argument: :buffer"))

  ;; Migration guard
  (when (and (boundp 'acp-auggie-command)
             acp-auggie-command)
    (user-error "Deprecated: use acp-auggie-acp-command instead"))

  (let ((auth acp-auggie-authentication))
    (acp--make-acp-client
     :command (car acp-auggie-acp-command)
     :command-params (cdr acp-auggie-acp-command)
     :environment-variables
     (cond
      ((plist-get auth :none)
       acp-auggie-environment)
      ((plist-get auth :login)
       acp-auggie-environment)
      (t
       (error "Invalid authentication config")))
     :context-buffer buffer)))

;; ------------------------------------------------------------------
;; UI / Welcome
;; ------------------------------------------------------------------

(defun acp-auggie--welcome-message (config)
  "Return welcome message."
  (let ((art (acp--indent-string 4 (acp-auggie--ascii-art)))
        (msg (string-trim-left
              (shell-maker-welcome-message config)
              "\n")))
    (concat "\n\n" art "\n\n" msg)))

(defun acp-auggie--ascii-art ()
  "Return Auggie ASCII art."
  (let* ((dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text
          (string-trim
           "
 █████╗ ██╗   ██╗ ██████╗  ██████╗ ██╗███████╗
██╔══██╗██║   ██║██╔════╝ ██╔════╝ ██║██╔════╝
███████║██║   ██║██║  ███╗██║  ███╗██║█████╗
██╔══██║██║   ██║██║   ██║██║   ██║██║██╔══╝
██║  ██║╚██████╔╝╚██████╔╝╚██████╔╝██║███████╗
╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝╚══════╝
"))
         (color (if dark "#3D855E" "#2D6B4A")))
    (propertize text 'face `(:foreground ,color))))

;; ------------------------------------------------------------------

(provide 'acp-auggie)

;;; acp-auggie.el ends here

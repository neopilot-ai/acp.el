;;; acp-permissions.el --- Permission management for acp -*- lexical-binding: t; -*-

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
;; Fine-grained permission management for agent file access and command
;; execution.  Provides a central permission manager that is consulted
;; before MCP actions, with per-session and per-agent policies.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'map)

;;;; Customization

(defgroup acp-permissions nil
  "Permission management for acp."
  :group 'acp)

(defcustom acp-permissions-default-policy 'prompt
  "Default permission policy for unspecified actions.
`allow'  - allow all actions without prompting.
`deny'   - deny all actions without prompting.
`prompt' - prompt the user for each action."
  :type '(choice (const :tag "Allow all" allow)
                 (const :tag "Deny all" deny)
                 (const :tag "Prompt" prompt))
  :group 'acp-permissions)

(defcustom acp-permissions-file-write-policy 'prompt
  "Policy for file write actions.
`allow' - allow all writes.
`deny'  - deny all writes.
`prompt' - prompt the user."
  :type '(choice (const :tag "Allow" allow)
                 (const :tag "Deny" deny)
                 (const :tag "Prompt" prompt))
  :group 'acp-permissions)

(defcustom acp-permissions-file-read-policy 'allow
  "Policy for file read actions.
`allow' - allow all reads.
`deny'  - deny all reads.
`prompt' - prompt the user."
  :type '(choice (const :tag "Allow" allow)
                 (const :tag "Deny" deny)
                 (const :tag "Prompt" prompt))
  :group 'acp-permissions)

(defcustom acp-permissions-command-execution-policy 'prompt
  "Policy for command execution actions.
`allow' - allow all commands.
`deny'  - deny all commands.
`prompt' - prompt the user."
  :type '(choice (const :tag "Allow" allow)
                 (const :tag "Deny" deny)
                 (const :tag "Prompt" prompt))
  :group 'acp-permissions)

(defcustom acp-permissions-allowed-paths nil
  "List of file path prefixes that are always allowed.
Paths are matched as prefixes.  Example: (\"~/projects/\")."
  :type '(repeat directory)
  :group 'acp-permissions)

(defcustom acp-permissions-denied-paths nil
  "List of file path prefixes that are always denied.
Paths are matched as prefixes.  Takes precedence over allowed-paths."
  :type '(repeat directory)
  :group 'acp-permissions)

(defcustom acp-permissions-audit-log t
  "Whether to log permission decisions to a file.
When non-nil, decisions are logged to <project>/.acp/permissions-audit.log."
  :type 'boolean
  :group 'acp-permissions)

;;;; Permission Record

(cl-defun acp-permissions--make-record (&key action target agent session-id decision timestamp reason)
  "Create a permission audit record.
ACTION is the action type (file-read, file-write, command-exec).
TARGET is the target path or command string.
AGENT is the agent identifier.
SESSION-ID is the session identifier.
DECISION is allow, deny, or prompt.
TIMESTAMP is when the decision was made.
REASON is a human-readable reason for the decision."
  (list :action action
        :target target
        :agent agent
        :session-id session-id
        :decision decision
        :timestamp timestamp
        :reason reason))

;;;; Audit Log

(defun acp-permissions--audit-directory ()
  "Return the audit log directory."
  (let ((dir (if (fboundp 'acp--dot-subdir)
                 (acp--dot-subdir "")
               (expand-file-name ".acp" default-directory))))
    (unless (file-directory-p dir)
      (make-directory dir t))
    dir))

(defun acp-permissions--audit-log-file ()
  "Return the path to the audit log file."
  (expand-file-name "permissions-audit.log"
                     (acp-permissions--audit-directory)))

(defun acp-permissions--audit-log (record)
  "Write RECORD to the audit log file."
  (when acp-permissions-audit-log
    (let ((file (acp-permissions--audit-log-file))
          (coding-system-for-write 'utf-8))
      (with-temp-buffer
        (let ((entry (format "[%s] %s %s -> %s (agent: %s, session: %s)%s\n"
                             (format-time-string "%Y-%m-%d %H:%M:%S")
                             (plist-get record :action)
                             (plist-get record :target)
                             (plist-get record :decision)
                             (or (plist-get record :agent) "?")
                             (or (plist-get record :session-id) "?")
                             (if-let ((reason (plist-get record :reason)))
                                 (format " - %s" reason)
                               ""))))
          (if (file-exists-p file)
              (append-to-file entry nil file)
            (write-region entry nil file)))))))

;;;; Path Matching

(defun acp-permissions--path-allowed-p (path)
  "Return non-nil if PATH matches any allowed path prefix."
  (cl-some (lambda (prefix)
             (string-prefix-p prefix path))
           acp-permissions-allowed-paths))

(defun acp-permissions--path-denied-p (path)
  "Return non-nil if PATH matches any denied path prefix."
  (cl-some (lambda (prefix)
             (string-prefix-p prefix path))
           acp-permissions-denied-paths))

;;;; Policy Evaluation

(defun acp-permissions--evaluate-policy (policy action target &optional agent session-id)
  "Evaluate PERMISSION for ACTION on TARGET.
POLICY is the permission policy symbol.
Returns 'allow, 'deny, or 'prompt."
  (pcase policy
    ('allow 'allow)
    ('deny 'deny)
    ('prompt
     (let ((answer (acp-permissions--prompt-user action target agent session-id)))
       answer))))

(defun acp-permissions--prompt-user (action target agent session-id)
  "Prompt the user for permission for ACTION on TARGET.
Returns 'allow or 'deny."
  (let* ((action-desc (pcase action
                        ('file-read "Read file")
                        ('file-write "Write file")
                        ('command-exec "Execute command")
                        (_ (format "Access %s" action))))
         (prompt (format "%s: %s%s"
                         action-desc
                         target
                         (if agent
                             (format " (agent: %s)" agent)
                           "")))
         (answer (y-or-n-p prompt)))
    (if answer 'allow 'deny)))

;;;; Permission Check API

;;;###autoload
(defun acp-permissions-check (action target &optional agent session-id)
  "Check whether ACTION on TARGET is permitted.
AGENT and SESSION-ID are used for audit logging.
Returns 'allow or 'deny.  May prompt the user depending on policy."
  (let* ((policy (pcase action
                   ('file-read acp-permissions-file-read-policy)
                   ('file-write acp-permissions-file-write-policy)
                   ('command-exec acp-permissions-command-execution-policy)
                   (_ acp-permissions-default-policy)))
         (decision
          (cond
           ;; Check denied paths first (highest priority)
           ((and (eq action 'file-read)
                 (acp-permissions--path-denied-p target))
            'deny)
           ((and (eq action 'file-write)
                 (acp-permissions--path-denied-p target))
            'deny)
           ;; Check allowed paths
           ((and (eq action 'file-read)
                 (acp-permissions--path-allowed-p target))
            'allow)
           ((and (eq action 'file-write)
                 (acp-permissions--path-allowed-p target))
            'allow)
           ;; Evaluate policy
           (t (acp-permissions--evaluate-policy policy action target agent session-id)))))
    ;; Audit log
    (acp-permissions--audit-log
     (acp-permissions--make-record
      :action action
      :target target
      :agent agent
      :session-id session-id
      :decision decision
      :timestamp (current-time)
      :reason (cond
               ((acp-permissions--path-denied-p target) "denied-path")
               ((acp-permissions--path-allowed-p target) "allowed-path")
               (t "policy"))))
    decision))

;;;###autoload
(defun acp-permissions-check-file-read (path &optional agent session-id)
  "Check if reading PATH is permitted."
  (acp-permissions-check 'file-read path agent session-id))

;;;###autoload
(defun acp-permissions-check-file-write (path &optional agent session-id)
  "Check if writing PATH is permitted."
  (acp-permissions-check 'file-write path agent session-id))

;;;###autoload
(defun acp-permissions-check-command (command &optional agent session-id)
  "Check if executing COMMAND is permitted."
  (acp-permissions-check 'command-exec command agent session-id))

;;;; Audit Log Viewer

;;;###autoload
(defun acp-permissions-view-audit-log ()
  "Display the permission audit log in a buffer."
  (interactive)
  (let ((file (acp-permissions--audit-log-file)))
    (if (file-exists-p file)
        (with-current-buffer (get-buffer-create "*acp-permissions-audit*")
          (erase-buffer)
          (insert-file-contents file)
          (goto-char (point-min))
          (special-mode)
          (current-buffer))
      (message "No audit log found"))))

;;;###autoload
(defun acp-permissions-clear-audit-log ()
  "Clear the permission audit log."
  (interactive)
  (let ((file (acp-permissions--audit-log-file)))
    (when (file-exists-p file)
      (delete-file file)
      (message "Audit log cleared"))))

(provide 'acp-permissions)

;;; acp-permissions.el ends here

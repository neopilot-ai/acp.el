;;; acp-session-store.el --- Session persistence for acp -*- lexical-binding: t; -*-

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
;; Provides session persistence for acp.el.  Sessions can be saved to disk
;; and restored across Emacs restarts.  Sessions are stored as Emacs Lisp
;; data files under <project-root>/.acp/sessions/.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'map)
(require 'json)

(defvar acp--state)

(declare-function acp--state "acp")
(declare-function acp--dot-subdir "acp")

;;;; Customization

(defgroup acp-session-store nil
  "Session persistence for acp."
  :group 'acp)

(defcustom acp-session-store-directory nil
  "Directory for storing session files.
When nil, defaults to <project-root>/.acp/sessions/."
  :type '(choice (const :tag "Default (<project>/.acp/sessions/)" nil)
                 (directory :tag "Custom directory"))
  :group 'acp-session-store)

(defcustom acp-session-store-max-sessions 50
  "Maximum number of sessions to keep on disk.
Older sessions beyond this limit are pruned on save."
  :type 'integer
  :group 'acp-session-store)

(defcustom acp-session-store-format 'elisp
  "Format for persisting session data.
`elisp' uses pr1-to-string for native Emacs data.
`json' uses json-serialize for cross-tool compatibility."
  :type '(choice (const :tag "Emacs Lisp (elisp)" elisp)
                 (const :tag "JSON" json))
  :group 'acp-session-store)

;;;; Session Data Structure

(cl-defun acp-session-store--make-session (&key id agent model timestamp tags transcript-path state-snapshot)
  "Create a session record for persistence.
ID is a unique session identifier.
AGENT is the agent name (e.g. \"anthropic\", \"openai\").
MODEL is the model identifier.
TIMESTAMP is the creation time (emacs time value).
TAGS is a list of user-defined string tags.
TRANSCRIPT-PATH is the path to the transcript file.
STATE-SNAPSHOT is a plist of state fields to persist."
  (list :id id
        :agent agent
        :model model
        :timestamp timestamp
        :tags (or tags '())
        :transcript-path transcript-path
        :state-snapshot (or state-snapshot '())))

(defun acp-session-store--session-id (session)
  "Return the ID of SESSION."
  (plist-get session :id))

(defun acp-session-store--session-agent (session)
  "Return the agent of SESSION."
  (plist-get session :agent))

(defun acp-session-store--session-timestamp (session)
  "Return the timestamp of SESSION."
  (plist-get session :timestamp))

(defun acp-session-store--session-tags (session)
  "Return the tags of SESSION."
  (plist-get session :tags))

;;;; Directory Management

(defun acp-session-store--directory ()
  "Return the session store directory, creating it if necessary."
  (let ((dir (or acp-session-store-directory
                 (when (fboundp 'acp--dot-subdir)
                   (acp--dot-subdir "sessions"))
                 (expand-file-name "sessions"
                                   (or (and (fboundp 'projectile-project-root)
                                            (projectile-project-root))
                                       (and (fboundp 'project-current-project-toplevel)
                                            (when-let ((proj (project-current-project-toplevel)))
                                              (project-root proj)))
                                       default-directory)))))
    (unless (file-directory-p dir)
      (make-directory dir t))
    dir))

(defun acp-session-store--session-file (session-id)
  "Return the file path for SESSION-ID."
  (expand-file-name (format "%s%s" session-id
                            (if (eq acp-session-store-format 'json) ".json" ".el"))
                    (acp-session-store--directory)))

;;;; Serialization

(defun acp-session-store--serialize (session)
  "Serialize SESSION to a string."
  (pcase acp-session-store-format
    ('elisp (prin1-to-string session))
    ('json (json-encode session))))

(defun acp-session-store--deserialize (string)
  "Deserialize STRING to a session record."
  (pcase acp-session-store-format
    ('elisp (read string))
    ('json (json-read-from-string string))))

;;;; State Snapshot

(defun acp-session-store--snapshot-state ()
  "Capture a snapshot of the current session state for persistence.
Returns a plist of serializable state fields."
  (when (boundp 'acp--state)
    (let ((state (acp--state)))
      (list :session-id (map-nested-elt state '(:session :id))
            :agent-config-id (when-let ((cfg (map-elt state :agent-config)))
                               (map-elt cfg :identifier))
            :request-count (map-elt state :request-count)
            :usage (map-elt state :usage)))))

;;;; Save / Load

;;;###autoload
(defun acp-session-store-save (&optional session-id)
  "Save the current session to disk.
SESSION-ID defaults to the current session ID from acp--state.
Returns the path to the saved file."
  (interactive)
  (let* ((id (or session-id
                 (when (boundp 'acp--state)
                   (map-nested-elt (acp--state) '(:session :id)))
                 (error "No active session")))
         (snapshot (acp-session-store--snapshot-state))
         (session (acp-session-store--make-session
                   :id id
                   :agent (plist-get snapshot :agent-config-id)
                   :model nil
                   :timestamp (current-time)
                   :tags nil
                   :transcript-path (when (boundp 'acp--transcript-file)
                                      acp--transcript-file)
                   :state-snapshot snapshot))
         (file (acp-session-store--session-file id))
         (coding-system-for-write 'utf-8))
    (with-temp-file file
      (insert (acp-session-store--serialize session))
      (insert "\n"))
    (message "Session saved: %s" file)
    file))

;;;###autoload
(defun acp-session-store-load (session-id)
  "Load a session from disk by SESSION-ID.
Returns the deserialized session record."
  (interactive
   (list (completing-read "Load session: "
                          (acp-session-store--list-sessions)
                          nil t)))
  (let* ((file (acp-session-store--session-file session-id))
         (session (unless (file-exists-p file)
                    (error "Session file not found: %s" file))
                  (with-temp-buffer
                    (insert-file-contents file)
                    (acp-session-store--deserialize
                     (buffer-string)))))
    (message "Session loaded: %s" session-id)
    session))

;;;; Session Listing and Search

(defun acp-session-store--list-sessions ()
  "Return a list of all session IDs on disk."
  (let ((dir (acp-session-store--directory))
        (ext (if (eq acp-session-store-format 'json) ".json" ".el")))
    (when (file-directory-p dir)
      (sort
       (mapcar #'file-name-sans-extension
               (directory-files dir nil (concat "\\`[^.].*" (regexp-quote ext) "\\'")))
       #'string>))))

;;;###autoload
(defun acp-session-store-list ()
  "Display a list of saved sessions in a buffer."
  (interactive)
  (let ((sessions (acp-session-store--list-sessions)))
    (if (null sessions)
        (message "No saved sessions")
      (with-current-buffer (get-buffer-create "*acp-sessions*")
        (erase-buffer)
        (insert "Saved Sessions\n")
        (insert (make-string 40 ?=) "\n\n")
        (dolist (id sessions)
          (let* ((file (acp-session-store--session-file id))
                 (session (when (file-exists-p file)
                            (with-temp-buffer
                              (insert-file-contents file)
                              (acp-session-store--deserialize
                               (buffer-string))))))
            (when session
              (insert (format "  %s\n" id))
              (insert (format "    Agent:  %s\n" (or (acp-session-store--session-agent session) "?")))
              (insert (format "    Time:   %s\n"
                              (if (acp-session-store--session-timestamp session)
                                  (format-time-string "%Y-%m-%d %H:%M:%S"
                                                      (acp-session-store--session-timestamp session))
                                "?")))
              (let ((tags (acp-session-store--session-tags session)))
                (when tags
                  (insert (format "    Tags:   %s\n" (string-join tags ", ")))))
              (insert "\n"))))
        (goto-char (point-min))
        (special-mode)
        (current-buffer)))))

;;;###autoload
(defun acp-session-store-search (query)
  "Search saved sessions matching QUERY.
QUERY is matched against session IDs and tags."
  (interactive "sSearch sessions: ")
  (let ((results (acp-session-store--search-sessions query)))
    (if (null results)
        (message "No sessions matching: %s" query)
      (with-current-buffer (get-buffer-create "*acp-sessions*")
        (erase-buffer)
        (insert (format "Sessions matching: %s\n" query))
        (insert (make-string 40 ?=) "\n\n")
        (dolist (id results)
          (insert (format "  %s\n" id)))
        (goto-char (point-min))
        (special-mode)
        (current-buffer)))))

(defun acp-session-store--search-sessions (query)
  "Return session IDs matching QUERY."
  (let ((all (acp-session-store--list-sessions))
        (case-fold-search t))
    (delq nil
          (mapcar
           (lambda (id)
             (when (string-match-p (regexp-quote query) id)
               id))
           all))))

;;;###autoload
(defun acp-session-store-tag (session-id tag)
  "Add TAG to SESSION-ID."
  (interactive
   (list (completing-read "Session: " (acp-session-store--list-sessions) nil t)
         (read-string "Tag: ")))
  (let* ((file (acp-session-store--session-file session-id))
         (session (when (file-exists-p file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (acp-session-store--deserialize
                       (buffer-string))))))
    (unless session
      (error "Session not found: %s" session-id))
    (let* ((tags (plist-get session :tags))
           (new-tags (if (member tag tags) tags (append tags (list tag)))))
      (plist-put session :tags new-tags)
      (let ((coding-system-for-write 'utf-8))
        (with-temp-file file
          (insert (acp-session-store--serialize session))
          (insert "\n")))
      (message "Tagged session %s: %s" session-id new-tags))))

;;;; Pruning

(defun acp-session-store--prune ()
  "Remove oldest sessions beyond `acp-session-store-max-sessions'."
  (let ((ids (acp-session-store--list-sessions)))
    (when (> (length ids) acp-session-store-max-sessions)
      (let ((to-remove (nthcdr acp-session-store-max-sessions (sort ids #'string<))))
        (dolist (id to-remove)
          (let ((file (acp-session-store--session-file id)))
            (when (file-exists-p file)
              (delete-file file))))))))

(provide 'acp-session-store)

;;; acp-session-store.el ends here

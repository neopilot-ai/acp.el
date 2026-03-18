;;; acp-diff.el --- A quick way to query/display a diff. -*- lexical-binding: t; -*-

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
;; Report issues at https://github.com/neopilot-ai/acp.el/issues
;;
;; ✨ Please support this work https://github.com/sponsors/neopilot-ai ✨

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'diff)
(require 'diff-mode)

(defvar-local acp-on-exit nil
  "Function to call when the diff buffer is killed.

This variable is automatically set by :on-exit from `acp-diff'
and can be temporarily let-bound to nil to prevent the
on-exit callback from running when the buffer is killed.")

(defvar-local acp-diff--file nil
  "Buffer-local file path associated with the diff.")

(defvar-local acp-diff--accept-all-command nil
  "Buffer-local command to accept all changes in the diff.")

(defvar-local acp-diff--reject-all-command nil
  "Buffer-local command to reject all changes in the diff.")

(defvar acp-diff-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'diff-hunk-next)
    (define-key map (kbd "p") #'diff-hunk-prev)
    (define-key map (kbd "y") #'acp-diff-accept-all)
    (define-key map (kbd "C-c C-c") #'acp-diff-reject-all)
    (define-key map (kbd "f") #'acp-diff-open-file)
    (define-key map (kbd "q") #'kill-current-buffer)
    map)
  "Keymap for `acp-diff-mode'.")

(define-derived-mode acp-diff-mode diff-mode "Agent-Shell-Diff"
  "Major mode for `acp' diff buffers.
Derives from `diff-mode'.  Provides `acp-diff-accept-all'
and `acp-diff-reject-all' commands that can be rebound
via `acp-diff-mode-map'."
  :group 'acp
  ;; Don't inherit diff-mode-map (some bindings can be destructive).
  (set-keymap-parent acp-diff-mode-map nil)
  (setq buffer-read-only t))

(defun acp-diff-kill-buffer (buffer)
  "Kill diff BUFFER, suppressing any `acp-on-exit' callback.
If BUFFER is not live, do nothing."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq acp-on-exit nil))
    (kill-buffer buffer)))

(defun acp-diff-accept-all ()
  "Accept all changes in the current diff buffer."
  (interactive)
  (if acp-diff--accept-all-command
      (funcall acp-diff--accept-all-command)
    (user-error "No accept command available in this buffer")))

(defun acp-diff-reject-all ()
  "Reject all changes in the current diff buffer."
  (interactive)
  (if acp-diff--reject-all-command
      (funcall acp-diff--reject-all-command)
    (user-error "No reject command available in this buffer")))

(cl-defun acp-diff (&key old new on-exit on-accept on-reject title file)
  "Display a diff between OLD and NEW strings in a buffer.

Creates a new buffer showing the differences between OLD and NEW
using `acp-diff-mode'.  The buffer is read-only.

When the buffer is killed, calls ON-EXIT with no arguments.

Returns the newly created diff buffer.

Arguments:
  :OLD       - Original string content
  :NEW       - Modified string content
  :ON-EXIT   - Function called with no arguments when buffer is killed
  :ON-ACCEPT - Command to accept all changes
  :ON-REJECT - Command to reject all changes
  :TITLE     - Optional title to display in header line
  :FILE      - File path"
  (let* ((diff-buffer (generate-new-buffer "*acp-diff*"))
         (calling-window (selected-window))
         (calling-buffer (current-buffer))
         (interrupt-key (where-is-internal 'acp-interrupt
                                           (current-local-map) t)))
    (unwind-protect
        (progn
          (with-current-buffer diff-buffer
            (let ((inhibit-read-only t)
                  (diff-mode-read-only nil))
              (erase-buffer)
              ;; Set mode before inserting diff so diff-no-select
              ;; doesn't reset font-lock (see #316).
              (acp-diff-mode)
              (acp-diff--insert-diff old new file diff-buffer)
              ;; Add overlays to hide scary text.
              (save-excursion
                (goto-char (point-min))
                ;; Remove command added by diff-no-select
                (delete-region (point) (progn (forward-line 1) (point)))
                ;; Remove "Diff finished." added by diff-no-select
                (delete-region (progn (goto-char (point-max)) (forward-line -1) (forward-line 0) (point))
                               (point-max))
                (goto-char (point-min))
                ;; Hide --- and +++ lines
                (while (re-search-forward "^\\(---\\|\\+\\+\\+\\).*\n" nil t)
                  (let ((overlay (make-overlay (match-beginning 0) (match-end 0))))
                    (overlay-put overlay 'category 'diff-header)
                    (overlay-put overlay 'display "")
                    (overlay-put overlay 'evaporate t)))
                ;; Replace @@ lines with "Changes"
                (goto-char (point-min))
                (while (re-search-forward "^@@.*@@.*\n" nil t)
                  (let ((overlay (make-overlay (match-beginning 0) (match-end 0)))
                        (face 'diff-hunk-header))  ; or any face you prefer
                    (overlay-put overlay 'category 'diff-header)
                    ;; Intended display is:
                    ;; ╭─────────╮
                    ;; │ changes │
                    ;; ╰─────────╯
                    ;; Using before-string so diff-hunk-next
                    ;; lands on "│" instead of "╭".
                    (overlay-put overlay 'before-string
                                 (propertize "\n╭─────────╮\n" 'face face))
                    (overlay-put overlay 'display
                                 (propertize "│ changes │\n╰─────────╯\n\n" 'face face))
                    (overlay-put overlay 'evaporate t)))))
            (goto-char (point-min))
            (ignore-errors (diff-hunk-next))
            (setq acp-diff--file file
                  acp-diff--accept-all-command on-accept
                  acp-diff--reject-all-command on-reject)
            (when on-exit
              (setq acp-on-exit on-exit)
              (add-hook 'kill-buffer-hook
                        (lambda ()
                          (when (and acp-on-exit
                                     (buffer-live-p calling-buffer))
                            (with-current-buffer calling-buffer
                              (funcall on-exit))
                            ;; Give focus back to calling buffer.
                            (ignore-errors
                              (if (window-live-p calling-window)
                                  (if (eq (window-buffer calling-window) calling-buffer)
                                      (select-window calling-window)
                                    (set-window-buffer calling-window calling-buffer)
                                    (select-window calling-window))))))
                        nil t))
            (let ((map (copy-keymap acp-diff-mode-map)))
              (when (and interrupt-key
                         (not (lookup-key map interrupt-key)))
                (define-key map interrupt-key #'acp-diff-reject-all))
              (use-local-map map))
            (setq header-line-format
                  (substitute-command-keys
                   (concat
                    "  "
                    (when title
                      (concat (propertize title 'face 'mode-line-emphasis) " "))
                    "\\[diff-hunk-next] next hunk  "
                    "\\[diff-hunk-prev] previous hunk  "
                    "\\[acp-diff-accept-all] accept  "
                    "\\[acp-diff-reject-all] reject  "
                    "\\[acp-diff-open-file] open  "
                    "\\[kill-current-buffer] quit"))))
          diff-buffer)
      (pop-to-buffer diff-buffer '((display-buffer-use-some-window
                                    display-buffer-same-window))))))

(defun acp-diff-open-file ()
  "Open the file associated with the current diff buffer."
  (interactive)
  (if acp-diff--file
      (find-file acp-diff--file)
    (user-error "No file associated with this diff buffer")))

(defun acp-diff--insert-diff (old new file buf)
  "Insert diff from FILE between OLD and NEW strings in buffer BUF."
  (let* ((suffix (format ".%s" (file-name-extension file)))
         (old-file (make-temp-file "old" nil suffix))
         (new-file (make-temp-file "new" nil suffix)))
    (with-temp-file old-file (insert old))
    (with-temp-file new-file (insert new))
    (diff-no-select old-file new-file "-U3" t buf)))

(provide 'acp-diff)

;;; acp-diff.el ends here

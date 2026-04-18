;;; acp-completion.el --- Completion support for acp. -*- lexical-binding: t; -*-

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

(require 'map)
(require 'acp-project)

(declare-function acp--shell-buffer "acp")
(declare-function acp--project-files "acp-project")

(defvar acp--state)

(defcustom acp-file-completion-enabled t
  "Non-nil automatically enables file completion when starting shells."
  :type 'boolean
  :group 'acp)

(defun acp--completion-bounds (char-class trigger-char)
  "Find completion bounds for CHAR-CLASS, if TRIGGER-CHAR precedes them.
Returns alist with :start and :end if TRIGGER-CHAR is found before
the word, nil otherwise."
  (save-excursion
    (when-let* ((end (progn (skip-chars-forward char-class) (point)))
                (start (progn (skip-chars-backward char-class) (point)))
                ((eq (char-before start) trigger-char)))
      `((:start . ,start) (:end . ,end)))))

(defun acp--capf-exit-with-space (_string _status)
  "Insert space after completion."
  (insert " "))

(defun acp--file-completion-at-point ()
  "Complete project files after @."
  (when-let* ((bounds (acp--completion-bounds "[:alnum:]/_.-" ?@))
              (files (acp--project-files)))
    (list (map-elt bounds :start) (map-elt bounds :end)
          files
          :exclusive 'no
          :company-kind (lambda (f) (if (string-suffix-p "/" f) 'folder 'file))
          :exit-function #'acp--capf-exit-with-space)))

(defun acp--command-completion-at-point ()
  "Complete available commands after /."
  (when-let* ((bounds (acp--completion-bounds "[:alnum:]_-" ?/))
              (commands (with-current-buffer (acp--shell-buffer
                                              :no-error t :no-create t)
                          (map-elt acp--state :available-commands)))
              (descriptions (mapcar (lambda (c)
                                      (cons (map-elt c 'name)
                                            (map-elt c 'description)))
                                    commands)))
    (list (map-elt bounds :start) (map-elt bounds :end)
          (mapcar #'car descriptions)
          :exclusive t
          :annotation-function
          (lambda (name)
            (when-let* ((desc (map-elt descriptions name)))
              (concat "  " desc)))
          :company-kind (lambda (_) 'function)
          :exit-function #'acp--capf-exit-with-space)))

(defun acp--trigger-completion-at-point ()
  "Trigger completion when @ or / is typed at a word boundary.
Only triggers when the character is at line start or after whitespace,
preventing spurious completions mid-word or in paths."
  (when (and (memq (char-before) '(?@ ?/))
             (or (= (point) (1+ (line-beginning-position)))
                 (memq (char-before (1- (point))) '(?\s ?\t ?\n))))
    (cond
     ((eq (char-before) ?@)
      (completion-at-point))
     ((and (eq (char-before) ?/)
           (acp--command-completion-at-point))
      (completion-at-point)))))

(define-minor-mode acp-completion-mode
  "Toggle agent shell completion with @ or / prefix."
  :lighter " @/Compl"
  (if acp-completion-mode
      (progn
        (add-hook 'completion-at-point-functions #'acp--file-completion-at-point nil t)
        (add-hook 'completion-at-point-functions #'acp--command-completion-at-point nil t)
        (add-hook 'post-self-insert-hook #'acp--trigger-completion-at-point nil t))
    (remove-hook 'completion-at-point-functions #'acp--file-completion-at-point t)
    (remove-hook 'completion-at-point-functions #'acp--command-completion-at-point t)
    (remove-hook 'post-self-insert-hook #'acp--trigger-completion-at-point t)))

(provide 'acp-completion)

;;; acp-completion.el ends here

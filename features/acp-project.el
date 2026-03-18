;;; acp-project.el --- Project file utilities for acp. -*- lexical-binding: t; -*-

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

(require 'project)
(require 'subr-x)

(defvar projectile-mode)

(declare-function projectile-project-p "projectile")
(declare-function projectile-project-root "projectile")
(declare-function projectile-project-name "projectile")
(declare-function projectile-current-project-files "projectile")

(defun acp--project-files ()
  "Get project files using projectile or project.el."
  (cond
   ((and (boundp 'projectile-mode)
         projectile-mode
         (projectile-project-p))
    (let ((root (file-name-as-directory (expand-file-name (projectile-project-root)))))
      (mapcar (lambda (f)
                (string-remove-prefix root f))
              (projectile-current-project-files))))
   ((fboundp 'project-current)
    (when-let* ((proj (project-current))
                (root (file-name-as-directory (expand-file-name (project-root proj)))))
      (mapcar (lambda (f)
                (string-remove-prefix root f))
              (project-files proj))))
   (t nil)))

(defcustom acp-cwd-function nil
  "When non-nil, a function called to determine the shell's CWD.

The function receives no arguments and should return a directory path.

When nil (the default), `acp-cwd' uses project root detection."
  :type '(choice (const :tag "Default (project root)" nil)
                 (function :tag "Custom function"))
  :group 'acp)

(defun acp-cwd ()
  "Return the CWD for this shell.

If `acp-cwd-function' is set, use it.
Otherwise, if in a project, use project root."
  (expand-file-name
   (or (when acp-cwd-function
         (funcall acp-cwd-function))
       (when (and (boundp 'projectile-mode)
                  projectile-mode
                  (fboundp 'projectile-project-root))
         (projectile-project-root))
       (when (fboundp 'project-root)
         (when-let ((proj (project-current)))
           (project-root proj)))
       default-directory
       (error "No CWD available"))))

(defun acp--project-name ()
  "Return the project name for this shell.

If in a project, use project name."
  (or (when-let (((boundp 'projectile-mode))
                 projectile-mode
                 ((fboundp 'projectile-project-name))
                 (root (projectile-project-root)))
        (projectile-project-name root))
      (when-let (((fboundp 'project-name))
                 (project (project-current)))
        (project-name project))
      (file-name-nondirectory
       (string-remove-suffix "/" default-directory))))

(provide 'acp-project)

;;; acp-project.el ends here

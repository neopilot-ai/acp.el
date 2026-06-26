;;; acp-file-tree.el --- File tree browser for acp -*- lexical-binding: t; -*-

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
;; Integrated file tree browser for acp sessions.  Provides a side panel
;; showing the project file tree with context actions for sending file
;; paths to the agent session.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'map)

;;;; Customization

(defgroup acp-file-tree nil
  "File tree browser for acp."
  :group 'acp)

(defcustom acp-file-tree-side 'left
  "Which side to display the file tree panel."
  :type '(choice (const :tag "Left" left)
                 (const :tag "Right" right))
  :group 'acp-file-tree)

(defcustom acp-file-tree-width 30
  "Width of the file tree panel in columns."
  :type 'integer
  :group 'acp-file-tree)

(defcustom acp-file-tree-ignored-directories
  '(".git" ".svn" ".hg" "node_modules" "__pycache__" ".DS_Store"
    "elpa" ".straight" "eln-cache" ".cache" ".acp")
  "Directories to hide from the file tree."
  :type '(repeat string)
  :group 'acp-file-tree)

(defcustom acp-file-tree-ignored-files
  '("*.elc" "*.pyc" "*.o" "*.class" "*.o" "*.so" "*.dylib"
    "*~" "#*#" ".DS_Store")
  "File patterns to hide from the file tree."
  :type '(repeat string)
  :group 'acp-file-tree)

;;;; Internal State

(defvar acp-file-tree--buffer nil
  "The file tree buffer.")

(defvar acp-file-tree--root nil
  "Root directory of the current file tree.")

(defvar acp-file-tree--expanded-dirs nil
  "List of expanded directory paths.")

;;;; Tree Node Structure

(cl-defun acp-file-tree--make-node (&key name path type children expanded)
  "Create a file tree node.
NAME is the display name.
PATH is the full file system path.
TYPE is 'dir or 'file.
CHILDREN is a list of child nodes (for directories).
EXPANDED is non-nil if the directory is expanded."
  (list :name name
        :path path
        :type type
        :children (or children '())
        :expanded expanded))

(defun acp-file-tree--node-name (node) (plist-get node :name))
(defun acp-file-tree--node-path (node) (plist-get node :path))
(defun acp-file-tree--node-type (node) (plist-get node :type))
(defun acp-file-tree--node-children (node) (plist-get node :children))
(defun acp-file-tree--node-expanded (node) (plist-get node :expanded))

;;;; Tree Building

(defun acp-file-tree--ignored-p (name)
  "Return non-nil if NAME should be ignored."
  (or (member name acp-file-tree-ignored-directories)
      (cl-some (lambda (pat)
                 (string-match-p (wildcard-to-regexp pat) name))
               acp-file-tree-ignored-files)))

(defun acp-file-tree--build-tree (dir &optional depth)
  "Build a file tree node for DIR.
DEPTH limits recursion depth (default 3)."
  (let ((max-depth (or depth 3)))
    (when (>= max-depth 0)
      (let* ((name (file-name-nondirectory (directory-file-name dir)))
             (entries (condition-case nil
                         (directory-files dir nil nil t)
                       (error nil)))
             (children
              (when entries
                (let ((dirs nil)
                      (files nil))
                  (dolist (entry entries)
                    (unless (or (string-prefix-p "." entry)
                                (acp-file-tree--ignored-p entry))
                      (let ((full (expand-file-name entry dir)))
                        (if (file-directory-p full)
                            (push (acp-file-tree--build-tree full (1- max-depth)) dirs)
                          (push (acp-file-tree--make-node
                                 :name entry :path full :type 'file)
                                files)))))
                  (append (sort dirs (lambda (a b)
                                       (string< (acp-file-tree--node-name a)
                                                (acp-file-tree--node-name b))))
                          (sort files (lambda (a b)
                                        (string< (acp-file-tree--node-name a)
                                                 (acp-file-tree--node-name b)))))))))
        (acp-file-tree--make-node
         :name (or (and (not (string= name ""))
                        name)
                   dir)
         :path dir
         :type 'dir
         :children children
         :expanded (member dir acp-file-tree--expanded-dirs))))))

;;;; Rendering

(defun acp-file-tree--render-node (node &optional indent)
  "Render NODE to the current buffer with INDENT level."
  (let ((indent-str (make-string (* (or indent 0) 2) ? ))
        (name (acp-file-tree--node-name node))
        (type (acp-file-tree--node-type node))
        (expanded (acp-file-tree--node-expanded node)))
    (cond
     ((eq type 'dir)
      (let ((icon (if expanded "[-] " "[+] ")))
        (insert (format "%s%s%s\n" indent-str icon name))
        (when expanded
          (dolist (child (acp-file-tree--node-children node))
            (acp-file-tree--render-node child (1+ (or indent 0)))))))
     (t
      (insert (format "%s  %s\n" indent-str name))))))

(defun acp-file-tree--render ()
  "Render the file tree in the current buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (when acp-file-tree--root
      (let ((tree (acp-file-tree--build-tree acp-file-tree--root)))
        (acp-file-tree--render-node tree)))))

;;;; Navigation and Interaction

(defun acp-file-tree--node-at-point ()
  "Return the file tree node at point."
  (let ((line (buffer-substring-no-properties
               (line-beginning-position)
               (line-end-position))))
    (when (string-match "^\\([ \t]*\\)\\(?:\\[[-+]\\]\\|  \\)\\(.+\\)$" line)
      (let ((indent-level (/ (length (match-string 1 line)) 2))
            (name (string-trim (match-string 2 line))))
        (acp-file-tree--find-node acp-file-tree--root name indent-level)))))

(defun acp-file-tree--find-node (node target-name target-indent &optional current-indent)
  "Find a node in the tree matching TARGET-NAME at TARGET-INDENT."
  (let ((current-indent (or current-indent 0)))
    (when (and (string= (acp-file-tree--node-name node) target-name)
               (= current-indent target-indent))
      node)
    (when (and (acp-file-tree--node-expanded node)
               (>= target-indent (1+ current-indent)))
      (cl-some (lambda (child)
                 (acp-file-tree--find-node child target-name target-indent
                                           (1+ current-indent)))
               (acp-file-tree--node-children node)))))

(defun acp-file-tree-toggle ()
  "Toggle expansion of the directory at point."
  (interactive)
  (let ((node (acp-file-tree--node-at-point)))
    (when (and node (eq (acp-file-tree--node-type node) 'dir))
      (let ((path (acp-file-tree--node-path node)))
        (if (member path acp-file-tree--expanded-dirs)
            (setq acp-file-tree--expanded-dirs
                  (delete path acp-file-tree--expanded-dirs))
          (push path acp-file-tree--expanded-dirs))
        (acp-file-tree--render)))))

(defun acp-file-tree-send-path ()
  "Send the file path at point to the current acp session."
  (interactive)
  (let ((node (acp-file-tree--node-at-point)))
    (when node
      (let ((path (acp-file-tree--node-path node)))
        (if (eq (acp-file-tree--node-type node) 'dir)
            (message "Directory: %s" path)
          (message "File: %s" path))))))

(defun acp-file-tree-open-file ()
  "Open the file at point."
  (interactive)
  (let ((node (acp-file-tree--node-at-point)))
    (when (and node (eq (acp-file-tree--node-type node) 'file))
      (find-file (acp-file-tree--node-path node)))))

;;;; Keymap

(defvar acp-file-tree-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'acp-file-tree-toggle)
    (define-key map (kbd "SPC") #'acp-file-tree-send-path)
    (define-key map (kbd "o") #'acp-file-tree-open-file)
    (define-key map (kbd "g") (lambda () (interactive) (acp-file-tree--render)))
    (define-key map (kbd "q") (lambda () (interactive) (acp-file-tree-close)))
    map)
  "Keymap for `acp-file-tree-mode'.")

;;;; Major Mode

(define-derived-mode acp-file-tree-mode special-mode "ACP-FileTree"
  "Major mode for browsing the project file tree."
  :group 'acp-file-tree
  (setq-local buffer-read-only t)
  (setq-local truncate-lines t))

;;;; Panel Management

;;;###autoload
(defun acp-file-tree-open (&optional root)
  "Open the file tree panel.
ROOT defaults to the project root or `default-directory'."
  (interactive)
  (setq acp-file-tree--root
        (or root
            (and (fboundp 'projectile-project-root)
                 (projectile-project-root))
            (and (fboundp 'project-current-project-toplevel)
                 (when-let ((proj (project-current-project-toplevel)))
                   (project-root proj)))
            default-directory))
  (setq acp-file-tree--expanded-dirs
        (list acp-file-tree--root))
  (let ((buf (get-buffer-create "*acp-file-tree*")))
    (with-current-buffer buf
      (acp-file-tree-mode)
      (acp-file-tree--render))
    (setq acp-file-tree--buffer buf)
    (display-buffer-in-side-window buf `((side . ,acp-file-tree-side)
                                         (window-width . ,acp-file-tree-width)))))

;;;###autoload
(defun acp-file-tree-close ()
  "Close the file tree panel."
  (interactive)
  (when (and acp-file-tree--buffer
             (buffer-live-p acp-file-tree--buffer))
    (let ((win (get-buffer-window acp-file-tree--buffer)))
      (when win
        (delete-window win)))
    (kill-buffer acp-file-tree--buffer))
  (setq acp-file-tree--buffer nil))

;;;###autoload
(defun acp-file-tree-refresh ()
  "Refresh the file tree panel."
  (interactive)
  (when (and acp-file-tree--buffer
             (buffer-live-p acp-file-tree--buffer))
    (with-current-buffer acp-file-tree--buffer
      (acp-file-tree--render))))

(provide 'acp-file-tree)

;;; acp-file-tree.el ends here

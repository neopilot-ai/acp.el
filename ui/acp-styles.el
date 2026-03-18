;;; acp-styles.el --- Alternative status/kind label styles. -*- lexical-binding: t; -*-

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
;; Alternative functions for `acp-status-kind-label-function'.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues
;;
;; ✨ Please support this work https://github.com/sponsors/neopilot-ai ✨

;;; Code:

(require 'map)
(require 'seq)

(declare-function acp--add-text-properties "acp")

(defun acp--short-kind-label (kind)
  "Return a short label for tool call KIND string."
  (pcase kind
    ("search" "find")
    ("execute" "run")
    (_ kind)))

(defun acp--status-config (status)
  "Return alist with :label, :icon, and :face for STATUS string.

  (acp--status-config \"completed\")
  ;; => ((:label . \"done\") (:icon . \"✓\") (:face . success))"
  (pcase status
    ("pending" '((:label . "wait") (:icon . "◇") (:face . font-lock-comment-face)))
    ("in_progress" '((:label . "busy") (:icon . "◆") (:face . warning)))
    ("completed" '((:label . "done") (:icon . "✓") (:face . success)))
    ("failed" '((:label . "error") (:icon . "✗") (:face . error)))
    (_ '((:label . "unknown") (:icon . "?") (:face . warning)))))

(defun acp--default-status-kind-label (status kind)
  "Default rendering for STATUS and KIND labels.
STATUS is a string like \"completed\" or nil.
KIND is a string like \"read\" or nil.
Returns a propertized string or nil."
  (let* ((status-config (acp--status-config status))
         (label-format (if (display-graphic-p) " %s " "[%s]"))
         (status-text (when status
                        (let ((label (map-elt status-config :label))
                              (face (map-elt status-config :face)))
                          (acp--add-text-properties
                           (propertize (format label-format label)
                                       'font-lock-face 'default)
                           'font-lock-face (list face '(:inverse-video t))))))
         (kind-text (when kind
                      (let ((box-color (face-foreground
                                        (map-elt status-config :face) nil t)))
                        (acp--add-text-properties
                         (propertize (format label-format
                                            (acp--short-kind-label kind))
                                     'font-lock-face 'default)
                         'font-lock-face `((:box (:color ,box-color))))))))
    (concat status-text kind-text)))

(defun acp--background-tint-status-kind-label (status kind)
  "Render STATUS and KIND as tinted background labels.

Derives background by blending the face foreground (30%) with the
default background (70%), so it adapts to any theme.

  (acp--background-tint-status-kind-label \"completed\" \"read\")
  ;; => #(\" done \" ...) #(\" read \" ...)

STATUS is a string like \"completed\" or nil.
KIND is a string like \"read\" or nil.
Returns a propertized string or nil."
  (let* ((status-config (acp--status-config status))
         (fg (face-foreground (map-elt status-config :face) nil t))
         (bg-base (face-background 'default nil t))
         (bg (when (and fg bg-base)
               (apply #'format "#%02x%02x%02x"
                      (seq-mapn (lambda (f b)
                                  (/ (+ (* f 3) (* b 7)) 10))
                                (color-values fg)
                                (color-values bg-base)))))
         (label-format (if (display-graphic-p) " %s " "[%s]"))
         (status-text (when status
                        (propertize (format label-format
                                           (map-elt status-config :label))
                                    'font-lock-face
                                    `(:background ,bg :foreground ,fg
                                      :weight bold))))
         (kind-text (when kind
                      (propertize (format label-format
                                         (acp--short-kind-label kind))
                                  'font-lock-face
                                  `(:background ,bg :foreground ,fg
                                    :slant italic)))))
    (concat status-text kind-text)))

(defun acp--unicode-icons-status-kind-label (status kind)
  "Render STATUS as a unicode icon and KIND as typed text.

  (acp--unicode-icons-status-kind-label \"completed\" \"read\")
  ;; => \"✓ read\"

  (acp--unicode-icons-status-kind-label \"completed\" nil)
  ;; => \"✓\"

STATUS is a string like \"completed\" or nil.
KIND is a string like \"read\" or nil.
Returns a propertized string or nil."
  (let ((status-config (acp--status-config status))
        (status-text nil)
        (kind-text nil))
    (when status
      (setq status-text (propertize (map-elt status-config :icon)
                                    'font-lock-face
                                    (map-elt status-config :face))))
    (when kind
      (setq kind-text (propertize (acp--short-kind-label kind)
                                  'font-lock-face 'font-lock-type-face)))
    (if (and status-text kind-text)
        (concat status-text " " kind-text)
      (or status-text kind-text))))

(defun acp--plain-colored-status-kind-label (status kind)
  "Render STATUS and KIND as plain colored text with no decoration.

  (acp--plain-colored-status-kind-label \"completed\" \"read\")
  ;; => #(\" done \" ...) #(\" read \" ...)

STATUS is a string like \"completed\" or nil.
KIND is a string like \"read\" or nil.
Returns a propertized string or nil."
  (let* ((status-config (acp--status-config status))
         (face (map-elt status-config :face))
         (label-format (if (display-graphic-p) " %s " "[%s]"))
         (status-text (when status
                        (propertize (format label-format
                                           (map-elt status-config :label))
                                    'font-lock-face face)))
         (kind-text (when kind
                      (propertize (format label-format
                                         (acp--short-kind-label kind))
                                  'font-lock-face face))))
    (concat status-text kind-text)))

(provide 'acp-styles)

;;; acp-styles.el ends here

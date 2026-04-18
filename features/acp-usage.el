;;; acp-usage.el --- Session usage tracking utilities -*- lexical-binding: t; -*-

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

;;; Commentary:
;;
;; Provides session usage tracking functionality for acp.

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'map)

(defvar acp--state)
(defvar acp-mode)
(declare-function acp--state "acp")

(defcustom acp-show-usage-at-turn-end nil
  "Whether to display usage information when agent turn ends.

When non-nil, displays a formatted box showing token counts,
context window usage, and cost information after each agent response."
  :type 'boolean
  :group 'acp)

(defcustom acp-show-context-usage-indicator 'detailed
  "Whether and how to show the context usage indicator.

When set to t, displays a vertical bar character indicating
fill level.  When set to `detailed', displays a numeric format
like \"➤ 29k/200k (29%%)\".  When nil, no indicator is shown.

Color-coded: green (low), yellow (high), red (critical).
Only appears when the ACP server provides usage information."
  :type '(choice (const :tag "Hidden" nil)
                 (const :tag "Bar" t)
                 (const :tag "Detailed" detailed))
  :group 'acp)

(cl-defun acp--save-usage (&key state acp-usage)
  "Update usage STATE from PromptResponse ACP-USAGE field.
Extracts cumulative token counts from the response."
  (let ((usage-state (map-elt state :usage)))
    (when-let ((total (map-elt acp-usage 'totalTokens)))
      (map-put! usage-state :total-tokens total))
    (when-let ((input (map-elt acp-usage 'inputTokens)))
      (map-put! usage-state :input-tokens input))
    (when-let ((output (map-elt acp-usage 'outputTokens)))
      (map-put! usage-state :output-tokens output))
    (when-let ((thought (map-elt acp-usage 'thoughtTokens)))
      (map-put! usage-state :thought-tokens thought))
    (when-let ((cached-read (map-elt acp-usage 'cachedReadTokens)))
      (map-put! usage-state :cached-read-tokens cached-read))
    (when-let ((cached-write (map-elt acp-usage 'cachedWriteTokens)))
      (map-put! usage-state :cached-write-tokens cached-write))
    (map-put! state :usage usage-state)))

(cl-defun acp--update-usage-from-notification (&key state acp-update)
  "Update usage STATE from session/update ACP-UPDATE.
Extracts context window and cost information from usage_update notification."
  (let ((usage-state (map-elt state :usage)))
    (when-let ((used (map-elt acp-update 'used)))
      (map-put! usage-state :context-used used))
    (when-let ((size (map-elt acp-update 'size)))
      (map-put! usage-state :context-size size))
    (when-let ((cost (map-elt acp-update 'cost)))
      (when-let ((amount (map-elt cost 'amount)))
        (map-put! usage-state :cost-amount amount))
      (when-let ((currency (map-elt cost 'currency)))
        (map-put! usage-state :cost-currency currency)))
    (map-put! state :usage usage-state)))

(defun acp--format-number-compact (num)
  "Format NUM compactly with k/m/b suffixes."
  (cond
   ((>= num 1000000000) (format "%.0fb" (/ num 1000000000.0)))
   ((>= num 1000000) (format "%.0fm" (/ num 1000000.0)))
   ((>= num 1000) (format "%.0fk" (/ num 1000.0)))
   (t (format "%d" num))))

(defun acp--usage-has-data-p (usage)
  "Return non-nil if USAGE contains meaningful data.
Checks if any token counts or context size are non-zero."
  (or (> (or (map-elt usage :total-tokens) 0) 0)
      (> (or (map-elt usage :context-size) 0) 0)))

(defun acp-show-usage ()
  "Display current session usage information in the minibuffer."
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in an acp buffer"))
  (unless (acp--usage-has-data-p (map-elt acp--state :usage))
    (error "Usage not available"))
  (message "\n%s\n" (acp--format-usage (map-elt acp--state :usage) t)))

(defun acp--format-usage (usage &optional multiline)
  "Format USAGE data as a display string.
USAGE should be an alist/plist with keys for token counts, context, and cost.
When MULTILINE is non-nil, format as right-aligned labeled rows."
  (let ((tokens
         (string-join
          (delq nil
                (list
                 (when (> (or (map-elt usage :input-tokens) 0) 0)
                   (format "%s in" (acp--format-number-compact
                                    (map-elt usage :input-tokens))))
                 (when (> (or (map-elt usage :output-tokens) 0) 0)
                   (format "%s out" (acp--format-number-compact
                                     (map-elt usage :output-tokens))))
                 (when (and (map-elt usage :thought-tokens)
                            (> (map-elt usage :thought-tokens) 0))
                   (format "%s thought" (acp--format-number-compact
                                         (map-elt usage :thought-tokens))))
                 (when (and (map-elt usage :cached-read-tokens)
                            (> (map-elt usage :cached-read-tokens) 0))
                   (format "%s cached" (acp--format-number-compact
                                        (map-elt usage :cached-read-tokens))))))
          " · "))
        (context
         (concat
          (if (> (or (map-elt usage :context-used) 0) 0)
              (acp--format-number-compact (or (map-elt usage :context-used) 0))
            "0")
          "/"
          (if (> (or (map-elt usage :context-size) 0) 0)
              (acp--format-number-compact (or (map-elt usage :context-size) 0))
            "?")
          (if (and (map-elt usage :context-size)
                   (> (map-elt usage :context-size) 0))
              (format " (%.1f%%)" (* 100.0 (/ (float (or (map-elt usage :context-used) 0))
                                              (map-elt usage :context-size))))
            "")))
        (total
         (let ((n (or (map-elt usage :total-tokens) 0)))
           (if (> n 0)
               (format " (%s total)" (acp--format-number-compact n))
             "")))
        (cost
         (concat
          (if (map-elt usage :cost-currency)
              (map-elt usage :cost-currency)
            "$")
          (if (and (map-elt usage :cost-amount) (> (map-elt usage :cost-amount) 0))
              (format "%.2f" (map-elt usage :cost-amount))
            "0.00"))))
    (if multiline
        (concat
         (propertize " Context: "
                     'face 'font-lock-comment-face
                     'font-lock-face 'font-lock-comment-face)
         context "\n"
         (propertize "  Tokens: "
                     'face 'font-lock-comment-face
                     'font-lock-face 'font-lock-comment-face)
         tokens total "\n"
         (propertize "    Cost: "
                     'face 'font-lock-comment-face
                     'font-lock-face 'font-lock-comment-face)
         cost)
      (concat
       (propertize "Context: "
                   'face 'font-lock-comment-face
                   'font-lock-face 'font-lock-comment-face)
       context " "
       (propertize "Tokens: "
                   'face 'font-lock-comment-face
                   'font-lock-face 'font-lock-comment-face)
       tokens total " "
       (propertize "Cost: "
                   'face 'font-lock-comment-face
                   'font-lock-face 'font-lock-comment-face)
       cost))))

(defun acp--context-usage-face (percentage)
  "Return the face for context usage at PERCENTAGE.
Green for normal, yellow for warning, red for critical."
  (cond
   ((>= percentage 85) 'error)
   ((>= percentage 60) 'warning)
   (t 'success)))

(defun acp--context-usage-indicator-bar (usage context-used context-size)
  "Return a bar indicator for context USAGE.
CONTEXT-USED and CONTEXT-SIZE are token counts."
  (let* ((percentage (/ (* 100.0 context-used) context-size))
         (indicator (cond
                     ((>= percentage 100) "█")
                     ((>= percentage 87.5) "▇")
                     ((>= percentage 75) "▆")
                     ((>= percentage 62.5) "▅")
                     ((>= percentage 50) "▄")
                     ((>= percentage 37.5) "▃")
                     ((>= percentage 25) "▂")
                     ((> percentage 0) "▁")
                     (t nil))))
    (when indicator
      (propertize indicator
                  'face (acp--context-usage-face percentage)
                  'help-echo (acp--format-usage usage)))))

(defun acp--context-usage-indicator-detailed (usage context-used context-size)
  "Return a detailed indicator for context USAGE.
CONTEXT-USED and CONTEXT-SIZE are token counts.
Format: \"29k/200k (29%)\"."
  (let ((percentage (/ (* 100.0 context-used) context-size)))
    (propertize (format "%s/%s (%.0f%%)"
                        (acp--format-number-compact context-used)
                        (acp--format-number-compact context-size)
                        percentage)
                'face (acp--context-usage-face percentage)
                'help-echo (acp--format-usage usage))))

(defun acp--context-usage-indicator ()
  "Return a string indicating context usage percentage.
Dispatches to bar or detailed indicator based on
`acp-show-context-usage-indicator'.
Only returns an indicator if enabled and usage data is available."
  (when-let* ((acp-show-context-usage-indicator)
              ((acp--usage-has-data-p (map-elt (acp--state) :usage)))
              (usage (map-elt (acp--state) :usage))
              (context-used (map-elt usage :context-used))
              (context-size (map-elt usage :context-size))
              ((> context-size 0)))
    (pcase acp-show-context-usage-indicator
      ('detailed
       (acp--context-usage-indicator-detailed usage context-used context-size))
      (_
       (acp--context-usage-indicator-bar usage context-used context-size)))))

(provide 'acp-usage)
;;; acp-usage.el ends here

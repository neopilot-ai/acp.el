;;; acp-viewport.el --- Agent shell viewport interaction  -*- lexical-binding: t -*-

;; Copyright (C) 2025 NeoPilot AI

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

;; Viewport provides an alternative interaction mode for acp.
;; It enables crafting queries, navigating conversation history,
;; and viewing responses in a dedicated buffer.
;;
;; Support the work https://github.com/sponsors/neopilot-ai

;;; Code:

(require 'cursor-sensor)
(require 'seq)
(require 'subr-x)
(require 'window)
(require 'flymake)
(require 'markdown-overlays nil t)
(require 'shell-maker nil t)

(eval-when-compile
  (require 'cl-lib))

(declare-function acp--current-shell "acp")
(declare-function acp--display-buffer "acp")
(declare-function acp--get-region "acp")
(declare-function acp--insert-to-shell-buffer "acp")
(declare-function acp--make-header "acp")
(declare-function acp--context "acp")
(declare-function acp--shell-buffer "acp")
(declare-function acp--start "acp")
(declare-function acp--state "acp")
(declare-function acp--filter-buffer-substring "acp")
(declare-function acp-buffers "acp")
(declare-function acp-copy-session-id "acp")
(declare-function acp-cycle-session-mode "acp")
(declare-function acp-interrupt "acp")
(declare-function acp-interrupt-confirmed-p "acp")
(declare-function acp-open-transcript "acp")
(declare-function acp-queue-request "acp")
(declare-function acp-remove-pending-request "acp")
(declare-function acp-resume-pending-requests "acp")
(declare-function acp-view-acp-logs "acp")
(declare-function acp-view-traffic "acp")
(declare-function acp-next-permission-button "acp")
(declare-function acp-other-buffer "acp")
(declare-function acp-previous-permission-button "acp")
(declare-function acp-project-buffers "acp")
(declare-function acp-select-config "acp")
(declare-function acp-set-session-mode "acp")
(declare-function acp-set-session-model "acp")
(declare-function acp-ui-backward-block "acp")
(declare-function acp-ui-forward-block "acp")
(declare-function acp-ui-mode "acp")
(declare-function acp-completion-mode "acp-completion")
(declare-function acp-yank-dwim "acp")

(defvar acp-header-style)
(defvar acp-prefer-viewport-interaction)
(defvar acp-preferred-agent-config)
(defvar acp-session-strategy)
(defvar acp--state)
(defvar acp-file-completion-enabled)

(defvar-local acp-viewport--compose-snapshot nil
  "Alist with :content and :location from compose buffer before viewing history.")
;; The viewport buffer transitions between major modes which clears
;; buffer-local vars. Make snapshot permanent-local.
(put 'acp-viewport--compose-snapshot 'permanent-local t)

(defvar-local acp-viewport--ring-index nil
  "Current index into `comint-input-ring' for history navigation.")
;; Survives mode switches (edit <-> view) which clear buffer-local vars.
(put 'acp-viewport--ring-index 'permanent-local t)

(cl-defun acp-viewport--show-buffer (&key append override submit no-focus shell-buffer)
  "Show a viewport compose buffer for the agent shell.

APPEND is appended to the viewport compose buffer.
OVERRIDE, when non-nil, replaces content verbatim (no trimming).
SUBMIT, when non-nil, submits after insertion.
NO-FOCUS, when non-nil, avoids focusing the viewport compose buffer.
SHELL-BUFFER, when non-nil, prefer this shell buffer.
NEW-SHELL, create a new shell (no history).

Returns an alist with insertion details or nil otherwise:

  ((:buffer . BUFFER)
   (:start . START)
   (:end . END))"
  (when submit
    (error "Not yet supported"))
  (when no-focus
    (error "Not yet supported"))
  (when (and append override)
    (error "Use :append or :override but not both"))
  (when shell-buffer
    ;; Momentarily set buffer to same window, so it's recent in stack.
    (let ((current (current-buffer)))
      (pop-to-buffer-same-window shell-buffer)
      (pop-to-buffer-same-window current)))
  (when-let* ((shell-buffer (or shell-buffer (acp--shell-buffer)))
              (viewport-buffer (acp-viewport--buffer :shell-buffer shell-buffer))
              (text (or append (acp--context :shell-buffer shell-buffer) "")))
    (when (and override (not (string-empty-p text)))
      (error "Cannot override"))
    (let ((insert-start nil)
          (insert-end nil))
      ;; Is there text to be inserted? Reject while busy.
      (when (and (acp-viewport--busy-p
                  :viewport-buffer viewport-buffer)
                 (or (not (string-empty-p (string-trim text)))
                     (and override (not (string-empty-p (string-trim override))))))
        (user-error "Busy... please wait"))
      (acp--display-buffer viewport-buffer)
      (when (and override
                 (with-current-buffer viewport-buffer
                   ;; viewport buffer empty?
                   (not (= (buffer-size) 0))))
        (unless (y-or-n-p "Compose buffer is not empty.  Override?")
          ;; User does not want to override.
          ;; Treat as regurlar text (typically appended).
          (setq text (concat text
                             (unless (string-empty-p text)
                               "\n\n")
                             override))
          (setq override nil)))
      ;; TODO: Do we need to get prompt and partial response,
      ;; in case viewport compose buffer is created for the
      ;; first time on an ongoing/busy shell session?
      (cond
       ((acp-viewport--busy-p)
        (acp-viewport-view-mode))
       (override
        (acp-viewport-edit-mode)
        (acp-viewport--initialize)
        (setq insert-start (point))
        (insert override)
        (setq insert-end (point)))
       ((derived-mode-p 'acp-viewport-edit-mode)
        (unless (string-empty-p text)
          (save-excursion
            (goto-char (point-max))
            (setq insert-start (point))
            (insert "\n\n" text)
            (setq insert-end (point)))))
       (t
        (acp-viewport-edit-mode)
        ;; Transitioned to edit mode. Wipe content.
        (acp-viewport--initialize)
        ;; Restore snapshot if needed.
        (when-let ((snapshot acp-viewport--compose-snapshot))
          (insert (map-elt snapshot :content))
          (goto-char (map-elt snapshot :location))
          (setq acp-viewport--compose-snapshot nil))
        (save-excursion
          (goto-char (point-max))
          (setq insert-start (point))
          (unless (string-empty-p text)
            (insert "\n\n" text))
          (setq insert-end (point)))))
      `((:buffer . ,viewport-buffer)
        (:start . ,insert-start)
        (:end . ,insert-end)))))

(defun acp-viewport-compose-send ()
  "Send the viewport composed prompt to the agent shell."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a shell viewport buffer"))
  (when (and (not (eq acp-session-strategy 'new-deferred))
             (not (with-current-buffer (acp-viewport--shell-buffer)
                    (map-nested-elt acp--state '(:session :id)))))
    (user-error "Session not ready... please wait"))
  (setq acp-viewport--compose-snapshot nil)
  (setq acp-viewport--ring-index nil)
  (if acp-prefer-viewport-interaction
      (acp-viewport-compose-send-and-wait-for-response)
    (acp-viewport-compose-send-and-kill)))

(defun acp-viewport-compose-send-and-kill ()
  "Send the viewport composed prompt to the agent shell and kill compose buffer."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a shell viewport buffer"))
  (let ((shell-buffer (acp-viewport--shell-buffer))
        (viewport-buffer (current-buffer))
        (prompt (buffer-string)))
    (with-current-buffer shell-buffer
      (acp--insert-to-shell-buffer
       :text prompt
       :submit t))
    (kill-buffer viewport-buffer)
    (pop-to-buffer shell-buffer)))

(defun acp-viewport-compose-send-and-wait-for-response ()
  "Send the viewport composed prompt and display response in viewport."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (catch 'exit
    (unless (derived-mode-p 'acp-viewport-edit-mode)
      (user-error "Not in a shell viewport buffer"))
    (let ((shell-buffer (acp-viewport--shell-buffer))
          (viewport-buffer (current-buffer))
          (prompt (string-trim (buffer-string))))
      (when (acp-viewport--busy-p)
        (unless (acp-interrupt-confirmed-p)
          (throw 'exit nil))
        (with-current-buffer shell-buffer
          (acp-interrupt t))
        (with-current-buffer viewport-buffer
          (acp-viewport-view-mode)
          (acp-viewport--initialize
           :prompt prompt))
        (user-error "Aborted"))
      (when (string-empty-p (string-trim prompt))
        (acp-viewport--initialize)
        (user-error "Nothing to send"))
      (if (derived-mode-p 'acp-viewport-view-mode)
          (progn
            (acp-viewport-edit-mode)
            (acp-viewport--initialize))
        (let ((inhibit-read-only t))
          (markdown-overlays-put))
        (acp-viewport-view-mode)
        (acp-viewport--initialize :prompt prompt)
        ;; (setq view-exit-action 'kill-buffer) TODO
        (when (string-equal prompt "clear")
          (acp-viewport-edit-mode)
          (acp-viewport--initialize))
        (acp--insert-to-shell-buffer
         :shell-buffer (acp-viewport--shell-buffer)
         :text prompt
         :submit t
         :no-focus t)
        ;; TODO: Point should go to beginning of response after submission.
        (let ((inhibit-read-only t))
          (markdown-overlays-put))))))

(defun acp-viewport-interrupt ()
  "Interrupt active agent shell request."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (catch 'exit
    (let ((shell-buffer (acp-viewport--shell-buffer)))
      (unless (acp-viewport--busy-p)
        (user-error "No pending request"))
      (unless (acp-interrupt-confirmed-p)
        (throw 'exit nil))
      (with-current-buffer shell-buffer
        (acp-interrupt t))
      (user-error "Aborted"))))

(cl-defun acp-viewport--initialize (&key prompt response)
  "Initialize viewport compose buffer.

Optionally set its PROMPT and RESPONSE."
  (acp-viewport--ensure-buffer)

  ;; Recalculate and cache position
  (acp-viewport--position :force-refresh t)
  (let ((inhibit-read-only t)
        (viewport-buffer (current-buffer)))
    (erase-buffer)
    (when-let ((shell-buffer (acp-viewport--shell-buffer)))
      (with-current-buffer shell-buffer
        (unless (eq acp-header-style 'graphical)
          ;; Insert newline at point-min purely for
          ;; display/layout. Only needed for non-graphical header.
          (with-current-buffer viewport-buffer
            (insert (propertize "\n"
                                'cursor-intangible t
                                'front-sticky '(cursor-intangible)
                                'rear-nonsticky '(cursor-intangible)))))))
    (when prompt
      (insert
       (if (derived-mode-p 'acp-viewport-view-mode)
           (propertize (concat prompt "\n\n")
                       'rear-nonsticky t
                       'acp-viewport-prompt t
                       'face 'font-lock-doc-face)
         prompt)))
    (when response
      (insert response))
    (let ((inhibit-read-only t))
      (markdown-overlays-put))))

(defun acp-viewport--ensure-buffer ()
  "Ensure current buffer is a viewport and err otherwise."
  (unless (or (derived-mode-p 'acp-viewport-view-mode)
              (derived-mode-p 'acp-viewport-edit-mode))
    (user-error "Not in a shell viewport buffer")))

(defun acp-viewport--prompt ()
  "Return the buffer prompt."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((start (if (get-text-property (point-min) 'acp-viewport-prompt)
                           (point-min)
                         (next-single-property-change (point-min) 'acp-viewport-prompt)))
                (found (get-text-property start 'acp-viewport-prompt)))
      (string-trim
       (buffer-substring-no-properties
        start
        (or (next-single-property-change
             start 'acp-viewport-prompt)
            (point-max)))))))

(defun acp-viewport--response ()
  "Return the buffer response."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((start (if (get-text-property (point-min) 'acp-viewport-prompt)
                           (point-min)
                         (next-single-property-change (point-min) 'acp-viewport-prompt)))
                (found (get-text-property start 'acp-viewport-prompt))
                (end (next-single-property-change start 'acp-viewport-prompt)))
      (buffer-substring end (point-max)))))

(defun acp-viewport--prompt-start ()
  "Return the start position of the prompt, or nil if no prompt."
  (save-excursion
    (goto-char (point-min))
    (when-let ((start (if (get-text-property (point-min) 'acp-viewport-prompt)
                          (point-min)
                        (next-single-property-change (point-min) 'acp-viewport-prompt))))
      (when (get-text-property start 'acp-viewport-prompt)
        start))))

(defun acp-viewport--response-start ()
  "Return the start position of the response, or nil if no response."
  (save-excursion
    (goto-char (point-min))
    (when-let* ((start (if (get-text-property (point-min) 'acp-viewport-prompt)
                           (point-min)
                         (next-single-property-change (point-min) 'acp-viewport-prompt)))
                (found (get-text-property start 'acp-viewport-prompt))
                (end (next-single-property-change start 'acp-viewport-prompt)))
      (when (< end (point-max))
        end))))

(defun acp-viewport-compose-cancel ()
  "Cancel prompt composition."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (setq acp-viewport--compose-snapshot nil)
  (let ((viewport-buffer (current-buffer))
        (shell-buffer (acp-viewport--shell-buffer)))
    ;; View mode
    (if (or (derived-mode-p 'acp-viewport-view-mode)
            (with-current-buffer shell-buffer
              (not (shell-maker-history-position))))
        (bury-buffer)
      ;; Edit mode
      (when (or (string-empty-p (string-trim (buffer-string)))
                (y-or-n-p "Discard composed prompt? "))
        (if acp-prefer-viewport-interaction
            (acp-viewport-view-last)
          (acp-other-buffer)
          (kill-buffer viewport-buffer))))))

(defun acp-viewport-previous-history ()
  "Insert previous prompt from history into compose buffer."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a shell viewport buffer"))
  (let* ((ring (with-current-buffer (acp-viewport--shell-buffer)
                 (seq-filter
                  (lambda (item)
                    (not (string-empty-p item)))
                  (ring-elements comint-input-ring))))
         (next-index (unless (seq-empty-p ring)
                       (if acp-viewport--ring-index
                           (1+ acp-viewport--ring-index)
                         0))))
    ;; Save in-progress compose text before first history navigation.
    (when (and (not acp-viewport--ring-index)
               (not acp-viewport--compose-snapshot))
      (setq acp-viewport--compose-snapshot
            `((:content . ,(buffer-string))
              (:location . ,(point)))))
    (cond
     ;; Empty ring.
     ((not next-index)
      (setq acp-viewport--ring-index nil))
     ;; Already at oldest entry, clamp.
     ((>= next-index (seq-length ring))
      (setq acp-viewport--ring-index (1- (seq-length ring))))
     (t
      (setq acp-viewport--ring-index next-index)))
    (when acp-viewport--ring-index
      (acp-viewport--initialize
       :prompt (seq-elt ring acp-viewport--ring-index)))))

(defun acp-viewport-next-history ()
  "Insert next prompt from history into compose buffer."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a shell viewport buffer"))
  (unless acp-viewport--ring-index
    (user-error "No more history"))
  (let* ((ring (with-current-buffer (acp-viewport--shell-buffer)
                 (seq-filter
                  (lambda (item)
                    (not (string-empty-p item)))
                  (ring-elements comint-input-ring))))
         (next-index (1- acp-viewport--ring-index)))
    (if (< next-index 0)
        ;; Past newest entry, restore in-progress compose text.
        (let ((snapshot acp-viewport--compose-snapshot))
          (setq acp-viewport--ring-index nil)
          (acp-viewport--initialize)
          (when snapshot
            (insert (map-elt snapshot :content))
            (goto-char (map-elt snapshot :location))
            (setq acp-viewport--compose-snapshot nil)))
      ;; Show older entry.
      (setq acp-viewport--ring-index next-index)
      (acp-viewport--initialize
       :prompt (seq-elt ring next-index)))))

(defun acp-viewport-search-history ()
  "Search prompt history, select, and insert into compose buffer."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a shell viewport buffer"))
  (insert (with-current-buffer (acp-viewport--shell-buffer)
            (completing-read
             "History: "
             (delete-dups
              (seq-filter
               (lambda (item)
                 (not (string-empty-p item)))
               (ring-elements comint-input-ring))) nil t))))

(defun acp-viewport-compose-peek-last ()
  "Save compose buffer snapshot and peek at the last interaction."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (user-error "Not in a prompt compose buffer"))
  (unless (with-current-buffer (acp-viewport--shell-buffer)
            (shell-maker-history-position))
    (user-error "No items in history"))
  (setq acp-viewport--compose-snapshot
        `((:content . ,(buffer-string))
          (:location . ,(point))))
  (acp-viewport-view-last))

(defun acp-viewport-view-last ()
  "Display the last request/response interaction."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (when-let ((shell-buffer (acp-viewport--shell-buffer)))
    (with-current-buffer shell-buffer
      (goto-char comint-last-input-start)))
  (acp-viewport-view-mode)
  (acp-viewport-refresh))

(defun acp-viewport-refresh ()
  "Refresh viewport buffer content with current item from shell."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (when-let ((shell-buffer (acp-viewport--shell-buffer))
             (viewport-buffer (current-buffer))
             (current (with-current-buffer shell-buffer
                        (or (shell-maker--command-and-response-at-point)
                            (shell-maker-next-command-and-response t)))))
    (acp-viewport--initialize
     :prompt (car current)
     :response (cdr current))
    (goto-char (point-min))
    current))

(defun acp-viewport-next-item ()
  "Go to next item.

If at point-max, attempt to switch to next interaction."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-view-mode)
    (error "Not in a viewport buffer"))
  (let* ((current-pos (point))
         (prompt-start (acp-viewport--prompt-start))
         (response-start (acp-viewport--response-start))
         (block-pos (save-mark-and-excursion
                      (acp-ui-forward-block)))
         (button-pos (save-mark-and-excursion
                       (acp-next-permission-button)))
         ;; Filter positions to only those after current position
         (candidates (delq nil (list
                                (when (and prompt-start (> prompt-start current-pos))
                                  prompt-start)
                                (when (and response-start (> response-start current-pos))
                                  response-start)
                                block-pos
                                button-pos)))
         (next-pos (if candidates
                       (apply #'min candidates)
                     ;; No more items, try point-max if not already there
                     (when (< current-pos (point-max))
                       (point-max)))))
    (if next-pos
        (progn
          (deactivate-mark)
          (goto-char next-pos))
      ;; At point-max with no more items, try next interaction
      (condition-case nil
          (acp-viewport-next-page)
        (error
         ;; At the end of all interactions, stay at point-max
         nil)))))

(defun acp-viewport-previous-item ()
  "Go to previous item.

If at the first item, attempt to switch to previous interaction."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-view-mode)
    (error "Not in a viewport buffer"))
  (let* ((current-pos (point))
         (prompt-start (acp-viewport--prompt-start))
         (response-start (acp-viewport--response-start))
         (block-pos (save-mark-and-excursion
                      (let ((pos (acp-ui-backward-block)))
                        (when (and pos (< pos current-pos))
                          pos))))
         (button-pos (save-mark-and-excursion
                       (let ((pos (acp-previous-permission-button)))
                         (when (and pos (< pos current-pos))
                           pos))))
         ;; Filter positions to only those before current position
         (candidates (delq nil (list
                                (when (and prompt-start (< prompt-start current-pos))
                                  prompt-start)
                                (when (and response-start (< response-start current-pos))
                                  response-start)
                                block-pos
                                button-pos)))
         (next-pos (when candidates
                     (apply #'max candidates))))
    (if next-pos
        (progn
          (deactivate-mark)
          (goto-char next-pos))
      ;; No more items before current position, try previous interaction
      (condition-case nil
          ;; Switch to previous page and stop at point-max (call next-interaction directly)
          (acp-viewport-next-page :backwards t)
        (error
         ;; At the beginning of all interactions, stay at first item
         (when prompt-start
           (goto-char prompt-start)))))))

(defconst acp-viewport--suffix " [viewport]"
  "Suffix appended to shell buffer name to create viewport buffer name.")

(cl-defun acp-viewport--buffer (&key shell-buffer existing-only)
  "Get the viewport buffer associated with a SHELL-BUFFER.

With EXISTING-ONLY, only return existing buffers without creating."
  (when-let ((shell-buffer (or shell-buffer
                               (acp--shell-buffer))))
    (with-current-buffer shell-buffer
      (let* ((viewport-buffer-name (concat (buffer-name (get-buffer shell-buffer))
                                           acp-viewport--suffix))
             (viewport-buffer (get-buffer viewport-buffer-name)))
        (if viewport-buffer
            viewport-buffer
          (if existing-only
              nil
            (with-current-buffer (get-buffer-create viewport-buffer-name)
              (acp-viewport-edit-mode)
              (current-buffer))))))))

(defun acp-viewport-reply ()
  "Reply as a follow-up and compose another prompt/query."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-view-mode)
    (user-error "Not in a shell viewport buffer"))
  (when (acp-viewport--busy-p)
    (user-error "Busy, please wait"))
  (let* ((region (map-elt (acp--get-region :deactivate t) :content))
         (block-quoted-text (when region
                              (concat
                               (mapconcat (lambda (line)
                                            (concat "> " line))
                                          (split-string region "\n")
                                          "\n")
                               "\n\n"))))
    (with-current-buffer (acp-viewport--shell-buffer)
      (goto-char (point-max)))
    (let ((snapshot acp-viewport--compose-snapshot))
      (acp-viewport-edit-mode)
      (acp-viewport--initialize)
      (when snapshot
        (insert (map-elt snapshot :content))
        (setq acp-viewport--compose-snapshot nil))
      (when block-quoted-text
        (goto-char (point-max))
        (insert (if snapshot
                    "\n\n"
                  "") block-quoted-text))
      ;; Skip past any cursor-intangible layout text (e.g. the
      ;; newline inserted by `acp-viewport--initialize')
      ;; so callers like `acp-viewport-reply-1' can insert.
      (goto-char (if (or snapshot block-quoted-text)
                     (point-max)
                   (or (next-single-property-change (point-min) 'cursor-intangible)
                       (point-max)))))
    ;; Setting point isn't enough at times. Force scrolling.
    (set-window-start (selected-window) (point-min))))

(defun acp-viewport-reply-yes ()
  "Reply with \"yes\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "yes")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-1 ()
  "Reply with \"1\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "1")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-2 ()
  "Reply with \"2\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "2")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-3 ()
  "Reply with \"3\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "3")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-4 ()
  "Reply with \"4\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "4")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-5 ()
  "Reply with \"5\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "5")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-6 ()
  "Reply with \"6\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "6")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-7 ()
  "Reply with \"7\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "7")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-8 ()
  "Reply with \"8\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "8")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-9 ()
  "Reply with \"9\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "9")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-more ()
  "Reply with \"more\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "more")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-again ()
  "Reply with \"again\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "again")
  (acp-viewport-compose-send))

(defun acp-viewport-reply-continue ()
  "Reply with \"continue\" and send immediately."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-reply)
  (insert "continue")
  (acp-viewport-compose-send))

(defun acp-viewport-previous-page ()
  "Show previous interaction (request / response)."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (acp-viewport-next-page :backwards t :start-at-top t))

(cl-defun acp-viewport-next-page (&key backwards start-at-top)
  "Show next interaction (request / response).

If BACKWARDS is non-nil, go to previous interaction.
If START-AT-TOP is non-nil, position at point-min regardless of direction.

If there are no more next items and a compose snapshot exists, restore the
buffer from the snapshot and switch to edit mode."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-view-mode)
    (error "Not in a viewport buffer"))
  (when (acp-viewport--busy-p)
    (user-error "Busy... please wait"))
  (let ((shell-buffer (acp-viewport--shell-buffer))
        (snapshot acp-viewport--compose-snapshot)
        (pos (acp-viewport--position :force-refresh t)))
    ;; Check if at last position going forward with a snapshot to restore
    (if (and (not backwards) snapshot pos
             (= (map-elt pos :current) (map-elt pos :total)))
        (progn
          (acp-viewport-edit-mode)
          (acp-viewport--initialize)
          (insert (map-elt snapshot :content))
          (goto-char (map-elt snapshot :location))
          (setq acp-viewport--compose-snapshot nil)
          (cl-return-from acp-viewport-next-page))
      (when-let ((next (with-current-buffer shell-buffer
                         (if backwards
                             (when (save-excursion
                                     (let ((orig-line (line-number-at-pos)))
                                       (comint-previous-prompt 1)
                                       (= orig-line (line-number-at-pos))))
                               (error "No previous page"))
                           (when (save-excursion
                                   (let ((orig-line (point)))
                                     (comint-next-prompt 1)
                                     (= orig-line (point))))
                             (error "No next page")))
                         (shell-maker-next-command-and-response backwards))))
        (acp-viewport--initialize
         :prompt (car next) :response (cdr next))
        (goto-char (if start-at-top
                       (point-min)
                     (if backwards (point-max) (point-min))))
        (acp-viewport--update-header)
        next))))

(defun acp-viewport-set-session-model ()
  "Set session model."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let* ((shell-buffer (or (acp--current-shell)
                           (user-error "Not in an acp buffer")))
         (viewport-buffer (acp-viewport--buffer
                          :shell-buffer shell-buffer
                          :existing-only t)))
    (with-current-buffer shell-buffer
      (acp-set-session-model
       (lambda ()
         (with-current-buffer viewport-buffer
           (acp-viewport--update-header)))))))

(defun acp-viewport-set-session-mode ()
  "Set session mode."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let* ((shell-buffer (or (acp--current-shell)
                           (user-error "Not in an acp buffer")))
         (viewport-buffer (acp-viewport--buffer
                          :shell-buffer shell-buffer
                          :existing-only t)))
    (with-current-buffer shell-buffer
      (acp-set-session-mode
       (lambda ()
         (when viewport-buffer
           (with-current-buffer viewport-buffer
             (acp-viewport--update-header))))))))

(defun acp-viewport-cycle-session-mode ()
  "Cycle through available session modes."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let* ((shell-buffer (or (acp--current-shell)
                           (user-error "Not in an acp buffer")))
         (viewport-buffer (acp-viewport--buffer
                          :shell-buffer shell-buffer
                          :existing-only t)))
    (with-current-buffer shell-buffer
      (acp-cycle-session-mode
       (lambda ()
         (when viewport-buffer
           (with-current-buffer viewport-buffer
             (acp-viewport--update-header))))))))

(defun acp-viewport-view-traffic ()
  "View agent shell traffic buffer."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (acp-view-traffic))))

(defun acp-viewport-view-acp-logs ()
  "View agent shell ACP logs buffer."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (acp-view-acp-logs))))

(defun acp-viewport-queue-request ()
  "Queue or immediately send a request depending on shell busy state."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (call-interactively #'acp-queue-request))))

(defun acp-viewport-resume-pending-requests ()
  "Resume processing pending requests in the queue."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (acp-resume-pending-requests))))

(defun acp-viewport-remove-pending-request ()
  "Remove pending requests."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (call-interactively #'acp-remove-pending-request))))

(defun acp-viewport-copy-session-id ()
  "Copy the current session ID to the kill ring."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (acp-copy-session-id))))

(defun acp-viewport-open-transcript ()
  "Open the transcript file for the current `acp' session."
  (declare (modes acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (acp-viewport--ensure-buffer)
  (let ((shell-buffer (or (acp--current-shell)
                          (user-error "Not in an acp buffer"))))
    (with-current-buffer shell-buffer
      (acp-open-transcript))))

;; Continuously fetching position can get expensive. Cache it.
(defvar-local acp-viewport--position-cache nil
  "Cached position alist with :current and :total.")

(cl-defun acp-viewport--position (&key force-refresh)
  "Return the position in history of the shell buffer.

When FORCE-REFRESH is non-nil, recalculate and update cache."
  (acp-viewport--ensure-buffer)
  (if (and (not force-refresh) acp-viewport--position-cache)
      acp-viewport--position-cache
    (let ((position (with-current-buffer (acp-viewport--shell-buffer)
                      (shell-maker-history-position))))
      (setq acp-viewport--position-cache position)
      position)))

(cl-defun acp-viewport--busy-p (&key viewport-buffer)
  "Return non-nil if the associated shell buffer is busy.

VIEWPORT-BUFFER is the viewport buffer to check."
  (when-let ((shell-buffer (acp--shell-buffer
                            :viewport-buffer viewport-buffer
                            :no-error t)))
    (with-current-buffer shell-buffer
      shell-maker--busy)))

(defvar acp-viewport-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'acp-viewport-compose-send)
    (define-key map (kbd "C-c C-p") #'acp-viewport-compose-peek-last)
    (define-key map (kbd "C-c C-k") #'acp-viewport-compose-cancel)
    (define-key map (kbd "C-c C-h") #'acp-viewport-compose-help-menu)
    (define-key map (kbd "C-<tab>") #'acp-viewport-cycle-session-mode)
    (define-key map (kbd "C-c C-m") #'acp-viewport-set-session-mode)
    (define-key map (kbd "C-c C-v") #'acp-viewport-set-session-model)
    (define-key map (kbd "C-c C-o") #'acp-other-buffer)
    (define-key map (kbd "M-p") #'acp-viewport-previous-history)
    (define-key map (kbd "M-n") #'acp-viewport-next-history)
    (define-key map (kbd "M-r") #'acp-viewport-search-history)
    (define-key map [remap yank] #'acp-yank-dwim)
    map)
  "Keymap for `acp-viewport-edit-mode'.")

(defvar acp-viewport-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'acp-viewport-interrupt)
    (define-key map (kbd "TAB") #'acp-viewport-next-item)
    (define-key map (kbd "<backtab>") #'acp-viewport-previous-item)
    (define-key map (kbd "n") #'acp-viewport-next-item)
    (define-key map (kbd "p") #'acp-viewport-previous-item)
    (define-key map (kbd "f") #'acp-viewport-next-page)
    (define-key map (kbd "b") #'acp-viewport-previous-page)
    (define-key map (kbd "r") #'acp-viewport-reply)
    (define-key map (kbd "y") #'acp-viewport-reply-yes)
    (define-key map (kbd "1") #'acp-viewport-reply-1)
    (define-key map (kbd "2") #'acp-viewport-reply-2)
    (define-key map (kbd "3") #'acp-viewport-reply-3)
    (define-key map (kbd "4") #'acp-viewport-reply-4)
    (define-key map (kbd "5") #'acp-viewport-reply-5)
    (define-key map (kbd "6") #'acp-viewport-reply-6)
    (define-key map (kbd "7") #'acp-viewport-reply-7)
    (define-key map (kbd "8") #'acp-viewport-reply-8)
    (define-key map (kbd "9") #'acp-viewport-reply-9)
    (define-key map (kbd "q") #'bury-buffer)
    (define-key map (kbd "C-<tab>") #'acp-viewport-cycle-session-mode)
    (define-key map (kbd "v") #'acp-viewport-set-session-model)
    (define-key map (kbd "m") #'acp-viewport-reply-more)
    (define-key map (kbd "a") #'acp-viewport-reply-again)
    (define-key map (kbd "c") #'acp-viewport-reply-continue)
    (define-key map (kbd "s") #'acp-viewport-set-session-mode)
    (define-key map (kbd "o") #'acp-other-buffer)
    (define-key map (kbd "C-c C-o") #'acp-other-buffer)
    (define-key map (kbd "?") #'acp-viewport-help-menu)
    map)
  "Keymap for `acp-viewport-view-mode'.")

(defun acp-viewport-help-menu ()
  "Show viewport and display the transient help menu (bound to ? in view mode)."
  (declare (modes acp-viewport-view-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-view-mode)
    (error "Not in a viewport buffer"))
  (transient-define-prefix acp-viewport--help-menu ()
    "`acp' viewport help menu"
    [:class transient-columns
            :setup-children
            (lambda (_)
              (transient-parse-suffixes
               'acp-viewport-help-menu
               (list
                (apply #'vector "Viewport Help"
                       (acp-viewport--make-transient-group
                        acp-viewport-view-mode-map
                        '(((:function . acp-viewport-next-item)
                           (:description . "Next item"))
                          ((:function . acp-viewport-previous-item)
                           (:description . "Previous item"))
                          ((:function . acp-viewport-next-page)
                           (:description . "Next page")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-previous-page)
                           (:description . "Previous Page")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-other-buffer)
                           (:description . "Switch to shell")
                           (:transient . nil))
                          ((:function . bury-buffer)
                           (:description . "Close")
                           (:transient . nil)))))
                (apply #'vector ""
                       (acp-viewport--make-transient-group
                        acp-viewport-view-mode-map
                        '(((:function . acp-viewport-reply)
                           (:description . "Reply…")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-yes)
                           (:description . "Reply \"yes\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-more)
                           (:description . "Reply \"more\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-again)
                           (:description . "Reply \"again\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-continue)
                           (:description . "Reply \"continue\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-1)
                           (:description . "Reply \"1\"")
                           (:if-not . acp-viewport--busy-p)))))
                (apply #'vector ""
                       (acp-viewport--make-transient-group
                        acp-viewport-view-mode-map
                        '(((:function . acp-viewport-reply-2)
                           (:description . "Reply \"2\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-reply-3)
                           (:description . "Reply \"3\"")
                           (:if-not . acp-viewport--busy-p))
                          ((:function . acp-viewport-set-session-model)
                           (:description . "Set model"))
                          ((:function . acp-viewport-set-session-mode)
                           (:description . "Set mode"))
                          ((:function . acp-viewport-cycle-session-mode)
                           (:description . "Cycle mode"))
                          ((:function . acp-viewport-interrupt)
                           (:description . "Interrupt")))))
                (apply #'vector ""
                       (acp-viewport--make-transient-group
                        acp-viewport-view-mode-map
                        '(((:function . acp-viewport-view-traffic)
                           (:description . "View traffic"))
                          ((:function . acp-viewport-view-acp-logs)
                           (:description . "View logs"))
                          ((:function . acp-viewport-copy-session-id)
                           (:description . "Copy session ID"))
                          ((:function . acp-viewport-open-transcript)
                           (:description . "Open transcript")))))
                )))])
  (call-interactively #'acp-viewport--help-menu))

(defun acp-viewport-compose-help-menu ()
  "Show the transient help menu for compose (edit) mode."
  (declare (modes acp-viewport-edit-mode))
  (interactive)
  (unless (derived-mode-p 'acp-viewport-edit-mode)
    (error "Not in a compose buffer"))
  (transient-define-prefix acp-viewport--compose-help-menu ()
    "`acp' viewport compose help menu"
    [:class transient-columns
            :setup-children
            (lambda (_)
              (transient-parse-suffixes
               'acp-viewport-compose-help-menu
               (list
                (apply #'vector "Compose Help"
                       (acp-viewport--make-transient-group
                        acp-viewport-edit-mode-map
                        '(((:function . acp-viewport-compose-send)
                           (:description . "Submit"))
                          ((:function . acp-viewport-compose-cancel)
                           (:description . "Cancel"))
                          ((:function . acp-viewport-compose-peek-last)
                           (:description . "Previous Page")))))
                (apply #'vector ""
                       (acp-viewport--make-transient-group
                        acp-viewport-edit-mode-map
                        '(((:function . acp-viewport-previous-history)
                           (:description . "Previous prompt"))
                          ((:function . acp-viewport-next-history)
                           (:description . "Next prompt"))
                          ((:function . acp-viewport-search-history)
                           (:description . "Search prompts")))))
                (apply #'vector ""
                       (acp-viewport--make-transient-group
                        acp-viewport-edit-mode-map
                        '(((:function . acp-viewport-set-session-model)
                           (:description . "Set model"))
                          ((:function . acp-viewport-set-session-mode)
                           (:description . "Set mode"))
                          ((:function . acp-viewport-cycle-session-mode)
                           (:description . "Cycle mode"))
                          ((:function . acp-other-buffer)
                           (:description . "Switch to shell")
                           (:transient . nil))))))))])
  (call-interactively #'acp-viewport--compose-help-menu))

(defun acp-viewport--make-transient-group (keymap commands)
  "Build a list of transient suffix specs from COMMANDS using KEYMAP.
Each element of COMMANDS is an alist with keys :function, :description,
and optionally :if, :if-not, or :transient (defaults to t).
Returns only suffixes whose function has a binding in KEYMAP."
  (seq-filter
   #'identity
   (seq-map (lambda (command)
              (when-let* ((keys (where-is-internal (map-elt command :function)
                                                   keymap t))
                          ((not (keymapp keys)))
                          (description (map-elt command :description)))
                (append (list (key-description keys) description (map-elt command :function)
                              :transient (map-elt command :transient t))
                        (when-let ((pred (map-elt command :if)))
                          (list :if pred))
                        (when-let ((pred (map-elt command :if-not)))
                          (list :if-not pred)))))
            commands)))

(defun acp-viewport--update-header ()
  "Update header and mode line based on `acp-header-style'.

Automatically determines qualifier and bindings based on current major mode."
  (acp-viewport--ensure-buffer)
  (let* ((pos (or (acp-viewport--position)
                  (list (cons :current 1) (cons :total 1))))
         (pos-label (format "%d/%d" (map-elt pos :current) (map-elt pos :total)))
         (qualifier (cond
                     ((acp-viewport--busy-p)
                      (format "[%s][Busy]" pos-label))
                     ((derived-mode-p 'acp-viewport-edit-mode)
                      (format "[%s][Edit]" pos-label))
                     ((derived-mode-p 'acp-viewport-view-mode)
                      (format "[%s][View]" pos-label))))
         (bindings (cond
                    ((derived-mode-p 'acp-viewport-edit-mode)
                     (list
                      `((:key . ,(key-description (where-is-internal
                                                   'acp-viewport-compose-send
                                                   acp-viewport-edit-mode-map t)))
                        (:description . "Submit"))
                      `((:key . ,(key-description (where-is-internal
                                                   'acp-viewport-compose-cancel
                                                   acp-viewport-edit-mode-map t)))
                        (:description . "Cancel"))
                      `((:key . ,(key-description (where-is-internal
                                                   'acp-viewport-compose-peek-last
                                                   acp-viewport-edit-mode-map t)))
                        (:description . "Previous Page"))
                      `((:key . ,(key-description (where-is-internal
                                                   'acp-viewport-compose-help-menu
                                                   acp-viewport-edit-mode-map t)))
                        (:description . "Help"))))
                    ((derived-mode-p 'acp-viewport-view-mode)
                     (append
                      (list
                       `((:key . ,(key-description (where-is-internal
                                                    'acp-viewport-next-item
                                                    acp-viewport-view-mode-map t)))
                         (:description . "Next"))
                       `((:key . ,(key-description (where-is-internal
                                                    'acp-viewport-previous-item
                                                    acp-viewport-view-mode-map t)))
                         (:description . "Previous")))
                      (unless (acp-viewport--busy-p)
                        (list
                         `((:key . ,(key-description (where-is-internal
                                                      'acp-viewport-reply
                                                      acp-viewport-view-mode-map t)))
                           (:description . "Reply…"))))
                      (when (acp-viewport--busy-p)
                        (list
                         `((:key . ,(key-description (where-is-internal
                                                      'acp-viewport-interrupt
                                                      acp-viewport-view-mode-map t)))
                           (:description . "Interrupt"))))
                      (list
                       `((:key . ,(key-description (where-is-internal
                                                    'acp-viewport-help-menu
                                                    acp-viewport-view-mode-map t)))
                         (:description . "Help"))))))))
    (when-let* ((shell-buffer (acp-viewport--shell-buffer))
                (header (with-current-buffer shell-buffer
                          (cond
                           ((eq acp-header-style 'graphical)
                            (acp--make-header (acp--state)
                                                      :qualifier qualifier
                                                      :bindings bindings))
                           ((memq acp-header-style '(text none nil))
                            (acp--make-header (acp--state)
                                                      :qualifier qualifier
                                                      :bindings bindings))))))
      (setq-local header-line-format header))))

(defvar-local acp-viewport--clean-up t)

(cl-defun acp-viewport--shell-buffer (&optional viewport-buffer)
  "Get the shell buffer associated with VIEWPORT-BUFFER.

Derives shell buffer name by removing the viewport suffix from buffer name.
Returns nil if VIEWPORT-BUFFER is not a viewport buffer or shell doesn't exist."
  (when-let* ((viewport-name (buffer-name (or viewport-buffer (current-buffer))))
              ((string-suffix-p acp-viewport--suffix viewport-name))
              (shell-name (substring viewport-name 0
                                     (- (length viewport-name)
                                        (length acp-viewport--suffix)))))
    (get-buffer shell-name)))

(defun acp-viewport--clean-up ()
  "Clean up resources.

For example, offer to kill associated shell session."
  (acp-viewport--ensure-buffer)
  (if (and acp-viewport--clean-up
           ;; Only offer to kill shell buffers when viewport buffer
           ;; is explicitly being killed from a viewport buffer.
           (eq (current-buffer)
               (window-buffer (selected-window))))
      ;; Temporarily disable cleaning up to avoid multiple clean-ups
      ;; triggered by shell buffers attempting to kill viewport buffer.
      (let ((acp-viewport--clean-up nil))
        (when-let ((shell-buffers (seq-filter (lambda (shell-buffer)
                                                (and (equal (acp-viewport--buffer
                                                             :shell-buffer shell-buffer
                                                             :existing-only t)
                                                            (current-buffer))
                                                     ;; Skip shells already shutting down (client
                                                     ;; is nil after acp--shutdown).
                                                     (buffer-local-value 'acp--state shell-buffer)
                                                     (map-elt (buffer-local-value 'acp--state shell-buffer) :client)))
                                              (acp-buffers)))
                   ((y-or-n-p "Kill shell session too?")))
          (mapc (lambda (shell-buffer)
                  (kill-buffer shell-buffer))
                shell-buffers)))))

(define-derived-mode acp-viewport-edit-mode text-mode "Agent Shell Viewport (Edit)"
  "Major mode for composing agent shell prompts.

\\{acp-viewport-edit-mode-map}"
  (cursor-intangible-mode +1)
  (setq buffer-read-only nil)
  (when acp-file-completion-enabled
    (acp-completion-mode +1))
  (acp-viewport--update-header)
  (let ((inhibit-read-only t))
    (erase-buffer))
  (add-hook 'kill-buffer-hook #'acp-viewport--clean-up nil t))

(define-derived-mode acp-viewport-view-mode text-mode "Agent Shell Viewport (View)"
  "Major mode for viewing agent shell prompts (read-only).

\\{acp-viewport-view-mode-map}"
  (cursor-intangible-mode +1)
  (acp-ui-mode +1)
  (acp-viewport--update-header)
  (setq-local filter-buffer-substring-function #'acp--filter-buffer-substring)
  (setq buffer-read-only t)
  (add-hook 'kill-buffer-hook #'acp-viewport--clean-up nil t))

(provide 'acp-viewport)

;;; acp-viewport.el ends here

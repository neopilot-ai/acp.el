;;; acp-sui.el --- Interactive shell UI elements -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI

;; Author: NeoPilot AI https://github.com/neopilot-ai
;; URL: https://github.com/neopilot-ai/acp.el

;;; Commentary:
;;
;; A library for creating interactive shell UI elements.
;;
;; Note: This package is in very early stages and likely has
;; rough edges.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues
;;
;; ✨ Please support this work https://github.com/sponsors/neopilot-ai ✨

;;; Code:

(require 'cl-lib)
(require 'cursor-sensor)

(cl-defun acp-acp-sui-make-dialog-block-model (&key (namespace-id "global") (block-id "1") label-left label-right body)
  "Create a dialog block model alist.
NAMESPACE-ID, BLOCK-ID, LABEL-LEFT, LABEL-RIGHT, and BODY are the keys."
  (list (cons :namespace-id namespace-id)
        (cons :block-id block-id)
        (cons :label-left (acp-sui--string-or-nil label-left))
        (cons :label-right (acp-sui--string-or-nil label-right))
        (cons :body (acp-sui--string-or-nil body))))

(cl-defun acp-sui-update-dialog-block (model &key append create-new on-post-process no-navigation expanded)
  "Update or add a dialog block using MODEL.

When APPEND is non-nil, append to body instead of replacing.
When CREATE-NEW is non-nil, create new block.
When ON-POST-PROCESS is non-nil, call this function after updating.
When NO-NAVIGATION is non-nil, block won't be TAB navigatable.
When EXPANDED is non-nil, body will be expanded by default.

For existing blocks, the current expansion state is preserved unless explicitly overridden."
  (require 'map)
  (let* ((namespace-id (map-elt model :namespace-id))
         (block-id (format "%s-%s" namespace-id (map-elt model :block-id)))
         (new-label-left (map-elt model :label-left))
         (new-label-right (map-elt model :label-right))
         (new-body (map-elt model :body)))
    (save-excursion
      (goto-char (point-max))
      (let ((inhibit-read-only t)
            (match (text-property-search-backward 'block-id block-id t)))
        (when match
          (goto-char (prop-match-beginning match)))
        (if (and match (not create-new))
            ;; Found existing block - update it
            (let* ((existing-model (acp-sui--read-dialog-block-at-point))
                   (existing-body (map-elt existing-model :body))
                   (indicator-overlay (seq-find (lambda (ov)
                                                  (overlay-get ov 'acp-sui-indicator))
                                                (overlays-in (prop-match-beginning match)
                                                             (prop-match-end match))))
                   (has-collapsed indicator-overlay)
                   (collapsed (and indicator-overlay
                                   (overlay-get indicator-overlay 'acp-sui-collapsed)))
                   (block-start (prop-match-beginning match))
                   (block-end (prop-match-end match))
                   (final-body (if new-body
                                   (if (and append existing-body)
                                       (concat existing-body new-body)
                                     new-body)
                                 existing-body))
                   (final-model (list (cons :namespace-id namespace-id)
                                      (cons :block-id (map-elt model :block-id))
                                      (cons :label-left (or new-label-left
                                                            (map-elt existing-model :label-left)))
                                      (cons :label-right (or new-label-right
                                                             (map-elt existing-model :label-right)))
                                      (cons :body final-body))))

              ;; Delete and regenerate, preserving collapsed state
              (delete-region block-start block-end)
              (goto-char block-start)
              (acp-sui--insert-dialog-block final-model block-id
                                        (if has-collapsed
                                            (not collapsed)  ; preserve existing state
                                          expanded)        ; use default for new blocks
                                        no-navigation))

          ;; Not found or create-new - insert new block
          (goto-char (point-max))
          (insert (acp-sui--required-newlines 2))
          (let ((insert-model (delq nil
                                    (list (cons :namespace-id namespace-id)
                                          (cons :block-id (map-elt model :block-id))
                                          (when new-label-left (cons :label-left new-label-left))
                                          (when new-label-right (cons :label-right new-label-right))
                                          (when new-body (cons :body new-body))))))
            (acp-sui--insert-dialog-block insert-model block-id expanded no-navigation)
            (insert "\n\n"))))
      (when on-post-process
        (funcall on-post-process)))))

(defun acp-sui--read-dialog-block (block-start block-end block-id)
  "Read dialog block between BLOCK-START and BLOCK-END with BLOCK-ID into a model."
  (let ((namespace-id nil)
        (id nil)
        (label-left nil)
        (label-right nil)
        (body nil)
        (collapsed nil)
        (indicator-overlay nil)
        (body-overlay nil))

    ;; Extract namespace-id from block-id if it contains a dash
    (when (string-match "^\\(.+\\)-\\(.+\\)$" block-id)
      (setq namespace-id (match-string 1 block-id))
      (setq id (match-string 2 block-id)))

    ;; Find relevant overlays
    (let ((overlays (overlays-at block-start)))
      (dolist (ov overlays)
        (when (overlay-get ov 'acp-sui-indicator)
          (setq indicator-overlay ov)
          (setq collapsed (overlay-get ov 'acp-sui-collapsed))
          (setq body-overlay (overlay-get ov 'acp-sui-body-overlay)))))

    (save-excursion
      (goto-char block-start)
      (while (< (point) block-end)
        (let ((next-match (text-property-search-forward 'dialog-section)))
          (if (and next-match
                   (<= (prop-match-beginning next-match) block-end))
              (let ((section-type (prop-match-value next-match))
                    (content (buffer-substring
                              (prop-match-beginning next-match)
                              (prop-match-end next-match))))
                (cond
                 ((eq section-type 'label-left)
                  (setq label-left content))
                 ((eq section-type 'label-right)
                  (setq label-right content))
                 ((eq section-type 'body)
                  (setq body (replace-regexp-in-string "^  " "" content))))
                (goto-char (prop-match-end next-match)))
            (goto-char block-end)))))

    ;; Build alist with only non-nil values
    (delq nil
          (list (when namespace-id (cons :namespace-id namespace-id))
                (when id (cons :block-id id))
                (when label-left (cons :label-left label-left))
                (when label-right (cons :label-right label-right))
                (when body (cons :body body))
                (when (not (null collapsed)) (cons :collapsed collapsed))
                (when indicator-overlay (cons :indicator-overlay indicator-overlay))
                (when body-overlay (cons :body-overlay body-overlay))))))

(defun acp-sui--read-dialog-block-at-point ()
  "Read dialog block at point, returning model or nil if none found."
  (let ((block-id (get-text-property (point) 'block-id)))
    (when block-id
      (let ((block-start (previous-single-property-change (point) 'block-id nil (point-min)))
            (block-end (next-single-property-change (point) 'block-id nil (point-max))))
        (acp-sui--read-dialog-block block-start block-end block-id)))))

(defun acp-sui--insert-dialog-block (model block-id &optional expanded no-navigation)
  "Insert dialog block from MODEL with BLOCK-ID text properties.
EXPANDED determines initial state (default nil for collapsed).
NO-NAVIGATION omits acp-sui-navigatable property to exclude from navigation."
  (require 'map)
  (let ((block-start (point))
        (label-left (map-elt model :label-left))
        (label-right (map-elt model :label-right))
        (body (map-elt model :body))
        (need-space nil)
        (indicator-overlay nil)
        (body-overlay nil)
        (body-start nil))

    ;; Insert collapse indicator if body exists
    (when (and body (or label-left label-right))
      (let ((indicator-start (point)))
        (insert (acp-sui-add-action-to-text
                 "> "
                 (lambda ()
                   (interactive)
                   (acp-sui-toggle-dialog-block-at-point))
                 (lambda ()
                   (message "Press RET to toggle"))))
        (setq indicator-overlay (make-overlay indicator-start (point)))
        (overlay-put indicator-overlay 'acp-sui-indicator t)
        (overlay-put indicator-overlay 'acp-sui-block-id block-id)
        (overlay-put indicator-overlay 'acp-sui-collapsed (not expanded))
        (overlay-put indicator-overlay 'evaporate t)
        (overlay-put indicator-overlay 'keymap (acp-sui-make-action-keymap
                                                (lambda ()
                                                  (interactive)
                                                  (acp-sui-toggle-dialog-block-at-point))))
        (overlay-put indicator-overlay 'display (if expanded "▼ " "▶ "))
        (put-text-property indicator-start (point) 'block-id block-id)
        (put-text-property indicator-start (point) 'read-only t)
        (put-text-property indicator-start (point) 'front-sticky '(read-only))))

    (when label-left
      (let ((start (point)))
        (insert (acp-sui-add-action-to-text
                 label-left
                 (lambda ()
                   (interactive)
                   (acp-sui-toggle-dialog-block-at-point))
                 (lambda ()
                   (message "Press RET to toggle"))))
        (put-text-property start (point) 'dialog-section 'label-left)
        (put-text-property start (point) 'block-id block-id)
        (put-text-property start (point) 'help-echo block-id)
        (put-text-property start (point) 'read-only t)
        (put-text-property start (point) 'front-sticky '(read-only))
        (setq need-space t)))

    (when label-right
      (when need-space (insert " "))
      (let ((start (point)))
        (insert (acp-sui-add-action-to-text
                 label-right
                 (lambda ()
                   (interactive)
                   (acp-sui-toggle-dialog-block-at-point))
                 (lambda ()
                   (message "Press RET to toggle"))))
        (put-text-property start (point) 'dialog-section 'label-right)
        (put-text-property start (point) 'block-id block-id)
        (put-text-property start (point) 'help-echo block-id)
        (put-text-property start (point) 'read-only t)
        (put-text-property start (point) 'front-sticky '(read-only))))

    (when body
      (when (or label-left label-right)
        (setq body-start (point))
        (insert "\n\n"))
      (let ((start (point))
            (end nil)
            ;; Get the face properties from the body string
            (body-face (get-text-property 0 'face body))
            (body-font-lock-face (get-text-property 0 'font-lock-face body)))
        ;; Insert body directly with its properties intact
        (insert body)
        (setq end (point))

        ;; Now indent each line in place
        (save-excursion
          (goto-char start)
          (while (< (point) end)
            (unless (looking-at "^$")  ; Don't indent empty lines
              (let ((indent-start (point)))
                (insert "  ")  ; Two spaces for indentation
                ;; Apply the same face properties to the indent spaces
                (when body-face
                  (put-text-property indent-start (point) 'face body-face))
                (when body-font-lock-face
                  (put-text-property indent-start (point) 'font-lock-face body-font-lock-face))
                (setq end (+ end 2))))  ; Adjust end position for inserted spaces
            (forward-line 1)))

        ;; Add acp-sui-specific properties
        (put-text-property start (point) 'dialog-section 'body)
        (put-text-property start (point) 'block-id block-id)
        (put-text-property start (point) 'help-echo block-id)
        (put-text-property start (point) 'read-only t)
        (put-text-property start (point) 'front-sticky '(read-only))

        ;; Create body overlay and link it to indicator
        (when indicator-overlay
          (setq body-overlay (make-overlay (or body-start start) (point)))
          (overlay-put body-overlay 'evaporate t)
          (unless expanded
            (overlay-put body-overlay 'invisible t))
          (overlay-put indicator-overlay 'acp-sui-body-overlay body-overlay))))

    (put-text-property block-start (point) 'block-id block-id)
    (unless no-navigation
      (put-text-property block-start (point) 'acp-sui-navigatable t))
    (put-text-property block-start (point) 'read-only t)
    (put-text-property block-start (point) 'front-sticky '(read-only))))

(defun acp-sui--required-newlines (desired)
  "Return string of newlines needed to reach DESIRED (max 2) before point."
  (let ((desired (min 2 desired)))
    (make-string
     (cond
      ((looking-back "\n\n" (- (point) 2)) 0)
      ((looking-back "\n" (- (point) 1)) (max 0 (- desired 1)))
      (t desired))
     ?\n)))

(defun acp-sui-toggle-dialog-block-at-point ()
  "Toggle visibility of dialog block body at point."
  (interactive)
  (let ((block-id (get-text-property (point) 'block-id))
        (indicator-overlay nil))
    (when block-id
      ;; Find the block start where the indicator overlay is
      (let ((block-start (previous-single-property-change (point) 'block-id nil (point-min))))
        ;; Look for indicator overlay at block start
        (dolist (ov (overlays-at block-start))
          (when (overlay-get ov 'acp-sui-indicator)
            (setq indicator-overlay ov)))
        (when indicator-overlay
          (let ((body-overlay (overlay-get indicator-overlay 'acp-sui-body-overlay))
                (collapsed (overlay-get indicator-overlay 'acp-sui-collapsed)))
            (when body-overlay
              (if collapsed
                  ;; Expand: show body and change indicator to down arrow
                  (progn
                    (overlay-put body-overlay 'invisible nil)
                    (overlay-put indicator-overlay 'display "▼ ")
                    (overlay-put indicator-overlay 'acp-sui-collapsed nil))
                ;; Collapse: hide body and change indicator to right arrow
                (progn
                  (overlay-put body-overlay 'invisible t)
                  (overlay-put indicator-overlay 'display "▶ ")
                  (overlay-put indicator-overlay 'acp-sui-collapsed t))))))))))

(defun acp-sui-toggle-all-dialog-blocks ()
  "Toggle all dialog blocks based on the state of the last block.
If the last block is collapsed, expand all.  Otherwise, collapse all."
  (interactive)
  ;; First, check if ANY blocks are collapsed
  (let ((any-collapsed nil)
        (any-expanded nil))
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov 'acp-sui-indicator)
        (if (overlay-get ov 'acp-sui-collapsed)
            (setq any-collapsed t)
          (setq any-expanded t))))

    ;; If any are collapsed, expand all. Otherwise collapse all.
    (cond
     (any-collapsed (acp-sui-expand-all-dialog-blocks))
     (any-expanded (acp-sui-collapse-all-dialog-blocks))
     (t (message "No collapsible found")))))

(defun acp-sui-expand-all-dialog-blocks ()
  "Expand all dialog blocks in buffer."
  (interactive)
  (let ((count 0))
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov 'acp-sui-indicator)
        (let ((body-overlay (overlay-get ov 'acp-sui-body-overlay)))
          (when body-overlay
            (when (overlay-get ov 'acp-sui-collapsed)
              (overlay-put body-overlay 'invisible nil)
              (overlay-put ov 'display "▼ ")
              (overlay-put ov 'acp-sui-collapsed nil)
              (setq count (1+ count)))))))))

(defun acp-sui-collapse-all-dialog-blocks ()
  "Collapse all dialog blocks in buffer."
  (interactive)
  (let ((count 0))
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov 'acp-sui-indicator)
        (let ((body-overlay (overlay-get ov 'acp-sui-body-overlay)))
          (when body-overlay
            (unless (overlay-get ov 'acp-sui-collapsed)
              (overlay-put body-overlay 'invisible t)
              (overlay-put ov 'display "▶ ")
              (overlay-put ov 'acp-sui-collapsed t)
              (setq count (1+ count)))))))))

(defun acp-sui-collapse-dialog-block-by-id (namespace-id block-id)
  "Collapse dialog block with NAMESPACE-ID and BLOCK-ID."
  (let ((full-block-id (format "%s-%s" namespace-id block-id)))
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (and (overlay-get ov 'acp-sui-indicator)
                 (string= (overlay-get ov 'acp-sui-block-id) full-block-id))
        (let ((body-overlay (overlay-get ov 'acp-sui-body-overlay)))
          (when (and body-overlay (not (overlay-get ov 'acp-sui-collapsed)))
            (overlay-put body-overlay 'invisible t)
            (overlay-put ov 'display "▶ ")
            (overlay-put ov 'acp-sui-collapsed t)))))))

(defun acp-sui--string-or-nil (str)
  "Return STR if it is not nil and not empty, otherwise nil."
  (and str (not (string-empty-p str)) str))

(defun acp-sui--indent-text (text &optional indent-string)
  "Indent TEXT by adding INDENT-STRING to the beginning of each non-empty line.
INDENT-STRING defaults to two spaces."
  (when text
    (let ((indent (or indent-string "  ")))
      (mapconcat (lambda (line)
                   (if (string-empty-p line)
                       line
                     (concat indent line)))
                 (split-string text "\n")
                 "\n"))))

(defun acp-sui-forward-block ()
  "Jump to the next block."
  (interactive)
  (let ((current-block (and (get-text-property (point) 'acp-sui-navigatable)
                            (get-text-property (point) 'block-id)))
        (start-point (point)))
    ;; If we're in a navigatable block, move past it first
    (when current-block
      (let ((match (text-property-search-forward 'block-id current-block t)))
        (when match
          (goto-char (prop-match-end match)))))
    ;; Now find the next navigatable block
    (let ((next (text-property-search-forward 'acp-sui-navigatable)))
      (if next
          (progn
            (goto-char (prop-match-beginning next))
            ;; Find label-left or label-right within this block
            (let ((block-start (prop-match-beginning next))
                  (block-end (prop-match-end next))
                  (label-left-pos nil)
                  (label-right-pos nil))
              ;; Search forward from block start for label-left and label-right
              (save-excursion
                (goto-char block-start)
                (while (and (< (point) block-end)
                            (not (and label-left-pos label-right-pos)))
                  (when (and (not label-left-pos)
                             (eq (get-text-property (point) 'dialog-section) 'label-left))
                    (setq label-left-pos (point)))
                  (when (and (not label-right-pos)
                             (eq (get-text-property (point) 'dialog-section) 'label-right))
                    (setq label-right-pos (point)))
                  (forward-char)))
              ;; Move to label-left if found, otherwise label-right, otherwise stay at block start
              (goto-char (or label-left-pos label-right-pos block-start))))
        (goto-char start-point)
        (message "No more blocks")))))

(defun acp-sui-backward-block ()
  "Jump to the previous block."
  (interactive)
  (let ((current-block (and (get-text-property (point) 'acp-sui-navigatable)
                            (get-text-property (point) 'block-id)))
        (start-point (point)))
    ;; If we're in a navigatable block, move to its beginning first
    (when current-block
      (let ((match (text-property-search-backward 'block-id current-block t)))
        (when match
          (goto-char (prop-match-beginning match)))))
    ;; Move back one char to get out of current block
    (when (> (point) (point-min))
      (backward-char))
    ;; Now find the previous navigatable block
    (let ((prev (text-property-search-backward 'acp-sui-navigatable)))
      (if prev
          (progn
            (goto-char (prop-match-beginning prev))
            ;; Find label-left or label-right within this block
            (let ((block-start (prop-match-beginning prev))
                  (block-end (prop-match-end prev))
                  (label-left-pos nil)
                  (label-right-pos nil))
              ;; Search forward from block start for label-left and label-right
              (goto-char block-start)
              (while (and (< (point) block-end)
                          (not (and label-left-pos label-right-pos)))
                (when (and (not label-left-pos)
                           (eq (get-text-property (point) 'dialog-section) 'label-left))
                  (setq label-left-pos (point)))
                (when (and (not label-right-pos)
                           (eq (get-text-property (point) 'dialog-section) 'label-right))
                  (setq label-right-pos (point)))
                (forward-char))
              ;; Move to label-left if found, otherwise label-right, otherwise stay at block start
              (goto-char (or label-left-pos label-right-pos block-start))))
        (goto-char start-point)
        (message "No previous blocks")))))

(defun acp-sui-make-action-keymap (action)
  "Create keymap with ACTION."
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] action)
    (define-key map (kbd "RET") action)
    (define-key map [remap self-insert-command] 'ignore)
    map))

(defun acp-sui-add-action-to-text (text action &optional on-entered)
  "Add ACTION lambda to propertized TEXT and return modified text.
ON-ENTERED is a function to call when the cursor enters the text."
  (add-text-properties 0 (length text)
                       `(keymap ,(acp-sui-make-action-keymap action))
                       text)
  (when on-entered
    (add-text-properties 0 (length text)
                         (list 'cursor-sensor-functions
                               (list (lambda (window old-pos sensor-action)
                                       (when (eq sensor-action 'entered)
                                         (funcall on-entered)))))
                         text))
  text)

(defvar acp-sui-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB") #'acp-sui-forward-block)
    (define-key map (kbd "<tab>") #'acp-sui-forward-block)
    (define-key map (kbd "<backtab>") #'acp-sui-backward-block)
    (define-key map (kbd "S-TAB") #'acp-sui-backward-block)
    map)
  "Keymap for `acp-sui-mode'.")

;;;###autoload
(define-minor-mode acp-sui-mode
  "Minor mode for SUI block navigation."
  :lighter " SUI"
  :keymap acp-sui-mode-map
  (if acp-sui-mode
      (cursor-sensor-mode 1)
    (cursor-sensor-mode -1)))

(provide 'acp-sui)

;;; acp-sui.el ends here

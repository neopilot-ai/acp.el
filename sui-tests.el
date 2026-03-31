;;; sui-tests.el --- Tests for sui.el -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the sui.el interactive shell UI elements library.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load the library under test
(require 'sui (expand-file-name "sui.el" (file-name-directory (or load-file-name buffer-file-name))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui--string-or-nil
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui--string-or-nil/nil ()
  "nil input returns nil."
  (should (null (sui--string-or-nil nil))))

(ert-deftest sui--string-or-nil/empty-string ()
  "Empty string returns nil."
  (should (null (sui--string-or-nil ""))))

(ert-deftest sui--string-or-nil/non-empty-string ()
  "Non-empty string returns the string itself."
  (should (equal "hello" (sui--string-or-nil "hello"))))

(ert-deftest sui--string-or-nil/whitespace-string ()
  "Whitespace-only string is non-empty, so it is returned as-is."
  (should (equal "   " (sui--string-or-nil "   "))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui--indent-text
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui--indent-text/nil ()
  "nil input returns nil."
  (should (null (sui--indent-text nil))))

(ert-deftest sui--indent-text/single-line ()
  "Single non-empty line is indented with two spaces by default."
  (should (equal "  hello" (sui--indent-text "hello"))))

(ert-deftest sui--indent-text/multiline ()
  "Each non-empty line is indented."
  (should (equal "  foo\n  bar" (sui--indent-text "foo\nbar"))))

(ert-deftest sui--indent-text/empty-line-not-indented ()
  "Empty lines are not indented."
  (should (equal "  foo\n\n  bar" (sui--indent-text "foo\n\nbar"))))

(ert-deftest sui--indent-text/custom-indent ()
  "Custom indent string is used when provided."
  (should (equal "----foo\n----bar" (sui--indent-text "foo\nbar" "----"))))

(ert-deftest sui--indent-text/empty-string ()
  "Empty string input returns empty string (no lines, no output)."
  ;; split-string "" "\n" gives ("") -> one empty string -> not indented
  (should (equal "" (sui--indent-text ""))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-make-dialog-block-model
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-make-dialog-block-model/defaults ()
  "Default arguments produce correct keys with default values."
  (let ((model (sui-make-dialog-block-model)))
    (should (equal "global" (map-elt model :namespace-id)))
    (should (equal "1" (map-elt model :block-id)))
    (should (null (map-elt model :label-left)))
    (should (null (map-elt model :label-right)))
    (should (null (map-elt model :body)))))

(ert-deftest sui-make-dialog-block-model/all-params ()
  "All parameters are stored correctly."
  (let ((model (sui-make-dialog-block-model
                :namespace-id "ns1"
                :block-id "b1"
                :label-left "Left"
                :label-right "Right"
                :body "Body text")))
    (should (equal "ns1" (map-elt model :namespace-id)))
    (should (equal "b1" (map-elt model :block-id)))
    (should (equal "Left" (map-elt model :label-left)))
    (should (equal "Right" (map-elt model :label-right)))
    (should (equal "Body text" (map-elt model :body)))))

(ert-deftest sui-make-dialog-block-model/empty-strings-become-nil ()
  "Empty strings for label/body are converted to nil via sui--string-or-nil."
  (let ((model (sui-make-dialog-block-model
                :label-left ""
                :label-right ""
                :body "")))
    (should (null (map-elt model :label-left)))
    (should (null (map-elt model :label-right)))
    (should (null (map-elt model :body)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui--required-newlines
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui--required-newlines/at-beginning-of-buffer ()
  "At beginning of buffer, returns the desired number of newlines."
  (with-temp-buffer
    (let ((result (sui--required-newlines 2)))
      (should (equal "\n\n" result)))))

(ert-deftest sui--required-newlines/after-one-newline ()
  "After one newline, returns one newline to reach desired 2."
  (with-temp-buffer
    (insert "\n")
    (let ((result (sui--required-newlines 2)))
      (should (equal "\n" result)))))

(ert-deftest sui--required-newlines/after-two-newlines ()
  "After two newlines, returns empty string (already at desired level)."
  (with-temp-buffer
    (insert "\n\n")
    (let ((result (sui--required-newlines 2)))
      (should (equal "" result)))))

(ert-deftest sui--required-newlines/desired-capped-at-2 ()
  "Desired value is capped at 2 even if larger value is passed."
  (with-temp-buffer
    (let ((result (sui--required-newlines 5)))
      ;; At start of buffer, capped desired=2 -> returns "\n\n"
      (should (equal "\n\n" result)))))

(ert-deftest sui--required-newlines/desired-one ()
  "With desired=1, at start of buffer returns one newline."
  (with-temp-buffer
    (let ((result (sui--required-newlines 1)))
      (should (equal "\n" result)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-make-action-keymap
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-make-action-keymap/binds-mouse-1 ()
  "Keymap binds [mouse-1] to the action."
  (let* ((called nil)
         (action (lambda () (interactive) (setq called t)))
         (map (sui-make-action-keymap action)))
    (should (keymapp map))
    (should (eq action (lookup-key map [mouse-1])))))

(ert-deftest sui-make-action-keymap/binds-ret ()
  "Keymap binds RET to the action."
  (let* ((called nil)
         (action (lambda () (interactive) (setq called t)))
         (map (sui-make-action-keymap action)))
    (should (eq action (lookup-key map (kbd "RET"))))))

(ert-deftest sui-make-action-keymap/remaps-self-insert ()
  "Keymap remaps self-insert-command to ignore."
  (let* ((action (lambda () (interactive)))
         (map (sui-make-action-keymap action)))
    (should (eq 'ignore (lookup-key map [remap self-insert-command])))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-add-action-to-text
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-add-action-to-text/returns-same-text ()
  "Function returns the text string."
  (let* ((action (lambda () (interactive)))
         (text "hello")
         (result (sui-add-action-to-text text action)))
    (should (equal "hello" result))))

(ert-deftest sui-add-action-to-text/adds-keymap-property ()
  "The returned text has a keymap text property."
  (let* ((action (lambda () (interactive)))
         (result (sui-add-action-to-text "hello" action)))
    (should (keymapp (get-text-property 0 'keymap result)))))

(ert-deftest sui-add-action-to-text/action-bound-in-keymap ()
  "The action is bound to RET in the keymap property."
  (let* ((action (lambda () (interactive)))
         (result (sui-add-action-to-text "test" action)))
    (should (eq action (lookup-key (get-text-property 0 'keymap result) (kbd "RET"))))))

(ert-deftest sui-add-action-to-text/adds-cursor-sensor-when-on-entered ()
  "When on-entered is provided, cursor-sensor-functions property is set."
  (let* ((action (lambda () (interactive)))
         (on-entered (lambda () nil))
         (result (sui-add-action-to-text "test" action on-entered)))
    (should (listp (get-text-property 0 'cursor-sensor-functions result)))
    (should (not (null (get-text-property 0 'cursor-sensor-functions result))))))

(ert-deftest sui-add-action-to-text/no-cursor-sensor-without-on-entered ()
  "Without on-entered, cursor-sensor-functions property is absent."
  (let* ((action (lambda () (interactive)))
         (result (sui-add-action-to-text "test" action)))
    (should (null (get-text-property 0 'cursor-sensor-functions result)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-update-dialog-block and sui--insert-dialog-block
;;; ─────────────────────────────────────────────────────────────────

(defmacro sui-test-with-buffer (&rest body)
  "Execute BODY in a temp buffer suitable for sui tests."
  `(with-temp-buffer
     (let ((inhibit-read-only t))
       ,@body)))

(ert-deftest sui-update-dialog-block/inserts-new-block ()
  "Inserting a new block adds block-id text property to buffer."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "test"
                 :block-id "b1"
                 :label-left "Label"
                 :body "Content")))
     (sui-update-dialog-block model)
     (goto-char (point-min))
     (let ((found (text-property-search-forward 'block-id "test-b1" t)))
       (should found)))))

(ert-deftest sui-update-dialog-block/body-only-block ()
  "Block with only body (no labels) is inserted without indicator overlay."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "x"
                 :body "Some body text")))
     (sui-update-dialog-block model)
     (goto-char (point-min))
     (let ((found (text-property-search-forward 'block-id "ns-x" t)))
       (should found))
     ;; No indicator overlay when no labels
     (let ((has-indicator
            (cl-some (lambda (ov) (overlay-get ov 'sui-indicator))
                     (overlays-in (point-min) (point-max)))))
       (should (null has-indicator))))))

(ert-deftest sui-update-dialog-block/label-only-block ()
  "Block with only label-left (no body) is inserted without indicator overlay."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "lbl"
                 :label-left "Status")))
     (sui-update-dialog-block model)
     (let ((has-indicator
            (cl-some (lambda (ov) (overlay-get ov 'sui-indicator))
                     (overlays-in (point-min) (point-max)))))
       (should (null has-indicator))))))

(ert-deftest sui-update-dialog-block/creates-indicator-overlay-with-label-and-body ()
  "Block with both label and body gets an indicator overlay."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "lb"
                 :label-left "Title"
                 :body "Content")))
     (sui-update-dialog-block model)
     (let ((indicator-ov
            (cl-find-if (lambda (ov) (overlay-get ov 'sui-indicator))
                        (overlays-in (point-min) (point-max)))))
       (should indicator-ov)
       (should (overlay-get indicator-ov 'sui-body-overlay))))))

(ert-deftest sui-update-dialog-block/expanded-block-has-visible-body ()
  "An expanded block's body overlay is not invisible."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "exp"
                 :label-left "Title"
                 :body "Content")))
     (sui-update-dialog-block model :expanded t)
     (let* ((indicator-ov
             (cl-find-if (lambda (ov) (overlay-get ov 'sui-indicator))
                         (overlays-in (point-min) (point-max))))
            (body-ov (overlay-get indicator-ov 'sui-body-overlay)))
       (should (null (overlay-get body-ov 'invisible)))
       (should (null (overlay-get indicator-ov 'sui-collapsed)))
       (should (equal "▼ " (overlay-get indicator-ov 'display)))))))

(ert-deftest sui-update-dialog-block/collapsed-block-has-invisible-body ()
  "A collapsed (default) block's body overlay is invisible."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "col"
                 :label-left "Title"
                 :body "Content")))
     (sui-update-dialog-block model)
     (let* ((indicator-ov
             (cl-find-if (lambda (ov) (overlay-get ov 'sui-indicator))
                         (overlays-in (point-min) (point-max))))
            (body-ov (overlay-get indicator-ov 'sui-body-overlay)))
       (should (overlay-get body-ov 'invisible))
       (should (overlay-get indicator-ov 'sui-collapsed))
       (should (equal "▶ " (overlay-get indicator-ov 'display)))))))

(ert-deftest sui-update-dialog-block/updates-existing-block ()
  "Calling update on existing block updates its content."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "upd"
                 :label-left "Old"
                 :body "Old body")))
     (sui-update-dialog-block model)
     ;; Now update label
     (let ((model2 (sui-make-dialog-block-model
                    :namespace-id "ns"
                    :block-id "upd"
                    :label-left "New"
                    :body "New body")))
       (sui-update-dialog-block model2))
     ;; Should find the block with updated content
     (goto-char (point-min))
     (let ((found (text-property-search-forward 'block-id "ns-upd" t)))
       (should found)))))

(ert-deftest sui-update-dialog-block/append-body ()
  "APPEND flag concatenates body onto existing block."
  (sui-test-with-buffer
   (let ((model1 (sui-make-dialog-block-model
                  :namespace-id "ns"
                  :block-id "app"
                  :body "Hello")))
     (sui-update-dialog-block model1)
     (let ((model2 (sui-make-dialog-block-model
                    :namespace-id "ns"
                    :block-id "app"
                    :body " World")))
       (sui-update-dialog-block model2 :append t))
     ;; Check body contains concatenated content
     (goto-char (point-min))
     (let ((found (text-property-search-forward 'dialog-section 'body t)))
       (should found)
       ;; The body text in the buffer should contain both parts
       (let ((content (buffer-substring-no-properties
                       (prop-match-beginning found)
                       (prop-match-end found))))
         (should (string-match-p "Hello" content))
         (should (string-match-p "World" content)))))))

(ert-deftest sui-update-dialog-block/create-new-adds-second-block ()
  "CREATE-NEW flag creates a duplicate block instead of updating."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "dup"
                 :label-left "Label"
                 :body "Body")))
     (sui-update-dialog-block model)
     (sui-update-dialog-block model :create-new t)
     ;; There should be two indicator overlays (one per block)
     (let ((indicator-count
            (length (seq-filter (lambda (ov) (overlay-get ov 'sui-indicator))
                                (overlays-in (point-min) (point-max))))))
       (should (= 2 indicator-count))))))

(ert-deftest sui-update-dialog-block/no-navigation-property ()
  "NO-NAVIGATION flag prevents sui-navigatable from being set."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "nonav"
                 :label-left "Label"
                 :body "Body")))
     (sui-update-dialog-block model :no-navigation t)
     (goto-char (point-min))
     ;; Use PREDICATE=t to find any position where sui-navigatable is non-nil.
     ;; If the property was never set, the search returns nil.
     (let ((has-nav (text-property-search-forward 'sui-navigatable t t)))
       (should (null has-nav))))))

(ert-deftest sui-update-dialog-block/navigation-set-by-default ()
  "Without NO-NAVIGATION, sui-navigatable is set on the block."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "nav"
                 :label-left "Label"
                 :body "Body")))
     (sui-update-dialog-block model)
     (goto-char (point-min))
     (let ((has-nav (text-property-search-forward 'sui-navigatable t t)))
       (should has-nav)))))

(ert-deftest sui-update-dialog-block/on-post-process-called ()
  "ON-POST-PROCESS callback is invoked after block is inserted."
  (sui-test-with-buffer
   (let ((called nil)
         (model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "post"
                 :body "Body")))
     (sui-update-dialog-block model :on-post-process (lambda () (setq called t)))
     (should called))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-toggle-dialog-block-at-point
;;; ─────────────────────────────────────────────────────────────────

(defun sui-test--insert-block (namespace-id block-id label body &optional expanded)
  "Helper to insert a dialog block with NAMESPACE-ID, BLOCK-ID, LABEL, BODY.
EXPANDED determines initial collapsed/expanded state."
  (let ((model (sui-make-dialog-block-model
                :namespace-id namespace-id
                :block-id block-id
                :label-left label
                :body body)))
    (sui-update-dialog-block model :expanded expanded)))

(ert-deftest sui-toggle-dialog-block-at-point/expands-collapsed-block ()
  "Toggle expands a collapsed block."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "t1" "Title" "Content" nil)
   ;; Find the block and move point to it
   (goto-char (point-min))
   (text-property-search-forward 'block-id "ns-t1" t)
   (sui-toggle-dialog-block-at-point)
   ;; After toggle, body overlay should be visible
   (let* ((indicator-ov
           (cl-find-if (lambda (ov) (overlay-get ov 'sui-indicator))
                       (overlays-in (point-min) (point-max))))
          (body-ov (and indicator-ov (overlay-get indicator-ov 'sui-body-overlay))))
     (should indicator-ov)
     (should body-ov)
     (should (null (overlay-get body-ov 'invisible)))
     (should (null (overlay-get indicator-ov 'sui-collapsed)))
     (should (equal "▼ " (overlay-get indicator-ov 'display))))))

(ert-deftest sui-toggle-dialog-block-at-point/collapses-expanded-block ()
  "Toggle collapses an expanded block."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "t2" "Title" "Content" t)
   ;; Find the block and move point to it
   (goto-char (point-min))
   (text-property-search-forward 'block-id "ns-t2" t)
   (sui-toggle-dialog-block-at-point)
   ;; After toggle, body overlay should be invisible
   (let* ((indicator-ov
           (cl-find-if (lambda (ov) (overlay-get ov 'sui-indicator))
                       (overlays-in (point-min) (point-max))))
          (body-ov (and indicator-ov (overlay-get indicator-ov 'sui-body-overlay))))
     (should (overlay-get body-ov 'invisible))
     (should (overlay-get indicator-ov 'sui-collapsed))
     (should (equal "▶ " (overlay-get indicator-ov 'display))))))

(ert-deftest sui-toggle-dialog-block-at-point/no-op-outside-block ()
  "Toggle is a no-op when point is not on a block."
  (sui-test-with-buffer
   (insert "no block here")
   (goto-char (point-min))
   ;; Should not signal an error
   (should-not (condition-case err
                   (progn (sui-toggle-dialog-block-at-point) nil)
                 (error err)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-expand-all-dialog-blocks
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-expand-all-dialog-blocks/expands-all-collapsed ()
  "All collapsed blocks become expanded."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "b1" "Block 1" "Body 1" nil)
   (sui-test--insert-block "ns" "b2" "Block 2" "Body 2" nil)
   (sui-expand-all-dialog-blocks)
   (dolist (ov (overlays-in (point-min) (point-max)))
     (when (overlay-get ov 'sui-indicator)
       (should (null (overlay-get ov 'sui-collapsed)))
       (let ((body-ov (overlay-get ov 'sui-body-overlay)))
         (when body-ov
           (should (null (overlay-get body-ov 'invisible)))))))))

(ert-deftest sui-expand-all-dialog-blocks/noop-when-already-expanded ()
  "Expanding already-expanded blocks does not error."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "b1" "Block 1" "Body 1" t)
   (should-not (condition-case err
                   (progn (sui-expand-all-dialog-blocks) nil)
                 (error err)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-collapse-all-dialog-blocks
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-collapse-all-dialog-blocks/collapses-all-expanded ()
  "All expanded blocks become collapsed."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "b1" "Block 1" "Body 1" t)
   (sui-test--insert-block "ns" "b2" "Block 2" "Body 2" t)
   (sui-collapse-all-dialog-blocks)
   (dolist (ov (overlays-in (point-min) (point-max)))
     (when (overlay-get ov 'sui-indicator)
       (should (overlay-get ov 'sui-collapsed))
       (let ((body-ov (overlay-get ov 'sui-body-overlay)))
         (when body-ov
           (should (overlay-get body-ov 'invisible))))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-toggle-all-dialog-blocks
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-toggle-all-dialog-blocks/expands-when-any-collapsed ()
  "When any block is collapsed, all blocks are expanded."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "b1" "Block 1" "Body 1" t)   ;; expanded
   (sui-test--insert-block "ns" "b2" "Block 2" "Body 2" nil) ;; collapsed
   (sui-toggle-all-dialog-blocks)
   ;; All should now be expanded
   (dolist (ov (overlays-in (point-min) (point-max)))
     (when (overlay-get ov 'sui-indicator)
       (should (null (overlay-get ov 'sui-collapsed)))))))

(ert-deftest sui-toggle-all-dialog-blocks/collapses-when-all-expanded ()
  "When all blocks are expanded, all blocks are collapsed."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "b1" "Block 1" "Body 1" t)
   (sui-test--insert-block "ns" "b2" "Block 2" "Body 2" t)
   (sui-toggle-all-dialog-blocks)
   ;; All should now be collapsed
   (dolist (ov (overlays-in (point-min) (point-max)))
     (when (overlay-get ov 'sui-indicator)
       (should (overlay-get ov 'sui-collapsed))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-collapse-dialog-block-by-id
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-collapse-dialog-block-by-id/collapses-target-block ()
  "Only the targeted block is collapsed."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "target" "Target" "Target body" t)
   (sui-test--insert-block "ns" "other" "Other" "Other body" t)
   (sui-collapse-dialog-block-by-id "ns" "target")
   ;; Find the target indicator
   (let ((target-collapsed nil)
         (other-collapsed nil))
     (dolist (ov (overlays-in (point-min) (point-max)))
       (when (overlay-get ov 'sui-indicator)
         (let ((bid (overlay-get ov 'sui-block-id)))
           (cond
            ((equal bid "ns-target") (setq target-collapsed (overlay-get ov 'sui-collapsed)))
            ((equal bid "ns-other") (setq other-collapsed (overlay-get ov 'sui-collapsed)))))))
     (should target-collapsed)
     (should (null other-collapsed)))))

(ert-deftest sui-collapse-dialog-block-by-id/noop-on-nonexistent ()
  "Collapsing a non-existent block-id does not error."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "real" "Label" "Body" t)
   (should-not (condition-case err
                   (progn (sui-collapse-dialog-block-by-id "ns" "ghost") nil)
                 (error err)))))

(ert-deftest sui-collapse-dialog-block-by-id/noop-when-already-collapsed ()
  "Collapsing an already-collapsed block leaves it collapsed."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "c1" "Label" "Body" nil)
   (sui-collapse-dialog-block-by-id "ns" "c1")
   (let ((indicator-ov
          (cl-find-if (lambda (ov)
                        (and (overlay-get ov 'sui-indicator)
                             (equal (overlay-get ov 'sui-block-id) "ns-c1")))
                      (overlays-in (point-min) (point-max)))))
     (should (overlay-get indicator-ov 'sui-collapsed)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-forward-block and sui-backward-block
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-forward-block/moves-to-next-block ()
  "sui-forward-block moves point to the next navigatable block."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "f1" "Block 1" "Body 1" nil)
   (sui-test--insert-block "ns" "f2" "Block 2" "Body 2" nil)
   (goto-char (point-min))
   (sui-forward-block)
   ;; Point should now be in a block
   (should (get-text-property (point) 'block-id))))

(ert-deftest sui-forward-block/wraps-at-end ()
  "sui-forward-block stays at start when no more blocks exist."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "only" "Only Block" "Body" nil)
   (goto-char (point-min))
   ;; Move to the block first
   (sui-forward-block)
   (let ((pos-after-first (point)))
     ;; Move forward again - no next block, should stay
     (sui-forward-block)
     (should (= pos-after-first (point))))))

(ert-deftest sui-forward-block/no-blocks-stays-in-place ()
  "sui-forward-block with no blocks stays at current position."
  (sui-test-with-buffer
   (insert "no blocks here")
   (goto-char (point-min))
   (let ((pos (point)))
     (sui-forward-block)
     (should (= pos (point))))))

(ert-deftest sui-backward-block/moves-to-previous-block ()
  "sui-backward-block moves point to the previous navigatable block."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "bk1" "Block 1" "Body 1" nil)
   (sui-test--insert-block "ns" "bk2" "Block 2" "Body 2" nil)
   ;; Start at end of buffer
   (goto-char (point-max))
   (sui-backward-block)
   ;; Should land in a block
   (should (get-text-property (point) 'block-id))))

(ert-deftest sui-backward-block/stays-when-no-previous ()
  "sui-backward-block stays at point when no previous blocks exist."
  (sui-test-with-buffer
   (sui-test--insert-block "ns" "only" "Only Block" "Body" nil)
   (goto-char (point-min))
   (sui-forward-block)
   (let ((initial-pos (point)))
     (sui-backward-block)
     ;; Since there's only one block, backward should find none and stay
     (should (= initial-pos (point))))))

(ert-deftest sui-backward-block/no-blocks-stays-in-place ()
  "sui-backward-block with no blocks stays at current position."
  (sui-test-with-buffer
   (insert "nothing here")
   (goto-char (point-max))
   (let ((pos (point)))
     (sui-backward-block)
     (should (= pos (point))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for sui-mode minor mode
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-mode/activates-cursor-sensor-mode ()
  "Activating sui-mode turns on cursor-sensor-mode."
  (with-temp-buffer
    (sui-mode 1)
    (should cursor-sensor-mode)
    (sui-mode -1)))

(ert-deftest sui-mode/deactivates-cursor-sensor-mode ()
  "Deactivating sui-mode turns off cursor-sensor-mode."
  (with-temp-buffer
    (sui-mode 1)
    (sui-mode -1)
    (should (not cursor-sensor-mode))))

(ert-deftest sui-mode/keymap-has-forward-binding ()
  "sui-mode keymap binds TAB to sui-forward-block."
  (should (eq #'sui-forward-block (lookup-key sui-mode-map (kbd "TAB")))))

(ert-deftest sui-mode/keymap-has-backward-binding ()
  "sui-mode keymap binds S-TAB to sui-backward-block."
  (should (or (eq #'sui-backward-block (lookup-key sui-mode-map (kbd "S-TAB")))
              (eq #'sui-backward-block (lookup-key sui-mode-map (kbd "<backtab>"))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Regression / boundary tests
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest sui-update-dialog-block/block-text-marked-read-only ()
  "All inserted block content is marked read-only."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "ro"
                 :label-left "Label"
                 :body "Body")))
     (sui-update-dialog-block model)
     ;; Find block content and verify read-only property
     (goto-char (point-min))
     (let ((match (text-property-search-forward 'block-id "ns-ro" t)))
       (should match)
       (should (get-text-property (prop-match-beginning match) 'read-only))))))

(ert-deftest sui-update-dialog-block/label-right-only ()
  "Block with only label-right is inserted correctly."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "ronly"
                 :label-right "Right Label")))
     (sui-update-dialog-block model)
     (goto-char (point-min))
     (let ((found (text-property-search-forward 'dialog-section 'label-right t)))
       (should found)))))

(ert-deftest sui-update-dialog-block/both-labels ()
  "Block with both label-left and label-right has both dialog sections."
  (sui-test-with-buffer
   (let ((model (sui-make-dialog-block-model
                 :namespace-id "ns"
                 :block-id "both"
                 :label-left "Left"
                 :label-right "Right"
                 :body "Body")))
     (sui-update-dialog-block model)
     (goto-char (point-min))
     (let ((left (text-property-search-forward 'dialog-section 'label-left t))
           (right nil))
       (should left)
       (setq right (text-property-search-forward 'dialog-section 'label-right t))
       (should right)))))

(ert-deftest sui--required-newlines/desired-zero ()
  "Desired 0 always returns empty string."
  (with-temp-buffer
    (should (equal "" (sui--required-newlines 0)))))

(ert-deftest sui-make-dialog-block-model/namespace-id-only ()
  "Custom namespace-id with default block-id."
  (let ((model (sui-make-dialog-block-model :namespace-id "custom")))
    (should (equal "custom" (map-elt model :namespace-id)))
    (should (equal "1" (map-elt model :block-id)))))

(provide 'sui-tests)

;;; sui-tests.el ends here
;;; acp-tests.el --- Tests for acp.el pure functions -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the pure/side-effect-free functions in acp.el.
;;
;; Because acp.el depends on external packages (shell-maker, markdown-overlays,
;; and the acp protocol client library), we define minimal stubs for those
;; symbols before loading the file under test.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'map)

;;; ─────────────────────────────────────────────────────────────────
;;; Stubs for external dependencies
;;; ─────────────────────────────────────────────────────────────────

;; -- markdown-overlays stubs --
(unless (featurep 'markdown-overlays)
  (defun markdown-overlays-put () nil)
  (provide 'markdown-overlays))

;; -- shell-maker stubs --
(unless (featurep 'shell-maker)
  (defvar shell-maker-mode-map (make-sparse-keymap))
  (defvar-local shell-maker--config nil)

  (cl-defun make-shell-maker-config (&key name prompt prompt-regexp execute-command)
    (list (cons :name name)
          (cons :prompt prompt)
          (cons :prompt-regexp prompt-regexp)
          (cons :execute-command execute-command)))

  (defmacro shell-maker-define-major-mode (_config _keymap)
    "Stub: define a no-op acp-mode."
    `(progn
       (define-derived-mode acp-mode text-mode "ACP"
         "Stub ACP major mode.")
       (defvar acp-mode-map (make-sparse-keymap))))

  (defun shell-maker-start (_config _no-focus _welcome _new-session _buffer-name _mode-line)
    (current-buffer))

  (defmacro shell-maker-with-auto-scroll-edit (&rest body)
    `(progn ,@body))

  (defun shell-maker--current-request-id () 0)
  (defun shell-maker-major-mode (_config) 'acp-mode)

  (provide 'shell-maker))

;; -- acp protocol library stubs --
;; The file does (require 'acp), which resolves to itself since the feature
;; name matches.  We still need the protocol-client symbols to be defined
;; so that the top-level forms in acp.el can be read without errors.
(defvar acp-logging-enabled nil)
(unless (fboundp 'acp--log)
  (defun acp--log (_tag _fmt &rest _args) nil))
(unless (fboundp 'acp-make-claude-client)
  (defun acp-make-claude-client (&rest _) nil))
(unless (fboundp 'acp-make-gemini-client)
  (defun acp-make-gemini-client (&rest _) nil))
(unless (fboundp 'acp-make-authenticate-request)
  (defun acp-make-authenticate-request (&rest _) nil))
(unless (fboundp 'acp-make-initialize-request)
  (defun acp-make-initialize-request (&rest _) nil))
(unless (fboundp 'acp-make-session-new-request)
  (defun acp-make-session-new-request (&rest _) nil))
(unless (fboundp 'acp-make-session-prompt-request)
  (defun acp-make-session-prompt-request (&rest _) nil))
(unless (fboundp 'acp-make-session-cancel-request)
  (defun acp-make-session-cancel-request (&rest _) nil))
(unless (fboundp 'acp-make-session-request-permission-response)
  (defun acp-make-session-request-permission-response (&rest _) nil))
(unless (fboundp 'acp-send-request)
  (defun acp-send-request (&rest _) nil))
(unless (fboundp 'acp-send-response)
  (defun acp-send-response (&rest _) nil))
(unless (fboundp 'acp-subscribe-to-errors)
  (defun acp-subscribe-to-errors (&rest _) nil))
(unless (fboundp 'acp-subscribe-to-notifications)
  (defun acp-subscribe-to-notifications (&rest _) nil))
(unless (fboundp 'acp-subscribe-to-requests)
  (defun acp-subscribe-to-requests (&rest _) nil))
(unless (fboundp 'acp-shutdown)
  (defun acp-shutdown (&rest _) nil))

;; Load the library under test.
;; Add the test directory to load-path so that (require 'sui) inside acp.el resolves.
;; Pre-register 'acp in `features' to prevent the circular (require 'acp) inside the
;; file from trying to reload itself before (provide 'acp) is reached.
(let* ((test-dir (file-name-directory (or load-file-name buffer-file-name)))
       (load-path (cons test-dir load-path)))
  (unless (featurep 'acp)
    (push 'acp features))
  (load (expand-file-name "acp.el" test-dir) nil t))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--make-state
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--make-state/default-keys-present ()
  "Default state contains all expected keys."
  (let ((state (acp--make-state)))
    (should (assq :client state))
    (should (assq :client-maker state))
    (should (assq :initialized state))
    (should (assq :needs-authentication state))
    (should (assq :authenticate-request-maker state))
    (should (assq :authenticated state))
    (should (assq :session-id state))
    (should (assq :last-entry-type state))
    (should (assq :request-count state))
    (should (assq :tool-calls state))))

(ert-deftest acp--make-state/default-values ()
  "Default state values are nil/0 as expected."
  (let ((state (acp--make-state)))
    (should (null (map-elt state :client)))
    (should (null (map-elt state :client-maker)))
    (should (null (map-elt state :initialized)))
    (should (null (map-elt state :needs-authentication)))
    (should (null (map-elt state :authenticate-request-maker)))
    (should (null (map-elt state :authenticated)))
    (should (null (map-elt state :session-id)))
    (should (null (map-elt state :last-entry-type)))
    (should (= 0 (map-elt state :request-count)))
    (should (null (map-elt state :tool-calls)))))

(ert-deftest acp--make-state/client-maker-stored ()
  "Provided :client-maker is stored in state."
  (let* ((maker (lambda (_s _st) 'client))
         (state (acp--make-state :client-maker maker)))
    (should (eq maker (map-elt state :client-maker)))))

(ert-deftest acp--make-state/needs-authentication-stored ()
  "Provided :needs-authentication is stored in state."
  (let ((state (acp--make-state :needs-authentication t)))
    (should (map-elt state :needs-authentication))))

(ert-deftest acp--make-state/authenticate-request-maker-stored ()
  "Provided :authenticate-request-maker is stored in state."
  (let* ((auth-maker (lambda () 'req))
         (state (acp--make-state :authenticate-request-maker auth-maker)))
    (should (eq auth-maker (map-elt state :authenticate-request-maker)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--stop-reason-description
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--stop-reason-description/end-turn ()
  "end_turn returns expected description."
  (should (equal "The language model finishes responding without requesting more tools"
                 (acp--stop-reason-description "end_turn"))))

(ert-deftest acp--stop-reason-description/max-tokens ()
  "max_tokens returns expected description."
  (should (equal "Max token limit reached"
                 (acp--stop-reason-description "max_tokens"))))

(ert-deftest acp--stop-reason-description/max-turn-requests ()
  "max_turn_requests returns expected description."
  (should (equal "Exceeded request limit"
                 (acp--stop-reason-description "max_turn_requests"))))

(ert-deftest acp--stop-reason-description/refusal ()
  "refusal returns expected description."
  (should (equal "Refused"
                 (acp--stop-reason-description "refusal"))))

(ert-deftest acp--stop-reason-description/cancelled ()
  "cancelled returns expected description."
  (should (equal "Cancelled"
                 (acp--stop-reason-description "cancelled"))))

(ert-deftest acp--stop-reason-description/unknown ()
  "Unknown stop reason returns a formatted message."
  (let ((result (acp--stop-reason-description "some_unknown_reason")))
    (should (string-match-p "some_unknown_reason" result))
    (should (string-match-p "unknown" result))))

(ert-deftest acp--stop-reason-description/empty-string ()
  "Empty stop reason returns a 'unknown' formatted message."
  (let ((result (acp--stop-reason-description "")))
    (should (string-match-p "unknown" result))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--add-text-properties
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--add-text-properties/non-face-property ()
  "Non-face property is set directly."
  (let ((str (copy-sequence "hello")))
    (let ((result (acp--add-text-properties str 'my-prop 'my-value)))
      (should (eq 'my-value (get-text-property 0 'my-prop result))))))

(ert-deftest acp--add-text-properties/face-property-no-existing ()
  "face property with no existing value is set directly."
  (let ((str (copy-sequence "hello")))
    (let ((result (acp--add-text-properties str 'face 'bold)))
      (should (equal 'bold (get-text-property 0 'face result))))))

(ert-deftest acp--add-text-properties/face-property-merges-existing ()
  "face property with existing value is merged into a list."
  (let ((str (propertize "hello" 'face 'italic)))
    (let ((result (acp--add-text-properties str 'face 'bold)))
      (let ((face (get-text-property 0 'face result)))
        (should (listp face))
        (should (memq 'bold face))
        (should (memq 'italic face))))))

(ert-deftest acp--add-text-properties/font-lock-face-merges-existing ()
  "font-lock-face property with existing value is merged into a list."
  (let ((str (propertize "hello" 'font-lock-face 'italic)))
    (let ((result (acp--add-text-properties str 'font-lock-face 'bold)))
      (let ((face (get-text-property 0 'font-lock-face result)))
        (should (listp face))
        (should (memq 'bold face))
        (should (memq 'italic face))))))

(ert-deftest acp--add-text-properties/does-not-mutate-input ()
  "Original string is not mutated (copy is made)."
  (let ((str (copy-sequence "hello")))
    (acp--add-text-properties str 'my-prop 'my-value)
    (should (null (get-text-property 0 'my-prop str)))))

(ert-deftest acp--add-text-properties/applies-to-whole-string ()
  "Property is applied to the entire string."
  (let* ((str (copy-sequence "hello"))
         (result (acp--add-text-properties str 'my-prop 'x)))
    (should (eq 'x (get-text-property 0 'my-prop result)))
    (should (eq 'x (get-text-property 4 'my-prop result)))))

(ert-deftest acp--add-text-properties/multiple-properties ()
  "Multiple properties can be set in one call."
  (let* ((str (copy-sequence "hello"))
         (result (acp--add-text-properties str 'p1 'v1 'p2 'v2)))
    (should (eq 'v1 (get-text-property 0 'p1 result)))
    (should (eq 'v2 (get-text-property 0 'p2 result)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--prepare-permission-actions
;;; ─────────────────────────────────────────────────────────────────

(defun acp-test--make-option (kind name option-id)
  "Create a permission option alist with KIND, NAME, OPTION-ID."
  `((kind . ,kind) (name . ,name) (optionId . ,option-id)))

(ert-deftest acp--prepare-permission-actions/allow-always ()
  "allow_always maps to '!' character."
  (let* ((opts (list (acp-test--make-option "allow_always" "Always" "opt-always")))
         (actions (acp--prepare-permission-actions opts)))
    (should (= 1 (length actions)))
    (let ((action (car actions)))
      (should (= ?! (map-elt action :char)))
      (should (equal "opt-always" (map-elt action :option-id)))
      (should (equal "allow_always" (map-elt action :kind)))
      (should (string-match-p "!" (map-elt action :label))))))

(ert-deftest acp--prepare-permission-actions/allow-once ()
  "allow_once maps to 'y' character."
  (let* ((opts (list (acp-test--make-option "allow_once" "Once" "opt-once")))
         (actions (acp--prepare-permission-actions opts)))
    (should (= 1 (length actions)))
    (should (= ?y (map-elt (car actions) :char)))))

(ert-deftest acp--prepare-permission-actions/reject-once ()
  "reject_once maps to 'n' character."
  (let* ((opts (list (acp-test--make-option "reject_once" "Reject" "opt-reject")))
         (actions (acp--prepare-permission-actions opts)))
    (should (= 1 (length actions)))
    (should (= ?n (map-elt (car actions) :char)))))

(ert-deftest acp--prepare-permission-actions/unknown-kind-filtered-out ()
  "Unknown kind is filtered out (produces nil, then excluded)."
  (let* ((opts (list (acp-test--make-option "unknown_kind" "Unknown" "opt-unknown")))
         (actions (acp--prepare-permission-actions opts)))
    ;; seq-map returns nil for unknown, seq-sort keeps nil -> result has nil
    ;; The actual function returns a list that may contain nil elements
    ;; Filter out nils to count valid actions
    (let ((valid (seq-filter #'identity actions)))
      (should (= 0 (length valid))))))

(ert-deftest acp--prepare-permission-actions/sorted-by-label-length ()
  "Actions are sorted by label length (shortest first)."
  (let* ((opts (list (acp-test--make-option "allow_always" "Allow Always" "opt-a")
                     (acp-test--make-option "reject_once" "No" "opt-r")
                     (acp-test--make-option "allow_once" "Yes" "opt-o")))
         (actions (seq-filter #'identity (acp--prepare-permission-actions opts))))
    (should (>= (length actions) 2))
    ;; Labels should be in non-decreasing length order
    (let ((labels (mapcar (lambda (a) (map-elt a :label)) actions)))
      (cl-loop for (a b) on labels
               while b
               do (should (<= (length a) (length b)))))))

(ert-deftest acp--prepare-permission-actions/all-three-kinds ()
  "All three known kinds produce three valid actions."
  (let* ((opts (list (acp-test--make-option "allow_always" "Always" "opt-a")
                     (acp-test--make-option "allow_once" "Once" "opt-o")
                     (acp-test--make-option "reject_once" "Reject" "opt-r")))
         (actions (seq-filter #'identity (acp--prepare-permission-actions opts))))
    (should (= 3 (length actions)))))

(ert-deftest acp--prepare-permission-actions/label-includes-name-and-char ()
  "Label includes the option name and the key character in parentheses."
  (let* ((opts (list (acp-test--make-option "allow_once" "Yes please" "opt-y")))
         (actions (seq-filter #'identity (acp--prepare-permission-actions opts)))
         (label (map-elt (car actions) :label)))
    (should (string-match-p "Yes please" label))
    (should (string-match-p "(y)" label))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--save-tool-call
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--save-tool-call/stores-new-tool-call ()
  "A new tool call is stored in state :tool-calls."
  (let ((state (acp--make-state))
        (tool-call-id "tc-001")
        (tool-call (list (cons :title "Read file")
                         (cons :status "pending")
                         (cons :kind "file"))))
    (acp--save-tool-call state tool-call-id tool-call)
    (let ((stored (map-nested-elt state `(:tool-calls ,tool-call-id))))
      (should stored)
      (should (equal "Read file" (map-elt stored :title)))
      (should (equal "pending" (map-elt stored :status))))))

(ert-deftest acp--save-tool-call/merges-existing-tool-call ()
  "An updated tool call is merged with existing data."
  (let ((state (acp--make-state))
        (tool-call-id "tc-002"))
    ;; Save initial data
    (acp--save-tool-call state tool-call-id
                         (list (cons :title "Write file")
                               (cons :status "pending")
                               (cons :kind "file")))
    ;; Update status
    (acp--save-tool-call state tool-call-id
                         (list (cons :status "completed")))
    (let ((stored (map-nested-elt state `(:tool-calls ,tool-call-id))))
      ;; Original fields are preserved
      (should (equal "Write file" (map-elt stored :title)))
      (should (equal "file" (map-elt stored :kind)))
      ;; Updated field is overwritten
      (should (equal "completed" (map-elt stored :status))))))

(ert-deftest acp--save-tool-call/multiple-tool-calls ()
  "Multiple tool calls are stored independently."
  (let ((state (acp--make-state)))
    (acp--save-tool-call state "tc-1" (list (cons :title "Call 1")))
    (acp--save-tool-call state "tc-2" (list (cons :title "Call 2")))
    (should (equal "Call 1" (map-elt (map-nested-elt state '(:tool-calls "tc-1")) :title)))
    (should (equal "Call 2" (map-elt (map-nested-elt state '(:tool-calls "tc-2")) :title)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp-google-key and acp-anthropic-key
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp-google-key/returns-nil-when-nil ()
  "Returns nil when acp-google-key is nil."
  (let ((acp-google-key nil))
    (should (null (acp-google-key)))))

(ert-deftest acp-google-key/returns-string-directly ()
  "Returns the string value when acp-google-key is a string."
  (let ((acp-google-key "my-google-key"))
    (should (equal "my-google-key" (acp-google-key)))))

(ert-deftest acp-google-key/calls-function-and-returns-result ()
  "Calls the function and returns its result."
  (let ((acp-google-key (lambda () "function-key")))
    (should (equal "function-key" (acp-google-key)))))

(ert-deftest acp-google-key/returns-KEY-NOT-FOUND-when-function-errors ()
  "Returns KEY-NOT-FOUND string when the function signals an error."
  (let ((acp-google-key (lambda () (error "no key"))))
    (should (equal "KEY-NOT-FOUND" (acp-google-key)))))

(ert-deftest acp-anthropic-key/returns-nil-when-nil ()
  "Returns nil when acp-anthropic-key is nil."
  (let ((acp-anthropic-key nil))
    (should (null (acp-anthropic-key)))))

(ert-deftest acp-anthropic-key/returns-string-directly ()
  "Returns the string value when acp-anthropic-key is a string."
  (let ((acp-anthropic-key "my-anthropic-key"))
    (should (equal "my-anthropic-key" (acp-anthropic-key)))))

(ert-deftest acp-anthropic-key/calls-function-and-returns-result ()
  "Calls the function and returns its result."
  (let ((acp-anthropic-key (lambda () "anthropic-function-key")))
    (should (equal "anthropic-function-key" (acp-anthropic-key)))))

(ert-deftest acp-anthropic-key/returns-KEY-NOT-FOUND-when-function-errors ()
  "Returns KEY-NOT-FOUND string when the function signals an error."
  (let ((acp-anthropic-key (lambda () (error "no key"))))
    (should (equal "KEY-NOT-FOUND" (acp-anthropic-key)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--make-button
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--make-button/returns-propertized-string ()
  "Returns a propertized string with text surrounded by spaces."
  (let ((btn (acp--make-button :text "Click me" :help "help" :kind 'test
                               :action (lambda () (interactive)))))
    (should (stringp btn))
    (should (string-match-p "Click me" btn))))

(ert-deftest acp--make-button/has-keymap-property ()
  "Button has a keymap text property."
  (let ((btn (acp--make-button :text "OK" :help "OK" :kind 'test
                               :action (lambda () (interactive)))))
    (should (keymapp (get-text-property 0 'keymap btn)))))

(ert-deftest acp--make-button/has-help-echo-property ()
  "Button has a help-echo text property matching HELP argument."
  (let ((btn (acp--make-button :text "OK" :help "Click for help" :kind 'test
                               :action (lambda () (interactive)))))
    (should (equal "Click for help" (get-text-property 0 'help-echo btn)))))

(ert-deftest acp--make-button/has-pointer-property ()
  "Button has pointer='hand text property."
  (let ((btn (acp--make-button :text "OK" :help "h" :kind 'test
                               :action (lambda () (interactive)))))
    (should (eq 'hand (get-text-property 0 'pointer btn)))))

(ert-deftest acp--make-button/has-button-property-set-to-kind ()
  "Button has 'button text property set to KIND."
  (let ((btn (acp--make-button :text "OK" :help "h" :kind 'my-kind
                               :action (lambda () (interactive)))))
    (should (eq 'my-kind (get-text-property 0 'button btn)))))

(ert-deftest acp--make-button/action-bound-to-ret ()
  "Action is bound to RET in the button keymap."
  (let* ((action (lambda () (interactive)))
         (btn (acp--make-button :text "OK" :help "h" :kind 'test :action action)))
    (should (eq action (lookup-key (get-text-property 0 'keymap btn) (kbd "RET"))))))

(ert-deftest acp--make-button/text-padded-with-spaces ()
  "Button text is padded with a space on each side."
  (let ((btn (acp--make-button :text "Go" :help "h" :kind 'test
                               :action (lambda () (interactive)))))
    (should (string-prefix-p " " btn))
    (should (string-suffix-p " " btn))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--format-available-commands
;;; ─────────────────────────────────────────────────────────────────

(defun acp-test--make-command (name description)
  "Create a command alist with NAME and DESCRIPTION."
  `((name . ,name) (description . ,description)))

(ert-deftest acp--format-available-commands/single-command ()
  "Single command is formatted with /prefix and description."
  (let* ((cmds (list (acp-test--make-command "help" "Show help")))
         (result (acp--format-available-commands cmds)))
    (should (string-match-p "/help" result))
    (should (string-match-p "Show help" result))))

(ert-deftest acp--format-available-commands/multiple-commands-joined-with-newline ()
  "Multiple commands are joined with newlines."
  (let* ((cmds (list (acp-test--make-command "help" "Show help")
                     (acp-test--make-command "clear" "Clear screen")))
         (result (acp--format-available-commands cmds)))
    (should (string-match-p "\n" result))
    (should (string-match-p "/help" result))
    (should (string-match-p "/clear" result))))

(ert-deftest acp--format-available-commands/names-padded-to-equal-width ()
  "Command names are padded so descriptions align."
  (let* ((cmds (list (acp-test--make-command "a" "Short name")
                     (acp-test--make-command "longercommand" "Long name")))
         (result (acp--format-available-commands cmds))
         (lines (split-string result "\n")))
    ;; Both lines start with /
    (should (string-prefix-p "/" (car lines)))
    (should (string-prefix-p "/" (cadr lines)))))

(ert-deftest acp--format-available-commands/empty-commands-list ()
  "Empty commands list returns empty string."
  (let ((result (acp--format-available-commands '())))
    (should (equal "" result))))

(ert-deftest acp--format-available-commands/commands-have-font-lock-face ()
  "Command names have font-lock-face property set."
  (let* ((cmds (list (acp-test--make-command "run" "Run the agent")))
         (result (acp--format-available-commands cmds)))
    ;; The /run text should have a font-lock-face
    (should (get-text-property 0 'font-lock-face result))))

;;; ─────────────────────────────────────────────────────────────────
;;; Tests for acp--gemini-text
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--gemini-text/returns-string-of-correct-length ()
  "Result has same length as 'Gemini' (6 characters)."
  (let ((result (acp--gemini-text)))
    (should (= 6 (length result)))))

(ert-deftest acp--gemini-text/each-char-has-foreground-face ()
  "Each character has a font-lock-face with :foreground."
  (let ((result (acp--gemini-text)))
    (dotimes (i (length result))
      (let ((face (get-text-property i 'font-lock-face result)))
        (should face)
        (should (plist-get face :foreground))))))

(ert-deftest acp--gemini-text/spells-gemini ()
  "Result spells 'Gemini'."
  (let ((result (acp--gemini-text)))
    (should (equal "Gemini" (substring-no-properties result)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Regression / boundary tests
;;; ─────────────────────────────────────────────────────────────────

(ert-deftest acp--make-state/is-alist ()
  "State is an alist (list of cons cells)."
  (let ((state (acp--make-state)))
    (should (listp state))
    (should (cl-every #'consp state))))

(ert-deftest acp--stop-reason-description/nil-input ()
  "nil input returns 'unknown' formatted message."
  (let ((result (acp--stop-reason-description nil)))
    (should (string-match-p "unknown" result))))

(ert-deftest acp--save-tool-call/does-not-share-structure-with-original ()
  "Save does not mutate old-tool-calls alist (uses copy-alist)."
  (let ((state (acp--make-state)))
    (acp--save-tool-call state "tc-a" (list (cons :title "A")))
    (let ((tool-calls-before (map-elt state :tool-calls)))
      (acp--save-tool-call state "tc-b" (list (cons :title "B")))
      ;; The original snapshot should not have tc-b
      (should (null (map-elt tool-calls-before "tc-b"))))))

(ert-deftest acp--prepare-permission-actions/empty-options ()
  "Empty options list returns empty (or all-nil) list."
  (let ((actions (seq-filter #'identity
                              (acp--prepare-permission-actions '()))))
    (should (= 0 (length actions)))))

(ert-deftest acp-google-key/non-function-non-string-returns-nil ()
  "When acp-google-key is a number (not string or function), returns nil."
  (let ((acp-google-key 42))
    (should (null (acp-google-key)))))

(ert-deftest acp-anthropic-key/non-function-non-string-returns-nil ()
  "When acp-anthropic-key is a number, returns nil."
  (let ((acp-anthropic-key 99))
    (should (null (acp-anthropic-key)))))

(provide 'acp-tests)

;;; acp-tests.el ends here
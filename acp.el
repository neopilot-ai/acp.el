;;; acp.el --- An agent shell powered by ACP -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI

;; Author: NeoPilot AI https://neopilot-ai.com
;; URL: https://github.com/neopilot-ai/acp.el
;; Version: 0.1.1

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
;; acp is driven by ACP (Agent Client Protocol) as per spec
;; https://agentclientprotocol.com
;;
;; Note: This package is in the very early stage and is likely
;; incomplete or may have some rough edges.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues
;;
;; ✨ Please support this work https://github.com/sponsors/neopilot-ai ✨

;;; Code:

(require 'json)
(require 'map)
(require 'markdown-overlays)
(require 'shell-maker)
(require 'acp)
(require 'sui)

(defcustom acp-google-key nil
  "Google API key as a string or a function that loads and returns it."
  :type '(choice (function :tag "Function")
                 (string :tag "String"))
  :group 'acp)

(defcustom acp-anthropic-key nil
  "Anthropic API key as a string or a function that loads and returns it."
  :type '(choice (function :tag "Function")
                 (string :tag "String"))
  :group 'acp)

(defcustom acp-permission-icon "⚠" ;; 􀇾
  "Icon displayed when shell commands require permission to execute."
  :type 'string
  :group 'acp)

(defcustom acp-thought-process-icon "💡" ;; 􁷘
  "Icon displayed during the AI's thought process."
  :type 'string
  :group 'acp)

(cl-defun acp--make-state (&key client-maker needs-authentication authenticate-request-maker)
  "Construct shell state.

Shell state is provider-dependent and needs CLIENT-MAKER, NEEDS-AUTHENTICATION
and AUTHENTICATE-REQUEST-MAKER."
  (list (cons :client nil)
        (cons :client-maker client-maker)
        (cons :initialized nil)
        (cons :needs-authentication needs-authentication)
        (cons :authenticate-request-maker authenticate-request-maker)
        (cons :authenticated nil)
        (cons :session-id nil)
        (cons :last-entry-type nil)
        (cons :request-count 0)
        (cons :tool-calls nil)))

(defvar-local acp--state
    (acp--make-state))

(defvar acp--config nil)

(defun acp-start-claude-code-agent ()
  "Start an interactive Claude Code agent shell."
  (interactive)
  (let ((api-key (acp-anthropic-key)))
    (unless api-key
      (user-error "Please set your `acp-anthropic-key'"))
    (with-current-buffer
        (acp-start
         :new-session t
         :mode-line-name "Claude Code"
         :buffer-name "Claude Code"
         :shell-prompt "Claude Code> "
         :shell-prompt-regexp "Claude Code> "
         :client-maker (lambda (_shell _state)
                         (acp-make-claude-client :api-key api-key))))))

(defun acp-start-gemini-agent ()
  "Start an interactive Gemini CLI agent shell."
  (interactive)
  (let ((api-key (acp-google-key)))
    (unless api-key
      (user-error "Please set your `acp-google-key'"))
    (with-current-buffer
        (acp-start
         :new-session t
         :mode-line-name "Gemini"
         :buffer-name "Gemini"
         :shell-prompt "Gemini> "
         :shell-prompt-regexp "Gemini> "
         :needs-authentication t
         :authenticate-request-maker (lambda ()
                                       (acp-make-authenticate-request :method-id "gemini-api-key"))
         :client-maker (lambda (_shell _state)
                         (acp-make-gemini-client :api-key api-key))))))

(defun acp-interrupt ()
  "Interrupt in-progress request."
  (interactive)
  (unless (eq major-mode 'acp-mode)
    (user-error "Not in a shell"))
  (unless (map-elt acp--state :session-id)
    (user-error "No active session"))
  (acp-send-request
   :client (map-elt acp--state :client)
   :request (acp-make-session-cancel-request
             :session-id (map-elt acp--state :session-id)
             :reason "User cancelled")
   :on-success (lambda (_response)
                 (message "Cancelling..."))))

(cl-defun acp--make-config (&key prompt prompt-regexp)
  "Create `shell-maker' configuration with PROMPT and PROMPT-REGEXP."
  (make-shell-maker-config
   :name "agent"
   :prompt prompt
   :prompt-regexp prompt-regexp
   :execute-command
   (lambda (command shell)
     (acp--handle
      :command command
      :shell shell))))

(defvar-keymap acp-mode-map
  :parent shell-maker-mode-map
  :doc "Keymap for `acp-mode'."
  "C-c C-c" #'acp-interrupt)

(shell-maker-define-major-mode (acp--make-config) acp-mode-map)

(cl-defun acp--handle (&key command shell)
  "Handle COMMAND using `shell-maker' SHELL."
  (unless (eq major-mode 'acp-mode)
    (user-error "Not in a shell"))
  (with-current-buffer (map-elt shell :buffer)
    (map-put! acp--state :request-count
              ;; TODO: Make public in shell-maker.
              (shell-maker--current-request-id))
    (cond ((not (map-elt acp--state :client))
           (acp--update-dialog-block
            :shell shell
            :state acp--state
            :block-id "starting"
            :label-left (propertize "Initialized" 'font-lock-face 'font-lock-doc-markup-face)
            :body "Creating client..."
            :create-new t
            :expanded t)
           (if (map-elt acp--state :client-maker)
               (progn
                 (map-put! acp--state :client (funcall (map-elt acp--state :client-maker)
                                                               shell acp--state))
                 (acp--subscribe-to-client-events
                  :shell shell :state acp--state)
                 (acp--handle :command command :shell shell))
             (funcall (map-elt shell :write-output) "No :client-maker found")
             (funcall (map-elt shell :finish-output) nil)))
          ((not (map-elt acp--state :initialized))
           (with-current-buffer (map-elt shell :buffer)
             (acp--update-dialog-block
              :shell shell
              :state acp--state
              :block-id "starting"
              :body "\n\nInitializing..."
              :append t))
           (acp-send-request
            :client (map-elt acp--state :client)
            :request (acp-make-initialize-request :protocol-version 1)
            :on-success (lambda (_response)
                          ;; TODO: More to be handled?
                          (with-current-buffer (map-elt shell :buffer)
                            (map-put! acp--state :initialized t)
                            (acp--handle :command command :shell shell)))
            :on-failure (acp--make-error-handler
                         :state acp--state :shell shell)))
          ((and (map-elt acp--state :needs-authentication)
                (not (map-elt acp--state :authenticated)))
           (with-current-buffer (map-elt shell :buffer)
             (acp--update-dialog-block
              :shell shell
              :state acp--state
              :block-id "starting"
              :body "\n\nAuthenticating..."
              :append t))
           (if (map-elt acp--state :authenticate-request-maker)
               (acp-send-request
                :client (map-elt acp--state :client)
                :request (funcall (map-elt acp--state :authenticate-request-maker))
                :on-success (lambda (_response)
                              ;; TODO: More to be handled?
                              (with-current-buffer (map-elt shell :buffer)
                                (map-put! acp--state :authenticated t)
                                (acp--handle :command command :shell shell)))
                :on-failure (acp--make-error-handler
                             :state acp--state :shell shell))
             (funcall (map-elt shell :write-output) "No :authenticate-request-maker")
             (funcall (map-elt shell :finish-output) nil)))
          ((not (map-elt acp--state :session-id))
           (acp--update-dialog-block
            :shell shell
            :state acp--state
            :block-id "starting"
            :body "\n\nCreating session..."
            :append t)
           (acp-send-request
            :client (map-elt acp--state :client)
            :request (acp-make-session-new-request :cwd default-directory)
            :on-success (lambda (response)
                          (with-current-buffer (map-elt shell :buffer)
                            (map-put! acp--state
                                      :session-id (map-elt response 'sessionId))
                            (with-current-buffer (map-elt shell :buffer)
                              (acp--update-dialog-block
                               :shell shell
                               :state acp--state
                               :block-id "starting"
                               :body "\n\nReady"
                               :append t))
                            (acp--handle :command command :shell shell)))
            :on-failure (acp--make-error-handler
                         :state acp--state :shell shell)))
          (t
           (acp-send-request
            :client (map-elt acp--state :client)
            :request (acp-make-session-prompt-request
                      :session-id (map-elt acp--state :session-id)
                      :prompt `[((type . "text")
                                 (text . ,(substring-no-properties command)))])
            :on-success (lambda (response)
                          (with-current-buffer (map-elt shell :buffer)
                            (let ((success (equal (map-elt response 'stopReason)
                                                  "end_turn")))
                              (unless success
                                (funcall (map-elt shell :write-output)
                                         (acp--stop-reason-description
                                          (map-elt response 'stopReason))))
                              (funcall (map-elt shell :finish-output) t))))
            :on-failure (acp--make-error-handler
                         :state acp--state :shell shell))))))

(defun acp--stop-reason-description (stop-reason)
  "Return a human-readable text description for STOP-REASON.

https://agentclientprotocol.com/protocol/schema#param-stop-reason"
  (pcase stop-reason
    ("end_turn" "The language model finishes responding without requesting more tools")
    ("max_tokens" "Max token limit reached")
    ("max_turn_requests" "Exceeded request limit")
    ("refusal" "Refused")
    ("cancelled" "Cancelled")
    (_ (format "Stop for unknown reason: %s" stop-reason))))

(cl-defun acp--subscribe-to-client-events (&key shell state)
  "Subscribe SHELL and STATE to ACP events."
  (acp-subscribe-to-errors
   :client (map-elt state :client)
   :on-error (lambda (error)
               (let-alist error
                 (acp--update-dialog-block
                  :shell shell
                  :state state
                  :block-id "Error"
                  :body (or .message "Some error ¯\\_ (ツ)_/¯")
                  :create-new t
                  :no-navigation t))))
  (acp-subscribe-to-notifications
   :client (map-elt state :client)
   :on-notification (lambda (notification)
                      (acp--log "NOTIFICATION" "%s" notification)
                      (let-alist notification
                        (cond ((equal .method "session/update")
                               (let ((update (map-elt (map-elt notification 'params) 'update)))
                                 (cond
                                  ((equal (map-elt update 'sessionUpdate) "tool_call")
                                   (acp--save-tool-call
                                    state
                                    (map-elt update 'toolCallId)
                                    (list (cons :title (map-elt update 'title))
                                          (cons :status (map-elt update 'status))
                                          (cons :kind (map-elt update 'kind))
                                          (cons :raw-input (map-elt update 'rawInput))
                                          (cons :content (map-elt update 'content))))
                                   (acp--update-dialog-block
                                    :shell shell
                                    :state state
                                    :block-id (map-elt update 'toolCallId)
                                    :label-left (acp-make-tool-call-label
                                                 state (map-elt update 'toolCallId)))
                                   (map-put! state :last-entry-type "tool_call"))
                                  ((equal (map-elt update 'sessionUpdate) "agent_thought_chunk")
                                   (let-alist update
                                     ;; (message "agent_thought_chunk: last-type=%s, will-append=%s"
                                     ;;          (map-elt state :last-entry-type)
                                     ;;          (equal (map-elt state :last-entry-type) "agent_thought_chunk"))
                                     (acp--update-dialog-block
                                      :shell shell
                                      :state state
                                      :block-id "agent_thought_chunk"
                                      :label-left  (concat
                                                    acp-thought-process-icon
                                                    " "
                                                    (propertize "Thought process" 'font-lock-face font-lock-doc-markup-face))
                                      :body .content.text
                                      :append (equal (map-elt state :last-entry-type)
                                                     "agent_thought_chunk")))
                                   (map-put! state :last-entry-type "agent_thought_chunk"))
                                  ((equal (map-elt update 'sessionUpdate) "agent_message_chunk")
                                   (let-alist update
                                     (acp--update-dialog-block
                                      :shell shell
                                      :state state
                                      :block-id "agent_message_chunk"
                                      :label-left nil ;;
                                      :body .content.text
                                      :create-new (not (equal (map-elt state :last-entry-type)
                                                              "agent_message_chunk"))
                                      :append t
                                      :no-navigation t))
                                   (map-put! state :last-entry-type "agent_message_chunk"))
                                  ((equal (map-elt update 'sessionUpdate) "plan")
                                   (let-alist update
                                     (acp--update-dialog-block
                                      :shell shell
                                      :state state
                                      :block-id "plan"
                                      :label-left (propertize "Plan" 'font-lock-face 'font-lock-doc-markup-face)
                                      :body (acp--format-plan .entries)
                                      :expanded t))
                                   (map-put! state :last-entry-type "plan"))
                                  ((equal (map-elt update 'sessionUpdate) "tool_call_update")
                                   (let-alist update
                                     ;; Update stored tool call data with new status and content
                                     (acp--save-tool-call
                                      state
                                      .toolCallId
                                      (list (cons :status (map-elt update 'status))
                                            (cons :content (map-elt update 'content))))
                                     (let ((output (concat
                                                    "\n\n"
                                                    (mapconcat (lambda (item)
                                                                 (let-alist item
                                                                   .content.text))
                                                               .content
                                                               "\n\n")
                                                    "\n\n")))
                                       (acp--update-dialog-block
                                        :shell shell
                                        :state state
                                        :block-id .toolCallId
                                        :label-left (acp-make-tool-call-label
                                                     state .toolCallId)
                                        :body (string-trim output))))
                                   (map-put! state :last-entry-type "tool_call_update"))
                                  ((equal (map-elt update 'sessionUpdate) "available_commands_update")
                                   (let-alist update
                                     (acp--update-dialog-block
                                      :shell shell
                                      :state state
                                      :block-id "available_commands_update"
                                      :label-left (propertize "Available commands" 'font-lock-face 'font-lock-doc-markup-face)
                                      :body (acp--format-available-commands (map-elt update 'availableCommands))))
                                   (map-put! state :last-entry-type "available_commands_update"))
                                  (t
                                   (acp--update-dialog-block
                                    :shell shell
                                    :state state
                                    :block-id "Session Update - fallback"
                                    :body (format "%s" notification)
                                    :create-new t
                                    :no-navigation t)
                                   (map-put! state :last-entry-type nil)))))
                              (t
                               (acp--update-dialog-block
                                :shell shell
                                :state state
                                :block-id "Notification - fallback"
                                :body (format "%s" notification)
                                :create-new t
                                :no-navigation t)
                               (map-put! state :last-entry-type nil))))
                      (with-current-buffer (map-elt shell :buffer)
                        (markdown-overlays-put))))
  (acp-subscribe-to-requests
   :client (map-elt state :client)
   :on-request (lambda (request)
                 (acp--log "INCOMING REQUEST" "%s" request)
                 (let-alist request
                   (cond ((equal .method "session/request_permission")
                          (acp--save-tool-call
                           state .params.toolCall.toolCallId
                           (list (cons :title .params.toolCall.title)
                                 (cons :status .params.toolCall.status)
                                 (cons :kind .params.toolCall.kind)))
                          (acp--update-dialog-block
                           :shell shell
                           :state state
                           :label-left (acp-make-tool-call-label
                                        state .params.toolCall.toolCallId)
                           :block-id .params.toolCall.toolCallId
                           :body (with-current-buffer (map-elt shell :buffer)
                                   (acp--make-tool-call-permission-text
                                    :request request
                                    :client (map-elt state :client)
                                    :state state))
                           :expanded t)
                          (run-at-time
                           0.1 nil (lambda ()
                                     (acp-send-response
                                      :client (map-elt state :client)
                                      :response (acp-make-session-request-permission-response
                                                 :request-id .id
                                                 :option-id (acp--prompt-for-permission .params.options)))
                                     (sui-collapse-dialog-block-by-id (map-elt state :request-count) .params.toolCall.toolCallId)))
                          (map-put! state :last-entry-type "session/request_permission"))
                         (t
                          (acp--update-dialog-block
                           :shell shell
                           :state state
                           :block-id "Unhandled Incoming Request"
                           :body (format "⚠ Unhandled incoming request: \"%s\"" .method)
                           :create-new t
                           :no-navigation t)
                          (map-put! state :last-entry-type nil))))
                 (with-current-buffer (map-elt shell :buffer)
                   (markdown-overlays-put)))))

(defun acp--format-available-commands (commands)
  "Format COMMANDS for shell rendering."
  (let ((max-name-length (cl-reduce #'max commands
                                    :key (lambda (cmd)
                                           (length (alist-get 'name cmd)))
                                    :initial-value 0)))
    (mapconcat
     (lambda (cmd)
       (let ((name (alist-get 'name cmd))
             (desc (alist-get 'description cmd)))
         (concat
          ;; For commands to be executable, they start with /
          (propertize (format (format "/%%-%ds" max-name-length) name)
                      'font-lock-face 'font-lock-function-name-face)
          "  "
          (propertize desc 'font-lock-face 'font-lock-comment-face))))
     commands
     "\n")))

(cl-defun acp--make-error-handler (&key state shell)
  "Create ACP error handler with SHELL STATE."
  (lambda (error raw-error)
    (let-alist error
      (with-current-buffer (map-elt shell :buffer)
        (acp--update-dialog-block
         :shell shell
         :state acp--state
         :block-id (format "failed-%s-id:%s-code:%s"
                           (map-elt state :request-count)
                           (or .id "?")
                           (or .code "?"))
         :body (acp--make-error-dialog-text
                :code .code
                :message .message
                ;; TODO: Serialize to json and prettify
                :raw-error raw-error)
         :create-new t)))
    ;; TODO: Mark buffer command with shell failure.
    (with-current-buffer (map-elt shell :buffer)
      (funcall (map-elt shell :finish-output) t))))

(defun acp--prepare-permission-actions (options)
  "Format permission OPTIONS for shell rendering."
  (let ((char-map '(("allow_always" . ?!)
                    ("allow_once" . ?y)
                    ("reject_once" . ?n))))
    (seq-sort (lambda (a b)
                (< (length (map-elt a :label))
                   (length (map-elt b :label))))
              (seq-map (lambda (opt)
                         (let* ((kind (map-elt opt 'kind))
                                (char (alist-get kind char-map nil nil #'string=))
                                (name (map-elt opt 'name)))
                           (when char
                             (map-into `((:label . ,(format "%s (%c)" name char))
                                         (:char . ,char)
                                         (:kind . ,kind)
                                         (:option-id . ,(map-elt opt 'optionId)))
                                       'alist))))
                       options))))

(cl-defun acp--make-tool-call-permission-text (&key request client state)
  "Create text to render permission dialog using REQUEST, CLIENT, and STATE."
  (let-alist request
    (let ((request-id .id)
          (tool-call-id .params.toolCall.toolCallId)
          (actions (acp--prepare-permission-actions .params.options)))
      (let ((text (format "
   %s %s %s%s

   %s

"
                          (propertize acp-permission-icon
                                      'font-lock-face 'warning)
                          (propertize "Tool Permission" 'font-lock-face 'bold)
                          (propertize acp-permission-icon
                                      'font-lock-face 'warning)
                          (if .params.toolCall.title
                              (format "\n\n%s" .params.toolCall.title)
                            "")
                          (mapconcat (lambda (action)
                                       (acp--make-button
                                        :text (map-elt action :label)
                                        :help (map-elt action :label)
                                        :kind 'permission
                                        :action (lambda ()
                                                  (interactive)
                                                  (acp-send-response
                                                   :client client
                                                   :response (acp-make-session-request-permission-response
                                                              :request-id request-id
                                                              :option-id (map-elt action :option-id)))
                                                  (sui-collapse-dialog-block-by-id (map-elt state :request-count) tool-call-id))))
                                     actions
                                     " "))))
        (font-lock-append-text-property 0 (length text)
                                        'font-lock-face
                                        `(:background ,(face-background 'next-error nil t) :extend t)
                                        text)
        text))))

(defun acp--save-tool-call (state tool-call-id tool-call)
  "Store TOOL-CALL with TOOL-CALL-ID in STATE's :tool-calls alist."
  (let* ((tool-calls (map-elt state :tool-calls))
         (old-tool-call (map-elt tool-calls tool-call-id))
         (updated-tools (copy-alist tool-calls)))
    (setf (alist-get tool-call-id updated-tools nil nil #'equal)
          (if old-tool-call
              (map-merge 'alist old-tool-call tool-call)
            tool-call))
    (map-put! state :tool-calls updated-tools)))

(defun acp--prompt-for-permission (options)
  "Prompt user for permission using OPTIONS and return selected option."
  (let* ((actions (acp--prepare-permission-actions options))
         (labels (mapcar (lambda (item)
                           (map-elt item :label))
                         actions))
         (valid-chars (mapcar (lambda (item)
                                (map-elt item :char))
                              actions))
         (prompt (format "%s " (string-join labels " ")))
         (choice-char (read-char-choice prompt valid-chars)))
    (map-elt (seq-find (lambda (item)
                         (= (map-elt item :char) choice-char))
                       actions)
             :option-id)))

(cl-defun acp--make-error-dialog-text (&key code message raw-error)
  "Create formatted error dialog text with CODE, MESSAGE, and RAW-ERROR."
  (format "╭─

  %s Error (%s) %s

  %s

  %s

╰─"
          (propertize "⚠" 'font-lock-face 'error)
          (or code "?")
          (propertize "⚠" 'font-lock-face 'error)
          (or message "¯\\_ (ツ)_/¯")
          (acp--make-button
           :text "Details" :help "Details" :kind 'error
           :action (lambda ()
                     (interactive)
                     (acp--view-as-error
                      (with-temp-buffer
                        (insert raw-error)
                        (json-pretty-print-buffer)
                        (buffer-string)))))))

(defun acp--view-as-error (text)
  "Display TEXT in a read-only error buffer."
  (let ((buf (get-buffer-create "*acp error*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text))
      (read-only-mode 1))
    (display-buffer buf)))

(defun acp--clean-up ()
  "Clean up resources.

For example, shut down ACP client."
  (acp--log "CLEANING-UP" "")
  (unless (eq major-mode (shell-maker-major-mode shell-maker--config))
    (user-error "Not in an agent shell"))
  (when (map-elt acp--state :client)
    (acp-shutdown :client (map-elt acp--state :client))))

(map-elt acp--state :client)

(defun acp--status-label (status)
  "Convert STATUS codes to user-visible labels."
  (let* ((config (pcase status
                   ("pending" '("pending" warning))
                   ("in_progress" '("in progress" warning))
                   ("completed" '("completed" success))
                   ("failed" '("failed" error))
                   (_ '("unknown" warning))))
         (label (car config))
         (face (cadr config))
         (color (face-foreground face nil t)))
    (acp--add-text-properties
     (propertize (format " %s " label) 'font-lock-face 'default)
     'font-lock-face
     `(:foreground ,color :box (:color ,color)))))

(defun acp-make-tool-call-label (state tool-call-id)
  "Create tool call label from STATE using TOOL-CALL-ID."
  (when-let ((tool-call (map-nested-elt state `(:tool-calls ,tool-call-id))))
    (let ((status (map-elt tool-call :status))
          (kind (map-elt tool-call :kind))
          (title (map-elt tool-call :title)))
      (concat
       (when status
         (acp--status-label status))
       (when (and status kind)
         " ")
       (when kind
         (acp--add-text-properties
          (propertize (format " %s " kind) 'font-lock-face 'default)
          'font-lock-face
          `(:box t)))
       (when title
         "\n\n  ")
       (when title (propertize title 'font-lock-face 'font-lock-doc-markup-face))))))

(defun acp--format-plan (entries)
  "Format plan ENTRIES for shell rendering."
  (let* ((max-label-width
          (apply #'max (cons 0 (mapcar (lambda (entry)
                                         (length (acp--status-label
                                                  (alist-get 'status entry))))
                                       entries)))))
    (mapconcat
     (lambda (entry)
       (let-alist entry
         (let* ((status-label (acp--status-label .status))
                (label-length (length status-label))
                ;; Add 2 spaces to compensate box padding.
                (padding (make-string
                          (max 1 (+ 2 (- max-label-width label-length)))
                          ?\s)))
           (concat
            status-label
            padding
            .content))))
     entries
     "\n")))

(cl-defun acp--make-button (&key text help kind action)
  "Make button with TEXT, HELP text, KIND, ACTION and NO-BOX."
  (propertize
   (format " %s " text)
   'font-lock-face '(:box t)
   'help-echo help
   'pointer 'hand
   'keymap (let ((map (make-sparse-keymap)))
             (define-key map [mouse-1] action)
             (define-key map (kbd "RET") action)
             (define-key map [remap self-insert-command] 'ignore)
             map)
   'button kind))

(defun acp--add-text-properties (string &rest properties)
  "Add text PROPERTIES to entire STRING and return the propertized string.
PROPERTIES should be a plist of property-value pairs."
  (let ((str (copy-sequence string))
        (len (length string)))
    (while properties
      (let ((prop (car properties))
            (value (cadr properties)))
        (if (memq prop '(face font-lock-face))
            ;; Merge face properties
            (let ((existing (get-text-property 0 prop str)))
              (put-text-property 0 len prop
                                 (if existing
                                     (list value existing)
                                   value)
                                 str))
          ;; Regular property replacement
          (put-text-property 0 len prop value str))
        (setq properties (cddr properties))))
    str))

(cl-defun acp-start (&key no-focus new-session mode-line-name welcome-function
                                  buffer-name shell-prompt shell-prompt-regexp
                                  client-maker
                                  needs-authentication
                                  authenticate-request-maker)
  "Start an agent shell programmatically.

Set NO-FOCUS to start in background.
Set NEW-SESSION to start a separate new session.
Set MODE-LINE-NAME and BUFFER-NAME for display customization.
Set SHELL-PROMPT and SHELL-PROMPT-REGEXP for shell prompt display.
Set CLIENT-MAKER function to create the ACP client.
Set NEEDS-AUTHENTICATION if ACP agent requires client authentication.
Set AUTHENTICATE-REQUEST-MAKER to create authentication requests.
Set WELCOME-FUNCTION for custom welcome message.

Returns the shell buffer."
  (let* ((config (acp--make-config
                  :prompt shell-prompt
                  :prompt-regexp shell-prompt-regexp))
         (acp--config config)
         (shell-buffer
          (shell-maker-start acp--config
                             no-focus
                             welcome-function
                             new-session
                             buffer-name
                             mode-line-name)))
    (with-current-buffer shell-buffer
      ;; Initialize buffer-local state
      (setq-local acp--state (acp--make-state
                                      :client-maker client-maker
                                      :needs-authentication needs-authentication
                                      :authenticate-request-maker authenticate-request-maker))
      ;; Initialize buffer-local config
      (setq-local acp--config config)
      (add-hook 'kill-buffer-hook #'acp--clean-up nil t)
      (sui-mode +1))
    shell-buffer))

(cl-defun acp--update-dialog-block (&key shell state block-id label-left label-right body append create-new no-navigation expanded)
  "Update dialog block in SHELL buffer.

Creates or updates existing dialog using STATE's request count as namespace.
BLOCK-ID uniquely identifies the block.

Dialog can have LABEL-LEFT, LABEL-RIGHT, and BODY.

Optional flags: APPEND text to existing content, CREATE-NEW block,
NO-NAVIGATION to skip navigation, EXPANDED to show block expanded
by default."
  (with-current-buffer (map-elt shell :buffer)
    ;; (message "acp--update-dialog-block: %s" body)
    (shell-maker-with-auto-scroll-edit
     (sui-update-dialog-block
      (sui-make-dialog-block-model
       :namespace-id (map-elt state :request-count)
       :block-id block-id
       :label-left label-left
       :label-right label-right
       :body body)
      :no-navigation no-navigation
      :append append
      :create-new create-new
      :expanded expanded))))

(defun acp--gemini-text ()
  "Colorized Gemini text with Google-branded colors."
  (let ((colors '("#4285F4" "#EA4335" "#FBBC04" "#4285F4" "#34A853" "#EA4335"))
        (text "Gemini")
        (result ""))
    (dotimes (i (length text))
      (setq result (concat result
                           (propertize (substring text i (1+ i))
                                       'font-lock-face `(:foreground ,(nth (mod i (length colors)) colors))))))
    result))

(defun acp-toggle-logging ()
  "Toggle logging."
  (interactive)
  (setq acp-logging-enabled (not acp-logging-enabled))
  (message "Logging: %s" (if acp-logging-enabled "ON" "OFF")))

(defun acp-reset-logs ()
  "Reset all log buffers."
  (interactive)
  (acp-reset-logs)
  (message "Logs reset"))

(defun acp-google-key ()
  "Get the Google API key."
  (cond ((stringp acp-google-key)
         acp-google-key)
        ((functionp acp-google-key)
         (condition-case _err
             (funcall acp-google-key)
           (error
            "KEY-NOT-FOUND")))
        (t
         nil)))

(defun acp-anthropic-key ()
  "Get the Anthropic API key."
  (cond ((stringp acp-anthropic-key)
         acp-anthropic-key)
        ((functionp acp-anthropic-key)
         (condition-case _err
             (funcall acp-anthropic-key)
           (error
            "KEY-NOT-FOUND")))
        (t
         nil)))

(provide 'acp)

;;; acp.el ends here

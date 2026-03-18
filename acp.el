;;; acp.el --- Native agentic integrations for Claude Code, Gemini CLI, etc  -*- lexical-binding: t; -*-

;; Copyright (C) 2024 NeoPilot AI

;; Author: NeoPilot AI https://github.com/neopilot-ai
;; URL: https://github.com/neopilot-ai/acp.el
;; Version: 0.49.1
;; Package-Requires: ((emacs "29.1") (shell-maker "0.89.2") (acp "0.11.1"))

(defconst acp--version "0.49.1")

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
;; `acp' offers a native `comint' shell experience to
;; interact with any agent powered by ACP (Agent Client Protocol).
;;
;; `acp' currently provides access to Claude Code, Cursor,
;; Gemini CLI, Goose, Codex, OpenCode, Qwen, and Auggie amongst other agents.
;;
;; This package depends on the `acp' package to provide the ACP layer
;; as per https://agentclientprotocol.com spec.
;;
;; Report issues at https://github.com/neopilot-ai/acp.el/issues
;;
;; ✨ Support this work https://github.com/sponsors/neopilot-ai ✨

;;; Code:

(require 'shell-maker nil t)
(eval-when-compile
  (require 'cl-lib))
(require 'dired)
(require 'diff)
(require 'json)
(require 'map)
(require 'markdown-overlays nil t)
(require 'acp-anthropic "agents/acp-anthropic")
(require 'acp-auggie "agents/acp-auggie")
(require 'acp-cline "agents/acp-cline")
(require 'acp-completion "features/acp-completion")
(require 'acp-cursor "agents/acp-cursor")
(require 'acp-devcontainer "features/acp-devcontainer")
(require 'acp-docker "features/acp-docker")
(require 'acp-diff "ui/acp-diff")
(require 'acp-droid "agents/acp-droid")
(require 'acp-github "features/acp-github")
(require 'acp-google "agents/acp-google")
(require 'acp-goose "agents/acp-goose")
(require 'acp-heartbeat "features/acp-heartbeat")
(require 'acp-active-message "ui/acp-active-message")
(require 'acp-kiro "agents/acp-kiro")
(require 'acp-mistral "agents/acp-mistral")
(require 'acp-openai "agents/acp-openai")
(require 'acp-opencode "agents/acp-opencode")
(require 'acp-pi "agents/acp-pi")
(require 'acp-project "features/acp-project")
(require 'acp-qwen "agents/acp-qwen")
(require 'acp-styles "ui/acp-styles")
(require 'acp-usage "features/acp-usage")
(require 'acp-worktree "features/acp-worktree")
(require 'acp-ui "ui/acp-ui")
(require 'acp-viewport "ui/acp-viewport")
(require 'image)
(require 'svg nil :noerror)
(require 'transient)

;; Optional flycheck integration (used in acp--get-flycheck-error-context)
(declare-function flycheck-overlay-errors-at "flycheck" (pos))
(declare-function flycheck-error-pos "flycheck" (err))
(declare-function flycheck-error-end-line "flycheck" (err))
(declare-function flycheck-error-end-column "flycheck" (err))
(declare-function flycheck-error-level "flycheck" (err))
(declare-function flycheck-error-message "flycheck" (err))
(declare-function flycheck-error-line "flycheck" (err))
(declare-function flycheck-error-column "flycheck" (err))

;; Declare as special so byte-compilation doesn't turn `let' bindings into
;; lexical bindings (which would not affect `auto-insert' behavior).
(defvar auto-insert)

(defcustom acp-permission-icon "⚠"
  "Icon displayed when shell commands require permission to execute.

You may use \"􀇾\" as an SF Symbol on macOS."
  :type 'string
  :group 'acp)

(defcustom acp-thought-process-icon "💡"
  "Icon displayed during the AI's thought process.

You may use \"􁷘\" as an SF Symbol on macOS."
  :type 'string
  :group 'acp)

(defcustom acp-thought-process-expand-by-default nil
  "Whether thought process sections should be expanded by default.

When nil (the default), thought process sections are collapsed.
When non-nil, thought process sections are expanded."
  :type 'boolean
  :group 'acp)

(defcustom acp-tool-use-expand-by-default nil
  "Whether tool use sections should be expanded by default.

When nil (the default), tool use sections are collapsed.
When non-nil, tool use sections are expanded."
  :type 'boolean
  :group 'acp)

(defvar acp-mode-hook nil
  "Hook run after an `acp-mode' buffer is fully initialized.
Runs after the buffer-local state has been set up, so it is safe to
call `acp-subscribe-to' and access `acp--state' here.")

(defvar acp-permission-responder-function nil
  "When non-nil, a function called before showing the permission prompt.

Return non-nil to indicate the request was handled (UI is skipped).
Return nil to fall back to the interactive permission dialog.

Called with an alist containing:

  :tool-call - the tool call alist with :title, :kind, :status,
               :permission-request-id, and optionally :diff
  :options   - enriched actions, each with :kind, :option-id,
               :label, :option, :char
  :respond   - function taking an option-id to respond programmatically

See `acp-permission-allow-always' for a built-in handler
that auto-approves all requests.

Example -- auto-approve reads:

  (setq acp-permission-responder-function
        (lambda (permission)
          (when-let (((equal (map-elt (map-elt permission :tool-call) :kind)
                             \"read\"))
                     (choice (seq-find
                               (lambda (option)
                                 (equal (map-elt option :kind) \"allow_once\"))
                               (map-elt permission :options))))
            (funcall (map-elt permission :respond)
                     (map-elt choice :option-id))
            t)))")

(defun acp-permission-allow-always (permission)
  "Auto-approve all PERMISSION requests.

Intended for use with `acp-permission-responder-function'.

Example:

  (setq acp-permission-responder-function
        #\\='acp-permission-allow-always)"
  (when-let ((choice (seq-find
                      (lambda (option) (equal (map-elt option :kind) "allow_once"))
                      (map-elt permission :options))))
    (funcall (map-elt permission :respond)
             (map-elt choice :option-id))
    t))

(defcustom acp-user-message-expand-by-default nil
  "Whether user message sections should be expanded by default.

When nil (the default), user message sections are collapsed.
When non-nil, user message sections are expanded."
  :type 'boolean
  :group 'acp)

(defcustom acp-show-config-icons t
  "Whether to show icons in agent config selection."
  :type 'boolean
  :group 'acp)

(defcustom acp-path-resolver-function nil
  "Function for resolving remote paths on the local file-system, and vice versa.

Expects a function that takes the path as its single argument, and
returns the resolved path.  Set to nil to disable mapping."
  :type 'function
  :group 'acp)

(defvaralias
  'acp-container-command-runner
  'acp-command-prefix)

(defcustom acp-command-prefix nil
  "Prefix to apply when executing agent commands and shell commands.

Can be a list of strings or a function or lambda that takes a buffer and
returns a list of strings.

Example for static list of strings:
  \\='(\"devcontainer\" \"exec\" \"--workspace-folder\" \".\")

Example for a lambda:
  (lambda (buffer)
    (let ((config (acp-get-config buffer)))
      (pcase (map-elt config :identifier)
        (\\='claude-code \\='(\"docker\" \"exec\" \"claude-dev\" \"--\"))
        (\\='gemini-cli \\='(\"docker\" \"exec\" \"gemini-dev\" \"--\"))
        (_ (error \"Unknown identifier\")))))"
  :type '(choice (repeat string) function)
  :group 'acp)

(defcustom acp-section-functions nil
  "Abnormal hook run after overlays are applied (experimental).
Called in `acp--update-fragment' after all overlays
are applied.  Each function is called with a range alist containing:
  :block       - The block range with :start and :end positions
  :body        - The body range (if present)
  :label-left  - The left label range (if present)
  :label-right - The right label range (if present)
  :padding     - The padding range with :start and :end (if present)"
  :type 'hook
  :group 'acp)

(defcustom acp-highlight-blocks nil
  "Whether or not to highlight source blocks.

Highlighting source blocks is currently turned off by default
as we need a more efficient mechanism.

See https://github.com/neopilot-ai/acp.el/issues/119"
  :type 'boolean
  :group 'acp)

(defcustom acp-confirm-interrupt t
  "Whether to prompt for confirmation before interrupting.

When non-nil (the default), `acp-interrupt' and related
commands ask \"Interrupt?\" via `y-or-n-p' before cancelling the
in-progress request.  Set to nil to interrupt immediately without
prompting."
  :type 'boolean
  :group 'acp)

(defun acp-interrupt-confirmed-p ()
  "Prompt the user to confirm an interrupt and return non-nil if confirmed.
When `acp-confirm-interrupt' is nil, skip the prompt and return t."
  (or (not acp-confirm-interrupt)
      (y-or-n-p "Interrupt?")))

(defcustom acp-context-sources '(files region error line)
  "Sources to consider when determining \\<acp-mode-map>\\[acp] automatic context.

Each element can be:
- A symbol: `files', `region', `error', or `line'
- A function: Called with no arguments, should return context or nil

Sources are checked in order until one returns non-nil."
  :type '(repeat (choice (const :tag "Buffer files" files)
                         (const :tag "Selected region" region)
                         (const :tag "Error at point" error)
                         (const :tag "Current line" line)
                         (function :tag "Custom function")))
  :group 'acp)

(cl-defun acp--make-acp-client (&key command
                                             command-params
                                             environment-variables
                                             context-buffer)
  "Create an ACP client.

COMMAND, COMMAND-PARAMS, ENVIRONMENT-VARIABLES, and CONTEXT-BUFFER are
passed through to `acp-make-client'."
  (let* ((full-command (append (list command) command-params))
         (wrapped-command (acp--build-command-for-execution full-command)))
    (acp-make-client :command (car wrapped-command)
                     :command-params (cdr wrapped-command)
                     :environment-variables environment-variables
                     :context-buffer context-buffer
                     :outgoing-request-decorator (when context-buffer
                                                   (map-elt (buffer-local-value 'acp--state context-buffer)
                                                            :outgoing-request-decorator)))))

(defcustom acp-text-file-capabilities t
  "Whether agents are initialized with read/write text file capabilities.

See `acp-make-initialize-request' for details."
  :type 'boolean
  :group 'acp)

(defcustom acp-write-inhibit-minor-modes '(aggressive-indent-mode)
  "List of minor mode commands to inhibit during `fs/write_text_file' edits.

Each element is a minor mode command symbol, such as
`aggressive-indent-mode'.

Agent Shell disables any listed modes that are enabled in the target
buffer before applying `fs/write_text_file' edits, and then restores
them.

Modes whose variables are not buffer-local in the target buffer (for
example, globalized minor modes) are ignored."
  :type '(repeat symbol)
  :group 'acp)

(defcustom acp-display-action
  '(display-buffer-same-window)
  "Display action for agent shell buffers.
See `display-buffer' for the format of display actions."
  :type '(cons (repeat function) alist)
  :group 'acp)

(defcustom acp-prefer-viewport-interaction nil
  "Non-nil makes `acp' prefer viewport interaction over shell interaction.

For example, `acp-send*' will insert text into the viewport
buffer instead of the shell buffer.  If no viewport buffer exists, one
will be created."
  :type 'boolean
  :group 'acp)

(defcustom acp-embed-file-size-limit 102400
  "Maximum file size in bytes for embedding with ContentBlock::Resource.
Files larger than this will use ContentBlock::ResourceLink instead.
Default is 100KB (102400 bytes)."
  :type 'integer
  :group 'acp)

(defcustom acp-header-style (if (display-graphic-p) 'graphical 'text)
  "Style for agent shell buffer headers.

Can be one of:

 \='graphical: Display header with icon and styled text.
 \='text: Display simple text-only header.
 nil: Display no header."
  :type '(choice (const :tag "Graphical" graphical)
                 (const :tag "Text only" text)
                 (const :tag "No header" nil))
  :group 'acp)

(defcustom acp-show-session-id nil
  "Non-nil to display the session ID in the header and session selection.

When enabled, the session ID is shown after the directory path in the
header and as an additional column in the session selection prompt.
Only appears when a session is active."
  :type 'boolean
  :group 'acp)

(defcustom acp-show-welcome-message t
  "Non-nil to show welcome message."
  :type 'boolean
  :group 'acp)

(defcustom acp-show-busy-indicator t
  "Non-nil to show the busy indicator animation in the header and mode line."
  :type 'boolean
  :group 'acp)

(defcustom acp-busy-indicator-frames 'wide
  "Frames for the busy indicator animation.
Can be a symbol selecting a predefined style, or a list of frame strings.
When providing custom frames, do not include leading spaces as padding
is added automatically."
  :type '(choice (const :tag "Wave (pulses up and down)" wave)
                 (const :tag "Dots Block (circular spin)" dots-block)
                 (const :tag "Dots Round (circular spin)" dots-round)
                 (const :tag "Wide (horizontal blocks)" wide)
                 (repeat :tag "Custom frames" string))
  :group 'acp)

(defcustom acp-screenshot-command
  (if (eq system-type 'darwin)
      '("/usr/sbin/screencapture" "-i")
    ;; ImageMagick is common on Linux and many other *nix systems.
    '("/usr/bin/import"))
  "The program to use for capturing screenshots.

Assume screenshot file path will be appended to this list."
  :type '(repeat string)
  :group 'acp)

(defcustom acp-clipboard-image-handlers
  (list
   (list (cons :command "pngpaste")
         (cons :save (lambda (file-path)
                       (let ((exit-code (call-process "pngpaste" nil nil nil file-path)))
                         (unless (zerop exit-code)
                           (error "Command pngpaste failed with exit code %d" exit-code))))))
   (list (cons :command "xclip")
         (cons :save (lambda (file-path)
                       (when-let* ((targets (and (eq (window-system) 'x)
                                                 (gui-get-selection 'CLIPBOARD 'TARGETS)))
                                   ((vectorp targets))
                                   ((not (seq-contains-p targets 'image/png))))
                         (error "No image/png in clipboard"))
                       (with-temp-buffer
                         (set-buffer-multibyte nil)
                         (let ((exit-code (call-process "xclip" nil t nil
                                                        "-selection" "clipboard"
                                                        "-t" "image/png" "-o")))
                           (unless (zerop exit-code)
                             (error "Command xclip failed with exit code %d" exit-code))
                           (write-region (point-min) (point-max) file-path nil 'silent)))))))
  "Handlers for saving clipboard images to a file.

Each handler is an alist with the following keys:

  :command  The executable name to look up via `executable-find'.
  :save     A function taking FILE-PATH that saves the clipboard
            image there, signaling an error on failure.

Handlers are tried in order.  The first whose :command is found
on the system is used."
  :type '(repeat (alist :key-type symbol :value-type sexp))
  :group 'acp)

(defcustom acp-buffer-name-format 'default
  "Format to use when generating agent shell buffer names.

Each element can be:
- Default: For example \='Claude Agent @ My Project\='
- Kebab case: For example \='claude-agent @ my-project\='
- A function: Called with agent name and project name."
  :type '(choice (const :tag "Default" default)
                 (const :tag "Kebab case" kebab-case)
                 (function :tag "Custom format"))
  :group 'acp)

;;;###autoload
(cl-defun acp-make-agent-config (&key identifier
                                              mode-line-name welcome-function
                                              buffer-name shell-prompt shell-prompt-regexp
                                              client-maker
                                              needs-authentication
                                              authenticate-request-maker
                                              default-model-id
                                              default-session-mode-id
                                              icon-name
                                              install-instructions)
  "Create an agent configuration alist.

Keyword arguments:
- IDENTIFIER: Symbol identifying agent type (e.g., \\='claude-code)
- MODE-LINE-NAME: Name to display in the mode line
- WELCOME-FUNCTION: Function to call for welcome message
- BUFFER-NAME: Name of the agent buffer
- SHELL-PROMPT: The shell prompt string
- SHELL-PROMPT-REGEXP: Regexp to match the shell prompt
- CLIENT-MAKER: Function to create the client
- NEEDS-AUTHENTICATION: Non-nil authentication is required
- AUTHENTICATE-REQUEST-MAKER: Function to create authentication requests
- DEFAULT-MODEL-ID: Default model ID (function returning value).
- DEFAULT-SESSION-MODE-ID: Default session mode ID (function returning value).
- ICON-NAME: Name of the icon to use
- INSTALL-INSTRUCTIONS: Instructions to show when executable is not found

Returns an alist with all specified values."
  `((:identifier . ,identifier)
    (:mode-line-name . ,mode-line-name)
    (:welcome-function . ,welcome-function)                     ;; function
    (:buffer-name . ,buffer-name)
    (:shell-prompt . ,shell-prompt)
    (:shell-prompt-regexp . ,shell-prompt-regexp)
    (:client-maker . ,client-maker)                             ;; function
    (:needs-authentication . ,needs-authentication)
    (:authenticate-request-maker . ,authenticate-request-maker) ;; function
    (:default-model-id . ,default-model-id)                     ;; function
    (:default-session-mode-id . ,default-session-mode-id)       ;; function
    (:icon-name . ,icon-name)
    (:install-instructions . ,install-instructions)))

(defun acp--make-default-agent-configs ()
  "Create a list of default agent configs.

This function aggregates agents from OpenAI, Anthropic, Google,
Goose, Cursor, Auggie, and others."
  (list (acp-auggie-make-agent-config)
        (acp-anthropic-make-claude-code-config)
        (acp-cline-make-agent-config)
        (acp-openai-make-codex-config)
        (acp-cursor-make-agent-config)
        (acp-droid-make-agent-config)
        (acp-github-make-copilot-config)
        (acp-google-make-gemini-config)
        (acp-goose-make-agent-config)
        (acp-kiro-make-config)
        (acp-mistral-make-config)
        (acp-opencode-make-agent-config)
        (acp-pi-make-agent-config)
        (acp-qwen-make-agent-config)))

(defcustom acp-agent-configs
  (acp--make-default-agent-configs)
  "The list of known agent configurations.

See `acp-*-make-*-config' for details."
  :type '(repeat (alist :key-type symbol :value-type sexp))
  :group 'acp)

(defcustom acp-preferred-agent-config nil
  "Default agent to use for all new shells.

If this is set, `acp' will unconditionally use this
agent and not prompt you to select one.

Can be set to a symbol identifier (e.g., `claude-code') or a full
configuration alist for backwards compatibility."
  :type '(choice (const :tag "None (prompt each time)" nil)
                 (const :tag "Auggie" auggie)
                 (const :tag "Claude Code" claude-code)
                 (const :tag "Cline" cline)
                 (const :tag "Codex" codex)
                 (const :tag "Copilot" copilot)
                 (const :tag "Cursor" cursor)
                 (const :tag "Droid" droid)
                 (const :tag "Gemini CLI" gemini-cli)
                 (const :tag "Goose" goose)
                 (const :tag "Kiro" kiro)
                 (const :tag "Mistral" le-chat)
                 (const :tag "OpenCode" opencode)
                 (const :tag "Pi" pi)
                 (const :tag "Qwen Code" qwen-code)
                 (symbol :tag "Custom identifier")
                 (alist :tag "Full configuration (legacy)"
                        :key-type symbol :value-type sexp))
  :group 'acp)

(defcustom acp-prefer-session-resume t
  "Prefer ACP session resume over session load when both are available.

When non-nil (and supported by agent), prefer ACP session resumes over loading."
  :type 'boolean
  :group 'acp)

(defcustom acp-session-strategy 'prompt
  "How to handle sessions when starting a new shell.

Available values:

  `new-deferred': Start a new session, but defer initialization until the
                  first prompt is submitted.
  `new': Always start a new session.
  `latest': Always load/resume the latest session.
  `prompt': Always prompt to choose a session (or start a new one)."
  :type '(choice (const :tag "New session, deferred init" new-deferred)
                 (const :tag "Always start new session" new)
                 (const :tag "Load latest session" latest)
                 (const :tag "Prompt for session" prompt))
  :group 'acp)

(defcustom acp-outgoing-request-decorator nil
  "Function to decorate outgoing ACP requests before they are sent.

When non-nil, this function is called with each outgoing request alist
and must return the (possibly modified) request.  This is useful for
injecting agent-specific metadata (e.g. system prompt extensions) into
requests.

The function receives the full request alist (with :method, :params, etc.)
and should return the decorated request.  Returning nil is treated as an
error and the original request is sent unchanged.

This is passed through to `acp-make-client' as :outgoing-request-decorator.
The keyword argument to `acp-start' takes precedence over this
variable when both are set."
  :type '(choice (const :tag "None" nil)
                 function)
  :group 'acp)

(defun acp--resolve-preferred-config ()
  "Resolve `acp-preferred-agent-config' to a full configuration.

If the value is a symbol, look it up in `acp-agent-configs'.
If it's already an alist (legacy format), return it as-is.
Returns nil if no matching configuration is found."
  (cond
   ((null acp-preferred-agent-config) nil)
   ((symbolp acp-preferred-agent-config)
    (seq-find (lambda (config)
                (eq (map-elt config :identifier)
                    acp-preferred-agent-config))
              acp-agent-configs))
   ((listp acp-preferred-agent-config)
    acp-preferred-agent-config)))

(defcustom acp-mcp-servers nil
  "List of MCP servers to initialize when creating a new session.

Each element should be an alist representing an MCP server configuration
following the ACP schema for McpServer as defined at:

https://agentclientprotocol.com/protocol/schema#mcpserver

The schema supports three transport variants:

1. Stdio Transport (universally supported):
   ((name . \"server-name\")
    (command . \"/path/to/executable\")
    (args . (\"arg1\" \"arg2\"))
    (env . (((name . \"ENV_VAR\") (value . \"value\")))))

2. HTTP Transport (requires mcpCapabilities.http):
   ((name . \"server-name\")
    (type . \"http\")
    (url . \"https://example.com/mcp\")
    (headers . (((name . \"Authorization\") (value . \"Bearer token\")))))

3. SSE Transport (requires mcpCapabilities.sse):
   ((name . \"server-name\")
    (type . \"sse\")
    (url . \"https://example.com/mcp\")
    (headers . (((name . \"Authorization\") (value . \"Bearer token\")))))

Example configuration with multiple servers:

  (setq acp-mcp-servers
        \='(((name . \"notion\")
           (type . \"http\")
           (url . \"https://mcp.notion.com/mcp\")
           (headers . ()))
          ((name . \"filesystem\")
           (command . \"npx\")
           (args . (\"-y\"
                    \"@modelcontextprotocol/server-filesystem\" \"/tmp\"))
           (env . ()))))

Lambdas can be used anywhere in the configuration hierarchy for dynamic
evaluation at session startup time.  This is useful for values that
depend on runtime context like the current working directory
\(`acp-cwd').  Note: only lambdas are evaluated, not named
functions, to avoid accidentally calling external symbols.

For example, using the `claude-code-ide' package (see its documentation
for more details), you can embed a lambda for the URL that registers
the session and returns the appropriate endpoint:

  (setq acp-mcp-servers
        \='(((name . \"emacs\")
           (type . \"http\")
           (headers . ())
           (url . (lambda ()
                    (require \='claude-code-ide-mcp-server)
                    (let* ((project-dir (acp-cwd))
                           (session-id (format \"acp-%s-%s\"
                                         (file-name-nondirectory
                                           (directory-file-name project-dir))
                                         (format-time-string \"%Y%m%d-%H%M%S\"))))
                      (puthash session-id `(:project-dir ,project-dir)
                               claude-code-ide-mcp-server--sessions)
                      (format \"http://localhost:%d/mcp/%s\"
                              (claude-code-ide-mcp-server-ensure-server)
                              session-id)))))))"
  :type '(repeat (choice (alist :key-type symbol :value-type sexp) function))
  :group 'acp)

(cl-defun acp--make-state (&key agent-config buffer client-maker needs-authentication authenticate-request-maker heartbeat outgoing-request-decorator)
  "Construct shell agent state with AGENT-CONFIG and BUFFER.

Shell state is provider-dependent and needs CLIENT-MAKER, NEEDS-AUTHENTICATION,
HEARTBEAT, AUTHENTICATE-REQUEST-MAKER, and optionally
OUTGOING-REQUEST-DECORATOR (passed through to `acp-make-client')."
  (list (cons :agent-config agent-config)
        (cons :buffer buffer)
        (cons :client nil)
        (cons :client-maker client-maker)
        (cons :outgoing-request-decorator outgoing-request-decorator)
        (cons :heartbeat heartbeat)
        (cons :initialized nil)
        (cons :needs-authentication needs-authentication)
        (cons :authenticate-request-maker authenticate-request-maker)
        (cons :authenticated nil)
        (cons :set-model nil)
        (cons :set-session-mode nil)
        (cons :session (list (cons :id nil)
                             (cons :mode-id nil)
                             (cons :modes nil)))
        (cons :last-entry-type nil)
        (cons :chunked-group-count 0)
        (cons :request-count 0)
        (cons :tool-calls nil)
        (cons :available-commands nil)
        (cons :available-modes nil)
        (cons :supports-session-list nil)
        (cons :supports-session-load nil)
        (cons :supports-session-resume nil)
        (cons :resume-session-id nil)
        (cons :prompt-capabilities nil)
        (cons :event-subscriptions nil)
        (cons :active-requests nil)
        (cons :pending-requests nil)
        (cons :usage (list (cons :total-tokens 0)
                           (cons :input-tokens 0)
                           (cons :output-tokens 0)
                           (cons :thought-tokens 0)
                           (cons :cached-read-tokens 0)
                           (cons :cached-write-tokens 0)
                           (cons :context-used 0)
                           (cons :context-size 0)
                           (cons :cost-amount 0.0)
                           (cons :cost-currency nil)))))

(defvar-local acp--state
    (acp--make-state))

(defvar-local acp--transcript-file nil
  "Path to the shell's transcript file.")

(defvar acp--shell-maker-config nil)

;;;###autoload
(defun acp (&optional arg)
  "Start or reuse an existing agent shell.

`acp' carries some DWIM (do what I mean) behaviour.

If in a project without a shell, offer to create one.

If already in a shell, invoke `acp-toggle'.

If a region is active or point is on relevant context (ie.
`dired' files or image buffers), carry them over to the
shell input.

See `acp-context-sources' on how to control DWIM
behaviour.

With \\[universal-argument] prefix ARG, force start a new shell.

With \\[universal-argument] \\[universal-argument] prefix ARG, prompt to pick an existing shell."
  (interactive "P")
  (cond
   ((equal arg '(16))
    (acp--dwim :switch-to-shell t))
   ((equal arg '(4))
    (acp--dwim :new-shell t))
   (t
    (acp--dwim))))

(cl-defun acp--dwim (&key config new-shell switch-to-shell)
  "Start or reuse an agent shell with DWIM behavior.

CONFIG is the agent configuration to use.
NEW-SHELL when non-nil forces starting a new shell.
SWITCH-TO-SHELL when non-nil prompts to pick an existing shell.

NEW-SHELL and SWITCH-TO-SHELL are mutually exclusive.

This function respects `acp-prefer-viewport-interaction' and
handles viewport mode detection, existing shell reuse, and project context."
  (when (and new-shell switch-to-shell)
    (error ":new-shell and :switch-to-shell are mutually exclusive"))
  (if acp-prefer-viewport-interaction
      (if (and (not new-shell)
               (or (derived-mode-p 'acp-viewport-view-mode)
                   (derived-mode-p 'acp-viewport-edit-mode)))
          (acp-toggle)
        (let* ((shell-buffer
                (cond (switch-to-shell
                       (get-buffer
                        (completing-read "Switch to shell: "
                                         (mapcar #'buffer-name (or (acp-buffers)
                                                                   (user-error "No shells available")))
                                         nil t)))
                      (new-shell
                       (acp--start :config (or config
                                                       (acp--resolve-preferred-config)
                                                       (acp-select-config
                                                        :prompt "Start new agent: ")
                                                       (error "No agent config found"))
                                           :no-focus t
                                           :new-session t))
                      (t
                       (acp--shell-buffer))))
               (text (acp--context :shell-buffer shell-buffer)))
          (if (and (eq (buffer-local-value 'acp-session-strategy shell-buffer) 'prompt)
                   (not (map-nested-elt (buffer-local-value 'acp--state shell-buffer)
                                        '(:session :id))))
              ;; Defer viewport display until session is selected.
              (acp-subscribe-to
               :shell-buffer shell-buffer
               :event 'session-selected
               :on-event (lambda (_event)
                           (acp-viewport--show-buffer
                            :append text
                            :shell-buffer shell-buffer)))
            (acp-viewport--show-buffer
             :append text
             :shell-buffer shell-buffer))))
    (cond (switch-to-shell
           (let* ((shell-buffer
                   (get-buffer
                    (completing-read "Switch to shell: "
                                     (mapcar #'buffer-name (or (acp-buffers)
                                                               (user-error "No shells available")))
                                     nil t)))
                  (text (acp--context :shell-buffer shell-buffer)))
             (acp--display-buffer shell-buffer)
             (when text
               (acp--insert-to-shell-buffer :text text
                                                    :shell-buffer shell-buffer))))
          (new-shell
           (acp-start :config (or config
                                          (acp--resolve-preferred-config)
                                          (acp-select-config
                                           :prompt "Start new agent: ")
                                          (error "No agent config found"))))
          (t
           (if (derived-mode-p 'acp-mode)
               (let* ((shell-buffer (acp--shell-buffer :no-create t))
                      (text (acp--context :shell-buffer shell-buffer)))
                 (acp-toggle)
                 (when text
                   (acp--insert-to-shell-buffer :text text
                                                        :shell-buffer shell-buffer)))
             (let* ((shell-buffer (acp--shell-buffer))
                    (text (acp--context :shell-buffer shell-buffer)))
               (if (and (eq (buffer-local-value 'acp-session-strategy shell-buffer) 'prompt)
                        (not (map-nested-elt (buffer-local-value 'acp--state shell-buffer)
                                             '(:session :id))))
                   ;; Defer viewport display until session is selected.
                   (acp-subscribe-to
                    :shell-buffer shell-buffer
                    :event 'session-selected
                    :on-event (lambda (_event)
                                (acp--display-buffer shell-buffer)
                                (when text
                                  (acp--insert-to-shell-buffer :text text
                                                                       :shell-buffer shell-buffer))))
                 (acp--display-buffer shell-buffer)
                 (when text
                   (acp--insert-to-shell-buffer :text text
                                                        :shell-buffer shell-buffer)))))))))

;;;###autoload
(defun acp-toggle ()
  "Toggle agent shell display."
  (interactive)
  (let ((shell-buffer (if acp-prefer-viewport-interaction
                          (acp-viewport--buffer)
                        (or (acp--current-shell)
                            (seq-first (acp-project-buffers))
                            (seq-first (acp-buffers))))))
    (unless shell-buffer
      (user-error "No agent shell buffers available for current project"))
    (if-let ((window (get-buffer-window shell-buffer)))
        (if (and (> (count-windows) 1)
                 (not (bound-and-true-p transient--prefix)))
            (delete-window window)
          (switch-to-prev-buffer))
      (acp--display-buffer shell-buffer))))

;;;###autoload
(defun acp-new-shell ()
  "Start a new agent shell.

Always prompts for agent selection, even if existing shells are available."
  (interactive)
  (acp '(4)))

;;;###autoload
(cl-defun acp-restart (&key session-id)
  "Clear conversation by restarting the agent shell in the same project.

Kills the current shell buffer (shutting down the ACP client) and
starts a fresh shell with the same agent configuration.

When SESSION-ID is provided, resume that session instead of starting new.

Works from both shell and viewport buffers."
  (declare (modes acp-mode
                  acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (let* ((from-viewport (or (derived-mode-p 'acp-viewport-view-mode)
                            (derived-mode-p 'acp-viewport-edit-mode)))
         (shell-buffer (or (acp--current-shell)
                           (user-error "Not in a shell or viewport buffer")))
         (strategy (if (eq (buffer-local-value 'acp-session-strategy shell-buffer)
                           'new-deferred)
                       'new-deferred
                     'new))
         (config (map-elt (buffer-local-value 'acp--state shell-buffer)
                          :agent-config)))
    (with-current-buffer shell-buffer
      (when (and (acp--active-requests-p (acp--state))
                 (not (y-or-n-p "Agent is busy.  Restart anyway?")))
        (user-error "Cancelled")))
    (kill-buffer shell-buffer)
    (let ((new-shell-buffer (acp--start
                             :config config
                             :session-strategy strategy
                             :session-id session-id
                             :new-session t
                             :no-focus t)))
      (if (or from-viewport acp-prefer-viewport-interaction)
          (acp-viewport--show-buffer
           :shell-buffer new-shell-buffer)
        (acp--display-buffer new-shell-buffer)))))

;;;###autoload
(defun acp-reload ()
  "Reload the current session by restarting with the same session ID.

Works from both shell and viewport buffers."
  (declare (modes acp-mode
                  acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (let* ((shell-buffer (or (acp--current-shell)
                           (user-error "Not in a shell or viewport buffer")))
         (session-id (map-nested-elt (buffer-local-value 'acp--state shell-buffer)
                                     '(:session :id))))
    (unless session-id
      (user-error "No active session to reload"))
    (acp-restart :session-id session-id)))

;;;###autoload
(defun acp-resume-session (session-id)
  "Resume an existing agent session by SESSION-ID.

Prompts for agent selection and starts a new shell that resumes
the session identified by SESSION-ID."
  (interactive "sSession ID: ")
  (when (string-empty-p (string-trim session-id))
    (user-error "Session ID cannot be empty"))
  (acp--start :config (or (acp--resolve-preferred-config)
                                  (acp-select-config
                                   :prompt "Resume with agent: ")
                                  (error "No agent config found"))
                      :session-id session-id
                      :new-session t))

;;;###autoload
(defun acp-prompt-compose ()
  "Compose an `acp' prompt in a dedicated buffer.

If currently visiting an `acp', transfer latest input."
  (interactive)
  (if-let (((derived-mode-p 'acp-mode))
           ((shell-maker-point-at-last-prompt-p))
           (input (acp--input)))
      (progn
        ;; Clear shell prompt as it's now
        ;; transferred to the compose buffer.
        (comint-kill-input)
        (acp-viewport--show-buffer :override input))
    (acp-viewport--show-buffer)))

(cl-defun acp-start (&key config session-id outgoing-request-decorator)
  "Programmatically start shell with CONFIG.

See `acp-make-agent-config' for config format.

SESSION-ID resumes an existing session by its id string.
OUTGOING-REQUEST-DECORATOR is an optional function passed through to
`acp-make-client'.  See its docstring for details."
  (acp--start :config config
                      :no-focus nil
                      :new-session t
                      :session-id session-id
                      :outgoing-request-decorator outgoing-request-decorator))

(cl-defun acp--config-icon (&key config)
  "Create icon string for CONFIG if available and icons are enabled.
Returns nil if no icon should be displayed."
  (and-let* ((graphics-capable (display-graphic-p))
             (icon-filename (if (map-elt config :icon-name)
                                (acp--fetch-agent-icon
                                 (map-elt config :icon-name))
                              (acp--make-agent-fallback-icon
                               (map-elt config :buffer-name) 100))))
    (with-temp-buffer
      (insert-image (create-image icon-filename nil nil
                                  :ascent 'center
                                  :height (frame-char-height)))
      (buffer-string))))

(cl-defun acp-select-config (&key prompt)
  "Display PROMPT to select an agent config from `acp-agent-configs'."
  (let* ((configs acp-agent-configs)
         (choices (mapcar (lambda (config)
                            (let ((display-name (or (map-elt config :mode-line-name)
                                                    (map-elt config :buffer-name)
                                                    "Unknown Agent"))
                                  (icon (when acp-show-config-icons
                                          (acp--config-icon :config config))))
                              (cons (concat icon (when icon " ") display-name)
                                    config)))
                          configs))
         (selected-name (completing-read (or prompt "Select agent: ") choices nil t)))
    (map-elt choices selected-name)))

(defun acp-buffers ()
  "Return all shell buffers ordered by recent access.
Includes shells accessed via viewport buffers, preserving visited order."
  (let (shell-buffers seen)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (when-let ((shell-buffer
                    (cond ((derived-mode-p 'acp-mode)
                           buffer)
                          ((or (derived-mode-p 'acp-viewport-view-mode)
                               (derived-mode-p 'acp-viewport-edit-mode))
                           (acp-viewport--shell-buffer buffer)))))
          (unless (memq shell-buffer seen)
            (push shell-buffer seen)
            (push shell-buffer shell-buffers)))))
    (nreverse shell-buffers)))

(defun acp-other-buffer ()
  "Switch to other associated buffer (viewport vs shell)."
  (declare (modes acp-mode
                  acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (cond ((or (derived-mode-p 'acp-viewport-view-mode)
             (derived-mode-p 'acp-viewport-edit-mode))
         (switch-to-buffer (or (acp--shell-buffer
                                :viewport-buffer (current-buffer)
                                :no-create t)
                               "No shell available")))
        ((derived-mode-p 'acp-mode)
         (when-let ((viewport-buffer (or (acp-viewport--buffer
                                          :shell-buffer (current-buffer))
                                         "Not in a shell viewport buffer")))
           (with-current-buffer viewport-buffer
             (when (derived-mode-p 'acp-viewport-view-mode)
               (acp-viewport-refresh)))
           (switch-to-buffer viewport-buffer)))
        (t
         (user-error "Not in an acp buffer"))))

(defun acp-version ()
  "Show `acp' mode version."
  (interactive)
  (message "acp v%s" acp--version))

(defun acp-copy-session-id ()
  "Copy the current session ID to the kill ring."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (user-error "Not in a shell"))
  (if-let (session-id (map-nested-elt (acp--state) '(:session :id)))
      (progn
        (kill-new session-id)
        (message "Copied session ID: %s" session-id))
    (user-error "No active session")))

(defun acp-interrupt (&optional force)
  "Interrupt in-progress request and reject all pending permissions.
When FORCE is non-nil, skip confirmation prompt.
See also `acp-confirm-interrupt'."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (cond ((map-nested-elt (acp--state) '(:session :id))
         (when (or force (acp-interrupt-confirmed-p))
           ;; First cancel all pending permission requests
           (map-do
            (lambda (tool-call-id tool-call-data)
              (when (map-elt tool-call-data :permission-request-id)
                (acp--send-permission-response
                 :client (map-elt (acp--state) :client)
                 :request-id (map-elt tool-call-data :permission-request-id)
                 :cancelled t
                 :state (acp--state)
                 :tool-call-id tool-call-id)))
            (map-elt (acp--state) :tool-calls))
           ;; Then send the cancel notification
           (acp-send-notification
            :client (map-elt (acp--state) :client)
            :notification (acp-make-session-cancel-notification
                           :session-id (map-nested-elt (acp--state) '(:session :id))
                           :reason "User cancelled"))))
        (t
         (acp--shutdown)
         (call-interactively #'shell-maker-interrupt))))

(cl-defun acp--make-shell-maker-config (&key prompt prompt-regexp)
  "Create `shell-maker' configuration with PROMPT and PROMPT-REGEXP."
  (make-shell-maker-config
   :name "agent"
   :prompt prompt
   :prompt-regexp prompt-regexp
   :execute-command
   (lambda (command shell)
     (acp--handle
      :command command
      :shell-buffer (map-elt shell :buffer)))))

(defun acp--filter-buffer-substring (start end &optional delete)
  "Return the buffer substring between START and END, after filtering.
Strip the text properties `line-prefix' and `wrap-prefix' from the
copied substring.  If DELETE is non-nil, delete the text between START
and END from the buffer."
  (let ((text (if delete
                  (prog1 (buffer-substring start end)
                    (delete-region start end))
                (buffer-substring start end))))
    (remove-text-properties 0 (length text)
                            '(line-prefix nil wrap-prefix nil)
                            text)
    text))

(when (featurep 'shell-maker)
  (defvar-keymap acp-mode-map
    :parent shell-maker-mode-map
    :doc "Keymap for `acp-mode'."
    "TAB" #'acp-next-item
    "<backtab>" #'acp-previous-item
    "n" #'acp-next-item
    "p" #'acp-previous-item
    "C-<tab>" #'acp-cycle-session-mode
    "C-c C-c" #'acp-interrupt
    "C-c C-m" #'acp-set-session-mode
    "C-c C-v" #'acp-set-session-model
    "C-c C-o" #'acp-other-buffer
    "<remap> <yank>" #'acp-yank-dwim)

  (shell-maker-define-major-mode (acp--make-shell-maker-config) acp-mode-map))

(cl-defun acp--handle (&key command shell-buffer)
  "Handle SHELL-BUFFER COMMAND (and lazy initialize the ACP stack).

SHELL-BUFFER is the shell buffer.

Flow:

  Before a shell COMMAND can be sent as a prompt to the agent, a
  handful of ACP initialization steps must take place (some asynchronously).
  Once all initialization steps are cleared, only then the COMMAND
  can be sent to the agent as a prompt (thus recursive nature of this function).

  -> Initialize ACP client
      |-> Subscribe to ACP events
           |-> Initiate handshake (ie.  initialize RPC)
                |-> Authenticate (optional)
                     |-> Start prompt session
                          |-> Send COMMAND/prompt (finally!)"
  (with-current-buffer shell-buffer
    (unless (derived-mode-p 'acp-mode)
      (error "Not in a shell"))
    (when (and command
               (not (eq acp-session-strategy 'new-deferred))
               (not (map-nested-elt (acp--state) '(:session :id))))
      (user-error "Session not ready... please wait"))
    (map-put! (acp--state) :request-count
              ;; TODO: Make public in shell-maker.
              (shell-maker--current-request-id))
    (cond ((not (map-elt (acp--state) :client))
           ;; Needs a client
           (acp--emit-event :event 'init-started)
           (when (and acp-show-busy-indicator
                      (not command))
             (acp-heartbeat-start
              :heartbeat (map-elt acp--state :heartbeat)))
           (when-let ((viewport-buffer (acp-viewport--buffer
                                        :shell-buffer shell-buffer
                                        :existing-only t)))
             (with-current-buffer viewport-buffer
               (acp-viewport-view-mode)
               (acp-viewport--initialize
                :prompt  command
                :response (acp-viewport--response))))
           (when (acp--initialize-client)
             (acp--handle :command command :shell-buffer shell-buffer)))
          ;; Needs ACP subscriptions
          ((or (not (map-nested-elt (acp--state) '(:client :request-handlers)))
               (not (map-nested-elt (acp--state) '(:client :notification-handlers)))
               (not (map-nested-elt (acp--state) '(:client :error-handlers))))
           (when (acp--initialize-subscriptions)
             (acp--handle :command command :shell-buffer shell-buffer)))
          ;; Needs to send ACP initialize request
          ((not (map-elt (acp--state) :initialized))
           (acp--initiate-handshake
            :shell-buffer shell-buffer
            :on-initiated (lambda ()
                            (map-put! (acp--state) :initialized t)
                            (acp--handle :command command :shell-buffer shell-buffer))))
          ;; Needs to send ACP authenticate request (optional)
          ((and (map-elt (acp--state) :needs-authentication)
                (not (map-elt (acp--state) :authenticated)))
           (acp--authenticate
            :shell-buffer shell-buffer
            :on-authenticated (lambda ()
                                (map-put! (acp--state) :authenticated t)
                                (acp--handle :command command :shell-buffer shell-buffer))))
          ;; Needs to send ACP new session request
          ((not (map-nested-elt (acp--state) '(:session :id)))
           (acp--initiate-session
            :shell-buffer shell-buffer
            :on-session-init (lambda ()
                               ;; Session is now initiated.
                               ;; Consider bootstrapping/handshake complete.
                               ;; Show shell prompt.
                               (unless command
                                 (acp-heartbeat-stop
                                  :heartbeat (map-elt acp--state :heartbeat))
                                 (when (seq-empty-p (map-elt (acp--state) :available-commands))
                                   ;; Setting an "available commands" placeholder fragment before
                                   ;; displaying the prompt (shell-maker-finish-output).
                                   ;; This enables updating the placeholder even if the notification
                                   ;; arrives after bootstrapping prompt is displayed.
                                   (acp--update-fragment
                                    :state (acp--state)
                                    :namespace-id "bootstrapping"
                                    :block-id "available_commands_update"
                                    :label-left (propertize "Available /commands" 'font-lock-face 'font-lock-doc-markup-face)))
                                 (when (and (map-nested-elt (acp--state) '(:agent-config :default-model-id))
                                            (funcall (map-nested-elt (acp--state)
                                                                     '(:agent-config :default-model-id)))
                                            (not (map-elt (acp--state) :set-model)))
                                   ;; Setting a "Setting model" placeholder fragment before
                                   ;; displaying the prompt (shell-maker-finish-output).
                                   ;; This enables updating the placeholder even if the response
                                   ;; arrives after bootstrapping prompt is displayed.
                                   (acp--update-fragment
                                    :state (acp--state)
                                    :namespace-id "bootstrapping"
                                    :block-id "set-model"
                                    :label-left (propertize "Setting model" 'font-lock-face 'font-lock-doc-markup-face)
                                    :body (format "Requesting %s..."
                                                  (funcall (map-nested-elt (acp--state)
                                                                           '(:agent-config :default-model-id))))))
                                 (when (and (map-nested-elt (acp--state) '(:agent-config :default-session-mode-id))
                                            (funcall (map-nested-elt (acp--state)
                                                                     '(:agent-config :default-session-mode-id)))
                                            (not (map-elt (acp--state) :set-session-mode)))
                                   ;; Setting a "Setting session mode" placeholder fragment before
                                   ;; displaying the prompt (shell-maker-finish-output).
                                   ;; This enables updating the placeholder even if the response
                                   ;; arrives after bootstrapping prompt is displayed.
                                   (acp--update-fragment
                                    :state (acp--state)
                                    :namespace-id "bootstrapping"
                                    :block-id "set-session-mode"
                                    :label-left (propertize "Setting session mode" 'font-lock-face 'font-lock-doc-markup-face)
                                    :body (format "Requesting %s..."
                                                  (funcall (map-nested-elt (acp--state)
                                                                           '(:agent-config :default-session-mode-id))))))
                                 (shell-maker-finish-output :config shell-maker--config
                                                            :success nil)
                                 (acp--emit-event :event 'prompt-ready))
                               (acp--handle :command command :shell-buffer shell-buffer))))
          ;; Send ACP request to set default model (optional)
          ((and (map-nested-elt (acp--state) '(:agent-config :default-model-id))
                (funcall (map-nested-elt (acp--state)
                                         '(:agent-config :default-model-id)))
                (not (map-elt (acp--state) :set-model)))
           (acp--set-default-model
            :shell-buffer shell-buffer
            :model-id (funcall (map-nested-elt (acp--state)
                                               '(:agent-config :default-model-id)))
            :on-model-changed (lambda ()
                                (map-put! (acp--state) :set-model t)
                                (acp--handle :command command :shell-buffer shell-buffer))))
          ;; Send ACP request to set default session mode (optional)
          ((and (map-nested-elt (acp--state) '(:agent-config :default-session-mode-id))
                (funcall (map-nested-elt (acp--state) '(:agent-config :default-session-mode-id)))
                (not (map-elt (acp--state) :set-session-mode)))
           (acp--set-default-session-mode
            :shell-buffer shell-buffer
            :mode-id (funcall (map-nested-elt (acp--state) '(:agent-config :default-session-mode-id)))
            :on-mode-changed (lambda ()
                               (map-put! (acp--state) :set-session-mode t)
                               (acp--handle :command command :shell-buffer shell-buffer))))
          ;; Initialization complete
          (t
           (acp--emit-event :event 'init-finished)
           ;; Send ACP prompt request
           (when (and command (not (string-empty-p (string-trim command))))
             (acp--send-command :prompt command :shell-buffer shell-buffer))))))

(cl-defun acp--on-error (&key state acp-error)
  "Handle ACP-ERROR with SHELL an STATE."
  (acp--update-fragment
   :state state
   :block-id "Error"
   :body (or (map-elt acp-error 'message) "Some error ¯\\_ (ツ)_/¯")
   :create-new t
   :navigation 'never))

(defun acp-get-config (buffer)
  "Get the agent configuration for BUFFER.

Returns the agent configuration alist for the given buffer, or nil
if the buffer has no agent configuration."
  (with-current-buffer buffer
    (map-elt acp--state :agent-config)))

(defun acp--build-command-for-execution (command)
  "Build COMMAND for the current buffer's configured execution environment.

COMMAND should be a list of command parts (executable and arguments).

Applies `acp-command-prefix', if set."
  (pcase acp-command-prefix
    ((pred functionp)
     (append (funcall acp-command-prefix (current-buffer)) command))
    ((pred listp)
     (append acp-command-prefix command))
    (_ command)))

(defun acp--tool-call-command-to-string (command)
  "Normalize tool call COMMAND to a display string.

COMMAND, when present, may be a shell command string or an argv vector."
  (cond ((stringp command) command)
        ((vectorp command)
         (combine-and-quote-strings (append command nil)))
        ((null command) nil)
        (t (error "Unexpected tool-call command type: %S" (type-of command)))))

(defun acp--active-requests-p (state)
  "Return non-nil if STATE has in-flight requests awaiting responses."
  (map-elt state :active-requests))

(cl-defun acp--on-notification (&key state acp-notification)
  "Handle incoming ACP-NOTIFICATION using STATE."
  (cond ((equal (map-elt acp-notification 'method) "session/update")
         (cond
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "tool_call")
           ;; Notification is out of context (session/prompt finished).
           ;; Cannot derive where to display, so show in minibuffer.
           (if (not (acp--active-requests-p state))
               (message "%s %s (stale, consider reporting to ACP agent)"
                        (acp--make-status-kind-label
                         :status (map-nested-elt acp-notification '(params update status))
                         :kind (map-nested-elt acp-notification '(params update kind)))
                        (propertize (or (map-nested-elt acp-notification '(params update title)) "")
                                    'face font-lock-doc-markup-face))
             (acp--save-tool-call
              state
              (map-nested-elt acp-notification '(params update toolCallId))
              (append (list (cons :title (cond
                                          ((and (string= (map-nested-elt acp-notification '(params update title)) "Skill")
                                                (map-nested-elt acp-notification '(params update rawInput command)))
                                           (format "Skill: %s"
                                                   (acp--tool-call-command-to-string
                                                    (map-nested-elt acp-notification '(params update rawInput command)))))
                                          (t
                                           (map-nested-elt acp-notification '(params update title)))))
                            (cons :status (map-nested-elt acp-notification '(params update status)))
                            (cons :kind (map-nested-elt acp-notification '(params update kind)))
                            (cons :command (acp--tool-call-command-to-string
                                            (map-nested-elt acp-notification '(params update rawInput command))))
                            (cons :description (map-nested-elt acp-notification '(params update rawInput description)))
                            (cons :content (map-nested-elt acp-notification '(params update content)))
                            (cons :raw-input (map-nested-elt acp-notification '(params update rawInput))))
                      (when-let ((diff (acp--make-diff-info
                                        :acp-tool-call (map-nested-elt acp-notification '(params update)))))
                        (list (cons :diff diff)))))
             (acp--emit-event
              :event 'tool-call-update
              :data (list (cons :tool-call-id (map-nested-elt acp-notification '(params update toolCallId)))
                          (cons :tool-call (map-nested-elt state (list :tool-calls (map-nested-elt acp-notification '(params update toolCallId)))))))
             (let ((tool-call-labels (acp-make-tool-call-label
                                      state (map-nested-elt acp-notification '(params update toolCallId)))))
               (acp--update-fragment
                :state state
                :block-id (map-nested-elt acp-notification '(params update toolCallId))
                :label-left (map-elt tool-call-labels :status)
                :label-right (map-elt tool-call-labels :title)
                :expanded acp-tool-use-expand-by-default)
               ;; Display plan as markdown block if present
               (when (map-nested-elt acp-notification '(params update rawInput plan))
                 (acp--update-fragment
                  :state state
                  :block-id (concat (map-nested-elt acp-notification '(params update toolCallId)) "-plan")
                  :label-left (propertize "Proposed plan" 'font-lock-face 'font-lock-doc-markup-face)
                  :body (map-nested-elt acp-notification '(params update rawInput plan))
                  :expanded t)))
             (map-put! state :last-entry-type "tool_call")))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "agent_thought_chunk")
           ;; Notification is out of context (session/prompt finished).
           ;; Cannot derive where to display, so show in minibuffer.
           (if (not (acp--active-requests-p state))
               (message "%s %s (stale, consider reporting to ACP agent): %s"
                        acp-thought-process-icon
                        (propertize "Thought process" 'face font-lock-doc-markup-face)
                        (truncate-string-to-width (map-nested-elt acp-notification '(params update content text)) 100))
             (unless (equal (map-elt state :last-entry-type)
                            "agent_thought_chunk")
               (map-put! state :chunked-group-count (1+ (map-elt state :chunked-group-count)))
               (acp--append-transcript
                :text (format "## Agent's Thoughts (%s)\n\n" (format-time-string "%F %T"))
                :file-path acp--transcript-file))
             (acp--append-transcript
              :text (acp--indent-markdown-headers
                     (map-nested-elt acp-notification '(params update content text)))
              :file-path acp--transcript-file)
             (acp--update-fragment
              :state state
              :block-id (format "%s-agent_thought_chunk"
                                (map-elt state :chunked-group-count))
              :label-left  (concat
                            acp-thought-process-icon
                            " "
                            (propertize "Thought process" 'font-lock-face font-lock-doc-markup-face))
              :body (map-nested-elt acp-notification '(params update content text))
              :append (equal (map-elt state :last-entry-type)
                             "agent_thought_chunk")
              :expanded acp-thought-process-expand-by-default)
             (map-put! state :last-entry-type "agent_thought_chunk")))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "agent_message_chunk")
           ;; Notification is out of context (session/prompt finished).
           ;; Cannot derive where to display, so show in minibuffer.
           (if (not (acp--active-requests-p state))
               (message "Agent message (stale, consider reporting to ACP agent): %s"
                        (truncate-string-to-width (map-nested-elt acp-notification '(params update content text)) 100))
             (unless (equal (map-elt state :last-entry-type) "agent_message_chunk")
               (map-put! state :chunked-group-count (1+ (map-elt state :chunked-group-count)))
               (acp--append-transcript
                :text (format "\n## Agent (%s)\n\n" (format-time-string "%F %T"))
                :file-path acp--transcript-file))
             ;; Indent markdown headers in LLM output so they nest
             ;; below the transcript's ## section headers.  Applied
             ;; per-chunk: if a header is split across chunks it may
             ;; not be indented (graceful degradation).
             (acp--append-transcript
              :text (acp--indent-markdown-headers
                     (map-nested-elt acp-notification '(params update content text)))
              :file-path acp--transcript-file)
             (acp--update-fragment
              :state state
              :block-id (format "%s-agent_message_chunk"
                                (map-elt state :chunked-group-count))
              :body (map-nested-elt acp-notification '(params update content text))
              :create-new (not (equal (map-elt state :last-entry-type)
                                      "agent_message_chunk"))
              :append t
              :navigation 'never
              :render-body-images t)
             (map-put! state :last-entry-type "agent_message_chunk")))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "user_message_chunk")
           ;; Only handle user_message_chunks when there's an active session/load to avoid
           ;; inserting a redundant shell prompt with the existing user submission.
           (when (seq-find (lambda (r)
                             (equal (map-elt r :method) "session/load"))
                           (map-elt state :active-requests))
             (let ((new-prompt-p (not (equal (map-elt state :last-entry-type)
                                             "user_message_chunk"))))
               (when new-prompt-p
                 (map-put! state :chunked-group-count (1+ (map-elt state :chunked-group-count)))
                 (acp--append-transcript
                  :text (format "## User (%s)\n\n" (format-time-string "%F %T"))
                  :file-path acp--transcript-file))
               (acp--append-transcript
                :text (format "> %s\n"
                              (acp--indent-markdown-headers
                               (map-nested-elt acp-notification '(params update content text))))
                :file-path acp--transcript-file)
               (acp--update-text
                :state state
                :block-id (format "%s-user_message_chunk"
                                  (map-elt state :chunked-group-count))
                :text (if new-prompt-p
                          (concat (propertize
                                   (map-nested-elt
                                    state '(:agent-config :shell-prompt))
                                   'font-lock-face 'comint-highlight-prompt)
                                  (propertize (map-nested-elt acp-notification '(params update content text))
                                              'font-lock-face 'comint-highlight-input))
                        (propertize (map-nested-elt acp-notification '(params update content text))
                                    'font-lock-face 'comint-highlight-input))
                :create-new new-prompt-p
                :append t))
             (map-put! state :last-entry-type "user_message_chunk")))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "plan")
           (acp--update-fragment
            :state state
            :block-id "plan"
            :label-left (propertize "Plan" 'font-lock-face 'font-lock-doc-markup-face)
            :body (acp--format-plan (map-nested-elt acp-notification '(params update entries)))
            :expanded t)
           (map-put! state :last-entry-type "plan"))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "tool_call_update")
           ;; Notification is out of context (session/prompt finished).
           ;; Cannot derive where to display, so show in minibuffer.
           (if (not (acp--active-requests-p state))
               (message "%s %s (stale, consider reporting to ACP agent)"
                        (acp--make-status-kind-label
                         :status (map-nested-elt acp-notification '(params update status))
                         :kind (map-nested-elt acp-notification '(params update kind)))
                        (propertize (or (map-nested-elt acp-notification '(params update title)) "")
                                    'face font-lock-doc-markup-face))
             ;; Update stored tool call data with new status and content
             (acp--save-tool-call
              state
              (map-nested-elt acp-notification '(params update toolCallId))
              (append (list (cons :status (map-nested-elt acp-notification '(params update status)))
                            (cons :content (map-nested-elt acp-notification '(params update content))))
                      ;; The initial tool_call notification often has a
                      ;; generic title (eg. "grep", "bash", "Read").
                      ;; The tool_call_update may have a more descriptive
                      ;; title (eg. 'grep -i -n "tool" /path/to/file').
                      ;; Upgrade to the more descriptive title when available.
                      ;; See https://github.com/neopilot-ai/acp.el/issues/182
                      ;; See https://github.com/neopilot-ai/acp.el/issues/309
                      (when-let* ((new-title (map-nested-elt acp-notification '(params update title)))
                                  ((not (string-empty-p new-title))))
                        (list (cons :title new-title)))
                      (when-let* ((description (acp--tool-call-command-to-string
                                                (map-nested-elt acp-notification '(params update rawInput description)))))
                        (list (cons :description description)))
                      (when-let* ((command (acp--tool-call-command-to-string
                                            (map-nested-elt acp-notification '(params update rawInput command)))))
                        (list (cons :command command)))
                      (when-let ((raw-input (map-nested-elt acp-notification '(params update rawInput))))
                        (list (cons :raw-input raw-input)))
                      (when-let ((diff (acp--make-diff-info
                                        :acp-tool-call (map-nested-elt acp-notification '(params update)))))
                        (list (cons :diff diff)))))
             (acp--emit-event
              :event 'tool-call-update
              :data (list (cons :tool-call-id (map-nested-elt acp-notification '(params update toolCallId)))
                          (cons :tool-call (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)))))))
             (let* ((diff (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :diff)))
                    (output (concat
                             "\n\n"
                             ;; TODO: Consider if there are other
                             ;; types of content to display.
                             (mapconcat (lambda (item)
                                          (map-nested-elt item '(content text)))
                                        (map-nested-elt acp-notification '(params update content))
                                        "\n\n")
                             "\n\n"))
                    (diff-text (acp--format-diff-as-text diff))
                    (body-text (if diff-text
                                   (concat output
                                           "\n\n"
                                           "╭─────────╮\n"
                                           "│ changes │\n"
                                           "╰─────────╯\n\n" diff-text)
                                 output)))
               ;; Log tool call to transcript when completed or failed
               (when (and (map-nested-elt acp-notification '(params update status))
                          (member (map-nested-elt acp-notification '(params update status)) '("completed" "failed")))
                 (acp--append-transcript
                  :text (acp--make-transcript-tool-call-entry
                         :status (map-nested-elt acp-notification '(params update status))
                         :title (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :title))
                         :kind (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :kind))
                         :description (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :description))
                         :command (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :command))
                         :parameters (acp--extract-tool-parameters
                                      (map-nested-elt state `(:tool-calls ,(map-nested-elt acp-notification '(params update toolCallId)) :raw-input)))
                         :output body-text)
                  :file-path acp--transcript-file))
               ;; Hide permission after sending response.
               ;; Status is completed or failed so the user
               ;; likely selected one of: accepted/rejected/always.
               ;; Remove stale permission dialog.
               (when (member (map-nested-elt acp-notification '(params update status))
                             '("completed" "failed"))
                 ;; block-id must be the same as the one used as
                 ;; acp--update-fragment param by "session/request_permission".
                 (acp--delete-fragment :state state :block-id (format "permission-%s" (map-nested-elt acp-notification '(params update toolCallId)))))
               (let* ((tool-call-labels (acp-make-tool-call-label state (map-nested-elt acp-notification '(params update toolCallId))))
                      (saved-command (map-nested-elt state `(:tool-calls
                                                             ,(map-nested-elt acp-notification '(params update toolCallId))
                                                             :command)))
                      ;; Prepend fenced command to body.
                      (command-block (when saved-command
                                      (concat "```console\n" saved-command "\n```"))))
                 (acp--update-fragment
                  :state state
                  :block-id (map-nested-elt acp-notification '(params update toolCallId))
                  :label-left (map-elt tool-call-labels :status)
                  :label-right (map-elt tool-call-labels :title)
                  :body (if command-block
                            (concat command-block "\n\n" (string-trim body-text))
                          (string-trim body-text))
                  :expanded acp-tool-use-expand-by-default)))
             (map-put! state :last-entry-type "tool_call_update")))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "available_commands_update")
           (map-put! state :available-commands (map-nested-elt acp-notification '(params update availableCommands)))
           (acp--update-fragment
            :state state
            :namespace-id "bootstrapping"
            :block-id "available_commands_update"
            :label-left (propertize "Available /commands" 'font-lock-face 'font-lock-doc-markup-face)
            :body (acp--format-available-commands (map-nested-elt acp-notification '(params update availableCommands))))
           (map-put! state :last-entry-type "available_commands_update"))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "current_mode_update")
           (let ((updated-session (map-elt state :session))
                 (new-mode-id (map-nested-elt acp-notification '(params update currentModeId))))
             (map-put! updated-session :mode-id new-mode-id)
             (map-put! state :session updated-session)
             (message "Session mode: %s"
                      (acp--resolve-session-mode-name
                       new-mode-id
                       (acp--get-available-modes state)))
             ;; Note: No need to set :last-entry-type as no text was inserted.
             (acp--update-header-and-mode-line)))
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "config_option_update")
           ;; Silently handle config option updates (e.g., from set_model/set_mode)
           ;; These are informational notifications that don't require user-visible output
           ;; Note: No need to set :last-entry-type as no text was inserted.
           nil)
          ((equal (map-nested-elt acp-notification '(params update sessionUpdate)) "usage_update")
           ;; Extract context window and cost information
           (acp--update-usage-from-notification
            :state state
            :acp-update (map-nested-elt acp-notification '(params update)))
           ;; Update header to reflect new context usage indicator
           (acp--update-header-and-mode-line)
           ;; Note: This is session-level state, no need to set :last-entry-type
           nil)
          (acp-logging-enabled
           (acp--update-fragment
            :state state
            :block-id "Session Update - fallback"
            :body (format "%s" acp-notification)
            :create-new t
            :navigation 'never)
           (map-put! state :last-entry-type nil))))
        (acp-logging-enabled
         (acp--update-fragment
          :state state
          :block-id "Notification - fallback"
          :body (format "Unhandled notification (%s) and include:

```json
%s
```"
                        (acp-ui-add-action-to-text
                         "please file a feature request"
                         (lambda ()
                           (interactive)
                           (browse-url "https://github.com/neopilot-ai/acp.el/issues/new/choose"))
                         (lambda ()
                           (message "Press RET to open URL"))
                         'link)
                        (with-temp-buffer
                          (insert (json-serialize acp-notification))
                          (json-pretty-print (point-min) (point-max))
                          (buffer-string)))
          :create-new t
          :navigation 'never)
         (map-put! state :last-entry-type nil))))

(cl-defun acp--on-request (&key state acp-request)
  "Handle incoming ACP-REQUEST using STATE."
  (cond ((equal (map-elt acp-request 'method) "session/request_permission")
         (acp--save-tool-call
          state (map-nested-elt acp-request '(params toolCall toolCallId))
          (append (list (cons :title (map-nested-elt acp-request '(params toolCall title)))
                        (cons :status (map-nested-elt acp-request '(params toolCall status)))
                        (cons :kind (map-nested-elt acp-request '(params toolCall kind)))
                        (cons :permission-request-id (map-elt acp-request 'id)))
                  (when-let ((diff (acp--make-diff-info
                                    :acp-tool-call (map-nested-elt acp-request '(params toolCall)))))
                    (list (cons :diff diff)))))
         (unless (and (functionp acp-permission-responder-function)
                      (funcall acp-permission-responder-function
                               (list (cons :tool-call (map-nested-elt state (list :tool-calls (map-nested-elt acp-request '(params toolCall toolCallId)))))
                                     (cons :options (acp--make-permission-actions
                                                     (map-nested-elt acp-request '(params options))))
                                     (cons :respond (lambda (option-id)
                                                      (acp--send-permission-response
                                                       :client (map-elt state :client)
                                                       :request-id (map-elt acp-request 'id)
                                                       :option-id option-id
                                                       :state state
                                                       :tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId)))
                                                      t)))))
           (when (map-nested-elt acp-request '(params toolCall rawInput plan))
             (acp--update-fragment
              :state state
              :block-id (concat (map-nested-elt acp-request '(params toolCall toolCallId)) "-plan")
              :label-left (propertize "Proposed plan" 'font-lock-face 'font-lock-doc-markup-face)
              :body (map-nested-elt acp-request '(params toolCall rawInput plan))
              :expanded t))
           ;; block-id must be the same as the one used
           ;; in acp--delete-fragment param.
           (acp--update-fragment
            :state state
            :block-id (format "permission-%s" (map-nested-elt acp-request '(params toolCall toolCallId)))
            :body (with-current-buffer (map-elt state :buffer)
                    (acp--make-tool-call-permission-text
                     :acp-request acp-request
                     :client (map-elt state :client)
                     :state state))
            :expanded t
            :navigation 'never)
           (acp-jump-to-latest-permission-button-row)
           (when-let (((map-elt state :buffer))
                      (viewport-buffer (acp-viewport--buffer
                                        :shell-buffer (map-elt state :buffer)
                                        :existing-only t)))
             (with-current-buffer viewport-buffer
               (acp-jump-to-latest-permission-button-row))))
         (let ((tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId))))
           (acp--emit-event
            :event 'permission-request
            :data (list (cons :request-id (map-elt acp-request 'id))
                        (cons :tool-call-id tool-call-id)
                        (cons :tool-call (map-nested-elt state (list :tool-calls tool-call-id))))))
         (map-put! state :last-entry-type "session/request_permission"))
        ((equal (map-elt acp-request 'method) "fs/read_text_file")
         (acp--on-fs-read-text-file-request
          :state state
          :acp-request acp-request))
        ((equal (map-elt acp-request 'method) "fs/write_text_file")
         (acp--on-fs-write-text-file-request
          :state state
          :acp-request acp-request))
        (t
         (acp--update-fragment
          :state state
          :block-id "Unhandled Incoming Request"
          :body (format "⚠ Unhandled incoming request: \"%s\"" (map-elt acp-request 'method))
          :create-new t
          :navigation 'never)
         (map-put! state :last-entry-type nil))))

(cl-defun acp--extract-buffer-text (&key buffer line limit)
  "Extract text from BUFFER starting from LINE with optional LIMIT.
If the buffer's file has changed, prompt the user to reload it."
  (with-current-buffer buffer
    (when (and (buffer-file-name)
               (not (verify-visited-file-modtime))
               (y-or-n-p (format "%s has changed on file.  Reload? "
                                 (buffer-name))))
      (revert-buffer t nil nil))
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-min))
        (when (and line (> line 1))
          ;; Seems odd to use forward-line but
          ;; that's what `goto-line' recommends.
          (forward-line (1- line)))
        (let ((start (point)))
          (if limit
              ;; Seems odd to use forward-line but
              ;; that's what `goto-line' recommends.
              (forward-line limit)
            (goto-char (point-max)))
          (buffer-substring-no-properties start (point)))))))

(cl-defun acp--on-fs-read-text-file-request (&key state acp-request)
  "Handle fs/read_text_file ACP-REQUEST with STATE."
  (condition-case err
      (let* ((path (acp--resolve-path (map-nested-elt acp-request '(params path))))
             (line (or (map-nested-elt acp-request '(params line)) 1))
             (limit (map-nested-elt acp-request '(params limit)))
             (existing-buffer (find-buffer-visiting path))
             (content (if existing-buffer
                          ;; Read from open buffer (includes unsaved changes)
                          (acp--extract-buffer-text :buffer existing-buffer :line line :limit limit)
                        ;; No open buffer, read from file
                        (with-temp-buffer
                          (insert-file-contents path)
                          (acp--extract-buffer-text :buffer (current-buffer) :line line :limit limit)))))
        (acp-send-response
         :client (map-elt state :client)
         :response (acp-make-fs-read-text-file-response
                    :request-id (map-elt acp-request 'id)
                    :content content)))
    (quit
     ;; Handle C-g interrupts during file read prompts
     (acp-send-response
      :client (map-elt state :client)
      :response (acp-make-fs-read-text-file-response
                 :request-id (map-elt acp-request 'id)
                 :error (acp-make-error
                         :code -32603
                         :message "Operation cancelled by user"))))
    (file-missing
     ;; File doesn't exist - return RESOURCE_NOT_FOUND (-32002).
     ;; This allows agents to distinguish "file not found" from actual errors.
     (acp-send-response
      :client (map-elt state :client)
      :response (acp-make-fs-read-text-file-response
                 :request-id (map-elt acp-request 'id)
                 :error (acp-make-error
                         :code -32002
                         :message "Resource not found"
                         :data `((path . ,(nth 3 err)))))))
    (error
     (acp-send-response
      :client (map-elt state :client)
      :response (acp-make-fs-read-text-file-response
                 :request-id (map-elt acp-request 'id)
                 :error (acp-make-error
                         :code -32603
                         :message (error-message-string err)))))))

(defun acp--call-with-inhibited-minor-modes (modes thunk)
  "Call THUNK with MODES temporarily disabled in the current buffer.

Disable each mode in MODES that is enabled in the current buffer and has
a buffer-local mode variable.  Re-enable any modes disabled by this
function before returning."
  (let (disabled)
    (unwind-protect
        (progn
          (dolist (mode modes)
            (when (and (symbolp mode)
                       (fboundp mode)
                       (boundp mode)
                       (symbol-value mode)
                       (local-variable-p mode))
              (funcall mode -1)
              (push mode disabled)))
          (funcall thunk))
      (dolist (mode disabled)
        (funcall mode 1)))))

(cl-defun acp--on-fs-write-text-file-request (&key state acp-request)
  "Handle fs/write_text_file ACP-REQUEST with STATE."
  (condition-case err
      (let* ((path (acp--resolve-path (map-nested-elt acp-request '(params path))))
             (content (map-nested-elt acp-request '(params content)))
             (dir (file-name-directory path))
             (buffer (or (find-buffer-visiting path)
                         ;; Prevent auto-insert-mode
                         ;; See issue #170
                         (let ((auto-insert nil))
                           (find-file-noselect path)))))
        (when (and dir (not (file-exists-p dir)))
          (make-directory dir t))
        (with-temp-buffer
          (insert content)
          (let ((content-buffer (current-buffer))
                (inhibit-read-only t))
            (with-current-buffer buffer
              (save-restriction
                (widen)
                ;; Set a time-out to prevent locking up on large files
                ;; https://github.com/neopilot-ai/acp.el/issues/168
                (acp--call-with-inhibited-minor-modes
                 acp-write-inhibit-minor-modes
                 (lambda ()
                   (replace-buffer-contents content-buffer 1.0)))
                (basic-save-buffer)))))
        (acp--emit-event
         :event 'file-write
         :data (list (cons :path path)
                     (cons :content content)))
        (acp-send-response
         :client (map-elt state :client)
         :response (acp-make-fs-write-text-file-response
                    :request-id (map-elt acp-request 'id))))
    (quit
     ;; Handle C-g interrupts during file save prompts
     (acp-send-response
      :client (map-elt state :client)
      :response (acp-make-fs-write-text-file-response
                 :request-id (map-elt acp-request 'id)
                 :error (acp-make-error
                         :code -32603
                         :message "Operation cancelled by user"))))
    (error
     (acp-send-response
      :client (map-elt state :client)
      :response (acp-make-fs-write-text-file-response
                 :request-id (map-elt acp-request 'id)
                 :error (acp-make-error
                         :code -32603
                         :message (error-message-string err)))))))

(defun acp--resolve-path (path)
  "Resolve PATH using `acp-path-resolver-function'."
  (funcall (or acp-path-resolver-function #'identity) path))

(defun acp--stop-reason-description (stop-reason)
  "Return a human-readable text description for STOP-REASON.

https://agentclientprotocol.com/protocol/schema#param-stop-reason"
  (pcase stop-reason
    ("end_turn" "Finished")
    ("max_tokens" "Max token limit reached")
    ("max_turn_requests" "Exceeded request limit")
    ("refusal" "Refused")
    ("cancelled" "Cancelled")
    (_ (format "Stop for unknown reason: %s" stop-reason))))

(defun acp--format-available-commands (commands)
  "Format COMMANDS for shell rendering."
  (acp--align-alist
   :data commands
   :columns (list
             (lambda (cmd)
               (propertize (concat "/" (map-elt cmd 'name))
                           'font-lock-face 'font-lock-function-name-face))
             (lambda (cmd)
               (propertize (map-elt cmd 'description)
                           'font-lock-face 'font-lock-comment-face)))
   :joiner "\n"))

(defun acp--format-agent-capabilities (capabilities)
  "Format agent CAPABILITIES for shell rendering.

CAPABILITIES is as per ACP spec:

  https://agentclientprotocol.com/protocol/schema#agentcapabilities

Groups capabilities by category and displays them as comma-separated values.

Example output:

  prompt        image, and embedded context
  mcp           http, and sse"
  (let* ((case-fold-search nil)
         (categories (delq nil
                           (mapcar
                            (lambda (pair)
                              (let* ((key (if (symbolp (car pair))
                                              (symbol-name (car pair))
                                            (car pair)))
                                     (value (cdr pair))
                                     ;; "prompt Capabilities" -> "prompt"
                                     (group-name (replace-regexp-in-string
                                                  " Capabilities$" ""
                                                  ;; "promptCapabilities" -> "prompt Capabilities"
                                                  (replace-regexp-in-string "\\([a-z]\\)\\([A-Z]\\)" "\\1 \\2" key))))
                                (cond
                                 ;; Nested capability groups (promptCapabilities, mcpCapabilities)
                                 ((and (listp value)
                                       (not (vectorp value))
                                       (consp (car value)))
                                  (when-let ((enabled-items (delq nil (mapcar
                                                                       (lambda (cap-pair)
                                                                         ;; Match (key . t) and (key) forms.
                                                                         ;; eg. promptCapabilities uses (image . t)
                                                                         ;; but sessionCapabilities uses (fork).
                                                                         (when (or (eq (cdr cap-pair) t)
                                                                                   (null (cdr cap-pair)))
                                                                           (let* ((cap-key (car cap-pair))
                                                                                  (cap-name (if (symbolp cap-key)
                                                                                                (symbol-name cap-key)
                                                                                              cap-key)))
                                                                             (downcase
                                                                              (replace-regexp-in-string
                                                                               "\\([a-z]\\)\\([A-Z]\\)" "\\1 \\2"
                                                                               cap-name)))))
                                                                       value))))
                                    (cons (downcase group-name)
                                          (if (= (length enabled-items) 1)
                                              (car enabled-items)
                                            (concat (string-join (butlast enabled-items) ", ")
                                                    " and "
                                                    (car (last enabled-items)))))))
                                 ;; Top-level capabilities (loadSession)
                                 (t
                                  (cons (downcase group-name) nil)))))
                            capabilities))))
    (acp--align-alist
     :data categories
     :columns (list
               (lambda (pair)
                 (propertize (car pair)
                             'font-lock-face 'font-lock-function-name-face))
               (lambda (pair)
                 (when (cdr pair)
                   (propertize (cdr pair)
                               'font-lock-face 'font-lock-comment-face))))
     :joiner "\n")))

(cl-defun acp--make-diff-info (&key acp-tool-call)
  "Make diff information from ACP-TOOL-CALL.

ACP-TOOL-CALL is an ACP tool call object that may contain diff info in
either `content' (standard ACP format) or `rawInput' (eg.  Copilot).

Standard ACP format uses content with type \"diff\" containing
oldText/newText/path fields.

See https://agentclientprotocol.com/protocol/schema#toolcallcontent

Copilot sends old_str/new_str/path in rawInput instead.

See https://github.com/neopilot-ai/acp.el/issues/217

Returns in the form:

 `((:old . old-text)
   (:new . new-text)
   (:file . file-path))."
  (let ((content (map-elt acp-tool-call 'content))
        (raw-input (map-elt acp-tool-call 'rawInput)))
    (when-let* ((diff-item (cond
                            ;; Single diff object
                            ((and content (equal (map-elt content 'type) "diff"))
                             content)
                            ;; TODO: Is this needed?
                            ;; Isn't content always an alist?
                            ;; Vector/array content - find diff item
                            ((vectorp content)
                             (seq-find (lambda (item)
                                         (equal (map-elt item 'type) "diff"))
                                       content))
                            ;; TODO: Is this needed?
                            ;; Isn't content always an alist?
                            ;; List content - find diff item
                            ((and content (listp content))
                             (seq-find (lambda (item)
                                         (equal (map-elt item 'type) "diff"))
                                       content))
                            ;; Attempt to get from rawInput.
                            ((and raw-input (map-elt raw-input 'new_str))
                             `((oldText . ,(or (map-elt raw-input 'old_str) ""))
                               (newText . ,(map-elt raw-input 'new_str))
                               (path . ,(map-elt raw-input 'path))))
                            ;; Attempt diff from rawInput (eg. Copilot).
                            ((and raw-input (map-elt raw-input 'diff))
                             (let ((parsed (acp--parse-unified-diff
                                            (map-elt raw-input 'diff))))
                               `((oldText . ,(car parsed))
                                 (newText . ,(cdr parsed))
                                 (path . ,(or (map-elt raw-input 'fileName)
                                              (map-elt raw-input 'path))))))))
                ;; oldText can be nil for Write tools creating new files, default to ""
                ;; TODO: Currently don't have a way to capture overwrites
                (old-text (or (map-elt diff-item 'oldText) ""))
                (new-text (map-elt diff-item 'newText))
                (file-path (map-elt diff-item 'path)))
      (append (list (cons :old old-text)
                    (cons :new new-text))
              (when file-path
                (list (cons :file file-path)))))))

;; Based on https://github.com/editor-code-assistant/eca-emacs/blob/298849d1aae3241bf8828b6558c6deb45d75a3c8/eca-diff.el#L22
(defun acp--parse-unified-diff (diff-string)
  "Parse unified DIFF-STRING into old and new text.
Returns a cons cell (OLD-TEXT . NEW-TEXT)."
  (let (old-lines new-lines in-hunk)
    (dolist (line (split-string diff-string "\n"))
      (cond
       ((string-match "^@@.*@@" line)
        (setq in-hunk t))
       ((and in-hunk (string-prefix-p " " line))
        (push (substring line 1) old-lines)
        (push (substring line 1) new-lines))
       ((and in-hunk (string-prefix-p "-" line))
        (push (substring line 1) old-lines))
       ((and in-hunk (string-prefix-p "+" line))
        (push (substring line 1) new-lines))))
    (cons (string-join (nreverse old-lines) "\n")
          (string-join (nreverse new-lines) "\n"))))

(defun acp--format-diff-as-text (diff)
  "Format DIFF info as text suitable for display in tool call body.

DIFF should be in the form returned by `acp--make-diff-info':
  ((:old . old-text) (:new . new-text) (:file . file-path))"
  (when-let (diff
             (old-file (make-temp-file "old"))
             (new-file (make-temp-file "new")))
    (unwind-protect
        (progn
          (with-temp-file old-file (insert (map-elt diff :old)))
          (with-temp-file new-file (insert (map-elt diff :new)))
          (with-temp-buffer
            (call-process diff-command nil t nil "-U3" old-file new-file)
            ;; Remove file header lines with timestamps
            (goto-char (point-min))
            (when (looking-at "^---")
              (delete-region (point) (progn (forward-line 1) (point))))
            (when (looking-at "^\\+\\+\\+")
              (delete-region (point) (progn (forward-line 1) (point))))
            ;; Apply diff syntax highlighting
            (goto-char (point-min))
            (while (not (eobp))
              (let ((line-start (point))
                    (line-end (line-end-position)))
                (cond
                 ;; Removed lines (start with -)
                 ((looking-at "^-")
                  (add-text-properties line-start line-end
                                       '(font-lock-face diff-removed)))
                 ;; Added lines (start with +)
                 ((looking-at "^\\+")
                  (add-text-properties line-start line-end
                                       '(font-lock-face diff-added)))
                 ;; Hunk headers (@@)
                 ((looking-at "^@@")
                  (add-text-properties line-start line-end
                                       '(font-lock-face diff-hunk-header))))
                (forward-line 1)))
            (buffer-string)))
      (delete-file old-file)
      (delete-file new-file))))
(cl-defun acp--make-error-handler (&key state shell-buffer)
  "Create ACP error handler with SHELL-BUFFER STATE."
  (lambda (acp-error raw-message)
    (acp-heartbeat-stop
     :heartbeat (map-elt state :heartbeat))
    (with-current-buffer (map-elt state :buffer)
      (acp--update-fragment
       :state (acp--state)
       :block-id (format "failed-%s-id:%s-code:%s"
                         (map-elt state :request-count)
                         (or (map-elt acp-error 'id) "?")
                         (or (map-elt acp-error 'code) "?"))
       :body (acp--make-error-dialog-text
              :code (map-elt acp-error 'code)
              :message (map-elt acp-error 'message)
              :raw-message raw-message)
       :create-new t))
    ;; TODO: Mark buffer command with shell failure.
    (with-current-buffer shell-buffer
      (shell-maker-finish-output :config shell-maker--config
                                 :success t))))

(defun acp--save-tool-call (state tool-call-id tool-call)
  "Store TOOL-CALL with TOOL-CALL-ID in STATE's :tool-calls alist."
  (let* ((tool-calls (map-elt state :tool-calls))
         (old-tool-call (map-elt tool-calls tool-call-id))
         (updated-tools (copy-alist tool-calls))
         (tool-call-overrides (seq-filter (lambda (pair)
                                            (cdr pair))
                                          tool-call)))
    (setf (map-elt updated-tools tool-call-id)
          (if old-tool-call
              (map-merge 'alist old-tool-call tool-call-overrides)
            tool-call-overrides))
    (map-put! state :tool-calls updated-tools)))

(cl-defun acp--make-error-dialog-text (&key code message raw-message)
  "Create formatted error dialog text with CODE, MESSAGE, and RAW-MESSAGE."
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
                        (let ((print-circle t))
                          (pp raw-message (current-buffer))
                          (buffer-string))))))))

(defun acp--view-as-error (text)
  "Display TEXT in a `read-only' error buffer."
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
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (acp--shutdown)
  ;; Kill any open diff buffers associated with tool calls.
  (map-do (lambda (_tool-call-id tool-call-data)
            (when-let ((diff-buf (map-elt tool-call-data :diff-buffer)))
              (acp-diff-kill-buffer diff-buf)))
          (map-elt (acp--state) :tool-calls))
  (when-let (((map-elt (acp--state) :buffer))
             (viewport-buffer (acp-viewport--buffer
                               :shell-buffer (map-elt (acp--state) :buffer)
                               :existing-only t))
             (buffer-live-p viewport-buffer))
    (kill-buffer viewport-buffer)))

(defun acp--shutdown ()
  "Shut down shell activity."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (when (map-elt (acp--state) :client)
    (acp-shutdown :client (map-elt (acp--state) :client))
    (map-put! (acp--state) :client nil)
    (map-put! (acp--state) :initialized nil)
    (map-put! (acp--state) :authenticated nil)
    (map-put! (acp--state) :set-model nil)
    (map-put! (acp--state) :set-session-mode nil))
  (acp-heartbeat-stop
   :heartbeat (map-elt (acp--state) :heartbeat)))

(defcustom acp-dot-subdir-function #'acp--dot-subdir-in-repo
  "Function used by `acp--dot-subdir' to resolve subdirectory paths.
Called with one argument, SUBDIR (a string such as \"screenshots\" or
\"transcripts\"), and must return the absolute path to that subdirectory.
Directory creation is handled by `acp--dot-subdir', not by this
function."
  :type '(choice (const :tag "In repo (.acp/)" acp--dot-subdir-in-repo)
                 (function :tag "Custom function"))
  :group 'acp)

(defun acp--dot-subdir-in-repo (subdir)
  "Return path to .acp/SUBDIR under the project root.

For example:

  (acp--dot-subdir-in-repo \"screenshots\")
  => \"/path/to/project/.acp/screenshots\""
  (expand-file-name (file-name-concat ".acp" subdir)
                    (acp-cwd)))

(defun acp--dot-subdir (subdir)
  "Return path to SUBDIR for `acp' data, creating it if needed.
Calls `acp-dot-subdir-function' to resolve the path.
When the directory is first created inside a git repo and
.acp/ is not yet ignored, automatically add it to .gitignore.
This gitignore update is a one-time operation: if the entry is later
removed from .gitignore it will not be re-added."
  (unless (functionp acp-dot-subdir-function)
    (error "acp-dot-subdir-function must be set to a function"))
  (let ((dir (funcall acp-dot-subdir-function subdir)))
    (unless (and (stringp dir) (not (string-empty-p (string-trim dir))))
      (error "Failed to resolve acp data directory (subdir: %s).  Resulting directory is not a non-empty string (dir: %s)" subdir dir))
    (unless (file-directory-p dir)
      (make-directory dir t)
      (acp--ensure-gitignore (acp-cwd)))
    dir))

(defun acp--ensure-gitignore (project-root)
  "If .acp/ is not ignored under PROJECT-ROOT, add it to .gitignore."
  (condition-case nil
      (when-let* (((eq 'Git (vc-responsible-backend project-root t)))
                  (default-directory project-root)
                  ((not (zerop (process-file "git" nil nil nil
                                             "check-ignore" "-q" ".acp")))))
        (vc-ignore "/.acp/" project-root))
    (error nil)))

(cl-defun acp--capture-screenshot (&key destination-dir)
  "Capture a screenshot and save it to DESTINATION-DIR.

Returns the full path to the captured screenshot file on success.
Signals an error on failure.

DESTINATION-DIR is required and must be provided."
  (unless destination-dir
    (error "Destination-dir is required"))
  (let* ((file-path (expand-file-name
                     (format "screenshot-%s.png"
                             (format-time-string "%Y%m%d-%H%M%S"))
                     destination-dir))
         (command (car acp-screenshot-command))
         (args (append (cdr acp-screenshot-command)
                       (list file-path))))
    (redisplay) ;; Give redisplay a chance before blocking call-process
    (let ((exit-code (apply #'call-process command nil nil nil args)))
      (cond
       ((not (zerop exit-code))
        (error "Screenshot command failed with exit code %d" exit-code))
       ((not (file-exists-p file-path))
        (error "Screenshot file was not created"))
       ((zerop (nth 7 (file-attributes file-path)))
        (error "Screenshot file is empty"))
       (t
        file-path)))))

(cl-defun acp--save-clipboard-image (&key destination-dir no-error)
  "Save clipboard image to DESTINATION-DIR.
Returns the full path to the saved image file on success.
When NO-ERROR is non-nil, return nil instead of signaling errors.

Needs external utilities.  See `acp-clipboard-image-handlers'
for details."
  (unless destination-dir
    (error "Destination-dir is required"))
  (let* ((file-path (expand-file-name
                     (format "clipboard-%s.png"
                             (format-time-string "%Y%m%d-%H%M%S"))
                     destination-dir))
         (handler (seq-find
                   (lambda (h)
                     (executable-find (map-elt h :command)))
                   acp-clipboard-image-handlers)))
    (cond
     ((not handler)
      (unless no-error
        (error "No clipboard image utility found (tried: %s)"
               (mapconcat (lambda (h) (map-elt h :command))
                          acp-clipboard-image-handlers ", "))))
     (t
      (condition-case err
          (funcall (map-elt handler :save) file-path)
        (error
         (unless no-error
           (signal (car err) (cdr err)))))
      (cond
       ((not (file-exists-p file-path))
        (unless no-error
          (error "Clipboard image file was not created")))
       ((zerop (nth 7 (file-attributes file-path)))
        (delete-file file-path)
        (unless no-error
          (error "No image found in clipboard")))
       (t
        file-path))))))

(defcustom acp-status-kind-label-function
  #'acp--default-status-kind-label
  "Function to render status and kind labels.

Called with two arguments: STATUS (string or nil) and KIND (string or nil).
Should return a propertized string or nil.

STATUS is one of: \"pending\", \"in_progress\", \"completed\", \"failed\".
See URL `https://agentclientprotocol.com/protocol/schema#toolcallstatus'.

KIND is the tool call kind string (e.g. \"read\", \"edit\", \"execute\") or nil.
See URL `https://agentclientprotocol.com/protocol/tool-calls'."
  :type 'function
  :group 'acp)

(cl-defun acp--make-status-kind-label (&key status kind)
  "Render STATUS and KIND using `acp-status-kind-label-function'."
  (funcall acp-status-kind-label-function status kind))

(defun acp--shorten-paths (text &optional include-project)
  "Shorten file paths in TEXT relative to project root.

\"/path/to/project/file.txt\" -> \"file.txt\"

With INCLUDE-PROJECT

\"/path/to/project/file.txt\" -> \"project/file.txt\""
  (when text
    (let ((cwd (string-remove-suffix "/" (acp-cwd))))
      (replace-regexp-in-string (concat (regexp-quote
                                         (if include-project
                                             (string-remove-suffix
                                              "/"
                                              (file-name-directory
                                               (directory-file-name cwd)))
                                           cwd)) "/")
                                ""
                                (or text "")))))

(defun acp-make-tool-call-label (state tool-call-id)
  "Create tool call label from STATE using TOOL-CALL-ID.

Returns propertized labels in :status and :title propertized."
  (when-let ((tool-call (map-nested-elt state `(:tool-calls ,tool-call-id))))
    (let* ((title (when-let ((text (acp--shorten-paths
                                    (map-elt tool-call :title)))
                            ;; Execute commands go to body instead; use description as title.
                            ((not (equal (map-elt tool-call :kind) "execute"))))
                    ;; Strip kind prefix from title to avoid
                    ;; redundancy "[read] Read file.el" becomes
                    ;; "[read] file.el"
                    (if (and (map-elt tool-call :kind)
                             (string-match-p (concat "\\`" (regexp-quote
                                                           (map-elt tool-call :kind)) " ")
                                             (downcase text)))
                        (string-trim-left (substring text (length (map-elt tool-call :kind))))
                      text)))
           (description (or (acp--shorten-paths
                             (map-elt tool-call :description))
                            ;; Fall back to the first line of the command when
                            ;; description is missing for execute tool calls.
                            (when (equal (map-elt tool-call :kind) "execute")
                              (seq-first (split-string (or (map-elt tool-call :title) "") "\n"))))))
      `((:status . ,(acp--make-status-kind-label
                     :status (map-elt tool-call :status)
                     :kind (map-elt tool-call :kind)))
        (:title . ,(cond ((and title description
                               (not (equal (string-remove-prefix "`" (string-remove-suffix "`" (string-trim title)))
                                           (string-remove-prefix "`" (string-remove-suffix "`" (string-trim description))))))
                          (concat
                           (propertize title 'font-lock-face 'font-lock-doc-markup-face)
                           " "
                           (propertize description 'font-lock-face 'font-lock-doc-face)))
                         (title
                          (propertize title 'font-lock-face 'font-lock-doc-markup-face))
                         (description
                          (propertize description 'font-lock-face 'font-lock-doc-markup-face))))))))

(defun acp--format-plan (entries)
  "Format plan ENTRIES for shell rendering."
  (acp--align-alist
   :data entries
   :columns (list
             (lambda (entry)
               (acp--make-status-kind-label :status (map-elt entry 'status)))
             (lambda (entry)
               (map-elt entry 'content)))
   :separator " "
   :joiner "\n"))

(cl-defun acp--make-button (&key text help kind action keymap)
  "Make button with TEXT, HELP text, KIND, KEYMAP, and ACTION."
  ;; Use [ ] brackets in TUI which cannot render the box border.
  (let ((button (propertize
                 (if (display-graphic-p)
                     (format " %s " text)
                   (format "[ %s ]" text))
                 'font-lock-face '(:box t)
                 'help-echo help
                 'pointer 'hand
                 'keymap (let ((map (make-sparse-keymap)))
                           (define-key map [mouse-1] action)
                           (define-key map (kbd "RET") action)
                           (define-key map [remap self-insert-command] 'ignore)
                           (when keymap
                             (set-keymap-parent map keymap))
                           map)
                 'button kind)))
    button))

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

(defun acp--format-buffer-name (agent-name project-name)
  "Format `acp' buffer name using AGENT-NAME and PROJECT-NAME."
  (pcase acp-buffer-name-format
        ((pred functionp)
         (funcall acp-buffer-name-format agent-name project-name))
        ('kebab-case
         (format "%s-agent @ %s"
                 (downcase (replace-regexp-in-string " " "-" agent-name))
                 project-name))
        ('default
         (format "%s Agent @ %s"
                 agent-name
                 project-name))))

(cl-defun acp--apply (&key function alist)
  "Apply keyword ALIST to FUNCTION.

ALIST should be a list of keyword-value pairs like (:foo 1 :bar 2).
FUNCTION should be a function accepting keyword arguments (&key ...)."
  (unless function
    (error "Missing required argument: :function"))
  (unless alist
    (error "Missing required argument: :alist"))
  (apply function
         (mapcan (lambda (pair)
                   (list (car pair) (cdr pair)))
                 alist)))

(cl-defun acp--start (&key config no-focus new-session session-strategy session-id outgoing-request-decorator)
  "Programmatically start shell with CONFIG.

See `acp-make-agent-config' for config format.

Set NO-FOCUS to start in background.
Set NEW-SESSION to start a separate new session.
SESSION-STRATEGY overrides `acp-session-strategy' buffer-locally.
SESSION-ID resumes an existing session by its id string.
OUTGOING-REQUEST-DECORATOR is passed through to `acp-make-client'."
  (unless (version<= "0.89.2" shell-maker-version)
    (error "Please update shell-maker to version 0.89.2 or newer"))
  (unless (version<= "0.11.1" acp-package-version)
    (error "Please update acp.el to version 0.11.1 or newer"))
  (when (boundp 'acp--transcript-file-path-function)
    (user-error "'acp--transcript-file-path-function is retired.

Please use 'acp-transcript-file-path-function and unbind old
variable (see makunbound)"))
  (let* ((shell-maker-config (acp--make-shell-maker-config
                              :prompt (map-elt config :shell-prompt)
                              :prompt-regexp (map-elt config :shell-prompt-regexp)))
         (acp--shell-maker-config shell-maker-config)
         (default-directory (acp-cwd))
         (shell-buffer
          ;; Suppress mode hook during shell-maker-start since
          ;; acp state isn't ready yet.
          ;;
          ;; Fire it below once state is fully initialised.
          (let ((acp-mode-hook nil))
            (shell-maker-start acp--shell-maker-config
                               t  ;; Always use no-focus, handle display below
                               nil ;; Defer showing welcome text
                               new-session
                               (acp--format-buffer-name (map-elt config :buffer-name) (acp--project-name))
                               (map-elt config :mode-line-name)))))
    ;; While sending the first prompt request would already validate
    ;; finding the ACP agent executable, users have to wait until they
    ;; type a prompt and send it, only to find out that they are missing
    ;; the agent executable. This leaves them with an unsuable shell.
    ;; Better to check on shell creation and bail early (leaving no
    ;; shell behind).
    (with-current-buffer shell-buffer
      ;; Apply dir-local variables in acp buffer
      (hack-dir-local-variables-non-file-buffer)
      (unless (and (map-elt config :client-maker)
                   (funcall (map-elt config :client-maker) (current-buffer)))
        (kill-buffer shell-buffer)
        (error "No way to create a new client"))
      (let ((command (map-elt (funcall (map-elt config :client-maker) (current-buffer)) :command)))
        (unless (executable-find command)
          (kill-buffer shell-buffer)
          (error "%s" (acp--make-missing-executable-error
                       :executable command
                       :install-instructions (map-elt config :install-instructions)))))
      ;; Initialize buffer-local state
      (setq-local acp--state (acp--make-state
                                      :buffer shell-buffer
                                      :heartbeat (acp-heartbeat-make
                                                  :on-heartbeat
                                                  (lambda (_heartbeat _status)
                                                    (when (get-buffer-window shell-buffer)
                                                      (with-current-buffer shell-buffer
                                                        (acp--update-header-and-mode-line)))
                                                    (when-let* ((using-viewports acp-prefer-viewport-interaction)
                                                                (viewport-buffer (acp-viewport--buffer
                                                                                  :shell-buffer shell-buffer
                                                                                  :existing-only t))
                                                                ((get-buffer-window viewport-buffer)))
                                                      (with-current-buffer viewport-buffer
                                                        (acp-viewport--update-header)))))
                                      :client-maker (map-elt config :client-maker)
                                      :needs-authentication (map-elt config :needs-authentication)
                                      :authenticate-request-maker (map-elt config :authenticate-request-maker)
                                      :outgoing-request-decorator (or outgoing-request-decorator
                                                                      acp-outgoing-request-decorator)
                                      :agent-config config))
      ;; Initialize buffer-local shell-maker-config
      (setq-local acp--shell-maker-config shell-maker-config)
      (setq-local filter-buffer-substring-function #'acp--filter-buffer-substring)
      (acp--update-header-and-mode-line)
      (add-hook 'kill-buffer-hook #'acp--clean-up nil t)
      (acp-ui-mode +1)
      (when acp-file-completion-enabled
        (acp-completion-mode +1))
      (acp--setup-modeline)
      (setq-local acp--transcript-file (acp--transcript-file-path))
      ;; acp does not support restoring sessions from transcript
      ;; via shell-maker. Unalias this functionality so it's not
      ;; misleading to users or appear via M-x.
      (fmakunbound 'acp-restore-session-from-transcript)
      (when acp--transcript-file
        ;; Prefer acp--transcript-file over shell-maker's
        ;; transcript capabilities. Unalias to hide this in favor
        ;; of acp's acp--transcript-file usage.
        (fmakunbound 'acp-save-session-transcript)
        (setq-local shell-maker-prompt-before-killing-buffer nil))
      (when session-id
        (map-put! acp--state :resume-session-id session-id))
      (when session-strategy
        (setq-local acp-session-strategy session-strategy))
      ;; Show deferred welcome text,
      ;; but first wipe buffer content.
      (let ((inhibit-read-only t))
        (erase-buffer))
      (set-marker (process-mark (shell-maker--process)) (point-max))
      (when (and acp-show-welcome-message
                 (map-elt config :welcome-function))
        (shell-maker-write-output
         :config shell-maker--config
         :output (funcall (map-elt config :welcome-function)
                          shell-maker--config)))
      (if (eq acp-session-strategy 'new-deferred)
          ;; Show prompt now (unbootstrapped).
          (shell-maker-finish-output
           :config shell-maker--config
           :success nil)
        ;; Kick off ACP session bootstrapping.
        (acp--handle :shell-buffer shell-buffer))
      ;; State should be available after kicking off
      ;; `acp--handle'.  Fire mode hook so initial
      ;; state is available to acp-mode-hook(s).
      (run-hooks 'acp-mode-hook)
      ;; Subscribe to session selection events (needed regardless of focus).
      (when (eq acp-session-strategy 'prompt)
        (acp-subscribe-to
         :shell-buffer shell-buffer
         :event 'session-selection-cancelled
         :on-event (lambda (_event)
                     (kill-buffer shell-buffer)))
        (let ((active-message (acp-active-message-show :text "Loading...")))
          (acp-subscribe-to
           :shell-buffer shell-buffer
           :event 'session-prompt
           :on-event (lambda (_event)
                       (acp-active-message-hide :active-message active-message)))
          (acp-subscribe-to
           :shell-buffer shell-buffer
           :event 'session-selected
           :on-event (lambda (_event)
                       (acp-active-message-hide :active-message active-message)))
          (acp-subscribe-to
           :shell-buffer shell-buffer
           :event 'session-selection-cancelled
           :on-event (lambda (_event)
                       (acp-active-message-hide :active-message active-message)))))
      ;; Display buffer if no-focus was nil, respecting acp-display-action
      (unless no-focus
        (if (eq acp-session-strategy 'prompt)
            ;; Defer display until user selects a session.
            ;; Why? The experience is janky to display a buffer
            ;; and soon after that prompt the user for input.
            ;; Better to prompt the user for input and then
            ;; display the buffer.
            (acp-subscribe-to
             :shell-buffer shell-buffer
             :event 'session-selected
             :on-event (lambda (_event)
                         (acp--display-buffer shell-buffer)))
          (acp--display-buffer shell-buffer))))
    shell-buffer))

(cl-defun acp--delete-fragment (&key state block-id)
  "Delete fragment with STATE and BLOCK-ID."
  (when-let (((map-elt state :buffer))
             (viewport-buffer (acp-viewport--buffer
                               :shell-buffer (map-elt state :buffer)
                               :existing-only t)))
    (with-current-buffer viewport-buffer
      (acp-ui-delete-fragment :namespace-id (map-elt state :request-count) :block-id block-id :no-undo t)))
  (with-current-buffer (map-elt state :buffer)
    (unless (and (derived-mode-p 'acp-mode)
                 (equal (current-buffer)
                        (map-elt state :buffer)))
      (error "Editing the wrong buffer: %s" (current-buffer)))
    (acp-ui-delete-fragment :namespace-id (map-elt state :request-count) :block-id block-id :no-undo t)))

(cl-defun acp--update-fragment (&key state namespace-id block-id label-left label-right
                                             body append create-new navigation expanded
                                             render-body-images)
  "Update fragment in the shell buffer.

Creates or updates existing dialog using STATE's request count as namespace
unless NAMESPACE-ID (rarely needed).  Rely on count is possible.

BLOCK-ID uniquely identifies the block.

Dialog can have LABEL-LEFT, LABEL-RIGHT, and BODY.

Optional flags: APPEND text to existing content, CREATE-NEW block,
NAVIGATION for navigation style, EXPANDED to show block expanded
by default, RENDER-BODY-IMAGES to enable inline image rendering in body."
  (when label-right
    (setq label-right (string-trim label-right)))
  ;; Convert non-standard multiline single-backtick code spans to fenced
  ;; code blocks so markdown-overlays can recognize them as source blocks,
  ;; but only for labels that start with `.
  (when (and label-right
             (not (string-match-p (rx "```") label-right))
             (string-match-p
              (rx "`" (zero-or-more (not (any "\n`")))
                  "\n")
              label-right))
    (setq label-right
          (replace-regexp-in-string
           (rx "`"
               (group (zero-or-more (not (any "\n`"))) "\n"
                      (*? (seq (zero-or-more (not (any "\n"))) "\n"))
                      (zero-or-more (not (any "\n`"))))
               "`")
           "Snippet\n\n```\n\\1\n```\n"
           label-right)))
  (when-let (((map-elt state :buffer))
             (viewport-buffer (acp-viewport--buffer
                               :shell-buffer (map-elt state :buffer)
                               :existing-only t))
             ((with-current-buffer viewport-buffer
                (derived-mode-p 'acp-viewport-view-mode))))
    (with-current-buffer viewport-buffer
      (let ((inhibit-read-only t)
            (auto-scroll (eobp))
            (saved-point (point-marker)))
        (when-let* ((range (acp-ui-update-fragment
                            (acp-ui-make-fragment-model
                             :namespace-id (or namespace-id
                                               (map-elt state :request-count))
                             :block-id block-id
                             :label-left label-left
                             :label-right label-right
                             :body body)
                            :navigation navigation
                            :append append
                            :create-new create-new
                            :expanded expanded
                            :no-undo t))
                    (padding-start (map-nested-elt range '(:padding :start)))
                    (padding-end (map-nested-elt range '(:padding :end)))
                    (block-start (map-nested-elt range '(:block :start)))
                    (block-end (map-nested-elt range '(:block :end))))
          ;; Apply markdown overlay to body.
          (save-restriction
            (when-let ((body-start (map-nested-elt range '(:body :start)))
                       (body-end (map-nested-elt range '(:body :end))))
              (narrow-to-region body-start body-end)
              (let ((markdown-overlays-highlight-blocks acp-highlight-blocks)
                    (markdown-overlays-render-images render-body-images))
                (markdown-overlays-put))))
          ;; Note: For now, we're skipping applying markdown overlays
          ;; on left labels as they currently carry propertized text
          ;; for statuses (ie. boxed).
          ;;
          ;; Apply markdown overlay to right label.
          (save-restriction
            (when-let ((label-right-start (map-nested-elt range '(:label-right :start)))
                       (label-right-end (map-nested-elt range '(:label-right :end))))
              (narrow-to-region label-right-start label-right-end)
              (let ((markdown-overlays-highlight-blocks acp-highlight-blocks)
                    (markdown-overlays-render-images nil))
                (markdown-overlays-put))))
          (if auto-scroll
              (goto-char (point-max))
            (goto-char saved-point))))))
  (with-current-buffer (map-elt state :buffer)
    (unless (and (derived-mode-p 'acp-mode)
                 (equal (current-buffer)
                        (map-elt state :buffer)))
      (error "Editing the wrong buffer: %s" (current-buffer)))
    (shell-maker-with-auto-scroll-edit
     (when-let* ((range (acp-ui-update-fragment
                         (acp-ui-make-fragment-model
                          :namespace-id (or namespace-id
                                            (map-elt state :request-count))
                          :block-id block-id
                          :label-left label-left
                          :label-right label-right
                          :body body)
                         :navigation navigation
                         :append append
                         :create-new create-new
                         :expanded expanded
                         :no-undo t))
                 (padding-start (map-nested-elt range '(:padding :start)))
                 (padding-end (map-nested-elt range '(:padding :end)))
                 (block-start (map-nested-elt range '(:block :start)))
                 (block-end (map-nested-elt range '(:block :end))))
       (save-restriction
         ;; TODO: Move this to shell-maker?
         (let ((inhibit-read-only t))
           ;; comint relies on field property to
           ;; derive `comint-next-prompt'.
           ;; Marking as field to avoid false positives in
           ;; `acp-next-item' and `acp-previous-item'.
           (add-text-properties (or padding-start block-start)
                                (or padding-end block-end) '(field output)))
         ;; Apply markdown overlay to body.
         (when-let ((body-start (map-nested-elt range '(:body :start)))
                    (body-end (map-nested-elt range '(:body :end))))
           (narrow-to-region body-start body-end)
           (let ((markdown-overlays-highlight-blocks acp-highlight-blocks))
             (markdown-overlays-put))
           (widen))
         ;;
         ;; Note: For now, we're skipping applying markdown overlays
         ;; on left labels as they currently carry propertized text
         ;; for statuses (ie. boxed).
         ;;
         ;; Apply markdown overlay to right label.
         (when-let ((label-right-start (map-nested-elt range '(:label-right :start)))
                    (label-right-end (map-nested-elt range '(:label-right :end))))
           (narrow-to-region label-right-start label-right-end)
           (let ((markdown-overlays-highlight-blocks acp-highlight-blocks))
             (markdown-overlays-put))
           (widen)))
       (run-hook-with-args 'acp-section-functions range)))))

(cl-defun acp--update-text (&key state namespace-id block-id text append create-new)
  "Update plain text entry in the shell buffer.

Uses STATE's request count as namespace unless NAMESPACE-ID is given.
BLOCK-ID uniquely identifies the entry.
TEXT is the string to insert or append.
APPEND and CREATE-NEW control update behavior."
  (let ((ns (or namespace-id (map-elt state :request-count))))
    (when-let (((map-elt state :buffer))
               (viewport-buffer (acp-viewport--buffer
                                 :shell-buffer (map-elt state :buffer)
                                 :existing-only t))
               ((with-current-buffer viewport-buffer
                  (derived-mode-p 'acp-viewport-view-mode))))
      (with-current-buffer viewport-buffer
        (let ((inhibit-read-only t))
          (acp-ui-update-text
           :namespace-id ns
           :block-id block-id
           :text text
           :append append
           :create-new create-new
           :no-undo t))))
    (with-current-buffer (map-elt state :buffer)
      (shell-maker-with-auto-scroll-edit
       (when-let* ((range (acp-ui-update-text
                           :namespace-id ns
                           :block-id block-id
                           :text text
                           :append append
                           :create-new create-new
                           :no-undo t))
                   (block-start (map-nested-elt range '(:block :start)))
                   (block-end (map-nested-elt range '(:block :end))))
         (let ((inhibit-read-only t))
           (add-text-properties block-start block-end '(field output))))))))

(defun acp-toggle-logging ()
  "Toggle logging."
  (declare (modes acp-mode))
  (interactive)
  (setq acp-logging-enabled (not acp-logging-enabled))
  (message "Logging: %s" (if acp-logging-enabled "ON" "OFF")))

(defun acp-reset-logs ()
  "Reset all log buffers."
  (declare (modes acp-mode))
  (interactive)
  (acp-reset-logs :client (map-elt (acp--state) :client))
  (message "Logs reset"))

(defun acp-next-item ()
  "Go to next item.

Could be a prompt or an expandable item.
If point is at the input prompt and a character key was pressed,
insert the character instead."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  ;; Check if at prompt and inserting a character
  ;; (Ignore special keys like TAB/Shift-TAB).
  (if (and (not (shell-maker-busy))
           (shell-maker-point-at-last-prompt-p)
           (integerp last-command-event)
           (> (length (this-command-keys-vector)) 0)
           ;; Ensure invoked using a key binding.
           (eq (key-binding (this-command-keys-vector)) this-command))
      ;; At prompt, insert character.
      (self-insert-command 1)
    ;; Otherwise navigate.
    (let* ((prompt-pos (save-mark-and-excursion
                         (when (comint-next-prompt 1)
                           (point))))
           (block-pos (save-mark-and-excursion
                        (acp-ui-forward-block)))
           (button-pos (save-mark-and-excursion
                         (acp-next-permission-button)))
           (next-pos (apply #'min (delq nil (list prompt-pos
                                                  block-pos
                                                  button-pos)))))
      (when next-pos
        (deactivate-mark)
        (goto-char next-pos)
        (when (eq next-pos prompt-pos)
          (comint-skip-prompt))))))

(defun acp-previous-item ()
  "Go to previous item.

Could be a prompt or an expandable item.
If point is at the input prompt and a character key was pressed,
insert the character instead."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  ;; Check if at prompt and inserting a character
  ;; (Ignore special keys like TAB/Shift-TAB).
  (if (and (not (shell-maker-busy))
           (shell-maker-point-at-last-prompt-p)
           (integerp last-command-event)
           (> (length (this-command-keys-vector)) 0)
           ;; Ensure invoked using a key binding.
           (eq (key-binding (this-command-keys-vector)) this-command))
      ;; At prompt, insert character.
      (self-insert-command 1)
    ;; Otherwise navigate.
    (let* ((current-pos (point))
           (prompt-pos (save-mark-and-excursion
                         (when (comint-next-prompt (- 1))
                           (let ((pos (point)))
                             (when (< pos current-pos)
                               pos)))))
           (block-pos (save-mark-and-excursion
                        (let ((pos (acp-ui-backward-block)))
                          (when (and pos (< pos current-pos))
                            pos))))
           (button-pos (save-mark-and-excursion
                         (let ((pos (acp-previous-permission-button)))
                           (when (and pos (< pos current-pos))
                             pos))))
           (positions (delq nil (list prompt-pos
                                      block-pos
                                      button-pos)))
           (next-pos (when positions
                       (apply #'max positions))))
      (when next-pos
        (deactivate-mark)
        (goto-char next-pos)
        (when (eq next-pos prompt-pos)
          (comint-skip-prompt))))))

(cl-defun acp-make-environment-variables (&rest vars &key inherit-env load-env &allow-other-keys)
  "Return VARS in the form expected by `process-environment'.

With `:INHERIT-ENV' t, also inherit system environment (as per `setenv')
With `:LOAD-ENV' PATH-OR-PATHS, load .env files from given path(s).

For example:

  (acp-make-environment-variables
    \"PATH\" \"/usr/bin\"
    \"HOME\" \"/home/user\"
    :load-env \"~/.env\")

Returns:

   (\"PATH=/usr/bin\"
    \"HOME=/home/user\")."
  (unless (zerop (mod (length vars) 2))
    (error "`acp-make-environment' must receive complete pairs"))
  (append (mapcan (lambda (pair)
                    (unless (keywordp (car pair))
                      (list (format "%s=%s" (car pair) (cadr pair)))))
                  (seq-partition vars 2))
          (when load-env
            (let ((paths (if (listp load-env) load-env (list load-env))))
              (mapcan (lambda (path)
                        (unless (file-exists-p path)
                          (error "File not found: %s" path))
                        (with-temp-buffer
                          (insert-file-contents path)
                          (let (result)
                            (dolist (line (mapcar #'string-trim (split-string (buffer-string) "\n" t)))
                              (unless (or (string-empty-p line)
                                          (string-prefix-p "#" line))
                                (if (string-match "^\\([^=]+\\)=\\(.*\\)$" line)
                                    (push line result)
                                  (error "Malformed line in %s: %s" path line))))
                            (nreverse result))))
                      paths)))
          (when inherit-env
            process-environment)))

(defvar-local acp--header-cache nil
  "Cache for graphical headers (no need for regenerating regularly).

A buffer-local hash table mapping cache keys to header strings.")

(defun acp--session-id-indicator ()
  "Return a propertized session ID string, or nil if unavailable or disabled."
  (when-let* ((acp-show-session-id)
              (session-id (map-nested-elt (acp--state) '(:session :id)))
              ((not (string-empty-p session-id))))
    (propertize session-id 'font-lock-face 'font-lock-constant-face)))

(cl-defun acp--make-header-model (state &key qualifier bindings)
  "Create a header model alist from STATE, QUALIFIER, and BINDINGS.
The model contains all inputs needed to render the graphical header."
  (let* ((model-name (or (map-elt (seq-find (lambda (model)
                                              (string= (map-elt model :model-id)
                                                       (map-nested-elt state '(:session :model-id))))
                                            (map-nested-elt state '(:session :models)))
                                  :name)
                         (map-nested-elt state '(:session :model-id))))
         (mode-id (map-nested-elt state '(:session :mode-id)))
         (mode-name (when mode-id
                      (or (acp--resolve-session-mode-name
                           mode-id
                           (acp--get-available-modes state))
                          mode-id))))
    `((:buffer-name . ,(map-nested-elt state '(:agent-config :buffer-name)))
      (:icon-name . ,(map-nested-elt state '(:agent-config :icon-name)))
      (:model-id . ,(map-nested-elt state '(:session :model-id)))
      (:model-name . ,model-name)
      (:mode-id . ,mode-id)
      (:mode-name . ,mode-name)
      (:directory . ,default-directory)
      (:session-id . ,(acp--session-id-indicator))
      (:frame-width . ,(frame-pixel-width))
      (:font-height . ,(frame-char-height))
      (:font-size . ,(when-let* (((display-graphic-p))
                                 (font (face-attribute 'default :font))
                                 ((fontp font)))
                       (font-get font :size)))
      (:background-mode . ,(frame-parameter nil 'background-mode))
      (:context-indicator . ,(acp--context-usage-indicator))
      (:busy-indicator-frame . ,(acp--busy-indicator-frame))
      (:qualifier . ,qualifier)
      (:bindings . ,bindings))))

(defun acp--header-cache-key (model)
  "Generate a cache key from header MODEL.
Joins all values from the model alist."
  (mapconcat (lambda (pair) (format "%s" (cdr pair)))
             model "|"))

(cl-defun acp--make-header (state &key qualifier bindings)
  "Return header text for current STATE.

STATE should contain :agent-config with :icon-name, :buffer-name, and
:session with :mode-id and :modes for displaying the current session mode.

QUALIFIER: Any text to prefix BINDINGS row with.

BINDINGS is a list of alists defining key bindings to display, each with:
  :key         - Key string (e.g., \"n\")
  :description - Description to display (e.g., \"next hunk\")"
  (unless state
    (error "STATE is required"))
  (let* ((header-model (acp--make-header-model state :qualifier qualifier :bindings bindings))
         (text-header (format " %s%s%s @ %s%s%s%s"
                              (propertize (concat (map-elt header-model :buffer-name) " Agent")
                                          'font-lock-face 'font-lock-variable-name-face)
                              (if (map-elt header-model :model-name)
                                  (concat " ➤ " (propertize (map-elt header-model :model-name) 'font-lock-face 'font-lock-negation-char-face))
                                "")
                              (if (map-elt header-model :mode-name)
                                  (concat " ➤ " (propertize (map-elt header-model :mode-name) 'font-lock-face 'font-lock-type-face))
                                "")
                              (propertize (string-remove-suffix "/" (abbreviate-file-name (map-elt header-model :directory)))
                                          'font-lock-face 'font-lock-string-face)
                              (if (map-elt header-model :session-id)
                                  (concat " ➤ " (map-elt header-model :session-id))
                                "")
                              (if (map-elt header-model :context-indicator)
                                  (concat (if (> (length (map-elt header-model :context-indicator)) 1) " ➤ " " ")
                                          (map-elt header-model :context-indicator))
                                "")
                              (if (map-elt header-model :busy-indicator-frame)
                                  (map-elt header-model :busy-indicator-frame)
                                ""))))
    (pcase acp-header-style
      ((or 'none (pred null)) nil)
      ('text text-header)
      ('graphical
       (if (display-graphic-p)
           ;; +------+
           ;; | icon | Top text line
           ;; |      | Bottom text line
           ;; +------+
           ;; [Qualifier] Bindings row (optional, last row)
           (let* ((cache-key (acp--header-cache-key header-model))
                  (cached (progn
                            (unless acp--header-cache
                              (setq acp--header-cache (make-hash-table :test #'equal)))
                            (map-elt acp--header-cache cache-key))))
             (or cached
                 (let* ((char-height (map-elt header-model :font-height))
                        (font-size (map-elt header-model :font-size))
                        (has-bindings (or bindings qualifier))
                        (image-height (* 3 char-height))
                        (image-width image-height)
                        (text-height char-height)
                        (top-padding-height (/ font-size 2))
                        (bottom-padding-height (if has-bindings (+ text-height top-padding-height) top-padding-height))
                        (row-spacing (if has-bindings font-size 0))
                        (total-height (+ image-height row-spacing top-padding-height bottom-padding-height))
                        ;; icon position
                        (icon-x 6)
                        (icon-y top-padding-height)
                        ;; text position right of the icon area
                        (icon-text-x (+ icon-x image-width 10))
                        (icon-text-y (+ icon-y char-height (/ (- char-height font-size) 2)))
                        ;; Bindings positioned below the icon area
                        (bindings-x icon-x)
                        (bindings-y (+ image-height font-size row-spacing))
                        (svg (svg-create (map-elt header-model :frame-width) total-height))
                        (icon-filename
                         (if (map-elt header-model :icon-name)
                             (acp--fetch-agent-icon (map-elt header-model :icon-name))
                           (acp--make-agent-fallback-icon (map-elt header-model :buffer-name) 100)))
                        (image-type (or (acp--image-type-to-mime icon-filename)
                                        "image/png")))
                   ;; Icon
                   (when (and icon-filename image-type)
                     (svg-embed svg icon-filename
                                image-type nil
                                :x icon-x :y icon-y :width image-width :height image-height))
                   ;; Top text line
                   (svg--append svg (let ((text-node (dom-node 'text
                                                               `((x . ,icon-text-x)
                                                                 (y . ,icon-text-y)
                                                                 (font-size . ,font-size)))))
                                      ;; Agent name
                                      (dom-append-child text-node
                                                        (dom-node 'tspan
                                                                  `((fill . ,(face-attribute 'font-lock-variable-name-face :foreground)))
                                                                  (concat (map-elt header-model :buffer-name) " Agent")))
                                      ;; Model name (optional)
                                      (when (map-elt header-model :model-name)
                                        ;; Add separator arrow
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'default :foreground))
                                                                      (dx . "8"))
                                                                    "➤"))
                                        ;; Add model name
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'font-lock-negation-char-face :foreground))
                                                                      (dx . "8"))
                                                                    (map-elt header-model :model-name))))
                                      ;; Session mode (optional)
                                      (when (map-elt header-model :mode-id)
                                        ;; Add separator arrow
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'default :foreground))
                                                                      (dx . "8"))
                                                                    "➤"))
                                        ;; Add session mode text
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(or (face-attribute 'font-lock-type-face :foreground nil t)
                                                                                   "#6699cc"))
                                                                      (dx . "8"))
                                                                    (map-elt header-model :mode-name))))
                                      (when (map-elt header-model :context-indicator)
                                        (when (> (length (map-elt header-model :context-indicator)) 1)
                                          ;; Add separator arrow
                                          (dom-append-child text-node
                                                            (dom-node 'tspan
                                                                      `((fill . ,(face-attribute 'default :foreground))
                                                                        (dx . "8"))
                                                                      "➤")))
                                        ;; Add context indicator
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute
                                                                                (or (get-text-property 0 'face (map-elt header-model :context-indicator))
                                                                                    'default)
                                                                                :foreground nil t))
                                                                      (dx . "8"))
                                                                    (format-mode-line (map-elt header-model :context-indicator)))))
                                      (when (map-elt header-model :busy-indicator-frame)
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'default :foreground))
                                                                      (dx . "8"))
                                                                    (map-elt header-model :busy-indicator-frame))))
                                      text-node))
                   ;; Bottom text line
                   (svg--append svg (let ((text-node (dom-node 'text
                                                               `((x . ,icon-text-x)
                                                                 (y . ,(+ icon-text-y text-height (- char-height font-size)))
                                                                 (font-size . ,font-size)))))
                                      ;; Directory path
                                      (dom-append-child text-node
                                                        (dom-node 'tspan
                                                                  `((fill . ,(face-attribute 'font-lock-string-face :foreground)))
                                                                  (string-remove-suffix "/" (abbreviate-file-name (map-elt header-model :directory)))))
                                      ;; Session ID (optional)
                                      (when (map-elt header-model :session-id)
                                        ;; Separator arrow (default foreground)
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'default :foreground))
                                                                      (dx . "8"))
                                                                    "➤"))
                                        ;; Session ID text
                                        (dom-append-child text-node
                                                          (dom-node 'tspan
                                                                    `((fill . ,(face-attribute 'font-lock-constant-face :foreground))
                                                                      (dx . "8"))
                                                                    (substring-no-properties (map-elt header-model :session-id)))))
                                      text-node))
                   ;; Bindings row (last row if bindings or qualifier present)
                   (when (or bindings qualifier)
                     (svg--append svg (let ((text-node (dom-node 'text
                                                                 `((x . ,bindings-x)
                                                                   (y . ,bindings-y)
                                                                   (font-size . ,font-size))))
                                            (first t))
                                        ;; Add qualifier if present
                                        (when qualifier
                                          (dom-append-child text-node
                                                            (dom-node 'tspan
                                                                      `((fill . ,(face-attribute 'default :foreground)))
                                                                      qualifier))
                                          (setq first nil))
                                        (dolist (binding bindings)
                                          (when (map-elt binding :description)
                                            ;; Add key (XML-escape angle brackets)
                                            (dom-append-child text-node
                                                              (dom-node 'tspan
                                                                        `((fill . ,(face-attribute 'help-key-binding :foreground))
                                                                          ,@(unless first '((dx . "8"))))
                                                                        (replace-regexp-in-string
                                                                         "<" "&lt;"
                                                                         (replace-regexp-in-string
                                                                          ">" "&gt;"
                                                                          (map-elt binding :key)))))
                                            (setq first nil)
                                            ;; Add space and description
                                            (dom-append-child text-node
                                                              (dom-node 'tspan
                                                                        `((fill . ,(face-attribute 'default :foreground))
                                                                          (dx . "8"))
                                                                        (map-elt binding :description)))))
                                        text-node)))
                   (let ((result (format " %s" (with-temp-buffer
                                                 (svg-insert-image svg)
                                                 (buffer-string)))))
                     (map-put! acp--header-cache cache-key result)
                     result))))
         text-header))
      (_ text-header))))

(defun acp--image-type-to-mime (filename)
  "Convert image type from FILENAME to MIME type string.
Returns a MIME type like \"image/png\" or \"image/jpeg\"."
  (when-let ((type (image-supported-file-p filename)))
    (pcase type
      ('svg "image/svg+xml")
      (_ (format "image/%s" type)))))

(defun acp--update-header-and-mode-line ()
  "Update header and mode line based on `acp-header-style'."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (cond
   ((eq acp-header-style 'graphical)
    (setq header-line-format (acp--make-header (acp--state))))
   ((memq acp-header-style '(text none nil))
    (setq header-line-format (acp--make-header (acp--state)))
    (force-mode-line-update))))

(defun acp--fetch-agent-icon (icon-name)
  "Download icon with ICON-NAME from GitHub, only if it exists, and save as binary.

Names can be found at https://github.com/lobehub/lobe-icons/tree/master/packages/static-png

Icon names starting with https:// are downloaded directly from that location."
  (when icon-name
    (let* ((mode (if (eq (frame-parameter nil 'background-mode) 'dark) "dark" "light"))
           (is-url (string-prefix-p "https://" (downcase icon-name)))
           (url (if is-url
                    icon-name
                  (concat "https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/"
                          mode "/" icon-name)))
           (filename (if is-url
                         ;; For URLs, sanitize to create readable filename
                         ;; e.g., "https://opencode.ai/favicon.svg" -> "opencode.ai-favicon.svg"
                         (replace-regexp-in-string
                          "[/:]" "-"
                          (replace-regexp-in-string
                           "^https?://" ""
                           url))
                       ;; For lobe-icons names, use the original filename
                       (file-name-nondirectory url)))
           (cache-dir (file-name-concat (temporary-file-directory) "acp" mode))
           (cache-path (expand-file-name filename cache-dir)))
      (unless (file-exists-p cache-path)
        (make-directory cache-dir t)
        (let ((buffer (url-retrieve-synchronously url t t 5.0)))
          (when buffer
            (with-current-buffer buffer
              (goto-char (point-min))
              (if (re-search-forward "^HTTP/[0-9.]+ 200" nil t)
                  (progn
                    (re-search-forward "\r?\n\r?\n")
                    (let ((coding-system-for-write 'no-conversion))
                      (write-region (point) (point-max) cache-path)))
                (message "Icon fetch failed: %s" url)))
            (kill-buffer buffer))))
      (when (file-exists-p cache-path)
        cache-path))))

(defun acp--make-agent-fallback-icon (icon-name width)
  "Create SVG icon with first character of ICON-NAME and WIDTH.
Return file path of the generated SVG."
  (when (and icon-name (not (string-empty-p icon-name)))
    (let* ((icon-text (char-to-string (string-to-char icon-name)))
           (mode (if (eq (frame-parameter nil 'background-mode) 'dark) "dark" "light"))
           (filename (format "%s-%s.svg" icon-name width))
           (cache-dir (file-name-concat (temporary-file-directory) "acp" mode))
           (cache-path (expand-file-name filename cache-dir))
           (font-size (* 0.7 width))
           (x (/ width 2))
           (y (/ width 2)))
      (unless (file-exists-p cache-path)
        (make-directory cache-dir t)
        (let ((svg (svg-create width width :stroke "white" :fill "black")))
          (svg-text svg icon-text
                    :x x :y y
                    :text-anchor "middle"
                    :dominant-baseline "central"
                    :font-weight "bold"
                    :font-size font-size
                    ;; :font-family "Monaco, Courier New, Courier, monospace"
                    :font-family (face-attribute 'default :family)
                    :fill (face-attribute 'default :foreground))
          (with-temp-buffer
            (let ((standard-output (current-buffer)))
              (svg-print svg))
            (write-region (point-min) (point-max) cache-path))))
      cache-path)))

(defun acp-view-traffic ()
  "View agent shell traffic buffer."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (let ((traffic-buffer (acp-traffic-buffer :client (map-elt (acp--state) :client))))
    (when (with-current-buffer traffic-buffer
            (= (buffer-size) 0))
      (error "No traffic logs available.  Try M-x acp-toggle-logging?"))
    (pop-to-buffer traffic-buffer)))

(defun acp-view-acp-logs ()
  "View agent shell ACP logs buffer."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (let ((logs-buffer (acp-logs-buffer :client (map-elt (acp--state) :client))))
    (when (with-current-buffer logs-buffer
            (= (buffer-size) 0))
      (error "No traffic logs available.  Try M-x acp-toggle-logging?"))
    (pop-to-buffer logs-buffer)))

(defun acp--indent-string (n str)
  "Indent STR lines by N spaces."
  (mapconcat (lambda (line)
               (concat (make-string n ?\s) line))
             (split-string str "\n")
             "\n"))

(defun acp--interpolate-gradient (colors progress)
  "Interpolate between gradient COLORS based on PROGRESS (0.0 to 1.0)."
  (let* ((segments (1- (length colors)))
         (segment-size (/ 1.0 segments))
         (segment (min (floor (/ progress segment-size)) (1- segments)))
         (local-progress (/ (- progress (* segment segment-size)) segment-size))
         (from-color (nth segment colors))
         (to-color (nth (1+ segment) colors)))
    (acp--mix-colors from-color to-color local-progress)))

(defun acp--mix-colors (color1 color2 ratio)
  "Mix two hex colors by RATIO (0.0 = COLOR1, 1.0 = COLOR2)."
  (let* ((r1 (string-to-number (substring color1 1 3) 16))
         (g1 (string-to-number (substring color1 3 5) 16))
         (b1 (string-to-number (substring color1 5 7) 16))
         (r2 (string-to-number (substring color2 1 3) 16))
         (g2 (string-to-number (substring color2 3 5) 16))
         (b2 (string-to-number (substring color2 5 7) 16))
         (r (round (+ (* r1 (- 1 ratio)) (* r2 ratio))))
         (g (round (+ (* g1 (- 1 ratio)) (* g2 ratio))))
         (b (round (+ (* b1 (- 1 ratio)) (* b2 ratio)))))
    (format "#%02x%02x%02x" r g b)))

(cl-defun acp--make-missing-executable-error (&key executable install-instructions)
  "Create error message for missing EXECUTABLE.
INSTALL-INSTRUCTIONS is optional installation guidance."
  (concat (format "Executable \"%s\" not found.  Do you need (add-to-list 'exec-path \"another/path/to/consider/\")?" executable)
          (when install-instructions
            (concat "  " install-instructions))))

(defun acp--display-buffer (shell-buffer)
  "Toggle agent SHELL-BUFFER display."
  (interactive)
  (if (get-buffer-window shell-buffer)
      (select-window (get-buffer-window shell-buffer))
    (select-window (display-buffer shell-buffer acp-display-action))))

(defun acp--state ()
  "Get shell state or fail in an incompatible buffer."
  (unless (derived-mode-p 'acp-mode)
    (error "Processed outside shell: %s" major-mode))
  (unless acp--state
    (error "No shell state available"))
  acp--state)

;;; Events

(defvar acp--subscription-counter 0
  "Counter for generating unique subscription tokens.")

(cl-defun acp-subscribe-to (&key shell-buffer event on-event)
  "Subscribe to events in SHELL-BUFFER.

ON-EVENT is a function called with an event alist containing:
  :event - A symbol identifying the event

When EVENT is non-nil, only events matching that symbol are dispatched.
When EVENT is nil, all events are dispatched.

Initialization events (emitted in order):
  `init-started'        - Initialization pipeline started
  `init-client'         - ACP client created
  `init-subscriptions'  - ACP event subscriptions registered
  `init-handshake'      - ACP initialize/handshake RPC completed
  `init-authenticate'   - ACP authentication completed (optional)
  `init-session'        - ACP session created
  `init-model'          - Default model set (optional)
  `init-session-mode'   - Default session mode set (optional)
  `session-list'        - Session list fetch initiated
  `session-prompt'      - About to prompt user for session selection
  `session-selected'    - Session chosen (new or existing)
    :data contains :session-id (nil when starting new)
  `session-selection-cancelled' - User cancelled session selection
  `init-finished'       - Initialization pipeline completed
  `prompt-ready'        - Shell prompt displayed and ready for input

Session events:
  `tool-call-update'    - Tool call started or updated
    :data contains :tool-call-id and :tool-call
  `file-write'          - File written via fs/write_text_file
    :data contains :path and :content
  `permission-request'  - Permission prompt displayed to user
    :data contains :request-id, :tool-call-id, :tool-call
  `permission-response' - Permission response sent
    :data contains :request-id, :tool-call-id, :option-id, :cancelled
  `turn-complete'       - Agent turn finished and prompt ready for input
    :data contains :stop-reason and :usage

Returns a subscription token for use with `acp-unsubscribe'.

Example usage:

  ;; Subscribe to all events
  (acp-subscribe-to
   :shell-buffer shell-buffer
   :on-event (lambda (event)
               (message \"event: %s\" (map-elt event :event))))

  ;; Subscribe to file writes
  (acp-subscribe-to
   :shell-buffer shell-buffer
   :event \\='file-write
   :on-event (lambda (event)
               (let ((data (map-elt event :data)))
                 (message \"wrote: %s\" (map-elt data :path)))))

  ;; Unsubscribe
  (let ((token (acp-subscribe-to
                :shell-buffer shell-buffer
                :on-event #\\='my-handler)))
    (acp-unsubscribe :subscription token))"
  (unless on-event
    (error "Missing required argument: :on-event"))
  (unless shell-buffer
    (error "Missing required argument: :shell-buffer"))
  (let ((token (cl-incf acp--subscription-counter)))
    (with-current-buffer shell-buffer
      (let ((subscriptions (map-elt (acp--state) :event-subscriptions)))
        (map-put! (acp--state)
                  :event-subscriptions
                  (cons (list (cons :token token)
                              (cons :event event)
                              (cons :on-event on-event))
                        subscriptions))))
    token))

(cl-defun acp-unsubscribe (&key subscription)
  "Remove event SUBSCRIPTION by token.

SUBSCRIPTION is a token returned by `acp-subscribe-to'."
  (unless subscription
    (error "Missing required argument: :subscription"))
  (let ((subscriptions (map-elt (acp--state) :event-subscriptions)))
    (map-put! (acp--state)
              :event-subscriptions
              (seq-remove (lambda (sub)
                            (equal (map-elt sub :token) subscription))
                          subscriptions))))

(cl-defun acp--emit-event (&key event data)
  "Emit an EVENT to matching subscribers.
EVENT is a symbol identifying the event.
DATA is an optional alist of event-specific data."
  (let ((event-alist (list (cons :event event))))
    (when data
      (push (cons :data data) event-alist))
    (dolist (sub (map-elt (acp--state) :event-subscriptions))
      (when (or (not (map-elt sub :event))
                (eq (map-elt sub :event) event))
        (with-current-buffer (map-elt (acp--state) :buffer)
          (funcall (map-elt sub :on-event) event-alist))))))

;;; Initialization

(cl-defun acp--initialize-client ()
  "Initialize ACP client."
  (acp--update-fragment
   :state (acp--state)
   :namespace-id "bootstrapping"
   :block-id "starting"
   :label-left (format "%s %s"
                       (acp--make-status-kind-label :status "in_progress")
                       (propertize "Starting agent" 'font-lock-face 'font-lock-doc-markup-face))
   :body "Creating client..."
   :create-new t)
  (if (map-elt (acp--state) :client-maker)
      (progn
        (map-put! (acp--state)
                  :client (funcall (map-elt acp--state :client-maker)
                                   (map-elt acp--state :buffer)))
        (acp--emit-event :event 'init-client)
        t)
    (shell-maker-write-output :config shell-maker--config
                              :output "No :client-maker found")
    (shell-maker-finish-output :config shell-maker--config
                               :success nil)
    nil))

(cl-defun acp--initialize-subscriptions ()
  "Initialize ACP client subscriptions."
  (acp--update-fragment
   :state acp--state
   :namespace-id "bootstrapping"
   :block-id "starting"
   :label-left (format "%s %s"
                       (acp--make-status-kind-label :status "in_progress")
                       (propertize "Starting agent" 'font-lock-face 'font-lock-doc-markup-face))
   :body "\n\nSubscribing..."
   :append t)
  (if (map-elt acp--state :client)
      (progn
        (acp--subscribe-to-client-events :state acp--state)
        (acp--emit-event :event 'init-subscriptions)
        t)
    (shell-maker-write-output :config shell-maker--config
                              :output "No :client found")
    (shell-maker-finish-output :config shell-maker--config
                               :success nil)
    nil))

(cl-defun acp--send-request (&key state client request buffer on-success on-failure sync)
  "Send ACP REQUEST, tracking it in STATE via :active-requests.

Wraps `acp-send-request' so that REQUEST is pushed to
:active-requests while in-flight and removed on success or failure.

CLIENT, REQUEST, BUFFER, ON-SUCCESS, ON-FAILURE, and SYNC are passed
through to `acp-send-request'."
  ;; Migrate state for sessions created before :active-requests existed.
  ;; Without this, map-put! fails on mid-session package updates.
  (unless (assq :active-requests state)
    (nconc state (list (cons :active-requests nil))))
  (map-put! state :active-requests
            (cons request (map-elt state :active-requests)))
  (acp-send-request
   :client client
   :request request
   :buffer buffer
   :on-success (lambda (acp-response)
                 (map-put! state :active-requests
                           (seq-remove (lambda (r)
                                         (equal r request))
                                       (map-elt state :active-requests)))
                 (when on-success
                   (funcall on-success acp-response)))
   :on-failure (lambda (acp-error raw-message)
                 (map-put! state :active-requests
                           (seq-remove (lambda (r)
                                         (equal r request))
                                       (map-elt state :active-requests)))
                 (when on-failure
                   (funcall on-failure acp-error raw-message)))
   :sync sync))

(cl-defun acp--initiate-handshake (&key shell-buffer on-initiated)
  "Initiate ACP handshake with SHELL-BUFFER.

Must provide ON-INITIATED (lambda ())."
  (unless on-initiated
    (error "Missing required argument: :on-initiated"))
  (with-current-buffer (map-elt acp--state :buffer)
    (acp--update-fragment
     :state acp--state
     :namespace-id "bootstrapping"
     :block-id "starting"
     :body "\n\nInitializing..."
     :append t))
  (acp--send-request
   :state acp--state
   :client (map-elt acp--state :client)
   :request (acp-make-initialize-request
             :protocol-version 1
             :client-info `((name . "acp")
                            (title . "Emacs Agent Shell")
                            (version . ,acp--version))
             :read-text-file-capability acp-text-file-capabilities
             :write-text-file-capability acp-text-file-capabilities)
   :on-success (lambda (acp-response)
                 (with-current-buffer shell-buffer
                   (let ((acp-session-capabilities (or (map-elt acp-response 'sessionCapabilities)
                                                       (map-nested-elt acp-response '(agentCapabilities sessionCapabilities)))))
                     (map-put! acp--state :supports-session-list
                               (and (listp acp-session-capabilities)
                                    (assq 'list acp-session-capabilities)
                                    t))
                     (map-put! acp--state :supports-session-resume
                               (and (listp acp-session-capabilities)
                                    (assq 'resume acp-session-capabilities)
                                    t)))
                   ;; Save prompt capabilities from agent, converting to internal symbols
                   (when-let ((prompt-capabilities
                               (map-nested-elt acp-response '(agentCapabilities promptCapabilities))))
                     (map-put! acp--state :prompt-capabilities
                               (list (cons :image (map-elt prompt-capabilities 'image))
                                     (cons :embedded-context (map-elt prompt-capabilities 'embeddedContext)))))
                   ;; Save available modes from agent, converting to internal symbols
                   (when-let ((modes (map-elt acp-response 'modes)))
                     (map-put! acp--state :available-modes
                               (list (cons :current-mode-id (map-elt modes 'currentModeId))
                                     (cons :modes (mapcar (lambda (mode)
                                                            `((:id . ,(map-elt mode 'id))
                                                              (:name . ,(map-elt mode 'name))
                                                              (:description . ,(map-elt mode 'description))))
                                                          (map-elt modes 'availableModes))))))
                   (when-let ((agent-capabilities (map-elt acp-response 'agentCapabilities)))
                     (map-put! acp--state :supports-session-load
                               (eq (map-elt agent-capabilities 'loadSession) t))
                     (acp--update-fragment
                      :state acp--state
                      :namespace-id "bootstrapping"
                      :block-id "agent_capabilities"
                      :label-left (propertize "Agent capabilities" 'font-lock-face 'font-lock-doc-markup-face)
                      :body (acp--format-agent-capabilities agent-capabilities)))
                   (acp--emit-event :event 'init-handshake))
                 (funcall on-initiated))
   :on-failure (acp--make-error-handler
                :state acp--state :shell-buffer shell-buffer)))

(cl-defun acp--authenticate (&key shell-buffer on-authenticated)
  "Initiate ACP authentication with SHELL-BUFFER.

Must provide ON-AUTHENTICATED (lambda ())."
  (with-current-buffer (map-elt acp--state :buffer)
    (acp--update-fragment
     :state (acp--state)
     :namespace-id "bootstrapping"
     :block-id "starting"
     :body "\n\nAuthenticating..."
     :append t))
  (if (map-elt (acp--state) :authenticate-request-maker)
      (acp--send-request
       :state (acp--state)
       :client (map-elt (acp--state) :client)
       :request (funcall (map-elt acp--state :authenticate-request-maker))
       :on-success (lambda (_acp-response)
                     ;; TODO: More to be handled?
                     (with-current-buffer shell-buffer
                       (acp--emit-event :event 'init-authenticate))
                     (funcall on-authenticated))
       :on-failure (acp--make-error-handler
                    :state (acp--state) :shell-buffer shell-buffer))
    (shell-maker-write-output :config shell-maker--config
                              :output "No :authenticate-request-maker")
    (shell-maker-finish-output :config shell-maker--config
                               :success nil)))

(cl-defun acp--set-default-model (&key shell-buffer model-id on-model-changed)
  "Set default model to MODEL-ID in SHELL-BUFFER.
Call ON-MODEL-CHANGED on success."
  (when-let ((session-id (map-nested-elt (acp--state) '(:session :id))))
    (with-current-buffer (map-elt acp--state :buffer)
      (acp--update-fragment
       :state (acp--state)
       :namespace-id "bootstrapping"
       :block-id "set-model"
       :label-left (propertize "Setting model" 'font-lock-face 'font-lock-doc-markup-face)
       :body (format "Requesting %s..." model-id)))
    (acp--send-request
     :state (acp--state)
     :client (map-elt (acp--state) :client)
     :request (acp-make-session-set-model-request
               :session-id session-id
               :model-id model-id)
     :on-success (lambda (_acp-response)
                   (acp--update-fragment
                    :state (acp--state)
                    :namespace-id "bootstrapping"
                    :block-id "set-model"
                    :body "\n\nDone"
                    :append t)
                   (let ((updated-session (map-elt (acp--state) :session)))
                     (map-put! updated-session :model-id model-id)
                     (map-put! (acp--state) :session updated-session))
                   (acp--update-header-and-mode-line)
                   (acp--emit-event :event 'init-model)
                   (when on-model-changed
                     (funcall on-model-changed)))
     :on-failure (acp--make-error-handler
                  :state (acp--state) :shell-buffer shell-buffer))))

(cl-defun acp--set-default-session-mode (&key shell-buffer mode-id on-mode-changed)
  "Set default session mode to MODE-ID in SHELL-BUFFER.
Call ON-MODE-CHANGED on success."
  (when-let ((session-id (map-nested-elt (acp--state) '(:session :id))))
    (with-current-buffer (map-elt acp--state :buffer)
      (acp--update-fragment
       :state (acp--state)
       :namespace-id "bootstrapping"
       :block-id "set-session-mode"
       :label-left (propertize "Setting session mode" 'font-lock-face 'font-lock-doc-markup-face)
       :body (format "Requesting %s..." mode-id)))
    (acp--send-request
     :state (acp--state)
     :client (map-elt (acp--state) :client)
     :request (acp-make-session-set-mode-request
               :session-id session-id
               :mode-id mode-id)
     :on-success (lambda (_acp-response)
                   (acp--update-fragment
                    :state (acp--state)
                    :namespace-id "bootstrapping"
                    :block-id "set-session-mode"
                    :body "\n\nDone"
                    :append t)
                   (let ((updated-session (map-elt (acp--state) :session)))
                     (map-put! updated-session :mode-id mode-id)
                     (map-put! (acp--state) :session updated-session))
                   (acp--update-header-and-mode-line)
                   (acp--emit-event :event 'init-session-mode)
                   (when on-mode-changed
                     (funcall on-mode-changed)))
     :on-failure (acp--make-error-handler
                  :state (acp--state) :shell-buffer shell-buffer))))

(cl-defun acp--initiate-session (&key shell-buffer on-session-init)
  "Initiate ACP session creation with SHELL-BUFFER.

Must provide ON-SESSION-INIT (lambda ())."
  (unless on-session-init
    (error "Missing required argument: :on-session-init"))
  (with-current-buffer (map-elt (acp--state) :buffer)
    (acp--update-fragment
     :state (acp--state)
     :namespace-id "bootstrapping"
     :block-id "starting"
     :body "\n\nCreating session..."
     :append t))
  ;; User requested resuming session with explicit session ID.
  (if-let ((resume-session-id (map-elt (acp--state) :resume-session-id)))
      (if (or (map-elt (acp--state) :supports-session-load)
              (map-elt (acp--state) :supports-session-resume))
          ;; Agent supports some form of resuming.
          (progn
            (acp--emit-event
             :event 'session-selected
             :data (list (cons :session-id resume-session-id)))
            (acp--initiate-session-resume-by-id
             :session-id resume-session-id
             :shell-buffer shell-buffer
             :on-session-init on-session-init))
        ;; Resuming not supported. Start a new session.
        (message "Resuming unsupported by agent. Starting new session.")
        (acp--emit-event :event 'session-selected)
        (acp--initiate-new-session
         :shell-buffer shell-buffer
         :on-session-init on-session-init))
    ;; Resuming, but must request session list first.
    (if (and (map-elt (acp--state) :supports-session-list)
             (or (map-elt (acp--state) :supports-session-load)
                 (map-elt (acp--state) :supports-session-resume))
             (not (memq acp-session-strategy '(new-deferred new))))
        (acp--initiate-session-list-and-load
         :shell-buffer shell-buffer
         :on-session-init on-session-init)
      (progn
        (acp--emit-event :event 'session-selected)
        (acp--initiate-new-session
         :shell-buffer shell-buffer
         :on-session-init on-session-init)))))

(defun acp--format-session-date (iso-timestamp)
  "Format ISO-TIMESTAMP as a human-friendly date string.

Returns \"Today, HH:MM\", \"Yesterday, HH:MM\", \"Mon DD, HH:MM\"
for the current year, or \"Mon DD, YYYY\" for other years."
  (condition-case nil
      (let* ((time (date-to-time iso-timestamp))
             (now (current-time))
             (decoded-now (decode-time now))
             (today-start (encode-time 0 0 0
                                       (decoded-time-day decoded-now)
                                       (decoded-time-month decoded-now)
                                       (decoded-time-year decoded-now)))
             (yesterday-start (time-subtract today-start (seconds-to-time (* 24 60 60))))
             (current-year (decoded-time-year (decode-time now)))
             (timestamp-year (decoded-time-year (decode-time time))))
        (cond
         ((not (time-less-p time today-start))
          (format-time-string "Today, %H:%M" time))
         ((not (time-less-p time yesterday-start))
          (format-time-string "Yesterday, %H:%M" time))
         ((= timestamp-year current-year)
          (format-time-string "%b %d, %H:%M" time))
         (t
          (format-time-string "%b %d, %Y" time))))
    (error iso-timestamp)))

(defun acp--session-dir-name (acp-session)
  "Return directory name for ACP-SESSION."
  (file-name-nondirectory
   (directory-file-name (or (map-elt acp-session 'cwd) ""))))

(defun acp--session-title (acp-session)
  "Return display title for ACP-SESSION, truncated to 50 chars."
  (let ((title (or (map-elt acp-session 'title) "Untitled")))
    (if (> (length title) 50)
        (concat (substring title 0 47) "...")
      title)))

(defun acp--session-column-value (column acp-session)
  "Return the string value for COLUMN from ACP-SESSION.

COLUMN is a symbol: `directory', `title', `date', or `session-id'.

  (acp--session-column-value
   \\='directory
   \\='((cwd . \"/home/user/project\")))
  ;; => \"project\""
  (pcase column
    ('directory (acp--session-dir-name acp-session))
    ('title (acp--session-title acp-session))
    ('date (acp--format-session-date
            (or (map-elt acp-session 'updatedAt)
                (map-elt acp-session 'createdAt)
                "unknown-time")))
    ('session-id (or (map-elt acp-session 'sessionId) ""))
    (_ "")))

(defun acp--session-column-face (column)
  "Return the face for COLUMN in the session selection prompt.

  (acp--session-column-face \\='directory)
  ;; => `font-lock-keyword-face'"
  (pcase column
    ('directory 'font-lock-keyword-face)
    ('date 'font-lock-comment-face)
    ('session-id 'font-lock-constant-face)
    (_ nil)))

(defun acp--session-selection-columns ()
  "Return the list of columns for session selection.
Always includes directory, title, and date.  Appends session-id
when `acp-show-session-id' is non-nil."
  (if acp-show-session-id
      '(directory title date session-id)
    '(directory title date)))

(cl-defun acp--session-choice-label (&key acp-session max-widths)
  "Return completion label for ACP-SESSION.
MAX-WIDTHS is an alist mapping column symbols to their max widths."
  (let* ((columns (acp--session-selection-columns))
         parts
         (last-col (car (last columns))))
    (dolist (col columns)
      (let* ((value (acp--session-column-value col acp-session))
             (face (acp--session-column-face col))
             (max-width (or (map-elt max-widths col) (length value)))
             (padded (if (eq col last-col)
                         value
                       (let ((padding (make-string
                                       (max 0 (- (+ max-width 1) (length value)))
                                       ?\s)))
                         (concat value padding)))))
        (push (if face (propertize padded 'face face) padded) parts)))
    (apply #'concat (nreverse parts))))

(defun acp--prompt-select-session (acp-sessions)
  "Prompt to choose one from ACP-SESSIONS.

Return selected session alist, nil to start a new session, or
`:other-shell' when the user chose an existing shell (already
displayed and bootstrapping shell killed).
Falls back to latest session in batch mode (e.g. tests)."
  (when (or acp-sessions (acp-buffers))
    (if noninteractive
        (car acp-sessions)
      (let* ((other-shells (seq-remove (lambda (b) (eq b (current-buffer)))
                                      (acp-buffers)))
             (new-session-choice "Start new shell")
             (columns (acp--session-selection-columns))
             (max-widths (when acp-sessions
                          (mapcar (lambda (col)
                                    (cons col (apply #'max
                                                     (mapcar (lambda (s)
                                                               (length (acp--session-column-value col s)))
                                                             acp-sessions))))
                                  columns)))
             (session-choices (append (list (cons new-session-choice nil))
                              (when other-shells
                                (list (cons "Open existing shell" :other-shell)))
                              (mapcar (lambda (acp-session)
                                        (cons (acp--session-choice-label
                                               :acp-session acp-session
                                               :max-widths max-widths)
                                              acp-session))
                                      acp-sessions)))
             (candidates (mapcar #'car session-choices))
             ;; Some completion frameworks yielded appended (nil) to each line
             ;; unless this-command was bound.
             ;;
             ;; For example:
             ;;
             ;; Let's build something                 Today, 16:25 (nil)
             ;; Let's optimize the rocket engine      Feb 12, 21:02 (nil)
             (this-command 'acp))
        (acp--emit-event :event 'session-prompt)
        (let ((selection (completing-read "Start shell (default: new): "
                                          (lambda (string pred action)
                                            (if (eq action 'metadata)
                                                '(metadata
                                                  (display-sort-function . identity)
                                                  (eager-display . t)
                                                  (eager-update . t))
                                              (complete-with-action action candidates string pred)))
                                          nil t nil nil
                                          new-session-choice)))
          (if (eq (map-elt session-choices selection) :other-shell)
              (let ((other-shell (get-buffer
                                  (completing-read "Choose a shell: "
                                                   (mapcar #'buffer-name other-shells)
                                                   nil t)))
                    (bootstrapping-shell (map-elt (acp--state) :buffer)))
                (acp--display-buffer other-shell)
                (kill-buffer bootstrapping-shell)
                :other-shell)
            (map-elt session-choices selection)))))))


(cl-defun acp--set-session-from-response (&key acp-response acp-session-id)
  "Set active session state from ACP-RESPONSE and ACP-SESSION-ID."
  (map-put! acp--state
            :session (list (cons :id acp-session-id)
                           (cons :mode-id (map-nested-elt acp-response '(modes currentModeId)))
                           (cons :modes (mapcar (lambda (mode)
                                                  `((:id . ,(map-elt mode 'id))
                                                    (:name . ,(map-elt mode 'name))
                                                    (:description . ,(map-elt mode 'description))))
                                                (map-nested-elt acp-response '(modes availableModes))))
                           (cons :model-id (map-nested-elt acp-response '(models currentModelId)))
                           (cons :models (mapcar (lambda (model)
                                                   `((:model-id . ,(map-elt model 'modelId))
                                                     (:name . ,(map-elt model 'name))
                                                     (:description . ,(map-elt model 'description))))
                                                 (map-nested-elt acp-response '(models availableModels)))))))

(cl-defun acp--finalize-session-init (&key on-session-init)
  "Finalize session initialization and invoke ON-SESSION-INIT."
  (acp--update-fragment
   :state acp--state
   :block-id "starting"
   :label-left (format "%s %s"
                       (acp--make-status-kind-label :status "completed")
                       (propertize "Starting agent" 'font-lock-face 'font-lock-doc-markup-face))
   :body "\n\nReady"
   :namespace-id "bootstrapping"
   :append t)
  (acp--update-header-and-mode-line)
  (when (map-nested-elt acp--state '(:session :models))
    (acp--update-fragment
     :state acp--state
     :namespace-id "bootstrapping"
     :block-id "available_models"
     :label-left (propertize "Available models" 'font-lock-face 'font-lock-doc-markup-face)
     :body (acp--format-available-models
            (map-nested-elt acp--state '(:session :models)))))
  (when (acp--get-available-modes acp--state)
    (acp--update-fragment
     :state acp--state
     :namespace-id "bootstrapping"
     :block-id "available_modes"
     :label-left (propertize "Available modes" 'font-lock-face 'font-lock-doc-markup-face)
     :body (acp--format-available-modes
            (acp--get-available-modes acp--state))))
  (acp--update-header-and-mode-line)
  (acp--emit-event :event 'init-session)
  (funcall on-session-init))

(cl-defun acp--initiate-new-session (&key shell-buffer on-session-init)
  "Initiate ACP session/new with SHELL-BUFFER and ON-SESSION-INIT."
  (acp--send-request
   :state (acp--state)
   :client (map-elt (acp--state) :client)
   :request (acp-make-session-new-request
             :cwd (acp--resolve-path (acp-cwd))
             :mcp-servers (acp--mcp-servers))
   :buffer (current-buffer)
   :on-success (lambda (acp-response)
                 (map-put! acp--state
                           :session (list (cons :id (map-elt acp-response 'sessionId))
                                          (cons :mode-id (map-nested-elt acp-response '(modes currentModeId)))
                                          (cons :modes (mapcar (lambda (mode)
                                                                 `((:id . ,(map-elt mode 'id))
                                                                   (:name . ,(map-elt mode 'name))
                                                                   (:description . ,(map-elt mode 'description))))
                                                               (map-nested-elt acp-response '(modes availableModes))))
                                          (cons :model-id (map-nested-elt acp-response '(models currentModelId)))
                                          (cons :models (mapcar (lambda (model)
                                                                  `((:model-id . ,(map-elt model 'modelId))
                                                                    (:name . ,(map-elt model 'name))
                                                                    (:description . ,(map-elt model 'description))))
                                                                (map-nested-elt acp-response '(models availableModels))))))
                 (acp--update-fragment
                  :state acp--state
                  :block-id "starting"
                  :label-left (format "%s %s"
                                      (acp--make-status-kind-label :status "completed")
                                      (propertize "Starting agent" 'font-lock-face 'font-lock-doc-markup-face))
                  :body "\n\nReady"
                  :namespace-id "bootstrapping"
                  :append t)
                 (acp--update-header-and-mode-line)
                 (when (map-nested-elt acp--state '(:session :models))
                   (acp--update-fragment
                    :state acp--state
                    :namespace-id "bootstrapping"
                    :block-id "available_models"
                    :label-left (propertize "Available models" 'font-lock-face 'font-lock-doc-markup-face)
                    :body (acp--format-available-models
                           (map-nested-elt acp--state '(:session :models)))))
                 (when (acp--get-available-modes acp--state)
                   (acp--update-fragment
                    :state acp--state
                    :namespace-id "bootstrapping"
                    :block-id "available_modes"
                    :label-left (propertize "Available modes" 'font-lock-face 'font-lock-doc-markup-face)
                    :body (acp--format-available-modes
                           (acp--get-available-modes acp--state))))
                 (acp--update-header-and-mode-line)
                 (acp--emit-event :event 'init-session)
                 (funcall on-session-init))
   :on-failure (acp--make-error-handler
                :state acp--state :shell-buffer shell-buffer)))

(cl-defun acp--initiate-session-resume-by-id (&key session-id session-title shell-buffer on-session-init)
  "Resume or load session SESSION-ID with SHELL-BUFFER and ON-SESSION-INIT.

SESSION-TITLE is an optional display title for the resumed session."
  (acp--update-fragment
   :state (acp--state)
   :namespace-id "bootstrapping"
   :block-id "starting"
   :body (format "\n\nLoading session %s..." session-id)
   :append t)
  (acp--send-request
   :state (acp--state)
   :client (map-elt (acp--state) :client)
   :request (let ((cwd (acp--resolve-path (acp-cwd)))
                  (mcp-servers (acp--mcp-servers)))
              (let ((use-resume (if acp-prefer-session-resume
                                    (map-elt (acp--state) :supports-session-resume)
                                  (not (map-elt (acp--state) :supports-session-load)))))
                (if use-resume
                    (acp-make-session-resume-request
                     :session-id session-id
                     :cwd cwd
                     :mcp-servers mcp-servers)
                  (acp-make-session-load-request
                   :session-id session-id
                   :cwd cwd
                   :mcp-servers mcp-servers))))
   :buffer (current-buffer)
   :on-success (lambda (acp-load-response)
                 (acp--set-session-from-response
                  :acp-response acp-load-response
                  :acp-session-id session-id)
                 (acp--update-fragment
                  :state (acp--state)
                  :namespace-id "bootstrapping"
                  :block-id "resumed_session"
                  :label-left (format "%s %s"
                                      (acp--make-status-kind-label :status "completed")
                                      (propertize "Resuming session" 'font-lock-face 'font-lock-doc-markup-face))
                  :expanded t
                  :body (or session-title session-id ""))
                 (acp--finalize-session-init :on-session-init on-session-init))
   :on-failure (lambda (_acp-error _raw-message)
                 (message "Couldn't resume session. Starting a new one.")
                 (acp--update-fragment
                  :state (acp--state)
                  :namespace-id "bootstrapping"
                  :block-id "starting"
                  :body "\n\nCouldn't resume session."
                  :append t)
                 (acp--initiate-session-list-and-load
                  :shell-buffer shell-buffer
                  :on-session-init on-session-init))))

(cl-defun acp--initiate-session-list-and-load (&key shell-buffer on-session-init)
  "Try loading latest existing session with SHELL-BUFFER and ON-SESSION-INIT."
  (with-current-buffer (map-elt (acp--state) :buffer)
    (acp--update-fragment
     :state (acp--state)
     :namespace-id "bootstrapping"
     :block-id "starting"
     :body "\n\nLooking for existing sessions..."
     :append t))
  (acp--emit-event :event 'session-list)
  (acp--send-request
   :state (acp--state)
   :client (map-elt (acp--state) :client)
   :request (acp-make-session-list-request
             :cwd (acp--resolve-path (acp-cwd)))
   :buffer (current-buffer)
   :on-success (lambda (acp-response)
                 (let ((acp-sessions (append (or (map-elt acp-response 'sessions) '()) nil)))
                   (condition-case nil
                       (let* ((acp-session
                               (pcase acp-session-strategy
                                 ('new-deferred nil)
                                 ('new nil)
                                 ('latest (car acp-sessions))
                                 ('prompt (acp--prompt-select-session acp-sessions))
                                 (_ (message "Unknown session strategy '%s', starting a new session"
                                             acp-session-strategy)
                                    nil))))
                         (unless (eq acp-session :other-shell)
                         (let ((acp-session-id (and acp-session
                                                    (map-elt acp-session 'sessionId))))
                         (acp--emit-event
                          :event 'session-selected
                          :data (list (cons :session-id acp-session-id)))
                         (if acp-session-id
                             (progn
                               (acp--update-fragment
                                :state (acp--state)
                                :namespace-id "bootstrapping"
                                :block-id "starting"
                                :body (format "\n\nLoading session %s..." acp-session-id)
                                :append t)
                               (acp--send-request
                                :state (acp--state)
                                :client (map-elt (acp--state) :client)
                                :request (let ((cwd (acp--resolve-path (acp-cwd)))
                                               (mcp-servers (acp--mcp-servers)))
                                           (let ((use-resume (if acp-prefer-session-resume
                                                                  (map-elt (acp--state) :supports-session-resume)
                                                                (not (map-elt (acp--state) :supports-session-load)))))
                                             (if use-resume
                                                 (acp-make-session-resume-request
                                                  :session-id acp-session-id
                                                  :cwd cwd
                                                  :mcp-servers mcp-servers)
                                               (acp-make-session-load-request
                                                :session-id acp-session-id
                                                :cwd cwd
                                                :mcp-servers mcp-servers))))
                                :buffer (current-buffer)
                                :on-success (lambda (acp-load-response)
                                              (acp--set-session-from-response
                                               :acp-response acp-load-response
                                               :acp-session-id acp-session-id)
                                              (acp--update-fragment
                                               :state (acp--state)
                                               :namespace-id "bootstrapping"
                                               :block-id "resumed_session"
                                               :label-left (format "%s %s"
                                                                   (acp--make-status-kind-label :status "completed")
                                                                   (propertize "Resuming session" 'font-lock-face 'font-lock-doc-markup-face))
                                               :expanded t
                                               :body (or (map-elt acp-session 'title) ""))
                                              (acp--finalize-session-init :on-session-init on-session-init))
                                :on-failure (lambda (_acp-error _raw-message)
                                              (acp--update-fragment
                                               :state (acp--state)
                                               :namespace-id "bootstrapping"
                                               :block-id "starting"
                                               :body "\n\nCould not load existing session. Creating a new one..."
                                               :append t)
                                              (acp--initiate-new-session
                                               :shell-buffer shell-buffer
                                               :on-session-init on-session-init))))
                           (acp--initiate-new-session
                            :shell-buffer shell-buffer
                            :on-session-init on-session-init)))))
                     (quit
                      (acp--emit-event :event 'session-selection-cancelled)))))
   :on-failure (lambda (_acp-error _raw-message)
                 (acp--initiate-new-session
                  :shell-buffer shell-buffer
                  :on-session-init on-session-init))))

(defun acp--eval-dynamic-values (obj)
  "Recursively evaluate any lambda values in OBJ.
Named functions (symbols) are not evaluated to avoid accidentally
calling external symbols."
  (cond
   ((and (functionp obj) (not (symbolp obj))) (acp--eval-dynamic-values (funcall obj)))
   ((consp obj)
    (cons (acp--eval-dynamic-values (car obj))
          (acp--eval-dynamic-values (cdr obj))))
   (t obj)))

(defun acp--mcp-servers ()
  "Return normalized MCP servers configuration for JSON serialization.

Converts list-valued `args', `env', and `headers' fields to vectors
so they serialize properly to JSON arrays.  Returns a vector of
normalized server configs."
  (when acp-mcp-servers
    (apply #'vector
           (mapcar (lambda (server)
                     (setq server (acp--eval-dynamic-values server))
                     (let ((normalized (copy-alist server)))
                       (when (map-contains-key normalized 'args)
                         (let ((args (map-elt normalized 'args)))
                           (when (listp args)
                             (map-put! normalized 'args (apply #'vector args)))))
                       (when (map-contains-key normalized 'env)
                         (let ((env (map-elt normalized 'env)))
                           (when (listp env)
                             (map-put! normalized 'env (apply #'vector env)))))
                       (when (map-contains-key normalized 'headers)
                         (let ((headers (map-elt normalized 'headers)))
                           (when (listp headers)
                             (map-put! normalized 'headers (apply #'vector headers)))))
                       normalized))
                   acp-mcp-servers))))

(cl-defun acp--subscribe-to-client-events (&key state)
  "Subscribe SHELL and STATE to ACP events."
  (acp-subscribe-to-errors
   :client (map-elt state :client)
   :on-error (lambda (acp-error)
               (acp--update-fragment
                :state state
                :block-id (format "%s-notices"
                                  (map-elt state :request-count))
                :label-left (propertize "Notices" 'font-lock-face 'font-lock-doc-markup-face) ;;
                :body (or (map-elt acp-error 'message)
                          (map-elt acp-error 'data)
                          "Something is up ¯\\_ (ツ)_/¯")
                :append t)))
  (acp-subscribe-to-notifications
   :client (map-elt state :client)
   :on-notification (lambda (acp-notification)
                      (acp--on-notification :state state :acp-notification acp-notification)))
  (acp-subscribe-to-requests
   :client (map-elt state :client)
   :on-request (lambda (acp-request)
                 (acp--on-request :state state :acp-request acp-request))))

(defun acp--parse-file-mentions (prompt)
  "Parse @ file mentions from PROMPT string.
Returns list of alists with :start, :end, and :path for each mention."
  (let ((mentions '())
        (pos 0))
    (while (string-match (rx (or line-start (not word))
                             "@"
                             (or (seq "\"" (group (+ (not "\""))) "\"")
                                 (group (+ (not space)))))
                         prompt pos)
      (push `((:start . ,(match-beginning 0))
              (:end . ,(match-end 0))
              (:path . ,(when-let ((path (or (match-string 1 prompt) (match-string 2 prompt))))
                          (substring-no-properties path))))
            mentions)
      (setq pos (match-end 0)))
    (nreverse mentions)))

(cl-defun acp--build-content-blocks (prompt)
  "Build content blocks from the PROMPT."
  (let* ((supports-embedded-context (map-nested-elt acp--state '(:prompt-capabilities :embedded-context)))
         (supports-image (map-nested-elt acp--state '(:prompt-capabilities :image)))
         (mentions (acp--parse-file-mentions prompt))
         (content-blocks '())
         (pos 0))
    (dolist (mention mentions)
      (let* ((start (map-elt mention :start))
             (end (map-elt mention :end))
             (relative-path (map-elt mention :path))
             (expanded-path (expand-file-name relative-path (acp-cwd)))
             (resolved-path (acp--resolve-path expanded-path)))
        ;; Add text before mention
        (when (> start pos)
          (push `((type . "text")
                  (text . ,(substring-no-properties prompt pos start)))
                content-blocks))

        ;; Try to embed or link file
        (condition-case nil
            (let ((file (and (file-readable-p expanded-path)
                             (acp--read-file-content :file-path expanded-path))))
              (cond
               ;; File not readable - keep mention as text
               ((not file)
                (push `((type . "text")
                        (text . ,(substring-no-properties prompt start end)))
                      content-blocks))
               ;; Binary image and image capability supported
               ;; Use ContentBlock::Image
               ((and supports-image (map-elt file :base64-p)
                     (string-prefix-p "image/" (map-elt file :mime-type)))
                (push `((type . "image")
                        (data . ,(map-elt file :content))
                        (mimeType . ,(map-elt file :mime-type))
                        (uri . ,(concat "file://" resolved-path)))
                      content-blocks))
               ;; Text file, small enough, text file capabilities granted and embeddedContext supported
               ;; Use ContentBlock::Resource
               ((and acp-text-file-capabilities supports-embedded-context (map-elt file :size)
                     (< (map-elt file :size) acp-embed-file-size-limit))
                (push `((type . "resource")
                        (resource . ((uri . ,(concat "file://" resolved-path))
                                     (text . ,(map-elt file :content))
                                     (mimeType . ,(map-elt file :mime-type)))))
                      content-blocks))
               ;; File too large, no text file capabilities granted or embeddedContext not supported
               ;; Use resource link
               (t
                (push `((type . "resource_link")
                        (uri . ,(concat "file://" resolved-path))
                        (name . ,relative-path)
                        (mimeType . ,(map-elt file :mime-type))
                        (size . ,(map-elt file :size)))
                      content-blocks))))
          (error
           ;; On error, just keep the mention as text
           (push `((type . "text")
                   (text . ,(substring-no-properties prompt start end)))
                 content-blocks)))

        (setq pos end)))

    ;; Add remaining text
    (when (< pos (length prompt))
      (push `((type . "text")
              (text . ,(substring-no-properties prompt pos)))
            content-blocks))

    (nreverse content-blocks)))

(cl-defun acp--read-file-content (&key file-path shallow)
  "Read FILE-PATH and return metadata and content as an alist.

When SHALLOW is non-nil, only metadata is returned without loading file content.

Returns an alist with:
  :size - file size in bytes
  :extension - file extension (lowercase)
  :mime-type - MIME type based on extension
  :base64-p - t if content is base64-encoded (binary image), nil otherwise
  :content - file content (omitted when SHALLOW is non-nil)"
  (let* ((ext (downcase (or (file-name-extension file-path) "")))
         (mime-type (or (acp--image-type-to-mime file-path)
                        "text/plain"))
         ;; Only treat supported binary image formats as binary
         ;; SVG is XML/text and should not be base64-encoded
         ;; API only supports: image/png, image/jpeg, image/gif, image/webp
         (is-binary (member mime-type '("image/png" "image/jpeg" "image/gif" "image/webp")))
         (file-size (file-attribute-size (file-attributes file-path)))
         (content (unless shallow
                    (with-temp-buffer
                      (if is-binary
                          (progn
                            (insert-file-contents-literally file-path)
                            (base64-encode-string (buffer-string) t))
                        (insert-file-contents file-path)
                        (buffer-string))))))
    (append (list (cons :size file-size)
                  (cons :extension ext)
                  (cons :mime-type mime-type)
                  (cons :base64-p is-binary))
            (unless shallow
              (list (cons :content content))))))

(cl-defun acp--load-image (&key file-path (max-width 200))
  "Load image from FILE-PATH and return the image object.

MAX-WIDTH specifies the maximum width in pixels for the image (default 200).
If FILE-PATH is not an image, returns nil."
  (when-let* (((display-graphic-p))
              (metadata (acp--read-file-content :file-path file-path :shallow t))
              (mime-type (map-elt metadata :mime-type))
              ;; Check if it's an image type
              (is-image (string-prefix-p "image/" mime-type)))
    (create-image file-path nil nil :max-width max-width)))

(cl-defun acp--collect-attached-files (content-blocks)
  "Collect attached resource uris from CONTENT-BLOCKS."
  (mapcan
   (lambda (content-block)
     (let ((type (map-elt content-block 'type)))
       (cond
        ((equal type "resource") (list (map-nested-elt content-block '(resource uri))))
        ((equal type "resource_link") (list (map-elt content-block 'uri)))
        ((equal type "image") (list (map-elt content-block 'uri)))
        (t nil))))
   content-blocks))

(cl-defun acp--display-attached-files (uris)
  "Display the attached URIS in the buffer."
  (acp--update-fragment
   :state acp--state
   :block-id "attached-files"
   :label-left (format "%d file%s attached"
                       (length uris)
                       (if (= (length uris) 1) "" "s"))
   :body (mapconcat (lambda (f) (format "• %s" f))
                    (nreverse uris)
                    "\n")
   :create-new t))

(cl-defun acp--send-command (&key prompt shell-buffer)
  "Send PROMPT to agent using SHELL-BUFFER."
  (let* ((content-blocks (condition-case nil
                             (acp--build-content-blocks prompt)
                           (error `[((type . "text")
                                     (text . ,(substring-no-properties prompt)))])))
         (attached-files (acp--collect-attached-files content-blocks)))
    (when attached-files
      (acp--display-attached-files attached-files))
    (when acp-show-busy-indicator
      (acp-heartbeat-start
       :heartbeat (map-elt acp--state :heartbeat)))

    (map-put! acp--state :last-entry-type nil)

    (acp--append-transcript
     :text (format "## User (%s)\n\n%s\n\n"
                   (format-time-string "%F %T")
                   (acp--indent-markdown-headers prompt))
     :file-path acp--transcript-file)

    (when-let ((viewport-buffer (acp-viewport--buffer
                                 :shell-buffer shell-buffer
                                 :existing-only t)))
      (with-current-buffer viewport-buffer
        (acp-viewport-view-mode)
        (acp-viewport--initialize
         :prompt  prompt)))

    (acp--send-request
     :state acp--state
     :client (map-elt acp--state :client)
     :request (acp-make-session-prompt-request
               :session-id (map-nested-elt acp--state '(:session :id))
               :prompt content-blocks)
     :buffer (current-buffer)
     :on-success (lambda (acp-response)
                   (when (equal (map-elt (acp--state) :last-entry-type) "agent_message_chunk")
                     (acp--append-transcript
                      :text "\n\n"
                      :file-path acp--transcript-file))
                   ;; Tool call details are no longer needed after
                   ;; a session prompt request is finished.
                   ;; Avoid accumulating them unnecessarily.
                   (map-put! (acp--state) :tool-calls nil)
                   ;; Extract usage information from response
                   (when (map-elt acp-response 'usage)
                     (acp--save-usage :state (acp--state) :acp-usage (map-elt acp-response 'usage)))
                   (let ((success (equal (map-elt acp-response 'stopReason)
                                         "end_turn")))
                     ;; Display usage box at end of turn if enabled and data available
                     (when (and success
                                acp-show-usage-at-turn-end
                                (acp--usage-has-data-p (map-elt (acp--state) :usage)))
                       (acp--update-fragment
                        :state (acp--state)
                        :block-id (format "%s-usage" (map-elt (acp--state) :request-count))
                        :label-left (propertize "Usage" 'font-lock-face 'font-lock-doc-markup-face)
                        :body (acp--format-usage (map-elt (acp--state) :usage) t)
                        :create-new t))
                     (unless success
                       (acp--update-fragment
                        :state (acp--state)
                        :block-id (format "%s-stop-reason"
                                          (map-elt (acp--state) :request-count))
                        :body (acp--stop-reason-description
                               (map-elt acp-response 'stopReason))
                        :create-new t))
                     (acp-heartbeat-stop
                      :heartbeat (map-elt acp--state :heartbeat))
                     (unless success
                       (acp--display-pending-requests))
                     (shell-maker-finish-output :config shell-maker--config
                                                :success t)
                     (acp--emit-event
                      :event 'turn-complete
                      :data (list (cons :stop-reason (map-elt acp-response 'stopReason))
                                  (cons :usage (map-elt (acp--state) :usage))))
                     ;; Update viewport header (longer busy)
                     (when-let ((viewport-buffer (acp-viewport--buffer
                                                  :shell-buffer shell-buffer
                                                  :existing-only t)))
                       (with-current-buffer viewport-buffer
                         (acp-viewport--update-header)))
                     (when success
                       (acp--process-pending-request))))
     :on-failure (lambda (acp-error raw-message)
                   ;; Display pending requests on failure.
                   (acp--display-pending-requests)
                   (funcall (acp--make-error-handler :state acp--state :shell-buffer shell-buffer)
                            acp-error raw-message)
                   (acp-heartbeat-stop
                    :heartbeat (map-elt acp--state :heartbeat))
                   ;; Update viewport header (longer busy)
                   (when-let ((viewport-buffer (acp-viewport--buffer
                                                :shell-buffer shell-buffer
                                                :existing-only t)))
                     (with-current-buffer viewport-buffer
                       (acp-viewport--update-header)))))))

;;; Projects

(defun acp-project-buffers ()
  "Return all shell buffers in the same project as current buffer."
  (let ((project-root (acp-cwd)))
    (seq-filter (lambda (buffer)
                  (equal project-root
                         (with-current-buffer buffer
                           (acp-cwd))))
                (acp-buffers))))

(cl-defun acp--shell-buffer (&key viewport-buffer no-error no-create)
  "Get an `acp' buffer for the current project.

Resolution order:
1. If VIEWPORT-BUFFER is provided, derive shell buffer from its name.
2. If inside of a viewport buffer, derive shell buffer from its name.
3. If currently in an `acp-mode' buffer, return it.
4. If there are shells in current project, return the first one found.
5. Otherwise, ask user to pick one.

When NO-CREATE is nil (default), prompt to create a new shell if none exists.
When NO-CREATE is non-nil, return existing shell or nil/error if none exists.
When NO-ERROR is non-nil, return nil instead of raising an error.

Returns a buffer object or nil."
  (let ((shell-buffer (or (acp-viewport--shell-buffer
                           (or viewport-buffer (current-buffer)))
                          (if (derived-mode-p 'acp-mode)
                              (current-buffer)
                            (seq-first (acp-project-buffers))))))
    (if shell-buffer
        shell-buffer
      (if no-create
          (unless no-error
            (user-error "No agent shell buffers available for current project"))
        (if (and (eq acp-session-strategy 'new-deferred)
                 (acp-buffers))
            (let* ((start-new "Start new shell")
                   (open-existing "Open existing shell")
                   (choice (completing-read "Start shell (default: new): "
                                            (list start-new open-existing) nil t)))
              (if (equal choice open-existing)
                  (get-buffer (completing-read "Choose a shell: "
                                               (mapcar #'buffer-name (acp-buffers))
                                               nil t))
                (acp--start :config (or (acp--resolve-preferred-config)
                                                (acp-select-config
                                                 :prompt "Start new agent: ")
                                                (error "No agent config found"))
                                    :no-focus t
                                    :new-session t)))
          (acp--start :config (or (acp--resolve-preferred-config)
                                          (acp-select-config
                                           :prompt "Start new agent: ")
                                          (error "No agent config found"))
                              :no-focus t
                              :new-session t
                              :session-strategy acp-session-strategy))))))

(defun acp--current-shell ()
  "Current shell for viewport or shell buffer."
  (cond ((derived-mode-p 'acp-mode)
         (current-buffer))
        ((or (derived-mode-p 'acp-viewport-view-mode)
             (derived-mode-p 'acp-viewport-edit-mode))
         (seq-first (seq-filter (lambda (shell-buffer)
                                  (equal (acp-viewport--buffer
                                          :shell-buffer shell-buffer
                                          :existing-only t)
                                         (current-buffer)))
                                (acp-buffers))))))

(defun acp--input ()
  "Return shell input (not yet submitted)."
  (when-let* ((shell-buffer (acp--shell-buffer))
              (input (with-current-buffer shell-buffer
                       ;; Based on `comint-kill-input'
                       ;; to get latest input.
                       (buffer-substring
                        (or (marker-position comint-accum-marker)
                            (process-mark (get-buffer-process (current-buffer))))
                        (point-max)))))
    (unless (string-empty-p (string-trim input))
      input)))

;;; Shell

(defun acp-insert-shell-command-output ()
  "Execute a shell command and insert output as a code block.

The command executes asynchronously.  When finished, the output is
inserted into the shell buffer prompt."
  (declare (modes acp-mode
                  acp-viewport-view-mode
                  acp-viewport-edit-mode))
  (interactive)
  (unless (or (derived-mode-p 'acp-viewport-view-mode)
              (derived-mode-p 'acp-viewport-edit-mode)
              (derived-mode-p 'acp-mode))
    (user-error "Not in an `acp' buffer"))
  (let* ((command (read-string "insert command output: "))
         (shell-buffer (or (acp--current-shell)
                           (user-error "No shell available")))
         (destination-buffer (progn
                               (when (with-current-buffer shell-buffer
                                       (shell-maker-busy))
                                 (user-error "Busy, try later"))
                               (if (or (derived-mode-p 'acp-viewport-view-mode)
                                       (derived-mode-p 'acp-viewport-edit-mode))
                                   (acp-viewport--buffer
                                    :shell-buffer shell-buffer)
                                 shell-buffer)))
         (output-buffer (with-current-buffer (generate-new-buffer (format "*%s*" command))
                          (insert "$ " command "\n\n")
                          (setq-local buffer-read-only t)
                          (let ((map (make-sparse-keymap)))
                            (define-key map (kbd "q") #'quit-window)
                            (use-local-map map))
                          (current-buffer)))
         (window-config (current-window-configuration))
         (proc (make-process
                :name command
                :buffer output-buffer
                :command (with-current-buffer shell-buffer
                           (acp--build-command-for-execution
                            (list shell-file-name
                                  shell-command-switch
                                  ;; Merge stderr into stdout output
                                  ;; (all into output buffer)
                                  (format "%s 2>&1" command))))
                :connection-type 'pipe
                :filter
                (lambda (proc output)
                  (when (buffer-live-p (process-buffer proc))
                    (with-current-buffer (process-buffer proc)
                      (let ((inhibit-read-only t))
                        (goto-char (point-max))
                        (insert output)))))
                :sentinel
                (lambda (process _event)
                  (when (memq (process-status process) '(exit signal))
                    (message "Done")
                    (set-window-configuration window-config)
                    (save-excursion
                      (goto-char (point-max))
                      (with-current-buffer destination-buffer
                        (insert "\n\n" (format "```shell
%s
```" (with-current-buffer output-buffer
       (buffer-string))))))
                    (let ((markdown-overlays-highlight-blocks acp-highlight-blocks))
                      (markdown-overlays-put))
                    (when (buffer-live-p output-buffer)
                      (kill-buffer output-buffer)))))))
    (set-process-query-on-exit-flag proc nil)
    (run-at-time "0.2 sec" nil
                 (lambda ()
                   (unless (equal (process-status proc) 'exit)
                     (acp--display-buffer output-buffer))))))

;;; Completion

(cl-defun acp--get-files-context (&key files agent-cwd)
  "Process FILES into sendable text with image preview if applicable.

Uses AGENT-CWD to shorten file paths where necessary."
  (when files
    (mapconcat (lambda (file)
                 (when agent-cwd
                   (setq file (expand-file-name file agent-cwd)))
                 (if-let ((image-display (acp--load-image
                                          :file-path file
                                          :max-width 200)))
                     ;; Propertize text to display the image
                     (acp-ui-add-action-to-text
                      (propertize (concat "@" file)
                                  'display image-display
                                  'pointer 'hand
                                  'acp-context-image t
                                  'modification-hooks
                                  ;; Delete entire image if any of it is deleted.
                                  (list (lambda (edit-start edit-end)
                                          (when-let (((get-text-property edit-start 'acp-context-image))
                                                     (image-start (or (previous-single-property-change
                                                                       (1+ edit-start) 'acp-context-image)
                                                                      (point-min)))
                                                     (image-end (or (next-single-property-change
                                                                     edit-start 'acp-context-image)
                                                                    (point-max)))
                                                     (inhibit-modification-hooks t))
                                            (when (> image-end edit-end)
                                              (delete-region edit-end image-end))
                                            (when (< image-start edit-start)
                                              (delete-region image-start edit-start))))))
                      (lambda ()
                        (interactive)
                        (find-file file))
                      (lambda ()
                        (message "Press RET to open"))
                      ;; No link face for image (no underline).
                      nil)
                   ;; Not an image, insert as normal text
                   (acp-ui-add-action-to-text
                    (if (and agent-cwd (file-in-directory-p file agent-cwd))
                        ;; File within project, shorten path.
                        (propertize (concat "@" (file-relative-name file agent-cwd))
                                    'pointer 'hand)
                      (propertize (concat "@" file)
                                  'pointer 'hand))
                    (lambda ()
                      (interactive)
                      (find-file file))
                    (lambda ()
                      (message "Press RET to open"))
                    'link)))
               files
               "\n\n")))

(defun acp-send-file (&optional prompt-for-file pick-shell)
  "Insert a file into `acp'.

If visiting a file, send this file.

If invoked from shell, select a project file.

If invoked from `dired', use selection or region files.

With prefix argument PROMPT-FOR-FILE, always prompt for file selection.

When PICK-SHELL is non-nil, prompt for which shell buffer to use."
  (interactive "P")
  (if (and (region-active-p)
           (buffer-file-name))
      (acp-send-region)
    (let* ((in-shell (derived-mode-p 'acp-mode))
           (files (if (or in-shell prompt-for-file)
                      (list (completing-read "Send file: " (acp--project-files)))
                    (or (acp--buffer-files)
                        (when (buffer-file-name)
                          (list (buffer-file-name)))
                        (list (completing-read "Send file: " (acp--project-files)))
                        (user-error "No file to send"))))
           (shell-buffer (when pick-shell
                           (completing-read "Send file to shell: "
                                            (mapcar #'buffer-name (or (acp-buffers)
                                                                      (user-error "No shells available")))
                                            nil t))))
      (acp-insert :text (acp--get-files-context :files files)
                          :shell-buffer shell-buffer))))

(defun acp-send-file-to (&optional prompt-for-file)
  "Like `acp-send-file' but prompt for which shell to use.

With prefix argument PROMPT-FOR-FILE, always prompt for file selection."
  (interactive "P")
  (acp-send-file prompt-for-file t))

(cl-defun acp--buffer-files (&key obvious)
  "Return buffer file(s) or `dired' selected file(s).

Buffer filename is OBVIOUS if its an image."
  (if (and obvious
           (buffer-file-name)
           (image-supported-file-p (buffer-file-name)))
      (list (buffer-file-name))
    (or
     (acp--dired-paths-in-region)
     (dired-get-marked-files))))

(defun acp--dired-paths-in-region ()
  "If `dired' buffer, return region files.  nil otherwise."
  (when (and (equal major-mode 'dired-mode)
             (use-region-p))
    (let ((start (region-beginning))
          (end (region-end))
          (paths))
      (save-excursion
        (save-restriction
          (goto-char start)
          (while (< (point) end)
            ;; Skip non-file lines.
            (while (and (< (point) end) (dired-between-files))
              (forward-line 1))
            (when (dired-get-filename nil t)
              (setq paths (append paths (list (dired-get-filename nil t)))))
            (forward-line 1))))
      paths)))

(defalias 'acp-insert-file #'acp-send-file)

(defalias 'acp-send-current-file #'acp-send-file)

(defun acp-send-other-file ()
  "Prompt to send a file into `acp'.

Always prompts for file selection, even if a current file is available."
  (interactive)
  (acp-send-file t))

(defun acp-send-screenshot (&optional pick-shell)
  "Capture a screenshot and insert it into `acp'.

The screenshot is saved to .acp/screenshots in the project root.
The captured screenshot file path is then inserted into the shell prompt.

When PICK-SHELL is non-nil, prompt for which shell buffer to use."
  (interactive)
  (let* ((screenshots-dir (acp--dot-subdir "screenshots"))
         (screenshot-path (acp--capture-screenshot :destination-dir screenshots-dir))
         (shell-buffer (when pick-shell
                         (completing-read "Send screenshot to shell: "
                                          (mapcar #'buffer-name (or (acp-buffers)
                                                                    (user-error "No shells available")))
                                          nil t))))
    (acp-insert
     :text (acp--get-files-context :files (list screenshot-path))
     :shell-buffer shell-buffer)))

(defun acp-send-screenshot-to ()
  "Like `acp-send-screenshot' but prompt for which shell to use."
  (interactive)
  (acp-send-screenshot t))

(defun acp-send-clipboard-image (&optional pick-shell)
  "Paste clipboard image and insert it into `acp'.

Needs external utilities.  See `acp-clipboard-image-handlers'
for details.

The image is saved to .acp/screenshots in the project root.
The saved image file path is then inserted into the shell prompt.

When PICK-SHELL is non-nil, prompt for which shell buffer to use."
  (interactive)
  (let* ((screenshots-dir (acp--dot-subdir "screenshots"))
         (image-path (acp--save-clipboard-image :destination-dir screenshots-dir))
         (shell-buffer (when pick-shell
                         (completing-read "Send image to shell: "
                                          (mapcar #'buffer-name (or (acp-buffers)
                                                                    (user-error "No shells available")))
                                          nil t))))
    (acp-insert
     :text (acp--get-files-context :files (list image-path))
     :shell-buffer shell-buffer)))

(defun acp-send-clipboard-image-to ()
  "Like `acp-send-clipboard-image' but prompt for which shell to use."
  (interactive)
  (acp-send-clipboard-image t))

;; Inherit yank's `delete-selection' property so
;; `delete-selection-mode' replaces the active region on paste.
(put 'acp-yank-dwim 'delete-selection 'yank)
(defun acp-yank-dwim (&optional arg)
  "Yank or paste clipboard image into `acp'.

If the clipboard contains an image, save it and insert as file context.
Otherwise, invoke `yank' with ARG as usual.

Needs external utilities.  See `acp-clipboard-image-handlers'
for details."
  (interactive "*P")
  (let* ((screenshots-dir (acp--dot-subdir "screenshots"))
         (image-path (acp--save-clipboard-image :destination-dir screenshots-dir
                                                        :no-error t)))
    (if image-path
        (acp-insert
         :text (acp--get-files-context :files (list image-path))
         :shell-buffer (acp--shell-buffer))
      (yank arg))))

;;; Permissions

(cl-defun acp--make-tool-call-permission-text (&key acp-request client state)
  "Create text to render permission dialog using ACP-REQUEST, CLIENT, and STATE.

For example:

   ╭─

       ⚠ Tool Permission ⚠

       Add more cowbell

       [ View (v) ] [ Allow (y) ] [ Reject (n) ] [ Always Allow (!) ]


   ╰─"
  (let* ((tool-call-id (map-nested-elt acp-request '(params toolCall toolCallId)))
         (diff (map-nested-elt state `(:tool-calls ,tool-call-id :diff)))
         (actions (acp--make-permission-actions (map-nested-elt acp-request '(params options))))
         (shell-buffer (map-elt state :buffer))
         (keymap (let ((map (make-sparse-keymap)))
                   (dolist (action actions)
                     (when-let ((char (map-elt action :char)))
                       (define-key map (kbd char)
                                   (lambda ()
                                     (interactive)
                                     (acp--send-permission-response
                                      :client client
                                      :request-id (map-elt acp-request 'id)
                                      :option-id (map-elt action :option-id)
                                      :state state
                                      :tool-call-id tool-call-id
                                      :message-text (map-elt action :option))
                                     (when (equal (map-elt action :kind) "reject_once")
                                       ;; No point in rejecting the change but letting
                                       ;; the agent continue (it doesn't know why you
                                       ;; have rejected the change).
                                       ;; May as well interrupt so you can course-correct.
                                       (with-current-buffer shell-buffer
                                         (acp-interrupt t)))))))
                   ;; Add diff keybinding if diff info is available
                   (when diff
                     (define-key map "v" (acp--make-diff-viewing-function
                                          :diff diff
                                          :actions actions
                                          :client client
                                          :request-id (map-elt acp-request 'id)
                                          :state state
                                          :tool-call-id tool-call-id)))
                   ;; Add interrupt keybinding
                   (define-key map (kbd "C-c C-c")
                               (lambda ()
                                 (interactive)
                                 (with-current-buffer shell-buffer
                                   (acp-interrupt t))))
                   map))
         (title (let* ((title (map-nested-elt acp-request '(params toolCall title)))
                       (command (acp--tool-call-command-to-string
                                 (map-nested-elt acp-request '(params toolCall rawInput command))))
                       ;; Some agents don't include the command in the
                       ;; permission/tool call title, so it's hard to know
                       ;; what the permission is actually allowing.
                       ;; Display command if needed.
                       (text (if (and (stringp title)
                                      (stringp command)
                                      (not (string-empty-p command))
                                      (string-match-p (regexp-quote command) title))
                                 title
                               (or command title))))
                  ;; Fence execute commands so markdown-overlays
                  ;; renders them verbatim, not as markdown.
                  (if (and text
                           (equal text command)
                           (equal (map-nested-elt acp-request '(params toolCall kind)) "execute"))
                      (concat "```console\n" text "\n```")
                    text)))
         (diff-button (when diff
                        (acp--make-permission-button
                         :text "View (v)"
                         :help "Press v to view diff"
                         :action (acp--make-diff-viewing-function
                                  :diff diff
                                  :actions actions
                                  :client client
                                  :request-id (map-elt acp-request 'id)
                                  :state state
                                  :tool-call-id tool-call-id)
                         :keymap keymap
                         :navigatable t
                         :char "v"
                         :option "view diff"))))
    (format "╭─

    %s %s %s%s


    %s%s


╰─"
            (propertize acp-permission-icon
                        'font-lock-face 'warning)
            (propertize "Tool Permission" 'font-lock-face 'bold)
            (propertize acp-permission-icon
                        'font-lock-face 'warning)
            (if title
                (propertize
                 (format "\n\n\n    %s" title)
                 'font-lock-face 'comint-highlight-input)
              "")
            (if diff-button
                (concat diff-button " ")
              "")
            (mapconcat (lambda (action)
                         (acp--make-permission-button
                          :text (map-elt action :label)
                          :help (map-elt action :label)
                          :action (lambda ()
                                    (interactive)
                                    (acp--send-permission-response
                                     :client client
                                     :request-id (map-elt acp-request 'id)
                                     :option-id (map-elt action :option-id)
                                     :state state
                                     :tool-call-id tool-call-id
                                     :message-text (format "Selected: %s" (map-elt action :option)))
                                    (when (equal (map-elt action :kind) "reject_once")
                                      ;; No point in rejecting the change but letting
                                      ;; the agent continue (it doesn't know why you
                                      ;; have rejected the change).
                                      ;; May as well interrupt so you can course-correct.
                                      (with-current-buffer shell-buffer
                                        (acp-interrupt t))))
                          :keymap keymap
                          :char (map-elt action :char)
                          :option (map-elt action :option)
                          :navigatable t))
                       actions
                       " "))))

(cl-defun acp--send-permission-response (&key client request-id option-id cancelled state tool-call-id message-text)
  "Send a response to a permission request and clean up related dialog UI.

Choose OPTION-ID or CANCELLED (never both).

CLIENT: The ACP client used to send the response.
REQUEST-ID: The ID of the original permission request.
OPTION-ID: The ID of the selected permission option.
CANCELLED: Non-nil if the request was cancelled instead of selecting an option.
STATE: The buffer-local acp session state.
TOOL-CALL-ID: The tool call identifier.
MESSAGE-TEXT: Optional message to display after sending the response."
  (acp-send-response
   :client client
   :response (acp-make-session-request-permission-response
              :request-id request-id
              :cancelled cancelled
              :option-id option-id))
  ;; Kill any diff buffer opened for this tool call, suppressing the
  ;; on-exit callback since the permission is already being resolved.
  (when-let ((diff-buf (map-nested-elt state (list :tool-calls tool-call-id :diff-buffer))))
    (acp-diff-kill-buffer diff-buf))
  ;; Ensure in the shell buffer for state operations, as this
  ;; function may be invoked from a viewport buffer.
  (with-current-buffer (map-elt state :buffer)
    ;; Hide permission after sending response.
    ;; block-id must be the same as the one used as
    ;; acp--update-fragment param by "session/request_permission".
    (acp--delete-fragment :state state :block-id (format "permission-%s" tool-call-id))
    ;; Note: Tool call data is no longer deleted here intentionally.
    ;; Subsequent tool_call_update notifications still need the data.
    ;; It gets cleared at end of turn with all tool calls.
    (acp--emit-event
     :event 'permission-response
     :data (list (cons :request-id request-id)
                 (cons :tool-call-id tool-call-id)
                 (cons :option-id option-id)
                 (cons :cancelled cancelled)))
    (when message-text
      (message "%s" message-text))
    ;; Jump to any remaining permission buttons, or go to end of buffer.
    (or (acp-jump-to-latest-permission-button-row)
        (goto-char (point-max)))
    (when-let (((map-elt state :buffer))
               (viewport-buffer (acp-viewport--buffer
                                 :shell-buffer (map-elt state :buffer)
                                 :existing-only t)))
      (with-current-buffer viewport-buffer
        (or (acp-jump-to-latest-permission-button-row)
            (goto-char (point-max)))))))

(cl-defun acp--resolve-permission-choice-to-action (&key choice actions)
  "Resolve `acp-diff' CHOICE to permission action from ACTIONS.

CHOICE can be \\='accept or \\='reject.
Returns the matching action or nil if no match found."
  (cond
   ((equal choice 'accept)
    (seq-find (lambda (action)
                (string= (map-elt action :kind) "allow_once"))
              actions))
   ((equal choice 'reject)
    (seq-find (lambda (action)
                (string= (map-elt action :kind) "reject_once"))
              actions))
   (t nil)))

(cl-defun acp--make-diff-viewing-function (&key diff actions client request-id state tool-call-id)
  "Create a diffing handler for the ACP CLIENT's REQUEST-ID and TOOL-CALL-ID.

DIFF as per `acp--make-diff-info'.
ACTIONS as per `acp--make-permission-action'."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (let ((shell-buffer (current-buffer)))
    (lambda ()
      (interactive)
      (if-let ((existing (map-nested-elt state (list :tool-calls tool-call-id :diff-buffer)))
               ((buffer-live-p existing)))
          (pop-to-buffer existing '((display-buffer-reuse-window
                                     display-buffer-use-some-window
                                     display-buffer-same-window)))
        (let ((diff-buffer
               (acp-diff
                :old (map-elt diff :old)
                :new (map-elt diff :new)
                :file (map-elt diff :file)
                :title (file-name-nondirectory (map-elt diff :file))
              :on-accept (lambda ()
                           (interactive)
                           (let ((action (acp--resolve-permission-choice-to-action
                                          :choice 'accept
                                          :actions actions)))
                             (acp-diff-kill-buffer (current-buffer))
                             (with-current-buffer shell-buffer
                               (acp--send-permission-response
                                :client client
                                :request-id request-id
                                :option-id (map-elt action :option-id)
                                :state state
                                :tool-call-id tool-call-id
                                :message-text (map-elt action :option)))))
              :on-reject (lambda ()
                           (interactive)
                           (when (acp-interrupt-confirmed-p)
                             (acp-diff-kill-buffer (current-buffer))
                             (with-current-buffer shell-buffer
                               (acp-interrupt t))))
              :on-exit (lambda ()
                         (if-let ((choice (condition-case nil
                                              (if (y-or-n-p "Accept changes?")
                                                  'accept
                                                'reject)
                                            (quit 'ignore)))
                                  (action (acp--resolve-permission-choice-to-action
                                           :choice choice
                                           :actions actions)))
                             (progn
                               (acp--send-permission-response
                                :client client
                                :request-id request-id
                                :option-id (map-elt action :option-id)
                                :state state
                                :tool-call-id tool-call-id
                                :message-text (map-elt action :option))
                               (when (eq choice 'reject)
                                 ;; No point in rejecting the change but letting
                                 ;; the agent continue (it doesn't know why you
                                 ;; have rejected the change).
                                 ;; May as well interrupt so you can course-correct.
                                 (with-current-buffer shell-buffer
                                   (acp-interrupt t))))
                           (message "Ignored"))))))
        ;; Track the diff buffer in tool-call state so it can be
        ;; cleaned up when the permission is resolved externally.
        (when-let ((tool-calls (map-elt state :tool-calls)))
          (map-put! tool-calls tool-call-id
                    (map-insert (map-elt tool-calls tool-call-id)
                                :diff-buffer diff-buffer))))))))

(cl-defun acp--make-permission-button (&key text help action keymap navigatable char option)
  "Create a permission button with TEXT, HELP, ACTION, and KEYMAP.

For example:

  \"[ Allow (y) ]\"

When NAVIGATABLE is non-nil, make button character navigatable.
CHAR and OPTION are used for cursor sensor messages."
  (let ((button (acp--make-button
                 :text text
                 :help help
                 :kind 'permission
                 :keymap keymap
                 :action action)))
    (when navigatable
      ;; Make the button character navigatable.
      ;;
      ;; For example, the "y" in:
      ;;
      ;; Graphical: " Allow (y) "
      ;;
      ;; Terminal: "[ Allow (y) ]"
      ;;
      ;; so adjust the offsets accordingly.
      (let ((trailing (if (display-graphic-p) 2 3)))
        (put-text-property (- (length button) (+ trailing 1))
                           (- (length button) trailing)
                           'acp-permission-button t button)
        (put-text-property (- (length button) (+ trailing 1))
                           (- (length button) trailing)
                           'cursor-sensor-functions
                           (list (lambda (_window _old-pos sensor-action)
                                   (when (eq sensor-action 'entered)
                                     (if char
                                         (message "Press RET or %s to %s" char option)
                                       (message "Press RET to %s" option)))))
                           button)))
    button))

(defun acp--make-permission-actions (acp-options)
  "Make actions from ACP-OPTIONS for shell rendering.

See `acp--make-permission-action' for ACP-OPTION and return schema."
  (let (acp-seen-kinds)
    (seq-sort (lambda (a b)
                (< (length (map-elt a :label))
                   (length (map-elt b :label))))
              (delq nil (mapcar (lambda (acp-option)
                                  (let ((action (acp--make-permission-action
                                                 :acp-option acp-option
                                                 :acp-seen-kinds acp-seen-kinds)))
                                    (push (map-elt acp-option 'kind) acp-seen-kinds)
                                    action))
                                acp-options)))))

(cl-defun acp--make-permission-action (&key acp-option acp-seen-kinds)
  "Convert a single ACP-OPTION to an action alist.

ACP-OPTION should be a PermissionOption per ACP spec:

  https://agentclientprotocol.com/protocol/schema#permissionoption

  An alist of the form:

  ((\='kind . \"allow_once\")
   (\='name . \"Allow\")
   (\='optionId . \"allow\"))

ACP-SEEN-KINDS is a list of kinds already processed.  If kind is in
ACP-SEEN-KINDS, omit the keybinding to avoid duplicates.

Returns an alist of the form:

  ((:label . \"Allow (y)\")
   (:option . \"Allow\")
   (:char . ?y)
   (:kind . \"allow_once\")
   (:option-id . ...))

Returns nil if the ACP-OPTION kind is not recognized."
  (let* ((char-map `(("allow_always" . "!")
                     ("allow_once" . "y")
                     ("reject_once" . ,(or (ignore-errors
                                             (key-description (where-is-internal 'acp-interrupt
                                                                                 acp-mode-map t)))
                                           "n"))))
         (kind (map-elt acp-option 'kind))
         (char (unless (member kind acp-seen-kinds)
                 (map-elt char-map kind)))
         (name (map-elt acp-option 'name)))
    (when (map-elt char-map kind)
      (map-into `((:label . ,(if char (format "%s (%s)" name char) name))
                  (:option . ,name)
                  (:char . ,char)
                  (:kind . ,kind)
                  (:option-id . ,(map-elt acp-option 'optionId)))
                'alist))))

(defun acp-jump-to-latest-permission-button-row ()
  "Jump to the latest permission button row.

Returns non-nil if a permission button was found, nil otherwise."
  (declare (modes acp-mode))
  (interactive)
  (when-let ((found (save-mark-and-excursion
                      (goto-char (point-max))
                      (acp-previous-permission-button))))
    (deactivate-mark)
    ;; Unless buffer is in window, cursor is not moved.
    ;; Make sure the cursor is moved even if buffer is in background.
    (when-let ((window (or (get-buffer-window (current-buffer))
                           (seq-first (window-list)))))
      (save-window-excursion
        (set-window-buffer window (current-buffer))
        (with-selected-window window
          (goto-char found)
          (beginning-of-line)
          (acp-next-permission-button)
          (set-window-point window (point)))))
    t))

(defun acp-next-permission-button ()
  "Jump to the next button."
  (declare (modes acp-mode))
  (interactive)
  (when-let* ((found (save-mark-and-excursion
                       (when (get-text-property (point) 'acp-permission-button)
                         (when-let ((next-change (next-single-property-change (point) 'acp-permission-button)))
                           (goto-char next-change)))
                       (when-let ((next (text-property-search-forward
                                         'acp-permission-button t t)))
                         (prop-match-beginning next)))))
    (deactivate-mark)
    (goto-char found)
    found))

(defun acp-previous-permission-button ()
  "Jump to the previous button."
  (declare (modes acp-mode))
  (interactive)
  (when-let* ((found (save-mark-and-excursion
                       (when (get-text-property (point) 'acp-permission-button)
                         (when-let ((prev-change (previous-single-property-change (point) 'acp-permission-button)))
                           (goto-char prev-change)))
                       (when-let ((prev (text-property-search-backward
                                         'acp-permission-button t t)))
                         (prop-match-beginning prev)))))
    (deactivate-mark)
    (goto-char found)
    found))

;;; Region

(cl-defun acp--insert-to-shell-buffer (&key shell-buffer text submit no-focus)
  "Insert TEXT into the agent shell buffer at `point-max'.

SHELL-BUFFER, when non-nil, specifies the target shell buffer.
Otherwise, uses `acp--shell-buffer' to find one.

SUBMIT, when non-nil, submits the shell buffer after insertion.

NO-FOCUS, when non-nil, avoid focusing shell on insertion.

Returns an alist with insertion details or nil otherwise:

  ((:buffer . BUFFER)
   (:start . START)
   (:end . END))"
  (unless text
    (user-error "No text provided to insert"))
  (let* ((shell-buffer (or shell-buffer
                           (acp--shell-buffer :no-create t))))
    (if (with-current-buffer shell-buffer
          (or (map-nested-elt acp--state '(:session :id))
              (eq acp-session-strategy 'new-deferred)))
        ;; Displaying before with-current-buffer below
        ;; ensures window is selected, thus window-point
        ;; is also updated after insertion.
        (let* ((inhibit-read-only t)
               (insert-start (if no-focus
                                 (with-current-buffer shell-buffer
                                   (point-max))
                               (acp--display-buffer shell-buffer)
                               (point-max)))
               (insert-end nil))
          (with-current-buffer shell-buffer
            (when (shell-maker-busy)
              (user-error "Busy, try later"))
            (save-excursion
              (save-restriction
                (goto-char insert-start)
                (unless submit
                  (insert "\n\n"))
                (insert text)
                (setq insert-end (point))
                (narrow-to-region insert-start insert-end)
                (let ((markdown-overlays-highlight-blocks acp-highlight-blocks)
                      (markdown-overlays-render-images nil))
                  (markdown-overlays-put))))
            (when submit
              (shell-maker-submit)))
          `((:buffer . ,shell-buffer)
            (:start . ,insert-start)
            (:end . ,insert-end)))
      (let ((token nil))
        (setq token
              (acp-subscribe-to
               :shell-buffer shell-buffer
               :event 'prompt-ready
               :on-event (lambda (_event)
                           (acp-unsubscribe :subscription token)
                           (acp--insert-to-shell-buffer
                            :text text :submit submit
                            :no-focus no-focus :shell-buffer shell-buffer))))))))

(cl-defun acp-insert (&key text submit no-focus shell-buffer)
  "Insert TEXT into the agent shell at `point-max'.

SUBMIT, when non-nil, submits the shell buffer after insertion.

NO-FOCUS, when non-nil, avoid focusing shell on insertion.

Use SHELL-BUFFER for insertion.

When `acp-prefer-viewport-interaction' is non-nil, prefer inserting
into the viewport compose buffer instead of the shell buffer.  If no compose
buffer exists, one will be created.

Returns an alist with insertion details or nil otherwise:

  ((:buffer . BUFFER)
   (:start . START)
   (:end . END))

Uses optional SHELL-BUFFER to make paths relative to shell project."
  (if acp-prefer-viewport-interaction
      (acp-viewport--show-buffer :append text :submit submit
                                         :no-focus no-focus :shell-buffer shell-buffer)
    (acp--insert-to-shell-buffer :text text :submit submit
                                         :no-focus no-focus :shell-buffer shell-buffer)))

(cl-defun acp-send-region (&optional pick-shell)
  "Send region to last accessed shell buffer in project.

When PICK-SHELL is non-nil, prompt for which shell buffer to use."
  (interactive)
  (let ((shell-buffer (or (when pick-shell
                            (completing-read "Send region to shell: "
                                             (mapcar #'buffer-name (or (acp-buffers)
                                                                       (user-error "No shells available")))
                                             nil t))
                          (acp--shell-buffer))))
    (acp-insert
     :text (acp--get-region-context
            :deactivate t
            :agent-cwd (with-current-buffer shell-buffer
                         (acp-cwd)))
     :shell-buffer shell-buffer)))

(defun acp-send-region-to ()
  "Like `acp-send-region' but prompt for which shell to use."
  (interactive)
  (acp-send-region t))

(cl-defun acp-send-dwim (&optional arg)
  "Send region or error at point to last accessed shell buffer in project.

With \\[universal-argument] prefix ARG, force start a new shell.

With \\[universal-argument] \\[universal-argument] prefix ARG, prompt to pick an existing shell."
  (interactive "P")
  (let ((shell-buffer
         (cond
          ((equal arg '(16))
           (acp--dwim :switch-to-shell t)
           (acp--shell-buffer))
          ((equal arg '(4))
           (acp--dwim :new-shell t)
           (acp--shell-buffer))
          (t
           (acp--shell-buffer)))))
    (acp-insert :text (acp--context :shell-buffer shell-buffer)
                        :shell-buffer shell-buffer)))

(cl-defun acp--get-region-context (&key deactivate no-error agent-cwd)
  "Get region as insertable text, ready for sending to agent.

When DEACTIVATE is non-nil, deactivate region.

When NO-ERROR is non-nil, return nil and continue without error.

Uses AGENT-CWD to shorten file paths where necessary."
  (let* ((region (or (acp--get-region :deactivate deactivate)
                     (unless no-error
                       (user-error "No region selected"))))
         (processed-text (if (map-elt region :file)
                             (let ((file-link (acp-ui-add-action-to-text
                                               (format "%s:%d-%d"
                                                       (if (and agent-cwd (file-in-directory-p (map-elt region :file) agent-cwd))
                                                           (file-relative-name (map-elt region :file) agent-cwd)
                                                         (map-elt region :file))
                                                       (map-elt region :line-start)
                                                       (map-elt region :line-end))
                                               (lambda ()
                                                 (interactive)
                                                 (if (and (map-elt region :file) (file-exists-p (map-elt region :file)))
                                                     (if-let ((window (when (get-file-buffer (map-elt region :file))
                                                                        (get-buffer-window (get-file-buffer (map-elt region :file))))))
                                                         (progn
                                                           (select-window window)
                                                           (goto-char (point-min))
                                                           (forward-line (1- (map-elt region :line-start)))
                                                           (beginning-of-line)
                                                           (push-mark (save-excursion
                                                                        (goto-char (point-min))
                                                                        (forward-line (1- (map-elt region :line-end)))
                                                                        (end-of-line)
                                                                        (point))
                                                                      t t))
                                                       (find-file (map-elt region :file))
                                                       (goto-char (point-min))
                                                       (forward-line (1- (map-elt region :line-start)))
                                                       (beginning-of-line)
                                                       (push-mark (save-excursion
                                                                    (goto-char (point-min))
                                                                    (forward-line (1- (map-elt region :line-end)))
                                                                    (end-of-line)
                                                                    (point))
                                                                  t t))
                                                   (message "File not found")))
                                               (lambda ()
                                                 (message "Press RET to open file"))
                                               'link))
                                   (numbered-preview
                                    (when-let ((buffer (get-file-buffer (map-elt region :file))))
                                      (let ((char-start (map-elt region :char-start))
                                            (char-end (map-elt region :char-end))
                                            (max-preview-lines 5))
                                        (if (equal (line-number-at-pos char-start)
                                                   (line-number-at-pos char-end))
                                            ;; Same line region? Avoid numbering.
                                            (buffer-substring char-start char-end)
                                          (acp--get-numbered-region
                                           :buffer buffer
                                           :from char-start
                                           :to char-end
                                           :cap max-preview-lines))))))
                               (if numbered-preview
                                   (concat file-link "\n\n" numbered-preview)
                                 file-link))
                           (map-elt region :content))))
    processed-text))

(cl-defun acp--get-numbered-region (&key buffer from to cap)
  "Get region from BUFFER between FROM and TO locations.

Expands to include entire lines.  Trims empty lines from beginning and end.

If CAP is non-nil, truncate at CAP."
  (with-current-buffer buffer
    (save-excursion
      (goto-char from)
      (let* ((start-line (line-number-at-pos from))
             (end-line (line-number-at-pos to))
             (lines '())
             (current-line start-line))
        (goto-char (point-min))
        (forward-line (1- start-line))
        (while (<= current-line end-line)
          (let ((line-content (buffer-substring
                               (line-beginning-position)
                               (line-end-position))))
            (push (format "   %d: %s" current-line line-content)
                  lines))
          (forward-line 1)
          (setq current-line (1+ current-line)))
        ;; Reverse the lines and trim empty lines from start and end
        (let ((reversed-lines (nreverse lines)))
          ;; Trim empty lines from the beginning
          (while (and reversed-lines
                      (string-match-p "^   [0-9]+:[[:space:]]*$" (car reversed-lines)))
            (setq reversed-lines (cdr reversed-lines)))
          ;; Trim empty lines from the end
          (setq reversed-lines (nreverse reversed-lines))
          (while (and reversed-lines
                      (string-match-p "^   [0-9]+:[[:space:]]*$" (car reversed-lines)))
            (setq reversed-lines (cdr reversed-lines)))
          ;; Reverse back to correct order and apply cap before final join
          (let ((final-lines (nreverse reversed-lines)))
            ;; Apply cap if specified
            (when (and cap (> (length final-lines) cap))
              (setq final-lines (append (seq-take final-lines cap) '("   ..."))))
            (string-join final-lines "\n")))))))

(cl-defun acp--format-diagnostic (&key buffer beg end line col type text)
  "Format a diagnostic error with context.
BUFFER is the buffer containing the error.
BEG and END are the error region positions.
LINE and COL are the line and column numbers.
TYPE is the error type/level.
TEXT is the error message."
  (let* ((file (acp--shorten-paths (buffer-file-name buffer) t))
         (code (when (and beg end)
                 (with-current-buffer buffer
                   (buffer-substring beg end))))
         (context-lines 3)
         (context (when beg
                    (with-current-buffer buffer
                      (save-excursion
                        (goto-char beg)
                        (let* ((start-line (max 1 (- line context-lines)))
                               (context-beg (progn
                                              (goto-char (point-min))
                                              (forward-line (1- start-line))
                                              (point)))
                               (context-end (progn
                                              (forward-line (+ context-lines context-lines 1))
                                              (point)))
                               (numbered-region (acp--get-numbered-region
                                                 :buffer buffer
                                                 :from context-beg
                                                 :to context-end))
                               ;; Replace the line number prefix for the error line
                               (error-line-prefix (format "   %d:" line))
                               (highlight-prefix (format "-> %d:" line)))
                          (replace-regexp-in-string
                           (regexp-quote error-line-prefix)
                           highlight-prefix
                           numbered-region
                           nil 'literal)))))))
    (if (or (not code) (string-empty-p (string-trim code)))
        (format "%s:%d:%d: %s: %s"
                (or file (buffer-name buffer))
                line (or col 0) type text)
      (format "%s:%d:%d: %s: %s\n\n%s"
              (or file (buffer-name buffer))
              line (or col 0) type text context))))

(defun acp--get-flymake-error-context ()
  "Get flymake error at point, ready for sending to agent."
  (when-let ((diagnostics (flymake-diagnostics (point))))
    (mapconcat
     (lambda (diagnostic)
       (let* ((buffer (flymake-diagnostic-buffer diagnostic))
              (beg (flymake-diagnostic-beg diagnostic))
              (end (flymake-diagnostic-end diagnostic))
              (type (flymake-diagnostic-type diagnostic))
              (text (flymake-diagnostic-text diagnostic))
              (line (with-current-buffer buffer
                      (line-number-at-pos beg)))
              (col (with-current-buffer buffer
                     (save-excursion
                       (goto-char beg)
                       (current-column)))))
         (acp--format-diagnostic
          :buffer buffer
          :beg beg
          :end end
          :line line
          :col col
          :type type
          :text text)))
     diagnostics
     "\n\n")))

(defun acp--get-flycheck-error-context ()
  "Get flycheck error at point, ready for sending to agent."
  (when-let (((bound-and-true-p flycheck-mode))
             ((fboundp 'flycheck-overlay-errors-at))
             (errors (flycheck-overlay-errors-at (point))))
    (mapconcat
     (lambda (err)
       (let* ((buffer (current-buffer))
              (beg (flycheck-error-pos err))
              (end (when beg
                     (save-excursion
                       (goto-char beg)
                       (if-let ((end-line (flycheck-error-end-line err))
                                (end-col (flycheck-error-end-column err)))
                           (progn
                             (forward-line (- end-line (line-number-at-pos)))
                             (move-to-column end-col)
                             (point))
                         beg))))
              (type (flycheck-error-level err))
              (text (flycheck-error-message err))
              (line (flycheck-error-line err))
              (col (flycheck-error-column err)))
         (acp--format-diagnostic
          :buffer buffer
          :beg beg
          :end end
          :line line
          :col col
          :type type
          :text text)))
     errors
     "\n\n")))

(defun acp--get-error-context ()
  "Get error at point from either flymake or flycheck, whichever is available.
Tries flymake first, then flycheck."
  (or (acp--get-flymake-error-context)
      (acp--get-flycheck-error-context)))

(cl-defun acp--get-current-line-context (&key agent-cwd)
  "Get the current line as insertable text, ready for sending to agent.

Uses AGENT-CWD to shorten file paths where necessary."
  (save-excursion
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (goto-char start)
      (set-mark end)
      (activate-mark)
      (acp--get-region-context :deactivate t :no-error t :agent-cwd agent-cwd))))

(cl-defun acp--context (&key shell-buffer)
  "Return context (if available).  Nil otherwise.

Uses optional SHELL-BUFFER to make paths relative to shell project.

Context could be either a region or error at point or files.
The sources checked are controlled by `acp-context-sources'."
  (unless (and (derived-mode-p 'acp-mode)
               (not (region-active-p)))
    (let ((agent-cwd (when shell-buffer
                       (with-current-buffer shell-buffer
                         (acp-cwd)))))
      (seq-some
       (lambda (source)
         (pcase source
           ('files (acp--get-files-context
                    :files (acp--buffer-files :obvious t)
                    :agent-cwd agent-cwd))
           ('region (acp--get-region-context
                     :deactivate t :no-error t
                     :agent-cwd agent-cwd))
           ('error (acp--get-error-context))
           ('line (acp--get-current-line-context
                   :agent-cwd agent-cwd))
           ((pred functionp) (funcall source))))
       acp-context-sources))))

(cl-defun acp--get-region (&key deactivate)
  "Get the active region as an alist.

When DEACTIVATE is non-nil, deactivate region/selection.

Available values:

 :file :language :char-start :char-end :line-start :line-end and :content."
  (when (region-active-p)
    (let ((start (region-beginning))
          (end (region-end))
          (content (buffer-substring-no-properties (region-beginning) (region-end)))
          (language (string-remove-suffix "-mode" (string-remove-suffix "-ts-mode" (symbol-name major-mode))))
          (file (buffer-file-name)))
      (when deactivate
        (deactivate-mark))
      `((:file . ,file)
        (:language . ,language)
        (:char-start . ,start)
        (:char-end . ,end)
        (:line-start . ,(save-excursion (goto-char start) (line-number-at-pos)))
        (:line-end . ,(save-excursion (goto-char end) (line-number-at-pos)))
        (:content . ,content)))))

(cl-defun acp--align-alist (&key data columns (separator "  ") joiner)
  "Align COLUMNS from DATA.

DATA is a list of alists.  COLUMNS is a list of extractor functions,
where each extractor takes one alist and returns a string for that
column.  SEPARATOR is the string used to join columns (defaults to
two spaces).  JOINER, when provided, wraps the result with
`string-join' using JOINER as the separator.

Returns a list of strings with spaced-aligned columns, or a single
joined string if JOINER is provided."
  (let* ((rows (mapcar
                (lambda (item)
                  (mapcar (lambda (extractor) (funcall extractor item))
                          columns))
                data))
         (widths (seq-reduce
                  (lambda (acc row)
                    (seq-mapn #'max
                              acc
                              (mapcar (lambda (cell) (length (or cell ""))) row)))
                  rows
                  (make-list (length columns) 0)))
         (result (mapcar (lambda (row)
                           (string-trim-right
                            (string-join
                             (seq-mapn (lambda (cell width)
                                         (format (format "%%-%ds" width) (or cell "")))
                                       row
                                       widths)
                             separator)))
                         rows)))
    (if joiner
        (string-join result joiner)
      result)))

(cl-defun acp--get-decorated-region (&key deactivate)
  "Get the active region decorated with file path and Markdown code block.

When DEACTIVATE is non-nil, deactivate region/selection."
  (when-let ((region-data (acp--get-region :deactivate deactivate)))
    (let ((file (map-elt region-data :file))
          (start (map-elt region-data :char-start))
          (end (map-elt region-data :char-end))
          (language (map-elt region-data :language))
          (content (map-elt region-data :content)))
      (concat (if file
                  (format "%s#C%d-C%d\n\n" file start end)
                "")
              "```"
              language
              "\n"
              content
              "\n"
              "```"))))

;;; Session modes

(defun acp--get-available-modes (state)
  "Get available modes list, preferring session modes over agent modes.

STATE is the agent shell state.

Returns the modes list from session if available, otherwise from
the agent's available modes."
  (or (map-nested-elt state '(:session :modes))
      ;; Use agent-level availability as fallback.
      (map-nested-elt state '(:available-modes :modes))))

(defun acp--resolve-session-mode-name (mode-id available-session-modes)
  "Get the name of the session mode with MODE-ID from AVAILABLE-SESSION-MODES.

AVAILABLE-SESSION-MODES is the list of mode objects from the ACP
session/new response.  Each mode has an `:id' and `:name' field.
We look up the mode by ID to get its display name.

See https://agentclientprotocol.com/protocol/session-modes for details."
  (when-let ((mode (seq-find (lambda (m)
                               (string= mode-id (map-elt m :id)))
                             available-session-modes)))
    (map-elt mode :name)))

(defun acp--busy-indicator-frame ()
  "Return busy frame string or nil if not busy."
  (when-let* ((acp-show-busy-indicator)
              ((eq 'busy (map-nested-elt (acp--state) '(:heartbeat :status))))
              (frames (pcase acp-busy-indicator-frames
                        ('wave '("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█" "▇" "▆" "▅" "▄" "▃" "▂"))
                        ('dots-block '("⣷" "⣯" "⣟" "⡿" "⢿" "⣻" "⣽" "⣾"))
                        ('dots-round '("⢎⡰" "⢎⡡" "⢎⡑" "⢎⠱" "⠎⡱" "⢊⡱" "⢌⡱" "⢆⡱"))
                        ('wide '("░   " "░░  " "░░░ " "░░░░" "░░░ " "░░  " "░   " "    "))
                        ((pred listp) acp-busy-indicator-frames)
                        (_ '("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█" "▇" "▆" "▅" "▄" "▃" "▂"))))
              (value (map-nested-elt (acp--state) '(:heartbeat :value))))
    (concat " " (seq-elt frames (mod value (length frames))))))

(defun acp--mode-line-format ()
  "Return `acp''s mode-line format.

Typically includes the container indicator, model, session mode and activity
or nil if unavailable.

For example: \" [C] [Sonnet] [Accept Edits] ░░░ \".
Shows \" [C]\" when a command prefix is used."
  (when-let* (((derived-mode-p 'acp-mode))
              ((memq acp-header-style '(text none nil))))
    (concat (when acp-command-prefix
              (propertize " [C]"
                          'face 'font-lock-constant-face
                          'help-echo "Running in container"))
            (when-let ((model-name (or (map-elt (seq-find (lambda (model)
                                                            (string= (map-elt model :model-id)
                                                                     (map-nested-elt (acp--state) '(:session :model-id))))
                                                          (map-nested-elt (acp--state) '(:session :models)))
                                                :name)
                                       (map-nested-elt (acp--state) '(:session :model-id)))))
              (propertize (format " [%s]" model-name)
                          'face 'font-lock-variable-name-face
                          'help-echo (format "Model: %s" model-name)))
            (when-let ((mode-name (acp--resolve-session-mode-name
                                   (map-nested-elt (acp--state) '(:session :mode-id))
                                   (acp--get-available-modes (acp--state)))))
              (propertize (format " [%s]" mode-name)
                          'face 'font-lock-type-face
                          'help-echo (format "Session Mode: %s" mode-name)))
            (when-let ((indicator (acp--context-usage-indicator)))
              (concat " " indicator))
            (acp--busy-indicator-frame))))

(defun acp--setup-modeline ()
  "Set up the modeline to display session mode.
Uses :eval so the mode updates automatically when state changes."
  (setq-local mode-line-misc-info
              (append mode-line-misc-info
                      '((:eval (acp--mode-line-format))))))

(defun acp-cycle-session-mode (&optional on-success)
  "Cycle through available session modes for the current `acp' session.

Optionally, get notified of completion with ON-SUCCESS function."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (user-error "Not in an acp buffer"))
  (unless (map-nested-elt (acp--state) '(:session :id))
    (user-error "No active session"))
  (unless (acp--get-available-modes (acp--state))
    (user-error "No session modes available"))
  (let* ((mode-ids (mapcar (lambda (mode)
                             (map-elt mode :id))
                           (acp--get-available-modes (acp--state))))
         (mode-idx (or (seq-position mode-ids
                                     (map-nested-elt (acp--state) '(:session :mode-id))
                                     #'string=) -1))
         (next-mode-idx (mod (1+ mode-idx) (length mode-ids)))
         (next-mode-id (nth next-mode-idx mode-ids)))
    (acp--send-request
     :state (acp--state)
     :client (map-elt (acp--state) :client)
     :request (acp-make-session-set-mode-request
               :session-id (map-nested-elt (acp--state) '(:session :id))
               :mode-id next-mode-id)
     :buffer (current-buffer)
     :on-success (lambda (_acp-response)
                   (let ((updated-session (map-elt (acp--state) :session)))
                     (map-put! updated-session :mode-id next-mode-id)
                     (map-put! (acp--state) :session updated-session)
                     (message "Session mode: %s"
                              (acp--resolve-session-mode-name
                               next-mode-id
                               (acp--get-available-modes (acp--state)))))
                   (acp--update-header-and-mode-line)
                   (when on-success
                     (funcall on-success)))
     :on-failure (lambda (acp-error _raw-message)
                   (message "Failed to change session mode: %s" acp-error)))))

(defun acp-set-session-mode (&optional on-success)
  "Set session mode (if any available).

Optionally, get notified of completion with ON-SUCCESS function."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (user-error "Not in an acp buffer"))
  (unless (map-nested-elt (acp--state) '(:session :id))
    (user-error "No active session"))
  (unless (acp--get-available-modes (acp--state))
    (user-error "No session modes available"))
  (let* ((current-mode-id (map-nested-elt (acp--state) '(:session :mode-id)))
         (default-mode-name (and current-mode-id
                                 (acp--resolve-session-mode-name
                                  current-mode-id
                                  (acp--get-available-modes (acp--state)))))
         (mode-choices (mapcar (lambda (mode)
                                 (cons (map-elt mode :name)
                                       (map-elt mode :id)))
                               (acp--get-available-modes (acp--state))))
         (selection (completing-read "Set session mode: "
                                     (mapcar #'car mode-choices)
                                     nil t nil nil default-mode-name))
         (selected-mode-id (cdr (seq-find (lambda (choice)
                                            (string= selection (car choice)))
                                          mode-choices))))
    (unless selected-mode-id
      (user-error "Unknown session mode: %s" selection))
    (when (and current-mode-id (string= selected-mode-id current-mode-id))
      (error "Session mode already %s" selection))
    (acp--send-request
     :state (acp--state)
     :client (map-elt (acp--state) :client)
     :request (acp-make-session-set-mode-request
               :session-id (map-nested-elt (acp--state) '(:session :id))
               :mode-id selected-mode-id)
     :buffer (current-buffer)
     :on-success (lambda (_acp-response)
                   (let ((updated-session (map-elt (acp--state) :session)))
                     (map-put! updated-session :mode-id selected-mode-id)
                     (map-put! (acp--state) :session updated-session)
                     (message "Session mode: %s"
                              (acp--resolve-session-mode-name
                               selected-mode-id
                               (acp--get-available-modes (acp--state)))))
                   (acp--update-header-and-mode-line)
                   (when on-success
                     (funcall on-success)))
     :on-failure (lambda (acp-error _raw-message)
                   (message "Failed to change session mode: %s" acp-error)))))

(defun acp-set-session-model (&optional on-success)
  "Set session model.

Optionally, get notified of completion with ON-SUCCESS function."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (user-error "Not in an acp buffer"))
  (unless (map-nested-elt (acp--state) '(:session :id))
    (user-error "No active session"))
  (unless (map-nested-elt (acp--state) '(:session :models))
    (user-error "No session models available"))
  (let* ((current-model-id (map-nested-elt (acp--state) '(:session :model-id)))
         (available-models (map-nested-elt (acp--state) '(:session :models)))
         (default-model-name (and current-model-id
                                  (map-elt (seq-find (lambda (model)
                                                       (string= (map-elt model :model-id) current-model-id))
                                                     available-models)
                                           :name)))
         (model-choices (seq-mapn (lambda (title model)
                                    (cons title (map-elt model :model-id)))
                                  (acp--align-alist
                                   :data available-models
                                   :columns (list
                                             (lambda (model)
                                               (map-elt model :name))
                                             (lambda (model)
                                               (format "(%s)" (map-elt model :model-id)))))
                                  available-models))
         (selection (completing-read "Set model: "
                                     (mapcar #'car model-choices)
                                     nil t nil nil
                                     (and default-model-name
                                          (car (seq-find (lambda (choice)
                                                           (string-prefix-p default-model-name (car choice)))
                                                         model-choices)))))
         (selected-model-id (cdr (seq-find (lambda (choice)
                                             (string= selection (car choice)))
                                           model-choices))))
    (unless selected-model-id
      (user-error "Unknown model: %s" selection))
    (when (and current-model-id (string= selected-model-id current-model-id))
      (error "Session model already %s" (map-elt (seq-find (lambda (model)
                                                             (string= (map-elt model :model-id) selected-model-id))
                                                           available-models)
                                                 :name)))
    (acp--send-request
     :state (acp--state)
     :client (map-elt (acp--state) :client)
     :request (acp-make-session-set-model-request
               :session-id (map-nested-elt (acp--state) '(:session :id))
               :model-id selected-model-id)
     :on-success (lambda (_acp-response)
                   (let ((updated-session (map-elt (acp--state) :session)))
                     (map-put! updated-session :model-id selected-model-id)
                     (map-put! (acp--state) :session updated-session)
                     (message "Model: %s"
                              (map-elt (seq-find (lambda (model)
                                                   (string= (map-elt model :model-id) selected-model-id))
                                                 (map-nested-elt (acp--state) '(:session :models)))
                                       :name)))
                   (acp--update-header-and-mode-line)
                   (when on-success
                     (funcall on-success)))
     :on-failure (lambda (acp-error _raw-message)
                   (message "Failed to change model: %s" acp-error)))))

(defun acp--format-available-modes (modes)
  "Format MODES for shell rendering.
If CURRENT-MODE-ID is provided, append \"(current)\" to the matching mode name."
  (acp--align-alist
   :data modes
   :columns (list
             (lambda (mode)
               (when (map-elt mode :name)
                 (propertize (format "%s (%s)"
                                     (map-elt mode :name)
                                     (map-elt mode :id))
                             'font-lock-face 'font-lock-function-name-face)))
             (lambda (mode)
               (when (map-elt mode :description)
                 (propertize (map-elt mode :description)
                             'font-lock-face 'font-lock-comment-face))))
   :joiner "\n"))

(defun acp--format-available-models (models)
  "Format MODELS for shell rendering.

Mark model using CURRENT-MODEL-ID."
  (acp--align-alist
   :data models
   :columns (list
             (lambda (model)
               (concat
                (when (map-elt model :name)
                  (propertize (map-elt model :name)
                              'font-lock-face 'font-lock-function-name-face))
                (when (map-elt model :model-id)
                  (propertize (format " (%s)" (map-elt model :model-id))
                              'font-lock-face 'font-lock-function-name-face))))
             (lambda (model)
               (when (map-elt model :description)
                 (propertize (map-elt model :description)
                             'font-lock-face 'font-lock-comment-face))))
   :joiner "\n"))

;;; Transient

(transient-define-prefix acp-help-menu ()
  "Transient menu for `acp' commands."
  [["Navigation"
    ("<tab>" "Next item" acp-next-item :transient t)
    ("<backtab>" "Previous item" acp-previous-item :transient t)]
   ["Insert"
    ("!" "Shell command" acp-insert-shell-command-output :transient t)
    ("@" "File" acp-insert-file :transient t)
    ("d" "Dwim" acp-send-dwim :transient t)
    ]]
  [["Session"
    ("m" "Cycle modes" acp-cycle-session-mode :transient t)
    ("M" "Set mode" acp-set-session-mode :transient t)
    ("v" "Set model" acp-set-session-model :transient t)
    ("C" "Interrupt" acp-interrupt :transient t)]
   ["Shell"
    ("b" "Toggle" acp-toggle :transient t)
    ("N" "New shell" acp-new-shell)]])

;;; Transcript

(defcustom acp-transcript-file-path-function #'acp--default-transcript-file-path
  "Function to generate the full transcript file path.
Called with no arguments, should return a string path or nil to disable.
When nil, transcript saving is disabled."
  :type '(choice (const :tag "Disabled" nil)
                 (function :tag "Custom function"))
  :group 'acp)

(defun acp--default-transcript-file-path ()
  "Generate a transcript file path in project root.

For example:

 project/.acp/transcripts/."
  (let* ((dir (acp--dot-subdir "transcripts"))
         (filename (format-time-string "%F-%H-%M-%S.md"))
         (filepath (expand-file-name filename dir)))
    filepath))

(defun acp--transcript-file-path ()
  "Return the transcript file path, or nil if disabled."
  (when-let ((path-fn acp-transcript-file-path-function))
    (condition-case err
        (funcall path-fn)
      (error
       (message "Failed to generate transcript path: %S" err)
       nil))))

(defun acp--ensure-transcript-file ()
  "Ensure the transcript file exists, creating it with header if needed.
Returns the file path, or nil if disabled."
  (unless (derived-mode-p 'acp-mode)
    (user-error "Not in an acp buffer"))
  (when-let* ((filepath acp--transcript-file)
              (dir (file-name-directory filepath)))
    (unless (file-exists-p filepath)
      (condition-case err
          (let ((agent-name (or (map-nested-elt acp--state '(:agent-config :mode-line-name))
                                (map-nested-elt acp--state '(:agent-config :buffer-name))
                                "Unknown Agent")))
            (write-region
             (format "# Agent Shell Transcript

**Agent:** %s
**Started:** %s
**Working Directory:** %s

---

"
                     agent-name
                     (format-time-string "%F %T")
                     (acp-cwd))
             nil filepath nil 'no-message)
            (message "Created %s"
                     (acp--shorten-paths filepath t)))
        (error
         (message "Failed to initialize transcript: %S" err))))
    filepath))

(defun acp--indent-markdown-headers (text)
  "Indent markdown headers in TEXT by 2 levels for transcript hierarchy.

Increases the level of all markdown headers while leaving content
inside code blocks unchanged.  Headers are capped at level 6
since markdown doesn't support deeper levels.

For example:

  (acp--indent-markdown-headers \"# Foo\")
    => \"### Foo\"
  (acp--indent-markdown-headers \"##### Deep\")
    => \"###### Deep\""
  (unless (stringp text)
    (setq text (or text "")))
  (let ((lines (split-string text "\n"))
        (in-code-block nil)
        (result nil))
    (dolist (line lines)
      (cond
       ;; Toggle code block state on fence lines (3+ backticks).
       ((string-match "\\`\\(```+\\)" line)
        (if in-code-block
            (when (>= (length (match-string 1 line)) in-code-block)
              (setq in-code-block nil))
          (setq in-code-block (length (match-string 1 line))))
        (push line result))
       ;; Outside code blocks, indent header lines.
       ((and (not in-code-block)
             (string-match "\\`\\(#+\\) " line))
        (let* ((hashes (match-string 1 line))
               (new-level (min 6 (+ (length hashes) 2)))
               (new-hashes (make-string new-level ?#)))
          (push (replace-regexp-in-string "\\`#+ " (concat new-hashes " ") line)
                result)))
       (t (push line result))))
    (mapconcat #'identity (nreverse result) "\n")))


(cl-defun acp--append-transcript (&key text file-path)
  "Append TEXT to the transcript at FILE-PATH."
  (when (and file-path (acp--ensure-transcript-file))
    (condition-case err
        (write-region text nil file-path t 'no-message)
      (error
       (message "Error writing to transcript: %S" err)))))

(defun acp--extract-tool-parameters (raw-input)
  "Extract and format tool parameters from RAW-INPUT.
Returns a formatted string of key parameters, or nil if no relevant
parameters found.  Excludes `command' and `description' as these are
already shown separately in transcript entries.

For example, given RAW-INPUT:

  \\='((filePath . \"/home/user/project/file.el\")
    (offset . 10)
    (limit . 20)
    (command . \"grep -r foo\")
    (description . \"Search for foo\"))

returns:

  \"filePath: /home/user/project/file.el
  offset: 10
  limit: 20\""
  (when-let* ((raw-input)
            (excluded-keys '(command description plan))
            (params (seq-remove
                     (lambda (pair)
                       (let ((key (car pair))
                             (value (cdr pair)))
                         (or (memq key excluded-keys)
                             (null value)
                             (and (stringp value) (string-empty-p value)))))
                     raw-input)))
  (mapconcat (lambda (pair)
               (format "%s: %s"
                       (symbol-name (car pair))
                       (cond
                        ((stringp (cdr pair)) (cdr pair))
                        ((numberp (cdr pair)) (number-to-string (cdr pair)))
                        ((eq (cdr pair) t) "true")
                        (t (prin1-to-string (cdr pair))))))
             params
             "\n")))

(defun acp--longest-backtick-run (text)
  "Return the length of the longest consecutive backtick sequence in TEXT.

For example:

  (acp--longest-backtick-run \"no backticks\")
    => 0
  (acp--longest-backtick-run \"has ``` three\")
    => 3
  (acp--longest-backtick-run \"has ```` four and ``` three\")
    => 4"
  (let ((pos 0)
        (max-run 0))
    (while (string-match "`+" text pos)
      (setq max-run (max max-run (- (match-end 0) (match-beginning 0)))
            pos (match-end 0)))
    max-run))

(cl-defun acp--make-transcript-tool-call-entry (&key status title kind description command parameters output)
  "Create a formatted transcript entry for a tool call.

Includes STATUS, TITLE, KIND, DESCRIPTION, COMMAND, PARAMETERS, and OUTPUT."
  (let* ((trimmed (string-trim output))
         (fence (make-string (max 3 (1+ (acp--longest-backtick-run trimmed))) ?`)))
    (concat
     (format "\n\n### Tool Call [%s]: %s\n"
             (or status "no status") (or title ""))
     (when kind
       (format "\n**Tool:** %s" kind))
     (format "\n**Timestamp:** %s" (format-time-string "%F %T"))
     (when description
       (format "\n**Description:** %s" description))
     (when command
       (format "\n**Command:** %s" command))
     (when parameters
       (format "\n**Parameters:**\n%s" parameters))
     "\n\n"
     fence
     "\n"
     trimmed
     "\n"
     fence
     "\n")))

(defun acp-open-transcript ()
  "Open the transcript file for the current `acp' buffer."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in an acp buffer"))
  (unless acp--transcript-file
    (error "No transcript file available for this buffer"))
  (unless (file-exists-p acp--transcript-file)
    (error "Transcript file does not exist: %s" acp--transcript-file))
  (find-file acp--transcript-file))

;;; Queueing

(cl-defun acp--process-pending-request ()
  "Process the next pending request from the queue if available."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (when-let ((pending (map-elt acp--state :pending-requests))
             (next-request (car pending)))
    (map-put! acp--state :pending-requests (cdr pending))
    (acp--insert-to-shell-buffer
     :text next-request
     :submit t
     :no-focus t)))

(defun acp--display-pending-requests ()
  "Display pending requests in the shell buffer if queue is not empty."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (unless (seq-empty-p (map-elt acp--state :pending-requests))
    (acp--update-fragment
     :state (acp--state)
     :block-id (format "%s-pending-requests"
                       (map-elt (acp--state) :request-count))
     :body (format "Pending requests: %d

%s

Resume: M-x acp-resume-pending-requests
Remove: M-x acp-remove-pending-request
"
                   (seq-length (map-elt acp--state :pending-requests))
                   (mapconcat
                    (lambda (idx-req)
                      (let* ((req (car idx-req))
                             (idx (cdr idx-req))
                             (first-line (car (split-string req "\n" t))))
                        (format "  %d: \"%s\""
                                (1+ idx)
                                (truncate-string-to-width first-line 80 nil nil "..."))))
                    (seq-map-indexed #'cons (map-elt acp--state :pending-requests))
                    "\n"))
     :create-new t)))

(cl-defun acp--enqueue-request (&key prompt)
  "Add PROMPT to the pending requests queue."
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (let ((pending (map-elt acp--state :pending-requests)))
    (map-put! acp--state :pending-requests
              (append pending (list prompt)))
    (message "Request queued (%d pending)" (length (map-elt acp--state :pending-requests)))))

(defun acp-queue-request (prompt)
  "Queue or immediately send a request depending on shell busy state.

Read PROMPT from the minibuffer.  If the shell is busy, add it to the pending
requests queue.  Otherwise, submit it immediately.  Queued requests will be
automatically sent when the current request completes."
  (interactive
   (progn
     (unless (derived-mode-p 'acp-mode)
       (error "Not in a shell"))
     (list (read-string (or (map-nested-elt (acp--state) '(:agent-config :shell-prompt))
                            "Enqueue request: ")))))
  (if (shell-maker-busy)
      (acp--enqueue-request :prompt prompt)
    (acp--insert-to-shell-buffer :text prompt :submit t :no-focus t)))

(defun acp-resume-pending-requests ()
  "Resume processing pending requests in the queue."
  (declare (modes acp-mode))
  (interactive)
  (unless (derived-mode-p 'acp-mode)
    (error "Not in a shell"))
  (when (seq-empty-p (map-elt acp--state :pending-requests))
    (user-error "No pending requests"))
  (if (shell-maker-busy)
      (message "Shell is busy, requests will auto-resume when ready")
    (acp--process-pending-request)))

(defun acp-remove-pending-request (&optional remove-index)
  "Remove all pending requests or a specific request by REMOVE-INDEX.

When called interactively with pending requests, prompt to either remove all
or select a specific request to remove."
  (declare (modes acp-mode))
  (interactive
   (let ((pending (map-elt acp--state :pending-requests)))
     (unless (derived-mode-p 'acp-mode)
       (error "Not in a shell"))
     (when (seq-empty-p pending)
       (user-error "No pending requests"))
     (let* ((choices (append
                      '(("Remove all" . remove-all))
                      (seq-map-indexed
                       (lambda (req idx)
                         (cons (format "%d: %s" (1+ idx)
                                       (truncate-string-to-width req 60 nil nil "..."))
                               idx))
                       pending)))
            (selection (cdr (assoc (completing-read "Remove: " choices nil t) choices))))
       (list (unless (eq selection 'remove-all) selection)))))
  (if remove-index
      (when-let* ((message "Remove? \"%s\"")
                  (confirmed (y-or-n-p (format message
                                               (nth remove-index
                                                    (map-elt acp--state :pending-requests)))))
                  (pending (map-elt acp--state :pending-requests))
                  (new-pending (append (seq-take pending remove-index)
                                       (seq-drop pending (1+ remove-index)))))
        (map-put! acp--state :pending-requests new-pending)
        (message "Removed (%d remaining)"
                 (length new-pending)))
    (when (y-or-n-p (format "Remove %d pending requests?"
                            (length (map-elt acp--state :pending-requests))))
      (map-put! acp--state :pending-requests nil)
      (message "Removed all pending requests"))))

(provide 'acp)

;;; acp.el ends here

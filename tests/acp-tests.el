;;; acp-tests.el --- Tests for acp -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp)

;;; Code:

(ert-deftest acp-make-environment-variables-test ()
  "Test `acp-make-environment-variables' function."
  ;; Test basic key-value pairs
  (should (equal (acp-make-environment-variables
                  "PATH" "/usr/bin"
                  "HOME" "/home/user")
                 '("PATH=/usr/bin"
                   "HOME=/home/user")))

  ;; Test empty input
  (should (equal (acp-make-environment-variables) '()))

  ;; Test single pair
  (should (equal (acp-make-environment-variables "FOO" "bar")
                 '("FOO=bar")))

  ;; Test with keywords (should be filtered out)
  (should (equal (acp-make-environment-variables
                  "VAR1" "value1"
                  :inherit-env nil
                  "VAR2" "value2")
                 '("VAR1=value1"
                   "VAR2=value2")))

  ;; Test error on incomplete pairs
  (should-error (acp-make-environment-variables "PATH")
                :type 'error)

  ;; Test :inherit-env t
  (let ((process-environment '("EXISTING_VAR=existing_value"
                               "MY_OTHER_VAR=another_value")))
    (should (equal (acp-make-environment-variables
                    "NEW_VAR" "new_value"
                    :inherit-env t)
                   '("NEW_VAR=new_value"
                     "EXISTING_VAR=existing_value"
                     "MY_OTHER_VAR=another_value"))))

  ;; Test :load-env with single file
  (let ((env-file (let ((file (make-temp-file "test-env" nil ".env")))
                    (with-temp-file file
                      (insert "TEST_VAR=test_value\n")
                      (insert "# This is a comment\n")
                      (insert "ANOTHER_TEST=another_value\n")
                      (insert "\n")  ; empty line
                      (insert "THIRD_VAR=third_value\n"))
                    file)))
    (unwind-protect
        (should (equal (acp-make-environment-variables
                        "MANUAL_VAR" "manual_value"
                        :load-env env-file)
                       '("MANUAL_VAR=manual_value"
                         "TEST_VAR=test_value"
                         "ANOTHER_TEST=another_value"
                         "THIRD_VAR=third_value")))
      (delete-file env-file)))

  ;; Test :load-env with multiple files
  (let ((env-file1 (let ((file (make-temp-file "test-env1" nil ".env")))
                     (with-temp-file file
                       (insert "FILE1_VAR=file1_value\n")
                       (insert "SHARED_VAR=from_file1\n"))
                     file))
        (env-file2 (let ((file (make-temp-file "test-env2" nil ".env")))
                     (with-temp-file file
                       (insert "FILE2_VAR=file2_value\n")
                       (insert "SHARED_VAR=from_file2\n"))
                     file)))
    (unwind-protect
        (should (equal (acp-make-environment-variables
                        :load-env (list env-file1 env-file2))
                       '("FILE1_VAR=file1_value"
                         "SHARED_VAR=from_file1"
                         "FILE2_VAR=file2_value"
                         "SHARED_VAR=from_file2")))
      (delete-file env-file1)
      (delete-file env-file2)))

  ;; Test :load-env with non-existent file (should error)
  (should-error (acp-make-environment-variables
                 "TEST_VAR" "test_value"
                 :load-env "/non/existent/file")
                :type 'error)

  ;; Test :load-env combined with :inherit-env
  (let ((env-file (let ((file (make-temp-file "test-env" nil ".env")))
                    (with-temp-file file
                      (insert "ENV_FILE_VAR=env_file_value\n"))
                    file))
        (process-environment '("EXISTING_VAR=existing_value")))
    (unwind-protect
        (should (equal (acp-make-environment-variables
                        "MANUAL_VAR" "manual_value"
                        :load-env env-file
                        :inherit-env t)
                       '("MANUAL_VAR=manual_value"
                         "ENV_FILE_VAR=env_file_value"
                         "EXISTING_VAR=existing_value")))
      (delete-file env-file))))

(ert-deftest acp--shorten-paths-test ()
  "Test `acp--shorten-paths' function."
  ;; Mock acp-cwd to return a predictable value
  (cl-letf (((symbol-function 'acp-cwd)
             (lambda () "/path/to/acp/")))

    ;; Test shortening full paths to project-relative format
    (should (equal (acp--shorten-paths
                    "/path/to/acp/README.org")
                   "README.org"))

    ;; Test with subdirectories
    (should (equal (acp--shorten-paths
                    "/path/to/acp/tests/acp-tests.el")
                   "tests/acp-tests.el"))

    ;; Test mixed text with project path
    (should (equal (acp--shorten-paths
                    "Read /path/to/acp/acp.el (4 - 6)")
                   "Read acp.el (4 - 6)"))

    ;; Test text that doesn't contain project path (should remain unchanged)
    (should (equal (acp--shorten-paths
                    "Some random text without paths")
                   "Some random text without paths"))

    ;; Test text with different paths (should remain unchanged)
    (should (equal (acp--shorten-paths
                    "/some/other/path/file.txt")
                   "/some/other/path/file.txt"))

    ;; Test nil input
    (should (equal (acp--shorten-paths nil) nil))

    ;; Test empty string
    (should (equal (acp--shorten-paths "") ""))))

(ert-deftest acp--format-plan-test ()
  "Test `acp--format-plan' function."
  (dolist (test-case `(;; Graphical display mode
                       ( :graphic t
                         :homogeneous-expected
                         ,(concat " wait  Update state initialization\n"
                                  " wait  Update session initialization")
                         :mixed-expected
                         ,(concat " wait  First task\n"
                                  " busy  Second task\n"
                                  " done  Third task"))
                       ;; Terminal display mode
                       ( :graphic nil
                         :homogeneous-expected
                         ,(concat "[wait] Update state initialization\n"
                                  "[wait] Update session initialization")
                         :mixed-expected
                         ,(concat "[wait] First task\n"
                                  "[busy] Second task\n"
                                  "[done] Third task"))))
    (cl-letf (((symbol-function 'display-graphic-p)
               (lambda (&optional _display) (plist-get test-case :graphic))))
      ;; Test homogeneous statuses
      (should (equal (substring-no-properties
                      (acp--format-plan [((content . "Update state initialization")
                                                  (status . "pending"))
                                                 ((content . "Update session initialization")
                                                  (status . "pending"))]))
                     (plist-get test-case :homogeneous-expected)))

      ;; Test mixed statuses
      (should (equal (substring-no-properties
                      (acp--format-plan [((content . "First task")
                                                  (status . "pending"))
                                                 ((content . "Second task")
                                                  (status . "in_progress"))
                                                 ((content . "Third task")
                                                  (status . "completed"))]))
                     (plist-get test-case :mixed-expected)))))

  ;; Test empty entries
  (should (equal (acp--format-plan []) "")))

(ert-deftest acp--make-button-test ()
  "Test `acp--make-button' brackets in terminal mode."
  ;; Graphical mode: spaces with box styling
  (cl-letf (((symbol-function 'display-graphic-p)
             (lambda (&optional _display) t)))
    (should (equal (substring-no-properties
                    (acp--make-button
                     :text "Allow (y)"
                     :help "help"
                     :kind 'permission
                     :action #'ignore))
                   " Allow (y) ")))

  ;; Terminal mode: brackets
  (cl-letf (((symbol-function 'display-graphic-p)
             (lambda (&optional _display) nil)))
    (should (equal (substring-no-properties
                    (acp--make-button
                     :text "Allow (y)"
                     :help "help"
                     :kind 'permission
                     :action #'ignore))
                   "[ Allow (y) ]"))))

(ert-deftest acp--parse-file-mentions-test ()
  "Test acp--parse-file-mentions function."
  ;; Simple @ mention
  (let ((mentions (acp--parse-file-mentions "@file.txt")))
    (should (= (length mentions) 1))
    (should (equal (map-elt (car mentions) :path) "file.txt")))

  ;; @ mention with quotes
  (let ((mentions (acp--parse-file-mentions "Compare @\"file with spaces.txt\" to @other.txt")))
    (should (= (length mentions) 2))
    (should (equal (map-elt (car mentions) :path) "file with spaces.txt"))
    (should (equal (map-elt (cadr mentions) :path) "other.txt")))

  ;; @ mention at start of line
  (let ((mentions (acp--parse-file-mentions "@README.md is the main file")))
    (should (= (length mentions) 1))
    (should (equal (map-elt (car mentions) :path) "README.md")))

  ;; Multiple @ mentions
  (let ((mentions (acp--parse-file-mentions "Compare @file1.txt with @file2.txt")))
    (should (= (length mentions) 2))
    (should (equal (map-elt (car mentions) :path) "file1.txt"))
    (should (equal (map-elt (cadr mentions) :path) "file2.txt")))

  ;; No @ mentions
  (let ((mentions (acp--parse-file-mentions "No mentions here")))
    (should (= (length mentions) 0))))

(ert-deftest acp--build-content-blocks-test ()
  "Test acp--build-content-blocks function."
  (let* ((temp-file (make-temp-file "acp-test" nil ".txt"))
         (file-content "Test file content")
         (default-directory (file-name-directory temp-file))
         (file-name (file-name-nondirectory temp-file))
         (file-path (expand-file-name temp-file))
         (file-uri (concat "file://" file-path)))

    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert file-content))

          ;; Mock acp-cwd
          (cl-letf (((symbol-function 'acp-cwd)
                     (lambda () default-directory)))

            ;; Test with embedded context support and small file
            (let ((acp--state (list
                                       (cons :prompt-capabilities '((:embedded-context . t))))))
              (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                (should (equal blocks
                               `(((type . "text")
                                  (text . "Analyze"))
                                 ((type . "resource")
                                  (resource . ((uri . ,file-uri)
                                               (text . ,file-content)
                                               (mimeType . "text/plain")))))))))

            ;; Test without embedded context support
            (let ((acp--state (list
                                       (cons :prompt-capabilities nil))))
              (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                (should (equal blocks
                               `(((type . "text")
                                  (text . "Analyze"))
                                 ((type . "resource_link")
                                  (uri . ,file-uri)
                                  (name . ,file-name)
                                  (mimeType . "text/plain")
                                  (size . ,(file-attribute-size (file-attributes temp-file)))))))))

            ;; Test fallback by setting a very small file size limit
            (let ((acp--state (list
                                       (cons :prompt-capabilities '((:embedded-context . t)))))
                  (acp-embed-file-size-limit 5))
              (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                (should (equal blocks
                               `(((type . "text")
                                  (text . "Analyze"))
                                 ((type . "resource_link")
                                  (uri . ,file-uri)
                                  (name . ,file-name)
                                  (mimeType . "text/plain")
                                  (size . ,(file-attribute-size (file-attributes temp-file)))))))))

            ;; Test with no mentions
            (let ((acp--state (list
                                       (cons :prompt-capabilities '((:embedded-context . t))))))
              (let ((blocks (acp--build-content-blocks "No mentions here")))
                (should (equal blocks
                               '(((type . "text")
                                  (text . "No mentions here")))))))))

      (delete-file temp-file))))

(ert-deftest acp--build-content-blocks-binary-file-test ()
  "Test acp--build-content-blocks with binary PNG files."
  (let* ((temp-file (make-temp-file "acp-test" nil ".png"))
         ;; Minimal valid 1x1 PNG file (69 bytes)
         (png-data (unibyte-string
                    #x89 #x50 #x4E #x47 #x0D #x0A #x1A #x0A ; PNG signature
                    #x00 #x00 #x00 #x0D #x49 #x48 #x44 #x52 ; IHDR chunk
                    #x00 #x00 #x00 #x01 #x00 #x00 #x00 #x01
                    #x08 #x02 #x00 #x00 #x00 #x90 #x77 #x53
                    #xDE #x00 #x00 #x00 #x0C #x49 #x44 #x41 ; IDAT chunk
                    #x54 #x08 #xD7 #x63 #xF8 #xCF #xC0 #x00
                    #x00 #x03 #x01 #x01 #x00 #x18 #xDD #x8D
                    #xB4 #x00 #x00 #x00 #x00 #x49 #x45 #x4E ; IEND chunk
                    #x44 #xAE #x42 #x60 #x82))
         (default-directory (file-name-directory temp-file))
         (file-name (file-name-nondirectory temp-file))
         (file-path (expand-file-name temp-file))
         (file-uri (concat "file://" file-path)))

    (unwind-protect
        (progn
          ;; Write binary PNG data
          (with-temp-file temp-file
            (set-buffer-multibyte nil)
            (insert png-data))

          ;; Mock acp-cwd
          (cl-letf (((symbol-function 'acp-cwd)
                     (lambda () default-directory)))

            (if (display-images-p)
                ;; Graphical Emacs: image-supported-file-p recognises PNG,
                ;; so the image code-path is reachable.
                (progn
                  ;; Test with image and embedded context support - should use ContentBlock::Image
                  (let ((acp--state (list
                                             (cons :prompt-capabilities '((:image . t) (:embedded-context . t))))))
                    (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                      ;; Should have text block and image block
                      (should (= (length blocks) 2))

                      ;; Check text block
                      (should (equal (map-elt (nth 0 blocks) 'type) "text"))
                      (should (equal (map-elt (nth 0 blocks) 'text) "Analyze"))

                      ;; Check image block
                      (let ((image-block (nth 1 blocks)))
                        (should (equal (map-elt image-block 'type) "image"))

                        ;; Check URI
                        (should (equal (map-elt image-block 'uri) file-uri))

                        ;; Check MIME type is image/png
                        (should (equal (map-elt image-block 'mimeType) "image/png"))

                        ;; Check content is base64-encoded (not raw binary)
                        (let ((content (map-elt image-block 'data)))
                          ;; Should be a string
                          (should (stringp content))
                          ;; Should not contain raw PNG signature
                          (should-not (string-match-p "\x89PNG" content))
                          ;; Should be base64 (alphanumeric + / + = padding)
                          (should (string-match-p "^[A-Za-z0-9+/\n]+=*$" content))
                          ;; Should be longer than original (base64 overhead)
                          (should (< 69 (length content)))))))

                  ;; Test without image capability - should use resource_link with correct mime type
                  (let ((acp--state (list
                                             (cons :prompt-capabilities nil))))
                    (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                      (should (= (length blocks) 2))

                      (let ((resource-link (nth 1 blocks)))
                        (should (equal (map-elt resource-link 'type) "resource_link"))
                        (should (equal (map-elt resource-link 'uri) file-uri))
                        ;; Should have image/png mime type
                        (should (equal (map-elt resource-link 'mimeType) "image/png"))
                        (should (equal (map-elt resource-link 'name) file-name))
                        (should (equal (map-elt resource-link 'size) 69))))))

              ;; Non-graphical Emacs: image-supported-file-p is unavailable,
              ;; so the PNG is treated as text/plain by the MIME resolver.
              ;; Verify the resource_link fallback still works.
              (let ((acp--state (list
                                         (cons :prompt-capabilities '((:image . t) (:embedded-context . t))))))
                (let ((blocks (acp--build-content-blocks (format "Analyze @%s" file-name))))
                  (should (= (length blocks) 2))

                  ;; Text block is still present
                  (should (equal (map-elt (nth 0 blocks) 'type) "text"))
                  (should (equal (map-elt (nth 0 blocks) 'text) "Analyze"))

                  ;; Without image MIME detection the file is embedded as a
                  ;; resource (text/plain), not as an image block.
                  (let ((block (nth 1 blocks)))
                    (should (member (map-elt block 'type) '("resource" "resource_link")))))))))

      (delete-file temp-file))))

(ert-deftest acp--collect-attached-files-test ()
  "Test acp--collect-attached-files function."
  ;; Test with empty list
  (should (equal (acp--collect-attached-files '()) '()))

  ;; Test with resource block
  (let ((blocks '(((type . "resource")
                   (resource . ((uri . "file:///path/to/file.txt")
                                (text . "content"))))
                  ((type . "text")
                   (text . "some text")))))
    (let ((uris (acp--collect-attached-files blocks)))
      (should (= (length uris) 1))
      (should (equal (car uris) "file:///path/to/file.txt"))))

  ;; Test with resource_link block
  (let ((blocks '(((type . "resource_link")
                   (uri . "file:///path/to/file.txt")
                   (name . "file.txt"))
                  ((type . "text")
                   (text . "some text")))))
    (let ((uris (acp--collect-attached-files blocks)))
      (should (= (length uris) 1))
      (should (equal (car uris) "file:///path/to/file.txt"))))

  ;; Test with multiple files
  (let ((blocks '(((type . "resource_link")
                   (uri . "file:///path/to/file1.txt"))
                  ((type . "text")
                   (text . " "))
                  ((type . "resource_link")
                   (uri . "file:///path/to/file2.txt")))))
    (let ((uris (acp--collect-attached-files blocks)))
      (should (= (length uris) 2)))))

(ert-deftest acp--send-command-integration-test ()
  "Integration test: verify acp--send-command calls ACP correctly."
  (let ((sent-request nil)
        (acp--state (list
                             (cons :client 'test-client)
                             (cons :session (list (cons :id "test-session")))
                             (cons :prompt-capabilities '((:embedded-context . t)))
                             (cons :buffer (current-buffer))
                             (cons :last-entry-type nil)
                             (cons :active-requests nil))))

    ;; Mock acp-send-request to capture what gets sent;
    ;; stub viewport--buffer to avoid interactive shell-buffer prompt in batch.
    (cl-letf (((symbol-function 'acp-send-request)
               (lambda (&rest args)
                 (setq sent-request args)))
              ((symbol-function 'acp-viewport--buffer)
               (lambda (&rest _) nil)))

      ;; Send a simple command
      (acp--send-command
       :prompt "Hello agent"
       :shell-buffer nil)

      ;; Verify request was sent
      (should sent-request)

      ;; Verify basic request structure
      (let* ((request (plist-get sent-request :request))
             (params (map-elt request :params))
             (prompt (map-elt params 'prompt)))
        (should prompt)
        (should (equal prompt '[((type . "text") (text . "Hello agent"))]))))))

(ert-deftest acp--send-command-error-fallback-test ()
  "Test acp--send-command falls back to plain text on build-content-blocks error."
  (let ((sent-request nil)
        (acp--state (list
                             (cons :client 'test-client)
                             (cons :session (list (cons :id "test-session")))
                             (cons :prompt-capabilities '((:embedded-context . t)))
                             (cons :buffer (current-buffer))
                             (cons :last-entry-type nil)
                             (cons :active-requests nil))))

    ;; Mock build-content-blocks to throw an error;
    ;; stub viewport--buffer to avoid interactive shell-buffer prompt in batch.
    (cl-letf (((symbol-function 'acp--build-content-blocks)
               (lambda (_prompt)
                 (error "Simulated error in build-content-blocks")))
              ((symbol-function 'acp-send-request)
               (lambda (&rest args)
                 (setq sent-request args)))
              ((symbol-function 'acp-viewport--buffer)
               (lambda (&rest _) nil)))

      ;; First, verify that build-content-blocks actually throws an error
      (should-error (acp--build-content-blocks "Test prompt")
                    :type 'error)

      ;; Now verify send-command handles the error gracefully
      (acp--send-command
       :prompt "Test prompt with @file.txt"
       :shell-buffer nil)

      ;; Verify request was sent (fallback succeeded)
      (should sent-request)

      ;; Verify it fell back to plain text
      (let* ((request (plist-get sent-request :request))
             (params (map-elt request :params))
             (prompt (map-elt params 'prompt)))
        ;; Should still have a prompt
        (should prompt)
        ;; Should be a single text block with the original prompt
        (should (equal prompt '[((type . "text") (text . "Test prompt with @file.txt"))]))))))

(ert-deftest acp--send-command-emits-turn-complete-event-test ()
  "Test `acp--send-command' emits turn-complete on success."
  (let ((received-events nil)
        (captured-on-success nil)
        (acp--state (list (cons :buffer (current-buffer))
                                  (cons :event-subscriptions nil)
                                  (cons :client 'test-client)
                                  (cons :session (list (cons :id "test-session")))
                                  (cons :last-entry-type nil)
                                  (cons :tool-calls nil)
                                  (cons :usage (list (cons :total-tokens 0)))))
        (acp-show-busy-indicator nil)
        (acp-show-usage-at-turn-end nil))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'acp--send-request)
               (lambda (&rest args)
                 (setq captured-on-success (plist-get args :on-success))))
              ((symbol-function 'shell-maker-finish-output)
               (lambda (&rest _)))
              ((symbol-function 'acp--process-pending-request)
               (lambda (&rest _))))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :event 'turn-complete
       :on-event (lambda (event)
                   (push event received-events)))
      (acp--send-command
       :prompt "Hello"
       :shell-buffer (current-buffer))
      ;; Simulate the ACP response arriving
      (should captured-on-success)
      (funcall captured-on-success
               `((stopReason . "end_turn")
                 (usage . ((totalTokens . 1500)))))
      (should (= (length received-events) 1))
      (let ((data (map-elt (car received-events) :data)))
        (should (equal (map-elt data :stop-reason) "end_turn"))
        (should (equal (map-elt (map-elt data :usage) :total-tokens)
                       1500))))))

(ert-deftest acp--format-diff-as-text-test ()
  "Test `acp--format-diff-as-text' function."
  ;; Test nil input
  (should (equal (acp--format-diff-as-text nil) nil))

  ;; Test basic diff formatting
  (let* ((old-text "line 1\nline 2\nline 3\n")
         (new-text "line 1\nline 2 modified\nline 3\n")
         (diff-info `((:old . ,old-text)
                      (:new . ,new-text)
                      (:file . "test.txt")))
         (result (acp--format-diff-as-text diff-info)))

    ;; Should return a string
    (should (stringp result))

    ;; Should NOT contain file header lines with timestamps (they should be stripped)
    (should-not (string-match-p "^---" result))
    (should-not (string-match-p "^\\+\\+\\+" result))

    ;; Should contain unified diff hunk headers
    (should (string-match-p "^@@" result))

    ;; Should contain the actual changes
    (should (string-match-p "^-line 2" result))
    (should (string-match-p "^\\+line 2 modified" result))

    ;; Should have syntax highlighting (text properties)
    (let ((has-diff-face nil))
      (dotimes (i (length result))
        (when (get-text-property i 'font-lock-face result)
          (setq has-diff-face t)))
      (should has-diff-face))))

(ert-deftest acp--format-agent-capabilities-test ()
  "Test `acp--format-agent-capabilities' function."
  ;; Test with multiple capabilities (includes comma)
  (let ((capabilities '((promptCapabilities (image . t) (audio . :false) (embeddedContext . t))
                        (mcpCapabilities (http . t) (sse . t)))))
    (should (equal (substring-no-properties
                    (acp--format-agent-capabilities capabilities))
                   (concat
                    "prompt  image and embedded context\n"
                    "mcp     http and sse"))))

  ;; Test with single capability per category (no comma)
  (let ((capabilities '((promptCapabilities (image . t))
                        (mcpCapabilities (http . t)))))
    (should (equal (substring-no-properties
                    (acp--format-agent-capabilities capabilities))
                   (concat "prompt  image\n"
                           "mcp     http"))))

  ;; Test with top-level boolean capability (loadSession)
  (let ((capabilities '((loadSession . t)
                        (promptCapabilities (image . t) (embeddedContext . t)))))
    (should (equal (substring-no-properties
                    (acp--format-agent-capabilities capabilities))
                   (concat "load session\n"
                           "prompt        image and embedded context"))))

  ;; Test with sessionCapabilities (bare keys without boolean values)
  (let ((capabilities '((promptCapabilities (image . t) (embeddedContext . t))
                        (mcpCapabilities (http . t) (sse . t))
                        (sessionCapabilities (fork) (list) (resume)))))
    (should (equal (substring-no-properties
                    (acp--format-agent-capabilities capabilities))
                   (concat "prompt   image and embedded context\n"
                           "mcp      http and sse\n"
                           "session  fork, list and resume"))))

  ;; Test with all capabilities disabled (should return empty string)
  (let ((capabilities '((promptCapabilities (image . :false) (audio . :false)))))
    (should (equal (acp--format-agent-capabilities capabilities) ""))))

(ert-deftest acp--make-transcript-tool-call-entry-test ()
  "Test `acp--make-transcript-tool-call-entry' function."
  ;; Mock format-time-string to return a predictable value
  (cl-letf (((symbol-function 'format-time-string)
             (lambda (format &optional _time _zone)
               (cond
                ((string= format "%F %T") "2025-11-02 18:17:41")
                (t (error "Unexpected format-time-string format: %s" format))))))

    ;; Test with all parameters provided
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "grep \"transcript\""
                  :kind "search"
                  :description "Search for transcript references"
                  :command "grep \"transcript\""
                  :output "Found 6 files\n/path/to/file1.md\n/path/to/file2.md")))
      (should (equal entry "\n\n### Tool Call [completed]: grep \"transcript\"

**Tool:** search
**Timestamp:** 2025-11-02 18:17:41
**Description:** Search for transcript references
**Command:** grep \"transcript\"

```
Found 6 files
/path/to/file1.md
/path/to/file2.md
```
")))

    ;; Test with minimal parameters
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "test command"
                  :output "simple output")))
      (should (equal entry "\n\n### Tool Call [completed]: test command

**Timestamp:** 2025-11-02 18:17:41

```
simple output
```
")))

    ;; Test with nil status and title
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status nil
                  :title nil
                  :output "output")))
      (should (equal entry "

### Tool Call [no status]: \n
**Timestamp:** 2025-11-02 18:17:41

```
output
```
")))

    ;; Test that output whitespace is trimmed
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "test"
                  :output "  \n  output with spaces  \n  ")))
      (should (equal entry "\n\n### Tool Call [completed]: test

**Timestamp:** 2025-11-02 18:17:41

```
output with spaces
```
")))

    ;; Test that code blocks in output are stripped and output containing backtick fences gets a longer outer fence
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "test"
                  :output "```\ncode block content\n```")))
      (should (equal entry "

### Tool Call [completed]: test

**Timestamp:** 2025-11-02 18:17:41

````
```
code block content
```
````
")))

    ;; Test that output containing backtick fences with whitespace is trimmed and output containing backtick fences gets a longer outer fence
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "test"
                  :output "  \n  ```\ncode block content with spaces\n```\n")))
      (should (equal entry "

### Tool Call [completed]: test

**Timestamp:** 2025-11-02 18:17:41

````
```
code block content with spaces
```
````
")))

    ;; Test output with 4-backtick fences gets 5-backtick outer fence
    (let ((entry (acp--make-transcript-tool-call-entry
                  :status "completed"
                  :title "test"
                  :output "````\ncode block content\n````")))
      (should (equal entry "\n\n### Tool Call [completed]: test

**Timestamp:** 2025-11-02 18:17:41

`````
````
code block content
````
`````
")))))

(ert-deftest acp--longest-backtick-run-test ()
  "Test `acp--longest-backtick-run'."
  (should (= (acp--longest-backtick-run "") 0))
  (should (= (acp--longest-backtick-run "no backticks here") 0))
  (should (= (acp--longest-backtick-run "has `one` inline") 1))
  (should (= (acp--longest-backtick-run "has ``` three") 3))
  (should (= (acp--longest-backtick-run "```elisp\n(foo)\n```") 3))
  (should (= (acp--longest-backtick-run "has ```` four and ``` three") 4))
  (should (= (acp--longest-backtick-run "``````") 6)))

(ert-deftest acp--indent-markdown-headers-test ()
  "Test `acp--indent-markdown-headers'."
  ;; Text without headers is unchanged.
  (should (equal (acp--indent-markdown-headers "no headers here")
                 "no headers here"))
  ;; Simple H1 becomes H3.
  (should (equal (acp--indent-markdown-headers "# Foo")
                 "### Foo"))
  ;; H2 becomes H4.
  (should (equal (acp--indent-markdown-headers "## Bar")
                 "#### Bar"))
  ;; H4 becomes H6.
  (should (equal (acp--indent-markdown-headers "#### Deep")
                 "###### Deep"))
  ;; H5 is capped at H6.
  (should (equal (acp--indent-markdown-headers "##### Five")
                 "###### Five"))
  ;; H6 stays at H6.
  (should (equal (acp--indent-markdown-headers "###### Six")
                 "###### Six"))
  ;; Mixed content with multiple headers.
  (should (equal (acp--indent-markdown-headers
                  "some text\n# Heading 1\nmore text\n## Heading 2\nend")
                 "some text\n### Heading 1\nmore text\n#### Heading 2\nend"))
  ;; Headers inside code blocks are left unchanged.
  (should (equal (acp--indent-markdown-headers
                  "before\n```\n# code comment\n## also code\n```\nafter")
                 "before\n```\n# code comment\n## also code\n```\nafter"))
  ;; Headers outside code blocks are indented, inside are not.
  (should (equal (acp--indent-markdown-headers
                  "# Top\n```\n# Inside\n```\n# Bottom")
                 "### Top\n```\n# Inside\n```\n### Bottom"))
  ;; Code blocks with 4+ backticks.
  (should (equal (acp--indent-markdown-headers
                  "````\n# Inside\n````\n# Outside")
                 "````\n# Inside\n````\n### Outside"))
  ;; Nested code blocks (inner fence shorter than outer).
  (should (equal (acp--indent-markdown-headers
                  "````\n```\n# Inside\n```\n````\n# Outside")
                 "````\n```\n# Inside\n```\n````\n### Outside"))
  ;; Nil input returns empty string.
  (should (equal (acp--indent-markdown-headers nil) ""))
  ;; Empty string.
  (should (equal (acp--indent-markdown-headers "") ""))
  ;; Hash without space is not a header.
  (should (equal (acp--indent-markdown-headers "#not-a-header")
                 "#not-a-header"))
  ;; Simulated LLM output with mixed headers and code blocks.
  ;; This is the primary transcript use case: an agent response containing
  ;; its own markdown structure that must be indented to stay below the
  ;; transcript's ## section headers.
  (should (equal (acp--indent-markdown-headers
                  (concat "Here's my analysis:\n"
                          "# Summary\n"
                          "Some text\n"
                          "## Details\n"
                          "More text\n"
                          "```elisp\n"
                          "# this is a comment in code\n"
                          "(defun foo () nil)\n"
                          "```\n"
                          "### Conclusion\n"
                          "Final thoughts"))
                 (concat "Here's my analysis:\n"
                          "### Summary\n"
                          "Some text\n"
                          "#### Details\n"
                          "More text\n"
                          "```elisp\n"
                          "# this is a comment in code\n"
                          "(defun foo () nil)\n"
                          "```\n"
                          "##### Conclusion\n"
                          "Final thoughts")))
  ;; Tool call entries (### Tool Call) are NOT passed through this function
  ;; because they are code-generated, not LLM output.  Verify that if
  ;; they hypothetically were, they would be indented -- this confirms the
  ;; function is agnostic and the correct behavior comes from applying it
  ;; only to LLM text.
  (should (equal (acp--indent-markdown-headers "### Tool Call [completed]: grep")
                 "##### Tool Call [completed]: grep")))

(ert-deftest acp-mcp-servers-test ()
  "Test `acp-mcp-servers' function normalization."
  ;; Test with nil
  (let ((acp-mcp-servers nil))
    (should (equal (acp--mcp-servers) nil)))

  ;; Test with empty list
  (let ((acp-mcp-servers '()))
    (should (equal (acp--mcp-servers) nil)))

  ;; Test stdio transport with lists that need normalization
  (let ((acp-mcp-servers
         '(((name . "filesystem")
            (command . "npx")
            (args . ("-y" "@modelcontextprotocol/server-filesystem" "/tmp"))
            (env . (((name . "DEBUG") (value . "true"))
                    ((name . "LOG_LEVEL") (value . "info"))))))))
    (should (equal (acp--mcp-servers)
                   [((name . "filesystem")
                     (command . "npx")
                     (args . ["-y" "@modelcontextprotocol/server-filesystem" "/tmp"])
                     (env . [((name . "DEBUG") (value . "true"))
                             ((name . "LOG_LEVEL") (value . "info"))]))])))

  ;; Test HTTP transport with lists that need normalization
  (let ((acp-mcp-servers
         '(((name . "notion")
            (type . "http")
            (url . "https://mcp.notion.com/mcp")
            (headers . (((name . "Authorization") (value . "Bearer token"))
                        ((name . "Content-Type") (value . "application/json"))))))))
    (should (equal (acp--mcp-servers)
                   [((name . "notion")
                     (type . "http")
                     (url . "https://mcp.notion.com/mcp")
                     (headers . [((name . "Authorization") (value . "Bearer token"))
                                 ((name . "Content-Type") (value . "application/json"))]))])))

  ;; Test empty list fields normalize to empty vectors
  (let ((acp-mcp-servers
         '(((name . "empty")
            (command . "npx")
            (args . ())
            (env . ())
            (headers . ())))))
    (should (equal (acp--mcp-servers)
                   [((name . "empty")
                     (command . "npx")
                     (args . [])
                     (env . [])
                     (headers . []))])))

  ;; Test with already-vectorized fields (should remain unchanged)
  (let ((acp-mcp-servers
         '(((name . "filesystem")
            (command . "npx")
            (args . ["-y" "@modelcontextprotocol/server-filesystem" "/tmp"])
            (env . [])))))
    (should (equal (acp--mcp-servers)
                   [((name . "filesystem")
                     (command . "npx")
                     (args . ["-y" "@modelcontextprotocol/server-filesystem" "/tmp"])
                     (env . []))])))

  ;; Test multiple servers
  (let ((acp-mcp-servers
         '(((name . "notion")
            (type . "http")
            (url . "https://mcp.notion.com/mcp")
            (headers . ()))
           ((name . "filesystem")
            (command . "npx")
            (args . ("-y" "@modelcontextprotocol/server-filesystem" "/tmp"))
            (env . ())))))
    (should (equal (acp--mcp-servers)
                   [((name . "notion")
                     (type . "http")
                     (url . "https://mcp.notion.com/mcp")
                     (headers . []))
                    ((name . "filesystem")
                     (command . "npx")
                     (args . ["-y" "@modelcontextprotocol/server-filesystem" "/tmp"])
                     (env . []))])))

  ;; Test server without optional fields
  (let ((acp-mcp-servers
         '(((name . "simple")
            (command . "simple-server")))))
    (should (equal (acp--mcp-servers)
                   [((name . "simple")
                     (command . "simple-server"))]))))

(ert-deftest acp--completion-bounds-test ()
  "Test `acp--completion-bounds' function."
  (let ((path-chars "[:alnum:]/_.-"))

    ;; Test finding bounds after @ trigger
    (with-temp-buffer
      (insert "@file.txt")
      (goto-char (point-min))
      (forward-char 1)
      (let ((bounds (acp--completion-bounds path-chars ?@)))
        (should bounds)
        (should (equal (map-elt bounds :start) 2))  ; start after @
        (should (equal (map-elt bounds :end) 10)))) ; end of file.txt

    ;; Test with cursor in middle of word
    (with-temp-buffer
      (insert "@some/path/file.el")
      (goto-char 8)
      (let ((bounds (acp--completion-bounds path-chars ?@)))
        (should bounds)
        (should (equal (map-elt bounds :start) 2))
        (should (equal (map-elt bounds :end) 19))))

    ;; Test returns nil when trigger character is missing
    (with-temp-buffer
      (insert "file.txt")
      (goto-char (point-min))
      (let ((bounds (acp--completion-bounds path-chars ?@)))
        (should-not bounds)))

    ;; Test with empty word after trigger
    (with-temp-buffer
      (insert "@ ")
      (goto-char 2) ; Right after @
      (let ((bounds (acp--completion-bounds path-chars ?@)))
        (should bounds)
        (should (equal (map-elt bounds :start) 2))
        (should (equal (map-elt bounds :end) 2)))) ; Empty range

    ;; Test with text before trigger
    (with-temp-buffer
      (insert "Look at @README.md please")
      (goto-char 12) ; In middle of README
      (let ((bounds (acp--completion-bounds path-chars ?@)))
        (should bounds)
        (should (equal (map-elt bounds :start) 10))
        (should (equal (map-elt bounds :end) 19))))))

(ert-deftest acp--capf-exit-with-space-test ()
  "Test `acp--capf-exit-with-space' function."
  (with-temp-buffer
    (insert "test")
    (acp--capf-exit-with-space "ignored" 'finished)
    (should (equal (buffer-string) "test "))
    (should (equal (point) 6))))

(ert-deftest acp-subscribe-to-test ()
  "Test `acp-subscribe-to' and event dispatching."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :on-event (lambda (event)
                   (push event received-events)))

      (acp--emit-event :event 'init-client)
      (acp--emit-event :event 'init-session)
      (acp--emit-event :event 'init-model)

      (should (= (length received-events) 3))

      ;; Events are pushed, so most recent is first
      (should (equal (map-elt (nth 2 received-events) :event) 'init-client))
      (should (equal (map-elt (nth 1 received-events) :event) 'init-session))
      (should (equal (map-elt (nth 0 received-events) :event) 'init-model)))))

(ert-deftest acp-subscribe-to-filtered-test ()
  "Test `acp-subscribe-to' with :event filter."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :event 'init-session
       :on-event (lambda (event)
                   (push event received-events)))

      (acp--emit-event :event 'init-client)
      (acp--emit-event :event 'init-session)
      (acp--emit-event :event 'init-client)
      (acp--emit-event :event 'init-session)

      ;; Only init-session events should be received
      (should (= (length received-events) 2))
      (should (equal (map-elt (nth 0 received-events) :event) 'init-session))
      (should (equal (map-elt (nth 1 received-events) :event) 'init-session)))))

(ert-deftest acp-unsubscribe-test ()
  "Test `acp-unsubscribe' removes subscription."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((token (acp-subscribe-to
                    :shell-buffer (current-buffer)
                    :on-event (lambda (event)
                                (push event received-events)))))

        (acp--emit-event :event 'init-client)
        (should (= (length received-events) 1))

        (acp-unsubscribe :subscription token)

        (acp--emit-event :event 'init-session)
        ;; Should still be 1 — no new events after unsubscribe
        (should (= (length received-events) 1))))))

(ert-deftest acp--emit-event-with-data-test ()
  "Test `acp--emit-event' passes :data to subscribers."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :on-event (lambda (event)
                   (push event received-events)))

      (acp--emit-event
       :event 'file-write
       :data (list (cons :path "/tmp/test.txt")
                   (cons :content "hello")))

      (should (= (length received-events) 1))
      (let ((event (car received-events)))
        (should (equal (map-elt event :event) 'file-write))
        (should (equal (map-elt (map-elt event :data) :path) "/tmp/test.txt"))
        (should (equal (map-elt (map-elt event :data) :content) "hello"))))))

(ert-deftest acp--emit-event-data-omitted-when-nil-test ()
  "Test `acp--emit-event' omits :data when nil."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :on-event (lambda (event)
                   (push event received-events)))

      (acp--emit-event :event 'init-client)

      (should (= (length received-events) 1))
      (let ((event (car received-events)))
        (should (equal (map-elt event :event) 'init-client))
        (should-not (assoc :data event))))))

(ert-deftest acp--emit-event-no-subscribers-test ()
  "Test `acp--emit-event' works with no subscribers."
  (let ((acp--state (list (cons :buffer (current-buffer))
                                  (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      ;; Should not error when no subscriptions exist
      (acp--emit-event :event 'init-client))))

(ert-deftest acp-subscribe-to-prompt-ready-test ()
  "Test subscribing to `prompt-ready' event."
  (let* ((received-events nil)
         (acp--state (list (cons :buffer (current-buffer))
                                   (cons :event-subscriptions nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :event 'prompt-ready
       :on-event (lambda (event)
                   (push event received-events)))

      ;; Other events should not be received.
      (acp--emit-event :event 'init-session)
      (acp--emit-event :event 'init-finished)
      (should (= (length received-events) 0))

      ;; prompt-ready should be received.
      (acp--emit-event :event 'prompt-ready)
      (should (= (length received-events) 1))
      (should (equal (map-elt (nth 0 received-events) :event) 'prompt-ready)))))

(ert-deftest acp-dwim-carries-context-to-first-viewport-open-test ()
  "Test `acp--dwim' carries context into deferred viewport open."
  (let ((acp-prefer-viewport-interaction t))
    (with-temp-buffer
      (let ((source-buffer (current-buffer))
            (show-buffer-args nil)
            (shell-buffer (generate-new-buffer " *acp shell*")))
        (unwind-protect
            (progn
              (with-current-buffer shell-buffer
                (setq-local acp-session-strategy 'prompt)
                (setq-local acp--state
                            `((:buffer . ,shell-buffer)
                              (:session . ((:id . nil)))
                              (:event-subscriptions . nil))))
              (cl-letf (((symbol-function 'derived-mode-p)
                         (lambda (&rest modes)
                           (and (eq (current-buffer) shell-buffer)
                                (memq 'acp-mode modes))))
                        ((symbol-function 'acp--shell-buffer)
                         (lambda (&rest _) shell-buffer))
                        ((symbol-function 'acp--context)
                         (lambda (&key shell-buffer)
                           (ignore shell-buffer)
                           (when (eq (current-buffer) source-buffer)
                             "context from source")))
                        ((symbol-function 'acp-viewport--show-buffer)
                         (lambda (&rest args)
                           (setq show-buffer-args args))))
                (with-current-buffer source-buffer
                  (acp--dwim))
                (should-not show-buffer-args)
                (with-current-buffer shell-buffer
                  (acp--emit-event :event 'session-selected))
                (should (equal (plist-get show-buffer-args :shell-buffer) shell-buffer))
                (should (equal (plist-get show-buffer-args :append)
                               "context from source"))))
          (kill-buffer shell-buffer))))))

(ert-deftest acp--on-request-emits-permission-request-event-test ()
  "Test `acp--on-request' emits permission-request event."
  (let ((received-events nil)
        (acp--state (list (cons :buffer (current-buffer))
                                  (cons :event-subscriptions nil)
                                  (cons :tool-calls nil)
                                  (cons :last-entry-type nil))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'acp--update-fragment)
               (lambda (&rest _))))
      (acp-subscribe-to
       :shell-buffer (current-buffer)
       :event 'permission-request
       :on-event (lambda (event)
                   (push event received-events)))
      (acp--on-request
       :state acp--state
       :acp-request `((id . "req-123")
                      (method . "session/request_permission")
                      (params . ((toolCall . ((toolCallId . "tc-456")
                                              (title . "Run command")
                                              (status . "pending")
                                              (kind . "bash")))))))
      (should (= (length received-events) 1))
      (let ((data (map-elt (car received-events) :data)))
        (should (equal (map-elt data :request-id) "req-123"))
        (should (equal (map-elt data :tool-call-id) "tc-456"))
        (should (equal (map-elt (map-elt data :tool-call) :title)
                       "Run command"))))))

(ert-deftest acp-mode-hook-subscriptions-survive-state-init ()
  "Subscriptions registered via `acp-mode-hook' should persist."
  (let ((test-buffer nil)
        (hook-fn (lambda ()
                   (acp-subscribe-to
                    :shell-buffer (current-buffer)
                    :event 'turn-complete
                    :on-event #'ignore)))
        (fake-process (start-process "fake-agent" nil "cat"))
        (config (list (cons :buffer-name "test-agent")
                      (cons :client-maker
                            (lambda (_buf)
                              (list (cons :command "cat")))))))
    (unwind-protect
        (progn
          (add-hook 'acp-mode-hook hook-fn)
          (cl-letf (((symbol-function 'shell-maker-start)
                     (lambda (_config &rest _args)
                       (setq test-buffer (get-buffer-create "*test-acp*"))
                       (with-current-buffer test-buffer
                         (setq major-mode 'acp-mode)
                         (run-hooks 'acp-mode-hook))
                       test-buffer))
                    ((symbol-function 'shell-maker--process) (lambda () fake-process))
                    ((symbol-function 'shell-maker-finish-output) #'ignore)
                    (acp-file-completion-enabled nil))
            (let* ((shell-buffer (acp--start :config config
                                                     :no-focus t
                                                     :new-session t))
                   (subs (map-elt (buffer-local-value 'acp--state shell-buffer)
                                  :event-subscriptions)))
              (should (= 1 (length subs)))
              (should (eq 'turn-complete (map-elt (car subs) :event))))))
      (remove-hook 'acp-mode-hook hook-fn)
      (when (process-live-p fake-process)
        (delete-process fake-process))
      (when (and test-buffer (buffer-live-p test-buffer))
        (kill-buffer test-buffer)))))

(ert-deftest acp--initiate-session-prefers-list-and-load-when-supported ()
  "Test `acp--initiate-session' prefers session/list + session/load."
  (with-temp-buffer
    (let* ((acp-session-strategy 'latest)
           (requests '())
           (session-init-called nil)
           (state `((:buffer . ,(current-buffer))
                    (:client . test-client)
                    (:session . ((:id . nil)
                                 (:mode-id . nil)
                                 (:modes . nil)))
                    (:supports-session-list . t)
                    (:supports-session-load . t)
                    (:active-requests)
                    (:event-subscriptions . nil))))
      (setq-local acp--state state)
      (cl-letf (((symbol-function 'acp--state)
                 (lambda () acp--state))
                ((symbol-function 'acp--update-fragment)
                 (lambda (&rest _args) nil))
                ((symbol-function 'acp--update-header-and-mode-line)
                 (lambda () nil))
                ((symbol-function 'acp-cwd)
                 (lambda () "/tmp"))
                ((symbol-function 'acp--resolve-path)
                 (lambda (path) path))
                ((symbol-function 'acp--mcp-servers)
                 (lambda () []))
                ((symbol-function 'acp-send-request)
                 (lambda (&rest args)
                   (push args requests)
                   (let* ((request (plist-get args :request))
                          (method (map-elt request :method)))
                     (pcase method
                       ("session/list"
                        (funcall (plist-get args :on-success)
                                 '((sessions . [((sessionId . "session-123")
                                                 (cwd . "/tmp")
                                                 (title . "Recent session"))]))))
                       ("session/load"
                        (funcall (plist-get args :on-success)
                                 '((modes (currentModeId . "default")
                                          (availableModes . [((id . "default")
                                                              (name . "Default")
                                                              (description . "Default mode"))]))
                                   (models (currentModelId . "gpt-5")
                                           (availableModels . [((modelId . "gpt-5")
                                                                (name . "GPT-5")
                                                                (description . "Test model"))])))))
                       (_ (error "Unexpected method: %s" method)))))))
        (acp--initiate-session
         :shell-buffer (current-buffer)
         :on-session-init (lambda ()
                            (setq session-init-called t)))
        (let ((ordered-requests (nreverse requests)))
          (should (equal (mapcar (lambda (req)
                                   (map-elt (plist-get req :request) :method))
                                 ordered-requests)
                         '("session/list" "session/load")))
          (let* ((load-request (plist-get (nth 1 ordered-requests) :request))
                 (load-params (map-elt load-request :params)))
            (should (equal (map-elt load-params 'sessionId) "session-123"))
            (should (equal (map-elt load-params 'cwd) "/tmp"))))
        (should session-init-called)
        (should (equal (map-nested-elt acp--state '(:session :id)) "session-123"))))))

(ert-deftest acp--initiate-session-falls-back-to-new-on-list-failure ()
  "Test `acp--initiate-session' falls back to session/new on list failure."
  (with-temp-buffer
    (let* ((acp-session-strategy 'latest)
           (requests '())
           (session-init-called nil)
           (state `((:buffer . ,(current-buffer))
                    (:client . test-client)
                    (:session . ((:id . nil)
                                 (:mode-id . nil)
                                 (:modes . nil)))
                    (:supports-session-list . t)
                    (:supports-session-load . t)
                    (:active-requests)
                    (:event-subscriptions . nil))))
      (setq-local acp--state state)
      (cl-letf (((symbol-function 'acp--state)
                 (lambda () acp--state))
                ((symbol-function 'acp--update-fragment)
                 (lambda (&rest _args) nil))
                ((symbol-function 'acp--update-header-and-mode-line)
                 (lambda () nil))
                ((symbol-function 'acp-cwd)
                 (lambda () "/tmp"))
                ((symbol-function 'acp--resolve-path)
                 (lambda (path) path))
                ((symbol-function 'acp--mcp-servers)
                 (lambda () []))
                ((symbol-function 'acp-send-request)
                 (lambda (&rest args)
                   (push args requests)
                   (let* ((request (plist-get args :request))
                          (method (map-elt request :method)))
                     (pcase method
                       ("session/list"
                        (funcall (plist-get args :on-failure)
                                 '((code . -32601)
                                   (message . "Method not found"))
                                 nil))
                       ("session/new"
                        (funcall (plist-get args :on-success)
                                 '((sessionId . "new-session-456"))))
                       (_ (error "Unexpected method: %s" method)))))))
        (acp--initiate-session
         :shell-buffer (current-buffer)
         :on-session-init (lambda ()
                            (setq session-init-called t)))
        (let ((ordered-requests (nreverse requests)))
          (should (equal (mapcar (lambda (req)
                                   (map-elt (plist-get req :request) :method))
                                 ordered-requests)
                         '("session/list" "session/new"))))
        (should session-init-called)
        (should (equal (map-nested-elt acp--state '(:session :id)) "new-session-456"))))))

(ert-deftest acp--format-session-date-test ()
  "Test `acp--format-session-date' humanizes timestamps."
  ;; Pin timezone to UTC so assertions are deterministic.
  (let ((orig-tz (getenv "TZ")))
    (unwind-protect
        (progn
          (set-time-zone-rule "UTC")
          ;; Today
          (let* ((now (current-time))
                 (today-iso (format-time-string "%Y-%m-%dT10:30:00Z" now)))
            (should (equal (acp--format-session-date today-iso)
                           "Today, 10:30")))
          ;; Yesterday
          (let* ((yesterday (time-subtract (current-time) (* 24 60 60)))
                 (yesterday-iso (format-time-string "%Y-%m-%dT15:45:00Z" yesterday)))
            (should (equal (acp--format-session-date yesterday-iso)
                           "Yesterday, 15:45")))
          ;; Same year, older
          (should (string-match-p "^[A-Z][a-z]+ [0-9]+, [0-9]+:[0-9]+"
                                   (acp--format-session-date "2026-01-05T09:00:00Z")))
          ;; Different year
          (should (string-match-p "^[A-Z][a-z]+ [0-9]+, [0-9]\\{4\\}"
                                   (acp--format-session-date "2025-06-15T12:00:00Z")))
          ;; Invalid input falls back gracefully
          (should (equal (acp--format-session-date "not-a-date")
                         "not-a-date")))
      (set-time-zone-rule orig-tz))))

(ert-deftest acp--prompt-select-session-test ()
  "Test `acp--prompt-select-session' choices."
  (let* ((noninteractive t)
         (session-a '((sessionId . "session-1")
                      (title . "First")
                      (cwd . "/home/user/project-a")
                      (updatedAt . "2026-01-19T14:00:00Z")))
         (session-b '((sessionId . "session-2")
                      (title . "Second")
                      (cwd . "/home/user/project-b")
                      (updatedAt . "2026-01-20T16:00:00Z")))
         (sessions (list session-a session-b)))
    ;; noninteractive falls back to (car acp-sessions)
    (should (equal (acp--prompt-select-session sessions)
                   session-a))))

(ert-deftest acp--prompt-select-session-nil-sessions-test ()
  "Test `acp--prompt-select-session' returns nil for empty sessions."
  (cl-letf (((symbol-function 'acp-buffers)
             (lambda () nil)))
    (should-not (acp--prompt-select-session nil))))

(ert-deftest acp--initiate-session-strategy-new-skips-list-load ()
  "Test `acp--initiate-session' skips list/load when strategy is `new'."
  (with-temp-buffer
    (let* ((acp-session-strategy 'new)
           (requests '())
           (session-init-called nil)
           (state `((:buffer . ,(current-buffer))
                    (:client . test-client)
                    (:session . ((:id . nil)
                                 (:mode-id . nil)
                                 (:modes . nil)))
                    (:supports-session-list . t)
                    (:supports-session-load . t)
                    (:active-requests)
                    (:event-subscriptions . nil))))
      (setq-local acp--state state)
      (cl-letf (((symbol-function 'acp--state)
                 (lambda () acp--state))
                ((symbol-function 'acp--update-fragment)
                 (lambda (&rest _args) nil))
                ((symbol-function 'acp--update-header-and-mode-line)
                 (lambda () nil))
                ((symbol-function 'acp-cwd)
                 (lambda () "/tmp"))
                ((symbol-function 'acp--resolve-path)
                 (lambda (path) path))
                ((symbol-function 'acp--mcp-servers)
                 (lambda () []))
                ((symbol-function 'acp-send-request)
                 (lambda (&rest args)
                   (push args requests)
                   (let* ((request (plist-get args :request))
                          (method (map-elt request :method)))
                     (pcase method
                       ("session/new"
                        (funcall (plist-get args :on-success)
                                 '((sessionId . "new-session-789"))))
                       (_ (error "Unexpected method: %s" method)))))))
        (acp--initiate-session
         :shell-buffer (current-buffer)
         :on-session-init (lambda ()
                            (setq session-init-called t)))
        (let ((ordered-requests (nreverse requests)))
          (should (equal (mapcar (lambda (req)
                                   (map-elt (plist-get req :request) :method))
                                 ordered-requests)
                         '("session/new"))))
        (should session-init-called)
        (should (equal (map-nested-elt acp--state '(:session :id)) "new-session-789"))))))

(ert-deftest acp--outgoing-request-decorator-reaches-client ()
  "Test that :outgoing-request-decorator from state reaches the ACP client."
  (with-temp-buffer
    (let* ((my-decorator (lambda (request) request))
           (acp--state (acp--make-state
                                :agent-config nil
                                :buffer (current-buffer)
                                :client-maker (lambda (_buffer)
                                                (acp--make-acp-client
                                                 :command "cat"
                                                 :context-buffer (current-buffer)))
                                :outgoing-request-decorator my-decorator)))
      ;; setq-local needed for buffer-local-value in acp--make-acp-client
      (setq-local acp--state acp--state)
      (let ((client (funcall (map-elt acp--state :client-maker)
                             (current-buffer))))
        (should (eq (map-elt client :outgoing-request-decorator) my-decorator))))))

(ert-deftest acp--outgoing-request-decorator-modifies-request ()
  "Test that :outgoing-request-decorator modifies the sent request."
  (with-temp-buffer
    (let* ((sent-json nil)
           (decorator (lambda (request)
                        (when (equal (map-elt request :method) "session/new")
                          (map-put! request :params
                                    (cons '(_meta . ((systemPrompt . ((append . "extra instructions")))))
                                          (map-elt request :params))))
                        request))
           (acp--state (acp--make-state
                                :agent-config nil
                                :buffer (current-buffer)
                                :client-maker (lambda (_buffer)
                                                (acp--make-acp-client
                                                 :command "cat"
                                                 :context-buffer (current-buffer)))
                                :outgoing-request-decorator decorator)))
      (setq-local acp--state acp--state)
      (let ((client (funcall (map-elt acp--state :client-maker)
                             (current-buffer))))
        ;; Give client a fake process so acp--request-sender proceeds
        (map-put! client :process (start-process "fake" nil "cat"))
        (cl-letf (((symbol-function 'process-send-string)
                   (lambda (_proc json)
                     (setq sent-json json))))
          (acp-send-request
           :client client
           :request (acp-make-session-new-request :cwd "/tmp")
           :on-success #'ignore))
        (delete-process (map-elt client :process))
        ;; Verify the decorator's modification is in the sent JSON
        (let ((parsed (json-parse-string (string-trim sent-json) :object-type 'alist)))
          (should (equal (map-nested-elt parsed '(params _meta systemPrompt append))
                         "extra instructions")))))))

(ert-deftest acp--extract-tool-parameters-test ()
  "Test `acp--extract-tool-parameters' function."
  ;; Test nil input
  (should (null (acp--extract-tool-parameters nil)))

  ;; Test empty alist
  (should (null (acp--extract-tool-parameters '())))

  ;; Test with filePath parameter
  (should (equal (acp--extract-tool-parameters
                  '((filePath . "/home/user/file.txt")))
                 "filePath: /home/user/file.txt"))

  ;; Test with multiple parameters
  (let ((result (acp--extract-tool-parameters
                 '((filePath . "/home/user/file.txt")
                   (offset . 100)
                   (limit . 50)))))
    (should (string-match-p "filePath: /home/user/file.txt" result))
    (should (string-match-p "offset: 100" result))
    (should (string-match-p "limit: 50" result)))

  ;; Test that command and description are excluded
  (should (null (acp--extract-tool-parameters
                 '((command . "ls -la")
                   (description . "List files")))))

  ;; Test that command/description are excluded but other params included
  (should (equal (acp--extract-tool-parameters
                  '((command . "ls -la")
                    (description . "List files")
                    (workdir . "/tmp")))
                 "workdir: /tmp"))

  ;; Test with boolean value
  (should (equal (acp--extract-tool-parameters
                  '((replaceAll . t)))
                 "replaceAll: true"))

  ;; Test with nil value (should be excluded)
  (should (null (acp--extract-tool-parameters
                 '((filePath . nil)))))

  ;; Test with empty string (should be excluded)
  (should (null (acp--extract-tool-parameters
                 '((pattern . "")))))

  ;; Test plan is excluded (shown separately)
  (should (null (acp--extract-tool-parameters
                 '((plan . "Step 1: do something"))))))

(ert-deftest acp--make-transcript-tool-call-entry-parameters-test ()
  "Test `acp--make-transcript-tool-call-entry' with parameters."
  ;; Test basic entry without parameters
  (let ((entry (acp--make-transcript-tool-call-entry
                :status "completed"
                :title "Read file"
                :kind "read"
                :output "file content here")))
    (should (string-match-p "### Tool Call \\[completed\\]: Read file" entry))
    (should (string-match-p "\\*\\*Tool:\\*\\* read" entry))
    (should (string-match-p "file content here" entry))
    (should-not (string-match-p "\\*\\*Parameters:\\*\\*" entry)))

  ;; Test entry with parameters
  (let ((entry (acp--make-transcript-tool-call-entry
                :status "completed"
                :title "Read file"
                :kind "read"
                :parameters "filePath: /home/user/test.txt\noffset: 100"
                :output "file content here")))
    (should (string-match-p "\\*\\*Parameters:\\*\\*" entry))
    (should (string-match-p "filePath: /home/user/test.txt" entry))
    (should (string-match-p "offset: 100" entry))))

(ert-deftest acp--session-column-value-test ()
  "Test `acp--session-column-value' extracts correct values."
  (let ((session '((sessionId . "abc-123")
                   (title . "My session")
                   (cwd . "/home/user/project")
                   (updatedAt . "2026-01-19T14:00:00Z"))))
    ;; directory extracts last path component
    (should (equal (acp--session-column-value 'directory session)
                   "project"))
    ;; title returns session title
    (should (equal (acp--session-column-value 'title session)
                   "My session"))
    ;; session-id returns full sessionId
    (should (equal (acp--session-column-value 'session-id session)
                   "abc-123"))
    ;; date returns formatted date string
    (should (stringp (acp--session-column-value 'date session)))
    ;; unknown column returns empty string
    (should (equal (acp--session-column-value 'unknown session)
                   ""))))

(ert-deftest acp--session-column-value-missing-fields-test ()
  "Test `acp--session-column-value' handles missing fields."
  (let ((session '((sessionId . "s1"))))
    ;; missing cwd
    (should (equal (acp--session-column-value 'directory session)
                   ""))
    ;; missing title
    (should (equal (acp--session-column-value 'title session)
                   "Untitled"))
    ;; missing sessionId
    (should (equal (acp--session-column-value 'session-id '())
                   ""))))

(ert-deftest acp--session-column-face-test ()
  "Test `acp--session-column-face' returns correct faces."
  (should (eq (acp--session-column-face 'directory)
              'font-lock-keyword-face))
  (should (eq (acp--session-column-face 'date)
              'font-lock-comment-face))
  (should (eq (acp--session-column-face 'session-id)
              'font-lock-constant-face))
  ;; title and unknown have no face
  (should-not (acp--session-column-face 'title))
  (should-not (acp--session-column-face 'unknown)))

(ert-deftest acp--session-choice-label-default-columns-test ()
  "Test `acp--session-choice-label' with default columns."
  (let ((acp-show-session-id nil)
        (session '((sessionId . "s1")
                   (title . "My session")
                   (cwd . "/home/user/project")
                   (updatedAt . "2026-01-19T14:00:00Z")))
        (max-widths '((directory . 10) (title . 15) (date . 20))))
    (let ((label (substring-no-properties
                  (acp--session-choice-label
                   :acp-session session
                   :max-widths max-widths))))
      ;; All three columns present
      (should (string-match-p "project" label))
      (should (string-match-p "My session" label))
      ;; Directory and title are padded, date is not (last column)
      (should (string-match-p "project   " label))
      (should (string-match-p "My session      " label)))))

(ert-deftest acp--session-choice-label-with-session-id-test ()
  "Test `acp--session-choice-label' includes session-id column."
  (let ((acp-show-session-id t)
        (session '((sessionId . "abc-123")
                   (title . "My session")
                   (cwd . "/home/user/project")
                   (updatedAt . "2026-01-19T14:00:00Z")))
        (max-widths '((directory . 10) (title . 15) (date . 20) (session-id . 10))))
    (let ((label (substring-no-properties
                  (acp--session-choice-label
                   :acp-session session
                   :max-widths max-widths))))
      (should (string-match-p "abc-123" label))
      (should (string-match-p "project" label))
      (should (string-match-p "My session" label)))))

(ert-deftest acp--session-id-indicator-disabled-test ()
  "Test `acp--session-id-indicator' returns nil when disabled."
  (with-temp-buffer
    (setq-local acp--state
                `((:session . ((:id . "test-session-id")))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-session-id nil))
        (should-not (acp--session-id-indicator))))))

(ert-deftest acp--session-id-indicator-enabled-test ()
  "Test `acp--session-id-indicator' returns formatted ID when enabled."
  (with-temp-buffer
    (setq-local acp--state
                `((:session . ((:id . "test-session-id")))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-session-id t))
        (let ((indicator (acp--session-id-indicator)))
          (should indicator)
          (should (equal (substring-no-properties indicator)
                         "test-session-id")))))))

(ert-deftest acp--session-id-indicator-no-session-test ()
  "Test `acp--session-id-indicator' returns nil without active session."
  (with-temp-buffer
    (setq-local acp--state
                `((:session . ((:id . nil)))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-session-id t))
        (should-not (acp--session-id-indicator))))))

(ert-deftest acp-copy-session-id-test ()
  "Test `acp-copy-session-id' copies ID to kill ring."
  (with-temp-buffer
    (setq-local acp--state
                `((:session . ((:id . "test-session-id")))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'derived-mode-p)
               (lambda (&rest _) t)))
      (acp-copy-session-id)
      (should (equal (current-kill 0) "test-session-id")))))

(ert-deftest acp-copy-session-id-no-session-test ()
  "Test `acp-copy-session-id' errors without active session."
  (with-temp-buffer
    (setq-local acp--state
                `((:session . ((:id . nil)))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'derived-mode-p)
               (lambda (&rest _) t)))
      (should-error (acp-copy-session-id)
                    :type 'user-error))))

(ert-deftest acp--make-header-model-includes-session-id-test ()
  "Test `acp--make-header-model' includes :session-id field."
  (with-temp-buffer
    (setq-local acp--state
                `((:agent-config . ((:buffer-name . "Claude Code")
                                    (:icon-name . nil)))
                  (:session . ((:id . "test-session-id")
                               (:model-id . nil)
                               (:models . nil)
                               (:mode-id . nil)
                               (:modes . nil)))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'acp--context-usage-indicator)
               (lambda () nil))
              ((symbol-function 'acp--busy-indicator-frame)
               (lambda () nil)))
      ;; Enabled
      (let ((acp-show-session-id t))
        (let ((model (acp--make-header-model acp--state)))
          (should (assq :session-id model))
          (should (equal (substring-no-properties (map-elt model :session-id))
                         "test-session-id"))))
      ;; Disabled
      (let ((acp-show-session-id nil))
        (let ((model (acp--make-header-model acp--state)))
          (should (assq :session-id model))
          (should-not (map-elt model :session-id)))))))

(ert-deftest acp--make-header-text-includes-session-id-test ()
  "Test `acp--make-header' text mode includes session ID."
  (with-temp-buffer
    (setq-local acp--state
                `((:agent-config . ((:buffer-name . "Claude Code")
                                    (:icon-name . nil)))
                  (:session . ((:id . "test-session-id")
                               (:model-id . nil)
                               (:models . nil)
                               (:mode-id . nil)
                               (:modes . nil)))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state))
              ((symbol-function 'acp--context-usage-indicator)
               (lambda () nil))
              ((symbol-function 'acp--busy-indicator-frame)
               (lambda () nil)))
      (let ((acp-header-style 'text)
            (acp-show-session-id t))
        (let ((header (acp--make-header acp--state)))
          (should (string-match-p "test-session-id"
                                  (substring-no-properties header)))))
      ;; Disabled: session ID absent
      (let ((acp-header-style 'text)
            (acp-show-session-id nil))
        (let ((header (acp--make-header acp--state)))
          (should-not (string-match-p "test-session-id"
                                      (substring-no-properties header))))))))

;;; Tests for acp--dot-subdir-in-repo

(ert-deftest acp--dot-subdir-in-repo-returns-path-test ()
  "Test that `acp--dot-subdir-in-repo' returns the correct path."
  (cl-letf (((symbol-function 'acp-cwd)
             (lambda () "/home/user/myproject")))
    (should (equal (acp--dot-subdir-in-repo "screenshots")
                   "/home/user/myproject/.acp/screenshots"))))

;;; Tests for acp--dot-subdir

(ert-deftest acp--dot-subdir-creates-directory-test ()
  "Test that `acp--dot-subdir' creates the directory."
  (let* ((temp-dir (make-temp-file "acp-test" t))
         (expected-dir (expand-file-name ".acp/screenshots" temp-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'acp-cwd) (lambda () temp-dir))
                  ((symbol-function 'acp--ensure-gitignore) #'ignore))
          (let ((acp-dot-subdir-function #'acp--dot-subdir-in-repo))
            (acp--dot-subdir "screenshots")
            (should (file-directory-p expected-dir))))
      (delete-directory temp-dir t))))

(ert-deftest acp--dot-subdir-returns-path-test ()
  "Test that `acp--dot-subdir' returns the resolved path."
  (let* ((temp-dir (make-temp-file "acp-test" t))
         (expected-dir (expand-file-name ".acp/screenshots" temp-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'acp-cwd) (lambda () temp-dir))
                  ((symbol-function 'acp--ensure-gitignore) #'ignore))
          (let ((acp-dot-subdir-function #'acp--dot-subdir-in-repo))
            (should (equal (acp--dot-subdir "screenshots") expected-dir))))
      (delete-directory temp-dir t))))

(ert-deftest acp--dot-subdir-noop-if-directory-exists-test ()
  "Test that `acp--dot-subdir' does not error if the directory already exists."
  (let* ((temp-dir (make-temp-file "acp-test" t))
         (expected-dir (expand-file-name ".acp/screenshots" temp-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'acp-cwd) (lambda () temp-dir))
                  ((symbol-function 'acp--ensure-gitignore) #'ignore))
          (let ((acp-dot-subdir-function #'acp--dot-subdir-in-repo))
            (make-directory expected-dir t)
            (should (equal (acp--dot-subdir "screenshots") expected-dir))
            (should (file-directory-p expected-dir))))
      (delete-directory temp-dir t))))

(ert-deftest acp--dot-subdir-uses-configured-function-test ()
  "Test that `acp--dot-subdir' delegates to `acp-dot-subdir-function'."
  (let* ((temp-dir (make-temp-file "acp-test" t))
         (custom-called-with nil))
    (unwind-protect
        (cl-letf (((symbol-function 'acp-cwd) (lambda () temp-dir))
                  ((symbol-function 'acp--ensure-gitignore) #'ignore))
          (let ((acp-dot-subdir-function
                 (lambda (subdir)
                   (setq custom-called-with subdir)
                   (expand-file-name subdir temp-dir))))
            (acp--dot-subdir "screenshots")
            (should (equal custom-called-with "screenshots"))))
      (delete-directory temp-dir t))))

(ert-deftest acp--dot-subdir-errors-if-function-not-callable-test ()
  "Test that `acp--dot-subdir' errors when `acp-dot-subdir-function' is not a function."
  (let ((acp-dot-subdir-function "not-a-function"))
    (should-error (acp--dot-subdir "screenshots") :type 'error)))

(ert-deftest acp--dot-subdir-errors-if-function-returns-non-string-test ()
  "Test that `acp--dot-subdir' errors when `acp-dot-subdir-function' returns a non-string."
  (cl-letf (((symbol-function 'acp-cwd) (lambda () "/tmp")))
    (let ((acp-dot-subdir-function (lambda (_subdir) nil)))
      (should-error (acp--dot-subdir "screenshots") :type 'error))
    (let ((acp-dot-subdir-function (lambda (_subdir) 42)))
      (should-error (acp--dot-subdir "screenshots") :type 'error))))

(ert-deftest acp--dot-subdir-errors-if-function-returns-blank-string-test ()
  "Test that `acp--dot-subdir' errors when `acp-dot-subdir-function' returns a blank string."
  (cl-letf (((symbol-function 'acp-cwd) (lambda () "/tmp")))
    (let ((acp-dot-subdir-function (lambda (_subdir) "  ")))
      (should-error (acp--dot-subdir "screenshots") :type 'error))))

(ert-deftest acp--on-request-calls-permission-request-handler-test ()
  "Test `acp--on-request' calls handler and :respond auto-approves."
  (with-temp-buffer
    (let* ((responded-option-id nil)
           (handler-received nil)
           (acp-permission-responder-function
            (lambda (request)
              (setq handler-received request)
              (when-let ((opt (seq-find
                               (lambda (o) (equal (map-elt o :kind) "allow_once"))
                               (map-elt request :options))))
                (funcall (map-elt request :respond)
                         (map-elt opt :option-id)))))
           (state `((:buffer . ,(current-buffer))
                    (:client . test-client)
                    (:tool-calls . nil)
                    (:last-entry-type . nil)
                    (:event-subscriptions . nil))))
      (cl-letf (((symbol-function 'acp--state)
                 (lambda () state))
                ((symbol-function 'acp--update-fragment)
                 (lambda (&rest _)))
                ((symbol-function 'acp-jump-to-latest-permission-button-row)
                 (lambda ()))
                ((symbol-function 'acp--make-tool-call-permission-text)
                 (lambda (&rest _) "mock"))
                ((symbol-function 'acp-viewport--buffer)
                 (lambda (&rest _) nil))
                ((symbol-function 'acp--send-permission-response)
                 (lambda (&rest args)
                   (setq responded-option-id (plist-get args :option-id)))))
        (acp--on-request
         :state state
         :acp-request `((id . "req-1")
                        (method . "session/request_permission")
                        (params . ((toolCall . ((toolCallId . "tc-1")
                                                (title . "Read file")
                                                (status . "pending")
                                                (kind . "read")))
                                   (options . [((kind . "allow_once")
                                                (name . "Allow")
                                                (optionId . "opt-allow"))
                                               ((kind . "reject_once")
                                                (name . "Reject")
                                                (optionId . "opt-reject"))])))))
        (should handler-received)
        (should (equal (map-elt (map-elt handler-received :tool-call) :kind) "read"))
        (should (equal (map-elt (map-elt handler-received :tool-call) :title) "Read file"))
        (should (= (length (map-elt handler-received :options)) 2))
        (should (equal responded-option-id "opt-allow"))))))

(ert-deftest acp--on-request-handler-nil-leaves-prompt-test ()
  "Test `acp--on-request' leaves interactive prompt when handler returns nil."
  (with-temp-buffer
    (let* ((responded nil)
           (acp-permission-responder-function
            (lambda (_request) nil))
           (state `((:buffer . ,(current-buffer))
                    (:client . test-client)
                    (:tool-calls . nil)
                    (:last-entry-type . nil)
                    (:event-subscriptions . nil))))
      (cl-letf (((symbol-function 'acp--state)
                 (lambda () state))
                ((symbol-function 'acp--update-fragment)
                 (lambda (&rest _)))
                ((symbol-function 'acp-jump-to-latest-permission-button-row)
                 (lambda ()))
                ((symbol-function 'acp--make-tool-call-permission-text)
                 (lambda (&rest _) "mock"))
                ((symbol-function 'acp-viewport--buffer)
                 (lambda (&rest _) nil))
                ((symbol-function 'acp--send-permission-response)
                 (lambda (&rest _)
                   (setq responded t))))
        (acp--on-request
         :state state
         :acp-request `((id . "req-1")
                        (method . "session/request_permission")
                        (params . ((toolCall . ((toolCallId . "tc-1")
                                                (title . "Run command")
                                                (status . "pending")
                                                (kind . "execute")))
                                   (options . [((kind . "allow_once")
                                                (name . "Allow")
                                                (optionId . "opt-allow"))])))))
        (should-not responded)
        (should (equal (map-elt state :last-entry-type) "session/request_permission"))))))

;;; Tests for acp-show-context-usage-indicator

(ert-deftest acp--context-usage-indicator-bar-test ()
  "Test `acp--context-usage-indicator' bar mode."
  (let ((acp--state
         (list (cons :buffer (current-buffer))
               (cons :usage (list (cons :context-used 50000)
                                  (cons :context-size 200000)
                                  (cons :total-tokens 50000))))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-context-usage-indicator t))
        (let ((result (acp--context-usage-indicator)))
          (should result)
          (should (= (length (substring-no-properties result)) 1))
          (should (eq (get-text-property 0 'face result) 'success)))))))

(ert-deftest acp--context-usage-indicator-detailed-test ()
  "Test `acp--context-usage-indicator' detailed mode."
  (let ((acp--state
         (list (cons :buffer (current-buffer))
               (cons :usage (list (cons :context-used 30000)
                                  (cons :context-size 200000)
                                  (cons :total-tokens 30000))))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-context-usage-indicator 'detailed))
        (let ((result (acp--context-usage-indicator)))
          (should result)
          (should (string-match-p "30k/200k" (substring-no-properties result)))
          (should (string-match-p "15%%" (substring-no-properties result)))
          (should (eq (get-text-property 0 'face result) 'success)))))))

(ert-deftest acp--context-usage-indicator-detailed-warning-test ()
  "Test `acp--context-usage-indicator' detailed mode with warning face."
  (let ((acp--state
         (list (cons :buffer (current-buffer))
               (cons :usage (list (cons :context-used 140000)
                                  (cons :context-size 200000)
                                  (cons :total-tokens 140000))))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-context-usage-indicator 'detailed))
        (let ((result (acp--context-usage-indicator)))
          (should (eq (get-text-property 0 'face result) 'warning)))))))

(ert-deftest acp--context-usage-indicator-nil-test ()
  "Test `acp--context-usage-indicator' returns nil when disabled."
  (let ((acp--state
         (list (cons :buffer (current-buffer))
               (cons :usage (list (cons :context-used 50000)
                                  (cons :context-size 200000)
                                  (cons :total-tokens 50000))))))
    (cl-letf (((symbol-function 'acp--state)
               (lambda () acp--state)))
      (let ((acp-show-context-usage-indicator nil))
        (should-not (acp--context-usage-indicator))))))

(provide 'acp-tests)
;;; acp-tests.el ends here

;;; acp-anthropic-tests.el --- Tests for acp-anthropic -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp)
(require 'acp-anthropic)

(ert-deftest acp-anthropic-make-claude-client-test ()
  "Test acp-anthropic-make-claude-client function."
  ;; Mock executable-find to always return the command path
  (cl-letf (((symbol-function 'executable-find)
             (lambda (_) "/usr/bin/claude-agent-acp")))
    ;; Test with API key authentication
    (let* ((acp-anthropic-authentication '(:api-key "test-api-key"))
           (acp-anthropic-claude-acp-command '("claude-agent-acp" "--json"))
           (acp-anthropic-claude-environment '("DEBUG=1"))
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer)))
      (unwind-protect
          (progn
            (should (listp client))
            (should (equal (map-elt client :command) "claude-agent-acp"))
            (should (equal (map-elt client :command-params) '("--json")))
            (should (member "ANTHROPIC_API_KEY=test-api-key" (map-elt client :environment-variables)))
            (should (member "DEBUG=1" (map-elt client :environment-variables))))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test with login authentication
    (let* ((acp-anthropic-authentication '(:login t))
           (acp-anthropic-claude-acp-command '("claude-agent-acp" "--interactive"))
           (acp-anthropic-claude-environment '("VERBOSE=true"))
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer)))
      (unwind-protect
          (progn
            ;; Verify environment variables include empty API key for login
            (should (member "ANTHROPIC_API_KEY=" (map-elt client :environment-variables)))
            (should (member "VERBOSE=true" (map-elt client :environment-variables))))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test with function-based API key
    (let* ((acp-anthropic-authentication `(:api-key ,(lambda () "dynamic-key")))
           (acp-anthropic-claude-acp-command '("claude-agent-acp"))
           (acp-anthropic-claude-environment '())
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer))
           (env-vars (map-elt client :environment-variables)))
      (unwind-protect
          (should (member "ANTHROPIC_API_KEY=dynamic-key" env-vars))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test error on invalid authentication
    (let* ((acp-anthropic-authentication '())
           (acp-anthropic-claude-acp-command '("claude-agent-acp"))
           (test-buffer (get-buffer-create "*test-buffer*")))
      (unwind-protect
          (should-error (acp-anthropic-make-claude-client :buffer test-buffer)
                        :type 'error)
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test with acp-make-environment-variables and :inherit-env t
    (let* ((acp-anthropic-authentication '(:api-key "test-key"))
           (acp-anthropic-claude-acp-command '("claude-agent-acp"))
           (process-environment '("EXISTING_VAR=existing_value"))
           (acp-anthropic-claude-environment (acp-make-environment-variables
                                                      "NEW_VAR" "new_value"
                                                      :inherit-env t))
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer))
           (env-vars (map-elt client :environment-variables)))
      (unwind-protect
          (progn
            (should (member "ANTHROPIC_API_KEY=test-key" env-vars))
            (should (member "NEW_VAR=new_value" env-vars))
            (should (member "EXISTING_VAR=existing_value" env-vars)))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test with OAuth token string
    (let* ((acp-anthropic-authentication '(:oauth "test-oauth-token"))
           (acp-anthropic-claude-acp-command '("claude-agent-acp"))
           (acp-anthropic-claude-environment '())
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer))
           (env-vars (map-elt client :environment-variables)))
      (unwind-protect
          (should (member "CLAUDE_CODE_OAUTH_TOKEN=test-oauth-token" env-vars))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))

    ;; Test with function-based OAuth token
    (let* ((acp-anthropic-authentication `(:oauth ,(lambda () "dynamic-oauth-token")))
           (acp-anthropic-claude-acp-command '("claude-agent-acp"))
           (acp-anthropic-claude-environment '())
           (test-buffer (get-buffer-create "*test-buffer*"))
           (client (acp-anthropic-make-claude-client :buffer test-buffer))
           (env-vars (map-elt client :environment-variables)))
      (unwind-protect
          (should (member "CLAUDE_CODE_OAUTH_TOKEN=dynamic-oauth-token" env-vars))
        (when (buffer-live-p test-buffer)
          (kill-buffer test-buffer))))))

(ert-deftest acp-anthropic-default-model-id-function-test ()
  "Test that acp-anthropic-default-model-id accepts a function."
  (let* ((config (acp-anthropic-make-claude-code-config))
         (default-model-id-fn (map-elt config :default-model-id)))

    ;; Test with nil value
    (let ((acp-anthropic-default-model-id nil))
      (should (null (funcall default-model-id-fn))))

    ;; Test with string value
    (let ((acp-anthropic-default-model-id "claude-opus-4-6"))
      (should (string= (funcall default-model-id-fn) "claude-opus-4-6")))

    ;; Test with function value
    (let ((acp-anthropic-default-model-id (lambda () "dynamic-model-id")))
      (should (string= (funcall default-model-id-fn) "dynamic-model-id")))

    ;; Test with function that returns nil
    (let ((acp-anthropic-default-model-id (lambda () nil)))
      (should (null (funcall default-model-id-fn))))))

(provide 'acp-anthropic-tests)
;;; acp-anthropic-tests.el ends here

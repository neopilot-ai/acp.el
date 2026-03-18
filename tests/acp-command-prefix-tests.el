;;; acp-command-prefix-tests.el --- Tests for acp command prefix functionality -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp)

;;; Code:

(ert-deftest acp--build-command-for-execution-test ()
  "Test `acp--build-command-for-execution' function."

  ;; No command prefix configured (nil)
  (let ((acp-command-prefix nil))
    (should (equal (acp--build-command-for-execution
                    '("claude-agent-acp"))
                   '("claude-agent-acp"))))

  ;; Static list
  (let ((acp-command-prefix
         '("devcontainer" "exec" "--workspace-folder" ".")))
    (should (equal (acp--build-command-for-execution
                    '("claude-agent-acp"))
                   '("devcontainer" "exec" "--workspace-folder" "." "claude-agent-acp"))))

  ;; Function
  (let ((acp-command-prefix
         (lambda (buffer)
           '("devcontainer" "exec" "--workspace-folder" "."))))
    (should (equal (acp--build-command-for-execution
                    '("claude-agent-acp"))
                   '("devcontainer" "exec" "--workspace-folder" "." "claude-agent-acp")))))

(provide 'acp-command-prefix-tests)
;;; acp-command-prefix-tests.el ends here

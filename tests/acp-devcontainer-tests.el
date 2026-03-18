;;; acp-devcontainer-tests.el --- Tests for acp Devcontainer support -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp)

;;; Code:

(ert-deftest acp-devcontainer-resolve-path-test ()
  "Test `acp-devcontainer-resolve-path' function."
  ;; Mock acp-devcontainer--get-workspace-path
  (cl-letf (((symbol-function 'acp-devcontainer--get-workspace-path)
             (lambda (_) "/workspace")))

    ;; Need to run in an existing directory (requirement of `file-in-directory-p')
    (let ((default-directory "/tmp"))
      ;; With text file capabilities enabled
      (let ((acp-text-file-capabilities t))

        ;; Resolves container paths to local filesystem paths
        (should (equal (acp-devcontainer-resolve-path "/workspace/d/f.el") "/tmp/d/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/workspace/f.el") "/tmp/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/workspace") "/tmp"))

        ;; Prevents attempts to leave local working directory
        (should-error (acp-devcontainer-resolve-path "/workspace/..") :type 'error)

        ;; Resolves local filesystem paths to container paths
        (should (equal (acp-devcontainer-resolve-path "/tmp/d/f.el") "/workspace/d/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/tmp/f.el") "/workspace/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/tmp") "/workspace"))

        ;; Does not resolve unexpected paths
        (should-error (acp-devcontainer-resolve-path "/unexpected") :type 'error))

      ;; With text file capabilities disabled (ie. never resolve to local filesystem)
      (let ((acp-text-file-capabilities nil))

        ;; Does not resolve container paths to local filesystem paths
        (should-error (acp-devcontainer-resolve-path "/workspace/d/f.el") :type 'error)
        (should-error (acp-devcontainer-resolve-path "/workspace/f.el.") :type 'error)
        (should-error (acp-devcontainer-resolve-path "/workspace") :type 'error)
        (should-error (acp-devcontainer-resolve-path "/workspace/..") :type 'error)

        ;; Resolves local filesystem paths to container paths
        (should (equal (acp-devcontainer-resolve-path "/tmp/d/f.el") "/workspace/d/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/tmp/f.el") "/workspace/f.el"))
        (should (equal (acp-devcontainer-resolve-path "/tmp") "/workspace"))

        ;; Does not resolve unexpected paths
        (should-error (acp-devcontainer-resolve-path "/unexpected") :type 'error)))))

(provide 'acp-devcontainer-tests)
;;; acp-devcontainer-tests.el ends here

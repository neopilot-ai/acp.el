;;; acp-permissions-tests.el --- Tests for acp-permissions -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp-permissions)

;;; Code:

(ert-deftest acp-permissions--make-record ()
  "Permission record creation."
  (let ((record (acp-permissions--make-record
                 :action 'file-read
                 :target "/tmp/test.txt"
                 :agent "anthropic"
                 :session-id "s1"
                 :decision 'allow
                 :timestamp (current-time)
                 :reason "allowed-path")))
    (should (eq (plist-get record :action) 'file-read))
    (should (equal (plist-get record :target) "/tmp/test.txt"))
    (should (eq (plist-get record :decision) 'allow))
    (should (equal (plist-get record :agent) "anthropic"))))

(ert-deftest acp-permissions--path-allowed-p ()
  "Path allowed check."
  (let ((acp-permissions-allowed-paths '("/home/user/projects/" "/tmp/")))
    (should (acp-permissions--path-allowed-p "/home/user/projects/foo.el"))
    (should (acp-permissions--path-allowed-p "/tmp/test.txt"))
    (should-not (acp-permissions--path-allowed-p "/etc/passwd"))))

(ert-deftest acp-permissions--path-denied-p ()
  "Path denied check."
  (let ((acp-permissions-denied-paths '("/etc/" "/root/")))
    (should (acp-permissions--path-denied-p "/etc/passwd"))
    (should (acp-permissions--path-denied-p "/root/secret"))
    (should-not (acp-permissions--path-denied-p "/home/user/file.txt"))))

(ert-deftest acp-permissions--path-denied-overrides-allowed ()
  "Denied paths take precedence over allowed paths."
  (let ((acp-permissions-allowed-paths '("/home/user/"))
        (acp-permissions-denied-paths '("/home/user/.ssh/")))
    (should (acp-permissions--path-allowed-p "/home/user/file.txt"))
    (should (acp-permissions--path-denied-p "/home/user/.ssh/authorized_keys"))))

(ert-deftest acp-permissions-check/allow-policy ()
  "Allow policy returns allow."
  (let ((acp-permissions-file-read-policy 'allow)
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check 'file-read "/tmp/test.txt") 'allow))))

(ert-deftest acp-permissions-check/deny-policy ()
  "Deny policy returns deny."
  (let ((acp-permissions-file-read-policy 'deny)
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check 'file-read "/tmp/test.txt") 'deny))))

(ert-deftest acp-permissions-check/denied-path-overrides-allow-policy ()
  "Denied path overrides allow policy."
  (let ((acp-permissions-file-read-policy 'allow)
        (acp-permissions-denied-paths '("/etc/"))
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check 'file-read "/etc/passwd") 'deny))))

(ert-deftest acp-permissions-check/allowed-path-overrides-deny-policy ()
  "Allowed path overrides deny policy."
  (let ((acp-permissions-file-read-policy 'deny)
        (acp-permissions-allowed-paths '("/tmp/"))
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check 'file-read "/tmp/test.txt") 'allow))))

(ert-deftest acp-permissions-check-file-read/allow ()
  "File read check with allow policy."
  (let ((acp-permissions-file-read-policy 'allow)
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check-file-read "/tmp/test.txt") 'allow))))

(ert-deftest acp-permissions-check-file-write/deny ()
  "File write check with deny policy."
  (let ((acp-permissions-file-write-policy 'deny)
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check-file-write "/tmp/test.txt") 'deny))))

(ert-deftest acp-permissions-check-command/allow ()
  "Command check with allow policy."
  (let ((acp-permissions-command-execution-policy 'allow)
        (acp-permissions-audit-log nil))
    (should (eq (acp-permissions-check-command "ls -la") 'allow))))

(ert-deftest acp-permissions-audit-log/creates-file ()
  "Audit log creates a log file."
  (let ((acp-permissions-audit-log t)
        (audit-dir (make-temp-file "acp-audit-test" t)))
    (unwind-protect
        (let ((record (acp-permissions--make-record
                       :action 'file-read
                       :target "/tmp/test.txt"
                       :agent "test-agent"
                       :session-id "test-session"
                       :decision 'allow
                       :timestamp (current-time)
                       :reason "test")))
          ;; Mock the audit directory
          (cl-letf (((symbol-function 'acp-permissions--audit-directory)
                     (lambda () audit-dir)))
            (acp-permissions--audit-log record)
            (let ((log-file (expand-file-name "permissions-audit.log" audit-dir)))
              (should (file-exists-p log-file))
              (with-temp-buffer
                (insert-file-contents log-file)
                (should (string-match-p "file-read" (buffer-string)))
                (should (string-match-p "/tmp/test.txt" (buffer-string)))
                (should (string-match-p "allow" (buffer-string)))))))
      (delete-directory audit-dir t))))

(ert-deftest acp-permissions-audit-log/disabled ()
  "Audit log does nothing when disabled."
  (let ((acp-permissions-audit-log nil)
        (audit-dir (make-temp-file "acp-audit-test" t)))
    (unwind-protect
        (let ((record (acp-permissions--make-record
                       :action 'file-read
                       :target "/tmp/test.txt"
                       :agent "test"
                       :session-id "s1"
                       :decision 'allow
                       :timestamp (current-time))))
          (cl-letf (((symbol-function 'acp-permissions--audit-directory)
                     (lambda () audit-dir)))
            (acp-permissions--audit-log record)
            (should-not (file-exists-p
                         (expand-file-name "permissions-audit.log" audit-dir)))))
      (delete-directory audit-dir t))))

(provide 'acp-permissions-tests)

;;; acp-permissions-tests.el ends here

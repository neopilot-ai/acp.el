;;; acp-session-store-tests.el --- Tests for acp-session-store -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp-session-store)

;;; Code:

(ert-deftest acp-session-store--make-session/defaults ()
  "Session record creation with defaults."
  (let ((session (acp-session-store--make-session
                  :id "test-123"
                  :agent "anthropic"
                  :model "claude-3"
                  :timestamp (current-time))))
    (should (equal (acp-session-store--session-id session) "test-123"))
    (should (equal (acp-session-store--session-agent session) "anthropic"))
    (should (equal (acp-session-store--session-tags session) '()))))

(ert-deftest acp-session-store--make-session/with-tags ()
  "Session record creation with tags."
  (let ((session (acp-session-store--make-session
                  :id "test-456"
                  :agent "openai"
                  :timestamp (current-time)
                  :tags '("bugfix" "important"))))
    (should (equal (acp-session-store--session-tags session) '("bugfix" "important")))))

(ert-deftest acp-session-store--session-id ()
  "Session ID accessor."
  (let ((session (acp-session-store--make-session
                  :id "my-session"
                  :timestamp (current-time))))
    (should (equal (acp-session-store--session-id session) "my-session"))))

(ert-deftest acp-session-store--session-agent ()
  "Session agent accessor."
  (let ((session (acp-session-store--make-session
                  :id "s1"
                  :agent "google"
                  :timestamp (current-time))))
    (should (equal (acp-session-store--session-agent session) "google"))))

(ert-deftest acp-session-store--session-timestamp ()
  "Session timestamp accessor."
  (let* ((ts (current-time))
         (session (acp-session-store--make-session
                   :id "s2"
                   :timestamp ts)))
    (should (equal (acp-session-store--session-timestamp session) ts))))

(ert-deftest acp-session-store--session-tags ()
  "Session tags accessor."
  (let ((session (acp-session-store--make-session
                  :id "s3"
                  :tags '("a" "b" "c")
                  :timestamp (current-time))))
    (should (equal (acp-session-store--session-tags session) '("a" "b" "c")))))

(ert-deftest acp-session-store--serialize-elisp ()
  "Elisp serialization roundtrip."
  (let ((acp-session-store-format 'elisp)
        (session (acp-session-store--make-session
                  :id "roundtrip-1"
                  :agent "anthropic"
                  :timestamp (current-time)
                  :tags '("test"))))
    (let ((serialized (acp-session-store--serialize session))
          (restored (acp-session-store--deserialize
                     (acp-session-store--serialize session))))
      (should (stringp serialized))
      (should (equal (acp-session-store--session-id restored) "roundtrip-1"))
      (should (equal (acp-session-store--session-agent restored) "anthropic"))
      (should (equal (acp-session-store--session-tags restored) '("test"))))))

(ert-deftest acp-session-store--serialize-json ()
  "JSON serialization roundtrip."
  (let ((acp-session-store-format 'json)
        (session (acp-session-store--make-session
                  :id "json-1"
                  :agent "openai"
                  :timestamp (current-time)
                  :tags '("feature"))))
    (let ((serialized (acp-session-store--serialize session))
          (restored (acp-session-store--deserialize
                     (acp-session-store--serialize session))))
      (should (stringp serialized))
      (should (equal (alist-get 'id restored) "json-1"))
      (should (equal (alist-get 'agent restored) "openai")))))

(ert-deftest acp-session-store--directory/creates-if-needed ()
  "Session directory is created on demand."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t)))
    (unwind-protect
        (progn
          (delete-directory acp-session-store-directory)
          (let ((dir (acp-session-store--directory)))
            (should (file-directory-p dir))))
      (when (file-exists-p acp-session-store-directory)
        (delete-directory acp-session-store-directory t)))))

(ert-deftest acp-session-store--session-file/format ()
  "Session file path has correct extension."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'elisp))
    (unwind-protect
        (let ((file (acp-session-store--session-file "test-001")))
          (should (string-suffix-p "test-001.el" file)))
      (delete-directory acp-session-store-directory t))))

(ert-deftest acp-session-store--session-file/json-format ()
  "Session file path has .json extension in json format."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'json))
    (unwind-protect
        (let ((file (acp-session-store--session-file "test-002")))
          (should (string-suffix-p "test-002.json" file)))
      (delete-directory acp-session-store-directory t))))

(ert-deftest acp-session-store-save-and-load ()
  "Save and load a session."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'elisp))
    (unwind-protect
        (let ((session (acp-session-store--make-session
                        :id "save-load-test"
                        :agent "anthropic"
                        :timestamp (current-time)
                        :tags '("integration"))))
          (let ((file (acp-session-store--session-file "save-load-test")))
            (with-temp-file file
              (insert (acp-session-store--serialize session))
              (insert "\n"))
            (let ((loaded (with-temp-buffer
                            (insert-file-contents file)
                            (acp-session-store--deserialize
                             (buffer-string)))))
              (should (equal (acp-session-store--session-id loaded) "save-load-test"))
              (should (equal (acp-session-store--session-agent loaded) "anthropic"))
              (should (equal (acp-session-store--session-tags loaded) '("integration"))))))
      (delete-directory acp-session-store-directory t))))

(ert-deftest acp-session-store--list-sessions ()
  "List sessions returns saved IDs."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'elisp))
    (unwind-protect
        (progn
          ;; Create two session files
          (dolist (id '("session-a" "session-b"))
            (let ((session (acp-session-store--make-session
                            :id id :agent "test" :timestamp (current-time))))
              (with-temp-file (acp-session-store--session-file id)
                (insert (acp-session-store--serialize session))
                (insert "\n"))))
          (let ((ids (acp-session-store--list-sessions)))
            (should (member "session-a" ids))
            (should (member "session-b" ids))
            (should (= 2 (length ids)))))
      (delete-directory acp-session-store-directory t))))

(ert-deftest acp-session-store--search-sessions ()
  "Search sessions by query."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'elisp))
    (unwind-protect
        (progn
          (dolist (id '("debug-123" "feature-456" "debug-789"))
            (let ((session (acp-session-store--make-session
                            :id id :agent "test" :timestamp (current-time))))
              (with-temp-file (acp-session-store--session-file id)
                (insert (acp-session-store--serialize session))
                (insert "\n"))))
          (let ((results (acp-session-store--search-sessions "debug")))
            (should (= 2 (length results)))
            (should (member "debug-123" results))
            (should (member "debug-789" results))))
      (delete-directory acp-session-store-directory t))))

(ert-deftest acp-session-store-tag/adds-tag ()
  "Adding a tag to a session."
  (let ((acp-session-store-directory
         (make-temp-file "acp-sessions-test" t))
        (acp-session-store-format 'elisp))
    (unwind-protect
        (let ((session (acp-session-store--make-session
                        :id "tag-test"
                        :agent "test"
                        :timestamp (current-time)
                        :tags '("existing"))))
          (let ((file (acp-session-store--session-file "tag-test")))
            (with-temp-file file
              (insert (acp-session-store--serialize session))
              (insert "\n"))
            ;; Add a tag
            (let ((loaded (with-temp-buffer
                            (insert-file-contents file)
                            (acp-session-store--deserialize
                             (buffer-string)))))
              (let ((tags (plist-get loaded :tags)))
                (unless (member "new-tag" tags)
                  (plist-put loaded :tags (append tags '("new-tag"))))
                (with-temp-file file
                  (insert (acp-session-store--serialize loaded))
                  (insert "\n")))
              ;; Verify
              (let ((reloaded (with-temp-buffer
                                (insert-file-contents file)
                                (acp-session-store--deserialize
                                 (buffer-string)))))
                (should (member "existing" (plist-get reloaded :tags)))
                (should (member "new-tag" (plist-get reloaded :tags)))))))
      (delete-directory acp-session-store-directory t))))

(provide 'acp-session-store-tests)

;;; acp-session-store-tests.el ends here

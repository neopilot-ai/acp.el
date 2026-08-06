;;; acp-file-tree-tests.el --- Tests for acp-file-tree -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp-file-tree)

;;; Code:

(ert-deftest acp-file-tree--make-node/file ()
  "File node creation."
  (let ((node (acp-file-tree--make-node
               :name "test.el"
               :path "/tmp/test.el"
               :type 'file)))
    (should (equal (acp-file-tree--node-name node) "test.el"))
    (should (equal (acp-file-tree--node-path node) "/tmp/test.el"))
    (should (eq (acp-file-tree--node-type node) 'file))
    (should (null (acp-file-tree--node-children node)))))

(ert-deftest acp-file-tree--make-node/dir ()
  "Directory node creation."
  (let ((node (acp-file-tree--make-node
               :name "src"
               :path "/tmp/src"
               :type 'dir
               :children (list (acp-file-tree--make-node
                                :name "a.el" :path "/tmp/src/a.el" :type 'file))
               :expanded t)))
    (should (eq (acp-file-tree--node-type node) 'dir))
    (should (= 1 (length (acp-file-tree--node-children node))))
    (should (acp-file-tree--node-expanded node))))

(ert-deftest acp-file-tree--ignored-p ()
  "Ignored file detection."
  (should (acp-file-tree--ignored-p ".git"))
  (should (acp-file-tree--ignored-p "node_modules"))
  (should-not (acp-file-tree--ignored-p "src"))
  (should-not (acp-file-tree--ignored-p "README.md")))

(ert-deftest acp-file-tree--build-tree/ignores-hidden ()
  "Tree building ignores hidden directories."
  (let ((root (make-temp-file "acp-tree-test" t)))
    (unwind-protect
        (progn
          ;; Create test structure
          (make-directory (expand-file-name ".git" root) t)
          (make-directory (expand-file-name "src" root) t)
          (write-region "content" nil (expand-file-name "src/a.el" root))
          (write-region "content" nil (expand-file-name ".hidden" root))
          (let ((tree (acp-file-tree--build-tree root)))
            (should (eq (acp-file-tree--node-type tree) 'dir))
            ;; Should have only src, not .git
            (let ((children (acp-file-tree--node-children tree)))
              (should (= 1 (length children)))
              (should (equal (acp-file-tree--node-name (car children)) "src")))))
      (delete-directory root t))))

(ert-deftest acp-file-tree--build-tree/ignores-patterns ()
  "Tree building ignores file patterns."
  (let ((root (make-temp-file "acp-tree-test" t)))
    (unwind-protect
        (progn
          (write-region "compiled" nil (expand-file-name "test.elc" root))
          (write-region "source" nil (expand-file-name "test.el" root))
          (write-region "cache" nil (expand-file-name "__pycache__" root))
          (let ((tree (acp-file-tree--build-tree root)))
            (let ((children (acp-file-tree--node-children tree)))
              ;; Only test.el should be present
              (should (= 1 (length children)))
              (should (equal (acp-file-tree--node-name (car children)) "test.el")))))
      (delete-directory root t))))

(ert-deftest acp-file-tree--render-node/file ()
  "File node rendering."
  (let ((node (acp-file-tree--make-node
               :name "test.el"
               :path "/tmp/test.el"
               :type 'file)))
    (with-temp-buffer
      (acp-file-tree--render-node node 1)
      (should (string-match-p "test.el" (buffer-string))))))

(ert-deftest acp-file-tree--render-node/dir-collapsed ()
  "Collapsed directory rendering."
  (let ((node (acp-file-tree--make-node
               :name "src"
               :path "/tmp/src"
               :type 'dir
               :expanded nil)))
    (with-temp-buffer
      (acp-file-tree--render-node node 0)
      (should (string-match-p "\\[\\+\\]" (buffer-string)))
      (should (string-match-p "src" (buffer-string))))))

(ert-deftest acp-file-tree--render-node/dir-expanded ()
  "Expanded directory rendering shows children."
  (let ((node (acp-file-tree--make-node
               :name "src"
               :path "/tmp/src"
               :type 'dir
               :expanded t
               :children (list (acp-file-tree--make-node
                                :name "a.el" :path "/tmp/src/a.el" :type 'file)))))
    (with-temp-buffer
      (acp-file-tree--render-node node 0)
      (should (string-match-p "\\[-\\]" (buffer-string)))
      (should (string-match-p "a\\.el" (buffer-string))))))

(ert-deftest acp-file-tree-mode/is-derived-from-special ()
  "acp-file-tree-mode is derived from special-mode."
  (with-temp-buffer
    (acp-file-tree-mode)
    (should (derived-mode-p 'special-mode))))

(provide 'acp-file-tree-tests)

;;; acp-file-tree-tests.el ends here

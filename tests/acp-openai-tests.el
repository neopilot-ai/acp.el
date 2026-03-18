;;; acp-openai-tests.el --- Tests for acp-openai -*- lexical-binding: t; -*-

(require 'ert)
(require 'acp)
(require 'acp-openai)

;;; Code:

(ert-deftest acp-openai-default-model-id-test ()
  "Test that Codex config exposes default model id."
  (let ((default-model-id-fn
         (map-elt (acp-openai-make-codex-config) :default-model-id)))

    (let ((acp-openai-default-model-id nil))
      (should (null (funcall default-model-id-fn))))

    (let ((acp-openai-default-model-id "gpt-5.4/low"))
      (should (string= (funcall default-model-id-fn) "gpt-5.4/low")))

    (let ((acp-openai-default-model-id (lambda () "gpt-5.4/low")))
      (should (string= (funcall default-model-id-fn) "gpt-5.4/low")))))

(ert-deftest acp-openai-default-session-mode-id-test ()
  "Test that Codex config exposes default session mode id."
  (let ((default-session-mode-id-fn
         (map-elt (acp-openai-make-codex-config) :default-session-mode-id)))

    (let ((acp-openai-default-session-mode-id nil))
      (should (null (funcall default-session-mode-id-fn))))

    (let ((acp-openai-default-session-mode-id "full-access"))
      (should (string= (funcall default-session-mode-id-fn) "full-access")))))

(provide 'acp-openai-tests)
;;; acp-openai-tests.el ends here

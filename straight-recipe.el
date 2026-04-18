;; straight.el recipe for local development
;; Add to your Emacs config:

(straight-use-package
 '(acp :type git :host github :repo "neopilot-ai/acp.el"
               :files (:defaults "agents/*.el" "ui/*.el" "features/*.el")))

;; For local development, use this instead:
;; (add-to-list 'load-path "~/path/to/acp.el")
;; (add-to-list 'load-path "~/path/to/acp.el/agents")
;; (add-to-list 'load-path "~/path/to/acp.el/ui")
;; (add-to-list 'load-path "~/path/to/acp.el/features")
;; (require 'acp)

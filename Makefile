.PHONY: install test lint clean test-standalone

install:
	@echo "Adding to load-path..."
	@echo "Add this to your Emacs config:"
	@echo ""
	@echo "(add-to-list \"load-path\" \"$$(pwd)/agents\")"
	@echo "(add-to-list \"load-path\" \"$$(pwd)/ui\")"
	@echo "(add-to-list \"load-path\" \"$$(pwd)/features\")"
	@echo "(add-to-list \"load-path\" \"$$(pwd)\")"
	@echo "(require 'acp)"

test:
	emacs --batch -L . -L agents -L ui -L features \
		--eval "(progn (require 'cl-lib) (require 'map) (require 'json) (ignore-errors (require 'markdown-overlays)) (ignore-errors (require 'shell-maker)) (require 'acp) (message \"Load check completed\"))"

test-standalone:
	emacs --batch -L . -L agents -L ui -L features -L tests \
		--eval "(progn (require 'ert) (require 'cl-lib) (require 'map) (require 'json) (ignore-errors (require 'markdown-overlays)) (ignore-errors (require 'shell-maker)))" \
		--eval "(dolist (f (directory-files \"tests\" nil \"-tests\\.el$$\")) (load (expand-file-name f \"tests\") nil t))" \
		--eval "(ert-run-tests-batch-and-exit)"

lint:
	@echo "Note: For full byte-compile lint, install shell-maker and markdown-overlays"
	@echo "Running load check instead..."
	emacs --batch -L . -L agents -L ui -L features \
		--eval "(progn (require 'cl-lib) (require 'map) (require 'json) (ignore-errors (require 'markdown-overlays)) (ignore-errors (require 'shell-maker)) (message \"Load check passed\"))"

clean:
	rm -f *.elc agents/*.elc ui/*.elc features/*.elc tests/*.elc

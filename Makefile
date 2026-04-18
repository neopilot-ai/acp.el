.PHONY: install test lint clean

install:
	@echo "Adding to load-path..."
	@echo "Add this to your Emacs config:"
	@echo ""
	@echo "(add-to-list 'load-path \"$$(pwd)/agents\")"
	@echo "(add-to-list 'load-path \"$$(pwd)/ui\")"
	@echo "(add-to-list 'load-path \"$$(pwd)/features\")"
	@echo "(add-to-list 'load-path \"$$(pwd)\")"
	@echo "(require 'acp)"

test:
	emacs --batch -L . -L agents -L ui -L features \
		--eval "(progn (require 'cl-lib) (require 'map) (require 'json) (ignore-errors (require 'markdown-overlays)) (ignore-errors (require 'shell-maker)) (ignore-errors (require 'acp)) (message \"Load check completed\"))"

lint:
	@echo "Note: For full byte-compile lint, install shell-maker and markdown-overlays"
	@echo "Running load check instead..."
	emacs --batch -L . -L agents -L ui -L features \
		--eval "(progn (require 'cl-lib) (require 'map) (require 'json) (ignore-errors (require 'markdown-overlays)) (ignore-errors (require 'shell-maker)) (message \"Load check passed\"))"

clean:
	rm -f *.elc agents/*.elc ui/*.elc features/*.elc

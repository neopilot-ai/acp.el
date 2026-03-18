# ACP - Project Guidelines

## Local Installation

After cloning, add subdirectories to your `load-path`:

```elisp
(add-to-list 'load-path "~/path/to/acp.el/agents")
(add-to-list 'load-path "~/path/to/acp.el/ui")
(add-to-list 'load-path "~/path/to/acp.el/features")
(add-to-list 'load-path "~/path/to/acp.el")
(require 'acp)
```

Or use the Makefile:
```bash
make install  # Shows installation instructions
make test     # Test load
make lint     # Byte-compile check
make clean    # Remove .elc files
```

## Communication norms

PR and issue conversations are human relationships. The maintainer prefers
talking directly to humans.

When contributing:

- Write your own PR descriptions and issue comments. Don't have AI generate them.
- If you used AI to research something, summarize the findings in your own words
  and give your level of endorsement rather than pasting AI output verbatim.
  Concise, human-written summaries save the maintainer from having to parse
  lengthy generated text.
- Review all code in your PR yourself and vouch for its quality.

## Contributing

This is an Emacs Lisp project. See [CONTRIBUTING.org](CONTRIBUTING.org) for style guidelines, code checks, and testing. Please adhere to these guidelines.

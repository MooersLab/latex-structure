# latex-structure documentation

latex-structure brings the structure editing commands of Org mode to
LaTeX buffers in Emacs.  It refiles a section anywhere in a multi-file
document, shows one section in an indirect buffer, builds sparse
trees, and moves, indents, and outdents list items with the same
Meta-arrow keys that Org uses.

## Where to start

- [Getting started](getting-started.html) walks through the first five
  minutes.  The source is `docs/guides/getting-started.md`.
- [The manual](manual.html) covers every command, key, and option.
  The same manual is available in Emacs as Info.  Run `make info` and
  then type `C-u C-h i docs/latex-structure.info`.
- [The API reference](api.html) is generated from the docstrings.  The
  Markdown source is `docs/api/latex-structure-api.md`.

## Build these pages

```bash
make docs        # Info manual, HTML manual, and API reference
make docs-serve  # serve docs/site at http://localhost:8000
```

![Version](https://img.shields.io/static/v1?label=list-manager&message=1.1.0&color=brightcolor)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-26.1+-purple.svg)](https://www.gnu.org/software/emacs/)

# Org-style structure editing for LaTeX buffers in Emacs

I work both in org-mode and LaTeX documents every day.
Org mode has features that LaTeX lacks, and I miss them.
This is part of my attempt to add some of the best of Org mode to LaTeX.
This also makes it easier to jump between the two systems.

Org mode lets you refile a subtree anywhere, show one subtree in an indirect buffer, build a sparse tree, and reshape plain lists with the Meta-arrow keys. 
This package brings those commands to LaTeX. 
It treats `\section`, `\subsection`, and the other sectioning commands as Org headlines, and it treats the items of `itemize`, `enumerate`, and `description` as Org plain list items.

It is a companion to [latex-speed-commands](https://github.com/MooersLab/latex-speed-commands-el),
but it does not depend on it. Both work with AUCTeX (`LaTeX-mode`) and with the built-in `latex-mode`.

## Installation

Clone the repository and add it to your load path.

```elisp
(add-to-list 'load-path "~/path/to/latex-structure")
(require 'latex-structure)
(add-hook 'LaTeX-mode-hook #'latex-structure-mode) ; AUCTeX
(add-hook 'latex-mode-hook #'latex-structure-mode) ; built-in mode
```

With `use-package` and a local checkout:

```elisp
(use-package latex-structure
  :load-path "~/path/to/latex-structure"
  :hook ((LaTeX-mode latex-mode) . latex-structure-mode))
```

## Key bindings

The Meta-arrow keys act only on a heading line or inside a list item.
Everywhere else they keep their usual meaning, so `M-<left>` still moves back one word in body text.

| Key           | On a heading line         | In a list item               | Org analog              |
|---------------|---------------------------|------------------------------|-------------------------|
| `M-<up>`      | Move section up           | Move item up                 | `org-metaup`            |
| `M-<down>`    | Move section down         | Move item down               | `org-metadown`          |
| `M-<left>`    | Promote heading           | Outdent item                 | `org-metaleft`          |
| `M-<right>`   | Demote heading            | Indent item                  | `org-metaright`         |
| `M-S-<left>`  | Promote whole section     | Outdent item                 | `org-shiftmetaleft`     |
| `M-S-<right>` | Demote whole section      | Indent item                  | `org-shiftmetaright`    |

| Key         | Command                                   | Org analog                    |
|-------------|-------------------------------------------|-------------------------------|
| `C-c C-w`   | `latex-structure-refile`                  | `org-refile`                  |
| `C-u C-c C-w` | Jump to a heading anywhere in the document | `org-refile` with `C-u`     |
| `C-c M-w`   | `latex-structure-refile-copy`             | `org-refile-copy`             |
| `C-c C-x b` | `latex-structure-tree-to-indirect-buffer` | `org-tree-to-indirect-buffer` |
| `C-c /`     | `latex-structure-sparse-tree`             | `org-sparse-tree`             |
| `C-c -`     | `latex-structure-cycle-list-type` (in a list) | `org-cycle-list-bullet`   |

## Refiling across a book

`latex-structure-refile` offers every heading in every file of the document. 
It starts from the master file (`TeX-master` in AUCTeX, `tex-main-file` in the built-in mode, or the current file) and follows `\input`, `\include`, `\subfile`, `\import`, and `\subimport` in document order. 
Each file also offers a "top level" target.

The section becomes the target's last child. 
Its headings change rank to fit, so a `\section` refiled under another `\section` becomes a `\subsection`, and its subsections move down one rank too. 
Set `latex-structure-refile-adjust-levels` to nil to keep the levels.

A section never swallows `\end{document}`, the bibliography, or an `\include` line of the master file. 
See `latex-structure-section-boundary-regexp`.

Refiling into another chapter file visits that file and leaves it modified but unsaved, so you can review the change before saving.

## List items

The item commands understand nested lists. 
An item carries its own nested lists with it when it moves.

* Indenting an item makes it the last child of the previous item.
  It joins the nested list that ends the previous item, or a new list of the same type.
* Outdenting an item makes it the sibling that follows its parent item.
  A nested list left empty is removed.
* `C-c -` cycles the innermost list through `itemize`, `enumerate`, and `description`.
  With `C-u` it asks for the type.

Add enumitem clones or custom lists to `latex-structure-list-environments`. 
The list text is reindented with the major mode's indentation after an indent or outdent. 
Set `latex-structure-reindent` to nil to turn that off.

## Speed commands

If you also use latex-speed-commands, add single-key commands after both packages load:

```elisp
(with-eval-after-load 'latex-speed-commands
  (require 'latex-structure)
  (latex-structure-speed-commands-setup))
```

At the beginning of a heading line, this adds:

| Key | Command                                   |
|-----|-------------------------------------------|
| `W` | Refile the section                        |
| `g` | Jump to any heading in the document       |
| `T` | Show the section in an indirect buffer    |
| `/` | Sparse tree (replaces `occur`)            |

At the beginning of an `\item` line (column zero or just before `\item`) it adds:

| Key | Command                 |
|-----|-------------------------|
| `n` | Next item               |
| `p` | Previous item           |
| `U` | Move item up            |
| `D` | Move item down          |
| `l` | Outdent item            |
| `r` | Indent item             |
| `-` | Cycle the list type     |

Change the keys with `latex-structure-speed-commands` and
`latex-structure-item-speed-commands`.

## Customization

Run `M-x customize-group RET latex-structure RET` to see all options.
The most useful are `latex-structure-section-levels`,
`latex-structure-list-environments`,
`latex-structure-refile-adjust-levels`, and
`latex-structure-indirect-buffer-display`.

## Documentation

* [Getting started](docs/guides/getting-started.md) takes five minutes.
* The manual is `docs/latex-structure.org`.  Run `make info` and then
  `C-u C-h i docs/latex-structure.info` to read it in Emacs, or run
  `make docs` and open `docs/site/manual.html`.
* The [API reference](docs/api/latex-structure-api.md) is generated
  from the docstrings by `make docs-api`.

## Development

```sh
make install-test-deps   # clone package-lint, AUCTeX, undercover
make lint                # byte-compile, checkdoc, package-lint
make test                # run the ERT tests
make coverage            # line coverage with undercover
make docs                # Info manual, HTML manual, API reference
make docs-check          # docstring coverage
```
## Sources of funding

- NIH: R01 CA242845
- NIH: R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel)
- NIH: P20 GM103640 and P30 GM145423 (PI: A. West)


## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

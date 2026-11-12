# Getting started with latex-structure

This guide takes about five minutes.  You need Emacs 28.1 or newer.
AUCTeX is optional.

## Turn the mode on

Add one hook per LaTeX mode that you use.

```elisp
(require 'latex-structure)
(add-hook 'LaTeX-mode-hook #'latex-structure-mode) ; AUCTeX
(add-hook 'latex-mode-hook #'latex-structure-mode) ; built-in
```

Open a `.tex` file.  The mode line shows `Struct`.

## Try the keys on one file

Copy this small document into a buffer.

```latex
\documentclass{book}
\begin{document}
\chapter{Introduction}
\section{Alpha}
Alpha text.
\section{Beta}
Beta text.
\begin{itemize}
\item one
\item two
\item three
\end{itemize}
\chapter{Methods}
Methods text.
\end{document}
```

1. Put point anywhere on `\section{Beta}` and press `M-<up>`.  Beta
   moves above Alpha.  Press `M-<down>` to move it back.
2. Press `M-<right>`.  The heading becomes `\subsection{Beta}`.  Press
   `M-<left>` to promote it again.
3. Press `C-c C-w` and choose the target that ends in `Methods`.  Beta
   and its list move to the end of the Methods chapter.
4. Put point on `\item two` and press `M-<right>`.  The item moves into
   a new nested `itemize` inside `\item one`.  Press `M-<left>` to move
   it back out.
5. Press `C-c -` inside the list.  The list becomes `enumerate`.
6. Press `C-c /` and type `text`.  Only the matching lines and their
   headings stay visible.  Press `C-c /` and `RET` with an empty regexp
   to show everything again.

## Refile across chapter files

Make a small book in a new folder.

`main.tex`:

```latex
\documentclass{book}
\begin{document}
\include{ch1}
\include{ch2}
\end{document}
```

`ch1.tex`:

```latex
\chapter{One}
\section{Moving}
This section will move.
```

`ch2.tex`:

```latex
\chapter{Two}
\section{Staying}
This section stays.
```

1. Open `ch1.tex`.  With AUCTeX, answer `main` when it asks for the
   master file, or add `%%% TeX-master: "main"` to the local variables.
2. Put point on `\section{Moving}` and press `C-c C-w`.
3. Choose `ch2.tex: Two / Staying`.  The section moves to `ch2.tex` and
   becomes `\subsection{Moving}` under `Staying`.
4. `ch2.tex` is now open and modified.  Review it and save it.

Press `C-u C-c C-w` to jump to any heading of the book without moving
anything.

## Next steps

- Read the manual with `C-u C-h i docs/latex-structure.info` after
  `make info`, or open `docs/site/manual.html` after `make docs`.
- If you use latex-speed-commands, call
  `latex-structure-speed-commands-setup` to get single-key refiling and
  list item commands.
- Add your own list environments to
  `latex-structure-list-environments`.

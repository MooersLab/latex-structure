;;; latex-structure-test.el --- Tests for latex-structure -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; This file is not part of GNU Emacs.

;;; Commentary:

;; ERT tests for latex-structure.  Run them with `make test'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'tex-mode)

(when (and (getenv "LST_COVERAGE") (require 'undercover nil t))
  (eval '(undercover "latex-structure.el"
                     (:report-format 'lcov)
                     (:report-file "coverage.lcov")
                     (:send-report nil))
        t))

(require 'latex-structure)

(defvar latex-speed-commands)
(defvar latex-speed-commands-activate-functions)
(defvar TeX-master)

(defconst lst-test-document
  "\\documentclass{book}
\\begin{document}
\\chapter{Introduction}
Intro text.
\\section{Alpha}
Alpha text.
\\subsection{Alpha One}
A1 text.
\\section{Beta}
Beta text.
\\chapter{Methods}
Methods text.
\\end{document}
"
  "A small book used by the section tests.")

(defconst lst-test-list
  "\\begin{itemize}
\\item one
\\item two
\\begin{enumerate}
\\item two-a
\\end{enumerate}
\\item three
\\end{itemize}
"
  "A list with a nested list used by the item tests.")

(defmacro lst-with-buffer (content &rest body)
  "Run BODY in a `latex-mode' buffer holding CONTENT.
Point starts at the beginning of the buffer."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (let ((latex-mode-hook nil) (tex-mode-hook nil) (text-mode-hook nil)
           (latex-structure-reindent nil))
       (latex-mode)
       (insert ,content)
       (goto-char (point-min))
       ,@body)))

(defun lst-goto (string)
  "Move point to the beginning of the line that contains STRING."
  (goto-char (point-min))
  (search-forward string)
  (beginning-of-line))

(defmacro lst-with-project (files &rest body)
  "Write FILES into a temporary directory and run BODY there.
FILES is an alist of (NAME . CONTENT).  The variable `dir' is bound
to the directory in BODY.  Buffers visiting the files are killed
afterward."
  (declare (indent 1) (debug t))
  `(let* ((dir (file-name-as-directory (make-temp-file "lst" t)))
          (latex-mode-hook nil) (tex-mode-hook nil) (text-mode-hook nil)
          (auto-mode-alist (cons '("\\.tex\\'" . latex-mode) auto-mode-alist)))
     (unwind-protect
         (progn
           (dolist (f ,files)
             (with-temp-file (expand-file-name (car f) dir)
               (insert (cdr f))))
           ,@body)
       (dolist (f ,files)
         (let ((b (find-buffer-visiting (expand-file-name (car f) dir))))
           (when b
             (with-current-buffer b (set-buffer-modified-p nil))
             (kill-buffer b))))
       (delete-directory dir t))))


;;;; Section model

(ert-deftest lst-section-bounds ()
  (lst-with-buffer lst-test-document
    (lst-goto "A1 text")
    (pcase-let ((`(,beg ,end ,level) (latex-structure-section-bounds)))
      (should (= level 3))
      (should (string-prefix-p "\\subsection{Alpha One}"
                               (buffer-substring beg end)))
      (should (string-suffix-p "A1 text.\n" (buffer-substring beg end))))
    (lst-goto "Methods text")
    (pcase-let ((`(,beg ,end ,_) (latex-structure-section-bounds)))
      (should-not (string-match-p "end{document}"
                                  (buffer-substring beg end))))))

(ert-deftest lst-section-before-first-heading ()
  (lst-with-buffer lst-test-document
    (should-error (latex-structure-section-bounds) :type 'user-error)))

(ert-deftest lst-heading-title-with-short-title ()
  (lst-with-buffer "\\section[Short]{Long {Nested} Title}\n"
    (should (equal (latex-structure-heading-title (point-min))
                   "Long {Nested} Title"))))

(ert-deftest lst-ancestors ()
  (lst-with-buffer lst-test-document
    (lst-goto "A1 text")
    (let ((titles (mapcar #'latex-structure-heading-title
                          (latex-structure--ancestors (point)))))
      (should (equal titles '("Introduction" "Alpha" "Alpha One"))))))

(ert-deftest lst-move-section-up-and-down ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-move-section-up)
    (should (looking-at "\\\\section{Beta}"))
    (should (< (save-excursion (search-forward "Beta text") (point))
               (save-excursion (search-forward "Alpha One") (point))))
    (latex-structure-move-section-down)
    (should (looking-at "\\\\section{Beta}"))
    (should (> (point) (save-excursion (lst-goto "A1 text") (point))))))

(ert-deftest lst-move-section-past-limit ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Alpha}")
    (should-error (latex-structure-move-section-up) :type 'user-error)))

(ert-deftest lst-promote-demote ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Alpha}")
    (latex-structure-demote-section)
    (should (search-forward "\\subsection{Alpha}" nil t))
    (should (search-forward "\\subsubsection{Alpha One}" nil t))
    (lst-goto "\\subsection{Alpha}")
    (latex-structure-promote-heading)
    (should (looking-at "\\\\section{Alpha}"))
    (latex-structure-demote-heading)
    (should (looking-at "\\\\subsection{Alpha}"))
    (latex-structure-promote-section)
    (should (looking-at "\\\\section{Alpha}"))
    (should (save-excursion (search-forward "\\subsection{Alpha One}" nil t)))))

(ert-deftest lst-promote-all-or-nothing ()
  (lst-with-buffer "\\part{P}\n\\chapter{C}\n"
    (should-error (latex-structure-promote-heading) :type 'user-error)
    (should (equal (buffer-string) "\\part{P}\n\\chapter{C}\n"))))

(ert-deftest lst-shift-text ()
  (should (equal (latex-structure--shift-text
                  "\\section{A}\n\\subsection{B}\n" 1)
                 "\\subsection{A}\n\\subsubsection{B}\n")))


;;;; Project files and targets

(ert-deftest lst-project-files ()
  (lst-with-project
      '(("main.tex" . "\\documentclass{book}\n\\begin{document}\n\\include{ch1}\n% \\input{skip}\n\\input{sub/ch2.tex}\n\\end{document}\n")
        ("ch1.tex" . "\\chapter{One}\n\\input{ch1a}\n")
        ("ch1a.tex" . "\\section{One A}\n")
        ("skip.tex" . "\\chapter{Skip}\n"))
    (make-directory (expand-file-name "sub" dir))
    (with-temp-file (expand-file-name "sub/ch2.tex" dir)
      (insert "\\chapter{Two}\n"))
    (with-current-buffer (find-file-noselect (expand-file-name "main.tex" dir))
      (should (equal (mapcar (lambda (f) (file-relative-name f dir))
                             (latex-structure-project-files))
                     '("main.tex" "ch1.tex" "ch1a.tex" "sub/ch2.tex")))
      (kill-buffer))))

(ert-deftest lst-master-from-tex-master ()
  (lst-with-project
      '(("main.tex" . "\\begin{document}\n\\include{ch1}\n\\end{document}\n")
        ("ch1.tex" . "\\chapter{One}\n"))
    (with-current-buffer (find-file-noselect (expand-file-name "ch1.tex" dir))
      (setq-local TeX-master "main")
      (should (equal (latex-structure-master-file)
                     (expand-file-name "main.tex" dir)))
      (should (= (length (latex-structure-project-files)) 2)))))

(ert-deftest lst-targets-disambiguate ()
  (lst-with-buffer "\\section{Same}\n\\section{Same}\n"
    (let ((names (mapcar #'car (latex-structure--targets))))
      (should (cl-some (lambda (n) (string-suffix-p ": Same" n)) names))
      (should (cl-some (lambda (n) (string-suffix-p "Same <2>" n)) names)))))


;;;; Refile and goto

(defun lst-target (suffix)
  "Return the refile target whose display ends with SUFFIX."
  (cl-find-if (lambda (tg) (string-suffix-p suffix (car tg)))
              (latex-structure--targets)))

(ert-deftest lst-refile-within-buffer-adjusts-levels ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-refile nil (lst-target ": Methods"))
    (should (= (how-many "\\\\section{Beta}" (point-min) (point-max)) 1))
    (lst-goto "\\chapter{Methods}")
    (should (search-forward "\\section{Beta}" nil t))
    (should (search-forward "\\end{document}" nil t))))

(ert-deftest lst-refile-under-section-becomes-subsection ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-refile nil (lst-target "Introduction / Alpha"))
    (lst-goto "\\subsection{Alpha One}")
    (should (search-forward "\\subsection{Beta}" nil t))))

(ert-deftest lst-refile-into-previous-sibling ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-refile nil (lst-target "Introduction / Alpha"))
    (should (= (how-many "Beta text" (point-min) (point-max)) 1))))

(ert-deftest lst-refile-no-level-adjust ()
  (lst-with-buffer lst-test-document
    (let ((latex-structure-refile-adjust-levels nil))
      (lst-goto "\\section{Beta}")
      (latex-structure-refile nil (lst-target "Introduction / Alpha"))
      (should (= (how-many "\\\\section{Beta}" (point-min) (point-max)) 1)))))

(ert-deftest lst-refile-into-itself-fails ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Alpha}")
    (should-error (latex-structure-refile nil (lst-target "Alpha / Alpha One"))
                  :type 'user-error)))

(ert-deftest lst-refile-copy ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-refile-copy (lst-target ": Methods"))
    (should (= (how-many "Beta text" (point-min) (point-max)) 2))))

(ert-deftest lst-refile-top-level-goes-before-end-document ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Beta}")
    (latex-structure-refile nil (lst-target " (top level)"))
    (goto-char (point-max))
    (should (search-backward "\\section{Beta}" nil t))
    (should (search-forward "\\end{document}" nil t))))

(ert-deftest lst-refile-across-files ()
  (lst-with-project
      '(("main.tex" . "\\begin{document}\n\\include{ch1}\n\\include{ch2}\n\\end{document}\n")
        ("ch1.tex" . "\\chapter{One}\nOne text.\n\\section{Moving}\nMoving text.\n")
        ("ch2.tex" . "\\chapter{Two}\nTwo text.\n\\section{Stay}\nStay text.\n"))
    (let ((ch1 (find-file-noselect (expand-file-name "ch1.tex" dir))))
      (with-current-buffer ch1
        (setq-local TeX-master "main")
        (lst-goto "\\section{Moving}")
        (latex-structure-refile nil (lst-target "ch2.tex: Two / Stay"))
        (should (equal (buffer-string) "\\chapter{One}\nOne text.\n")))
      (with-current-buffer (find-buffer-visiting (expand-file-name "ch2.tex" dir))
        (should (equal (buffer-string)
                       (concat "\\chapter{Two}\nTwo text.\n\\section{Stay}\n"
                               "Stay text.\n\\subsection{Moving}\n"
                               "Moving text.\n")))))))

(ert-deftest lst-refile-with-prefix-only-jumps ()
  (lst-with-buffer lst-test-document
    (let ((before (buffer-string)))
      (lst-goto "\\section{Beta}")
      (latex-structure-refile '(4) (lst-target ": Methods"))
      (should (looking-at "\\\\chapter{Methods}"))
      (should (equal before (buffer-string))))))


;;;; Indirect buffer

(ert-deftest lst-tree-to-indirect-buffer ()
  (lst-with-buffer lst-test-document
    (lst-goto "\\section{Alpha}")
    (let* ((latex-structure-indirect-buffer-display 'current-window)
           (buf (save-window-excursion
                  (latex-structure-tree-to-indirect-buffer))))
      (unwind-protect
          (with-current-buffer buf
            (should (buffer-base-buffer))
            (should (string-prefix-p "\\section{Alpha}" (buffer-string)))
            (should-not (string-match-p "Beta" (buffer-string))))
        (kill-buffer buf)))))


;;;; Sparse tree

(ert-deftest lst-sparse-tree ()
  (lst-with-buffer lst-test-document
    (should (= (latex-structure-sparse-tree "A1") 1))
    (let ((visible (lambda (s)
                     (save-excursion
                       (goto-char (point-min))
                       (search-forward s)
                       (not (invisible-p (match-beginning 0)))))))
      (should (funcall visible "A1 text"))
      (should (funcall visible "\\subsection{Alpha One}"))
      (should (funcall visible "\\section{Alpha}"))
      (should (funcall visible "\\chapter{Introduction}"))
      (should-not (funcall visible "Beta text"))
      (should-not (funcall visible "\\documentclass")))
    (latex-structure-sparse-tree-remove)
    (should-not latex-structure--sparse-overlays)
    (should (= (latex-structure-sparse-tree "nomatchatall") 0))
    (should (= (latex-structure-sparse-tree "") 0))))


;;;; List items

(ert-deftest lst-item-at ()
  (lst-with-buffer lst-test-list
    (lst-goto "two-a")
    (let ((info (latex-structure-item-at)))
      (should (equal (plist-get (plist-get info :list) :name) "enumerate")))
    (lst-goto "\\begin{enumerate}")
    (let ((info (latex-structure-item-at)))
      (should (equal (plist-get (plist-get info :list) :name) "itemize"))
      (should (= (plist-get info :index) 1)))
    (goto-char (point-min))
    (should-not (latex-structure-item-at))))

(ert-deftest lst-item-ignores-itemsep ()
  (lst-with-buffer "\\begin{itemize}\\itemsep0pt\n\\item a\n\\end{itemize}\n"
    (lst-goto "\\item a")
    (should (= (length (plist-get (latex-structure-item-at) :items)) 1))))

(ert-deftest lst-move-item-up-down ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item three")
    (latex-structure-move-item-up)
    (should (looking-at "\\\\item three"))
    (should (equal (buffer-string)
                   "\\begin{itemize}
\\item one
\\item three
\\item two
\\begin{enumerate}
\\item two-a
\\end{enumerate}
\\end{itemize}
"))
    (latex-structure-move-item-down)
    (should (looking-at "\\\\item three"))
    (should (equal (buffer-string) lst-test-list))
    (should-error (latex-structure-move-item-down) :type 'user-error)))

(ert-deftest lst-next-previous-item ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item one")
    (latex-structure-next-item)
    (should (looking-at "\\\\item two"))
    (latex-structure-next-item)
    (should (looking-at "\\\\item three"))
    (should-error (latex-structure-next-item) :type 'user-error)
    (latex-structure-previous-item)
    (should (looking-at "\\\\item two"))))

(ert-deftest lst-indent-item-new-list ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item two")
    (latex-structure-indent-item)
    (should (looking-at "\\\\item two"))
    (should (equal (buffer-string)
                   "\\begin{itemize}
\\item one
\\begin{itemize}
\\item two
\\begin{enumerate}
\\item two-a
\\end{enumerate}
\\end{itemize}
\\item three
\\end{itemize}
"))))

(ert-deftest lst-indent-item-into-existing-list ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item three")
    (latex-structure-indent-item)
    (should (equal (buffer-string)
                   "\\begin{itemize}
\\item one
\\item two
\\begin{enumerate}
\\item two-a
\\item three
\\end{enumerate}
\\end{itemize}
"))))

(ert-deftest lst-indent-first-item-fails ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item one")
    (should-error (latex-structure-indent-item) :type 'user-error)))

(ert-deftest lst-outdent-only-item-removes-list ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item two-a")
    (latex-structure-outdent-item)
    (should (looking-at "\\\\item two-a"))
    (should (equal (buffer-string)
                   "\\begin{itemize}
\\item one
\\item two
\\item two-a
\\item three
\\end{itemize}
"))))

(ert-deftest lst-indent-then-outdent-round-trip ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item three")
    (latex-structure-indent-item)
    (latex-structure-outdent-item)
    (should (equal (buffer-string) lst-test-list))))

(ert-deftest lst-outdent-top-level-fails ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item one")
    (should-error (latex-structure-outdent-item) :type 'user-error)))

(ert-deftest lst-cycle-list-type ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item one")
    (should (equal (latex-structure-cycle-list-type) "enumerate"))
    (goto-char (point-min))
    (should (looking-at "\\\\begin{enumerate}"))
    (should (string-suffix-p "\\end{enumerate}\n" (buffer-string)))
    (lst-goto "two-a")
    (should (equal (latex-structure-cycle-list-type) "description"))
    (should (equal (latex-structure-cycle-list-type) "itemize"))))


;;;; Meta-arrow dispatch and key map

(ert-deftest lst-meta-dispatch ()
  (lst-with-buffer (concat lst-test-document lst-test-list)
    (lst-goto "\\section{Beta}")
    (forward-char 3)
    (should (eq (latex-structure--context) 'heading))
    (latex-structure-metaup)
    (should (save-excursion (beginning-of-line)
                            (looking-at "\\\\section{Beta}")))
    (lst-goto "\\item three")
    (should (eq (latex-structure--context) 'item))
    (latex-structure-metaup)
    (should (looking-at "\\\\item three"))
    (lst-goto "Intro text")
    (should (eq (latex-structure--context) nil))
    (should-error (latex-structure-metaup) :type 'user-error)))

(ert-deftest lst-keymap-falls-through ()
  (lst-with-buffer lst-test-document
    (latex-structure-mode 1)
    (lst-goto "Intro text")
    (should-not (eq (key-binding [M-up]) 'latex-structure-metaup))
    (lst-goto "\\section{Alpha}")
    (should (eq (key-binding [M-up]) 'latex-structure-metaup))
    (should (eq (key-binding (kbd "C-c C-w")) 'latex-structure-refile))))


;;;; Speed command integration

(ert-deftest lst-item-speed-activate ()
  (lst-with-buffer "\\begin{itemize}\n  \\item one\n\\end{itemize}\n"
    (lst-goto "\\item one")
    (should (eq (latex-structure-item-speed-activate "U")
                'latex-structure-move-item-up))
    (skip-chars-forward " ")
    (should (latex-structure-at-item-line-p))
    (forward-char 1)
    (should-not (latex-structure-item-speed-activate "U"))))

(ert-deftest lst-speed-commands-setup ()
  (let ((latex-speed-commands '(("n" . next-line) ("/" . occur)))
        (latex-speed-commands-activate-functions nil))
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t)))
      (latex-structure-speed-commands-setup)
      (latex-structure-speed-commands-setup))
    (should (eq (cdr (assoc "/" latex-speed-commands))
                'latex-structure-sparse-tree))
    (should (= (cl-count "W" latex-speed-commands
                         :key #'car :test #'equal)
               1))
    (should (memq #'latex-structure-item-speed-activate
                  latex-speed-commands-activate-functions))))

(ert-deftest lst-goto-other-file-and-subimport ()
  (lst-with-project
      '(("main.tex" . "\\begin{document}\n\\subimport{parts/}{p1}\n\\end{document}\n"))
    (make-directory (expand-file-name "parts" dir))
    (with-temp-file (expand-file-name "parts/p1.tex" dir)
      (insert "\\chapter{Part One}\nText.\n"))
    (with-current-buffer (find-file-noselect (expand-file-name "main.tex" dir))
      (save-window-excursion
        (latex-structure-goto (lst-target "p1.tex: Part One"))
        (should (looking-at "\\\\chapter{Part One}"))
        (should (string-suffix-p "parts/p1.tex" (buffer-file-name))))
      (kill-buffer (find-buffer-visiting (expand-file-name "parts/p1.tex" dir))))))

(ert-deftest lst-refile-to-empty-file-top-level ()
  (lst-with-project
      '(("main.tex" . "\\begin{document}\n\\chapter{Here}\n\\section{Mover}\nM.\n\\include{empty}\n\\end{document}\n")
        ("empty.tex" . "% nothing yet\n"))
    (with-current-buffer (find-file-noselect (expand-file-name "main.tex" dir))
      (lst-goto "\\section{Mover}")
      (latex-structure-refile nil (lst-target "empty.tex (top level)"))
      (with-current-buffer (find-buffer-visiting (expand-file-name "empty.tex" dir))
        (should (equal (buffer-string) "% nothing yet\n\\section{Mover}\nM.\n"))))))

(ert-deftest lst-indirect-buffer-reuse ()
  (lst-with-buffer lst-test-document
    (let ((latex-structure-indirect-buffer-display 'current-window)
          first second)
      (save-window-excursion
        (save-current-buffer
          (lst-goto "\\section{Alpha}")
          (setq first (latex-structure-tree-to-indirect-buffer)))
        (save-current-buffer
          (lst-goto "\\section{Beta}")
          (setq second (latex-structure-tree-to-indirect-buffer))))
      (should-not (buffer-live-p first))
      (should (buffer-live-p second))
      (kill-buffer second))))

(ert-deftest lst-cycle-list-type-with-prefix ()
  (lst-with-buffer lst-test-list
    (lst-goto "\\item one")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "description")))
      (should (equal (latex-structure-cycle-list-type '(4)) "description")))))

(ert-deftest lst-mode-toggle-removes-sparse-tree ()
  (lst-with-buffer lst-test-document
    (latex-structure-mode 1)
    (latex-structure-sparse-tree "A1")
    (should latex-structure--sparse-overlays)
    (latex-structure-mode -1)
    (should-not latex-structure--sparse-overlays)))

(provide 'latex-structure-test)
;;; latex-structure-test.el ends here

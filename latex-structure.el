;;; latex-structure.el --- Org-style structure editing for LaTeX -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: tex, outlines, convenience
;; URL: https://github.com/MooersLab/latex-structure
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package ports the structure editing commands of Org mode to
;; LaTeX buffers.  It treats sectioning commands such as \section and
;; \subsection as Org headlines, and items of itemize, enumerate, and
;; description environments as Org plain list items.
;;
;; The main commands are the following.
;;
;;   * `latex-structure-refile' moves the current section under
;;     another section, in this file or in any file reached from the
;;     master file through \input, \include, \subfile, or \import.
;;     Heading levels are adjusted so that the section becomes a
;;     child of its new parent.  This is the analog of `org-refile'.
;;     With a prefix argument it only jumps to the chosen heading.
;;
;;   * `latex-structure-goto' jumps to any heading in the project.
;;
;;   * `latex-structure-tree-to-indirect-buffer' shows the current
;;     section alone in an indirect buffer, like
;;     `org-tree-to-indirect-buffer'.
;;
;;   * `latex-structure-sparse-tree' hides everything except the lines
;;     that match a regexp and the headings above them, like
;;     `org-sparse-tree'.
;;
;;   * The item commands move a list item up or down, indent it into
;;     a nested list, outdent it, and cycle the list environment
;;     between itemize, enumerate, and description.
;;
;; The minor mode `latex-structure-mode' binds these commands to the
;; keys that Org uses.  M-<up>, M-<down>, M-<left>, and M-<right> act
;; on a heading line or on a list item and keep their usual meaning
;; elsewhere.
;;
;; Quick start:
;;
;;   (require 'latex-structure)
;;   (add-hook 'LaTeX-mode-hook #'latex-structure-mode) ; AUCTeX
;;   (add-hook 'latex-mode-hook #'latex-structure-mode) ; built-in
;;
;; If you also use latex-speed-commands, call
;; `latex-structure-speed-commands-setup' after both packages are
;; loaded to add single-key speed commands for refiling, sparse trees,
;; and list items.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar TeX-master)
(defvar tex-main-file)
(defvar latex-speed-commands)
(defvar latex-speed-commands-activate-functions)


;;;; Customization

(defgroup latex-structure nil
  "Org-style structure editing for LaTeX."
  :group 'tex
  :prefix "latex-structure-"
  :link '(url-link :tag "Home page"
                   "https://github.com/MooersLab/latex-structure"))

(defcustom latex-structure-section-levels
  '(("part" . 0)
    ("chapter" . 1)
    ("section" . 2)
    ("subsection" . 3)
    ("subsubsection" . 4)
    ("paragraph" . 5)
    ("subparagraph" . 6))
  "Alist of LaTeX sectioning commands and their outline levels.
Each element has the form (NAME . LEVEL) where NAME is the command
name without the backslash.  A smaller LEVEL is a higher rank.
Promotion, demotion, and refiling move between neighboring entries
of this alist after sorting it by LEVEL.  The default matches
`latex-speed-commands-section-levels'."
  :type '(alist :key-type (string :tag "Command")
                :value-type (integer :tag "Level"))
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-section-boundary-regexp
  (concat "^[ \t]*\\\\\\(?:"
          "end[ \t]*{document}"
          "\\|appendix\\b"
          "\\|frontmatter\\b"
          "\\|mainmatter\\b"
          "\\|backmatter\\b"
          "\\|bibliography{"
          "\\|printbibliography\\b"
          "\\|include[ \t]*{"
          "\\)")
  "Regexp for lines that end every section that precedes them.
A section normally extends up to the next heading of the same or a
higher rank.  A line that matches this regexp also ends it, so that
moving or refiling a section never carries \\end{document}, the
bibliography, or an \\include line of the master file along.  The
regexp must not contain capturing groups."
  :type 'regexp
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-list-environments
  '("itemize" "enumerate" "description")
  "Names of environments whose \\item lines are list items.
Add the names of enumitem clones or custom lists here."
  :type '(repeat string)
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-list-cycle
  '("itemize" "enumerate" "description")
  "Environment names visited in turn by `latex-structure-cycle-list-type'.
This is the analog of the bullet cycle of `org-cycle-list-bullet'."
  :type '(repeat string)
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-reindent t
  "Non-nil means reindent list text after an item is indented or outdented."
  :type 'boolean
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-refile-adjust-levels t
  "Non-nil means refiling changes heading levels to fit the target.
A section refiled under a target heading becomes a child of that
heading, so a \\section refiled under another \\section turns into
a \\subsection, and its subsections move down one rank as well.
When nil, the section keeps its levels."
  :type 'boolean
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-refile-include-commented nil
  "Non-nil means commented-out headings are offered as refile targets."
  :type 'boolean
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-include-regexp
  (concat "\\\\\\(?:input\\|include\\|subfile\\)[ \t]*{\\([^}\n]+\\)}"
          "\\|\\\\\\(sub\\)?import\\*?[ \t]*{\\([^}\n]*\\)}[ \t]*{\\([^}\n]+\\)}")
  "Regexp for commands that pull another file into the document.
Group 1 is the file of \\input, \\include, or \\subfile.  For
\\import and \\subimport, group 2 is the sub prefix, group 3 the
directory, and group 4 the file."
  :type 'regexp
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-indirect-buffer-display 'other-window
  "How `latex-structure-tree-to-indirect-buffer' shows the new buffer.
This is the analog of `org-indirect-buffer-display'."
  :type '(choice (const :tag "In another window" other-window)
                 (const :tag "In the current window" current-window)
                 (const :tag "In a new frame" new-frame))
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-lighter " Struct"
  "Mode line lighter for `latex-structure-mode'."
  :type '(choice (const :tag "None" nil) string)
  :package-version '(latex-structure . "0.1.0"))

(defface latex-structure-sparse-match
  '((t :inherit highlight))
  "Face for the matches that `latex-structure-sparse-tree' highlights."
  :group 'latex-structure
  :package-version '(latex-structure . "0.1.0"))


;;;; Low-level parsing

(defconst latex-structure--env-token-regexp
  "\\\\\\(begin\\|end\\)[ \t]*{\\([^}\n]*\\)}"
  "Regexp for a \\begin{NAME} or \\end{NAME} token.
Group 1 is begin or end and group 2 the environment name.")

(defconst latex-structure--item-token-regexp
  (concat "\\\\\\(?:\\(begin\\|end\\)[ \t]*{\\([^}\n]*\\)}"
          "\\|\\(item\\)\\_>\\)")
  "Regexp for an environment token or an \\item token.
Groups 1 and 2 are as in `latex-structure--env-token-regexp'.
Group 3 matches only for \\item.")

(defvar latex-structure--heading-regexp-cache nil
  "Cons of the levels alist and the heading regexp built from it.")

(defun latex-structure-heading-regexp ()
  "Return the regexp that matches a heading line.
Group 1 is the indentation, group 2 an optional comment prefix,
group 3 the command name, and group 4 the optional star."
  (unless (equal (car latex-structure--heading-regexp-cache)
                 latex-structure-section-levels)
    (setq latex-structure--heading-regexp-cache
          (cons (copy-tree latex-structure-section-levels)
                (concat "^\\([ \t]*\\)\\(%+[ \t]*\\)?\\\\\\("
                        (regexp-opt
                         (mapcar #'car latex-structure-section-levels))
                        "\\)\\(\\*\\)?[ \t]*[[{]"))))
  (cdr latex-structure--heading-regexp-cache))

(defun latex-structure--level (name)
  "Return the outline level of the sectioning command NAME."
  (cdr (assoc name latex-structure-section-levels)))

(defun latex-structure--looking-at-heading ()
  "Return non-nil when the text after point is a heading line.
Point must be at the beginning of a line.  The match data is set."
  (and (bolp) (looking-at (latex-structure-heading-regexp))))

(defun latex-structure-on-heading-line-p ()
  "Return non-nil when point is anywhere on a heading line."
  (save-excursion
    (save-match-data
      (beginning-of-line)
      (latex-structure--looking-at-heading))))

(defun latex-structure--in-comment-p (pos)
  "Return non-nil when POS follows an unescaped percent sign on its line."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (let ((limit pos))
        (goto-char (line-beginning-position))
        (re-search-forward "\\(?:^\\|[^\\]\\)\\(?:\\\\\\\\\\)*%" limit t)))))

(defun latex-structure--heading-start ()
  "Return the start of the heading line at or before point, or nil."
  (save-excursion
    (save-match-data
      (end-of-line)
      (when (re-search-backward (latex-structure-heading-regexp) nil t)
        (match-beginning 0)))))

(defun latex-structure--heading-level-at (pos)
  "Return the level of the heading at POS, or nil."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (when (latex-structure--looking-at-heading)
        (latex-structure--level (match-string-no-properties 3))))))

(defun latex-structure-section-end (beg level)
  "Return the end of the section of LEVEL with its heading at BEG.
The end is the start of the next heading of LEVEL or a higher rank,
the start of a line matching
`latex-structure-section-boundary-regexp', or the end of the
buffer."
  (save-excursion
    (save-match-data
      (goto-char beg)
      (end-of-line)
      (let ((re (concat "\\(?:" (latex-structure-heading-regexp) "\\)\\|"
                        "\\(?:" latex-structure-section-boundary-regexp
                        "\\)"))
            (found nil))
        (while (and (not found) (re-search-forward re nil t))
          (if (match-beginning 3)
              (when (<= (latex-structure--level
                         (match-string-no-properties 3))
                        level)
                (setq found (match-beginning 0)))
            (setq found (match-beginning 0))))
        (or found (point-max))))))

(defun latex-structure-section-bounds ()
  "Return (BEG END LEVEL) for the section around point.
Signal a `user-error' when point is before the first heading."
  (let ((beg (latex-structure--heading-start)))
    (unless beg
      (user-error "Before first heading"))
    (let ((level (latex-structure--heading-level-at beg)))
      (list beg (latex-structure-section-end beg level) level))))

(defun latex-structure--headings-in (beg end)
  "Return the start positions of all headings between BEG and END."
  (save-excursion
    (save-match-data
      (goto-char beg)
      (let ((re (latex-structure-heading-regexp)) result)
        (while (and (< (point) end) (re-search-forward re end t))
          (push (match-beginning 0) result)
          (end-of-line))
        (nreverse result)))))

(defun latex-structure--previous-sibling (beg level)
  "Return the start of the sibling section before BEG at LEVEL, or nil."
  (save-excursion
    (save-match-data
      (goto-char beg)
      (let ((re (latex-structure-heading-regexp)) result done)
        (while (and (not done) (not (bobp))
                    (progn (backward-char) (re-search-backward re nil t)))
          (let ((lv (latex-structure--level (match-string-no-properties 3)))
                (pos (match-beginning 0)))
            (cond ((< lv level) (setq done t))
                  ((= lv level)
                   (setq done t)
                   (when (= (latex-structure-section-end pos level) beg)
                     (setq result pos))))))
        result))))

(defun latex-structure--next-sibling (end level)
  "Return the start of the sibling section at END with LEVEL, or nil."
  (when (and (< end (point-max))
             (eql (latex-structure--heading-level-at end) level))
    end))

(defun latex-structure--read-braced (pos)
  "Read a brace group whose opening brace is just before POS.
Return the contents, or nil when the group is not closed."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (let ((depth 1))
        (while (and (> depth 0) (re-search-forward "\\\\.\\|[{}]" nil t))
          (when (= (length (match-string 0)) 1)
            (setq depth (if (eq (char-before) ?{) (1+ depth) (1- depth)))))
        (when (= depth 0)
          (buffer-substring-no-properties pos (1- (point))))))))

(defun latex-structure-heading-title (pos)
  "Return the title of the heading at POS, or nil.
An optional short title in brackets is skipped."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (when (latex-structure--looking-at-heading)
        (goto-char (1- (match-end 0)))
        (when (eq (char-after) ?\[)
          (let ((depth 0) (done nil))
            (while (and (not done) (not (eobp)))
              (forward-char)
              (pcase (char-after)
                (?{ (setq depth (1+ depth)))
                (?} (setq depth (1- depth)))
                (?\] (when (= depth 0) (setq done t))))))
          (forward-char)
          (skip-chars-forward " \t\n"))
        (when (eq (char-after) ?{)
          (let ((title (latex-structure--read-braced (1+ (point)))))
            (and title
                 (string-trim
                  (replace-regexp-in-string "[ \t\n]+" " " title)))))))))

(defun latex-structure--ancestors (pos)
  "Return the positions of the headings above POS, outermost first.
The last element is the heading of the section around POS.  The
list is empty when POS is before the first heading."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (let ((start (latex-structure--heading-start))
            (re (latex-structure-heading-regexp))
            result level)
        (when start
          (push start result)
          (setq level (latex-structure--heading-level-at start))
          (goto-char start)
          (while (and (not (bobp))
                      (progn (backward-char) (re-search-backward re nil t)))
            (let ((lv (latex-structure--level (match-string-no-properties 3))))
              (when (< lv level)
                (setq level lv)
                (push (match-beginning 0) result)))))
        result))))


;;;; Heading level arithmetic

(defun latex-structure--sorted-names ()
  "Return the sectioning command names sorted from highest to lowest rank."
  (mapcar #'car (sort (copy-sequence latex-structure-section-levels)
                      (lambda (a b) (< (cdr a) (cdr b))))))

(defun latex-structure--rank (name)
  "Return the position of NAME in `latex-structure--sorted-names'."
  (cl-position name (latex-structure--sorted-names) :test #'string=))

(defun latex-structure--shift-name (name delta)
  "Return the sectioning command DELTA ranks below NAME, or nil."
  (let* ((names (latex-structure--sorted-names))
         (idx (latex-structure--rank name))
         (new (and idx (+ idx delta))))
    (and new (>= new 0) (< new (length names)) (nth new names))))

(defun latex-structure--shift-headings (positions delta)
  "Shift the headings that start at POSITIONS by DELTA ranks.
Check every heading before changing any, so that the change is all
or nothing.  Signal a `user-error' when a heading cannot move."
  (unless (zerop delta)
    (let ((plan
           (mapcar
            (lambda (pos)
              (save-excursion
                (goto-char pos)
                (latex-structure--looking-at-heading)
                (let* ((name (match-string-no-properties 3))
                       (new (latex-structure--shift-name name delta)))
                  (unless new
                    (user-error "Cannot %s \\%s"
                                (if (> delta 0) "demote" "promote") name))
                  (cons pos new))))
            positions)))
      (save-excursion
        (save-match-data
          (dolist (step (reverse plan))
            (goto-char (car step))
            (latex-structure--looking-at-heading)
            (replace-match (cdr step) t t nil 3)))))))

(defun latex-structure--shift-text (text delta)
  "Return TEXT with every heading in it shifted by DELTA ranks."
  (with-temp-buffer
    (insert text)
    (latex-structure--shift-headings
     (latex-structure--headings-in (point-min) (point-max)) delta)
    (buffer-string)))


;;;; Section commands

(defun latex-structure--section-text (beg end)
  "Return the text from BEG to END, ending with a newline."
  (let ((text (buffer-substring beg end)))
    (if (string-suffix-p "\n" text) text (concat text "\n"))))

(defun latex-structure-move-section-up ()
  "Swap the current section with the previous sibling section.
This is the analog of `org-move-subtree-up'.  Subsections travel
with their section."
  (interactive)
  (pcase-let* ((`(,beg ,end ,level) (latex-structure-section-bounds))
               (prev (latex-structure--previous-sibling beg level))
               (offset (- (point) beg)))
    (unless prev
      (user-error "Cannot move past superior level or buffer limit"))
    (let ((text (latex-structure--section-text beg end)))
      (delete-region beg end)
      (goto-char prev)
      (insert text)
      (goto-char (+ prev (min offset (length text)))))))

(defun latex-structure-move-section-down ()
  "Swap the current section with the next sibling section.
This is the analog of `org-move-subtree-down'."
  (interactive)
  (pcase-let* ((`(,beg ,end ,level) (latex-structure-section-bounds))
               (next (latex-structure--next-sibling end level))
               (offset (- (point) beg)))
    (unless next
      (user-error "Cannot move past superior level or buffer limit"))
    (let* ((next-end (latex-structure-section-end next level))
           (text (latex-structure--section-text next next-end)))
      (delete-region next next-end)
      (goto-char beg)
      (insert text)
      (goto-char (+ beg (length text) offset)))))

(defun latex-structure-promote-heading ()
  "Promote the current heading line only.
This is the analog of `org-do-promote'."
  (interactive)
  (latex-structure--shift-headings
   (list (car (latex-structure-section-bounds))) -1))

(defun latex-structure-demote-heading ()
  "Demote the current heading line only.
This is the analog of `org-do-demote'."
  (interactive)
  (latex-structure--shift-headings
   (list (car (latex-structure-section-bounds))) 1))

(defun latex-structure-promote-section ()
  "Promote the current heading and every heading inside its section.
This is the analog of `org-promote-subtree'."
  (interactive)
  (pcase-let ((`(,beg ,end ,_) (latex-structure-section-bounds)))
    (latex-structure--shift-headings
     (latex-structure--headings-in beg end) -1)))

(defun latex-structure-demote-section ()
  "Demote the current heading and every heading inside its section.
This is the analog of `org-demote-subtree'."
  (interactive)
  (pcase-let ((`(,beg ,end ,_) (latex-structure-section-bounds)))
    (latex-structure--shift-headings
     (latex-structure--headings-in beg end) 1)))


;;;; Project files

(defun latex-structure--resolve (name dir)
  "Return the existing file for NAME relative to DIR, or nil.
Try NAME as given and with a .tex extension."
  (let ((file (expand-file-name (string-trim name) dir)))
    (cond ((and (file-name-extension file) (file-regular-p file)) file)
          ((file-regular-p (concat file ".tex")) (concat file ".tex"))
          ((file-regular-p file) file))))

(defun latex-structure-master-file ()
  "Return the master file of the current buffer, or nil.
Use `TeX-master' from AUCTeX or `tex-main-file' from the built-in
mode when they name a file.  Otherwise use the file of the current
buffer."
  (let* ((file (buffer-file-name (or (buffer-base-buffer) (current-buffer))))
         (dir (if file (file-name-directory file) default-directory))
         (master (cond ((and (boundp 'TeX-master) (stringp TeX-master))
                        TeX-master)
                       ((and (boundp 'tex-main-file) (stringp tex-main-file))
                        tex-main-file))))
    (or (and master (latex-structure--resolve master dir))
        file)))

(defmacro latex-structure--with-file-text (file &rest body)
  "Run BODY in a buffer with the current text of FILE.
Use the buffer visiting FILE when there is one, so that unsaved
edits count.  Otherwise read FILE into a temporary buffer."
  (declare (indent 1) (debug t))
  (let ((buf (make-symbol "buf")))
    `(let ((,buf (find-buffer-visiting ,file)))
       (if ,buf
           (with-current-buffer ,buf
             (save-excursion
               (save-restriction
                 (widen)
                 (goto-char (point-min))
                 ,@body)))
         (with-temp-buffer
           (insert-file-contents ,file)
           (goto-char (point-min))
           ,@body)))))

(defun latex-structure--included-files (file master-dir)
  "Return the files that FILE pulls in, in document order.
Names in \\input and \\include are relative to MASTER-DIR, as in
LaTeX.  Names in \\subimport are relative to FILE."
  (let ((file-dir (file-name-directory file)) result)
    (latex-structure--with-file-text file
      (save-match-data
        (while (re-search-forward latex-structure-include-regexp nil t)
          (unless (latex-structure--in-comment-p (match-beginning 0))
            (let ((target
                   (if (match-beginning 1)
                       (latex-structure--resolve (match-string-no-properties 1)
                                                 master-dir)
                     (latex-structure--resolve
                      (match-string-no-properties 4)
                      (expand-file-name (match-string-no-properties 3)
                                        (if (match-beginning 2)
                                            file-dir
                                          master-dir))))))
              (when target (push target result)))))))
    (nreverse result)))

(defun latex-structure-project-files ()
  "Return the files of the current document, master file first.
The list follows \\input, \\include, \\subfile, \\import, and
\\subimport from the master file in document order.  The current
buffer's file is always included.  A buffer without a file gives
an empty list."
  (let* ((master (latex-structure-master-file))
         (current (buffer-file-name (or (buffer-base-buffer)
                                        (current-buffer))))
         (seen nil))
    (when master
      (let ((master-dir (file-name-directory master)))
        (let ((result nil) (stack (list master)))
          ;; Depth-first walk in document order.
          (while stack
            (let* ((f (pop stack)) (key (file-truename f)))
              (unless (member key seen)
                (push key seen)
                (push f result)
                (setq stack (append (latex-structure--included-files
                                     f master-dir)
                                    stack)))))
          (when (and current
                     (not (member (file-truename current) seen)))
            (push current result))
          (nreverse result))))))


;;;; Refile targets

(defun latex-structure--file-label (file root)
  "Return a short name for FILE relative to the directory ROOT."
  (if root (file-relative-name file root) (file-name-nondirectory file)))

(defun latex-structure--headings-with-paths ()
  "Return (POS LEVEL PATH COMMENTED) for every heading in the buffer.
PATH is the list of titles from the top level down to the heading."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (let ((re (latex-structure-heading-regexp)) stack result)
        (while (re-search-forward re nil t)
          (let* ((pos (match-beginning 0))
                 (commented (match-beginning 2))
                 (level (latex-structure--level
                         (match-string-no-properties 3)))
                 (title (or (latex-structure-heading-title pos) "")))
            (while (and stack (>= (caar stack) level))
              (pop stack))
            (push (cons level title) stack)
            (push (list pos level (reverse (mapcar #'cdr stack)) commented)
                  result)
            (goto-char pos)
            (end-of-line)))
        (nreverse result)))))

(defun latex-structure--targets (&optional files)
  "Return an alist of refile targets for FILES.
Each element is (DISPLAY FILE POS LEVEL).  POS and LEVEL are nil
for the target that means the top level of a file.  FILES defaults
to `latex-structure-project-files'.  A buffer without a file gives
targets in the current buffer only, with FILE set to the buffer."
  (let* ((files (or files (latex-structure-project-files)))
         (master (car files))
         (root (and master (stringp master) (file-name-directory master)))
         (seen (make-hash-table :test #'equal))
         result)
    (cl-labels ((add (display file pos level)
                (let* ((n (gethash display seen 0))
                       (shown (if (> n 0) (format "%s <%d>" display (1+ n))
                                display)))
                  (puthash display (1+ n) seen)
                  (push (list shown file pos level) result)))
              (collect (label file)
                (dolist (h (latex-structure--headings-with-paths))
                  (pcase-let ((`(,pos ,level ,path ,commented) h))
                    (when (or (not commented)
                              latex-structure-refile-include-commented)
                      (add (concat label ": " (string-join path " / "))
                           file pos level))))))
      (if (null files)
          (let ((label (buffer-name)))
            (add (concat label " (top level)") (current-buffer) nil nil)
            (collect label (current-buffer)))
        (dolist (file files)
          (let ((label (latex-structure--file-label file root)))
            (add (concat label " (top level)") file nil nil)
            (latex-structure--with-file-text file
              (collect label file))))))
    (nreverse result)))

(defun latex-structure--read-target (prompt)
  "Read a refile target with PROMPT and return (DISPLAY FILE POS LEVEL)."
  (let* ((targets (latex-structure--targets))
         (choice (completing-read
                  prompt
                  (lambda (string pred action)
                    (if (eq action 'metadata)
                        '(metadata (category . latex-structure-target)
                                   (display-sort-function . identity))
                      (complete-with-action action targets string pred)))
                  nil t)))
    (or (assoc choice targets)
        (user-error "No such target: %s" choice))))

(defun latex-structure--target-buffer (file)
  "Return the buffer for FILE, visiting it when needed.
FILE may already be a buffer."
  (if (bufferp file) file (find-file-noselect file)))

(defun latex-structure--top-level-insertion-point ()
  "Return the top-level insertion point for a section in this buffer.
This is the end of the last section, before \\end{document} or the
bibliography when one of them follows it."
  (let ((headings (latex-structure--headings-in (point-min) (point-max))))
    (if headings
        (latex-structure-section-end (car (last headings))
                                     most-negative-fixnum)
      (save-excursion
        (save-match-data
          (goto-char (point-min))
          (if (re-search-forward "^[ \t]*\\\\end[ \t]*{document}" nil t)
              (match-beginning 0)
            (point-max)))))))

(defun latex-structure--insert-section-text (pos text)
  "Insert TEXT at POS as whole lines and return the start of TEXT."
  (goto-char pos)
  (unless (bolp) (insert "\n"))
  (let ((start (point)))
    (insert text)
    start))


;;;; Refile and goto

(defun latex-structure-goto (&optional target)
  "Jump to a heading anywhere in the current document.
Offer every heading of every file reached from the master file.
This is the analog of `org-goto' and of `org-refile' with a prefix
argument.  TARGET is an element of `latex-structure--targets'; it
is read with completion when called interactively."
  (interactive)
  (pcase-let ((`(,_ ,file ,pos ,_)
               (or target (latex-structure--read-target "Goto: "))))
    (push-mark nil t)
    (let ((buf (latex-structure--target-buffer file)))
      (pop-to-buffer-same-window buf)
      (when (and pos (or (< pos (point-min)) (> pos (point-max))))
        (widen))
      (goto-char (or pos (point-min))))))

(defun latex-structure--refile (target copy)
  "Refile the current section to TARGET.
TARGET is an element of `latex-structure--targets'.  When COPY is
non-nil, leave the original section in place."
  (pcase-let* ((`(,beg ,end ,level) (latex-structure-section-bounds))
               (`(,display ,file ,pos ,tlevel) target)
               (src-buf (current-buffer))
               (dst-buf (latex-structure--target-buffer file))
               (delta (if (and pos latex-structure-refile-adjust-levels)
                          (- (1+ (latex-structure--rank
                                  (car (rassq tlevel
                                              latex-structure-section-levels))))
                             (latex-structure--rank
                              (car (rassq level
                                          latex-structure-section-levels))))
                        0)))
    (when (and (eq (or (buffer-base-buffer dst-buf) dst-buf)
                   (or (buffer-base-buffer src-buf) src-buf))
               pos (>= pos beg) (< pos end))
      (user-error "Cannot refile a section into itself"))
    (let* ((text (latex-structure--shift-text
                  (latex-structure--section-text beg end) delta))
           (beg-m (copy-marker beg t))
           (end-m (copy-marker end)))
      (unwind-protect
          (progn
            (with-current-buffer dst-buf
              (save-excursion
                (save-restriction
                  (widen)
                  (let ((ins (if pos
                                 (latex-structure-section-end pos tlevel)
                               (latex-structure--top-level-insertion-point))))
                    (latex-structure--insert-section-text ins text)))))
            (unless copy
              (with-current-buffer src-buf
                (delete-region beg-m end-m))))
        (set-marker beg-m nil)
        (set-marker end-m nil))
      (message "Section %s to %s" (if copy "copied" "refiled") display))))

(defun latex-structure-refile (&optional arg target)
  "Move the current section under another heading of the document.
This is the analog of `org-refile'.  The targets are every heading
in every file reached from the master file through \\input,
\\include, \\subfile, \\import, and \\subimport, plus the top level
of each file.

The section becomes the last child of the target heading.  When
`latex-structure-refile-adjust-levels' is non-nil, its headings
change rank to fit, so a \\section refiled under a \\section
becomes a \\subsection.

With a \\[universal-argument] prefix ARG, only jump to the chosen
heading, like `org-refile' with a prefix argument.  TARGET is an
element of `latex-structure--targets'; it is read with completion
when nil."
  (interactive "P")
  (if (equal arg '(4))
      (latex-structure-goto target)
    (latex-structure--refile
     (or target (latex-structure--read-target "Refile to: ")) nil)))

(defun latex-structure-refile-copy (&optional target)
  "Copy the current section under another heading of the document.
This is the analog of `org-refile-copy'.  See
`latex-structure-refile' for TARGET and for the choice of targets."
  (interactive)
  (latex-structure--refile
   (or target (latex-structure--read-target "Copy to: ")) t))


;;;; Indirect buffer

(defvar latex-structure--last-indirect-buffer nil
  "The indirect buffer made by the last call of the indirect command.")

(defun latex-structure-tree-to-indirect-buffer (&optional arg)
  "Show the current section alone in an indirect buffer.
This is the analog of `org-tree-to-indirect-buffer'.  Edits in the
indirect buffer change the original buffer.  The buffer made by the
previous call is killed first, unless ARG is non-nil, so that one
indirect buffer is reused.  See
`latex-structure-indirect-buffer-display' for where it appears."
  (interactive "P")
  (pcase-let* ((`(,beg ,end ,_) (latex-structure-section-bounds))
               (base (or (buffer-base-buffer) (current-buffer)))
               (title (or (latex-structure-heading-title beg) "section")))
    (when (and (not arg)
               (buffer-live-p latex-structure--last-indirect-buffer)
               (not (eq latex-structure--last-indirect-buffer
                        (current-buffer))))
      (kill-buffer latex-structure--last-indirect-buffer))
    (let ((buf (make-indirect-buffer
                base
                (generate-new-buffer-name
                 (format "%s-%s" (buffer-name base) title))
                t)))
      (with-current-buffer buf
        (widen)
        (narrow-to-region beg end)
        (goto-char beg))
      (setq latex-structure--last-indirect-buffer buf)
      (pcase latex-structure-indirect-buffer-display
        ('current-window (pop-to-buffer-same-window buf))
        ('new-frame (switch-to-buffer-other-frame buf))
        (_ (pop-to-buffer buf)))
      buf)))


;;;; Sparse tree

(defvar-local latex-structure--sparse-overlays nil
  "Overlays made by `latex-structure-sparse-tree' in this buffer.")

(defun latex-structure-sparse-tree-remove ()
  "Show the whole buffer again after `latex-structure-sparse-tree'."
  (interactive)
  (mapc #'delete-overlay latex-structure--sparse-overlays)
  (setq latex-structure--sparse-overlays nil))

(defun latex-structure--hide (beg end ellipsis)
  "Hide the text from BEG to END, with an ellipsis when ELLIPSIS is non-nil."
  (when (< beg end)
    (let ((ov (make-overlay beg end nil t nil)))
      (overlay-put ov 'invisible (if ellipsis
                                     'latex-structure-sparse
                                   'latex-structure-sparse-lead))
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'isearch-open-invisible #'delete-overlay)
      (push ov latex-structure--sparse-overlays))))

(defun latex-structure-sparse-tree (regexp)
  "Hide everything except the lines that match REGEXP and their headings.
This is the analog of `org-sparse-tree' with the regexp option.
The matches are highlighted.  An empty REGEXP, or the command
`latex-structure-sparse-tree-remove', shows the whole buffer again.
Return the number of matches."
  (interactive (list (read-regexp "Sparse tree (regexp)")))
  (latex-structure-sparse-tree-remove)
  (if (or (null regexp) (string-empty-p regexp))
      0
    (add-to-invisibility-spec '(latex-structure-sparse . t))
    (add-to-invisibility-spec 'latex-structure-sparse-lead)
    (let ((lines nil) (count 0))
      (save-excursion
        (save-match-data
          (goto-char (point-min))
          (while (and (not (eobp)) (re-search-forward regexp nil t))
            (let ((mb (match-beginning 0)) (me (match-end 0)))
              (if (= mb me)
                  (forward-char 1)
                (cl-incf count)
                (let ((ov (make-overlay mb me)))
                  (overlay-put ov 'face 'latex-structure-sparse-match)
                  (overlay-put ov 'evaporate t)
                  (push ov latex-structure--sparse-overlays))
                (goto-char mb)
                (while (progn (push (line-beginning-position) lines)
                              (and (< (line-end-position) me)
                                   (zerop (forward-line 1)))))
                (dolist (h (latex-structure--ancestors mb))
                  (push h lines))
                (goto-char me))))))
      (if (zerop count)
          (message "No match for %s" regexp)
        (setq lines (sort (delete-dups lines) #'<))
        (save-excursion
          (latex-structure--hide (point-min) (car lines) nil)
          (let ((prev (car lines)))
            (dolist (bol (cdr lines))
              (goto-char bol)
              (latex-structure--hide
               (save-excursion (goto-char prev) (line-end-position))
               (1- bol) t)
              (setq prev bol))
            (goto-char prev)
            (latex-structure--hide (line-end-position) (point-max) t)))
        (message "%d match%s" count (if (= count 1) "" "es")))
      count)))


;;;; List items

(defun latex-structure--list-env-p (name)
  "Return non-nil when the environment NAME is a list environment."
  (member name latex-structure-list-environments))

(defun latex-structure--matching-end (after)
  "Return (BEG . END) of the \\end token that closes an environment.
AFTER is the position just after the \\begin token.  Return nil
when the environment is not closed."
  (save-excursion
    (save-match-data
      (goto-char after)
      (let ((depth 0) found)
        (while (and (not found)
                    (re-search-forward latex-structure--env-token-regexp nil t))
          (unless (latex-structure--in-comment-p (match-beginning 0))
            (if (string= (match-string 1) "begin")
                (cl-incf depth)
              (if (> depth 0)
                  (cl-decf depth)
                (setq found (cons (match-beginning 0) (match-end 0)))))))
        found))))

(defun latex-structure--list-at (pos)
  "Return the innermost list environment around POS, or nil.
The value is a plist with :name, :begin (start of the \\begin
token), :body (end of the \\begin token), :end (start of the \\end
token), and :end-after (end of the \\end token)."
  (save-excursion
    (save-match-data
      (goto-char pos)
      (let ((depth 0) found)
        (while (and (not found)
                    (re-search-backward latex-structure--env-token-regexp nil t))
          (unless (latex-structure--in-comment-p (match-beginning 0))
            (if (string= (match-string 1) "end")
                (cl-incf depth)
              (if (> depth 0)
                  (cl-decf depth)
                (when (latex-structure--list-env-p (match-string 2))
                  (let ((close (latex-structure--matching-end (match-end 0))))
                    (when (and close (< pos (cdr close)))
                      (setq found
                            (list :name (match-string-no-properties 2)
                                  :begin (match-beginning 0)
                                  :body (match-end 0)
                                  :end (car close)
                                  :end-after (cdr close))))))))))
        found))))

(defun latex-structure--line-start-if-blank-before (pos)
  "Return the start of POS's line when only blanks precede POS on it.
Otherwise return POS."
  (save-excursion
    (goto-char pos)
    (skip-chars-backward " \t")
    (if (bolp) (point) pos)))

(defun latex-structure--list-items (list)
  "Return the items of LIST as a list of (START . END).
Only items at the top level of LIST count.  START is the start of
the \\item line, or the \\item token when text precedes it on the
line.  END is the start of the next item or of the \\end token."
  (save-excursion
    (save-match-data
      (goto-char (plist-get list :body))
      (let ((limit (plist-get list :end)) (depth 0) starts)
        (while (re-search-forward latex-structure--item-token-regexp limit t)
          (unless (latex-structure--in-comment-p (match-beginning 0))
            (cond ((match-beginning 3)
                   (when (= depth 0) (push (match-beginning 0) starts)))
                  ((string= (match-string 1) "begin") (cl-incf depth))
                  (t (cl-decf depth)))))
        (let* ((starts (mapcar #'latex-structure--line-start-if-blank-before
                               (nreverse starts)))
               (ends (append (cdr starts)
                             (list (latex-structure--line-start-if-blank-before
                                    limit)))))
          (cl-mapcar #'cons starts ends))))))

(defun latex-structure-item-at (&optional pos)
  "Return the list item around POS, or nil.
POS defaults to point.  The value is a plist with :list, the list
as returned by `latex-structure--list-at', :items, all of its items,
and :index, the position of the item in :items."
  (let* ((pos (or pos (point))) (search pos) result)
    (while (and (not result) search)
      (let ((list (latex-structure--list-at search)))
        (if (not list)
            (setq search nil)
          (let* ((items (latex-structure--list-items list))
                 (idx (cl-position-if (lambda (it)
                                        (and (>= pos (car it)) (< pos (cdr it))))
                                      items)))
            (if idx
                (setq result (list :list list :items items :index idx))
              (setq search (plist-get list :begin)))))))
    result))

(defun latex-structure--item-or-error ()
  "Return the item at point or signal a `user-error'."
  (or (latex-structure-item-at) (user-error "Not in a list item")))

(defun latex-structure--split-trailing (text)
  "Return (BODY . TRAILING) where TRAILING is TEXT's trailing whitespace."
  (if (string-match "[ \t\n]*\\'" text)
      (cons (substring text 0 (match-beginning 0))
            (substring text (match-beginning 0)))
    (cons text "")))

(defun latex-structure--swap-items (first second)
  "Swap the adjacent items FIRST and SECOND, each a (START . END).
Return the start of the moved copy of FIRST."
  (pcase-let* ((`(,b1 . ,t1) (latex-structure--split-trailing
                              (buffer-substring (car first) (cdr first))))
               (`(,b2 . ,t2) (latex-structure--split-trailing
                              (buffer-substring (car second) (cdr second))))
               (sep (if (string-empty-p t1) "\n" t1)))
    (goto-char (car first))
    (delete-region (car first) (cdr second))
    (insert b2 sep)
    (prog1 (point)
      (insert b1 t2))))

(defun latex-structure-move-item-up ()
  "Swap the current list item with the previous one.
This is the analog of `org-move-item-up'.  Nested lists inside the
item travel with it."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (items (plist-get info :items))
         (idx (plist-get info :index))
         (cur (nth idx items)))
    (when (= idx 0)
      (user-error "Cannot move this item further up"))
    (let* ((prev (nth (1- idx) items))
           (offset (- (point) (car cur)))
           (body-len (length (car (latex-structure--split-trailing
                                   (buffer-substring (car cur) (cdr cur)))))))
      (latex-structure--swap-items prev cur)
      (goto-char (+ (car prev) (min offset body-len))))))

(defun latex-structure-move-item-down ()
  "Swap the current list item with the next one.
This is the analog of `org-move-item-down'."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (items (plist-get info :items))
         (idx (plist-get info :index))
         (cur (nth idx items)))
    (when (= idx (1- (length items)))
      (user-error "Cannot move this item further down"))
    (let* ((offset (- (point) (car cur)))
           (body-len (length (car (latex-structure--split-trailing
                                   (buffer-substring (car cur) (cdr cur))))))
           (start (latex-structure--swap-items cur (nth (1+ idx) items))))
      (goto-char (+ start (min offset body-len))))))

(defun latex-structure--goto-item-token (start)
  "Move point to the \\item token of the item beginning at START."
  (goto-char start)
  (skip-chars-forward " \t"))

(defun latex-structure-next-item ()
  "Move to the next item of the current list."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (next (nth (1+ (plist-get info :index)) (plist-get info :items))))
    (unless next (user-error "No next item"))
    (latex-structure--goto-item-token (car next))))

(defun latex-structure-previous-item ()
  "Move to the previous item of the current list."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (idx (plist-get info :index)))
    (when (= idx 0) (user-error "No previous item"))
    (latex-structure--goto-item-token
     (car (nth (1- idx) (plist-get info :items))))))

(defun latex-structure--item-text (item)
  "Return the text of ITEM, a (START . END), ending with a newline."
  (let ((text (string-trim-right (buffer-substring (car item) (cdr item)))))
    (concat text "\n")))

(defun latex-structure--reindent (beg end)
  "Reindent the lines from BEG to END when `latex-structure-reindent' is on."
  (when latex-structure-reindent
    (let ((inhibit-message t))
      (indent-region beg end))))

(defun latex-structure-indent-item ()
  "Make the current item the last child of the previous item.
This is the analog of `org-indent-item-tree'.  The item moves into
the list that ends the previous item, or into a new list of the
same type when the previous item has no nested list."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (items (plist-get info :items))
         (idx (plist-get info :index))
         (cur (nth idx items))
         (list (plist-get info :list))
         (name (plist-get list :name)))
    (when (= idx 0)
      (user-error "Cannot indent the first item of a list"))
    (let* ((list-beg (copy-marker (plist-get list :begin)))
           (list-end (copy-marker (plist-get list :end-after)))
           (prev (nth (1- idx) items))
           (text (latex-structure--item-text cur))
           (nested (save-excursion
                     (goto-char (car prev))
                     (let ((prev-body (string-trim-right
                                       (buffer-substring (car prev) (cdr prev)))))
                       (when (string-match
                              "\\\\end[ \t]*{\\([^}\n]*\\)}\\'" prev-body)
                         (let ((pos (+ (car prev) (match-beginning 0))))
                           (and (latex-structure--list-env-p
                                 (match-string 1 prev-body))
                                pos))))))
           start)
      (delete-region (car cur) (cdr cur))
      (if nested
          (progn
            (setq start (latex-structure--line-start-if-blank-before nested))
            (goto-char start)
            (unless (bolp) (insert "\n") (setq start (point)))
            (insert text))
        (goto-char (car cur))
        (unless (bolp) (insert "\n"))
        (setq start (point))
        (insert "\\begin{" name "}\n" text "\\end{" name "}\n"))
      (latex-structure--reindent list-beg list-end)
      (set-marker list-beg nil)
      (set-marker list-end nil)
      (goto-char start)
      (re-search-forward "\\\\item\\_>" nil t)
      (goto-char (match-beginning 0)))))

(defun latex-structure-outdent-item ()
  "Make the current nested item a sibling that follows its parent item.
This is the analog of `org-outdent-item-tree'.  When the item was
the only one in its nested list, the empty list is removed."
  (interactive)
  (let* ((info (latex-structure--item-or-error))
         (list (plist-get info :list))
         (items (plist-get info :items))
         (cur (nth (plist-get info :index) items))
         (parent (latex-structure-item-at (plist-get list :begin))))
    (unless parent
      (user-error "Item is already at the top level"))
    (let* ((text (latex-structure--item-text cur))
           (pitem (nth (plist-get parent :index) (plist-get parent :items)))
           (plist (plist-get parent :list))
           (pstart (copy-marker (car pitem)))
           (outer-beg (copy-marker (plist-get plist :begin)))
           (outer-end (copy-marker (plist-get plist :end-after)))
           start)
      (unwind-protect
          (progn
            (if (= (length items) 1)
                (let ((lbeg (latex-structure--line-start-if-blank-before
                             (plist-get list :begin)))
                      (lend (save-excursion
                              (goto-char (plist-get list :end-after))
                              (if (looking-at "[ \t]*\n")
                                  (match-end 0)
                                (point)))))
                  (delete-region lbeg lend))
              (delete-region (car cur) (cdr cur)))
            (let* ((pinfo (latex-structure-item-at pstart))
                   (pend (cdr (nth (plist-get pinfo :index)
                                   (plist-get pinfo :items)))))
              (goto-char pend)
              (unless (bolp) (insert "\n"))
              (setq start (point))
              (insert text)
              (latex-structure--reindent outer-beg outer-end)))
        (set-marker pstart nil)
        (set-marker outer-beg nil)
        (set-marker outer-end nil))
      (goto-char start)
      (re-search-forward "\\\\item\\_>" nil t)
      (goto-char (match-beginning 0)))))

(defun latex-structure--rename-list (list new)
  "Rename the \\begin and \\end tokens of LIST to NEW."
  (save-excursion
    (save-match-data
      (goto-char (plist-get list :end))
      (when (looking-at latex-structure--env-token-regexp)
        (replace-match new t t nil 2))
      (goto-char (plist-get list :begin))
      (when (looking-at latex-structure--env-token-regexp)
        (replace-match new t t nil 2)))))

(defun latex-structure-cycle-list-type (&optional arg)
  "Change the innermost list around point to the next type.
The types come from `latex-structure-list-cycle', so itemize turns
into enumerate, enumerate into description, and description back
into itemize.  This is the analog of `org-cycle-list-bullet'.  With
a prefix ARG, read the new type with completion."
  (interactive "P")
  (let* ((list (or (latex-structure--list-at (point))
                   (user-error "Not in a list")))
         (name (plist-get list :name))
         (new (if arg
                  (completing-read "List type: " latex-structure-list-cycle
                                   nil nil nil nil name)
                (let ((tail (cdr (member name latex-structure-list-cycle))))
                  (or (car tail) (car latex-structure-list-cycle))))))
    (latex-structure--rename-list list new)
    (message "List is now %s" new)
    new))


;;;; Context-sensitive Meta-arrow commands

(defun latex-structure--context ()
  "Return `heading', `item', or nil for the structure at point."
  (cond ((latex-structure-on-heading-line-p) 'heading)
        ((latex-structure-item-at) 'item)))

(defmacro latex-structure--define-meta (name doc heading item)
  "Define the command NAME with DOC to call HEADING or ITEM.
HEADING runs on a heading line and ITEM in a list item."
  (declare (indent 1) (doc-string 2))
  `(defun ,name ()
     ,doc
     (interactive)
     (pcase (latex-structure--context)
       ('heading (call-interactively #',heading))
       ('item (call-interactively #',item))
       (_ (user-error "Not on a heading line or in a list item")))))

(latex-structure--define-meta latex-structure-metaup
  "Move the section or the list item at point up.
This is the analog of `org-metaup'."
  latex-structure-move-section-up latex-structure-move-item-up)

(latex-structure--define-meta latex-structure-metadown
  "Move the section or the list item at point down.
This is the analog of `org-metadown'."
  latex-structure-move-section-down latex-structure-move-item-down)

(latex-structure--define-meta latex-structure-metaleft
  "Promote the heading line or outdent the list item at point.
This is the analog of `org-metaleft'."
  latex-structure-promote-heading latex-structure-outdent-item)

(latex-structure--define-meta latex-structure-metaright
  "Demote the heading line or indent the list item at point.
This is the analog of `org-metaright'."
  latex-structure-demote-heading latex-structure-indent-item)

(latex-structure--define-meta latex-structure-shiftmetaleft
  "Promote the section or outdent the list item at point.
This is the analog of `org-shiftmetaleft'."
  latex-structure-promote-section latex-structure-outdent-item)

(latex-structure--define-meta latex-structure-shiftmetaright
  "Demote the section or indent the list item at point.
This is the analog of `org-shiftmetaright'."
  latex-structure-demote-section latex-structure-indent-item)


;;;; Speed command integration

(defcustom latex-structure-speed-commands
  '(("Structure (latex-structure)")
    ("W" . latex-structure-refile)
    ("g" . latex-structure-goto)
    ("T" . latex-structure-tree-to-indirect-buffer)
    ("/" . latex-structure-sparse-tree))
  "Heading speed commands added by `latex-structure-speed-commands-setup'.
The format is that of `latex-speed-commands'.  The entries go to
the front of that list, so they win over entries with the same key."
  :type '(repeat (choice (list :tag "Descriptive Headline"
                               (string :tag "Headline"))
                         (cons :tag "Letter and Command"
                               (string :tag "Command letter")
                               (choice (function) (sexp)))))
  :package-version '(latex-structure . "0.1.0"))

(defcustom latex-structure-item-speed-commands
  '(("n" . latex-structure-next-item)
    ("p" . latex-structure-previous-item)
    ("U" . latex-structure-move-item-up)
    ("D" . latex-structure-move-item-down)
    ("l" . latex-structure-outdent-item)
    ("r" . latex-structure-indent-item)
    ("-" . latex-structure-cycle-list-type))
  "Speed commands that are active at the start of an \\item line.
The format is that of `latex-speed-commands'.  They take effect
after `latex-structure-speed-commands-setup'."
  :type '(repeat (cons :tag "Letter and Command"
                       (string :tag "Command letter")
                       (choice (function) (sexp))))
  :package-version '(latex-structure . "0.1.0"))

(defun latex-structure-at-item-line-p ()
  "Return non-nil when point is at the start of an \\item line.
The start is either the beginning of the line or the \\item token
after the indentation."
  (save-excursion
    (save-match-data
      (and (or (bolp)
               (and (looking-at "\\\\item\\_>")
                    (progn (skip-chars-backward " \t") (bolp))))
           (looking-at "[ \t]*\\\\item\\_>")))))

(defun latex-structure-item-speed-activate (key)
  "Return the item speed command for KEY at an \\item line, or nil.
This function goes on `latex-speed-commands-activate-functions'."
  (when (latex-structure-at-item-line-p)
    (cdr (assoc key latex-structure-item-speed-commands))))

;;;###autoload
(defun latex-structure-speed-commands-setup ()
  "Add the latex-structure commands to latex-speed-commands.
Put `latex-structure-speed-commands' at the front of
`latex-speed-commands' and add `latex-structure-item-speed-activate'
to `latex-speed-commands-activate-functions'.  Calling this again
does not add duplicates.  Signal an error when latex-speed-commands
is not installed."
  (interactive)
  (unless (require 'latex-speed-commands nil t)
    (user-error "The package latex-speed-commands is not available"))
  (setq latex-speed-commands
        (append latex-structure-speed-commands
                (cl-remove-if (lambda (entry)
                                (member entry latex-structure-speed-commands))
                              latex-speed-commands)))
  (add-hook 'latex-speed-commands-activate-functions
            #'latex-structure-item-speed-activate))


;;;; Minor mode

(defun latex-structure--conditional (cmd pred)
  "Return a key binding for CMD that is active only when PRED is non-nil.
Otherwise key lookup falls through to the other key maps."
  `(menu-item "" ,cmd :filter ,(lambda (c) (and (funcall pred) c))))

(defvar latex-structure-mode-map
  (let ((map (make-sparse-keymap)))
    (dolist (b `(([M-up] . latex-structure-metaup)
                 ([M-down] . latex-structure-metadown)
                 ([M-left] . latex-structure-metaleft)
                 ([M-right] . latex-structure-metaright)
                 ([M-S-left] . latex-structure-shiftmetaleft)
                 ([M-S-right] . latex-structure-shiftmetaright)))
      (define-key map (car b)
                  (latex-structure--conditional (cdr b)
                                                #'latex-structure--context)))
    (define-key map (kbd "C-c -")
                (latex-structure--conditional
                 #'latex-structure-cycle-list-type
                 (lambda () (latex-structure--list-at (point)))))
    (define-key map (kbd "C-c C-w") #'latex-structure-refile)
    (define-key map (kbd "C-c M-w") #'latex-structure-refile-copy)
    (define-key map (kbd "C-c C-x b") #'latex-structure-tree-to-indirect-buffer)
    (define-key map (kbd "C-c /") #'latex-structure-sparse-tree)
    map)
  "Keymap for `latex-structure-mode'.
The Meta-arrow keys and \\`C-c -' are active only on a heading line
or in a list, so they keep their usual meaning elsewhere.")

;;;###autoload
(define-minor-mode latex-structure-mode
  "Toggle Org-style structure editing in LaTeX buffers.

\\<latex-structure-mode-map>On a heading line, \\[latex-structure-metaup] and \
\\[latex-structure-metadown] move the section, and
\\[latex-structure-metaleft] and \\[latex-structure-metaright] \
promote or demote the heading.  In a list
item they move, outdent, and indent the item.  Elsewhere these keys
keep their usual meaning.

\\[latex-structure-refile] refiles the section anywhere in the document, \
\\[latex-structure-refile-copy] copies it,
\\[latex-structure-tree-to-indirect-buffer] shows it in an indirect \
buffer, and \\[latex-structure-sparse-tree] makes a sparse tree.

\\{latex-structure-mode-map}"
  :lighter latex-structure-lighter
  :keymap latex-structure-mode-map
  :group 'latex-structure
  (unless latex-structure-mode
    (latex-structure-sparse-tree-remove)))

(provide 'latex-structure)
;;; latex-structure.el ends here

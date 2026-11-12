;;; doc-coverage.el --- Docstring coverage for latex-structure -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Used by `make docs-check'.  Load the package, collect every
;; function and variable that latex-structure.el defines, and report
;; how many carry a docstring.  Exit with status 1 when the share is
;; below the threshold.

;;; Code:

(require 'cl-lib)
(require 'latex-structure)

(defun lst-docs--defined-symbols ()
  "Return a cons of the functions and the variables in the package file."
  (let ((entry (cl-find-if (lambda (e)
                             (and (stringp (car e))
                                  (string-match-p "latex-structure\\.elc?\\'"
                                                  (car e))))
                           load-history))
        fns vars)
    (dolist (item (cdr entry))
      (cond ((and (consp item) (eq (car item) 'defun)) (push (cdr item) fns))
            ((symbolp item) (push item vars))))
    (cons (nreverse fns) (nreverse vars))))

(defun lst-docs-check-coverage (threshold)
  "Print docstring coverage and exit non-zero when below THRESHOLD percent."
  (let* ((syms (lst-docs--defined-symbols))
         (fns (car syms))
         (vars (cdr syms))
         (missing nil)
         (total (+ (length fns) (length vars)))
         documented pct)
    (dolist (f fns)
      (unless (documentation f t) (push (format "function %s" f) missing)))
    (dolist (v vars)
      (unless (or (documentation-property v 'variable-documentation t)
                  (and (facep v) (face-documentation v)))
        (push (format "variable %s" v) missing)))
    (setq documented (- total (length missing))
          pct (if (> total 0) (/ (* 100.0 documented) total) 0.0))
    (dolist (m (nreverse missing)) (message "  Missing docstring: %s" m))
    (message "Documented: %d of %d symbols (%d functions, %d variables), %.1f%%"
             documented total (length fns) (length vars) pct)
    (if (< pct threshold)
        (progn (message "Documentation coverage is below %d%%" threshold)
               (kill-emacs 1))
      (message "Documentation coverage meets the %d%% threshold" threshold))))

(provide 'doc-coverage)
;;; doc-coverage.el ends here

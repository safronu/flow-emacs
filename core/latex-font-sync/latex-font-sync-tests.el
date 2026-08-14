;;; latex-font-sync-tests.el --- ERT tests for latex-font-sync -*- lexical-binding: t; -*-
;;
;; Run from the repo root:
;;   emacs --batch \
;;     --eval "(progn (require 'package) (package-initialize))" \
;;     -L core/latex-font-sync \
;;     -l latex-font-sync -l latex-font-sync-tests \
;;     -f ert-run-tests-batch-and-exit
;;
;; AUCTeX must be installed in the package archive that batch Emacs sees.
;; The Termux-side Emacs profile does; the Android-side profile also does
;; once first-run bootstrap has completed.

(require 'ert)
(require 'latex-font-sync)
;; AUCTeX
(require 'tex)
(require 'latex)

;;; --- Layer A / B invariants ---------------------------------------------

(ert-deftest lfs/package-alist-values-are-intended-keys ()
  "Every RHS in `my/latex-font-package-alist' is a keyword we know how to render."
  (dolist (entry my/latex-font-package-alist)
    (should (keywordp (cdr entry)))
    (should (assq (cdr entry) my/latex-font-candidate-alist))))

(ert-deftest lfs/nfss-alist-values-are-intended-keys ()
  "Every RHS in `my/latex-font-nfss-code-alist' points at a known candidate list."
  (dolist (entry my/latex-font-nfss-code-alist)
    (should (assq (cdr entry) my/latex-font-candidate-alist))))

(ert-deftest lfs/candidate-lists-end-in-guaranteed-family ()
  "Each candidate list ends with a family Android Emacs is guaranteed to have.
Without this, `my/latex-resolve-family' could return nil for a known
intended key on a stock Boox."
  (dolist (entry my/latex-font-candidate-alist)
    (let ((last (car (last (cdr entry)))))
      (should (member last '("Noto Serif" "Noto Sans" "Droid Sans Mono" "serif"))))))

;;; --- Detector -----------------------------------------------------------

(defmacro lfs-test/with-latex-buffer (body-text active-styles pkg-options &rest body)
  "Run BODY in a LaTeX-mode temp buffer with BODY-TEXT, ACTIVE-STYLES, PKG-OPTIONS.
Setting these buffer-locally simulates the state AUCTeX would produce
after `TeX-update-style' runs."
  (declare (indent 3))
  `(with-temp-buffer
     (insert ,body-text)
     (LaTeX-mode)
     ,(if active-styles
          `(setq-local TeX-active-styles ,active-styles)
        `(kill-local-variable 'TeX-active-styles))
     (setq-local LaTeX-provided-package-options ,pkg-options)
     ,@body))

(ert-deftest lfs/detect-nfss-ppl ()
  (lfs-test/with-latex-buffer
      "\\documentclass{article}\n\\renewcommand{\\rmdefault}{ppl}\n\\begin{document}x\\end{document}"
      '("article") nil
    (should (eq (my/latex-detect-intended-family) :family/palatino))))

(ert-deftest lfs/detect-package-mathpazo ()
  (lfs-test/with-latex-buffer "x" '("article" "mathpazo") '(("mathpazo"))
    (should (eq (my/latex-detect-intended-family) :family/palatino))))

(ert-deftest lfs/detect-last-loaded-wins ()
  "When two font packages are listed, the later one wins (approximates LaTeX)."
  (lfs-test/with-latex-buffer "x" '("article" "mathpazo" "times")
      '(("mathpazo") ("times"))
    (should (eq (my/latex-detect-intended-family) :family/times))))

(ert-deftest lfs/detect-unparsed-returns-nil ()
  "Before AUCTeX parses the buffer, detector must return nil so the
applier leaves the face alone."
  (lfs-test/with-latex-buffer "x" nil nil
    (should (null (my/latex-detect-intended-family)))))

(ert-deftest lfs/detect-parsed-but-no-font-info-defaults-to-lm ()
  (lfs-test/with-latex-buffer "x" '("article") nil
    (should (eq (my/latex-detect-intended-family) :family/lm-roman))))

(ert-deftest lfs/detect-nfss-only-in-preamble ()
  "An `\\rmdefault' override AFTER `\\begin{document}' must be ignored."
  (lfs-test/with-latex-buffer
      "\\documentclass{article}\n\\begin{document}\n\\renewcommand{\\rmdefault}{ppl}\nx\\end{document}"
      '("article") nil
    (should (eq (my/latex-detect-intended-family) :family/lm-roman))))

(ert-deftest lfs/detect-user-path-override-wins-even-unparsed ()
  (let ((my/latex-font-user-overrides-by-path '(("*/lecture-notes/*.tex" . :family/bookman))))
    (with-temp-buffer
      (setq buffer-file-name "/tmp/lecture-notes/day1.tex")
      (LaTeX-mode)
      (kill-local-variable 'TeX-active-styles)
      (should (eq (my/latex-detect-intended-family) :family/bookman)))))

;;; --- Resolver + cache ---------------------------------------------------

(ert-deftest lfs/resolver-tty-returns-nil ()
  "In batch / TTY there is no font backend; resolver must return nil, not error."
  (should (null (my/latex-resolve-family :family/palatino))))

(ert-deftest lfs/resolver-cache-memoises-misses ()
  "A second call for an unresolved key must not re-probe `find-font'."
  (clrhash my/latex-family-cache)
  (let ((probes 0))
    (cl-letf (((symbol-function 'find-font)
               (lambda (&rest _) (cl-incf probes) nil))
              ((symbol-function 'display-graphic-p) (lambda () t)))
      (my/latex-resolve-family :family/palatino)
      (my/latex-resolve-family :family/palatino)
      (should (= probes (length (my/latex-font--all-candidates :family/palatino)))))))

(ert-deftest lfs/resolver-picks-first-available ()
  "Resolver walks the candidate list and returns the first family
`find-font' accepts.  Uses `format' comparison because `font-get' on a
`:family' property returns a symbol, not a string."
  (clrhash my/latex-family-cache)
  (cl-letf (((symbol-function 'find-font)
             (lambda (spec)
               (equal (format "%s" (font-get spec :family)) "Noto Serif")))
            ((symbol-function 'display-graphic-p) (lambda () t)))
    (should (equal (my/latex-resolve-family :family/palatino) "Noto Serif"))))

;;; --- User overrides file wiring ----------------------------------------

(ert-deftest lfs/all-candidates-prefers-user-list ()
  (let ((my/latex-font-user-candidates
         '((:family/palatino . ("MyPalatino" "Noto Serif")))))
    (should (equal (my/latex-font--all-candidates :family/palatino)
                   '("MyPalatino" "Noto Serif")))))

(provide 'latex-font-sync-tests)
;;; latex-font-sync-tests.el ends here

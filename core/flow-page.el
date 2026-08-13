;;; flow-page.el --- display-math air, like the compiled page -*- lexical-binding: t; -*-
;;
;; In the PDF, a full-line formula is set off from the surrounding text
;; by \abovedisplayskip / \belowdisplayskip.  In the .tex buffer the
;; formula's source sits flush between the text lines.  This module
;; adds that air visually: jit-lock-managed overlays put extra
;; `line-spacing' below the row before a display-math opener and below
;; its closer's row, sized from the document class's real skips.
;;
;; This is the surviving slice of a larger "page look" experiment
;; (uniform \baselineskip leading, \textwidth column with fit-width,
;; \parindent, fold-string restyling) — all rolled back at the user's
;; request on 2026-08-13; only the display-math separation was kept.
;; See CLAUDE.md "Page look" for what was learned before reintroducing
;; any of it.
;;
;; Requires a graphical frame — the Termux profile must not load this.
;;
;; Class metrics were measured once from real compiles (\typeout of
;; \the\abovedisplayskip etc.).  v1 limitations, on purpose: pt-size
;; class options are ignored (the alist entries ARE the sizes this
;; repo's documents use: amsart a4paper 11pt, article 10pt), the
;; *shortskip variants are ignored, and `$$' display math is not
;; recognized (write `\[ ... \]').

;;; Code:

(defvar flow-page-mode)                 ; define-minor-mode, below

;;; --- Class metrics ----------------------------------------------------------

(defconst flow-page-class-metrics-alist
  ;; Measured: article 10pt → BS=12pt ADS=10pt (0.83 line);
  ;;           amsart a4paper 11pt → BS=13pt ADS=4.55pt (0.35 line).
  '((amsart  . (:baseline 1.187 :above-skip 0.35 :below-skip 0.35))
    (amsbook . (:baseline 1.187 :above-skip 0.35 :below-skip 0.35))
    (article . (:baseline 1.20 :above-skip 0.83 :below-skip 0.83))
    (report  . (:baseline 1.20 :above-skip 0.83 :below-skip 0.83))
    (book    . (:baseline 1.20 :above-skip 0.83 :below-skip 0.83)))
  "Map document class symbol → skip metrics.
:baseline is \\baselineskip as a multiple of the font size;
:above-skip/:below-skip are \\abovedisplayskip etc. as a fraction of
one baseline.  Unknown classes fall back to `article'.")

(defun flow-page--doc-class ()
  "Best guess at this buffer's document class symbol, or nil.
Tries AUCTeX's parse, then a \\documentclass regex, then — for
Stacks-style chapters that only `\\input' a preamble — the first
\\input'ed file next to this one."
  (or (and (bound-and-true-p LaTeX-provided-class-options)
           (intern (caar LaTeX-provided-class-options)))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (let ((bound (min (point-max) 10000)))
            (cond
             ((re-search-forward
               "^[^%\n]*\\\\documentclass\\(?:\\[[^]]*\\]\\)?{\\([A-Za-z-]+\\)}"
               bound t)
              (intern (match-string 1)))
             ((re-search-forward "^[^%\n]*\\\\input{\\([^}]+\\)}" bound t)
              (let* ((name (match-string 1))
                     (file (expand-file-name
                            (if (string-suffix-p ".tex" name) name
                              (concat name ".tex"))
                            default-directory)))
                (when (file-readable-p file)
                  (with-temp-buffer
                    (insert-file-contents file nil 0 4000)
                    (goto-char (point-min))
                    (when (re-search-forward
                           "^[^%\n]*\\\\documentclass\\(?:\\[[^]]*\\]\\)?{\\([A-Za-z-]+\\)}"
                           nil t)
                      (intern (match-string 1)))))))))))))

(defun flow-page--metrics ()
  "Skip metrics plist for this buffer's class (article fallback)."
  (or (cdr (assq (flow-page--doc-class) flow-page-class-metrics-alist))
      (cdr (assq 'article flow-page-class-metrics-alist))))

;;; --- Display-math skips (jit-lock scanner) ----------------------------------

(defconst flow-page--display-open-re
  (concat "^[ \t]*\\(?:\\(\\\\\\[\\)\\|\\\\begin{\\("
          (regexp-opt '("equation" "align" "gather" "multline"
                        "eqnarray" "displaymath"))
          "\\*?\\)}\\)")
  "Opener of a display-math block at (possibly indented) line start.
Group 1 = \\=\\[, group 2 = environment name.")

(defsubst flow-page--make-ov (beg end &rest props)
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'flow-page t)
    (overlay-put ov 'evaporate t)
    (while props
      (overlay-put ov (pop props) (pop props)))
    ov))

(defvar flow-page--scan-slack 4000
  "How far beyond the jit-lock chunk the scanner looks for context.")

(defun flow-page--skip-px ()
  "(ABOVE-PX . BELOW-PX) for this buffer's class at the current font size.
`font-info' of the effective default font already reflects the
latex-font-sync remap AND `text-scale-mode' (measured), so the skips
track font and zoom with no extra bookkeeping — recomputed on every
scan, which is cheap (the opened font is cached by Emacs)."
  (when (display-graphic-p)
    (let* ((fi (ignore-errors (font-info (face-font 'default))))
           (m (flow-page--metrics)))
      (when fi
        ;; index 2 = em pixel size; one baseline in px:
        (let* ((baseline-px (* (plist-get m :baseline) (aref fi 2)))
               (base (or line-spacing 0)))
          (cons (+ base (round (* (plist-get m :above-skip) baseline-px)))
                (+ base (round (* (plist-get m :below-skip) baseline-px)))))))))

(defun flow-page--fontify (start end)
  "jit-lock function: display-math skip overlays.
The skip is expressed as `line-spacing' (space BELOW a row): below the
last row before the opener, and below the closer's row.  The overlay's
value replaces the buffer-wide `line-spacing' on that newline, so the
base value is included in it."
  (let ((skips (and flow-page-mode (flow-page--skip-px))))
    (when skips
      (save-excursion
        (save-restriction
          (widen)
          (let* ((ext-start (progn (goto-char (max (point-min)
                                                   (- start flow-page--scan-slack)))
                                   (line-beginning-position)))
                 (ext-end (progn (goto-char (min (point-max)
                                                 (+ end flow-page--scan-slack)))
                                 (line-end-position))))
            (remove-overlays ext-start ext-end 'flow-page t)
            (goto-char ext-start)
            (while (re-search-forward flow-page--display-open-re ext-end t)
              (let* ((env (match-string 2))
                     (open-bol (line-beginning-position))
                     (close-re (if env (concat "\\\\end{" (regexp-quote env) "}")
                                 "\\\\\\]"))
                     (close (save-excursion
                              (re-search-forward
                               close-re
                               (min (point-max) (+ ext-end flow-page--scan-slack))
                               t))))
                (when (and close (> open-bol (point-min)))
                  (flow-page--make-ov (1- open-bol) open-bol
                                      'line-spacing (car skips)))
                (when close
                  (let ((close-eol (save-excursion (goto-char close)
                                                   (line-end-position))))
                    (when (< close-eol (point-max))
                      (flow-page--make-ov close-eol (1+ close-eol)
                                          'line-spacing (cdr skips))))))))))
      ;; Tell jit-lock we handled the extended region.
      `(jit-lock-bounds ,(max (point-min) (- start flow-page--scan-slack))
                        . ,(min (point-max) (+ end flow-page--scan-slack))))))

;;; --- Minor mode -------------------------------------------------------------

(defun flow-page-refresh ()
  "Rebuild the skip overlays (e.g. after a font or zoom change)."
  (interactive)
  (when flow-page-mode
    (remove-overlays (point-min) (point-max) 'flow-page t)
    (jit-lock-refontify)))

(defun flow-page--on-text-scale ()
  "Buffer-local `text-scale-mode-hook': re-size skips to the new em."
  (flow-page-refresh))

;;;###autoload
(define-minor-mode flow-page-mode
  "Visually separate display math from text, like the compiled page.
Adds \\abovedisplayskip/\\belowdisplayskip-sized air around \\=\\[...\\=\\]
and display environments, derived from the document class
(`flow-page-class-metrics-alist') and the effective buffer font, so
`latex-font-sync' and `text-scale-adjust' are tracked automatically."
  :lighter " Page"
  (if flow-page-mode
      (progn
        (jit-lock-register #'flow-page--fontify)
        (add-hook 'text-scale-mode-hook #'flow-page--on-text-scale nil t))
    (jit-lock-unregister #'flow-page--fontify)
    (remove-hook 'text-scale-mode-hook #'flow-page--on-text-scale t)
    (remove-overlays (point-min) (point-max) 'flow-page t)))

(defun flow-page-enable-maybe ()
  "Enable `flow-page-mode' where the knob and the display allow it."
  (when (and (bound-and-true-p flow-page)
             (display-graphic-p)
             (derived-mode-p 'LaTeX-mode))
    (flow-page-mode 1)))

;; Depth 90: after latex-font-sync's applier on the same hook, so the
;; first scan usually already measures the document font.
(add-hook 'LaTeX-mode-hook #'flow-page-enable-maybe 90)

(provide 'flow-page)
;;; flow-page.el ends here

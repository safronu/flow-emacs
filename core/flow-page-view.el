;;; flow-page-view.el --- read the .tex buffer like the compiled page -*- lexical-binding: t; -*-
;;
;; Requires a graphical frame (Termux must not load this — it builds on
;; preview overlays that build needs images for).
;;
;; `flow-page-view-mode' makes a LaTeX buffer approximate the compiled
;; document while staying editable source.  Three ingredients, two of
;; them from this file:
;;
;;   1. Margins.  `olivetti-mode' centres the text as a fixed-width
;;      column (`flow-page-view-width') with empty margins either side,
;;      so a maximised window reads like a sheet of paper.
;;   2. Math renders itself.  `preview-auto-mode' (MELPA, needs AUCTeX
;;      >= 14.0.6) watches the window and runs preview-latex over any
;;      unrendered math that scrolls into view, and re-previews after
;;      edits — the buffer simply STAYS rendered; the fragment at point
;;      shows source, exactly like org-fragtog in .org files.  All
;;      renders go through the normal preview pipeline, so the
;;      char-metric DPI sizing from flow-preview.el applies unchanged.
;;   3. Everything else is already on from the other modules: TeX-fold
;;      collapses markup to styled text, latex-font-sync sets the
;;      document font, and `flow-latex-sectioning-scale' (a knob read by
;;      flow-latex.el) gives folded headings a PDF-like type scale.
;;
;; What this deliberately does NOT attempt in-buffer: justification,
;; page breaks, float placement, centring of display-math overlays
;; (AUCTeX overlays sit where the source sits; indent the source if you
;; want them off the left edge).  For the real thing there is
;; `flow-latex-live-pdf' below — a true compiled PDF in a side window,
;; refreshed on every save.
;;
;; Keys:
;;   C-c p v   toggle page view in this buffer
;;   C-c p l   toggle the live compiled-PDF side window

;;; Code:

;;; --- The two ingredient packages -------------------------------------------
;;
;; Both installs are guarded like org-fragtog in flow-preview.el: if the
;; one-time MELPA fetch failed (offline first launch), page view
;; degrades to "no margins / manual C-c p b" instead of erroring on
;; every .tex visit.

(use-package olivetti
  :preface
  (defun flow--olivetti-available-p ()
    (require 'olivetti nil 'noerror)))

(use-package preview-auto
  :preface
  (defun flow--preview-auto-available-p ()
    (require 'preview-auto nil 'noerror)))

;;; --- flow-page-view-mode ----------------------------------------------------

(define-minor-mode flow-page-view-mode
  "Read this LaTeX buffer like the compiled page.
Centres the text column with page-like margins (olivetti) and keeps all
math rendered as inline preview overlays automatically (preview-auto).
The fragment at point reverts to source while you are on it."
  :lighter " Page"
  (cond
   (flow-page-view-mode
    (unless (derived-mode-p 'LaTeX-mode)
      (setq flow-page-view-mode nil)
      (user-error "flow-page-view-mode is for LaTeX buffers"))
    (when (flow--olivetti-available-p)
      (setq-local olivetti-body-width flow-page-view-width)
      (olivetti-mode 1))
    (when (and (display-graphic-p) (flow--preview-auto-available-p))
      (preview-auto-mode 1)))
   (t
    (when (bound-and-true-p olivetti-mode) (olivetti-mode -1))
    (when (bound-and-true-p preview-auto-mode) (preview-auto-mode -1)))))

(defun flow-page-view-maybe ()
  "Enable `flow-page-view-mode' when the profile asks for it.
Hooked on `LaTeX-mode-hook' when `flow-page-view' is non-nil."
  (when (and flow-page-view (display-graphic-p))
    (flow-page-view-mode 1)))

(when flow-page-view
  (add-hook 'LaTeX-mode-hook #'flow-page-view-maybe))

;;; --- Live compiled PDF in a side window ------------------------------------
;;
;; The complement to page view: the actual pdflatex output, re-rendered
;; on every save, in a window beside the source.  Uses `latexmk -pvc'
;; when latexmk is installed (handles bibtex/multi-pass on its own; -pvc
;; watches the files, so saves recompile with no Emacs involvement).
;; Without latexmk it falls back to running pdflatex from an after-save
;; hook.  The PDF buffer displays via pdf-tools when installed, else
;; built-in doc-view (gs-based — fine for a refresh preview), with
;; auto-revert so each rebuild repaints the window.

(defvar-local flow--live-pdf-proc nil
  "The latexmk -pvc process watching this buffer's master, if any.")

(defvar-local flow--live-pdf-save-hook-installed nil
  "Non-nil when the pdflatex-on-save fallback is active in this buffer.")

(defun flow--live-pdf-master ()
  "Absolute path of the master .tex file, per AUCTeX."
  (expand-file-name (TeX-master-file "tex")))

(defun flow--live-pdf-output ()
  "Absolute path of the master's PDF output."
  (expand-file-name (TeX-master-file "pdf")))

(defun flow--live-pdf-compile-once ()
  "Compile the master once with pdflatex (fallback path, after save)."
  (let ((default-directory (file-name-directory (flow--live-pdf-master))))
    (start-process "flow-live-pdf-compile" "*flow-live-pdf*"
                   "pdflatex" "-interaction=nonstopmode"
                   "-synctex=1"
                   (file-name-nondirectory (flow--live-pdf-master)))))

(defun flow--live-pdf-display (pdf)
  "Show PDF in a side window with auto-revert, once it exists."
  (if (not (file-exists-p pdf))
      ;; First compile still running — retry until the file appears.
      (run-with-timer 1 nil #'flow--live-pdf-display pdf)
    (let ((buf (find-file-noselect pdf)))
      (with-current-buffer buf
        (auto-revert-mode 1))
      (display-buffer-in-side-window buf '((side . right))))))

(defun flow-latex-live-pdf ()
  "Toggle a continuously recompiled PDF of this document in a side window.
Prefers `latexmk -pvc' (recompiles whenever any input file changes);
falls back to pdflatex on every save when latexmk is not installed."
  (interactive)
  (unless (derived-mode-p 'LaTeX-mode)
    (user-error "Not in a LaTeX buffer"))
  (cond
   ;; Something is on — turn it all off.
   ((or (process-live-p flow--live-pdf-proc) flow--live-pdf-save-hook-installed)
    (when (process-live-p flow--live-pdf-proc)
      (interrupt-process flow--live-pdf-proc)
      (setq flow--live-pdf-proc nil))
    (when flow--live-pdf-save-hook-installed
      (remove-hook 'after-save-hook #'flow--live-pdf-compile-once t)
      (setq flow--live-pdf-save-hook-installed nil))
    (when-let* ((win (get-buffer-window
                      (get-file-buffer (flow--live-pdf-output)))))
      (delete-window win))
    (message "Live PDF: off"))
   ;; latexmk available — the good path.
   ((executable-find "latexmk")
    (let ((default-directory (file-name-directory (flow--live-pdf-master))))
      (setq flow--live-pdf-proc
            (start-process "flow-live-pdf" "*flow-live-pdf*"
                           "latexmk" "-pdf" "-pvc" "-view=none"
                           "-interaction=nonstopmode" "-synctex=1"
                           (file-name-nondirectory (flow--live-pdf-master)))))
    (flow--live-pdf-display (flow--live-pdf-output))
    (message "Live PDF: latexmk -pvc watching %s"
             (file-name-nondirectory (flow--live-pdf-master))))
   ;; Fallback: recompile on save.
   ((executable-find "pdflatex")
    (add-hook 'after-save-hook #'flow--live-pdf-compile-once nil t)
    (setq flow--live-pdf-save-hook-installed t)
    (flow--live-pdf-compile-once)
    (flow--live-pdf-display (flow--live-pdf-output))
    (message "Live PDF: recompiling on save (install latexmk for watch mode)"))
   (t (user-error "Neither latexmk nor pdflatex found on PATH"))))

;;; --- Keys -------------------------------------------------------------------

(with-eval-after-load 'latex
  (define-key LaTeX-mode-map (kbd "C-c p v") #'flow-page-view-mode)
  (define-key LaTeX-mode-map (kbd "C-c p l") #'flow-latex-live-pdf))

(provide 'flow-page-view)
;;; flow-page-view.el ends here

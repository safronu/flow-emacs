;;; flow-live-pdf.el --- compiled PDF beside the source, always fresh -*- lexical-binding: t; -*-
;;
;; `C-c p l' (`flow-latex-live-pdf') toggles a continuously recompiled
;; PDF of the current document.  Where it appears is asked in
;; ace-window's language: every window shows its selection letter, you
;; press one, and the PDF lands there — including ace-window's dispatch
;; keys, so from a single window `b' splits side-by-side first and then
;; asks again, `v' splits top/bottom, etc.  C-g cancels the whole thing.
;;
;; Recompilation: `latexmk -pvc' when latexmk is installed (watches all
;; input files and handles bibtex/multi-pass itself — saves recompile
;; with no Emacs involvement); otherwise pdflatex from a buffer-local
;; after-save hook.  Display: whatever `find-file' picks for PDFs
;; (pdf-tools when installed, else built-in doc-view, which renders via
;; ghostscript), plus `auto-revert-mode' so each rebuild repaints.
;;
;; Requires a graphical frame to be of any use; the Termux profile does
;; not load this file.

;;; Code:

;;; --- doc-view: make the fallback viewer actually pleasant ------------------
;;
;; Out of the box doc-view is why "the PDF looks bad": it rasterises
;; pages at a hardcoded 100 DPI and displays that bitmap 1:1, which on
;; a ~200 DPI panel is a 2x-blurry postage stamp.  And with
;; `doc-view-continuous' nil, C-n / the wheel stop dead at the bottom
;; of each page instead of flowing to the next.
;;
;; Render at double the display's REAL resolution (derived from
;; character metrics — the same trick as `preview-get-dpi' in
;; flow-preview.el, because the reported monitor size lies on both our
;; devices), then let doc-view's internal scaling fit the sharp bitmap
;; to the window.  Downscaling a 2x render is crisp; upscaling a 100
;; DPI render never can be.

(defun flow--display-dpi ()
  "The display's true DPI, from character metrics (reported size lies)."
  (/ (* (frame-char-height) 72.0)
     (/ (face-attribute 'default :height) 10.0)))

(with-eval-after-load 'doc-view
  (setq doc-view-resolution (min 600 (round (* 2 (flow--display-dpi))))
        ;; Scroll straight through page boundaries.
        doc-view-continuous t
        ;; Scale the rendered bitmap inside Emacs (native scaling) so
        ;; fit-to-window downsamples the sharp render.
        doc-view-scale-internally t))

(defun flow--live-pdf-tune-docview (buf window)
  "In doc-view BUF, make the page exactly fill WINDOW's width.
Two strategies, picked by what the display backend can do:

- With image scaling (laptop: X reports `scale' in `image-transforms-p'):
  keep the sharp 2x render and let doc-view downscale it to the window.
- Without scaling (the Android port has none): a big bitmap displays
  1:1 and forces horizontal scrolling, so instead RENDER at the
  resolution where a US-letter page width equals the window width —
  1:1 then fits by construction, at exactly the window's own pixel
  density (all a scaling-less display could show anyway)."
  (with-current-buffer buf
    (when (derived-mode-p 'doc-view-mode)
      (if (memq 'scale (image-transforms-p))
          (progn
            ;; Display width = the window it lives in, so the 2x render
            ;; is downscaled to exactly fit — sharp and fully visible.
            (setq-local doc-view-image-width
                        (max 400 (window-body-width window t)))
            ;; auto-revert re-runs conversion on each rebuild; the
            ;; buffer-local width survives, so nothing else is needed to
            ;; stay fitted.  The fit command errors if the first page
            ;; conversion hasn't finished yet — harmless then, since the
            ;; width above already applies once the image appears.
            (ignore-errors (doc-view-fit-width-to-window)))
        ;; 8.5in = US letter width; A4 (8.27in) comes out a hair
        ;; narrower than the window, which errs on the fitting side.
        (setq-local doc-view-resolution
                    (max 72 (round (/ (window-body-width window t) 8.5))))
        (ignore-errors (doc-view-reconvert-doc))))))

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
                   "pdflatex" "-interaction=nonstopmode" "-synctex=1"
                   (file-name-nondirectory (flow--live-pdf-master)))))

(defun flow--live-pdf-pick-window ()
  "Ask for a target window in ace-window's language; return it.
Falls back to `next-window' when ace-window isn't available (offline
first launch).  The selection happens NOW, in the interactive call —
never from the deferred display timer, which must not steal focus to
prompt."
  (if (require 'ace-window nil 'noerror)
      (aw-select " Flow live-PDF: pick a window")
    (next-window)))

(defun flow--live-pdf-display (pdf window)
  "Show PDF in WINDOW with auto-revert, waiting for the file to appear."
  (if (not (file-exists-p pdf))
      ;; First compile still running — poll until the file appears.
      (run-with-timer 1 nil #'flow--live-pdf-display pdf window)
    (let ((buf (find-file-noselect pdf)))
      (with-current-buffer buf
        (auto-revert-mode 1))
      (if (window-live-p window)
          (progn (set-window-buffer window buf)
                 (select-window window)
                 (flow--live-pdf-tune-docview buf window))
        ;; The chosen window died while we compiled; don't re-prompt from
        ;; a timer — just show the buffer wherever display-buffer likes.
        (when-let* ((win (display-buffer buf)))
          (flow--live-pdf-tune-docview buf win))))))

(defun flow-latex-live-pdf ()
  "Toggle a continuously recompiled PDF of this document.
Asks which window to use ace-window-style (labels in every window;
dispatch keys like `b'/`v' split first).  Recompiles via `latexmk -pvc'
when available, else with pdflatex on every save."
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
    (when-let* ((buf (get-file-buffer (flow--live-pdf-output)))
                (win (get-buffer-window buf)))
      (delete-window win))
    (message "Live PDF: off"))
   ;; latexmk available — the good path.
   ((executable-find "latexmk")
    (let ((window (flow--live-pdf-pick-window))   ; ask BEFORE starting anything
          (default-directory (file-name-directory (flow--live-pdf-master))))
      (setq flow--live-pdf-proc
            (start-process "flow-live-pdf" "*flow-live-pdf*"
                           "latexmk" "-pdf" "-pvc" "-view=none"
                           "-interaction=nonstopmode" "-synctex=1"
                           (file-name-nondirectory (flow--live-pdf-master))))
      (flow--live-pdf-display (flow--live-pdf-output) window)
      (message "Live PDF: latexmk -pvc watching %s"
               (file-name-nondirectory (flow--live-pdf-master)))))
   ;; Fallback: recompile on save.
   ((executable-find "pdflatex")
    (let ((window (flow--live-pdf-pick-window)))
      (add-hook 'after-save-hook #'flow--live-pdf-compile-once nil t)
      (setq flow--live-pdf-save-hook-installed t)
      (flow--live-pdf-compile-once)
      (flow--live-pdf-display (flow--live-pdf-output) window)
      (message "Live PDF: recompiling on save (install latexmk for watch mode)")))
   (t (user-error "Neither latexmk nor pdflatex found on PATH"))))

(with-eval-after-load 'latex
  (define-key LaTeX-mode-map (kbd "C-c p l") #'flow-latex-live-pdf))

(provide 'flow-live-pdf)
;;; flow-live-pdf.el ends here

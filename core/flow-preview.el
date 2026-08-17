;;; flow-preview.el --- inline math previews for .tex and .org -*- lexical-binding: t; -*-
;;
;; Requires a graphical frame — terminal Emacs (the Termux profile) must
;; NOT load this file; it has no image support at all.
;;
;; Keys, identical in .tex and .org buffers so the muscle memory is one:
;;   C-c p p   preview the construct at point (formula / environment / section)
;;   C-c p b   preview the whole buffer
;;   C-c p c   clear previews
;; Org's native C-c C-x C-l keeps working unchanged.
;;
;; ── Why DPI is computed here instead of trusted ─────────────────────────
;; Both preview.el and org compute their rendering resolution from the
;; frame's reported physical size, and BOTH devices lie about it:
;;   * native Android Emacs reports a frame roughly 3 metres wide, so the
;;     built-in computation lands near 9 DPI and previews come out as
;;     invisible specks;
;;   * X (and XWayland) report a screen size derived from a hardcoded
;;     96 DPI — on the laptop's 3200x2000 panel that is off by ~2x, so
;;     previews come out at half the size of the text around them.
;; Font metrics don't lie — but the RIGHT metric is the em, not the
;; line.  A font opened at `face-pt' points has an em of exactly
;; face-pt/72 inch, and `font-info' reports the real pixel size that em
;; came out at, scaling included.  Deriving DPI from that makes a 10pt
;; glyph in a rendered formula the same optical size as a glyph of the
;; buffer text around it — which is how the compiled PDF looks, where
;; text and math share the point size.  The earlier derivation here
;; used `frame-char-height', which is the LINE height (ascent + descent
;; + leading): with JetBrains Mono that is 1.34x the em, and previews
;; came out exactly that much oversized on every device.  The line
;; height remains the fallback where `font-info' is unavailable.
;; This also makes previews track the default-face height and
;; `text-scale-adjust' automatically.
;; Do not restore either built-in.  They are two functions on purpose —
;; `preview-get-dpi' returns a CONS, `org--get-display-dpi' a NUMBER, and
;; they serve different callers.  Do not merge or "deduplicate" them.

;;; Code:

(defun flow-preview--base-dpi ()
  "Emacs's rendering DPI, derived from the default font's em size.
Uses the buffer's effective default font, so a `latex-font-sync'
remap (serif document font) is measured as displayed.  Falls back to
`frame-char-height' (the line height — slightly too large) on
backends where `font-info' returns nil."
  (let* ((face-pt (/ (face-attribute 'default :height) 10.0))
         (em-px   (or (ignore-errors
                        (aref (font-info (face-font 'default)) 2))
                      (frame-char-height))))
    (/ (* em-px 72.0) face-pt)))

;;; --- AUCTeX preview-latex -------------------------------------------------
;;
;; AUCTeX's `preview' subsystem shells out to a LaTeX run producing one
;; image per formula, then overlays those images on the source.
;;
;; NOTE on image types: valid values of `preview-image-type' are `png',
;; `jpeg', `pnm', `tiff' (all via Ghostscript on the PDF) and `dvi*'
;; (which runs `preview-dvi*-command', e.g. dvisvgm, on a DVI file).  SVG
;; output requires the DVI pipeline, i.e. `TeX-PDF-mode' nil, giving up
;; hyperref and friends.  With pdflatex the answer is PNG.

(use-package preview
  ;; `preview' ships INSIDE AUCTeX.  There is no standalone `preview'
  ;; package on any archive, so use-package must not try to install it —
  ;; otherwise startup errors out here and everything below is skipped.
  :ensure nil
  :after latex
  :config
  (defun flow-preview--optical-factor ()
    "Extra scale needed for previews to LOOK the size of the buffer text.
Previews are typeset by the document's own preamble, i.e. in the
document font.  When `latex-font-sync' has remapped the buffer to that
same font (`my/latex-current-family' non-nil), equal ems ARE equal
optical size — factor 1.  When the buffer still shows the code font,
its x-height (~0.53 em for JetBrains Mono) dwarfs the math font's
(~0.43 em), and `flow-preview-scale' closes that gap."
    (if (bound-and-true-p my/latex-current-family) 1.0 flow-preview-scale))

  (defun flow-preview-scale ()
    "`preview-scale-from-face', times the buffer-dependent optical factor."
    (* (flow-preview--optical-factor) (funcall (preview-scale-from-face))))

  (setq preview-image-type 'png
        ;; Face scale = face-pt / doc-pt (e.g. 15pt / 10pt = 1.5).  With
        ;; DPI below set to Emacs's actual rendering resolution, that
        ;; alone makes one preview em equal one buffer em; the flow
        ;; function multiplies in the x-height compensation.
        preview-scale-function #'flow-preview-scale
        preview-auto-reveal t)

  ;; Overfull display math: tightpage sizes each snippet's PDF page from
  ;; \wd of the snippet box; amsmath packs display rows to
  ;; \displaywidth, so an overfull display sticks out past the page's
  ;; right edge and the PNG is clipped mid-formula.
  ;; core/preview/prflowwidth.def re-measures each snippet at shipout
  ;; and widens the page by the overhang.  It is pulled in as an unknown
  ;; preview option ("flowwidth" -> \InputIfFileExists{prflowwidth.def}),
  ;; found via TEXINPUTS.  Must stay AFTER "tightpage" in the option
  ;; list (load order decides whose shipout code runs first).  A missing
  ;; file degrades silently to today's clipped behavior.
  (let ((dir (flow-core-file "preview")))
    (unless (member dir (split-string (or (getenv "TEXINPUTS") "") ":"))
      ;; Trailing separator keeps kpathsea's default search path.
      (setenv "TEXINPUTS" (concat dir ":" (getenv "TEXINPUTS")))))
  (add-to-list 'preview-required-option-list "flowwidth" 'append)

  (defun preview-get-dpi ()
    "Emacs's real rendering resolution, from the default font's em size.
Scaled by the buffer's `text-scale-mode-amount' so C-x C-+ / C-x C--
resize previews along with the text."
    (let* ((base-dpi (flow-preview--base-dpi))
           (zoom     (if (bound-and-true-p text-scale-mode)
                         (expt text-scale-mode-step text-scale-mode-amount)
                       1.0))
           (dpi      (* base-dpi zoom)))
      (cons dpi dpi)))

  ;; When the buffer's text-scale changes, existing overlays keep their old
  ;; pixel size.  Clear them so the next C-c p p regenerates at the new zoom.
  (add-hook 'text-scale-mode-hook
            (lambda ()
              (when (derived-mode-p 'LaTeX-mode)
                (preview-clearout-buffer)))))

(defun flow-latex-preview-at-point ()
  "Preview the LaTeX construct around point as an inline overlay.
In math, previews just the formula; otherwise the enclosing environment;
otherwise the section."
  (interactive)
  (cond
   ((use-region-p) (preview-region (region-beginning) (region-end)))
   ((and (fboundp 'texmathp) (texmathp))
    (save-excursion
      (let* ((env (car texmathp-why))
             (beg (cdr texmathp-why))
             (end (save-excursion
                    (goto-char beg)
                    (cond
                     ((equal env "$")   (forward-char 1)
                      (or (search-forward "$" nil t) (point-max)))
                     ((equal env "$$")  (forward-char 2)
                      (or (search-forward "$$" nil t) (point-max)))
                     ((equal env "\\(") (forward-char 2)
                      (or (search-forward "\\)" nil t) (point-max)))
                     ((equal env "\\[") (forward-char 2)
                      (or (search-forward "\\]" nil t) (point-max)))
                     (t (or (search-forward (format "\\end{%s}" env) nil t)
                            (point-max)))))))
        (preview-region beg end))))
   (t (preview-section))))

;; The command used to be `my/latex-preview-at-point'; keep the old name
;; working for muscle memory and for any stale keybinding.
(defalias 'my/latex-preview-at-point #'flow-latex-preview-at-point)

;;; --- Unified display controls: previews + folds + font on one keymap ------
;;
;; C-c p is the single "what does this buffer show" prefix, switching
;; between two buffer states modelled by the buffer-local
;; `flow-latex-doc-mode' (lighter " Doc"):
;;   raw code  — mode off: default (code) font, no folds, no previews.
;;               How every buffer opens; C-c p c returns here.
;;   document  — mode on: doc font (latex-font-sync), markup folded,
;;               math previewed; C-c p b enters (or refreshes) it.
;; C-c p p is the per-item control (preview or fold at point) and never
;; touches the buffer font — that is a buffer-wide property.  Nothing
;; folds, previews, or re-fonts on its own (see flow-latex.el and
;; latex-font-sync.el).  Syntax highlighting (font-latex) is a separate
;; always-on layer and is never touched here.

(defun flow-preview--fold-ready-p ()
  "Non-nil when TeX-fold commands are usable in the current buffer."
  (and (bound-and-true-p flow-latex-fold)
       (bound-and-true-p TeX-fold-mode)
       (fboundp 'flow-tex-fold-env-markers)))

(defun flow-latex-display-at-point ()
  "Preview or fold the construct at point — unified display control.
With an active region or in math, preview it (see
`flow-latex-preview-at-point').  On an existing fold, unfold it.  On a
foldable macro, fold it; on \\begin/\\end or elsewhere inside an
environment, fold that environment's begin/end markers
\(`flow-tex-fold-env-markers').  Otherwise fall back to previewing the
section.  \\verb bodies fold only via `flow-latex-display-buffer' —
AUCTeX folds them per-region, not per-item."
  (interactive)
  (cond
   ((or (use-region-p) (and (fboundp 'texmathp) (texmathp)))
    (flow-latex-preview-at-point))
   ((and (flow-preview--fold-ready-p)
         (or
          ;; Point on a fold → remove it (per-item toggle).
          (TeX-fold-clearout-item)
          ;; Point on a macro → fold it; \begin/\end mean "the env".
          (let ((ms (TeX-find-macro-start)))
            (if (and ms (save-excursion
                          (goto-char ms)
                          (looking-at (concat (regexp-quote TeX-esc)
                                              "\\(?:begin\\|end\\)\\b"))))
                (flow-tex-fold-env-markers)
              (and ms (TeX-fold-item 'macro))))
          ;; Inside an environment → fold its markers.
          (flow-tex-fold-env-markers))))
   (t (preview-section))))

(define-minor-mode flow-latex-doc-mode
  "Document look for a LaTeX buffer: doc font, folded markup, previews.
Buffer-local; the \" Doc\" lighter answers \"which state is this
buffer in\".  Enabling applies the document font FIRST
(`latex-font-sync-apply' changes the buffer's character metrics,
clears stale previews, and `flow-preview--optical-factor' must see
the synced family so the previews rendered next come out at factor
1), then folds all markup and renders all previews (the preview
compile finishes asynchronously); line numbers are hidden — they
belong to the raw-code look and come back on exit.  Enabling while
already on re-runs
all three — C-c p b doubles as a refresh after edits.  Disabling
clears every preview and fold — including ones made per-item with
C-c p p; the mode owns the whole display state on exit — and reverts
to the code font.  Font-lock styling is untouched either way."
  :lighter " Doc"
  (if flow-latex-doc-mode
      (progn
        ;; Line numbers are part of the raw-code look (enabled on
        ;; LaTeX-mode-hook in flow-latex.el); the document page has none.
        (display-line-numbers-mode -1)
        (when (fboundp 'latex-font-sync-apply)
          (latex-font-sync-apply))
        (when (flow-preview--fold-ready-p)
          (TeX-fold-buffer))
        (preview-buffer))
    (preview-clearout-buffer)
    (when (flow-preview--fold-ready-p)
      (TeX-fold-clearout-buffer))
    (when (fboundp 'latex-font-sync-revert)
      (latex-font-sync-revert))
    (display-line-numbers-mode 1)))

(defun flow-latex-display-buffer ()
  "Enter (or refresh) `flow-latex-doc-mode' — the document look.
Deliberately not a toggle: pressing it in document mode re-folds and
re-previews the buffer after edits."
  (interactive)
  (flow-latex-doc-mode 1))

(defun flow-latex-display-clearout-buffer ()
  "Exit `flow-latex-doc-mode' — back to raw code.
Works from any state: clears previews and folds (even hand-made ones)
and restores the default (code) font."
  (interactive)
  (flow-latex-doc-mode -1))

(with-eval-after-load 'latex
  (define-key LaTeX-mode-map (kbd "C-c p p") #'flow-latex-display-at-point)
  (define-key LaTeX-mode-map (kbd "C-c p b") #'flow-latex-display-buffer)
  (define-key LaTeX-mode-map (kbd "C-c p c") #'flow-latex-display-clearout-buffer)
  ;; One-chord toggle for the two display states ("page").  M-p and M-n
  ;; are the only modifier-letter chords unbound in a .tex buffer with
  ;; the full stack active (AUCTeX + cdlatex + yas + RefTeX + TeX-fold,
  ;; enumerated 2026-08-17) — the pair Emacs convention reserves for
  ;; modes.  The minor-mode command itself is the toggle; C-c p b stays
  ;; the enter-or-REFRESH key, which a toggle cannot be.
  (define-key LaTeX-mode-map (kbd "M-p") #'flow-latex-doc-mode))

;;; --- Org-mode fragment previews -------------------------------------------
;;
;; Org has its own preview pipeline, entirely separate from AUCTeX's.
;; Two deliberate departures from org's stock configuration:
;;
;;  - `:latex-header' builds the snippet on the `standalone' class,
;;    because org's default header is a full `article' page and cropping
;;    is normally the converter's job (dvipng -T tight, convert -trim);
;;    ghostscript has no crop switch, so the PAGE itself must be tight.
;;    This header REPLACES org's default header and its package
;;    injection, hence the explicit package list.
;;  - PNG instead of SVG: the SVG pt→px mapping at display time is
;;    unmeasurable (which is why dvisvgm carries a hand-tuned 1.7
;;    adjustment); PNG at an exact `gs -r' resolution has no unknown, and
;;    matches the .tex flow by construction.

(with-eval-after-load 'org
  (when flow-org-preview-image-directory
    (setq org-preview-latex-image-directory flow-org-preview-image-directory))

  (add-to-list 'org-preview-latex-process-alist
               '(pdfpng
                 :programs ("pdflatex" "gs")
                 :description "pdf > png, AUCTeX-preview-equivalent sizing"
                 :message "you need to install pdflatex and ghostscript"
                 :image-input-type "pdf"
                 :image-output-type "png"
                 :image-size-adjust (1.0 . 1.0)
                 :latex-header
                 "\\documentclass[border=1pt,varwidth]{standalone}\n\\usepackage{amsmath,amssymb,mathtools}\n\\usepackage[normalem]{ulem}\n\\usepackage[T1]{fontenc}\n\\usepackage{color}"
                 :latex-compiler
                 ("pdflatex -interaction nonstopmode -output-directory %o %f")
                 :image-converter
                 ("gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pngalpha -r%D -sOutputFile=%O %f")))
  (setq org-preview-latex-default-process 'pdfpng)

  ;; Truly transparent fragments: org emits \pagecolor unless :background
  ;; is the STRING "Transparent" (the default, `default', resolves to the
  ;; face background and paints the page).  With pngalpha this makes
  ;; fragments sit on the page the way C-c p p overlays do.  :background
  ;; is part of the cache key, so the change regenerates images by itself.
  (plist-put org-format-latex-options :background "Transparent")

  ;; Fully automatic sizing, no knobs: recompute :scale from the CURRENT
  ;; default-face height and C-x C-+ zoom right before every render.  gs
  ;; then runs at -r%D = :scale × org--get-display-dpi, which equals
  ;; preview-latex's (face-pt/10) × char-metric DPI — the same sizing
  ;; equation the .tex flow uses.  `face-attribute' returns the BASE
  ;; height (text-scale works by face remapping), so the zoom factor is
  ;; not double-counted.  :scale is part of org's cache key, so a changed
  ;; font size or zoom regenerates images automatically and each rendered
  ;; size stays cached.  There is no size knob — do not add one back.
  (defun flow-org-latex-auto-scale (&rest _)
    "Set org preview :scale from font height, text-scale zoom, and
the `flow-preview-scale' x-height compensation (same factor as the
AUCTeX pipeline, so fragments match across .tex and .org)."
    (plist-put org-format-latex-options :scale
               (* flow-preview-scale
                  (/ (face-attribute 'default :height) 100.0)
                  (if (bound-and-true-p text-scale-mode)
                      (expt text-scale-mode-step text-scale-mode-amount)
                    1.0))))
  (advice-add 'org-latex-preview :before #'flow-org-latex-auto-scale)

  (defun flow-org-preview-buffer ()
    "Preview all LaTeX fragments in the buffer (like C-c p b in .tex)."
    (interactive)
    (org-latex-preview '(16)))
  (defun flow-org-preview-clearout-buffer ()
    "Clear all LaTeX fragment previews in the buffer (like C-c p c in .tex)."
    (interactive)
    (org-latex-preview '(64)))
  (define-key org-mode-map (kbd "C-c p p") #'org-latex-preview)
  (define-key org-mode-map (kbd "C-c p b") #'flow-org-preview-buffer)
  (define-key org-mode-map (kbd "C-c p c") #'flow-org-preview-clearout-buffer)

  ;; See the DPI note in this file's header.  Org wants a plain NUMBER.
  ;; NOTE: org's preview cache key does NOT include the DPI, so after any
  ;; change to THIS function stale images must be deleted by hand
  ;; (`org-preview-latex-image-directory', typically .../ltximg).
  ;; :scale changes need no such step — they re-key the cache.
  (defun org--get-display-dpi ()
    "Derive DPI from the default font's em size; the reported monitor size lies."
    (round (flow-preview--base-dpi))))

;;; --- org-fragtog: auto-toggle previews at point ---------------------------
;;
;; Matches the .tex flow's UX: AUCTeX overlays reveal their source when
;; point enters and re-close on exit.  Org's own overlays only vanish on
;; MODIFICATION — point motion does nothing.  org-fragtog watches point
;; via a buffer-local `post-command-hook': entering a fragment clears its
;; preview (source appears), leaving one that has no overlay re-runs
;; `org-latex-preview' on it.  Worth knowing:
;;  - an unchanged fragment re-displays instantly from org's disk cache;
;;  - ANY fragment you leave gets previewed, including ones you merely
;;    cursored through; the FIRST render of a fragment is a synchronous
;;    compile (a brief pause), after which it is cached;
;;  - it goes through the normal `org-latex-preview' entry point, so the
;;    sizing setup above applies unchanged;
;;  - if some org buffer suffers from cursor-motion compiles or `$5'-style
;;    false math (an LLM chat log, say), scope it down there with
;;    `org-fragtog-ignore-predicates' or `(org-fragtog-mode -1)' — don't
;;    rip out the hook.
;;
;; The hook goes through `flow-org-fragtog-maybe', NOT `org-fragtog-mode'
;; directly, ON PURPOSE: if the one-time install failed (offline first
;; launch), a direct hook would leave a dangling autoload that errors on
;; EVERY .org visit and — because add-hook prepends — would also stop
;; cdlatex/yasnippet from enabling in org buffers.  The guard degrades to
;; "no auto-toggle" instead.

(use-package org-fragtog
  :preface
  (defun flow-org-fragtog-maybe ()
    "Enable `org-fragtog-mode' if the package is available; else no-op."
    (when (require 'org-fragtog nil 'noerror)
      (org-fragtog-mode 1)))
  :hook (org-mode . flow-org-fragtog-maybe))

(provide 'flow-preview)
;;; flow-preview.el ends here

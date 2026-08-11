;;; init.el --- LaTeX-for-impatient-scholars on native Android Emacs -*- lexical-binding: t; -*-
;;
;; Adapted from Karthik Chikmagalur's "LaTeX Input for Impatient Scholars":
;;   https://karthinks.com/software/latex-input-for-impatient-scholars/
;;   https://gist.github.com/karthink/7d89df35ee9b7ac0c93d0177b862dadb
;;
;; Runs under the native Android Emacs port (org.gnu.emacs), which ships with
;; librsvg / libjpeg / libtiff / cairo — so we get REAL inline `preview-latex'
;; overlays.  The heavy lifting (pdflatex, dvisvgm, ghostscript) is done by
;; the TeX Live installed under Termux at /data/data/com.termux/files/usr, and
;; those binaries are self-contained enough to run from this app's process.
;;
;; Bindings:
;;   C-c C-p C-p     AUCTeX preview at point (inline PNG overlay)
;;   C-c C-p C-b     AUCTeX preview whole buffer
;;   C-c C-p C-c C-p AUCTeX preview-clearout-at-point (clear one overlay)
;;   C-c p p         my/latex-preview-at-point (inline overlay via AUCTeX)
;;   C-c p b         preview-buffer
;;   C-c p c         preview-clearout-buffer

;;; --- Package system -------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

;; Divert Customize output to its own file so we don't accumulate
;; `custom-set-variables' / `custom-set-faces' blocks at the tail of
;; init.el.  The old inline block silently rewrote
;; `package-selected-packages' to nil on every startup, which broke
;; `package-autoremove'.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage)

;; NEVER refresh archives at startup.  On a mobile connection this blocks the
;; UI for a long time (or forever if the network is asleep).  Bootstrap only:
;; if `use-package' isn't there yet, refresh once and install it.  After that,
;; the user runs `M-x package-refresh-contents' manually when they want
;; updates.  Emacs ≥27 has already called `package-initialize' by this point.
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t
      ;; If a use-package block references a not-yet-installed package,
      ;; don't silently fetch it — bail loudly so startup isn't blocked
      ;; by a network call the user didn't ask for.
      use-package-always-defer nil)

;; Install the current GNU ELPA signing key on first run so signatures work
;; later.  Wrapped in `ignore-errors' so it can't wedge startup.
(unless (package-installed-p 'gnu-elpa-keyring-update)
  (ignore-errors (package-install 'gnu-elpa-keyring-update)))

;; Once the keyring bootstrap has succeeded, re-enable signature checking
;; for subsequent `package-install' / `package-refresh-contents' calls.
;; early-init.el keeps `nil' so first-ever run can still bootstrap.
(when (package-installed-p 'gnu-elpa-keyring-update)
  (setq package-check-signature 'allow-unsigned))

;;; --- Sane defaults for the Boox tablet ------------------------------------

(setq inhibit-startup-screen t
      make-backup-files nil
      auto-save-default nil
      ring-bell-function 'ignore
      use-short-answers t)
(setq-default indent-tabs-mode nil
              tab-width 2
              fill-column 80)
(when (fboundp 'pixel-scroll-precision-mode) (pixel-scroll-precision-mode 1))
(column-number-mode 1)
(show-paren-mode 1)
(electric-pair-mode 1)
(save-place-mode 1)
(recentf-mode 1)
(setq recentf-max-saved-items 200)

;; E-ink friendly: no blink, no cursor movement animation, high contrast.
(blink-cursor-mode -1)
(setq scroll-conservatively 100
      scroll-margin 2
      scroll-preserve-screen-position t)
(when (display-graphic-p)
  (load-theme 'modus-operandi t)                 ; pure white background
  (set-face-attribute 'default nil :height 150)) ; readable on a 13" e-ink panel

;; Bring Termux binaries onto exec-path so pdflatex / dvisvgm / gs / tlmgr all
;; resolve when Emacs calls them via `call-process' / `start-process'.  These
;; binaries are self-contained and run under this app's process just fine.
(dolist (dir '("/data/data/com.termux/files/usr/bin"
               "/data/data/com.termux/files/usr/bin/texlive"
               "/data/data/com.termux/files/usr/share/texlive/2026/bin/aarch64-linux"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (or (getenv "PATH") "")))))

;; TEXMFROOT is set in early-init.el; everything else (TEXMFDIST, TEXMFVAR,
;; TEXMFSYSVAR) is derived from it by kpathsea via texmf.cnf.

;;; --- ace-window: manage ALL windows with M-o ------------------------------
;;
;; `aw-dispatch-always t' makes M-o always enter selection mode, even with
;; one or two windows.  Press a window letter to jump, or an action key
;; first: b = split side-by-side, v = split top/bottom, x = close a
;; window, o = keep only one, m = swap, ? = help, C-g = cancel.  So a
;; single window needs no C-x 2/3/0/1 at all: M-o b splits and M-o x
;; closes.  `?j' is removed from `aw-keys' because `j' is a dispatch
;; action (select buffer) — the two sets must not overlap.
;; `aw-background nil' is deliberate for e-ink: the default dims the whole
;; frame during selection, which forces a full-screen repaint (ghosting).

(use-package ace-window
  :bind ("M-o" . ace-window)
  :config
  (setq aw-keys '(?a ?s ?d ?f ?g ?h ?k ?l)  ; home row, minus dispatch char j
        aw-dispatch-always t               ; letters + actions even with 1-2 windows
        aw-background nil                  ; no full-frame dim on e-ink
        aw-scope 'frame)
  ;; Make the selection letters big enough to spot on a 13" panel.
  (set-face-attribute 'aw-leading-char-face nil
                      :height 2.5 :weight 'bold))

;;; --- AUCTeX ---------------------------------------------------------------

(use-package tex
  :ensure auctex
  :demand t
  :preface
  (defun my/latex-preview-at-point ()
    "Preview the LaTeX construct around point as an inline overlay.
If in math, previews just the formula; otherwise previews the enclosing
environment; otherwise the section."
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
  ;; No prettify-symbols-mode: replacing `\pi' with `π' in-buffer breaks
  ;; editing (super/subscripts jump above/below the baseline, integral
  ;; glyphs are hard to point at with a stylus).  Use `C-c p p' to see
  ;; the rendered form as an overlay when you want it.
  :hook ((LaTeX-mode . visual-line-mode))
  :bind (:map LaTeX-mode-map
              ("C-S-e"   . latex-math-from-calc)
              ("C-c p p" . my/latex-preview-at-point)
              ("C-c p b" . preview-buffer)
              ("C-c p c" . preview-clearout-buffer))
  :config
  (require 'latex)
  (require 'texmathp)
  (setq TeX-parse-self t
        TeX-auto-save t
        TeX-master nil
        TeX-electric-math '("$" . "$")
        TeX-electric-sub-and-superscript t
        LaTeX-electric-left-right-brace t
        ;; Use pdflatex; it's the default LaTeX engine we installed.
        TeX-engine 'default
        ;; Don't raise `^{...}' / lower `_{...}' graphically via display
        ;; properties — the visual shift makes the caret jump across lines
        ;; when editing and looks off on e-ink.  Rely on preview overlays.
        font-latex-fontify-script nil
        font-latex-fontify-sectioning 1.0)

  ;; Make `\textbf{...}' / `\textit{...}' render as actual bold / italic
  ;; on-screen so the buffer looks close to the compiled document.  The
  ;; defaults tint them olive-green, which on e-ink drowns out the weight
  ;; and slant change — strip the color so the weight/slant is the only
  ;; visual cue.  The family cascades from the buffer default (see
  ;; latex-font-sync), so `\textbf{X}' becomes e.g. `TeX Gyre Pagella
  ;; Bold' when the document uses mathpazo.
  (with-eval-after-load 'font-latex
    (dolist (face '(font-latex-bold-face
                    font-latex-italic-face
                    font-latex-math-face
                    font-latex-sedate-face
                    font-latex-string-face
                    font-latex-warning-face
                    font-latex-verbatim-face))
      (when (facep face)
        (set-face-attribute face nil :foreground 'unspecified)))
    ;; Force the weight/slant explicitly in case some theme cleared them.
    (set-face-attribute 'font-latex-bold-face   nil :weight 'bold :slant 'normal)
    (set-face-attribute 'font-latex-italic-face nil :weight 'normal :slant 'italic))

  (defun latex-math-from-calc ()
    "Evaluate `calc' on the contents of line at point."
    (interactive)
    (cond ((region-active-p)
           (let* ((beg (region-beginning))
                  (end (region-end))
                  (string (buffer-substring-no-properties beg end)))
             (kill-region beg end)
             (insert (calc-eval `(,string calc-language latex
                                          calc-prefer-frac t
                                          calc-angle-mode rad)))))
          (t (let ((l (thing-at-point 'line)))
               (end-of-line 1) (kill-line 0)
               (insert (calc-eval `(,l
                                    calc-language latex
                                    calc-prefer-frac t
                                    calc-angle-mode rad))))))))

;;; --- RefTeX: reference navigation for Stacks-style notes ------------------
;;
;; RefTeX is a BUILT-IN package (it ships inside Emacs and is not
;; distributed on any archive).  `package-installed-p' returns t for
;; built-ins, so `:ensure t' would merely be a useless check — but
;; `:ensure nil' states the intent explicitly (this repo's idiom for
;; anything that must never be fetched from an archive).
;;
;;   C-c )   insert \ref from a label menu; `x' in the menu switches to
;;           another chapter (any \externaldocument file in the preamble)
;;           and prepends its prefix automatically
;;   C-c &   jump from the \ref at point to the label definition — also
;;           across chapters (RefTeX prefix-matches against the
;;           \externaldocument declarations and parses that file on demand)
;;   C-c (   insert \label, auto-prefixed by environment (lemma- etc.)
;;   C-c =   table of contents; RET jumps
;;
;; `reftex-plug-into-AUCTeX t' turns on all five integration flags
;; (labels/refs/cites/index prompts are taken over by RefTeX).  It works
;; via `fset', so changing it needs an Emacs restart to undo.

(use-package reftex
  :ensure nil                ; built-in — never install from an archive
  :hook (LaTeX-mode . turn-on-reftex)
  :config
  ;; YaSnippet's minor-mode map claims `C-c &' as a PREFIX for its
  ;; snippet-management commands, and yas-minor-mode is on in every
  ;; LaTeX buffer here — whether it or RefTeX's `reftex-view-crossref'
  ;; wins the key would depend on minor-mode load order.  Free the key
  ;; unconditionally; snippet management stays reachable via
  ;; M-x yas-insert-snippet / M-x yas-visit-snippet-file.
  (with-eval-after-load 'yasnippet
    (define-key yas-minor-mode-map (kbd "C-c &") nil))
  (setq reftex-plug-into-AUCTeX t)
  ;; Teach RefTeX the theorem environments from the notes preamble, with
  ;; Stacks-style label prefixes (`lemma-…', not `lem:…').  Entry format:
  ;; (ENV KEY PREFIX REF-FORMAT CONTEXT MAGIC-WORDS).  KEY is the letter
  ;; typed at the `C-c )' type prompt — `?h' for theorem because `?t'
  ;; is taken by tables (same choice as RefTeX's own manual).  The magic
  ;; words mean typing e.g. "Lemma " right before `C-c )' preselects the
  ;; lemma menu.
  (setq reftex-label-alist
        '(("theorem"     ?h "theorem-"     "~\\ref{%s}" t ("theorem"     "thm."))
          ("proposition" ?p "proposition-" "~\\ref{%s}" t ("proposition" "prop."))
          ("lemma"       ?l "lemma-"       "~\\ref{%s}" t ("lemma"       "lem."))
          ("corollary"   ?c "corollary-"   "~\\ref{%s}" t ("corollary"   "cor."))
          ("definition"  ?d "definition-"  "~\\ref{%s}" t ("definition"  "def."))
          ("example"     ?x "example-"     "~\\ref{%s}" t ("example"))
          ("exercise"    ?X "exercise-"    "~\\ref{%s}" t ("exercise"))
          ("remark"      ?r "remark-"      "~\\ref{%s}" t ("remark")))))

;;; --- preview-latex: inline overlays (karthinks-style) ---------------------
;;
;; AUCTeX's `preview' subsystem shells out to a LaTeX run that produces one
;; image per formula, then overlays those images on top of the source.
;;
;; NOTE on image types: the valid values of `preview-image-type' are `png',
;; `jpeg', `pnm', `tiff' (all via Ghostscript on the PDF) and `dvi*' (which
;; uses `preview-dvi*-command' — e.g. dvisvgm — on a DVI file).  SVG output
;; requires the DVI pipeline (i.e. `TeX-PDF-mode nil'); with pdflatex we use
;; PNG.  On the Boox e-ink screen, PNG at scale 1.4 is crisp enough.

(use-package preview
  ;; `preview' ships inside AUCTeX (loaded above via :ensure auctex).  There
  ;; is no standalone `preview' package on any archive, so use-package must
  ;; NOT try to install it — otherwise startup errors out here and every
  ;; form below (including latex-font-sync) is skipped.
  :ensure nil
  :after latex
  :config
  (setq preview-image-type 'png
        ;; Default scale function = face-pt / doc-pt (e.g. 15pt / 10pt = 1.5).
        ;; With DPI overridden below to Emacs's actual rendering DPI, this
        ;; makes 1 preview em == 1 buffer em, so previews scale in lockstep
        ;; with the Emacs default face height.
        preview-scale-function #'preview-scale-from-face
        preview-auto-reveal t)

  ;; Android Emacs reports a bogus monitor physical size, so preview.el's
  ;; built-in `preview-get-dpi' computes garbage (~9 DPI).  Derive DPI from
  ;; the frame's actual character metrics, and scale by the buffer's
  ;; `text-scale-mode-amount' so `C-x C-+' / `C-x C--' also resize previews.
  ;; This tracks both global default-face changes AND per-buffer zoom.
  (defun preview-get-dpi ()
    (let* ((face-pt   (/ (face-attribute 'default :height) 10.0))
           (char-px   (float (frame-char-height)))
           (base-dpi  (/ (* char-px 72.0) face-pt))
           (zoom      (if (bound-and-true-p text-scale-mode)
                          (expt text-scale-mode-step text-scale-mode-amount)
                        1.0))
           (dpi       (* base-dpi zoom)))
      (cons dpi dpi)))

  ;; When the buffer's text-scale changes, existing overlays stay at their
  ;; old pixel size.  Clear them so the next `C-c p p' regenerates at the
  ;; new zoom level.
  (add-hook 'text-scale-mode-hook
            (lambda ()
              (when (derived-mode-p 'LaTeX-mode)
                (preview-clearout-buffer)))))

;;; --- Sync buffer font to LaTeX document font ------------------------------
;;
;; Remap the buffer's default face family to a TTF matching the document's
;; declared font package (mathpazo → TeX Gyre Pagella, times → TeX Gyre
;; Termes, etc.).  Only the `:family' is remapped; `:height' stays global
;; so previews continue to scale with the default face.  See
;; `latex-font-sync.el' for the detector / resolver / applier details.
;; TTFs are shipped in `android-emacs/fonts/' and symlinked into
;; `$HOME/fonts' by install.sh (Android Emacs enumerates that dir on launch).

;; Load by absolute path rather than adding `user-emacs-directory' to
;; `load-path' (Emacs ≥29 warns against the latter).
(load (expand-file-name "latex-font-sync" user-emacs-directory) nil 'nomessage)

;; Enable by default: aside from font matching the document, a side effect
;; of the buffer-local `:family' remap is that `TeX-fold' display strings
;; correctly render bold/italic for `\textbf'/`\emph'/etc.  Without the
;; remap in place, Android Emacs's font backend picks a regular-weight
;; font for the overlay's display string even when its face carries
;; `:weight bold'.  All bundled TTFs have been validated in-frame.
(latex-font-sync-mode 1)


;;; --- Code font for LaTeX syntactic markup --------------------------------
;;
;; `latex-font-sync' remaps the buffer's default :family to the document's
;; declared font — so `\textbf{...}' args, folded macro contents, section
;; titles all render in Pagella / Termes / Latin Modern.  But that also
;; drags macro NAMES (`\textbf', `\begin', `\ref') into the serif face,
;; where they get lost among the styled content.
;;
;; Remap the syntactic font-latex + font-lock faces (macro names, braces,
;; comments, env names, math delimiters) to a monospace family so code
;; stands apart from content at a glance.  Only :family is remapped;
;; foreground/weight from each face survive.  Content-styling faces
;; (`font-latex-bold-face', `-italic-face', `-underline-face', sectioning,
;; sub/super, verbatim, type) are deliberately *not* remapped, so they
;; keep inheriting the buffer default (i.e. the document font).

(defvar my/latex-code-font-family "Droid Sans Mono"
  "Monospace family used for LaTeX syntactic markup in `LaTeX-mode' buffers.
Any TTF present under $HOME/fonts/ works; \"Droid Sans Mono\" ships with
Android and is always available.")

(defconst my/latex-code-font-faces
  '(font-latex-sedate-face             ; { } [ ]
    font-latex-warning-face            ; \begin, \end, keyword commands
    font-latex-math-face               ; math source highlighting
    font-latex-string-face             ; env names inside \begin{...}
    font-latex-script-char-face        ; ^ and _
    font-latex-doctex-preprocessor-face
    font-latex-doctex-documentation-face
    font-lock-keyword-face             ; \command names
    font-lock-comment-face             ; % comments
    font-lock-comment-delimiter-face
    font-lock-function-name-face       ; \label{}, \ref{}, \newcommand{}
    font-lock-variable-name-face
    font-lock-constant-face
    font-lock-builtin-face
    font-lock-preprocessor-face)
  "Faces remapped to `my/latex-code-font-family' in LaTeX buffers.
Deliberately excludes content-styling faces (bold, italic, underline,
sectioning-*, sub/superscript, verbatim, type) so styled content follows
the document font selected by `latex-font-sync-mode'.")

(defvar-local my/latex-code-font-cookies nil
  "Face-remap cookies installed by `my/latex-code-font-apply'.")

(defun my/latex-code-font-apply ()
  "Remap LaTeX syntactic-markup faces to a monospace family, buffer-locally."
  (when (and (derived-mode-p 'LaTeX-mode)
             (display-graphic-p))
    (mapc #'face-remap-remove-relative my/latex-code-font-cookies)
    (setq my/latex-code-font-cookies
          (mapcar (lambda (face)
                    (face-remap-add-relative
                     face :family my/latex-code-font-family))
                  my/latex-code-font-faces))))

(add-hook 'LaTeX-mode-hook #'my/latex-code-font-apply)


;;; --- Fold macros to WYSIWYG-ish, auto-reveal on point entry ---------------
;;
;; `TeX-fold-mode' hides macro syntax behind an overlay: `\textbf{F}' shows
;; as bold "F", `\emph{x}' as italic "x", `\section{Foo}' as "Foo".  Combined
;; with `reveal-mode', the overlay auto-expands when point enters it, so you
;; edit the raw source, then it re-folds on point exit.  This gives an
;; approximation of the rendered document appearance for text markup, while
;; math still uses `C-c p p' (preview-latex) for real rasterised previews.

(add-hook 'LaTeX-mode-hook #'TeX-fold-mode)
;; NOTE: `reveal-mode' does NOT auto-reveal TeX-fold overlays — the
;; overlays hide their contents through the `display' property, but
;; `reveal-mode' only watches the `invisible' property.  Auto-reveal on
;; point entry is TeX-fold's own machinery (`TeX-fold-auto-reveal',
;; default = reveal on char/left/right motion into the fold).  This hook
;; is kept for the small win it gives around org-mode links and
;; outline-minor-mode headings that a user might also enable in a LaTeX
;; buffer; it is unrelated to fold reveal.
(add-hook 'LaTeX-mode-hook #'reveal-mode)

(with-eval-after-load 'tex-fold
  ;; Fold macros inserted via `TeX-insert-macro' (C-c C-m and cdlatex's
  ;; electric insertion) automatically, so freshly-typed macros collapse
  ;; without a manual `C-c C-o C-b'.  This does NOT fold as-you-type text;
  ;; it only fires on the macro-insertion command.
  (setq TeX-fold-auto t
        ;; env + macro only, NOT `math'.  `math' folds `\pi'/`\int'/etc. to
        ;; Unicode glyphs (π, ∫), but the text fonts font-sync selects
        ;; (Latin Modern Roman, TeX Gyre Pagella, …) don't contain those
        ;; glyphs, so Android's font backend renders tofu / random fallback.
        ;; Math stays as source; preview it inline with `C-c p p'.
        TeX-fold-type-list '(env macro))

  ;; How fold specs work here: an integer N means "show arg N as the
  ;; placeholder"; the manual promises the arg text is copied with its
  ;; font-latex face, so `\textbf{X}' folds to `X' in bold, `\emph{X}'
  ;; in italic, etc. — the default `TeX-fold-macro-spec-list' already
  ;; covers textbf/textit/emph/texttt/textsf.  A function spec is called
  ;; via `(apply SPEC ARGS)' with the collected `{...}' args as
  ;; positional params, point at ov-start.  `(SPEC . (opt . mand))'
  ;; extends the fold region to that many args.  See the AUCTeX manual
  ;; node "Folding" and tex-fold.el:1217-1230.

  ;; \href{url}{text} → show arg 2 (the visible text), fold both args.
  ;; NOTE: the `(SPEC . SIG)' form requires AUCTeX >= 14.1.1.
  (push '((2 . (0 . 2)) ("href")) TeX-fold-macro-spec-list)

  ;; \enquote{x} → “x” (curly quotes).  A fold function that returns nil
  ;; makes tex-fold render the literal string "[Error: No content or
  ;; function found]"; returning the symbol `abort' is the sanctioned way
  ;; to skip folding this occurrence.
  (defun my/tex-fold-quoted (&rest a)
    (or (when-let* ((s (car a))) (format "\u201C%s\u201D" s)) 'abort))
  (push '(my/tex-fold-quoted ("enquote")) TeX-fold-macro-spec-list)

  ;; Missing from defaults; use integer 1 so buffer face is preserved.
  (push '(1 ("underline" "sout" "st" "url" "path" "text"))
        TeX-fold-macro-spec-list)

  ;; \verb / \verb* are folded natively by AUCTeX via `TeX-fold-verbs'
  ;; (part of the default `TeX-fold-region-functions').  Adding a second
  ;; overlay through `TeX-fold-macro-spec-list' collides with that one
  ;; and leaves an overlay that doesn't span the `|…|' body.  For
  ;; `\lstinline', extend AUCTeX's own verb-macro list so it handles the
  ;; same way.
  (when (boundp 'TeX-fold-verb-macros)
    (add-to-list 'TeX-fold-verb-macros "lstinline")))

;; Fold the buffer once on open so existing content isn't a wall of
;; backslashes.  Deferred a hair so font-lock and AUCTeX styles finish first.
(add-hook 'LaTeX-mode-hook
          (lambda ()
            (run-with-idle-timer 0.1 nil
                                 (lambda (buf)
                                   (when (buffer-live-p buf)
                                     (with-current-buffer buf
                                       (TeX-fold-buffer))))
                                 (current-buffer)))
          'append)


;;; --- CDLaTeX --------------------------------------------------------------

(use-package cdlatex
  :hook ((LaTeX-mode . turn-on-cdlatex)
         (org-mode   . turn-on-org-cdlatex))
  :bind (:map cdlatex-mode-map
              ("<tab>" . cdlatex-tab)))

;;; --- YaSnippet + Karthik's auto-expand hook -------------------------------

(use-package yasnippet
  :hook ((LaTeX-mode        . yas-minor-mode)
         (org-mode          . yas-minor-mode)
         (post-self-insert  . my/yas-try-expanding-auto-snippets))
  :config
  (with-eval-after-load 'warnings
    (cl-pushnew '(yasnippet backquote-change)
                warning-suppress-types :test #'equal))
  (setq yas-triggers-in-field t
        yas-snippet-dirs (list (expand-file-name "snippets" user-emacs-directory)))
  (yas-reload-all)

  (defun my/yas-try-expanding-auto-snippets ()
    (when (and (boundp 'yas-minor-mode) yas-minor-mode)
      (let ((yas-buffer-local-condition ''(require-snippet-condition . auto)))
        (yas-expand)))))

;; CDLatex <TAB> that co-operates with YaSnippet fields (Karthik).
(with-eval-after-load 'cdlatex
  (with-eval-after-load 'yasnippet
    (add-hook 'cdlatex-tab-hook #'yas-expand)
    (add-hook 'cdlatex-tab-hook #'cdlatex-in-yas-field)
    (define-key yas-keymap (kbd "<tab>") #'yas-next-field-or-cdlatex)
    (define-key yas-keymap (kbd "TAB")  #'yas-next-field-or-cdlatex)

    (defun cdlatex-in-yas-field ()
      (when-let* ((_ (overlayp yas--active-field-overlay))
                  (end (overlay-end yas--active-field-overlay)))
        (if (>= (point) end)
            (let ((s (thing-at-point 'sexp)))
              (unless (and s (assoc (substring-no-properties s)
                                    cdlatex-command-alist-comb))
                (yas-next-field-or-maybe-expand) t))
          (let (cdlatex-tab-hook minp)
            (setq minp
                  (min (save-excursion (cdlatex-tab) (point))
                       (overlay-end yas--active-field-overlay)))
            (goto-char minp) t))))

    (defun yas-next-field-or-cdlatex ()
      "Jump to the next Yas field correctly with cdlatex active."
      (interactive)
      (if (or (bound-and-true-p cdlatex-mode)
              (bound-and-true-p org-cdlatex-mode))
          (cdlatex-tab)
        (yas-next-field-or-maybe-expand)))))

;;; --- Karthik's lazytab (matrix / table entry with cdlatex + org-table) ----

(with-eval-after-load 'cdlatex
  (with-eval-after-load 'org-table
    (define-key orgtbl-mode-map (kbd "<tab>") #'lazytab-org-table-next-field-maybe)
    (define-key orgtbl-mode-map (kbd "TAB")  #'lazytab-org-table-next-field-maybe)
    (add-hook 'cdlatex-tab-hook #'lazytab-cdlatex-or-orgtbl-next-field 90)
    (add-to-list 'cdlatex-command-alist
                 '("smat" "Insert smallmatrix env"
                   "\\left( \\begin{smallmatrix} ? \\end{smallmatrix} \\right)"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("bmat" "Insert bmatrix env"
                   "\\begin{bmatrix} ? \\end{bmatrix}"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("pmat" "Insert pmatrix env"
                   "\\begin{pmatrix} ? \\end{pmatrix}"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("tbl" "Insert table"
                   "\\begin{table}\n\\centering ? \\caption{}\n\\end{table}\n"
                   lazytab-position-cursor-and-edit nil t nil))

    (defun lazytab-position-cursor-and-edit ()
      (cdlatex-position-cursor)
      (lazytab-orgtbl-edit))

    (defun lazytab-orgtbl-edit ()
      (advice-add 'orgtbl-ctrl-c-ctrl-c :after #'lazytab-orgtbl-replace)
      (orgtbl-mode 1)
      (open-line 1)
      (insert "\n|"))

    (defun lazytab-orgtbl-replace (_)
      (interactive "P")
      (unless (org-at-table-p) (user-error "Not at a table"))
      (let* ((table (org-table-to-lisp))
             params
             (replacement-table
              (if (texmathp)
                  (lazytab-orgtbl-to-amsmath table params)
                (orgtbl-to-latex table params))))
        (kill-region (org-table-begin) (org-table-end))
        (open-line 1)
        (push-mark)
        (insert replacement-table)
        (align-regexp (region-beginning) (region-end) "\\([[:space:]]*\\)& ")
        (orgtbl-mode -1)
        (advice-remove 'orgtbl-ctrl-c-ctrl-c #'lazytab-orgtbl-replace)))

    (defun lazytab-orgtbl-to-amsmath (table params)
      (orgtbl-to-generic
       table
       (org-combine-plists
        '(:splice t :lstart "" :lend " \\\\" :sep " & " :hline nil :llend "")
        params)))

    (defun lazytab-cdlatex-or-orgtbl-next-field ()
      (when (and (bound-and-true-p orgtbl-mode)
                 (org-table-p)
                 (looking-at "[[:space:]]*\\(?:|\\|$\\)")
                 (let ((s (thing-at-point 'sexp)))
                   (not (and s (assoc s cdlatex-command-alist-comb)))))
        (call-interactively #'org-table-next-field)
        t))

    (defun lazytab-org-table-next-field-maybe ()
      (interactive)
      (if (bound-and-true-p cdlatex-mode)
          (cdlatex-tab)
        (org-table-next-field)))))

;;; --- org-mode inline previews (bonus) -------------------------------------
;;
;; In .org buffers, C-c C-x C-l previews LaTeX fragments inline as PNG,
;; through the same pdflatex+gs pair as the C-c p p flow.

(with-eval-after-load 'org
  (setq org-preview-latex-image-directory
        (expand-file-name "ltximg/" (getenv "HOME")))

  ;; Render org previews with the same binaries as the C-c p p flow
  ;; (pdflatex → ghostscript → PNG).  Two deliberate differences from
  ;; org's stock process entries:
  ;;  - :latex-header builds the snippet on the `standalone' class (the
  ;;    same border+varwidth wrapper the Termux <f5> flow uses), because
  ;;    org's default header is a full `article' page and cropping is
  ;;    normally the converter's job (dvipng -T tight / convert -trim);
  ;;    gs has no crop switch, so the page itself must be tight.  This
  ;;    header REPLACES org's default header AND its package injection,
  ;;    hence the explicit package list.
  ;;  - PNG instead of SVG: the SVG pt→px mapping at display time is
  ;;    unmeasurable (that is why dvisvgm carries a hand-tuned 1.7
  ;;    adjust); PNG at an exact gs -r resolution has no unknown, and
  ;;    matches the .tex flow by construction.  (House rule: PNG.)
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

  ;; Truly transparent fragments: org emits \pagecolor unless the
  ;; :background option is the STRING "Transparent" (the default,
  ;; `default', resolves to the face background and paints the page).
  ;; With pngalpha this makes fragments sit on the page like the
  ;; C-c p p overlays do.  :background is inside the cache key, so the
  ;; change regenerates images by itself.
  (plist-put org-format-latex-options :background "Transparent")

  ;; Fully automatic sizing, no knobs: recompute :scale from the
  ;; CURRENT default-face height and C-x C-+ zoom right before every
  ;; render.  gs then runs at
  ;;   -r%D = :scale × org--get-display-dpi
  ;; which equals preview-latex's (face-pt/10) × char-metric-DPI — the
  ;; sizing equation the .tex flow already uses on this device.
  ;; `face-attribute' returns the BASE height (text-scale works via
  ;; face remapping), so the zoom factor below is not double-counted.
  ;; :scale is part of org's preview cache key, so a changed font size
  ;; or zoom regenerates images automatically; each rendered size stays
  ;; cached and is reused free when you switch back.
  (defun my/org-latex-auto-scale (&rest _)
    "Set org preview :scale from current font height and text-scale zoom."
    (plist-put org-format-latex-options :scale
               (* (/ (face-attribute 'default :height) 100.0)
                  (if (bound-and-true-p text-scale-mode)
                      (expt text-scale-mode-step text-scale-mode-amount)
                    1.0))))
  (advice-add 'org-latex-preview :before #'my/org-latex-auto-scale)

  ;; Same Android bug as AUCTeX's `preview-get-dpi' (see the preview
  ;; section above), fixed separately for org: the frame reports a bogus
  ;; physical size (~3 m wide), so org's pixels/mm computation in
  ;; `org--get-display-dpi' returns ~9 DPI.  Derive DPI from character
  ;; metrics instead (same approach as `preview-get-dpi', but org wants
  ;; a plain NUMBER, not a cons — do not merge the two functions).
  ;; NOTE: org's preview cache key does NOT include the DPI, so after
  ;; any change to THIS function, stale images must be deleted by hand:
  ;;   rm -rf /data/data/org.gnu.emacs/files/ltximg
  ;; (:scale changes need no such step — they re-key the cache.)
  (defun org--get-display-dpi ()
    "Android reports bogus monitor mm-size; derive DPI from char metrics."
    (round (/ (* (frame-char-height) 72.0)
              (/ (face-attribute 'default :height) 10.0)))))

(provide 'init)
;;; init.el ends here

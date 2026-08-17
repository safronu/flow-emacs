;;; eink-faces.el --- Monochrome typographic face signatures for e-ink -*- lexical-binding: t; -*-
;;
;; Layered ON TOP of modus-operandi (loaded in init.el before this file):
;; re-encodes the meaning a color theme carries in hue into channels the
;; 16-gray Carta panel renders perfectly -- weight, slant, underline,
;; boxes, inverse video, strike-through -- plus a short ladder of grays
;; quantized to the panel's 16 native levels (every channel byte is a
;; multiple of #x11, so nothing dithers):
;;   #000000 ink | #444444 soft | #777777 mid | #aaaaaa pale | #dddddd wash
;;
;; Implementation note: `custom-set-faces' stores these in the `user'
;; theme, which outranks any enabled custom theme (modus-operandi), and
;; also applies to faces that are only DEFINED later (diff-mode, org,
;; dired...) -- no with-eval-after-load needed.
;;
;; This file deliberately does NOT touch:
;;   - the `default' face (the profile owns family and :height; preview
;;     DPI and latex-font-sync both key off it),
;;   - any font-latex-* face GLOBALLY (init.el manages those; the
;;     TeX-specific tweaks at the end of this file are buffer-local
;;     remaps layered on top),
;;   - any minor mode or scroll/refresh setting (init.el owns them).
;;
;; No `display-graphic-p' guard on purpose: `custom-set-faces' is
;; harmless on a tty (unsupported attributes are ignored) and the
;; C-c e keybindings should exist regardless of display type.
;;
;; To remove the whole experiment: delete the load line in init.el.

;;; Code:

(custom-set-faces
 ;; --- Syntax: typographic signatures instead of hues ---------------
 ;; In LaTeX buffers these also get their :family remapped to the code
 ;; font by `my/latex-code-font-apply' -- family and weight/slant are
 ;; independent channels, so both apply.
 '(font-lock-keyword-face       ((t (:foreground "#000000" :weight bold))))
 '(font-lock-type-face          ((t (:foreground "#000000" :weight bold :slant italic))))
 '(font-lock-function-name-face ((t (:foreground "#000000" :weight ultra-bold))))
 '(font-lock-function-call-face ((t (:foreground "#000000" :weight semi-bold))))
 '(font-lock-variable-name-face ((t (:foreground "#000000" :weight medium))))
 '(font-lock-builtin-face       ((t (:foreground "#000000" :weight semi-bold))))
 '(font-lock-constant-face      ((t (:foreground "#000000" :underline t))))
 '(font-lock-string-face        ((t (:foreground "#444444" :slant italic))))
 '(font-lock-doc-face           ((t (:foreground "#777777" :slant italic))))
 '(font-lock-comment-face       ((t (:foreground "#777777" :slant italic))))
 '(font-lock-comment-delimiter-face ((t (:foreground "#aaaaaa" :slant italic))))
 '(font-lock-warning-face       ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(font-lock-preprocessor-face  ((t (:foreground "#000000" :weight semi-bold :underline t))))
 '(font-lock-negation-char-face ((t (:foreground "#000000" :weight bold))))

 ;; --- Search & matching: inverse = "here", box = "also here" -------
 '(isearch        ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(isearch-fail   ((t (:foreground "#000000" :background "#dddddd" :strike-through t))))
 '(lazy-highlight ((t (:foreground "#000000" :background "#ffffff"
                       :box (:line-width (1 . -1) :color "#444444")))))
 '(match          ((t (:foreground "#000000" :background "#dddddd" :weight bold))))
 '(show-paren-match ((t (:foreground "#000000" :background "#dddddd" :weight ultra-bold))))
 '(show-paren-mismatch ((t (:foreground "#ffffff" :background "#000000" :weight bold :strike-through t))))
 '(minibuffer-prompt ((t (:foreground "#000000" :weight bold))))

 ;; --- Mode line: solid black anchor bar ----------------------------
 '(mode-line          ((t (:foreground "#ffffff" :background "#000000" :weight medium
                           :box (:line-width (1 . 4) :color "#000000")))))
 '(mode-line-inactive ((t (:foreground "#777777" :background "#dddddd"
                           :box (:line-width (1 . 4) :color "#dddddd")))))
 '(mode-line-buffer-id ((t (:weight ultra-bold))))
 ;; ace-window's per-window letter (`ace-window-display-mode', flow-core),
 ;; leftmost in every mode line.  The default inherits mode-line-buffer-id,
 ;; which on an INACTIVE bar renders #777777-on-#dddddd -- and the inactive
 ;; windows are precisely the ones M-o jumps to.  A WHITE chip with a big
 ;; black letter, not inverse video: a black chip at the bar's left edge
 ;; sits flush against the neighboring window's solid-black active bar and
 ;; the two fuse into one smear (tried 2026-08-17), while white touches
 ;; nothing else on any bar -- it pops against the active bar's black and
 ;; still reads against the inactive #dddddd because the letter itself is
 ;; full ink.  :height 1.4 because a mode-line-sized glyph is spotting-
 ;; distance illegible on the 13" panel; the bar grows to fit once,
 ;; uniformly (every window carries a letter).  The white box is pure
 ;; padding: +3px per side horizontally, vertical 1 so it adds nothing
 ;; the enlarged glyph doesn't already claim.
 '(aw-mode-line-face  ((t (:foreground "#000000" :background "#ffffff"
                           :weight ultra-bold :height 1.4
                           :box (:line-width (3 . 1) :color "#ffffff")))))
 '(header-line        ((t (:foreground "#000000" :background "#dddddd" :weight medium))))

 ;; --- Diagnostics: severity as loudness, never as hue --------------
 '(error   ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(warning ((t (:foreground "#000000" :weight bold :box (:line-width (1 . -1) :color "#000000")))))
 '(success ((t (:foreground "#000000" :weight bold :underline t))))
 '(compilation-error   ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(compilation-warning ((t (:foreground "#000000" :weight bold :box (:line-width (1 . -1) :color "#000000")))))
 '(compilation-info    ((t (:foreground "#000000" :weight semi-bold :underline t))))
 '(flymake-error   ((t (:underline (:style wave :color "#000000")))))
 '(flymake-warning ((t (:underline (:style wave :color "#444444")))))
 '(flymake-note    ((t (:underline (:style wave :color "#aaaaaa")))))
 '(flyspell-incorrect ((t (:underline (:style wave :color "#000000")))))
 '(flyspell-duplicate ((t (:underline (:style wave :color "#777777")))))

 ;; --- Diffs: + underline / - strike-through ------------------------
 '(diff-added             ((t (:foreground "#000000" :underline t :weight bold))))
 '(diff-removed           ((t (:foreground "#444444" :strike-through t))))
 '(diff-changed           ((t (:foreground "#000000" :slant italic :weight medium))))
 '(diff-refine-added      ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(diff-refine-removed    ((t (:foreground "#ffffff" :background "#444444" :strike-through t))))
 '(diff-header            ((t (:foreground "#000000" :background "#dddddd" :weight bold))))
 '(diff-file-header       ((t (:foreground "#000000" :background "#dddddd" :weight ultra-bold))))
 '(diff-hunk-header       ((t (:foreground "#444444" :background "#dddddd" :slant italic))))
 '(diff-context           ((t (:foreground "#444444"))))
 '(smerge-upper   ((t (:background "#dddddd" :strike-through t :extend t))))
 '(smerge-lower   ((t (:background "#dddddd" :underline t :extend t))))
 '(smerge-base    ((t (:background "#dddddd" :slant italic :extend t))))
 '(smerge-markers ((t (:foreground "#ffffff" :background "#444444" :weight bold :extend t))))
 '(smerge-refined-added   ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(smerge-refined-removed ((t (:foreground "#ffffff" :background "#444444" :strike-through t))))

 ;; --- Org: structure as size + weight; state as typography ---------
 '(org-level-1 ((t (:foreground "#000000" :weight ultra-bold :height 1.25 :overline t))))
 '(org-level-2 ((t (:foreground "#000000" :weight bold :height 1.15))))
 '(org-level-3 ((t (:foreground "#000000" :weight semi-bold :height 1.05))))
 '(org-todo    ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(org-done    ((t (:foreground "#777777" :strike-through t :weight regular))))
 '(org-headline-done ((t (:foreground "#777777"))))
 '(org-priority ((t (:foreground "#000000" :weight bold :box (:line-width (1 . -1) :color "#444444")))))
 '(org-tag     ((t (:foreground "#444444" :slant italic :height 0.9))))
 '(org-date    ((t (:foreground "#444444" :underline t))))

 ;; --- Dired / completions ------------------------------------------
 '(dired-directory ((t (:foreground "#000000" :weight bold))))
 '(dired-symlink   ((t (:foreground "#000000" :slant italic :underline t))))
 '(dired-marked    ((t (:foreground "#ffffff" :background "#000000" :weight bold))))
 '(dired-flagged   ((t (:foreground "#000000" :strike-through t :weight bold))))
 '(dired-header    ((t (:foreground "#000000" :weight ultra-bold :underline t))))
 '(completions-common-part      ((t (:foreground "#000000" :weight bold))))
 ;; No :underline here — the "first difference" is often a SPACE (e.g.
 ;; completing "Latin Modern Roman" against "Latin Modern Roman Ink" /
 ;; "... Demi", where the diverging char is the space before the grade
 ;; token), and an underlined space is visually indistinguishable from
 ;; an underscore on the panel.  Users then type what they "see", get
 ;; face-remap :family "Latin Modern Roman_Ink" (a family no font has),
 ;; cascade through the fallback chain to AndroidClock, and every
 ;; character renders as a glyphless-char box.  Ultra-bold alone is
 ;; enough of a signal on 16-gray e-ink.
 '(completions-first-difference ((t (:foreground "#000000" :weight ultra-bold))))

 ;; --- AUCTeX chrome not covered by modus (upstream defaults dither) --
 ;; Folded macro content is real content: full ink, not SlateBlue.
 '(TeX-fold-folded-face   ((t (:foreground "#000000"))))
 ;; Revealed-for-editing regions: panel-native wash instead of the
 ;; upstream lavender (#f2f0fd) / beige backgrounds.
 '(TeX-fold-unfolded-face ((t (:background "#dddddd"))))
 '(preview-face           ((t (:background "#dddddd")))))

;;; --- Display helpers on the C-c e prefix ----------------------------
;; NOT on F5/F6/F7 -- those are the Termux-side preview keys.

(defvar my/eink-font-heights '(170 185 200 220)
  "Cycle of default-face heights (1/10 pt) for `my/eink-cycle-font-height'.
170 is the profile baseline (`flow-font-height'); the cycle always
returns to it.")

(defun my/eink-cycle-font-height ()
  "Cycle the default face height through `my/eink-font-heights'.
Starts from the CURRENT height, so the profile baseline (170) is the
normal entry point.  Touches :height only, never :family -- preview
DPI and latex-font-sync both derive from the default face and follow
automatically.  Already-rendered preview overlays keep their old pixel
size; press `C-c p c' then re-preview to regenerate at the new size."
  (interactive)
  (let* ((cur  (face-attribute 'default :height))
         (rest (member cur my/eink-font-heights))
         (next (if (and rest (cdr rest))
                   (cadr rest)
                 (car my/eink-font-heights))))
    (set-face-attribute 'default nil :height next)
    (message "Font height: %d (%.0f pt).  Stale previews: C-c p c, then re-preview."
             next (/ next 10.0))))

(global-set-key (kbd "C-c e f") #'my/eink-cycle-font-height)
;; Full-frame redraw: clears e-ink ghosting from Emacs's side.  Pair
;; with the Boox full-refresh gesture for panel-level ghosts.
(global-set-key (kbd "C-c e g") #'redraw-display)

;;; --- TeX-mode-specific signatures (buffer-local) ----------------------
;;
;; Three fixes for LaTeX buffers, all using only IMAGE-SAFE channels
;; (foreground/weight/slant style glyphs and add nothing outside a
;; preview image; underline/box/background are drawn on the glyph cell
;; and leak under/behind rendered previews -- per the Elisp manual, a
;; display property leaves undefined attributes to the UNDERLYING
;; text's face).
;;
;; 1. References (\label, \ref, \eqref, \cite -- font-latex's
;;    "reference" class on `font-lock-constant-face') drop the module's
;;    global underline signature, which drew a stray line through
;;    rendered formulas, and become semi-bold instead.
;;    `face-remap-set-base' REPLACES the face's global spec in this
;;    buffer -- deterministic, no attribute-merge subtleties -- and
;;    init.el's :family remap (my/latex-code-font-apply) layers on top.
;;    `font-lock-preprocessor-face' is the only other globally
;;    underlined syntax face: same leak class, same fix.
;; 2. Sectioning: modus dims section titles to its fg-alt gray; remap
;;    to full ink, with a weight ladder (\part/\chapter/\section
;;    ultra-bold; deeper levels bold).  NOTE: the bundled document
;;    TTFs ship a single bold weight, so the whole ladder usually
;;    renders as plain bold -- the real win is full ink instead of
;;    dim gray, and the ladder engages for free if a multi-weight
;;    family is ever installed.  Relative remaps only -- the heights
;;    that `font-latex-fontify-sectioning' manages are not touched.
;;    This also makes TeX-folded section titles read as real headings.
;; 3. Script chars (^ and _) get full ink + bold so super/subscript
;;    structure is spottable in unrendered math source.
;;
;; The defvar-local guard is belt-and-braces idempotence for a
;; repeated hook invocation in a live buffer.  (A full mode re-init
;; kills local variables -- flag AND remaps together -- so re-init is
;; naturally clean either way.)

(defvar-local my/eink-latex-faces--done nil
  "Non-nil once `my/eink-latex-faces' has run in this buffer.")

(defun my/eink-latex-faces ()
  "TeX-specific e-ink face signatures, buffer-local and image-safe."
  (when (and (derived-mode-p 'LaTeX-mode)
             (display-graphic-p)
             (not my/eink-latex-faces--done))
    (setq my/eink-latex-faces--done t)
    (face-remap-set-base 'font-lock-constant-face
                         '(:foreground "#000000" :weight semi-bold))
    (face-remap-set-base 'font-lock-preprocessor-face
                         '(:foreground "#000000" :weight semi-bold))
    (dolist (f '(font-latex-sectioning-0-face
                 font-latex-sectioning-1-face
                 font-latex-sectioning-2-face))
      (face-remap-add-relative f :foreground "#000000" :weight 'ultra-bold))
    (dolist (f '(font-latex-sectioning-3-face
                 font-latex-sectioning-4-face
                 font-latex-sectioning-5-face))
      (face-remap-add-relative f :foreground "#000000" :weight 'bold))
    (face-remap-add-relative 'font-latex-script-char-face
                             :foreground "#000000" :weight 'bold)))

(add-hook 'LaTeX-mode-hook #'my/eink-latex-faces)

(provide 'eink-faces)
;;; eink-faces.el ends here

;;; flow-core.el --- package system, editing defaults, window management -*- lexical-binding: t; -*-
;;
;; Device-independent.  Everything here behaves the same on the Boox
;; tablet (native Android Emacs and Termux Emacs) and on the laptop; what
;; differs is expressed through the knobs declared in `flow-boot.el'.
;;
;; Load this FIRST from a profile: it bootstraps `use-package', which
;; every other module assumes is available.

;;; Code:

;; A stale .elc must never shadow a newer .el.  `load' tries the .elc
;; FIRST and, with this nil, uses it even when the source is newer —
;; which is how a byte-compiled init once froze a device's config
;; against every subsequent `git pull' (see CLAUDE.md, "Things not to
;; do").  Setting it here cannot protect early-init/init themselves
;; (they load before this line runs); install.sh prunes those .elc
;; files instead.  This covers everything loaded afterwards.
(setq load-prefer-newer t)

(require 'package)

;;; --- Package system -------------------------------------------------------

(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

;; Emacs 30's `package--quickstart-maybe-refresh' (invoked at the end of
;; every `package-install') calls `package-quickstart-refresh', which in
;; turn calls `(package-initialize 'no-activate)'.  With
;; `package-quickstart' t AND a package being installed during init (a
;; `use-package :ensure' block hitting a freshly-added package for the
;; first time), that second `package-initialize' fires while
;; `after-init-time' is still nil and `package--initialized' is already
;; t — which is the "Unnecessary call to `package-initialize' in init
;; file" warning.  We never call `package-initialize' ourselves; the
;; warning is package.el complaining about its own second call.
;; Deferring the refresh to `after-init-hook' both silences the check
;; (`after-init-time' is set by then) and coalesces multiple installs in
;; one init into a single refresh — exactly what package.el's own FIXME
;; asks for.
(defun flow-package-quickstart-maybe-refresh-deferred ()
  "Defer `package-quickstart-refresh' to `after-init-hook'."
  (if package-quickstart
      (add-hook 'after-init-hook #'package-quickstart-refresh)
    (ignore-errors (delete-file (concat package-quickstart-file "c")))
    (ignore-errors (delete-file package-quickstart-file))))
(advice-add 'package--quickstart-maybe-refresh :override
            #'flow-package-quickstart-maybe-refresh-deferred)

;; Divert Customize output to its own file so `custom-set-variables' /
;; `custom-set-faces' blocks never accumulate at the tail of a config
;; file that lives in git.  (An inline block once silently rewrote
;; `package-selected-packages' to nil on every startup, which broke
;; `package-autoremove'.)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror 'nomessage)

;; NEVER refresh archives at startup.  On a mobile connection that blocks
;; the UI for a long time, or forever if the network is asleep.
;; Bootstrap only: if `use-package' isn't there yet, refresh once and
;; install it.  After that, updates are a deliberate
;; `M-x package-refresh-contents'.  Emacs >= 27 has already run
;; `package-initialize' by the time init.el is read.
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t
      ;; A use-package block for a not-yet-installed package should fail
      ;; loudly rather than silently deferring the work to first use.
      use-package-always-defer nil)

;; GNU ELPA rotates its signing key and a given Emacs often ships an
;; older one.  early-init sets `package-check-signature' to nil so this
;; first install can happen at all; once the current key is in place,
;; verification goes back on for everything installed afterwards.
(unless (package-installed-p 'gnu-elpa-keyring-update)
  (ignore-errors (package-install 'gnu-elpa-keyring-update)))
(when (package-installed-p 'gnu-elpa-keyring-update)
  (setq package-check-signature 'allow-unsigned))

;; Async native compilation runs in the background over freshly
;; installed packages and surfaces every byte-compile-grade warning in
;; a popped-up *Warnings* buffer — e.g. pdf-tools' pdf-annot.el warning
;; about functions that actually live in pdf-links.el and exist fine at
;; runtime.  `silent' keeps the full record in *Async-native-compile-log*
;; without interrupting anything.  Harmless no-op on builds without
;; native compilation (the variable just sits unused).
(setq native-comp-async-report-warnings-errors 'silent)

;;; --- Editing defaults -----------------------------------------------------

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

;; Scrolling that never recenters: a recenter repaints the whole frame,
;; which on e-ink is a visible flash, and on any display loses your place.
(setq scroll-conservatively 100
      scroll-margin 2
      scroll-preserve-screen-position t)

(when flow-eink-p
  (blink-cursor-mode -1))

;;; --- Theme and fonts ------------------------------------------------------

(when (and flow-theme (display-graphic-p))
  (load-theme flow-theme t))

(when (display-graphic-p)
  ;; :height and :family are applied INDEPENDENTLY, on purpose.  An
  ;; earlier version guarded both behind one `find-font' check on the
  ;; family — but if that lookup fails at init time (conceivable on the
  ;; sfnt-android backend), the size silently stays at the build's
  ;; default too, and a profile's `flow-font-height' bump does nothing.
  ;; The height must never depend on the family resolving.  A family
  ;; that doesn't resolve is itself harmless — Emacs falls back — and
  ;; the pre-split configs applied it unconditionally for months; the
  ;; crash risk on Android is malformed TTF *files* (all bundled ones
  ;; are validated in-frame), not unknown family names.
  (when flow-font-height
    (set-face-attribute 'default nil :height flow-font-height))
  (when flow-font-family
    (set-face-attribute 'default nil :family flow-font-family)))

;;; --- ace-window: manage ALL windows with M-o ------------------------------
;;
;; `aw-dispatch-always' makes M-o enter selection mode even with one or
;; two windows, so window management needs no C-x 2/3/0/1 at all: press a
;; window letter to jump, or an action key first — b = split
;; side-by-side, v = split top/bottom, x = close, o = keep only one,
;; m = swap, ? = help, C-g = cancel.  `?j' is out of `aw-keys' because
;; `j' is itself a dispatch action (select buffer); the two sets must not
;; overlap.
;;
;; `ace-window-display-mode' keeps each window's selection letter in its
;; mode line at all times, so the target letter is known BEFORE M-o —
;; on e-ink that also means the big overlay letters (a repaint) can be
;; skipped entirely: M-o, letter, done.  The mode must be on from
;; startup, hence `:demand' — with only `:bind' the package (and the
;; mode-line letters) wouldn't exist until the first M-o.

;; The mode-line letters (below) are always visible, so the big
;; in-window overlay letters during M-o are redundant — and on e-ink
;; each overlay is another repaint + ghost.  But `aw-display-mode-overlay'
;; nil is all-or-nothing: it no-ops the overlay fn for EVERY window,
;; leaving any window with no mode line (the active minibuffer, a
;; buffer-local `mode-line-format' nil) letter-less and unswitchable
;; by sight.  So the knob stays t and the per-window decision moves
;; into `aw--lead-overlay-fn' (internal ace-window API; re-verify on
;; upgrade): overlay only where no bar renders.
;; `window-mode-line-height' is 0 exactly for those windows, whatever
;; the cause — it measures the rendered bar, not the variable.
;;
;; The minibuffer gets its own shape: `aw--lead-overlay' puts the
;; letter ON the first character (a `display' overlay that pads to
;; preserve alignment), which in the minibuffer swallows the first
;; char of the prompt ("Find file:" → "sind file:").  There we
;; PREPEND instead — a zero-cover `before-string' overlay at
;; `point-min', letter + space before an intact prompt — pushed to
;; `avy--overlays-lead' so avy's normal cleanup removes it.

(defun flow-aw--chip-string (letter)
  "LETTER fenced by unfaced spaces, styled as the minibuffer chip.
The spaces keep the chip off the frame edge and the prompt, same
language as the mode-line letters' fences."
  (concat " "
          (propertize letter 'face 'aw-minibuffer-leading-char-face)
          " "))

(defvar-local flow-aw--minibuffer-chip nil
  "Overlay showing this minibuffer's M-o letter before the prompt.")

(defun flow-aw--minibuffer-chip-refresh (&rest _)
  "Sync the active minibuffer's letter chip with its `ace-window-path'.
Runs after `aw-update' (and from `minibuffer-setup-hook'), so the chip
tracks letter reassignments while the minibuffer stays open."
  (let ((win (active-minibuffer-window)))
    (when win
      (with-current-buffer (window-buffer win)
        (let ((path (window-parameter win 'ace-window-path)))
          (unless (overlayp flow-aw--minibuffer-chip)
            (setq flow-aw--minibuffer-chip
                  (make-overlay (point-min) (point-min) (current-buffer))))
          (overlay-put flow-aw--minibuffer-chip 'window win)
          (overlay-put flow-aw--minibuffer-chip 'before-string
                       (and path
                            (flow-aw--chip-string
                             (substring-no-properties path)))))))))

(defun flow-aw--minibuffer-setup ()
  "Assign the fresh minibuffer its letter and show the chip at once.
On `minibuffer-setup-hook' — activation is not a window-configuration
change, so `aw-update' would not run on its own until one happens."
  (when ace-window-display-mode
    (aw-update)
    (flow-aw--minibuffer-chip-refresh)))

(defun flow-aw--minibuffer-last (windows)
  "Move minibuffer windows to the end of WINDOWS.
`:filter-return' advice on `aw-window-list'.  Mid-list, an activating
minibuffer would shift the letters of every window sorted after it
while their mode lines keep showing the old ones (`aw-update' does not
run on minibuffer activation) — M-o would then obey letters nobody can
see.  Last, it simply takes the next free letter and every other
window's letter stays put."
  (nconc (cl-remove-if #'window-minibuffer-p windows)
         (cl-remove-if-not #'window-minibuffer-p windows)))

(defun flow-aw--lead-overlay (path leaf)
  "Show M-o's overlay letter only where no mode line renders.
LEAF is (PT . WND).  In the minibuffer the persistent chip from
`flow-aw--minibuffer-setup' already shows the letter; only if it is
somehow absent, prepend a temporary one (never cover the prompt)."
  (let ((wnd (cdr leaf)))
    (cond
     ((window-minibuffer-p wnd)
      (let ((chip (buffer-local-value 'flow-aw--minibuffer-chip
                                      (window-buffer wnd))))
        (unless (and (overlayp chip) (overlay-get chip 'before-string))
          (let ((ol (make-overlay (point-min) (point-min)
                                  (window-buffer wnd))))
            (overlay-put ol 'window wnd)
            (overlay-put ol 'before-string
                         (flow-aw--chip-string
                          (mapconcat (lambda (c) (string (avy--key-to-char c)))
                                     (reverse path) "")))
            (push ol avy--overlays-lead)))))
     ((zerop (window-mode-line-height wnd))
      (aw--lead-overlay path leaf)))))

(use-package ace-window
  :demand t
  :bind ("M-o" . ace-window)
  :config
  (setq aw-keys '(?a ?s ?d ?f ?g ?h ?k ?l)  ; home row, minus dispatch char j
        aw-dispatch-always t
        ;; The default dims the whole frame during selection, i.e. repaints
        ;; every pixel.  Fine on an LCD, a flash and lingering ghosts on e-ink.
        aw-background (not flow-eink-p)
        aw-scope 'frame)
  (setq aw--lead-overlay-fn #'flow-aw--lead-overlay)
  (advice-add 'aw-window-list :filter-return #'flow-aw--minibuffer-last)
  (advice-add 'aw-update :after #'flow-aw--minibuffer-chip-refresh)
  (add-hook 'minibuffer-setup-hook #'flow-aw--minibuffer-setup)
  (set-face-attribute 'aw-leading-char-face nil
                      :height flow-aw-leading-char-height :weight 'bold)
  (ace-window-display-mode 1)
  ;; Re-wrap the entry the mode just installed at the head of
  ;; `mode-line-format': a plain space fences the letter off the window
  ;; edge, and " │ " fences it from the rest of the mode line.  The
  ;; fences deliberately carry NO face, so they render in the bar's own
  ;; mode-line/-inactive colors, not the letter chip's.  Keyed on the
  ;; same `ace-window-display-mode' guard symbol, so toggling the mode
  ;; off removes our entry exactly as it would its own (and a re-enable
  ;; would re-install the package's bare letter — re-run this setq-
  ;; default after it if that ever becomes a live path).
  (setq-default mode-line-format
                (cons '(ace-window-display-mode
                        (:eval (let ((path (window-parameter (selected-window)
                                                             'ace-window-path)))
                                 (and path (list " " path " │ ")))))
                      (assq-delete-all 'ace-window-display-mode
                                       (default-value 'mode-line-format)))))

(provide 'flow-core)
;;; flow-core.el ends here

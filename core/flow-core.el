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

(use-package ace-window
  :bind ("M-o" . ace-window)
  :config
  (setq aw-keys '(?a ?s ?d ?f ?g ?h ?k ?l)  ; home row, minus dispatch char j
        aw-dispatch-always t
        ;; The default dims the whole frame during selection, i.e. repaints
        ;; every pixel.  Fine on an LCD, a flash and lingering ghosts on e-ink.
        aw-background (not flow-eink-p)
        aw-scope 'frame)
  (set-face-attribute 'aw-leading-char-face nil
                      :height flow-aw-leading-char-height :weight 'bold))

(provide 'flow-core)
;;; flow-core.el ends here

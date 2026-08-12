;;; init.el --- laptop profile: Xiaomi 15.6" (Ubuntu, snap Emacs 30) -*- lexical-binding: t; -*-
;;
;; The colour-LCD adaptation of the Boox setup.  This file holds ONLY
;; what is true of this machine; everything portable lives in ../core/
;; and is shared with the two tablet profiles.
;;
;; The panel is 3200x2000 at ~239 physical DPI, but the X/XWayland
;; session reports a screen size back-derived from 96 DPI — the same
;; class of lie the Android port tells, just a different multiple.  The
;; char-metric DPI overrides in flow-preview handle it identically, so
;; previews here need no laptop-specific code at all.
;;
;; Keys on top of the shared ones:
;;   C-c p p / b / c   preview at point / whole buffer / clear (flow-preview)
;;   C-c d …           deadlines, when ~/flow/deadlines is cloned

;;; Code:

;; Find the repo through this file's symlink and declare the knobs.
(load (expand-file-name "../core/flow-boot"
                        (file-name-directory (file-truename load-file-name)))
      nil 'nomessage)

;;; --- What this machine is --------------------------------------------------

(setq flow-profile 'laptop
      flow-eink-p nil
      ;; Same family as the tablet, so the two devices read identically.
      ;; install-laptop.sh apt-installs fonts-jetbrains-mono; flow-core
      ;; skips the family if it is missing rather than falling back to
      ;; something arbitrary.
      flow-font-family "JetBrains Mono"
      flow-font-height 130
      flow-code-font-family "JetBrains Mono"
      ;; Colour stays: this is an LCD, so modus-operandi keeps its normal
      ;; syntax colours and eink-faces.el is deliberately not loaded.
      flow-theme 'modus-operandi
      flow-monochrome-latex-faces nil
      flow-latex-fold t
      flow-aw-leading-char-height 2.0
      ;; Deadlines checkout lives next to this repo in the flow folder.
      flow-deadlines-repo
      (let ((d (expand-file-name "~/flow/deadlines")))
        (and (file-directory-p d) d)))

;; Snap/GUI-launched Emacs inherits a bare PATH; make sure user-local
;; tools (tinymist, claude, …) resolve.  TeX Live from apt is in /usr/bin
;; and needs nothing.
(dolist (dir (list (expand-file-name "~/.local/bin")))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (or (getenv "PATH") "")))))

;;; --- Shared modules ---------------------------------------------------------

(flow-load "flow-core")       ; packages, defaults, M-o window management
(flow-load "flow-latex")      ; AUCTeX, cdlatex, snippets, folding
(flow-load "flow-preview")    ; inline previews in .tex and .org

;; Buffer font follows the document's font package.  The TeX Gyre and
;; Latin Modern families are installed system-wide by TeX Live on this
;; machine (fontconfig finds their OTFs — no bundled TTFs needed, that
;; dance is Android-only).
(flow-load "latex-font-sync")
(latex-font-sync-mode 1)

;;; --- Deadlines (private repo, loaded only if cloned) ------------------------

(flow-load "flow-deadlines")

(provide 'init)
;;; init.el ends here

;;; init.el --- Boox profile: native Android Emacs (org.gnu.emacs) -*- lexical-binding: t; -*-
;;
;; The e-ink tablet's graphical profile.  This file holds ONLY what is
;; true of this device; everything portable lives in ../core/ and is
;; shared with the Termux and laptop profiles.
;;
;; Runs under the native Android Emacs port, which ships librsvg /
;; libjpeg / libtiff / cairo — so inline `preview-latex' overlays work
;; here.  The heavy lifting (pdflatex, ghostscript) is done by the TeX
;; Live installed under Termux at /data/data/com.termux/files/usr, whose
;; binaries are self-contained enough to run from this app's process
;; because both apps share an Android UID.
;;
;; Keys added on top of the shared ones:
;;   C-c p p / b / c   preview at point / buffer / clear   (flow-preview)
;;   C-c e f           cycle the default font height       (eink-faces)
;;   C-c e g           full redraw, clears e-ink ghosting  (eink-faces)

;;; Code:

;; Find the repo through this file's symlink and declare the knobs.
(load (expand-file-name "../core/flow-boot"
                        (file-name-directory (file-truename load-file-name)))
      nil 'nomessage)

;;; --- What this device is --------------------------------------------------

(setq flow-profile 'android
      flow-eink-p t
      ;; JetBrains Mono is bundled as a TTF under android-emacs/fonts/ and
      ;; symlinked into $HOME/fonts by install.sh; Android Emacs enumerates
      ;; that directory at launch (.ttf/.ttc only — no OTF, no fontconfig).
      flow-font-family "JetBrains Mono"
      flow-font-height 150            ; readable on a 13" e-ink panel
      flow-code-font-family "JetBrains Mono"
      flow-theme 'modus-operandi      ; pure white background
      flow-monochrome-latex-faces t   ; hue carries nothing on 16 grays
      flow-latex-fold t
      flow-aw-leading-char-height 2.5 ; spottable on a 13" panel
      flow-org-preview-image-directory (expand-file-name "ltximg/" (getenv "HOME"))
      ;; The deadlines checkout lives in the Termux home (same UID, so it
      ;; is readable from here).  nil when it isn't cloned — the loader
      ;; then does nothing at all.
      flow-deadlines-repo
      (seq-find #'file-directory-p
                '("/data/data/com.termux/files/home/deadlines"
                  "/data/data/org.gnu.emacs/files/deadlines"))
      ;; git run from this app would look for ~/.gitconfig and ~/.ssh in
      ;; the Emacs app's private dir, where there are none; the keys are
      ;; in the Termux home.
      flow-deadlines-git-home "/data/data/com.termux/files/home")

;;; --- Termux binaries on PATH ---------------------------------------------
;;
;; So pdflatex / dvisvgm / gs / tlmgr resolve when Emacs calls them via
;; `call-process' / `start-process'.  early-init.el already did the first
;; two directories (AUCTeX resolves some programs at load time); the
;; TeX Live bin dir is added here because it only exists after install.
;; TEXMFROOT is exported in early-init.el; TEXMFDIST / TEXMFVAR /
;; TEXMFSYSVAR are derived from it by kpathsea via texmf.cnf.

(dolist (dir '("/data/data/com.termux/files/usr/bin"
               "/data/data/com.termux/files/usr/bin/texlive"
               "/data/data/com.termux/files/usr/share/texlive/2026/bin/aarch64-linux"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (or (getenv "PATH") "")))))

;;; --- Shared modules -------------------------------------------------------

(flow-load "flow-core")       ; packages, defaults, M-o window management
(flow-load "flow-latex")      ; AUCTeX, cdlatex, snippets, folding
(flow-load "flow-preview")    ; inline previews in .tex and .org

;;; --- Buffer font follows the document font --------------------------------
;;
;; Remaps a LaTeX buffer's default :family to a TTF matching the
;; document's declared font package (mathpazo → TeX Gyre Pagella, times →
;; TeX Gyre Termes, …).  Only :family is remapped; :height stays global,
;; so previews keep scaling with the default face.
;;
;; Enabled by default here for a second, non-obvious reason: without a
;; buffer-local family remap in place, Android's sfnt-android font
;; backend won't pick a bold variant for TeX-fold's overlay display
;; strings, so `\textbf{X}' folds render regular-weight even though the
;; fold text property says `:weight bold'.  Don't disable it lightly.
;; All bundled TTFs have been validated in-frame — a malformed TTF can
;; hard-crash the app's font backend on face-remap.

(flow-load "latex-font-sync")
(latex-font-sync-mode 1)

;;; --- Deadlines (private repo, loaded only if cloned) ----------------------

(flow-load "flow-deadlines")

;;; --- E-ink monochrome face signatures -------------------------------------
;;
;; Typographic re-encoding of syntax/diff/org meaning for the 16-gray
;; panel, layered over modus-operandi via the `user' theme.  Loaded LAST
;; so nothing can override its faces.  Device-specific by nature — the
;; laptop profile deliberately keeps colour.

(load (expand-file-name "eink-faces"
                        (file-name-directory (file-truename load-file-name)))
      nil 'nomessage)

(provide 'init)
;;; init.el ends here

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
;;   C-c p p / b / c   in .md: live preview / browser / close (flow-markdown)
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
      flow-font-height 170            ; 17pt — easy on the eyes on 13" e-ink
      flow-code-font-family "JetBrains Mono"
      flow-theme 'modus-operandi      ; pure white background
      flow-monochrome-latex-faces t   ; hue carries nothing on 16 grays
      flow-latex-fold t
      flow-page t
      ;; E-ink hairline strategy: a LARGER regular cut, not bold.  Bold
      ;; was tried and looked squat next to the compiled PDF (wider
      ;; glyphs, closed counters).  Extra size keeps the document's
      ;; exact proportions while making the hairlines more pixels wide;
      ;; \textbf folds stand out again.  Tune to taste — previews
      ;; follow automatically.
      flow-font-sync-extra-scale 1.15
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
(flow-load "flow-live-pdf")   ; C-c p l: compiled PDF in a chosen window
;; Guarded: the load line was committed ahead of core/flow-markdown.el
;; itself (in-progress in another session).  The guard keeps a pull
;; from aborting init on a module missing from the tree; drop it once
;; flow-markdown.el is committed.
(when (file-exists-p (flow-core-file "flow-markdown.el"))
  (flow-load "flow-markdown")) ; markdown-mode + C-c p p live HTML preview

;;; --- Buffer font follows the document font --------------------------------
;;
;; Remaps a LaTeX buffer's default :family to a TTF matching the
;; document's declared font package (mathpazo → TeX Gyre Pagella, times →
;; TeX Gyre Termes, …), plus a relative :height factor compensating the
;; serif font's smaller x-height; the global default face is untouched
;; and previews keep scaling with the effective buffer font.
;;
;; Enabled by default here for a second, non-obvious reason: without a
;; buffer-local family remap in place, Android's sfnt-android font
;; backend won't pick a bold variant for TeX-fold's overlay display
;; strings, so `\textbf{X}' folds render regular-weight even though the
;; fold text property says `:weight bold'.  Don't disable it lightly.
;; All bundled TTFs have been validated in-frame — a malformed TTF can
;; hard-crash the app's font backend on face-remap.

(flow-load "latex-font-sync")

;; Weight ladder for e-ink: regular LM/TeX Gyre hairlines wash out on
;; the 16-gray panel, bold is squat.  Two intermediate grades are
;; bundled — "Ink" (subtle: tools/embolden.py, +12 units LM / +10
;; TeX Gyre) and "Demi" (dark: LM's OFFICIAL demi converted via
;; tools/otf2ttf.py; TeX Gyre synthesized at +20).  Ink is preferred
;; after Demi read as too dark in daily use; all grades stay installed,
;; so comparing is just `M-x my/latex-font-try-family' — no restart.
;; ("Ink" was "Book" until 2026-08-13.  Renamed as defensive hygiene:
;; the face :family path used here loads either name fine (verified),
;; but "book" is a weight token in name-string parsers — font.c
;; font_parse_fcname, fontconfig style constants, sfntfont.c's token
;; list — so a style word inside a FAMILY name misparses under
;; set-frame-font/fc-match and muddies debugging.  Grade suffixes
;; should never be style vocabulary; see CLAUDE.md.)
(setq my/latex-font-user-candidates
      '((:family/lm-roman . ("Latin Modern Roman Ink" "Latin Modern Roman Demi"
                             "Latin Modern Roman" "Noto Serif" "serif"))
        (:family/palatino . ("TeX Gyre Pagella Ink" "TeX Gyre Pagella Demi"
                             "TeX Gyre Pagella" "Noto Serif" "serif"))
        (:family/times    . ("TeX Gyre Termes Ink" "TeX Gyre Termes Demi"
                             "TeX Gyre Termes" "Noto Serif" "serif"))
        (:family/bookman  . ("TeX Gyre Bonum Ink" "TeX Gyre Bonum Demi"
                             "TeX Gyre Bonum" "Noto Serif" "serif"))
        (:family/newcent  . ("TeX Gyre Schola Ink" "TeX Gyre Schola Demi"
                             "TeX Gyre Schola" "Noto Serif" "serif"))))

(latex-font-sync-mode 1)

;; Display-math air on top of the synced font: full-line formulas get
;; \abovedisplayskip-sized separation, like the compiled page.  Em
;; pixels are measured from the effective buffer font, so
;; `flow-font-sync-extra-scale' above flows through automatically.
(flow-load "flow-page")

;;; --- Deadlines (private repo, loaded only if cloned) ----------------------

(flow-load "flow-deadlines")

;;; --- Telega: Telegram client (native Android Emacs only) ------------------
;;
;; Telega talks to Telegram via `telega-server', a small C shim that
;; dynamically loads TDLib (`libtdjson.so').
;;
;; TDLib source: `install.sh' builds TDLib from github.com/tdlib/td and
;; installs it under `$HOME/.local/tdlib' (headers + libs).  We do NOT
;; use Termux's `libtd' package — it's frozen at 1.8.50 and telega
;; ≥ 2026-01 requires ≥ 1.8.56 (current master wants ≥ 1.8.66).  The
;; `telega-server-libs-prefix' setting below hands that prefix to the
;; server's Makefile (`-I$prefix/include', `-L$prefix/lib', rpath), so
;; `M-x telega-server-build' links against the right libtdjson without
;; touching pkg-config or system paths.
;;
;; Deferred via `:commands' so a normal LaTeX-focused startup never
;; loads telega: no TDLib mmap, no auth check, no image/network I/O
;; until the first `M-x telega'.  `use-package-always-ensure' picks the
;; package up on a fresh device.
;;
;; The Termux Emacs build has no image support (avatars/photos/stickers
;; would all fail to render), so this is deliberately NOT mirrored in
;; `termux-emacs/init.el'.

(use-package telega
  :commands (telega)
  :custom
  (telega-server-libs-prefix (expand-file-name "~/.local/tdlib")))

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

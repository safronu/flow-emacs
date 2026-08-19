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
;;   C-c p p / b / c   in .md: live preview / browser / close (flow-markdown)
;;   C-c d …           deadlines, when ~/flow/deadlines is cloned
;;   C-c g …           LLM chat via the Claude Code CLI (flow-gptel)
;;   C-c a …, M-n      agentic coding: agent-shell + Claude Code (flow-agent-shell)

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
      flow-font-height 150            ; 15pt — comfortable on the 3200x2000 panel
      flow-code-font-family "JetBrains Mono"
      ;; Colour stays: this is an LCD, so modus-operandi keeps its normal
      ;; syntax colours and eink-faces.el is deliberately not loaded.
      flow-theme 'modus-operandi
      flow-monochrome-latex-faces nil
      flow-latex-fold t
      flow-page t
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
(flow-load "flow-live-pdf")   ; C-c p l: compiled PDF in a chosen window
(flow-load "flow-markdown")   ; markdown-mode + C-c p p live HTML preview
(flow-load "flow-gptel")      ; C-c g …: LLM chat via the Claude Code CLI
(flow-load "flow-agent-shell"); C-c a …: agentic coding, Claude Code over ACP

;; Buffer font follows the document's font package — on demand: buffers
;; open in the code font, C-c p b applies the document font, C-c p c
;; reverts (same contract as folds/previews).  The TeX Gyre and
;; Latin Modern families are installed system-wide by TeX Live on this
;; machine (fontconfig finds their OTFs — no bundled TTFs needed, that
;; dance is Android-only).
(flow-load "latex-font-sync/latex-font-sync")
(latex-font-sync-mode 1)

;; Display-math air on top of the synced font: full-line formulas get
;; \abovedisplayskip-sized separation, like the compiled page.
(flow-load "flow-page")

;;; --- pdf-tools: proper PDF rendering (laptop only) --------------------------
;;
;; Vector-sharp at any zoom, fast, SyncTeX-capable — what the C-c p l
;; live-PDF window uses instead of doc-view once installed.  Needs the
;; native `epdfinfo' helper, built once against system poppler-glib
;; (build deps came via apt; the binary lives in the elpa package dir
;; and survives until a pdf-tools version bump, which will prompt to
;; rebuild).  `pdf-loader-install' only registers autoloads — nothing
;; loads until a PDF is actually opened.  Laptop-only: on the tablet
;; epdfinfo would have to be cross-built under Termux; doc-view (tuned
;; in flow-live-pdf.el) does that job there.

(use-package pdf-tools
  :config
  (pdf-loader-install))

;;; --- Deadlines (private repo, loaded only if cloned) ------------------------

(flow-load "flow-deadlines")

(provide 'init)
;;; init.el ends here

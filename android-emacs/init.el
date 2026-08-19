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
;;   C-c g …           LLM chat via the Claude Code CLI    (flow-gptel)
;;   C-c a …, M-n      agentic coding: agent-shell + Claude Code (flow-agent-shell)
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
                '("/data/data/com.termux/files/home/flow/deadlines"
                  "/data/data/org.gnu.emacs/files/deadlines"))
      ;; git run from this app would look for ~/.gitconfig and ~/.ssh in
      ;; the Emacs app's private dir, where there are none; the keys are
      ;; in the Termux home.
      flow-deadlines-git-home "/data/data/com.termux/files/home"
      ;; Same story for the `claude' CLI: the binary is reachable through
      ;; the Termux PATH added below, but its login lives in Termux's
      ;; ~/.claude, not in this app's HOME.  See `flow-gptel'.
      flow-claude-config-dir "/data/data/com.termux/files/home/.claude"
      ;; The ACP adapter must go through the repo's Termux-side wrapper:
      ;; npm's own bin shim has an `env node' shebang that only works
      ;; under termux-exec (which this app lacks), and the wrapper also
      ;; exports CLAUDE_CODE_EXECUTABLE — mandatory here, because Termux
      ;; node reports platform "android" so the SDK's own CLI resolution
      ;; always fails.  See bin/claude-agent-acp.
      flow-claude-acp-command
      (list (expand-file-name "bin/claude-agent-acp" flow-root)))

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
(flow-load "flow-markdown")   ; markdown-mode + C-c p p live HTML preview
;; LLM chat via the Termux `claude' CLI.  Possible here only since the
;; 2026-08-14 migration put a working CLI on the tablet; the `exec-path'
;; block above finds it, `flow-claude-config-dir' supplies the login.
(flow-load "flow-gptel")      ; C-c g …: LLM chat via the Claude Code CLI
;; Agentic coding over ACP, wired here 2026-08-18: the adapter runs on
;; Termux's bionic node (plain JS — only the CLI binary needed patching)
;; and drives the patched glibc `claude' via CLAUDE_CODE_EXECUTABLE,
;; verified end-to-end on-device.  Same subscription login as gptel,
;; supplied by `flow-claude-config-dir' above.
(flow-load "flow-agent-shell"); C-c a …: agentic coding, Claude Code over ACP

;; agent-shell display fixes for this device (2026-08-19), both header-
;; line artifacts diagnosed from the installed package sources:
;;
;; 1. Tofu separators.  agent-shell's text header and mode line join
;;    their segments with a hardcoded ➤ (U+27A4).  The ONLY font on the
;;    whole device containing that char is Boox's subsetted
;;    NotoSansSymbols (verified over every ~/fonts + /system/fonts cmap),
;;    and the sfnt-android backend doesn't use it — so each separator
;;    rendered as a glyphless box.  Display-table remap to ▸ (U+25B8,
;;    present in JetBrains Mono): display tables apply to header and
;;    mode lines too, and a plain-char entry keeps the underlying face.
;;    Global (standard-display-table) on purpose — U+27A4 is tofu in ANY
;;    buffer on this device, agent output included.
;;
;; 2. Black bar.  While the agent works, the header's busy indicator
;;    animates 4-cell ░-block frames on a heartbeat tick.  On the
;;    16-gray panel the ░░░░ strip reads as a solid dark bar, and every
;;    tick partially refreshes the header line, which smears/ghosts it.
;;    Off entirely: an animation has no place on e-ink, and busy state
;;    is visible in the transcript itself.  (Laptop keeps both defaults
;;    — this block is profile-side for that reason.)
(unless standard-display-table
  (setq standard-display-table (make-display-table)))
(aset standard-display-table #x27A4 (vector ?▸))
(with-eval-after-load 'agent-shell
  (setq agent-shell-show-busy-indicator nil))

;;; --- Emacs server, reachable from Termux ----------------------------------
;;
;; The socket deliberately lives in TERMUX's home, not this app's: the
;; two apps share a UID (see CLAUDE.md), so a Claude Code session (or
;; any Termux shell) can eval in the running native Emacs with
;;
;;   emacsclient -s /data/data/com.termux/files/home/.emacs-server-native/server -e '<form>'
;;
;; This is primarily a diagnostic channel — it's what made the
;; 2026-08-19 black-bar hunt convergent: dumping the live
;; header-line-format and realized face attributes beat theorizing over
;; specs (custom-set-faces merges per ATTRIBUTE with an enabled theme,
;; so the rendered face is not readable off any one spec).  Same-UID
;; sockets only; nothing is exposed beyond the two apps.  The guard
;; keeps a second `load' of init (or a stale socket left by a killed
;; process, which `server-running-p' reports dead) from erroring.

(require 'server)
(setq server-socket-dir "/data/data/com.termux/files/home/.emacs-server-native")
(unless (server-running-p)
  (server-start))

;;; --- Buffer font follows the document font --------------------------------
;;
;; Remaps a LaTeX buffer's default :family to a TTF matching the
;; document's declared font package (mathpazo → TeX Gyre Pagella, times →
;; TeX Gyre Termes, …), plus a relative :height factor compensating the
;; serif font's smaller x-height; the global default face is untouched
;; and previews keep scaling with the effective buffer font.
;;
;; On-demand, same contract as folds/previews: buffers open in the code
;; font, C-c p b applies the document font, C-c p c reverts it.  The
;; mode stays enabled here — it provides the machinery (style/save
;; hooks that re-detect the family for opted-in buffers).
;;
;; A non-obvious dependency while in document mode: without a
;; buffer-local family remap in place, Android's sfnt-android font
;; backend won't pick a bold variant for TeX-fold's overlay display
;; strings, so `\textbf{X}' folds render regular-weight even though the
;; fold text property says `:weight bold'.  (Consequence: a fold created
;; per-item in RAW mode shows that regular-weight rendering until
;; C-c p b applies the remap.)  All bundled TTFs have been validated
;; in-frame — a malformed TTF can hard-crash the app's font backend on
;; face-remap.

(flow-load "latex-font-sync/latex-font-sync")

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

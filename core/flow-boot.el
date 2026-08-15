;;; flow-boot.el --- locate the repo, declare the device knobs -*- lexical-binding: t; -*-
;;
;; Every profile (android-emacs/, termux-emacs/, laptop-emacs/) starts by
;; loading THIS file, and nothing else needs to know where the repo is:
;;
;;   (load (expand-file-name
;;          "../core/flow-boot"
;;          (file-name-directory (file-truename load-file-name))) nil 'nomessage)
;;
;; Why `file-truename': the live init path is a SYMLINK into this repo
;; (~/.emacs.d/init.el on the laptop, .emacs.d/init.el inside the Emacs
;; app's private dir on Android).  Resolving the symlink gives the file's
;; real location in the repo, so `flow-root' is the repo root and the
;; shared modules load straight out of the working tree.  Consequence
;; worth knowing: a `git pull' is enough to update a device — no new
;; symlinks are needed when a core module is added, and re-running
;; install.sh is only ever about the live *entry points*.
;;
;; A profile then sets the knobs it cares about and pulls in modules:
;;
;;   (setq flow-profile 'laptop
;;         flow-font-family "JetBrains Mono")
;;   (flow-load "flow-core")
;;   (flow-load "flow-latex")
;;
;; Load order is the profile's business.  `flow-core' must come first: it
;; bootstraps `use-package', which every other module assumes.

;;; Code:

(defconst flow-root
  (file-name-as-directory
   (expand-file-name
    ".." (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
  "Absolute path of the flow-emacs repository working tree.
Derived from this file's own resolved location, so it is correct no
matter which symlink the profile was reached through.")

(defun flow-load (module)
  "Load MODULE (a basename, no extension) from the repo's `core/' directory."
  (load (expand-file-name (concat "core/" module) flow-root) nil 'nomessage))

(defun flow-core-file (relative)
  "Absolute path of RELATIVE inside the repo's `core/' directory."
  (expand-file-name (concat "core/" relative) flow-root))


;;; --- Device knobs ---------------------------------------------------------
;;
;; Defaults here describe a plain graphical Emacs on a normal computer.
;; Each profile overrides what differs about its device.  Anything a
;; module needs to branch on lives in this list — modules never sniff the
;; machine themselves, so behaviour is always readable from the profile.

(defvar flow-profile 'unknown
  "Which profile is running: `android', `termux', `laptop', or `unknown'.")

(defvar flow-eink-p nil
  "Non-nil on an e-ink panel.
Turns off cursor blink and anything that repaints the whole frame
(ace-window's background dimming), because a full repaint on e-ink is a
visible flash and leaves ghosting.")

(defvar flow-font-family nil
  "Default-face family to set at startup, or nil to leave Emacs's choice.")

(defvar flow-font-height nil
  "Default-face height in 1/10 pt, or nil to leave Emacs's choice.
Preview sizing and `latex-font-sync' both derive from this face, so
changing it rescales rendered math along with the text.")

(defvar flow-code-font-family "monospace"
  "Monospace family for LaTeX syntactic markup (macro names, braces, comments).
Keeps code legible after `latex-font-sync-mode' remaps the buffer default
to the document's serif font.")

(defvar flow-theme nil
  "Theme symbol to load at startup, or nil for none.")

(defvar flow-monochrome-latex-faces nil
  "Non-nil to strip colour from font-latex faces, leaving weight/slant only.
The point on a 16-gray panel: hue carries no information there, so bold
and italic must carry it instead.")

(defvar flow-latex-prettify-symbols nil
  "Non-nil to turn on `prettify-symbols-mode' in LaTeX buffers.
Worth it only where real previews are impossible (terminal Emacs): the
substituted glyphs make sub/superscripts jump off the baseline and are
awkward to point at.")

(defvar flow-latex-fold t
  "Non-nil to enable `TeX-fold-mode' in LaTeX buffers.
Folding is on-demand (C-c p keys); nothing folds automatically.")

(defvar flow-page t
  "Non-nil to enable `flow-page-mode' in LaTeX buffers.
Adds \\abovedisplayskip-sized air around display math, like the
compiled page.  Needs a graphical frame and the `flow-page' module —
the Termux profile sets this nil and never loads it.")

(defvar flow-font-sync-weight nil
  "Weight for the font-sync buffer remap, or nil to keep the regular cut.
Tried as `bold' on e-ink against the hairline problem and rejected:
bold LM/TeX Gyre glyphs are wider and squatter than the regular cut,
so the buffer stopped looking like the compiled document.  The e-ink
answer is `flow-font-sync-extra-scale' instead — a larger REGULAR cut
has proportionally identical glyphs whose hairlines are simply more
pixels wide.  Knob kept for experiments.")

(defvar flow-font-sync-extra-scale 1.0
  "Device multiplier on top of the per-family optical scale.
The e-ink profile raises it: at print sizes, LM/TeX Gyre hairlines are
too few pixels wide for a 16-gray panel, and since these families ship
no medium weight, the sturdiness has to come from SIZE — a bigger
regular cut keeps the compiled document's exact proportions while its
strokes cross the legibility threshold.  Previews track automatically
through the effective-font DPI.")

(defvar flow-preview-scale 1.25
  "Extra scale on math previews WHEN the buffer shows the code font.
Em-for-em, Computer Modern math looks SMALLER than monospace text: its
x-height is ~0.43 em against JetBrains Mono's ~0.53 em.  1.25 is the
ratio of those x-heights.  It applies only where that mismatch exists:
org buffers (always mono) and .tex buffers where `latex-font-sync' has
NOT remapped the buffer to the document font.  In font-synced buffers
the preview and the buffer share a family, so equal ems are already
equal optical size and no factor is applied — see
`flow-preview--optical-factor' in flow-preview.el.")

(defvar flow-aw-leading-char-height 2.0
  "Scale of ace-window's selection letters, relative to the default face.")

(defvar flow-deadlines-repo nil
  "Path to a checkout of the private `deadlines' repo, or nil to skip it.
The repo itself is never vendored here — it holds customer data.  See
`flow-deadlines'.")

(defvar flow-deadlines-git-home nil
  "HOME to hand git subprocesses run by deadlines.el, or nil to inherit.
Needed only on Android, where Emacs's HOME is the app's private dir and
the ssh keys live in Termux's home.")

(defvar flow-claude-config-dir nil
  "CLAUDE_CONFIG_DIR for `claude' subprocesses, or nil to inherit.
Same shape of problem as `flow-deadlines-git-home': on Android, Emacs's
HOME is the app's private dir, but the CLI's login lives in Termux's
`~/.claude'.  Without this the CLI starts fine and every request fails
with \"Not logged in - Please run /login\".  See `flow-gptel'.")

(defvar flow-claude-acp-command nil
  "Argv list for the Claude Code ACP adapter, or nil for agent-shell's default.
The default — (\"claude-agent-acp\") — resolves through `exec-path'.
Set it in a profile only when the adapter needs an explicit path or
wrapper, e.g. an Android profile pointing at a Termux-side Node
script.  See `flow-agent-shell'.")

(defvar flow-org-preview-image-directory nil
  "Directory for org's cached LaTeX-fragment images, or nil for org's default.")

(defvar flow-markdown-command nil
  "Argv list for the Markdown-to-HTML converter, or nil to auto-detect.
Nil means `flow-markdown' picks the first installed program from
`flow-markdown-command-candidates' (pandoc first).  Set it in a profile
only to override that choice — e.g. \\='(\"pandoc\" \"--from=markdown\").
The program must read Markdown on stdin and write an HTML fragment, not
a standalone document; see `flow-markdown.el'.")

;;; --- Diagnostics ------------------------------------------------------------

(defun flow-font-report ()
  "Report everything relevant to why the fonts look the way they do.
First line to check: `user-init-file'.  If it ends in `.elc', Emacs is
running a stale byte-compiled init and IGNORING init.el — no knob
change can take effect until the .elc is deleted (re-run install.sh)
and the app is fully restarted."
  (interactive)
  (let* ((family flow-font-family)
         (found  (and family (find-font (font-spec :family family))))
         (fi     (and (display-graphic-p)
                      (ignore-errors (font-info (face-font 'default)))))
         ;; Must be computed HERE, in the buffer being diagnosed —
         ;; everything it reads is buffer-local or mode-dependent.
         (chain  (flow-font-report--preview-chain))
         (line-px (frame-char-height)))
    (with-current-buffer (get-buffer-create "*flow font report*")
      (erase-buffer)
      (insert
       (format "user-init-file:  %s%s\n" user-init-file
               (if (and (stringp user-init-file)
                        (string-suffix-p ".elc" user-init-file))
                   "   <-- STALE BYTE-COMPILED INIT: init.el is being IGNORED"
                 ""))
       (format "profile:         %s\n" flow-profile)
       (format "knob family:     %s\n" family)
       (format "knob height:     %s\n" flow-font-height)
       (format "find-font:       %s\n" (or found "NOT FOUND (family would fall back)"))
       (format "face height now: %s\n" (face-attribute 'default :height))
       (format "actual font:     %s\n" (if fi (aref fi 1) "n/a (no graphic display)"))
       (format "em px / line px: %s / %s\n"
               (if fi (aref fi 2) "n/a") line-px)
       chain)
      (display-buffer (current-buffer)))))

(defun flow-font-report--preview-chain ()
  "Report every number the preview/text size sync depends on.
Empty string outside LaTeX buffers.  The key line is `ratio': the
preview em divided by the text em — 1.00 means rendered math and
buffer text are the same size by construction; anything else names
the broken link (dpi not seeing the remap, scale double-counting,
text-scale interference, ...)."
  (if (not (derived-mode-p 'LaTeX-mode))
      ""
    (let* ((synced   (bound-and-true-p my/latex-current-family))
           (factor   (and (fboundp 'flow-preview--optical-factor)
                          (flow-preview--optical-factor)))
           (dpi      (and (fboundp 'flow-preview--base-dpi)
                          (flow-preview--base-dpi)))
           (scale    (and (boundp 'preview-scale-function)
                          (functionp preview-scale-function)
                          (ignore-errors (funcall preview-scale-function))))
           ;; The font actually drawing buffer text at point.
           (fat      (and (display-graphic-p)
                          (ignore-errors (query-font (font-at (point))))))
           (text-em  (and fat (aref fat 2)))
           ;; What a 10pt glyph in a rendered preview comes out as.
           (prev-em  (and dpi scale (/ (* scale dpi 10.0) 72)))
           ;; An actually-rendered overlay near point, if one exists.
           (ov-px    (let (found)
                       (dolist (ov (overlays-in (point-min) (point-max)))
                         (when-let* ((img (and (not found)
                                               (overlay-get ov 'preview-image))))
                           (ignore-errors
                             (setq found (cdr (image-size (cdr img) t))))))
                       found)))
      (concat
       (format "--- preview sizing chain (this buffer) ---\n")
       (format "font at point:   %s px=%s\n"
               (if fat (aref fat 0) "n/a") (or text-em "n/a"))
       (format "synced family:   %s\n" (or synced "nil (code font, factor applies)"))
       (format "optical factor:  %s\n" (or factor "n/a"))
       (format "text-scale amt:  %s\n" (if (bound-and-true-p text-scale-mode)
                                           text-scale-mode-amount 0))
       (format "base-dpi:        %s\n" (if dpi (format "%.1f" dpi) "n/a"))
       (format "preview scale:   %s\n" (if scale (format "%.3f" scale) "n/a"))
       (format "preview em px:   %s (computed: scale x dpi / 72 x 10pt)\n"
               (if prev-em (format "%.1f" prev-em) "n/a"))
       (format "ratio prev/text: %s   <-- 1.00 = in sync\n"
               (if (and prev-em text-em) (format "%.3f" (/ prev-em text-em)) "n/a"))
       (format "overlay px h:    %s (an actual rendered image, if any)\n"
               (or ov-px "none rendered"))))))

(provide 'flow-boot)
;;; flow-boot.el ends here

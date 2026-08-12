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
  "Non-nil to enable `TeX-fold-mode' in LaTeX buffers and fold on open.")

(defvar flow-latex-sectioning-scale 1.0
  "Height multiplier for folded sectioning commands, compounded per level.
1.0 = all headings at body size (the e-ink choice: scaled faces repaint
badly there).  ~1.2 gives a PDF-like type scale on an LCD.  This is
AUCTeX's `font-latex-fontify-sectioning'; its script-raising stays off
regardless.")

(defvar flow-page-view nil
  "Non-nil to turn on `flow-page-view-mode' in every LaTeX buffer.
Page view = wide margins around a fixed text column (olivetti) plus
automatic math previews as formulas scroll into view (preview-auto),
approximating the compiled page while staying editable source.  Needs a
graphical frame; pointless on a tty.")

(defvar flow-page-view-width 90
  "Text-column width, in columns, for `flow-page-view-mode'.")

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

(defvar flow-org-preview-image-directory nil
  "Directory for org's cached LaTeX-fragment images, or nil for org's default.")

(provide 'flow-boot)
;;; flow-boot.el ends here

;;; flow-markdown.el --- editing and previewing Markdown -*- lexical-binding: t; -*-
;;
;; Device-independent, like every module here; what differs between
;; devices is the converter that happens to be installed, and that is
;; found at load time (or pinned per profile through the
;; `flow-markdown-command' knob in flow-boot.el).
;;
;; Keys in markdown buffers — the same `C-c p' prefix the .tex and .org
;; previews use, so "preview this" is one gesture across every kind of
;; document in this setup:
;;
;;   C-c p p   toggle the live preview beside the buffer (re-renders on save)
;;   C-c p b   render once and hand the HTML to the system browser
;;   C-c p c   close the live preview
;;   C-c p i   toggle inline images
;;
;; markdown-mode's own keys are untouched: `C-c C-c l' (live preview),
;; `C-c C-c p' (browser), `C-c C-x C-i' (images) still work, and so does
;; the whole `C-c C-s' insertion family.
;;
;; How the preview actually works, since it is NOT the AUCTeX pipeline:
;; markdown-mode pipes the buffer through an external converter
;; (`markdown-command'), wraps the returned HTML *fragment* in a <head>
;; of our making (`markdown-xhtml-header-content' below), writes the
;; result next to the source file as FOO.html, and loads that file in
;; eww in a side window.  Two consequences worth knowing:
;;
;;   - The converter must emit a fragment, not a whole document.  That
;;     is why pandoc is invoked WITHOUT `--standalone': markdown-mode
;;     only adds its header — i.e. our stylesheet — when the output does
;;     not already match `markdown-xhtml-standalone-regexp'.
;;   - The FOO.html file is real and lives in the source directory.  It
;;     is deleted when the live preview is turned off
;;     (`markdown-live-preview-delete-export'), but a hard kill of Emacs
;;     mid-preview leaves it behind.
;;
;; Math is rendered DIFFERENTLY on the two surfaces, on purpose:
;;
;;   - Live preview (eww): pandoc's default HTML math — `$e^{i\pi}$'
;;     becomes ordinary <em>/<sup> markup, which shr draws as genuinely
;;     raised superscripts.  Tried `--mathml' here first and it was
;;     worse: eww can't lay out MathML, so it flattens the whole thing
;;     AND prints pandoc's <annotation> copy of the TeX after it —
;;     every formula appeared twice.
;;   - Browser (`C-c p b'): `--mathml' is added for that one render
;;     (`flow-markdown--mathml-command'), because Firefox and Chrome
;;     typeset MathML natively — no network, no JavaScript, no MathJax.
;;
;; Either way this is a convenience, not a math surface: real work stays
;; in .tex with the `C-c p p' overlays of flow-preview.el.

;;; Code:

(require 'seq)

;;; --- Which converter to run -----------------------------------------------
;;
;; First candidate whose program is on PATH wins.  pandoc is first
;; because it is the only one here that handles pipe tables, footnotes
;; and math in one pass.  cmark/cmark-gfm are the realistic fallback on
;; the tablet (small C programs, packaged for Termux); the Python and
;; Perl ones are listed because they are what a random machine tends to
;; have.  Each entry is a full argv — markdown-mode accepts a list and
;; passes it to `call-process-region' without a shell, so nothing here
;; needs quoting.

;; Why pandoc's own `markdown' dialect and not `gfm': the gfm reader is
;; commonmark-based and REFUSES the math extension outright ("The
;; extension tex_math_dollars is not supported for gfm"), so `$x$' would
;; come out as literal text.  The `markdown' reader gives math, pipe
;; tables, task lists, strikethrough and footnotes in one go — i.e.
;; everything GFM has that we use, plus the one thing it can't do.

(defconst flow-markdown-command-candidates
  '(("pandoc" "--from=markdown" "--to=html5")
    ("cmark-gfm" "--extension" "table" "--extension" "strikethrough"
     "--extension" "autolink" "--extension" "tasklist")
    ("cmark")
    ("multimarkdown")
    ("markdown_py")
    ("markdown"))
  "Candidate Markdown-to-HTML converters, best first.
Each element is an argv list: program name followed by its arguments.
The program must read Markdown on stdin and write an HTML *fragment*
on stdout — see the header comment on why a standalone document is
wrong here.")

(defun flow-markdown--detect-command ()
  "Return the first installed converter from `flow-markdown-command-candidates'.
Nil when none of them is on PATH."
  (seq-find (lambda (argv) (executable-find (car argv)))
            flow-markdown-command-candidates))

(defun flow-markdown--program ()
  "Return the program name in `markdown-command', whatever its form."
  (let ((cmd (bound-and-true-p markdown-command)))
    (cond ((consp cmd) (car cmd))
          ((stringp cmd) (car (split-string cmd))))))

(defun flow-markdown--ensure-command ()
  "Signal a useful error unless a working converter is configured.
markdown-mode's own message names the missing binary but not what to do
about it, and what to do differs per device."
  (let ((program (flow-markdown--program)))
    (unless (and program (executable-find program))
      (user-error
       "No Markdown converter installed%s.  %s"
       (if program (format " (%s not on PATH)" program) "")
       (pcase flow-profile
         ('laptop "Install one: sudo apt install pandoc")
         ((or 'termux 'android)
          "Install one under Termux: pkg install pandoc (or pkg install cmark)")
         (_ "Install pandoc, or set `flow-markdown-command' in your profile"))))))

;;; --- The mode --------------------------------------------------------------

(use-package markdown-mode
  ;; The package autoloads .md/.markdown/.mkd/... to `markdown-mode'
  ;; already; these two entries only pick the GitHub dialect where the
  ;; file is by convention read on GitHub.
  :mode (("README\\.md\\'" . gfm-mode)
         ("CONTRIBUTING\\.md\\'" . gfm-mode))
  :hook (markdown-mode . visual-line-mode)   ; prose wraps to the window
  :custom
  ;; `$...$' and `\[...\]' fontify as math instead of as literal text,
  ;; and `_' inside them stops being read as emphasis.
  (markdown-enable-math t)
  ;; Fenced code blocks get the real major-mode fontification of their
  ;; info string (```elisp, ```python, ...).
  (markdown-fontify-code-blocks-natively t)
  ;; Headings render at descending sizes.  Pure typography, which is
  ;; exactly what carries structure on a 16-gray panel where the theme's
  ;; heading colours are all the same gray.
  (markdown-header-scaling t)
  ;; `## Title' rather than `## Title ##'.
  (markdown-asymmetric-header t)
  ;; Remove the exported FOO.html when the live preview is switched off,
  ;; not after every single render — deleting on export races eww, which
  ;; reads the file after the export returns.
  (markdown-live-preview-delete-export 'delete-on-destroy)
  :config
  ;; Pin the converter unless the profile already chose one.  Left alone
  ;; if nothing is installed: markdown-mode's default stays in place and
  ;; `flow-markdown--ensure-command' explains the situation at the point
  ;; where it actually matters, instead of erroring at startup.
  (when-let* ((argv (or flow-markdown-command (flow-markdown--detect-command))))
    (setq markdown-command argv))

  ;; The <head> markdown-mode wraps around the converter's fragment.
  ;; eww honours very little of this; the browser view (`C-c p b') is
  ;; where it pays off.  Deliberately self-contained — no CDN, no font
  ;; download, nothing that needs the tablet to be online.
  (setq markdown-xhtml-header-content
        (concat
         "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n"
         "<style>\n"
         "  body { max-width: 42em; margin: 2em auto; padding: 0 1em;\n"
         "         font-family: 'TeX Gyre Pagella', Palatino, Georgia, serif;\n"
         "         line-height: 1.5; }\n"
         "  h1, h2, h3, h4 { line-height: 1.2; margin-top: 1.4em; }\n"
         "  code, pre, kbd { font-family: 'JetBrains Mono', monospace; font-size: 0.9em; }\n"
         "  pre { background: #f4f4f4; padding: 0.6em 0.8em; overflow-x: auto; }\n"
         "  blockquote { border-left: 3px solid #bbb; margin-left: 0;\n"
         "               padding-left: 1em; color: #444; }\n"
         "  table { border-collapse: collapse; }\n"
         "  th, td { border: 1px solid #bbb; padding: 0.3em 0.6em; }\n"
         "  img { max-width: 100%; }\n"
         "</style>\n"))

  (define-key markdown-mode-map (kbd "C-c p p") #'flow-markdown-preview-toggle)
  (define-key markdown-mode-map (kbd "C-c p b") #'flow-markdown-preview-browser)
  (define-key markdown-mode-map (kbd "C-c p c") #'flow-markdown-preview-close)
  (define-key markdown-mode-map (kbd "C-c p i") #'flow-markdown-toggle-images))

;;; --- Commands behind the C-c p keys ----------------------------------------
;;
;; These two are the only markdown-mode entry points used here that
;; carry no autoload cookie; declaring them keeps a byte-compile of this
;; file quiet.  Reachability is not in doubt at runtime — every command
;; below is bound in `markdown-mode-map', so the package is loaded.

(declare-function markdown-preview "markdown-mode" (&optional output-buffer-name))
(declare-function markdown-toggle-inline-images "markdown-mode" ())

(defun flow-markdown-preview-toggle ()
  "Toggle the live HTML preview of this buffer in a side window.
Renders now and re-renders on every save.  The buffer must be visiting
a file — the exported HTML is written beside it."
  (interactive)
  (flow-markdown--ensure-command)
  (unless buffer-file-name
    (user-error "Save this buffer to a file first — the preview exports beside it"))
  (markdown-live-preview-mode 'toggle))

(defconst flow-markdown--math-flag-re
  "\\`--\\(mathml\\|mathjax\\|katex\\|webtex\\|gladtex\\|mimetex\\|jsmath\\)"
  "Matches any pandoc flag that already decides how math is emitted.")

(defun flow-markdown--mathml-command ()
  "`markdown-command' with pandoc's `--mathml' added, where that applies.
Left alone for any other converter, and for a pandoc invocation that
already names a math backend — including one a profile pinned through
`flow-markdown-command'."
  (let ((argv (if (consp markdown-command)
                  markdown-command
                (split-string (or markdown-command "")))))
    (if (and (equal (file-name-nondirectory (or (car argv) "")) "pandoc")
             (not (seq-some (lambda (arg)
                              (string-match-p flow-markdown--math-flag-re arg))
                            argv)))
        (append argv '("--mathml"))
      argv)))

(defun flow-markdown-preview-browser ()
  "Render this buffer once and open the HTML in the system browser.
This is where math is typeset: the render is done with `--mathml',
which a real browser lays out and eww cannot."
  (interactive)
  (flow-markdown--ensure-command)
  (let ((markdown-command (flow-markdown--mathml-command)))
    (markdown-preview)))

(defun flow-markdown-preview-close ()
  "Turn off the live preview and remove its exported HTML file."
  (interactive)
  (if (bound-and-true-p markdown-live-preview-mode)
      (markdown-live-preview-mode -1)
    (message "No live preview in this buffer")))

(defun flow-markdown-toggle-images ()
  "Show or hide inline images in this buffer."
  (interactive)
  (unless (display-graphic-p)
    (user-error "This Emacs has no image support (terminal frame)"))
  (markdown-toggle-inline-images))

(provide 'flow-markdown)
;;; flow-markdown.el ends here

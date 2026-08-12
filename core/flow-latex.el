;;; flow-latex.el --- LaTeX authoring: AUCTeX, cdlatex, snippets, folding -*- lexical-binding: t; -*-
;;
;; Device-independent half of Karthik Chikmagalur's "LaTeX Input for
;; Impatient Scholars" workflow:
;;   https://karthinks.com/software/latex-input-for-impatient-scholars/
;;   https://gist.github.com/karthink/7d89df35ee9b7ac0c93d0177b862dadb
;;
;; Everything here works with or without image support, so all three
;; profiles load it.  What needs a graphical frame — inline preview
;; overlays, org fragment images, buffer-font syncing — lives in
;; `flow-preview.el' and `latex-font-sync.el' instead.
;;
;; Keys defined here:
;;   C-S-e     evaluate the line/region with calc, replace with the result
;;   TAB       cdlatex expansion, co-operating with yasnippet fields
;;   C-c )     RefTeX: insert \ref from a label menu
;;   C-c &     RefTeX: jump from \ref at point to its \label
;;   C-c (     RefTeX: insert a \label, prefixed by environment
;;   C-c =     RefTeX: table of contents

;;; Code:

;;; --- AUCTeX ---------------------------------------------------------------

(use-package tex
  :ensure auctex
  :demand t
  :hook ((LaTeX-mode . visual-line-mode))
  :bind (:map LaTeX-mode-map
              ("C-S-e" . latex-math-from-calc))
  :config
  (require 'latex)      ; guarantees LaTeX-mode + LaTeX-mode-map
  (require 'texmathp)   ; guarantees texmathp / texmathp-why
  (setq TeX-parse-self t
        TeX-auto-save t
        TeX-master nil
        TeX-electric-math '("$" . "$")
        TeX-electric-sub-and-superscript t
        LaTeX-electric-left-right-brace t
        TeX-engine 'default              ; pdflatex
        ;; Don't raise `^{...}' / lower `_{...}' graphically via display
        ;; properties: the visual shift makes the caret jump across lines
        ;; while editing.  Rendered math is what previews are for.
        font-latex-fontify-script nil
        font-latex-fontify-sectioning flow-latex-sectioning-scale)

  (when flow-latex-prettify-symbols
    (add-hook 'LaTeX-mode-hook #'prettify-symbols-mode))

  ;; Make `\textbf{...}' / `\textit{...}' read as actual bold / italic in
  ;; the buffer, so the source looks close to the compiled document.
  (with-eval-after-load 'font-latex
    (when flow-monochrome-latex-faces
      ;; AUCTeX tints these olive-green by default.  On a gray panel the
      ;; tint only muddies the weight/slant change that carries the
      ;; meaning — strip it so typography is the single visual cue.
      (dolist (face '(font-latex-bold-face
                      font-latex-italic-face
                      font-latex-math-face
                      font-latex-sedate-face
                      font-latex-string-face
                      font-latex-warning-face
                      font-latex-verbatim-face))
        (when (facep face)
          (set-face-attribute face nil :foreground 'unspecified))))
    ;; Force weight/slant explicitly in case a theme cleared them.
    (set-face-attribute 'font-latex-bold-face   nil :weight 'bold :slant 'normal)
    (set-face-attribute 'font-latex-italic-face nil :weight 'normal :slant 'italic))

  (defun latex-math-from-calc ()
    "Evaluate `calc' on the contents of line at point."
    (interactive)
    (cond ((region-active-p)
           (let* ((beg (region-beginning))
                  (end (region-end))
                  (string (buffer-substring-no-properties beg end)))
             (kill-region beg end)
             (insert (calc-eval `(,string calc-language latex
                                          calc-prefer-frac t
                                          calc-angle-mode rad)))))
          (t (let ((l (thing-at-point 'line)))
               (end-of-line 1) (kill-line 0)
               (insert (calc-eval `(,l
                                    calc-language latex
                                    calc-prefer-frac t
                                    calc-angle-mode rad))))))))

;;; --- RefTeX: reference navigation for Stacks-style notes ------------------
;;
;; RefTeX is BUILT IN (it ships inside Emacs and is on no archive).
;; `:ensure nil' states that intent explicitly — this repo's idiom for
;; anything that must never be fetched.
;;
;; `reftex-plug-into-AUCTeX' turns on all five integration flags
;; (label/ref/cite/index prompts are taken over by RefTeX).  It works via
;; `fset', so undoing it needs a restart.

(use-package reftex
  :ensure nil
  :hook (LaTeX-mode . turn-on-reftex)
  :config
  ;; YaSnippet's minor-mode map claims `C-c &' as a PREFIX for snippet
  ;; management, and yas-minor-mode is on in every LaTeX buffer here — so
  ;; whether it or RefTeX's `reftex-view-crossref' wins would depend on
  ;; minor-mode load order.  Free the key unconditionally; snippet
  ;; management stays reachable via M-x yas-insert-snippet /
  ;; M-x yas-visit-snippet-file.
  (with-eval-after-load 'yasnippet
    (define-key yas-minor-mode-map (kbd "C-c &") nil))
  (setq reftex-plug-into-AUCTeX t)
  ;; Theorem environments from the notes preamble, with Stacks-style label
  ;; prefixes (`lemma-…', not `lem:…').  Entry format:
  ;; (ENV KEY PREFIX REF-FORMAT CONTEXT MAGIC-WORDS).  KEY is the letter
  ;; typed at the `C-c )' type prompt — `?h' for theorem because `?t' is
  ;; taken by tables (RefTeX's own manual makes the same choice).  The
  ;; magic words mean typing "Lemma " right before `C-c )' preselects the
  ;; lemma menu.
  (setq reftex-label-alist
        '(("theorem"     ?h "theorem-"     "~\\ref{%s}" t ("theorem"     "thm."))
          ("proposition" ?p "proposition-" "~\\ref{%s}" t ("proposition" "prop."))
          ("lemma"       ?l "lemma-"       "~\\ref{%s}" t ("lemma"       "lem."))
          ("corollary"   ?c "corollary-"   "~\\ref{%s}" t ("corollary"   "cor."))
          ("definition"  ?d "definition-"  "~\\ref{%s}" t ("definition"  "def."))
          ("example"     ?x "example-"     "~\\ref{%s}" t ("example"))
          ("exercise"    ?X "exercise-"    "~\\ref{%s}" t ("exercise"))
          ("remark"      ?r "remark-"      "~\\ref{%s}" t ("remark")))))

;;; --- CDLaTeX --------------------------------------------------------------

(use-package cdlatex
  :hook ((LaTeX-mode . turn-on-cdlatex)
         (org-mode   . turn-on-org-cdlatex))
  :bind (:map cdlatex-mode-map
              ("<tab>" . cdlatex-tab)))

;;; --- YaSnippet + Karthik's auto-expand hook -------------------------------
;;
;; Snippets live in the repo (core/snippets/), not under
;; `user-emacs-directory' — one copy, shared by every device, and editing
;; one is a commit rather than a file that drifts per machine.

(use-package yasnippet
  :hook ((LaTeX-mode        . yas-minor-mode)
         (org-mode          . yas-minor-mode)
         (post-self-insert  . flow-yas-try-expanding-auto-snippets))
  :config
  (with-eval-after-load 'warnings
    (cl-pushnew '(yasnippet backquote-change)
                warning-suppress-types :test #'equal))
  (setq yas-triggers-in-field t
        yas-snippet-dirs (list (flow-core-file "snippets")))
  (yas-reload-all)

  (defun flow-yas-try-expanding-auto-snippets ()
    (when (and (boundp 'yas-minor-mode) yas-minor-mode)
      (let ((yas-buffer-local-condition ''(require-snippet-condition . auto)))
        (yas-expand)))))

;; Backwards-compatible alias: the hook used to be named `my/…' and may
;; still sit in a stale `custom.el' or a half-loaded session.
(defalias 'my/yas-try-expanding-auto-snippets #'flow-yas-try-expanding-auto-snippets)

;; CDLaTeX <TAB> that co-operates with YaSnippet fields (Karthik).
(with-eval-after-load 'cdlatex
  (with-eval-after-load 'yasnippet
    (add-hook 'cdlatex-tab-hook #'yas-expand)
    (add-hook 'cdlatex-tab-hook #'cdlatex-in-yas-field)
    (define-key yas-keymap (kbd "<tab>") #'yas-next-field-or-cdlatex)
    (define-key yas-keymap (kbd "TAB")  #'yas-next-field-or-cdlatex)

    (defun cdlatex-in-yas-field ()
      (when-let* ((_ (overlayp yas--active-field-overlay))
                  (end (overlay-end yas--active-field-overlay)))
        (if (>= (point) end)
            (let ((s (thing-at-point 'sexp)))
              (unless (and s (assoc (substring-no-properties s)
                                    cdlatex-command-alist-comb))
                (yas-next-field-or-maybe-expand) t))
          (let (cdlatex-tab-hook minp)
            (setq minp
                  (min (save-excursion (cdlatex-tab) (point))
                       (overlay-end yas--active-field-overlay)))
            (goto-char minp) t))))

    (defun yas-next-field-or-cdlatex ()
      "Jump to the next Yas field correctly with cdlatex active."
      (interactive)
      (if (or (bound-and-true-p cdlatex-mode)
              (bound-and-true-p org-cdlatex-mode))
          (cdlatex-tab)
        (yas-next-field-or-maybe-expand)))))

;;; --- Karthik's lazytab (matrix / table entry with cdlatex + org-table) ----

(with-eval-after-load 'cdlatex
  (with-eval-after-load 'org-table
    (define-key orgtbl-mode-map (kbd "<tab>") #'lazytab-org-table-next-field-maybe)
    (define-key orgtbl-mode-map (kbd "TAB")  #'lazytab-org-table-next-field-maybe)
    (add-hook 'cdlatex-tab-hook #'lazytab-cdlatex-or-orgtbl-next-field 90)
    (add-to-list 'cdlatex-command-alist
                 '("smat" "Insert smallmatrix env"
                   "\\left( \\begin{smallmatrix} ? \\end{smallmatrix} \\right)"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("bmat" "Insert bmatrix env"
                   "\\begin{bmatrix} ? \\end{bmatrix}"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("pmat" "Insert pmatrix env"
                   "\\begin{pmatrix} ? \\end{pmatrix}"
                   lazytab-position-cursor-and-edit nil nil t))
    (add-to-list 'cdlatex-command-alist
                 '("tbl" "Insert table"
                   "\\begin{table}\n\\centering ? \\caption{}\n\\end{table}\n"
                   lazytab-position-cursor-and-edit nil t nil))

    (defun lazytab-position-cursor-and-edit ()
      (cdlatex-position-cursor)
      (lazytab-orgtbl-edit))

    (defun lazytab-orgtbl-edit ()
      (advice-add 'orgtbl-ctrl-c-ctrl-c :after #'lazytab-orgtbl-replace)
      (orgtbl-mode 1)
      (open-line 1)
      (insert "\n|"))

    (defun lazytab-orgtbl-replace (_)
      (interactive "P")
      (unless (org-at-table-p) (user-error "Not at a table"))
      (let* ((table (org-table-to-lisp))
             params
             (replacement-table
              (if (texmathp)
                  (lazytab-orgtbl-to-amsmath table params)
                (orgtbl-to-latex table params))))
        (kill-region (org-table-begin) (org-table-end))
        (open-line 1)
        (push-mark)
        (insert replacement-table)
        (align-regexp (region-beginning) (region-end) "\\([[:space:]]*\\)& ")
        (orgtbl-mode -1)
        (advice-remove 'orgtbl-ctrl-c-ctrl-c #'lazytab-orgtbl-replace)))

    (defun lazytab-orgtbl-to-amsmath (table params)
      (orgtbl-to-generic
       table
       (org-combine-plists
        '(:splice t :lstart "" :lend " \\\\" :sep " & " :hline nil :llend "")
        params)))

    (defun lazytab-cdlatex-or-orgtbl-next-field ()
      (when (and (bound-and-true-p orgtbl-mode)
                 (org-table-p)
                 (looking-at "[[:space:]]*\\(?:|\\|$\\)")
                 (let ((s (thing-at-point 'sexp)))
                   (not (and s (assoc s cdlatex-command-alist-comb)))))
        (call-interactively #'org-table-next-field)
        t))

    (defun lazytab-org-table-next-field-maybe ()
      (interactive)
      (if (bound-and-true-p cdlatex-mode)
          (cdlatex-tab)
        (org-table-next-field)))))

;;; --- Fold macros to WYSIWYG-ish, auto-reveal on point entry ---------------
;;
;; `TeX-fold-mode' hides markup behind an overlay: `\textbf{F}' shows as
;; bold "F", `\emph{x}' as italic "x", `\section{Foo}' as "Foo".
;;
;; Auto-reveal on point entry is TeX-fold's OWN machinery
;; (`TeX-fold-auto-reveal', default = reveal on char/left/right motion
;; into the fold).  `reveal-mode' does NOT participate: fold overlays
;; hide their contents through the `display' property, while reveal-mode
;; only watches the `invisible' property.

(when flow-latex-fold
  (add-hook 'LaTeX-mode-hook #'TeX-fold-mode)

  (with-eval-after-load 'tex-fold
    ;; Fold macros inserted via `TeX-insert-macro' (C-c C-m, and cdlatex's
    ;; electric insertion) automatically, so a freshly typed macro
    ;; collapses without a manual `C-c C-o C-b'.  This does not fold
    ;; as-you-type text; it fires on the macro-insertion command only.
    (setq TeX-fold-auto t
          ;; env + macro only, NOT `math'.  Folding math substitutes
          ;; Unicode glyphs (π, ∫, …) that the document text fonts
          ;; (Latin Modern, TeX Gyre Pagella, …) don't contain, so they
          ;; render as tofu.  Math stays as source and is previewed.
          TeX-fold-type-list '(env macro))

    ;; How fold specs work: an integer N means "show arg N as the
    ;; placeholder", and the arg text is copied with its font-latex face,
    ;; so `\textbf{X}' folds to a bold `X'.  A function spec is called
    ;; via `(apply SPEC ARGS)' with the collected `{...}' args.
    ;; `(SPEC . (opt . mand))' extends the fold region to that many args.

    ;; \href{url}{text} → show arg 2 (the visible text), fold both args.
    ;; NOTE: the `(SPEC . SIG)' form requires AUCTeX >= 14.1.1.
    (push '((2 . (0 . 2)) ("href")) TeX-fold-macro-spec-list)

    ;; \enquote{x} → “x”.  A fold function returning nil makes tex-fold
    ;; render the literal string "[Error: No content or function found]";
    ;; returning `abort' is the sanctioned way to skip this occurrence.
    (defun flow-tex-fold-quoted (&rest a)
      (or (when-let* ((s (car a))) (format "\u201C%s\u201D" s)) 'abort))
    (push '(flow-tex-fold-quoted ("enquote")) TeX-fold-macro-spec-list)

    ;; Missing from the defaults; integer 1 preserves the buffer face.
    (push '(1 ("underline" "sout" "st" "url" "path" "text"))
          TeX-fold-macro-spec-list)

    ;; \verb / \verb* are folded natively by AUCTeX via `TeX-fold-verbs'
    ;; (part of the default `TeX-fold-region-functions').  A second
    ;; overlay through `TeX-fold-macro-spec-list' collides with that one
    ;; and leaves an overlay that doesn't span the `|…|' body.  For
    ;; `\lstinline', extend AUCTeX's own verb-macro list instead.
    (when (boundp 'TeX-fold-verb-macros)
      (add-to-list 'TeX-fold-verb-macros "lstinline")))

  ;; Fold the buffer once on open so existing content isn't a wall of
  ;; backslashes.  Deferred a hair so font-lock and AUCTeX styles finish first.
  (add-hook 'LaTeX-mode-hook
            (lambda ()
              (run-with-idle-timer 0.1 nil
                                   (lambda (buf)
                                     (when (buffer-live-p buf)
                                       (with-current-buffer buf
                                         (TeX-fold-buffer))))
                                   (current-buffer)))
            'append))

;;; --- Code font for LaTeX syntactic markup --------------------------------
;;
;; `latex-font-sync' remaps the buffer's default :family to the
;; document's declared font — so `\textbf{...}' args, folded macro
;; contents and section titles render in Pagella / Termes / Latin
;; Modern.  That also drags macro NAMES (`\textbf', `\begin', `\ref')
;; into the serif face, where they get lost among the styled content.
;;
;; Remap the syntactic faces (macro names, braces, comments, env names,
;; math delimiters) to a monospace family so code stands apart from
;; content at a glance.  Only :family is remapped; each face's
;; foreground/weight survives.  Content-styling faces
;; (`font-latex-bold-face', `-italic-face', `-underline-face',
;; sectioning, sub/super, verbatim, type) are deliberately NOT remapped,
;; so they keep inheriting the buffer default, i.e. the document font.

(defconst flow-latex-code-font-faces
  '(font-latex-sedate-face             ; { } [ ]
    font-latex-warning-face            ; \begin, \end, keyword commands
    font-latex-math-face               ; math source highlighting
    font-latex-string-face             ; env names inside \begin{...}
    font-latex-script-char-face        ; ^ and _
    font-latex-doctex-preprocessor-face
    font-latex-doctex-documentation-face
    font-lock-keyword-face             ; \command names
    font-lock-comment-face             ; % comments
    font-lock-comment-delimiter-face
    font-lock-function-name-face       ; \label{}, \ref{}, \newcommand{}
    font-lock-variable-name-face
    font-lock-constant-face
    font-lock-builtin-face
    font-lock-preprocessor-face)
  "Faces remapped to `flow-code-font-family' in LaTeX buffers.")

(defvar-local flow-latex-code-font-cookies nil
  "Face-remap cookies installed by `flow-latex-code-font-apply'.")

(defun flow-latex-code-font-apply ()
  "Remap LaTeX syntactic-markup faces to a monospace family, buffer-locally."
  (when (and (derived-mode-p 'LaTeX-mode)
             (display-graphic-p)
             flow-code-font-family)
    (mapc #'face-remap-remove-relative flow-latex-code-font-cookies)
    (setq flow-latex-code-font-cookies
          (mapcar (lambda (face)
                    (face-remap-add-relative face :family flow-code-font-family))
                  flow-latex-code-font-faces))))

(add-hook 'LaTeX-mode-hook #'flow-latex-code-font-apply)

(provide 'flow-latex)
;;; flow-latex.el ends here

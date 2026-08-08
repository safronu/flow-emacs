;;; init.el --- LaTeX-for-impatient-scholars on native Android Emacs -*- lexical-binding: t; -*-
;;
;; Adapted from Karthik Chikmagalur's "LaTeX Input for Impatient Scholars":
;;   https://karthinks.com/software/latex-input-for-impatient-scholars/
;;   https://gist.github.com/karthink/7d89df35ee9b7ac0c93d0177b862dadb
;;
;; Runs under the native Android Emacs port (org.gnu.emacs), which ships with
;; librsvg / libjpeg / libtiff / cairo — so we get REAL inline `preview-latex'
;; overlays.  The heavy lifting (pdflatex, dvisvgm, ghostscript) is done by
;; the TeX Live installed under Termux at /data/data/com.termux/files/usr, and
;; those binaries are self-contained enough to run from this app's process.
;;
;; Bindings:
;;   C-c C-p C-p   AUCTeX preview at point (inline SVG overlay)
;;   C-c C-p C-b   AUCTeX preview whole buffer
;;   C-c C-p C-c   clear previews at point
;;   C-c p p       my/latex-preview-at-point  (inline overlay via AUCTeX)
;;   C-c p b       preview-buffer
;;   C-c p c       preview-clearout-buffer

;;; --- Package system -------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

;; NEVER refresh archives at startup.  On a mobile connection this blocks the
;; UI for a long time (or forever if the network is asleep).  Bootstrap only:
;; if `use-package' isn't there yet, refresh once and install it.  After that,
;; the user runs `M-x package-refresh-contents' manually when they want
;; updates.  Emacs ≥27 has already called `package-initialize' by this point.
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t
      ;; If a use-package block references a not-yet-installed package,
      ;; don't silently fetch it — bail loudly so startup isn't blocked
      ;; by a network call the user didn't ask for.
      use-package-always-defer nil)

;; Install the current GNU ELPA signing key on first run so signatures work
;; later.  Wrapped in `ignore-errors' so it can't wedge startup.
(unless (package-installed-p 'gnu-elpa-keyring-update)
  (ignore-errors (package-install 'gnu-elpa-keyring-update)))

;;; --- Sane defaults for the Boox tablet ------------------------------------

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

;; E-ink friendly: no blink, no cursor movement animation, high contrast.
(blink-cursor-mode -1)
(setq scroll-conservatively 100
      scroll-margin 2
      scroll-preserve-screen-position t)
(when (display-graphic-p)
  (load-theme 'modus-operandi t)                 ; pure white background
  (set-face-attribute 'default nil :height 150)) ; readable on a 13" e-ink panel

;; Bring Termux binaries onto exec-path so pdflatex / dvisvgm / gs / tlmgr all
;; resolve when Emacs calls them via `call-process' / `start-process'.  These
;; binaries are self-contained and run under this app's process just fine.
(dolist (dir '("/data/data/com.termux/files/usr/bin"
               "/data/data/com.termux/files/usr/bin/texlive"
               "/data/data/com.termux/files/usr/share/texlive/2026/bin/aarch64-linux"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (or (getenv "PATH") "")))))

;; TEXMFROOT is set in early-init.el; everything else (TEXMFDIST, TEXMFVAR,
;; TEXMFSYSVAR) is derived from it by kpathsea via texmf.cnf.

;;; --- AUCTeX ---------------------------------------------------------------

(use-package tex
  :ensure auctex
  :demand t
  :preface
  (defun my/latex-preview-at-point ()
    "Preview the LaTeX construct around point as an inline overlay.
If in math, previews just the formula; otherwise previews the enclosing
environment; otherwise the section."
    (interactive)
    (cond
     ((use-region-p) (preview-region (region-beginning) (region-end)))
     ((and (fboundp 'texmathp) (texmathp))
      (save-excursion
        (let* ((env (car texmathp-why))
               (beg (cdr texmathp-why))
               (end (save-excursion
                      (goto-char beg)
                      (cond
                       ((equal env "$")   (forward-char 1)
                        (or (search-forward "$" nil t) (point-max)))
                       ((equal env "$$")  (forward-char 2)
                        (or (search-forward "$$" nil t) (point-max)))
                       ((equal env "\\(") (forward-char 2)
                        (or (search-forward "\\)" nil t) (point-max)))
                       ((equal env "\\[") (forward-char 2)
                        (or (search-forward "\\]" nil t) (point-max)))
                       (t (or (search-forward (format "\\end{%s}" env) nil t)
                              (point-max)))))))
          (preview-region beg end))))
     (t (preview-section))))
  :hook ((LaTeX-mode . prettify-symbols-mode)
         (LaTeX-mode . visual-line-mode))
  :bind (:map LaTeX-mode-map
              ("C-S-e"   . latex-math-from-calc)
              ("C-c p p" . my/latex-preview-at-point)
              ("C-c p b" . preview-buffer)
              ("C-c p c" . preview-clearout-buffer))
  :config
  (require 'latex)
  (require 'texmathp)
  (setq TeX-parse-self t
        TeX-auto-save t
        TeX-master nil
        TeX-electric-math '("$" . "$")
        TeX-electric-sub-and-superscript t
        LaTeX-electric-left-right-brace t
        ;; Use pdflatex; it's the default LaTeX engine we installed.
        TeX-engine 'default)

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

;;; --- preview-latex: inline overlays (karthinks-style) ---------------------
;;
;; AUCTeX's `preview' subsystem shells out to a LaTeX run that produces one
;; image per formula, then overlays those images on top of the source.
;;
;; NOTE on image types: the valid values of `preview-image-type' are `png',
;; `jpeg', `pnm', `tiff' (all via Ghostscript on the PDF) and `dvi*' (which
;; uses `preview-dvi*-command' — e.g. dvisvgm — on a DVI file).  SVG output
;; requires the DVI pipeline (i.e. `TeX-PDF-mode nil'); with pdflatex we use
;; PNG.  On the Boox e-ink screen, PNG at scale 1.4 is crisp enough.

(use-package preview
  :after latex
  :config
  (setq preview-image-type 'png
        ;; Default scale function = face-pt / doc-pt (e.g. 15pt / 10pt = 1.5).
        ;; With DPI overridden below to Emacs's actual rendering DPI, this
        ;; makes 1 preview em == 1 buffer em, so previews scale in lockstep
        ;; with the Emacs default face height.
        preview-scale-function #'preview-scale-from-face
        preview-auto-reveal t)

  ;; Android Emacs reports a bogus monitor physical size, so preview.el's
  ;; built-in `preview-get-dpi' computes garbage (~9 DPI).  Derive DPI from
  ;; the frame's actual character metrics, and scale by the buffer's
  ;; `text-scale-mode-amount' so `C-x C-+' / `C-x C--' also resize previews.
  ;; This tracks both global default-face changes AND per-buffer zoom.
  (defun preview-get-dpi ()
    (let* ((face-pt   (/ (face-attribute 'default :height) 10.0))
           (char-px   (float (frame-char-height)))
           (base-dpi  (/ (* char-px 72.0) face-pt))
           (zoom      (if (bound-and-true-p text-scale-mode)
                          (expt text-scale-mode-step text-scale-mode-amount)
                        1.0))
           (dpi       (* base-dpi zoom)))
      (cons dpi dpi)))

  ;; When the buffer's text-scale changes, existing overlays stay at their
  ;; old pixel size.  Clear them so the next `C-c p p' regenerates at the
  ;; new zoom level.
  (add-hook 'text-scale-mode-hook
            (lambda ()
              (when (derived-mode-p 'LaTeX-mode)
                (preview-clearout-buffer)))))

;;; --- Sync buffer font to LaTeX document font ------------------------------
;;
;; Remap the buffer's default face family to a TTF matching the document's
;; declared font package (mathpazo → TeX Gyre Pagella, times → TeX Gyre
;; Termes, etc.).  Only the `:family' is remapped; `:height' stays global
;; so previews continue to scale with the default face.  See
;; `latex-font-sync.el' for the detector / resolver / applier details.
;; TTFs are shipped in `android-emacs/fonts/' and symlinked into
;; `$HOME/fonts' by install.sh (Android Emacs enumerates that dir on launch).

(add-to-list 'load-path user-emacs-directory)
(require 'latex-font-sync)


;;; --- CDLaTeX --------------------------------------------------------------

(use-package cdlatex
  :hook ((LaTeX-mode . turn-on-cdlatex)
         (org-mode   . turn-on-org-cdlatex))
  :bind (:map cdlatex-mode-map
              ("<tab>" . cdlatex-tab)))

;;; --- YaSnippet + Karthik's auto-expand hook -------------------------------

(use-package yasnippet
  :hook ((LaTeX-mode        . yas-minor-mode)
         (org-mode          . yas-minor-mode)
         (post-self-insert  . my/yas-try-expanding-auto-snippets))
  :config
  (with-eval-after-load 'warnings
    (cl-pushnew '(yasnippet backquote-change)
                warning-suppress-types :test #'equal))
  (setq yas-triggers-in-field t
        yas-snippet-dirs (list (expand-file-name "snippets" user-emacs-directory)))
  (yas-reload-all)

  (defun my/yas-try-expanding-auto-snippets ()
    (when (and (boundp 'yas-minor-mode) yas-minor-mode)
      (let ((yas-buffer-local-condition ''(require-snippet-condition . auto)))
        (yas-expand)))))

;; CDLatex <TAB> that co-operates with YaSnippet fields (Karthik).
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
        (align-regexp (region-beginning) (region-end) "\\([:space:]]*\\)& ")
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

;;; --- org-mode inline previews (bonus) -------------------------------------
;;
;; In .org buffers, C-c C-x C-l previews all LaTeX fragments inline as SVG.

(with-eval-after-load 'org
  (setq org-preview-latex-default-process 'dvisvgm
        org-preview-latex-image-directory
        (expand-file-name "ltximg/" (getenv "HOME")))
  (plist-put org-format-latex-options :scale 1.6))

(provide 'init)
;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

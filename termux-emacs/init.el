;;; init.el --- LaTeX-for-impatient-scholars on Termux/Boox -*- lexical-binding: t; -*-
;;
;; Adapted from Karthik Chikmagalur's "LaTeX Input for Impatient Scholars"
;; workflow (AUCTeX + CDLaTeX + YaSnippet + lazytab).  Original gist:
;; https://gist.github.com/karthink/7d89df35ee9b7ac0c93d0177b862dadb
;;
;; This Emacs on Termux is a terminal build (no PNG/SVG image support), so the
;; inline overlay preview of the original workflow is replaced with an
;; on-demand render: `M-x my/latex-preview-at-point' (bound to <f5>) compiles
;; the formula around point to PNG and hands it to Android via `termux-open'.
;; A companion HTTP server (bin/latex-preview-server) can be pointed at from
;; the Boox browser for continuous side-by-side preview.

;;; --- Package system -------------------------------------------------------

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(setq package-quickstart t)
(package-initialize)
(unless package-archive-contents (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;;; --- Sane defaults for a tablet -------------------------------------------

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

;; Ensure TeX Live binaries are visible to child processes, even if this Emacs
;; was launched from a context that did not source ~/.bashrc.
(dolist (dir '("/data/data/com.termux/files/usr/bin"
               "/data/data/com.termux/files/usr/bin/texlive"
               "/data/data/com.termux/files/home/.local/bin"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (getenv "PATH")))))

;;; --- AUCTeX ----------------------------------------------------------------
;;
;; Karthik's config verbatim, minus the preview-overlay bits (we have no image
;; support in this terminal Emacs).  `latex-math-from-calc' is preserved because
;; it is independently useful.

;; Load AUCTeX eagerly so opening a .tex file uses `LaTeX-mode' (AUCTeX)
;; instead of Emacs's built-in `latex-mode', and so `LaTeX-mode-map',
;; `texmathp' etc. are available before any user command.
(use-package tex
  :ensure auctex
  :demand t
  :hook ((LaTeX-mode . prettify-symbols-mode)
         (LaTeX-mode . visual-line-mode))
  :bind (:map LaTeX-mode-map
              ("C-S-e" . latex-math-from-calc)
              ("<f5>"  . my/latex-preview-at-point)
              ("<f6>"  . my/latex-preview-buffer)
              ("<f7>"  . my/latex-preview-open-viewer))
  :config
  (require 'latex)      ; guarantees LaTeX-mode + LaTeX-mode-map
  (require 'texmathp)   ; guarantees texmathp / texmathp-why
  (setq TeX-parse-self t
        TeX-auto-save t
        TeX-master nil
        TeX-electric-math '("$" . "$")
        TeX-electric-sub-and-superscript t
        LaTeX-electric-left-right-brace t)

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

;;; --- CDLaTeX ---------------------------------------------------------------

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

;;; --- Preview: compile formula at point to PNG, hand to Android ------------
;;
;; Terminal Emacs on Termux has no image support.  Instead of overlays we
;; render into ~/latex-scratch/preview/ and open with `termux-open' (which
;; hands the file to Android's default image viewer).  A tiny HTTP server in
;; bin/latex-preview-server can serve the same directory to the Boox browser
;; for split-screen "live" preview.

(defcustom my/latex-preview-dir
  (expand-file-name "~/latex-scratch/preview/")
  "Directory where formula previews are written."
  :type 'directory :group 'my-latex)

(defcustom my/latex-preview-dpi 200
  "Resolution for PNG renders. Higher = crisper on e-ink, slower to render."
  :type 'integer :group 'my-latex)

(defcustom my/latex-preview-preamble
  "\\documentclass[border=8pt,varwidth]{standalone}
\\usepackage{amsmath,amssymb,mathtools}
\\usepackage[T1]{fontenc}
\\begin{document}
%s
\\end{document}\n"
  "Wrapper document for previewing a snippet. `%s' is replaced with the body."
  :type 'string :group 'my-latex)

(defun my/latex--formula-at-point ()
  "Return (BEG END STRING) for the LaTeX math around point, or the active region.
Recognises $...$, \\(...\\), \\[...\\], and \\begin{env}...\\end{env} via
`texmathp'.  Falls back to the current paragraph."
  (cond
   ((use-region-p)
    (list (region-beginning) (region-end)
          (buffer-substring-no-properties (region-beginning) (region-end))))
   ((and (fboundp 'texmathp) (texmathp))
    ;; `texmathp-why' is (ENV . OPEN-POS).  OPEN-POS points at the first
    ;; character of the opening delimiter, so the delimiter itself is included
    ;; in the render — good; we want the whole thing.
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
                     (t                 (or (search-forward
                                             (format "\\end{%s}" env) nil t)
                                            (point-max)))))))
        (list beg end (buffer-substring-no-properties beg end)))))
   (t
    (list (save-excursion (backward-paragraph) (point))
          (save-excursion (forward-paragraph) (point))
          (or (thing-at-point 'paragraph t) "")))))

(defvar my/latex-preview--counter 0)

(defun my/latex--render (body)
  "Compile BODY (a LaTeX snippet) to PNG in `my/latex-preview-dir'.
Returns the absolute PNG path, or signals an error with the log tail."
  (make-directory my/latex-preview-dir t)
  (let* ((stem (format "preview-%03d" (cl-incf my/latex-preview--counter)))
         (work (file-name-as-directory
                (expand-file-name stem my/latex-preview-dir)))
         (tex  (expand-file-name (concat stem ".tex") work))
         (pdf  (expand-file-name (concat stem ".pdf") work))
         (png  (expand-file-name (concat stem ".png") work))
         (latest-png (expand-file-name "latest.png" my/latex-preview-dir))
         (latest-tex (expand-file-name "latest.tex" my/latex-preview-dir)))
    (make-directory work t)
    (with-temp-file tex
      (insert (format my/latex-preview-preamble body)))
    (let* ((default-directory work)
           (buf (get-buffer-create "*latex-preview*"))
           (rc  (call-process "pdflatex" nil buf nil
                              "-interaction=nonstopmode"
                              "-halt-on-error"
                              (file-name-nondirectory tex))))
      (unless (and (eq rc 0) (file-exists-p pdf))
        (pop-to-buffer buf)
        (error "pdflatex failed (rc=%s), see *latex-preview*" rc))
      (let ((rc2 (call-process "gs" nil buf nil
                               "-q" "-dNOPAUSE" "-dBATCH" "-dSAFER"
                               "-sDEVICE=pngalpha"
                               (format "-r%d" my/latex-preview-dpi)
                               (concat "-sOutputFile=" png)
                               pdf)))
        (unless (and (eq rc2 0) (file-exists-p png))
          (pop-to-buffer buf)
          (error "ghostscript PDF->PNG failed (rc=%s)" rc2))))
    ;; Publish "latest" files so the HTTP server and viewer always find them.
    (copy-file png latest-png t)
    (copy-file tex latest-tex t)
    latest-png))

(defun my/latex-preview-at-point ()
  "Render the LaTeX math at point (or the active region) and open the PNG."
  (interactive)
  (pcase-let* ((`(,_beg ,_end ,body) (my/latex--formula-at-point))
               (png (my/latex--render body)))
    (message "latex preview: %s" png)
    (my/latex-preview-open png)))

(defun my/latex-preview-buffer ()
  "Render the current LaTeX buffer's body (between \\begin/\\end{document} if
present, else the whole buffer) and open the PNG."
  (interactive)
  (let* ((body (save-excursion
                 (goto-char (point-min))
                 (if (re-search-forward "\\\\begin{document}" nil t)
                     (let ((b (point)))
                       (goto-char (point-max))
                       (re-search-backward "\\\\end{document}" nil t)
                       (buffer-substring-no-properties b (point)))
                   (buffer-substring-no-properties (point-min) (point-max)))))
         (png (my/latex--render body)))
    (message "latex preview: %s" png)
    (my/latex-preview-open png)))

(defcustom my/latex-preview-open-command "termux-open"
  "Command used to hand a rendered image to Android.
Set to nil to skip opening (useful with the HTTP server + browser)."
  :type '(choice (const :tag "Don't open" nil) string)
  :group 'my-latex)

(defun my/latex-preview-open (path)
  "Open PATH with `my/latex-preview-open-command', if set."
  (when my/latex-preview-open-command
    (call-process my/latex-preview-open-command nil 0 nil path)))

(defun my/latex-preview-open-viewer ()
  "Open the preview folder in Android's image viewer (last render)."
  (interactive)
  (let ((latest (expand-file-name "latest.png" my/latex-preview-dir)))
    (if (file-exists-p latest)
        (my/latex-preview-open latest)
      (user-error "No previews yet — hit <f5> on a formula first"))))

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

(provide 'init)
;;; init.el ends here

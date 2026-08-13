;;; init.el --- Boox profile: Termux Emacs (-nw, no image support) -*- lexical-binding: t; -*-
;;
;; The e-ink tablet's terminal profile.  This file holds ONLY what is
;; true of this Emacs build; everything portable lives in ../core/ and is
;; shared with the Android and laptop profiles.
;;
;; This Emacs is a terminal build with no image support at all (check
;; with `M-x describe-variable RET image-types'), so the inline overlay
;; previews of the graphical profiles are replaced with an on-demand
;; render: <f5> compiles the formula around point to PNG and hands it to
;; Android via `termux-open'.  A companion HTTP server
;; (bin/latex-preview-server) can serve the same directory to the Boox
;; browser for continuous side-by-side preview.
;;
;; Keys added on top of the shared ones:
;;   <f5>   render the formula at point to PNG, open in Android's viewer
;;   <f6>   render the whole buffer body
;;   <f7>   re-open the last render

;;; Code:

;; Find the repo through this file's symlink and declare the knobs.
(load (expand-file-name "../core/flow-boot"
                        (file-name-directory (file-truename load-file-name)))
      nil 'nomessage)

;;; --- What this device is --------------------------------------------------

(setq flow-profile 'termux
      flow-eink-p t
      ;; A -nw frame has no fonts, themes or preview images; leave every
      ;; graphical knob nil.  The terminal emulator owns the font.
      flow-font-family nil
      flow-font-height nil
      flow-code-font-family nil
      flow-theme nil
      flow-monochrome-latex-faces t
      ;; With no rendered previews available at all, prettified symbols
      ;; (\pi shown as π) are the least bad way to read math — the
      ;; baseline-jump objection matters less in a 16-color terminal.
      flow-latex-prettify-symbols t
      ;; TeX-fold's overlays also work on a tty, but without the font
      ;; machinery bold/italic folds render inconsistently under Termux;
      ;; historically this profile never folded.  Keep it off.
      flow-latex-fold nil
      ;; flow-page's display-math air is sized from pixel font metrics,
      ;; which a tty doesn't have.  The module is never loaded here; the
      ;; nil documents intent.
      flow-page nil
      flow-deadlines-repo
      (let ((d (expand-file-name "~/deadlines"))) (and (file-directory-p d) d)))

;; TeX Live binaries must be visible to child processes even when this
;; Emacs was launched from a context that didn't source ~/.bashrc.
(dolist (dir '("/data/data/com.termux/files/usr/bin"
               "/data/data/com.termux/files/usr/bin/texlive"
               "/data/data/com.termux/files/home/.local/bin"))
  (when (file-directory-p dir)
    (add-to-list 'exec-path dir)
    (setenv "PATH" (concat dir ":" (getenv "PATH")))))

;;; --- Shared modules -------------------------------------------------------

(flow-load "flow-core")       ; packages, defaults, M-o window management
(flow-load "flow-latex")      ; AUCTeX, cdlatex, snippets, folding
(flow-load "flow-deadlines")  ; private repo, loaded only if cloned
;; NOT flow-preview: it drives image overlays this build cannot display.

;;; --- Preview: compile formula at point to PNG, hand to Android ------------

(defcustom flow-termux-preview-dir
  (expand-file-name "~/latex-scratch/preview/")
  "Directory where formula previews are written."
  :type 'directory :group 'flow)

(defcustom flow-termux-preview-dpi 200
  "Resolution for PNG renders. Higher = crisper on e-ink, slower to render."
  :type 'integer :group 'flow)

(defcustom flow-termux-preview-preamble
  "\\documentclass[border=8pt,varwidth]{standalone}
\\usepackage{amsmath,amssymb,mathtools}
\\usepackage[T1]{fontenc}
\\begin{document}
%s
\\end{document}\n"
  "Wrapper document for previewing a snippet. `%s' is replaced with the body."
  :type 'string :group 'flow)

(defun flow-termux--formula-at-point ()
  "Return (BEG END STRING) for the LaTeX math around point, or the active region.
Recognises $...$, \\(...\\), \\[...\\], and \\begin{env}...\\end{env} via
`texmathp'.  Falls back to the current paragraph."
  (cond
   ((use-region-p)
    (list (region-beginning) (region-end)
          (buffer-substring-no-properties (region-beginning) (region-end))))
   ((and (fboundp 'texmathp) (texmathp))
    ;; `texmathp-why' is (ENV . OPEN-POS).  OPEN-POS points at the first
    ;; character of the opening delimiter, so the delimiter itself is
    ;; included in the render — good; we want the whole thing.
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

(defvar flow-termux-preview--counter 0)

(defun flow-termux--render (body)
  "Compile BODY (a LaTeX snippet) to PNG in `flow-termux-preview-dir'.
Returns the absolute PNG path, or signals an error with the log tail."
  (make-directory flow-termux-preview-dir t)
  (let* ((stem (format "preview-%03d" (cl-incf flow-termux-preview--counter)))
         (work (file-name-as-directory
                (expand-file-name stem flow-termux-preview-dir)))
         (tex  (expand-file-name (concat stem ".tex") work))
         (pdf  (expand-file-name (concat stem ".pdf") work))
         (png  (expand-file-name (concat stem ".png") work))
         (latest-png (expand-file-name "latest.png" flow-termux-preview-dir))
         (latest-tex (expand-file-name "latest.tex" flow-termux-preview-dir)))
    (make-directory work t)
    (with-temp-file tex
      (insert (format flow-termux-preview-preamble body)))
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
                               (format "-r%d" flow-termux-preview-dpi)
                               (concat "-sOutputFile=" png)
                               pdf)))
        (unless (and (eq rc2 0) (file-exists-p png))
          (pop-to-buffer buf)
          (error "ghostscript PDF->PNG failed (rc=%s)" rc2))))
    ;; Publish "latest" files so the HTTP server and viewer always find them.
    (copy-file png latest-png t)
    (copy-file tex latest-tex t)
    latest-png))

(defcustom flow-termux-preview-open-command "termux-open"
  "Command used to hand a rendered image to Android.
Set to nil to skip opening (useful with the HTTP server + browser)."
  :type '(choice (const :tag "Don't open" nil) string)
  :group 'flow)

(defun flow-termux-preview-open (path)
  "Open PATH with `flow-termux-preview-open-command', if set."
  (when flow-termux-preview-open-command
    (call-process flow-termux-preview-open-command nil 0 nil path)))

(defun flow-termux-preview-at-point ()
  "Render the LaTeX math at point (or the active region) and open the PNG."
  (interactive)
  (pcase-let* ((`(,_beg ,_end ,body) (flow-termux--formula-at-point))
               (png (flow-termux--render body)))
    (message "latex preview: %s" png)
    (flow-termux-preview-open png)))

(defun flow-termux-preview-buffer ()
  "Render the buffer body (between \\begin/\\end{document} if present) as PNG."
  (interactive)
  (let* ((body (save-excursion
                 (goto-char (point-min))
                 (if (re-search-forward "\\\\begin{document}" nil t)
                     (let ((b (point)))
                       (goto-char (point-max))
                       (re-search-backward "\\\\end{document}" nil t)
                       (buffer-substring-no-properties b (point)))
                   (buffer-substring-no-properties (point-min) (point-max)))))
         (png (flow-termux--render body)))
    (message "latex preview: %s" png)
    (flow-termux-preview-open png)))

(defun flow-termux-preview-open-viewer ()
  "Open the last render in Android's image viewer."
  (interactive)
  (let ((latest (expand-file-name "latest.png" flow-termux-preview-dir)))
    (if (file-exists-p latest)
        (flow-termux-preview-open latest)
      (user-error "No previews yet — hit <f5> on a formula first"))))

(with-eval-after-load 'latex
  (define-key LaTeX-mode-map (kbd "<f5>") #'flow-termux-preview-at-point)
  (define-key LaTeX-mode-map (kbd "<f6>") #'flow-termux-preview-buffer)
  (define-key LaTeX-mode-map (kbd "<f7>") #'flow-termux-preview-open-viewer))

;; The commands used to be `my/latex-preview-*'; keep the names alive.
(defalias 'my/latex-preview-at-point   #'flow-termux-preview-at-point)
(defalias 'my/latex-preview-buffer     #'flow-termux-preview-buffer)
(defalias 'my/latex-preview-open-viewer #'flow-termux-preview-open-viewer)

(provide 'init)
;;; init.el ends here

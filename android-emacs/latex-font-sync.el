;;; latex-font-sync.el --- Sync buffer face family to LaTeX document font -*- lexical-binding: t; -*-
;;
;; When a LaTeX document declares a text-font package (`mathpazo',
;; `times', etc.) or a raw NFSS override (`\renewcommand{\rmdefault}{ppl}'),
;; remap the buffer's default face family to the matching TrueType font
;; installed under $HOME/fonts/.  Only affects the current buffer; the
;; global default face height (set in init.el for preview DPI derivation)
;; is untouched.
;;
;; Architecture (v1, pdflatex only):
;;   Layer A  package alist          - `my/latex-font-package-alist'
;;            NFSS-code alist        - `my/latex-font-nfss-code-alist'
;;   Layer B  intended-family key    - `my/latex-font-candidate-alist'
;;                                   - ordered candidate list, ends in a
;;                                     family guaranteed to exist on Android
;;                                     (Noto Serif / Noto Sans / Droid Sans Mono)
;;   Layer C  user overrides file    - `my/latex-font-overrides-file'
;;
;; Data sources we read (AUCTeX already parses these; we do NOT write our own
;; preamble parser except for the NFSS regex, which AUCTeX doesn't expose
;; keyed by macro name):
;;   `LaTeX-provided-package-options'  - alist ((pkg . opts) ...)
;;   `LaTeX-provided-class-options'    - alist ((cls . opts) ...)
;;   `TeX-active-styles'               - loaded styles (`nil' until parsed)
;;
;; Fires on `LaTeX-mode-hook' (first open) and `TeX-update-style-hook'
;; (re-parse, which runs on save via `TeX-auto-save t' in init.el).
;;
;; XeLaTeX `\setmainfont' is out of scope in v1.

(require 'cl-lib)

;;; --- Layer A: package + NFSS-code → intended-family key ------------------

(defconst my/latex-font-package-alist
  '((mathpazo   . :family/palatino)
    (palatino   . :family/palatino)
    (newpxtext  . :family/palatino)
    (newpx      . :family/palatino)
    (kpfonts    . :family/palatino)
    (mathptmx   . :family/times)
    (times      . :family/times)
    (newtxtext  . :family/times)
    (newtx      . :family/times)
    (bookman    . :family/bookman)
    (newcent    . :family/newcent)
    (chancery   . :family/chancery)
    (lmodern    . :family/lm-roman))
  "Map LaTeX font package name → intended-family key.
Priority: last-loaded wins in LaTeX; we approximate by matching the LAST
entry in `LaTeX-provided-package-options' that appears here.  Packages
that only change `\\sfdefault' / `\\ttdefault' (helvet, courier) are
deliberately omitted — body font drives buffer legibility.")

(defconst my/latex-font-nfss-code-alist
  '(("ppl"    . :family/palatino)
    ("pplj"   . :family/palatino)
    ("pplx"   . :family/palatino)
    ("zpltlf" . :family/palatino)
    ("jkp"    . :family/palatino)
    ("ptm"    . :family/times)
    ("ntxtlf" . :family/times)
    ("pbk"    . :family/bookman)
    ("pnc"    . :family/newcent)
    ("pzc"    . :family/chancery)
    ("lmr"    . :family/lm-roman)
    ("cmr"    . :family/lm-roman))
  "Map NFSS three/four-letter code → intended-family key.
Applied to arguments of `\\renewcommand{\\rmdefault}{...}' in the preamble.")

(defconst my/latex-font-rmdefault-regex
  "\\\\renewcommand\\*?\\s-*{?\\\\rmdefault}?\\s-*{\\([a-z]+\\)}"
  "Regex matching `\\renewcommand{\\rmdefault}{code}' with optional braces.")

;;; --- Layer B: intended-family → ordered TTF candidate list --------------

(defconst my/latex-font-candidate-alist
  '((:family/lm-roman . ("Latin Modern Roman" "Noto Serif" "serif"))
    (:family/palatino . ("TeX Gyre Pagella" "Noto Serif" "serif"))
    (:family/times    . ("TeX Gyre Termes" "Noto Serif" "serif"))
    (:family/bookman  . ("TeX Gyre Bonum" "Noto Serif" "serif"))
    (:family/newcent  . ("TeX Gyre Schola" "Noto Serif" "serif"))
    (:family/chancery . ("TeX Gyre Chorus" "Noto Serif" "serif")))
  "Map intended-family key → ordered list of family-name strings to try.
Each list ends in a family guaranteed to exist on the Android Emacs port
(Noto Serif is present on every Boox), so `my/latex-resolve-family'
never returns nil for a known key.")

;;; --- Layer C: user overrides --------------------------------------------

(defvar my/latex-font-overrides-file
  (expand-file-name "latex-font-overrides.el" user-emacs-directory)
  "Optional user file loaded at feature init.
It may `setq' the following variables:
  `my/latex-font-user-overrides-by-path'  - alist of (glob . intended-key)
  `my/latex-font-user-candidates'         - additions to `my/latex-font-candidate-alist'.")

(defvar my/latex-font-user-overrides-by-path nil
  "Alist of (filename-glob . intended-family-key) that force a family for matching files.")

(defvar my/latex-font-user-candidates nil
  "Extra intended-family → candidate-list entries appended to the built-in alist.")

(condition-case err
    (load my/latex-font-overrides-file 'noerror 'nomessage)
  (error (message "latex-font-sync: overrides file failed to load: %s" err)))

;;; --- Layer C helper: combined candidate lookup --------------------------

(defun my/latex-font--all-candidates (intended)
  "Return the effective candidate list for INTENDED, user overrides first."
  (or (cdr (assq intended my/latex-font-user-candidates))
      (cdr (assq intended my/latex-font-candidate-alist))))

(defun my/latex-font--override-for-file (path)
  "Return the overridden intended-family key for PATH, or nil."
  (when path
    (cl-loop for (glob . key) in my/latex-font-user-overrides-by-path
             when (string-match-p (wildcard-to-regexp glob) path)
             return key)))

;;; --- Layer A/preamble: detect intended family in current buffer ---------

(defun my/latex-detect-intended-family ()
  "Return the intended-family key for the current LaTeX buffer, or nil.
Nil means \"unknown, don't touch the face\" (AUCTeX hasn't parsed yet).
Fallback for parsed-but-no-font-package buffers is `:family/lm-roman'."
  (when (derived-mode-p 'LaTeX-mode)
    ;; 1. User path override wins even before AUCTeX has parsed.
    (or (my/latex-font--override-for-file (buffer-file-name))
        ;; Everything else needs AUCTeX's parse to be reliable.
        (when (bound-and-true-p TeX-active-styles)
          (or
           ;; 2. Package alist: last match wins (approximates last-loaded).
           (let (result)
             (dolist (entry (bound-and-true-p LaTeX-provided-package-options))
               (let ((key (cdr (assq (intern (car entry))
                                     my/latex-font-package-alist))))
                 (when key (setq result key))))
             result)
           ;; 3. NFSS `\renewcommand{\rmdefault}{...}' in preamble.
           (save-excursion
             (save-restriction
               (widen)
               (goto-char (point-min))
               (let ((end (or (and (boundp 'LaTeX-header-end)
                                   (save-excursion
                                     (re-search-forward LaTeX-header-end nil t)))
                              (min (point-max) 10000))))
                 (when (re-search-forward my/latex-font-rmdefault-regex end t)
                   (cdr (assoc (match-string 1) my/latex-font-nfss-code-alist))))))
           ;; 4. Default when parsed but no font info: Latin Modern.
           :family/lm-roman)))))

;;; --- Layer B: resolve intended-family → available family string ---------

(defvar my/latex-family-cache (make-hash-table :test 'eq)
  "Session cache: intended-family key → resolved family string (or `:none').")

(defun my/latex-font-forget-cache ()
  "Clear the intended-family → actual-family session cache.
Call this after installing new fonts and before restarting Emacs is
inconvenient."
  (interactive)
  (clrhash my/latex-family-cache))

(defun my/latex-resolve-family (intended)
  "Return the first available family name for INTENDED, or nil.
Nil on a TTY (no font backend) or when no candidate is installed."
  (when (display-graphic-p)
    (let ((cached (gethash intended my/latex-family-cache 'miss)))
      (cond
       ((eq cached :none) nil)
       ((not (eq cached 'miss)) cached)
       (t
        (let ((resolved
               (cl-loop for fam in (my/latex-font--all-candidates intended)
                        when (find-font (font-spec :family fam))
                        return fam)))
          (puthash intended (or resolved :none) my/latex-family-cache)
          resolved))))))

;;; --- Buffer face applier ------------------------------------------------

(defvar-local my/latex-face-remap-cookie nil
  "Cookie from `face-remap-add-relative' for the buffer's family remap.")

(defvar-local my/latex-current-family nil
  "The family string currently applied to this buffer via `my/latex-face-remap-cookie'.")

(defun my/latex-apply-family ()
  "Compute the desired family for this buffer and apply it if changed.
Preserves the global default face's `:height' — only `:family' is remapped."
  (when (and (derived-mode-p 'LaTeX-mode)
             (display-graphic-p))
    (let* ((intended (my/latex-detect-intended-family))
           (family   (and intended (my/latex-resolve-family intended))))
      (when (and family (not (equal family my/latex-current-family)))
        (when my/latex-face-remap-cookie
          (face-remap-remove-relative my/latex-face-remap-cookie))
        (setq my/latex-face-remap-cookie
              (face-remap-add-relative 'default :family family)
              my/latex-current-family family)
        ;; Character metrics shifted → existing preview overlays are now
        ;; slightly the wrong pixel size.  Clear them so C-c p p regenerates
        ;; at the correct DPI (mirrors the text-scale-mode-hook in init.el).
        (when (fboundp 'preview-clearout-buffer)
          (preview-clearout-buffer))))))

;;; --- Diagnostic command -------------------------------------------------

(defun my/latex-font-explain ()
  "Show why the current buffer's font is what it is."
  (interactive)
  (unless (derived-mode-p 'LaTeX-mode)
    (user-error "Not in LaTeX-mode"))
  (let* ((intended (my/latex-detect-intended-family))
         (candidates (and intended (my/latex-font--all-candidates intended)))
         (resolved (and intended (my/latex-resolve-family intended)))
         (path-override (my/latex-font--override-for-file (buffer-file-name)))
         (packages (bound-and-true-p LaTeX-provided-package-options))
         (matched-pkgs (cl-loop for (pkg . _) in packages
                                when (assq (intern pkg) my/latex-font-package-alist)
                                collect pkg)))
    (with-current-buffer (get-buffer-create "*LaTeX Font Sync*")
      (erase-buffer)
      (insert (format "Buffer:        %s\n" (buffer-name (other-buffer))))
      (insert (format "AUCTeX parsed: %s\n"
                      (if (bound-and-true-p TeX-active-styles) "yes" "NO (returning nil)")))
      (insert (format "Path override: %s\n" (or path-override "none")))
      (insert (format "Matched pkgs:  %s\n" (or matched-pkgs "none")))
      (insert (format "Intended key:  %s\n" (or intended "nil")))
      (insert (format "Candidates:    %s\n" (or candidates "n/a")))
      (insert (format "Resolved:      %s\n" (or resolved "nil (no candidate available)")))
      (insert (format "Currently on:  %s\n" (or my/latex-current-family "unchanged")))
      (display-buffer (current-buffer)))))

;;; --- Global minor mode --------------------------------------------------
;;
;; init.el turns this on for every session — see the `latex-font-sync-mode'
;; call there for rationale.  The bundled TTFs under `android-emacs/fonts/'
;; have been validated in-frame; if you add a new candidate to
;; `my/latex-font-candidate-alist' or drop a new TTF into `$HOME/fonts/',
;; test it first with `M-x my/latex-font-try-family' before shipping —
;; sfnt-android can hard-crash the app on a malformed TTF.

(defun my/latex-font-try-family (family)
  "Prompt for a FAMILY string and remap this buffer's :family to it.
Use this to test one candidate at a time on device before flipping
`latex-font-sync-mode' on globally."
  (interactive (list (completing-read
                      "Family: "
                      (delete-dups
                       (apply #'append (mapcar #'cdr my/latex-font-candidate-alist))))))
  (when my/latex-face-remap-cookie
    (face-remap-remove-relative my/latex-face-remap-cookie))
  (setq my/latex-face-remap-cookie
        (face-remap-add-relative 'default :family family)
        my/latex-current-family family)
  (message "Applied :family = %s" family))

;;;###autoload
(define-minor-mode latex-font-sync-mode
  "Global minor mode: sync each LaTeX buffer's :family to its document font.
When enabled, `my/latex-apply-family' runs on `LaTeX-mode-hook' and
`TeX-update-style-hook'.  Disabled by default because a bad TTF can
crash Android Emacs's font backend on face-remap."
  :global t
  :group 'latex-font-sync
  (if latex-font-sync-mode
      (progn
        (add-hook 'LaTeX-mode-hook       #'my/latex-apply-family)
        (add-hook 'TeX-update-style-hook #'my/latex-apply-family))
    (remove-hook 'LaTeX-mode-hook       #'my/latex-apply-family)
    (remove-hook 'TeX-update-style-hook #'my/latex-apply-family)))

(provide 'latex-font-sync)
;;; latex-font-sync.el ends here

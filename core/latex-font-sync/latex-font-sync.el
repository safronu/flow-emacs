;;; latex-font-sync.el --- Sync buffer face family to LaTeX document font -*- lexical-binding: t; -*-
;;
;; When a LaTeX document declares a text-font package (`mathpazo',
;; `times', etc.) or a raw NFSS override (`\renewcommand{\rmdefault}{ppl}'),
;; remap the buffer's default face family to the matching TrueType font
;; installed under $HOME/fonts/, together with a relative :height factor
;; that compensates the family's smaller x-height (see
;; `my/latex-font-optical-scale-alist').  Only affects the current
;; buffer; the global default face is untouched.
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
;; Fires on:
;;   * `LaTeX-mode-hook'      — first open of a .tex buffer;
;;   * `TeX-update-style-hook' — after AUCTeX re-parses styles (e.g. after
;;                              `C-c C-n' / `TeX-normal-mode', or the first
;;                              time styles finish loading);
;;   * `after-save-hook'       — installed buffer-locally when the mode is
;;                              on, so that adding `\usepackage{mathpazo}'
;;                              and saving the file re-selects the buffer
;;                              font.  `TeX-update-style-hook' does NOT run
;;                              on plain save (TeX-auto-write calls
;;                              `TeX-update-style' without FORCE, which is a
;;                              no-op once styles have been applied once).
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

(defconst my/latex-font-usepackage-regex
  "\\\\usepackage\\(?:\\[[^]]*\\]\\)?\\s-*{\\([^}]+\\)}"
  "Regex matching `\\usepackage[opts]{pkg1, pkg2, ...}'.")

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

(defconst my/latex-font-optical-scale-alist
  '((:family/lm-roman . 1.25)
    (:family/palatino . 1.10)
    (:family/times    . 1.18)
    (:family/bookman  . 1.06)
    (:family/newcent  . 1.08)
    (:family/chancery . 1.30))
  "Map intended-family key → :height multiplier for the buffer remap.
Serif document fonts draw their lowercase far smaller than the code
font at the same nominal size — Latin Modern's x-height is ~0.43 em,
JetBrains Mono's ~0.53 em — so a family swap alone makes .tex buffers
optically SHRINK and strain the eyes.  Each factor is roughly (code
font x-height) / (family x-height), bringing the document font's
lowercase up to the size the rest of the editor reads at.

Previews follow automatically: `flow-preview--base-dpi' measures the
buffer's effective (remapped) font, so the render resolution scales by
the same factor and formulas keep matching the text around them.")

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

(defun my/latex-font--preamble-end ()
  "Position where the preamble of the current buffer ends, for scanning."
  (or (and (boundp 'LaTeX-header-end)
           (save-excursion
             (goto-char (point-min))
             (re-search-forward LaTeX-header-end nil t)))
      (min (point-max) 10000)))

(defun my/latex-font--scan-preamble-packages ()
  "Scan THIS buffer's preamble for a known font package; key or nil.
Reads the buffer text, deliberately NOT AUCTeX's parse info: AUCTeX
keys parsed styles by bare base name in the GLOBAL `TeX-style-hook-list',
so two open documents that are both named e.g. test.tex share one
entry — the second one to load inherits the first one's package list
and is never re-parsed (`TeX-auto-apply' is skipped when a hook for
the name exists).  The buffer's own text is ground truth for what the
buffer should look like.  Last match wins, like LaTeX's last-loaded."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((end (my/latex-font--preamble-end))
            result)
        (while (re-search-forward my/latex-font-usepackage-regex end t)
          (dolist (pkg (split-string (match-string 1) "[, \t\n]+" t))
            (let ((key (cdr (assq (intern pkg) my/latex-font-package-alist))))
              (when key (setq result key)))))
        result))))

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
           ;; 2. This buffer's own preamble.  Trusted over AUCTeX's parse
           ;; info because that is keyed by bare base name globally and
           ;; poisoned by same-named documents (see the scan docstring).
           (my/latex-font--scan-preamble-packages)
           ;; 3. Package alist from AUCTeX's parse: last match wins
           ;; (approximates last-loaded).  Still needed for multi-file
           ;; documents whose preamble lives in the master file.
           (let (result)
             (dolist (entry (bound-and-true-p LaTeX-provided-package-options))
               (let ((key (cdr (assq (intern (car entry))
                                     my/latex-font-package-alist))))
                 (when key (setq result key))))
             result)
           ;; 4. NFSS `\renewcommand{\rmdefault}{...}' in preamble.
           (save-excursion
             (save-restriction
               (widen)
               (goto-char (point-min))
               (let ((end (my/latex-font--preamble-end)))
                 (when (re-search-forward my/latex-font-rmdefault-regex end t)
                   (cdr (assoc (match-string 1) my/latex-font-nfss-code-alist))))))
           ;; 5. Default when parsed but no font info: Latin Modern.
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

(defvar-local my/latex-font-sync-wanted nil
  "Non-nil when this buffer has opted into the document font.
Font sync is on-demand (the C-c p display keys, same contract as
folding/previews): buffers open in the default code font, and the
mode's open/style/save hooks apply the document font only in buffers
where `latex-font-sync-apply' has set this flag.")

(defun my/latex-apply-family ()
  "Compute the desired family for this buffer and apply it if changed.
No-op unless the buffer opted in via `latex-font-sync-apply'.
The global default face is untouched; the remap sets `:family' and a
RELATIVE `:height' multiplier from `my/latex-font-optical-scale-alist',
so the document font reads at the same optical size as the code font
(see that alist's docstring — previews track the change through the
effective-font DPI)."
  (when (and my/latex-font-sync-wanted
             (derived-mode-p 'LaTeX-mode)
             (display-graphic-p))
    (let* ((intended (my/latex-detect-intended-family))
           (family   (and intended (my/latex-resolve-family intended)))
           (scale    (* (or (cdr (assq intended my/latex-font-optical-scale-alist))
                            1.0)
                        (or (bound-and-true-p flow-font-sync-extra-scale) 1.0))))
      (when (and family (not (equal family my/latex-current-family)))
        (when my/latex-face-remap-cookie
          (face-remap-remove-relative my/latex-face-remap-cookie))
        (setq my/latex-face-remap-cookie
              (apply #'face-remap-add-relative 'default
                     :family family :height scale
                     ;; e-ink knob: these families' only sturdy cut.
                     (when (bound-and-true-p flow-font-sync-weight)
                       (list :weight flow-font-sync-weight)))
              my/latex-current-family family)
        ;; Character metrics shifted → existing preview overlays are now
        ;; slightly the wrong pixel size.  Clear them so C-c p p regenerates
        ;; at the correct DPI (mirrors the text-scale-mode-hook in init.el).
        (when (fboundp 'preview-clearout-buffer)
          (preview-clearout-buffer))))))

(defun latex-font-sync-apply ()
  "Opt this buffer into the document font and apply it now.
From here on the mode's style/save hooks keep it in sync (a preamble
edit + save re-selects the family).  Undone by `latex-font-sync-revert'."
  (interactive)
  (setq my/latex-font-sync-wanted t)
  (my/latex-apply-family))

(defun latex-font-sync-revert ()
  "Restore the default (code) font and opt this buffer out of syncing.
Removes the family remap; stale preview overlays are cleared because
their pixel size was computed against the document font's metrics."
  (interactive)
  (setq my/latex-font-sync-wanted nil)
  (when my/latex-face-remap-cookie
    (face-remap-remove-relative my/latex-face-remap-cookie)
    (setq my/latex-face-remap-cookie nil
          my/latex-current-family nil)
    (when (fboundp 'preview-clearout-buffer)
      (preview-clearout-buffer))))

;;; --- Diagnostic command -------------------------------------------------

(defun my/latex-font-explain ()
  "Show why the current buffer's font is what it is."
  (interactive)
  (unless (derived-mode-p 'LaTeX-mode)
    (user-error "Not in LaTeX-mode"))
  (let* ((src-buffer-name (buffer-name))
         (intended (my/latex-detect-intended-family))
         (candidates (and intended (my/latex-font--all-candidates intended)))
         (resolved (and intended (my/latex-resolve-family intended)))
         (path-override (my/latex-font--override-for-file (buffer-file-name)))
         (packages (bound-and-true-p LaTeX-provided-package-options))
         (matched-pkgs (cl-loop for (pkg . _) in packages
                                when (assq (intern pkg) my/latex-font-package-alist)
                                collect pkg)))
    (with-current-buffer (get-buffer-create "*LaTeX Font Sync*")
      (erase-buffer)
      (insert (format "Buffer:        %s\n" src-buffer-name))
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
Use this to test one candidate at a time on device — e.g. comparing
the bundled weight grades (Ink / Demi / regular) live.

Completion offers every family the display actually has
(`font-family-list'), plus all configured candidates (user overrides
included); free typing is allowed for names not yet installed.

The remap keeps the same :height factor `my/latex-apply-family' would
use (optical scale x `flow-font-sync-extra-scale'), so grades are
compared at identical size — a bare :family swap would also silently
shrink the text back to code-font proportions."
  (interactive
   (list (completing-read
          "Family: "
          (delete-dups
           (append
            (apply #'append (mapcar #'cdr my/latex-font-user-candidates))
            (apply #'append (mapcar #'cdr my/latex-font-candidate-alist))
            (and (display-graphic-p) (font-family-list)))))))
  (let* ((intended (my/latex-detect-intended-family))
         (scale (* (or (cdr (assq intended my/latex-font-optical-scale-alist))
                       1.0)
                   (or (bound-and-true-p flow-font-sync-extra-scale) 1.0)))
         ;; Guard against the completion UI handing back a mangled family
         ;; (e.g. spaces silently replaced with underscores).  A remap to a
         ;; family the font backend doesn't know cascades all the way to a
         ;; system fallback whose cmap misses Latin, so every char draws as
         ;; a glyphless-char box — visually white parallelograms all over
         ;; the buffer.  find-font, not string membership: font-family-list
         ;; is expensive on Android and the spec matcher is what a real
         ;; face-remap would use anyway.
         (found (and (display-graphic-p)
                     (find-font (font-spec :family family)))))
    (unless (or (not (display-graphic-p)) found)
      (user-error "No font matches family %S — refusing to remap (would fall back to a system font and render as glyphless boxes)"
                  family))
    (when my/latex-face-remap-cookie
      (face-remap-remove-relative my/latex-face-remap-cookie))
    (setq my/latex-face-remap-cookie
          (face-remap-add-relative 'default :family family :height scale)
          my/latex-current-family family)
    (message "Applied :family = %s (:height x%.2f)" family scale)))

(defun my/latex-font-sync--install-save-hook ()
  "Add `my/latex-apply-family' to buffer-local `after-save-hook'.
Ensures adding a font package (e.g. `\\usepackage{mathpazo}') and saving
re-selects the buffer font, since `TeX-update-style-hook' is a no-op on
save once styles have been applied."
  (add-hook 'after-save-hook #'my/latex-apply-family nil t))

(defun my/latex-font-sync--uninstall-save-hook ()
  "Remove `my/latex-apply-family' from buffer-local `after-save-hook'."
  (remove-hook 'after-save-hook #'my/latex-apply-family t))

;;;###autoload
(define-minor-mode latex-font-sync-mode
  "Global minor mode: sync a LaTeX buffer's :family to its document font.
When enabled, `my/latex-apply-family' runs on `LaTeX-mode-hook',
`TeX-update-style-hook', and (buffer-locally in every LaTeX buffer)
`after-save-hook' — but applies only in buffers that opted in via
`latex-font-sync-apply' (the C-c p b display key); everything else
stays in the default code font (`latex-font-sync-revert' / C-c p c
returns to it).  Enabled from init.el; a bad TTF can crash Android
Emacs's font backend on face-remap, so all bundled candidates must be
validated in-frame before shipping."
  :global t
  :group 'latex-font-sync
  (if latex-font-sync-mode
      (progn
        (add-hook 'LaTeX-mode-hook       #'my/latex-apply-family)
        (add-hook 'TeX-update-style-hook #'my/latex-apply-family)
        (add-hook 'LaTeX-mode-hook       #'my/latex-font-sync--install-save-hook)
        ;; Retro-install the save hook in any already-open LaTeX buffers.
        (dolist (buf (buffer-list))
          (with-current-buffer buf
            (when (derived-mode-p 'LaTeX-mode)
              (my/latex-font-sync--install-save-hook)))))
    (remove-hook 'LaTeX-mode-hook       #'my/latex-apply-family)
    (remove-hook 'TeX-update-style-hook #'my/latex-apply-family)
    (remove-hook 'LaTeX-mode-hook       #'my/latex-font-sync--install-save-hook)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (derived-mode-p 'LaTeX-mode)
          (my/latex-font-sync--uninstall-save-hook))))))

(provide 'latex-font-sync)
;;; latex-font-sync.el ends here

;;; early-init.el -*- lexical-binding: t; -*-
;; Termux binaries + TeX Live must be visible before any package loads a
;; command in a subprocess (AUCTeX resolves programs at load time in some
;; code paths).  `android-use-exec-loader nil' lets self-contained ELF
;; binaries under $PREFIX exec each other without going through Android's
;; app_process shim.
(let ((dirs '("/data/data/com.termux/files/usr/bin"
              "/data/data/com.termux/files/usr/bin/texlive")))
  (dolist (d dirs) (push d exec-path))
  (setenv "PATH" (concat (mapconcat #'identity dirs ":")
                         ":" (or (getenv "PATH") ""))))
(setq android-use-exec-loader nil)

;; GNU ELPA rotates its signing key periodically.  If Emacs doesn't ship the
;; current key, signature checks fail on `package-refresh-contents' and no
;; packages install.  Turning verification off here lets `package.el' pull
;; `gnu-elpa-keyring-update' on first run; that package installs the new key
;; so verification can be re-enabled later if you want.
(setq package-check-signature nil)

;; `package-quickstart' only takes effect if set BEFORE package initialization
;; (which Emacs ≥27 runs automatically between early-init.el and init.el).
(setq package-quickstart t)

;; Termux's pdflatex was compiled with a hardcoded TEXMFROOT of `2026.0'
;; while the actual install lives at `2026'.  A login shell fixes this by
;; sourcing /etc/profile.d/texlive.sh; Android Emacs doesn't, so we reproduce
;; the important exports here.  Without this, `kpsewhich' looks for tlpkg,
;; format files, and mktexlsr.pl in the wrong dir → "I can't find pdflatex.fmt".
(setenv "TEXMFROOT"  "/data/data/com.termux/files/usr/share/texlive/2026")
(setenv "TEXMFLOCAL" "/data/data/com.termux/files/usr/share/texlive/texmf-local")
(setenv "OSFONTDIR"  "/data/data/com.termux/files/usr/share/fonts/TTF")

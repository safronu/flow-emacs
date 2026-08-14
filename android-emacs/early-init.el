;;; early-init.el -*- lexical-binding: t; -*-
;; Termux binaries + TeX Live must be visible before any package loads a
;; command in a subprocess (AUCTeX resolves programs at load time in some
;; code paths).  `android-use-exec-loader nil' lets self-contained ELF
;; binaries under $PREFIX exec each other without going through Android's
;; app_process shim.
;;
;; This only works because Emacs shares its Android UID with the
;; SourceForge-signed Termux, which is a targetSdk-28 app — SELinux puts
;; that app's process in the `untrusted_app_27' domain, which retains the
;; `execmod'/`execute_no_trans' permissions on files under an app's
;; private data dir.  A modern (targetSdk >= 29) app process runs in
;; `untrusted_app_29+' and Android's SELinux policy DENIES exec of those
;; files there, so the direct-exec shortcut fails with EACCES / "Permission
;; denied".  If Termux (or Emacs) is ever updated to a newer targetSdk and
;; subprocess calls start failing with "Permission denied", set this back
;; to `t' (the default) so Emacs routes exec through the app_process
;; loader again.
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

;; No tool-bar (the icon button strip) or menu-bar (the File/Edit/…
;; text row) at the top.  Setting the frame parameters in
;; `default-frame-alist' here means the bars are never drawn on any
;; frame — no startup flash, unlike `(tool-bar-mode -1)' in init.
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(menu-bar-lines . 0) default-frame-alist)

;; Termux's pdflatex was compiled with a hardcoded TEXMFROOT of `2026.0'
;; while the actual install lives at `2026'.  A login shell fixes this by
;; sourcing /etc/profile.d/texlive.sh; Android Emacs doesn't, so we reproduce
;; the important exports here.  Without this, `kpsewhich' looks for tlpkg,
;; format files, and mktexlsr.pl in the wrong dir → "I can't find pdflatex.fmt".
(setenv "TEXMFROOT"  "/data/data/com.termux/files/usr/share/texlive/2026")
(setenv "TEXMFLOCAL" "/data/data/com.termux/files/usr/share/texlive/texmf-local")
(setenv "OSFONTDIR"  "/data/data/com.termux/files/usr/share/fonts/TTF")

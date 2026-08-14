;;; early-init.el --- laptop profile -*- lexical-binding: t; -*-

;; GNU ELPA rotates its signing key periodically and a given Emacs often
;; ships an older one, which makes signature checks fail on the very
;; first `package-refresh-contents'.  nil here lets the first run pull
;; `gnu-elpa-keyring-update'; flow-core re-enables verification once that
;; key is in place.
(setq package-check-signature nil)

;; `package-quickstart' only takes effect if set BEFORE package
;; initialization, which Emacs >= 27 runs automatically between
;; early-init.el and init.el.
(setq package-quickstart t)

;; No tool-bar (the icon button strip) or menu-bar (the File/Edit/…
;; text row) at the top.  Setting the frame parameters in
;; `default-frame-alist' here means the bars are never drawn on any
;; frame — no startup flash, unlike `(tool-bar-mode -1)' in init.
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(menu-bar-lines . 0) default-frame-alist)

;;; flow-deadlines.el --- load the private deadlines setup, if present -*- lexical-binding: t; -*-
;;
;; The `deadlines' repository is NOT vendored here and must not be: it
;; lists customers and what is owed to them, while this repo is meant to
;; be publishable.  What lives here is only the wiring — where the
;; checkout is on this device, and which HOME its git subprocesses need.
;;
;; If the checkout is missing (a device that doesn't track deadlines, or
;; one where it hasn't been cloned yet), this is a silent no-op: no error,
;; no message, no C-c d prefix.  That is the point of the guard — a
;; missing private repo must never break the editor.
;;
;; Set `flow-deadlines-repo' in the profile before loading this module:
;;
;;   (setq flow-deadlines-repo "~/flow/deadlines")
;;
;; With it loaded, C-c d d/D/c/f/l/s are the deadline agenda, capture,
;; lint and git-sync commands; see the deadlines repo's own README.

;;; Code:

(defun flow-deadlines-load ()
  "Load deadlines.el from `flow-deadlines-repo' when that checkout exists.
Return the loaded file's path, or nil when there is nothing to load."
  (when flow-deadlines-repo
    (let* ((repo (expand-file-name flow-deadlines-repo))
           (file (expand-file-name "emacs/deadlines.el" repo)))
      (when (file-readable-p file)
        ;; Both variables are `defcustom's over in deadlines.el, and
        ;; `custom-declare-variable' only assigns when the symbol is still
        ;; unbound — so setting them HERE, before the load, wins, and the
        ;; agenda/capture entries that bake the path in at load time get
        ;; the right one.
        (setq deadlines-repo      repo
              deadlines-git-home  flow-deadlines-git-home)
        (load file nil 'nomessage)
        file))))

(flow-deadlines-load)

(provide 'flow-deadlines)
;;; flow-deadlines.el ends here

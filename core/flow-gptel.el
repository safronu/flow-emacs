;;; flow-gptel.el --- LLM chat: gptel with the Claude Code CLI backend -*- lexical-binding: t; -*-
;;
;; gptel (MELPA) provides the chat UI; the model behind it is the local
;; `claude' CLI in headless mode, via our own backend library in
;; `core/gptel-claude-code/' (gptel-claude-code.el + tests + docs).
;; No API keys anywhere: the CLI's own subscription login is the auth.
;; On a machine without the `claude' executable the module still loads;
;; a request just fails with a clear "cannot find executable" error.
;;
;; Two backends are registered:
;;   "Claude-Code"  (default) — plain chat: no agentic tools, runs in a
;;                  scratch directory, behaves like a normal LLM chat.
;;   "Claude-Agent" — Claude Code's real tools in read-only mode
;;                  (--permission-mode plan), working directory = the
;;                  request buffer's directory.  Pick it from the gptel
;;                  menu (C-c g m) per buffer when wanted.
;;
;; Keys (global, prefix C-c g):
;;   g  open/switch to a chat buffer    s  send region / buffer-to-point
;;   m  gptel menu (model, backend, …)  r  rewrite region
;;   a  add region/buffer to context    f  add file to context
;;   k  abort the request in this buffer
;; Inside a chat buffer, C-c RET also sends (gptel-mode's binding).
;;
;; Non-obvious constraints (details in gptel-claude-code.el's Commentary):
;; - Streaming needs `gptel-use-curl' non-nil (the default) even though
;;   no curl process ever runs — gptel's streaming gate consults it.
;; - The backend hooks gptel's transport via advice on
;;   `gptel-curl-get-response' / `gptel--url-get-response' and reuses
;;   several internal contracts.  Verified against gptel-20260703; after
;;   upgrading the gptel package, run the tests in
;;   `core/gptel-claude-code/' (command in the tests' Commentary)
;;   before trusting it.

;;; Code:

;; Loaded by the time a rewrite completes (the request comes from it).
(declare-function gptel--rewrite-update-status "gptel-rewrite")

;; Point the CLI at its login when Emacs's HOME isn't the one that holds
;; it (Android: the app's private dir, vs Termux's ~/.claude).  Verified
;; on the Boox 2026-08-14: with a foreign HOME the CLI runs but every
;; request returns "Not logged in - Please run /login"; with
;; CLAUDE_CONFIG_DIR set it authenticates normally.  A global `setenv' is
;; safe here — no other program reads this variable — and the CLI is
;; started with `make-process', which inherits `process-environment'.
(when flow-claude-config-dir
  (setenv "CLAUDE_CONFIG_DIR" (expand-file-name flow-claude-config-dir)))

(use-package gptel
  ;; The package's own autoloads cover the entry commands; :config runs
  ;; on first use, so startup pays nothing.
  :defer t
  :init
  (autoload 'gptel-abort "gptel" nil t) ;no autoload cookie upstream
  (define-prefix-command 'flow-gptel-map)
  (keymap-global-set "C-c g" 'flow-gptel-map)
  (keymap-set flow-gptel-map "g" #'gptel)
  (keymap-set flow-gptel-map "s" #'gptel-send)
  (keymap-set flow-gptel-map "m" #'gptel-menu)
  (keymap-set flow-gptel-map "r" #'gptel-rewrite)
  (keymap-set flow-gptel-map "a" #'gptel-add)
  (keymap-set flow-gptel-map "f" #'gptel-add-file)
  (keymap-set flow-gptel-map "k" #'gptel-abort)
  :config
  (flow-load "gptel-claude-code/gptel-claude-code")
  (setq-default gptel-backend (gptel-make-claude-code "Claude-Code")
                gptel-model 'sonnet)
  (gptel-make-claude-code "Claude-Agent"
    :cli-tools "default"
    :permission-mode "plan"
    :allowed-tools '("Read" "Grep" "Glob"
                     "Bash(git diff *)" "Bash(git log *)" "Bash(git status)")
    :working-dir 'buffer
    :timeout 600)
  ;; When a rewrite (C-c g r) finishes, advertise the action keys in
  ;; the overlay's REWRITE title.  gptel's default is to wait silently
  ;; for RET/mouse-1 on the overlay, with only a one-shot echo message,
  ;; eldoc and mouse hover as hints — all three invisible in practice
  ;; on the e-ink tablet, where a finished rewrite just read as "stuck
  ;; at REWRITE Ready".  Deliberately NOT the modal chooser (symbol
  ;; `dispatch' / `gptel--rewrite-dispatch'): `read-multiple-choice'
  ;; grabs all input until answered — can't even switch windows — and
  ;; the keys it advertises already exist non-modally on the overlay's
  ;; own keymap (user feedback, 2026-08-15).  Constraint verified
  ;; against gptel-20260813.2132: the value must be a NAMED function
  ;; symbol — the rewrite callback calls `symbol-name' on it before
  ;; funcalling, so a lambda errors.
  (setq gptel-rewrite-default-action #'flow-gptel--rewrite-advertise-on-ready))

(defun flow-gptel--rewrite-advertise-on-ready (ov)
  "Show the rewrite action keys in OV's title, without stealing input.
The keys live on the overlay's keymap, so they apply with point
inside the rewritten region; RET there opens the full chooser."
  (gptel--rewrite-update-status
   ov (concat " Ready · "
              (mapconcat (pcase-lambda (`(,key . ,action))
                           (concat (propertize key 'face 'help-key-binding)
                                   " " action))
                         '(("C-c r a" . "accept") ("C-c r k" . "reject")
                           ("C-c r r" . "iterate") ("RET" . "more"))
                         " · "))))

;; Rebind the rewrite action keys.  The overlay's keymap outranks the
;; major mode whenever point is inside a pending rewrite, and gptel's
;; stock keys there (C-c C-a/C-c C-r/C-c C-k/C-c C-d/C-c C-e/C-c C-n/
;; C-c C-p/C-c C-m) shadow AUCTeX's core commands — compile-all,
;; compile-region, kill-job, insert-environment, insert-macro, and the
;; C-c C-p preview prefix.  Worst case, a muscle-memory C-c C-a
;; ("compile") silently ACCEPTS the rewrite.  Move the actions to the
;; user-reserved `C-c r' prefix (mnemonic: rewrite, matching C-c g r;
;; unused by AUCTeX, RefTeX, cdlatex or flow's other prefixes), so TeX
;; keys fall through to the major mode again.  RET/mouse-1 (the action
;; chooser) stay.  The eldoc hint and the transient menu pick up the
;; new bindings automatically via `substitute-command-keys'.
(with-eval-after-load 'gptel-rewrite
  (dolist (key '("C-c C-a" "C-c C-r" "C-c C-k" "C-c C-d"
                 "C-c C-e" "C-c C-n" "C-c C-p" "C-c C-m"))
    (keymap-unset gptel-rewrite-actions-map key 'remove))
  (pcase-dolist (`(,key . ,cmd)
                 '(("a" . gptel--rewrite-accept)
                   ("k" . gptel--rewrite-reject)
                   ("r" . gptel--rewrite-iterate)
                   ("m" . gptel--rewrite-merge)
                   ("d" . gptel--rewrite-diff)
                   ("e" . gptel--rewrite-ediff)
                   ("n" . gptel--rewrite-next)
                   ("p" . gptel--rewrite-previous)))
    (keymap-set gptel-rewrite-actions-map (concat "C-c r " key) cmd)))

(provide 'flow-gptel)
;;; flow-gptel.el ends here

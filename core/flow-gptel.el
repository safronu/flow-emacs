;;; flow-gptel.el --- LLM chat: gptel with the Claude Code CLI backend -*- lexical-binding: t; -*-
;;
;; gptel (MELPA) provides the chat UI; the model behind it is the local
;; `claude' CLI in headless mode, via `core/gptel-claude-code.el' — our
;; own backend library, kept in this repo like `latex-font-sync.el'.
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
;;   upgrading the gptel package, run `core/gptel-claude-code-tests.el'
;;   (command in its Commentary) before trusting it.

;;; Code:

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
  (flow-load "gptel-claude-code")
  (setq-default gptel-backend (gptel-make-claude-code "Claude-Code")
                gptel-model 'sonnet)
  (gptel-make-claude-code "Claude-Agent"
    :cli-tools "default"
    :permission-mode "plan"
    :allowed-tools '("Read" "Grep" "Glob"
                     "Bash(git diff *)" "Bash(git log *)" "Bash(git status)")
    :working-dir 'buffer
    :timeout 600))

(provide 'flow-gptel)
;;; flow-gptel.el ends here

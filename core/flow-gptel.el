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
;;   m  gptel menu (model, backend, …)  r  rewrite region (or current line)
;; M-r (global) = the same rewrite, one chord; shadows the unused
;; `move-to-window-line-top-bottom' outside minibuffer/isearch.
;;   a  add region/buffer to context    f  add file to context
;;   k  abort the request in this buffer
;; Inside a chat buffer, C-c RET also sends (gptel-mode's binding).
;;
;; Reusable prompts live in core/prompts/ (one NAME.txt per prompt):
;; each is a named directive in the gptel menu, and rewrite-latex.txt
;; is the system message for C-c g r in TeX buffers.  Files are read
;; per request — edit and the next request uses the new text.
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
(defvar gptel-directives)               ;defined by gptel, required before use

;; Reusable prompt library: one plain-text file per prompt in
;; core/prompts/, read straight from the repo like core/snippets/.
;; Contents are read at REQUEST time, so editing a file changes the
;; very next request — no reload, no re-eval.  Each file also becomes
;; a named directive in `gptel-menu' (registered on first gptel use);
;; ADDING or removing a file needs `M-x flow-gptel-reload-prompts' (or
;; a restart) for the menu entry, content edits do not.

(defconst flow-gptel-prompts-directory (flow-core-file "prompts")
  "Directory of reusable prompts, one plain-text NAME.txt per prompt.")

(defun flow-gptel-prompt (name)
  "Return the prompt stored as NAME.txt in `flow-gptel-prompts-directory'.
Reads the file on every call, so edits apply to the next request.
Returns nil if the file is missing or unreadable."
  (let ((file (expand-file-name (concat name ".txt")
                                flow-gptel-prompts-directory)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (string-trim (buffer-string))))))

(defun flow-gptel-reload-prompts ()
  "Register every core/prompts/*.txt as a named entry in `gptel-directives'.
Each entry is a closure calling `flow-gptel-prompt', so the menu
name is stable while the file contents stay live-editable."
  (interactive)
  (require 'gptel)                     ;defines `gptel-directives'
  (dolist (file (directory-files flow-gptel-prompts-directory nil "\\.txt\\'"))
    (let ((name (file-name-base file)))
      (setf (alist-get (intern name) gptel-directives)
            (lambda () (flow-gptel-prompt name))))))

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
  (keymap-set flow-gptel-map "r" #'flow-gptel-rewrite-dwim)
  ;; Short chord for the frequent rewrite flow (user request 2026-08-17).
  ;; This SHADOWS `move-to-window-line-top-bottom' (core Emacs, unused
  ;; here) in normal buffers only: the minibuffer's M-r history search
  ;; and isearch's M-r regexp toggle live in local keymaps, which
  ;; outrank the global map.  C-c g r remains as the mnemonic form.
  (keymap-global-set "M-r" #'flow-gptel-rewrite-dwim)
  (keymap-set flow-gptel-map "a" #'gptel-add)
  (keymap-set flow-gptel-map "f" #'gptel-add-file)
  (keymap-set flow-gptel-map "k" #'gptel-abort)
  :config
  (flow-load "gptel-claude-code/gptel-claude-code")
  (flow-gptel-reload-prompts)
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

;; `gptel-rewrite' hard-errors without an active region (the final
;; branch of its interactive spec).  The frequent flow here is: type a
;; short description ("Euler's formula") where the math should go, then
;; have it rewritten into real LaTeX — and manually re-selecting the
;; text just typed (C-SPC, move point back) was the friction.  The
;; fallback unit is the CURRENT LINE: tested 2026-08-17 against
;; expand-region, expreg and thing-at-point in AUCTeX buffers, the line
;; is the only candidate that selects exactly the typed phrase with
;; zero extra keys in the common case (phrase on its own line), and the
;; rule "no region = this line" is trivially predictable.  Sentence
;; detection drags in preceding markup (`\begin{document}' etc.), and
;; expreg has no tree-sitter grammar for LaTeX so it can only offer
;; word -> paragraph.  For a phrase typed mid-line, select it manually
;; (C-= from flow-core grows the region from point) — or set the mark
;; before typing and C-x C-x afterwards.
(defun flow-gptel-rewrite-dwim ()
  "Start `gptel-rewrite' on the region, else on the current line.
With no active region, select this line's text (sans surrounding
whitespace) first, so the rewrite replaces exactly it.  With
rewrite overlays pending and no region, fall through untouched so
the key still opens gptel's rewrite-actions menu."
  (interactive)
  (unless (or (use-region-p) (bound-and-true-p gptel--rewrite-overlays))
    (let ((beg (save-excursion (back-to-indentation) (point)))
          (end (save-excursion
                 (end-of-line) (skip-chars-backward " \t") (point))))
      (when (>= beg end)
        (user-error "Current line is empty — nothing to rewrite"))
      (goto-char end)
      (push-mark beg t t)))
  (call-interactively #'gptel-rewrite))

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

;; TeX-specific rewrite directive, from core/prompts/rewrite-latex.txt.
;; `gptel-rewrite-directives-hook' runs its functions in the buffer
;; being rewritten until one returns non-nil; that string REPLACES the
;; entire default rewrite system message, so the prompt file must
;; restate the "ONLY the replacement text, no fences" guardrail itself.
;; Returns nil outside TeX buffers — and when the file is missing — so
;; every other mode keeps gptel's stock mode-aware directive.  AUCTeX
;; 14's LaTeX-mode derives from TeX-mode and the built-in latex-mode
;; from tex-mode, so the two parents cover both stacks.  The add-hook
;; runs before gptel-rewrite's defcustom loads; that is the standard
;; safe pattern (custom-declare-variable keeps an existing value).
(defun flow-gptel--rewrite-directive-tex ()
  "Rewrite directive for TeX buffers, read from prompts/rewrite-latex.txt."
  (when (derived-mode-p 'TeX-mode 'tex-mode)
    (flow-gptel-prompt "rewrite-latex")))

(add-hook 'gptel-rewrite-directives-hook #'flow-gptel--rewrite-directive-tex)

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

;;; flow-agent-shell.el --- agentic coding: agent-shell driving Claude Code -*- lexical-binding: t; -*-
;;
;; agent-shell (MELPA; pulls in acp.el and shell-maker) is a shell-maker
;; buffer that talks to coding agents over the Agent Client Protocol.
;; This is the other half of the LLM story from `flow-gptel': gptel is
;; CHAT (at most read-only tools), agent-shell is the full agentic loop —
;; the agent edits files and runs commands, with per-action permission
;; prompts and diff review inside Emacs.
;;
;; The agent process is NOT the `claude' binary: acp.el spawns the
;; `claude-agent-acp' adapter (an npm package wrapping the Claude Agent
;; SDK, Node >= 22), which speaks ACP on stdio and runs Claude Code
;; underneath.  On the laptop, `~/.local/bin/claude-agent-acp' is a
;; wrapper script pinning nvm's Node v22.14.0 — the nvm default (v16)
;; cannot run it, so a bare `npm install -g` binary on PATH would fail.
;; Auth is the CLI's subscription login (no API keys anywhere, same as
;; flow-gptel); if requests fail with a login error, run `claude' once
;; in a terminal and /login.
;;
;; Keys (global, prefix C-c a):
;;   a  start a Claude Code agent shell (rooted at the current project)
;;   d  start one in a directory chosen explicitly
;;
;; One-chord access: M-n (global) runs the dwim `agent-shell' — jump to
;; the current project's shell, create one if there is none, and from
;; inside a shell toggle back to the previous buffer.  M-n is the
;; companion of M-p (flow-latex-doc-mode): the 2026-08-17 enumeration
;; found them the ONLY modifier-letter chords unbound in a .tex buffer
;; with the full stack, and vanilla Emacs leaves both unbound globally.
;; M-s was considered and rejected — it is Emacs's search prefix
;; everywhere (M-s o occur, M-s . symbol isearch, the highlight
;; family).  Known shadows, deliberate: markdown buffers keep their own
;; M-n (markdown-next-link), and comint-derived buffers — the agent
;; shell itself included — keep M-n as comint-next-input, so walking
;; back down after M-p history never breaks; the return trip from a
;; shell is M-o (ace-window), the config's window key.
;;
;; agent-shell is a NEW package for this config: on a machine whose elpa
;; archive cache predates it, the `use-package' ensure fails at startup
;; with "package unavailable" — run `M-x package-refresh-contents' once
;; and restart (never add an automatic refresh; see flow-core).
;;
;; On the tablet (wired 2026-08-18): same module, different plumbing per
;; profile.  The android profile points `flow-claude-acp-command' at
;; bin/claude-agent-acp — a Termux-side wrapper that runs the adapter
;; under Termux's node and exports CLAUDE_CODE_EXECUTABLE to the patched
;; glibc `claude' (the SDK's own CLI resolution can never succeed there:
;; Termux node reports platform "android", so npm skips every
;; platform-specific CLI dep) — and sets `flow-claude-config-dir' so the
;; CLI finds Termux's ~/.claude login, exactly as for flow-gptel.

;;; Code:

;; Same knob, same reason as in flow-gptel (see the comment there): the
;; adapter's Claude reads CLAUDE_CONFIG_DIR when Emacs's HOME isn't the
;; one holding the CLI login.  Guarded setenv, idempotent across the two
;; modules — whichever loads first sets it.
(when flow-claude-config-dir
  (setenv "CLAUDE_CONFIG_DIR" (expand-file-name flow-claude-config-dir)))

;; Marks the variable special even if this file is ever byte-compiled
;; before agent-shell has loaded, so the `let' below binds dynamically.
(defvar agent-shell-cwd-function)

(defvar-local flow-agent-shell--directory nil
  "Directory this agent shell is pinned to, or nil for project detection.
Buffer-local in the shell buffer; read by the global
`agent-shell-cwd-function' installed in this module's `:config'.")

(defun flow-agent-shell-in-directory (dir)
  "Start a Claude Code agent shell rooted at DIR.
Bypasses `agent-shell-cwd''s project detection, which always climbs to
the git root — this is the way to scope the agent to a subfolder of a
repo, or to any directory regardless of what buffer is current.  The
session's cwd decides which CLAUDE.md, .claude/ skills and settings
the agent loads, exactly like running `claude' from that directory in
a terminal.

A dynamic `let' of `agent-shell-cwd-function' alone is NOT enough:
only the buffer name and the buffer's `default-directory' are
computed inside this call.  The ACP session/new request that actually
carries the cwd is sent from the initialize-response callback, after
the `let' has exited — at which point project detection climbed back
to the git root (verified on-device 2026-08-18: buffer in core/, CLI
spawned at the repo root).  So DIR is also pinned buffer-locally in
the new shell buffer, where the module's global
`agent-shell-cwd-function' picks it up at callback time."
  (interactive "DAgent shell in: ")
  ;; Load now, not via the autoload inside the `let': the defcustom must
  ;; exist before the `let' is evaluated for the binding to be dynamic.
  (require 'agent-shell)
  (let* ((dir (expand-file-name dir))
         (default-directory dir)
         (existing (buffer-list))
         (agent-shell-cwd-function (lambda () dir)))
    (agent-shell-anthropic-start-claude-code)
    (dolist (buffer (buffer-list))
      (unless (memq buffer existing)
        (with-current-buffer buffer
          (when (derived-mode-p 'agent-shell-mode)
            (setq-local flow-agent-shell--directory dir)))))))

(declare-function agent-shell--completion-bounds "agent-shell-completion")
(declare-function agent-shell-completion--source-buffer "agent-shell-completion")

(defun flow-agent-shell--file-exit-function (string _status)
  "Insert a space after completed STRING unless it is a directory.
Upstream's exit function adds the space unconditionally; a directory
must stay open-ended so the path can keep being drilled down."
  (unless (string-suffix-p "/" string)
    (insert " ")))

(defun flow-agent-shell--project-files-or-filesystem (orig-fn)
  "Around-advice on `agent-shell--file-completion-at-point': ORIG-FN,
falling back to plain filesystem completion when it has no candidates.

Upstream @ completion offers ONLY the project file list (projectile or
project.el).  A shell rooted outside any project — e.g. `M-n' from a
non-project buffer lands the shell in HOME — gets an EMPTY list, so
typing @ triggers completion and silently shows nothing (diagnosed on
the live tablet 2026-08-19).  Here: same @-bounds as upstream, but the
collection is `completion-file-name-table' resolved against the
shell's `default-directory', so paths complete component by component
(directories end in a slash and take no trailing space).  Inert inside
a project: whenever ORIG-FN has candidates they are returned untouched."
  (let ((result (funcall orig-fn)))
    (if (nth 2 result)
        result
      (when-let* ((bounds (agent-shell--completion-bounds "[:alnum:]/_.-" ?@)))
        ;; Resolve against the SHELL's cwd even from the minibuffer
        ;; (agent-shell-send-* prompts), whose own default-directory is
        ;; whatever buffer the command was invoked from.
        (let ((dir (buffer-local-value
                    'default-directory
                    (or (and (fboundp 'agent-shell-completion--source-buffer)
                             (agent-shell-completion--source-buffer))
                        (current-buffer)))))
          (list (alist-get :start bounds) (alist-get :end bounds)
                (lambda (string pred action)
                  (let ((default-directory dir))
                    (completion-file-name-table string pred action)))
                :exclusive 'no
                :company-kind (lambda (f)
                                (if (string-suffix-p "/" f) 'folder 'file))
                :exit-function #'flow-agent-shell--file-exit-function))))))

(use-package agent-shell
  ;; :defer keeps startup free: nothing loads until the key is hit.
  :defer t
  :init
  ;; The entry command lives in agent-shell-anthropic.el inside the
  ;; package; the explicit autoload keeps the binding working even if
  ;; the package's own autoloads miss it.
  (autoload 'agent-shell-anthropic-start-claude-code "agent-shell-anthropic" nil t)
  (autoload 'agent-shell "agent-shell" nil t)
  (define-prefix-command 'flow-agent-shell-map)
  (keymap-global-set "C-c a" 'flow-agent-shell-map)
  (keymap-set flow-agent-shell-map "a" #'agent-shell-anthropic-start-claude-code)
  (keymap-set flow-agent-shell-map "d" #'flow-agent-shell-in-directory)
  ;; See the header comment for why M-n and not M-s, and the shadows.
  (keymap-global-set "M-n" #'agent-shell)
  :config
  ;; No ASCII-art banner: it eats most of a half-screen window and
  ;; scrolls the actually useful first response out of view.
  (setq agent-shell-show-welcome-message nil)
  ;; The banner has a SECOND half: on graphical frames the default
  ;; header style is a multi-row SVG (icon block + key-hints row) that
  ;; stays glued to the top of the buffer.  `text' is the one-line
  ;; version with the same name/status content.
  (setq agent-shell-header-style 'text)
  ;; @file / directory references and /command completion in the prompt:
  ;; agent-shell auto-enables `agent-shell-completion-mode' in each new
  ;; shell when this is non-nil.  It is upstream's default (verified in
  ;; 20260817.1240 on the tablet), pinned here explicitly so completion
  ;; stays on in every profile even if the upstream default ever flips.
  ;; On an agent-shell old enough to lack agent-shell-completion.el the
  ;; setq is inert (nothing reads it) — upgrade the package there.
  (setq agent-shell-file-completion-enabled t)
  ;; Filesystem fallback for @ outside projects — see the advice's
  ;; docstring.  fboundp-guarded: an agent-shell old enough to lack the
  ;; completion module has nothing to advise (upgrade the package there).
  (when (fboundp 'agent-shell--file-completion-at-point)
    (advice-add 'agent-shell--file-completion-at-point
                :around #'flow-agent-shell--project-files-or-filesystem))
  ;; Subscription login, not ANTHROPIC_API_KEY.
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t))
  ;; Claude is the only agent this config sets up, so resolve EVERY
  ;; entry point to it unconditionally.  `C-c a a' passes its config
  ;; explicitly, but the package's other entry points (M-x agent-shell,
  ;; the viewport toggles, agent-shell-send-*) resolve through this
  ;; variable and otherwise fall back to a 19-agent completing-read
  ;; picker — where a plain RET returns "" (empty input bypasses
  ;; require-match), matches nothing, and errors with the baffling
  ;; "No agent config found".  The full-alist value, not the shorter
  ;; 'claude-code symbol, on purpose: symbol designators are newer than
  ;; the laptop's installed agent-shell, while the alist form is
  ;; accepted by every version.
  (setq agent-shell-preferred-agent-config
        (agent-shell-anthropic-make-claude-code-config))
  ;; The async half of `flow-agent-shell-in-directory' (see its
  ;; docstring): a pinned shell buffer answers with its pin, every
  ;; other buffer answers nil, which makes `agent-shell-cwd' fall
  ;; through to its normal project detection — so `C-c a a' behavior
  ;; is unchanged.
  (setq agent-shell-cwd-function
        (lambda () flow-agent-shell--directory))
  (when flow-claude-acp-command
    (setq agent-shell-anthropic-claude-acp-command flow-claude-acp-command)))

(provide 'flow-agent-shell)
;;; flow-agent-shell.el ends here

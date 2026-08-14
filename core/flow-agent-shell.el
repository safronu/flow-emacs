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
;; agent-shell is a NEW package for this config: on a machine whose elpa
;; archive cache predates it, the `use-package' ensure fails at startup
;; with "package unavailable" — run `M-x package-refresh-contents' once
;; and restart (never add an automatic refresh; see flow-core).
;;
;; Tablet phase (not yet wired): the module itself is device-neutral.
;; What the Android profile will need before loading it: (1) the adapter
;; runnable from the native Emacs — Node >= 22 lives in Termux, so
;; `flow-claude-acp-command' must point at a Termux-side wrapper; (2)
;; `flow-claude-config-dir' set, as for flow-gptel, so the adapter's
;; Claude finds Termux's ~/.claude login.

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

(defun flow-agent-shell-in-directory (dir)
  "Start a Claude Code agent shell rooted at DIR.
Bypasses `agent-shell-cwd''s project detection, which always climbs to
the git root — this is the way to scope the agent to a subfolder of a
repo, or to any directory regardless of what buffer is current."
  (interactive "DAgent shell in: ")
  ;; Load now, not via the autoload inside the `let': the defcustom must
  ;; exist before the `let' is evaluated for the binding to be dynamic.
  (require 'agent-shell)
  (let* ((dir (expand-file-name dir))
         (default-directory dir)
         (agent-shell-cwd-function (lambda () dir)))
    (agent-shell-anthropic-start-claude-code)))

(use-package agent-shell
  ;; :defer keeps startup free: nothing loads until the key is hit.
  :defer t
  :init
  ;; The entry command lives in agent-shell-anthropic.el inside the
  ;; package; the explicit autoload keeps the binding working even if
  ;; the package's own autoloads miss it.
  (autoload 'agent-shell-anthropic-start-claude-code "agent-shell-anthropic" nil t)
  (define-prefix-command 'flow-agent-shell-map)
  (keymap-global-set "C-c a" 'flow-agent-shell-map)
  (keymap-set flow-agent-shell-map "a" #'agent-shell-anthropic-start-claude-code)
  (keymap-set flow-agent-shell-map "d" #'flow-agent-shell-in-directory)
  :config
  ;; Subscription login, not ANTHROPIC_API_KEY.
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t))
  (when flow-claude-acp-command
    (setq agent-shell-anthropic-claude-acp-command flow-claude-acp-command)))

(provide 'flow-agent-shell)
;;; flow-agent-shell.el ends here

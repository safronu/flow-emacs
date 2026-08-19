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
  ;; No ASCII-art banner: it eats most of a half-screen window and
  ;; scrolls the actually useful first response out of view.
  (setq agent-shell-show-welcome-message nil)
  ;; The banner has a SECOND half: on graphical frames the default
  ;; header style is a multi-row SVG (icon block + key-hints row) that
  ;; stays glued to the top of the buffer.  `text' is the one-line
  ;; version with the same name/status content.
  (setq agent-shell-header-style 'text)
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

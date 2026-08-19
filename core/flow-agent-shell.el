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

(defun flow-agent-shell--completions-cap ()
  "The *Completions* height cap for agent-shell popups: 1/3 frame, min 8."
  (max 8 (/ (frame-height) 3)))

(defun flow-agent-shell--completion-limit-popup (orig-fn)
  "Around `agent-shell--trigger-completion-at-point': cap the popup height.
Un-capped, the *Completions* window is sized by `fit-window-to-buffer'
to fit ALL candidates — on the tablet's 46-line frame a 115-file
project pushed it to 39 lines, squeezing the shell window to a SINGLE
line (measured live 2026-08-19): point technically stays visible, but
completion is blind.  A dynamic let of `completions-max-height' holds
for the whole synchronous display no matter which buffer is current
when the window-height action function reads it (a buffer-local value
on the shell buffer is NOT read there — verified live), and it scopes
the cap to agent-shell's @ and / popups only: the global value stays
untouched for the rest of Emacs.  The live-refresh path re-renders the
popup outside this advice and binds the same cap itself — see
`flow-agent-shell--completion-refresh'."
  (let ((completions-max-height (flow-agent-shell--completions-cap)))
    (funcall orig-fn)))

(defvar-local flow-agent-shell--completion-last-field nil
  "Field text (after the @ or /) at the last candidate-list render.
Managed by `flow-agent-shell--completion-keep-view'; compared by
`flow-agent-shell--completion-refresh' to re-render only on change.")

(defun flow-agent-shell--completion-field-text ()
  "The current completion field text, or nil when there is no session.
Reads the bounds from `completion-in-region--data' (START is a marker,
END a marker advancing on insertion, so the field tracks typing)."
  (pcase completion-in-region--data
    (`(,start ,end . ,_)
     (when (and (markerp start)
                (eq (marker-buffer start) (current-buffer)))
       (buffer-substring-no-properties start end)))))

(defun flow-agent-shell--completion-refresh ()
  "Re-render the candidate list if the field text changed since last render.
Stock Emacs leaves *Completions* a static snapshot — typing after @
narrows NOTHING until the next explicit completion command.  This calls
`completion-help-at-point', the built-in list-only refresh (M-? in a
session): it re-runs the capf and re-renders the list for the text now
in the field, and, unlike `completion-at-point', never expands text
into the buffer (auto-expansion mid-typing would splice \"re/\" into a
half-typed \"co\" — unacceptable).  Gated on actual TEXT change, so
M-n/M-p candidate navigation — also a command, also hitting the
watchdog — does not re-render and lose the selection highlight.  Binds
the same height cap as the trigger advice: this render path does not go
through the trigger, and un-capped it would blow the popup back up to
the whole frame."
  (when-let* ((field (flow-agent-shell--completion-field-text)))
    (unless (equal field flow-agent-shell--completion-last-field)
      (setq flow-agent-shell--completion-last-field field)
      (let ((completions-max-height (flow-agent-shell--completions-cap)))
        (completion-help-at-point)))))

(defvar-local flow-agent-shell--pre-completion-row nil
  "Screen row of point in the shell window before a completion popup.
Set and consumed by `flow-agent-shell--completion-keep-view'.")

(defvar flow-agent-shell--completion-session-buffer nil
  "The shell buffer of the live completion session, or nil.
Global on purpose: `completion-in-region-mode' is a global minor mode,
so there is at most one session at a time.")

(defvar-local flow-agent-shell--completion-session-p nil
  "Non-nil in a shell buffer while its completion popup is up.
The gate variable for `flow-agent-shell--completion-nav-map' in
`minor-mode-overriding-map-alist'; managed by
`flow-agent-shell--completion-keep-view'.")

(defun flow-agent-shell-completion-choose ()
  "Insert the selected completion candidate — the first one if none yet.
`minibuffer-choose-completion' acts on the candidate at point in the
*Completions* window and errors (\"No completion here\") when nothing
has been navigated to yet, point still sitting on the list's header —
in that case select the first candidate and choose it."
  (interactive)
  (condition-case nil
      (minibuffer-choose-completion)
    (t (minibuffer-next-completion 1)
       (minibuffer-choose-completion))))

(defvar flow-agent-shell--completion-nav-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "M-p" #'minibuffer-previous-completion)
    (keymap-set map "M-n" #'minibuffer-next-completion)
    (keymap-set map "M-m" #'flow-agent-shell-completion-choose)
    ;; The raw GUI event, looked up BEFORE function-key-map would
    ;; translate it to the M-RET that `completion-in-region-mode-map'
    ;; binds — so hardware that does deliver Alt+Enter gets the
    ;; pick-first nicety too.
    (keymap-set map "M-<return>" #'flow-agent-shell-completion-choose)
    map)
  "Candidate navigation for the @/-completion popup, on M-n/M-p/M-m.
Emacs's own keys for this are M-<up>/M-<down>/M-RET (in
`completion-in-region-mode-map'), but the Boox's Android layer does not
deliver Alt+arrow or Alt+Enter chords to Emacs at all — Alt+Enter
arrives as a BARE Enter, which comint happily treats as send, firing a
half-typed @ref at the agent as a query — while Alt+letter provably
arrives (M-p/M-n/M-o are this config's daily drivers).  Registered in
the global `minor-mode-map-alist' gated on the buffer-local
`flow-agent-shell--completion-session-p', so the binding exists ONLY
while the popup is up — outside a session M-p/M-n stay comint history
(and M-RET still chooses, when the hardware has it).  NOT in
`minor-mode-overriding-map-alist': that variable is automatically
BUFFER-LOCAL, so an add-to-list from a load lands in whichever buffer
happened to be current and is invisible everywhere else (found the
hard way 2026-08-19 — the entry existed, in the server's eval
buffer).  Minor-mode maps outrank the comint/major-mode map, which is
all that is needed; the popup's own `completion-in-region-mode-map'
(M-<up>/M-<down>/M-RET) binds no M-letter keys, so there is no
conflict with its higher rank.")

(defun flow-agent-shell--completion-keep-view ()
  "Restore the shell window's view after an @/-completion session.
The *Completions* window that pops up shrinks the shell window, which
scrolls to keep point visible — and that scroll SURVIVES the popup, so
every completion leaves the transcript view shifted.

Hard-won subtleties, each a shipped bug in an earlier version:
- `completion-in-region-mode' can toggle MORE than once per popup as
  keys are typed, so only the FIRST enable has the undisturbed view
  (it fires before the first redisplay — @ is typed →
  `post-self-insert-hook' → `completion-at-point', one command); a
  later save would capture the scrolled view and \"restore\" that.
  Hence save-once: keep the pending row until it has been used.
- On disable, teardown and candidate insertion continue AFTER this
  hook, and can scroll again.  So restore via a 0-second timer — after
  the full command loop — and by point's SCREEN ROW rather than a raw
  `window-start', which the inserted text would shift anyway.
- While the popup is UP, the edited line must be actively kept on
  screen: the shrunk shell window keeps its old top anchored, and only
  the SELECTED window gets point forced visible by redisplay — so the
  moment focus is in the *Completions* window (choosing by tap or
  `switch-to-completions'), the input line at the bottom is clipped
  and completion is blind.  A one-shot timer is NOT enough (it can
  fire before the clipping happens and then nothing repairs it) — the
  enable branch installs a `post-command-hook' watchdog instead, which
  re-reveals the line after any command that hid it and removes itself
  when the session ends.
- A restore timer can fire while the session is still live (the
  mid-session toggle above ends with a re-enable).  Recentering to a
  full-height row inside the half-height window shoves the input line
  off screen — so the restore re-stashes the row and defers to the
  real session end instead."
  (when (derived-mode-p 'agent-shell-mode)
    (if completion-in-region-mode
        (progn
          (unless flow-agent-shell--pre-completion-row
            (when-let* ((window (get-buffer-window)))
              (setq flow-agent-shell--pre-completion-row
                    (count-screen-lines (window-start window) (point) t window))))
          (setq flow-agent-shell--completion-session-buffer (current-buffer))
          (setq flow-agent-shell--completion-session-p t)
          (setq flow-agent-shell--completion-last-field
                (flow-agent-shell--completion-field-text))
          (add-hook 'post-command-hook
                    #'flow-agent-shell--completion-keep-input-visible))
      (remove-hook 'post-command-hook
                   #'flow-agent-shell--completion-keep-input-visible)
      (setq flow-agent-shell--completion-session-buffer nil)
      (setq flow-agent-shell--completion-session-p nil)
      (setq flow-agent-shell--completion-last-field nil)
      (when-let* ((row flow-agent-shell--pre-completion-row))
        (setq flow-agent-shell--pre-completion-row nil)
        (run-with-timer 0 nil #'flow-agent-shell--completion-restore-view
                        (current-buffer) row)))))

(defun flow-agent-shell--completion-keep-input-visible ()
  "Re-reveal the shell's edited line while the completion popup is up.
On the global `post-command-hook' only during a session (installed and
removed by `flow-agent-shell--completion-keep-view'); self-removes as a
belt-and-suspenders if the session is found dead.  Only touches the
window when the line has actually been clipped."
  (let ((buffer flow-agent-shell--completion-session-buffer))
    (if (not (and completion-in-region-mode (buffer-live-p buffer)))
        (remove-hook 'post-command-hook
                     #'flow-agent-shell--completion-keep-input-visible)
      ;; Live-narrow the candidate list as the field text changes.
      ;; Only from the shell buffer itself: the field can only change
      ;; from commands running there, and `completion-help-at-point'
      ;; needs the shell's point.
      (when (eq buffer (current-buffer))
        (flow-agent-shell--completion-refresh))
      (when-let* ((window (get-buffer-window buffer)))
        (unless (pos-visible-in-window-p (window-point window) window)
          (with-selected-window window
            (recenter -1)))))))

(defun flow-agent-shell--completion-restore-view (buffer row)
  "Scroll BUFFER's window so the edited line is back at screen ROW.
Runs from a 0-second timer scheduled on the popup's disable.  If the
session turns out to be live again by then (mid-session toggle), the
window is still half-height — restoring now would scroll the input line
off screen, so re-stash ROW for the real session end instead."
  (when-let* (((buffer-live-p buffer))
              (window (get-buffer-window buffer)))
    (if completion-in-region-mode
        (with-current-buffer buffer
          (unless flow-agent-shell--pre-completion-row
            (setq flow-agent-shell--pre-completion-row row)))
      (with-selected-window window
        (recenter (min (max 0 (1- row))
                       (1- (window-body-height window))))))))

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
  ;; Un-scroll the shell after the *Completions* popup — see the
  ;; function's docstring.  The hook is global (it must run on both the
  ;; mode's enable and disable); the agent-shell-mode guard is inside.
  (add-hook 'completion-in-region-mode-hook
            #'flow-agent-shell--completion-keep-view)
  ;; …and keep the popup itself from eating the whole frame — see the
  ;; advice's docstring.  Same fboundp guard as above: no completion
  ;; module, nothing to advise.
  (when (fboundp 'agent-shell--trigger-completion-at-point)
    (advice-add 'agent-shell--trigger-completion-at-point
                :around #'flow-agent-shell--completion-limit-popup))
  ;; M-n/M-p candidate navigation while the popup is up — see the nav
  ;; map's docstring (including why minor-mode-map-alist and not the
  ;; buffer-local overriding alist).  The commands are Emacs 29+; both
  ;; machines run 30.
  (when (fboundp 'minibuffer-next-completion)
    (add-to-list 'minor-mode-map-alist
                 (cons 'flow-agent-shell--completion-session-p
                       flow-agent-shell--completion-nav-map)))
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

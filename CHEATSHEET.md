# LaTeX on Boox Note Max — Cheatsheet

Karthik Chikmagalur's "impatient scholars" setup, adapted for native Android
Emacs (`org.gnu.emacs`) + Termux TeX Live.

## Start

1. Open the **Emacs** app (the native Android port).
2. `C-x C-f` → open a `.tex` file (try `~/latex-scratch/test.tex`).
3. First launch installs `auctex cdlatex yasnippet ace-window org-fragtog`
   (+ `avy` as ace-window's dep) from MELPA — needs network.

## Display: previews + folds + font on one prefix

`C-c p` controls everything the buffer *shows*, switching between two
states tracked by the buffer-local minor mode `flow-latex-doc-mode`
(look for the ` Doc` lighter in the mode line). **Raw code** (mode
off, how every buffer opens): default mono font, line numbers, no
folds, no previews. **Document** (mode on): the document's own font
(`latex-font-sync`), markup folded, math previewed, no line numbers.
The current line stays highlighted (`hl-line-mode`) in both states, so
point is easy to find right after a switch. Nothing folds,
previews, or re-fonts on its own; these keys are the only triggers.

| Keys        | Action                                             |
| ----------- | -------------------------------------------------- |
| `M-p`       | Toggle between the two states with one chord       |
| `C-c p p`   | In math: preview the formula. Elsewhere: fold the macro/environment at point (on an existing fold: unfold it). Never touches the font |
| `C-c p b`   | Enter document mode: doc font + fold all markup + preview the whole buffer. Pressing again refreshes after edits |
| `C-c p c`   | Back to raw code: clear previews and folds, restore the default font (syntax colors stay) |
| `C-c C-p C-p` | AUCTeX default: preview at point                 |

Point inside `$…$`, `\[…\]`, or an env like `equation` — hit `C-c p p`.
Move point onto an overlay to reveal the source; leave to re-render.
`\verb` bodies fold only via the buffer-wide `C-c p b` (AUCTeX folds
them per-region, not per-item).

The same `C-c p p` / `C-c p b` / `C-c p c` work in `.org` buffers too
(`C-c p p` toggles the fragment at point; org's own `C-c C-x C-l` also
still works).

## Markdown (`.md`)

| Keys      | Action                                             |
| --------- | -------------------------------------------------- |
| `C-c p p` | Live HTML preview in a side window, re-renders on save |
| `C-c p b` | Render once, open in the system browser (math typeset) |
| `C-c p c` | Close the live preview                             |
| `C-c p i` | Toggle inline images                               |

Same prefix as the LaTeX/org previews, different engine: the buffer goes
through `pandoc` and the HTML is shown by eww (`C-c p p`) or a real
browser (`C-c p b`). markdown-mode's own keys still work — `C-c C-s`
insertion family, `C-c C-n`/`C-c C-p` heading motion, `C-c C-c l`/`p`.
Math (`$x$`) is fontified in the buffer and typeset only in the browser
view; for real math work use `.tex`.

## Folding + fonts

`TeX-fold-mode` is on, but folding is strictly on-demand: the buffer
opens as plain source and folds only via `C-c p p`/`C-c p b` (or the
native `C-c C-o` keys below). Text-markup macros display as their
styled content (`\textbf{F}` → **F**, `\emph{x}` → *x*,
`\section{Foo}` → Foo); point entry auto-reveals the source (via
TeX-fold's own `TeX-fold-auto-reveal`, not `reveal-mode` — fold
overlays hide contents through the `display` property, which
`reveal-mode` doesn't watch), exit re-folds. Math (`\pi`, `\int`) is
NOT folded — preview it instead with `C-c p p`.

| Keys          | Action                                    |
| ------------- | ----------------------------------------- |
| `C-c C-o C-b` | Fold whole buffer                         |
| `C-c C-o C-r` | Fold region                               |
| `C-c C-o b`   | Unfold whole buffer                       |
| `C-c C-o C-e` | Fold current environment (hides its body — `C-c p p` folds just the `\begin`/`\end` markers) |
| `C-c C-o C-m` | Fold macro at point                       |

In document mode (`C-c p b`) buffer text is set to the document's own
font (via `latex-font-sync`), while macro syntax stays in a monospace
face (Droid Sans Mono by default); `C-c p c` puts the whole buffer back
in the default mono font. `M-x my/latex-font-explain` shows why the
document font is what it is; override with `M-x my/latex-font-try-family`.

## Windows (everything via M-o)

`M-o` always shows a big letter (`a s d f …`) on every window and waits
for one key. Press a window's letter to jump there — or press an action
key first:

| After `M-o` | Action                                        |
| ----------- | --------------------------------------------- |
| `a s d …`   | Jump to that window                           |
| `b`         | New window side by side (was `C-x 3`)         |
| `v`         | New window below (was `C-x 2`)                |
| `x`         | Close a window (then press its letter)        |
| `o`         | Keep only the current window (was `C-x 1`)    |
| `m`         | Swap: press the other window's letter         |
| `?`         | Show all actions                              |
| `C-g`       | Cancel                                        |

Works from a single window too: `M-o b` splits side-by-side, `M-o v`
splits top/bottom. The classic `C-x 2/3/0/1` keys still work if you
ever want them.

## Selecting text

| Keys        | Action                                             |
| ----------- | -------------------------------------------------- |
| `C-=`       | Grow the region from point: word → phrase → paragraph … (expand-region) |
| `C-- C-=`   | Shrink it back one step                            |
| `C-SPC` … `C-x C-x` | Mark set *before* typing; afterwards re-selects exactly what you typed |
| `M-@` / `C-M-SPC` / `M-h` | Built-ins: mark word / sexp / paragraph at point |

`C-=` is a Ctrl+punctuation chord — the GUI Android Emacs takes it
natively, but a terminal may have no encoding for it; in Termux
`emacs -nw` use `M-x er/expand-region` if the key doesn't register.
For the "rewrite what I just typed" case you usually need no selection
at all — `M-r` (or `C-c g r`) falls back to the current line (see
*LLM chat*).

## Display (e-ink)

Syntax, diffs, and org states are styled by typography instead of
color (bold keywords, italic strings, strike-through = removed/DONE,
inverse black = error/current match) — see
`android-emacs/eink-faces.el`.

In `.tex` buffers: section titles are full-ink and bold,
`\ref`/`\label`/`\cite` are semi-bold (not underlined), folded macro
content is black, and a light-gray wash marks any preview/fold
that is currently open for editing.

| Keys      | Action                                              |
| --------- | --------------------------------------------------- |
| `C-c e f` | Cycle font size 15 → 16 → 18 → 20 pt (previews follow; `C-c p c` clears stale ones) |
| `C-c e g` | Full redraw — clear e-ink ghosting from Emacs's side |

## Math snippets (YaSnippet)

`mm` and `dm` expand anywhere in a LaTeX buffer — type the key, then
**TAB**. `ee`, `sr`, `sb` are *auto-snippets*: they fire the instant
you finish typing the key inside math (`$…$`, `\[…\]`, envs), no TAB
needed.

| Key  | Expands to        | When it fires             |
| ---- | ----------------- | ------------------------- |
| `mm` | `$ | $`           | anywhere, on TAB          |
| `dm` | `\[ | \]`         | anywhere, on TAB          |
| `sr` | `^{ | }`          | in math only, auto        |
| `sb` | `_{ | }`          | in math only, auto        |
| `ee` | `e^{ | }`         | in math only, auto        |

Add snippets under `~/.config/emacs/snippets/latex-mode/` (Termux
Emacs — its `user-emacs-directory` is `~/.config/emacs/`, NOT
`~/.emacs.d/`) or `/data/data/org.gnu.emacs/files/.emacs.d/snippets/latex-mode/`
(Android Emacs), then `M-x yas-reload-all`.

## CDLaTeX (fast math input)

Active in `LaTeX-mode` and inside org-mode LaTeX fragments.

| Keys              | Action                                 |
| ----------------- | -------------------------------------- |
| `TAB` (in math)   | Expand abbrev or jump to next `?` slot |
| `` ` ``           | Prefix for symbols (`` `a `` → `\alpha`) |
| `'`               | Accent prefix (`'a` → `\hat{a}` etc.)  |
| `_`, `^`          | Auto-brace: `_1` → `_{1}`              |
| `fr` + TAB        | `\frac{ | }{ }`                        |
| `sq` + TAB        | `\sqrt{ | }`                           |
| `sum` + TAB       | `\sum_{ | }^{ }`                       |
| `int` + TAB       | `\int_{ | }^{ } \, d`                  |
| `bmat` + TAB      | `\begin{bmatrix} | \end{bmatrix}` + org-table edit |
| `pmat`, `smat`    | pmatrix / smallmatrix — same table flow |

**Matrix/table flow:** `bmat` TAB → fill cells in the org-table with TAB between
fields → `C-c C-c` to replace with a LaTeX matrix.

## Compile / view PDF

| Keys       | Action                              |
| ---------- | ----------------------------------- |
| `C-c C-c`  | Run next command (LaTeX / View / …) |
| `C-c C-a`  | LaTeXmk-style: build until stable   |
| `C-c C-l`  | Show compilation log                |
| `C-c C-e`  | Insert environment (`equation`, …)  |
| `C-c C-s`  | Insert section                      |
| `C-c C-f`  | Font: `C-c C-f C-b` bold, `C-i` italic |

## References (RefTeX) + Stacks-style notes

Create a notes project with `notes-init` (Termux). Architecture: one
small `.tex` file per chapter, each independently compilable; labels are
`\label{lemma-descriptive-name}`; other chapters reference them as
`\ref{<chapter>-lemma-descriptive-name}` (see the project's README.md).

| Keys       | Action                                                   |
| ---------- | -------------------------------------------------------- |
| `C-c )`    | Insert `\ref` — menu of labels in this chapter           |
| … then `x` | Switch menu to another chapter (prefix auto-added)       |
| `C-c &`    | Jump from `\ref` at point to the label's definition      |
| `C-c (`    | Insert `\label` (auto-prefixed: `lemma-`, `definition-`) |
| `C-c =`    | Chapter table of contents; `RET` jumps                   |

At the `C-c )` type prompt: `h` theorem, `p` proposition, `l` lemma,
`c` corollary, `d` definition, `x` example, `X` exercise, `r` remark,
`s` section, `e` equation. Inside the menu: `TAB` completes by name,
`RET` inserts, `q` quits. (`C-c &` belongs to RefTeX here — YaSnippet's
snippet-management prefix on that key is unbound; use
`M-x yas-insert-snippet` instead.)

## Calc → LaTeX

`C-S-e` on a line (or region) sends it through Emacs Calc and pastes the
result as LaTeX (fractions, radians).

## Deadlines (`C-c d` prefix)

Commitments to external parties, in
`/data/data/com.termux/files/home/deadlines/deadlines.org` (the Termux home —
`~` inside the Emacs app is a different directory). `C-c d f` opens it.
Customers are headlines; their deadlines are the children beneath them.

| Key | Does |
| --- | --- |
| `C-c d d` | live agenda — honours each entry's `-Nd` lead time |
| `C-c d D` | 60-day horizon — ignores `-Nd`, for the weekly review |
| `C-c d c` | capture into Inbox (text + date only, no customer needed) |
| `C-c d f` | open `deadlines.org` |
| `C-c d l` | lint — unassigned, and open >30 days overdue |
| `C-c d s` | pull, commit, push |

`C-c d d` hiding an entry that `C-c d D` shows is correct, not a bug: `-Nd` on
a DEADLINE is a per-entry lead time, and a positive global
`org-deadline-warning-days` cannot widen it — only a negative value overrides
it, which is what `D` sets.

Saving `deadlines.org` commits locally (no network). `C-c d s` pushes. A GitHub
Actions job sends the daily Telegram digest at 07:00 MSK; nothing on this
device has to be running for that (GitHub delays scheduled runs, so it lands
between 07:00 and roughly 07:20). The whole prefix is absent unless the
checkout exists — that is by design, see `core/flow-deadlines.el`.

## LLM chat (`C-c g` prefix)

`gptel` with the local `claude` CLI as the backend (the CLI's own
subscription login is the auth — no API key). Two backends are
registered: **Claude-Code** (default, plain chat, sandboxed working
dir) and **Claude-Agent** (real Claude Code tools in read-only `plan`
mode, working dir = the request buffer's dir) — switch per buffer from
`C-c g m`.

Needs Termux's `claude` CLI (see `CLAUDE.md`); Emacs finds it on the
same `PATH` it uses for TeX Live. If every request comes back `Not
logged in · Please run /login`, the CLI is running but reading the
Emacs app's HOME instead of Termux's — check `flow-claude-config-dir`
in `android-emacs/init.el`, not your login.

| Keys      | Action                                          |
| --------- | ----------------------------------------------- |
| `C-c g g` | Open / switch to a chat buffer                  |
| `C-c g s` | Send region, or buffer up to point              |
| `C-c g m` | gptel menu (model, backend, system prompt, …)   |
| `M-r`     | Rewrite region — no region: the current line    |
| `C-c g r` | Same rewrite, on the mnemonic prefix            |
| `C-c g a` | Add region / buffer to context                  |
| `C-c g f` | Add file to context                             |
| `C-c g k` | Abort the request in this buffer                |
| `C-c RET` | Inside a chat buffer: send (gptel's own key)    |

`M-r` shadows Emacs's `move-to-window-line-top-bottom` in normal
buffers; the minibuffer's `M-r` history search and isearch's `M-r`
are in local keymaps and keep working.

**Describe → LaTeX** (the typical rewrite): type a plain description
where the math should go — `Euler's formula` on its own line — and hit
`M-r` straight away. With no region active it selects the current
line for you (whitespace-trimmed), so there is no marking step; with a
region active it rewrites exactly the region. `RET` through the
instruction prompt (the TeX prompt file already says "produce valid
LaTeX, nothing else") or type a refinement, then accept with `C-c r a`
when it's ready. For a phrase typed mid-line, select it first — `C-=`
(see *Selecting text*) or set the mark before typing and `C-x C-x`
after.

**Prompt library** (`core/prompts/`): one plain-text `NAME.txt` per
reusable prompt. In TeX buffers the rewrite's system message comes
from `rewrite-latex.txt`; every file is also a named directive in the
`C-c g m` menu (pick it globally, per buffer, or for one request).
Files are read per request — edit one and the next request uses the
new text; after *adding* a file, `M-x flow-gptel-reload-prompts` (or
restart) registers the menu entry.

**Rewrite lifecycle** (`M-r` on a region): the region gets a
`REWRITE` title that cycles *Waiting…* (includes the model's thinking
time, so this is most of the wait) → *Typing…* → *Ready*. The buffer is
NOT modified — the proposed text is shown in an overlay, and nothing
blocks: keep editing elsewhere, switch windows, decide whenever. On
*Ready* the title lists the keys, which work with point inside the
highlighted region: `C-c r a` accept, `C-c r k` reject, `C-c r r`
iterate (refine with a new instruction), `C-c r m` merge with conflict
markers, `C-c r d` diff, `C-c r e` ediff, and `C-c r n` / `C-c r p`
hop between multiple pending rewrites. (gptel's stock `C-c C-a`-style
keys are deliberately rebound — inside the region they would shadow
AUCTeX's compile/environment/preview commands, see
`core/flow-gptel.el`; TeX keys keep working there instead.) `RET` or
mouse-1 on the region opens a one-key chooser for the same actions
(`a`/`k`/`r`/`m`/`d`/`e` — it does grab input until you pick or
`C-g`), and `M-r` with point on a pending rewrite opens the full
menu. The title line and the
proposed text are pure display — never buffer text — so pdflatex,
the live PDF and inline previews never see them.

## Agentic coding (`C-c a` prefix, laptop only)

`agent-shell` driving Claude Code over ACP — the agentic complement to
`C-c g` chat: the agent edits files and runs commands, asking
permission per action and showing diffs to accept or reject. Same
subscription login as gptel, no API key. The shell starts at the
current buffer's **project root** (git root); use `d` to pick the
directory explicitly — that is also the only way to scope the agent to
a subfolder of a repo, since project detection always climbs to the
git root.

| Keys      | Action                                            |
| --------- | ------------------------------------------------- |
| `C-c a a` | Start a Claude Code agent shell at project root   |
| `C-c a d` | Start one in a directory chosen explicitly        |

Only those two are global; everything below is either an in-buffer key
or `M-x`.

**Talking to the agent.** The shell is a comint buffer — the prompt is
the last line, history is `M-p`/`M-n`.

| Keys        | Action                                                     |
| ----------- | ---------------------------------------------------------- |
| `RET`       | Submit the prompt                                          |
| `S-RET`     | Newline inside the prompt                                  |
| `@`         | Complete a project file at point                           |
| `/`         | Complete an agent command                                  |
| `C-c C-c`   | Interrupt the running turn (confirms first)                |
| `TAB` / `S-TAB` | Next / previous item (tool call, permission, block)    |
| `n` / `p`   | Same, outside the prompt area                              |
| `r`         | Quote the region from the other buffer into the prompt     |
| `C-y`       | Yank DWIM — text, image, or file path as an attachment     |
| `+` `-` `0` | Scale inline images                                        |
| `C-c C-o`   | Switch between the shell and its compose/viewport buffer   |
| `C-M-h`     | Mark the response at point                                 |

`M-x agent-shell-prompt-compose` writes the next prompt in a dedicated
buffer (with the same `@` and `/` completion) instead of the one-line
comint prompt — the way to send anything long. `M-x
agent-shell-prompt-queue` queues a prompt *while the agent is busy*; it
is sent automatically when the turn ends (`-resume`, `-remove` manage
the queue). `M-x agent-shell-send-region` / `-send-dwim` /
`-send-file-to` / `-send-screenshot` / `-send-clipboard-image` push
context in from anywhere. Starting a shell with a region active, or
from dired, carries that in too (`agent-shell-context-sources`).

**Permissions, on the fly.** The current mode shows in the mode line and
can be changed mid-session — the ACP adapter exposes Claude Code's own
permission modes.

| Keys      | Action                                             |
| --------- | -------------------------------------------------- |
| `C-<tab>` | Cycle session mode                                 |
| `C-c C-m` | Pick session mode by name                          |
| `C-c C-v` | Pick model (Opus / Opus 1M / Fable / Sonnet / Haiku) |
| `C-c C-t` | Pick thought level (reasoning effort)              |
| `C-c C-s` | One menu over every session option above           |

Modes: **Manual** (`default`, asks before dangerous operations),
**Auto** (a classifier answers the prompts), **Accept Edits**
(auto-accepts file edits), **Plan Mode** (plans, executes nothing),
**Don't Ask** (never asks, denies anything not pre-approved), **Bypass
Permissions** (no checks). Clicking the mode name in the mode line opens
the same menu. For a startup default set
`agent-shell-anthropic-default-session-mode-id` to one of those ids.

When the agent asks for permission, the buttons in the buffer are keys:

| Key       | Action                                                  |
| --------- | ------------------------------------------------------- |
| `y`       | Allow once                                              |
| `!`       | Always allow                                            |
| `C-c C-c` | Reject — also interrupts, so you can course-correct     |
| `v`       | View the diff                                           |

In the diff buffer: `n`/`p` move by hunk, `y` accepts all, `C-c C-c`
rejects all, `RET` opens the file, `q` quits. To answer permissions
programmatically, set `agent-shell-permission-responder-function`
(`#'agent-shell-permission-allow-always` is the built-in YOLO handler).

**Several sessions.** One buffer per session, named `Claude @ <project>`;
killing the buffer shuts that agent down.

| Keys / command                  | Action                                     |
| ------------------------------- | ------------------------------------------ |
| `C-u M-x agent-shell`           | Force a new shell in the same project      |
| `C-u C-u M-x agent-shell`       | Pick an existing shell                     |
| `M-x agent-shell-switch-buffer` | Same picker, by name                       |
| `M-x agent-shell-toggle`        | Show/hide this project's shell             |
| `M-x agent-shell-new-worktree-shell` | New `git worktree` + a shell in it    |
| `M-x agent-shell-new-temp-shell` | Shell in a temp dir, trashed on kill      |
| `M-x agent-shell-fork`          | Branch a second shell off this session     |

The worktree one is how to run two agents on the same repo without them
fighting over the working tree.

**Resuming.** Not a separate command — `C-c a a` asks the agent for the
sessions in that directory and offers them, newest first, alongside “New
shell”:

| Variable                            | Effect                                          |
| ----------------------------------- | ----------------------------------------------- |
| `agent-shell-session-strategy`      | `prompt` (default) / `latest` / `new`           |
| `agent-shell-session-restore-verbosity` | how much history is replayed: `minimal` (default, title only) / `last` / `first-last` / `full` |

Sessions are the CLI's own and are keyed by working directory, so a
shell started with `C-c a d` in a subfolder lists only that subfolder's
sessions. `M-x agent-shell-resume-session` takes a session id directly,
`-copy-session-id` yields one, `-reload` restarts the process on the
same session, `-restart` starts a fresh session in the same project, and
`-open-transcript` opens the saved conversation.

**Inspecting.** `M-x agent-shell-show-usage` (tokens, context, cost — a
context indicator also sits in the mode line);
`agent-shell-view-traffic`, `agent-shell-view-acp-logs` and
`agent-shell-toggle-logging` are the three to reach for when the adapter
itself misbehaves. `agent-shell-mcp-servers` attaches MCP servers
(stdio/http/sse) to new sessions.

## Files

- `~/.emacs.d/init.el` — the config (mirror of Karthik's, tuned for e-ink).
- `~/.emacs.d/snippets/latex-mode/` — YaSnippet math snippets.
- `~/latex-scratch/` — scratch `.tex` files.
- `~/math-notes/` — Stacks-style notes project (create with `notes-init`).
- `/data/data/com.termux/files/home/deadlines/` — the private deadlines repo
  (`C-c d`), cloned by hand; absent on devices that don't track deadlines.
- Termux TeX Live: `/data/data/com.termux/files/usr/share/texlive/2026`.

## Troubleshooting

- **Snippet doesn't expand:** `M-x yas-reload-all`. `mm`/`dm` work
  anywhere; `ee`/`sr`/`sb` fire only when point is inside math.
- **`dvisvgm` rejects gs:** `pkg install mupdf-tools` (mutool is
  required for `dvisvgm`'s PDF pipeline because Termux gs 10.07 is
  newer than what dvisvgm accepts). This applies to `dvisvgm` only —
  the `C-c p p` preview pipeline is `pdflatex → pdf2dsc → gs` and does
  not touch dvisvgm.
- **`pdflatex: command not found` from Emacs:** relaunch the app — early-init
  puts Termux + TeX Live on `PATH`.
- **Missing LaTeX package:** `tlmgr install <pkg>` in Termux.
- **Overlay is fuzzy:** raise the default face height — `C-c e f`
  cycles 15/16/18/20 pt at runtime, or edit the `set-face-attribute
  'default … :height 150` line in `android-emacs/init.el` to change
  the startup value. Preview DPI is derived from the default face
  height, so bigger buffer text = higher DPI = crisper overlay.
  After a size change: `C-c p c`, then re-preview.

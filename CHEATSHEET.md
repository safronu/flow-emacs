# LaTeX on Boox Note Max — Cheatsheet

Karthik Chikmagalur's "impatient scholars" setup, adapted for native Android
Emacs (`org.gnu.emacs`) + Termux TeX Live.

## Start

1. Open the **Emacs** app (the native Android port).
2. `C-x C-f` → open a `.tex` file (try `~/latex-scratch/test.tex`).
3. First launch installs `auctex cdlatex yasnippet ace-window org-fragtog`
   (+ `avy` as ace-window's dep) from MELPA — needs network.

## Preview (inline PNG overlay)

| Keys        | Action                          |
| ----------- | ------------------------------- |
| `C-c p p`   | Preview formula/env at point    |
| `C-c p b`   | Preview whole buffer            |
| `C-c p c`   | Clear all previews              |
| `C-c C-p C-p` | AUCTeX default: preview at point |

Point inside `$…$`, `\[…\]`, or an env like `equation` — hit `C-c p p`.
Move point onto an overlay to reveal the source; leave to re-render.

The same `C-c p p` / `C-c p b` / `C-c p c` work in `.org` buffers too
(`C-c p p` toggles the fragment at point; org's own `C-c C-x C-l` also
still works).

## Folding + fonts

`TeX-fold-mode` is on by default and the buffer folds itself on open.
Text-markup macros display as their styled content (`\textbf{F}` →
**F**, `\emph{x}` → *x*, `\section{Foo}` → Foo); point entry
auto-reveals the source (via TeX-fold's own `TeX-fold-auto-reveal`, not
`reveal-mode` — fold overlays hide contents through the `display`
property, which `reveal-mode` doesn't watch), exit re-folds. Math
(`\pi`, `\int`) is NOT folded — preview it instead with `C-c p p`.

| Keys          | Action                                    |
| ------------- | ----------------------------------------- |
| `C-c C-o C-b` | Fold whole buffer                         |
| `C-c C-o C-r` | Fold region                               |
| `C-c C-o b`   | Unfold whole buffer                       |
| `C-c C-o C-e` | Fold current environment                  |
| `C-c C-o C-m` | Fold macro at point                       |

Buffer text is set to the document's own font (via `latex-font-sync`),
while macro syntax stays in a monospace face (Droid Sans Mono by default).
`M-x my/latex-font-explain` shows why the document font is what it is;
override with `M-x my/latex-font-try-family`.

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

| Keys      | Action                                          |
| --------- | ----------------------------------------------- |
| `C-c g g` | Open / switch to a chat buffer                  |
| `C-c g s` | Send region, or buffer up to point              |
| `C-c g m` | gptel menu (model, backend, system prompt, …)   |
| `C-c g r` | Rewrite region                                  |
| `C-c g a` | Add region / buffer to context                  |
| `C-c g f` | Add file to context                             |
| `C-c g k` | Abort the request in this buffer                |
| `C-c RET` | Inside a chat buffer: send (gptel's own key)    |

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

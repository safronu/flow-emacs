# LaTeX on Boox Note Max — Cheatsheet

Karthik Chikmagalur's "impatient scholars" setup, adapted for native Android
Emacs (`org.gnu.emacs`) + Termux TeX Live.

## Start

1. Open the **Emacs** app (the native Android port).
2. `C-x C-f` → open a `.tex` file (try `~/latex-scratch/test.tex`).
3. First launch installs `auctex cdlatex yasnippet` from MELPA — needs network.

## Preview (inline SVG overlay)

| Keys        | Action                          |
| ----------- | ------------------------------- |
| `C-c p p`   | Preview formula/env at point    |
| `C-c p b`   | Preview whole buffer            |
| `C-c p c`   | Clear all previews              |
| `C-c C-p C-p` | AUCTeX default: preview at point |

Point inside `$…$`, `\[…\]`, or an env like `equation` — hit `C-c p p`.
Move point onto an overlay to reveal the source; leave to re-render.

## Math snippets (YaSnippet)

Type the key, then **TAB**. Only fire inside math (`$…$`, `\[…\]`, envs).

| Key  | Expands to        |
| ---- | ----------------- |
| `mm` | `$ | $`           |
| `dm` | `\[ | \]`         |
| `sr` | `^{ | }`          |
| `sb` | `_{ | }`          |
| `ee` | `e^{ | }`         |

Add snippets under `~/.emacs.d/snippets/latex-mode/`, then `M-x yas-reload-all`.

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

## Calc → LaTeX

`C-S-e` on a line (or region) sends it through Emacs Calc and pastes the
result as LaTeX (fractions, radians).

## Files

- `~/.emacs.d/init.el` — the config (mirror of Karthik's, tuned for e-ink).
- `~/.emacs.d/snippets/latex-mode/` — YaSnippet math snippets.
- `~/latex-scratch/` — scratch `.tex` files.
- Termux TeX Live: `/data/data/com.termux/files/usr/share/texlive/2026`.

## Troubleshooting

- **Snippet doesn't expand:** `M-x yas-reload-all`. Check point is in math.
- **Preview error "gs not supported":** `pkg install mupdf-tools` (mutool is
  required because Termux gs 10.07 is newer than dvisvgm accepts).
- **`pdflatex: command not found` from Emacs:** relaunch the app — early-init
  puts Termux + TeX Live on `PATH`.
- **Missing LaTeX package:** `tlmgr install <pkg>` in Termux.
- **Overlay is fuzzy:** raise `preview-scale-function` factor in `init.el`
  (currently `1.4`).

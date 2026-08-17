# flow-emacs

One Emacs configuration for two machines — the **Onyx Boox Note Max**
(13" Android 13 e-ink tablet, both its native Emacs app and Termux) and
an **Ubuntu laptop** (Xiaomi 15.6", 3200x2000).  The heart of it is a
portable adaptation of Karthik Chikmagalur's ["LaTeX Input for Impatient
Scholars"][karthink] — fast math snippets, live inline previews, minimal
typing.

[karthink]: https://karthinks.com/software/latex-input-for-impatient-scholars/

## How the sharing works

Everything device-independent lives in `core/` as `flow-*` modules.
Each device has a small **profile** directory holding only its entry
point (`init.el`, sometimes `early-init.el`) plus anything true of that
machine alone.  The live init path on every device is a **symlink** to
its profile's init.el; the init resolves that symlink (`file-truename`)
to find the repo, so core modules, snippets and the rest load straight
from the working tree — `git pull` is a complete update, and no new
symlinks are ever needed when a module is added.

A profile declares what its device *is* (knobs defined in
`core/flow-boot.el`: e-ink or LCD, fonts, theme, folding, where the
private deadlines checkout lives) and the core modules read those knobs
instead of sniffing the machine.

| | android profile | termux profile | laptop profile |
| --- | --- | --- | --- |
| display | e-ink, images OK | e-ink, **no images** | colour LCD |
| previews | inline overlays (`C-c p p`) | external viewer (`<f5>`) | inline overlays (`C-c p p`) |
| theme | modus-operandi + eink-faces | terminal's own | modus-operandi, colour |
| math folding | on | off (prettify-symbols instead) | on |
| doc-font sync | on (bundled TTFs) | off (tty) | on (system TeX Gyre fonts) |
| markdown preview | eww side window (`C-c p p`) | eww side window, text only | eww side window (`C-c p p`) |

The private `deadlines` repo (customer data — never vendored here) is
loaded if its checkout exists at the profile's declared path, silently
skipped otherwise; see `core/flow-deadlines.el`.

## What this gives you

- **Native Android Emacs** (`org.gnu.emacs`) with real `preview-latex`
  inline overlays for every math snippet, sized to match your buffer text.
- **Termux Emacs** (`-nw`) as a fallback for terminal work, with an
  external-viewer preview flow (no image support in that Emacs build).
- **Termux TeX Live 2026** (`scheme-infraonly` + a few packages) providing
  `pdflatex`, `dvisvgm`, `mutool`, `gs`.
- **CDLaTeX + YaSnippet** for one-keystroke math (`mm`, `dm`, `fr`, `bmat`, …).
- A `latex-scratch` command that opens a scratch `.tex` file in Emacs.
- A `notes-init` command that scaffolds a Stacks-style multi-chapter
  math-notes project with RefTeX-navigable cross-references.
- An optional `latex-preview-server` (Python HTTP) for browser preview.

## Repository layout

```
flow-emacs/
├── README.md                       This file — architecture & rationale
├── DEPLOY.md                       Step-by-step install on a fresh Boox
├── CLAUDE.md                       Context primer for Claude Code sessions
├── CHEATSHEET.md                   One-page keys reference
├── install.sh                      Idempotent deploy script (Boox/Termux)
├── install-laptop.sh               Idempotent deploy script (laptop)
│
├── core/                           Shared, device-independent modules
│   ├── flow-boot.el                Repo locator + device-knob declarations
│   ├── flow-core.el                Package system, defaults, M-o windows
│   ├── flow-latex.el               AUCTeX, RefTeX, cdlatex, yas, folding
│   ├── flow-preview.el             Inline previews (.tex + .org) — GUI only
│   ├── flow-live-pdf.el            C-c p l: fresh compiled PDF, ace-window placed
│   ├── flow-markdown.el            markdown-mode + C-c p p HTML preview
│   ├── flow-page.el                Display-math air around \[...\] blocks
│   ├── flow-gptel.el               C-c g: LLM chat via the Claude Code CLI
│   ├── flow-agent-shell.el         C-c a: agentic coding over ACP
│   ├── flow-deadlines.el           Guarded loader for the private repo
│   ├── gptel-claude-code/          gptel backend running claude -p (+ tests, docs)
│   ├── latex-font-sync/            Buffer :family follows LaTeX font package
│   │   ├── latex-font-sync.el      The mode itself
│   │   └── latex-font-sync-tests.el  ERT tests
│   └── snippets/latex-mode/        mm, dm, sr, sb, ee — one copy for all
│
├── android-emacs/                  Profile: native Android Emacs (org.gnu.emacs)
│   ├── early-init.el               PATH, TEXMFROOT, package-quickstart
│   ├── init.el                     Knobs + Termux PATH + module loads
│   ├── eink-faces.el               Monochrome typographic face signatures
│   └── fonts/                      TTF conversions of TeX Gyre + Latin Modern
│
├── termux-emacs/                   Profile: terminal Emacs (no image support)
│   └── init.el                     Knobs + external-viewer preview flow
│
├── laptop-emacs/                   Profile: Ubuntu laptop (snap Emacs 30)
│   ├── early-init.el               package-quickstart, signature bootstrap
│   └── init.el                     Knobs + module loads (colour, no eink)
│
├── termux/                         Termux shell / installer files
│   ├── bashrc                      PATH, texlive.sh sourcing, aliases
│   └── texlive-basic.profile       install-tl profile (scheme-infraonly)
│
├── bin/                            Helper scripts on $PATH (Termux)
│   ├── latex-scratch               Scratch .tex file + open in Emacs
│   └── latex-preview-server        HTTP preview server (Python)
│
└── scratch/                        Playground
    └── test.tex                    Sanity test file with math
```

On every device the live init path is a **symlink into this repo**, and
only the entry points are linked — everything else loads from the
working tree through that symlink. Editing a file in the repo takes
effect the next time the relevant program is launched.

## Live compiled PDF

`C-c p l` (`flow-latex-live-pdf`, android + laptop profiles) toggles the
actual compiled PDF of the current document, kept fresh — via
`latexmk -pvc` when installed (watches all inputs, handles
bibtex/multi-pass), else by recompiling with pdflatex on every save.
Where the PDF goes is asked in ace-window's language: every window
shows its selection letter; press one to place the PDF there, or use a
dispatch key first (`b` split side-by-side, `v` split top/bottom).
`C-g` cancels.  Displayed through pdf-tools when installed, otherwise
built-in doc-view, with auto-revert repainting on each rebuild.

## Markdown

`core/flow-markdown.el` puts `markdown-mode` on every profile and gives
`.md` buffers the same `C-c p` prefix the .tex and .org previews use:
`C-c p p` opens a live HTML preview in a side window that re-renders on
save, `C-c p b` hands the same HTML to the system browser, `C-c p c`
closes the preview, `C-c p i` toggles inline images.

The engine is not AUCTeX's: markdown-mode pipes the buffer through an
external converter — pandoc when installed, cmark/cmark-gfm and friends
as fallbacks (`flow-markdown-command-candidates`, overridable per device
with the `flow-markdown-command` knob) — wraps the returned HTML
*fragment* in a `<head>` carrying our stylesheet, writes it beside the
source as `FOO.html`, and shows it in eww. That export file is removed
when the preview is switched off. Math is emitted as plain HTML for the
eww view (real superscripts, one copy — `--mathml` there produced each
formula twice) and as MathML for the browser view, which Firefox and
Chrome typeset natively without network or JavaScript.

With no converter installed nothing breaks: editing works, and the
preview keys say which package to install for the device.

## Laptop notes

The laptop panel is 3200x2000 at ~239 physical DPI, but X/XWayland
reports a screen size back-derived from 96 DPI — the same *class* of lie
the Android port tells (see "Bogus monitor size" below), just a
different multiple. The char-metric DPI overrides in
`core/flow-preview.el` cover both, which is why they live in core and
not in an Android profile. Deploy with `bash install-laptop.sh`
(apt-installs TeX Live recommended+extra, preview-latex's style,
JetBrains Mono, then symlinks `~/.emacs.d/{init,early-init}.el`).

## Why the pieces are shaped this way

**Two Emacses.** Termux Emacs is text-only (its build ships without image
support), so `preview-latex`'s inline overlays don't render there. The
native Android port (`org.gnu.emacs`) has librsvg/libjpeg/libtiff/cairo
compiled in — that's where the real Karthik experience lives. Termux Emacs
is kept as a keyboard-driven fallback that shells out to an external viewer.

**Shared UID.** The native Android Emacs and Termux run under the same
Android UID (`u0_a114`), so files under `/data/data/com.termux/files/…` are
readable/writable from the Emacs app. That's how the Emacs app runs
Termux's `pdflatex` binary and reads scratch `.tex` files. This only
works when both APKs are signed with the same key — that's why both
must be installed from the [Emacs Android port's SourceForge
project][port] (which ships a Termux APK re-signed with the Emacs
key), *not* F-Droid Termux + SourceForge Emacs.

[port]: https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/

**TeX Live layout.** The Termux `texlive-bin` package hardcodes
`TEXMFROOT=…/2026.0`, but `install-tl` writes the tree to `…/2026`. A
login shell fixes this by sourcing `/etc/profile.d/texlive.sh`; Android
Emacs doesn't, so `early-init.el` exports `TEXMFROOT` explicitly.

**PNG previews, not SVG.** `preview-image-type 'png'` is the only value
that works with `pdflatex → PDF` + Ghostscript out of the box. SVG would
require switching to DVI mode (`TeX-PDF-mode nil`) and forfeiting
hyperref/etc. PNG at scale 1.4 on 220 DPI looks crisp on e-ink.

**Bogus monitor size.** Android Emacs reports the frame's physical size
incorrectly (~3 meters wide), which makes `preview-get-dpi` compute ~9
DPI → invisible pixel-sized previews. `init.el` overrides `preview-get-dpi`
to derive DPI from `frame-char-height`, which also makes previews scale in
lockstep with the default face height and with `text-scale-adjust`.

**Package signatures.** GNU ELPA rotates its signing key; a fresh Emacs
often ships an older one. `early-init.el` sets `package-check-signature nil`
so bootstrap can pull `gnu-elpa-keyring-update`, which installs the current
key so verification can be re-enabled later.

**Macro folding.** `TeX-fold-mode` hides text-markup syntax behind
overlays — `\textbf{F}` displays as bold "F", `\emph{x}` as italic
"x", `\section{Foo}` as "Foo". Folding is strictly on-demand: buffers
open unfolded and nothing folds on insertion; `C-c p p` folds the
macro or environment markers at point (in math it previews instead,
and on an existing fold it unfolds), `C-c p b` folds the whole buffer
alongside previewing it, and `C-c p c` strips all folds and previews
while leaving syntax highlighting alone. Auto-reveal is TeX-fold's *own*
machinery (`TeX-fold-auto-reveal`, default = reveal on left/right/char
movement into the fold); `reveal-mode` doesn't participate because
fold overlays hide their contents via the `display` property, not the
`invisible` property that `reveal-mode` watches. `TeX-fold-type-list`
is `(env macro)` — deliberately *without* `math`: math folding would
substitute Unicode glyphs (π, ∫, …) that the document text font
doesn't contain, so they'd render as fallback tofu. Math stays as
source and uses `C-c p p` (preview-latex) for real rasterised previews.

**Buffer font follows the document — on demand.** `latex-font-sync.el`
remaps the buffer's `:family` to a TTF matching the document's declared
font package — `\usepackage{mathpazo}` → TeX Gyre Pagella,
`\usepackage{times}` → TeX Gyre Termes,
`\renewcommand{\rmdefault}{ppl}` → Pagella, and so on. Only
`:family` is remapped along with a relative `:height` factor that
compensates the serif font's smaller x-height (the global default face
is untouched), and previews keep scaling with the default face. Like
folding and previews, the font never changes on its own: buffers open
in the default code font, `C-c p b` applies the document font (as part
of entering document mode — the buffer-local `flow-latex-doc-mode`,
shown as ` Doc` in the mode line), and `C-c p c` reverts to the code
font.
While a buffer is opted in, re-sync fires on `C-c C-n`
(`TeX-normal-mode`, which re-parses the preamble) and on save (after
the AUCTeX auto-parse write hook already ran). Android Emacs's font
backend enumerates `$HOME/fonts` for `.ttf`/`.ttc` only (no OTF, no
fontconfig), so we ship TrueType conversions of the TeX Gyre + Latin
Modern OTFs under `android-emacs/fonts/`; `install.sh` symlinks them
into place, and Emacs picks them up on next launch.
The document-font remap is also what makes the folded-macro overlays
actually render bold/italic (Android's font backend doesn't pick a
bold variant for overlay display strings unless the buffer default has
been remapped first) — so folds made in raw-code mode show
regular-weight until `C-c p b`.

**Code font for markup.** With the buffer default remapped to a serif
document font, macro names (`\textbf`, `\begin`) and delimiters get lost
among styled content. `init.el` installs a second buffer-local remap
that pins the syntactic font-latex + font-lock faces (macro names,
braces, comments, env names, math delimiters) to a monospace family —
Droid Sans Mono by default, override with `my/latex-code-font-family`.
Content-styling faces (bold/italic/underline/sectioning/verbatim) are
deliberately left alone, so styled content stays in the doc font while
code stands apart at a glance.

## Deploying / reproducing

See [`DEPLOY.md`](./DEPLOY.md). The short version:

1. Install Termux and the Android Emacs port **both from the
   [SourceForge project][port]** so they share signing key (and thus UID).
2. Clone this repo on the tablet (any directory name works — the
   config finds the repo through its own symlinks; the existing install
   uses `~/boox-latex-setup/`).
3. `bash install.sh` — installs packages, symlinks configs, sets up TeX Live.
4. Do the manual steps listed in `DEPLOY.md` (grant storage, launch Emacs
   once, etc.).

## Working with the setup

- Open a scratch buffer: `latex-scratch` in Termux, or open a `.tex` in the
  Emacs app.
- Preview a formula: point on it, `C-c p p`.
- Preview whole buffer: `C-c p b`.
- Clear previews: `C-c p c`.
- Math notes: `notes-init` scaffolds a Stacks-style multi-chapter project
  (`~/math-notes` by default); references via RefTeX — `C-c )` to insert,
  `C-c &` to follow, `C-c =` for the TOC.
- Markdown: open any `.md`, `C-c p p` for the live preview beside it,
  `C-c p b` to see it in the browser.
- Deadlines: `C-c d d` the live agenda, `C-c d c` to capture, `C-c d s` to
  sync. Present only where the private `deadlines` repo is cloned.
- Full cheatsheet: [`CHEATSHEET.md`](./CHEATSHEET.md).

## Troubleshooting

Most gotchas are already documented as comments in the relevant file. In
short:

| Symptom | Look at |
| ------- | ------- |
| `pdflatex.fmt` not found | `TEXMFROOT` env in `android-emacs/early-init.el` |
| dvisvgm rejects PDF | `pkg install mupdf-tools` (Termux gs ≥10.01 needs mutool) |
| Overlay disappears / invisible | `preview-get-dpi` override in `core/flow-preview.el` |
| Org `C-c C-x C-l` fragment shrinks to a smudge (or `ulem.sty` not found) | `org--get-display-dpi` override in `core/flow-preview.el` — same bogus-DPI bug, separate fix. After changing DPI, delete the stale cache: `rm -rf /data/data/org.gnu.emacs/files/ltximg`. `ulem` is in install.sh's tlmgr list. |
| Startup hangs at "Connecting to melpa" | `package-refresh-contents` is now first-run only |
| Signature verify fails | `package-check-signature nil` in `early-init.el` |
| Buffer font didn't change after adding `\usepackage{mathpazo}` | `M-x my/latex-font-explain` — check "Resolved" line; if nil, the TTF isn't installed (restart Emacs after `install.sh`) |
| `pdflatex` fails with `Font OT1/ppl/… pplr7t not loadable` (or ptmr/pbkr/pncr/…) | Missing URW font metric package. Re-run `install.sh`, or `tlmgr install palatino times bookman ncntrsbk helvetic courier mathpazo zapfchan` |
| Preview fails with `pdf2dsc: command not found` | Termux ghostscript is at exactly 10.05.0 — the one release that dropped `pdf2dsc` (restored in 10.05.1). Upgrade: `pkg upgrade ghostscript` (or `pkg install ghostscript` after `pkg update`). |
| `M-o` undefined (ace-window not installed yet) | First launch after adding ace-window needs network once; if it was offline, reconnect and restart Emacs (or run `M-x package-install RET ace-window`) |
| Org previews don't auto-reveal source at point | org-fragtog not installed yet (its org hook is guarded, so nothing errors — the feature is just absent). First launch after adding it needs network once, or `M-x package-install RET org-fragtog`, then restart |
| `C-c p p` in a `.md` says "No Markdown converter installed" | Nothing from `flow-markdown-command-candidates` is on PATH — `sudo apt install pandoc` on the laptop, `pkg install pandoc` (or `cmark`) under Termux. Editing is unaffected either way. |
| `C-c d` undefined | The private `deadlines` repo isn't cloned on this device, so `core/flow-deadlines.el` no-ops by design. It needs an SSH key first — see `DEPLOY.md` "After install (manual)" item 6. |

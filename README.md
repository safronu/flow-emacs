# boox-latex-setup

LaTeX authoring environment for the **Onyx Boox Note Max** (13" Android 13
e-ink tablet), built as a portable adaptation of Karthik Chikmagalur's
["LaTeX Input for Impatient Scholars"][karthink] — fast math snippets, live
inline previews, minimal typing.

[karthink]: https://karthinks.com/software/latex-input-for-impatient-scholars/

## What this gives you

- **Native Android Emacs** (`org.gnu.emacs`) with real `preview-latex`
  inline overlays for every math snippet, sized to match your buffer text.
- **Termux Emacs** (`-nw`) as a fallback for terminal work, with an
  external-viewer preview flow (no image support in that Emacs build).
- **Termux TeX Live 2026** (`scheme-infraonly` + a few packages) providing
  `pdflatex`, `dvisvgm`, `mutool`, `gs`.
- **CDLaTeX + YaSnippet** for one-keystroke math (`mm`, `dm`, `fr`, `bmat`, …).
- A `latex-scratch` command that opens a scratch `.tex` file in Emacs.
- An optional `latex-preview-server` (Python HTTP) for browser preview.

## Repository layout

```
boox-latex-setup/
├── README.md                       This file — architecture & rationale
├── DEPLOY.md                       Step-by-step install on a fresh Boox
├── CLAUDE.md                       Context primer for Claude Code sessions
├── install.sh                      Idempotent deploy script
│
├── android-emacs/                  Native Android Emacs (org.gnu.emacs)
│   ├── early-init.el               PATH, TEXMFROOT, package-quickstart
│   ├── init.el                     AUCTeX + preview-latex + cdlatex + yas
│   ├── latex-font-sync.el          Buffer :family follows LaTeX font package
│   ├── latex-font-sync-tests.el    ERT tests for the above
│   ├── fonts/                      TTF conversions of TeX Gyre + Latin Modern
│   └── snippets/latex-mode/        mm, dm, sr, sb, ee
│
├── termux-emacs/                   Terminal Emacs (no image support)
│   ├── init.el                     External-viewer preview flow
│   └── snippets/latex-mode/
│
├── termux/                         Termux shell / installer files
│   ├── bashrc                      PATH, texlive.sh sourcing, aliases
│   └── texlive-basic.profile       install-tl profile (scheme-infraonly)
│
├── bin/                            Helper scripts on $PATH
│   ├── latex-scratch               Scratch .tex file + open in Emacs
│   └── latex-preview-server        HTTP preview server (Python)
│
└── scratch/                        Playground
    ├── CHEATSHEET.md               One-page keys reference
    └── test.tex                    Sanity test file with math
```

Every path under `~/` on the tablet that used to hold a config file is now
a **symlink into this repo**. Editing a file in this repo takes effect the
next time the relevant program is launched.

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

**Buffer font follows the document.** `latex-font-sync.el` remaps the
buffer's `:family` to a TTF matching the document's declared font package
— `\usepackage{mathpazo}` → TeX Gyre Pagella, `\usepackage{times}` → TeX
Gyre Termes, `\renewcommand{\rmdefault}{ppl}` → Pagella, and so on. Only
`:family` is remapped; `:height` stays global so previews keep scaling
with the default face. Android Emacs's font backend enumerates
`$HOME/fonts` for `.ttf`/`.ttc` only (no OTF, no fontconfig), so we ship
TrueType conversions of the TeX Gyre + Latin Modern OTFs under
`android-emacs/fonts/`; `install.sh` symlinks them into place, and Emacs
picks them up on next launch.

## Deploying / reproducing

See [`DEPLOY.md`](./DEPLOY.md). The short version:

1. Install Termux and the Android Emacs port **both from the
   [SourceForge project][port]** so they share signing key (and thus UID).
2. Clone this repo to `~/boox-latex-setup/`.
3. `bash install.sh` — installs packages, symlinks configs, sets up TeX Live.
4. Do the manual steps listed in `DEPLOY.md` (grant storage, launch Emacs
   once, etc.).

## Working with the setup

- Open a scratch buffer: `latex-scratch` in Termux, or open a `.tex` in the
  Emacs app.
- Preview a formula: point on it, `C-c p p`.
- Preview whole buffer: `C-c p b`.
- Clear previews: `C-c p c`.
- Full cheatsheet: [`scratch/CHEATSHEET.md`](./scratch/CHEATSHEET.md).

## Troubleshooting

Most gotchas are already documented as comments in the relevant file. In
short:

| Symptom | Look at |
| ------- | ------- |
| `pdflatex.fmt` not found | `TEXMFROOT` env in `android-emacs/early-init.el` |
| dvisvgm rejects PDF | `pkg install mupdf-tools` (Termux gs ≥10.01 needs mutool) |
| Overlay disappears / invisible | `preview-get-dpi` override in `android-emacs/init.el` |
| Startup hangs at "Connecting to melpa" | `package-refresh-contents` is now first-run only |
| Signature verify fails | `package-check-signature nil` in `early-init.el` |
| Buffer font didn't change after adding `\usepackage{mathpazo}` | `M-x my/latex-font-explain` — check "Resolved" line; if nil, the TTF isn't installed (restart Emacs after `install.sh`) |
| `pdflatex` fails with `Font OT1/ppl/… pplr7t not loadable` (or ptmr/pbkr/pncr/…) | Missing URW font metric package. Re-run `install.sh`, or `tlmgr install palatino times bookman ncntrsbk helvetic courier mathpazo zapfchan` |

# Context primer for Claude Code

Read this before helping the user with anything in this repo. It captures
non-obvious constraints of the environment that aren't visible from the
code alone.

## Architecture (read this first)

- **Three profiles, one core.** `core/` holds the shared `flow-*`
  modules; `android-emacs/`, `termux-emacs/`, `laptop-emacs/` are thin
  profiles that set the knobs declared in `core/flow-boot.el` and load
  modules with `flow-load`. Modules never sniff the machine — if
  behaviour must differ per device, add a knob in flow-boot and branch
  on it.
- **Only entry points are symlinked** into the live init paths. Each
  init.el finds the repo via `file-truename` of its own symlink
  (`flow-root`), so core modules and `core/snippets/` load straight
  from the working tree. Adding a core module needs no install step.
- The private `deadlines` repo (customer data) is loaded by
  `core/flow-deadlines.el` only if the checkout exists at the
  profile's declared path. Never vendor it here — this repo is
  publishable.

## Environment

- **Devices:** Onyx Boox Note Max — 13" Android 13 e-ink tablet (the
  next sections) — and a Xiaomi 15.6" Ubuntu 22.04 laptop (snap Emacs
  30, X build under XWayland; 3200x2000 panel whose X session reports
  96 DPI while really rendering near 2x that — same class of DPI lie
  as Android, handled by the same overrides in `core/flow-preview.el`).
- **Termux:** package name `com.termux`, standard `$PREFIX =
  /data/data/com.termux/files/usr`, home
  `/data/data/com.termux/files/home`.
- **Native Emacs:** package name `org.gnu.emacs`, HOME
  `/data/data/org.gnu.emacs/files/`, emacs-dir
  `/data/data/org.gnu.emacs/files/.emacs.d/`.
- **Same UID.** The two apps share Android UID (`u0_a114`) — files under
  either app's private dir are readable/writable from the other. This
  only works because **both** apps were installed from the [Emacs
  Android port on SourceForge][port] (`files/` for Emacs, `files/termux/`
  for a Termux APK re-signed with the Emacs key). F-Droid's Termux uses
  a different signing key and Android will refuse to share UID across
  keys. If you're ever unsure, `pm list packages -U | grep -E
  'termux|emacs'` — the UIDs must match.

[port]: https://sourceforge.net/projects/android-ports-for-gnu-emacs/
- **Termux Emacs has no image support** (verify with
  `M-x describe-variable RET image-types RET`). Only the native Emacs port
  can render inline images.

## LaTeX toolchain

- TeX Live 2026 installed via `install-tl` (**not** the Termux
  `texlive-bin` package alone) at `$PREFIX/share/texlive/2026/`.
- Termux's `pdflatex` binary hardcodes `TEXMFROOT=…/2026.0` — wrong. A
  login shell fixes this via `/etc/profile.d/texlive.sh`. Emacs doesn't
  source that; `android-emacs/early-init.el` exports `TEXMFROOT` manually.
- `dvisvgm`'s PDF mode requires `mutool` because Termux ships
  Ghostscript 10.07 (dvisvgm supports gs < 10.01 or mutool).
- **We use PNG for previews, not SVG.** `preview-image-type 'png'` is the
  only value that pairs with pdflatex+gs out of the box. `'dvisvgm'` is
  not a valid value — it silently no-ops the postprocessing. Do not try
  to "fix" this to SVG without also switching `TeX-PDF-mode` to nil.

## Preview sizing

- `preview-get-dpi` is **overridden** in `core/flow-preview.el`. The
  Android frame reports a bogus physical size (~3 meters wide), which
  makes the built-in DPI computation return ~9; the laptop's X session
  reports a 96-DPI-derived size that is ~2x off. We derive DPI from
  the default font's **em size** (`font-info` pixel size against the
  face point size — `flow-preview--base-dpi`), and multiply by
  `text-scale-mode-amount` so `C-x C-+/-` also resizes previews.
  NOT from `frame-char-height`: that is the LINE height (ascent +
  descent + leading), 1.34x the em for JetBrains Mono, and previews
  came out exactly that much bigger than the surrounding text until
  it was fixed. The em is what makes a 10pt formula glyph match a
  buffer glyph optically, like text and math match in the PDF.
- Do not restore the built-in `preview-get-dpi` — previews become
  invisible.
- `org--get-display-dpi` is overridden too (same bogus-mm bug hitting
  org's separate preview pipeline; also in `core/flow-preview.el`).
  It returns a plain NUMBER while `preview-get-dpi` returns a CONS —
  they serve different callers and are separate on purpose. Do not
  merge or "deduplicate" them, and do not restore either built-in.
  Org's preview cache does not key on DPI: after any DPI change,
  delete `/data/data/org.gnu.emacs/files/ltximg`.
  Org previews render via a custom `pdfpng` process — pdflatex+gs, a
  tight `standalone`-class snippet header (org's stock header is a full
  article page and gs cannot crop), transparent via pngalpha with
  `:background "Transparent"`, same resolution equation as AUCTeX
  preview. Sizing is fully automatic: `flow-org-latex-auto-scale`
  (advised before `org-latex-preview`) recomputes `:scale` =
  face-pt/10 × text-scale zoom on every render; `:scale` sits in the
  cache key, so font/zoom changes regenerate images with no cache
  deletion. There is no size knob — do not add one back.  `C-c p p/b/c`
  mirror the .tex preview keys in org buffers (bound in `org-mode-map`;
  org's `C-c C-x C-l` untouched).
- Org preview auto-toggle: `org-fragtog-mode`, enabled via the guarded
  `flow-org-fragtog-maybe` org-mode hook (MELPA package, in
  `core/flow-preview.el`, so android + laptop; Termux never loads that
  module). Clears a fragment's preview when point enters, re-runs
  `org-latex-preview` on exit — org's analogue of AUCTeX auto-reveal.
  It uses the normal `org-latex-preview` entry point, so whatever
  sizing setup is active applies. First render of a fragment is a
  synchronous compile (brief pause), then cached. The hook guard is
  deliberate (offline-failed install must not error on .org visits or
  block the cdlatex/yas hooks) — do not "simplify" it to a direct
  hook. If a future org-buffer type (e.g. an LLM chat) suffers from
  cursor-motion compiles or `$5`-style false math, scope it down with
  `org-fragtog-ignore-predicates` or `(org-fragtog-mode -1)` there.
  The Termux profile must never load `flow-preview` (no image support).

## Live compiled PDF

- `C-c p l` (`flow-latex-live-pdf`, core/flow-live-pdf.el) shows the
  real compiled PDF: `latexmk -pvc` when available, else pdflatex on
  save; pdf-tools if installed, else built-in doc-view + auto-revert.
  The target window is chosen via `aw-select` (ace-window labels +
  dispatch keys) — the prompt happens in the interactive call, BEFORE
  the compile starts; never prompt from the display timer, it polls
  for the PDF file and must not steal focus.  The Termux profile loads
  none of this (no images).

## Folding + buffer font

- `TeX-fold-mode` is on in every LaTeX buffer, and the buffer auto-folds
  on open.  `TeX-fold-type-list` is `(env macro)` — **not** `math`.
  Folding math substitutes Unicode glyphs (π, ∫) that the document text
  font (Latin Modern, Pagella, …) doesn't contain, so they render as
  tofu on Android.  Math stays as source; `C-c p p` previews it.
  Auto-reveal on point entry is TeX-fold's own machinery
  (`TeX-fold-auto-reveal`, default = reveal on left/right/char motion
  into the fold).  `reveal-mode` does NOT participate: fold overlays hide
  their contents via the `display` property, but `reveal-mode` only
  watches the `invisible` property.  The `(add-hook 'LaTeX-mode-hook
  #'reveal-mode)` line is essentially a no-op for folds; keep or delete
  as you like.
- `latex-font-sync-mode` is ON in the android and laptop profiles
  (enabled in each profile's init.el; `core/latex-font-sync.el`).  It
  remaps the buffer's default `:family` to a doc-matching TTF.  A
  non-obvious side effect: without this remap, Android's sfnt-android
  font backend doesn't pick a bold variant for TeX-fold overlay display
  strings, so `\textbf{X}` folds render regular-weight.  Turning font
  sync off breaks that visual, even though the fold text property still
  says `:weight bold`.  Don't disable it lightly.
- A second buffer-local face-remap in `core/flow-latex.el` pins syntactic faces
  (`font-latex-sedate-face`, `-warning-face`, `-math-face`,
  `-string-face`, `-script-char-face`, doctex-*, and the standard
  `font-lock-{keyword,comment,function-name,variable-name,constant,
  builtin,preprocessor}-face`) to a monospace family so markup stays
  legible against the serif document font.  Content-styling faces
  (bold/italic/underline/sectioning/sub-super/verbatim/type) are
  deliberately *not* remapped.  See `flow-latex-code-font-faces` in
  `core/flow-latex.el`.

## Package system quirks

- `package-check-signature` is set to `nil` in early-init because GNU
  ELPA rotates keys and fresh Emacs doesn't ship the current one.
  `gnu-elpa-keyring-update` is installed on first run to bring in the
  new key so verification can be re-enabled later.
- `package-quickstart` must be set in **early-init.el**, not init.el —
  otherwise it takes effect a launch later than expected.
- `package-refresh-contents` runs only on first-ever launch (when
  `use-package` isn't installed). Adding an unconditional refresh will
  hang startup on mobile networks — don't do it. To update, the user runs
  `M-x package-refresh-contents` manually.
- `package--quickstart-maybe-refresh` is `:override`-advised (in
  `core/flow-core.el`) to defer to `after-init-hook`. In Emacs 30,
  every `package-install` calls that function, which in turn calls
  `(package-initialize 'no-activate)` a second time — during init that
  triggers a spurious "Unnecessary call to `package-initialize' in
  init file" warning even though we never call it ourselves. Deferring
  the refresh moves the second `package-initialize` past
  `after-init-time` (silencing the check) and coalesces multi-install
  runs. Do not remove the advice.

## Telega / TDLib

- `telega.el` is installed on the native Android Emacs only (Termux
  Emacs has no image support — avatars/photos/stickers wouldn't render).
- `telega-server` links against **our own TDLib build**, not Termux's
  `libtd` package. Termux ships `libtd 1.8.50` and hasn't bumped it;
  telega ≥ 2026-01 requires ≥ 1.8.56 (master wants ≥ 1.8.66), and
  overriding the version check risks silent breakage on newer API
  calls. `install.sh` clones `github.com/tdlib/td` and installs to
  `~/.local/tdlib`; the elisp custom `telega-server-libs-prefix` in
  `android-emacs/init.el` hands that path to the server's Makefile
  via `LIBS_PREFIX` (produces `-I`, `-L`, and `-Wl,-rpath` flags).
  The build is a one-shot ~1–2 hours with peak ~1.5 GB/proc; `-j2`
  fits under this device's 6 GB RAM budget, `-j4` OOMs.
- Do NOT `pkg install libtd libtd-static`. It fights our custom install
  path on `LD_LIBRARY_PATH` and pkg-config lookups if you ever run
  `telega-server-build` without `LIBS_PREFIX`.

## Repo conventions

- Every user-visible config file lives inside this repo. The live
  locations (`~/.bashrc`, `~/.config/emacs/init.el`,
  `/data/data/org.gnu.emacs/files/.emacs.d/init.el`, `~/.local/bin/…`)
  are **symlinks** into the repo. Edit files in the repo, not through
  the symlinks.
- Exception: `notes-template/` is a *template*. `bin/notes-init` COPIES
  it to create a user notes project (default `~/math-notes`) — notes are
  content, not config, and are not symlinked back into this repo.
- Byte-compiled `.elc` files are gitignored — they're regenerated from
  source.
- No secrets are stored here — this repo can be published.

## Common Claude tasks and how to approach them

- **"Add a snippet."** Drop the file in `core/snippets/latex-mode/` —
  all three profiles read that one directory directly from the repo.
  Then `M-x yas-reload-all` in Emacs.
- **"Preview isn't working."** Ask which pipeline stage the log stops at:
  pdflatex, pdf2dsc, ghostscript, or overlay placement. See README's
  troubleshooting table for known failure modes.
- **"Deploy to a new device."** Follow `DEPLOY.md` step by step. Don't try
  to shortcut the manual steps (F-Droid install, permission grants) —
  they can't be automated.
- **"Change font size."** Edit `flow-font-height` in the device's
  profile init.el (startup value), or on the tablet use `C-c e f`
  (`my/eink-cycle-font-height` in `eink-faces.el`) at runtime. Previews
  follow automatically; already-rendered AUCTeX overlays need `C-c p c`
  + re-preview.

## Things not to do

- Don't restore `(package-initialize)` in init.el — Emacs ≥27 does it
  automatically; a duplicate call triggers a warning.
- Don't add an unconditional `(package-refresh-contents)` at startup.
- Don't change `preview-image-type` to `'dvisvgm'`.
- Don't remove the `TEXMFROOT` export from `early-init.el`.
- Don't move files out of the repo — the live setup is symlinked to
  paths inside this repo.
- Don't rename `android-emacs/`, `termux-emacs/`, or the entry files —
  the tablet's live symlinks point at those exact paths, and the local
  clone there is still named `boox-latex-setup` (the GitHub repo was
  renamed to `flow-emacs`; the directory name on a device is free).
- Don't put device conditionals inside core modules — add a knob in
  `core/flow-boot.el` and set it from the profiles instead.

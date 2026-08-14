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
  On top of that, `flow-preview-scale' (default 1.25) compensates for
  math fonts' small x-height (~0.43 em in Computer Modern vs ~0.53 em
  in JetBrains Mono) — but ONLY where the buffer actually shows the
  code font: org buffers always, .tex buffers only when latex-font-sync
  has not remapped to the document font (`flow-preview--optical-factor';
  previews are typeset by the document's own preamble, so in a synced
  buffer preview and text share a family and equal ems are already
  optically equal — applying the factor there OVERSIZES math, which is
  a bug we shipped once). Change the knob, not the call sites, or .tex
  and .org fragments drift apart.
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

## Markdown preview

- `core/flow-markdown.el` is loaded by ALL THREE profiles, Termux
  included — unlike `flow-preview`, it needs no image support: the
  preview is an eww *text* render of exported HTML.  Only `C-c p i`
  (inline images) is graphical, and it says so on a tty.
- The pipeline is markdown-mode's, not AUCTeX's: buffer → external
  converter (`markdown-command`) → HTML *fragment* → markdown-mode
  wraps it in a `<head>` (our stylesheet in
  `markdown-xhtml-header-content`) → written beside the source as
  `FOO.html` → eww.  **Never add `--standalone`**: markdown-mode adds
  its header only when the output does NOT match
  `markdown-xhtml-standalone-regexp`, so a full document silently
  drops our CSS.
- pandoc is invoked `--from=markdown`, NOT `--from=gfm`: the gfm reader
  is commonmark-based and rejects `tex_math_dollars` outright ("The
  extension tex_math_dollars is not supported for gfm"), which would
  leave `$x$` as literal text.  The `markdown` reader gives math, pipe
  tables, task lists and strikethrough together.
- Math is deliberately rendered two ways.  Default (eww): pandoc's
  plain HTML math, i.e. real `<sup>`/`<em>` that shr draws as raised
  superscripts.  `--mathml` is added ONLY for the browser render
  (`C-c p b`, `flow-markdown--mathml-command`) — in eww it is worse
  than useless: shr can't lay MathML out and prints pandoc's
  `<annotation>` copy of the TeX as well, so every formula appeared
  twice.
- The exported `FOO.html` is a real file in the source directory,
  deleted when the live preview is switched off
  (`markdown-live-preview-delete-export` = `delete-on-destroy`); a hard
  kill of Emacs mid-preview leaves it behind.
- `:config` in that use-package block is deferred (the `:mode` keyword
  makes markdown-mode autoload), so `markdown-command` and the `C-c p`
  keys only exist once a markdown buffer has been opened.  That is
  expected — don't "fix" it by forcing the package to load at startup.

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
  (enabled in each profile's init.el;
  `core/latex-font-sync/latex-font-sync.el`).  It
  remaps the buffer's default `:family` to a doc-matching TTF.  A
  non-obvious side effect: without this remap, Android's sfnt-android
  font backend doesn't pick a bold variant for TeX-fold overlay display
  strings, so `\textbf{X}` folds render regular-weight.  Turning font
  sync off breaks that visual, even though the fold text property still
  says `:weight bold`.  Don't disable it lightly.
- Font-sync detection reads the BUFFER'S OWN preamble first
  (`my/latex-font--scan-preamble-packages`) and only then AUCTeX's
  `LaTeX-provided-package-options`.  That order is a bug fix
  (2026-08-15), not an accident: AUCTeX registers parsed styles in the
  GLOBAL `TeX-style-hook-list` keyed by bare base name, so two open
  documents both named `test.tex` share one entry — the second one to
  load inherits the first one's (possibly stale `auto/*.el`) package
  list and `TeX-auto-apply` never re-parses it.  Symptom: a mathpazo
  document stuck on the Latin Modern fallback until a save re-parsed
  it.  Do not "simplify" detection back to the parse info alone.
- A second buffer-local face-remap in `core/flow-latex.el` pins syntactic faces
  (`font-latex-sedate-face`, `-warning-face`, `-math-face`,
  `-string-face`, `-script-char-face`, doctex-*, and the standard
  `font-lock-{keyword,comment,function-name,variable-name,constant,
  builtin,preprocessor}-face`) to a monospace family so markup stays
  legible against the serif document font.  Content-styling faces
  (bold/italic/underline/sectioning/sub-super/verbatim/type) are
  deliberately *not* remapped.  See `flow-latex-code-font-faces` in
  `core/flow-latex.el`.

## Page look (flow-page)

- `core/flow-page.el`, knob `flow-page` (laptop + android t, Termux
  nil and the module is never loaded there).  Buffer-local
  `flow-page-mode` on `LaTeX-mode-hook` adds ONE thing: visual
  \abovedisplayskip/\belowdisplayskip air around `\[...\]` and display
  environments — jit-lock-managed overlays tagged `'flow-page` putting
  `'line-spacing` on the newline before the opener and on the closer's
  newline.  Class metrics (`flow-page-class-metrics-alist`) were
  measured from real compiles — amsart a4 11pt (0.35 line) and article
  10pt (0.83 line); pt-size options, `\*shortskip` variants and `$$`
  are deliberately unsupported.
- The module began as a full "page look" (uniform \baselineskip
  leading via buffer `line-spacing` + mono scaled to fit the serif
  row, \textwidth column with fit-width/margins, \parindent overlays,
  fold-display-string restyling to the document serif) — all verified
  working, then **rolled back at the user's request on 2026-08-13**:
  in the usual half-screen split the extras read as wasted space.
  Only the display-math separation survived.  Don't reintroduce the
  rest without asking.
- Traps learned then, KEEP for any future overlay/metrics work here:
  (1) a relative face `:height` float STACKS per remapped face on the
  same char (math + sedate → 0.744² = 0.55 em) — use absolute heights;
  (2) `find-font`+`font-spec` opens at a degenerate size (px 1) for
  metrics — open `"FAMILY:pixelsize=32"` instead; (3) `font-info` of
  `(face-font 'default)` ALREADY includes the font-sync remap AND
  `text-scale-mode` (index 2 = em px, index 3 = ascent+descent) —
  never multiply by the zoom again; (4) overlay display strings do NOT
  see buffer face-remaps (folds render in the FRAME default family —
  restyling needs advice on `TeX-fold-hide-item` AND
  `TeX-fold-make-overlay`, the latter because `TeX-fold-verbs`/
  `-quotes` bypass hide-item on first fold); (5) an overlay carrying
  `'evaporate` must cover ≥1 char — zero-length self-deletes on the
  spot; (6) any width-fit must go through `text-scale-set`, never a
  private remap cookie, or preview sizing desyncs.

## Bundled fonts

- `android-emacs/fonts/` also carries **Demi** cuts, preferred by the
  android profile (`my/latex-font-user-candidates` in its init.el):
  regular LM/TeX Gyre hairlines wash out on e-ink, bold is squat.
  "Latin Modern Roman Demi" is LM's OFFICIAL demi weight, converted
  from TeX Live's OTF with `tools/otf2ttf.py`.  The TeX Gyre demis are
  SYNTHESIZED (`tools/embolden.py`: union of outline and its 20-unit
  stroke) — those families ship no real demi.
- `*.ttf` files are tracked normally (the blanket `*.ttf` gitignore was
  removed on 2026-08-15 — it only created a `git add -f` trap that had
  already silently dropped two probe fonts).
- **Deploying a new font file to the tablet takes THREE steps**: git
  pull, `bash install.sh` (creates the symlink — a pull alone updates
  only existing links' targets), and a FORCE-STOP of the Emacs app
  (fonts are scanned once per process; android-enumerate-fonts even
  errors if called twice).  Debug order when a family is missing:
  count files in /data/data/org.gnu.emacs/files/fonts/ FIRST, theorize
  never.  A missing-install.sh here once cost a full parser audit.
- Keep OS/2 usWeightClass at 400 on generated fonts; the grades are
  separate FAMILIES ("... Ink", "... Demi"), so the weight field
  carries nothing and standard values avoid any driver's weight-name
  mapping quirks (sfntfont.c keys weights off style-string tokens like
  "book"/"demibold" — family names are used verbatim).
- **Grade suffixes should not be font-style vocabulary.** The subtle
  grade was renamed "... Book" → "... Ink" on 2026-08-13 as defensive
  hygiene, NOT because the family failed to load: an `emacs -Q` probe
  verified the face `:family` path (the only path latex-font-sync and
  try-family use) matches and renders "Latin Modern Roman Book"
  correctly on the ftcrhb backend, and sfntfont.c matches families by
  exact string equality.  The hazard is name-STRING contexts only:
  `font.c` `font_parse_fcname` (used by `set-frame-font`, frame
  parameters, GTK-style names) treats a trailing "book" as a weight
  token (weight 80 = regular) and strips it, `fonts-conf(5)` lists
  "book" among fontconfig's style constants, and sfntfont.c's
  weight-token list has it too — so "Family Book" misparses in those
  contexts and muddies `fc-match` debugging.  ("Demi" is absent from
  the trailing-token lists — only "demibold" is in them.)  A
  try-family report of "no effect" for the preferred grade usually
  means the ladder already had the buffer in that grade — check
  `M-x flow-font-report`'s "font at point" before theorizing.  Before
  inventing a new suffix, check it against `weight_table` /
  `PROP_MATCH` lists in Emacs `src/font.c`, fontconfig's constants in
  `fonts-conf(5)`, and sfntfont.c's style tokens.
- Two traps learned converting: (1) fontTools keeps the source's
  `OTTO` sfnt tag; a glyf font in an OTTO wrapper is rejected before
  any table is read — set `sfntVersion` explicitly (otf2ttf.py does).
  (2) fontconfig caches a rejected file against its path; after fixing
  a font, reinstalling under the SAME filename can keep failing on the
  laptop — rename or clear the cache.  Android Emacs has no fontconfig
  (it scans `$HOME/fonts` itself), so only the laptop hits this.

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

## Claude Code CLI on the Boox (Termux)

- **Installed as a patched native binary, NOT via npm.**  Since 2.1.113
  the `@anthropic-ai/claude-code` npm package ships only a native glibc
  ELF — no Android target, no JS fallback — so it cannot run under
  Termux's bionic libc.  2.1.112 was the last pure-JS release.  The
  tablet was migrated off npm on 2026-08-14 and now runs the official
  linux-arm64 binary with its ELF interpreter repointed at Termux's
  glibc.
- Method: [`ferrumclaudepilgrim/claude-code-android`][cca].  `install.sh`
  is for a clean device; because an npm install was present here the
  script used was **`migrate.sh`** (`install.sh` detects npm and exits by
  design).  It refuses to run while any `claude` process is alive, so a
  Claude Code session **cannot upgrade itself** — the user runs it from a
  plain Termux shell.  The debugged prompt that drove that migration
  lived in `upgrade-claude-termux-prompt.md` (deleted 2026-08-15);
  recover it from git history if the device ever has to be redone.
- What is on disk now:
  - `$PREFIX/bin/claude` — a ~10 KB **bash wrapper** (same path the npm
    shim used), with `~/.local/bin/claude` symlinked to it.
  - `~/.local/share/claude/versions/<version>` — the real binaries
    (~320 MB each), plus `.verified`, `.blocklist`, `.last-update-check`.
    N−1 are kept for rollback.
  - glibc side: `glibc-repo`, `glibc-runner`, `patchelf-glibc` from the
    termux-glibc apt repo (`$PREFIX/etc/apt/sources.list.d/glibc.list`);
    the loader is `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`.
  - `~/claude-migration-backup-<timestamp>/` — migrate.sh's backup.
    `~/.claude` and `~/.claude.json` carried over untouched (auth intact).
- The wrapper **self-updates**: at most once per 24 h it asks the npm
  registry for the latest version number, downloads that binary from
  `downloads.claude.ai`, verifies SHA256 against the release
  `manifest.json`, patchelfs it, and smoke-tests it with `--init-only`
  before promoting it.  A binary that dies on a fatal signal is
  blocklisted and the previous version keeps running.  Nothing here needs
  a manual upgrade step; `claude --update-now` forces a check.
- **`LD_PRELOAD` is cleared for Claude Code and everything it spawns.**
  The wrapper does this deliberately (line ~222) — Termux's
  `libtermux-exec-ld-preload.so` is a bionic library and must not be
  preloaded into a glibc process.  The side effect is that termux-exec's
  shebang rewriting is inactive inside a Claude session, so
  `#!/usr/bin/env bash|python3` scripts fail with *"/usr/bin/env: bad
  interpreter"*.  Verified by walking `/proc/*/environ` up the process
  tree: the plain Termux login shell still has `LD_PRELOAD` set, only
  claude's descendants don't.  So this is **not** a device-wide
  regression — env shebangs still work when the user runs them by hand.
  Practical rule for a Claude session on this tablet: invoke
  `tools/otf2ttf.py` and `tools/embolden.py` as `python3 tools/...`, and
  any `#!/usr/bin/env bash` script as `bash script.sh`.  Repo scripts
  that already use the full `#!/data/data/com.termux/files/usr/bin/…`
  shebang (`install.sh`, `bin/latex-scratch`, `bin/notes-init`,
  `bin/latex-preview-server`) are unaffected — prefer that form for new
  scripts meant to run here.
- Claude Code's own DNS lookups are pinned to 8.8.8.8/8.8.4.4 by a
  `BUN_OPTIONS=--preload …/setdns.js` the wrapper injects.  The system
  resolver is untouched, but those lookups bypass a VPN or Pi-hole.
- If the patched binary ever segfaults or is SIGKILLed by the kernel's
  seccomp filter, the fallback is a `proot-distro` Ubuntu (~2 GB) running
  the normal `claude.ai/install.sh`.  Not needed so far.

[cca]: https://github.com/ferrumclaudepilgrim/claude-code-android

## gptel / LLM chat (laptop + native Android Emacs)

- `core/flow-gptel.el` (module, C-c g prefix) + `core/gptel-claude-code/`
  (our own gptel backend: `gptel-claude-code.el`, its tests, the
  recorded stream fixture, and `docs/`).  gptel itself comes
  from **MELPA**; the backend shells out to the local `claude` CLI in
  headless mode (subscription auth, no API keys, one `claude -p`
  process per request, stateless full-transcript replay).
- **Loaded by `laptop-emacs/` and `android-emacs/`** — the latter since
  2026-08-14, when the Termux migration finally put a working `claude`
  CLI on the Boox.  `termux-emacs/` does not load it (that profile is
  the minimal tty one).  Reachability across the app boundary is not a
  problem: `android-emacs/early-init.el` + `init.el` already put
  `/data/data/com.termux/files/usr/bin` on `exec-path` and `PATH` (for
  pdflatex/gs/tlmgr), and the shared UID makes another app's binary
  executable, so `executable-find` — what the backend uses — resolves it.
- **`flow-claude-config-dir` is what makes it work on Android**, and it
  is not optional.  Emacs's HOME there is the app's private dir, which
  has no `.claude`, while the CLI's login lives in Termux's `~/.claude`.
  Symptom without it: the CLI launches fine and *every* request fails
  with `Not logged in · Please run /login` — it looks like an auth
  problem, it is a HOME problem.  Measured on the device: a foreign HOME
  reproduces it exactly, and `CLAUDE_CONFIG_DIR` pointed at the Termux
  `~/.claude` fixes it with nothing else changed.  The knob lives in
  `core/flow-boot.el`, is set by the android profile, and `flow-gptel`
  turns it into a `setenv` at load (global is safe — nothing else reads
  that variable).  Exactly the same shape as `flow-deadlines-git-home`,
  which solves the same HOME mismatch for git's ssh keys; if a third
  subprocess ever needs Termux's home, follow that pattern rather than
  setting HOME wholesale.
- The backend replaces gptel's transport via advice on
  `gptel-curl-get-response`/`gptel--url-get-response` and reuses
  internal contracts (callback symbols, FSM transitions).  Verified
  against gptel-20260703, and again against **gptel-20260813.2132** on
  2026-08-14 (17/17 including the four live e2e, run with the Android
  HOME + `CLAUDE_CONFIG_DIR` to rehearse the tablet).  After
  `M-x package-refresh-contents` + gptel upgrade, run the ERT suite
  first, from the repo root:
  `emacs -Q --batch --eval '(package-initialize)' -L
  core/gptel-claude-code -l gptel-claude-code-tests.el -f
  ert-run-tests-batch-and-exit`
  (tests the installed elpa gptel; live e2e adds
  `GPTEL_CLAUDE_LIVE=1`, costs quota).
- **Running that suite from inside a Claude Code session on the Boox
  needs `env -u BUN_OPTIONS`.**  The wrapper exports
  `BUN_OPTIONS=--preload <relative>/setdns.js` computed against the cwd
  it was launched from, and re-appends whatever it inherits; a nested
  `claude` started in a different directory (the suite runs in a scratch
  temp dir) is handed that stale relative path and dies instantly with
  `preload not found "…/setdns.js"`, surfacing as FSM state `ERRS` and
  `:status "Claude Code startup error"`.  Nothing is wrong with the
  backend when this happens — it cost one wrong-premise "fix" already.
  Emacs launched from the Android launcher has no `BUN_OPTIONS`, so the
  real path is unaffected.  Note also that Emacs sets the child's `PWD`
  from `default-directory` itself (callproc.c); do not add code to do
  that.
- Streaming requires `gptel-use-curl` non-nil (the default) even
  though no curl runs — gptel's streaming gate consults it.  Don't
  "clean up" that variable for this backend.
- Emacs 30's bundled transient is too old for gptel's menu (missing
  `:environment` slot); the MELPA transient already installed in the
  laptop's elpa satisfies it.  A fresh machine gets it as a gptel
  dependency automatically.
- Chat buffers default to markdown-mode (gptel's own default; markdown
  preview keys apply).  Do NOT default them to org-mode without
  scoping org-fragtog first — see the org-fragtog note above.
- Reference documentation lives in `core/gptel-claude-code/docs/`
  (gptel requirements/architecture/implementation specs, the claude -p
  CLI spec, the implementation plan) and a development skill in
  `.claude/skills/gptel-claude-code/` loads it — invoke
  `/gptel-claude-code` before nontrivial work on the backend.  The
  gptel v0.9.9.5 source the docs' line numbers cite stays at
  `~/flow/gptel-headless/gptel/` (reference only, never on load-path).

## agent-shell / agentic coding (laptop only, for now)

- `core/flow-agent-shell.el` (module, C-c a prefix; `C-c a a` starts a
  Claude Code agent shell at the current project root, `C-c a d` at an
  explicitly chosen directory — project detection climbs to the git
  root, so `d` is how a repo SUBFOLDER is scoped).  agent-shell +
  acp.el + shell-maker, all MELPA.  The agentic complement to flow-gptel's chat: the agent edits
  files and runs commands, with per-action permission prompts and diff
  review in Emacs.  Only `laptop-emacs/` loads it today.
- **The agent process is NOT the `claude` binary.**  acp.el spawns the
  `claude-agent-acp` npm adapter (wraps the Claude Agent SDK, needs
  Node ≥ 22), which speaks ACP on stdio.  On the laptop
  `~/.local/bin/claude-agent-acp` is a hand-written wrapper pinning
  nvm's Node v22.14.0 — the nvm *default* is v16 and cannot run it, so
  don't "simplify" the wrapper away.  Adapter 0.59.0 verified by ACP
  initialize handshake on 2026-08-15.
- Auth is the CLI's subscription login
  (`agent-shell-anthropic-make-authentication :login t`), no API keys —
  same story as gptel; a login failure means run `claude` + `/login` in
  a terminal once.
- Knob `flow-claude-acp-command` (flow-boot) overrides the adapter
  argv; nil = agent-shell's default, resolved via `exec-path`.
  Reserved for the tablet phase: there the adapter must run under
  Termux's node (the patched glibc `claude` binary story does not cover
  the adapter — it's plain JS on bionic node, but whether the SDK it
  wraps can drive the patched CLI is UNVERIFIED), and
  `flow-claude-config-dir` applies exactly as it does for gptel.
- agent-shell was new to this config's elpa caches: pre-installed on
  the laptop 2026-08-15; any other machine needs one
  `M-x package-refresh-contents` before first load or the use-package
  ensure fails loudly at startup.

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
- **Don't `npm install`/`npm update`/`npm uninstall`
  `@anthropic-ai/claude-code` on the Boox.** The tablet's CLI is the
  patched native binary; npm ≥ 2.1.113 installs a glibc ELF that bionic
  cannot exec, and it would land on the same `$PREFIX/bin/claude` path,
  overwriting the wrapper. Upgrades are automatic — see the Claude Code
  section above.
- Don't put device conditionals inside core modules — add a knob in
  `core/flow-boot.el` and set it from the profiles instead.
- **Never byte-compile `init.el`/`early-init.el` at their live
  locations.** `load` tries `.elc` BEFORE `.el` and (with
  `load-prefer-newer` nil, which is where init loading happens) uses a
  stale `.elc` even when the source is newer — the device then runs a
  frozen config and ignores every `git pull`, while looking healthy.
  This actually happened on the Boox: a `flow-font-height` bump had "no
  effect" because a `batch-byte-compile` verification step (since
  removed from DEPLOY.md) had left an `init.elc` behind.  install.sh
  prunes these; `M-x flow-font-report` (flow-boot) diagnoses it — its
  `user-init-file` line ends in `.elc` when the trap is live.
  `flow-core` also sets `load-prefer-newer` t for everything loaded
  after init.

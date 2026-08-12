# Deployment guide (Boox tablet)

For the laptop, the whole guide is: clone this repo and run
`bash install-laptop.sh`.  Everything below is the tablet.

The repo was renamed `boox-latex-setup` → `flow-emacs` on GitHub; the
clone directory on a device can keep any name (the config finds the
repo through its own symlinks), so the existing tablet install stays at
`~/boox-latex-setup` untouched.

Reproduces the full LaTeX-on-Boox setup on a fresh device. Split into
**manual** steps (must be done by the user with a screen) and **automated**
steps (the `install.sh` script).

## Prerequisites (manual, one-time per device)

**Both apps must come from the same source (the Emacs Android port on
SourceForge).** Shared Android UID requires matching signing
certificates, and F-Droid's Termux is signed with F-Droid's key, which
is incompatible with the Emacs port's key. The SourceForge project
therefore ships its own Termux APK re-signed with the Emacs key.

1. **Install Termux** from the Emacs Android port's `termux/` folder:
   [android-ports-for-gnu-emacs/files/termux/][port-termux]. Do **not**
   use F-Droid or Play Store Termux — those won't share UID with the
   Emacs APK below. If you already have F-Droid Termux installed,
   uninstall it first (Android refuses to update across signing keys).
2. **Install the native Android Emacs port** — download
   `emacs-<version>-android.apk` from the [Emacs Android port
   page][port]. Because you installed the matching Termux in step 1,
   the two apps will share Android UID and can read/write each other's
   private files. Verify after install with `pm list packages -U | grep
   -E 'termux|emacs'` in Termux — both lines should show the same UID.
3. **Launch each app once** so Android provisions their private
   filesystems (`/data/data/com.termux/files/…`, `/data/data/org.gnu.emacs/files/…`).
4. In Termux, allow storage access if you want to browse `/sdcard/`:
   `termux-setup-storage` and grant the permission dialog.
5. Give Termux **wake lock** in its notification (long-press → Acquire
   wake lock) so long installs don't get killed when the screen sleeps.
6. **Disable Android's phantom process killer** *before* running
   `install.sh` or any long-lived Emacs session. Android 12 and 13
   silently enforce a global limit of 32 non-app "child" processes per
   UID; anything beyond it is killed with SIGKILL (signal 9). TeX
   Live's `install-tl` easily spawns more than 32 helper processes,
   and Emacs's package-refresh + byte-compile flurry can do the same.
   The wake lock does **not** protect against this — it only prevents
   the CPU governor from sleeping. From `adb shell` on a paired
   computer (this cannot be set from inside the device), run:

   ```
   adb shell "settings put global settings_enable_monitor_phantom_procs false"
   ```

   The setting persists across reboots on Android 13. Without it,
   `install.sh` will occasionally exit mid-way with mysterious
   `Killed` messages or leave a half-populated `~/.texlive2026/`
   directory.

[port]: https://sourceforge.net/projects/android-ports-for-gnu-emacs/
[port-termux]: https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/

## Automated install

From Termux:

```bash
cd ~
git clone <this repo> boox-latex-setup
cd boox-latex-setup
bash install.sh
```

`install.sh` is idempotent — safe to re-run. It:

1. Installs Termux packages: `emacs`, `git`, `perl`, `python`, `wget`,
   `ghostscript`, `mupdf-tools`, `texlive-bin`, `texlive-installer`
   (the last one ships `/etc/profile.d/texlive.sh`, which puts the
   right `TEXMFROOT=…/2026` into every login shell).
2. Downloads and installs **TeX Live 2026 scheme-infraonly** via
   `install-tl -profile termux/texlive-basic.profile` (≈ 300 MB, 10–30 min).
3. Installs the extra TeX packages we need: LaTeX kernel + preview-latex
   runtime + font families (`latex-bin`, `amsmath`, `amsfonts`,
   `mathtools`, `standalone`, `varwidth`, `cm-super`, `psnfss`, `ulem`,
   `tools`, `hyperref`, `amscls`,
   `mylatex`, `preview`, `pgf`, `xkeyval`, `tex-gyre`, `tex-gyre-math`,
   `lm`, `lm-math`, `palatino`, `mathpazo`, `times`, `bookman`,
   `ncntrsbk`, `zapfchan`, `helvetic`, `courier`, `newtx`, `newpx`,
   `kpfonts`, `pxfonts`, `fpl`).
4. **Builds TDLib** from `github.com/tdlib/td` (master branch) into
   `~/.local/tdlib` if the native Emacs app is present and TDLib is not
   already at ≥ 1.8.66 there. This is a **1–2 hour compile** on the
   Boox Note Max (peak RAM ~1.5 GB per process, `-j2`, ~5 GB disk under
   `~/src/tdlib`). Termux's `libtd` package is stuck at 1.8.50, which
   no current telega.el can talk to — hence the source build. Skip with
   `SKIP_TELEGA=1 bash install.sh` if you don't want telega. Re-runs of
   `install.sh` skip the build unless upstream moved past what's installed.
5. Symlinks every config file from this repo to its live location
   (`~/.bashrc`, `~/.config/emacs/…`, `/data/data/org.gnu.emacs/files/.emacs.d/…`,
   `~/.local/bin/…`).
6. Creates `~/latex-scratch/` and symlinks `test.tex` + `CHEATSHEET.md`
   in from `scratch/`.
7. Creates convenience symlinks so the Android Emacs app can reach Termux
   files: `~/latex-scratch` and `~/termux-home` in its HOME.

## After install (manual)

1. **Launch Android Emacs**. First launch bootstraps MELPA + installs
   `use-package`, `auctex`, `cdlatex`, `yasnippet`, `ace-window` (+ `avy`
   as its dependency), `org-fragtog`, `gnu-elpa-keyring-update`, and
   `telega`. Takes a few minutes on Wi-Fi, and you'll see byte-compile
   output scroll for each package — that's normal. Subsequent launches
   skip the network.
2. Open the test file: `C-x C-f ~/latex-scratch/test.tex RET`.
3. Point on `$ e^{i\pi} + 1 = 0 $` → `C-c p p`. Expect an inline PNG overlay.
4. If it hangs on "Connecting to melpa", you're on a very slow connection —
   let it finish once, or force-close and reopen (bootstrap will retry).
5. **Telegram (optional):** `M-x telega-server-build` once. It links
   against the TDLib built in step 4 of the automated phase — the elisp
   custom `telega-server-libs-prefix` (set in `android-emacs/init.el` to
   `~/.local/tdlib`) drives the server's `Makefile` to `-I` / `-L` /
   `-Wl,-rpath` that prefix. Binary lands at `~/.telega/telega-server`.
   Then `M-x telega` and sign in (phone number → SMS code, or QR from
   another logged-in Telegram client). Auth state persists under
   `~/.telega/`.

## Verification checklist

Run in Termux:

```bash
source ~/.bashrc
command -v pdflatex dvisvgm mutool gs latex-scratch notes-init  # all should print paths
kpsewhich -var-value=TEXMFROOT                                # ends in /2026, NOT /2026.0
kpsewhich pdflatex.fmt                                        # must return a path
pdflatex -version | head -1                                   # TeX Live 2026/Termux
test ! -d ~/.emacs.d                                          # MUST NOT exist on the
                                                              # Termux side: if ~/.emacs.d
                                                              # is present, Termux Emacs
                                                              # loads that and silently
                                                              # ignores ~/.config/emacs
                                                              # (this repo's live location)
```

Byte-compile the Emacs configs (should be silent):

```bash
emacs -Q --batch -f batch-byte-compile \
  /data/data/org.gnu.emacs/files/.emacs.d/init.el \
  /data/data/org.gnu.emacs/files/.emacs.d/early-init.el 2>&1 | grep -iE 'error|multiple'
```

## What can't be automated

- **Downloading APKs.** SourceForge downloads require the browser UI.
- **Granting Android permissions.** Storage, wake-lock, and the initial
  "allow install" dialogs must be tapped by hand.
- **Matching signing keys.** Shared UID depends on the Termux and Emacs
  APKs being signed with the same key — you can't change signatures
  after install. If they don't match at install time, uninstall and
  reinstall from the SourceForge project's `termux/` folder.
- **Wi-Fi.** Both `install-tl` and the first Emacs launch need network;
  offline install is possible but not covered here.

## Uninstall / rollback

The install script never overwrites without symlinking, so removing the
repo and its symlinks is enough:

```bash
find /data/data/com.termux/files/home /data/data/org.gnu.emacs/files \
     -lname '*boox-latex-setup*' -delete
rm -rf ~/boox-latex-setup
```

To also remove TeX Live: `rm -rf $PREFIX/share/texlive/2026 ~/.texlive2026`.

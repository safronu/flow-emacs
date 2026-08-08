# Deployment guide

Reproduces the full LaTeX-on-Boox setup on a fresh device. Split into
**manual** steps (must be done by the user with a screen) and **automated**
steps (the `install.sh` script).

## Prerequisites (manual, one-time per device)

1. **Install Termux** from F-Droid (not Play Store — the Play version is
   frozen). Version ≥ 0.118.
2. **Install the native Android Emacs port** — build or download
   `org.gnu.emacs.apk` from the [Emacs Android port page][port].
   Recent builds share the same Android UID as Termux, which is what lets
   the two apps see each other's files. If your build uses a different
   UID you'll need to grant explicit access or fall back to
   `/sdcard/Documents` as the shared workspace.
3. **Launch each app once** so Android provisions their private
   filesystems (`/data/data/com.termux/files/…`, `/data/data/org.gnu.emacs/files/…`).
4. In Termux, allow storage access if you want to browse `/sdcard/`:
   `termux-setup-storage` and grant the permission dialog.
5. Give Termux **wake lock** in its notification (long-press → Acquire
   wake lock) so long installs don't get killed when the screen sleeps.

[port]: https://sourceforge.net/projects/android-ports-for-gnu-emacs/

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
   `ghostscript`, `mupdf-tools`.
2. Downloads and installs **TeX Live 2026 scheme-infraonly** via
   `install-tl -profile termux/texlive-basic.profile` (≈ 300 MB, 10–30 min).
3. Installs the extra TeX packages preview-latex needs
   (`mylatex`, `preview`, `pgf`, `xkeyval`).
4. Symlinks every config file from this repo to its live location
   (`~/.bashrc`, `~/.config/emacs/…`, `/data/data/org.gnu.emacs/files/.emacs.d/…`,
   `~/.local/bin/…`).
5. Creates `~/latex-scratch/` and symlinks `test.tex` + `CHEATSHEET.md`
   in from `scratch/`.
6. Creates convenience symlinks so the Android Emacs app can reach Termux
   files: `~/latex-scratch` and `~/termux-home` in its HOME.

## After install (manual)

1. **Launch Android Emacs**. First launch bootstraps MELPA + installs
   `use-package`, `auctex`, `cdlatex`, `yasnippet`, `gnu-elpa-keyring-update`.
   Takes a few minutes on Wi-Fi. Subsequent launches skip the network.
2. Open the test file: `C-x C-f ~/latex-scratch/test.tex RET`.
3. Point on `$ e^{i\pi} + 1 = 0 $` → `C-c p p`. Expect an inline PNG overlay.
4. If it hangs on "Connecting to melpa", you're on a very slow connection —
   let it finish once, or force-close and reopen (bootstrap will retry).

## Verification checklist

Run in Termux:

```bash
source ~/.bashrc
command -v pdflatex dvisvgm mutool gs latex-scratch          # all should print paths
kpsewhich -var-value=TEXMFROOT                                # ends in /2026, NOT /2026.0
kpsewhich pdflatex.fmt                                        # must return a path
pdflatex -version | head -1                                   # TeX Live 2026/Termux
```

Byte-compile the Emacs configs (should be silent):

```bash
emacs -Q --batch -f batch-byte-compile \
  /data/data/org.gnu.emacs/files/.emacs.d/init.el \
  /data/data/org.gnu.emacs/files/.emacs.d/early-init.el 2>&1 | grep -iE 'error|multiple'
```

## What can't be automated

- **Downloading APKs.** F-Droid / SourceForge downloads require the Play/
  browser UI.
- **Granting Android permissions.** Storage, wake-lock, and the initial
  "allow install" dialogs must be tapped by hand.
- **Sharing the UID.** Whether the Emacs APK you install shares UID with
  Termux depends on the APK's manifest — you can't change it after install.
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

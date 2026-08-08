#!/data/data/com.termux/files/usr/bin/bash
# install.sh — idempotent deployer for boox-latex-setup.
#
# Run from Termux, from the repo root:
#   cd ~/boox-latex-setup && bash install.sh
#
# What it does:
#   1. Installs Termux packages (emacs, git, perl, python, ghostscript,
#      mupdf-tools).
#   2. Installs TeX Live 2026 scheme-infraonly if not already present,
#      then adds the packages preview-latex needs (mylatex, preview,
#      pgf, xkeyval).
#   3. Symlinks every config file from this repo to its live location.
#   4. Sets up the scratch dir and Android-Emacs-side symlinks.
#
# What it does NOT do:
#   * Install APKs (Termux, Android Emacs) — manual.
#   * Grant Android permissions — manual.
#   * Launch Emacs for the first-run MELPA bootstrap — user does it.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
HOME_="${HOME:-/data/data/com.termux/files/home}"
PREFIX_="${PREFIX:-/data/data/com.termux/files/usr}"
ANDROID_EMACS_HOME="/data/data/org.gnu.emacs/files"
ANDROID_EMACS_D="${ANDROID_EMACS_HOME}/.emacs.d"

log() { printf '[install] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── 1. Termux packages ────────────────────────────────────────────────────
log "Installing Termux packages"
pkg install -y emacs git perl python wget ghostscript mupdf-tools

# ── 2. TeX Live ───────────────────────────────────────────────────────────
TL_YEAR=2026
TL_ROOT="${PREFIX_}/share/texlive/${TL_YEAR}"

if [ ! -x "${PREFIX_}/bin/texlive/pdflatex" ] || [ ! -d "${TL_ROOT}" ]; then
    log "Installing TeX Live ${TL_YEAR} scheme-infraonly (this takes a while)"
    # Symlink the install profile into HOME so install-tl can find it by name.
    ln -sfn "${REPO}/termux/texlive-basic.profile" "${HOME_}/.texlive-basic.profile"
    TMP="$(mktemp -d)"
    cd "${TMP}"
    wget -q https://mirrors.mit.edu/CTAN/systems/texlive/tlnet/install-tl-unx.tar.gz
    tar xzf install-tl-unx.tar.gz
    cd install-tl-*
    ./install-tl -profile "${HOME_}/.texlive-basic.profile" \
                 -repository https://mirrors.mit.edu/CTAN/systems/texlive/tlnet
    cd "${HOME_}" && rm -rf "${TMP}"
    # Regenerate format symlinks in case texlinks didn't run.
    "${PREFIX_}/bin/texlive/texlinks" || true
else
    log "TeX Live already installed at ${TL_ROOT} — skipping"
fi

# The extra packages preview-latex + our config assume.
if have tlmgr; then
    log "Ensuring extra TeX packages: mylatex preview pgf xkeyval"
    # shellcheck disable=SC1091
    . "${PREFIX_}/etc/profile.d/texlive.sh" 2>/dev/null || true
    tlmgr install mylatex preview pgf xkeyval 2>&1 | tail -5 || true
fi

# ── 3. Symlink configs into live locations ────────────────────────────────
link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] || [ ! -e "$dst" ]; then
        ln -sfn "$src" "$dst"
    else
        log "backup: $dst → $dst.bak"
        mv "$dst" "$dst.bak"
        ln -sfn "$src" "$dst"
    fi
}

log "Linking Termux shell config"
link "${REPO}/termux/bashrc"                "${HOME_}/.bashrc"
link "${REPO}/termux/texlive-basic.profile" "${HOME_}/.texlive-basic.profile"

log "Linking helper binaries onto ~/.local/bin"
link "${REPO}/bin/latex-scratch"         "${HOME_}/.local/bin/latex-scratch"
link "${REPO}/bin/latex-preview-server"  "${HOME_}/.local/bin/latex-preview-server"
chmod +x "${REPO}/bin/"*

log "Linking Termux Emacs config"
link "${REPO}/termux-emacs/init.el" "${HOME_}/.config/emacs/init.el"
for s in mm dm sr sb ee; do
    link "${REPO}/termux-emacs/snippets/latex-mode/$s" \
         "${HOME_}/.config/emacs/snippets/latex-mode/$s"
done

if [ -d "${ANDROID_EMACS_HOME}" ]; then
    log "Linking Android Emacs config"
    link "${REPO}/android-emacs/early-init.el" "${ANDROID_EMACS_D}/early-init.el"
    link "${REPO}/android-emacs/init.el"       "${ANDROID_EMACS_D}/init.el"
    for s in mm dm sr sb ee; do
        link "${REPO}/android-emacs/snippets/latex-mode/$s" \
             "${ANDROID_EMACS_D}/snippets/latex-mode/$s"
    done
    # Convenience symlinks so C-x C-f in the Emacs app reaches Termux files.
    link "${HOME_}"                    "${ANDROID_EMACS_HOME}/termux-home"
    link "${HOME_}/latex-scratch"      "${ANDROID_EMACS_HOME}/latex-scratch"
else
    log "Android Emacs not installed (${ANDROID_EMACS_HOME} missing) — skipping"
fi

# ── 4. Scratch playground ─────────────────────────────────────────────────
log "Setting up ~/latex-scratch"
mkdir -p "${HOME_}/latex-scratch"
link "${REPO}/scratch/test.tex"      "${HOME_}/latex-scratch/test.tex"
link "${REPO}/scratch/CHEATSHEET.md" "${HOME_}/latex-scratch/README.md"

log "Done."
cat <<EOF

Next steps (manual):
  1. Launch the native Emacs app on the Boox. First run will fetch MELPA
     and install auctex, cdlatex, yasnippet, gnu-elpa-keyring-update.
  2. Open ~/latex-scratch/test.tex; put point in a \$…\$ formula; press
     'C-c p p' to preview inline.
  3. See scratch/CHEATSHEET.md for keys.
EOF

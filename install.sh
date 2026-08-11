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
#      then adds the LaTeX kernel + preview-latex runtime + the font
#      families latex-font-sync knows about (latex-bin, amsmath, amsfonts,
#      mathtools, standalone, varwidth, cm-super, psnfss, ulem, tools,
#      hyperref, amscls, mylatex,
#      preview, pgf, xkeyval, tex-gyre*, lm*, palatino, mathpazo, times,
#      bookman, ncntrsbk, zapfchan, helvetic, courier, newtx, newpx,
#      kpfonts, pxfonts, fpl).
#   3. Symlinks every config file from this repo to its live location.
#   4. Sets up the scratch dir and Android-Emacs-side symlinks.
#
# What it does NOT do:
#   * Install APKs — manual. Both Termux and Emacs must come from the
#     Emacs Android port on SourceForge (files/termux/ and files/), so
#     they share signing key and thus Android UID. F-Droid Termux won't
#     work — different signing key means no shared UID.
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
pkg install -y emacs git perl python wget ghostscript mupdf-tools texlive-bin texlive-installer

# ── 2. TeX Live ───────────────────────────────────────────────────────────
TL_YEAR=2026
TL_ROOT="${PREFIX_}/share/texlive/${TL_YEAR}"

if [ ! -d "${TL_ROOT}" ]; then
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

# Extra TeX packages our config assumes.
#   latex-bin — LaTeX kernel + pdflatex.fmt (scheme-infraonly ships
#     neither; without this `pdflatex' has nothing to load).
#   amsmath / amsfonts / mathtools — standard math extensions; amsfonts
#     provides `amssymb.sty' referenced by test.tex and the preview preamble.
#   standalone / varwidth — the previewer's wrapper class in
#     termux-emacs/init.el (`\documentclass[varwidth]{standalone}');
#     `standalone' does NOT pull `varwidth', so it must be listed.
#   cm-super — Type-1 outlines for Computer Modern at T1 encoding; without
#     it pdflatex falls back to bitmap PK fonts and previews come out fuzzy.
#   psnfss — provides `mathpazo.sty', `times.sty', `helvet.sty',
#     `courier.sty' etc. (the .sty wrappers around the URW font metrics).
#   tools — `xr.sty' (cross-document \externaldocument references for the
#     Stacks-style notes; xr v6+ absorbed the old xr-hyper) plus multicol
#     and the other LaTeX "required tools".
#   hyperref — clickable \ref/\cite links in output PDFs (notes preamble).
#   amscls — `amsart.cls' + `amsthm.sty' (theorem environments; NOT part
#     of amsmath).
#   ulem — required by org-mode's LaTeX-preview preamble
#     (org-latex-default-packages-alist ships \usepackage[normalem]{ulem}
#     with the snippet flag, so C-c C-x C-l compiles fail without it).
#   preview / mylatex / pgf / xkeyval — preview-latex runtime.
#   tex-gyre / tex-gyre-math / lm / lm-math — Latin Modern + TeX Gyre
#     outlines, used to derive the bundled TTFs and also referenced from
#     documents.
#   palatino / mathpazo / times / bookman / ncntrsbk / zapfchan / helvetic
#     / courier — URW clones of the standard 35 PS fonts. `scheme-infraonly'
#     ships only `symbol' and `zapfding', so `\usepackage{mathpazo}' etc.
#     fail with "TFM pplr7t not loadable" until these are added. Package
#     names match the intended-family keys in `latex-font-sync.el'.
#   newtx / newpx / kpfonts / pxfonts / fpl — modern math+text bundles
#     also recognised by `latex-font-sync.el'.
if have tlmgr; then
    log "Ensuring extra TeX packages (LaTeX kernel + preview + font families)"
    # shellcheck disable=SC1091
    . "${PREFIX_}/etc/profile.d/texlive.sh" 2>/dev/null || true
    tlmgr install \
        latex-bin amsmath amsfonts mathtools standalone varwidth cm-super psnfss \
        ulem \
        tools hyperref amscls \
        mylatex preview pgf xkeyval \
        tex-gyre tex-gyre-math lm lm-math \
        palatino mathpazo times bookman ncntrsbk zapfchan helvetic courier \
        newtx newpx kpfonts pxfonts fpl \
        2>&1 | tail -5 || true
    # tlmgr chains updmap-sys after `install', but a single missing
    # package in the list (e.g. a bad name) makes the whole run exit
    # non-zero and skip the map rebuild.  Without the map rebuild
    # pdftex loads the new fonts' TFMs but can't find their PFBs, so
    # math extension glyphs (`\pi', `\int', …) render as empty boxes.
    # Force the rebuild unconditionally.
    log "Rebuilding font maps (updmap-sys)"
    updmap-sys 2>&1 | tail -3 || true
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
link "${REPO}/bin/notes-init"            "${HOME_}/.local/bin/notes-init"
chmod +x "${REPO}/bin/"*

log "Linking Termux Emacs config"
link "${REPO}/termux-emacs/init.el" "${HOME_}/.config/emacs/init.el"
for s in mm dm sr sb ee; do
    link "${REPO}/termux-emacs/snippets/latex-mode/$s" \
         "${HOME_}/.config/emacs/snippets/latex-mode/$s"
done

if [ -d "${ANDROID_EMACS_HOME}" ]; then
    log "Linking Android Emacs config"
    link "${REPO}/android-emacs/early-init.el"        "${ANDROID_EMACS_D}/early-init.el"
    link "${REPO}/android-emacs/init.el"              "${ANDROID_EMACS_D}/init.el"
    link "${REPO}/android-emacs/latex-font-sync.el"   "${ANDROID_EMACS_D}/latex-font-sync.el"
    for s in mm dm sr sb ee; do
        link "${REPO}/android-emacs/snippets/latex-mode/$s" \
             "${ANDROID_EMACS_D}/snippets/latex-mode/$s"
    done
    # Convenience symlinks so C-x C-f in the Emacs app reaches Termux files.
    link "${HOME_}"                    "${ANDROID_EMACS_HOME}/termux-home"
    link "${HOME_}/latex-scratch"      "${ANDROID_EMACS_HOME}/latex-scratch"

    # TTF fonts for latex-font-sync. Android Emacs enumerates $HOME/fonts/
    # for .ttf/.ttc only (no OpenType, no fontconfig) — so we ship
    # TrueType-converted TeX Gyre + Latin Modern here. Emacs picks these up
    # only on next launch.
    mkdir -p "${ANDROID_EMACS_HOME}/fonts"
    for f in "${REPO}/android-emacs/fonts/"*.ttf; do
        [ -e "$f" ] && link "$f" "${ANDROID_EMACS_HOME}/fonts/$(basename "$f")"
    done
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
     and install auctex, cdlatex, yasnippet, ace-window (+ avy dep),
     org-fragtog, gnu-elpa-keyring-update.
  2. Open ~/latex-scratch/test.tex; put point in a \$…\$ formula; press
     'C-c p p' to preview inline.
  3. See scratch/CHEATSHEET.md for keys.
EOF

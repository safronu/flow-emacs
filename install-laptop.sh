#!/usr/bin/env bash
# install-laptop.sh — idempotent deployer for the LAPTOP profile.
#
# Run from the repo root on the laptop:
#   cd ~/flow/flow-emacs && bash install-laptop.sh
#
# What it does:
#   1. apt-installs TeX Live (recommended + extra), preview-latex's style
#      file, and JetBrains Mono.  Uses sudo — you'll be prompted once.
#   2. Backs up any real ~/.emacs.d/{init,early-init}.el, then symlinks
#      them to laptop-emacs/ in this repo.
#
# Only the entry points are linked: init.el resolves its own symlink to
# find the repo and loads everything else (core modules, snippets)
# straight from the working tree, so a `git pull` is a complete update.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
EMACS_D="${HOME}/.emacs.d"

log() { printf '[install] %s\n' "$*"; }

# ── 1. System packages ────────────────────────────────────────────────────
# texlive-latex-recommended  amsmath, standalone/varwidth, psnfss wrappers
# texlive-latex-extra        csquotes/enquote, tcolorbox, the long tail
# texlive-fonts-recommended  URW 35 clones (mathpazo/times/… metrics+outlines)
# texlive-fonts-extra is NOT pulled (multi-GB); add later if a doc needs it.
# texlive-science            mathtools and friends
# preview-latex-style        preview.sty for AUCTeX inline overlays
# fonts-jetbrains-mono       same buffer font as the tablet
# pandoc                     Markdown -> HTML for the .md preview (C-c p p)
NEEDED=()
for p in texlive-latex-recommended texlive-latex-extra \
         texlive-fonts-recommended texlive-science \
         preview-latex-style ghostscript fonts-jetbrains-mono pandoc; do
    dpkg -s "$p" >/dev/null 2>&1 || NEEDED+=("$p")
done
if [ "${#NEEDED[@]}" -gt 0 ]; then
    log "Installing: ${NEEDED[*]}"
    sudo apt-get install -y "${NEEDED[@]}"
else
    log "System packages already installed — skipping"
fi

# ── 2. Symlink the Emacs entry points ─────────────────────────────────────
link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] || [ ! -e "$dst" ]; then
        ln -sfn "$src" "$dst"
    else
        log "backup: $dst -> $dst.bak"
        mv "$dst" "$dst.bak"
        ln -sfn "$src" "$dst"
    fi
}

log "Linking laptop Emacs config into ${EMACS_D}"
link "${REPO}/laptop-emacs/init.el"       "${EMACS_D}/init.el"
link "${REPO}/laptop-emacs/early-init.el" "${EMACS_D}/early-init.el"

log "Done."
cat <<'EOF'

Next steps:
  1. Start Emacs.  First launch fetches MELPA and installs auctex,
     cdlatex, yasnippet, ace-window, org-fragtog — give it a minute.
  2. Open a .tex file with some $math$; C-c p p previews it inline.
  3. If you keep the deadlines repo, clone it to ~/flow/deadlines and
     restart — C-c d comes alive by itself.
EOF

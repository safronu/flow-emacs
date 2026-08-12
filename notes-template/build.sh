#!/data/data/com.termux/files/usr/bin/bash
# build.sh — recompile chapters.  Two pdflatex passes per chapter (TOC+refs).
#
#   ./build.sh              chapters whose .tex (or preamble.tex) changed
#   ./build.sh groups sets  these chapters, rebuilt UNCONDITIONALLY
#
# Cross-chapter \ref's read the OTHER chapter's .aux file, so they can go
# stale but never break the build.  After rebuilding chapter B, refresh a
# chapter that cites it by naming it:  ./build.sh <citing-chapter>
# (named chapters skip the timestamp check on purpose).
set -u
shopt -s nullglob
cd "$(dirname "$0")"
# shellcheck disable=SC1091
. "${PREFIX:-/data/data/com.termux/files/usr}/etc/profile.d/texlive.sh" 2>/dev/null || true

force=0
chapters=("$@")
if [ ${#chapters[@]} -eq 0 ]; then
    for f in *.tex; do
        case "$f" in preamble.tex|chapter-template.tex) continue ;; esac
        chapters+=("${f%.tex}")
    done
    if [ ${#chapters[@]} -eq 0 ]; then
        echo "build.sh: no chapters yet — cp chapter-template.tex <name>.tex"
        exit 0
    fi
else
    force=1
fi

status=0
for c in "${chapters[@]}"; do
    c="${c%.tex}"
    if [ ! -f "$c.tex" ]; then
        printf 'build.sh: no such chapter: %s.tex\n' "$c" >&2
        status=1
        continue
    fi
    if [ "$force" -eq 1 ] || [ ! -f "$c.pdf" ] || [ "$c.tex" -nt "$c.pdf" ] \
       || [ preamble.tex -nt "$c.pdf" ]; then
        printf '== %s\n' "$c"
        if pdflatex -interaction=nonstopmode "$c.tex" >/dev/null 2>&1; then
            pdflatex -interaction=nonstopmode "$c.tex" >/dev/null 2>&1 || true
        else
            printf 'FAILED: %s (see %s.log)\n' "$c" "$c"
            status=1
        fi
    fi
done
exit "$status"

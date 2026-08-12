# Math notes — Stacks-project architecture, scaled down

This project mimics how the Stacks Project organizes 7000+ pages: many
small chapter files instead of one big one. Each chapter is a complete,
independently compilable LaTeX document; cross-chapter references go
through the `xr` package; the payoff is fast per-chapter compiles and
stable, meaningful label names.

## Layout

- `preamble.tex` — shared preamble, `\input` by every chapter. Holds the
  theorem environments and one `\externaldocument` line per chapter.
- `chapter-template.tex` — copy to `<name>.tex` to start a chapter (the
  header comment walks through the steps).
- `build.sh` — recompiles chapters whose source changed; a chapter named
  on the command line is rebuilt unconditionally (use this to refresh
  cross-references after rebuilding the chapter they point into).

## Label rules (from the Stacks Project)

1. Every statement environment is labeled, on the line after `\begin`:
   `\label{lemma-zorn-application}`, `\label{definition-group}`, … The
   name should describe the statement, never its number.
2. Same-chapter reference: `Lemma \ref{lemma-zorn-application}`.
3. Cross-chapter reference: `Groups, Lemma \ref{groups-lemma-zorn-application}`
   — the chapter file name plus `-` in front of the label. This works
   because `preamble.tex` declares `\externaldocument[groups-]{groups}`.
4. Never use the long (prefixed) form for a label in the same chapter.
5. Never name a chapter so that its name is a prefix of another
   chapter's name.

## Working in Emacs (RefTeX)

- `C-c )` — insert a `\ref`: pick the label from a menu. Press `x`
  inside the menu to switch to another chapter's labels (the prefix is
  added for you).
- `C-c &` — jump from the `\ref` at point to the label's definition,
  including across chapters.
- `C-c (` — insert a `\label`; inside a lemma it is pre-prefixed
  `lemma-`, and so on.
- `C-c =` — table of contents of the chapter; `RET` jumps.

## Building

    ./build.sh            # chapters whose source changed
    ./build.sh groups     # named chapters always rebuild, even if unchanged

A reference into a chapter that was never compiled shows as `??` and the
log says "LABELS NOT IMPORTED" — build that chapter, then rebuild the
referring chapter by naming it: `./build.sh <referring-chapter>`.

This directory is your content, not managed by boox-latex-setup —
`git init` here if you want history.

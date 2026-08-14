# Upgrade prompt for Claude Code 2.1.112 on the Boox (Termux) — FINAL (v3)

Debugged in two rounds against an Opus subagent: round 1 (with live web verification of
the installer repo) found two fatal flaws in the draft — wrong script (`install.sh`
refuses when an npm install exists; `migrate.sh` is the right one) and a catch-22 (the
installer aborts while any `claude` process is alive, i.e. the agent itself), which
forced the human-runs-installer design. Round 2 blind-simulated the revision: verdict
"high probability of a safe, successful outcome", six fail-safe polish items, all
applied below.

Paste everything between the lines into Claude Code on the tablet:

---

Upgrade Claude Code on this device from 2.1.112 to the current version.

Environment facts — trust these over your own knowledge; your training and your CLI are from April 2026 and things changed after that:

- Device: Onyx Boox Note Max, Android 13, aarch64, Termux (bionic libc). You are Claude Code 2.1.112 installed via npm (`@anthropic-ai/claude-code`) — the last pure-JS release.
- Since 2.1.113 the npm package ships ONLY a native glibc binary (no android target, no JS fallback). It cannot run under Termux's bionic libc. **Never run `npm install`/`npm update` for `@anthropic-ai/claude-code`**, and do not improvise install methods from your own memory.
- The working method is glibc-runner ELF patching via https://github.com/ferrumclaudepilgrim/claude-code-android (maintained; downloads the official binary from downloads.claude.ai with SHA256 verification, auto-updates, keeps the previous version for rollback).
- Because an npm install is present on this device, the correct script is **`migrate.sh`, NOT `install.sh`** — `install.sh` detects the npm install and exits by design.
- **`migrate.sh` refuses to run while any `claude` process is alive — and you are that process, so you cannot run it yourself.** Your job is to verify, review, and prepare; I will run the script myself after quitting you.

Do the following, in order:

1. Report these values and continue to step 2 — step 1 is report-only, I judge the values, you do not abort here: `uname -m` (expect aarch64); `getprop ro.build.version.release` (need ≥ 11); `df -h $PREFIX` (need ~600 MB free; the step-6 fallback would need ~2 GB); `curl -fsSI https://github.com >/dev/null && echo net-ok`.
2. Download but **do not run**: `curl -fsSL https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/migrate.sh -o ~/migrate.sh`. Read it, plus `https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/docs/install.md` (if that doc is missing or unfetchable, just note it and continue — not a failure). Then tell me: (a) what the script does to the existing npm install and in what order, (b) every interactive prompt it will ask, with the literal keystroke to answer each (not "accept defaults" — some prompts default to No). Expected shape: installs `glibc-runner` + `patchelf-glibc` from termux-pacman's glibc repo; downloads the claude binary from downloads.claude.ai with SHA256 verification against manifest.json; backs up `~/.claude`; smoke-tests the new binary BEFORE removing the npm package. If anything differs, list the differences — they are mine to judge — and still proceed to step 3.
3. Then print instructions for me and **stop**: tell me to (a) quit this Claude Code session and any others, (b) in the plain Termux shell confirm `pgrep -fa claude` prints nothing, then run `bash ~/migrate.sh`, answering each prompt with the keystrokes you listed, (c) restart `claude` afterwards. Then wait — do not do anything else, and do not invoke `claude` in any form until I tell you to.
4. Verification (I will ask you to do this after the restart, when you are the new binary): `$PREFIX/bin/claude --version` must NOT print 2.1.112 — if it does, the native binary crashed and the wrapper rolled back; report that instead of retrying. Note the wrapper installs to `$PREFIX/bin/claude` — the SAME path the npm shim occupied — and symlinks `~/.local/bin/claude`. Any PATH edit belongs in `~/.bashrc` (Termux does not read `~/.profile`), and the installer already edits `~/.bashrc`, so check before adding anything. Also run `command -v claude` and one end-to-end check: `claude -p "reply with exactly: ok" --model haiku`.
5. Known quirks after migration: Claude Code's own DNS lookups are redirected to 8.8.8.8/8.8.4.4 via a `BUN_OPTIONS` preload (system DNS untouched; VPN/Pi-hole bypassed for those lookups). Scripts with `#!/usr/bin/env bash` shebangs fail with "bad interpreter" — invoke them as `bash script.sh`, or use the full Termux shebang `#!/data/data/com.termux/files/usr/bin/bash`.
6. Fallback — only if the patched binary segfaults or is killed (kernel seccomp), and ask me before starting (~2 GB): `pkg install proot-distro -y && proot-distro install ubuntu`, then non-interactively: `proot-distro login ubuntu -- bash -lc 'apt update && curl -fsSL https://claude.ai/install.sh | bash'`.
7. Auth: `~/.claude` carries over. If the new binary asks to log in, stop and tell me — no credential workarounds.

Constraints: never delete or uninstall anything, and **never `kill`/`pkill` any `claude` process** — if something needs a claude session closed, that is my job, not yours. Never edit the installer to bypass its guards. From step 2 onward, if a step fails, stop and report the exact command and full error output instead of improvising.

---

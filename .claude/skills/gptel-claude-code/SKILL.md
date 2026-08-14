---
name: gptel-claude-code
description: Development context for gptel-claude-code.el — the in-repo gptel backend that runs the local Claude Code CLI (claude -p) instead of an HTTP API. Use whenever working on core/gptel-claude-code.el, core/flow-gptel.el, their tests, gptel internals they hook into, or debugging LLM chat (C-c g) in this config.
---

# gptel-claude-code development

## Load the reference docs first

Read ALL files in `core/gptel-claude-code/docs/` before nontrivial work on this
backend — they are the distilled knowledge the extension was built from:

- `gptel-requirements.md` — gptel's requirements spec (FR/NFR/P/TC ids; the
  product's normative behavior).
- `gptel-architecture.md` — gptel's architecture: FSM, transports, backend
  generics, wire protocols, text-property model. The §-references in code
  comments point here and at file:line in the gptel source.
- `gptel-implementation.md` — deep per-definition index of gptel v0.9.9.5 with
  experimentally verified traps (the "trap list" in §2 is gold).
- `claude-headless-spec.md` — normative spec of `claude -p` (verified on CLI
  v2.1.231): flags, stream-json events, exit codes, permission semantics. The
  backend's parser is built on this.
- `gptel-claude-code-plan.md` — the implementation plan: design decisions,
  approach comparison, prior-art survey results, risks. Explains WHY the
  extension is shaped the way it is.
- `spec-validation-survey.md` — QA questionnaire for the two gptel spec docs;
  use it if you ever edit/compress those specs.

Line-number citations in these docs refer to the gptel v0.9.9.5 checkout kept
at `~/flow/gptel-headless/gptel/` (reference only — NEVER add it to load-path;
the running gptel comes from MELPA elpa).

## The extension in one screen

Files: everything lives in `core/gptel-claude-code/` — `gptel-claude-code.el`
(backend library), `gptel-claude-code-tests.el` (ERT),
`gptel-claude-code-fixture.jsonl` (recorded stream transcript), `docs/` —
except the flow module `core/flow-gptel.el` (C-c g keymap + the two registered
backends), which stays with its flow-* siblings in `core/`.

- **Transport**: one `claude -p --no-session-persistence` process per request,
  prompt on stdin (10 MB guard), `--output-format stream-json --verbose
  --include-partial-messages` when streaming, `--output-format json` otherwise.
  Dispatch is `:around` advice on BOTH `gptel-curl-get-response` and
  `gptel--url-get-response` (their only call sites are in `gptel--handle-wait`)
  — this covers gptel-send/menu/rewrite, which hardcode their own FSM tables.
- **Stateless full replay**: every request serializes the buffer transcript
  (from the `gptel` text property walk) into one prompt; multi-turn history is
  wrapped in `<conversation-history>` tags with a replay instruction appended
  to the system prompt. No `--resume`, no session ids — gptel's
  buffer-is-the-conversation semantics survive intact.
- **Payload shape** (`:data`): `(:argv [vector] :prompt STRING :stream
  t|:json-false)` — the backend's own shape, not an HTTP body. Dry-run
  inspector renders it; the transport consumes edited copies.
- **Reasoning channel**: thinking deltas AND agentic activity (tool_use →
  "→ Bash: …", tool_result → "  ✓ N lines") accumulate into INFO `:reasoning`;
  the filter emits `(reasoning . chunk)` / `(reasoning . t)` callbacks, and
  `:reasoning-block` is deliberately allowed to reopen (in→done→in) because
  agentic runs interleave text and tools. Rendered as foldable blocks marked
  `ignore` — never re-sent.
- **Models** are registered WITHOUT `tool-use`/`media` capabilities on purpose:
  gptel's own tool loop and media pipeline must stay inert; Claude Code's CLI
  tools are the tool story (per-backend flags: --tools/--allowedTools/
  --permission-mode/working-dir).
- **Auth**: the CLI's own subscription login. No keys, no `--bare`.

## Contracts that MUST hold (breakage points on gptel upgrade)

1. Advice targets `gptel-curl-get-response` / `gptel--url-get-response`, both
   `(fn FSM)`, called from `gptel--handle-wait`.
2. Default callbacks must be the EXACT symbols
   `gptel-curl--stream-insert-response` / `gptel--insert-response` —
   `gptel--handle-pre-insert` memq-tests callback identity for the read-only
   redirect.
3. Set `:http-status "200"` and `:status` BEFORE the WAIT→TYPE transition —
   pre-insert hooks gate on `(member http-status '("200" "100"))`.
4. Registry entry `(PROC FSM . ABORT-FN)` in `gptel--request-alist` is all
   `gptel-abort` needs; the abort thunk must neuter the sentinel, cancel the
   stall timer, delete the process, and kill buffers with
   `kill-buffer-query-functions` bound to nil (live stderr pipe would prompt).
5. Effective streaming = `:stream` ∧ `gptel-use-curl` ∧ `gptel-stream` ∧
   backend/model — so streaming REQUIRES `gptel-use-curl` non-nil even though
   no curl runs. Don't "fix" that.
6. Backend generics dispatched on the struct: `gptel--parse-buffer`
   (`&optional max-entries`), `gptel--parse-list`, `gptel--request-data`,
   `gptel-curl--parse-stream` (point persists in process buffer; pt-checkpoint
   rewind on partial JSON), `gptel--parse-response`, plus a warning no-op
   `gptel--inject-prompt` override.

Verified against MELPA `gptel-20260703.611` (struct slots, generics signatures,
and all the above are identical to v0.9.9.5). **After any gptel package
upgrade, run the ERT suite before trusting the backend** (see below), and
re-check contracts 1–3 by grep if tests fail.

## Tests

From the flow-emacs repo root:

    # offline (13 tests: serialization, payload shape, stream parsing incl.
    # chunking invariance + real fixture, response/error parsing)
    emacs -Q --batch --eval '(package-initialize)' -L core/gptel-claude-code \
      -l gptel-claude-code-tests.el -f ert-run-tests-batch-and-exit

    # live e2e (4 tests: stream, nonstream, abort, error; costs quota)
    GPTEL_CLAUDE_LIVE=1 emacs -Q --batch --eval '(package-initialize)' \
      -L core/gptel-claude-code \
      -l gptel-claude-code-tests.el -f ert-run-tests-batch-and-exit

## CLI version compatibility

- Built and verified on claude CLI **2.1.231** (laptop).
- **2.1.112** (Termux/Boox pinned era): everything the backend emits exists and
  is byte-identical (verified by grepping the actual 2.1.112 npm tarball) —
  EXCEPT model names: `fable`/`claude-fable-5`/`claude-opus-5` don't exist
  before 2.1.170/2.1.219; use `sonnet`/`opus`/`haiku`. Old-CLI soft caveats:
  large-output truncation (fixed 2.1.208/214) degrades to missing token counts
  or a clean parse error; aborting mid-Bash-tool may orphan processes (fixed
  2.1.212). The Termux upgrade path is documented in the repo-root
  `upgrade-claude-termux-prompt.md`.

## Known gotchas (learned the hard way)

- Bare `gptel-request` defaults `:stream` to nil — tests and programmatic
  callers must pass `:stream t` explicitly (only gptel-send passes it).
- A bogus `--model` is NOT a reliable error trigger — the CLI sometimes
  recovers or reports `is_error` with exit 0 + subtype "success". Use a bogus
  flag to test the startup-error path.
- Emacs 30's bundled transient lacks the `:environment` slot gptel's menu
  needs; the elpa transient satisfies it (auto-installed as a gptel dep).
- stream-json event tolerance: `system/init` may NOT be the first line; unknown
  event types must be ignored; text comes ONLY from `text_delta` stream events
  (full `assistant` events duplicate it).
- `stop_reason` can be JSON null → `:null` (truthy!) — always guard.
- Permission denials end with exit 0 subtype "success" — surface
  `permission_denials` explicitly or the user thinks the agent did the work.

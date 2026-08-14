# gptel-claude-code.el — Claude Code headless (`claude -p`) as a gptel backend

## Context

The goal is to use the locally installed Claude Code CLI (v2.1.231, subscription OAuth) as a first-class gptel backend, so gptel chat buffers, rewrite, menus, org branching, and context all work against `claude -p` — including optional access to Claude Code's own agentic tools. Research across the gptel source (v0.9.9.5 in `gptel/`), the three spec documents, and prior art established:

- **No such backend exists anywhere.** gptel issue #1366 requests a subprocess transport (open ~4 months, no maintainer response) → build out-of-tree.
- **The HTTP-proxy route is proven bad for gptel** (issue #1175: OpenAI-compat wrappers hide Claude's tools; org-babel workarounds corrupt buffers). A fake-curl wrapper script is viable but adds a platform-specific artifact and inherits curl-flavored error handling. **A native elisp `make-process` transport is the right shape.**
- gptel's transport is hardcoded (`gptel--handle-wait`, gptel-request.el:1899-1913: `(if gptel-use-curl #'gptel-curl-get-response #'gptel--url-get-response)`), with each transport function having exactly one caller — a narrow, stable advice seam. All backend parse methods are transport-agnostic; Ollama's NDJSON stream parser (gptel-ollama.el:56-94) is a near-verbatim skeleton for claude's stream-json.
- Auth note: local personal use of the real `claude` CLI is the compliant shape; Anthropic prohibits re-exposing subscription OAuth as a generic API. We run the CLI as-is (no `--bare`, which would disable OAuth).

**User decisions:** build the package · **stateless full replay** (no `--resume`; gptel's buffer-is-the-conversation semantics preserved exactly) · agent tools **configurable per backend** · **subscription auth**.

## Deliverables

| File | Contents |
|---|---|
| `/home/safronu/flow/gptel-headless/gptel-claude-code.el` | Backend struct + constructor, cl-defmethods, transport (process/filter/sentinel/abort), advice install/teardown, error taxonomy (~650 lines) |
| `/home/safronu/flow/gptel-headless/gptel-claude-code-test.el` | ERT tests, batch-runnable |
| `/home/safronu/flow/gptel-headless/fixtures/claude-stream.jsonl` | One recorded real stream-json transcript (with text deltas, a tool_use, a tool_result, final result) |

`gptel/` is upstream and is never modified.

## 1. Backend struct + constructor

```elisp
(cl-defstruct (gptel-claude-code (:constructor gptel--make-claude-code)
                                 (:copier nil) (:include gptel-backend))
  (executable "claude")
  (cli-tools "")            ; --tools: "" = none (chat default), "default" = all, or names
  (allowed-tools nil)       ; permission rules → --allowedTools (comma-joined)
  (disallowed-tools nil)    ; → --disallowedTools
  (permission-mode nil)     ; "plan"|"acceptEdits"|"dontAsk"|… → --permission-mode
  (add-dirs nil)            ; → --add-dir (one per dir)
  (working-dir 'scratch)    ; 'scratch | 'buffer | string | (fn info) → default-directory
  (system-prompt-mode 'append) ; 'append → --append-system-prompt, 'replace → --system-prompt
  (max-turns nil) (max-budget-usd nil) (effort nil) (fallback-models nil)
  (extra-args nil)          ; raw argv strings or function of INFO
  (timeout nil))            ; stall timeout secs; nil = off
```

- Inherited slots: `:stream t`, `:key nil` (no key resolution — `gptel--get-api-key` returns nil harmlessly, no password prompt), `:url "claude-code-cli"` placeholder (keeps the dry-run "Copy Curl" path from crashing; its output is documented as meaningless).
- `working-dir 'scratch` (default) = `(expand-file-name "gptel-claude-code/" (temporary-file-directory))` — no project CLAUDE.md scan / MCP autodiscovery → leaner cold starts, no project side effects. `'buffer` = request buffer's `default-directory` (agent profiles; documented as used-as-trusted since `-p` skips the trust dialog).
- Constructor `gptel-make-claude-code` (autoloaded `cl-defun`, `(declare (indent 1))`): fills slots, `(gptel--process-models models)`, registers via `(setf (alist-get name gptel--known-backends nil nil #'equal) backend)` — the Ollama pattern (gptel-ollama.el:324-406).
- Default models: `fable`, `opus`, `sonnet`, `haiku` + full ids (`claude-fable-5`, `claude-sonnet-5`) with `:capabilities (reasoning)` only — **no `tool-use`, no `media`** (keeps gptel's tool loop and media machinery inert for this backend). Symbol passed verbatim to `--model`.

Documented example configs:

```elisp
(gptel-make-claude-code "Claude-Code")                     ; chat profile
(gptel-make-claude-code "Claude-Agent"                     ; agent profile
  :cli-tools "default" :permission-mode "plan"
  :allowed-tools '("Read" "Grep" "Glob" "Bash(git diff *)")
  :working-dir 'buffer :max-turns 25 :timeout 600)
```

## 2. Transcript serialization (stateless replay)

`gptel--request-data` builds our own `:data` plist (no HTTP body): `(:executable … :argv [vector of flags] :prompt STRING :stream t|:json-false)`. Prompt goes to the process via **stdin** (10 MB cap checked); argv computed at request-data time (effective streaming is already resolved there, gptel-request.el:2339-2348).

Serialization of `gptel--parse-buffer` output:
- **Single user turn** → bare content string, no wrappers.
- **Multi-turn** → prior turns wrapped in `<conversation-history>` with `<user>`/`<assistant>` blocks, final user message after `USER: `; a replay instruction is appended to the system text ("the prompt contains your prior conversation… answer only the current message, no tags, no role prefixes, don't repeat history").
- **Trailing assistant turn** (continue-style send) → all turns in history + `USER: (No new message. Continue your previous reply from exactly where it left off.)`.
- System prompt + gptel-context (which arrives pre-merged into `gptel-system-prompt` by the standard transform) → `--append-system-prompt` (default; keeps Claude Code's own system prompt so agent profiles behave) or `--system-prompt`.
- `gptel-temperature`/`gptel-max-tokens`: no CLI equivalent — one-time warning if set. `gptel-tools`/`gptel-use-tools`: ignored by design.
- Streaming flags: `--output-format stream-json --verbose --include-partial-messages` (the `--verbose` is mandatory, spec §4.3); non-streaming: `--output-format json`. Always `-p --no-session-persistence`, plus flags from backend slots.

Rewrite (3-turn prompt list → `gptel--parse-list`), org branching/topics, presets, dry-run editing all flow through unchanged — they act upstream of the backend.

## 3. cl-defmethods (dispatch on `gptel-claude-code`)

- **`gptel--parse-buffer`** — Ollama's backward walk on the `gptel` property (gptel-ollama.el:233-278): `response`→assistant, `ignore`→skipped, **`(tool . id)`→skipped** (tool records from prior runs can't replay through a text prompt; assistant text carries the conclusions), nil→user; `gptel--trim-prefixes`; honors max-entries; non-gptel-mode fallback = whole buffer as one user turn.
- **`gptel--parse-list`** — Ollama's (gptel-ollama.el:208-231), tool branch degraded to a plain assistant note.
- **`gptel--request-data`** — §2. Also wires **`:schema`** (v1, ~15 lines): when `gptel--schema` set → force non-streaming, add `--json-schema` with `(gptel--json-encode (gptel--preprocess-schema (gptel--dispatch-schema-type gptel--schema)))`; result's `structured_output` returned as JSON text.
- **`gptel-curl--parse-stream`** — NDJSON over stream-json events, Ollama's pt-checkpoint/rewind idiom for partial lines. Per event type:
  - `stream_event` `text_delta` → text chunks (the *only* text source; full `assistant` events would duplicate it); `thinking_delta` → concat into `:reasoning`.
  - `assistant` message `tool_use` blocks → append to `:reasoning`: `"\n→ NAME: DETAIL\n"` (Bash→command trunc 80, Read/Edit/Write→file_path, Grep/Glob→pattern, WebSearch/WebFetch→query/url, Task→description, default→compact JSON).
  - `user` message `tool_result` blocks → `"  ✓ N lines\n"` / `"  ✗ first-line\n"`.
  - `result` → `:tokens` (Anthropic-style mapping: input = input+cache_creation, `:cached`/`:cache` from cache fields; `gptel--sum-plists` into `:tokens-full`), `:stop-reason`, stash `total_cost_usd`/`permission_denials` in INFO; `is_error`/subtype≠success → `plist-put :error`.
  - `system/*`, startup/hook/plugin events, `rate_limit_event`, unknown → tolerated/ignored (spec: init may not be first).
- **`gptel--parse-response`** — non-streaming json object: success → `.result` text (empty→nil so gptel's " Empty response" works); denials appended as a bracketed note + status mention; errors → `:error`, return nil.
- **`gptel--inject-prompt`** — safe warning no-op override (default would corrupt our `:data`; can't fire anyway without tool-use capability).

## 4. Transport

**Dispatch:** `:around` advice on **both** `gptel-curl-get-response` and `gptel--url-get-response` (single callers at gptel-request.el:1910/1911) checking `(cl-typep (plist-get (gptel-fsm-info fsm) :backend) 'gptel-claude-code)` → `gptel-claude-code--get-response`, else original. Covers `gptel-send`/`gptel-menu`/`gptel-rewrite` (which hardcode their own FSM tables) with zero global mutation; WAIT bookkeeping and `gptel-post-request-hook` untouched. Idempotent `gptel-claude-code-setup` (called at load) / `gptel-claude-code-teardown`. Streaming keeps gptel's normal gate (needs `gptel-use-curl` non-nil, its default) — accepted and documented; with it nil, requests still work non-streaming via the url-advice arm.

**`gptel-claude-code--get-response (fsm)`:** resolve executable (`executable-find`, clear error otherwise) and working dir; `make-process` with `:connection-type 'pipe` and a **separate `:stderr` buffer** (startup errors must not corrupt the NDJSON stream); utf-8-unix coding; send `:prompt` on stdin + eof; first-run `nconc` into fsm info mirroring gptel-request.el:2913-2927 — `:transformer` (org md→org converter when target is org) and default `:callback` as the **exact symbols** `gptel-curl--stream-insert-response` / `gptel--insert-response` (identity-tested by `gptel--handle-pre-insert`, gptel.el:1350); register `(cons fsm abort-thunk)` in `gptel--request-alist` (all `gptel-abort` needs; thunk neuters sentinel, cancels timer, deletes process — SIGTERM, which claude handles — kills buffers).

**Streaming filter** (own, modeled on gptel-request.el:3029-3116 minus HTTP parsing): insert at process-mark in save-excursion; on first complete line set `:http-status "200"` + `:status` **then** WAIT→TYPE (pre-insert hook gates on http-status); call backend `gptel-curl--parse-stream`; reasoning demux copied (~30 lines): `(reasoning . chunk)` callbacks, `(reasoning . t)` when text resumes, `:reasoning-block` allowed to cycle in→done→in (agentic runs interleave text and tools); zero-length chunks dropped before callback (preserves structural empty-response detection).

**Sentinels:** streaming — exit 0 → `(funcall callback t info)` + transition (FSM routes to ERRS automatically if parse recorded `:error`); nonzero → error taxonomy below, WAIT→TYPE first if no output ever arrived, callback nil, transition; always deregister + kill buffers + cancel timer. Non-streaming — parse whole buffer JSON, `gptel--parse-response`, same status/transition/cleanup shape as gptel-request.el:3130-3175.

**Error taxonomy** (probe order: last `result` event → stderr → exit code; never say "Curl"):

| Condition | `:error` / `:status` |
|---|---|
| exit 0, success, denials ≠ [] | success + `"200 OK (N tool calls denied)"` + message naming tools |
| `is_error` with result text (bad auth/model) | result text / `"Claude Code error"` |
| `error_max_turns` (no result text) | explanatory string / `"Max turns exceeded"` |
| `error_during_execution` | subtype + text / `"Execution error"` |
| exit 1, no result, stderr non-empty (bad flag/schema) | first stderr line / `"Claude Code startup error"` |
| stall-timer kill | timeout explanation citing known CLI stall bug / `"Stalled"` |
| other nonzero exit | `"claude exited with code N"` / `"Claude Code failure"` |

**Stall timeout:** opt-in slot (default nil; recommend 600 for agent profiles) — filter timestamps output, repeating timer kills the process with a clear `:error` on breach (mitigates the current ~405 s headless stall bug).

## 5. Out of scope v1 / v2 seeds

V1 excludes: gptel elisp tools (Claude's CLI tools are the tool story), media, sessions/`--resume`, MCP passthrough (reachable via `:extra-args`), stream-json *input* mode, `--bare`/API-key auth, cost in header line. Natural v2: session-cache hybrid (hash serialized history → `--resume` when unchanged), MCP config slot, context media via temp files, cost display, an ephemeral MCP server bridging gptel tools back into Emacs.

## 6. Verification

Batch: `emacs -Q --batch -L gptel -l gptel-claude-code.el -l gptel-claude-code-test.el -f ert-run-tests-batch-and-exit` from `/home/safronu/flow/gptel-headless/`.

1. `payload-shape` (offline): propertized 3-turn temp buffer → `gptel-request :dry-run t` → assert exact `:prompt` serialization + argv flags; single-turn degenerates to bare string.
2. `parse-stream-fixture` (offline): fixture fed whole *and* re-split at every 7-byte boundary → identical text (chunking invariance), reasoning renderings present, `:tokens` set, `:error` nil.
3. `parse-response-json` (offline): recorded success + synthetic `error_max_turns` through `gptel--parse-response`.
4. `e2e-stream` (live, skip-unless claude): "Reply with exactly the word: pong" on `haiku` → buffer contains pong, FSM DONE, registry empty, tokens present.
5. `e2e-abort` (live): abort mid-stream → ABRT, no live process, buffers killed.
6. `e2e-error` (live): bogus model → ERRS, `:error` names it, no "Curl" wording.
7. `e2e-nonstream` (live): `gptel-stream nil` → `--output-format json` path + url-advice arm.

Interactive checklist: `gptel-send` in markdown and org chats (streaming, prefixes, header-line tokens, foldable reasoning); edit history and re-send (replay reflects edit); org branching; menu + dry-run inspector (Lisp/JSON, C-c C-c resume); `gptel-rewrite` incl. iterate; abort; agent profile on a real repo (`→ Read:` / `✓` reasoning rendering, denial surfacing under `dontAsk`); `gptel-context` file visible in dry-run system text. Record the fixture during this pass.

## 7. Risks

Cold start 2–6 s/request (scratch cwd default; document `--strict-mcp-config` extra-args; v2 session cache) · stall bug (opt-in timeout, abort always works) · transcript mimicry (replay instruction, tags only when history exists; residual risk documented) · gptel-upgrade fragility of advice + callback-symbol identity + demux copy (load-time version check warning; every integration point cited file:line in comments; offline tests catch parser drift) · bare model symbols share global plists (chosen to avoid current collisions) · denials invisible at exit 0 (explicit surfacing in status/message/note).

## Implementation order

1. Struct + constructor + models + advice seam → dry-run works.
2. parse-buffer / parse-list / request-data + serialization → test 1.
3. parse-stream + parse-response + fixture → tests 2–3.
4. Transport: process/filter/sentinels/abort/errors → tests 4–7.
5. Reasoning rendering polish, schema, stall timer, Commentary docs, interactive checklist.

Key reference files: `gptel/gptel-request.el` (transport template L2868-2946, filter/demux L3029-3116, sentinels, abort L2379-2405, gate L2339-2348) · `gptel/gptel-ollama.el` (the backend pattern to copy) · `gptel/gptel.el` (callback identity L1350, insertion/reasoning rendering L1765-1886) · `claude-headless-spec.md` (normative CLI behavior) · `gptel/gptel-anthropic.el:43-58` (token key mapping).

# gptel — Requirements Specification

LLM client for Emacs, "in the spirit of Emacs: available at any time and uniformly in any buffer"; multi-provider. Audience: experienced Emacs Lisp developers implementing from scratch — this file defines *what*, `gptel-architecture.md` (cited as "A§n") defines *how*. Baseline: gptel v0.9.9.5.

## 1. Design principles (normative tie-breakers)

- **P1 Free-form**: query with any text in any buffer, redirect the response anywhere; the chat buffer is a convenience, never a requirement (no prescribed format like comint shells or org-babel blocks).
- **P2 Buffer = conversation**: who-said-what lives in buffer text + invisible metadata (text properties), never required syntax; prompts *and* past responses are freely editable and the edited text is what gets sent.
- **P3 Minimally annoying**: never moves point, steals focus, or blocks Emacs; auto-scroll/cursor-follow are opt-in.
- **P4 Provider-uniform**: one UX over 25+ providers; differences absorbed by a backend abstraction.
- **P5 Transparent & programmable**: payloads inspectable/editable pre-send; raw logs; public request API.
- **P6 No hard external deps**: built-in Emacs suffices; curl used opportunistically for streaming and robustness.

## 2. Glossary

**Backend** = registered provider endpoint config (name, host, auth, models, dialect). **Model** = provider model symbol + metadata. **Chat buffer** = buffer with the minor mode on. **Directive / system prompt** = system message: string, function, or string list (system + canned conversation template). **Context** = extra material (regions/buffers/files) attached to requests — distinct from the conversation text, and from the API's `:context` key (opaque caller data, FR-API-1). **Tool** = user elisp function + JSON-schema arg spec callable by the LLM. **Preset** = named bundle of option values. **Scope** = where an option change applies: global / buffer-local / oneshot (next request only). **Dry-run** = build a request without sending, for inspection/editing/resumption. **Reasoning** = "thinking" content some models emit before their answer.

## 3. Functional requirements

### 3.1 Sending (FR-SEND)
1. One command (`gptel-send`), any buffer: sends text from beginning to point (extended to end of word at point); active region → region only.
2. Response inserted asynchronously below the send position; Emacs stays usable; typing below and re-sending continues the conversation.
3. Buffer parse yields faithful multi-turn history: tracked responses (FR-TRACK) → assistant turns, tool records → tool turns, rest → user turns.
4. Multiple simultaneous requests, same or different buffers, without interference.
5. Abort command stops the current buffer's active request (first found; repeat for others); partial output stays; state reported; callback gets `(callback 'abort INFO)`.
6. Turn limit: N most recent user/assistant pairs (nil = all).
7. Failures surface a human-readable status (header line/echo) with HTTP status + provider message; no partial garbage inserted.
8. Empty response → status " Empty response", no separators inserted.

### 3.2 Response tracking (FR-TRACK)
1. Responses watermarked by copy-surviving text properties — never prefixes/headings/syntax; pasted response text stays a response.
2. Four text classes: user (default) · `response` · `ignore` (visible, never sent: reasoning fences, delimiters) · `tool` records keyed by call id (re-sent as tool messages).
3. Typing inside or immediately before a response extends it; typing after its end, or at buffer end, is user text.
4. `gptel-track-response` nil (non-chat buffers only) disables tracking — everything is user input; no effect in chat buffers.
5. Cosmetic per-major-mode prefixes (`gptel-prompt-prefix-alist`/`gptel-response-prefix-alist`): chat buffers only, stripped before sending, no semantic role.
6. Navigation commands: beginning/end of response at point, with repeat counts.
7. Highlight minor mode (any buffer) marks responses/ignored/tool text via background face, fringe bitmap, and/or margin bar (margin and fringe mutually exclusive).

### 3.3 Chat buffers (FR-CHAT)
1. `gptel` command creates/switches to a named session (name prompted, default from backend; prefix arg forces new; active region = initial prompt; unresolvable API key → password prompt).
2. Major mode = `gptel-default-mode` (markdown if available, else text; org selectable) + `gptel-mode` minor mode (`C-c RET` = send); refuses major modes not derived from org/markdown/text.
3. Unlimited sessions, each with independent buffer-local settings (backend, model, system prompt, tools, temperature, …).
4. Header-line UI (toggleable to mode-line + echo): backend name; clickable status (Ready/Waiting/Typing/Calling tool/Run tools?/errors/Abort/Empty response → request diagnostic); right-aligned clickable: token usage, tool count → tool menu, media toggle (media-capable models only), context summary → inspector, system-prompt preview → directive menu, model → menu. Detail: A§8.8.
5. Token usage accumulated and shown compactly (`[12k↑, C4.1k↑ 890↓]`, `C` = cached), per-request and per-session.
6. Markdown chats: TAB on a fence line folds/unfolds the block (nesting by fence parity).

### 3.4 Persistence (FR-PERSIST)
1. Saving persists conversation state: response/ignore/tool bounds, model, backend name, system prompt, tool names, preset, temperature, max tokens, turn limit.
2. Markdown/text → file-local variables; Org → properties at file top (optionally per heading). All persisted variables marked safe (no prompts on open).
3. Reopen + enable minor mode restores everything; backend/model/tools/preset resolved by name with per-item warnings, never aborting (chat stays usable).
4. With a preset active, only settings differing from it are written (minimal files).
5. Legacy bounds format (flat response-range list) must restore.
6. A pre-save hook customizes what is persisted.

### 3.5 Backends, models, keys (FR-BACKEND)
1. Constructors register: OpenAI (+ any OpenAI-compatible server), OpenAI Responses, OpenAI ChatGPT-subscription OAuth, Azure, Anthropic, Gemini, Ollama, Kagi (FastGPT + Summarizer), AWS Bedrock (Converse), GitHub Copilot, PrivateGPT, Perplexity, DeepSeek, xAI; the OpenAI-compatible constructor also covers GPT4All, Groq, Mistral, OpenRouter, together.ai, Anyscale, Cerebras, Novita, Moonshot, llama.cpp, Open WebUI, etc. *Known deviation:* the OpenAI constructor silently builds a Responses backend when host matches `api.openai.com` (A§7.1, A§12).
2. Constructor args (minimum): name, host, protocol, endpoint, key (string/variable/function), models, stream flag, extra headers (alist or function), extra request params, extra curl args, coding-system where needed.
3. Model metadata: description, capabilities, MIME types, context window, input/output costs, cutoff date, per-model request params. Capabilities gate: `media` (image/file input) · `tool-use` · `json` (native structured output) · `url` (media by URL instead of base64) · `nosystem` (system message suppressed everywhere) · `cache` (prompt caching) · `reasoning` · `responses-api` (route to Responses dialect) · `audio`/`video` (Gemini media classes).
4. Selection UI lists all models as `Backend:model` with metadata annotations.
5. Key resolution chain: string / function / auth-source (`host` + user "apikey"); function keys called per request; trailing whitespace trimmed.
6. OAuth backends (Copilot; Codex): device-code and/or PKCE flows, token persistence, auto-refresh, explicit login commands; auth lazy + automatic on first request.
7. Default backend settable declaratively (setter accepting a type+plist form) and programmatically.
8. Request-param layering: global < backend < model (per-key, later wins).

### 3.6 Transport (FR-NET)
1. curl when available (t/nil/path), else built-in `url-retrieve` — zero external dependency.
2. Streaming only on the curl path, toggleable globally/per-backend/per-model; without curl, still async but whole-response.
3. Proxy (curl `--proxy`; the fallback has none), user curl args, redirects, compression, stall timeout, unlimited payload size (stdin, not argv — also keeps keys off the process list).
4. Parallel requests demultiplexed by process identity; a per-request token frames headers/body inside each stream (A§5).
5. Binary (non-UTF-8) response streams supported (Bedrock).
6. Error classes: connection failure (curl exit code; url.el error data on fallback) · HTTP error with parseable provider body · malformed JSON · unparseable response. No retries. *Known deviation:* HTTP 100-then-error misclassified as success (A§12).

### 3.7 Menu & scoping (FR-MENU)
1. Transient menu (`gptel-menu`, also `C-u gptel-send`), live state display, exposing: model/backend; system prompt; a one-shot "additional instruction" for the next request; context add/inspect/remove; tools; response length (max tokens); temperature; turn limit; context placement; reasoning handling; response tracking; media toggle; input/output redirection; rewrite; response tweaks; dry-run + logging (expert-flag-gated).
2. Scope switch (`=`, shared across all menus): global / buffer-local / oneshot (restored after the next request; must survive the machinery's let-bindings). The scope choice persists.
3. Input redirection: minibuffer (region include/exclude toggle, edit-in-buffer escape, history, preset-cookie completion) or kill-ring (prefix arg picks the kill). Mutually exclusive.
4. Output redirection: echo area · kill-ring (partial output still copied on error) · arbitrary buffer · gptel session (existing or new; the prompt is inserted there fenced in the *target's* markup when modes differ). "Respond in place" (`i`): kills the prompt text (region or text after last response); in the prompt-source exclusivity group (minibuffer/kill-ring prompts have nothing to kill) yet composes with any destination — alone: response replaces prompt; with a destination: prompt killed, response goes there. Read-only text left with a message; killed text kept as response history when not redirecting. Streaming forced off for echo/kill-ring destinations.
5. Send button description = live plain-English sentence: what will be sent, from where, context-source count, destination.
6. Redirection flags are per-invocation; persist with `C-x C-s`, cycle saved combos `C-x p`/`C-x n`.
7. System-prompt menu: pick from `gptel-directives` (string/function/string-list forms); edit in a dedicated buffer (read-only example header, `C-c C-c`/`C-c C-k`); unset; or pick-and-edit a crowdsourced prompt (network fetch consent-gated, cached, refreshed after 14 days). Function directives require confirmation before editing their current value. Accepted quirk: quitting the crowdsourced picker exits the menu.
8. Tool menu: category → tool two-level selection, per-category toggle-all, hidden-category selections preserved, confirm/include options, "continue pending tool calls" entry when a request is paused in TOOL.
9. Visibility adapts: expert-only, mode-gated, capability-gated (instructions column hidden for `nosystem` models with explanatory header), state-gated entries (context/rewrite/tool-continue only when applicable).
10. Works under evil-mode visual selections (region-gated entries appear correctly).
11. Keys rebindable via Transient's `transient-suffix-put`.

### 3.8 Presets (FR-PRESET)
1. `gptel-make-preset`: special keys `:description`, `:parents` (applied first), `:pre`/`:post` thunks, `:system` (string/directive-symbol/function), `:backend` (name or object), `:tools` (names or objects, deduped); other `:foo` → variable `gptel-foo` else `gptel--foo`; unknown keys warn.
2. Declarative value specs: `:append`/`:prepend` (idempotent on strings), `:eval`, `:function` (old→new), `:merge`.
3. Application paths: menu (any scope) · plain elisp (global) · `gptel-with-preset` macro (let-bound, no leakage) · `@preset-name` cookie in the final user turn (stripped from sent text; applied buffer-locally in the per-request prompt copy; only the last turn scanned). Valid cookies fontified + completed in chat buffers.
4. Save-preset command snapshots current settings, copies the elisp form to the kill-ring. Menu shows the active preset; strike-through on drift.
5. Built-in `gptel-default` preset resets all options.

### 3.9 Context (FR-CTX)
1. `gptel-add` (dwim): region → add (replacing overlaps) · point on context → remove (toggle) · else whole buffer · Dired marked files (directories recursively after confirm) · ibuffer marked buffers · negative prefix removes. `gptel-add-file` adds files/directories by path. Yank-to-context adds the current kill (prefix = append).
2. Live, not snapshots: sources re-read per request; region context tracks edits and evaporates when its text is deleted; dead buffers/files silently dropped at collection.
3. Entry kinds: whole buffers, buffer regions, files, file line/char ranges, binary/media files (MIME-detected). Binary needs media-capable model + supported MIME, else refused with message; ICC-profile images must still be detected as binary. *Known deviations:* directory entries mis-derive MIME from the directory name; MIME matching exact, no `image/*` globs (A§12).
4. Gitignored files skipped by default (message names `gptel-context-restrict-to-project-files`); remote files always allowed.
5. Serialized as literal `Request context:` + per-source header ``In buffer `NAME`:``/``In file `~/path`:`` (backtick-quoted) + fenced excerpt, with line-number markers and ellipses for discontinuities (A§8.1). Formatter replaceable, may be async.
6. Placement (`gptel-use-context`): system message (default) / before the final user prompt / off. `nosystem` models auto-fall back system→user. Media context attaches to the *first* user message (media can't ride in system messages).
7. Inspector buffer: previews (inline images), point-highlighting, `n`/`p` navigation, `RET` visits source position, `d` flags for deletion, `C-c C-c` confirm / `C-c C-k` quit. *Known deviation:* `:bounds`/`:lines` sub-range specs not rendered (A§12).
8. Menu shows live context counts (regions/buffers/files).

### 3.10 Media input (FR-MEDIA)
1. `gptel-track-media` (default off; global/buffer/header-line toggle) + media-capable model → bracketed links in chat buffers become media (base64) or text-file parts. Markdown: `[](path)`, `[desc](path)`, `<url>`; org: `[[file:…]]`, `[[attachment:…]]`, `<file:…>`. Plain unbracketed links ignored.
2. Every prompt-region link annotated: "SEND" badge, or warning badge + tooltip reason (bad type / failed predicate / unreadable / MIME unsupported). Links inside responses never annotated or sent.
3. User predicates (separate for markdown and org) restrict which links count (e.g. standalone-only).
4. URL (non-downloaded) media only for `url`-capable models.

### 3.11 Reasoning (FR-REASON)
1. `gptel-include-reasoning`: `ignore` (default: insert but mark `ignore`, never re-sent) / t (insert as response) / nil (drop) / buffer name (redirect there).
2. Inserted reasoning delimited as org `#+begin_reasoning` / markdown ```` ``` reasoning ```` (space after fence) blocks, auto-folded; delimiter lines marked `ignore`.
3. Applies to streaming (chunk-wise state machine; text before an inline `<think>` tag emitted as response first; assumes one reasoning block, before the answer) and non-streaming. *Known deviation:* Bedrock discards streamed reasoning (A§12).

### 3.12 Tools (FR-TOOL)
1. `gptel-make-tool`: name (snake_case), description, function, arg specs (name/type/description; optional/enum/array/nested-object), async flag (function gets result-callback first), category, per-tool confirm (bool or predicate over args), per-tool include policy. Registry: category → name.
2. Selected tools (`gptel-tools`) declared per request in the backend's native format. `gptel-use-tools`: nil / t / `force` (require a call where the API supports it).
3. Tool loop: run calls locally, send results back, continue until a turn without calls. Parallel calls; sync+async mix; continuation fires when all results are in.
4. Confirmation: `gptel-confirm-tool-calls` ∈ t / nil / `auto` (per-tool slot; default), hook override highest. Pending-call UI: in-buffer read-only block (`(tool_name "arg" …)` truncated) + banner ("Run tools:" `C-c C-c` / "Cancel request:" `C-c C-k` / "Inspect or Edit:" `C-c C-i`; mouse dispatch offers y-run / n-noop / k-cancel / i-inspect), or minibuffer multiple-choice (forced for read-only buffers).
5. Inspect buffer: pending calls as editable plists; edit args or delete calls; edits propagate into outgoing history.
6. Rejected calls leave the request paused + resumable ("continue tool calls" in the menu).
7. Sync tool errors → string results to the LLM (request never breaks); unknown tool → error result listing available tools.
8. In-buffer tool records: foldable org `#+begin_tool` / markdown ```` ``` tool ```` (space after fence) blocks (call plist + result, `tool`-propertized) so saved chats replay tool turns. `gptel-include-tool-results` ∈ t / nil / `call` (args only; result replaced by a cache notice on replay) / `auto` (per-tool; default).
9. Pre/post tool hooks: block a call (error string to LLM), stop the request, rewrite name/args (reflected in history), force/suppress confirmation, replace the result. Scope: wired by the send/rewrite handler sets; bare `gptel-request` opts in via custom `:fsm`.
10. MCP (opt-in library + mcp.el): connect/disconnect register/unregister each server's tools under category `mcp-<server>`; connect starts servers as needed, registers *and activates* (adds to `gptel-tools`), reports partial failures; menu gains add/remove entries preserving other selections. Collisions disambiguated by category **in the registry only** — simultaneous selection of same-named tools still collides in the payload (bare names on the wire; A§12).

### 3.13 Rewrite (FR-RW)
1. `gptel-rewrite` with region → minibuffer instruction (default "Rewrite: …", history, TAB shows directive, `C-c C-e` buffer editor, `M-RET` full menu) → request. No region + pending rewrites → actions menu; neither → error.
2. Directive: variable seeded from `gptel-directives`' `rewrite` entry; its default = `gptel-rewrite-directives-hook` (first non-nil) → else mode-derived template (prog-modes: programmer variant "generate ONLY code, no fences/explanations"; text: editor variant). Menu sets it at the chosen scope. `nosystem` models: directive folds into the user prompt; rewrite context moves to the user channel.
3. Preview in place over the region via overlay display, streaming live (grayed original shrinks as rewrite grows); buffer NOT modified. Overlay status line: state (Waiting/Typing/tool states/Ready) + model.
4. On completion: pulse; overlay mouse/RET-actionable, eldoc + tooltip hints. Actions: accept · reject/clear · iterate (input = pending output, instruction pre-filled) · diff (with switches) · ediff (raw text; window config restored on quit) · merge (`git merge-file` if git, manual markers else; smerge-mode on). Batch variants over all pending rewrites; navigation between rewrite regions.
5. `gptel-rewrite-default-action` (default nil = wait): accept/diff/ediff/merge, `dispatch` (open the chooser), or custom function (gets the overlay).
6. Multiple pending rewrites coexist; abort/error cleans up; post-rewrite hook runs over final text in the staging buffer before display.
7. Prompt = 3 turns: text-to-rewrite · canned assistant turn `"What is the required change?  I will generate only the final replacement."` (exact, two spaces) · instruction.
8. A trailing newline the original had but the response lacks is restored (in the stored replacement, hence all actions).

### 3.14 Org extras (FR-ORG)
1. Org prompts sent as Org (no conversion), with cleanup: gptel's own tool/reasoning block header lines stripped (anti-mimicry); configurable element list (default property drawers) removed; tool blocks unescaped.
2. Topics: `gptel-org-set-topic` sets `GPTEL_TOPIC` on a heading; requests under it use only that subtree — many conversations per file.
3. Branching (`gptel-org-branching-context`; Org ≥ 9.7, else warn + linear): context = outline lineage of point — each ancestor's heading + body up to its first child; deepest heading's body up to point; siblings excluded; pre-heading top text included. Composition: region wins outright; topic narrows first, branching within. Normative caveat: heading-shaped prompt prefixes (default `*** `) make successive prompts siblings = separate branches; use non-heading prefixes.
4. Per-heading config: `gptel-org-set-properties` writes `GPTEL_MODEL`, `GPTEL_BACKEND`, `GPTEL_SYSTEM` (`\n`-escaped), `GPTEL_TEMPERATURE`, `GPTEL_MAX_TOKENS`, `GPTEL_NUM_MESSAGES_TO_SEND`, `GPTEL_TOOLS`/`GPTEL_PRESET` (space-separated names); inherited properties override buffer settings for that request only; preset property beats system property; preset-aware minimal writes (FR-PERSIST-4).
5. md→org response conversion (`gptel-org-convert-response`, default on): fences, inline code, headings, bold, italic, bullets. Streaming converter: byte-identical output regardless of chunking (withholds ambiguous trailing lexemes); no emphasis conversion inside code blocks; literal Org src blocks pass through.
6. `GPTEL_BOUNDS` persistence: write must converge though it shifts the offsets being written; long lists never truncated.

### 3.15 Introspection (FR-INSPECT)
1. Dry-run (menu, expert-gated): full payload shown as editable pretty-printed Lisp or JSON; `C-c C-c` sends edits (bad edits → clear error); `C-c C-w` copies an equivalent shell curl command; async-transform dry-runs display when transforms finish.
2. `gptel-log-level`: nil / `info` (bodies) / `debug` (+headers, curl config/command) → timestamped JSON in `*gptel-log*`.
3. Per-request diagnostic (clickable status): state trail (`INIT → WAIT → …`), INFO fields, payload attributes; message bodies scrubbed unless logging.
4. Paused requests (dry-run, rejected tools) are resumable objects.

### 3.16 Variants (FR-VAR)
1. Regenerate: delete response at point (prefix/suffix swallowed in chat buffers), re-send with current settings; old text kept as variant.
2. Variants at a position (from regeneration, rewrites, in-place replacements) cycle forward/back (point offset preserved, pulse) and ediff vs current (prefix arg → variant picker). Session-only, never persisted. *Known deviation:* menu binds both variant keys to one command (A§12).
3. Mark-response command selects the response at point.

### 3.17 Public API (FR-API)
1. `gptel-request`: prompt = string / alternating-turn list / structured `(prompt|response|tool . …)` list / nil (buffer content); keys: callback, buffer/position, `:context` (opaque caller data — not FR-CTX context), stream, system, dry-run, in-place, `:schema`, transforms, `:fsm` (pluggable state machine). Returns the FSM (resumable); never blocks.
2. Callback `(callback RESPONSE INFO)`; RESPONSE ∈ string chunk/full · t (stream done) · nil (error in INFO) · `abort` · `(reasoning . text|t)` · `(tool-call . ((tool args continue-fn)…))` (invoke each continue-fn with a result to resume) · `(tool-result . ((tool args result)…))`. Callback exceptions never break the pipeline.
3. `:schema` (elisp plist / JSON string / shorthand DSL) forces JSON output; native JSON-schema modes where available, synthetic tool elsewhere.
4. Hook points (system-wide; tool-call and save/refresh hooks are wired by the chat/send layer): prompt transforms (sync/async, in the isolated prompt buffer; *known deviation:* async completion is a counter, not a chain — race-prone, A§12) · post-request-dispatch · pre-response-insertion · per-stream-chunk · post-response (BEG END; fires on error/abort with BEG=END) · pre/post tool call · save-state · buffer-refresh · context wrap · rewrite post-processing.
5. Helper hook members documented: auto-scroll (stream), move-to-next-prompt (post-response).

### 3.18 Wire protocols (FR-WIRE)
Per-provider dialects (endpoints, auth, message shapes, streaming framings — SSE, JSONL, JSON-array, binary AWS event stream — tool formats, media encodings, reasoning fields, caching, usage fields) are normative in A§7–8. Anchors:
1. Anthropic: `max_tokens` mandatory; whitespace-only messages skipped; caching (`gptel-cache` ∈ nil/t/list of `message`,`system`,`tool`) via `cache_control` on system parts, last tool, first block of last message, when enabled ∧ model `cache`-capable. Bedrock honors the same option via `cachePoint` (system + tools only).
2. Gemini: safety settings pinned BLOCK_NONE; `additionalProperties` recursively stripped from schemas; no-arg tools `parameters:null` (Anthropic requires `{}`).
3. DeepSeek: strict role alternation — consecutive same-role messages merged.
4. OpenAI Responses: stateless (`store:false`, full context each request).
5. Kagi: single-turn, no streaming, no system message; summarizer takes URL at point or region text.
6. Bedrock: SigV4 via curl ≥ 8.9 (or bearer token); event-stream frames parsed without CRC validation.
7. Cross-provider replay tolerates foreign tool-call id formats.

## 4. Non-functional requirements

1. (P6 concrete) Emacs ≥ 27.1; Transient ≥ 0.7.8; optional markdown-mode; no other hard deps. Exception: Bedrock SigV4 needs curl ≥ 8.9. Optional integrations: mcp.el, vterm, project.el, Org ≥ 9.7.
2. All network activity async; UI never blocks (incl. OAuth polling, tool loops).
3. Point/window never moved by default (P3); post-insertion hooks run with the buffer's visible window selected (window-point correctness).
4. Request construction isolated: prompt processing in a temp-buffer copy snapshotting all request options — in-flight requests immune to later edits; transforms can't damage user buffers.
5. Privacy: diagnostics scrub bodies unless logging on; keys never in argv; crowdsourced fetch consent-gated.
6. Robustness: callback errors demoted (at every site except the streaming filter's per-chunk calls — A§5.5); tool errors stringified; malformed/partial stream chunks retried on the next chunk; buffer liveness checked before insertion.
7. Performance: org stripping via fast regex path (full parse "extremely slow"); binary detection reads ≤ 512 bytes; project lists + link types memoized; insertion O(chunk).
8. All persisted file-locals `safe-local-variable`-marked.
9. Back-compat: obsolete aliases warn; legacy persistence formats restore.

## 5. Manual QA test cases

Format: action → expected. Run send/stream suites with a streaming backend and once with curl disabled.

### 5.1 Sending
- **001** Fresh buffer, question, send → Waiting → response below point after blank line; cursor unmoved.
- **002** Region send → only region in payload (dry-run); response after region end.
- **003** Point mid-word ("Explain recursi|on") → whole word in prompt.
- **004** Reply below response, send → dry-run: user, assistant, user in order.
- **005** Edit mid-response text, send → edit appears in assistant turn.
- **006** Send in two buffers at once → responses land in the right buffers.
- **007** Abort mid-stream → insertion stops, status Abort, partial text kept, no stray processes (`list-processes`).
- **008** Empty completion → " Empty response", no separator/prefix inserted.
- **009** Invalid key → HTTP error + provider message in status; nothing inserted; `*Messages*` has details.
- **010** Network down → curl exit-code message; url path shows url.el error.
- **011** Kill request buffer mid-flight → no error on response arrival.
- **012** Turn limit 1 → dry-run has only last pair + final prompt.
- **013** `gptel-use-curl` nil → works; streaming silently off even with `gptel-stream` t.
- **014** Streaming: incremental arrival; post-stream-hook fires per chunk; final text = non-streaming equivalent (modulo sampling).
- **015** Point never moved by streaming insertion, even parked at the insertion position (stays before arriving text); following is hook-opt-in.
- **016** `gptel-auto-scroll` on stream hook → window scrolls past bottom.
- **017** `gptel-end-of-response` on post-response → cursor after response/next prefix.

### 5.2 Tracking
- **020** Paste response elsewhere, send → assistant turn.
- **021** Same + `gptel-track-response` nil (non-chat) → user turn.
- **022** Type at response's first char → joins response; at buffer end after response → user text.
- **023** Undo removes properties with text; redo restores.
- **024** beginning/end-of-response ±2 across 3 responses → correct, prefixes skipped.
- **025** Highlight mode (face/margin/fringe; margin+fringe → margin wins): existing responses decorated; deletion tracked; disable → clean.

### 5.3 Chat buffers
- **030** `M-x gptel` → name prompt (default `*<Backend>*`), prefix inserted, "Send your query…"; `C-u` → fresh session.
- **031** Completion offers only gptel-mode buffers (a non-gptel buffer named like one must not appear).
- **032** No key anywhere → password prompt; used for request.
- **033** Active region → becomes initial prompt.
- **034** gptel-mode in fundamental-mode → user-error, mode off.
- **035** Header line: all six indicators clickable per FR-CHAT-4; `gptel-use-header-line` nil → mode-line + echo; old header restored on disable.
- **036** Token usage: `[No info]` before; counts after; click toggles request/session; cumulative grows; `C` prefix for cached.
- **037** Fence folding: TAB folds ("..."), unfolds; nested; fence at EOB.
- **038** Custom prefixes inserted cosmetically; dry-run stripped.

### 5.4 Persistence
- **040** Save markdown chat (turns + reasoning + tool block) → file-locals; reopen + gptel-mode → "gptel chat restored."; exact properties (response/ignore/tool·id/front-sticky).
- **041** Org chat → properties at top; >10 tool bounds round-trip untruncated.
- **042** Unknown backend on restore → message + hint; usable after choosing one.
- **043** One missing tool → named warning; others restored.
- **044** Preset in file → applied; only drifted settings present.
- **045** Legacy `((BEG . END)…)` bounds restore.
- **046** No safe-local-variable prompts.
- **047** Org heading on line 1 → properties inserted at top uncorrupted; repeated saves stable.

### 5.5 Backends/keys
- **050** Register OpenAI-compatible backend (e.g. llama.cpp) → models in selector with annotations.
- **051** authinfo key (`machine <host> login apikey password …`) auto-used; function key called per request; trailing newline trimmed.
- **052** Azure → `api-key` header (not Bearer) at deployment endpoint.
- **053** Declarative `gptel-backend` setopt form → equivalent backend.
- **054** `nosystem` model → no system message in payload; instructions column hidden with header.
- **055** Model `:request-params :stream :json-false` → streaming off for that model only.
- **056** Copilot: device-flow on first request (code copied, browser); token cached; session token auto-renewed; `gptel-gh-login` forces; responses-api models route to Responses dialect (log).
- **057** Codex OAuth: PKCE (refuses over SSH) and device flow; refresh near expiry; temperature/max-tokens stripped with warnings.
- **058** Bedrock: SigV4 + curl < 8.9 → constructor error; bearer works regardless; both stream modes parse.
- **059** Kagi: only last user prompt sent; references appended; URL at point summarized; region summarized; trailing response → "No user prompt found!".
- **060** DeepSeek: consecutive same-role turns merged in payload.
- **061** Perplexity: citations appended once, both modes.

### 5.6 Menu/scope/redirection
- **070** Menu shows truthful current values (model, system preview with ⮐, context and tool counts).
- **071** Scope: buffer-local set isolates; global set kills a local value; oneshot restores after next request even on error; second oneshot before restore keeps true original.
- **072** Minibuffer prompt: `M-RET` region toggle; `C-c C-e` editor round-trip; history; `@preset` completion.
- **073** Kill-ring prompt; empty ring → user-error; `C-u` → kill selector.
- **074** Echo destination → stream off, full response messaged; tool prompts in minibuffer.
- **075** Kill-ring destination → yank matches; on error partial copied + message.
- **076** Buffer destination → at that buffer's point.
- **077** Session destination from elisp buffer → fenced `#+begin_src emacs-lisp` (org) / ``` (markdown); backend/model copied; window shown; read-only target: prompt not inserted, request proceeds.
- **078** In-place: region replaced; killed text recoverable as variant (`gptel--previous-variant`); read-only → message, kept; vterm-specific deletion.
- **079** Within-group flags block each other (sources m/y/i; destinations e/g/b/k); cross-group (`i`+`b`) allowed.
- **080** Send description live: line ranges, kill preview, "empty" in error face, context count, destination, replace/kill phrasing.
- **081** One-shot instruction (`d`): overlay labeled "DIRECTIVE:" at region start / response start / after last response; cleared on exit; applies once; merges with string/list/function system prompts.
- **082** `C-x C-s` persists flags; `C-x p`/`C-x n` cycle saved combos.
- **083** Evil visual → region-gated entries (rewrite, add-region) visible.
- **084** `transient-suffix-put` rebind (e.g. `-m` → `M`) honored.

### 5.7 Directives
- **090** Menu lists all directives with previews; pick sets at scope; `DEL` unsets; unique auto keys.
- **091** Editor: read-only header immune; `C-c C-c` applies at scope; `C-c C-k` aborts; window restored.
- **092** Function directive → y/n confirm to edit its current value; decline cancels.
- **093** List directive → only system part edited, template kept; dry-run shows template turns.
- **094** Crowdsourced: consent + URL on first use; cache written; >14 d refetch; refusal → no fetch; quit exits menu (quirk); pick → editor.

### 5.8 Presets
- **100** `:system` string/symbol/function, `:backend` name, `:tools` names → applied at scope; `@` indicator; drift strike-through.
- **101** `:parents` chain: parents first, child overrides.
- **102** `:append` on string idempotent; on non-string system → clear user-error; `(:context (:append …))` works.
- **103** `@cookie` start/mid/before-punctuation → applied + stripped; `@unknown` inert; prior-turn cookie ignored; cookie in response region neither fontified nor applied.
- **104** `gptel-with-preset` → globals unchanged after.
- **105** Save-preset snapshot correct; kill-ring elisp reproduces it.
- **106** `gptel-default` resets all.

### 5.9 Context
- **110** Region add → overlay; dry-run shows `Request context:` + fenced `In buffer…` in system message; point-inside toggles off; overlapping re-add replaces.
- **111** Edits inside region reflected next send; full deletion evaporates overlay; list stays clean.
- **112** Whole-buffer context grows both ends; region grows at neither edge.
- **113** Killed context buffer → send fine, inspector omits it, menu counts pruned.
- **114** Dired: mark 2 files + 1 directory → recursion confirm; gitignored skipped with message; restriction off → included; TRAMP always included.
- **115** Binary + incapable model refused; ICC PNG detected binary; capable model → media part in payload.
- **116** Kill-ring context: add replaces; prefix appends with `----`.
- **117** Placement: `system` (prepended to system message, original retained), `user` (inserted before final user text, prefix handling right), nil (not sent though still listed); `nosystem` → user; function system prompt still correct.
- **118** Excerpts: same-line regions → one `... (Line N)`; mid-line start → leading `...`; short of EOB → trailing `...`; line 1 → no marker.
- **119** Inspector: highlight under point; `RET` exact positions (overlay/file/binary); `n`/`p` extremes; `d` flag/unflag/region; confirm removes flagged only; empty confirm normalizes; images inline.
- **120** Narrowed source → out-of-narrowing regions still sent.

### 5.10 Media links
- **125** `[](./img.png)` → SEND badge + base64 part; plain unbracketed `file:///…` ignored; `[desc](./file.txt)` → textfile part.
- **126** Unreadable → "!" + reason; unsupported MIME → "!" + reason; URL link w/o `url` capability → not sent.
- **127** Org forms `[[file:…]]`/`[[attachment:…]]`/`<file:…>` recognized; plain org link not.
- **128** Standalone predicate: inline rejected, standalone accepted.
- **129** Response-region links never annotated/sent; media toggle refreshes annotations both ways.

### 5.11 Reasoning
- **135** Each `gptel-include-reasoning` value × stream/non-stream: `ignore` → visible, delimited, folded, absent from next payload; t → response; nil → absent; buffer name → redirected (created if missing).
- **136** Inline `<think>` tags (e.g. via Ollama distills) = API-field handling; pre-`<think>` text emitted as response.
- **137** Org `#+begin_reasoning` / markdown ``` reasoning fence; delimiters foldable.

### 5.12 Tools
- **140** Sync 2-arg tool: "Calling tool" → result → final answer; block inserted, folded, `tool·id`; save/restore replays (dry-run shows tool messages).
- **141** Async tool same; mixed parallel sync+async → continuation after all.
- **142** Confirm t → banner block; `C-c C-c` runs; `C-c C-k` cancels ("gptel-menu to continue"), menu resume works; mouse y/n/k/i; read-only → minibuffer; `:confirm` predicate honored under `auto`.
- **143** Inspect: edited arg used AND history updated; deleted call dropped; unparseable edit → clear error.
- **144** Tool signal → error-string result, request completes; unknown tool → error listing tools, continues.
- **145** force → forced-choice field in payload; nil → no tools despite selection.
- **146** Include `call` → cache notice replayed; nil → no record, conversation continues.
- **147** Pre-hook `:block "reason"` → error-wrapped to LLM; `:stop` ends request; `:confirm t` forces prompt; args rewrite in execution + history. Post-hook `:result` replacement sent + shown.
- **148** Tool menu: three-state category key; hidden-category selections persist; RET applies at scope; `q` leaves `gptel-tools`; counts right.
- **149** MCP: absent mcp.el → user-error; no servers → user-error; connect ALL registers under `mcp-<server>` + activates + counts failures; disconnect offers shutdown; reconnect clean; `M+`/`M-` preserve unrelated selections; same name on two servers addressable by category; both selected → payload collision (limitation; verify the declaration list).

### 5.13 Rewrite
- **155** Region → instruction minibuffer (TAB directive, `M-RET` menu, `C-c C-e` editor) → Waiting→Typing (morphing; `buffer-modified-p` nil, undo clean) → Ready + pulse.
- **156** Prog-mode region → programmer directive variant (dry-run).
- **157** Accept replaces exactly; reject leaves original; iterate: input = pending output, instruction pre-filled.
- **158** Diff switches (`-w`, `-U 5`) honored; jump-to-old → source. Ediff: raw text, window config + overlay display restored on quit; twice.
- **159** Merge: git markers labeled original/backend; no git → manual equivalent; non-BOL region → markers at BOL; smerge on.
- **160** Multiple rewrites: batch accept/clear/merge/diff; `C-c C-n`/`C-c C-p`; "No further rewrite regions!" at ends.
- **161** Abort → overlay + staging cleaned; error → status message + cleanup; killed source buffer → no error.
- **162** Each `gptel-rewrite-default-action` value (accept/diff/ediff/merge/dispatch/custom fn) fires on completion.
- **163** No region/pending → user-error. Missing trailing newline restored. RET dispatch: keys in status line (Emacs 29+), status restored on quit.
- **164** `nosystem` → directive in prompt, context in user channel.
- **165** Narrowed buffer → diff/ediff correct.

### 5.14 Org
- **170** Response converted: fences→`#+begin_src`, `**b**`→`*b*`, `*i*`→`/i/`, `##`→`**`, `` `c` ``→`=c=`, `* item`→`- item`.
- **171** Stream = one-shot byte-identical; adversarial chunking: split fences, split `**`, response ending in ```` ``` ````, 5 backticks inside a block, emphasis in code untouched, literal `#+begin_src` passthrough (< 11 chars/chunk).
- **172** Two simultaneous org streams convert independently; staging cleaned per response.
- **173** Topic on heading 2/3 → dry-run only that subtree; completion offers topics; errors outside org.
- **174** Branching: nested point → lineage without siblings; point-min heading excluded unless point under it; leading text included; composes with topic + region; Org < 9.7 → warn + linear.
- **175** Branching + `*** ` prefix pitfall reproducible; non-heading prefixes fix.
- **176** Properties under heading → per-request override; `GPTEL_PRESET` beats `GPTEL_SYSTEM`; `\n` decodes; other headings/non-org unaffected.
- **177** Property drawers stripped; org-escaped tool block lines (`,*`) unescaped; gptel block header lines never sent.

### 5.15 Introspection
- **185** Dry-run Lisp + JSON exact; edited payload sent (log); corrupt sexp → "Can not resume"; `C-c C-w` runnable curl (quoting with spaces/quotes).
- **186** Async-transform dry-run displays after transforms (polling).
- **187** info vs debug log content; timestamps; no key material at info.
- **188** Diagnostic trails: plain INIT→WAIT→TYPE→DONE; send tool-loop …TYPE→TPRE→TOOL→TRET→WAIT→…; →ERRS; →ABRT; bodies scrubbed when logging off.

### 5.16 Variants
- **190** Regenerate keeps old as variant; `gptel--previous-variant`/`next` cycle with offset + wraparound + pulse.
- **191** Ediff vs variant; prefix → picker; no history → "response is additive" error; mark-response outside → error.

### 5.17 Cross-cutting
- **195** `emacs -Q` + package + only `gptel-api-key` set → first send works (OpenAI default).
- **196** Obsolete aliases (`gptel-post-response-hook`, `gptel-context--alist`, `gptel--system-message` file-local) warn but work; legacy file-local deleted on restore.
- **197** Unicode round-trip both transports; Windows CRLF byte-count check.
- **198** 100+ KB prompt via stdin, no argv errors.
- **199** Simultaneous stream + rewrite + pending tool confirm in 3 buffers → independent; abort affects only its buffer.
- **200** Menu changes without send → only scoped variable sets; oneshot pending exactly one request.

### 5.18 API/wire
- **201** `gptel-request` each prompt form (string / alternating list / structured list / nil) + custom callback: event sequences per FR-API-2 (stream: chunks…t; non-stream: one string; error: nil + INFO `:status`; abort); return value resumable via dry-run resume.
- **202** `:schema` plist + shorthand: OpenAI → `response_format`/`text.format` in dry-run; Anthropic → `response_json` in `tools`, **no** `tool_choice` forcing unless `gptel-use-tools` force; callback gets JSON string; no confirmation, no loop.
- **203** `gptel-proxy` → curl `--proxy` (debug log); url fallback ignores (limitation).
- **204** Post-rewrite hook uppercasing staged text → accepted rewrite uppercased; ran in staging buffer pre-display.
- **205** Save-state hook removing a variable → absent from file; restore still works.
- **206** `gptel-cache` t + capable Anthropic model → `cache_control` on system parts/last tool/last message in dry-run; incapable or nil → absent. Bedrock: `cachePoint` after system + tools.
- **207** Two sessions, different buffer-local settings → each dry-run reflects its own.

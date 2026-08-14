# gptel — Implementation Index & State Model

Deep inspection of gptel v0.9.9.5's ELisp implementation (18 files, 644 top-level definitions). Every definition was read and indexed by 16 parallel inspectors; ~140 claims were **verified by executing the code in a live batch Emacs 30.2** (`emacs -Q --batch -L <repo> …`, Org 9.7.11, no network); Emacs primitive semantics were checked against the local ELisp Reference / Emacs manuals (Info) where in doubt. The finished document was then audited claim-by-claim against the source by 18 independent verifiers (~600 claims re-checked, many re-executed; ~30 corrections applied). Line numbers refer to the checkout at `~/flow/gptel-headless/gptel`.

Format of index entries: `name` (kind, line) — what it does. State: what it reads/writes. Notes: non-obvious details (experimentally verified claims are marked).

---

## 1. State model

gptel keeps state in eight distinct places. Everything below was observed in code and, where marked, confirmed by experiment.

### 1.1 Persistent (survives Emacs)
- **Chat files themselves**: markdown/text chats carry a file-local-variables block (`gptel--bounds` + config vars, written by `gptel--save-state`); org chats carry `GPTEL_*` properties incl. `GPTEL_BOUNDS` (marker-checked ≤6-retry write). The conversation's role structure is thus persisted as positions, re-applied as text properties on restore.
- **OAuth token files** (prin1'd plists): `.cache/copilot-chat/{github-token,token}`, `.cache/gptel-openai/openai-oauth-token` (one file shared by ALL OpenAI-OAuth backends — clobber hazard, TODO in source).
- **Crowdsourced prompts CSV cache** (`gptel-crowdsourced-prompts-file`, 14-day staleness).

### 1.2 Process-lifetime globals
- **Registries**: `gptel--known-backends` (name→struct, equal-keyed, replace-on-re-register), `gptel--known-tools` (category→name→tool; new categories PREPEND), `gptel--known-presets` (ordered; re-register keeps position), `gptel--request-alist` (live requests: dotted `(PROC FSM . ABORT-FN)` triples).
- **Model symbol plists**: `:capabilities :mime-types :request-params …` stored on the interned model symbol itself — global, wholesale-REPLACED at registration, last backend to register a shared name wins (verified).
- **Symbol-plist `gptel-history` keys**: the oneshot-scope stash (save-once guard; restore via self-removing `gptel-post-request-hook` member deferred `run-at-time 0`; fires after the next DISPATCH, not completion).
- **Caches**: `gptel--link-type-cache` (path→binary verdict), `gptel-context--project-files` (+0-delay debounced reset timer), `gptel-bedrock--aws-profile-cache` (expiry-aware, one forced retry), `gptel--crowdsourced-prompts` (hash; Lisp-2 collision — same symbol's value cell = cache, function cell = fetcher).
- **Load-time mutations**: `text-property-default-nonsticky` gains `(gptel . t)`; `gptel-directives` gains the `rewrite` entry; org send-advice installed on `gptel-send`/`gptel--suffix-send`; the highlight fringe bitmap registered; `gptel--bedrock-models` snapshots the model-id alist (later pushes invisible).
- **The ~19 request-option globals** (`gptel-backend gptel-model gptel-stream gptel-system-prompt gptel-tools gptel--schema gptel-context gptel-temperature …`) — each may also be buffer-local or oneshot; snapshotted per request (§1.6). `gptel--set-buffer-locally` (nil/t/1) is the single scope flag all menus share.

### 1.3 Buffer-local state
- Chat buffers (gptel-mode): local `before-save-hook`/`after-change-functions` members, jit-lock registrations, `header-line-format`/`mode-line-process`, persistence vars (`gptel--bounds --backend-name --tool-names`, plus `gptel--preset` — a plain defvar made buffer-local only by the restore path), `gptel--token-usage`(+`-strings`), `gptel--fsm-last` (latest request's FSM; `:data` bodies scrubbed on DONE/ERRS unless logging — but NOT when cached mid-tool-call), `gptel--old-header-line`, plus any option set at buffer scope.
- Rewrite: `gptel--rewrite-overlays` (accept leaves dead entries; only reject/sanitize prune), `gptel--rewrite-message`.
- Process buffers: **point itself is parser state** (persists between filter calls; rewound on partial frames); Bedrock adds `gptel-bedrock--stream-cursor` (marker).
- `left-margin-width` (highlight-mode ±1).

### 1.4 Text-property-carried state (the buffer is the database)
- `gptel` property: absent=user · `response` (+`front-sticky (gptel)`) · `ignore` · `(tool . ID)` (ID nil for Gemini/Ollama). Globally rear-nonsticky; `gptel--inherit-stickiness` re-propertizes insertions whose END abuts propertized text, except at point-max.
- `gptel-history` (response variants; session-only), `read-only`+`font-lock-fontified` (tool confirmation text), `keymap` (`gptel--markdown-block-map` on fence/tool/reasoning delimiter lines).
- Org: `GPTEL_*` properties are literally buffer text.

### 1.5 Overlays (the full zoo)
context source highlights (`gptel-context t`, evaporate, advance-flag growth semantics) · context inspector chunks (`gptel-overlay t` + source pointer) · context deletion marks (priority −80) — three species sharing one property name · rewrite overlay (display projection, `gptel-rewrite` payload, 4-slot `status` before-string, priority 2000, evaporate — **evaporate kills it during accept's delete-region**) · media-link annotations (evaporate, −80, SEND/"!" badges) · tool-confirmation overlay (REUSED across rounds; `'prompt` sub-overlays consed on, `'previews`/`'gptel-tool` nconc'd) · highlight-mode overlays (jit-lock mirror of the `gptel` property) · fence-fold overlays (invisible + "...") · DIRECTIVE preview overlay (transient-arg lifecycle, exit-hook cleanup) · minibuffer prefix overlays · inspect-buffer per-call overlays (index into `:tool-use`).

### 1.6 Per-request state
- **`gptel-fsm`** struct: `state` (INIT/WAIT/TYPE/[TPRE]/TOOL/TRET/DONE/ERRS/ABRT), `table` (first-match-wins), `handlers` (run on entry, synchronously), `info`. Transitions are explicit calls from handlers/transport code; a state nobody transitions out of = paused. Entering a state RUNS its handlers (mock hazard: a real FSM entering WAIT re-dispatches HTTP).
- **INFO plist** (reference semantics — only `plist-put` tail-mutation is visible to co-holders): target keys (`:buffer :position :tracking-marker :context`), payload `:data` (prompt buffer → payload plist, swapped by plist-put = in-place setcar of the value cell); separately, the FIRST curl run swaps the FSM's whole info reference via `(setf (gptel-fsm-info fsm) (nconc (:uuid :transformer :callback…) info))` — new keys PREPENDED, so holders of the old reference see only tail mutations, config snapshot, round state (cleared on WAIT entry: `:tool-result :tool-use :error :http-status :reasoning :tokens` — NOT `:uuid`, NOT `:tool-pending`), stream state (`:partial_json :partial_text :partial_reasoning :signature :reasoning-block :reasoning-marker :tool-marker :transformer :uuid`, Bedrock `:accumulated-events :message-complete`), bookkeeping (`:history :status :stop-reason :tokens-full :post :end-time`, gh `:gh-initiator`, rewrite `:newline`, vterm `:vterm-marker`).
- **The prompt buffer**: temp copy with ~19 buffer-local option snapshots + text + `major-mode` set as a variable (mode function never run) — the transform sandbox, killed at realize.
- **Markers**: `:position` (re-homed into `*LLM response*` on read-only redirect), `:tracking-marker` (insertion-type t while streaming → nil at DONE), `:reasoning-marker`/`:tool-marker`.
- **Child process** (curl pipe / url-retrieve) + its buffer; per-round UUID.
- **Staging buffers**: rewrite `" *gptel-rewrite*"` (shadow-placeholder overtype), md→org scratch (withhold pointer; **no end-of-stream flush — withheld text is dropped**), vterm redirect.

### 1.7 Ephemeral UI state
Transient scope plists (tool selection `:tools/:category/:key`) · `transient-history` · transient-exit-hook one-shots · timers (1s inspect-query poll; 0s context cache-buster; 0s oneshot restore) · saved window configs + one-shot `ediff-quit-hook` members · kill-ring writes (in-place prompt kill, "k" destination, curl-command copy, save-preset form) · named buffers: `*gptel-log*` `*gptel-query*` `*gptel-diagnostic*` `*gptel-context*` `*gptel-tool-calls*` `*LLM response*` `*gptel-prompt*` `*gptel-diff*`.

### 1.8 External state
HTTP(S) via curl/url-retrieve (+ localhost:1455 OAuth listener) · filesystem reads (context files, media base64, binary probes ≤512 bytes) · env vars (`AWS_*`, `SSH_*`) · subprocesses (`aws configure export-credentials`, `curl --version`, `git merge-file`) · OS clipboard (OAuth codes) · browser (`browse-url`) · OS temp files (merge, unwind-protected).

---

## 2. Non-obvious findings verified by experiment (the trap list)

Genuine bugs found: **(1)** malformed JSON on a 2xx/100 status is silently swallowed to a nil response with no error, in BOTH transports (success cond-clause tested before the json-read-error clause); **(2)** Bedrock `toolChoice` emits `{"any":{"quote":{}}}` (stray `'()` in a backquote); **(3)** Bedrock's header TLV parser reads a 2-byte length for every type — spec-correct fixed-width headers would crash it (latent; real headers are all strings); **(4)** `gptel-mcp-disconnect` crashes `void-variable mcp-server-connections` when mcp.el is absent (menu guards it; `M-x` doesn't); **(5)** `gptel--sanitize-model`'s fallback calls `gptel-make-openai` — void-function in a gptel-request-only image; **(6)** DeepSeek's schema rewrite splices into `messages[0]` regardless of role (corrupts the first user message when no system prompt); **(7)** DeepSeek models declare capability `tool`, not `tool-use`; **(8)** two Gemini models have duplicate `:capabilities` plist keys — the narrower first value wins, audio/video advertised-but-dead; **(9)** md→org mangles bold at the very start of a response: `**bold**` → `**bold*` — the opening `**` is left un-shrunk (looking-back needs preceding chars absent at buffer start) while the closing `**` shrinks to `*`; **(10)** streaming vs one-shot md→org diverge on an unclosed trailing `*emphasis`; **(11)** the `GPTEL_SYSTEM` `\n` escape round-trip is lossy for literal `\n` text; **(12)** rewrite accept's `delete-region` evaporates its own overlay before the insert — the registry keeps dead entries; **(13)** rewrite-previous from point-max misses a region abutting point-max; **(14)** "notsupported" missing-space typo in the sanitize-model warning; **(15)** PrivateGPT constructor docstring contradicts its actual defaults; **(16)** Kagi's URL closure and payload builder disagree on unknown models (silent /summarize URL vs pcase-exhaustive error); **(17)** OpenAI stream parser leaves `:partial_json` stale after `[DONE]`.

Design facts that surprise: the host-sniff in `gptel-make-openai` is an UNANCHORED substring match ("api.openai.com.evil.org" matches) · `<think>` demux is one-shot per request — a late think tag becomes plain response text · Gemini includes `thinkingConfig` BY DEFAULT (because `gptel-include-reasoning`'s default `'ignore` is truthy) · Anthropic prepends the `response_json` schema tool even when `gptel-use-tools` is nil · Anthropic replay keeps wire-format `:input` while `:tool-use` is reshaped to `:args` (copy-before-reshape ordering) · 9 of Copilot's 11 delegating methods key off the GLOBAL `gptel-model`, not INFO's · `gptel--merge-plists` mutates its first arg; `gptel--sum-plists` copies · `gptel--json-read` maps null→`:null` but `gptel--json-read-string` maps null→nil · `max-entries` in buffer parsing counts only USER turns · schema `:name`s are md5-of-random per call · `gptel-curl--get-args` (argv form, key-leaking) is dead code for requests — kill-ring copy only · the `" Empty response"` branch inside `gptel--handle-post-insert` is unreachable (status comes from elsewhere) · the log-response regex contains raw CR bytes that render deceptively · reasoning routed to a side buffer swallows its end sentinel · `gptel-context--collect` mutates `gptel-context` in place as a side effect of being "read" · evaporated context overlays leave dangling registry entries until the next collect · attach-response-history / stream-cleanup closures / ediff-quit members are all self-removing one-shots.

---

## 3. Per-file index

The sections below index every top-level definition, file by file. Duplicated coverage at slice boundaries (gptel.el highlight block) was cross-checked for consistency.
## gptel-request.el lines 1–1430

## Index

- `gptel-proxy` (defcustom L72) — Proxy address string passed to curl's `--proxy`. State: pure global var; consumed via the stdin config builder.
- `gptel-api-key` (defcustom L78) — Default API key: string or zero-arg function. State: global var; default is `gptel-api-key-from-auth-source`.
- `gptel-stream` (defcustom L89) — Whether to stream responses (curl + capable backend only). State: pure global var.
- `gptel-use-curl` (defcustom L102) — t/nil/path. State: global var; default computed ONCE at load via `(executable-find "curl")` — not re-probed.
- `gptel-org-convert-response` (defcustom L111) — md→org conversion toggle for Org-originated requests. State: pure global.
- `gptel-curl-file-size-threshold` (defcustom L117) — obsolete (stdin payloads); kept for compat, `make-obsolete-variable`'d.
- `gptel-prompt-transform-functions` (defcustom L153) — prompt-transform hook, default `(gptel--transform-apply-preset gptel--transform-add-context)`. State: global hook; members run in the prompt temp buffer and may mutate it + INFO.
- `gptel-post-request-hook` (defcustom L186) — run after dispatch, possibly pre-response. State: global hook.
- `gptel-response-filter-functions` (defvar L193) — dead; obsoleted immediately.
- `gptel-prompt-prefix-alist` (defcustom L203) / `gptel-response-prefix-alist` (L216) — mode→prefix alists ("### ", "*** ", ""). State: global.
- `gptel-response-separator` (defcustom L229) — "\n\n". State: global.
- `gptel-directives` (defcustom L236) — named system prompts (default/programming/writing/chat). State: global; `gptel-system-prompt` default seeded from `'default` at load.
- `gptel-system-prompt` (defcustom L270) — active directive: string/nil/list-template/function. State: global, commonly buffer-local.
- `gptel-max-tokens` (L319), `gptel-temperature` (L332), `gptel-cache` (L345) — sampling/caching knobs. State: pure globals.
- `gptel--known-backends` (defvar L379) — NAME→backend-struct registry; mutated via the `gptel-get-backend` gv-setter (`alist-get … #'equal` — replace, not duplicate; verified).
- `gptel--openai` (defvar L388) — dead, obsoleted.
- `gptel-backend` (defcustom L391) — active backend struct. Notes: `:set` on a `(TYPE NAME . PLIST)` list value interns `gptel-make-<type>` (special-case gh) and CALLS it → `setopt` constructs AND registers a backend. Name shared with the struct type (different namespaces).
- `gptel-model` (defcustom L554) — active model symbol. Notes: Customize `:type` choices computed at defcustom time — later-registered backends absent from the widget.
- `gptel-expert-commands` (defvar L573) — expert menu toggle. State: global.
- `gptel--num-messages-to-send` (defvar L578) — turn cap; `safe-local-variable` integer-or-null.
- `gptel-log-level` (defcustom L581) — nil/info/debug.
- `gptel-track-response` (L598), `gptel-track-media` (L616), `gptel-use-context` (L631), `gptel-include-reasoning` (L654) — behavior toggles. State: globals.
- `gptel-context` (defcustom L680) — context source list. State: global; mutated by gptel-context.el.
- `gptel-markdown-validate-link` (defcustom L726) — md link predicate.
- `gptel--request-alist` (defvar L748) — live-request registry of dotted triples `(PROC FSM . ABORT-FN)` — the cons shape is `(cons fsm lambda)`, retrieved via `(cddr entry)` and funcalled directly (L2396); the docstring's "(PROCESS . (FSM ABORT-CLOSURE))" notation misleadingly suggests a proper list.
- `gptel--request-params` (defvar L753) — raw extra payload params ("dangerous").
- `gptel--ersatz-json-tool` (defconst L761) — "response_json".
- `gptel-curl-extra-args` (defcustom L766) — user curl args.
- `gptel-curl--common-args` (defconst L780) — per-OS baseline curl args, computed at load; darwin and default branches identical, only Windows differs (no --compressed).
- `gptel--link-type-cache` (defvar L793) — path→(t . binaryp) cache. Notes: NOT read/written by `gptel--file-binary-p` — populated by the media-link validators (markdown method at L2543 of this file; gptel-org.el:427).
- `gptel-markdown--link-regex` (defconst L806) — inlined markdown link regex (avoids requiring markdown-mode).
- `gptel--mode-description-alist` (defvar L810) — odd mode-name→language map.
- `gptel--json-read` (defmacro L834) — JSON at point → plist; null→`:null`, false→`:json-false` (json-parse-buffer or json.el fallback). State: reads buffer/point.
- `gptel--json-read-string` (defmacro L849) — JSON from string; **null→nil here** (asymmetric with `gptel--json-read`; known TODO in source).
- `gptel--json-encode` (defmacro L862) — elisp→JSON; `:null`→null, `:json-false`→false (verified).
- `gptel--maybe-funcall` (defmacro L876) — call-or-value; on arity mismatch warns (*Warnings*) and RETRIES WITH ZERO ARGS (compat shim; retry may re-error).
- `gptel--process-models` (defun L898) — normalize model specs; `(name . plist)` **replaces the symbol's whole plist** (verified: pre-existing keys wiped). State: global symbol plists.
- `gptel-get-backend` (defun L918) — registry lookup, `user-error` if absent; gv-setter at L926 enables `setf`.
- `gptel-backend` (cl-defstruct L931) — slots `name host header protocol stream endpoint key models url request-params curl-args coding-system`; custom `:constructor gptel--make-backend` → default `make-gptel-backend` does NOT exist (verified).
- `gptel-api-key-from-auth-source` (defun L941) — auth-source lookup, host defaults to active backend's, user "apikey"; utf-8-encodes function-valued secrets; `user-error` if absent. State: reads dynamic `gptel-backend`; may touch netrc/keychain.
- `gptel--get-api-key` (defun L958) — key resolution: function→call+trim, string→trim, symbol→recurse on value (multi-hop verified); trims trailing `[\r\n]+`.
- `gptel--to-number` (defsubst L969) — number/string coercion, errors otherwise (verified).
- `gptel--to-string` (L976), `gptel--intern` (L983) — coercions; `--intern` interns into global obarray.
- `gptel--merge-plists` (defun L989) — later-wins merge; **mutates first arg in place** (verified `eq`; the copy-sequence line is commented out — footgun).
- `gptel--sum-plists` (defun L1005) — numeric summation; **copies** first plist (verified non-`eq`) — opposite of merge.
- `gptel--file-binary-p` (defun L1019) — extension fast-path (jpe?g/png/gif/webp — ICC-profile HACK) else read 512 bytes and check `buffer-file-coding-system`; `file-missing`→message+nil. State: filesystem read.
- `gptel--insert-file-string` (defun L1033) — insert file wrapped in ``In file `PATH`:`` + fence, using an insertion-type-t marker.
- `gptel--strip-mode-suffix` (defun L1043) — mode→language name; only prog/text/tex-derived modes; alist first.
- `gptel--url-retrieve` (cl-defun L1061) — **synchronous blocking** JSON-over-HTTP helper (auxiliary calls, not the LLM transport); error handling TODO; non-JSON content-type payloads skip JSON serialization but are still utf-8-encoded (encode-coding-string wraps the whole pcase).
- `gptel-prompt-prefix-string` / `gptel-response-prefix-string` (defsubst L1080/L1085) — mode-keyed prefix lookup.
- `gptel--at-word-end` (defmacro L1090) — point-to-word-end within save-excursion.
- `gptel--temp-buffer` (defmacro L1097) — generate-new-buffer with inhibit-hooks on ≥28.
- `gptel--with-buffer-copy` (defmacro L1109) / `gptel--with-buffer-copy-internal` (defun L1116) — temp buffer + copies ~19 request buffer-locals + text + `major-mode` **set as a variable, mode function never run** (no hooks/keymaps). The prompt-buffer sandbox.
- `gptel--trim-prefixes` (defsubst L1133) — strip cosmetic prefixes/whitespace; nil if empty.
- `gptel--link-standalone-p` (defun L1148) — link alone on its line?
- `gptel--curl-path` (defsubst L1162) — `gptel-use-curl` string or "curl".
- `gptel--transform-add-context` (defun L1166) — default async transform; delegates to `gptel-context--wrap` when context active. State: reads FSM info `:data`.
- `gptel--model-name/-capabilities/-mimes/-capable-p/-mime-capable-p/-request-params` (defsubsts L1176–1199) — symbol-plist readers; `-capable-p`/`-mime-capable-p` default to `gptel-model`.
- `gptel--base64-encode` (defun L1204) — literal file read + base64 (no line breaks).
- `gptel--describe-directive` (defun L1216) — directive preview string (λ: docstring first line for functions); newlines → REPLACEMENT arg (default plain space; the "⮐ " glyph comes from UI callers in gptel.el/gptel-transient.el).
- `gptel--parse-directive` (defun L1244) — directive → (system . template); function directives called (arbitrary side effects possible); template through `gptel--parse-list` unless RAW.
- `gptel--parse-response-plist-error` (defun L1267) — `:error` > `:detail` > `:message` > `:Message` (verified precedence).
- `gptel--parse-response-error` (defun L1276) — plist or `cl-some` over array.
- `gptel--log-buffer-name` (defconst L1286) — "*gptel-log*".
- `gptel--log` (defun L1291) — append header line + pretty-printed JSON to *gptel-log*; pretty-print wrapped in ignore-errors (malformed data stays raw).
- `gptel--schema` (defvar L1306) — active schema; copied into prompt buffer, consumed by backends.
- `gptel--parse-schema` (cl-defgeneric L1309) — bodyless generic (no default method).
- `gptel--dispatch-schema-type` (defun L1312) — plist/JSON-string/two shorthand DSLs → canonical schema; array roots wrapped in `{items:…}` object (verified shapes).
- `gptel--preprocess-schema` (defun L1395) — **destructive** walk: symbol `:type`→string; every object gains `additionalProperties:false` + `required` + `propertyOrdering` (verified in-place).

## Experiments (12, all passed)
merge-plists mutation `eq`; json-encode null/false; to-number error path; process-models plist replacement; api-key symbol chain + CRLF trim; struct constructor naming; error-plist precedence; schema DSL shapes; preprocess-schema destructiveness; gv-setter replace semantics; coercion round-trips; sum-plists copies.

## STATE-CARRIERS (slice)
`gptel--known-backends` (global alist) · `gptel-backend` var (+ `:set` constructs backends) · `gptel--request-alist` (declared) · ~19 request-option globals copied into prompt buffers · `gptel--schema` · `gptel--link-type-cache` · model **symbol plists** (replaced wholesale) · `*gptel-log*` buffer · `*Warnings*` (maybe-funcall) · filesystem reads (binary probe, base64, file insert) · sync network (`gptel--url-retrieve` only) · caller plists mutated in place (`gptel--merge-plists` first arg, `gptel--preprocess-schema` SPEC).
## gptel-request.el lines 1430–2450

## Index

- `gptel-use-tools` (defcustom L1432) — t/`force`/nil master tool switch; `force` silently falls back where unsupported.
- `gptel-confirm-tool-calls` (defcustom L1454) — t/nil/`auto` (default; defers to tool's `:confirm`).
- `gptel-include-tool-results` (defcustom L1468) — t/nil/`call`/`auto`; declared here, consumed only by gptel.el/transient.
- `gptel-tools` (defcustom L1488) — selected tool structs; snapshotted into prompt buffer; copied to INFO `:tools` at realize.
- `gptel-tool` (cl-defstruct L1496) — function/name/description/args/async/category/confirm/include; ctor `gptel--make-tool-internal` (`&allow-other-keys`).
- `gptel--preprocess-tool-args` (defun L1521) — recursively converts symbol `:type`s to strings **destructively in the caller's SPEC** (setcar/aset; verified through nested :properties/:items and vectors); avoids `sequencep` (would match strings).
- `gptel--make-tool` (defun L1546) — preprocess args then build struct (same destructive note).
- `gptel--known-tools` (defvar L1551) — category → (name → tool) registry. Notes: new categories PREPEND (LIFO) via nested `setf alist-get` (verified).
- `gptel-get-tool` (defun L1575) — lookup by name / `(category name)` / category (returns list) / struct passthrough; `(error "No tool matches for %S" path)` on miss (all 4 branches verified).
- `gptel-make-tool` (defun L1599) — public ctor + registry insert/overwrite (category default "misc").
- `gptel--parse-tools` (defgeneric+default L1688) — tools → OpenAI-shaped vector; per-arg operates on `copy-sequence` (originals safe); `additionalProperties :json-false`; `:optional` → excluded from `required`.
- `gptel--parse-tool-results` (defgeneric L1740) — bodyless; per-backend only.
- `gptel--inject-prompt` (defgeneric+default L1747) — splice message(s) into `:messages`: nil pos=append, n=insert at index, negative=from end (verified all cases); **mutates DATA in place**.
- `gptel--inject-tool-call` (defgeneric+default L1773) — default only `display-warning`s (*Warnings*).
- `gptel-request--transitions` (defvar L1799) — default table INIT→WAIT→TYPE→{ERRS|TOOL|DONE}, TOOL→TRET→{ERRS|WAIT|DONE}; predicates in order, `t` catch-all.
- `gptel-request--handlers` (defvar L1819) — WAIT→handle-wait, TOOL→handle-tool-use, TRET→handle-tool-result, DONE/ERRS/ABRT→handle-post. ABRT reachable ONLY via explicit `gptel--fsm-transition` NEW-STATE (no table entry).
- `gptel-fsm` (cl-defstruct L1843, ctor `gptel-make-fsm`) — state (INIT), table, handlers, info.
- `gptel--fsm-transition` (defun L1869) — push previous state onto `:history` (newest-first, verified), set state, run new state's handlers **synchronously in order**.
- `gptel--fsm-next` (defun L1883) — first-match-wins over `(pred . next)`; predicates receive INFO, not the FSM (verified).
- `gptel--handle-wait` (defun L1899) — clears `:tool-result :tool-use :error :http-status :reasoning :tokens` in place (plist-put nil, same object — verified; `:uuid` deliberately kept), dispatches curl/url per `gptel-use-curl`, runs `gptel-post-request-hook`.
- `gptel--process-tool-call` (defun L1915) — stringify result, push `(spec args result)` onto `:tool-result` (**LIFO**, verified), plist-put `:result` into the call plist (aliased into `:tool-use` — FIXME'd implicit mutation); transitions only when the LAST pending call resolves (verified countdown).
- `gptel--handle-tool-use` (defun L1941) — per unresolved call: unknown name → ersatz `response_json` unwrap (encode args → callback (+t if stream), strip call) or error-result listing tools; confirmation: call-plist `:confirm` (plist-member) > global t/nil > tool slot under `auto`; queue confirmables (set `:tool-pending t`, callback `(tool-call . pending)`), run others (async: continuation prepended; sync: condition-case → error string). Runs in INFO `:buffer`.
- `gptel--map-tool-args` (defun L2000) — positional args in TOOL-SPEC declaration order (verified: spec order, not plist order; missing → nil).
- `gptel--handle-tool-result` (defun L2011) — inject `gptel--parse-tool-results` output into `:data`, callback `(tool-result . alist)`, transition (TRET→WAIT normally).
- `gptel--handle-post` (defun L2025) — run INFO `:post` functions with INFO (DONE/ERRS/ABRT cleanup).
- `gptel--error-p`/`gptel--tool-use-p`/`gptel--tool-result-p` (L2035–2039) — plist-get predicates.
- `gptel-request` (cl-defun L2043) — public entry; prompt shapes (nil/string/list/structured); start-marker = region-end or word-end-at-point; INFO assembled into FSM `:info`; function system prompts resolved in the REQUEST buffer, result stored buffer-locally in prompt buffer; transforms fan-out (buffer-local list; `t` splices global; apply-preset hoisted first then stripped; sync/async by func-arity; completion counter → realize); returns FSM immediately. Dry-run: FSM stays INIT, no network (verified end-to-end with inert backend).
- `gptel--realize-query` (defun L2327) — in prompt buffer: parse-directive (drop system for `nosystem`), effective stream = :stream ∧ use-curl ∧ gptel-stream ∧ model/backend ok, insert directive template at point-min, `gptel--parse-buffer` (cap 2×N), inject media into first user message, plist-put `:backend :model` unconditionally; `:include-reasoning` only when non-nil and `:tools` only when both gates non-nil — those keys ABSENT otherwise (verified), replace `:data` with request payload, kill buffer, transition unless dry-run.
- `gptel-abort` (defun L2379, interactive) — find first entry whose FSM info `:buffer` eq BUF; callback `'abort`; run abort closure; deregister; force ABRT (runs `:post`); message. Entry shape verified: **dotted triple `(PROC FSM . ABORT-FN)`** — `(cddr entry)` is the bare closure.
- `gptel--create-prompt-buffer` (defun L2409) — org → gptel-org copier; region → region copy; else point-min..point/PROMPT-END; source buffer never mutated (save-excursion/restriction).
- `gptel--create-prompt` (defun L2431, obsolete 0.9.9) — buffer→parse→kill wrapper.
- `gptel--parse-buffer` (cl-defgeneric L2449) — bodyless contract (backward walk, MAX-ENTRIES).

## Experiments (11, all passed)
FSM defaults eq to global tables; transition history push + sync handlers; fsm-next order + INFO arg; handle-wait in-place clears (+:uuid kept); map-tool-args ordering; preprocess-tool-args destructive/nested; tool registry LIFO categories + 4 lookup branches + miss error; full dry-run (INFO keys exactly `:data :buffer :position :dry-run :backend :model :include-reasoning`; payload `(:model … :messages […] :stream :json-false)`); inject-prompt positions incl. negative; process-tool-call countdown + LIFO results; gptel-abort end-to-end (dotted entry, callback 'abort, ABRT :post ran).

## STATE-CARRIERS (slice)
`gptel--known-tools` (LIFO categories) · FSM instances (state/:history/info) · INFO keys `:data :buffer :position :callback :context :in-place :dry-run :transforms :stream :backend :model :include-reasoning :tools :tool-use (aliased call plists) :tool-result (LIFO) :tool-pending :error :http-status :reasoning :tokens :history :post` (`:uuid` never cleared) · prompt temp buffer (~19 locals + text + major-mode-as-variable) · `gptel--request-alist` (read/pruned; dotted triples) · external curl/url processes · hooks: `gptel-post-request-hook`, buffer-local transforms · `*Warnings*` (inject-tool-call default) · caller args mutated: tool `:args` specs, DATA payloads.
## gptel-request.el lines 2450–3219

- `gptel--parse-list-and-insert` (defun L2457) — insert prompt list as propertized turns (`response` / `(tool . ID)`); simple alternating or advanced alist format (experimental).
- `gptel--parse-list` (cl-defgeneric L2493) — bodyless.
- `gptel--parse-media-links` (defgeneric+default L2502) — default wraps whole region as one `(:text …)` ignoring MODE; only markdown-mode (here) and org-mode (gptel-org) have methods — every other mode gets no link extraction.
- `gptel-markdown--validate-link` (defsubst L2518) — resolves type/readability/binary-mime/model-capability; memoizes binary verdicts in `gptel--link-type-cache`; returns fixed-shape list where **only the first nil in the tail is guaranteed correct** (short-circuit); URL links need `url` capability else silently skipped with a message (verified).
- markdown `gptel--parse-media-links` (defmethod L2552) — text/media/textfile/url parts; **rejected links stay as literal text folded into the surrounding :text chunk** (from-pt advances only past accepted links; verified).
- `gptel--inject-media` (defgeneric+default L2596) — default = display-warning only ("Context support not implemented…"); every shipped backend overrides EXCEPT Kagi (bare `(:include gptel-backend)`, no method — media context silently dropped with only the warning).
- `gptel--request-data` (cl-defgeneric L2608) — bodyless.
- `gptel--sanitize-model` (cl-defun L2615) — **writes globals** gptel-backend/gptel-model: nil backend → first registered, else fabricates `(gptel-make-openai "ChatGPT")` — **hard undeclared dependency on gptel-openai.el: void-function in a gptel-request-only image (verified)**; string model interned; unknown model → backend's first model + warning. **Warning text typo: "not"+"supported" concatenates to "notsupported" (verified literally).**
- `gptel--url-get-response` (defun L2652) — url-retrieve transport: dynamically binds url-request-* + gptel-backend/model; registers proc-buf + abort closure in request-alist; two fsm transitions; full-response `<think>` extraction (no streaming); kills buffer at end.
- `gptel--parse-response` (cl-defgeneric L2738) — bodyless.
- `gptel--url-parse-response` (defun L2748) — → (response http-status http-msg error). **Verified bug (BOTH transports): 2xx/100 status is checked BEFORE the malformed-JSON clause → malformed JSON on success status passes bare symbol `json-read-error` to the backend parser → silent nil response, NO error surfaced.** "Malformed JSON in response." only appears on non-2xx.
- `gptel-curl--get-config-args` (defun L2788) — common + user + backend curl args (backend/model/stream dyn-bound).
- `gptel-curl--get-args` (defun L2799) — full argv incl. `-d<json>`/`-H<hdr>`. **Dead for real requests** — used ONLY by gptel.el's copy-curl-command feature; would leak keys via /proc (why the real path uses --config stdin).
- `gptel-curl--get-config` (defun L2830) — config text: `key = value` lines (cl-etypecase: cons → `%s = %S` so strings are elisp-quoted, bare symbol `@-` unquoted), proxy trio only when gptel-proxy non-empty (verified), `-w` write-out with UUID + %{size_header}, `data-binary = @-`, blank line, raw JSON body.
- `gptel-curl-get-response` (defun L2869) — make-process `--config -` pipe; coding binary vs utf-8-unix per backend; config+body via process-send-string+eof; first run **replaces the FSM info via `(setf … (nconc new-keys … info))`** (prepends, not in-place), retry run only refreshes `:uuid`; `:transformer` set only for org buffers + gptel-org-convert-response — **requires INFO `:buffer` set or crashes in set-buffer (verified)**; filter/sentinels installed per :stream; abort closure registered. End-to-end verified against 127.0.0.1:1 → exit 7 → ":error Curl failed with exit code 7…" ":status Curl failure" → callback nil.
- `gptel-curl--log-response` (defun L2959) — logs headers (debug) + body; **the L2966 regex contains RAW embedded CR bytes rendering like `"?\n?\n"` in viewers — actually `"\r?\n\r?\n"`, correct (verified via od -c); do not "fix" by retyping.**
- `gptel-curl--stream-cleanup` (defun L2979) — streaming sentinel: curl-exit / 200-100 (just `(funcall callback t info)` — no body reparse, sidesteps the malformed-JSON hazard) / non-2xx (parse error body); 1–2 fsm transitions; deregister + kill buffer.
- `gptel-curl--stream-filter` (defun L3029) — insert at process-mark; status line recognized only once buffer holds MORE than the line itself (verified); WAIT→TYPE + first parse-stream happen in the SAME filter invocation that completes headers (verified); `<think>` demux: **one-shot per request — once :reasoning-block is 'done, a late `<think>` is plain response text** (verified; matches "reasoning precedes response" comment); open/close split across chunks handled (reasoning cb, (reasoning . t) sentinel, remainder as response, same invocation). **Mock hazard (discovered): transitioning a real default FSM into WAIT re-dispatches gptel-curl-get-response — test harnesses need inert tables.**
- `gptel-curl--parse-stream` (cl-defgeneric L3118) — bodyless; runs inside the filter's with-current-buffer.
- `gptel-curl--sentinel` (defun L3130) — non-streaming sentinel; **guarded by `(eq (process-status process) 'exit)` — killed/signaled processes are silently ignored (no callback/cleanup from the sentinel; the abort closure is the complementary path)**; success → parse-response incl. `<think>` extraction; 2 transitions; deregister + kill buffer.
- `gptel-curl--parse-response` (defun L3177) — search-backward UUID trailer, `read` the (uuid . header-size) cons, parse status+body. Same 2xx malformed-JSON silent-nil bug (verified). Missing UUID → `(nil nil nil "Could not parse curl response.")` — the only branch with nil status/msg.

## Experiments (10): config/argv builders + proxy; file-binary-p (extension HACK: ASCII file named .png → binary!); markdown media-links in real markdown-mode; full stream-filter state machine walkthrough incl. one-shot think detection + FSM mock hazard; both parse-response 2xx-malformed-JSON bugs; gptel--log format (header+data pretty-printed together); log-response CR bytes od -c; sanitize-model mutations + void-function + typo; end-to-end curl failure path; Info nodes on filters/sentinels/coding systems.

## STATE-CARRIERS (slice)
gptel-backend/model/stream dyn-bound per request (written by sanitize-model) · gptel--request-alist add/remove · FSM info (first-run wholesale replace via nconc) + state via transitions (side-effecting: handlers run) · gptel--link-type-cache · *gptel-log* · curl/url child processes + buffers/markers/coding systems · *Warnings*/*Messages*.
## gptel.el lines 1–1000

## Index
- `gptel-version` (defconst L191) — "0.9.9.5".
- Hooks: `gptel-pre-response-hook` (L226) · `gptel-post-response-functions` (L242; BEG END; fires even on failure with beg=end; `pulse-momentary-highlight-region` added at depth 70 at L256) · `gptel-post-stream-hook` (L258) · `gptel-pre-tool-call-functions` (L266) · `gptel-post-tool-call-functions` (L309) · `gptel-save-state-hook` (L346).
- `gptel-default-mode` (L355) — markdown if fboundp else text (probed at defcustom eval).
- `gptel-use-header-line` (L365), `gptel-display-buffer-action` (L374, #533), `gptel-crowdsourced-prompts-file` (L389, XDG cache), `gptel-refresh-buffer-hook` (defvar L403, default jit-lock-refontify).
- Persistence vars: `gptel--bounds` (defvar-local L409, safe-local listp) · `gptel--preset` (**plain defvar** L412, safe-local symbolp — buffer-local only when restore does `(set (make-local-variable …))`; a bare setq leaks globally) · `gptel--tool-names` (defvar-local L418, safe-local listp) · `gptel--backend-name` (defvar-local L425, safe-local stringp) · `gptel--old-header-line` (defvar-local L432, **no safe-local property**; consumer past L1000).
- `gptel--markdown-block-map` (L434) — TAB → cycle-block keymap for fence lines.
- `gptel--modify-value` (L442) — preset value combinator `:append/:prepend/:eval/:function/:merge`; verified string append/prepend idempotent, merge = plist later-wins.
- `gptel-auto-scroll` (L479) — scroll-up when point off-window; swallows end-of-buffer errors.
- `gptel-beginning-of-response` (L491) / `gptel-end-of-response` (L497) — property-search navigation, prefix strings trimmed (verified landings).
- `gptel-markdown-cycle-block` (L530) — regex fence fold via evaporating `invisible` overlay + "..." before-string; nesting parity; **mode-agnostic** (verified in fundamental-mode).
- `gptel--annotate-link` (defsubst L563) — SEND/"!" before-string + help-echo reason onto a link overlay.
- `gptel--annotate-link-clear` (L603) — delete only `gptel-track-media` overlays (verified selectivity).
- `gptel--get-buffer-bounds` (L612) — widened backward walk → `(PROP (BEG END [VAL])…)`; VAL only for cons-valued props; per-key lists ascending despite backward scan (push ordering; verified).
- `gptel--get-response-bounds` (L635) / `gptel--in-response-p` (L646) / `gptel--at-response-history-p` (L650) — property reads.
- `gptel--restore-props` (L657) — bounds → properties in `with-silent-modifications` (no modified flag, no change hooks); `front-sticky (gptel)` ONLY for `response`; legacy flat format = all-response (verified round-trips).
- `gptel--restore-state` (L693) — no-op without buffer-file-name (verified); org delegates; restores props + preset + backend (message on unknown) + tools (per-miss demoted error + warning; never aborts — verified).
- `gptel--save-state` (L734) — runs save-state-hook; org delegates; add/delete-file-local-variable for preset-diffed vars; unconditional `gptel--bounds`; deletes legacy `gptel--system-message`. Verified literal Local Variables block output.
- Top-level L804: `(cl-pushnew '(gptel . t) (default-value 'text-property-default-nonsticky))` — global; makes `gptel` rear-nonsticky by default (verified present post-load) — the reason `gptel--inherit-stickiness` exists.
- `gptel--inherit-stickiness` (L807) — after-change: propagate the `gptel` property at END onto [BEG,END) + front-sticky, **unless END = point-max** (verified 3 cases: inside=inherit, EOB-after=no, plain prompt=no).
- `gptel-markdown--annotate-links` (L817) — jit-lock fn; one `gptel-track-media` overlay per link (evaporate, priority −80); validates + decorates; skips links in responses; no-op when tracking off; registered by gptel-mode's markdown branch (L1034).
- `gptel--header-line-info` (defvar L848) — `:eval` display program (recomputed every redisplay): token usage / [N tools] / media toggle / context / prompt / model buttons, right-aligned via string-pixel-width; toggle-track-media lambda writes buffer-local gptel-track-media + runs refresh hook + clears annotations; toggle-usage mutates `gptel--token-usage-strings` car.
- `gptel-use-header-line` fn (L946) — sets 3-segment header-line-format (backend · static " Ready" · info); status updates happen elsewhere.
- `gptel--token-usage` (defvar-local L960) — (REQUEST-PLIST BUFFER-PLIST). `gptel--token-usage-strings` (L969) — (IDX REQ-STR BUF-STR). `gptel--format-token-usage` (L976) — plist → "[…↑ …↓]" (file-size-human-readable). `gptel--update-token-usage` (L991) — merge + accumulate via sum-plists; first use defaults IDX=1 (buffer total); nil TOKENS = no-op.

## Experiments (15): nonsticky entry; bounds walk + VAL-for-cons; props round-trip incl. front-sticky-only-for-response + legacy format; stickiness 3 cases; modify-value semantics; fence fold mode-agnostic; annotate-clear selectivity; response navigation; restore-state gating + graceful degradation; save-state literal output; bounds ordering; gptel-mode gate (text-mode ok + hooks installed; fundamental-mode user-error).

## STATE-CARRIERS
Buffer-locals: `gptel--bounds --tool-names --backend-name --old-header-line --token-usage --token-usage-strings` (+`gptel--preset`, a plain defvar made buffer-local at the restore site) · global `text-property-default-nonsticky` gains `(gptel . t)` at load · header-line-format (buffer) · after-change-functions/before-save-hook members (wired by gptel-mode) · text props `gptel front-sticky gptel-history` · overlays: fence-fold (invisible/evaporate), link annotations (gptel-track-media, priority −80) · file-local variables block written into saved chats · point/scroll (auto-scroll, navigation).
## gptel.el lines 1000–2100

- `gptel-mode` (define-minor-mode L1009) — installs buffer-local before-save-hook→save-state, after-change→inherit-stickiness; markdown: font-lock keyword putting `gptel--markdown-block-map` on fence lines + jit-lock link annotator; org: jit-lock annotator + local post-response font-lock-flush; header-line/mode-line-process; restore-state; prettify-preset. Unsupported mode: `(gptel-mode -1)` BEFORE user-error (never half-enabled).
- `gptel--update-status` (L1057) — buttonized status → `(setf (nth 1 header-line-format))` or mode-line-process; force-mode-line-update; body gated on gptel-mode; mode-line mode echoes non-Ready statuses to minibuffer, header-line mode never does.
- Highlight block (L1077–1225) — see inspector 6's part (duplicated coverage; consistent).
- `gptel-send--transitions` (defvar L1226) — INIT→WAIT→TYPE→{ERRS,TPRE,DONE}, TPRE→{ERRS,TOOL}, TOOL→TRET, TRET→{ERRS,WAIT,DONE}.
- `gptel-send--handlers` (defvar L1242) — DONE and ERRS end with `gptel--fsm-last`; **ABRT does not → aborted FSMs are never cached into gptel--fsm-last**.
- `gptel--fsm-last` (defvar-local L1257 + defun L1260) — handler snapshots FSM into buffer-local; strips `:data`'s `:messages/:contents/:query` **in place (values nilled, keys kept)** unless gptel-log-level (verified); always sets `:end-time`. Never reset on new request.
- `gptel--inspect-fsm` (L1272) — *gptel-diagnostic* tabulated-list in bottom side window (slot 10); default FSM from gptel--fsm-last or gptel--request-alist matched by :buffer; hides :data/:history/:tools/:partial_*.
- `gptel--handle-pre-insert` (L1343) — read-only target → redirect to `*LLM response*` (or vterm pre-insert): **`(move-marker start-marker (point) NEW-BUFFER)` re-homes the marker**; redirect only when :callback is exactly one of the two default insertion fns; pre-response-hook only for HTTP 200/100; " Typing..." for streams.
- `gptel--handle-post-insert` (L1378) — locks tracking marker (type nil), separator+next prompt prefix unless :in-place, " Ready", token usage, post-response hooks in visible window. **Verified: the " Empty response" branch is dead code in this handler** — tracking-marker binds `(or :tracking-marker start-marker)` and start-marker must be live (marker-buffer earlier would error) → empty-response status actually comes from other paths.
- `gptel--handle-error` (L1415) — message + " Error: STATUS" + hooks + tokens; no-ops without :error. `gptel--handle-abort` (L1454) — " Abort" + hooks + tokens.
- `gptel--handle-token-usage` (L1480) — TPRE handler; live-buffer + gptel-mode gated.
- `gptel--handle-pre-tool` (L1490) — pre-tool hooks: :stop → sets :stop-reason/:status "Stopped by hook"/:error; :confirm plist-member → call plist; :args/:name merged via gptel--merge-plists + gptel--inject-tool-call into :data; :result → gptel--process-tool-call short-circuit; :block → `<tool_call_error>` wrap (TODO "not final").
- `gptel--handle-post-tool` (L1551) — post-tool hooks; matches :tool-result entry by name + args-subset test (`(null (cl-set-difference stored-args args))` — one-directional, not exact equality), `(setf (caddr call))` destructive replace; display-warning '(gptel tools) if unmatched; does NOT inject-tool-call.
- `gptel--update-wait` (L1607) — " Waiting..." warning face. `gptel--update-tool-call` (L1613) — **direct `(setq gptel--fsm-last fsm)` bypassing the stripping function → mid-tool-call inspection retains full :data even with logging off**; " Calling tool(s) (…)". `gptel--update-tool-ask` (L1632) — one-shot consumes `:tool-pending` → " Run tools?".
- `gptel-send` (L1645) — prefix → gptel-menu (status untouched on that path — verified via `read` of the source); else sanitize, fresh FSM (send tables), gptel-request, "Querying BACKEND...", " Waiting...".
- `gptel--inspect-query` (L1677) — *gptel-query* editable dry-run viewer; `(bufferp (plist-get info :data))` = still-constructing sentinel → 1s self-cancelling polling timer (letrec); view-mode + composed keymap; C-c C-c resend, C-c C-w curl, C-c C-k quit.
- `gptel--continue-query` (L1734) — re-`read`s edited buffer into :data; curl copy via gptel-curl--get-args (kill-new); resume via fsm-transition INIT→WAIT; **hard-requires buffer-name "*gptel-query*"**; parse errors → generic user-error unless debug-on-error.
- `gptel--insert-response` (L1765) — non-streaming insert; outer with-current-buffer gptel-buffer BEFORE save-excursion (point protected even when called from another buffer — verified); inner with-current-buffer (marker-buffer start-marker) handles the *LLM response* redirect divergence; tracking marker gets insertion-type t "for uniformity"; second call prepends response separator (verified); reasoning recurses for open/text/close + folds.
- `gptel-curl--stream-insert-response` (L1841) — first chunk: separator+prefix, marker moves, tracking marker type t; per-chunk transformer→propertize→insert; post-stream-hook; point untouched (verified 2-chunk synthetic stream); tool-result chunks mid-reasoning re-home `:reasoning-marker` to tracking marker (extended-thinking-with-tools fix).
- `gptel` (L1889) — see inspector 6 (consistent); gptel-mode + restore run BEFORE initial text insertion; model sanitize uses default-values.
- `gptel--display-reasoning-stream` (L1941) — verified all four include-reasoning behaviors: t → block wrapped, TEXT propertized **response** (IS resent next turn); 'ignore → same visuals, propertized ignore; STRING → routed to side buffer, **end sentinel silently swallowed there** (no closing written); nil → full no-op. Skips duplicate header when reasoning-marker == tracking-marker.
- `gptel--display-tool-calls` (L2032–2143) — minibuffer path forced when USE-MINIBUFFER or read-only (buffer or insertion-point property); in-buffer: overlay REUSED across confirmation rounds — `'previews`/`'gptel-tool` props accumulate via nconc, `'prompt` sub-overlays via cons; ov-start via text-property-search-backward 'gptel 'response (FIXME fragile); confirm text read-only+font-lock-fontified; `(ignore-errors (backward-char))` keeps point inside overlay.

## Extra verified helpers (out-of-range, exercised): format-token-usage — "[in↑ out↓]" + `C` cached suffix omitted when 0 + stray leading space when :input absent; update-token-usage — request slot REPLACED (setcar) from tokens-full, session slot SUMMED from tokens, IDX defaults 1 (buffer view).

## STATE-CARRIERS (slice)
buffer-locals gptel--fsm-last/header-line-format/mode-line-process/left-margin-width · markers :position (re-homed on redirect) / :tracking-marker (t→nil lifecycle) / :reasoning-marker · overlays gptel-highlight, gptel-tool + prompt sub-overlays · INFO keys (full set incl. :end-time) · *LLM response* / *gptel-diagnostic* / *gptel-query* buffers · 1s polling timer (inspect-query) · kill-ring (curl copy) · hooks run: pre-response/post-stream/post-response/pre-tool/post-tool.
## gptel.el lines ~1077–3047 selections + 2100–end

## Highlight mode
- `gptel-highlight-methods` (defcustom L1077) — fringe/face/margin; decorate checks margin BEFORE fringe → margin silently wins.
- Faces L1092/L1101 (fringe face branches on emacs<29, #1254); `gptel-highlight-fringe` bitmap (L1112, global fringe table).
- `gptel-highlight--margin-prefix`/`--fringe-prefix` (L1123/L1135) — display-spec strings. `--decorate` (L1146) — overlay props evaporate/gptel-highlight/font-lock-face/line-prefix/wrap-prefix.
- `gptel-highlight--update` (L1164) — jit-lock: mirror `gptel` property transitions into gptel-highlight overlays (create/extend/split).
- `gptel-highlight-mode` (define-minor-mode L1195) — ±left-margin-width, jit-lock register/unregister, full pass on enable, remove-overlays on disable, set-window-buffer redisplay. Verified lifecycle exactly.

## Chat command
- `gptel` (defun L1889) — read-buffer predicate checks live buffer-local gptel-mode (#450); mode setup; sanitize-model; prefix at bobp; read-passwd fallback assigns `gptel-api-key`; display-buffer when interactive.

## Tool confirmation UI
- `gptel--tool-preview-alist` (defvar L2002) — name → (setup [teardown]) custom previews (experimental).
- `gptel-tool-call-actions-map` (L2025) — mouse-1 dispatch, C-c C-c/C-k/C-i.
- `gptel--display-tool-calls` (L2032) — minibuffer path when use-minibuffer OR buffer read-only OR insertion point has read-only prop (source comment: `TEMP(tool-preview) Handle read-only buffers better`); else overlay `gptel-tool` (props info/gptel-tool/mouse-face/help-echo/keymap/previews/prompt) + banner prompt-ov (evaporate, before/after-string "<Backend> wants to run:"); confirm text inserted read-only+font-lock-fontified.
- `gptel--display-tool-results` (L2145) — records via `(funcall :callback text info 'raw)`; region propertized `gptel (tool . ID)` both modes; markdown fences additionally `gptel ignore` + block keymap; org folded via org-cycle, md via cycle-block; maintains `:tool-marker`. Verified: `(tool . "toolid-123")` on [47,156); include='call → literal cache-notice string, real result ABSENT.
- `gptel--format-tool-call` (L2240) — "(name arg…)", newlines→⮐, 256-char truncation.
- `gptel--accept-tool-calls` (L2258) — teardown previews, delete prompt regions (inhibit-read-only), delete overlay; async tools get process-tool-result as first arg; sync in condition-case → stringified error result. Interactive spec pulls (resp . ov) from char property at point.
- `gptel--reject-tool-calls` (L2305) — same teardown; status " Tools cancelled" error face.
- `gptel--dispatch-tool-calls` (L2327) — read-multiple-choice y/n/k/i.
- Inspection: keymap (L2340); `gptel--inspect-accept-tool-calls` (L2346) — if modified: re-`read` each gptel-overlay region → gptel--inject-tool-call into :data + merge-plists into :tool-use (in-place), deleted sexp = call dropped; then accept. `--inspect-reject` (L2402), `--inspect-quit` (L2410). `gptel--inspect-tool-post-command` (L2415) — **single shared lexical highlight slot across all invocations (not buffer-local)** — concurrent inspect buffers would share highlight state. `gptel--inspect-tool-calls` (L2435) — lisp-data-mode buffer, calls written via plain prin1 with print-length/level nil (single-line, not pp-indented); overlay `gptel-overlay` = index into :tool-use (matched by name+args); sets buffer-local `gptel--fsm-last` wrapping INFO; `:tool-display` = (tool-calls tool-overlay).

## Presets
- `gptel--known-presets` (defvar L2503) — seeded with `gptel-default` (resets all options); append-ordered (nconc).
- `gptel-make-preset` (L2522) — setcdr in place if exists (position preserved — verified), else nconc.
- `gptel-get-preset` (L2626) — alist-get #'equal; **symbol keys: string lookup returns nil** (verified) — callers intern-soft first.
- `gptel--save-preset` (L2630) — snapshot → gptel-make-preset form eval'd + pp'd to kill-ring; directive symbol stored when system matches gptel-directives.
- `gptel--apply-preset` (L2666) — :pre → :parents (in order, recursively, same setter) → own keys → :post. Verified: parentA→parentB→child order (later wins); `:foo` → `gptel-foo` if bound else `gptel--foo` (both branches verified); unknown key → display-warning, silent no-op; modify-specs resolved against CURRENT value pre-setter.
- `gptel--preset-syms` (L2747) — symbols a preset would touch (recurses parents; :system → gptel-system-prompt specifically).
- `gptel-with-preset` (defmacro L2780) — let-binds every affected symbol to its CURRENT value then applies with #'set (cl-progv-like, #1005); verified full restore.
- `gptel--preset-mismatch-value` (L2801) — drift heuristic; modify-list specs = automatic mismatch.
- `gptel--transform-apply-preset` (L2853) — scan starts after `(text-property-search-backward 'gptel nil t)` (last non-nil-property text); verified: @cookie inside a response region untouched, later plain-text cookie stripped + preset applied buffer-locally (default value untouched); `@` must be at bob or after whitespace/word-boundary syntax (guards user@host).
- `gptel--fontify-preset-keyword` (L2882) — font-lock matcher; duplicates the boundary logic. `gptel-preset-capf` (L2891) — completion table IS gptel--known-presets alist. `gptel--prettify-preset` (L2908) — adds/removes font-lock keywords + capf buffer-locally; box face only for COMPLETE valid names.

## Variants
- `gptel--attach-response-history` (L2930) — one-shot local post-response hook; stamps gptel-history + front-sticky (gptel gptel-history) over [b,e); self-removes (verified).
- `gptel--ediff` (L2952) — region-wordwise ediff vs variant; scratch buffers + window-config restore via self-removing ediff-quit-hook; no `gptel-history` at point → entire body skipped (SILENT no-op, verified); the `user-error "…response is additive"` at L2982 is effectively dead — `(insert prev-response)` runs earlier inside the pcase-let* bindings and would crash on a nil first.
- `gptel--mark-response` (L3004) — push-mark/activate.
- `gptel--previous-variant` (L3011) — rotate: display history's car, displaced text appended to history END; new text propertized (gptel response + gptel-history) pre-insert; offset-clamped point; pulse. Verified exact rotation + round-trip via `gptel--next-variant` (L3037) = `(gptel--previous-variant (- arg))`.

## Experiments (9): preset parent order/mapping/warning; with-preset restore; cookie boundary; :append idempotent strings NOT lists (→ why tools dedup); attach-history one-shot + variant rotation; tool-results record + cache notice; highlight lifecycle; get-preset symbol-vs-string; make-preset position preservation.

## STATE-CARRIERS
`gptel--known-presets` · `gptel--preset` · `gptel--tool-preview-alist` · INFO `:position :tracking-marker :tool-marker :callback :tools :tool-use (in-place merges) :backend :data :tool-display :in-place :transformer :include-reasoning` · buffer-local `gptel--fsm-last` (inspect buffer) · overlays gptel-tool/gptel-overlay/gptel-highlight · text props gptel/gptel-history/read-only/front-sticky · buffer-locals left-margin-width, font-lock-keywords, completion-at-point-functions, one-shot post-response hooks · kill-ring (save-preset).
## gptel-openai.el + gptel-openai-extras.el

## gptel-openai.el
- `gptel-openai` (cl-defstruct L37) / `gptel-openai-responses` (L42) — backend structs, `:include gptel-backend`, no extra slots; ctors `gptel--make-openai`/`gptel--make-openai-responses`.
- `gptel--openai-update-tokens` (defun L47) — usage→INFO `:tokens` (:input net of cached, :output, :cached) + `:tokens-full` accumulate. Handles `prompt_tokens_details.cached_tokens` AND DeepSeek `prompt_cache_hit_tokens`.
- `gptel-curl--parse-stream` (defmethod gptel-openai L94) — SSE parser; point persists/rewinds on parse error. Writes `:tool-use :partial_json :reasoning :reasoning-chunks :reasoning-block`; on `[DONE]`: flatten args, inject assistant message into `:data :messages`, rewrite `:tool-use` to (:id :name :args), read usage from the data line preceding [DONE]. Notes (verified): `:partial_json` NOT cleared after [DONE] (stale fragments if INFO reused); litellm compat treats `:function :name` == string "null" as continuation; reasoning→text transition detected once (`:reasoning-block` → 'done gates further capture).
- `gptel--parse-response` (defmethod L183) — non-streaming; `:stop-reason`, tokens, tool-use; injects the raw message plist VERBATIM into `:data` — but ONLY inside the tool-calls branch (verified: a reasoning-only response with no tool_calls leaves `:data` untouched; reasoning survives replay only alongside tool calls); content and tool_calls checked independently (#819, llama.cpp).
- `gptel--request-data` (defmethod L217) — payload; verified: `:stream_options (:include_usage t)` only when streaming; `:tool_choice "required"` only under 'force (omitted otherwise); `:tools`/`:parallel_tool_calls t` only when gptel-tools non-nil; system pushed as first message.
- `gptel--parse-schema` (defmethod L252) — `{type:"json_schema", json_schema:{name,schema,strict:t}}`; **`:name` = md5 of `(random)` — fresh random name every call** (verified).
- `gptel--inject-tool-call` (defmethod L263) — edits/deletes call in the LAST message (FIXME hardcoded); drops the message if it was the only call; warns if not found.
- `gptel--parse-tool-results` (defmethod L300) — role "tool" messages, one per call. Pure.
- `gptel--openai-format-tool-id` (defun L312) — nil→random `call_`+24hex; `toolu_`/`call_` pass through; else prepend `call_`. `gptel--openai-unformat-tool-id` (L325) — strips only `call_`; `toolu_` ids fall through unchanged (round-trips fine in practice); zero call sites anywhere — dead code. Both TODO-removal (#792).
- `gptel--parse-list` (defmethod L334) — simple + advanced list formats; `(tool . call)` expands to TWO messages (assistant tool_calls + tool result); mutates the call plist (assigns `:id` if absent).
- `gptel--parse-buffer` (defmethod L365) — backward property walk. Notes: `max-entries` decrements ONLY on user (nil-property) regions — tool/response regions are free; whole-buffer-as-user fallback when neither gptel-mode nor track-response.
- `gptel--openai-parse-multipart` (defun L421) — parts → text/image_url vector; prefix-trim only first/last text part.
- `gptel--inject-media` (defmethod L459) — prepends context media into first prompt's `:content` via cl-callf (string content → vector first).
- `gptel--openai-models` (defconst L473) — model metadata; every entry lists `responses-api` capability.
- `gptel-make-openai` (cl-defun L731) — registers backend; **host-sniff `(string-match-p "api\\.openai\\.com" host)` is an UNANCHORED substring match** (verified: "api.openai.com.evil.org" also dispatches to Responses); Responses branch lazily requires gptel-openai-responses, endpoint /v1/responses.
- `gptel-make-azure` (cl-defun L823) — plain gptel-openai struct always (no sniffing); `api-key` header.
- `gptel-make-gpt4all` (defalias L892) — alias of gptel-make-openai.

## gptel-openai-extras.el
- `gptel-privategpt` (cl-defstruct L42) — `:include gptel-openai` + slots `context sources`.
- `gptel--privategpt-parse-sources` (defun L47) — "Sources:" block; pages print in REVERSE encounter order (push, never nreversed — verified).
- privategpt `gptel-curl--parse-stream` (L63) — full replacement (not cl-call-next-method); NO tool handling (FIXME); `:sources` captured once.
- privategpt `gptel--parse-response` (L83) — no token/stop-reason bookkeeping AT ALL for this backend.
- privategpt `gptel--request-data` (L89) — adds `:use_context`/`:include_sources`; ignores tools/schema/stream_options entirely.
- `gptel-make-privategpt` (cl-defun L112) — **docstring/code mismatch**: docstring says host "api.privategpt.com" endpoint "/v1/messages"; actual defaults `localhost:8001` + `/v1/chat/completions` + http.
- `gptel-perplexity` (cl-defstruct L180); `gptel--perplexity-parse-citations` (defsubst L184) — numbered [n] url block.
- perplexity `gptel--parse-response` (L192) — cl-call-next-method + citations appended (verified). `gptel-curl--parse-stream` (L199) — delegates then one-shot `:citations` guard; locates the citations chunk by searching BACKWARD for INFO `:uuid` then nearest `data:` line.
- `gptel-make-perplexity` (L222) — sonar* models, no metadata plists.
- `gptel-deepseek` (cl-defstruct L280) — also the literal struct type for xAI (no gptel-xai struct).
- deepseek `gptel--parse-buffer :around` (L284) — merges adjacent same-role text-only messages in place (setcdr/plist-put); skips tool-call entries (no `:content`); handles string and vector content (verified with response/ignore/response property layout).
- deepseek `gptel--request-data :around` (L310) — `:response_format (:type "json_object")` + schema prin1'd into messages[0] content. **Latent bug (verified): splices into messages[0] regardless of role — corrupts the first user message when no system prompt exists.**
- `gptel-make-deepseek` (L327) — default models declare `:capabilities (tool reasoning)` — **singular `tool`, not `tool-use`** (inconsistent with every other model list; would fail a `gptel--model-capable-p 'tool-use` check — currently DORMANT: the only such gate, gptel-request.el:2338, is commented out).
- `gptel-make-xai` (L366) — calls `gptel--make-deepseek`: xAI backends ARE gptel-deepseek structs (verified `type-of`), inheriting BOTH DeepSeek :around methods (role merge + schema rewrite) undocumented.

## Experiments (11) — host-sniff swap + unanchored match; payload shapes; SSE reassembly (2-fragment tool args; usage 50-5cached→input 45; stale partial_json); verbatim message injection incl. reasoning; tool-id (un)format asymmetry; perplexity citations; privategpt reverse pages; deepseek merge (needed ignore-separated regions to test — base parser never splits same-property runs); deepseek schema rewrite; xai type-of.

## STATE-CARRIERS
`gptel--known-backends` (all constructors) · INFO keys `:tool-use :partial_json (stale after DONE) :reasoning :reasoning-chunks :reasoning-block :tokens :tokens-full :stop-reason :sources (privategpt) :citations (perplexity) :data` · dynamic request vars read · `gptel` text property read (never written) · model symbol plists via gptel--process-models.
## gptel-openai-responses.el + gptel-oauth.el + gptel-openai-oauth.el

## gptel-openai-responses.el
- `gptel--openai-responses-update-tokens` (defun L36) — usage → INFO `:tokens` (input net of cached) + `:tokens-full`. Verified: input 10/cached 2 → :input 8.
- `gptel-curl--parse-stream` (defmethod L53) — event-typed SSE. Verified: deltas concatenate in order; **tool call reconstructed from `response.output_item.done`'s full `:arguments` string, NOT from `:partial_json`** (which is write-only accumulation, reset to nil at done); `response.completed` wraps usage/status under `:response`; tool calls re-injected into `:data :input` as function_call items; `error` SSE event parsed as data (HTTP 200); truncated trailing event → point rewound before dangling `event:` line (retry).
- `gptel--parse-response` (defmethod L144) — output[] by type; reasoning prefers `:content` over `:summary`; message items may carry output_text AND refusal parts.
- `gptel--request-data` (defmethod L222) — verified: `:store :json-false` UNCONDITIONAL; temperature omitted only for literal `memq` list `o1 o1-preview o1-mini o3-mini o3 o4-mini` (new o-models would get temperature until list updated); schema at `:text (:format …)`; force → `:tool_choice "required"`.
- `gptel--parse-schema` (defmethod L268) — returns the inner schema plist (:type/:name/:schema/:strict; `:name` = md5(random)), NOT the full text.format wrapper; zero call sites for this backend — request-data duplicates the logic inline (dead code).
- `gptel--parse-tools` (defmethod L277) — flat specs; no-arg tool → `:parameters (:type "object" :properties nil)` with no required/additionalProperties.
- `gptel--inject-tool-call` (L327) — keyed by call id; delete splices vector; edit mutates located plist in place; warns if id missing.
- `gptel--parse-tool-results` (L355) — function_call_output items. Pure.
- `gptel--inject-prompt` (L366) — into `:input`; keywordp car distinguishes single item vs list.
- `gptel--parse-list` (L387) — tool entry expands to TWO items (function_call + function_call_output); assigns id via format-tool-id if absent (mutates call plist).
- `gptel--parse-buffer` (L414) — backward walk; ignore regions skipped; tool regions `read` the stored sexp, re-derive JSON `:arguments`; parse failure → `message`, not error.
- `gptel--openai-responses-parse-multipart` (L467) — input_text/input_image; trim only first/last text part.
- `gptel--inject-media` (L505) — first prompt content; bare string normalized to input_text vector.
- `gptel-make-openai-responses` (cl-defun L520) — registers; header closure resolves key at request time.

## gptel-oauth.el
- `gptel-oauth--write-token` (L35) — prin1 plist → FILE; parent dirs auto-created (verified multi-level); utf-8-unix, :silent.
- `gptel-oauth--read-token` (L46) — read back; missing file / reader-error garbage (unbalanced syntax, empty) → nil silently, BUT token-shaped garbage `read`s to a non-plist atom (`"42"` → 42, prose → a symbol — verified) that flows downstream un-validated; insert-file-contents-literally + utf-8-auto-dos (tolerates CRLF).
- `gptel-oauth--base64url-encode/-decode` (L63/L72) — RFC 4648 §5, no padding; round-trip incl. non-ASCII verified.
- `gptel-oauth--generate-code-verifier` (L83) — 128 chars from unreserved set; elisp `random` (not CSPRNG — acceptable: only the hash is transmitted).
- `gptel-oauth--generate-code-challenge` (L92) — base64url(sha256(v)); **verified against RFC 7636 Appendix B.1 test vector, exact match**.
- `gptel-oauth--device-auth-prompt` (L99) — clipboard write (ignore-errors), browse-url unless SSH (SSH_CLIENT/SSH_CONNECTION/SSH_TTY), blocking minibuffer.
- `gptel-oauth--jwt-payload` (L126) — decode middle segment; colon-bearing claim keys become single keywords (verified); NO signature verification (by design); all errors → nil.

## gptel-openai-oauth.el
- Constants: client id `app_EMoamEEZ73f0CkXaXp7hrann` (L29), auth URL (L30), token file `.cache/gptel-openai/openai-oauth-token` under user-emacs-directory (L33; TODO: single file shared by ALL OAuth backends — they clobber each other), login-method defcustom (L37), redirect port 1455 / timeout 300s / path /auth/callback (L48–50).
- `gptel-openai-oauth` (cl-defstruct L53) — `:include gptel-openai-responses` + slot `token`; instances satisfy responses-p (verified) → all Responses generics reused; request-data is the sole defmethod override (the differing header is just a struct-slot default, not a method).
- `gptel--request-data` (defmethod L58) — strips `:temperature` AND `:max_output_tokens` **unconditionally on model** with display-warnings (verified both fire for gpt-5.2) — stricter than parent.
- Poll: interval 2s (L78), timeout 30s total (L79 — only ~15 attempts, vs 300s for the code flow); `gptel--openai-oauth-poll-token` (L83) — sync POSTs, sleep-for, `:error` in a poll → immediate user-error.
- `gptel--openai-oauth-login-with-device-code` (L119) — fixed remote redirect_uri `https://auth.openai.com/deviceauth/callback` (no local server).
- `gptel--openai-oauth-authorization-url` (L147) — PKCE + scope "openid profile email offline_access" + nonstandard flags codex_cli_simplified_flow=true/originator=gptel/prompt=login.
- `gptel--openai-oauth-callback-request` (L167) / `-send-callback-response` (L180) — hand-rolled HTTP parse/respond over the network process.
- `gptel--openai-oauth-read-code` (L193) — `make-network-process` server on localhost:1455; filter buffers partial requests via process-put `:gptel-request` until `\r\n\r\n`; user-error over SSH; unwind-protect delete-process.
- `gptel--openai-oauth-login-with-authorization-code` (L270) — state = sha256(float-time+random).
- `gptel--openai-oauth-default-backend` (L294) — current backend if OAuth, else first in registry, else user-error (all 3 branches verified).
- `gptel-openai-oauth-login` (interactive L304) — dispatch per login-method; success message only when interactive AND :access_token present.
- `gptel--openai-oauth-persist` (L330) — requires access_token+expires_in+refresh_token else user-error; `:id_token` stored PRE-DECODED (JWT payload plist); expires_in → absolute `:expires_at` = float-time+TTL (round-trip verified).
- `gptel--openai-oauth-refresh` (L348) — refresh grant; omits code_verifier (correct — PKCE binds only the original request).
- `gptel--openai-oauth-ensure` (L362) — slot → disk → refresh (<10s to expiry) → login, all in one call; expired-on-disk token refreshed immediately.
- `gptel--openai-oauth-header` (L385) — ensure + Authorization/Originator/ChatGPT-Account-Id; account id from claim `https://api.openai.com/auth`.chatgpt_account_id else organizations[0].id (first org — potentially wrong for multi-org users).
- `gptel-make-openai-oauth` (cl-defun L406) — host chatgpt.com, endpoint /backend-api/codex/responses, stream t, `:key` always nil; gpt-5.* model list OVERLAPS the plain Responses defaults heavily (7 of 9 appear verbatim in `gptel--openai-models`; only gpt-5.3-codex/-spark are OAuth-exclusive).

## Experiments (8): payload shapes (store/temperature/schema/tool_choice); SSE parse incl. truncated-event rewind + error event; PKCE RFC vector; base64url; token file round-trip + auto-mkdir; JWT decode; struct inheritance + unconditional stripping; persist/ensure/default-backend branches.

## STATE-CARRIERS
Token FILES (single shared path — clobber hazard) · localhost:1455 listener + sync HTTP (poll/exchange/refresh) · browse-url + clipboard · backend struct `token` slot (in-memory) · `gptel--known-backends` · INFO `:tokens :tokens-full :tool-use :partial_json :reasoning :reasoning-block :stop-reason :error` · `:data :input` vector mutations.
## gptel-anthropic.el + gptel-gemini.el

## Anthropic
- `gptel--anthropic-update-tokens` (L43) — 4 usage fields → :tokens/:tokens-full; cache-WRITE tokens folded into :input. Comment L60-70: NEVER convert plist-put info to push/setf (reference semantics).
- `gptel-curl--parse-stream` (defmethod L76) — SSE event parse; writes :partial_json :tool-use :reasoning :reasoning-block(nil→'in→t) :signature :stop-reason :tokens :partial_text :partial_reasoning; on message_delta with tools, appends assistant message to :data :messages. Verified: replayed message built from `copy-sequence` of the call BEFORE the reshape → replay keeps wire-format `:input` while info :tool-use gets internal :args; thinking content_block_start OVERWRITES :reasoning, deltas concat; :partial_reasoning only populated when (info :tools); malformed event → condition-case rewinds point to event start (resume next chunk). Docstring: "Not my best work, I know."
- `gptel--parse-response` (L182) — same append-raw-then-reshape ordering (verified).
- `gptel--request-data` (L223) — verified: :max_tokens ALWAYS present (4096 default); :stream ALWAYS present (:json-false when off); force → tool_choice (:type "any"); cache_control gated on gptel-cache + model capability, spliced onto LAST tool only (nconc on aref); **response_json schema tool prepended UNCONDITIONALLY — even when gptel-use-tools is nil** (verified: tools = [response_json] with use-tools nil).
- `gptel--parse-schema` (L271) — schema → response_json tool spec. NOT pure: `gptel--preprocess-schema` plist-puts `:additionalProperties :required :propertyOrdering` onto the caller's schema object in place (verified).
- `gptel--parse-tools` (L280) — {name, description, input_schema}; forces :required [] on object args; comment: Anthropic wants {} not null for no-arg (verified via json-serialize: nil-properties → {}).
- `gptel--parse-tool-results` (L315) — user message with tool_result blocks, :is_error t on error. Pure.
- `gptel--inject-tool-call` (L340) — locate by :id in LAST message (FIXME); edit via plist-put; deleting the SOLE tool_use block removes the ENTIRE message (verified); display-warning fallback.
- `gptel--anthropic-format-tool-id` (L376) — nil→toolu_+24hex(md5 of random+float-time); call_/toolu_ pass through; else prepend toolu_. `--unformat-tool-id` (L386) strips toolu_ only. TODO removal #792.
- `gptel--parse-list` (L391) — advanced/simple; auto toolu_ ids; last-message cache splice as parse-buffer.
- `gptel--parse-buffer` (L427) — backward property walk; whitespace-skip guard applies to EVERY segment type (not just user, despite comment); issues #452/#409/#406/#351/#321; 'ignore dropped.
- `gptel--anthropic-parse-multipart` (L498) — text/media/textfile → blocks; only image/* + application/pdf; errors on others; trim first/last text only.
- `gptel--inject-media` (L543) — first prompt content via cl-callf.
- `gptel--anthropic-models` (L566), `gptel-make-anthropic` (L698) — header: x-api-key, anthropic-version 2023-06-01, anthropic-beta extended-cache-ttl-2025-04-11 (unconditional); registers.

## Gemini
- `gptel--gemini-update-tokens` (L44) — :output = total − prompt; :input = prompt − cached.
- `gptel-curl--parse-stream` (L62) — JSON-array streaming: loop search-forward "{" + json-parse-buffer (ignores [ , ] tokens); parse error → goto match-beginning, stop; per-object delegates to gptel--parse-response with include-text; TODO alt=sse. Coarser than SSE (no per-event resume subtlety).
- `gptel--parse-response` (L82, +include-text) — candidates[0].content.parts split into thought/text/functionCall; verified: thought:true → :reasoning (excluded from text), :reasoning-block 'in→t on first non-thought part; functionCall verbatim `(copy-sequence)` into :tool-use (no reshape — already {name,args}); **streaming chunks with existing trailing "model" role entry get parts vconcat'd into it (merge, not append — verified)**; stop-reason/tokens only on terminal chunk (finishReason present).
- `gptel--request-data` (L130) — verified: safetySettings ALWAYS the 4 hardcoded categories BLOCK_NONE; systemInstruction key ABSENT (not nil) when no system prompt; force → toolConfig functionCallingConfig mode ANY; generationConfig key omitted entirely when empty; **`gptel-include-reasoning` default 'ignore is truthy → :thinkingConfig (:includeThoughts t) included BY DEFAULT** (only explicit nil suppresses).
- `gptel--parse-schema` (L177) — responseMimeType + responseSchema (native; no tool emulation).
- `gptel--gemini-filter-schema` (L182) — recursively strips :additionalProperties (incl. anyOf/allOf, nested, array items — verified) — i.e. generic preprocessor ADDS it, Gemini strips it back out; keeps :required/:propertyOrdering. Destructive on arg.
- `gptel--parse-tools` (L203) — single {functionDeclarations [...]} wrapper; no-arg tool → :parameters :null (verified via json-serialize → null); strips :format from string args.
- `gptel--parse-tool-results` (L244) — user message, functionResponse {name, response {name, content}} (name doubled).
- `gptel--inject-prompt` (L259) — into :contents; nil append, negative = from-end splice-insert (verified). (Anthropic uses the generic default instead.)
- `gptel--inject-tool-call` (L274) — match by :name AND :args value equality in LAST message (no ids); ambiguous for identical parallel calls (unguarded); display-warning fallback.
- `gptel--parse-list` (L312) — role user/model; no id generation.
- `gptel--parse-buffer` (L340) — **NO whitespace-only-segment skip (asymmetry vs Anthropic — confirmed by full-file comparison)**; role "model".
- `gptel--gemini-parse-multipart` (L389) — text/inline_data; **no MIME allowlist/validation** (vs Anthropic's error).
- `gptel--inject-media` (L423) — media parts prepended to first prompt's :parts.
- `gptel--gemini-models` (L433) — **duplicate-key artifact: gemini-flash-lite-latest + gemini-2.5-flash-lite each have TWO :capabilities entries; plist-get returns the FIRST → audio/video advertised-but-dead for those two models** (source-inspected).
- `gptel-make-gemini` (L652) — X-goog-api-key header; **function-valued :url** re-evaluates (and stream ∧ gptel-use-curl ∧ gptel-stream) per request — a stream-t backend can hit generateContent if gptel-stream is later nil.

## Experiments (6 suites, ~30 sub-tests) — request-data shapes both backends; SSE + JSON-array stream parsing over synthetic buffers; append-then-reshape ordering; whitespace skip; inject-tool-call by id vs name+args; format/unformat ids; filter-schema recursion; thinkingConfig default-on discovery. (First Gemini stream attempt failed silently for lack of :backend in the fake INFO — parse-stream needs it to dispatch; reminder that INFO and gptel-backend are separate channels.)

## STATE-CARRIERS
INFO keys as listed (incl. Anthropic-only :partial_json/:partial_text/:partial_reasoning/:signature) · :data :messages/:contents appends (Gemini merges same-turn chunks) · gptel--known-backends · process-buffer point (backward walks + stream consumption) · model symbol plists (via process-models at construction).
## gptel-ollama.el + gptel-kagi.el + gptel-bedrock.el

## Ollama
- `gptel--ollama-update-tokens` (L40) — prompt_eval_count/eval_count → :tokens/:tokens-full.
- `gptel-curl--parse-stream` (L56) — JSONL; skips non-JSON preamble (bobp + ^{ search); tool_calls injected via inject-prompt; done → tokens + goto point-max, **but the failed re-parse at EOF rewinds point to just after the last JSON object (one byte behind buffer end)** — verified quirk.
- `gptel--parse-response` (L96) — stop-reason/tokens/reasoning/tool-use; assistant message appended on tool calls.
- `gptel--request-data` (L124) — verified: :stream :json-false when off; :format = PREPROCESSED schema only when set; :options temperature/num_predict fill ONLY when absent from merged request-params; :options key present with nil value when nothing applies.
- `gptel--parse-tool-results` (L161) — "tool"-role messages. `gptel--inject-tool-call` (L170) — by name+args in last message (FIXME). `gptel--parse-list` (L208), `gptel--parse-buffer` (L233), `gptel--ollama-parse-multipart` (L280 — trim first/last only), `gptel--inject-media` (L312 — :images prepend), `gptel-make-ollama` (L324).

## Kagi
- `gptel--parse-response` (L37) — :data :output + references formatted per target major-mode (org/markdown links or buttonize); :tokens input=output=same count.
- `gptel--request-data` (L78) — fastgpt → +:web_search t :cache t; "summarize:X" → :engine via `(substring model 10)` (verified); **pcase-exhaustive errors on unknown models**.
- `gptel--parse-buffer` (L86) — summarize: {:url} if URL at point else {:text}; fastgpt {:query}; last user region via text-property-search-backward.
- `gptel-make-kagi` (L123) — **URL/payload inconsistency (verified): the :url closure only special-cases `(equal gptel-model 'fastgpt)` — any other symbol (even undeclared) silently gets the /summarize URL, while request-data would error on it.**

## Bedrock
- `gptel-bedrock` struct (L36) — +slot model-region (global/apac/eu/us).
- `gptel--bedrock-update-tokens` (L41) — cache-write folded into :input, :cached separate.
- `gptel-bedrock--prompt-type` (defconst L62) — documentation-only, never referenced.
- `gptel--request-data` (L81) — maxTokens default **500**; system + cachePoint; toolConfig. **BUG verified end-to-end through real gptel--json-encode: `'(:any '())` inside backquote = (quote nil) → wire JSON `"toolChoice":{"any":{"quote":{}}}` (force) / `{"auto":{"quote":{}}}` (t).**
- `gptel--parse-tools` (L106) — wraps cl-call-next-method output in toolSpec/inputSchema.json. (Harness note: :json-false needs gptel's wrapped encoder, not bare json-serialize.)
- `gptel--parse-response` (L121) / `gptel-bedrock--record-tool-use` (L135) — message appended (vconcat) + {:name :args :id} tuples.
- `gptel--parse-list` (L153), `gptel--inject-media` (L163).
- `gptel-bedrock--stream-cursor` (defvar-local L171) — **primary streaming state: buffer-local marker of consumption progress; nil until HTTP headers validated** (Content-Type vnd.amazon.eventstream asserted; cl-return bails leaving nil if headers incomplete → next chunk retries).
- `gptel-curl--parse-stream` (L174) — loops parse-stream-message; events accumulated in INFO `:accumulated-events` (cleared per messageStop); metadata → tokens; contentBlockDelta text streamed; messageStop → assemble + record tools + :stop-reason + :message-complete.
- `gptel-bedrock--parse-stream-message` (L221) — frame = 12-byte prelude + headers + JSON + 4-byte CRC; returns nil on truncation with point unmoved (verified synthetic single + double frames); CRCs never validated (message CRC skipped outright, prelude CRC swept up unused — all-zero fake CRCs parse fine).
- `gptel-bedrock--parse-headers` (L271) — TLV parse. **Latent BUG verified by byte-injection: reads the 2-byte value-len field UNCONDITIONALLY for every type — spec-correct fixed-width headers (bool/int32/…) with no length field throw args-out-of-range. Never triggered because Bedrock's real headers (:message-type/:event-type/:content-type) are always string-type (7).**
- `bytes-to-int16/32/64` (L310/317/326) — big-endian signed; int64 via bignums; boundary values verified. `bytes-to-uuid` (L342) — 16 bytes → canonical hex.
- `gptel-bedrock--assemble-content-blocks` (L354) — group by contentBlockIndex; tool :input JSON = mapconcat of delta fragments with NO separator then one json-read (verified split reassembly); **reasoning blocks explicitly discarded** (future extension comment); unknown event type errors.
- `gptel--parse-buffer` (L397) — backward walk; skips blank separators (avoids empty {} blocks); toolUse/toolResult reconstruction.
- `gptel-bedrock--image-formats` (L463 — image/jpg AND image/jpeg → "jpeg") / `--doc-formats` (L471).
- `gptel-bedrock--parse-multipart` (L483) — text/image/document blocks; errors on unsupported MIME.
- `gptel--inject-tool-call` (L523) — by :toolUseId in last message. `gptel--parse-tool-results` (L561) — one user message, toolResult blocks.
- `gptel-bedrock--aws-profile-cache` (defvar L578) — (PROFILE . creds-hash) cache; verified cache-hit avoids subprocess; expired → exactly ONE forced retry then user-error.
- `gptel-bedrock-aws-cli-command` (L581) — executable-find "aws" at load; overridable (stub-testable).
- `gptel-bedrock--fetch-aws-profile-credentials` (L587) — `aws configure export-credentials [--profile=P]`; :static omits --profile (verified).
- `gptel-bedrock--get-credentials` (L617) — **profile (arg or AWS_PROFILE env) wins unconditionally over static env creds** (verified); env creds only when no profile resolvable; user-error if neither.
- `gptel-bedrock--model-ids` (L641) — symbol→id map, user-extensible via push. `gptel--bedrock-models` (L680) — **snapshot at load time (mapcar) — later pushes to model-ids do NOT update it**.
- `gptel-bedrock--get-model-id` (L684) — region prefixes global./apac./eu./us. verified + both error paths.
- `gptel-bedrock--curl-args` (L696) — bearer branch (arg or AWS_BEARER_TOKEN_BEDROCK) plain Authorization; else sigv4 --user/--aws-sigv4 + x-amz-security-token; --output /dev/stdout except Windows.
- `gptel-bedrock--curl-version` (L716) — shell-command-to-string curl --version.
- `gptel-bedrock--base-url` (L724) — **scheme-carrying HOST silently overrides PROTOCOL arg** (verified).
- `gptel-make-bedrock` (L742) — curl ≥8.9 gate SKIPPED entirely with a bearer token (verified: sandbox curl 7.81 errors without one); host derived from region; the `:url` closure (takes INFO) re-resolves the LIVE registered backend per request, but `:curl-args` is a ZERO-arg closure over the registration-time region/profile/bearer-token — a fixed snapshot, never re-resolved (verified via func-arity + live slot mutation); :coding-system 'binary only when STREAM.

## Experiments (11 suites): ollama payload/JSONL/rewind quirk; kagi payloads + URL/payload mismatch; bedrock TLV bug byte-injection; synthetic frames; int signedness; toolChoice quote bug e2e; model-id regions; fake-aws credential cache/expiry/priority; assemble-content-blocks reassembly; base-url override; bearer curl-args.

## STATE-CARRIERS
`gptel-bedrock--stream-cursor` (buffer-local marker — THE Bedrock stream state) · INFO :accumulated-events (Bedrock, mutable cell) :message-complete + standard keys · `gptel-bedrock--aws-profile-cache` · env vars AWS_* · subprocesses: aws CLI, curl --version · `gptel--bedrock-models` load-time snapshot · registries.
## gptel-gh.el + gptel-integrations.el

## gptel-gh.el
- `gptel--gh-models` (defconst L31) — 23 Copilot models (GPT/Claude/Gemini) with metadata.
- `gptel--gh` (cl-defstruct L227) — `:include gptel-openai` + slots `token github-token sessionid machineid responses-backend`; instances are gptel-openai/gptel-backend too (verified accessors).
- `gptel-gh-github-token-file` (defcustom L232) — `.cache/copilot-chat/github-token`; `gptel-gh-token-file` (L238) — `.cache/copilot-chat/token` (session token plist :token/:expires_at).
- `gptel--gh-auth-common-headers` (L244) — editor-plugin-version/editor-version/User-Agent (embeds emacs-version).
- `gptel--gh-client-id` (L249) — "Iv1.b507a08c87ecfe98".
- `gptel--gh-uuid` (L252) — v4-shaped; variant nibble hardcoded "8" (not spec-random; harmless).
- `gptel--gh-machine-id` (L261) — 65 lowercase hex (one longer than VS Code's real 64 — cosmetic); generated per construction, stored in slot (stable per backend, verified).
- `gptel-gh-login` (interactive L270) — device flow: github.com/login/device/code → browser/clipboard → login/oauth/access_token; persists github-token file + slot. Backend pick: current if gh-p → first gh in registry → user-error.
- `gptel--gh-renew-token` (L319) — GET api.github.com/copilot_internal/v2/token with `authorization: token <github>`; caches token file + slot; on failure NILS github-token and user-errors (forces re-login next auth).
- `gptel--gh-auth` (L336) — ensure github-token (disk→login) + session token (disk→renew); expiry vs `(round (float-time))`; token without :expires_at = never expires.
- Delegating cl-defmethods (L360–419): `gptel-curl--parse-stream` + `gptel--parse-response` key the responses-api check off **INFO `:model`**; ALL other nine methods (request-data, parse-schema, parse-tools, inject-tool-call, parse-tool-results, inject-prompt, parse-list, parse-buffer, inject-media) key off the **GLOBAL `gptel-model`** (verified behaviorally — binding global changed vision header; info :model did not).
- `gptel-make-gh-copilot` (cl-defun L422) — builds gh struct + embedded `gptel-openai-responses` shadow backend (endpoint /v1/responses, SAME `eq` header closure → auth state shared); `:url` closure switches endpoint per-call on global gptel-model's responses-api capability (verified gpt-4o→chat, gpt-5-mini→responses). Header closure: authorization Bearer, openai-intent, x-request-id (uuid per call), vscode-sessionid/machineid, copilot-vision-request (from GLOBAL gptel-model + gptel-track-media), **x-initiator: first call per request "user", then mutates INFO in place `:gh-initiator "agent"` → subsequent calls "agent"** (verified), copilot-integration-id.

## gptel-integrations.el
- vterm forward decls (L44–51). `gptel--vterm-delete` (L53) — region delete via vterm-delete-region, fallback char-by-char backspace bounded by vterm-cursor-in-command-buffer-p. `gptel--vterm-pre-insert` (L79) — relocates INFO `:position` marker into hidden buffer `" *gptel-vterm-redirect*"`, saves `:vterm-marker`, one-shot depth-90 local post-response hook copies result via vterm-insert and kills the buffer.
- MCP forward decls (L100–109): **`mcp-server-connections` declared with NO value → void-variable if referenced before mcp loads.**
- `gptel-mcp-connect` (interactive L111) — require mcp-hub or clean `user-error "Could not find mcp!  Please install or configure the mcp package"` (verified); skips already-registered `mcp-<name>` categories; starts servers (async with callback, or sync when SERVER-CALLBACK truthy-non-function); registers via gptel-make-tool + activates.
- `gptel-mcp-disconnect` (interactive L191) — removes category tools from gptel-tools + gptel--known-tools; y-or-n-p server shutdown. **BUG (verified): called cold with mcp absent → `(void-variable mcp-server-connections)` crash, not user-error** — the no-MCP-tools fallback branch dereferences it unconditionally. The menu suffix's `:inapt-if` guards this path, but `M-x gptel-mcp-disconnect` crashes.
- `gptel-mcp--get-tools` (L244) — connected servers' tools → gptel tool specs tagged `:category "mcp-<server>"` (only mcp--status 'connected).
- `gptel-mcp--activate-tools` (L264) — cl-pushnew onto `gptel-tools`; dedup works by IDENTITY because gptel-get-tool returns the same interned struct object.
- `gptel--suffix-mcp-connect` (transient suffix "M+", L273, inside with-eval-after-load gptel-transient) — connect + merge activated tools into the gptel-tools transient scope `:tools`; user-errors demoted to message; guards `(eq (oref transient--prefix command) 'gptel-tools)`.
- `gptel--suffix-mcp-disconnect` ("M-", L298) — dynamic description ("Remove MCP server tools" vs "Shut down MCP servers"); `:inapt-if` when mcp unconfigured/no connections.
- Menu surgery (L324–328): transient-remove-suffix (0 2) + append the MCP column; deferred via `with-eval-after-load 'gptel-transient` (feature-based; no fboundp check anywhere in the file).

## Experiments (6): struct/backend shape + embedded responses-backend eq-header; URL endpoint switching per model; machine-id/uuid shapes + stability; x-initiator in-place INFO mutation; vision header global-var dependence; MCP cold-start user-error vs void-variable crash.

## STATE-CARRIERS
Token FILES `.cache/copilot-chat/{github-token,token}` · clipboard + browser · gh struct slots (token/github-token/machineid/responses-backend; `sessionid` is declared but never assigned — the vscode-sessionid header is always "") · GLOBAL `gptel-model` read by 9/11 delegating methods (+vision header) · INFO `:model :gh-initiator :position :vterm-marker` · `gptel--known-backends` `gptel-tools` `gptel--known-tools` · gptel-tools transient scope `:tools` · `gptel-post-response-functions` (vterm one-shot) · model symbol plists (shared across backends registering the same symbols).
## gptel-context.el

- Faces L41/L48 (highlight :extend t; deletion reddish). `gptel-context-wrap-function` (L61) obsolete. `gptel-context-string-function` (L69) — sync/async by func-arity. `gptel-context-restrict-to-project-files` (L96, default t).
- `gptel-context--project-files` (L105) + `--reset-cache` (L108) — memoized project files + debounced run-at-time(0) cache-buster armed by --add-directory/--collect.
- `gptel-context-add-current-kill` (L113) — hidden buffer `" *gptel-kill-ring-context*"`; no ARG = replace (kill-region+insert — **the replace kill evaporates the prior overlay itself, leaving one dangling dead reference in gptel-context until next collect** — verified), ARG = append `\n----\n`.
- `gptel-context-add` / `gptel-add` (L128/223) — dwim dispatch (region/dired/ibuffer/image/prefix/toggle); `(interactive "P\np")` → confirmations suppressed mainly on programmatic calls.
- `--add-buffer` (L225, advance=t), `--add-text-file` (L231, cl-pushnew equal), `--add-binary-file` (L237, media+mime gates), `--add-directory` (L250 — per-file delegation, mime CORRECT here), `gptel-context-add-file`/`gptel-add-file` (L270/283).
- `--get-project-files` (L286), `--skip-p` (L293), `--message-skipped` (L302 — plain fallback if project cache entry missing).
- `gptel-context-remove` (L315) — polymorphic; buffer alist entry cleared only when the LAST live overlay is removed (verified; quadratic FIXME). `gptel-context-remove-all` (L352) — resets to nil.
- `gptel-context--make-overlay` (L371) — `(make-overlay start end nil (not advance) advance)` + evaporate/face/gptel-context t. **Verified advance semantics: region (advance=nil) → insert at start moves start forward (excluded), insert at end excluded; whole-buffer (advance=t) → both ends included (grows).**
- `gptel-context--wrap` (L386) — string-fn (sync/async) → --wrap-in-buffer → CALLBACK.
- `--wrap-in-buffer` (L402) — 'system: prepend/set gptel-system-prompt (string/function/list); nosystem → silent redispatch to 'user; 'user: `text-property-search-backward 'gptel nil t` → **on a buffer with NO gptel-tagged text anywhere, lands at point-min → context inserted at buffer START** (verified; correct in real chat buffers where responses are tagged).
- `--collect-media` (L440) — path entries with :mime → (:media . entry).
- `--add-region` (cl-defun L450) — removes overlapping overlays first (verified replace-not-stack).
- `--in-region` (L462), `--at-point` (L469).
- `gptel-context--collect` (L475) — normalizes; **mutates gptel-context's plists IN PLACE (prunes dead overlays) as a side effect of being "read"** (verified); dead buffers/unreadable files excluded from output but LEFT in gptel-context; directory expansion; **verified directory-MIME bug at ~L508: `(mailcap-file-name-to-mime-type entry)` uses the DIRECTORY name — dir literally named weird.png yields :mime "image/png" for its files**.
- `--collect-regions` (L516) — :bounds/:overlays/:lines → sorted (START . END) pairs; moves point without restoring (without-restriction).
- `--insert-buffer-string` (L547) — fenced excerpt with `... (Line N)` markers/leading-trailing `...`; exact output verified byte-for-byte.
- `--insert-file-string` (L590) — whole-file fast path; line/bounds excerpts reuse an UNMODIFIED visiting buffer else temp `" *gptel-file-context*"` — **edited-but-unsaved files are read fresh from disk (on-screen edits ignored)**.
- `gptel-context--string` (L611) — assemble; "Request context:\n\n" prefix only when non-empty; nil if empty.
- Inspection buffer: mode-map (L636: C-c C-c/C-c C-k/RET/n/p/d), `gptel-context-buffer-mode` (L644, special-mode + local post-command-hook + revert-buffer-function), `--buffer-setup` (L653 — rebuilds *gptel-context*; chunk overlays gptel-overlay t + gptel-context SOURCE + evaporate; **:lines/:bounds-only entries render NOTHING (dolist over nil :overlays) though --string still sends them** — the known FIXME), `--buffer-reverse` (L731), `--post-command` (L736 — **closure-shared highlight slot across all buffers installing it**), `gptel-context-visit` (L750 — unfiltered `(car (overlays-at))`), next/previous (L767/781), `flag-deletion` (L794 — third overlay species: deletion-mark t, priority −80, copies gptel-context value; auto-advance per --buffer-reverse), `gptel-context-quit` (L820 — quit-window + gptel-menu!), `gptel-context-confirm` (L826 — removes flagged sources, then **`(setq gptel-context (nreverse (gptel-context--collect)))` — wholesale replace, also GCing stale entries**; global not per-source-buffer, FIXME).

## Experiments (10): advance flags; overlap replacement; evaporate + dangling refs; collect pruning/killed buffers; exact --string output; wrap 'system/'user/nosystem; property-search on untagged buffer; kill-ring replace/append + dangling overlay; directory-MIME bug reproduced with a dir named weird.png; remove granularity.

## STATE-CARRIERS
`gptel-context` (global; **mutated in place by collect**; wholesale replaced by confirm) · project-files cache + reset flag + 0-delay timers · `--buffer-reverse` · gptel-system-prompt (wrap 'system) · buffers: kill-ring-context (persistent hidden), file-context (throwaway), *gptel-context* (rebuilt) · THREE overlay species sharing the gptel-context prop name (source highlights / inspector chunks / deletion marks) · local post-command-hook with closure-shared state.
## gptel-org.el

- Compat shims L74–111 (lineage-map/begin/end/parent) — **dead on Org ≥9.7 (aliases to real fns; verified fboundp)**.
- `gptel-org-branching-context` (L115) — verified docstring example byte-for-byte (branching includes lineage only; linear includes all).
- `gptel-org-ignore-elements` (L158, default (property-drawer)) — default uses fast regex path; anything else → full org-element parse ("extremely slow").
- `gptel-org-validate-link` (L171, #'always), `gptel-org--link-regex` (L193).
- `gptel-org--presets` (defvar L200) — "hack" channel: GPTEL_PRESET names ride a dynamic let from send-advice into prompt-buffer construction where gptel--apply-preset applies them buffer-locally.
- `gptel-org--get-topic-start` (L206) — org-entry-get 'inherit + the `org-entry-property-inherited-from` marker side channel.
- `gptel-org-set-topic` (L211) — completion incl. slugified heading; errors outside org.
- `gptel-org--create-prompt-buffer` (L235) — region → topic → branching order; **narrows the CALLER's buffer without save-restriction (deliberate; callers must wrap)**; copies org-complex-heading-regexp + tab-width into the copy; applies gptel-org--presets in the copy. Verified: branching example exact; topic composes with branching; property drawer stripped.
- `gptel-org--strip-elements` (L324) — fast regex path only when list == (property-drawer) ("fast but inexact"); else org-element parse.
- `gptel-org--strip-block-headers` (L351) — ^#+begin/end_tool|_reasoning whole lines; **strict bol anchor — indented headers NOT stripped (verified)**; src blocks untouched; EOF-safe.
- `gptel-org--unescape-tool-results` (L366) — backward scan; unescape ONLY `(tool . _)`-tagged spans (verified: untagged/response-tagged identical text untouched); skips stray propertized #+begin_tool header lines; malformed-block min-guard rough edge.
- `gptel-org--link-standalone-p` (L392), `gptel-org--validate-link` (defsubst L405 — same fixed-shape tuple + link-type-cache memoization), org `gptel--parse-media-links` (defmethod L436), `gptel-org--annotate-links` (L485 — jit-lock; overlays evaporate/priority −80; skips responses; forward-line −1 rescan guard).
- `gptel-org--send-with-props` (L516) + advice-add (L538) — :around on gptel-send + gptel--suffix-send ONLY (gptel-request deliberately not advised); 8 vars let-bound from heading properties via `(or prop current)`; **true dynamic override — buffer-locals provably intact after (verified)**; works because the vars are special.
- `gptel-org--entry-properties` (L548) — 'selective reads (non-inheriting under the default `org-use-property-inheritance` nil); typed coercion; missing tools warned+dropped. **Verified lossy round-trip: a system prompt containing the literal 2-char text `\n` reads back as a real newline** (escape scheme has no escaping of the escape).
- `gptel-org--restore-state` (L580) — widen; GPTEL_BOUNDS via read + gptel--restore-props; buffer-locals set; condition-case → message on failure; unknown preset → display-warning; unknown backend → message only (var left at prior value).
- `gptel-org-set-properties` (L616) — writes only preset-diverging fields (matching ones org-entry-delete'd); FIXME nil ambiguity (explicit-nil system silently dropped); temperature also gated vs default-value.
- `gptel-org--save-state` (L677) — org-open-line before a point-min heading; **bounds retry verified real: exactly 2 writes when the property drawer first grows above the response text; marker-vs-baked-offset divergence triggers the retry; final positions verified exact**. `(let ((print-length)) …)` at L691 dynamically binds `print-length` (a special variable) to nil around the `prin1-to-string` — **verified essential: with a global print-length of 3 the bounds would serialize truncated as `(1 2 3 ...)`; the binding disables truncation** (an inspector claimed it was a vestigial lexical no-op; reviewer experiment refuted this).
- `gptel--convert-markdown->org` (L702) — verified corpus conversions. **Verified bug: bold at the very start of the string (`"**b**"` alone) converts to `"**b*"`** (looking-back window requires a preceding char; absent at point-min) — relevant since LLMs often open with bold.
- `gptel--replace-source-marker` (L762) — 3 backticks at (indented) line start → src fence; anywhere else → `=`.
- `gptel--stream-convert-markdown->org` (L779) — stateful closure (in-src-block/in-org-src-block/ticks-total/start-pt withhold marker); cleanup one-shot on gptel-post-response-functions keyed by START-MARKER identity (the chat-buffer :position marker). **Verified byte-identical vs one-shot across 12/12 adversarial splits.** **Verified divergence: unclosed trailing `*emphasis` (no closer) — one-shot leaves the `*`, streaming eagerly converts to `/`.** **No end-of-stream flush: text still withheld when the stream ends is silently dropped when the scratch buffer is killed** (no synthetic final chunk is ever sent).

## Experiments (8 suites): md→org corpus + bold-at-bob bug; 12 adversarial chunk splits + emphasis divergence; prompt-buffer branching/topic composition; strip-headers anchoring; \n round-trip lossiness + bounds retry instrumentation (org-entry-put counted); unescape scoping; send-advice dynamic-scope proof; compat shims dead.

## STATE-CARRIERS
Org properties GPTEL_{TOPIC,PRESET,SYSTEM,BACKEND,MODEL,TEMPERATURE,MAX_TOKENS,NUM_MESSAGES_TO_SEND,TOOLS,BOUNDS} (persistent buffer text) · gptel text property (bounds round-trip) · buffer-local gptel vars (restore/set-properties; dyn-overridden by advice) · `gptel-org--presets` dynamic channel · gptel-track-media overlays · advice on 2 send fns · one-shot member on global gptel-post-response-functions per stream · gptel--link-type-cache · caller-buffer narrowing (unrestored by design) · markers (bounds drift detection; stream withhold pointer).
## gptel-rewrite.el

## Index
- Options: `gptel-rewrite-directives-hook` (L40, first non-nil wins) · `gptel-post-rewrite-functions` (L53; run in staging buffer with the SOURCE buffer's local value rebound there) · `gptel-rewrite-default-action` (L65: merge/diff/ediff/accept/dispatch/fn/nil).
- `gptel-rewrite-highlight-face` (L91, :extend t). `gptel-rewrite-actions-map` (L102: RET/mouse-1 dispatch; C-c C-a/r/k/d/e/n/p/m).
- `gptel--rewrite-overlays` (defvar-local L115) — pending-overlay registry. **Accept does NOT prune it (dead overlays linger until `gptel--rewrite-sanitize-overlays` in gptel-transient.el runs on next gptel-rewrite); reject prunes via delq.**
- `gptel--rewrite-message` (defvar-local L118) — instruction text.
- Load-time form L122: adds `(rewrite . gptel--rewrite-directive-default)` to gptel-directives unless present (user's own entry preserved).
- `gptel--rewrite-directive` (defvar L125) — active rewrite directive (snapshot of alist entry at load).
- `gptel--rewrite-directive-default` (L141) — hook first, else mode template. Verified: an/a from first letter of stripped mode name applies to BOTH branches; fundamental-mode → bare "You are an editor." (strip-mode-suffix returns "" outside prog/text/tex).
- `gptel--rewrite-handlers` (defvar L178) — WAIT/TPRE/TOOL/TRET overlay-status handlers layered on the standard tool handlers.
- `gptel--rewrite-update-tool-call` (L189) — "Calling tool(s) (…)" status; **clobbers the target buffer's (buffer-local) `gptel--fsm-last`** (defvar-local in gptel.el:1257; MAYBE-comment at L177). `--update-wait` (L206) — lazily builds the 4-element status list (label/message/right-align spacer via string-pixel-width/model hint). `--update-status` (L227) — replaces element 1; **throws wrong-type-argument if called before status primed** (verified).
- `gptel--rewrite-key-help` (L235) — eldoc; **double gate**: buffer-local overlays list non-empty AND gptel-rewrite char property at point (verified).
- `gptel--rewrite-move` (L248) — char-property hop. **Boundary bug (verified): `previous` from point-max misses a region whose overlay end == point-max** (clamp only guards the nil-overlay start case). `--next` (L263) / `--previous` (L268).
- `gptel--rewrite-overlay-at` (L275) — overlay at point or user-error ("Could not find region…"/"No LLM output available…"); shadows diff-entire-buffers nil.
- `gptel--rewrite-prepare-buffer` (L286) — singleton `*gptel-diff*` copy with rewrites applied (via accept against the copy); source + payload untouched (verified).
- `gptel--rewrite-read-message` (L317) — minibuffer: TAB directive preview cycle (setup-hook primes once), C-c C-e → edit-directive, RET starts (or reopens transient via run-at-time 0), M-RET → transient; writes source-buffer `gptel--rewrite-message` + transient-history (dedup).
- `gptel--rewrite-reject` (L380) — delete overlays, delq from registry, remove eldoc hook when empty.
- `gptel--rewrite-accept` (L390) — per overlay delete-region + insert payload (optionally into another buf). **Verified trap: `evaporate t` kills the overlay the moment delete-region empties it — before the insert; overlay-buffer nil after; registry/eldoc NOT cleaned by accept.**
- `gptel--rewrite-iterate` (defalias L410) = `gptel-rewrite` (re-entry with point on overlay → its payload becomes the new input).
- `gptel--rewrite-diff` (L413) — diff-no-select vs prepared copy; buffer-local diff-jump-to-old-file.
- `gptel--rewrite-ediff` (L427) — stashes each overlay's display in `gptel--ediff` prop (nil'd during session), saves window config, one-shot lambda on GLOBAL ediff-quit-hook (depth 50) restores both; plain horizontal split.
- `gptel--rewrite-merge-git` (L455) — `git merge-file --no-diff3` with 3 temp files (labels original/Empty/<backend>); leading newline forced at BEG unless bolp; unwind-protect temp cleanup.
- `gptel--rewrite-merge-simple` (L479) — manual markers; **END processed before BEG** (position safety, verified); BOL forcing both ends; final `insert-before-markers "<<<<<<< original\n"` at BEG so a type-nil boundary marker lands after the banner (semantics verified vs plain insert).
- `gptel--rewrite-merge` (L491) — git-or-simple per executable-find, smerge-mode on, then reject (clears overlays).
- `gptel--rewrite-dispatch` (L508) — read-multiple-choice a/k/r/m/d/e; temporary status-line key hints (rmc--add-key-description if fboundp, Emacs ≥29) restored via unwind-protect from copy-sequence snapshot; interactive dispatch via call-interactively (each action re-resolves ov).
- `gptel--rewrite-callback` (L529) — `:context` = (ov . proc-buf). Verified mechanics: (1) chunk 1 seeds proc-buf with shadow-faced ORIGINAL text + sets `:newline` iff it ends in \n; each chunk = insert then equal-length forward delete-char in ignore-errors (**oversized chunk: delete silently fails, stale shadow chars persist until success branch's final delete-region point..point-max**); (2) intermediate chunks set overlay `display` only; (3) on `t`: trailing-newline restore from `:newline` (verified "XY"→"XY\n"), post-rewrite-functions run IN STAGING BUFFER, payload stored in BOTH `display` and `gptel-rewrite`, proc-buf killed, overlay gets face/priority 2000/keymap/mouse-face/help-echo, pushed onto registry, eldoc hook added, pulse, default-action dispatch. Abort: delete overlay + kill proc-buf. Error: message then abort path. proc-buf major-mode set as VARIABLE (mode never run).
- Transients: `gptel--rewrite-directive-menu` (prefix L641) · `gptel-rewrite` (prefix L659, autoload; interactive body sanitizes overlays then region→minibuffer / pending→menu / else user-error; :environment evil fix) · `gptel--infix-rewrite-extra` (L742) · diff `-U` argument (L754) · `--suffix-rewrite-directive` (L762, function-directive confirm) · `gptel--suffix-rewrite` (L781; 3-turn prompt list [region-or-pending-payload / canned turn / instruction], :system gptel--rewrite-directive, fresh-or-reused overlay evaporate t, run-at-time backward-char onto overlay, deactivate-mark; interactive-only nil for dry-run) · batch suffixes D/E/M/A/K (L819–851, delegate over the registry).

## Experiments (10): directive strings per mode + article logic; shadow consumption incl. oversized-chunk stall; newline restore; payload/proc-buf lifecycle; merge-simple BOL + ordering; insert-before-markers semantics; prepare-buffer isolation; accept self-evaporation; navigation boundary bug; eldoc double gate.

## STATE-CARRIERS
`gptel--rewrite-overlays` (buffer-local; accept leaves dead entries) · `gptel--rewrite-message` (buffer-local) · `gptel--rewrite-directive` (global) · gptel-directives 'rewrite entry (load-time) · the rewrite overlay (props: gptel-rewrite payload, display, status 4-list, before-string, face, priority 2000, evaporate (set at finalization L805), keymap, mouse-face, help-echo, gptel--ediff stash) · staging buffer " *gptel-rewrite*" (hidden, undo-inhibited) · singleton `*gptel-diff*` · window config + global ediff-quit-hook one-shot · smerge-mode · transient-history (rewrite-extra key) · local eldoc-documentation-functions · target buffer's `gptel--fsm-last` (buffer-local; tool-call updates) · OS temp files (merge-git, unwind-protected) · INFO `:context :newline :stream :tool-use :include-reasoning`.
## gptel-transient.el lines 1–1000

- `gptel--rewrite-overlays` (defvar L40) + `gptel--rewrite-sanitize-overlays` (L43) — live-overlay pruning; :if predicate for menu groups.
- `gptel--set-buffer-locally` (defvar L49) — the singleton scope flag (nil/t/1).
- `gptel--set-with-scope` (defun L54) — global (kill-local + set-default) / buffer-local / oneshot. **Verified: oneshot stashes original in `(get sym 'gptel-history)` ONLY if absent (second oneshot doesn't clobber or double-hook); restore = self-removing gptel-post-request-hook member whose body defers via run-at-time 0 (escapes the enclosing dynamic extent); restore observed only after run-hooks + timer flush.**
- `gptel--preset-mismatch-p` (L78) — catch/throw fold; "fast but imperfect" (function/spec values skipped).
- `gptel--get-directive` (L126) — first ":"-arg; nil when none (verified; ":" alone → "").
- `gptel--instructions-make-overlay` (L134) — DIRECTIVE label overlay at region start / response start / last response boundary; 'category 'gptel.
- `gptel--read-with-prefix-help` (L162 — used by add-directive's :prompt at L1467 and twice in gptel-rewrite.el; only its docstring is a TODO) / `gptel--read-with-prefix` (L172) — minibuffer prefix overlay cycling hide→truncated→full via a 'gptel state property; user-error outside minibuffer.
- `gptel--minibuffer-prompt-history` (L230) / `gptel--read-minibuffer-prompt` (L233) — M-RET region toggle, C-c C-e → gptel--edit-directive (cancel unwinds the minibuffer's nested command loop via minibuffer-quit-recursive-edit); installs gptel-preset-capf locally.
- `gptel--transient-read-number` (L291) — transient#172 workaround: **setcar's the history's car to a string in place** (verified); −1 sentinel → nil.
- `gptel-system-prompt--format` (L306) — heading preview; "λ:" for function directives.
- `gptel--tools-init-value` (L322) — seeds switch value from scope :tools; absent → left nil (verified).
- Crowdsourced: URL (L331); `gptel--crowdsourced-prompts` — **Lisp-2 name collision verified: the symbol simultaneously holds the cache hash table (value cell) and the fetcher (function cell)**; `gptel--read-csv-column` (L339) — RFC 4180 verified (quoted commas/newlines, "" escape, tolerant unterminated quote); fetcher (L379) — y-or-n-p gated url-copy-file, 14-day staleness, run-at-time re-entry (NOT exercised — network).
- `gptel--describe-infix-context` (L423) — counts (FIXME: :bounds/:lines not counted). `gptel--describe-suffix-send` (L453) — live send description; reads transient internals pre-export (documented HACK); 20-char kill preview + CHARACTER count (Lisp `length`, labeled " chars"; not bytes — differs on non-ASCII).
- `gptel--format-preset-string` (L528) — @preset indicator + strike-through on mismatch.
- `gptel--transient-fix-evil-visual` (L546) — :environment wrapper; boundp/fboundp-guarded no-op without evil.
- Classes: `gptel-lisp-variable` (L575; display-nil/display-map; **transient-infix-set calls set-value with 3 args — inherited default #'set signals wrong-number-of-arguments; every instantiation must supply :set-value #'gptel--set-with-scope (verified + grep-confirmed)**) · `gptel--switch` (L598; category slot; set mutates scope :tools + writes prefix scope back) · `gptel--switch-category` (L622; own value ignored; format shows (active/total); **read 3-way verified: not-shown → reveal unchanged / shown+some → nil (deselect all) / shown+none → own argument (select all)**; set fans out over transient--suffixes via cl-typep scan) · `gptel--switches` (L677; **read = (not value) — any truthy collapses to nil, not strict t/nil**) · `gptel--scope` (L699; cycles nil→t→1→nil verified; set is the sole 2-arg set-value call site) · `gptel-provider-variable` (L736; pair-setter for gptel-model+gptel-backend; format reads transient--original-buffer's backend; set triggers transient-setup redraw) · `gptel-option-overlaid` (L764; **transient-format-value SIDE-EFFECT: creates/updates the in-buffer DIRECTIVE overlay + registers self-removing transient-exit-hook cleanups — verified lifecycle: first post-set render → 1 overlay + 1 hook entry, but each later redraw adds a second, structurally-distinct closure (add-hook can't dedup — captured `ov` differs), stabilizing at 2 hook entries + 1 overlay; ALL self-remove on exit → 0/0**).
- `gptel-menu` (prefix L800) — `:incompatible (("m" "y" "i") ("e" "g" "b" "k"))` (slot-read verified); :environment evil fix; invocation body sanitizes model + prunes dead context buffers.
- `gptel--setup-directive-menu` (L954) — generated suffixes per directive; keys from a–z0–9 pool excluding ?s; previews truncated at menu-BUILD-time window-width.

## Experiments (10): set-with-scope 3 scopes + oneshot nesting; CSV parser; 3-arg set-value trap; scope cycle; switch-category read/set with faked prefix/suffixes; tools-init-value; get-directive; read-number history setcar; Lisp-2 collision; option-overlaid overlay lifecycle. (Env note: system Emacs 30 transient too old for :environment slot — used ~/.emacs.d/elpa transient 20260701 + compat/cond-let/llama.)

## STATE-CARRIERS
`gptel-history` symbol-plist entries (oneshot stash) · gptel-post-request-hook self-removing members · buffer-local vs default variable cells (set-with-scope) · transient scope plist :tools/:category/:key + prefix scope slot writeback · transient-exit-hook one-shots · working-buffer DIRECTIVE overlays · minibuffer prefix overlays ('gptel state prop) · crowdsourced CSV cache file + network fetch + hash table (Lisp-2 shared symbol) · transient-history · echo-area messages.
## gptel-transient.el lines 1000–2030

- `gptel-system-prompt` (prefix L1002) — dynamic directive picker (via gptel--setup-directive-menu) + edit + scope.
- `gptel-preset` (defun L1029) — completing-read with minibuffer hint overlay; C-s saves current config as preset (run-at-time 0 + minibuffer-quit-recursive-edit); `=` cycles scope via a THROWAWAY gptel--scope object mirroring gptel--set-buffer-locally (not the real infix); applies via gptel--apply-preset with the scope-aware setter; transient-setup gptel-menu redraw if a prefix is live.
- `gptel-tools` (prefix L1106) — scope-plist selection state (`:tools (("category" "name")…)` — two-element lists, not conses; seeded from gptel-tools at setup); RET resolves via map-nested-elt on gptel--known-tools → gptel--set-with-scope; q discards; :refresh-suffixes t (columns rebuilt every keypress); key M reserved for MCP.
- Infixes: use-context (L1208) · variable-scope `=` (L1236, the real singleton) · num-messages (L1245, display-nil 'all) · max-tokens (L1262, 'auto) · **provider (L1278) — pair-sets gptel-model+gptel-backend, full annotations (desc/caps/context-window/costs/cutoff), transient-setup redraw; TODO: doesn't run gptel-refresh-buffer-hook** · temperature (L1325, "default") · track-response (L1336) · **track-media (L1356 — actually a SUFFIX so it can order infix-set THEN run refresh-hook/annotate-clear; calls (transient--show) manually)** · context add-kill (L1384, expert-gated) / add-region (L1396, dual add/remove description) / add-buffer (L1413, `(gptel-add '(4))`) / add-file (L1425) / remove-all (L1434, :if gptel-context) · **add-directive (L1446) — value lives ONLY in transient args (":"-prefixed; :variable commented out); DIRECTIVE overlay via the class side effect; TAB preview reader** · include-reasoning (L1491, buffer-name option via read-buffer) · use-tools (L1531, set-value + transient-setup for live group visibility) · confirm-tool-calls (L1562) · include-tool-results (L1590).
- `gptel--suffix-send` (suffix L1625) — THE dispatcher. Verified: `("I" …)` dry-run returns synchronously, fsm-state INIT, full :data inspectable, zero network; instructions merged: dry-run payload `:instructions "…assistant. Respond concisely.\n\nBe terse"` proves get-directive + merge-additional-directive compose through the real path. Kill-ring: kill-region on in-place prompt (killed text → attach-response-history when NOT redirecting); kill-new response for "k" (incl. partial on error). Session redirect "g<name>": new session created via `gptel` copying backend/model; **fencing verified both branches: org target → `#+begin_src python …#+end_src` (org-escape-code-in-string), other targets → ``` python fences; language from gptel--strip-mode-suffix**. Buffer redirect "b<name>" → get-buffer-create at its point. `(put … 'interactive-only nil)`.
- `gptel--merge-additional-directive` (defun L1828) — verified: string → `(concat full "\n\n" additional)`; cons/list → copy-sequence + setcar on the COPY (original untouched); function → NEW lambda lazily re-merging on call (underlying fn not invoked at merge time); otherwise (nil/symbol/number) → additional alone.
- `gptel--regenerate` (defun L1853) — delete response region (swallowing prefixes in gptel-mode), attach history property, call-interactively gptel--suffix-send (inherits the live transient args; real send unless "I" ambient).
- `gptel--read-crowdsourced-prompt` (L1876) — reads via `(gptel--crowdsourced-prompts)`, which on an empty hash may y-or-n-p-prompt and network-fetch the CSV; pick → set with scope → edit-directive → reopen menu.
- `gptel--suffix-system-message` (L1911) — y-or-n-p guard for function directives (blocking); :setup #'activate-mark.
- `gptel--edit-directive` (cl-defun L1932) — *gptel-prompt* buffer (text-mode + visual-line); read-only front-sticky header; C-c C-c → gptel--set-with-scope in orig-buf (list directives: setcar of first element only — incomplete-edit comment); C-c C-k abort; display below selected, fit-window; quit-window + refocus orig-buf (skipped for minibuffer callers).
- `gptel--suffix-context-buffer` (L2015) — " C"; transient--do-exit; gptel-context--buffer-setup.

## Experiments (6): get-directive variants (first-wins, ":"→""); merge-additional-directive all four branches + purity; gptel-menu :incompatible slot read; dry-run suffix-send end-to-end; fencing org vs text targets with real region; option-overlaid overlay via transient-format-value with faked transient--original-buffer. (Same transient-version workaround as part 15.)

## STATE-CARRIERS
kill-ring (in-place prompt kill; "k" response; partial on error) · new session/plain buffers + display-buffer · DIRECTIVE overlay (transient arg lifecycle) · gptel-history text property (regenerate) · *gptel-prompt* editor buffer (read-only header props) · all scoped gptel vars via = flag · gptel-tools transient scope plist · transient-history · gptel--fsm-last (read by continue-tool-calls; populated by sends) · network ONLY via gptel-request from suffix-send when not dry-run.

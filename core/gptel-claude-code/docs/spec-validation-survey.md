# Information-loss survey for the gptel specification pair

Answer every question in your assigned block using ONLY `gptel-requirements.md` and `gptel-architecture.md` (the compressed pair). Cite the section for each answer. If a question cannot be answered from those two files, write **UNANSWERABLE**.

## Block A — principles, tracking, sending
A1. Which principle resolves whether the chat buffer may ever be required? What does it say?
A2. What exactly happens to the prompt boundary when point is mid-word at send time?
A3. With several requests in flight in one buffer, what does the abort command do, and with what exact callback invocation?
A4. What is the turn-limit semantics (units, nil meaning)?
A5. What are the four text classes and which one is "visible but never sent"? Give its two named examples.
A6. State the tracked role of text typed: (a) at the first char of a response, (b) inside, (c) right after the response mid-buffer, (d) at buffer end.
A7. In which buffers does `gptel-track-response` nil have no effect?
A8. Which two highlight methods are mutually exclusive and which wins?
A9. Are cosmetic prefixes propertized? How are they removed at parse time?
A10. What does the empty-response status string say, and what is structurally NOT inserted?
A11. What signals "stream finished successfully" to a callback?
A12. What is inserted before response text on the first streamed chunk in a chat buffer, and what marker is created with which insertion-type?
A13. Does point follow the stream when parked at the insertion position? What mechanism guarantees the answer?
A14. Which two hook members give opt-in follow/scroll behavior, on which hooks?
A15. What happens to zero-length streaming chunks, and why does that matter for empty-response detection?
A16. What are the two consumers of the curl write-out UUID cons, and what does the streaming filter use instead?
A17. What is written to curl's stdin, in exact order?

## Block B — chat buffers, persistence
B1. What major modes may host gptel-mode? What happens otherwise?
B2. Default chat buffer name pattern, and how a fresh session is forced?
B3. List the six right-aligned header-line indicators and each one's click target.
B4. Exact token-usage display format example, and what the `C` marks.
B5. What replaces the header line when it is disabled?
B6. How is markdown fence-fold nesting resolved?
B7. Enumerate every persisted file-local variable name.
B8. Write the bounds alist shape including the optional third element's meaning, and the accepted legacy shape.
B9. Under what condition is `gptel-temperature` written to file?
B10. Restore behavior for: unknown backend / missing tool / unknown preset — and why absent-preset restores may be partial.
B11. Is variant history persisted?
B12. Where do Org chats store persisted state, and what is special about writing GPTEL_BOUNDS (mechanism, iteration cap, print setting)?
B13. Which hook customizes persistence, at what moment?
B14. What is the minimal-diff persistence rule?
B15. What message confirms a successful restore?

## Block C — backends, models, keys, transport
C1. Which constructor silently builds a different backend type, under what exact host condition?
C2. List every capability symbol and the feature each gates.
C3. What happens when two backends register the same model symbol with plists?
C4. Give the full API-key resolution chain including symbol handling and trimming.
C5. Where is the interactive password prompt implemented (which layer), and what does `gptel-request` do instead?
C6. What is the request-param layering order and merge granularity?
C7. Which struct slots may be functions of request INFO, and which four backends need that?
C8. What is `coding-system 'binary` for and who uses it?
C9. Name the curl args essential to streaming and the stall-timeout values.
C10. Which transport features are missing on the url-retrieve path (list)?
C11. What are the four error classes and the exact fallback-path difference for connection errors?
C12. What known bug affects HTTP 100 responses?
C13. How are parallel curl processes demultiplexed (primary mechanism)?
C14. What is the declarative default-backend configuration form?
C15. What does the model+backend picker display and from where do annotations come?
C16. Which exception to the zero-dependency principle exists and where is it enforced?
C17. Why does the payload travel via stdin (two reasons)?
C18. On Windows, why is CRLF translation disabled?

## Block D — menu, scoping, presets
D1. The three scopes and the exact mechanics of "global" w.r.t. existing buffer-local values.
D2. Oneshot: where is the old value saved, what guard prevents nested clobbering, when does the restore fire (dispatch or completion?), and via which deferred mechanism?
D3. What happens with two overlapping oneshot requests on one variable?
D4. The two redirection exclusivity groups with their key letters; which flag sits in a surprising group and why; what happens when it combines with a destination?
D5. Which destinations force streaming off?
D6. What happens to the response routed to the kill-ring when the request errors midway?
D7. Cross-mode fencing: when routing a prompt into a session of a different major mode, whose markup wins?
D8. How are saved redirection combinations persisted and cycled (keys)?
D9. The one-shot "additional instruction": where is it stored, what previews it, what is the overlay's literal label, how does it merge into each of the three system-prompt shapes, and with what separator?
D10. Crowdsourced prompts: fetch precondition, cache refresh age, what always happens to a picked prompt, and the accepted quirk.
D11. Preset special keys and the `:foo` → variable mapping rule (both fallbacks).
D12. The four preset application paths and each one's scope.
D13. `@cookie` scanning rules (where scanned, what happens to the cookie, cookies in responses/prior turns).
D14. What triggers the preset strike-through, and what is skipped in the comparison?
D15. Tool menu: where does selection state live and why can't transient args hold it?
D16. The category key's three-state cycle, exactly.
D17. Reserved keys in dynamic key assignment and the ignored prefix.
D18. How are menu keybindings rebound?

## Block E — context, media, reasoning
E1. All context entry shapes including the plist keys and each key's value format (positions/line indexing).
A: `gptel-context` entries: file paths · buffers · `(buffer . plist)` · `(path . plist)`. Plist keys: `:overlays` (live overlays), `:bounds` (`(START . END)` char-position cons or list of them, inclusive-exclusive), `:lines` (`(FROM . TO)` 1-indexed cons or list), `:mime` (string). Singleton conses accepted for lists. [A§2.6]

E2. The overlay creation call with both advance combinations and the resulting growth behaviors.
A: `(make-overlay beg end nil (not advance) advance)`, `evaporate t` + highlight face. Region adds (advance=nil) → front-advance t, rear-advance nil — grows at neither edge. Whole-buffer adds (advance=t) → grows at both ends. [A§2.6]

E3. How is kill-ring context represented and how does append interact with overlay growth rules?
A: Hidden buffer `" *gptel-kill-ring-context*"` added as whole-content region context. Append (prefix arg) rewrites the buffer and re-covers it. [A§2.6] UNANSWERABLE for the explicit "growth rules are moot there" characterization — not stated in either compressed file.

E4. How do file `:lines`/`:bounds` entries come to exist?
A: They are API/preset-level only — no interactive command creates them. [A§2.6]

E5. Collection: what is pruned, how are directories filtered, what bypasses the project restriction, what makes it narrowing-immune?
A: Pruned = dead sources. Directories expanded via memoized `project-files`, `.gitignore`-respecting. Remote paths are exempt from the project/gitignore restriction. Regions read under `without-restriction` makes it narrowing-immune (TC-120). [A§8.1]

E6. The serialized context string: opening literal, per-source header formats, fence info-string rule for buffers vs files, and all three discontinuity markers with triggers.
A: Opens `Request context:`; per source `In buffer 'NAME':` / `In file '~/path':` + fence (buffers: info-string = major-mode name minus `-mode`, e.g. `emacs-lisp`; files: bare fence). Discontinuity markers (R§5.9 TC-118): same-line regions → one `... (Line N)`; mid-line start → leading `...`; short of EOB → trailing `...` (line-1 start → no marker). [A§8.1, R-TC-118]

E7. Injection placements and the `nosystem` fallback; where does media context go and why?
A: Placement (`gptel-use-context`): system message (default) / before final user prompt / off. `nosystem` models auto-fall-back system→user. Media context attaches to the *first* user message because media can't ride in system messages. [R-FR-CTX-6, A§8.1]

E8. Inspector keybindings (all six operations) and its known limitation.
A: `n`/`p` navigation, `RET` visits source position, `d` flags for deletion, `C-c C-c` confirm, `C-c C-k` quit (plus point-highlighting/inline previews as passive features). Known limitation: `:bounds`/`:lines` sub-range specs not rendered. [R-FR-CTX-7, A§12]

E9. Two known context deviations regarding MIME.
A: Directory context entries mis-derive MIME from the directory name, not the file; MIME capability matching is exact, no `image/*` globs. [A§12]

E10. Which context entities does the transient menu summarize?
A: Live counts of regions/buffers/files. [R-FR-CTX-8]

E11. Recognized media link forms for markdown and org, and what form is ignored.
A: Markdown: `[](path)`, `[desc](path)`, `<url>`. Org: `[[file:…]]`, `[[attachment:…]]`, `<file:…>`. Plain unbracketed links are ignored. [R-FR-MEDIA-1]

E12. The four validation failure reasons shown in link tooltips.
A: Bad type / failed predicate / unreadable / MIME unsupported. [R-FR-MEDIA-2]

E13. Which links are never annotated or followed?
A: Links inside responses. [R-FR-MEDIA-2]

E14. Default value of `gptel-track-media`?
A: Off. [R-FR-MEDIA-1]

E15. The four `gptel-include-reasoning` values with behaviors, and the default.
A: `ignore` (default: insert but mark `ignore`, never re-sent) / `t` (insert as response) / `nil` (drop) / buffer name (redirect there). [R-FR-REASON-1]

E16. Reasoning block delimiters in org and markdown, and their text property.
A: Org `#+begin_reasoning` / markdown ```` ```reasoning ```` blocks, auto-folded; delimiter lines marked `ignore`. [R-FR-REASON-2]

E17. The reasoning state machine's assumption, and what happens to text preceding an inline `<think>` tag.
A: Assumes a single reasoning block, arriving before the answer. Text preceding an inline `<think>` tag is emitted as response first. [A§5.4]

E18. Which backend discards streamed reasoning?
A: Bedrock. [A§7.7, A§12]

## Block F — tools, MCP, rewrite
F1. All tool struct slots; arg spec keys; the two special slot value forms (confirm predicate, include values).
A: Slots: `function name description args async category confirm include`. Arg spec keys: `:name :type :description` (optional `:optional :enum :items :properties`). Special forms: `confirm` = bool or predicate over call args; `include` = t / `call` / nil. [A§2.3]

F2. The full confirmation precedence chain, including how "explicit nil from a hook" is detected.
A: Hook-set `:confirm` on the call plist > global `gptel-confirm-tool-calls` (t/nil) > tool's `confirm` slot (predicate on args) under `auto`. Explicit nil is detected with `plist-member` (so it's distinguishable from "key absent"), suppressing confirmation. [A§8.2, A§3]

F3. `gptel-use-tools` values and what force does.
A: nil / t / `force`; force requires a tool call where the API supports it. [R-FR-TOOL-2]

F4. The pending-call UI: block contents, banner keys, the four mouse dispatch choices, and when the minibuffer is forced.
A: In-buffer read-only block `(tool_name "arg" …)` (truncated) + banner (Run `C-c C-c` / Cancel `C-c C-k` / Inspect `C-c C-i`); mouse dispatch offers y-run / n-noop / k-cancel / i-inspect; minibuffer multiple-choice forced for read-only buffers. [R-FR-TOOL-4, A§8.2]

F5. What can the inspect buffer edit, and where must edits propagate?
A: Pending calls shown as editable plists — edit args or delete calls; edits propagate into the outgoing message history (via `gptel--inject-tool-call`). [R-FR-TOOL-5, A§8.2]

F6. What FSM state does a request rest in after rejection, and what does "continue tool calls" do? What gates its menu visibility?
A: Rejected calls never resolve → FSM rests in TOOL. "Continue tool calls" re-invokes the TOOL handler on the saved FSM; gated on the buffer's last FSM being in TOOL. [A§3]

F7. Sync tool error handling and unknown-tool handling.
A: Sync tool errors (via `condition-case`) → string results to the LLM, request never breaks. Unknown tool → error-string result listing available tools. [R-FR-TOOL-7, A§8.2]

F8. In-buffer tool record format (org + markdown header, body layout, property), and the exact cache-notice string.
A: Org `#+begin_tool <truncated call>` / markdown ```` ```tool <truncated call> ```` blocks; body = plist `(:name NAME :args ARGS)` + blank line + result, propertized `(tool . ID)` (delimiters `ignore`), auto-folded. include=`call` cache notice: `"(Cached tool result — available during original generation but not replayed)"`. [A§8.2]

F9. `gptel-include-tool-results` values + default.
A: t / nil / `call` (args only; result replaced by cache notice on replay) / `auto` (per-tool; default). [R-FR-TOOL-8]

F10. Both tool hooks: input plist keys and all recognized return keys with effects; which FSM states run them; do bare gptel-request callers get them?
A: Input: `(:name :args :buffer :backend :model [:result])`. Returns: `:stop` · `:stop-reason` · `:block` (t or error string for the LLM) · `:confirm` · `:args` · `:name` (rewrites propagate to execution and history) · `:result` (post-hook: replaces what is sent and shown). Pre-hook runs in TPRE; post-hook runs on TRET entry, before result injection. Bare `gptel-request` with the default FSM does NOT run them — opt in via `:fsm`. [A§3, A§8.2]

F11. What does the ersatz `response_json` call do client-side (five specifics: encoding, callback, removal, confirmation, transition)?
A: A call named `response_json` is unwrapped in place: args JSON-encoded → sent to the callback as the response (+ `t` when streaming) → call removed from `:tool-use` → no confirmation → no further transition from that branch (no result round-trip). [A§8.2]

F12. MCP: category naming, what connect does end-to-end, what activate means, disconnect semantics, and the payload-collision limitation.
A: Category `mcp-<server>`. Connect starts servers as needed, registers tools, and pushes them onto global `gptel-tools` (= activation), reporting partial failures. Disconnect removes category + selection, offers server shutdown. Limitation: same-named tools from two servers are disambiguated by category only in the local registry — selecting both simultaneously still collides in the outgoing payload since providers key tools by bare name. [A§8.2, R-FR-TOOL-10, A§12]

F13. Rewrite entry behavior in all three situations.
A: Region present → minibuffer instruction (default "Rewrite: …", history, TAB shows directive, `C-c C-e` buffer editor, `M-RET` full menu) → request. No region + pending rewrites → actions menu. Neither → error. [R-FR-RW-1]

F14. The rewrite directive's sourcing chain and the two default template variants.
A: Variable seeded from `gptel-directives`' `rewrite` entry; default = `gptel-rewrite-directives-hook` (first non-nil) → else mode-derived template: prog-modes get the programmer variant ("generate ONLY code, no fences/explanations"), text gets the editor variant. [R-FR-RW-2]

F15. The exact canned assistant turn (verbatim, including spacing).
A: `"What is the required change?  I will generate only the final replacement."` (two spaces between the sentences). [R-FR-RW-7, A§8.3]

F16. Where does response text physically live during a rewrite, how is it projected, and what is deliberately NOT done to the staging buffer's major mode?
A: Staged in a hidden buffer (original text as shadow-faced placeholder, consumed as chunks arrive); projected onto the region via the overlay's `display` property (live morphing preview; buffer unmodified until accept). The staging buffer's `major-mode` variable is set WITHOUT running the mode (mode hooks in temp buffers caused breakage — only font-lock was wanted). [A§8.3]

F17. All rewrite actions and the two documented subtleties for ediff and merge (incl. marker placement and git labels).
A: Actions: accept · reject/clear · iterate (input = pending output, instruction pre-filled) · diff (with switches) · ediff · merge. Ediff: raw text; overlay `display`/`face` stashed and restored + window config restored on quit. Merge: `git merge-file --no-diff3`, labels original/<backend>, when git exists; manual `<<<<<<<` markers fallback (forced to BOL); `smerge-mode` on. [R-FR-RW-4, A§8.3]

F18. `gptel-rewrite-default-action` values and default; what does `dispatch` do?
A: Values: accept/diff/ediff/merge, `dispatch`, or a custom function (gets the overlay); default nil = wait. `dispatch` opens the action chooser. [R-FR-RW-5, A§8.3]

F19. The trailing-newline rule.
A: A trailing newline the original had but the response lacks is restored, in the stored replacement — hence it applies to every action. [R-FR-RW-8]
F20. What cleans up on abort/error/killed source buffer?
A: Abort/error/killed-source-buffer paths delete the overlay and the staging buffer. [A§8.3]

## Block G — org, introspection, variants, API, NFR
G1. Org prompt cleanup: the three operations and each one's reason.
G2. Topic mechanism: property name, how the subtree start is located.
G3. Branching: precise inclusion rule (ancestors, deepest heading, siblings, pre-heading text), version requirement + fallback, composition with region/topic, and the prompt-prefix caveat.
G4. Per-heading properties: full list with encodings; override mechanism + scope; which property beats which.
G5. md→org conversions performed, and the streaming converter's design (state held, withholding, correctness criterion, code-block rule, passthrough).
G6. GPTEL_BOUNDS write-convergence mechanism and its failure behavior; the print-length pitfall.
G7. Dry-run: how the payload is edited and resumed; what `C-c C-w` does; async-transform display behavior.
G8. Log levels and content at each.
G9. What does the diagnostic view show, and what privacy rule applies?
G10. Variant operations and the known deviation.
G11. `gptel-request` full keyword list and all four prompt forms.
G12. The complete callback RESPONSE shape enumeration.
G13. What does a third-party pass to a tool continuation closure?
G14. `:schema` accepted forms and array-root handling.
G15. Which hooks are wired by the chat/send layer rather than the bare API?
G16. NFR: what is snapshotted for request isolation and why?
G17. NFR privacy items (three).
G18. Performance NFR items (four).

## Block H — wire protocols
H1. OpenAI chat: full endpoint, auth header, streaming-only payload field, and the force-tool value/omission rule.
H2. OpenAI chat streaming: how tool-call deltas are segmented into calls, what field starts a new call, and what is ignored?
H3. OpenAI cached-token field names (both variants).
H4. Responses API: endpoint, what replaces messages, system prompt location, max-tokens field name, statelessness mechanism + reason.
H5. Responses streaming: list the event types and what `response.completed` wraps.
H6. Responses schema encoding and force-tool value.
H7. Anthropic: three headers (with values) and their conditionality; the mandatory field + default.
H8. Anthropic cache marker placement (three sites) and gating.
H9. Anthropic content block types (all six) with the tool_result content type rule.
H10. Anthropic streaming: consumed vs ignored events; how delta kinds are distinguished; what must be replayed with thinking.
H11. Anthropic structured output mechanism and its (non-)forcing.
H12. Gemini: host, URL template, key header, roles, the four safety categories, schema stripping, no-arg tool rule vs Anthropic's.
H13. Gemini streaming framing and parsing approach; reasoning marking; usage fields.
H14. Gemini/Ollama tool-call id situation and its consequence.
H15. Ollama: endpoint, stream-off encoding, sampling/schema locations, image encoding, JSONL specifics (fragmentation, argument type, terminator, usage fields).
H16. Kagi: endpoints per model, auth scheme, the two payload shapes, turn/streaming/system limitations, citation handling.
H17. Bedrock: URL template, model-id mapping + region prefixes, both auth modes with requirements, credential sources, cache mechanism + placement.
H18. Bedrock event stream: frame layout (prelude fields + sizes, payload length formula, CRC policy), header encoding (fields, per-type widths), where the event name lives, the six event types and correlation key.
H19. Copilot: dialect + endpoint, the responses-api delegation target, both tokens (flow, storage paths, renewal), and all per-request headers incl. x-initiator semantics.
H20. Codex: endpoint, both login flows with their constraints, token storage, the account-id header's JWT claim, and which params are stripped.

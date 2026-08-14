# Claude Code Headless Mode — Technical Specification

Applies to: `claude` CLI v2.1.231 (Claude Code). Verified on Linux.

## 1. Invocation

```
claude -p [options] ["<prompt>"]
```

- `-p` / `--print` selects headless (non-interactive) mode: the CLI runs the full agent loop (tools included), prints the final result to stdout, and exits. Without `-p`, `claude` starts an interactive TUI session.
- The prompt MAY be given as a positional argument, via stdin, or both. If both are given, stdin content and the argument prompt are combined into one user message.
- Piped stdin is capped at 10 MB; exceeding it aborts with a non-zero exit code.
- The workspace-trust dialog is skipped in `-p` mode; run only in trusted directories.
- `--bare` additionally skips hooks, plugins, MCP auto-discovery, CLAUDE.md, and keychain/OAuth auth (requires `ANTHROPIC_API_KEY` or `apiKeyHelper`); recommended for CI. Context must then be provided explicitly (`--append-system-prompt`, `--mcp-config`, `--settings`, …).

## 2. Model and run-control options

| Flag | Meaning |
|---|---|
| `--model <alias\|full-name>` | e.g. `haiku`, `sonnet`, `opus`, `fable`, or `claude-sonnet-5` |
| `--fallback-model <m1,m2>` | fallback(s) when the primary is overloaded (`-p` only) |
| `--effort low\|medium\|high\|xhigh\|max` | reasoning effort |
| `--max-turns <n>` | hard cap on agentic turns. UNDOCUMENTED in `--help` but accepted and enforced; on hitting the cap: exit code 1, JSON `subtype:"error_max_turns"`, no `result` text |
| `--max-budget-usd <amount>` | hard cap on API spend (`-p` only) |
| `--system-prompt <s>` / `--append-system-prompt <s>` | replace / extend the default system prompt (also `*-file` variants) |
| `--session-id <uuid>` | force a specific session UUID |
| `--no-session-persistence` | do not save the session to disk (`-p` only; not resumable) |

## 3. Input formats

`--input-format text` (default) or `stream-json`.

- `stream-json` input: newline-delimited JSON user messages on stdin, each of the form
  `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}`.
  Requires `--output-format stream-json`. Enables multi-turn conversations over one process; the process ends when stdin closes and the last turn completes.
- `--replay-user-messages` re-emits user messages on stdout for acknowledgment (stream-json in+out only).

## 4. Output formats

`--output-format text | json | stream-json` (`-p` only; default `text`).

### 4.1 `text`
Final result text only, on stdout.

### 4.2 `json`
A single JSON object on stdout. Guaranteed fields (verified):

- `type:"result"`, `subtype:"success" | "error_max_turns" | "error_during_execution"`
- `is_error` (bool), `result` (string; absent on `error_max_turns`)
- `structured_output` — present iff `--json-schema` was given; the schema-conforming object
- `session_id` (UUID string), `num_turns` (int), `uuid`
- `total_cost_usd` (float, client-side estimate), `usage` (token counts), `modelUsage` (per-model breakdown)
- `permission_denials` (array; see §6), `stop_reason`, `duration_ms`, `duration_api_ms`

Additional fields (e.g. `ttft_ms`, `terminal_reason`, `fast_mode_state`) exist and MUST be ignored if unknown.

### 4.3 `stream-json`
Newline-delimited JSON events. **With `-p`, requires `--verbose`; otherwise the CLI errors (exit 1).**
Event order: `{"type":"system","subtype":"init",...}` (model, tools, mcp_servers, plugins, session_id) → `assistant` / `user` messages (tool calls and tool results as content blocks) → final `{"type":"result",...}` identical to §4.2. `system/init` is first except that startup events (SessionStart/Setup hook events, plugin installs) MAY precede it. Other event types (`system/api_retry`, `rate_limit_event`, `system/thinking_tokens`, …) MAY appear and MUST be tolerated.

- `--include-partial-messages` adds `stream_event` lines carrying raw API deltas (e.g. `text_delta`) for token-level streaming.
- `--forward-subagent-text` forwards subagent text/thinking; subagent messages carry `parent_tool_use_id` (null for main conversation).

### 4.4 Structured output
`--json-schema '<JSON Schema>'` + `--output-format json` forces the final answer to validate against the schema, delivered in `structured_output` (the `result` field still holds text). Malformed value → startup error on stderr, exit 1: `Error: --json-schema is not valid JSON: …` (unparseable) or `Error: --json-schema is not a valid JSON Schema: <diagnostic>` (parseable but invalid). `format` keywords are accepted but not enforced.

## 5. Sessions

- `--continue` / `-c`: continue the most recent conversation in the current directory.
- `--resume <session_id>` / `-r`: resume by ID; works from any directory (the session is found machine-wide). Full context is restored (verified: recalls facts from the resumed session).
- `--fork-session`: with resume/continue, allocate a new session ID instead of appending.
- Capture the ID for scripting: `claude -p ... --output-format json | jq -r .session_id`.
- **Caveat (verified):** `--resume` with an unknown/unsaved session ID prints `No conversation found with session ID: <id>` and exits **0** — scripts must check the output, not the exit code.
- `--no-session-persistence` sessions are not saved: a later `--resume` of their ID fails as above.

## 6. Permissions

Headless mode can never show an interactive prompt. Semantics:

- A tool call not covered by an allow rule is **denied**; the run continues, and the denial is recorded in `permission_denials` (`[{tool_name, tool_use_id, tool_input}]`). The run still ends `subtype:"success"`, exit 0 — check `permission_denials` / the result text to detect blocked work.
- `--allowedTools "<rules>"` / `--disallowedTools "<rules>"`: comma- or space-separated permission rules, e.g. `"Read,Edit"`, `"Bash(git diff *)"` (trailing ` *` = prefix match; the space matters).
- `--permission-mode acceptEdits|plan|dontAsk|bypassPermissions|auto|manual`: session baseline (`acceptEdits` auto-approves file edits and common FS commands; `dontAsk` denies anything not explicitly allowed; `plan` = read-only planning).
- `--dangerously-skip-permissions`: approve everything (sandboxed environments only).
- `--tools "<names>"` restricts which built-in tools exist at all (`""` = none, `"default"` = all); distinct from permission rules.
- `--add-dir <dirs…>` extends filesystem access beyond the working directory.

## 7. Exit codes and errors

| Condition | Exit | Channel |
|---|---|---|
| Success (including runs with permission denials) | 0 | result on stdout |
| Unknown flag / invalid flag combo (e.g. stream-json without `--verbose`) | 1 | error on stderr, before the run |
| In-run failure (bad model, missing auth) | 1 | failure text printed as the result on **stdout** |
| `--max-turns` cap hit | 1 | JSON `subtype:"error_max_turns"` |
| SIGTERM | 143 | aborts turn, runs SessionEnd hooks |

Background Bash tasks started during the run are killed ~5 s after the final result; background subagents are awaited (capped at 10 min by default, `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`).

## 8. Other headless-relevant options

- `--mcp-config <file-or-json>` (+ `--strict-mcp-config` to ignore all other MCP sources). With `-p`, startup waits for MCP servers up to `MCP_TIMEOUT` (default 30 s); load failures appear in `system/init` `mcp_server_errors`.
- `--agents '<json>'` defines custom subagents inline; `--settings <file-or-json>`; `--setting-sources user,project,local`.
- Skills/slash commands work inside the prompt string (e.g. `claude -p "/skill-name args"`); terminal-only commands (`/login`) do not.
- `--verbose` in text mode prints turn-by-turn detail; required for stream-json output.

## 9. Canonical recipes

```bash
# One-shot with tool access
claude -p "fix the failing test" --allowedTools "Bash,Read,Edit"

# Structured extraction
claude -p "Extract deps" --output-format json \
  --json-schema '{"type":"object","properties":{"deps":{"type":"array","items":{"type":"string"}}},"required":["deps"]}' \
  | jq .structured_output

# Token-level streaming
claude -p "Explain X" --output-format stream-json --verbose --include-partial-messages \
  | jq -rj 'select(.type=="stream_event" and .event.delta.type?=="text_delta") | .event.delta.text'

# Multi-turn scripting
sid=$(claude -p "step 1" --output-format json | jq -r .session_id)
claude -p "step 2" --resume "$sid"
```

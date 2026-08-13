;;; gptel-claude-code.el --- Claude Code CLI backend for gptel  -*- lexical-binding: t; -*-

;; Author: Uladzislau Safronau
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (gptel "0.9.9"))
;; Keywords: hypermedia, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; This file adds support for the Claude Code CLI ("claude") in headless
;; mode (claude -p) as a gptel backend.  Unlike every other gptel
;; backend, requests do not go over HTTP: the transport spawns a local
;; `claude' process per request and parses its stream-json output.
;;
;; Design (see the project plan for full rationale):
;;
;; - STATELESS FULL REPLAY: each request serializes the gptel-parsed
;;   transcript (from the buffer's `gptel' text property) into a single
;;   one-shot `claude -p --no-session-persistence' invocation.  No
;;   --resume, no session ids.  gptel's buffer-is-the-conversation
;;   semantics (history edits, org branching, topics, variants) work
;;   unchanged.
;;
;; - TRANSPORT DISPATCH: gptel hardcodes its transport choice in
;;   `gptel--handle-wait' (gptel-request.el L1899-1913).  We install
;;   :around advice on both `gptel-curl-get-response' and
;;   `gptel--url-get-response' (their only call sites are L1910/L1911)
;;   that diverts requests whose backend is a `gptel-claude-code' struct
;;   to our own `make-process'-based transport.  This covers gptel-send,
;;   gptel-menu and gptel-rewrite (which build their own FSMs) without
;;   touching any gptel globals.  `gptel-claude-code-teardown' removes
;;   the advice.
;;
;; - CLAUDE'S AGENTIC TOOLS are configurable per backend (constructor
;;   keywords mapping to --tools/--allowedTools/--disallowedTools/
;;   --permission-mode/--add-dir and the working directory).  The
;;   default profile is chat-only: no tools, neutral scratch working
;;   directory.  gptel's own elisp tools (`gptel-tools') are ignored by
;;   this backend: Claude Code's CLI tools are the tool story here, and
;;   the registered models deliberately lack the `tool-use' capability.
;;
;; - AUTH: the CLI's own login (subscription OAuth or whatever `claude'
;;   is configured with).  No API key handling, no --bare.
;;
;; - Claude's intermediate agentic activity (thinking deltas, tool calls
;;   and tool results) is rendered into gptel's REASONING channel, so it
;;   appears as foldable ```reasoning blocks that are marked `ignore'
;;   and never re-sent (per `gptel-include-reasoning').
;;
;; Usage:
;;
;;   (require 'gptel-claude-code)
;;
;;   ;; Chat profile (default): no agentic tools, scratch cwd
;;   (gptel-make-claude-code "Claude-Code")
;;
;;   ;; Full-agent profile: project cwd, read-only exploration
;;   (gptel-make-claude-code "Claude-Agent"
;;     :cli-tools "default" :permission-mode "plan"
;;     :allowed-tools '("Read" "Grep" "Glob" "Bash(git diff *)")
;;     :working-dir 'buffer :max-turns 25 :timeout 600)
;;
;; Notes and limitations (v1):
;; - `gptel-temperature' and `gptel-max-tokens' have no CLI equivalent
;;   and are ignored (with a one-time warning).
;; - Media (`gptel-track-media') is unsupported; models are registered
;;   without the `media' capability so gptel never routes media here.
;; - Streaming requires `gptel-use-curl' non-nil (its default) because
;;   gptel's effective-streaming decision (gptel-request.el L2339-2348)
;;   includes it even though no curl runs.  With it nil, requests still
;;   work, non-streaming.
;; - The dry-run inspector works (both Lisp and JSON views, C-c C-c
;;   resume); the "copy Curl command" action produces a meaningless
;;   command for this backend.
;; - Structured output (`gptel-request' :schema) is supported via
;;   --json-schema and forces a non-streaming request.

;;; Code:

(require 'cl-generic)
(require 'cl-lib)
(require 'map)
(eval-and-compile (require 'gptel-request))

;; Defined in gptel.el / gptel-org.el, always loaded by the time a
;; request runs.
(declare-function gptel--insert-response "gptel")
(declare-function gptel-curl--stream-insert-response "gptel")
(declare-function gptel--stream-convert-markdown->org "gptel-org")
(declare-function gptel--convert-markdown->org "gptel-org")

;;; Backend struct and constructor

(cl-defstruct (gptel-claude-code (:constructor gptel--make-claude-code)
                                 (:copier nil)
                                 (:include gptel-backend))
  (executable "claude")
  (cli-tools "")
  (allowed-tools nil)
  (disallowed-tools nil)
  (permission-mode nil)
  (add-dirs nil)
  (working-dir 'scratch)
  (system-prompt-mode 'append)
  (max-turns nil)
  (max-budget-usd nil)
  (effort nil)
  (fallback-models nil)
  (extra-args nil)
  (timeout nil))

(defconst gptel-claude-code--default-models
  '((sonnet
     :description "Claude Sonnet (current) via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200)
    (fable
     :description "Claude Fable (current) via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200)
    (opus
     :description "Claude Opus (current) via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200)
    (haiku
     :description "Claude Haiku (current) via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200)
    (claude-fable-5
     :description "Claude Fable 5 via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200)
    (claude-sonnet-5
     :description "Claude Sonnet 5 via Claude Code CLI"
     :capabilities (reasoning)
     :context-window 200))
  "Default models for Claude Code backends.

Model symbols are passed to the CLI's --model flag verbatim.  None
of them declare the `tool-use' or `media' capabilities: gptel's own
tool loop and media pipeline are deliberately inert for this
backend.")

;;;###autoload
(cl-defun gptel-make-claude-code
    (name &key (models gptel-claude-code--default-models) (stream t)
          (executable "claude") (cli-tools "") allowed-tools disallowed-tools
          permission-mode add-dirs (working-dir 'scratch)
          (system-prompt-mode 'append) max-turns max-budget-usd effort
          fallback-models extra-args timeout request-params curl-args)
  "Register a Claude Code CLI backend for gptel with NAME.

Requests run the local `claude' executable in headless mode (-p)
instead of making HTTP calls; see the Commentary of
gptel-claude-code.el for the design.  Authentication is whatever
the CLI is logged in with.

Keyword arguments:

MODELS is a list of model symbols (or symbol-plist conses) passed
to the CLI's --model flag.  Defaults to
`gptel-claude-code--default-models'.

STREAM is a boolean to toggle streaming responses, t by default.

EXECUTABLE is the program name or absolute path of the CLI,
\"claude\" by default.

CLI-TOOLS is the value of the CLI's --tools flag controlling which
built-in tools exist at all: \"\" (default) for none — plain chat —
\"default\" for all, or a comma-separated subset.  nil omits the
flag (CLI default = all tools).

ALLOWED-TOOLS / DISALLOWED-TOOLS are lists of permission rules
\(e.g. \\='(\"Read\" \"Bash(git diff *)\")) for --allowedTools /
--disallowedTools.

PERMISSION-MODE is a string for --permission-mode
\(\"plan\", \"acceptEdits\", \"dontAsk\", ...), nil omits it.

ADD-DIRS is a list of extra directories for --add-dir.

WORKING-DIR controls the process working directory: `scratch'
\(default) uses a dedicated neutral directory under
`temporary-file-directory' (no project CLAUDE.md, no MCP
autodiscovery — lean and side-effect free); `buffer' uses the
request buffer's `default-directory' (the CLI then sees that
project's context — note headless mode skips the trust dialog, so
the directory is used as trusted); a string is used literally; a
function is called with the request INFO plist.

SYSTEM-PROMPT-MODE is `append' (default) to pass gptel's system
prompt via --append-system-prompt, keeping Claude Code's own
system prompt, or `replace' to substitute it via --system-prompt.

MAX-TURNS, MAX-BUDGET-USD, EFFORT, FALLBACK-MODELS map to the
corresponding CLI flags when non-nil.

EXTRA-ARGS is a list of raw argv strings appended to the command
line, or a function of the request INFO returning such a list
\(function values are resolved at dispatch time and are not
visible in dry-run).

TIMEOUT, when non-nil, is a stall timeout in seconds: if the
process produces no output for that long it is killed with a clear
error (guards against the known headless-stall CLI bug).  nil
\(default) disables it; 600 is a reasonable value for agent
profiles.

REQUEST-PARAMS and CURL-ARGS are accepted for interface
compatibility but unused by this backend."
  (declare (indent 1))
  (let ((backend (gptel--make-claude-code
                  :name name
                  :host "localhost"
                  :protocol nil
                  :endpoint ""
                  ;; Placeholder; keeps unrelated code paths (e.g. the
                  ;; dry-run "copy Curl command") from erroring on a nil
                  ;; URL.  Its value is never used to make a request.
                  :url "claude-code-cli"
                  :key nil
                  :header nil
                  :models (gptel--process-models models)
                  :stream stream
                  :request-params request-params
                  :curl-args curl-args
                  :executable executable
                  :cli-tools cli-tools
                  :allowed-tools allowed-tools
                  :disallowed-tools disallowed-tools
                  :permission-mode permission-mode
                  :add-dirs add-dirs
                  :working-dir working-dir
                  :system-prompt-mode system-prompt-mode
                  :max-turns max-turns
                  :max-budget-usd max-budget-usd
                  :effort effort
                  :fallback-models fallback-models
                  :extra-args extra-args
                  :timeout timeout)))
    (prog1 backend
      (gptel-claude-code-setup)
      (setf (alist-get name gptel--known-backends nil nil #'equal)
            backend))))

;;; Prompt parsing (buffer/list -> message plists)

(cl-defmethod gptel--parse-buffer ((_backend gptel-claude-code) &optional max-entries)
  "Parse the current (prompt) buffer into a list of message plists.

Backward walk on the `gptel' text property, per the standard
backend contract.  Tool records from prior runs and `ignore'
segments are skipped: structured tool turns cannot be replayed
through a one-shot text prompt, and the surrounding assistant text
already carries their conclusions."
  (let ((prompts) (prev-pt (point)))
    (if (or gptel-mode gptel-track-response)
        (while (and (or (not max-entries) (>= max-entries 0))
                    (goto-char (previous-single-property-change
                                (point) 'gptel nil (point-min)))
                    (not (= (point) prev-pt)))
          (pcase (get-char-property (point) 'gptel)
            ('response
             (when-let* ((content (gptel--trim-prefixes
                                   (buffer-substring-no-properties (point) prev-pt))))
               (push (list :role "assistant" :content content) prompts)))
            (`(tool . ,_id))            ;skipped, see docstring
            ('ignore)
            ('nil
             (when-let* ((content (gptel--trim-prefixes
                                   (buffer-substring-no-properties (point) prev-pt))))
               (push (list :role "user" :content content) prompts))))
          (setq prev-pt (point))
          (and max-entries (cl-decf max-entries)))
      (let ((content (string-trim (buffer-substring-no-properties
                                   (point-min) (point-max)))))
        (unless (string-empty-p content)
          (push (list :role "user" :content content) prompts))))
    prompts))

(cl-defmethod gptel--parse-list ((_backend gptel-claude-code) prompt-list)
  "Convert PROMPT-LIST (gptel's prompt-list formats) to message plists."
  (if (consp (car prompt-list))
      (let ((full-prompt))              ;Advanced format, list of lists
        (dolist (entry prompt-list)
          (pcase entry
            (`(prompt . ,msg)
             (push (list :role "user" :content (or (car-safe msg) msg))
                   full-prompt))
            (`(response . ,msg)
             (push (list :role "assistant" :content (or (car-safe msg) msg))
                   full-prompt))
            (`(tool . ,call)
             ;; No structured tool replay over a text prompt; degrade to
             ;; a plain assistant note.
             (push (list :role "assistant"
                         :content (format "(ran tool %s)" (plist-get call :name)))
                   full-prompt))))
        (nreverse full-prompt))
    (cl-loop for text in prompt-list    ;Simple format, list of strings
             for role = t then (not role)
             if text collect
             (list :role (if role "user" "assistant") :content text))))

;;; Transcript serialization

(defconst gptel-claude-code--replay-instruction
  "The prompt contains the transcript of your prior conversation with the \
user inside <conversation-history> tags, followed by the user's current \
message after \"USER: \".  Continue that conversation: answer only the \
current message.  Write your reply directly, without <user>/<assistant> \
tags, without a \"USER:\" or \"ASSISTANT:\" prefix, and without repeating \
the history."
  "Instruction appended to the system prompt for multi-turn requests.")

(defconst gptel-claude-code--continue-sentinel
  "(No new message. Continue your previous reply from exactly where it left off.)"
  "Stand-in user message when the transcript ends with an assistant turn.")

(defun gptel-claude-code--serialize (prompts)
  "Serialize PROMPTS (message plists) into a one-shot prompt string.

Returns (STRING . MULTI-TURN-P).  A single leading user turn is
passed through bare; anything else wraps prior turns in
<conversation-history> markup with the current user message last."
  (cond
   ((null prompts) (cons "" nil))
   ((and (null (cdr prompts))
         (equal (plist-get (car prompts) :role) "user"))
    (cons (plist-get (car prompts) :content) nil))
   (t
    (let* ((last (car (last prompts)))
           (last-user-p (equal (plist-get last :role) "user"))
           (history (if last-user-p (butlast prompts) prompts))
           (current (if last-user-p
                        (plist-get last :content)
                      gptel-claude-code--continue-sentinel)))
      (cons
       (concat
        "<conversation-history>\n"
        (mapconcat
         (lambda (msg)
           (let ((tag (if (equal (plist-get msg :role) "user")
                          "user" "assistant")))
             (format "<%s>\n%s\n</%s>" tag (plist-get msg :content) tag)))
         history "\n")
        "\n</conversation-history>\n\nUSER: " current)
       t)))))

;;; Request data (payload plist held in INFO :data)

(defvar gptel-claude-code--sampling-warned nil)

(cl-defmethod gptel--request-data ((backend gptel-claude-code) prompts)
  "Build the request payload for the Claude Code CLI from PROMPTS.

The returned plist is this backend's own shape (there is no HTTP
body): :argv holds the CLI flags, :prompt the serialized transcript
\(sent on stdin), :stream the effective delivery mode."
  (when (and (or gptel-temperature gptel-max-tokens)
             (not gptel-claude-code--sampling-warned))
    (setq gptel-claude-code--sampling-warned t)
    (display-warning '(gptel claude-code)
                     "gptel-temperature/gptel-max-tokens have no Claude Code CLI \
equivalent and are ignored by this backend (warning shown once)"))
  (pcase-let* ((`(,prompt . ,multi) (gptel-claude-code--serialize prompts))
               ;; --json-schema output arrives only in the final result
               ;; object, so schema requests are forced non-streaming.
               (stream (and gptel-stream (not gptel--schema)))
               (system (let ((sys gptel-system-prompt))
                         (cond ((and sys multi)
                                (concat sys "\n\n" gptel-claude-code--replay-instruction))
                               (multi gptel-claude-code--replay-instruction)
                               (t sys))))
               (argv nil))
    (cl-flet ((flag (&rest args) (setq argv (nconc argv (delq nil args)))))
      (flag "-p" "--no-session-persistence")
      (flag "--model" (gptel--model-name gptel-model))
      (if stream
          (flag "--output-format" "stream-json" "--verbose"
                "--include-partial-messages")
        (flag "--output-format" "json"))
      (when (and system (not (string-empty-p system)))
        (flag (if (eq (gptel-claude-code-system-prompt-mode backend) 'replace)
                  "--system-prompt" "--append-system-prompt")
              system))
      (when-let* ((tools (gptel-claude-code-cli-tools backend)))
        (flag "--tools" tools))
      (when-let* ((allowed (gptel-claude-code-allowed-tools backend)))
        (flag "--allowedTools" (mapconcat #'identity allowed ",")))
      (when-let* ((disallowed (gptel-claude-code-disallowed-tools backend)))
        (flag "--disallowedTools" (mapconcat #'identity disallowed ",")))
      (when-let* ((mode (gptel-claude-code-permission-mode backend)))
        (flag "--permission-mode" mode))
      (dolist (dir (gptel-claude-code-add-dirs backend))
        (flag "--add-dir" (expand-file-name dir)))
      (when-let* ((turns (gptel-claude-code-max-turns backend)))
        (flag "--max-turns" (number-to-string turns)))
      (when-let* ((budget (gptel-claude-code-max-budget-usd backend)))
        (flag "--max-budget-usd" (number-to-string budget)))
      (when-let* ((effort (gptel-claude-code-effort backend)))
        (flag "--effort" effort))
      (when-let* ((fallback (gptel-claude-code-fallback-models backend)))
        (flag "--fallback-model" fallback))
      (when gptel--schema
        (flag "--json-schema"
              (gptel--json-encode
               (gptel--preprocess-schema
                (gptel--dispatch-schema-type gptel--schema)))))
      (let ((extra (gptel-claude-code-extra-args backend)))
        (when (listp extra) (apply #'flag extra))))
    (list :argv (vconcat argv)
          :prompt (or prompt "")
          :stream (if stream t :json-false))))

(cl-defmethod gptel--inject-prompt ((_backend gptel-claude-code) _data _new-prompt
                                    &optional _position)
  "Refuse tool-result injection: this backend has no tool loop.

The generic default would corrupt this backend's :data payload
\(which has no :messages array).  It should be unreachable, since
the registered models lack the `tool-use' capability and
`gptel--request-data' never declares tools."
  (display-warning '(gptel claude-code)
                   "Tool-result injection is not supported by gptel-claude-code"))

;;; Stream parsing (claude --output-format stream-json)

(defun gptel-claude-code--update-tokens (usage info)
  "Update token counts in INFO from a result event's USAGE.
Mirrors gptel-anthropic's accounting: input combines input and
cache-creation tokens; cache reads are reported separately."
  (when usage
    (let ((input  (or (plist-get usage :input_tokens) 0))
          (output (or (plist-get usage :output_tokens) 0))
          (cached (or (plist-get usage :cache_read_input_tokens) 0))
          (cache  (or (plist-get usage :cache_creation_input_tokens) 0)))
      (let ((tokens (list :input (+ input cache) :output output
                          :cached cached :cache cache)))
        (plist-put info :tokens tokens)
        (plist-put info :tokens-full
                   (gptel--sum-plists (plist-get info :tokens-full)
                                      tokens))))))

(defun gptel-claude-code--render-tool-use (block)
  "Render an assistant tool_use BLOCK as a compact reasoning line."
  (let* ((name (plist-get block :name))
         (input (plist-get block :input))
         (input (and (not (eq input :null)) input))
         (str (lambda (v) (and (stringp v) v)))
         (detail
          (pcase name
            ("Bash" (funcall str (plist-get input :command)))
            ((or "Read" "Edit" "Write" "NotebookEdit")
             (funcall str (plist-get input :file_path)))
            ((or "Grep" "Glob") (funcall str (plist-get input :pattern)))
            ("WebSearch" (funcall str (plist-get input :query)))
            ("WebFetch" (funcall str (plist-get input :url)))
            ("Task" (funcall str (plist-get input :description)))
            ("TodoWrite" "(update todos)")
            (_ (and input (gptel--json-encode input))))))
    (format "\n→ %s: %s\n" name
            (truncate-string-to-width (or detail "") 80 nil nil t))))

(defun gptel-claude-code--render-tool-result (block)
  "Render a user tool_result BLOCK as a compact reasoning line."
  (let* ((content (plist-get block :content))
         (text (cond ((stringp content) content)
                     ((vectorp content)
                      (mapconcat (lambda (c)
                                   (let ((s (plist-get c :text)))
                                     (if (stringp s) s "")))
                                 content ""))
                     (t "")))
         (errp (eq (plist-get block :is_error) t)))
    (if errp
        (format "  ✗ %s\n"
                (truncate-string-to-width
                 (car (split-string text "\n")) 120 nil nil t))
      (format "  ✓ %d lines\n"
              (if (string-empty-p text) 0 (1+ (cl-count ?\n text)))))))

(defun gptel-claude-code--add-reasoning (info text)
  "Append TEXT to INFO's :reasoning accumulator."
  (when (and text (stringp text) (not (string-empty-p text)))
    (plist-put info :reasoning
               (concat (plist-get info :reasoning) text))))

(defun gptel-claude-code--handle-result (result info)
  "Record metadata (and errors) from a claude RESULT object into INFO."
  (let ((stop-reason (plist-get result :stop_reason)))
    (plist-put info :stop-reason
               (if (and stop-reason (not (eq stop-reason :null)))
                   stop-reason
                 (plist-get result :subtype))))
  (gptel-claude-code--update-tokens (plist-get result :usage) info)
  (plist-put info :cc-cost (plist-get result :total_cost_usd))
  (let ((denials (plist-get result :permission_denials)))
    (when (and (vectorp denials) (> (length denials) 0))
      (plist-put info :cc-denials denials)))
  (let ((subtype (plist-get result :subtype)))
    (when (or (eq (plist-get result :is_error) t)
              (and subtype (not (equal subtype "success"))))
      (plist-put info :error
                 (pcase subtype
                   ("error_max_turns"
                    (format "Claude Code hit its --max-turns limit (%s turns); raise :max-turns or reduce the task scope"
                            (or (plist-get result :num_turns) "?")))
                   (_ (let ((text (plist-get result :result)))
                        (if (and (stringp text) (not (string-empty-p text)))
                            (format "Claude Code: %s" (string-trim text))
                          (format "Claude Code error (%s)" (or subtype "unknown")))))))
      (plist-put info :status
                 (pcase subtype
                   ("error_max_turns" "Max turns exceeded")
                   ("error_during_execution" "Execution error")
                   (_ "Claude Code error"))))))

(cl-defmethod gptel-curl--parse-stream ((_backend gptel-claude-code) info)
  "Parse the Claude Code stream-json (NDJSON) response stream.

Returns the text accumulated since the last call.  Thinking deltas
and agentic tool activity are routed into INFO's :reasoning;
the final result event populates tokens, cost, stop reason,
permission denials and errors."
  (let ((content-strs) (evt) (pt (point)))
    (condition-case nil
        (while (setq evt (gptel--json-read))
          (setq pt (point))
          (pcase (plist-get evt :type)
            ("stream_event"
             (let ((delta (map-nested-elt evt '(:event :delta))))
               (pcase (plist-get delta :type)
                 ("text_delta"
                  (let ((text (plist-get delta :text)))
                    (when (stringp text) (push text content-strs))))
                 ("thinking_delta"
                  (gptel-claude-code--add-reasoning
                   info (plist-get delta :thinking))))))
            ("assistant"
             (let ((content (map-nested-elt evt '(:message :content))))
               (when (vectorp content)
                 (cl-loop for block across content
                          when (equal (plist-get block :type) "tool_use") do
                          (gptel-claude-code--add-reasoning
                           info (gptel-claude-code--render-tool-use block))))))
            ("user"
             (let ((content (map-nested-elt evt '(:message :content))))
               (when (vectorp content)
                 (cl-loop for block across content
                          when (equal (plist-get block :type) "tool_result") do
                          (gptel-claude-code--add-reasoning
                           info (gptel-claude-code--render-tool-result block))))))
            ("result"
             (gptel-claude-code--handle-result evt info))
            ;; system/init, hook/plugin startup events, rate_limit_event,
            ;; api_retry, unknown types: tolerated and ignored.
            (_ nil)))
      (error (goto-char pt)))
    (apply #'concat (nreverse content-strs))))

;;; Non-streaming response parsing (claude --output-format json)

(cl-defmethod gptel--parse-response ((_backend gptel-claude-code) response info)
  "Parse a one-shot claude RESPONSE (a result object); return its text.

Store response metadata in state INFO."
  (gptel-claude-code--handle-result response info)
  (unless (plist-get info :error)
    (let* ((structured (plist-get response :structured_output))
           (text (if (and structured (not (eq structured :null)))
                     (gptel--json-encode structured)
                   (plist-get response :result)))
           (denials (plist-get info :cc-denials)))
      (when (and (stringp text) (not (string-empty-p text)))
        (if denials
            (concat text
                    (format "\n\n[gptel: %d tool call(s) denied by permission rules: %s]"
                            (length denials)
                            (mapconcat (lambda (d) (plist-get d :tool_name))
                                       denials ", ")))
          text)))))

;;; Transport

(defun gptel-claude-code--working-directory (backend info)
  "Resolve the working directory for a request per BACKEND's spec and INFO."
  (let ((spec (gptel-claude-code-working-dir backend)))
    (cond
     ((eq spec 'scratch)
      (let ((dir (expand-file-name "gptel-claude-code/"
                                   (temporary-file-directory))))
        (make-directory dir t)
        dir))
     ((eq spec 'buffer)
      (let ((buf (plist-get info :buffer)))
        (if (buffer-live-p buf)
            (with-current-buffer buf (expand-file-name default-directory))
          default-directory)))
     ((stringp spec) (expand-file-name spec))
     ((functionp spec) (funcall spec info))
     (t default-directory))))

(defun gptel-claude-code--cancel-timer (info)
  "Cancel INFO's stall timer, if any."
  (when-let* ((timer (plist-get info :cc-timer)))
    (cancel-timer timer)
    (plist-put info :cc-timer nil)))

(defun gptel-claude-code--fail (fsm msg)
  "Fail the request in FSM before process creation with error MSG."
  (let ((info (gptel-fsm-info fsm)))
    (plist-put info :error msg)
    (plist-put info :status "Claude Code error")
    (unless (plist-get info :callback)
      (plist-put info :callback #'gptel--insert-response))
    (gptel--fsm-transition fsm)         ;WAIT -> TYPE
    (with-demoted-errors "gptel callback error: %S"
      (funcall (plist-get info :callback) nil info))
    (gptel--fsm-transition fsm)))       ;TYPE -> ERRS

(defun gptel-claude-code--get-response (fsm)
  "Fetch a response for the request in FSM by running the claude CLI.

This is the Claude Code analog of `gptel-curl-get-response'
\(gptel-request.el L2868-2938): it creates the process, installs
filter/sentinel, sets up default callbacks and the org transformer
in INFO, and registers the abort closure in
`gptel--request-alist'."
  (let* ((info (gptel-fsm-info fsm))
         (backend (plist-get info :backend))
         (data (plist-get info :data))
         (stream (not (eq (plist-get data :stream) :json-false)))
         (prompt (or (plist-get data :prompt) ""))
         (exe (executable-find (gptel-claude-code-executable backend))))
    (cond
     ((not exe)
      (gptel-claude-code--fail
       fsm (format "Cannot find the %S executable in `exec-path'"
                   (gptel-claude-code-executable backend))))
     ((> (string-bytes prompt) (* 10 1024 1024))
      (gptel-claude-code--fail
       fsm "Prompt exceeds the claude CLI's 10MB stdin limit"))
     (t
      (let* ((default-directory (gptel-claude-code--working-directory backend info))
             (extra (gptel-claude-code-extra-args backend))
             (command (append (list exe)
                              (append (plist-get data :argv) nil)
                              (and (functionp extra) (funcall extra info))))
             (stderr-buffer (generate-new-buffer " *gptel-claude-stderr*"))
             (process (make-process
                       :name "gptel-claude-code"
                       :buffer (generate-new-buffer " *gptel-claude-code*")
                       :command command
                       :connection-type 'pipe
                       :stderr stderr-buffer)))
        (when (eq gptel-log-level 'debug)
          (gptel--log (format "%s" command) "request command"))
        (when gptel-log-level
          (gptel--log prompt "request prompt (stdin)"))
        ;; Suppress "Process ... finished" noise in the stderr buffer.
        (when-let* ((stderr-proc (get-buffer-process stderr-buffer)))
          (set-process-sentinel stderr-proc #'ignore))
        (with-current-buffer (process-buffer process)
          (set-process-coding-system process 'utf-8-unix 'utf-8-unix)
          (set-process-query-on-exit-flag process nil)
          (process-send-string process prompt)
          (process-send-eof process)
          (unless (plist-get info :cc-init) ;first run: set process parameters
            (setf (gptel-fsm-info fsm)
                  (nconc (list :cc-init t
                               :transformer
                               (when (with-current-buffer (plist-get info :buffer)
                                       (and (derived-mode-p 'org-mode)
                                            gptel-org-convert-response))
                                 (if stream
                                     (gptel--stream-convert-markdown->org
                                      (plist-get info :position))
                                   #'gptel--convert-markdown->org)))
                         (unless (plist-get info :callback)
                           (list :callback (if stream
                                               #'gptel-curl--stream-insert-response
                                             #'gptel--insert-response)))
                         info)))
          (setq info (gptel-fsm-info fsm)) ;may have been replaced by nconc
          (plist-put info :cc-stderr stderr-buffer)
          (plist-put info :cc-last-output (float-time))
          (when-let* ((timeout (gptel-claude-code-timeout backend)))
            (plist-put info :cc-timer
                       (run-at-time (/ timeout 4.0) (/ timeout 4.0)
                                    #'gptel-claude-code--check-stall
                                    process timeout)))
          (if stream
              (progn (set-process-sentinel process #'gptel-claude-code--stream-sentinel)
                     (set-process-filter process #'gptel-claude-code--stream-filter))
            (set-process-filter process #'gptel-claude-code--nonstream-filter)
            (set-process-sentinel process #'gptel-claude-code--sentinel))
          (setf (alist-get process gptel--request-alist)
                (cons fsm
                      (lambda ()
                        ;; Clean up the claude process (abort path)
                        (gptel-claude-code--cancel-timer (gptel-fsm-info fsm))
                        (set-process-sentinel process #'ignore)
                        (delete-process process)
                        (when-let* ((stderr-proc (get-buffer-process stderr-buffer)))
                          (delete-process stderr-proc))
                        (let (kill-buffer-query-functions)
                          (when (buffer-live-p (process-buffer process))
                            (kill-buffer (process-buffer process)))
                          (when (buffer-live-p stderr-buffer)
                            (kill-buffer stderr-buffer))))))))))))

(defun gptel-claude-code--check-stall (process timeout)
  "Kill PROCESS if it has produced no output for TIMEOUT seconds."
  (if (not (process-live-p process))
      (when-let* ((fsm (car (alist-get process gptel--request-alist))))
        (gptel-claude-code--cancel-timer (gptel-fsm-info fsm)))
    (when-let* ((fsm (car (alist-get process gptel--request-alist)))
                (info (gptel-fsm-info fsm))
                (last (plist-get info :cc-last-output)))
      (when (> (- (float-time) last) timeout)
        (gptel-claude-code--cancel-timer info)
        (plist-put info :cc-stalled timeout)
        (delete-process process)))))    ;the sentinel takes it from here

(defun gptel-claude-code--stream-filter (process output)
  "Filter for streaming Claude Code requests.

Inserts OUTPUT into PROCESS's buffer, drives the WAIT->TYPE
transition when the response starts, runs the stream parser, and
demultiplexes text and reasoning callbacks (analog of
`gptel-curl--stream-filter', gptel-request.el L3029-3116, minus
HTTP status handling and <think>-tag support, plus reasoning-block
re-entry for interleaved agentic activity)."
  (when-let* ((fsm (car (alist-get process gptel--request-alist))))
    (let* ((info (gptel-fsm-info fsm))
           (callback (or (plist-get info :callback)
                         #'gptel-curl--stream-insert-response)))
      (with-current-buffer (process-buffer process)
        (save-excursion
          (goto-char (process-mark process))
          (insert output)
          (set-marker (process-mark process) (point)))
        (plist-put info :cc-last-output (float-time))
        ;; Response started: WAIT -> TYPE once the first full line is in.
        (unless (plist-get info :http-status)
          (when (save-excursion (goto-char (point-min))
                                (search-forward "\n" nil t))
            (plist-put info :http-status "200")
            (plist-put info :status "200 OK")
            (gptel--fsm-transition fsm)))
        (when (plist-get info :http-status)
          (let ((response (gptel-curl--parse-stream
                           (plist-get info :backend) info)))
            ;; Reasoning demux.  Unlike gptel's stock filter, the block
            ;; may reopen after closing: agentic runs interleave text
            ;; and tool activity.
            (let ((reasoning (plist-get info :reasoning)))
              (when (stringp reasoning)
                (funcall callback (cons 'reasoning reasoning) info)
                (plist-put info :reasoning nil)
                (plist-put info :reasoning-block 'in)))
            (when (and (eq (plist-get info :reasoning-block) 'in)
                       (length> response 0))
              (funcall callback '(reasoning . t) info)
              (plist-put info :reasoning-block 'done))
            (unless (equal response "")
              (funcall callback response info))))))))

(defun gptel-claude-code--nonstream-filter (process output)
  "Accumulate OUTPUT in PROCESS's buffer and timestamp it (stall timer)."
  (when-let* ((fsm (car (alist-get process gptel--request-alist))))
    (plist-put (gptel-fsm-info fsm) :cc-last-output (float-time)))
  (when (buffer-live-p (process-buffer process))
    (with-current-buffer (process-buffer process)
      (save-excursion
        (goto-char (process-mark process))
        (insert output)
        (set-marker (process-mark process) (point))))))

(defun gptel-claude-code--last-result (buffer)
  "Return the last claude result object in BUFFER, or nil.
Scans backward over the trailing lines of NDJSON (or a single JSON
document) looking for a plist with :type \"result\"."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-max))
        (let ((result nil) (count 0))
          (while (and (not result) (< count 25) (not (bobp)))
            (forward-line -1)
            (cl-incf count)
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (when (string-prefix-p "{" (string-trim-left line))
                (let ((obj (condition-case nil
                               (gptel--json-read-string line)
                             (error nil))))
                  (when (equal (plist-get obj :type) "result")
                    (setq result obj))))))
          ;; Fallback: the whole buffer is one (possibly multi-line)
          ;; JSON document (--output-format json).
          (unless result
            (goto-char (point-min))
            (let ((obj (condition-case nil (gptel--json-read) (error nil))))
              (when (equal (plist-get obj :type) "result")
                (setq result obj))))
          result)))))

(defun gptel-claude-code--set-exit-error (info process exit-status)
  "Set INFO's :error/:status for a failed claude PROCESS with EXIT-STATUS.
Probes, in order: a stall-kill marker, a parseable result object in
the output, the stderr buffer, and finally the bare exit code."
  (let* ((result (gptel-claude-code--last-result (process-buffer process)))
         (stderr-buffer (plist-get info :cc-stderr))
         (stderr (and (buffer-live-p stderr-buffer)
                      (with-current-buffer stderr-buffer
                        (string-trim (buffer-string))))))
    (cond
     ((plist-get info :cc-stalled)
      (plist-put info :error
                 (format "No output from claude for %ss; process killed (backend :timeout).  This may be the known headless-stall CLI bug — retry the request."
                         (plist-get info :cc-stalled)))
      (plist-put info :status "Stalled"))
     (result
      (gptel-claude-code--handle-result result info)
      ;; A result that claims success but a nonzero exit: still an error.
      (unless (plist-get info :error)
        (plist-put info :error (format "claude exited with code %d" exit-status))
        (plist-put info :status "Claude Code failure")))
     ((and stderr (not (string-empty-p stderr)))
      (plist-put info :error (car (split-string stderr "\n")))
      (plist-put info :status "Claude Code startup error"))
     ((= exit-status 143)
      (plist-put info :error "Claude Code terminated (SIGTERM)")
      (plist-put info :status "Terminated"))
     (t
      ;; In-run failures may also land as plain text on stdout.
      (let ((text (and (buffer-live-p (process-buffer process))
                       (with-current-buffer (process-buffer process)
                         (string-trim (buffer-string))))))
        (plist-put info :error
                   (if (and text (not (string-empty-p text))
                            (not (string-prefix-p "{" text)))
                       (format "Claude Code: %s"
                               (truncate-string-to-width text 200 nil nil t))
                     (format "claude exited with code %d" exit-status))))
      (plist-put info :status "Claude Code failure")))))

(defun gptel-claude-code--report-denials (info)
  "Surface permission denials recorded in INFO, if any."
  (when-let* ((denials (plist-get info :cc-denials))
              ((> (length denials) 0)))
    (plist-put info :status
               (format "200 OK (%d tool call%s denied)"
                       (length denials) (if (= (length denials) 1) "" "s")))
    (message "gptel: Claude Code denied %d tool call(s) by permission rules: %s"
             (length denials)
             (mapconcat (lambda (d) (plist-get d :tool_name)) denials ", "))))

(defun gptel-claude-code--cleanup (process fsm)
  "Deregister PROCESS and kill its buffers; cancel FSM's stall timer."
  (when fsm (gptel-claude-code--cancel-timer (gptel-fsm-info fsm)))
  (setf (alist-get process gptel--request-alist nil 'remove) nil)
  (let ((proc-buf (process-buffer process))
        (stderr-buf (and fsm (plist-get (gptel-fsm-info fsm) :cc-stderr)))
        (kill-buffer-query-functions nil))
    (when-let* ((stderr-proc (and (buffer-live-p stderr-buf)
                                  (get-buffer-process stderr-buf))))
      (delete-process stderr-proc))
    (when (buffer-live-p proc-buf) (kill-buffer proc-buf))
    (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))))

(defun gptel-claude-code--stream-sentinel (process _status)
  "Sentinel for streaming Claude Code requests (analog of
`gptel-curl--stream-cleanup', gptel-request.el L2979-3027)."
  (when (memq (process-status process) '(exit signal))
    (let ((fsm (car (alist-get process gptel--request-alist))))
      (when fsm
        (let* ((info (gptel-fsm-info fsm))
               (exit-status (process-exit-status process))
               (callback (plist-get info :callback)))
          (cond
           ;; Clean exit with no recorded error: successful stream end.
           ((and (zerop exit-status) (not (plist-get info :error)))
            (gptel-claude-code--report-denials info)
            (with-demoted-errors "gptel callback error: %S"
              (funcall callback t info)))
           (t                           ;error path
            ;; If the process died before any output, we're still in WAIT.
            (when (eq (gptel-fsm-state fsm) 'WAIT)
              (gptel--fsm-transition fsm)) ;WAIT -> TYPE
            (unless (plist-get info :error)
              (gptel-claude-code--set-exit-error info process exit-status))
            (with-demoted-errors "gptel callback error: %S"
              (funcall callback nil info))))
          (gptel--fsm-transition fsm)))  ;TYPE -> next
      (gptel-claude-code--cleanup process fsm))))

(defun gptel-claude-code--sentinel (process _status)
  "Sentinel for non-streaming Claude Code requests (analog of
`gptel-curl--sentinel', gptel-request.el L3130-3175)."
  (when (memq (process-status process) '(exit signal))
    (let ((fsm (car (alist-get process gptel--request-alist))))
      (when fsm
        (let* ((info (gptel-fsm-info fsm))
               (exit-status (process-exit-status process))
               (callback (plist-get info :callback)))
          (if (zerop exit-status)
              (let ((response
                     (when (buffer-live-p (process-buffer process))
                       (with-current-buffer (process-buffer process)
                         (goto-char (point-min))
                         (condition-case nil (gptel--json-read)
                           (error nil))))))
                (plist-put info :http-status "200")
                (plist-put info :status "200 OK")
                (gptel--fsm-transition fsm) ;WAIT -> TYPE
                (let ((text (and response
                                 (gptel--parse-response
                                  (plist-get info :backend) response info))))
                  (when (null response)
                    (plist-put info :error "Could not parse claude output")
                    (plist-put info :status "Claude Code error"))
                  (unless (plist-get info :error)
                    (gptel-claude-code--report-denials info))
                  ;; Match the curl sentinel's contract: call the
                  ;; callback with text, or with nil on error; skip it
                  ;; entirely for a genuinely empty success (gptel then
                  ;; reports " Empty response").
                  (when (or text (plist-get info :error))
                    (with-demoted-errors "gptel callback error: %S"
                      (funcall callback text info)))))
            ;; Nonzero exit
            (gptel-claude-code--set-exit-error info process exit-status)
            (when (eq (gptel-fsm-state fsm) 'WAIT)
              (gptel--fsm-transition fsm)) ;WAIT -> TYPE
            (with-demoted-errors "gptel callback error: %S"
              (funcall callback nil info)))
          (gptel--fsm-transition fsm)))  ;TYPE -> next
      (gptel-claude-code--cleanup process fsm))))

;;; Transport dispatch (advice)

(defun gptel-claude-code--dispatch (orig-fn fsm)
  "Divert requests for `gptel-claude-code' backends to the CLI transport.
Other backends proceed through ORIG-FN with FSM unchanged."
  (if (cl-typep (plist-get (gptel-fsm-info fsm) :backend) 'gptel-claude-code)
      (gptel-claude-code--get-response fsm)
    (funcall orig-fn fsm)))

;;;###autoload
(defun gptel-claude-code-setup ()
  "Install the Claude Code transport dispatch into gptel.
Idempotent; called automatically by `gptel-make-claude-code'."
  (advice-add 'gptel-curl-get-response :around #'gptel-claude-code--dispatch)
  (advice-add 'gptel--url-get-response :around #'gptel-claude-code--dispatch))

(defun gptel-claude-code-teardown ()
  "Remove the Claude Code transport dispatch from gptel."
  (interactive)
  (advice-remove 'gptel-curl-get-response #'gptel-claude-code--dispatch)
  (advice-remove 'gptel--url-get-response #'gptel-claude-code--dispatch))

(provide 'gptel-claude-code)
;;; gptel-claude-code.el ends here

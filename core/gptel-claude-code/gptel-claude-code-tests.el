;;; gptel-claude-code-tests.el --- Tests for gptel-claude-code  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run offline tests against the INSTALLED gptel (the one the config
;; actually uses), from the repo root:
;;
;;   emacs -Q --batch --eval '(package-initialize)' -L core/gptel-claude-code \
;;     -l gptel-claude-code-tests.el -f ert-run-tests-batch-and-exit
;;
;; (`package-initialize' activates the elpa gptel + transient; the -L
;; puts gptel-claude-code.el on the load path.)  Run this after every
;; gptel package upgrade — the backend reuses gptel internals.
;;
;; Live end-to-end tests (spawn the real claude CLI, cost quota) are
;; skipped unless the environment variable GPTEL_CLAUDE_LIVE is set:
;;   GPTEL_CLAUDE_LIVE=1 emacs -Q --batch ... -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'gptel)
(require 'gptel-claude-code)

(defconst gptel-cc-test--dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory of this test file; the stream fixture lives beside it.")

(defvar gptel-cc-test--backend
  (gptel-make-claude-code "Claude-Code-Test"))

(defun gptel-cc-test--live-p ()
  (and (getenv "GPTEL_CLAUDE_LIVE") (executable-find "claude")))

;;; Serialization

(ert-deftest gptel-cc-serialize-single-turn ()
  "A lone user turn passes through bare."
  (pcase-let ((`(,prompt . ,multi)
               (gptel-claude-code--serialize
                '((:role "user" :content "Hello")))))
    (should (equal prompt "Hello"))
    (should-not multi)))

(ert-deftest gptel-cc-serialize-multi-turn ()
  (pcase-let ((`(,prompt . ,multi)
               (gptel-claude-code--serialize
                '((:role "user" :content "Hello")
                  (:role "assistant" :content "Hi there")
                  (:role "user" :content "What next?")))))
    (should multi)
    (should (equal prompt
                   (concat "<conversation-history>\n"
                           "<user>\nHello\n</user>\n"
                           "<assistant>\nHi there\n</assistant>\n"
                           "</conversation-history>\n\n"
                           "USER: What next?")))))

(ert-deftest gptel-cc-serialize-trailing-assistant ()
  "A transcript ending in an assistant turn gets the continue sentinel."
  (pcase-let ((`(,prompt . ,multi)
               (gptel-claude-code--serialize
                '((:role "user" :content "Hello")
                  (:role "assistant" :content "Hi there")))))
    (should multi)
    (should (string-suffix-p
             (concat "USER: " gptel-claude-code--continue-sentinel) prompt))
    (should (string-match-p "<assistant>\nHi there\n</assistant>" prompt))))

;;; Dry-run payload shape

(defun gptel-cc-test--dry-run-data (&rest request-args)
  "Issue a dry-run `gptel-request' in the current buffer, return :data."
  (let* ((fsm (apply #'gptel-request nil :dry-run t request-args))
         (info (gptel-fsm-info fsm))
         (count 0))
    (while (and (bufferp (plist-get info :data)) (< count 100))
      (sit-for 0.02) (cl-incf count))
    (should-not (bufferp (plist-get info :data)))
    (plist-get info :data)))

(ert-deftest gptel-cc-payload-shape ()
  "Dry-run over a propertized multi-turn buffer yields the exact payload."
  (with-temp-buffer
    (text-mode)
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'sonnet)
          (gptel-stream t)
          (gptel-use-curl t)
          (gptel-track-response t)
          (gptel-use-context nil))
      (insert "Hello\n\n")
      (insert (propertize "Hi there" 'gptel 'response 'front-sticky '(gptel)))
      (insert "\n\nWhat next?")
      (let* ((data (gptel-cc-test--dry-run-data :system "SYS" :stream t))
             (argv (append (plist-get data :argv) nil)))
        (should (equal (plist-get data :prompt)
                       (concat "<conversation-history>\n"
                               "<user>\nHello\n</user>\n"
                               "<assistant>\nHi there\n</assistant>\n"
                               "</conversation-history>\n\n"
                               "USER: What next?")))
        (should (eq (plist-get data :stream) t))
        (should (member "-p" argv))
        (should (member "--no-session-persistence" argv))
        (should (equal (nth (1+ (cl-position "--model" argv :test #'equal)) argv)
                       "sonnet"))
        (should (member "stream-json" argv))
        (should (member "--verbose" argv))
        (should (member "--include-partial-messages" argv))
        ;; Chat profile: --tools ""
        (should (equal (nth (1+ (cl-position "--tools" argv :test #'equal)) argv)
                       ""))
        ;; System prompt carries the replay instruction
        (let ((system (nth (1+ (cl-position "--append-system-prompt" argv
                                            :test #'equal))
                           argv)))
          (should (string-prefix-p "SYS\n\n" system))
          (should (string-match-p "conversation-history" system)))))))

(ert-deftest gptel-cc-payload-single-turn ()
  "A fresh buffer degenerates to a bare prompt with no replay instruction."
  (with-temp-buffer
    (text-mode)
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'sonnet)
          (gptel-stream t)
          (gptel-use-curl t)
          (gptel-track-response t)
          (gptel-use-context nil))
      (insert "Hello")
      (let* ((data (gptel-cc-test--dry-run-data :system "SYS"))
             (argv (append (plist-get data :argv) nil)))
        (should (equal (plist-get data :prompt) "Hello"))
        (should (equal (nth (1+ (cl-position "--append-system-prompt" argv
                                             :test #'equal))
                            argv)
                       "SYS"))))))

(ert-deftest gptel-cc-payload-nonstream ()
  "With streaming off the payload switches to --output-format json."
  (with-temp-buffer
    (text-mode)
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'sonnet)
          (gptel-stream nil)
          (gptel-use-curl t)
          (gptel-track-response t)
          (gptel-use-context nil))
      (insert "Hello")
      ;; :stream t at the request level, but the global gptel-stream nil
      ;; vetoes it (gptel--realize-query's effective-streaming gate).
      (let* ((data (gptel-cc-test--dry-run-data :stream t))
             (argv (append (plist-get data :argv) nil)))
        (should (eq (plist-get data :stream) :json-false))
        (should (member "json" argv))
        (should-not (member "stream-json" argv))
        (should-not (member "--include-partial-messages" argv))))))

;;; Stream parsing

(defconst gptel-cc-test--stream-input
  (concat
   "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"abc\",\"model\":\"claude-haiku\"}\n"
   "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"hmm...\"}}}\n"
   "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello \"}}}\n"
   "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello \"},{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"Bash\",\"input\":{\"command\":\"git status\"}}]}}\n"
   "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"tu_1\",\"content\":\"ok\\nline2\",\"is_error\":false}]}}\n"
   "{\"type\":\"rate_limit_event\",\"info\":\"ignored\"}\n"
   "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"world\"}}}\n"
   "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Hello world\",\"stop_reason\":null,\"num_turns\":2,\"total_cost_usd\":0.0123,\"permission_denials\":[],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3}}\n")
  "Synthetic but spec-shaped stream-json transcript.")

(defun gptel-cc-test--parse-chunked (input chunk-size)
  "Feed INPUT to the stream parser CHUNK-SIZE bytes at a time.
Returns (TEXT . INFO).  Reproduces the process-buffer point
conventions: point persists between calls, output is inserted at
the end without moving point."
  (with-temp-buffer
    (let ((info (list :backend gptel-cc-test--backend))
          (out "")
          (idx 0)
          (len (length input)))
      (goto-char (point-min))
      (while (< idx len)
        (let ((end (min len (+ idx chunk-size))))
          (save-excursion
            (goto-char (point-max))
            (insert (substring input idx end)))
          (setq idx end))
        (setq out (concat out (gptel-curl--parse-stream
                               gptel-cc-test--backend info))))
      (cons out info))))

(ert-deftest gptel-cc-parse-stream-whole ()
  (pcase-let ((`(,text . ,info)
               (gptel-cc-test--parse-chunked
                gptel-cc-test--stream-input (length gptel-cc-test--stream-input))))
    (should (equal text "Hello world"))
    (let ((reasoning (plist-get info :reasoning)))
      (should (string-match-p "hmm\\.\\.\\." reasoning))
      (should (string-match-p "→ Bash: git status" reasoning))
      (should (string-match-p "✓ 2 lines" reasoning)))
    (should (equal (plist-get info :tokens)
                   '(:input 13 :output 5 :cached 2 :cache 3)))
    (should (equal (plist-get info :stop-reason) "success"))
    (should (equal (plist-get info :cc-cost) 0.0123))
    (should-not (plist-get info :error))))

(ert-deftest gptel-cc-parse-stream-chunked ()
  "Chunking invariance: any split of the input yields identical text."
  (let ((whole (car (gptel-cc-test--parse-chunked
                     gptel-cc-test--stream-input
                     (length gptel-cc-test--stream-input)))))
    (dolist (size '(1 7 13 64 251))
      (pcase-let ((`(,text . ,info)
                   (gptel-cc-test--parse-chunked
                    gptel-cc-test--stream-input size)))
        (should (equal text whole))
        (should (equal (plist-get info :tokens)
                       '(:input 13 :output 5 :cached 2 :cache 3)))))))

(ert-deftest gptel-cc-parse-stream-error-result ()
  (pcase-let ((`(,_text . ,info)
               (gptel-cc-test--parse-chunked
                "{\"type\":\"result\",\"subtype\":\"error_max_turns\",\"is_error\":true,\"num_turns\":25}\n"
                27)))
    (should (string-match-p "max-turns" (plist-get info :error)))
    (should (equal (plist-get info :status) "Max turns exceeded"))))

(ert-deftest gptel-cc-parse-stream-fixture-file ()
  "If a recorded real transcript exists, the parser must handle it."
  (let ((fixture (expand-file-name "gptel-claude-code-fixture.jsonl"
                                   gptel-cc-test--dir)))
    (skip-unless (file-readable-p fixture))
    (let ((input (with-temp-buffer
                   (insert-file-contents fixture) (buffer-string))))
      (pcase-let ((`(,text . ,info) (gptel-cc-test--parse-chunked input 113)))
        (should (stringp text))
        (should (> (length text) 0))
        (should (plist-get info :tokens))
        (should-not (plist-get info :error))))))

;;; Non-streaming response parsing

(ert-deftest gptel-cc-parse-response-success ()
  (let* ((info (list :backend gptel-cc-test--backend))
         (response (gptel--json-read-string
                    "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"pong\",\"usage\":{\"input_tokens\":4,\"output_tokens\":1,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0},\"permission_denials\":[]}")))
    (should (equal (gptel--parse-response gptel-cc-test--backend response info)
                   "pong"))
    (should (equal (plist-get info :tokens)
                   '(:input 4 :output 1 :cached 0 :cache 0)))
    (should-not (plist-get info :error))))

(ert-deftest gptel-cc-parse-response-denials ()
  (let* ((info (list :backend gptel-cc-test--backend))
         (response (gptel--json-read-string
                    "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"done\",\"permission_denials\":[{\"tool_name\":\"Bash\",\"tool_use_id\":\"x\",\"tool_input\":{}}]}"))
         (text (gptel--parse-response gptel-cc-test--backend response info)))
    (should (string-prefix-p "done" text))
    (should (string-match-p "denied by permission rules: Bash" text))))

(ert-deftest gptel-cc-parse-response-error ()
  (let* ((info (list :backend gptel-cc-test--backend))
         (response (gptel--json-read-string
                    "{\"type\":\"result\",\"subtype\":\"error_during_execution\",\"is_error\":true,\"result\":\"Invalid model name: bogus\"}")))
    (should-not (gptel--parse-response gptel-cc-test--backend response info))
    (should (string-match-p "Invalid model name" (plist-get info :error)))
    (should (equal (plist-get info :status) "Execution error"))))

;;; Live end-to-end tests (GPTEL_CLAUDE_LIVE=1)

(defun gptel-cc-test--run-live (prompt &rest args)
  "Run a live request with PROMPT; return (EVENTS . FSM).
EVENTS is the reversed list of callback invocations' RESPONSE args.
ARGS are extra `gptel-request' keywords."
  (let* ((events nil)
         (fsm (apply #'gptel-request prompt
                     :callback (lambda (resp _info) (push resp events))
                     args))
         (deadline (+ (float-time) 180)))
    (while (and (not (memq (gptel-fsm-state fsm) '(DONE ERRS ABRT)))
                (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (cons (nreverse events) fsm)))

(ert-deftest gptel-cc-e2e-stream ()
  (skip-unless (gptel-cc-test--live-p))
  (with-temp-buffer
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'haiku)
          (gptel-stream t)
          (gptel-use-curl t)
          (gptel-use-context nil))
      (pcase-let ((`(,events . ,fsm) (gptel-cc-test--run-live
                                      "Reply with exactly one word: pong"
                                      :stream t)))
        (should (eq (gptel-fsm-state fsm) 'DONE))
        (should (memq t events))        ;stream end signal
        (let ((text (mapconcat (lambda (e) (if (stringp e) e "")) events "")))
          (should (string-match-p "pong" (downcase text))))
        (should (plist-get (gptel-fsm-info fsm) :tokens))
        (should-not (cl-find-if (lambda (e) (string-match-p "gptel-claude" (process-name e)))
                                (process-list)))))))

(ert-deftest gptel-cc-e2e-nonstream ()
  (skip-unless (gptel-cc-test--live-p))
  (with-temp-buffer
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'haiku)
          (gptel-stream nil)
          (gptel-use-curl t)
          (gptel-use-context nil))
      (pcase-let ((`(,events . ,fsm) (gptel-cc-test--run-live
                                      "Reply with exactly one word: pong")))
        (should (eq (gptel-fsm-state fsm) 'DONE))
        (let ((text (cl-find-if #'stringp events)))
          (should (string-match-p "pong" (downcase (or text "")))))))))

(ert-deftest gptel-cc-e2e-error ()
  "A bogus CLI flag must surface as a startup error, never as \"Curl\"."
  (skip-unless (gptel-cc-test--live-p))
  (with-temp-buffer
    ;; NOTE: a bogus --model is NOT a reliable error trigger — the CLI
    ;; recovers (or reports is_error with exit 0) inconsistently.  A
    ;; bogus flag fails deterministically at startup (exit 1, stderr).
    (let ((gptel-backend (gptel-make-claude-code "Claude-Code-Err-Test"
                           :extra-args '("--bogus-flag-xyz")))
          (gptel-model 'haiku)
          (gptel-stream t)
          (gptel-use-curl t)
          (gptel-use-context nil))
      (pcase-let ((`(,_events . ,fsm) (gptel-cc-test--run-live "hi" :stream t)))
        (should (eq (gptel-fsm-state fsm) 'ERRS))
        (let ((err (plist-get (gptel-fsm-info fsm) :error)))
          (should (stringp err))
          (should-not (string-match-p "[Cc]url" err)))))))

(ert-deftest gptel-cc-e2e-abort ()
  (skip-unless (gptel-cc-test--live-p))
  (with-temp-buffer
    (let ((gptel-backend gptel-cc-test--backend)
          (gptel-model 'haiku)
          (gptel-stream t)
          (gptel-use-curl t)
          (gptel-use-context nil)
          (buf (current-buffer)))
      (let* ((events nil)
             (fsm (gptel-request "Count slowly from 1 to 500, one number per line."
                    :stream t
                    :callback (lambda (resp _info) (push resp events))))
             (deadline (+ (float-time) 60)))
        ;; Wait for the first output, then abort.
        (while (and (null events) (< (float-time) deadline))
          (accept-process-output nil 0.2))
        (gptel-abort buf)
        (should (eq (gptel-fsm-state fsm) 'ABRT))
        (should (memq 'abort events))
        (should-not (cl-find-if
                     (lambda (p) (string-match-p "gptel-claude" (process-name p)))
                     (process-list)))))))

(provide 'gptel-claude-code-tests)
;;; gptel-claude-code-tests.el ends here

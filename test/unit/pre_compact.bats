#!/usr/bin/env bats

load helper

setup() {
  tandem_setup
  TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
  echo '{"type":"user","message":"refactor the parser"}' > "$TRANSCRIPT"
  # Stand-in for the claude CLI: prints $STUB_OUTPUT, exits $STUB_EXIT,
  # and records its arguments.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/claude" <<EOF
#!/bin/bash
cat >/dev/null
echo "\$@" > "$BATS_TEST_TMPDIR/claude-args"
printf '%s' "\${STUB_OUTPUT:-}"
exit "\${STUB_EXIT:-0}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

run_hook() {
  run bash -c "jq -n --arg cwd '$1' --arg t '${2:-$TRANSCRIPT}' \
    '{cwd: \$cwd, transcript_path: \$t, trigger: \"auto\"}' | '$SCRIPTS/pre-compact.sh'"
}

@test "log written in the last 2 minutes: no model call, log unchanged" {
  write_log 2
  STUB_OUTPUT="- should not appear" run_hook "$ROOT"
  assert_success
  [ ! -e "$BATS_TEST_TMPDIR/claude-args" ]
  [ "$(wc -l < "$LOG")" -eq 2 ]
}

@test "stale log: appends a dated summary entry" {
  write_log 2; age_file "$LOG" 10
  STUB_OUTPUT="- refactoring the parser" run_hook "$ROOT"
  assert_success
  run cat "$LOG"
  assert_line "entry 2"
  assert_line --regexp '^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}: captured before compaction$'
  assert_line "- refactoring the parser"
}

@test "no log yet: creates .agents/progress.md with the entry" {
  STUB_OUTPUT="- first entry" run_hook "$ROOT"
  run cat "$LOG"
  assert_line "- first entry"
}

@test "model call runs with settings and tools switched off" {
  STUB_OUTPUT="- x" run_hook "$ROOT"
  run cat "$BATS_TEST_TMPDIR/claude-args"
  assert_output --partial "--setting-sources"
  assert_output --partial "--tools"
  assert_output --partial "--model haiku"
}

@test "model answers SKIP: log unchanged" {
  write_log 1; age_file "$LOG" 10
  STUB_OUTPUT="SKIP" run_hook "$ROOT"
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "model call fails: log unchanged" {
  write_log 1; age_file "$LOG" 10
  STUB_OUTPUT="- partial" STUB_EXIT=1 run_hook "$ROOT"
  assert_success
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "missing transcript: does nothing" {
  run_hook "$ROOT" "$BATS_TEST_TMPDIR/nope.jsonl"
  assert_success
  [ ! -e "$LOG" ]
}

@test "outside a git repo: does nothing" {
  STUB_OUTPUT="- x" run_hook "$PLAIN"
  assert_success
  [ ! -e "$PLAIN/.agents/progress.md" ]
}

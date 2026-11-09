#!/usr/bin/env bats

load helper

setup() {
  tandem_setup
  MARK="$TMPDIR/tandem-log-check-s1"
}

# run_hook <cwd> [stop_hook_active]
run_hook() {
  run bash -c "jq -n --arg cwd '$1' --argjson active '${2:-false}' \
    '{cwd: \$cwd, session_id: \"s1\", stop_hook_active: \$active}' | '$SCRIPTS/log-check.sh'"
}

@test "first stop of a session: starts the clock and stays quiet" {
  run_hook "$ROOT"
  assert_success
  assert_output ""
  [ -e "$MARK" ]
}

@test "session under 20 minutes old: quiet even with a stale log" {
  write_log 1; age_file "$LOG" 60
  touch "$MARK"; age_file "$MARK" 5
  run_hook "$ROOT"
  assert_output ""
}

@test "log written in the last 20 minutes: quiet" {
  write_log 1; age_file "$LOG" 5
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$ROOT"
  assert_output ""
}

@test "stale log in a 25-minute-old session: asks for an entry" {
  write_log 1; age_file "$LOG" 30
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$ROOT"
  assert_success
  [ "$(jq -r .decision <<<"$output")" = "block" ]
  [[ "$(jq -r .reason <<<"$output")" == *"$LOG"* ]]
}

@test "no log at all in a 25-minute-old session: asks for an entry" {
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$ROOT"
  [ "$(jq -r .decision <<<"$output")" = "block" ]
}

@test "after asking: quiet on the next stop" {
  write_log 1; age_file "$LOG" 30
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$ROOT"
  [ "$(jq -r .decision <<<"$output")" = "block" ]
  run_hook "$ROOT"
  assert_output ""
}

@test "continuation from a Stop hook: never asks twice in a row" {
  write_log 1; age_file "$LOG" 30
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$ROOT" true
  assert_output ""
}

@test "outside a git repo: quiet" {
  touch "$MARK"; age_file "$MARK" 25
  run_hook "$PLAIN"
  assert_output ""
}

#!/usr/bin/env bats

load helper

setup() { tandem_setup; }

run_hook() { run bash -c "jq -n --arg cwd '$1' '{cwd: \$cwd, source: \"startup\"}' | '$SCRIPTS/session-start.sh'"; }

@test "outside a git repo: prints nothing" {
  run_hook "$PLAIN"
  assert_success
  assert_output ""
}

@test "no log yet: prints only the log path line" {
  run_hook "$ROOT"
  assert_success
  assert_output --partial "Session log: $LOG (append-only)"
  refute_output --partial "Latest entries:"
}

@test "short log: replays every entry" {
  write_log 3
  run_hook "$ROOT"
  assert_success
  assert_line "Latest entries:"
  assert_line "entry 1"
  assert_line "entry 3"
}

@test "log over 150 lines: replays only the last 150" {
  write_log 200
  run_hook "$ROOT"
  assert_success
  refute_line "entry 50"
  assert_line "entry 51"
  assert_line "entry 200"
  [ "$(printf '%s\n' "$output" | grep -c '^entry ')" -eq 150 ]
}

@test "subfolder of a repo: finds the log at the repo root" {
  write_log 1
  mkdir -p "$ROOT/src/deep"
  run_hook "$ROOT/src/deep"
  assert_line "entry 1"
}

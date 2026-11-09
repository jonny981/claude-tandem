# Shared setup for Tandem's bats tests: a temp HOME, TMPDIR and git repo,
# so no test touches the real machine.

load '../lib/bats-support/load'
load '../lib/bats-assert/load'

SCRIPTS="$BATS_TEST_DIRNAME/../../plugins/tandem/scripts"

tandem_setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$HOME" "$TMPDIR" "$BATS_TEST_TMPDIR/repo" "$BATS_TEST_TMPDIR/plain"
  git -C "$BATS_TEST_TMPDIR/repo" init -q
  ROOT=$(git -C "$BATS_TEST_TMPDIR/repo" rev-parse --show-toplevel)
  LOG="$ROOT/.agents/progress.md"
  PLAIN="$BATS_TEST_TMPDIR/plain"
}

# Set a file's modification time to N minutes ago (GNU date, then BSD date).
age_file() {
  local stamp
  stamp=$(date -d "-$2 minutes" +%Y%m%d%H%M 2>/dev/null || date -v-"$2"M +%Y%m%d%H%M)
  touch -t "$stamp" "$1"
}

write_log() {
  mkdir -p "$ROOT/.agents"
  local i
  for i in $(seq 1 "$1"); do echo "entry $i"; done > "$LOG"
}

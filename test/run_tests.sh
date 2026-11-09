#!/bin/bash
# Run Tandem's bats tests. Usage: ./test/run_tests.sh [filter]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS="$SCRIPT_DIR/lib/bats-core/bin/bats"

if [ ! -x "$BATS" ]; then
  echo "Error: bats-core not found. Run: git submodule update --init --recursive"
  exit 1
fi

"$BATS" --timing ${1:+--filter "$1"} "$SCRIPT_DIR/unit/"

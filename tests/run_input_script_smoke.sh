#!/usr/bin/env bash
# Input-script ordering smoke (regression for #25).
#
# parse_input_script must return events in cycle order: apply_input_events
# stops at the first future event, so an overlapping-duration entry that
# lands out of order blocks every later press. The script below expands to
#   press a @1000, release a @101000, press b @5000, release b @5100
# With a 20K-cycle budget, cycle order applies 3 of 4 events (only the
# a-release @101000 stays pending). The unsorted order applies just 1.
set -euo pipefail
cd "$(dirname "$0")/.."

EIGS=${EIGENSCRIPT_BIN:-eigenscript}
if ! command -v "$EIGS" >/dev/null 2>&1; then
    EIGS=../EigenScript/src/eigenscript
fi

out=$("$EIGS" dmg.eigs roms/cpu_instrs.gb --cycles 20000 \
      --input-script "1000:a:100000,5000:b:100" 2>&1)

if echo "$out" | grep -q "Input events applied: 3/4"; then
    echo "PASS: input-script events applied in cycle order (3/4)"
else
    echo "FAIL: expected 'Input events applied: 3/4'"
    echo "$out" | grep "Input events applied" || echo "(no applied-events line found)"
    exit 1
fi

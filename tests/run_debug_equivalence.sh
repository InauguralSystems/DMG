#!/usr/bin/env bash
# Debug-engine equivalence gate (#53). The debugger's stepper
# (src/debug.eigs) is the non-inlined, non-twin-marked form of the hot
# loops; its guard is semantic, not textual:
#
#   A. hot engine vs debug engine — full state dump (regs/flags/MMIO/
#      SERLEN/MEMSUM) byte-identical at the same cycle bound.
#   B. a real Blargg ROM driven entirely through the debug engine must
#      print Passed — "the suite stays green with the chrome's engine".
#
# Headless: runs on any pinned binary, no gfx or lib/ui needed. CI gate.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CYCLES="${DMG_DEBUG_EQ_CYCLES:-500000}"
BLARGG_ROM="${DMG_DEBUG_EQ_BLARGG_ROM:-roms/individual/06.gb}"
BLARGG_CYCLES="${DMG_DEBUG_EQ_BLARGG_CYCLES:-40000000}"
TIMEOUT_SECONDS="${DMG_DEBUG_EQ_TIMEOUT_SECONDS:-300}"

if [[ -n "${EIGENSCRIPT_BIN:-}" ]]; then
    EIGS="$EIGENSCRIPT_BIN"
elif [[ -x "$ROOT_DIR/../EigenScript/src/eigenscript" ]]; then
    EIGS="$ROOT_DIR/../EigenScript/src/eigenscript"
elif command -v eigenscript >/dev/null 2>&1; then
    EIGS="$(command -v eigenscript)"
else
    echo "ERROR: eigenscript binary not found (set EIGENSCRIPT_BIN)."
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout command not found."
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

dump() { sed -n '/^=== STATE DUMP/,$p'; }

echo "--- A: hot vs debug engine, ${CYCLES} cycles, cpu_instrs.gb ---"
timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs roms/cpu_instrs.gb \
    --cycles "$CYCLES" --dump-state 2>&1 | dump > "$tmp/hot.txt"
timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs roms/cpu_instrs.gb \
    --cycles "$CYCLES" --dump-state --engine debug 2>&1 | dump > "$tmp/dbg.txt"
if [[ ! -s "$tmp/hot.txt" || ! -s "$tmp/dbg.txt" ]]; then
    echo "FAIL: a dump is empty (run died before the STATE DUMP marker)."
    exit 1
fi
if ! diff -u "$tmp/hot.txt" "$tmp/dbg.txt"; then
    echo "FAIL: debug engine diverged from the hot engine."
    exit 1
fi
echo "PASS: engines byte-identical ($(grep -c . "$tmp/hot.txt") dump lines)"

echo "--- B: Blargg $BLARGG_ROM through the debug engine ---"
out="$(timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs "$BLARGG_ROM" \
    --cycles "$BLARGG_CYCLES" --engine debug 2>&1)"
if ! grep -q "Passed" <<< "$out"; then
    echo "FAIL: Blargg ROM did not pass through the debug engine."
    printf '%s\n' "$out" | tail -5
    exit 1
fi
echo "PASS: Blargg $BLARGG_ROM Passed on the debug engine"

echo "--- C: disasm length-consistency vs the live CPU ---"
out="$(timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs roms/cpu_instrs.gb \
    --cycles 20000000 --disasm-oracle 300000 2>&1)" || {
    echo "FAIL: disasm length oracle exited nonzero"; printf '%s\n' "$out" | tail -4; exit 1; }
if ! grep -q "mismatches=0" <<< "$out"; then
    echo "FAIL: disasm length oracle reported mismatches."
    printf '%s\n' "$out" | tail -4
    exit 1
fi
checked="$(grep -o 'checked=[0-9]*' <<< "$out" | cut -d= -f2)"
if [[ "${checked:-0}" -lt 100000 ]]; then
    echo "FAIL: disasm oracle checked only ${checked:-0} instructions."
    exit 1
fi
echo "PASS: disasm lengths consistent over $checked live instructions"
# The checker must catch a planted wrong-length fault or it proves nothing.
if timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs roms/cpu_instrs.gb \
    --cycles 20000000 --disasm-oracle 1000 --plant-disasm-fault >/dev/null 2>&1; then
    echo "FAIL: planted disasm length fault NOT caught."
    exit 1
fi
echo "PASS: planted disasm length fault caught"

echo "--- D: disasm golden master (regression pin, not proof) ---"
timeout "$TIMEOUT_SECONDS" "$EIGS" dmg.eigs roms/cpu_instrs.gb \
    --disasm-dump 256 24 2>/dev/null | grep -v "^ROM loaded" > "$tmp/dis.txt"
if ! diff -u tests/disasm_golden.txt "$tmp/dis.txt"; then
    echo "FAIL: disasm output drifted from the golden master."
    exit 1
fi
echo "PASS: disasm golden master unchanged"

echo "PASS: debug-engine equivalence gate"

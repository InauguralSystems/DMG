#!/usr/bin/env bash
# Planted-fault self-test for the Blargg CI gate (tests/run_blargg_ci.sh)
# and for the disasm plant check in tests/run_debug_equivalence.sh.
#
# Each plant is applied to a scratch copy of the tree, and the real gate
# script is run on that copy. A plant passes when the gate goes RED for the
# expected reason. Each plant checks that its edit actually changed the
# copy, so a plant that no longer applies fails instead of passing.
#
#   --quick (CI)  plants that need no full ROM run: a fake runtime that
#                 makes one ROM report Failed (alone, or next to Passed),
#                 the skip-list and count-pin checks, a missing ROM, a
#                 selection that runs nothing, and the disasm plant crash
#                 (DMG-EQ-C).
#   (default)     --quick plus the two emulator plants, each run through the
#                 full gate (about a minute each): DAA "a -= 0x06" -> 0x07
#                 (fails individual 01.gb) and LD (a16),SP "return 20" -> 16
#                 (fails instr_timing). Run this whenever the gate, the
#                 runners or the skip list change.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=full
case "${1:-}" in
    "") ;;
    --quick) MODE=quick ;;
    *) echo "usage: $0 [--quick]"; exit 2 ;;
esac

source "$ROOT_DIR/tests/runtime.sh"
EIGS="$(dmg_runtime "$ROOT_DIR" "${EIGENSCRIPT_BIN:-}")"
case "$EIGS" in /*) ;; *) EIGS="$(command -v "$EIGS")" ;; esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
N=0

fresh_tree() {
    local dst="$TMP/$1"
    rm -rf "$dst"
    mkdir -p "$dst"
    tar -C "$ROOT_DIR" --exclude=./.git -cf - . | tar -C "$dst" -xf -
    printf '%s\n' "$dst"
}

# plant_edit FILE OLD NEW: replace the one occurrence of OLD (fixed string).
plant_edit() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
n = src.count(old)
if n != 1:
    sys.exit(f"plant not applied: {old!r} occurs {n} times in {path}")
open(path, "w").write(src.replace(old, new))
PY
}

# expect_red NAME PATTERN -- CMD...: CMD must exit nonzero and print PATTERN.
expect_red() {
    local name="$1" pattern="$2" out rc
    shift 3
    N=$((N + 1))
    set +e
    out="$("$@" 2>&1)"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]] && grep -Eq -- "$pattern" <<< "$out"; then
        echo "ok: plant $name -> RED (rc=$rc): $(grep -Em1 -- "$pattern" <<< "$out")"
    else
        echo "FAIL: plant $name was not caught (rc=$rc, want /$pattern/)"
        printf '%s\n' "$out" | tail -n 12 | sed 's/^/    /'
        FAILS=$((FAILS + 1))
    fi
}

# A fake runtime that reports Failed for one ROM and Passed for the rest.
# It checks that the gate's verdict and its per-ROM attribution work without
# running the emulator. FAKE_BOTH_ROM prints Passed AND Failed for one ROM,
# so the runners' "Failed" check is tested on its own (the "did not report
# Passed" check cannot catch that output).
cat > "$TMP/fake_eigs" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo fake; exit 0; }
case "${2:-}" in
    *"${FAKE_FAIL_ROM:-no-rom-fails}") printf 'Failed\nCycles: 1000\n' ;;
    *"${FAKE_BOTH_ROM:-no-rom-both}") printf 'Passed\nFailed\nCycles: 1000\n' ;;
    *) printf 'Passed\nCycles: 1000\n' ;;
esac
EOF
chmod +x "$TMP/fake_eigs"

echo "== quick plants"
t="$(fresh_tree verdict)"
expect_red "fake runtime: 01.gb reports Failed" \
    '^FAIL: Blargg CI gate \(1 failed: cpu:individual_01\)$' -- \
    env FAKE_FAIL_ROM=individual/01.gb EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"
expect_red "fake runtime: interrupt_time reports Failed" \
    '^FAIL: Blargg CI gate \(1 failed: timing:interrupt_time\)$' -- \
    env FAKE_FAIL_ROM=interrupt_time.gb EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"
expect_red "fake runtime: 07.gb reports Passed and Failed" \
    '^FAIL: Blargg CI gate \(1 failed: cpu:individual_07\)$' -- \
    env FAKE_BOTH_ROM=individual/07.gb EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"
expect_red "fake runtime: mem_timing reports Passed and Failed" \
    '^FAIL: Blargg CI gate \(1 failed: timing:mem_timing\)$' -- \
    env FAKE_BOTH_ROM=roms/mem_timing.gb EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"

t="$(fresh_tree skip_extra)"
printf 'cpu:individual_05 planted: silently drop a ROM\n' >> "$t/tests/blargg_ci_skip.txt"
expect_red "skip list drops individual_05" \
    '^FAIL: 14 ROMs selected, pinned EXPECTED_ROMS=15' -- \
    env EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"

t="$(fresh_tree skip_noreason)"
printf 'timing:mem_timing\n' >> "$t/tests/blargg_ci_skip.txt"
expect_red "skip entry without a reason" \
    "^FAIL: skip entry 'timing:mem_timing' has no reason" -- \
    env EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"

t="$(fresh_tree skip_unknown)"
printf 'cpu:individual_12 no such ROM\n' >> "$t/tests/blargg_ci_skip.txt"
expect_red "skip entry naming an unknown ROM" \
    "^FAIL: skip entry 'cpu:individual_12' names no ROM a runner lists" -- \
    env EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"

t="$(fresh_tree rom_missing)"
rm "$t/roms/mem_timing-2/mem_timing.gb"
expect_red "missing ROM file" \
    '^FAIL: Blargg CI gate \(1 failed: timing:mem_timing_2\)$' -- \
    env EIGENSCRIPT_BIN="$TMP/fake_eigs" "$t/tests/run_blargg_ci.sh"

expect_red "runner selection that runs nothing" \
    '^FAIL: no ROM selected' -- \
    env EIGENSCRIPT="$TMP/fake_eigs" BLARGG_CPU_INSTRS_MODE=individual \
        BLARGG_CPU_INSTRS_ONLY=cpu_instrs "$ROOT_DIR/tests/run_blargg_cpu_instrs_suite.sh"

# DMG-EQ-C: a crash in the --plant-disasm-fault path used to count as
# "caught", because the old check accepted any nonzero exit.
t="$(fresh_tree eqc)"
plant_edit "$t/dmg.eigs" '        _dis_plant[0] is 1
' '        _dis_plant[0] is 1
        boom is undefined_name_planted + 1
'
expect_red "disasm plant path crashes (DMG-EQ-C)" \
    '^FAIL: planted disasm run failed without the oracle reporting the plant' -- \
    env EIGENSCRIPT_BIN="$EIGS" "$t/tests/run_debug_equivalence.sh"

if [[ "$MODE" == full ]]; then
    echo "== emulator plants (full gate runs)"
    t="$(fresh_tree daa)"
    plant_edit "$t/src/cpu.eigs" '            a -= 0x06' '            a -= 0x07'
    expect_red "DAA subtract 0x06 -> 0x07" \
        '^FAIL: Blargg CI gate \([0-9]+ failed: .*cpu:individual_01' -- \
        env EIGENSCRIPT_BIN="$EIGS" "$t/tests/run_blargg_ci.sh"

    t="$(fresh_tree ldsp)"
    plant_edit "$t/src/opcodes.eigs" '    cpu_mem_write of [ctx[0], ctx[1], (addr + 1) & 0xFFFF, ctx[0].sp >> 8]
    return 20' '    cpu_mem_write of [ctx[0], ctx[1], (addr + 1) & 0xFFFF, ctx[0].sp >> 8]
    return 16'
    expect_red "LD (a16),SP 20 -> 16 cycles" \
        '^FAIL: Blargg CI gate \([0-9]+ failed: .*timing:instr_timing' -- \
        env EIGENSCRIPT_BIN="$EIGS" "$t/tests/run_blargg_ci.sh"
fi

if [[ "$FAILS" -ne 0 ]]; then
    echo "FAIL: $FAILS of $N plants were not caught"
    exit 1
fi
echo "PASS: all $N plants caught ($MODE)"

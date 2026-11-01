#!/usr/bin/env bash
# CI gate for the Blargg ROMs: the 11 individual cpu_instrs ROMs and the
# timing ROMs (instr_timing, mem_timing, mem_timing-2, interrupt_time).
#
# Each ROM runs through its existing runner (tests/run_blargg_*_suite.sh),
# which applies the full verdict: exit status, timeout, "Failed", "Passed",
# the Blargg RAM result, cycle progress and the RSS guard. This script runs
# them in parallel, one runner invocation per ROM, and then checks that
# each one passed.
#
# Nothing is skipped silently. The ROM set is taken from the runners' own
# --list output. A ROM that is not run must be named, with a reason, in
# tests/blargg_ci_skip.txt. The number of ROMs that run is pinned in
# EXPECTED_ROMS, so a ROM that drops out of the set fails the gate.
#
# Budgets are the runners' defaults: inherited BLARGG_CPU_INSTRS_* and
# BLARGG_TIMING_* tunables are cleared so the gate always checks the same
# budgets. BLARGG_CI_JOBS sets the number of parallel jobs (default: nproc).
set -euo pipefail

# mapfile, declare -A and date +%s%N need bash 4+ and GNU date (stock macOS
# bash is 3.2: install a newer bash, e.g. from Homebrew, to run this locally).
if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: $0 needs bash 4 or newer (this is bash $BASH_VERSION)."
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Count pin: 11 individual cpu_instrs ROMs + 4 timing ROMs. Change it only
# together with a runner's ROM list or tests/blargg_ci_skip.txt.
EXPECTED_ROMS=15
SKIP_FILE="$ROOT_DIR/tests/blargg_ci_skip.txt"

source "$ROOT_DIR/tests/runtime.sh"
EIGS="$(dmg_runtime "$ROOT_DIR" "${EIGENSCRIPT_BIN:-}")"

for tool in timeout xargs nproc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "PREREQ MISSING: $tool"
        exit 1
    fi
done
if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "PREREQ MISSING: /usr/bin/time (GNU time; the runners' RSS guard needs it)"
    exit 1
fi

JOBS="${BLARGG_CI_JOBS:-$(nproc)}"
if ! [[ "$JOBS" =~ ^[0-9]+$ && "$JOBS" -gt 0 ]]; then
    echo "ERROR: BLARGG_CI_JOBS must be a positive integer."
    exit 1
fi

while IFS= read -r var; do
    unset "$var"
done < <(compgen -e | grep -E '^BLARGG_(CPU_INSTRS|TIMING)_' || true)
export EIGENSCRIPT="$EIGS"

list_labels() {
    local out
    case "$1" in
        cpu) out="$(BLARGG_CPU_INSTRS_MODE=all tests/run_blargg_cpu_instrs_suite.sh --list)" ;;
        timing) out="$(tests/run_blargg_timing_suite.sh --list)" ;;
    esac
    if [[ -z "$out" ]]; then
        echo "FAIL: the $1 runner listed no ROMs." >&2
        return 1
    fi
    printf '%s\n' "$out"
}

CPU_LABELS=()
TIMING_LABELS=()
mapfile -t CPU_LABELS < <(list_labels cpu)
mapfile -t TIMING_LABELS < <(list_labels timing)
if [[ "${#CPU_LABELS[@]}" -eq 0 || "${#TIMING_LABELS[@]}" -eq 0 ]]; then
    echo "FAIL: could not list the runners' ROMs."
    exit 1
fi

declare -A KNOWN=()
for label in "${CPU_LABELS[@]}"; do KNOWN["cpu:$label"]=1; done
for label in "${TIMING_LABELS[@]}"; do KNOWN["timing:$label"]=1; done

declare -A SKIP=()
if [[ ! -f "$SKIP_FILE" ]]; then
    echo "FAIL: missing $SKIP_FILE"
    exit 1
fi
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${line%%[[:space:]]*}"
    reason="${line#"$key"}"
    reason="${reason#"${reason%%[![:space:]]*}"}"
    if [[ -z "$reason" ]]; then
        echo "FAIL: skip entry '$key' has no reason ($SKIP_FILE)."
        exit 1
    fi
    if [[ -z "${KNOWN[$key]:-}" ]]; then
        echo "FAIL: skip entry '$key' names no ROM a runner lists ($SKIP_FILE)."
        exit 1
    fi
    if [[ -n "${SKIP[$key]:-}" ]]; then
        echo "FAIL: duplicate skip entry '$key' ($SKIP_FILE)."
        exit 1
    fi
    SKIP["$key"]="$reason"
done < "$SKIP_FILE"

# Longest first: the higher-numbered individual ROMs run longest (11.gb
# sets the wall-time floor), so start them first; the timing ROMs are short.
WORK=()
for (( i=${#CPU_LABELS[@]}-1; i>=0; i-- )); do
    key="cpu:${CPU_LABELS[$i]}"
    [[ -n "${SKIP[$key]:-}" ]] || WORK+=("$key")
done
for label in "${TIMING_LABELS[@]}"; do
    key="timing:$label"
    [[ -n "${SKIP[$key]:-}" ]] || WORK+=("$key")
done

for key in "${!SKIP[@]}"; do
    echo "skip (allowlisted): $key: ${SKIP[$key]}"
done
if [[ "${#WORK[@]}" -ne "$EXPECTED_ROMS" ]]; then
    echo "FAIL: ${#WORK[@]} ROMs selected, pinned EXPECTED_ROMS=$EXPECTED_ROMS (${WORK[*]})."
    exit 1
fi

BLARGG_CI_TMP="$(mktemp -d)"
trap 'rm -rf "$BLARGG_CI_TMP"' EXIT
export BLARGG_CI_TMP

run_one() {
    local key="$1" runner="${1%%:*}" label="${1#*:}"
    local log="$BLARGG_CI_TMP/$runner.$label.log" rc start end
    start="$(date +%s%N)"
    set +e
    case "$runner" in
        cpu) BLARGG_CPU_INSTRS_MODE=all BLARGG_CPU_INSTRS_ONLY="$label" \
                tests/run_blargg_cpu_instrs_suite.sh >"$log" 2>&1 ;;
        timing) BLARGG_TIMING_ONLY="$label" \
                tests/run_blargg_timing_suite.sh >"$log" 2>&1 ;;
        *) echo "unknown runner: $runner" >"$log"; false ;;
    esac
    rc=$?
    set -e
    end="$(date +%s%N)"
    echo "$rc" >"$log.rc"
    printf 'done: %-24s rc=%s %d.%01ds\n' "$key" "$rc" \
        $(( (end - start) / 1000000000 )) $(( (end - start) / 100000000 % 10 ))
}
export -f run_one

echo "Blargg CI gate: ${#WORK[@]} ROMs, jobs=$JOBS, runtime=$EIGS ($("$EIGS" --version 2>/dev/null || echo '?'))"
wall_start="$(date +%s%N)"
# shellcheck disable=SC2016  # $1 expands in the child bash, not here
printf '%s\n' "${WORK[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one "$1"' _ {}
wall_end="$(date +%s%N)"

passed=0
failed=()
for key in "${WORK[@]}"; do
    runner="${key%%:*}"
    label="${key#*:}"
    log="$BLARGG_CI_TMP/$runner.$label.log"
    rc="$(cat "$log.rc" 2>/dev/null || echo missing)"
    if [[ "$rc" == "0" ]] \
        && [[ "$(grep -c "^ok: rom=$label " "$log")" -eq 1 ]] \
        && grep -q '^PASS: Blargg' "$log"; then
        passed=$((passed + 1))
        grep "^ok: rom=$label " "$log"
    else
        failed+=("$key")
    fi
done

for key in "${failed[@]}"; do
    runner="${key%%:*}"
    label="${key#*:}"
    log="$BLARGG_CI_TMP/$runner.$label.log"
    echo "FAIL: $key (rc=$(cat "$log.rc" 2>/dev/null || echo missing))"
    # Drop GNU time's tab-indented stats so the ROM's own verdict shows.
    grep -v $'^\t' "$log" 2>/dev/null | tail -n 20 | sed 's/^/    /'
done

wall_ms=$(( (wall_end - wall_start) / 1000000 ))
echo "Blargg CI gate: passed=$passed/${#WORK[@]} wall=$((wall_ms / 1000)).$(( (wall_ms % 1000) / 100 ))s"
if [[ "${#failed[@]}" -ne 0 || "$passed" -ne "$EXPECTED_ROMS" ]]; then
    echo "FAIL: Blargg CI gate (${#failed[@]} failed: ${failed[*]})"
    exit 1
fi
echo "PASS: Blargg CI gate"

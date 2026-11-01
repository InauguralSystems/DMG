#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --list prints the labels this invocation would run (after ONLY) and exits;
# tests/run_blargg_ci.sh uses it so a ROM added here cannot go unexercised in
# CI without an entry in tests/blargg_ci_skip.txt.
LIST_ONLY=0
case "${1:-}" in
    "") ;;
    --list) LIST_ONLY=1 ;;
    *) echo "ERROR: unknown argument: $1 (only --list is accepted)"; exit 1 ;;
esac

# BLARGG_TIMING_ONLY=<label> runs just that ROM (CI runs the ROMs in
# parallel, one invocation each). An unknown label is an error.
ONLY="${BLARGG_TIMING_ONLY:-}"

CYCLES="${BLARGG_TIMING_CYCLES:-50000000}"
TIMEOUT_SECONDS="${BLARGG_TIMING_TIMEOUT_SECONDS:-180}"
MAX_RSS_KB="${BLARGG_TIMING_MAX_RSS_KB:-65536}"

if ! [[ "$CYCLES" =~ ^[0-9]+$ && "$CYCLES" -gt 0 ]]; then
    echo "ERROR: BLARGG_TIMING_CYCLES must be a positive integer."
    exit 1
fi

if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$TIMEOUT_SECONDS" -gt 0 ]]; then
    echo "ERROR: BLARGG_TIMING_TIMEOUT_SECONDS must be a positive integer."
    exit 1
fi

if ! [[ "$MAX_RSS_KB" =~ ^[0-9]+$ && "$MAX_RSS_KB" -gt 0 ]]; then
    echo "ERROR: BLARGG_TIMING_MAX_RSS_KB must be a positive integer."
    exit 1
fi

LABELS=(
    instr_timing
    mem_timing
    mem_timing_2
    interrupt_time
)

ROMS=(
    "$ROOT_DIR/roms/instr_timing.gb"
    "$ROOT_DIR/roms/mem_timing.gb"
    "$ROOT_DIR/roms/mem_timing-2/mem_timing.gb"
    "$ROOT_DIR/roms/interrupt_time/interrupt_time.gb"
)

selected() {
    [[ -z "$ONLY" || "$1" == "$ONLY" ]]
}

if [[ -n "$ONLY" ]]; then
    known=0
    for label in "${LABELS[@]}"; do
        if [[ "$label" == "$ONLY" ]]; then
            known=1
        fi
    done
    if [[ "$known" -ne 1 ]]; then
        echo "ERROR: BLARGG_TIMING_ONLY=$ONLY is not a known label (${LABELS[*]})."
        exit 1
    fi
fi

if [[ "$LIST_ONLY" -eq 1 ]]; then
    for label in "${LABELS[@]}"; do
        if selected "$label"; then
            echo "$label"
        fi
    done
    exit 0
fi

# The runtime is resolved only when ROMs will run, so --list works without it.
if [[ -n "${EIGENSCRIPT:-}" ]]; then
    EIGENSCRIPT_BIN="$EIGENSCRIPT"
elif [[ -x "$ROOT_DIR/../EigenScript/src/eigenscript" ]]; then
    EIGENSCRIPT_BIN="$ROOT_DIR/../EigenScript/src/eigenscript"
elif command -v eigenscript >/dev/null 2>&1; then
    EIGENSCRIPT_BIN="$(command -v eigenscript)"
else
    echo "ERROR: eigenscript binary not found."
    echo "Set EIGENSCRIPT=/path/to/eigenscript."
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout command not found; refusing to run an uncapped timing suite."
    exit 1
fi

if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "ERROR: /usr/bin/time not found; RSS guard requires GNU time."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MAX_SEEN_RSS_KB=0
RAN=0
RAN_LABELS=()

echo "Blargg timing suite: only=${ONLY:-<all>} cycles=$CYCLES timeout=${TIMEOUT_SECONDS}s max_rss=${MAX_RSS_KB}KB"

for i in "${!LABELS[@]}"; do
    LABEL="${LABELS[$i]}"
    ROM_PATH="${ROMS[$i]}"
    LOG_FILE="$TMP_DIR/${LABEL}.log"

    if ! selected "$LABEL"; then
        continue
    fi

    if [[ ! -f "$ROM_PATH" ]]; then
        echo "FAIL: missing ROM for ${LABEL}: $ROM_PATH"
        exit 1
    fi

    set +e
    timeout "${TIMEOUT_SECONDS}s" /usr/bin/time -v \
        "$EIGENSCRIPT_BIN" "$ROOT_DIR/dmg.eigs" "$ROM_PATH" --cycles "$CYCLES" \
        >"$LOG_FILE" 2>&1
    STATUS=$?
    set -e

    if [[ "$STATUS" -eq 124 ]]; then
        echo "FAIL: ${LABEL} timed out after ${TIMEOUT_SECONDS}s."
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$STATUS" -ne 0 ]]; then
        echo "FAIL: ${LABEL} exited with status $STATUS."
        tail -n 100 "$LOG_FILE"
        exit "$STATUS"
    fi

    if grep -qi "Failed" "$LOG_FILE"; then
        echo "FAIL: ${LABEL} reported a Blargg failure."
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if ! grep -q "Passed" "$LOG_FILE"; then
        echo "FAIL: ${LABEL} did not report Passed."
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    RAM_RESULT="$(sed -n 's/Blargg RAM result: \([0-9][0-9]*\)/\1/p' "$LOG_FILE" | tail -n 1)"
    if [[ -n "$RAM_RESULT" && "$RAM_RESULT" -ne 0 ]]; then
        echo "FAIL: ${LABEL} reported nonzero Blargg RAM result: $RAM_RESULT"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    REPORTED_CYCLES="$(awk '/^Cycles: / { cycles = $2 } END { print cycles + 0 }' "$LOG_FILE")"
    RSS_KB="$(awk -F': ' '/Maximum resident set size/ { rss = $2 } END { print rss + 0 }' "$LOG_FILE")"

    if [[ "$REPORTED_CYCLES" -le 0 ]]; then
        echo "FAIL: ${LABEL} did not report cycle progress."
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$RSS_KB" -gt "$MAX_RSS_KB" ]]; then
        echo "FAIL: ${LABEL} exceeded RSS guard."
        echo "Max RSS:       ${RSS_KB} KB"
        echo "Allowed RSS:   ${MAX_RSS_KB} KB"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$RSS_KB" -gt "$MAX_SEEN_RSS_KB" ]]; then
        MAX_SEEN_RSS_KB="$RSS_KB"
    fi

    RAN=$((RAN + 1))
    RAN_LABELS+=("$LABEL")
    printf 'ok: rom=%s cycles=%s rss_kb=%s\n' "$LABEL" "$REPORTED_CYCLES" "$RSS_KB"
done

# A selection that ran nothing is a failure, not a pass.
if [[ "$RAN" -eq 0 ]]; then
    echo "FAIL: no ROM selected (only=${ONLY:-<all>})."
    exit 1
fi

echo "PASS: Blargg timing suite"
echo "ROMs:     ${RAN_LABELS[*]}"
echo "Peak RSS: ${MAX_SEEN_RSS_KB} KB"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${BLARGG_CPU_INSTRS_MODE:-all}"
AGGREGATE_CYCLES="${BLARGG_CPU_INSTRS_AGGREGATE_CYCLES:-${BLARGG_CPU_INSTRS_CYCLES:-260000000}}"
INDIVIDUAL_CYCLES="${BLARGG_CPU_INSTRS_INDIVIDUAL_CYCLES:-${BLARGG_CPU_INSTRS_CYCLES:-120000000}}"
AGGREGATE_TIMEOUT_SECONDS="${BLARGG_CPU_INSTRS_AGGREGATE_TIMEOUT_SECONDS:-${BLARGG_CPU_INSTRS_TIMEOUT_SECONDS:-1500}}"
INDIVIDUAL_TIMEOUT_SECONDS="${BLARGG_CPU_INSTRS_INDIVIDUAL_TIMEOUT_SECONDS:-${BLARGG_CPU_INSTRS_TIMEOUT_SECONDS:-700}}"
MAX_RSS_KB="${BLARGG_CPU_INSTRS_MAX_RSS_KB:-65536}"

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

if ! [[ "$AGGREGATE_CYCLES" =~ ^[0-9]+$ && "$AGGREGATE_CYCLES" -gt 0 ]]; then
    echo "ERROR: BLARGG_CPU_INSTRS_AGGREGATE_CYCLES must be a positive integer."
    exit 1
fi

if ! [[ "$INDIVIDUAL_CYCLES" =~ ^[0-9]+$ && "$INDIVIDUAL_CYCLES" -gt 0 ]]; then
    echo "ERROR: BLARGG_CPU_INSTRS_INDIVIDUAL_CYCLES must be a positive integer."
    exit 1
fi

if ! [[ "$AGGREGATE_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$AGGREGATE_TIMEOUT_SECONDS" -gt 0 ]]; then
    echo "ERROR: BLARGG_CPU_INSTRS_AGGREGATE_TIMEOUT_SECONDS must be a positive integer."
    exit 1
fi

if ! [[ "$INDIVIDUAL_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$INDIVIDUAL_TIMEOUT_SECONDS" -gt 0 ]]; then
    echo "ERROR: BLARGG_CPU_INSTRS_INDIVIDUAL_TIMEOUT_SECONDS must be a positive integer."
    exit 1
fi

if ! [[ "$MAX_RSS_KB" =~ ^[0-9]+$ && "$MAX_RSS_KB" -gt 0 ]]; then
    echo "ERROR: BLARGG_CPU_INSTRS_MAX_RSS_KB must be a positive integer."
    exit 1
fi

case "$MODE" in
    all|aggregate|individual)
        ;;
    *)
        echo "ERROR: BLARGG_CPU_INSTRS_MODE must be all, aggregate, or individual."
        exit 1
        ;;
esac

if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout command not found; refusing to run an uncapped CPU instruction suite."
    exit 1
fi

if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "ERROR: /usr/bin/time not found; RSS guard requires GNU time."
    exit 1
fi

LABELS=(
    cpu_instrs
    individual_01
    individual_02
    individual_03
    individual_04
    individual_05
    individual_06
    individual_07
    individual_08
    individual_09
    individual_10
    individual_11
)

ROMS=(
    "$ROOT_DIR/roms/cpu_instrs.gb"
    "$ROOT_DIR/roms/individual/01.gb"
    "$ROOT_DIR/roms/individual/02.gb"
    "$ROOT_DIR/roms/individual/03.gb"
    "$ROOT_DIR/roms/individual/04.gb"
    "$ROOT_DIR/roms/individual/05.gb"
    "$ROOT_DIR/roms/individual/06.gb"
    "$ROOT_DIR/roms/individual/07.gb"
    "$ROOT_DIR/roms/individual/08.gb"
    "$ROOT_DIR/roms/individual/09.gb"
    "$ROOT_DIR/roms/individual/10.gb"
    "$ROOT_DIR/roms/individual/11.gb"
)

CYCLE_BUDGETS=(
    "$AGGREGATE_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
    "$INDIVIDUAL_CYCLES"
)

TIMEOUTS=(
    "$AGGREGATE_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
    "$INDIVIDUAL_TIMEOUT_SECONDS"
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MAX_SEEN_RSS_KB=0
TOTAL_REPORTED_CYCLES=0

echo "Blargg CPU instruction suite: mode=$MODE aggregate_cycles=$AGGREGATE_CYCLES aggregate_timeout=${AGGREGATE_TIMEOUT_SECONDS}s individual_cycles=$INDIVIDUAL_CYCLES individual_timeout=${INDIVIDUAL_TIMEOUT_SECONDS}s max_rss=${MAX_RSS_KB}KB"

for i in "${!LABELS[@]}"; do
    LABEL="${LABELS[$i]}"
    ROM_PATH="${ROMS[$i]}"
    CYCLES="${CYCLE_BUDGETS[$i]}"
    TIMEOUT_SECONDS="${TIMEOUTS[$i]}"
    LOG_FILE="$TMP_DIR/${LABEL}.log"

    if [[ "$MODE" == "aggregate" && "$LABEL" != "cpu_instrs" ]]; then
        continue
    fi
    if [[ "$MODE" == "individual" && "$LABEL" == "cpu_instrs" ]]; then
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
    TOTAL_REPORTED_CYCLES=$((TOTAL_REPORTED_CYCLES + REPORTED_CYCLES))

    printf 'ok: rom=%s budget=%s cycles=%s rss_kb=%s\n' "$LABEL" "$CYCLES" "$REPORTED_CYCLES" "$RSS_KB"
done

echo "PASS: Blargg CPU instruction suite"
echo "Mode:         ${MODE}"
echo "Total cycles: ${TOTAL_REPORTED_CYCLES}"
echo "Peak RSS:     ${MAX_SEEN_RSS_KB} KB"

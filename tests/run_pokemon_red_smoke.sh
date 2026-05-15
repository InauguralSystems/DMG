#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROM_PATH="${POKEMON_RED_ROM:-$ROOT_DIR/roms/pokemon-red.gb}"
CHECKPOINTS="${POKEMON_RED_CHECKPOINTS:-${POKEMON_RED_CYCLES:-1000000 3000000 5000000 10000000}}"
TIMEOUT_SECONDS="${POKEMON_RED_TIMEOUT_SECONDS:-240}"
MAX_RSS_KB="${POKEMON_RED_MAX_RSS_KB:-65536}"

if [[ ! -f "$ROM_PATH" ]]; then
    echo "SKIP: Pokemon Red ROM not found."
    echo "Set POKEMON_RED_ROM=/path/to/pokemon-red.gb or place an untracked ROM at roms/pokemon-red.gb."
    exit 0
fi

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
    echo "ERROR: timeout command not found; refusing to run an uncapped smoke test."
    exit 1
fi

if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "ERROR: /usr/bin/time not found; RSS guard requires GNU time."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

read -r -a CHECKPOINT_ARRAY <<< "$CHECKPOINTS"
if [[ "${#CHECKPOINT_ARRAY[@]}" -eq 0 ]]; then
    echo "ERROR: no Pokemon Red checkpoints configured."
    exit 1
fi

PREV_CHECKPOINT=0
SNAPSHOT_COUNT=0
UNIQUE_STATES=""
MAX_SEEN_RSS_KB=0
FIRST_RSS_KB=0
LAST_RSS_KB=0
LAST_REPORTED_CYCLES=0

echo "Pokemon Red smoke checkpoints: ${CHECKPOINT_ARRAY[*]}"

for CHECKPOINT in "${CHECKPOINT_ARRAY[@]}"; do
    if ! [[ "$CHECKPOINT" =~ ^[0-9]+$ ]]; then
        echo "ERROR: invalid checkpoint '$CHECKPOINT'. Use integer cycle counts."
        exit 1
    fi
    if [[ "$CHECKPOINT" -le "$PREV_CHECKPOINT" ]]; then
        echo "ERROR: checkpoints must be strictly increasing."
        echo "Previous: $PREV_CHECKPOINT"
        echo "Current:  $CHECKPOINT"
        exit 1
    fi

    LOG_FILE="$TMP_DIR/pokemon-red-${CHECKPOINT}.log"
    set +e
    timeout "${TIMEOUT_SECONDS}s" /usr/bin/time -v \
        "$EIGENSCRIPT_BIN" "$ROOT_DIR/dmg.eigs" "$ROM_PATH" --cycles "$CHECKPOINT" \
        >"$LOG_FILE" 2>&1
    STATUS=$?
    set -e

    if [[ "$STATUS" -eq 124 ]]; then
        echo "FAIL: Pokemon Red checkpoint ${CHECKPOINT} timed out after ${TIMEOUT_SECONDS}s."
        tail -n 80 "$LOG_FILE"
        exit 1
    fi

    if [[ "$STATUS" -ne 0 ]]; then
        echo "FAIL: Pokemon Red checkpoint ${CHECKPOINT} exited with status $STATUS."
        tail -n 100 "$LOG_FILE"
        exit "$STATUS"
    fi

    REPORTED_CYCLES="$(awk '/^Cycles: / { cycles = $2 } END { print cycles + 0 }' "$LOG_FILE")"
    RSS_KB="$(awk -F': ' '/Maximum resident set size/ { rss = $2 } END { print rss + 0 }' "$LOG_FILE")"
    PC="$(sed -n 's/.* PC=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    HALTED="$(sed -n 's/.* halted=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    STOPPED="$(sed -n 's/.* stopped=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    IE="$(sed -n 's/IE=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    IF="$(sed -n 's/.* IF=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    IME="$(sed -n 's/.* IME=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    LY="$(sed -n 's/.* LY=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"

    if [[ -z "$PC" || -z "$HALTED" || -z "$STOPPED" || -z "$IE" || -z "$IF" || -z "$IME" || -z "$LY" ]]; then
        echo "FAIL: checkpoint ${CHECKPOINT} did not emit a complete CPU snapshot."
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$REPORTED_CYCLES" -lt "$CHECKPOINT" ]]; then
        echo "FAIL: checkpoint ${CHECKPOINT} exited before the requested cycle budget."
        echo "Requested cycles: $CHECKPOINT"
        echo "Reported cycles:  $REPORTED_CYCLES"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$RSS_KB" -gt "$MAX_RSS_KB" ]]; then
        echo "FAIL: checkpoint ${CHECKPOINT} exceeded RSS guard."
        echo "Max RSS:       ${RSS_KB} KB"
        echo "Allowed RSS:   ${MAX_RSS_KB} KB"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    if [[ "$STOPPED" -ne 0 ]]; then
        echo "FAIL: checkpoint ${CHECKPOINT} ended in STOP state."
        echo "halted=$HALTED stopped=$STOPPED"
        tail -n 100 "$LOG_FILE"
        exit 1
    fi

    STATE="${PC}:${LY}:${IE}:${IF}:${IME}:${HALTED}:${STOPPED}"
    if [[ "$UNIQUE_STATES" != *"|$STATE|"* ]]; then
        UNIQUE_STATES="${UNIQUE_STATES}|${STATE}|"
        SNAPSHOT_COUNT=$((SNAPSHOT_COUNT + 1))
    fi

    if [[ "$RSS_KB" -gt "$MAX_SEEN_RSS_KB" ]]; then
        MAX_SEEN_RSS_KB="$RSS_KB"
    fi
    if [[ "$FIRST_RSS_KB" -eq 0 ]]; then
        FIRST_RSS_KB="$RSS_KB"
    fi
    LAST_RSS_KB="$RSS_KB"
    LAST_REPORTED_CYCLES="$REPORTED_CYCLES"

    printf 'ok: checkpoint=%s cycles=%s pc=%s ly=%s ie=%s if=%s ime=%s halted=%s rss_kb=%s\n' \
        "$CHECKPOINT" "$REPORTED_CYCLES" "$PC" "$LY" "$IE" "$IF" "$IME" "$HALTED" "$RSS_KB"

    PREV_CHECKPOINT="$CHECKPOINT"
done

if [[ "${#CHECKPOINT_ARRAY[@]}" -gt 1 && "$SNAPSHOT_COUNT" -lt 2 ]]; then
    echo "FAIL: Pokemon Red checkpoints produced the same final CPU/LCD snapshot."
    echo "This suggests the emulator is not making visible progress as cycle budgets increase."
    exit 1
fi

echo "PASS: Pokemon Red smoke test"
echo "ROM:          $ROM_PATH"
echo "Checkpoints:  ${CHECKPOINT_ARRAY[*]}"
echo "Final cycles: $LAST_REPORTED_CYCLES"
echo "First RSS:    ${FIRST_RSS_KB} KB"
echo "Last RSS:     ${LAST_RSS_KB} KB"
echo "Peak RSS:     ${MAX_SEEN_RSS_KB} KB"

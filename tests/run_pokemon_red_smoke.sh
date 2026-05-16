#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROM_PATH="${POKEMON_RED_ROM:-$ROOT_DIR/roms/pokemon-red.gb}"
CHECKPOINTS="${POKEMON_RED_CHECKPOINTS:-${POKEMON_RED_CYCLES:-1000000 3000000 5000000 10000000 25000000}}"
TIMEOUT_SECONDS="${POKEMON_RED_TIMEOUT_SECONDS:-240}"
MAX_RSS_KB="${POKEMON_RED_MAX_RSS_KB:-65536}"
RENDER_PROBE="${POKEMON_RED_RENDER_PROBE:-1}"
MIN_RENDER_NONZERO="${POKEMON_RED_MIN_RENDER_NONZERO:-1}"
MIN_RENDER_UNIQUE="${POKEMON_RED_MIN_RENDER_UNIQUE:-2}"
DEFAULT_INPUT_SCRIPT="9000000:start:5000000,16000000:a:3000000,20500000:a:3000000"

DEFAULT_INPUT_MODE=0
if [[ -n "${POKEMON_RED_INPUT_SCRIPT+x}" ]]; then
    INPUT_SCRIPT="$POKEMON_RED_INPUT_SCRIPT"
elif [[ -n "${POKEMON_RED_CYCLES:-}" ]]; then
    INPUT_SCRIPT=""
else
    INPUT_SCRIPT="$DEFAULT_INPUT_SCRIPT"
    DEFAULT_INPUT_MODE=1
fi

if [[ -n "${POKEMON_RED_MIN_INPUT_EVENTS+x}" ]]; then
    MIN_INPUT_EVENTS="$POKEMON_RED_MIN_INPUT_EVENTS"
elif [[ "$DEFAULT_INPUT_MODE" -eq 1 ]]; then
    MIN_INPUT_EVENTS=6
else
    MIN_INPUT_EVENTS=0
fi

if [[ ! -f "$ROM_PATH" ]]; then
    echo "SKIP: Pokemon Red ROM not found."
    echo "Set POKEMON_RED_ROM=/path/to/pokemon-red.gb or place an untracked ROM at roms/pokemon-red.gb."
    exit 0
fi

if [[ "$RENDER_PROBE" != "0" && "$RENDER_PROBE" != "1" ]]; then
    echo "ERROR: POKEMON_RED_RENDER_PROBE must be 0 or 1."
    exit 1
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
RENDER_SNAPSHOT_COUNT=0
UNIQUE_RENDER_HASHES=""
MAX_SEEN_RSS_KB=0
FIRST_RSS_KB=0
LAST_RSS_KB=0
LAST_REPORTED_CYCLES=0
LAST_INPUT_APPLIED=0
LAST_INPUT_TOTAL=0
LAST_RENDER_NONZERO=0
LAST_RENDER_UNIQUE=0
LAST_RENDER_HASH=0
MAX_RENDER_NONZERO=0
MAX_RENDER_UNIQUE=0

echo "Pokemon Red smoke checkpoints: ${CHECKPOINT_ARRAY[*]}"
if [[ -n "$INPUT_SCRIPT" ]]; then
    echo "Pokemon Red input script: $INPUT_SCRIPT"
fi
if [[ "$RENDER_PROBE" -eq 1 ]]; then
    echo "Pokemon Red render probe: enabled"
fi

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
    CMD=(
        timeout "${TIMEOUT_SECONDS}s"
        /usr/bin/time -v
        "$EIGENSCRIPT_BIN" "$ROOT_DIR/dmg.eigs" "$ROM_PATH" --cycles "$CHECKPOINT"
    )
    if [[ -n "$INPUT_SCRIPT" ]]; then
        CMD+=(--input-script "$INPUT_SCRIPT")
    fi
    if [[ "$RENDER_PROBE" -eq 1 ]]; then
        CMD+=(--render-probe)
    fi

    set +e
    "${CMD[@]}" >"$LOG_FILE" 2>&1
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
    INPUT_APPLIED="$(sed -n 's/Input events applied: \([0-9][0-9]*\)\/[0-9][0-9]*/\1/p' "$LOG_FILE" | tail -n 1)"
    INPUT_TOTAL="$(sed -n 's/Input events applied: [0-9][0-9]*\/\([0-9][0-9]*\)/\1/p' "$LOG_FILE" | tail -n 1)"
    RENDER_NONZERO="$(sed -n 's/Render probe: nonzero=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    RENDER_UNIQUE="$(sed -n 's/Render probe: .* unique=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
    RENDER_HASH="$(sed -n 's/Render probe: .* hash=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"

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

    if [[ -n "$INPUT_SCRIPT" ]]; then
        if [[ -z "$INPUT_APPLIED" || -z "$INPUT_TOTAL" ]]; then
            echo "FAIL: checkpoint ${CHECKPOINT} did not report input event application."
            tail -n 100 "$LOG_FILE"
            exit 1
        fi
        LAST_INPUT_APPLIED="$INPUT_APPLIED"
        LAST_INPUT_TOTAL="$INPUT_TOTAL"
    fi

    RENDER_FIELDS=""
    if [[ "$RENDER_PROBE" -eq 1 ]]; then
        if [[ -z "$RENDER_NONZERO" || -z "$RENDER_UNIQUE" || -z "$RENDER_HASH" ]]; then
            echo "FAIL: checkpoint ${CHECKPOINT} did not emit render probe stats."
            tail -n 100 "$LOG_FILE"
            exit 1
        fi
        RENDER_STATE="${RENDER_HASH}:${RENDER_NONZERO}:${RENDER_UNIQUE}"
        if [[ "$UNIQUE_RENDER_HASHES" != *"|$RENDER_STATE|"* ]]; then
            UNIQUE_RENDER_HASHES="${UNIQUE_RENDER_HASHES}|${RENDER_STATE}|"
            RENDER_SNAPSHOT_COUNT=$((RENDER_SNAPSHOT_COUNT + 1))
        fi
        LAST_RENDER_NONZERO="$RENDER_NONZERO"
        LAST_RENDER_UNIQUE="$RENDER_UNIQUE"
        LAST_RENDER_HASH="$RENDER_HASH"
        if [[ "$RENDER_NONZERO" -gt "$MAX_RENDER_NONZERO" ]]; then
            MAX_RENDER_NONZERO="$RENDER_NONZERO"
        fi
        if [[ "$RENDER_UNIQUE" -gt "$MAX_RENDER_UNIQUE" ]]; then
            MAX_RENDER_UNIQUE="$RENDER_UNIQUE"
        fi
        RENDER_FIELDS=" render_nonzero=${RENDER_NONZERO} render_unique=${RENDER_UNIQUE} render_hash=${RENDER_HASH}"
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

    if [[ -n "$INPUT_SCRIPT" ]]; then
        printf 'ok: checkpoint=%s cycles=%s pc=%s ly=%s ie=%s if=%s ime=%s halted=%s input=%s/%s rss_kb=%s%s\n' \
            "$CHECKPOINT" "$REPORTED_CYCLES" "$PC" "$LY" "$IE" "$IF" "$IME" "$HALTED" "$INPUT_APPLIED" "$INPUT_TOTAL" "$RSS_KB" "$RENDER_FIELDS"
    else
        printf 'ok: checkpoint=%s cycles=%s pc=%s ly=%s ie=%s if=%s ime=%s halted=%s rss_kb=%s%s\n' \
            "$CHECKPOINT" "$REPORTED_CYCLES" "$PC" "$LY" "$IE" "$IF" "$IME" "$HALTED" "$RSS_KB" "$RENDER_FIELDS"
    fi

    PREV_CHECKPOINT="$CHECKPOINT"
done

if [[ "${#CHECKPOINT_ARRAY[@]}" -gt 1 && "$SNAPSHOT_COUNT" -lt 2 ]]; then
    echo "FAIL: Pokemon Red checkpoints produced the same final CPU/LCD snapshot."
    echo "This suggests the emulator is not making visible progress as cycle budgets increase."
    exit 1
fi

if [[ "$RENDER_PROBE" -eq 1 && "${#CHECKPOINT_ARRAY[@]}" -gt 1 ]]; then
    if [[ "$MAX_RENDER_NONZERO" -lt "$MIN_RENDER_NONZERO" ]]; then
        echo "FAIL: Pokemon Red render probes never produced visible pixels."
        echo "Max nonzero pixels: $MAX_RENDER_NONZERO"
        echo "Required minimum:   $MIN_RENDER_NONZERO"
        exit 1
    fi
    if [[ "$MAX_RENDER_UNIQUE" -lt "$MIN_RENDER_UNIQUE" ]]; then
        echo "FAIL: Pokemon Red render probes never used enough shades."
        echo "Max unique shades:  $MAX_RENDER_UNIQUE"
        echo "Required minimum:   $MIN_RENDER_UNIQUE"
        exit 1
    fi
    if [[ "$RENDER_SNAPSHOT_COUNT" -lt 2 ]]; then
        echo "FAIL: Pokemon Red render probes produced the same framebuffer snapshot."
        echo "This suggests the PPU output is not changing as cycle budgets increase."
        exit 1
    fi
fi

if [[ "$MIN_INPUT_EVENTS" -gt 0 && "$LAST_INPUT_APPLIED" -lt "$MIN_INPUT_EVENTS" ]]; then
    echo "FAIL: Pokemon Red input script did not apply enough events."
    echo "Applied input events: $LAST_INPUT_APPLIED"
    echo "Required minimum:     $MIN_INPUT_EVENTS"
    exit 1
fi

echo "PASS: Pokemon Red smoke test"
echo "ROM:          $ROM_PATH"
echo "Checkpoints:  ${CHECKPOINT_ARRAY[*]}"
if [[ -n "$INPUT_SCRIPT" ]]; then
    echo "Input events: $LAST_INPUT_APPLIED/$LAST_INPUT_TOTAL"
fi
if [[ "$RENDER_PROBE" -eq 1 ]]; then
    echo "Render hash:  $LAST_RENDER_HASH"
    echo "Render pixels: nonzero=$LAST_RENDER_NONZERO unique=$LAST_RENDER_UNIQUE"
    echo "Render peak:   nonzero=$MAX_RENDER_NONZERO unique=$MAX_RENDER_UNIQUE"
fi
echo "Final cycles: $LAST_REPORTED_CYCLES"
echo "First RSS:    ${FIRST_RSS_KB} KB"
echo "Last RSS:     ${LAST_RSS_KB} KB"
echo "Peak RSS:     ${MAX_SEEN_RSS_KB} KB"

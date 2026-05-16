#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROM_PATH="${DMG_GFX_ROM:-$ROOT_DIR/roms/instr_timing.gb}"
FRAMES="${DMG_GFX_FRAMES:-2}"
FRAMESKIP="${DMG_GFX_FRAMESKIP:-1}"
SCALE="${DMG_GFX_SCALE:-1}"
TIMEOUT_SECONDS="${DMG_GFX_TIMEOUT_SECONDS:-60}"
GFX_REQUIRED="${DMG_GFX_REQUIRED:-0}"

if [[ ! -f "$ROM_PATH" ]]; then
    echo "SKIP: gfx smoke ROM not found: $ROM_PATH"
    exit 0
fi

if ! [[ "$FRAMES" =~ ^[0-9]+$ && "$FRAMES" -gt 0 ]]; then
    echo "ERROR: DMG_GFX_FRAMES must be a positive integer."
    exit 1
fi

if ! [[ "$FRAMESKIP" =~ ^[0-9]+$ && "$FRAMESKIP" -gt 0 ]]; then
    echo "ERROR: DMG_GFX_FRAMESKIP must be a positive integer."
    exit 1
fi

if ! [[ "$SCALE" =~ ^[0-9]+$ && "$SCALE" -gt 0 ]]; then
    echo "ERROR: DMG_GFX_SCALE must be a positive integer."
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout command not found; refusing to run an uncapped gfx smoke test."
    exit 1
fi

if [[ -n "${EIGENSCRIPT_GFX:-}" ]]; then
    EIGENSCRIPT_BIN="$EIGENSCRIPT_GFX"
    GFX_REQUIRED=1
elif [[ -n "${EIGENSCRIPT:-}" ]]; then
    EIGENSCRIPT_BIN="$EIGENSCRIPT"
elif [[ -x "$ROOT_DIR/../EigenScript/src/eigenscript" ]]; then
    EIGENSCRIPT_BIN="$ROOT_DIR/../EigenScript/src/eigenscript"
elif command -v eigenscript >/dev/null 2>&1; then
    EIGENSCRIPT_BIN="$(command -v eigenscript)"
else
    echo "ERROR: eigenscript binary not found."
    echo "Set EIGENSCRIPT_GFX=/path/to/gfx-built/eigenscript."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
LOG_FILE="$TMP_DIR/dmg-gfx-smoke.log"

if [[ -z "${SDL_VIDEODRIVER:-}" ]]; then
    export SDL_VIDEODRIVER=dummy
fi

CMD=(
    timeout "${TIMEOUT_SECONDS}s"
    "$EIGENSCRIPT_BIN" "$ROOT_DIR/dmg.eigs" "$ROM_PATH"
    --gfx --gfx-frames "$FRAMES" --frameskip "$FRAMESKIP" --scale "$SCALE"
)

echo "DMG gfx smoke: rom=$ROM_PATH frames=$FRAMES frameskip=$FRAMESKIP scale=$SCALE sdl=${SDL_VIDEODRIVER:-default}"

set +e
"${CMD[@]}" >"$LOG_FILE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 124 ]]; then
    echo "FAIL: gfx smoke timed out after ${TIMEOUT_SECONDS}s."
    tail -n 100 "$LOG_FILE"
    exit 1
fi

if grep -q "undefined variable 'gfx_open'\|undefined variable 'ppu_render_frame'\|gfx_open:" "$LOG_FILE"; then
    if [[ "$GFX_REQUIRED" -eq 0 ]]; then
        echo "SKIP: EigenScript gfx/SDL support is not available."
        echo "Build EigenScript with 'make gfx' or set EIGENSCRIPT_GFX=/path/to/gfx-built/eigenscript."
        exit 0
    fi
    echo "FAIL: gfx smoke requires a working gfx-built EigenScript binary."
    tail -n 100 "$LOG_FILE"
    exit 1
fi

if [[ "$STATUS" -ne 0 ]]; then
    echo "FAIL: gfx smoke exited with status $STATUS."
    tail -n 100 "$LOG_FILE"
    exit "$STATUS"
fi

if grep -q "^Error line " "$LOG_FILE"; then
    echo "FAIL: gfx smoke emitted EigenScript runtime errors."
    tail -n 100 "$LOG_FILE"
    exit 1
fi

REPORTED_FRAMES="$(sed -n 's/.* frames=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"
REPORTED_CYCLES="$(sed -n 's/.*Loop exited: cycles=\([0-9][0-9]*\).*/\1/p' "$LOG_FILE" | tail -n 1)"

if [[ -z "$REPORTED_FRAMES" || -z "$REPORTED_CYCLES" ]]; then
    echo "FAIL: gfx smoke did not emit loop completion metrics."
    tail -n 100 "$LOG_FILE"
    exit 1
fi

if [[ "$REPORTED_FRAMES" -lt "$FRAMES" ]]; then
    echo "FAIL: gfx smoke exited before requested frame budget."
    echo "Requested frames: $FRAMES"
    echo "Reported frames:  $REPORTED_FRAMES"
    tail -n 100 "$LOG_FILE"
    exit 1
fi

if [[ "$REPORTED_CYCLES" -le 0 ]]; then
    echo "FAIL: gfx smoke did not advance CPU cycles."
    tail -n 100 "$LOG_FILE"
    exit 1
fi

echo "PASS: DMG gfx smoke"
echo "Frames: $REPORTED_FRAMES"
echo "Cycles: $REPORTED_CYCLES"

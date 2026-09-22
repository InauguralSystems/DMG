#!/usr/bin/env bash
# Debugger-chrome UI oracle wrapper (#53). Validate the selected runtime
# and declared UI prerequisites before opening a window. A missing
# prerequisite is a nonzero exit, never an accepted-but-skipped oracle.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/tests/runtime.sh"
EIGS="$(dmg_runtime "$ROOT_DIR" "${EIGENSCRIPT_GFX:-${EIGENSCRIPT_BIN:-}}")"

ulimit -v "${DMG_DEBUG_UI_MEM_KB:-1500000}"

if ! command -v timeout >/dev/null 2>&1; then
    echo "PREREQ MISSING: timeout"
    exit 1
fi
# --api advertises extension names even in a headless build. Bind the
# actual builtin, without opening a window, to establish gfx support.
if ! timeout 10 "$EIGS" tests/probe_gfx.eigs >/dev/null 2>&1; then
    echo "PREREQ MISSING: gfx build (requires gfx_open; set EIGENSCRIPT_GFX)"
    exit 1
fi

if ! timeout 10 "$EIGS" tests/probe_debug_ui.eigs >/dev/null 2>&1; then
    echo "PREREQ MISSING: dock widget in the selected runtime's lib"
    exit 1
fi

for tool in xdotool xwd xwininfo python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "PREREQ MISSING: $tool"
        exit 1
    fi
done
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "PREREQ MISSING: python3-pil"
    exit 1
fi

# The chrome needs a real (or virtual) X display and an SDL video driver
# that can open a window there — the dummy driver has no pixels to read.
RUNNER=()
if [[ -z "${DISPLAY:-}" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
        echo "PREREQ MISSING: X display (set DISPLAY or install xvfb-run)"
        exit 1
    fi
    RUNNER=(xvfb-run -a -s "-screen 0 1280x800x24")
fi

# Check the display inside the same Xvfb session used by the oracle.
# A nonempty DISPLAY alone does not prove that an X server is reachable.
EIGENSCRIPT="$EIGS" "${RUNNER[@]}" "$BASH" -c '
    if ! timeout 10 xwininfo -root >/dev/null 2>&1; then
        echo "PREREQ MISSING: usable X display"
        exit 1
    fi
    exec python3 tests/ui_debug_oracle.py
'

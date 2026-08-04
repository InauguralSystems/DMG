#!/usr/bin/env bash
# Debugger-chrome UI oracle wrapper (#53): probes for the dock widget
# (dev-binary only until the post-v0.37.0 cut reaches the pin — the
# liferaft probe_timeline pattern), then runs tests/ui_debug_oracle.py
# under a memory cap (an unbounded gfx run can freeze a small box).
#
# Self-arming skip policy: while the pinned lib predates dock the probe
# SKIPs (exit 0, loud). Once the probe PASSES, everything downstream —
# X tooling, display, the oracle itself — is REQUIRED and fails loud,
# so the oracle can never be silently dropped after the pin bump.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "${EIGENSCRIPT_GFX:-}" ]]; then
    EIGS="$EIGENSCRIPT_GFX"
elif [[ -x "$ROOT_DIR/../EigenScript/src/eigenscript" ]]; then
    EIGS="$ROOT_DIR/../EigenScript/src/eigenscript"
elif command -v eigenscript >/dev/null 2>&1; then
    EIGS="$(command -v eigenscript)"
else
    echo "SKIP: eigenscript binary not found (set EIGENSCRIPT_GFX)"
    exit 0
fi

if ! "$EIGS" tests/probe_debug_ui.eigs >/dev/null 2>&1; then
    echo "SKIP: dock widget not in this runtime's lib (dev binary only until the next release cut)"
    exit 0
fi

for tool in xdotool xwd xwininfo python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: probe passed but $tool is not installed — the UI oracle must run."
        exit 1
    fi
done
if ! python3 -c "import PIL" 2>/dev/null; then
    echo "FAIL: probe passed but python3-pil is not installed — the UI oracle must run."
    exit 1
fi

# The chrome needs a real (or virtual) X display and an SDL video driver
# that can open a window there — the dummy driver has no pixels to read.
RUNNER=()
if [[ -z "${DISPLAY:-}" ]]; then
    if ! command -v xvfb-run >/dev/null 2>&1; then
        echo "FAIL: probe passed but there is no DISPLAY and no xvfb-run."
        exit 1
    fi
    RUNNER=(xvfb-run -a -s "-screen 0 1280x800x24")
fi

ulimit -v "${DMG_DEBUG_UI_MEM_KB:-1500000}"

EIGENSCRIPT="$EIGS" "${RUNNER[@]}" python3 tests/ui_debug_oracle.py

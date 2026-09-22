#!/usr/bin/env bash
# Shared selection for the debugger wrappers. An explicit but invalid choice
# is an error: falling back would test a runtime the caller did not choose.
dmg_runtime() {
    local root="$1" candidate="${2:-${EIGENSCRIPT:-${EIGS:-}}}"
    if [[ -z "$candidate" ]]; then
        if [[ -n "${EIGS_DIR:-}" ]]; then
            candidate="$EIGS_DIR/src/eigenscript"
        elif command -v eigenscript >/dev/null 2>&1; then
            candidate="$(command -v eigenscript)"
        else
            candidate="$root/../EigenScript/src/eigenscript"
        fi
    fi
    if ! command -v "$candidate" >/dev/null 2>&1; then
        printf 'PREREQ MISSING: eigenscript binary (%s)\n' "$candidate" >&2
        return 1
    fi
    printf '%s\n' "$candidate"
}

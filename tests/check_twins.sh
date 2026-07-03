#!/usr/bin/env bash
# Twin gate (#20): the timer/LCD "bus tick", halted-skip, and inlined-exec
# bodies are hand-synchronized copies, kept inline for hot-loop perf (the
# loop-body bytecode footprint is why they aren't one function — see the
# lcd_line_advance comment in dmg.eigs). This gate fails CI when the copies
# drift, which has happened twice before (#27, #28).
#
# Marker syntax (comment lines around each copy):
#   # twin: <name> copy=<label> [map local=canonical local=canonical ...]
#   ...region...
#   # twin: <name> end
#
# Normalization before comparing: comment-only and blank lines dropped, the
# first line's indentation stripped from every line (relative indent kept),
# and each declared `map` rename applied (word-boundary, local -> canonical).
set -euo pipefail
cd "$(dirname "$0")/.."

FILES="dmg.eigs src/opcodes.eigs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ---- extract regions ----
current=""
outfile=""
for f in $FILES; do
    while IFS= read -r line; do
        stripped="${line#"${line%%[![:space:]]*}"}"
        case "$stripped" in
            "# twin: "*" end")
                current=""
                continue
                ;;
            "# twin: "*" copy="*)
                rest="${stripped#\# twin: }"
                name="${rest%% *}"
                rest="${rest#* }"
                label="${rest#copy=}"
                label="${label%% *}"
                maps=""
                case "$rest" in *" map "*) maps="${rest#* map }" ;; esac
                current="$name"
                outfile="$tmp/$name.$label"
                if [ -e "$outfile" ]; then
                    echo "FAIL: duplicate twin label '$label' for region '$name' ($f)"
                    exit 1
                fi
                : > "$outfile"
                printf '%s\n' "$maps" > "$outfile.map"
                printf '%s\n' "$f" > "$outfile.src"
                echo "$name" >> "$tmp/names"
                continue
                ;;
        esac
        if [ -n "$current" ]; then
            # drop comment-only and blank lines
            case "$stripped" in ""|"#"*) continue ;; esac
            printf '%s\n' "$line" >> "$outfile"
        fi
    done < "$f"
done

if [ -n "$current" ]; then
    echo "FAIL: unterminated twin region '$current'"
    exit 1
fi

# ---- normalize one extracted copy to stdout ----
normalize() {
    local file=$1
    local indent n maps pair
    indent=$(head -1 "$file" | sed 's/[^ ].*//')
    n=${#indent}
    sed "s/^ \{$n\}//" "$file" > "$file.norm"
    maps=$(cat "$file.map")
    for pair in $maps; do
        sed -Ei "s/\b${pair%%=*}\b/${pair#*=}/g" "$file.norm"
    done
    cat "$file.norm"
}

# ---- compare all copies of each region against the first ----
fail=0
for name in $(sort -u "$tmp/names"); do
    set -- "$tmp/$name".*
    copies=$(ls "$tmp/$name".* | grep -v '\.\(map\|src\|norm\)$')
    count=$(echo "$copies" | wc -l)
    if [ "$count" -lt 2 ]; then
        echo "FAIL: twin region '$name' has only $count copy — marker lost?"
        fail=1
        continue
    fi
    ref=""
    reflabel=""
    for c in $copies; do
        label="${c##*/$name.}"
        normalize "$c" > "$c.canon"
        if [ -z "$ref" ]; then
            ref="$c.canon"
            reflabel="$label"
            continue
        fi
        if ! diff -u "$ref" "$c.canon" > "$tmp/diffout" 2>&1; then
            echo "FAIL: twin region '$name' drifted: copy '$label' ($(cat "$c.src")) != copy '$reflabel'"
            sed 's/^/    /' "$tmp/diffout"
            fail=1
        fi
    done
    [ "$fail" -eq 0 ] && echo "ok: twin '$name' — $count copies in sync"
done

if [ "$fail" -ne 0 ]; then
    echo "FAIL: twin gate — sync the copies (or fix the map= renames)"
    exit 1
fi
echo "PASS: twin gate"

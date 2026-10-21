#!/bin/bash
# Fresh scratch DB through the canonical order of tests/sql/final_build.sh (72..97, then 98) and, unless PHASE99=0, phase99 LAST.
# usage: bash tests/sql/opt_build.sh <dbname>       (Postgres on socket /tmp port 5544)   PHASE99=0 builds the same without phase99 (for A/B comparisons)
HERE="$(cd "$(dirname "$0")" && pwd)"
ORD=$(grep -o 'ORDER=${2:-"[^"]*"}' "$HERE/final_build.sh" | sed 's/^ORDER=${2:-"//; s/"}$//')
[ "${PHASE99:-1}" = "1" ] && ORD="$ORD phase99"
bash "$HERE/final_build.sh" "$1" "$ORD"

#!/bin/bash
# Fresh scratch DB: canonical order (final_build.sh) + phase99 + phase101 + phase102 (Img). usage: bash tests/sql/img_build.sh <dbname>
HERE="$(cd "$(dirname "$0")" && pwd)"
ORD=$(grep -o 'ORDER=${2:-"[^"]*"}' "$HERE/final_build.sh" | sed 's/^ORDER=${2:-"//; s/"}$//')
bash "$HERE/final_build.sh" "$1" "$ORD phase99 phase101 phase102"

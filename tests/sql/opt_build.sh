#!/bin/bash
# Fresh scratch DB through the canonical order of tests/sql/final_build.sh PLUS phase96, phase97 (they are in supabase/ but not in that script's default ORDER) and, unless PHASE99=0, phase99.
# usage: bash tests/sql/opt_build.sh <dbname>       (Postgres on socket /tmp port 5544)
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71 phase72 phase73 phase74 phase75 phase76 phase77 phase78 phase79 phase80 phase81 phase82 phase83 phase84 phase85 phase86 phase87 phase88 phase90 phase91 phase89 phase92 phase93 phase95 phase94 phase96 phase97"
[ "${PHASE98:-0}" = "1" ] && BASE="$BASE phase98"
[ "${PHASE99:-1}" = "1" ] && BASE="$BASE phase99"
bash "$HERE/final_build.sh" "$1" "$BASE"

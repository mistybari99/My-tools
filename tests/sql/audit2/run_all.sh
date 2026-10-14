#!/bin/bash
# Audit 2 verification harness.  usage: bash tests/sql/audit2/run_all.sh [--matrix] [--no-build] [--out FILE]
#   builds a fresh scratch DB b5run (tests/sql/final_build.sh), runs the five suites a1..a5, parses PASS/FAIL, maps them to gap ids
#   (gap_map.tsv) and writes docs/audit2/VERIFY_STATUS.md.   --matrix = second pass with the switches of switches_on.txt ON.
# Needs the scratch PG16 on /tmp:5544.  Restart: su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"
# Env: DB (default b5run), REPO.  Only the databases b5run, b5run_on, b5_a2/b5_a3/b5_a5 (+ _on) and the fixed names the a1/a4 runners use (a1s, a4run) are touched.
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../../.." && pwd)}; DB=${DB:-b5run}
MATRIX=0; BUILD=1; OUT="$REPO/docs/audit2/VERIFY_STATUS.md"
while [ $# -gt 0 ]; do case $1 in --matrix) MATRIX=1;; --no-build) BUILD=0;; --out) OUT=$2; shift;; *) echo "unknown arg $1"; exit 2;; esac; shift; done
P="psql -h /tmp -p 5544 -U postgres"; W=$(mktemp -d /tmp/b5verify.XXXXXX)
$P -Atc "select 1" >/dev/null 2>&1 || { su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start" >/dev/null 2>&1; sleep 3; }
$P -Atc "select 1" >/dev/null 2>&1 || { echo "no Postgres on /tmp:5544"; exit 1; }
# phases that exist on disk but are not in the canonical order are NOT built: say so
MISS=""; for f in "$REPO"/supabase/phase11[2-9].sql "$REPO"/supabase/phase12[0-9].sql; do [ -f "$f" ] || continue; b=$(basename "$f" .sql); grep -qw "$b" "$REPO/tests/sql/paste_order.env" || MISS="$MISS $b"; done
[ -n "$MISS" ] && echo "WARNING: phase files not in tests/sql/paste_order.env (not built):$MISS"
if [ $BUILD = 1 ]; then bash "$REPO/tests/sql/final_build.sh" $DB 2>&1 | grep -E "^(FAIL|built)|ERROR" ; fi
$P -Atc "select 1 from pg_database where datname='$DB'" | grep -q 1 || { echo "DB $DB missing"; exit 1; }

# ---- new rules (not in rules_baseline.txt) and the switches pass database
NEW=$($P -d $DB -Atc "select key||'|'||kind||'|'||coalesce(default_value::text,'null') from rules order by key" | awk -F'|' 'NR==FNR{b[$1]=1;next} !($1 in b){print}' "$HERE/rules_baseline.txt" -)
echo "$NEW" | sed '/^$/d' > $W/new_rules.txt
NOTES=$W/notes.txt; : > $NOTES; ON_DB=${DB}_on; ONLIST=$W/on.txt; : > $ONLIST
if [ $MATRIX = 1 ]; then
  AUTO=on; grep -qE '^@auto_new_switches +off' "$HERE/switches_on.txt" && AUTO=off
  $P -qc "drop database if exists $ON_DB" -c "create database $ON_DB template $DB" 2>&1 | grep -v NOTICE
  # explicit list: "key = json  # comment"
  grep -vE '^\s*(#|@|!|$)' "$HERE/switches_on.txt" | sed -E 's/\s+#.*$//' | while IFS= read -r l; do
    k=$(echo "$l" | sed -E 's/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$/\1/'); v=$(echo "$l" | sed -E 's/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$/\2/')
    echo "$k|$v" >> $ONLIST; done
  if [ $AUTO = on ]; then while IFS='|' read -r k kind d; do [ "$kind" = switch ] && ! grep -qE "^!$k\s*$" "$HERE/switches_on.txt" && ! grep -q "^$k|" $ONLIST && echo "$k|true" >> $ONLIST; done < $W/new_rules.txt; fi
  while IFS='|' read -r k v; do
    [ -z "$k" ] && continue
    ex=$($P -d $ON_DB -Atc "select kind from rules where key='$k'")
    if [ -z "$ex" ]; then echo "rule $k not present yet (skipped)" >> $NOTES; continue; fi
    $P -d $ON_DB -qAt -v ON_ERROR_STOP=1 -c "update rules set default_value='$v'::jsonb where key='$k'" >/dev/null 2>$W/err || { echo "rule $k: bad value $v" >> $NOTES; continue; }
    echo "$k|$ex|$v" >> $W/applied.txt
  done < $ONLIST
fi

run_pass() {  # $1 = template DB, $2 = suffix, $3 = out dir
  local T=$1 S=$2 D=$3; mkdir -p $D
  bash "$HERE/a1/run.sh" $T > $D/a1.txt 2>&1
  TEMPLATE=$T bash "$HERE/a2/run_a2.sh" b5_a2$S > $D/a2.txt 2>&1
  $P -qc "drop database if exists b5_a3$S" -c "create database b5_a3$S template $T" >/dev/null 2>&1; bash "$HERE/a3/run.sh" b5_a3$S > $D/a3.txt 2>&1
  bash "$HERE/a4/run_a4.sh" $T > $D/a4.txt 2>&1
  $P -qc "drop database if exists b5_a5$S" -c "create database b5_a5$S template $T" >/dev/null 2>&1; bash "$HERE/a5/run.sh" b5_a5$S > $D/a5.txt 2>&1
  for n in 1 2 3 4 5; do echo "a$n: $(grep -cE '(^|NOTICE: +)PASS ' $D/a$n.txt) pass, $(grep -cE '(^|NOTICE: +)FAIL ' $D/a$n.txt) fail"; done
}
echo "== pass 1: defaults"; run_pass $DB "" $W/def
ARGS=("defaults=$W/def")
if [ $MATRIX = 1 ]; then echo "== pass 2: switches ON ($(wc -l < $W/applied.txt 2>/dev/null || echo 0) rules)"; run_pass $ON_DB _on $W/on; ARGS+=("switches ON=$W/on"); fi

python3 - "$W" "$REPO" "$MISS" <<'PY'
import json, sys, os
W, repo, miss = sys.argv[1:4]
def rd(p): return [l.rstrip("\n") for l in open(p)] if os.path.exists(p) else []
applied = {l.split("|")[0]: l.split("|")[2] for l in rd(W + "/applied.txt")}
new = []
for l in rd(W + "/new_rules.txt"):
    k, kind, d = l.split("|"); new.append({"key": k, "kind": kind, "default": d, "on": applied.get(k, "-")})
import subprocess
c = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"commit": c, "new_rules": new, "switch_notes": rd(W + "/notes.txt"), "missing_phases": miss.split()}, open(W + "/info.json", "w"))
PY
python3 -I "$HERE/verify_report.py" "$OUT" "$HERE/gap_map.tsv" $W/info.json "${ARGS[@]}"
echo "raw outputs: $W"

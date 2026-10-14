#!/usr/bin/env python3
"""Check docs/PASTE_ORDER.md against the supabase/phase72..phase103 files on disk.

Reports:
  1. every supabase/phase72..phase103.sql present, with byte size and sha256
  2. phases that exist as files but have no row in the doc table (section B)
  3. doc rows whose phase file does not exist
  4. wrong order: the order run_all_sql.sh would paste (rows with a numeric
     first column, then any leftover phase1NN files appended numerically) vs
     the canonical order (final_build.sh default ORDER for 72..98, then 99..103)
  5. un-numbered rows (first column not a plain number, e.g. '(31)')

Usage: python3 tools/check_paste_order.py          (exit 0 = clean, 1 = problems)
"""
import hashlib
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOC = os.path.join(REPO, "docs", "PASTE_ORDER.md")
FINAL_BUILD = os.path.join(REPO, "tests", "sql", "final_build.sh")
SUPA = os.path.join(REPO, "supabase")
RANGE = list(range(72, 104)) + [106, 107, 109]
TAIL_AFTER_FINAL_BUILD = [99, 100, 101, 102, 103, 106, 107, 109]


def canonical_order():
    """final_build.sh default ORDER (phase72..98) followed by phase99..103."""
    text = open(FINAL_BUILD, encoding="utf-8").read()
    m = re.search(r'ORDER=\$\{2:-"([^"]+)"\}', text)
    if not m:
        sys.exit("cannot find default ORDER in final_build.sh")
    nums = [int(x) for x in re.findall(r"phase(\d+)", m.group(1))]
    head = [n for n in nums if 72 <= n <= 98]
    return head + TAIL_AFTER_FINAL_BUILD


def parse_doc():
    """Table rows of section B: '| <num-col> | <file cell> | ...'."""
    rows = []
    for lineno, line in enumerate(open(DOC, encoding="utf-8"), 1):
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        m = re.search(r"(phase\d+)\.sql", cells[1])
        if not m:
            continue  # header / separator / non-phase rows
        num_cell = cells[0]
        num = int(num_cell) if re.fullmatch(r"\d+", num_cell) else None
        rows.append({
            "line": lineno,
            "num_cell": num_cell,
            "num": num,
            "phase": int(m.group(1)[5:]),
        })
    return rows


def as_run_order(rows):
    """Replicates run_all_sql.sh: numbered table rows in file order, then
    leftover phase1NN.sql files appended in numeric order."""
    table = [r["phase"] for r in rows if r["num"] is not None]
    extra = []
    for f in os.listdir(SUPA):
        m = re.fullmatch(r"phase(1\d\d)\.sql", f)
        if m and int(m.group(1)) not in table:
            extra.append(int(m.group(1)))
    return table + sorted(extra)


def main():
    canon = canonical_order()
    rows = parse_doc()
    doc_phases = {r["phase"] for r in rows}
    problems = []

    # 1. files on disk
    files = {}
    for n in RANGE:
        path = os.path.join(SUPA, f"phase{n}.sql")
        if os.path.isfile(path):
            data = open(path, "rb").read()
            files[n] = (len(data), hashlib.sha256(data).hexdigest())
        else:
            files[n] = None
            problems.append(f"file missing: supabase/phase{n}.sql")

    print("== 1. supabase files phase72..phase103 ==")
    print(f"{'file':<22}{'bytes':>9}  sha256")
    for n in RANGE:
        if files[n]:
            size, digest = files[n]
            print(f"{'phase' + str(n) + '.sql':<22}{size:>9}  {digest}")
        else:
            print(f"{'phase' + str(n) + '.sql':<22}{'MISSING':>9}")
    print()

    # 2. phases missing from the doc
    missing_from_doc = [n for n in RANGE if files[n] and n not in doc_phases]
    for n in missing_from_doc:
        problems.append(f"phase{n}.sql exists but has no row in docs/PASTE_ORDER.md")

    # 3. rows with no file
    rows_no_file = [r for r in rows if not os.path.isfile(os.path.join(SUPA, f"phase{r['phase']}.sql"))]
    for r in rows_no_file:
        problems.append(f"doc line {r['line']}: phase{r['phase']}.sql has no file")

    # 5. un-numbered rows
    unnumbered = [r for r in rows if r["num"] is None]
    for r in unnumbered:
        problems.append(f"doc line {r['line']}: row number '{r['num_cell']}' is not a plain number (run_all_sql.sh skips it)")

    # 4. wrong order
    run_order = as_run_order(rows)
    expected_set = set(canon)
    for p in canon:
        if p not in run_order:
            problems.append(f"phase{p}.sql is in the canonical order but run_all_sql.sh does not paste it")
    if run_order != canon:
        problems.append("run_all_sql.sh order differs from the canonical order (see summary below)")

    print("== 2-5. doc table vs files and canonical order ==")
    print(f"canonical order (final_build.sh + 99..103): {' '.join(str(p) for p in canon)}")
    print(f"run_all_sql.sh order (as parsed):           {' '.join(str(p) for p in run_order)}")
    print()

    # clean table
    canon_pos = {p: i + 1 for i, p in enumerate(canon)}
    print(f"{'row':>4} {'doc#':>6} {'file':<16}{'exists':<8}{'bytes':>9}  {'sha256':<16}  order")
    for r in rows:
        p = r["phase"]
        exists = os.path.isfile(os.path.join(SUPA, f"phase{p}.sql"))
        size, digest = files.get(p) or (None, None)
        status = []
        if r["num"] is None:
            status.append("UNNUMBERED")
        if p in canon_pos and r["num"] is not None:
            if r["num"] != canon_pos[p]:
                status.append(f"expected #{canon_pos[p]}")
        elif p not in canon_pos:
            status.append("not in canon")
        if not status:
            status.append("ok")
        print(f"{canon_pos.get(p, '-'):>4} {r['num_cell']:>6} {'phase' + str(p) + '.sql':<16}"
              f"{'yes' if exists else 'NO':<8}{(str(size) if size is not None else '-'):>9}  "
              f"{(digest[:16] if digest else '-'):<16}  {', '.join(status)}")
    print()

    # summary
    if run_order != canon:
        first = next((i for i, (g, w) in enumerate(zip(run_order, canon)) if g != w), None)
        if first is not None:
            print(f"wrong order: first difference at position {first + 1}: run_all_sql.sh has phase{run_order[first]}, canonical has phase{canon[first]}")
        misplaced = [p for p in run_order if p in expected_set and run_order.index(p) != canon.index(p)]
        if misplaced:
            print("misplaced phases: " + ", ".join(f"phase{p}" for p in misplaced))
    if missing_from_doc:
        print("phases missing from doc: " + ", ".join(f"phase{n}" for n in missing_from_doc))
    if rows_no_file:
        print("rows with no file: " + ", ".join(f"phase{r['phase']}" for r in rows_no_file))
    if not problems:
        print("OK: no problems found")
        return 0
    print(f"{len(problems)} problem(s):")
    for p in problems:
        print("  - " + p)
    return 1


if __name__ == "__main__":
    sys.exit(main())

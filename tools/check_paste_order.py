#!/usr/bin/env python3
"""Check docs/PASTE_ORDER.md against tests/sql/paste_order.env (the ONE canonical order) and the supabase/phaseNN.sql files on disk.

Reports: byte size + sha256 of every NEW phase file; table rows missing/extra/out of order/un-numbered; files in env but absent on disk;
phase1NN files on disk that are in neither the env nor the doc; run_all_sql.sh / final_build.sh consistency (both source the env file).

Usage: python3 tools/check_paste_order.py          (exit 0 = clean, 1 = problems)
"""
import hashlib
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOC = os.path.join(REPO, "docs", "PASTE_ORDER.md")
ENV = os.path.join(REPO, "tests", "sql", "paste_order.env")
SUPA = os.path.join(REPO, "supabase")


def read_env():
    text = open(ENV, encoding="utf-8").read()
    out = {}
    for key in ("FOUNDATION", "NEW"):
        m = re.search(r'^%s="([^"]*)"' % key, text, re.M)
        if not m:
            sys.exit("cannot find %s in paste_order.env" % key)
        out[key] = [int(x) for x in re.findall(r"phase(\d+)", m.group(1))]
    return out


def parse_doc():
    rows = []
    for lineno, line in enumerate(open(DOC, encoding="utf-8"), 1):
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        m = re.search(r"phase(\d+)\.sql", cells[1])
        if not m:
            continue
        rows.append({"line": lineno, "num_cell": cells[0], "num": int(cells[0]) if re.fullmatch(r"\d+", cells[0]) else None, "phase": int(m.group(1))})
    return rows


def main():
    env = read_env()
    canon = [n for n in env["NEW"] if os.path.isfile(os.path.join(SUPA, "phase%d.sql" % n))]
    rows = parse_doc()
    problems = []

    print("== 1. NEW phase files (canonical order) ==")
    print("%-5s %-16s %9s  %s" % ("pos", "file", "bytes", "sha256"))
    for i, n in enumerate(env["NEW"], 1):
        path = os.path.join(SUPA, "phase%d.sql" % n)
        if os.path.isfile(path):
            data = open(path, "rb").read()
            print("%-5d %-16s %9d  %s" % (i, "phase%d.sql" % n, len(data), hashlib.sha256(data).hexdigest()))
        else:
            print("%-5d %-16s %9s" % (i, "phase%d.sql" % n, "MISSING"))
            problems.append("phase%d.sql is in paste_order.env but not on disk (builders skip it)" % n)
    print()

    unnum = [r for r in rows if r["num"] is None]
    for r in unnum:
        problems.append("doc line %d: row number %r is not a plain number" % (r["line"], r["num_cell"]))
    numbered = [r for r in rows if r["num"] is not None]
    doc_order = [r["phase"] for r in numbered]
    if doc_order != canon:
        problems.append("doc table order differs from paste_order.env")
        for p in canon:
            if p not in doc_order:
                problems.append("phase%d is in paste_order.env but has no numbered row in the doc" % p)
        for p in doc_order:
            if p not in canon:
                problems.append("phase%d has a doc row but is not in paste_order.env (or its file is missing)" % p)
        dup = sorted({p for p in doc_order if doc_order.count(p) > 1})
        for p in dup:
            problems.append("phase%d appears in more than one doc row" % p)
    for i, r in enumerate(numbered, 1):
        if r["num"] != i:
            problems.append("doc line %d: row number %d, expected %d (rows must be 1..N without gaps)" % (r["line"], r["num"], i))
    for f in os.listdir(SUPA):
        m = re.fullmatch(r"phase(1\d\d)\.sql", f)
        if m and int(m.group(1)) not in env["NEW"]:
            problems.append("%s exists on disk but is not in paste_order.env" % f)
    for sh in ("tests/sql/final_build.sh", "tests/sql/run_all_sql_adv.sh"):
        if "paste_order.env" not in open(os.path.join(REPO, sh), encoding="utf-8").read():
            problems.append("%s does not read tests/sql/paste_order.env" % sh)
    # union merge: tests/sql/ORDER.txt (read by run_all_union.sh, check_numbering.py, build_phase477.py, build_paste_parts.py) must be the same list as FOUNDATION + NEW
    words = []
    for ln in open(os.path.join(REPO, "tests", "sql", "ORDER.txt"), encoding="utf-8"):
        if not ln.lstrip().startswith("#"):
            words += re.findall(r"phase(\d+)", ln)
    if [int(x) for x in words] != env["FOUNDATION"] + env["NEW"]:
        problems.append("tests/sql/ORDER.txt is not FOUNDATION + NEW of tests/sql/paste_order.env")

    print("== 2. doc table vs paste_order.env ==")
    print("canonical: " + " ".join(str(p) for p in canon))
    print("doc rows : " + " ".join(str(p) for p in doc_order))
    if not problems:
        print("OK: no problems found")
        return 0
    print("%d problem(s):" % len(problems))
    for p in problems:
        print("  - " + p)
    return 1


if __name__ == "__main__":
    sys.exit(main())

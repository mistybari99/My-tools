#!/usr/bin/env python3
"""Guard for the phase and form numbering. Exit 0 = PASS, 1 = FAIL. Python standard library only.

Checks
  1. Every supabase/phaseNNN.sql in 479-498 has its phaseNNN_test.sql pair, or a note that it has none
     ("no test for NNN" in docs/integration, docs/PASTE_ORDER.md or tests/sql/ORDER.txt). A _test file
     without its main file also fails.
  2. No old-only number (500, 510, 511, 520, 530-533, 540-542, 550-554) is used as a phase number in
     supabase, tests/sql, docs/PASTE_ORDER.md, docs/integration, web/data/info.json src fields or tools.
     Phase numbers are matched with word boundaries, and lists such as "phases 530 to 533" are read.
  3. A \\i supabase/phaseNNN.sql include for NNN >= 479 points to a file that exists.
  4. tests/sql/ORDER.txt lists each phase once, every listed phase file exists, and the 479-498 phases
     are all listed (missing ones are a WARN, not a FAIL).
  5. Numbers that are both old and new (480, 481, 490, 491) cannot be judged by digits. They are
     listed as REVIEW with their count per file. They never fail the check.

usage: python3 tools/check_numbering.py
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import renumber as rn  # same scope and phase-context rules as the dry-run tool

ROOT = rn.ROOT
FIRST, LAST = rn.PHASE_RANGE
INCLUDE_RE = re.compile(r'\\i\s+supabase/phase(\d+)\.sql')


def main():
    data, map_problems = rn.load_map()
    phases = data['phases']
    olds = {p['old'] for p in phases}
    news = {p['new'] for p in phases}
    old_only = olds - news
    ambig = olds & news
    fails, warns, review = [], [], {}
    lines_out = []

    # 1. pairs
    sup = os.path.join(ROOT, 'supabase')
    docs_text = ''
    for rel in ('docs/PASTE_ORDER.md', 'tests/sql/ORDER.txt'):
        with open(os.path.join(ROOT, rel), encoding='utf-8') as fh:
            docs_text += fh.read()
    for dirpath, _, files in os.walk(os.path.join(ROOT, 'docs', 'integration')):
        for name in files:
            if name.endswith('.md'):
                with open(os.path.join(dirpath, name), encoding='utf-8') as fh:
                    docs_text += fh.read()
    pair_ok = 0
    for n in range(FIRST, LAST + 1):
        main_f, test_f = f'phase{n}.sql', f'phase{n}_test.sql'
        has_main = os.path.exists(os.path.join(sup, main_f))
        has_test = os.path.exists(os.path.join(sup, test_f))
        if has_main and has_test:
            pair_ok += 1
        elif has_main:
            if re.search(rf'no test (for|of) (phase ?)?{n}\b|phase ?{n}\b[^\n]{{0,40}}no test', docs_text, re.I):
                pair_ok += 1
            else:
                fails.append(f'supabase/{main_f} has no supabase/{test_f} and no "no test" note')
        elif has_test:
            fails.append(f'supabase/{test_f} exists without supabase/{main_f}')
    lines_out.append(f'[pair]   {pair_ok} phase files in {FIRST}-{LAST} have a _test pair or a "no test" note')

    # 2 and 5: references, scanned over the same scope as renumber.py
    old_hits, old_files = [], set()
    for rel, kind in rn.iter_scope():
        try:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as fh:
                text_lines = fh.readlines()
        except UnicodeDecodeError:
            continue
        for i, line in enumerate(text_lines, 1):
            if kind == 'info_src' and not rn.SRC_RE.match(line):
                continue
            for _, _, n in rn.phase_spans(line):
                if n in old_only:
                    old_hits.append(f'{rel}:{i}: phase {n}: {line.strip()[:150]}')
                    old_files.add(rel)
                elif n in ambig:
                    review[rel] = review.get(rel, 0) + 1
    if old_hits:
        fails.append(f'{len(old_hits)} old-only phase number reference(s) in {len(old_files)} file(s)')
    lines_out.append(f'[old]    old-only numbers {sorted(old_only)}: {len(old_hits)} reference(s) left')
    lines_out.extend(f'         {h}' for h in old_hits)
    lines_out.append(f'[review] numbers both old and new {sorted(ambig)}: {sum(review.values())} reference(s) '
                     f'in {len(review)} file(s); judged by hand, not by digits')
    lines_out.extend(f'         {rel}: {n}' for rel, n in sorted(review.items()))

    # 3. includes
    bad_inc = []
    for rel, kind in rn.iter_scope():
        if not rel.endswith('.sql') and not rel.startswith('tests/'):
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as fh:
                for i, line in enumerate(fh, 1):
                    for m in INCLUDE_RE.finditer(line):
                        n = int(m.group(1))
                        if n >= FIRST and not os.path.exists(os.path.join(sup, f'phase{n}.sql')):
                            bad_inc.append(f'{rel}:{i}: \\i supabase/phase{n}.sql (file missing)')
        except (UnicodeDecodeError, FileNotFoundError):
            continue
    if bad_inc:
        fails.append(f'{len(bad_inc)} include(s) of a missing phase file')
    lines_out.append(f'[include] {len(bad_inc)} \\i include(s) of a missing phase file')
    lines_out.extend(f'         {b}' for b in bad_inc)

    # 4. ORDER.txt
    order_path = os.path.join(ROOT, 'tests', 'sql', 'ORDER.txt')
    tokens = []
    with open(order_path, encoding='utf-8') as fh:
        for line in fh:
            if line.lstrip().startswith('#'):
                continue
            tokens += re.findall(r'\bphase\d+\b', line)
    seen, dupes = set(), set()
    for t in tokens:
        (dupes if t in seen else seen).add(t)
    missing_file = sorted(t for t in seen if not os.path.exists(os.path.join(sup, f'{t}.sql')))
    not_listed = [f'{n}' for n in range(FIRST, LAST + 1)
                  if os.path.exists(os.path.join(sup, f'phase{n}.sql')) and f'phase{n}' not in seen]
    if dupes:
        fails.append(f'ORDER.txt lists twice: {", ".join(sorted(dupes))}')
    if missing_file:
        fails.append(f'ORDER.txt lists missing files: {", ".join(missing_file)}')
    lines_out.append(f'[order]  ORDER.txt: {len(seen)} phases, duplicates {sorted(dupes) or "none"}, '
                     f'missing files {missing_file or "none"}')
    if not_listed:
        warns.append(f'tests/sql/ORDER.txt does not list phase(s) {", ".join(not_listed)} '
                     '(docs/PASTE_ORDER.md says they must be added and built once)')

    if map_problems:
        fails.extend(map_problems)

    print('check_numbering: phases 479-498 and form numbers')
    for line in lines_out:
        print(line)
    for w in warns:
        print(f'[WARN]   {w}')
    for f in fails:
        print(f'[FAIL]   {f}')
    print(f'RESULT: {"FAIL" if fails else "PASS"} ({len(fails)} failure(s), {len(warns)} warning(s))')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())

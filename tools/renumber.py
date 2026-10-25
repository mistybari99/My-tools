#!/usr/bin/env python3
"""Renumber phase files, phase references and printed form codes from tools/numbering_map.json.

Dry run by default: prints every file and count, and writes nothing.
--apply writes, and only when every guard passes. Python standard library only.

What may change
  - phase file names (supabase/phaseNNN.sql and _test pair) for the map's pending renames
  - phase numbers in text, in the phase scope (comment rule for supabase/*.sql, see below)
  - printed form codes (NN-N, e.g. 02-4) from the map's form_codes list (the mapping in
    docs/FORM_SEQUENCE.md). Only when form_groups_approved = true. The map is applied in ONE pass
    per line, so a code is never mapped twice (02-4 -> 01-1 never continues to 40-1).
    Form codes are changed only in the form scope: app code, tests/web, tools, docs (except the
    frozen names below) and web/data/info.json.

What never changes
  - phases 8 to 478 (the tool refuses any number below 479)
  - a line of supabase/*.sql that is not a SQL comment (starts with --) and carries a phase number:
    reported as BLOCKED and --apply refuses. The owner decides those lines by hand.
  - form codes in supabase/ and tests/sql/ (frozen SQL: a new code goes only in a NEW phase file),
    in generated docs and history/audit docs (FROZEN_FORM_PREFIXES, FROZEN_FORM_NAMES): reported as FROZEN
  - the files in SELF_FILES (this tool, check_numbering.py, the map, the applied marker)

Guards for form codes
  - form_groups_approved must be true
  - the applied marker tools/numbering_applied.json must not exist: a second apply would shift
    the codes again. --apply writes the marker after the files.
  - every form-code-shaped token (NN-N, NN 01..41, N 1..9, ASCII digits) on a row line (a markdown table row or a line with a quoted code)
    must be a code the map knows (old or new). An unknown code refuses the apply.

Phase numbers are matched with word boundaries (phase480 never matches phase4800) and
replaced in one pass, so a chain such as 481 -> 480 -> 479 cannot happen.

Numbers that are both an old and a new number (480, 481, 490, 491 in the current map) cannot be
told apart by digits. Once renamed they are skipped here; check_numbering.py lists them for review.

usage:
  python3 tools/renumber.py            dry run
  python3 tools/renumber.py --apply    apply (see docs/NUMBERING.md for the steps first)
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_PATH = os.path.join(ROOT, 'tools', 'numbering_map.json')
MARKER_REL = 'tools/numbering_applied.json'
BANGLA_MARKER_REL = 'tools/numbering_applied_bangla.json'
BN_DIGITS = '০১২৩৪৫৬৭৮৯'   # Bangla digits 0-9
BN_TO_ASCII = str.maketrans(BN_DIGITS, '0123456789')
# Bangla-digit form code. Same context rule as FORM_RE (see there).
BN_FORM_RE = re.compile('(?<![0-9' + BN_DIGITS + 'A-Za-z_.\\-])([' + BN_DIGITS + ']{2}-[' + BN_DIGITS + '])(?![0-9' + BN_DIGITS + 'A-Za-z_\\-]|\\.[' + BN_DIGITS + '0-9])')
SELF_FILES = {'tools/renumber.py', 'tools/check_numbering.py', 'tools/numbering_map.json', MARKER_REL, BANGLA_MARKER_REL,
              'tests/py/test_renumber_forms.py'}   # the tool's own test keeps the old codes it asserts on
FIRST_TOUCHED = 479          # phases below this number are never renamed or edited
PHASE_RANGE = (479, 498)     # the sequence the map must land in
TEXT_EXT = ('.sql', '.sh', '.txt', '.py', '.js', '.json', '.md')
SCOPE_GIT_PATHS = ['supabase', 'tests', 'tools', 'web', 'docs', 'web/data/info.json']
FORM_EXT = ('.js', '.html', '.json', '.md', '.py', '.sh', '.txt', '.css', '.ts', '.yml', '.yaml', '.xml', '.kt', '.java', '.swift')
# form codes: frozen paths are reported, never changed
FROZEN_FORM_PREFIXES = ('supabase/', 'tests/sql/', 'docs/paste_parts/', 'docs/inputs/', 'docs/audit2/',
                        'docs/audit_rpt/', 'docs/briefs_p2p3/', 'docs/plan_v2/', 'web/data/kb.json',
                        'tests/ui_inventory/')
FROZEN_FORM_NAMES = ('AUDIT', 'LOG', 'ROADMAP', 'PLAN', 'FORM_SEQUENCE', 'FORM_NAMES_PROPOSAL', 'NUMBERING',
                     'HANDOFF', 'VERIFY', 'RECOVERY')

HEAD_RE = re.compile(r'\bphases?[ _]?(\d{3})(?!\d)', re.I)
LIST_RE = re.compile(r'\s*(?:,|/|\+|&|-|–|\band\b|\bor\b|\bto\b)\s*(?:phase[ _]?)?(\d{3})(?!\d)', re.I)
# NN-N, ASCII digits. Not inside a word, number, file name part or range: no letter, digit, '_', '-' or '.'
# just before it, and no letter, digit, '_', '-' or '.digit' just after it. A colon or a slash may surround a code
# ('field:10-2:x', '#/entry/new/10-2/1'), so these are matched too.
FORM_RE = re.compile(r'(?<![0-9A-Za-z_.\-])\d{2}-\d(?![0-9A-Za-z_\-]|\.\d)', re.ASCII)
# internal ids that carry a code (f04_1, form_20_4, salary_sheet_02_2): stored in SQL and contracts, never changed
UNDERSCORE_RE = re.compile(r'(?<![A-Za-z0-9])(f|form_|sheet_)(\d{2})_(\d)(?![0-9])', re.ASCII)
ROW_QUOTED_RE = re.compile(r"""['"]\d{2}-\d['"]""", re.ASCII)
SRC_RE = re.compile(r'\s*"src"\s*:')


def load_map():
    with open(MAP_PATH, encoding='utf-8') as fh:
        data = json.load(fh)
    problems = []
    phases = data.get('phases', [])
    olds = [p['old'] for p in phases]
    news = [p['new'] for p in phases]
    if len(set(olds)) != len(olds):
        problems.append('map: an old number appears twice')
    if len(set(news)) != len(news):
        problems.append('map: a new number appears twice')
    stems = [p.get('file_stem', '') for p in phases]
    if len(set(stems)) != len(stems) or not all(stems):
        problems.append('map: file_stem must be present and unique')
    for p in phases:
        if p['old'] < FIRST_TOUCHED or p['new'] < FIRST_TOUCHED:
            problems.append(f"map: {p['old']}->{p['new']} touches a phase below {FIRST_TOUCHED}")
        if not (PHASE_RANGE[0] <= p['new'] <= PHASE_RANGE[1]):
            problems.append(f"map: new number {p['new']} is outside {PHASE_RANGE}")
    problems.extend(check_form_codes(data.get('form_codes', [])))
    return data, problems


def check_form_codes(rows):
    """Problems in the per-code map. Rules: 41 sorted rows, A-Z by English short name (case-insensitive),
    sort n -> NN-1 with NN = n, old and new codes each unique, and the fixed row 0-1 maps to itself."""
    problems = []
    if not rows:
        return problems
    fixed = [r for r in rows if r.get('sort') is None]
    sorted_rows = [r for r in rows if r.get('sort') is not None]
    if len(fixed) != 1 or fixed[0].get('old') != '0-1' or fixed[0].get('new') != '0-1':
        problems.append('form map: exactly one fixed row, 0-1 -> 0-1, is required')
    if [r['sort'] for r in sorted_rows] != list(range(1, len(sorted_rows) + 1)):
        problems.append('form map: sort numbers must run 1..n in order')
    for r in sorted_rows:
        if r['new'] != f"{r['sort']:02d}-1":
            problems.append(f"form map: {r['old']} sort {r['sort']} must map to {r['sort']:02d}-1, not {r['new']}")
        if not r.get('en') or not r.get('bn'):
            problems.append(f"form map: {r['old']} needs an English and a Bangla short name")
    names = [r.get('en', '').lower() for r in sorted_rows]
    if names != sorted(names):
        problems.append('form map: rows are not in A-Z order by English short name')
    olds = [r['old'] for r in rows]
    news = [r['new'] for r in rows]
    if len(set(olds)) != len(olds):
        problems.append('form map: an old code appears twice')
    if len(set(news)) != len(news):
        problems.append('form map: a new code appears twice')
    return problems


def form_map_of(data):
    """{old: new} for every code that changes (the fixed 0-1 is not in it)."""
    return {r['old']: r['new'] for r in data.get('form_codes', []) if r['old'] != r['new']}


def known_form_codes(data):
    return {c for r in data.get('form_codes', []) for c in (r['old'], r['new'])}


def phase_spans(line):
    """(start, end, number) of every phase number in phase context, e.g. 'phase 480', 'phases 479 to 480'."""
    spans = []
    pos = 0
    while True:
        m = HEAD_RE.search(line, pos)
        if not m:
            break
        spans.append((m.start(1), m.end(1), int(m.group(1))))
        p = m.end()
        while True:
            m2 = LIST_RE.match(line, p)
            if not m2:
                break
            spans.append((m2.start(1), m2.end(1), int(m2.group(1))))
            p = m2.end()
        pos = p
    return spans


def iter_scope():
    """Phase scope. Yields (relative path, kind). kind: 'sql' (comment rule), 'text', or 'info_src' (only src lines)."""
    sup = os.path.join(ROOT, 'supabase')
    for name in sorted(os.listdir(sup)):
        if name.endswith('.sql'):
            yield f'supabase/{name}', 'sql'
    for top, kind in (('tests/sql', 'text'), ('docs/integration', 'text'), ('tools', 'text')):
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, top)):
            dirnames[:] = sorted(d for d in dirnames if d != '__pycache__')
            for name in sorted(filenames):
                if name.endswith(TEXT_EXT):
                    rel = os.path.relpath(os.path.join(dirpath, name), ROOT).replace(os.sep, '/')
                    if rel not in SELF_FILES:
                        yield rel, kind
    yield 'docs/PASTE_ORDER.md', 'text'
    yield 'web/data/info.json', 'info_src'


def form_status(rel):
    """Form scope: 'change', 'frozen' or None (not scanned)."""
    if rel in SELF_FILES or rel.endswith('.png'):
        return None
    if rel.startswith(FROZEN_FORM_PREFIXES):
        return 'frozen'
    base = os.path.basename(rel)
    if rel.startswith('docs/') and any(k in base.upper() for k in FROZEN_FORM_NAMES):
        return 'frozen'
    if rel.endswith(FORM_EXT) and rel.split('/')[0] in ('web', 'tests', 'tools', 'docs', 'supabase'):
        return 'change'
    return None


def form_files():
    """Tracked text files of the form scope (git ls-files), so untracked scratch files are never touched."""
    code, out = git('ls-files')
    if code != 0:
        raise SystemExit('git ls-files failed: the form scope needs a git checkout')
    for rel in out.splitlines():
        if form_status(rel):
            yield rel


def phase_state(p):
    sup = os.path.join(ROOT, 'supabase')
    old_files = [f for f in (f"phase{p['old']}.sql", f"phase{p['old']}_test.sql") if os.path.exists(os.path.join(sup, f))]
    new_files = [f for f in (f"phase{p['new']}.sql", f"phase{p['new']}_test.sql") if os.path.exists(os.path.join(sup, f))]
    if not old_files:
        return 'applied', old_files, new_files
    if not new_files:
        return 'pending', old_files, new_files
    return 'collision', old_files, new_files


def to_bangla(code):
    return code.translate(str.maketrans('0123456789', BN_DIGITS))


def transform(body, phase_map, form_map=None, digits='all'):
    """Returns (new_body, kinds). Every edit is computed on the original text and applied together.
    digits: 'all' (ASCII and Bangla-digit codes), 'bangla' (only Bangla-digit codes, for the second apply)."""
    edits = []
    for s, e, n in phase_spans(body):
        if n in phase_map and digits == 'all':
            edits.append((s, e, f'{phase_map[n]:03d}', 'phase'))
    if form_map and digits == 'all':
        for m in FORM_RE.finditer(body):
            code = m.group(0)
            if code in form_map:
                edits.append((m.start(), m.end(), form_map[code], 'form'))
    if form_map:
        for m in BN_FORM_RE.finditer(body):
            code = m.group(1).translate(BN_TO_ASCII)
            if code in form_map:
                edits.append((m.start(1), m.end(1), to_bangla(form_map[code]), 'form'))
    if not edits:
        return body, []
    kinds = [k for *_, k in edits]
    out = body
    for s, e, t, _ in sorted(edits, reverse=True):
        out = out[:s] + t + out[e:]
    return out, kinds


def is_row(line):
    s = line.strip()
    return s.startswith('|') or bool(ROW_QUOTED_RE.search(line))


def is_form_shape(token):
    """NN-N with NN in 01..41 and N in 1..9: the shape of a printed form code (14-0 and 2026-1 are not)."""
    nn, n = int(token[:2]), int(token[3])
    return 1 <= nn <= 41 and 1 <= n <= 9


def unmapped_row_codes(lines, known):
    """(line number, token) for every form-code token on a row line that the map does not know."""
    bad = []
    for i, line in enumerate(lines, 1):
        if not is_row(line):
            continue
        for m in FORM_RE.finditer(line):
            if m.group(0) not in known and is_form_shape(m.group(0)):
                bad.append((i, m.group(0)))
    return bad


def scan(phase_map, form_map, digits='all'):
    """Returns (changes, texts, frozen, unmapped). One pass per file, so every edit is computed on the
    original text. changes: dicts with path, line, old, new, kinds, comment, blocked.
    frozen: (path, line, token) for form codes that would change in a frozen path (never changed).
    unmapped: (path, line, token) for form-code tokens on row lines that the map does not know."""
    changes, texts, frozen, unmapped = [], {}, [], []
    phase_kinds = {rel: kind for rel, kind in iter_scope()}
    known = known_form_codes(DATA) if form_map else set()
    for rel in dict.fromkeys(list(phase_kinds) + (list(form_files()) if form_map else [])):
        kind = phase_kinds.get(rel)
        fstat = form_status(rel) if form_map else None
        if kind is None and fstat is None:
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding='utf-8', newline='') as fh:
                raw_lines = fh.read().splitlines(keepends=True)
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        if fstat == 'change':
            unmapped.extend((rel, i, t) for i, t in unmapped_row_codes(raw_lines, known))
        new_lines = list(raw_lines)
        for i, raw in enumerate(raw_lines, 1):
            body = raw.rstrip('\r\n')
            phase_here = phase_map if kind and not (kind == 'info_src' and not SRC_RE.match(body)) else {}
            if fstat == 'frozen' and digits == 'all':
                frozen.extend((rel, i, m.group(0)) for m in FORM_RE.finditer(body) if m.group(0) in form_map)
            form_here = form_map if fstat == 'change' else None
            new_body, kinds = transform(body, phase_here, form_here, digits)
            if new_body == body:
                continue
            is_comment = kind == 'sql' and body.lstrip().startswith('--')
            changes.append({'path': rel, 'line': i, 'old': body, 'new': new_body, 'kinds': kinds,
                            'comment': is_comment, 'blocked': kind == 'sql' and 'phase' in kinds and not is_comment})
            new_lines[i - 1] = new_body + raw[len(body):]
        if new_lines != raw_lines:
            texts[rel] = ''.join(new_lines)
    return changes, texts, frozen, unmapped


DATA = {}


def ambiguous_refs(ambig):
    """Count phase references to numbers that are both old and new (not changed, reported only)."""
    per_file = {}
    for rel, kind in iter_scope():
        try:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as fh:
                for line in fh:
                    if kind == 'info_src' and not SRC_RE.match(line):
                        continue
                    n = sum(1 for *_, num in phase_spans(line) if num in ambig)
                    if n:
                        per_file[rel] = per_file.get(rel, 0) + n
        except (UnicodeDecodeError, FileNotFoundError):
            continue
    return per_file


def marker_problem(root=ROOT, rel=MARKER_REL):
    """A message when the applied marker exists (a second apply would shift the codes again), else None."""
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        m = json.load(fh)
    return (f"applied marker {rel} exists (applied {m.get('applied_on', '?')}, "
            f"mapping {str(m.get('mapping_sha256', ''))[:12]}): the form codes are already renamed; "
            "a second apply would shift them again")


def mapping_sha(data):
    rows = [(r['old'], r['new']) for r in data.get('form_codes', [])]
    return hashlib.sha256(json.dumps(rows).encode('utf-8')).hexdigest()


def git(*args):
    r = subprocess.run(['git', '-C', ROOT, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    global DATA
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apply', action='store_true', help='write the changes (default: dry run only)')
    ap.add_argument('--show-lines', action='store_true', help='print every changed line (default: per-file counts)')
    ap.add_argument('--bangla-digits', action='store_true',
                    help='second apply: only the form codes written with Bangla digits (run after the ASCII apply; own marker)')
    args = ap.parse_args()

    data, problems = load_map()
    phases = data['phases']
    blockers = list(problems)
    states = {}
    for p in phases:
        st, old_files, new_files = phase_state(p)
        states[p['old']] = (st, old_files, new_files)
        # a collision (both old and new file exist) is reported in the phase list, not a blocker:
        # the phase map leaves such a phase out, so no phase number changes for it

    new_set = {p['new'] for p in phases}
    old_set = {p['old'] for p in phases}
    ambig = old_set & new_set
    phase_map = {}
    for p in phases:
        st = states[p['old']][0]
        if st == 'pending' or (st == 'applied' and p['old'] not in new_set):
            phase_map[p['old']] = p['new']

    form_map = form_map_of(data)
    DATA = data
    approved = bool(data.get('form_groups_approved', False))
    digits = 'all'
    if args.bangla_digits:
        digits = 'bangla'
        phase_map = {}
        marker = marker_problem(ROOT, BANGLA_MARKER_REL) or (None if marker_problem() else
                 'the ASCII form-code apply has not run (run it first: python3 tools/renumber.py --apply)')
    else:
        marker = marker_problem()

    print(f"renumber: map {os.path.relpath(MAP_PATH, ROOT)}  mode={'APPLY' if args.apply else 'DRY RUN'}")
    print('\nPhase files')
    pending_renames = []
    for p in phases:
        st, old_files, new_files = states[p['old']]
        label = f"{p['old']} -> {p['new']} ({p['package']}, {p['file_stem']})"
        if st == 'pending':
            pending_renames.append(p)
            print(f"  PENDING   {label}: {', '.join(old_files)} -> {', '.join(f.replace(str(p['old']), str(p['new']), 1) for f in old_files)}")
        elif st == 'applied':
            print(f"  applied   {label}")
        else:
            print(f"  COLLISION {label}: old {', '.join(old_files)}, new {', '.join(new_files)}")
    print(f"  pending renames: {len(pending_renames)}")

    changes, texts, frozen, unmapped = scan(phase_map, form_map, digits)
    phase_changes = [c for c in changes if 'phase' in c['kinds']]
    form_changes = [c for c in changes if 'form' in c['kinds']]
    blocked_phase = [c for c in phase_changes if c['blocked']]

    print(f"\nText references to old phase numbers (scanned: {', '.join(str(k) for k in sorted(phase_map)) or 'none'})")
    for c in phase_changes:
        tag = 'BLOCKED (SQL, not a comment)' if c['blocked'] else ('comment' if c['comment'] else 'text')
        print(f"  {c['path']}:{c['line']} [{tag}]")
        if args.show_lines:
            print(f"      - {c['old'].strip()[:160]}")
            print(f"      + {c['new'].strip()[:160]}")
    files_with_phase = len({c['path'] for c in phase_changes})
    print(f"  lines that would change: {len(phase_changes)} in {files_with_phase} files; "
          f"comment lines: {sum(1 for c in phase_changes if c['comment'])}; "
          f"BLOCKED SQL lines: {len(blocked_phase)}")

    print(f"\nForm codes (form_groups_approved = {str(approved).lower()}, mapping {mapping_sha(data)[:12]})")
    per_dir = {}
    for c in form_changes:
        key = '/'.join(c['path'].split('/')[:2])
        per_dir[key] = per_dir.get(key, 0) + 1
        if args.show_lines:
            print(f"  {c['path']}:{c['line']}")
            print(f"      - {c['old'].strip()[:160]}")
            print(f"      + {c['new'].strip()[:160]}")
    for k in sorted(per_dir):
        print(f"  {per_dir[k]:5d} lines in {k}")
    frozen_files = {}
    for rel, _, _ in frozen:
        frozen_files[rel] = frozen_files.get(rel, 0) + 1
    print(f"  lines with form-code changes: {len(form_changes)} in {len({c['path'] for c in form_changes})} files")
    print(f"  FROZEN (not changed; SQL data needs a new phase, history/generated docs keep old codes): "
          f"{len(frozen)} codes in {len(frozen_files)} files")
    for rel in sorted(frozen_files):
        print(f"      frozen {rel}: {frozen_files[rel]}")
    internal = []
    for rel in sorted(set(c['path'] for c in changes) | set(form_files())):
        if form_status(rel) != 'change':
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as fh:
                for i, line in enumerate(fh, 1):
                    for m in UNDERSCORE_RE.finditer(line):
                        if f'{m.group(2)}-{m.group(3)}' in form_map:
                            internal.append((rel, i, m.group(0)))
        except (UnicodeDecodeError, FileNotFoundError):
            continue
    print(f"  internal ids with an old code, kept (SQL and contracts use them; review by hand): {len(internal)} "
          f"in {len({r for r, _, _ in internal})} files")
    print(f"  unknown codes on row lines (refuse): {len(unmapped)}")
    for rel, i, t in unmapped[:50]:
        print(f"      {rel}:{i}: {t}")

    amb = ambiguous_refs(ambig) if ambig else {}
    print(f"\nNot changed: numbers both old and new {sorted(ambig)}: {sum(amb.values())} references in {len(amb)} files "
          f"(check with tools/check_numbering.py)")

    if blocked_phase:
        blockers.append(f"{len(blocked_phase)} phase line(s) in supabase/*.sql are not SQL comments (owner decides by hand)")
    if form_changes and not approved:
        blockers.append(f"{len(form_changes)} form-code line(s) would change but form_groups_approved is false")
    if unmapped:
        blockers.append(f"{len(unmapped)} form-code token(s) on row lines are not in the map (add them to the map or fix the row)")
    if marker:
        blockers.append(marker)

    if args.apply:
        _, status = git("status", "--porcelain", "--", *SCOPE_GIT_PATHS)
        if status.strip():
            blockers.append('git working tree is not clean in the scope paths (commit or stash first)')
        _, tags = git('tag', '--points-at', 'HEAD')
        if not any(t.startswith('backup/numbering-') for t in tags.split()):
            blockers.append('no backup tag at HEAD (run: git tag backup/numbering-<date>)')

    if blockers:
        print('\nBLOCKERS' + (' (apply refused)' if args.apply else ' (apply would be refused)'))
        for b in blockers:
            print(f'  - {b}')
    else:
        print('\nNo blockers.')

    if not args.apply:
        print(f"\nDRY RUN: nothing written. Pending phase renames: {len(pending_renames)}; "
              f"text lines to change: {len(changes)}.")
        return 0 if not problems else 1

    if blockers:
        return 2
    if phase_changes == [] and not pending_renames and not form_changes:
        print('\nNothing to do.')
        return 0

    for rel, text in texts.items():
        with open(os.path.join(ROOT, rel), 'w', encoding='utf-8', newline='') as fh:
            fh.write(text)
    for p in pending_renames:
        assert p['old'] >= FIRST_TOUCHED
        for suffix in ('.sql', '_test.sql'):
            src = os.path.join(ROOT, 'supabase', f"phase{p['old']}{suffix}")
            dst = os.path.join(ROOT, 'supabase', f"phase{p['new']}{suffix}")
            if os.path.exists(src):
                os.rename(src, dst)
    if form_changes:
        marker_data = {'applied_on': datetime.date.today().isoformat(), 'mapping_sha256': mapping_sha(data),
                       'form_code_lines': len(form_changes), 'files': len(texts), 'digits': digits}
        with open(os.path.join(ROOT, BANGLA_MARKER_REL if digits == 'bangla' else MARKER_REL), 'w', encoding='utf-8') as fh:
            json.dump(marker_data, fh, indent=2)
            fh.write('\n')
    print(f"\nAPPLIED: {len(texts)} files written, {len(pending_renames)} phase renames, "
          f"{len(form_changes)} form-code lines.")
    print('Next: python3 tools/check_numbering.py, then python3 tools/check_no_demo_leak.py, then the web suite.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Renumber phase files and phase references from tools/numbering_map.json.

Dry run by default: prints every file and line that would change, with counts, and writes nothing.
--apply writes, and only when every guard passes. Python standard library only.

What may change
  - phase file names (supabase/phaseNNN.sql and _test pair) for the map's pending renames
  - phase numbers in text, in the scope below
  - form codes (08-1 style), only when the map says form_groups_approved = true

What never changes
  - phases 8 to 478 (the tool refuses any number below 479)
  - a line of supabase/*.sql that is not a SQL comment (starts with --): such a line is
    reported as BLOCKED and --apply refuses. The owner decides those lines by hand.
  - the files in SELF_FILES (this tool, check_numbering.py, the map)

Phase numbers are matched with word boundaries (phase480 never matches phase4800) and
replaced in one pass, so a chain such as 481 -> 480 -> 479 cannot happen.

Numbers that are both an old and a new number (480, 481, 490, 491 in the current map) cannot be
told apart by digits. Once renamed they are skipped here; check_numbering.py lists them for review.

usage:
  python3 tools/renumber.py            dry run
  python3 tools/renumber.py --apply    apply (see docs/NUMBERING.md for the steps first)
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_PATH = os.path.join(ROOT, 'tools', 'numbering_map.json')
SELF_FILES = {'tools/renumber.py', 'tools/check_numbering.py', 'tools/numbering_map.json'}
FIRST_TOUCHED = 479          # phases below this number are never renamed or edited
PHASE_RANGE = (479, 498)     # the sequence the map must land in
TEXT_EXT = ('.sql', '.sh', '.txt', '.py', '.js', '.json', '.md')
SCOPE_GIT_PATHS = ['supabase', 'tests/sql', 'docs/PASTE_ORDER.md', 'docs/integration', 'tools', 'web/data/info.json']

HEAD_RE = re.compile(r'\bphases?[ _]?(\d{3})(?!\d)', re.I)
LIST_RE = re.compile(r'\s*(?:,|/|\+|&|-|–|\band\b|\bor\b|\bto\b)\s*(?:phase[ _]?)?(\d{3})(?!\d)', re.I)
FORM_RE = re.compile(r'(?<![\w.:/-])(\d{2})-(\d{1,2})(?![\w.:/-]|\d)')
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
    forms = data.get('form_groups', [])
    fold = [f['old'] for f in forms]
    fnew = [f['new'] for f in forms]
    if len(set(fnew)) != len(fnew):
        problems.append('map: two form groups get the same new code')
    if len(set(fold)) != len(fold):
        problems.append('map: a form group old code appears twice')
    return data, problems


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
    """Yields (relative path, kind). kind: 'sql' (comment rule), 'text', or 'info_src' (only src lines)."""
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


def phase_state(p):
    sup = os.path.join(ROOT, 'supabase')
    old_files = [f for f in (f"phase{p['old']}.sql", f"phase{p['old']}_test.sql") if os.path.exists(os.path.join(sup, f))]
    new_files = [f for f in (f"phase{p['new']}.sql", f"phase{p['new']}_test.sql") if os.path.exists(os.path.join(sup, f))]
    if not old_files:
        return 'applied', old_files, new_files
    if not new_files:
        return 'pending', old_files, new_files
    return 'collision', old_files, new_files


def transform(body, phase_map, form_map):
    edits = []
    for s, e, n in phase_spans(body):
        if n in phase_map:
            edits.append((s, e, f'{phase_map[n]:03d}', 'phase'))
    for m in FORM_RE.finditer(body):
        code = m.group(1)
        if code in form_map and form_map[code] != code:
            edits.append((m.start(1), m.end(1), form_map[code], 'form'))
    if not edits:
        return body, []
    kinds = [k for *_, k in edits]
    out = body
    for s, e, t, _ in sorted(edits, reverse=True):
        out = out[:s] + t + out[e:]
    return out, kinds


def scan(phase_map, form_map):
    """Returns (changes, file_texts). changes: dicts with path, line, old, new, kinds, comment, blocked."""
    changes, texts = [], {}
    for rel, kind in iter_scope():
        path = os.path.join(ROOT, rel)
        try:
            with open(path, encoding='utf-8', newline='') as fh:
                raw_lines = fh.read().splitlines(keepends=True)
        except UnicodeDecodeError:
            continue
        new_lines = list(raw_lines)
        for i, raw in enumerate(raw_lines, 1):
            body = raw.rstrip('\r\n')
            if kind == 'info_src' and not SRC_RE.match(body):
                continue
            new_body, kinds = transform(body, phase_map, form_map)
            if new_body == body:
                continue
            is_comment = kind == 'sql' and body.lstrip().startswith('--')
            changes.append({'path': rel, 'line': i, 'old': body, 'new': new_body, 'kinds': kinds,
                            'comment': is_comment, 'blocked': kind == 'sql' and not is_comment})
            new_lines[i - 1] = new_body + raw[len(body):]
        if new_lines != raw_lines:
            texts[rel] = ''.join(new_lines)
    return changes, texts


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


def git(*args):
    r = subprocess.run(['git', '-C', ROOT, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apply', action='store_true', help='write the changes (default: dry run only)')
    args = ap.parse_args()

    data, problems = load_map()
    phases = data['phases']
    blockers = list(problems)
    states = {}
    for p in phases:
        st, old_files, new_files = phase_state(p)
        states[p['old']] = (st, old_files, new_files)
        if st == 'collision':
            blockers.append(f"phase {p['old']} -> {p['new']}: target phase{p['new']} already exists, state cannot be told apart")

    new_set = {p['new'] for p in phases}
    old_set = {p['old'] for p in phases}
    ambig = old_set & new_set
    phase_map = {}
    for p in phases:
        st = states[p['old']][0]
        if st == 'pending' or (st == 'applied' and p['old'] not in new_set):
            phase_map[p['old']] = p['new']

    form_map = {f['old']: f['new'] for f in data.get('form_groups', []) if f['old'] != f['new']}
    approved = bool(data.get('form_groups_approved', False))

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

    changes, texts = scan(phase_map, form_map)
    phase_changes = [c for c in changes if 'phase' in c['kinds']]
    form_changes = [c for c in changes if 'form' in c['kinds']]
    blocked_phase = [c for c in phase_changes if c['blocked']]
    blocked_form = [c for c in form_changes if c['blocked']]

    print(f"\nText references to old phase numbers (scanned: {', '.join(str(k) for k in sorted(phase_map)) or 'none'})")
    for c in changes:
        if 'phase' not in c['kinds']:
            continue
        tag = 'BLOCKED (SQL, not a comment)' if c['blocked'] else ('comment' if c['comment'] else 'text')
        print(f"  {c['path']}:{c['line']} [{tag}]")
        print(f"      - {c['old'].strip()[:160]}")
        print(f"      + {c['new'].strip()[:160]}")
    files_with_phase = len({c['path'] for c in phase_changes})
    print(f"  lines that would change: {len(phase_changes)} in {files_with_phase} files; "
          f"comment lines: {sum(1 for c in phase_changes if c['comment'])}; "
          f"BLOCKED SQL lines: {len(blocked_phase)}")

    print(f"\nForm codes (form_groups_approved = {str(approved).lower()})")
    for c in form_changes:
        print(f"  {c['path']}:{c['line']}")
        print(f"      - {c['old'].strip()[:160]}")
        print(f"      + {c['new'].strip()[:160]}")
    print(f"  lines with form-code changes: {len(form_changes)} in {len({c['path'] for c in form_changes})} files; "
          f"BLOCKED (non-comment SQL): {len(blocked_form)}")

    amb = ambiguous_refs(ambig) if ambig else {}
    print(f"\nNot changed: numbers both old and new {sorted(ambig)}: {sum(amb.values())} references in {len(amb)} files "
          f"(check with tools/check_numbering.py)")

    if blocked_phase or blocked_form:
        blockers.append(f"{len(blocked_phase)} phase and {len(blocked_form)} form-code line(s) in supabase/*.sql "
                        "are not SQL comments (owner decides by hand)")
    if form_changes and not approved:
        blockers.append(f"{len(form_changes)} form-code line(s) would change but form_groups_approved is false")

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
    print(f"\nAPPLIED: {len(texts)} files written, {len(pending_renames)} phase renames.")
    print('Next: python3 tools/check_numbering.py, then python3 tools/check_no_demo_leak.py, then the web suite.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Static guard for the backup workflow: database dumps must never reach a public place.

Exit 0 = PASS, 1 = FAIL. Python standard library only. No network, no secrets, no database.

Checks
  1. .github/workflows/backup.yml: the step "Refuse to run in a public repository" comes BEFORE the dump step and before any step that
     fetches, copies or pushes data.
  2. That guard fails closed: it exits 1 unless the repository reports private == "true" (an empty answer also refuses).
  3. Only backup.yml pushes to git (`git push`). Another workflow must not publish data.
  4. No workflow uploads a data artifact (dumps, the backups branch, out/ or data/). The website build is public by design and is allowed.
  5. No workflow or tool writes a dump (.ndjson, .ndjson.gz, .enc, manifest.json) to a path outside the backup folders.
     (A check on names only: it looks for these names in the upload and push steps.)

usage: python3 tools/check_backup_guard.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF_DIR = os.path.join(ROOT, '.github', 'workflows')
BACKUP = os.path.join(WF_DIR, 'backup.yml')
GUARD_NAME = 'Refuse to run in a public repository'
DUMP_STEP = 'Dump the database'
DUMP_NAMES = re.compile(r'\.ndjson(\.gz)?(\.enc)?\b|manifest\.json')


def read(p):
    with open(p, encoding='utf8') as fh:
        return fh.read()


def step_blocks(text):
    """The workflow steps as (name, body) pairs, in file order."""
    parts = re.split(r'(?m)^\s*-\s+name:\s*', text)
    out = []
    for part in parts[1:]:
        name, _, body = part.partition('\n')
        out.append((name.strip(), body))
    return out


def main():
    fails, notes = [], []
    if not os.path.exists(BACKUP):
        print('[FAIL] backup.yml is missing: ' + BACKUP)
        return 1
    text = read(BACKUP)
    steps = step_blocks(text)
    names = [n for n, _ in steps]

    # 1. the guard comes first among the steps that touch data
    if GUARD_NAME not in names:
        fails.append('backup.yml has no step named "%s"' % GUARD_NAME)
    else:
        g = names.index(GUARD_NAME)
        if DUMP_STEP in names and names.index(DUMP_STEP) < g:
            fails.append('the dump step runs before the public-repository guard')
        for i, (n, body) in enumerate(steps[:g]):
            if re.search(r'actions/checkout|git push|backup_dump|backup_photos|upload-artifact', body):
                fails.append('step "%s" touches data before the guard' % n)
        # 2. fail closed
        guard_body = dict(steps)[GUARD_NAME]
        if 'if [ "$private" != "true" ]' not in guard_body or 'exit 1' not in guard_body:
            fails.append('the guard does not refuse unless private == "true" (fail closed)')
        if 'gh api' not in guard_body or '.private' not in guard_body:
            fails.append('the guard does not read the repository visibility from the API')
        else:
            notes.append('guard reads visibility from the API and refuses otherwise')

    # 3, 4, 5 across every workflow file
    for path in sorted(glob.glob(os.path.join(WF_DIR, '*.yml'))):
        rel = os.path.relpath(path, ROOT)
        body = read(path)
        if path != BACKUP and re.search(r'git\s+push', body):
            fails.append('%s pushes to git (only backup.yml may push data)' % rel)
        # an artifact is public in a public repository: it may carry the website build (dist/site), never a dump, a backup folder or the data folder
        for m in re.finditer(r'upload-artifact@[^\n]*\n(?:[^\n]*\n){0,6}', body):
            block = m.group(0)
            if path == BACKUP or DUMP_NAMES.search(block) or re.search(r'backups|out/|data/|\bdump', block):
                fails.append('%s uploads an artifact that may carry data (artifacts of a public repository are public)' % rel)
        for name, step in step_blocks(body):
            if re.search(r'upload|push|cp\s|mv\s|rclone', step) and DUMP_NAMES.search(step):
                if path != BACKUP:
                    fails.append('%s step "%s" moves a dump file' % (rel, name))

    if fails:
        for f in fails:
            print('[FAIL] ' + f)
        print('RESULT: FAIL (%d problem(s))' % len(fails))
        return 1
    for n in notes:
        print('[note] ' + n)
    print('OK: backup guard first, fails closed, no data artifact upload, only backup.yml pushes or moves dumps.')
    print('RESULT: PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())

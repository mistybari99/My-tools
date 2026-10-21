#!/usr/bin/env python3
"""Recovery merge rehearsal: try to merge the advanced line into a temporary branch of ours and report.

Why: the public site was rebuilt from another line (origin/ccr-9c1f9be7-3s9qnz) than this branch, and
features were lost when this branch's web/ replaced it (see docs/RECOVERY_AUDIT.md, docs/RECOVERY_ROADMAP.md).
This tool rehearses the recovery merge. It never touches the checkout you run it from.

What it does (dry run, the default)
  1. refuses to run when the disk is more than 90% full
  2. creates a SCRATCH worktree and a TEMP local branch (recovery-trial-<time>) from the current HEAD
  3. runs `git merge --no-commit --no-ff <source>` there and lists the conflicts per file and per area
  4. resolves every conflict with the chosen policy (default: ours wins) ONLY so the repo checks can run
     on a complete tree; the result is a rehearsal, not a recovery
  5. runs the repo checks on the BASELINE (your HEAD) and on the REHEARSED tree
  6. proposes a phase renumbering map for number collisions (numbers <= 478 of this branch never change)
  7. writes a Markdown report and removes the worktree and the temp branch

What it never does
  - never merges into your branch, never commits on it, never pushes anything (no `git push` anywhere)
  - never writes outside the scratch directory and the report path
  - never talks to Supabase or any network service (a local `git fetch` is NOT done; run `git fetch origin` yourself)

usage
  python3 tools/recovery_merge.py                       dry run, report in $TMPDIR
  python3 tools/recovery_merge.py --keep                keep the worktree + temp branch for hand resolution (still never pushed)
  python3 tools/recovery_merge.py --source origin/other-branch --report /path/report.md --no-checks
  python3 tools/recovery_merge.py --policy theirs       resolve conflicts to the source side for the rehearsal
Exit code: 0 report written (conflicts are expected and are not a failure), 2 refused (disk, bad ref, dirty guard).
"""
import argparse
import collections
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = 'origin/ccr-9c1f9be7-3s9qnz'
DESIGNATED = 'claude/supabase-readonly-audit-xo3qkp'
CHECKS = [
    ('demo leak', ['python3', 'tools/check_no_demo_leak.py']),
    ('numbering', ['python3', 'tools/check_numbering.py']),
    ('phase477 build', ['python3', 'tools/build_phase477.py', '--check']),
    ('test-only files', ['python3', 'tools/test_testonly_files.py']),
    ('info coverage', ['python3', 'tools/check_info_coverage.py']),
    ('ui inventory', ['python3', 'tools/check_ui_inventory.py']),
    ('report registry', ['python3', 'tools/build_report_registry.py', '--check']),
    ('backup guard', ['python3', 'tools/check_backup_guard.py']),
]


def run(cmd, cwd=ROOT, timeout=600, check=False):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError('%s failed: %s' % (' '.join(cmd), (p.stderr or p.stdout)[-400:]))
    return p


def git(*a, cwd=ROOT, check=False):
    return run(['git'] + list(a), cwd=cwd, check=check)


def disk_used_pct(path):
    u = shutil.disk_usage(path)
    return round(100.0 * u.used / u.total, 1)


def area_of(path):
    if path.startswith('supabase/'):
        return 'sql'
    if path.startswith('tests/sql') or path.startswith('tests/'):
        return 'tests'
    if path.startswith('web/'):
        return 'web'
    if path.startswith('docs/'):
        return 'docs'
    if path.startswith('tools/'):
        return 'tools'
    if path.startswith('.github/'):
        return 'ci'
    return 'other'


def phase_no(path):
    m = re.match(r'supabase/phase(\d+)([a-z]?)(_test)?\.sql$', path)
    return int(m.group(1)) if m else None


def phase_numbers(ref):
    out = git('ls-tree', '--name-only', ref, 'supabase/').stdout.split()
    nums = set()
    for f in out:
        m = re.match(r'supabase/phase(\d+)\.sql$', f)
        if m:
            nums.add(int(m.group(1)))
    return nums


def renumber_proposal(ours_ref, src_ref, base_ref):
    ours = phase_numbers(ours_ref)
    src = phase_numbers(src_ref)
    base = phase_numbers(base_ref)
    changed_src = set()
    for n in src & ours:
        a = git('show', '%s:supabase/phase%d.sql' % (ours_ref, n)).stdout
        b = git('show', '%s:supabase/phase%d.sql' % (src_ref, n)).stdout
        if a != b:
            changed_src.add(n)
    collide = sorted(changed_src)
    # numbers that exist only on the source side and are free here keep their number
    keep = sorted(n for n in src - ours)
    nxt = max(ours | src) + 1
    # next free number above everything on both sides; 500 is retired (docs/NUMBERING.md section 8)
    mapping = []
    for n in collide:
        while nxt == 500 or nxt in ours or nxt in src:
            nxt += 1
        mapping.append((n, nxt))
        nxt += 1
    return collide, keep, mapping


def run_checks(tree, label, enabled):
    rows = []
    if not enabled:
        return rows
    for name, cmd in CHECKS:
        try:
            p = run(cmd, cwd=tree, timeout=900)
            allout = [l for l in (p.stdout + '\n' + p.stderr).strip().splitlines() if l.strip()]
            tail = allout[-2:]
            bad = [l for l in allout if re.match(r'\s*(LEAK|FAIL|MISSING|WARN|RENAMED)', l)][:14] if p.returncode else []
            rows.append((name, p.returncode, ' | '.join(t.strip()[:150] for t in tail), bad))
        except subprocess.TimeoutExpired:
            rows.append((name, 124, 'timeout', []))
        except Exception as e:  # a missing tool must not stop the report
            rows.append((name, 127, str(e)[:150], []))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--source', default=DEFAULT_SOURCE)
    ap.add_argument('--policy', choices=['ours', 'theirs'], default='ours')
    ap.add_argument('--report', default=None)
    ap.add_argument('--keep', action='store_true', help='keep the scratch worktree and temp branch (never pushed)')
    ap.add_argument('--no-checks', action='store_true')
    ap.add_argument('--workdir', default=None, help='parent folder for the scratch worktree (default: system temp)')
    args = ap.parse_args()

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
    pct = disk_used_pct(ROOT)
    if pct > 90:
        print('REFUSED: disk is %.1f%% full (limit 90%%)' % pct)
        return 2
    if git('rev-parse', '--verify', '--quiet', args.source + '^{commit}').returncode != 0:
        print('REFUSED: ref %s not found (run `git fetch origin` first; this tool never fetches)' % args.source)
        return 2
    head = git('rev-parse', 'HEAD').stdout.strip()
    cur = git('rev-parse', '--abbrev-ref', 'HEAD').stdout.strip()
    base = git('merge-base', 'HEAD', args.source).stdout.strip()
    ahead = git('rev-list', '--count', 'HEAD..' + args.source).stdout.strip()
    behind = git('rev-list', '--count', args.source + '..HEAD').stdout.strip()

    parent = args.workdir or tempfile.gettempdir()
    wt = tempfile.mkdtemp(prefix='recovery_merge_', dir=parent)
    os.rmdir(wt)  # git wants to create it
    branch = 'recovery-trial-' + stamp
    if branch == DESIGNATED or branch.startswith(DESIGNATED):
        print('REFUSED: temp branch name clashes with the designated branch')
        return 2
    report_path = args.report or os.path.join(parent, 'recovery_merge_report_%s.md' % stamp)
    lines = []
    P = lines.append
    try:
        git('worktree', 'add', '-q', '-b', branch, wt, head, check=True)
        m = git('merge', '--no-commit', '--no-ff', args.source, cwd=wt)
        st = git('status', '--porcelain=v1', cwd=wt).stdout.splitlines()
        conflicts = [(l[:2], l[3:]) for l in st if l[:2] in ('UU', 'AA', 'DU', 'UD', 'AU', 'UA', 'DD')]
        clean_added = [l[3:] for l in st if l[:1] == 'A' and l[:2] not in ('AA', 'AU')]
        clean_mod = [l[3:] for l in st if l[:1] == 'M']
        by_area = collections.defaultdict(list)
        for code, path in conflicts:
            by_area[area_of(path)].append((code, path))
        src_only_web = [p for p in clean_added if p.startswith('web/')]
        src_only_sql = [p for p in clean_added if p.startswith('supabase/')]

        # rehearsal resolution (only so the checks can run on a whole tree)
        for code, path in conflicts:
            side = '--ours' if args.policy == 'ours' else '--theirs'
            r = git('checkout', side, '--', path, cwd=wt)
            if r.returncode == 0:
                git('add', '--', path, cwd=wt)
            else:
                git('rm', '-q', '-f', '--', path, cwd=wt)
        leftover = [l for l in git('status', '--porcelain=v1', cwd=wt).stdout.splitlines() if l[:2] in ('UU', 'AA', 'DU', 'UD', 'AU', 'UA')]

        P('# Recovery merge rehearsal report')
        P('')
        P('Generated %s UTC by tools/recovery_merge.py (dry run%s). Nothing was merged into %s, nothing was pushed.' % (stamp, ', worktree kept' if args.keep else '', cur))
        P('')
        P('- Ours: `%s` at `%s`' % (cur, head[:8]))
        P('- Source: `%s` at `%s` (%s commits ahead, %s behind, merge base `%s`)' % (args.source, git('rev-parse', args.source).stdout.strip()[:8], ahead, behind, base[:8]))
        P('- Temp branch (local only): `%s`; scratch worktree: `%s`' % (branch, wt))
        P('- Disk used at start: %s%%' % pct)
        P('- git merge exit code: %s (1 = conflicts, expected)' % m.returncode)
        P('')
        P('## 1. Conflicts per area')
        P('')
        P('| area | conflicted files |')
        P('|---|---:|')
        for a in ('sql', 'web', 'tests', 'docs', 'tools', 'ci', 'other'):
            P('| %s | %d |' % (a, len(by_area.get(a, []))))
        P('| **total** | **%d** |' % len(conflicts))
        P('')
        P('Merged without conflict: %d files added from the source (%d under web/, %d under supabase/), %d files modified.' % (len(clean_added), len(src_only_web), len(src_only_sql), len(clean_mod)))
        P('')
        for a in ('web', 'tools', 'ci', 'other', 'docs'):
            if by_area.get(a):
                P('### Conflicted files: %s' % a)
                P('')
                for code, path in sorted(by_area[a], key=lambda x: x[1]):
                    P('- `%s` %s' % (code, path))
                P('')
        if by_area.get('sql'):
            ph = sorted(set(phase_no(p) for _, p in by_area['sql'] if phase_no(p) is not None))
            P('### Conflicted SQL phase numbers (%d numbers, test files counted with their phase)' % len(ph))
            P('')
            P(', '.join(str(n) for n in ph))
            P('')
        if by_area.get('tests'):
            exts = collections.Counter(os.path.splitext(p)[1] or '(none)' for _, p in by_area['tests'])
            P('### Conflicted test files: %s' % ', '.join('%s x%d' % kv for kv in sorted(exts.items())))
            P('')
        P('## 2. Source-only web files that merged cleanly (%d)' % len(src_only_web))
        P('')
        P(', '.join(os.path.basename(p) for p in sorted(src_only_web)) or '(none)')
        P('')
        P('Note: a file that merged cleanly is NOT wired in. Wiring is `web/index.html`, `web/ia.js`, `web/sw.js` (all conflicted) - see the roadmap, phase P1.')
        P('')

        coll, keep, mapping = renumber_proposal('HEAD', args.source, base)
        P('## 3. Phase number collisions and the proposed renumbering (rules of tools/renumber.py: numbers <= 478 of this branch never change)')
        P('')
        P('Same number, different content on the two sides: **%d** numbers: %s' % (len(coll), ', '.join(str(n) for n in coll)))
        P('')
        P('Source-only numbers that are free here and keep their number (%d): %s' % (len(keep), ', '.join(str(n) for n in keep)))
        P('')
        P('| source phase (original name) | imported as | note |')
        P('|---|---|---|')
        for old, new in mapping:
            P('| phase%d | phase%d | source side moves; ours keeps %d |' % (old, new, old))
        P('')
        P('Number 500 is retired (docs/NUMBERING.md section 8) and is skipped. The numbers above are a proposal: the live database already holds the source phases under their ORIGINAL numbers, so the imported files keep a note of the original number in their first comment line.')
        P('')

        P('## 4. Repo checks')
        P('')
        P('Rehearsed tree policy: conflicts resolved `%s`; leftover unmerged paths after resolution: %d.' % (args.policy, len(leftover)))
        P('')
        if args.no_checks:
            P('(checks skipped by --no-checks)')
        else:
            base_rows = run_checks(ROOT, 'baseline', True)
            reh_rows = run_checks(wt, 'rehearsed', True)
            P('| check | baseline (HEAD) | rehearsed merge | rehearsed output (last lines) |')
            P('|---|---|---|---|')
            for (n1, rc1, _, _b1), (n2, rc2, out2, _b2) in zip(base_rows, reh_rows):
                P('| %s | %s | %s | %s |' % (n1, 'OK' if rc1 == 0 else 'FAIL(%d)' % rc1, 'OK' if rc2 == 0 else 'FAIL(%d)' % rc2, out2.replace('|', '/')))
            P('')
            for (n2, rc2, out2, bad) in reh_rows:
                if rc2 != 0 and bad:
                    P('### Detail: %s (first lines of the failure)' % n2)
                    P('')
                    P('```')
                    for l in bad:
                        P(l[:220])
                    P('```')
                    P('')
        P('')
        P('## 5. Reading this report')
        P('')
        P('- Conflicts are expected: the two lines reuse phase numbers 80-99, 120, 131, 132 for different work and both rewrote web/index.html, ia.js, nav.js, sw.js.')
        P('- A FAIL in the rehearsed column that is OK in the baseline column is work the real merge must do (wire scripts, add info entries, register phases in ORDER.txt, remove demo-like text).')
        P('- This is a rehearsal under policy `%s`; it does not decide any owner question.' % args.policy)
    finally:
        os.makedirs(os.path.dirname(os.path.abspath(report_path)), exist_ok=True)
        with open(report_path, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')
        if args.keep:
            print('kept worktree %s on branch %s (local only, never push it)' % (wt, branch))
        else:
            git('worktree', 'remove', '--force', wt)
            git('branch', '-D', branch)
            git('worktree', 'prune')
    print('report written: %s' % report_path)
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Runs EVERY tests/web/*_test.js (headless Chromium, mocked RPCs; needs node and playwright) against a COPY of this checkout.

Why a copy: several older suites hard-code the folder /home/user/My-tools/web (the main checkout), so run in another folder or worktree they would test the wrong files.
The copy rewrites that path to the copy, and sets BOS_WEB / BOS_WEB_ROOT for the suites that read them. Suites that share a fixed port run one after the other, the rest in parallel (3 workers).
The test screenshots are written inside the COPY, never into the repository.

usage:  python3 tests/web/run_all.py [--copy /tmp/bos_web_copy] [--out /tmp/bos_web_out] [--workers 3] [test_name ...]
        -> <out>/<test>.log and <out>/summary.txt (exit code, seconds, last lines); prints how many suites ended with a non-zero exit code.
The suites that once hung (settings2_test, nav2_test, nav_test) have a 700 second limit like every other suite; all of them ended in a few minutes in the integration run.
"""
import argparse, concurrent.futures as cf, glob, os, re, shutil, subprocess, sys, time

ap = argparse.ArgumentParser()
ap.add_argument('--copy', default='/tmp/bos_web_copy')
ap.add_argument('--out', default='/tmp/bos_web_out')
ap.add_argument('--workers', type=int, default=3)
ap.add_argument('--timeout', type=int, default=700)
ap.add_argument('names', nargs='*')
a = ap.parse_args()
wt = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
cp, out = a.copy, a.out
if os.path.exists(cp):
    shutil.rmtree(cp)
shutil.copytree(wt, cp, ignore=shutil.ignore_patterns('.git', 'node_modules', '*.png'))
for f in glob.glob(cp + '/tests/web/*.js') + glob.glob(cp + '/tests/web/*.sh'):
    t = open(f, encoding='utf8').read()
    if '/home/user/My-tools/' in t:
        open(f, 'w', encoding='utf8').write(t.replace('/home/user/My-tools/', cp + '/'))
os.makedirs(out, exist_ok=True)
tests = sorted(os.path.basename(f)[:-3] for f in glob.glob(cp + '/tests/web/*_test.js'))
if a.names:
    tests = [t for t in tests if t in a.names]


def ports(t):
    s = open(cp + '/tests/web/%s.js' % t, encoding='utf8').read()
    return tuple(sorted({x or y for x, y in re.findall(r'PORT\s*=\s*(\d+)|listen\((\d{4})\)', s)}))


parent = {t: t for t in tests}


def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


byport = {}
for t in tests:
    for p in ports(t):
        byport.setdefault(p, []).append(t)
for ts in byport.values():
    for u in ts[1:]:
        parent[find(u)] = find(ts[0])
groups = {}
for t in tests:
    groups.setdefault(find(t), []).append(t)
env = dict(os.environ, BOS_WEB=cp + '/web', BOS_WEB_ROOT=cp + '/web', BOS_REPO_DIR=cp)


def run_group(ts):
    res = []
    for t in ts:
        t0 = time.time()
        try:
            r = subprocess.run(['node', 'tests/web/%s.js' % t, cp + '/tests/web'], cwd=cp, env=env, capture_output=True, text=True, timeout=a.timeout)
            txt, code = r.stdout + r.stderr, r.returncode
        except subprocess.TimeoutExpired as e:
            txt, code = (e.stdout.decode('utf8', 'ignore') if isinstance(e.stdout, bytes) else (e.stdout or '')), 'TIMEOUT'
        open(os.path.join(out, t + '.log'), 'w', encoding='utf8').write(txt)
        res.append((t, code, round(time.time() - t0), ' | '.join(l.strip() for l in txt.strip().split('\n')[-3:])[:300]))
    return res


with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
    allr = sorted(r for rs in ex.map(run_group, groups.values()) for r in rs)
with open(os.path.join(out, 'summary.txt'), 'w', encoding='utf8') as f:
    for t, code, sec, tail in allr:
        f.write('%-28s exit=%s %4ds  %s\n' % (t, code, sec, tail))
bad = [r for r in allr if r[1] != 0]
print(len(allr), 'suites;', len(bad), 'with a non-zero exit code', [r[0] for r in bad])
sys.exit(1 if bad else 0)

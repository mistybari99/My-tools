"""XC-6: tools/bump_sw.py - the cache version goes up by exactly one, the file stays valid, a missing line is refused, a dry run changes nothing.
Run: python3 -I tests/py/test_xc_bump_sw.py   (from the repository root). Works on a temporary copy; the real web/sw.js is not touched."""
import io
import os
import sys
import tempfile
from contextlib import redirect_stdout

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import bump_sw  # noqa: E402

fails = []


def chk(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)


real = open(os.path.join(ROOT, 'web', 'sw.js'), encoding='utf-8').read()
chk('the real service worker has a VERSION line of the form bos-sw-vN', bump_sw.current(real) >= 1)

new, old, nxt = bump_sw.bumped(real)
chk('the number goes up by exactly one', nxt == old + 1)
chk('only the VERSION line changes', new.replace(f"bos-sw-v{nxt}", f"bos-sw-v{old}") == real)
chk('the bumped file still has one VERSION line', len(bump_sw.LINE.findall(new)) == 1)

sample = "const VERSION = 'bos-sw-v7';\nself.addEventListener('install', () => {});\n"
d = tempfile.mkdtemp(prefix='xc_sw_')
p = os.path.join(d, 'sw.js')
open(p, 'w', encoding='utf-8').write(sample)
buf = io.StringIO()
with redirect_stdout(buf):
    bump_sw.main([], path=p)
chk('a dry run changes nothing', open(p, encoding='utf-8').read() == sample)
chk('a dry run says what it would do', 'bos-sw-v7 -> bos-sw-v8' in buf.getvalue())
with redirect_stdout(io.StringIO()):
    bump_sw.main(['--write'], path=p)
chk('--write bumps the file to v8 and keeps the rest', open(p, encoding='utf-8').read() == sample.replace('v7', 'v8'))

bad = os.path.join(d, 'bad.js')
open(bad, 'w', encoding='utf-8').write("const x = 1;\n")
refused = False
try:
    bump_sw.main([], path=bad)
except SystemExit:
    refused = True
chk('a file without a VERSION line is refused', refused)

print(f'RESULT: {"FAILED " + str(len(fails)) if fails else "ALL PASS"}')
sys.exit(1 if fails else 0)

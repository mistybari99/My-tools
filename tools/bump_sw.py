#!/usr/bin/env python3
"""Bump the service-worker cache version (web/sw.js: const VERSION = 'bos-sw-vN') so a deploy does not leave old screens in the phone cache.
Python 3 standard library only. Dry run by default: prints the change. Use --write to change the file.

Checklist (also in docs/integration/XC.md, section 'Service-worker version bump'):
  1. Run:  python3 tools/bump_sw.py            (prints current -> next; changes nothing)
  2. Run:  python3 tools/bump_sw.py --write     (changes web/sw.js only)
  3. Run:  python3 tests/py/test_xc_bump_sw.py  (the file is still valid and the number went up by exactly one)
  4. Commit web/sw.js together with the web change it ships.
Exit codes: 0 ok, 1 the VERSION line is missing or not in the form bos-sw-vN.
"""
import re
import sys
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SW = os.path.join(ROOT, 'web', 'sw.js')
LINE = re.compile(r"^const VERSION = 'bos-sw-v(\d+)';", re.M)


def current(text):
    m = LINE.search(text)
    if not m:
        raise SystemExit("web/sw.js: no line of the form const VERSION = 'bos-sw-vN';")
    return int(m.group(1))


def bumped(text):
    n = current(text)
    return LINE.sub(f"const VERSION = 'bos-sw-v{n + 1}';", text, count=1), n, n + 1


def main(argv=None, path=SW):
    argv = sys.argv[1:] if argv is None else argv
    text = open(path, encoding='utf-8').read()
    new, old, nxt = bumped(text)
    if '--write' in argv:
        open(path, 'w', encoding='utf-8').write(new)
        print(f'web/sw.js: bos-sw-v{old} -> bos-sw-v{nxt} (written)')
    else:
        print(f'DRY RUN. web/sw.js: bos-sw-v{old} -> bos-sw-v{nxt}. Run with --write to change the file.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

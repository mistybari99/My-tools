#!/usr/bin/env python3
"""Cost-free copy of the item seed file (item U-12, owner decision OD-15). Python 3 standard library only. Safe to run twice. Reads no secret and no database.

Why: docs say a cost price must never sit in a public copy of the repository. data/items_seed.csv has a cost_price column. Whether to remove it depends on a fact only the owner
has (is any copy of this repository public?). The repository copy is documented as PRIVATE (docs/SETUP.md); the public app repository is a different one. So NOTHING here
changes the seed file by itself. The owner decides, then runs the step below; every step can be undone.

  check                                   (default) says whether the seed file carries cost data (counts only, no value is printed). Exit 0 = no cost column, 1 = has costs.
  public-copy --out FILE                  writes a cost-free copy to FILE (any path except the seed itself). The seed is not touched. Use this for a public repository / a share.
  strip --private-costs FILE --owner-decision OD-15 [--apply]
                                          moves the costs out: writes them to FILE (which must be OUTSIDE this repository and must not exist yet) and rewrites the seed
                                          without the cost column. Without --apply it only says what it would do. It refuses to run without --owner-decision.
  restore --private-costs FILE [--apply]  puts the costs back from FILE: the seed becomes byte-for-byte what it was before strip. Without --apply it only says what it would do.

This does not remove cost prices from git HISTORY. That is a separate, owner-approved step: docs/HISTORY_CLEANUP_RUNBOOK.md and tools/make_clean_branch.sh (never rewrite the only copy).
Options for every command: --seed PATH (default data/items_seed.csv next to this tool).
"""
import argparse
import csv
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SEED = os.path.join(ROOT, 'data', 'items_seed.csv')
COST = 'cost_price'
KEY = ('product_name', 'category')


class SeedError(Exception):
    pass


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def parse(raw):
    text = raw.decode('utf-8')
    bom = text.startswith('﻿')
    if bom:
        text = text[1:]
    eol = '\r\n' if '\r\n' in text else '\n'
    rd = csv.reader(io.StringIO(text, newline=''))
    rows = list(rd)
    if not rows:
        raise SeedError('the seed file is empty')
    return rows, eol, bom, text.endswith(eol)


def render(rows, eol, bom, final_eol):
    buf = io.StringIO(newline='')
    w = csv.writer(buf, lineterminator=eol)
    w.writerows(rows)
    s = buf.getvalue()
    if not final_eol and s.endswith(eol):
        s = s[:-len(eol)]
    return (('﻿' if bom else '') + s).encode('utf-8')


def cost_state(path):
    rows, _, _, _ = parse(read_bytes(path))
    head = rows[0]
    if COST not in head:
        return {'has_column': False, 'rows': len(rows) - 1, 'with_cost': 0}
    i = head.index(COST)
    return {'has_column': True, 'rows': len(rows) - 1, 'with_cost': sum(1 for r in rows[1:] if len(r) > i and r[i].strip())}


def drop_column(rows):
    head = rows[0]
    if COST not in head:
        raise SeedError('there is no cost_price column to remove')
    i = head.index(COST)
    missing = [k for k in KEY if k not in head]
    if missing:
        raise SeedError('cannot key the rows: missing column ' + ', '.join(missing))
    ki = [head.index(k) for k in KEY]
    seen, costs = set(), []
    for r in rows[1:]:
        if len(r) != len(head):
            raise SeedError('a row has a different number of columns than the header (line not shown, it may hold a cost)')
        k = tuple(r[j] for j in ki)
        if k in seen:
            raise SeedError('two rows have the same product_name and category; cannot restore costs safely')
        seen.add(k)
        costs.append(list(k) + [r[i]])
    return [[c for j, c in enumerate(r) if j != i] for r in rows], [list(KEY) + [COST]] + costs, i


def inside_repo(path):
    p = os.path.realpath(path)
    return p == ROOT or p.startswith(ROOT + os.sep)


def cmd_check(a):
    st = cost_state(a.seed)
    if st['has_column']:
        print(f"seed has a cost_price column: {st['with_cost']} of {st['rows']} rows carry a cost (values are not printed)")
        print('If any copy of this repository is public, the owner decides to run: strip --owner-decision OD-15 (see --help); history cleanup is separate.')
        return 1
    print(f"seed has no cost_price column ({st['rows']} rows): OK")
    return 0


def cmd_public_copy(a):
    if os.path.realpath(a.out) == os.path.realpath(a.seed):
        raise SeedError('--out must not be the seed file itself')
    rows, eol, bom, fe = parse(read_bytes(a.seed))
    if COST not in rows[0]:
        public = render(rows, eol, bom, fe)
    else:
        i = rows[0].index(COST)
        public = render([[c for j, c in enumerate(r) if j != i] for r in rows], eol, bom, fe)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'wb') as f:
        f.write(public)
    print(f'wrote the cost-free copy: {a.out} (the seed file was not changed)')
    return 0


def cmd_strip(a):
    if a.owner_decision != 'OD-15':
        raise SeedError('refused: the owner decision is missing. Pass --owner-decision OD-15 only after the owner has said yes (docs/UNIFIED_BUILD_PLAN.md section 5, item 15).')
    if not a.private_costs:
        raise SeedError('--private-costs FILE is required (a place outside this repository where the costs are kept)')
    if inside_repo(a.private_costs):
        raise SeedError('refused: --private-costs must be OUTSIDE this repository (a cost file inside it would defeat the purpose)')
    if os.path.exists(a.private_costs):
        raise SeedError('refused: --private-costs already exists (nothing is overwritten)')
    raw = read_bytes(a.seed)
    rows, eol, bom, fe = parse(raw)
    if COST not in rows[0]:
        print('the seed file has no cost_price column: nothing to do')
        return 0
    stripped, costs, _ = drop_column(rows)
    n = sum(1 for c in costs[1:] if c[2].strip())
    if not a.apply:
        print(f'DRY RUN: would move {n} cost values (of {len(costs) - 1} rows) to {a.private_costs} and remove the cost_price column from {a.seed}. Add --apply to do it.')
        return 0
    os.makedirs(os.path.dirname(os.path.abspath(a.private_costs)), exist_ok=True)
    with open(a.private_costs, 'wb') as f:
        f.write(render(costs, eol, bom, fe))
    try:
        os.chmod(a.private_costs, 0o600)
    except OSError:
        pass
    with open(a.seed, 'wb') as f:
        f.write(render(stripped, eol, bom, fe))
    print(f'done: {n} cost values saved to {a.private_costs}; the seed file no longer has a cost column. Keep that file private. Undo: restore --private-costs.')
    return 0


def cmd_restore(a):
    if not a.private_costs or not os.path.isfile(a.private_costs):
        raise SeedError('--private-costs FILE must exist')
    rows, eol, bom, fe = parse(read_bytes(a.seed))
    if COST in rows[0]:
        raise SeedError('the seed file already has a cost_price column: nothing to restore')
    crow, _, _, _ = parse(read_bytes(a.private_costs))
    if crow[0] != list(KEY) + [COST]:
        raise SeedError('the private costs file has an unexpected header')
    costs = {(r[0], r[1]): r[2] for r in crow[1:]}
    head = rows[0]
    missing = [k for k in KEY if k not in head]
    if missing:
        raise SeedError('cannot key the rows: missing column ' + ', '.join(missing))
    ki = [head.index(k) for k in KEY]
    pos = head.index('selling_price') + 1 if 'selling_price' in head else len(head)
    out = [head[:pos] + [COST] + head[pos:]]
    for r in rows[1:]:
        if len(r) != len(head):
            raise SeedError('a seed row has a different number of columns than the header; restore refused, nothing written')
        k = tuple(r[j] for j in ki)
        if k not in costs:
            raise SeedError('a seed row has no matching entry in the private costs file (the seed changed since strip); restore refused, nothing written')
        out.append(r[:pos] + [costs[k]] + r[pos:])
    if len(costs) != len(rows) - 1:
        raise SeedError('the private costs file has a different number of rows than the seed; restore refused, nothing written')
    if not a.apply:
        print(f'DRY RUN: would put {len(costs)} cost values back into {a.seed}. Add --apply to do it.')
        return 0
    with open(a.seed, 'wb') as f:
        f.write(render(out, eol, bom, fe))
    print(f'done: {len(costs)} cost values restored into {a.seed}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--seed', default=SEED)
    sub = ap.add_subparsers(dest='cmd')
    sub.add_parser('check')
    p = sub.add_parser('public-copy')
    p.add_argument('--out', required=True)
    s = sub.add_parser('strip')
    s.add_argument('--private-costs')
    s.add_argument('--owner-decision')
    s.add_argument('--apply', action='store_true')
    r = sub.add_parser('restore')
    r.add_argument('--private-costs')
    r.add_argument('--apply', action='store_true')
    a = ap.parse_args(argv)
    try:
        return {None: cmd_check, 'check': cmd_check, 'public-copy': cmd_public_copy, 'strip': cmd_strip, 'restore': cmd_restore}[a.cmd](a)
    except SeedError as e:
        print('refused:', e, file=sys.stderr)
        return 2
    except (OSError, UnicodeDecodeError, csv.Error) as e:
        print('could not run:', type(e).__name__, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

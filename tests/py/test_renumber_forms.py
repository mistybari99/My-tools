"""S1: tools/renumber.py expresses the per-code form mapping of docs/FORM_SEQUENCE.md and has the guards.
Run: python3 -I tests/py/test_renumber_forms.py   (from the repository root). Writes nothing to the repository:
the applied-marker test uses a temporary folder."""
import json
import os
import re
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import renumber as rn  # noqa: E402

fails = []


def chk(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)


data, map_problems = rn.load_map()
rows = data['form_codes']
fm = rn.form_map_of(data)

# 1. the map file is valid and complete
chk('numbering map loads with no problems ' + str(map_problems), not map_problems)
chk('41 sorted rows plus the fixed 0-1 row', len([r for r in rows if r.get('sort')]) == 41 and len(rows) == 42)

# 2. the map equals the table in docs/FORM_SEQUENCE.md (the rule file)
seq = open(os.path.join(ROOT, 'docs', 'FORM_SEQUENCE.md'), encoding='utf-8').read()
table = [re.match(r'^\| (\d+) \| ([^|]+?) \| ([^|]+?) \| (\d{2}-\d) \| (\d{2}-\d) \|$', l) for l in seq.splitlines()]
table = [(int(m.group(1)), m.group(4), m.group(5), m.group(2).strip()) for m in table if m]
by_sort = {r['sort']: r for r in rows if r.get('sort')}
chk('FORM_SEQUENCE.md table has 41 rows', len(table) == 41)
chk('map old/new/sort/English name equal the FORM_SEQUENCE.md table',
    all(by_sort[n]['old'] == old and by_sort[n]['new'] == new and by_sort[n]['en'] == en for n, old, new, en in table))

# 3. the rule itself: A-Z by English name, NN-1 with NN = sort
chk('new code is NN-1 with NN = sort number', all(r['new'] == f"{r['sort']:02d}-1" for r in rows if r.get('sort')))
names = [by_sort[n]['en'].lower() for n in sorted(by_sort)]
chk('A-Z by English short name', names == sorted(names))

# 4. the checker itself refuses a broken map
bad = [dict(r) for r in rows]
bad[3]['new'] = '99-1'
chk('a wrong new code is refused', any('must map' in p for p in rn.check_form_codes(bad)))
swap = [dict(r) for r in rows]
swap[0], swap[1] = swap[1], swap[0]
chk('a map not in A-Z order is refused', any('A-Z' in p for p in rn.check_form_codes(swap)))
dup = [dict(r) for r in rows]
dup[5]['new'] = dup[4]['new']
chk('a duplicate new code is refused', any('appears twice' in p or 'must map' in p for p in rn.check_form_codes(dup)))
noname = [dict(r) for r in rows]
noname[2]['bn'] = ''
chk('a row with no Bangla short name is refused', any('Bangla' in p for p in rn.check_form_codes(noname)))

# 5. one pass: a chain never happens (02-4 -> 01-1 is not mapped again to 40-1; 01-1 -> 40-1 stays)
chk('02-4 maps to 01-1 once', rn.transform('form 02-4', {}, fm)[0] == 'form 01-1')
chk('a line with 02-4 and 01-1 maps both in one pass', rn.transform('02-4 and 01-1', {}, fm)[0] == '01-1 and 40-1')
chk('the fixed 0-1 is never changed', rn.transform('0-1 Location', {}, fm)[0] == '0-1 Location')
chk('a code inside a larger number is not a form code', rn.transform('x 10-12 2026-10-1 10-1-2026 v10-1 1.10-1', {}, fm)[0]
    == 'x 10-12 2026-10-1 10-1-2026 v10-1 1.10-1')
chk('a code in quotes is changed', rn.transform("'10-2' and \"20-1\"", {}, fm)[0] == "'11-1' and \"05-1\"")
chk('a form code written with Bangla digits maps too, in Bangla digits', rn.transform('দিন (১৪-১)', {}, fm)[0] == 'দিন (০৬-১)')
chk('a Bangla-digit number that is not a form code is not changed', rn.transform('১০-১২', {}, fm)[0] == '১০-১২')
chk('internal ids with a code are not changed by the form mapping', rn.transform("f04_1 form_20_4", {}, fm)[0] == "f04_1 form_20_4")

# 6. row guard: an unknown form-shaped code on a table or quoted row is flagged; known codes and non-form numbers are not
lines = ['| 02-4 | Appointment |\n', "x = ['14-0', '07-9', '10-2']\n", 'plain 07-9 prose\n']
known = rn.known_form_codes(data)
flagged = rn.unmapped_row_codes(lines, known)
chk('an unknown code on a row is flagged', flagged == [(2, '07-9')])
chk('14-0 (not a form shape) is not flagged', all(t != '14-0' for _, t in flagged))
chk('prose outside a row is not flagged', all(i != 3 for i, _ in flagged))

# 7. applied marker: a second apply is refused
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, 'tools'))
    chk('no marker: apply allowed', rn.marker_problem(tmp) is None)
    with open(os.path.join(tmp, rn.MARKER_REL), 'w', encoding='utf-8') as fh:
        json.dump({'applied_on': '2026-10-21', 'mapping_sha256': rn.mapping_sha(data)}, fh)
    msg = rn.marker_problem(tmp)
    chk('marker present: second apply refused', msg is not None and 'second apply' in msg)

# 8. the mapping hash changes when a code changes (the marker names the mapping it applied)
alt = json.loads(json.dumps(data))
alt['form_codes'][1]['new'] = '77-1'
chk('mapping hash changes with the mapping', rn.mapping_sha(alt) != rn.mapping_sha(data))

print(f'assert failures: {len(fails)}')
sys.exit(1 if fails else 0)

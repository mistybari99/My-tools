#!/usr/bin/env python3
"""Checks of the item-master import files. Run:  python3 tests/py/test_item_import.py
 1. supabase/phase14_import.sql has exactly 1312 dictionary rows (in each of its two parts), codes unique, same as data/item_dictionary.csv
 2. web/data/item_dictionary.json matches the CSV; no price or cost field anywhere in the public JSON files
 3. seed_item_mapping.csv: 57 rows, one per seed item, confidence in [0,1]
 4. (needs the local Postgres on 5544) builds a scratch db, loads the 57 seed items, runs PART 1 (writes nothing), PART 2 (guard refuses, then after the switch creates 1312, twice = no change)"""
import csv, json, os, re, subprocess, sys, unittest
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = lambda *a: os.path.join(root, *a)
rows = list(csv.DictReader(open(P('data', 'item_dictionary.csv'), encoding='utf-8')))
sql = open(P('supabase', 'phase14_import.sql'), encoding='utf-8').read()
part1, part2 = sql.split('-- ======================== PART 2')
code_re = re.compile(r"^\('(\d\d-\d{3})', '", re.M)

class Files(unittest.TestCase):
    def test_row_count_and_unique(self):
        for name, part in (('part1', part1), ('part2', part2)):
            codes = code_re.findall(part)
            self.assertEqual(len(codes), 1312, name)
            self.assertEqual(len(set(codes)), 1312, name + ' unique')
            self.assertEqual(sorted(codes), sorted(r['code'] for r in rows), name + ' = csv')
    def test_csv(self):
        self.assertEqual(len(rows), 1312); self.assertEqual(len({r['code'] for r in rows}), 1312)
        self.assertEqual(sum(1 for r in rows if r['name_en'].startswith('RETIRED')), 7)
    def test_json_matches(self):
        j = json.load(open(P('web', 'data', 'item_dictionary.json'), encoding='utf-8'))
        self.assertEqual([x['code'] for x in j], [r['code'] for r in rows])
        for f in ('web/data/item_dictionary.json', 'web/data/seed_item_mapping.json'):
            keys = {k for x in json.load(open(P(f), encoding='utf-8')) for k in x}
            self.assertFalse([k for k in keys if re.search(r'price|cost', k, re.I)], f + ' has a price/cost key: ' + str(keys))
    def test_mapping(self):
        m = list(csv.DictReader(open(P('docs', 'inputs', 'seed_item_mapping.csv'), encoding='utf-8')))
        self.assertEqual(len(m), 57); self.assertEqual(len({r['seed_code'] for r in m}), 57)
        self.assertTrue(all(0 <= float(r['confidence']) <= 1 for r in m))
        self.assertTrue(all(r['auto'] in ('0', '1') for r in m))
    def test_guard_and_switch_text(self):
        self.assertIn("item_master_apply_ok", part2); self.assertIn('on conflict (code) do nothing', part2)
        body = '\n'.join(l for l in part1.split('\n') if not l.lstrip().startswith('--')).lower()
        for w in ('insert into', 'update public.', 'delete from', 'create table', 'alter table', 'drop '):
            self.assertNotIn(w, body)

def psql(db, args, input_=None):
    return subprocess.run(['psql', '-h', '/tmp', '-p', '5544', '-U', 'postgres', '-d', db, '-qAt', '-v', 'ON_ERROR_STOP=0'] + args, capture_output=True, text=True, input=input_)

@unittest.skipUnless(os.path.exists('/tmp/.s.PGSQL.5544'), 'local postgres not running')
class Db(unittest.TestCase):
    def test_import_on_scratch_db(self):
        db = 'p14_pytest'
        b = subprocess.run(['bash', P('tests', 'sql', 'build_fresh_db.sh'), db], env=dict(os.environ, ORDER='phase8 phase9 phase10 phase11 phase12 phase13 phase14'), capture_output=True, text=True)
        self.assertIn('built', b.stdout, b.stdout + b.stderr)
        n0 = psql(db, ['-c', 'select count(*) from items']).stdout.strip(); self.assertEqual(n0, '57')
        r = psql(db, ['-f', P('supabase', 'phase14_import.sql')]); self.assertIn('1312', r.stdout.split('\n')[0] + r.stdout[:200])           # PART 1 printed the file row count first
        self.assertEqual(psql(db, ['-c', 'select count(*) from items']).stdout.strip(), '57')                                           # nothing written: the guard stopped PART 2
        psql(db, ['-c', "update public.rules set value = 'true'::jsonb where key = 'item_master_apply_ok'"])
        psql(db, ['-f', P('supabase', 'phase14_import.sql')])
        self.assertEqual(psql(db, ['-c', 'select count(*) from items where import_batch is not null']).stdout.strip(), '1312')
        self.assertEqual(psql(db, ['-c', 'select count(*) from items where import_batch is not null and not is_active']).stdout.strip(), '7')
        self.assertEqual(psql(db, ['-c', 'select count(*) from items where sell_price is not null and import_batch is not null']).stdout.strip(), '0')
        psql(db, ['-f', P('supabase', 'phase14_import.sql')])
        self.assertEqual(psql(db, ['-c', 'select count(*) from items']).stdout.strip(), str(57 + 1312))
        self.assertEqual(psql(db, ['-c', "select count(*) from audit_log where action='import'"]).stdout.strip(), '1')
        self.assertEqual(psql(db, ['-c', "select sum(sell_price) from items where code like 'I-%'"]).stdout.strip(), psql(db, ['-c', "select sum(sell_price) from items where import_batch is null"]).stdout.strip())

if __name__ == '__main__':
    unittest.main(verbosity=2)

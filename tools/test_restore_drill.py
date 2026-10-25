#!/usr/bin/env python3
"""Tests for tools/restore_drill.py. Unit tests need nothing; the real end-to-end tests need the local Postgres (default: psql -h /tmp -p 5544 -U postgres, set BOS_PG_CMD
to change) and the repo's supabase/*.sql files: they build a template database with every phase, seed one copy, take a backup of it with the REAL tools/backup_dump.py
(through the real backup_manifest / backup_dump SQL functions), restore it into a second copy named *scratch* and check the PASS / FAIL report.

    python3 -m unittest tools/test_restore_drill.py -v
Database names used: p70drill_tpl, p70drill_src, p70drill_scratch (dropped and re-created each run).
"""
import contextlib
import gzip
import io
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import backup_dump  # noqa: E402
import ops_common as oc  # noqa: E402
import restore_drill as rd  # noqa: E402

PG = shlex.split(os.environ.get('BOS_PG_CMD', 'psql -h /tmp -p 5544 -U postgres'))
ORDER = ('phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 '
         'phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70')
OWNER, BOT = '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b0'
SEED = f"""
insert into auth.users (id,email,raw_user_meta_data) values ('{OWNER}','owner1@s.app','{{"full_name":"Owner"}}'),('{BOT}','bot@s.app','{{}}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('{OWNER}','owner') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('T1','T1','T1','kg','kg','raw_material',true,0);
select set_config('request.jwt.claim.sub','{OWNER}',false);
select stock_opening((select id from items where code='T1'), 1, 100, 10, null, 'seed');
select stock_issue((select id from items where code='T1'), 1, 3, null, 'x');
begin;
insert into journal_entries (entry_date, source_type, source_id, memo) values (current_date,'test','1','m');
insert into journal_lines select (select max(id) from journal_entries),1,(select min(id) from coa_accounts),100,0;
insert into journal_lines select (select max(id) from journal_entries),2,(select max(id) from coa_accounts),0,100;
commit;
insert into ops_accounts (user_id,purpose) values ('{BOT}','backup');
"""


def psql(db, sql=None, file=None, check=True):
    cmd = PG + ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db] + (['-c', sql] if sql is not None else ['-f', file])
    p = subprocess.run(cmd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(p.stderr[:800])
    return p.stdout


def pg_available():
    try:
        return subprocess.run(PG + ['-X', '-q', '-At', '-d', 'postgres', '-c', 'select 1'], capture_output=True, text=True, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def lit(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (dict, list)):
        return "'" + json.dumps(v).replace("'", "''") + "'::jsonb"
    return "'" + str(v).replace("'", "''") + "'"


class PgApi:
    """Same interface as ops_common.Api.rpc but calls the SQL function straight in the local DB as the ops bot (no HTTP)."""

    def __init__(self, db, uid):
        self.db, self.uid = db, uid

    def rpc(self, fn, args=None):
        a = ', '.join(f'{k} => {lit(v)}' for k, v in (args or {}).items())
        out = psql(self.db, f"with s as (select set_config('request.jwt.claim.sub','{self.uid}',false)) select public.{fn}({a})::text from s")
        return oc.loads_exact(out.strip()) if out.strip() else None


def dsn(db):
    return f'postgresql://postgres@/{db}?host=/tmp&port=5544'


def dropdb(name):
    psql('postgres', f'drop database if exists {name}')


class Unit(unittest.TestCase):
    def test_refuses_remote_and_non_scratch(self):
        bad = ['postgresql://postgres:pw@db.abcdefgh.supabase.co:5432/postgres', 'postgresql://u@aws-0-eu.pooler.supabase.com:6543/scratch',
               'postgresql://u@10.0.0.5/bos_scratch', 'postgresql://u@example.com/bos_scratch', 'postgresql://u@localhost/postgres', 'postgresql://u@localhost/bos',
               'postgresql://u@localhost/', 'host=db.x.supabase.co dbname=scratch', 'host=localhost dbname=production', '', 'postgresql://u@localhost,example.com/scratch',
               'postgresql://u@localhost/bos_scratch?host=example.com', 'postgresql://u@/prod?host=/tmp']
        for d in bad:
            with self.assertRaises(rd.Refused, msg=d):
                rd.check_target(d)

    def test_accepts_local_scratch(self):
        for d, h in [('postgresql://postgres@localhost:5432/bos_scratch', 'localhost'), ('postgresql://postgres@127.0.0.1/Scratch1', '127.0.0.1'),
                     ('postgresql://postgres@[::1]/x_scratch', '::1'), ('postgresql://postgres@/p70scratch?host=/tmp&port=5544', '/tmp'),
                     ('host=/tmp port=5544 dbname=my_scratch user=postgres', '/tmp'), ("host=localhost dbname='bos_scratch'", 'localhost')]:
            self.assertEqual(rd.check_target(d)[0], h, d)

    def test_main_refuses_without_touching_anything(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = rd.main(['/nonexistent', '--dsn', 'postgresql://postgres@db.x.supabase.co/postgres'])
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(buf.getvalue())['result'], 'REFUSED')

    def test_newest_backup(self):
        with tempfile.TemporaryDirectory() as d:
            for name, fin in [('a', '2026-01-01T00:00:00Z'), ('b', '2026-03-01T00:00:00Z'), ('c', '2026-02-01T00:00:00Z')]:
                os.makedirs(os.path.join(d, name))
                with open(os.path.join(d, name, 'manifest.json'), 'w') as f:
                    json.dump({'finished_at': fin, 'tables': {}}, f)
            os.makedirs(os.path.join(d, 'junk'))
            self.assertEqual(os.path.basename(rd.newest_backup(d)), 'b')
            self.assertEqual(rd.newest_backup(os.path.join(d, 'c')), os.path.join(d, 'c'))
        with tempfile.TemporaryDirectory() as d, self.assertRaises(rd.Refused):
            rd.newest_backup(d)


@unittest.skipUnless(pg_available() and os.path.isfile(os.path.join(ROOT, 'tests/sql/build_fresh_db.sh')), 'local Postgres (port 5544) not available')
class EndToEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        env = dict(os.environ, ORDER=ORDER)
        r = subprocess.run(['bash', os.path.join(ROOT, 'tests/sql/build_fresh_db.sh'), 'p70drill_tpl'], capture_output=True, text=True, env=env)
        assert 'built p70drill_tpl' in r.stdout, r.stdout[-800:] + r.stderr[-800:]
        for n in ('p70drill_src', 'p70drill_scratch'):
            dropdb(n)
            psql('postgres', f'create database {n} template p70drill_tpl')
        psql('p70drill_src', SEED)
        cls.tmp = tempfile.mkdtemp()
        cls.bk = os.path.join(cls.tmp, 'backups', 'run1')
        cls.manifest = backup_dump.run(PgApi('p70drill_src', BOT), cls.bk, page=50, log_run=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)
        for n in ('p70drill_src', 'p70drill_scratch', 'p70drill_tpl'):
            dropdb(n)

    def drill(self, **kw):
        return rd.run_drill(kw.pop('backup', self.bk), dsn(kw.pop('db', 'p70drill_scratch')), ' '.join(PG[:1] + PG[1:]), log=lambda *a: None, **kw)

    def check(self, rep, name):
        return next(c for c in rep['checks'] if c['name'] == name)

    def test_1_backup_has_data_and_is_the_real_format(self):
        self.assertGreater(self.manifest['table_count'], 100)
        self.assertEqual(self.manifest['tables']['journal_lines']['rows'], 2)
        self.assertEqual(self.manifest['tables']['stock_ledger']['rows'], 2)
        self.assertIn('assistant_usage', self.manifest['tables'])           # phase70 stopped hiding it
        self.assertNotIn('attendance_devices', self.manifest['tables'])
        self.assertEqual(psql('p70drill_src', 'select status from backup_runs order by id desc limit 1').strip(), 'ok')

    def test_2_full_drill_passes(self):
        rep = self.drill(backup=os.path.dirname(self.bk))                   # a folder of backups: the newest is picked
        bad = [c for c in rep['checks'] if not c['ok']]
        self.assertEqual(rep['result'], 'PASS', json.dumps(bad, default=str)[:1500])
        self.assertEqual([c['name'] for c in rep['checks']], ['backup_intact', 'restore', 'tables_list', 'functions', 'rls', 'row_counts', 'journal', 'stock'])
        self.assertTrue(rep['tables_ok'] and rep['rows_ok'])
        self.assertEqual(rep['record_hint']['p_result'], 'pass')
        self.assertEqual(rep['backup']['name'], 'run1')
        self.assertEqual(self.check(rep, 'journal')['detail']['unbalanced_entries'], 0)
        self.assertEqual(self.check(rep, 'stock')['detail']['mismatch'], 0)
        skipped = {s['table']: s['reason'] for s in rep['skipped_by_dump']}
        self.assertIn('token_hash', skipped['attendance_devices'])
        self.assertIn('ops_accounts', skipped)
        self.assertIn('backup_runs', skipped)
        json.dumps(rep, default=str)
        self.assertEqual(psql('p70drill_scratch', 'select count(*) from journal_lines').strip(), '2')

    def test_3_cli_prints_json_and_exit_code(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = rd.main([self.bk, '--dsn', dsn('p70drill_scratch'), '--psql', ' '.join(PG)])   # with the restore: stdout must still be pure JSON
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(buf.getvalue())['result'], 'PASS')

    def test_4_damaged_backup_is_refused(self):
        d = os.path.join(self.tmp, 'bad')
        shutil.copytree(self.bk, d)
        with open(os.path.join(d, 'items.ndjson.gz'), 'ab') as f:
            f.write(b'x')
        rep = self.drill(backup=d)
        self.assertEqual(rep['result'], 'FAIL')
        self.assertFalse(self.check(rep, 'backup_intact')['ok'])

    def test_5_each_failure_is_detected(self):
        self.drill()                                                          # start from a good restored copy
        rep = None
        steps = [
            ('row_counts', "set session_replication_role = replica; delete from items", None),
            ('journal', "set session_replication_role = replica; update journal_lines set credit = 90 where line_no = 2", None),
            ('stock', "set session_replication_role = replica; update stock_balance set qty = qty + 1", None),
            ('rls', "alter table public.items disable row level security", None),
            ('functions', "drop function public.backup_log(text, jsonb, timestamptz, int, bigint, bigint, text)", None),
        ]
        for name, sql, _ in steps:
            self.drill()                                                      # restore again: clean copy
            psql('p70drill_scratch', sql)
            rep = self.drill(restore=False)
            self.assertEqual(rep['result'], 'FAIL', name)
            self.assertFalse(self.check(rep, name)['ok'], name)
            if name == 'row_counts':
                self.assertIn('items', self.check(rep, name)['detail']['different'])
            if name == 'rls':
                self.assertEqual(self.check(rep, name)['detail']['without_rls'], ['items'])
            psql('p70drill_scratch', "alter table public.items enable row level security")
        rep = self.drill()                                                    # a restore repairs a scratch copy except the dropped function
        self.assertFalse(self.check(rep, 'functions')['ok'])
        self.assertTrue(self.check(rep, 'row_counts')['ok'])

    def edited_copy(self, name, fn):
        d = os.path.join(self.tmp, name)
        shutil.copytree(self.bk, d)
        path = os.path.join(d, 'manifest.json')
        with open(path) as f:
            m = json.load(f)
        fn(m)
        with open(path, 'w') as f:
            json.dump(m, f)
        return d

    def test_6_table_list_mismatch(self):
        def drop(m):
            del m['tables']['stock_wastage']
        rep = self.drill(backup=self.edited_copy('short', drop))               # the dump silently omitted an expected table
        self.assertEqual(rep['result'], 'FAIL')
        self.assertEqual(self.check(rep, 'tables_list')['detail']['missing_from_backup'], ['stock_wastage'])

        def ghost(m):
            m['tables']['ghost_table'] = dict(m['tables']['items'])
        rep = self.drill(backup=self.edited_copy('extra', ghost))              # the manifest lists a table the schema does not have
        self.assertEqual(rep['result'], 'FAIL')
        self.assertTrue(any(not c['ok'] for c in rep['checks']))

    def test_7_refuses_a_database_without_the_schema_or_not_scratch(self):
        psql('postgres', 'drop database if exists p70drill_emptyscratch')
        psql('postgres', 'create database p70drill_emptyscratch')
        try:
            with self.assertRaises(rd.Refused):
                self.drill(db='p70drill_emptyscratch')
        finally:
            dropdb('p70drill_emptyscratch')
        with self.assertRaises(rd.Refused):
            self.drill(db='p70drill_src')                                     # a real-looking (non scratch) name: refused before connecting
        self.assertEqual(psql('p70drill_src', 'select count(*) from journal_lines').strip(), '2')


if __name__ == '__main__':
    unittest.main(verbosity=2)

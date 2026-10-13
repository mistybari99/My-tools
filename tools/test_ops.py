#!/usr/bin/env python3
"""Unit tests for the ops scripts against a FAKE local Supabase (HTTP server in a thread) and a stub SMTP server. No network, no real secrets.

    python3 -m unittest tools/test_ops.py -v        (or: python3 tools/test_ops.py)

Optional end-to-end restore test on a real local Postgres: set BOS_PG_RESTORE_DB (an empty db that already has the app tables; see docs/OPS_SETUP.md) and
BOS_PG_CMD (default "psql -h /tmp -p 5544 -U postgres").
"""
import contextlib
import gzip
import hashlib
import io
import json
import os
import shlex
import socketserver
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backup_dump  # noqa: E402
import backup_photos  # noqa: E402
import notify_digest  # noqa: E402
import ops_common as oc  # noqa: E402
import restore_backup  # noqa: E402

PASSWORD = 'S3cret-Bot-Passw0rd'
ANON = 'anon-public-key-for-tests'
FAKE_JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJib3QifQ.c2lnbmF0dXJlMTIzNDU2'


class Fake:
    """State of the fake Supabase."""

    def __init__(self):
        self.tables = {'customers': [{'id': i, 'name': 'C%d' % i} for i in range(1, 12)],
                       'sales': [{'id': 'a%02d' % i, 'total': i * 10} for i in range(1, 6)],
                       'notes': []}
        self.fail = {}                 # rpc name -> list of status codes to return before succeeding
        self.always = {}               # rpc name -> (status, body) every time
        self.hooks = {}                # rpc name -> callable(args) -> result
        self.calls = []                # (path, args, headers)
        self.logins = 0
        self.log_rows = []
        self.bad_login = False
        self.drop_rows = None          # table -> number of rows to hide in backup_dump
        self.loop_cursor = False
        self.storage = {}              # path -> bytes
        self.unauth_once = False
        self.digest = None
        self.alerts = []
        self.cfg = {'email_on': True, 'digest_times': '08,21', 'now_hour': '08'}


def make_handler(F):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code, obj, raw=None):
            b = raw if raw is not None else json.dumps(obj).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_GET(self):
            F.calls.append((self.path, None, dict(self.headers)))
            p = self.path.split('/storage/v1/object/authenticated/photos/', 1)
            if len(p) == 2 and p[1] in F.storage:
                return self._send(200, None, raw=F.storage[p[1]])
            self._send(404, {'message': 'not found'})

        def do_POST(self):
            n = int(self.headers.get('Content-Length') or 0)
            body = json.loads(self.rfile.read(n) or b'{}')
            F.calls.append((self.path, body, dict(self.headers)))
            if self.path.startswith('/auth/v1/token'):
                F.logins += 1
                if F.bad_login or body.get('password') != PASSWORD:
                    return self._send(400, {'error': 'invalid_grant', 'echo': body.get('password')})
                return self._send(200, {'access_token': FAKE_JWT})
            if self.path.startswith('/storage/v1/object/list/photos'):
                pre = body.get('prefix') or ''
                seen, out = set(), []
                for path, data in sorted(F.storage.items()):
                    if pre and not path.startswith(pre + '/'):
                        continue
                    rest = path[len(pre) + 1:] if pre else path
                    if '/' in rest:
                        d = rest.split('/')[0]
                        if d not in seen:
                            seen.add(d)
                            out.append({'name': d, 'id': None})
                    else:
                        out.append({'name': rest, 'id': 'id-' + rest, 'metadata': {'size': len(data)}})
                return self._send(200, out)
            if not self.path.startswith('/rest/v1/rpc/'):
                return self._send(404, {'message': 'nope'})
            fn = self.path.rsplit('/', 1)[1]
            if self.headers.get('Authorization') != 'Bearer ' + FAKE_JWT or self.headers.get('apikey') != ANON:
                return self._send(401, {'message': 'JWT expired'})
            if F.unauth_once:
                F.unauth_once = False
                return self._send(401, {'message': 'JWT expired'})
            if F.always.get(fn):
                code, msg = F.always[fn]
                return self._send(code, {'message': msg})
            if F.fail.get(fn):
                return self._send(F.fail[fn].pop(0), {'message': 'upstream trouble ' + PASSWORD})
            if fn in F.hooks:
                res = F.hooks[fn](body)
                return self._send(200, None, raw=res) if isinstance(res, bytes) else self._send(200, res)
            if fn == 'backup_manifest':
                return self._send(200, {'schema_version': 46, 'fingerprint': 'f' * 32, 'tables': [{'name': t, 'rows': len(r)} for t, r in sorted(F.tables.items())]})
            if fn == 'backup_dump':
                rows = [r for r in F.tables[body['p_table']]]
                if F.drop_rows and body['p_table'] in F.drop_rows:
                    rows = rows[:-F.drop_rows[body['p_table']]]
                after = body.get('p_after_id')
                if after is not None:
                    rows = [r for r in rows if str(r['id']) > json.loads(after)[0]] if isinstance(rows[0]['id'], str) else [r for r in rows if r['id'] > json.loads(after)[0]]
                lim = body['p_limit']
                page = rows[:lim]
                nxt = json.dumps([page[-1]['id']]) if len(rows) > lim or (F.loop_cursor and page) else None
                if F.loop_cursor and page:
                    nxt = json.dumps([rows[0]['id']]) if after is not None else nxt
                return self._send(200, {'table': body['p_table'], 'rows': page, 'next': nxt, 'total': len(F.tables[body['p_table']])})
            if fn == 'backup_log':
                F.log_rows.append(body)
                return self._send(200, len(F.log_rows))
            if fn == 'notify_config':
                return self._send(200, F.cfg)
            if fn == 'notify_scan':
                return self._send(200, {'created': 2, 'kinds': {}})
            if fn == 'urgent_alerts':
                return self._send(200, F.alerts)
            if fn == 'notifications_mark_emailed':
                return self._send(200, len(body['p_ids']))
            if fn == 'daily_digest':
                d = dict(F.digest)
                d['date'] = body.get('p_date')
                return self._send(200, d)
            return self._send(404, {'message': 'unknown rpc ' + fn})
    return H


class FakeServer:
    def __enter__(self):
        self.F = Fake()
        self.srv = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.F))
        self.t = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.t.start()
        self.url = 'http://127.0.0.1:%d' % self.srv.server_address[1]
        return self

    def __exit__(self, *a):
        self.srv.shutdown()
        self.srv.server_close()

    def api(self, sleeps=None, retries=4):
        sl = sleeps if sleeps is not None else []
        a = oc.Api(self.url, ANON, retries=retries, backoff=1.0, sleep=sl.append)
        a.login('bot@example.com', PASSWORD)
        return a


def slurp(path, mode='rb', **kw):
    with open(path, mode, **kw) as f:
        return f.read()


def read_ndjson(path):
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        return [json.loads(x) for x in f if x.strip()]


DIGEST = {
    'generated_at': 'x', 'sales': {'today': {'net': 1300, 'bills': 2, 'total': 1500}, 'yesterday': {'net': 650}, 'last_week': {'net': 2600}, 'vs_yesterday_pct': 100.0, 'vs_last_week_pct': -50.0,
                                   'by_location': [{'location_id': 1, 'name_bn': 'মেইন', 'name_en': 'Main <b>', 'net': 1300}]},
    'top_items': [{'name': 'Rasgulla', 'qty': 3, 'amount': 900}], 'cash': {'short': 800, 'over': 0}, 'collections': 250,
    'dues': {'customers_total': 250, 'customers': 1, 'suppliers': {'payable': 5000, 'overdue': 5000}}, 'wastage': {'count': 1, 'value': 2000},
    'voids_discounts': {'void_count': 1, 'void_total': 300, 'discount_count': 1, 'discount_total': 50}, 'exceptions_open': {'red': 1, 'yellow': 1}, 'approvals_pending': 1,
    'stock_alerts': {'low_items': 1, 'expiring_batches': 1}, 'day_close': [{'name_bn': 'মেইন', 'name_en': 'Main', 'closed': False, 'mode': 'app'}, {'name_bn': 'শাখা', 'name_en': 'Branch', 'closed': True, 'mode': 'app'}],
    'backup': {'stale': True, 'age_hours': 40.0},
}
ALERTS = [{'id': 14, 'kind': 'red_exceptions', 'title_bn': '৩টি লাল এক্সেপশন', 'title_en': '3 red <script>alert(1)</script>', 'body_bn': 'বডি', 'body_en': 'body'},
          {'id': 15, 'kind': 'backup_stale', 'title_bn': 'ব্যাকআপ পুরনো', 'title_en': 'Backup is out of date', 'body_bn': None, 'body_en': None}]


class Quiet:
    """Captures stderr so tests can assert that no secret was printed."""

    def __enter__(self):
        self.buf = io.StringIO()
        self.cm = contextlib.redirect_stderr(self.buf)
        self.cm.__enter__()
        return self

    def __exit__(self, *a):
        self.cm.__exit__(*a)

    @property
    def text(self):
        return self.buf.getvalue()


class BackupTests(unittest.TestCase):
    def test_full_backup_files_manifest_and_log(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            with Quiet() as q:
                m = backup_dump.run(S.api(), out, page=4)
            self.assertEqual(m['table_count'], 3)
            self.assertEqual(m['rows'], 16)
            for t, n in (('customers', 11), ('sales', 5), ('notes', 0)):
                rows = read_ndjson(os.path.join(out, t + '.ndjson.gz'))
                self.assertEqual(len(rows), n, t)
                info = m['tables'][t]
                self.assertEqual(info['rows'], n)
                self.assertEqual(hashlib.sha256(slurp(os.path.join(out, info['file']))).hexdigest(), info['sha256'])
            self.assertEqual([r['id'] for r in read_ndjson(os.path.join(out, 'customers.ndjson.gz'))], list(range(1, 12)), 'every row once, in key order across 3 pages')
            disk = json.loads(slurp(os.path.join(out, 'manifest.json')))
            self.assertEqual(disk['schema_fingerprint'], 'f' * 32)
            self.assertEqual(disk['schema_version'], 46)
            self.assertEqual(len(S.F.log_rows), 1)
            self.assertEqual(S.F.log_rows[0]['p_status'], 'ok')
            self.assertEqual((S.F.log_rows[0]['p_tables'], S.F.log_rows[0]['p_rows']), (3, 16))
            self.assertNotIn(PASSWORD, q.text)
            self.assertNotIn(FAKE_JWT, q.text)
            blob = b''.join(slurp(os.path.join(out, f)) for f in os.listdir(out))
            self.assertNotIn(PASSWORD.encode(), blob)

    def test_output_is_deterministic(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            with Quiet():
                backup_dump.run(S.api(), a, page=3, log_run=False)
                backup_dump.run(S.api(), b, page=5, log_run=False)
            for t in ('customers', 'sales', 'notes'):
                self.assertEqual(slurp(os.path.join(a, t + '.ndjson.gz')), slurp(os.path.join(b, t + '.ndjson.gz')), 'same data = same bytes whatever the page size')

    def test_retries_with_backoff_then_success(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            S.F.fail['backup_dump'] = [503, 502]
            sl = []
            with Quiet() as q:
                m = backup_dump.run(S.api(sl), out, page=50, log_run=False)
            self.assertEqual(m['rows'], 16)
            self.assertEqual(sl, [1.0, 2.0], 'exponential back-off 1s, 2s')
            self.assertIn('retry 1/4', q.text)
            self.assertNotIn(PASSWORD, q.text, 'the error body echoed the password; it must be redacted')

    def test_gives_up_after_the_retries_and_exits_nonzero(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            S.F.always['backup_manifest'] = (500, 'down ' + PASSWORD)
            sl = []
            api = S.api(sl, retries=3)
            with Quiet() as q:
                rc = backup_dump.main(['--out', out], api=api)
            self.assertEqual(rc, 1)
            self.assertEqual(sl, [1.0, 2.0, 4.0])
            self.assertNotIn(PASSWORD, q.text)
            self.assertFalse(os.path.exists(os.path.join(out, 'manifest.json')), 'a failed run never leaves a manifest that looks complete')

    def test_client_errors_are_not_retried(self):
        with FakeServer() as S:
            S.F.always['backup_manifest'] = (403, 'not allowed')
            sl = []
            api = S.api(sl)
            before = api.attempts
            with self.assertRaises(oc.ApiError) as cm:
                api.rpc('backup_manifest')
            self.assertEqual(api.attempts - before, 1)
            self.assertEqual(sl, [])
            self.assertEqual(cm.exception.status, 403)

    def test_relogin_once_on_expired_token(self):
        with FakeServer() as S:
            api = S.api()
            S.F.unauth_once = True
            self.assertIsNotNone(api.rpc('backup_manifest'))
            self.assertEqual(S.F.logins, 2)

    def test_login_failure_is_reported_without_the_password(self):
        with FakeServer() as S:
            api = oc.Api(S.url, ANON, sleep=lambda s: None)
            with Quiet() as q:
                with self.assertRaises(oc.ApiError) as cm:
                    api.login('bot@example.com', 'wrong-password-x')
                oc.log('failed:', cm.exception)
            self.assertNotIn('wrong-password-x', q.text)
            self.assertNotIn('wrong-password-x', str(cm.exception))

    def test_manifest_mismatch_is_a_failure_and_is_logged(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            S.F.drop_rows = {'customers': 2}
            with Quiet():
                rc = backup_dump.main(['--out', out], api=S.api())
            self.assertEqual(rc, 1)
            self.assertFalse(os.path.exists(os.path.join(out, 'manifest.json')))
            self.assertEqual(S.F.log_rows[-1]['p_status'], 'failed')
            self.assertIn('customers', S.F.log_rows[-1]['p_detail']['error'])

    def test_rows_added_while_reading_are_fine_but_lost_rows_are_not(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            calls = {'n': 0}
            orig = S.F.tables['sales']

            def manifest(_):
                calls['n'] += 1
                if calls['n'] == 2:
                    orig.append({'id': 'a99', 'total': 1})          # a sale arrived during the backup
                return {'schema_version': 46, 'fingerprint': 'f' * 32, 'tables': [{'name': t, 'rows': len(r)} for t, r in sorted(S.F.tables.items())]}
            S.F.hooks['backup_manifest'] = manifest
            with Quiet():
                m = backup_dump.run(S.api(), out, log_run=False)
            self.assertEqual(m['tables']['sales']['rows_at_end'], m['tables']['sales']['rows_at_start'] + 1)

    def test_schema_change_during_the_run_fails(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            calls = {'n': 0}

            def manifest(_):
                calls['n'] += 1
                return {'schema_version': 46, 'fingerprint': ('a' if calls['n'] == 1 else 'b') * 32, 'tables': [{'name': t, 'rows': len(r)} for t, r in sorted(S.F.tables.items())]}
            S.F.hooks['backup_manifest'] = manifest
            with Quiet():
                self.assertEqual(backup_dump.main(['--out', out], api=S.api()), 1)
            self.assertIn('schema', S.F.log_rows[-1]['p_detail']['error'])

    def test_a_cursor_that_does_not_advance_stops(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            S.F.hooks['backup_dump'] = lambda b: {'table': b['p_table'], 'rows': [], 'next': '[1]', 'total': 1}
            with Quiet():
                self.assertEqual(backup_dump.main(['--out', out, '--tables', 'sales'], api=S.api()), 1)

    def test_missing_env_names_the_variable_not_a_value(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith(('SUPABASE_', 'BOT_'))}
        with unittest_env(env):
            with self.assertRaises(SystemExit) as cm:
                backup_dump.main(['--out', tempfile.gettempdir() + '/x_unused'])
        self.assertIn('SUPABASE_URL', str(cm.exception))


@contextlib.contextmanager
def unittest_env(new):
    old = dict(os.environ)
    os.environ.clear()
    os.environ.update(new)
    try:
        yield
    finally:
        os.environ.clear()
        os.environ.update(old)


class ExactNumberTests(unittest.TestCase):
    RAW = '{"a":260.00,"b":12345678901234567.123456789,"c":0.10000000000000000000,"d":[1,2.50,{"z":-0.0050}],"e":"x\u09f3","f":null,"g":true}'

    def test_round_trip_keeps_every_digit(self):
        out = oc.dumps_exact(oc.loads_exact(self.RAW))
        self.assertEqual(out, '{"a":260.00,"b":12345678901234567.123456789,"c":0.10000000000000000000,"d":[1,2.50,{"z":-0.0050}],"e":"x\u09f3","f":null,"g":true}'.replace('\\u09f3', '\u09f3'))

    def test_backup_file_keeps_exact_numbers(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out:
            S.F.hooks['backup_manifest'] = lambda b: {'schema_version': 46, 'fingerprint': 'f' * 32, 'tables': [{'name': 'money', 'rows': 1}]}
            S.F.hooks['backup_dump'] = lambda b: b'{"table":"money","rows":[{"id":1,"amount":260.00,"big":12345678901234567.123456789}],"next":null,"total":1}'
            with Quiet():
                backup_dump.run(S.api(), out, log_run=False)
            self.assertEqual(gzip.decompress(slurp(os.path.join(out, 'money.ndjson.gz'))).decode().strip(), '{"amount":260.00,"big":12345678901234567.123456789,"id":1}')


class RedactTests(unittest.TestCase):
    def test_redactor(self):
        r = oc.Redactor(['hunter2-long', 'tok-abcdef'])
        s = r('x hunter2-long y Bearer abcdefghijklmnop1234 z ' + FAKE_JWT + ' tok-abcdef')
        for bad in ('hunter2-long', 'abcdefghijklmnop1234', FAKE_JWT, 'tok-abcdef'):
            self.assertNotIn(bad, s)
        self.assertIn('***', s)

    def test_api_registers_secrets(self):
        with FakeServer() as S:
            S.api()
            self.assertIn(PASSWORD, oc.REDACT.secrets)
            self.assertNotIn(PASSWORD, oc.REDACT('login with ' + PASSWORD))
            self.assertNotIn(FAKE_JWT, oc.REDACT('token ' + FAKE_JWT))


class NotifyTests(unittest.TestCase):
    def setUp(self):
        self.sent = []

    def send(self, subject, text, htm):
        self.sent.append((subject, text, htm))

    def test_urgent_mail_then_mark_emailed_only_after_sending(self):
        with FakeServer() as S:
            S.F.alerts, S.F.digest = ALERTS, DIGEST
            with Quiet():
                r = notify_digest.run(S.api(), self.send, mode='scan')
            self.assertEqual(len(self.sent), 1)
            subj, text, htm = self.sent[0]
            self.assertIn('URGENT', subj)
            self.assertIn('জরুরি', subj)
            self.assertIn('৩টি লাল এক্সেপশন', text)
            self.assertIn('Backup is out of date', text)
            self.assertNotIn('<script>', htm, 'html is escaped')
            self.assertIn('&lt;script&gt;', htm)
            mark = [c for c in S.F.calls if c[0].endswith('notifications_mark_emailed')]
            self.assertEqual([m[1]['p_ids'] for m in mark], [[14, 15]])
            self.assertTrue(r['urgent_sent'] and not r['digest_sent'])
            self.assertEqual(r['scan_created'], 2)

    def test_nothing_is_marked_when_sending_fails(self):
        with FakeServer() as S:
            S.F.alerts = ALERTS

            def boom(*a):
                raise OSError('smtp down')
            with Quiet():
                rc = notify_digest.main(['--mode', 'scan'], api=S.api(), send=boom)
            self.assertEqual(rc, 1)
            self.assertFalse([c for c in S.F.calls if c[0].endswith('notifications_mark_emailed')])

    def test_no_alerts_means_no_mail(self):
        with FakeServer() as S:
            with Quiet():
                r = notify_digest.run(S.api(), self.send, mode='scan')
            self.assertEqual(self.sent, [])
            self.assertEqual(r['urgent'], 0)

    def test_email_switch_off_sends_nothing_but_still_scans(self):
        with FakeServer() as S:
            S.F.cfg = {'email_on': False, 'digest_times': '08,21'}
            S.F.alerts, S.F.digest = ALERTS, DIGEST
            with Quiet():
                r = notify_digest.run(S.api(), self.send, mode='digest', slot='21')
            self.assertEqual(self.sent, [])
            self.assertEqual(r['scan_created'], 2)
            self.assertFalse([c for c in S.F.calls if c[0].endswith('urgent_alerts')])

    def test_digest_slots(self):
        import datetime
        now = datetime.datetime(2026, 10, 13, 21, 0, tzinfo=notify_digest.DHAKA)
        with FakeServer() as S:
            S.F.digest = DIGEST
            with Quiet():
                notify_digest.run(S.api(), self.send, mode='digest', slot='21', now=now)
                notify_digest.run(S.api(), self.send, mode='digest', slot='08', now=now)
            dates = [c[1]['p_date'] for c in S.F.calls if c[0].endswith('daily_digest')]
            self.assertEqual(dates, ['2026-10-13', '2026-10-12'], '21:00 reports today, 08:00 reports yesterday')
            self.assertEqual(len(self.sent), 2)
            subj, text, htm = self.sent[0]
            for must in ('Daily summary', 'দৈনিক সারাংশ', '৳1,300', '(+100.0%)', '(-50.0%)', 'Rasgulla', 'NOT closed', 'জমা হয়নি', 'STALE!', '৳5,000'):
                self.assertIn(must, text)
            self.assertIn('Main &lt;b&gt;', htm)
            self.assertIn('max-width:480px', htm, 'single narrow column for phones')

    def test_digest_only_when_the_hour_is_enabled(self):
        with FakeServer() as S:
            S.F.digest = DIGEST
            S.F.cfg = {'email_on': True, 'digest_times': '21'}
            with Quiet():
                notify_digest.run(S.api(), self.send, mode='digest', slot='08')
                self.assertEqual(self.sent, [])
                notify_digest.run(S.api(), self.send, mode='digest', slot='21')
                self.assertEqual(len(self.sent), 1)
                S.F.cfg = {'email_on': True, 'digest_times': 'off'}
                notify_digest.run(S.api(), self.send, mode='digest', slot='manual')
                self.assertEqual(len(self.sent), 1, 'off = never, even for a manual slot')
                S.F.cfg = {'email_on': True, 'digest_times': '08,21'}
                notify_digest.run(S.api(), self.send, mode='scan', slot='21')
                self.assertEqual(len(self.sent), 1, 'scan mode never sends the digest')

    def test_dry_run_prints_and_sends_nothing(self):
        with FakeServer() as S:
            S.F.alerts, S.F.digest = ALERTS, DIGEST
            printed = []
            with Quiet():
                r = notify_digest.run(S.api(), self.send, mode='digest', slot='manual', dry=True, out=printed.append)
            self.assertEqual(self.sent, [])
            self.assertTrue(any('DRY RUN: urgent' in p for p in printed) and any('DRY RUN: daily digest' in p for p in printed))
            paths = [c[0] for c in S.F.calls]
            self.assertFalse([p for p in paths if p.endswith(('notify_scan', 'notifications_mark_emailed'))], 'dry run writes nothing on the server')
            self.assertFalse(r['urgent_sent'] or r['digest_sent'])

    def test_dry_run_main_needs_no_gmail_settings(self):
        with FakeServer() as S:
            S.F.digest = DIGEST
            env = {k: v for k, v in os.environ.items() if not k.startswith(('GMAIL_', 'MAIL_'))}
            buf = io.StringIO()
            with unittest_env(env), Quiet(), contextlib.redirect_stdout(buf):
                rc = notify_digest.main(['--dry-run', '--mode', 'digest'], api=S.api())
            self.assertEqual(rc, 0)
            self.assertIn('Daily summary', buf.getvalue())

    def test_recipients_are_validated(self):
        self.assertEqual(notify_digest.parse_recipients('a@b.com, c@d.org'), ['a@b.com', 'c@d.org'])
        for bad in ('', 'not-an-email', 'a@b.com, x', ','.join('u%d@e.com' % i for i in range(11))):
            with self.assertRaises(SystemExit):
                notify_digest.parse_recipients(bad)

    def test_money_format(self):
        self.assertEqual(notify_digest.money(1234567), '৳1,234,567')
        self.assertEqual(notify_digest.money(12.5), '৳12.50')
        self.assertEqual(notify_digest.money(-800), '-৳800')
        self.assertEqual(notify_digest.money(None), '-')


class StubSMTP(socketserver.StreamRequestHandler):
    """A minimal SMTP server: records one message."""
    box = None

    def handle(self):
        w = lambda s: self.wfile.write((s + '\r\n').encode())
        w('220 stub ready')
        data_mode, buf, env = False, [], {'rcpt': []}
        while True:
            line = self.rfile.readline()
            if not line:
                return
            if data_mode:
                if line in (b'.\r\n', b'.\n'):
                    data_mode = False
                    env['data'] = b''.join(buf)
                    StubSMTP.box.append(env)
                    w('250 queued')
                else:
                    buf.append(line)
                continue
            cmd = line.decode('latin-1').strip()
            u = cmd.upper()
            if u.startswith(('EHLO', 'HELO')):
                w('250 stub')
            elif u.startswith('MAIL FROM'):
                env['from'] = cmd[10:]
                w('250 ok')
            elif u.startswith('RCPT TO'):
                env['rcpt'].append(cmd[8:])
                w('250 ok')
            elif u == 'DATA':
                data_mode = True
                w('354 go')
            elif u == 'QUIT':
                w('221 bye')
                return
            else:
                w('250 ok')


class SmtpTests(unittest.TestCase):
    def test_real_smtp_path_against_a_local_stub(self):
        import email
        from email import policy
        StubSMTP.box = []
        srv = socketserver.ThreadingTCPServer(('127.0.0.1', 0), StubSMTP)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            with FakeServer() as S:
                S.F.alerts, S.F.digest = ALERTS, DIGEST
                env = dict(os.environ, GMAIL_USER='shop@gmail.test', GMAIL_APP_PASSWORD='app-password-xyz', MAIL_TO='owner@example.com, boss@example.com',
                           SMTP_HOST='127.0.0.1', SMTP_PORT=str(srv.server_address[1]), SMTP_SECURITY='plain')
                with unittest_env(env), Quiet() as q:
                    rc = notify_digest.main(['--mode', 'digest', '--slot', 'manual'], api=S.api())
                self.assertEqual(rc, 0)
                self.assertNotIn('app-password-xyz', q.text)
            self.assertEqual(len(StubSMTP.box), 2, 'urgent mail + digest')
            first = StubSMTP.box[0]
            self.assertEqual(len(first['rcpt']), 2)
            msg = email.message_from_bytes(first['data'], policy=policy.default)
            self.assertEqual(msg['To'], 'owner@example.com, boss@example.com')
            body = msg.get_body(('plain',)).get_content()
            self.assertIn('৩টি লাল এক্সেপশন', body)
            self.assertIsNotNone(msg.get_body(('html',)))
            self.assertNotIn(b'app-password-xyz', first['data'])
        finally:
            srv.shutdown()
            srv.server_close()


class RestoreTests(unittest.TestCase):
    def make_backup(self, S, out, tricky=False):
        if tricky:
            S.F.tables['notes'] = [{'id': 1, 'text': "it's $bk0$ and $rs0$ and $r$ and '' \\ \"q\" বাংলা"}]
        with Quiet():
            backup_dump.run(S.api(), out, page=4, log_run=False)

    def test_dry_run_writes_nothing(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as w:
            self.make_backup(S, out)
            target = os.path.join(w, 'restore.sql')
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = restore_backup.main([out, '--out', target, '--dry-run'])
            self.assertEqual(rc, 0)
            self.assertIn('customers: 11', buf.getvalue())
            self.assertIn('sales: 5', buf.getvalue())
            self.assertFalse(os.path.exists(target))

    def test_damaged_backup_is_refused(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as w:
            self.make_backup(S, out)
            with open(os.path.join(out, 'sales.ndjson.gz'), 'ab') as f:
                f.write(b'garbage')
            target = os.path.join(w, 'restore.sql')
            with Quiet() as q:
                rc = restore_backup.main([out, '--out', target])
            self.assertEqual(rc, 1)
            self.assertIn('sales', q.text)
            self.assertFalse(os.path.exists(target))

    def test_sql_shape_tags_and_split(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as w:
            self.make_backup(S, out, tricky=True)
            target = os.path.join(w, 'restore.sql')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(restore_backup.main([out, '--out', target, '--chunk-rows', '4']), 0)
            sql = slurp(target, 'r', encoding='utf-8')
            self.assertIn('set local session_replication_role = replica', sql)
            self.assertTrue(sql.startswith('-- Restore generated'))
            self.assertTrue(sql.rstrip().endswith('commit;'))
            self.assertIn('on conflict do nothing', sql)
            self.assertNotIn('truncate', sql)
            self.assertIn('$bk1$', sql, 'the dollar tag moved past the one used in the data')
            self.assertEqual(sql.count('-- table '), 3)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(restore_backup.main([out, '--out', os.path.join(w, 'r2.sql'), '--truncate', '--split-mb', '0.001', '--chunk-rows', '2']), 0)
            parts = sorted(f for f in os.listdir(w) if f.startswith('r2.part'))
            self.assertGreater(len(parts), 1)
            for p in parts:
                s = slurp(os.path.join(w, p), 'r', encoding='utf-8')
                self.assertIn('begin;', s)
                self.assertIn('commit;', s)
                self.assertIn('WARNING: --truncate', s)

    def test_unsafe_table_name_refused(self):
        with self.assertRaises(SystemExit):
            restore_backup.table_sql('x; drop table y', [], 10, False)

    @unittest.skipUnless(os.environ.get('BOS_PG_RESTORE_DB'), 'set BOS_PG_RESTORE_DB to run against a real local Postgres')
    def test_restore_into_postgres(self):
        db = os.environ['BOS_PG_RESTORE_DB']
        cmd = shlex.split(os.environ.get('BOS_PG_CMD', 'psql -h /tmp -p 5544 -U postgres')) + ['-d', db, '-v', 'ON_ERROR_STOP=1', '-qAt']
        with FakeServer() as S, tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as w:
            S.F.tables = {'zz_restore': [{'id': i, 'name': 'n%d' % i, 'note': "q'uote $x$ বাংলা", 'total': i * 2, 'twice': i * 4} for i in range(1, 8)]}
            with Quiet():
                backup_dump.run(S.api(), out, log_run=False)
            subprocess.run(cmd + ['-c', 'drop table if exists public.zz_restore; create table public.zz_restore (id bigserial primary key, name text, note text, total int, twice int generated always as (total * 2) stored)'], check=True)
            target = os.path.join(w, 'r.sql')
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(restore_backup.main([out, '--out', target]), 0)
            subprocess.run(cmd + ['-f', target], check=True)
            subprocess.run(cmd + ['-f', target], check=True)       # twice: still 7 rows
            n = subprocess.run(cmd + ['-c', 'select count(*), max(id), sum(twice) from public.zz_restore'], check=True, capture_output=True, text=True).stdout.strip()
            self.assertEqual(n, '7|7|112')
            nxt = subprocess.run(cmd + ['-c', "insert into public.zz_restore (name, total) values ('new', 1) returning id"], check=True, capture_output=True, text=True).stdout.strip().splitlines()[0]
            self.assertEqual(nxt, '8', 'the sequence moved past the restored ids')
            subprocess.run(cmd + ['-c', 'drop table public.zz_restore'], check=True)


class PhotoTests(unittest.TestCase):
    def test_copy_skip_existing_and_limits(self):
        with FakeServer() as S, tempfile.TemporaryDirectory() as w:
            S.F.storage = {'POS/1/a.jpg': b'A' * 100, 'POS/1/b.jpg': b'B' * 50, 'ITEMS/x.jpg': b'C' * 10}
            gd, dd = os.path.join(w, 'out', 'photos'), os.path.join(w, 'drive')
            with Quiet():
                m = backup_photos.run(S.api(), gd, dd)
            self.assertEqual((m['files'], m['new'], m['failed'], m['destination']), (3, 3, 0, 'git'))
            self.assertEqual(slurp(os.path.join(gd, 'POS/1/a.jpg')), b'A' * 100)
            self.assertTrue(os.path.exists(os.path.join(w, 'out', 'photos_manifest.json')))
            gets = lambda: len([c for c in S.F.calls if c[1] is None and 'object/authenticated' in c[0]])
            n0 = gets()
            with Quiet():
                m2 = backup_photos.run(S.api(), gd, dd)
            self.assertEqual(m2['new'], 0)
            self.assertEqual(gets(), n0, 'nothing downloaded twice')
            with Quiet():
                big = backup_photos.run(S.api(), os.path.join(w, 'g2'), dd, use_drive=False, git_limit_mb=0.0001)
            self.assertEqual(big['destination'], 'none')
            self.assertIn('NOT copied', big['warning'])
            self.assertFalse(os.path.exists(os.path.join(w, 'g2')))
            with Quiet():
                big2 = backup_photos.run(S.api(), os.path.join(w, 'g3'), dd, use_drive=True, git_limit_mb=0.0001)
            self.assertEqual(big2['destination'], 'drive')
            self.assertTrue(os.path.exists(os.path.join(dd, 'ITEMS/x.jpg')))

    def test_unsafe_names_are_skipped(self):
        with tempfile.TemporaryDirectory() as w:
            with self.assertRaises(ValueError):
                backup_photos.safe_join(w, '../evil')


if __name__ == '__main__':
    unittest.main(verbosity=2)

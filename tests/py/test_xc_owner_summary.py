"""XC-1: tools/owner_summary.py - dry run by default, no secrets or addresses printed, quiet days, one send per day, failures recorded and redacted,
outlet messages without company-wide figures or wastage cost. Mocks only: no network, no Supabase, no SMTP, no Telegram.
Run: python3 -I tests/py/test_xc_owner_summary.py   (from the repository root)"""
import datetime
import io
import os
import sys
from contextlib import redirect_stdout

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import owner_summary as osum  # noqa: E402
import ops_common as oc  # noqa: E402

fails = []


def chk(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)


SECRET_TOKEN = '123456789:AAFAKE-test-token-value-xyz'
SECRET_PW = 'test-app-password-xyz'
ADDR = 'test_owner_addr@example.com'
CHAT = '-1009876543'


class FakeApi:
    def __init__(self, targets, compose_by_loc=None, already=None):
        self.targets = targets
        self.compose_by_loc = compose_by_loc or {}
        self.already = set(already or [])
        self.calls = []

    def rpc(self, fn, args=None):
        args = args or {}
        self.calls.append((fn, args))
        if fn == 'xc_summary_targets':
            return self.targets
        if fn == 'xc_summary_compose':
            return self.compose_by_loc.get(args.get('p_loc'), self.compose_by_loc.get('owner'))
        if fn == 'xc_summary_already_sent':
            return (args['p_run'], args['p_recipient'], args['p_channel']) in self.already
        if fn == 'xc_summary_record':
            return {'ok': True}
        raise AssertionError('unexpected rpc ' + fn)

    def recorded(self):
        return [a for f, a in self.calls if f == 'xc_summary_record']


def composed(nothing=False, net_today=500, bills=2):
    return {'date': '2026-10-16', 'scope': 'owner', 'nothing_to_report': nothing,
            'sales': {'today': {'net': net_today, 'bills': bills}, 'yesterday': {'net': 200, 'bills': 1}, 'last_week': {'net': 390, 'bills': 3},
                      'vs_yesterday_pct': 150, 'vs_last_week_pct': 28.2,
                      'by_location': [{'name_bn': 'শাখা ১', 'name_en': 'Branch 1', 'net': 500}]},
            'cash': {'short': 20, 'over': 0, 'count': 1}, 'wallet_receipts': {'total': 150, 'by_wallet': [{'wallet': 'test_wallet', 'amount': 150}]},
            'collections': 0, 'wastage': {'count': 1, 'value': 77},
            'orders': {'open': 3, 'cakes_due_tomorrow': 1, 'cake_specs_due_tomorrow': 1},
            'owner_only': {'dues': {'customers_total': 900, 'suppliers': {'payable': 400, 'overdue': 0}}, 'approvals_waiting': 2, 'low_stock_items': 0,
                           'batches_expiring': 0, 'red_exceptions': 0, 'failed_intake': 0, 'failed_mail': 0, 'failed_jobs': 0},
            'notes': [{'code': 'x', 'text_en': 'Every figure is computed on the server.', 'text_bn': 'x'}]}


def targets(**kw):
    t = {'on': True, 'email_on': True, 'telegram_on': True, 'times': '08,21',
         'recipients': [{'id': 1, 'name': 'test_owner_mail', 'channel': 'email', 'address': ADDR, 'scope': 'owner', 'location_id': None, 'quiet_when_empty': False},
                        {'id': 2, 'name': 'test_owner_tg', 'channel': 'telegram', 'address': CHAT, 'scope': 'owner', 'location_id': None, 'quiet_when_empty': False}]}
    t.update(kw)
    return t


NOW = datetime.datetime(2026, 10, 17, 21, 5, tzinfo=osum.DHAKA)

# 1 dry run is the default: nothing sent, nothing recorded, the text shows, no address and no secret is printed
api = FakeApi(targets(), {'owner': composed()})
sent = []
buf = io.StringIO()
with redirect_stdout(buf):
    r = osum.run(api, lambda *a: sent.append(a), lambda *a: sent.append(a), slot='21', send=False, now=NOW, out=print)
out_text = buf.getvalue()
chk('T1 dry run sends nothing', sent == [])
chk('T1 dry run records nothing', api.recorded() == [])
chk('T1 dry run shows the message text for each recipient', 'DRY RUN: email' in out_text and 'DRY RUN: telegram' in out_text and 'Net sales' in out_text)
chk('T1 dry run prints no recipient address', ADDR not in out_text and CHAT not in out_text)
chk('T1 dry run reports two dry messages', r['dry'] == 2 and r['sent'] == 0)

# 2 the switch is off: nothing at all
api = FakeApi(targets(on=False))
r = osum.run(api, lambda *a: None, lambda *a: None, slot='21', send=True, now=NOW, out=lambda *a: None)
chk('T2 the summary switched off: skipped, no compose call', r == {'skipped': 'switch_off'} and not any(f == 'xc_summary_compose' for f, _ in api.calls))

# 3 not a summary hour: slot 08 when the owner set only 21
api = FakeApi(targets(times='21'))
r = osum.run(api, lambda *a: None, lambda *a: None, slot='08', send=True, now=NOW, out=lambda *a: None)
chk('T3 an hour that is not in the list sends nothing', r == {'skipped': 'not_due_hour'})

# 4 real send: both channels, one line per recipient, the hash is recorded, no address or token in the log
api = FakeApi(targets(), {'owner': composed()})
got = []
buf = io.StringIO()
with redirect_stdout(buf):
    r = osum.run(api, lambda to, s, t, h: got.append(('email', to)), lambda chat, t: got.append(('tg', chat)), slot='21', send=True, now=NOW, out=print)
chk('T4 both recipients are sent once each', got == [('email', ADDR), ('tg', CHAT)] and r['sent'] == 2)
rec = api.recorded()
chk('T4 two sent lines are recorded with the day and a short hash', len(rec) == 2 and all(x['p_status'] == 'sent' and x['p_run'] == '2026-10-17' and len(x['p_hash']) == 16 for x in rec))

# 5 already sent today: not sent again
api = FakeApi(targets(), {'owner': composed()}, already=[('2026-10-17', 1, 'email')])
got = []
r = osum.run(api, lambda to, s, t, h: got.append(to), lambda chat, t: got.append(chat), slot='21', send=True, now=NOW, out=lambda *a: None)
chk('T5 an e-mail already sent today is not sent again; telegram still is', got == [CHAT] and r['skipped'] == 1 and r['sent'] == 1)

# 6 quiet when empty: nothing to report and the recipient asked for quiet -> nothing sent, logged as skipped_empty
t6 = targets(recipients=[{'id': 3, 'name': 'test_quiet', 'channel': 'email', 'address': ADDR, 'scope': 'owner', 'location_id': None, 'quiet_when_empty': True}])
api = FakeApi(t6, {'owner': composed(nothing=True, net_today=0, bills=0)})
got = []
r = osum.run(api, lambda to, s, t, h: got.append(to), lambda chat, t: got.append(chat), slot='21', send=True, now=NOW, out=lambda *a: None)
chk('T6 a quiet recipient on a day with nothing to report gets nothing', got == [] and r['skipped'] == 1)
chk('T6 that is written to the log as skipped_empty', [x['p_status'] for x in api.recorded()] == ['skipped_empty'])
# the same day for a recipient who did not ask for quiet still gets the message
t6b = targets(recipients=[{'id': 3, 'name': 'test_loud', 'channel': 'email', 'address': ADDR, 'scope': 'owner', 'location_id': None, 'quiet_when_empty': False}])
api = FakeApi(t6b, {'owner': composed(nothing=True, net_today=0, bills=0)})
got = []
osum.run(api, lambda to, s, t, h: got.append(to), lambda chat, t: got.append(chat), slot='21', send=True, now=NOW, out=lambda *a: None)
chk('T6 without the quiet option the same day is still sent', got == [ADDR])

# 7 a failed send: recorded as failed, the error is short and the secrets are masked, the other recipient still goes
oc.REDACT.add(SECRET_PW)
oc.REDACT.add(SECRET_TOKEN)
def bad_mail(to, s, t, h):
    raise RuntimeError('login failed for password ' + SECRET_PW + ' token ' + SECRET_TOKEN)
api = FakeApi(targets(), {'owner': composed()})
got = []
r = osum.run(api, bad_mail, lambda chat, t: got.append(chat), slot='21', send=True, now=NOW, out=lambda *a: None)
failed = [x for x in api.recorded() if x['p_status'] == 'failed']
chk('T7 the failed e-mail is recorded as failed', len(failed) == 1 and failed[0]['p_recipient'] == 1)
chk('T7 the error stored has no password and no token', failed and SECRET_PW not in failed[0]['p_error'] and SECRET_TOKEN not in failed[0]['p_error'])
chk('T7 the other recipient is still sent', got == [CHAT] and r['sent'] == 1 and r['failed'] == 1)

# 8 outlet messages: no company-wide sections, no wastage value (cost), no other outlets
outlet_c = composed()
outlet_c['scope'] = 'outlet'
outlet_c['location_name_en'] = 'Branch 2'
outlet_c.pop('owner_only')
outlet_c['sales']['by_location'] = []
t8 = targets(recipients=[{'id': 4, 'name': 'test_outlet', 'channel': 'email', 'address': ADDR, 'scope': 'outlet', 'location_id': 2, 'quiet_when_empty': False}])
api = FakeApi(t8, {2: outlet_c})
txt_holder = []
osum.run(api, lambda to, s, t, h: txt_holder.append(t), lambda chat, t: None, slot='21', send=True, now=NOW, out=lambda *a: None)
body = txt_holder[0] if txt_holder else ''
chk('T8 the outlet message asks the server for that place only', any(f == 'xc_summary_compose' and a.get('p_loc') == 2 for f, a in api.calls))
chk('T8 the outlet message has no dues and no approvals section', 'Dues' not in body and 'Approvals waiting' not in body)
chk('T8 the outlet message has no wastage cost value', '77' not in body and 'Wastage' in body)
chk('T8 the outlet message names the place', 'Branch 2' in body)

# 9 the day: slot 08 summarises yesterday; slot 21 today
api = FakeApi(targets(), {'owner': composed()})
osum.run(api, lambda *a: None, lambda *a: None, slot='08', send=False, now=NOW, out=lambda *a: None)
chk('T9 the morning slot summarises yesterday', [a for f, a in api.calls if f == 'xc_summary_compose'][0]['p_date'] == '2026-10-16')
api = FakeApi(targets(), {'owner': composed()})
osum.run(api, lambda *a: None, lambda *a: None, slot='21', send=False, now=NOW, out=lambda *a: None)
chk('T9 the evening slot summarises today', [a for f, a in api.calls if f == 'xc_summary_compose'][0]['p_date'] == '2026-10-17')

# 10 no telegram token: the telegram recipient fails with a clear message, e-mail still goes
def no_token(chat, text):
    raise RuntimeError('TELEGRAM_BOT_TOKEN is not set (GitHub secret)')
api = FakeApi(targets(), {'owner': composed()})
got = []
r = osum.run(api, lambda to, s, t, h: got.append(to), no_token, slot='21', send=True, now=NOW, out=lambda *a: None)
chk('T10 without the token only the telegram recipient fails; e-mail is sent', got == [ADDR] and r['failed'] == 1 and r['sent'] == 1)

# 11 the sender helpers never put the secret in an error (the redactor masks it)
masked = oc.REDACT('https://api.telegram.org/bot' + SECRET_TOKEN + '/sendMessage')
chk('T11 a URL with the bot token is masked in every log line', SECRET_TOKEN not in masked and '***' in masked)

# 12 the script's own text has no leftover fictional names and no demo labels in the layout
text_all = osum.build_message(composed(), 'owner', '2026-10-17')[1]
chk('T12 the message is plain text with the owner sections', 'Sales' in text_all and 'Cash and collections' in text_all and 'Orders and cakes' in text_all)

print(f'RESULT: {"FAILED " + str(len(fails)) if fails else "ALL PASS"}')
sys.exit(1 if fails else 0)

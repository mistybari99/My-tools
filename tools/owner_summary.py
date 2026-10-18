#!/usr/bin/env python3
"""Owner daily summary (XC-1): sends the server-composed day summary to the recipients the owner entered, by e-mail (Gmail SMTP) and/or Telegram.
Python 3 standard library only. Run by hand or by GitHub Actions. DRY RUN IS THE DEFAULT: nothing is sent and nothing is recorded unless --send is given.

What one run does:
  1. Logs in as the dedicated ops bot (purpose 'notify') with the public anon key - never the service_role key.
  2. xc_summary_targets()  -> is the summary on, which channels are on, the hours, the active recipients (no secrets are stored there).
  3. For the hour given by --slot (08 = yesterday's figures, 21 = today's, manual = today): skip when that hour is not in the list.
  4. For each recipient: xc_summary_compose(day, place) -> the figures, a plain Bangla + English layout, one message.
     A quiet recipient (quiet_when_empty) gets nothing on a day with nothing to report; that is written to the log as skipped_empty.
  5. --send only: a recipient already sent for that day is skipped (xc_summary_already_sent); otherwise the message goes out and xc_summary_record() writes one line.
     A failed send is recorded as failed (with a short, redacted error) and is tried again on the next run.
Secrets (environment only, never printed, never written):
  SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL (falls back to BOT_EMAIL), NOTIFY_BOT_PASSWORD (falls back to BOT_PASSWORD),
  GMAIL_USER, GMAIL_APP_PASSWORD (for e-mail recipients), TELEGRAM_BOT_TOKEN (for telegram recipients), optional APP_URL.
Privacy: wastage VALUE (cost) is left out of outlet messages; outlet messages have no company-wide dues, approvals or failures.
Not built here: SMS / WhatsApp (they need consent and a template via the existing notify_outbox path).
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402
import notify_digest as nd  # noqa: E402

DHAKA = datetime.timezone(datetime.timedelta(hours=6))
TG_LIMIT = 4000


def money(v):
    return nd.money(v)


def sections_for(c, scope):
    """The layout of one summary, as [(title, [(label, value), ...])]. Pure function of the server's figures."""
    s = c.get('sales') or {}
    t, y, w = s.get('today') or {}, s.get('yesterday') or {}, s.get('last_week') or {}
    sec = []
    rows = [(nd.bi('নিট বিক্রি', 'Net sales'), money(t.get('net')) + nd.pct(s.get('vs_yesterday_pct')) + ' ' + nd.bi('গতকালের তুলনায়', 'vs yesterday')),
            (nd.bi('গতকাল', 'Yesterday'), money(y.get('net'))),
            (nd.bi('গত সপ্তাহ একই দিন', 'Same weekday last week'), money(w.get('net')) + nd.pct(s.get('vs_last_week_pct'))),
            (nd.bi('বিল', 'Bills'), str(t.get('bills', 0)))]
    if scope == 'owner':
        for loc in s.get('by_location') or []:
            rows.append(('  ' + nd.bi(loc.get('name_bn') or '', loc.get('name_en') or ''), money(loc.get('net'))))
    sec.append((nd.bi('বিক্রি', 'Sales'), rows))
    cash = c.get('cash') or {}
    wal = c.get('wallet_receipts') or {}
    rows = [(nd.bi('ক্যাশ কম', 'Cash short'), money(cash.get('short', 0))), (nd.bi('ক্যাশ বেশি', 'Cash over'), money(cash.get('over', 0))),
            (nd.bi('বাকি আদায়', 'Collections'), money(c.get('collections', 0))), (nd.bi('মোবাইল ওয়ালেট জমা', 'Mobile wallet receipts'), money(wal.get('total', 0)))]
    for x in wal.get('by_wallet') or []:
        rows.append(('  ' + str(x.get('wallet')), money(x.get('amount'))))
    sec.append((nd.bi('ক্যাশ ও আদায়', 'Cash and collections'), rows))
    wst = c.get('wastage') or {}
    rows = [(nd.bi('অপচয়', 'Wastage') + f" ({wst.get('count', 0)})", ('' if scope == 'outlet' else money(wst.get('value', 0))))]
    sec.append((nd.bi('অপচয়', 'Wastage'), rows))
    o = c.get('orders') or {}
    sec.append((nd.bi('অর্ডার ও কেক', 'Orders and cakes'), [
        (nd.bi('খোলা অর্ডার', 'Open orders'), str(o.get('open', 0))),
        (nd.bi('আগামীকালের কেক/অর্ডার', 'Due tomorrow'), str(o.get('cakes_due_tomorrow', 0)))]))
    if scope == 'owner' and c.get('owner_only'):
        ow = c['owner_only']
        due = ow.get('dues') or {}
        sup = due.get('suppliers') or {}
        sec.append((nd.bi('পাওনা-দেনা', 'Dues'), [
            (nd.bi('গ্রাহকের বাকি', 'Customer dues'), money((due.get('customers_total')) or 0)),
            (nd.bi('সরবরাহকারীর পাওনা', 'Supplier payable'), money(sup.get('payable', 0))),
            (nd.bi('এর মধ্যে মেয়াদোত্তীর্ণ', 'of which overdue'), money(sup.get('overdue', 0)))]))
        sec.append((nd.bi('নজর দিন', 'Needs attention'), [
            (nd.bi('অনুমোদন বাকি', 'Approvals waiting'), str(ow.get('approvals_waiting', 0))),
            (nd.bi('কম স্টকের আইটেম', 'Low-stock items'), str(ow.get('low_stock_items', 0))),
            (nd.bi('মেয়াদ শেষ হতে চলা ব্যাচ', 'Batches expiring'), str(ow.get('batches_expiring', 0))),
            (nd.bi('লাল এক্সেপশন', 'Red exceptions'), str(ow.get('red_exceptions', 0))),
            (nd.bi('ব্যর্থ ইনটেক', 'Failed intake'), str(ow.get('failed_intake', 0))),
            (nd.bi('ব্যর্থ মেইল/এসএমএস', 'Failed mail/SMS'), str(ow.get('failed_mail', 0))),
            (nd.bi('ব্যর্থ কাজ (জব)', 'Failed jobs'), str(ow.get('failed_jobs', 0)))]))
    notes = [n.get('text_en') for n in c.get('notes') or [] if n.get('text_en')]
    if notes:
        sec.append((nd.bi('টীকা', 'Notes'), [(n, '') for n in notes]))
    return sec


def build_message(c, scope, day, recipient_name=''):
    heading = nd.bi('দৈনিক সারাংশ', 'Daily summary') + f' - {day}'
    if c.get('location_name_en'):
        heading += f" ({c['location_name_en']})"
    subject = f"[Islamia BOS] {nd.bi('দৈনিক সারাংশ', 'Daily summary')} {day}" + (' - ' + c['location_name_en'] if c.get('location_name_en') else '')
    text, htm = nd.render(subject, heading, sections_for(c, scope), os.environ.get('APP_URL', ''))
    return subject, text, htm


def digest_hash(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]


def run(api, send_email, send_telegram, slot='manual', day_override=None, send=False, now=None, out=print):
    """send_email(to, subject, text, html) and send_telegram(chat_id, text) deliver one message each. Returns a summary dict (no addresses, no secrets)."""
    t = api.rpc('xc_summary_targets', {}) or {}
    if not t.get('on'):
        oc.log('owner summary is switched OFF (xc_summary_on): nothing is sent')
        return {'skipped': 'switch_off'}
    times = {x.strip() for x in str(t.get('times') or '21').split(',') if x.strip()}
    if slot != 'manual' and slot not in times:
        oc.log(f'not a summary hour (slot {slot}; hours {sorted(times)}): nothing is sent')
        return {'skipped': 'not_due_hour'}
    if day_override:
        day = datetime.date.fromisoformat(day_override)
    else:
        today = (now or datetime.datetime.now(DHAKA)).astimezone(DHAKA).date()
        day = today - datetime.timedelta(days=1) if slot == '08' else today
    res = {'day': day.isoformat(), 'sent': 0, 'failed': 0, 'skipped': 0, 'dry': 0, 'items': []}
    cache = {}
    for r in t.get('recipients') or []:
        ch = r.get('channel')
        if (ch == 'email' and not t.get('email_on')) or (ch == 'telegram' and not t.get('telegram_on')):
            res['skipped'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'channel_off'})
            continue
        if send and api.rpc('xc_summary_already_sent', {'p_run': day.isoformat(), 'p_recipient': r['id'], 'p_channel': ch}) is True:
            res['skipped'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'already_sent'})
            continue
        scope = r.get('scope') or 'owner'
        key = (scope, r.get('location_id') if scope == 'outlet' else None)
        if key not in cache:
            cache[key] = api.rpc('xc_summary_compose', {'p_date': day.isoformat(), 'p_loc': key[1]}) or {}
        c = cache[key]
        if c.get('nothing_to_report') and r.get('quiet_when_empty'):
            res['skipped'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'skipped_empty'})
            if send:
                api.rpc('xc_summary_record', {'p_run': day.isoformat(), 'p_recipient': r['id'], 'p_channel': ch, 'p_status': 'skipped_empty'})
            continue
        subject, text, htm = build_message(c, 'outlet' if scope == 'outlet' else 'owner', day.isoformat())
        h = digest_hash(text)
        if not send:
            res['dry'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'dry_run', 'hash': h})
            out(f"--- DRY RUN: {ch} to '{r.get('name')}' ({scope}) ---\nSubject: {subject}\n\n{text}")
            continue
        try:
            if ch == 'email':
                send_email(r['address'], subject, text, htm)
            else:
                send_telegram(r['address'], text[:TG_LIMIT])
            api.rpc('xc_summary_record', {'p_run': day.isoformat(), 'p_recipient': r['id'], 'p_channel': ch, 'p_status': 'sent', 'p_hash': h})
            res['sent'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'sent', 'hash': h})
        except Exception as e:  # one failed recipient never stops the others; the error is redacted and kept short
            msg = oc.REDACT(str(e))[:300]
            try:
                api.rpc('xc_summary_record', {'p_run': day.isoformat(), 'p_recipient': r['id'], 'p_channel': ch, 'p_status': 'failed', 'p_error': msg})
            except Exception:
                pass
            res['failed'] += 1
            res['items'].append({'name': r.get('name'), 'channel': ch, 'status': 'failed', 'error': msg})
            oc.log(f"summary to '{r.get('name')}' ({ch}) failed: {msg}")
    oc.log('owner summary:', json.dumps({k: res[k] for k in ('day', 'sent', 'failed', 'skipped', 'dry')}))
    return res


def telegram_sender(token):
    oc.REDACT.add(token)

    def send(chat_id, text):
        url = f'https://api.telegram.org/bot{token}/sendMessage'
        data = urllib.parse.urlencode({'chat_id': chat_id, 'text': text, 'disable_web_page_preview': 'true'}).encode()
        req = urllib.request.Request(url, data=data, method='POST')
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.loads(r.read().decode('utf-8', 'replace') or '{}')
        if not body.get('ok'):
            raise RuntimeError('telegram answered not ok')
    return send


def main(argv=None, api=None, send_email=None, send_telegram=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--slot', default='manual', help='08 | 21 | manual (which scheduled hour this is)')
    ap.add_argument('--date', default=None, help='YYYY-MM-DD to summarise (default: today, or yesterday for slot 08)')
    ap.add_argument('--send', action='store_true', help='actually send and record. Without it: dry run (nothing sent, nothing recorded)')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('NOTIFY_BOT_EMAIL') or oc.env('BOT_EMAIL', required=True), oc.env('NOTIFY_BOT_PASSWORD') or oc.env('BOT_PASSWORD', required=True))
        if a.send and send_email is None:
            user, pw = oc.env('GMAIL_USER'), oc.env('GMAIL_APP_PASSWORD')
            if pw:
                oc.REDACT.add(pw)

            def send_email(to, subject, text, htm):
                if not (user and pw):
                    raise RuntimeError('GMAIL_USER / GMAIL_APP_PASSWORD not set')
                nd.smtp_send(nd.make_message(subject, text, htm, user, [to]), user=user, password=pw)
        if a.send and send_telegram is None:
            tok = oc.env('TELEGRAM_BOT_TOKEN')
            if tok:
                send_telegram = telegram_sender(tok)
            else:
                def send_telegram(chat_id, text):   # each telegram recipient is then recorded as failed; e-mail still goes
                    raise RuntimeError('TELEGRAM_BOT_TOKEN is not set (GitHub secret)')
        r = run(api, send_email, send_telegram, slot=a.slot, day_override=a.date, send=a.send)
        return 0 if not r.get('failed') else 1
    except SystemExit:
        raise
    except Exception as e:
        oc.log('OWNER SUMMARY FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

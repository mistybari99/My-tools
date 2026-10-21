#!/usr/bin/env python3
"""Gmail alerts and the daily digest for Islamia BOS, run by GitHub Actions (.github/workflows/notify.yml). Python 3 standard library only.

What one run does:
  1. Logs in as the dedicated "ops bot" (purpose 'notify') with the public anon key - never the service_role key.
  2. notify_config()  -> is e-mail on, at which hours the digest goes.
  3. notify_scan()    -> makes today's in-app notifications (idempotent per day; also what the bell shows).
  4. urgent_alerts()  -> new "bad" notifications not yet e-mailed  -> ONE short e-mail; only after Gmail accepted it, notifications_mark_emailed(ids).
  5. In --mode digest, for the slot ("08" = yesterday's numbers, "21" = today's, "manual" = today) if that hour is enabled: daily_digest(date) -> a plain,
     mobile-friendly e-mail in Bangla + English (numbers only; the server decides the figures, this script only lays them out).
Mail goes through Gmail SMTP over SSL (smtp.gmail.com:465) with a Google "app password". Secrets (environment only, never printed):
  SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL, NOTIFY_BOT_PASSWORD (falls back to BOT_EMAIL / BOT_PASSWORD), GMAIL_USER, GMAIL_APP_PASSWORD, MAIL_TO (comma list).
--dry-run: logs in and READS (config, urgent alerts, digest), prints the e-mail(s) to the screen, and sends nothing, marks nothing, scans nothing.
"""
import argparse
import datetime
import html
import os
import re
import smtplib
import ssl
import sys
from email.message import EmailMessage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

DHAKA = datetime.timezone(datetime.timedelta(hours=6))
MAIL_RE = re.compile(r'^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$')


# ---------- small formatting helpers ----------
def money(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return '-'
    s = f'{abs(x):,.0f}' if abs(x - round(x)) < 0.005 else f'{abs(x):,.2f}'
    return ('-' if x < 0 else '') + '৳' + s


def pct(v):
    if v is None:
        return ''
    return f' ({float(v):+.1f}%)'


def g(d, *path, default=None):
    for p in path:
        if isinstance(d, dict) and p in d:
            d = d[p]
        elif isinstance(d, list) and isinstance(p, int) and -len(d) <= p < len(d):
            d = d[p]
        else:
            return default
    return d


def bi(bn, en):
    return f'{bn} / {en}'


# ---------- e-mail content ----------
def digest_sections(d):
    """Returns [(title, [(label, value), ...]), ...] in reading order. Pure function of the server's numbers."""
    s = g(d, 'sales', default={}) or {}
    sec = []
    rows = [(bi('নিট বিক্রি', 'Net sales'), money(g(s, 'today', 'net')) + pct(g(s, 'vs_yesterday_pct')) + ' ' + bi('গতকালের তুলনায়', 'vs yesterday')),
            (bi('গতকাল', 'Yesterday'), money(g(s, 'yesterday', 'net'))),
            (bi('গত সপ্তাহ একই দিন', 'Same day last week'), money(g(s, 'last_week', 'net')) + pct(g(s, 'vs_last_week_pct'))),
            (bi('বিল', 'Bills'), str(g(s, 'today', 'bills', default=0)))]
    for loc in g(s, 'by_location', default=[]) or []:
        rows.append(('  ' + bi(loc.get('name_bn') or '', loc.get('name_en') or ''), money(loc.get('net'))))
    sec.append((bi('বিক্রি', 'Sales'), rows))
    top = g(d, 'top_items', default=[]) or []
    if top:
        sec.append((bi('সেরা ৫ আইটেম', 'Top 5 items'), [(f"{i + 1}. {t.get('name')}", f"{money(t.get('amount'))} ({t.get('qty')})") for i, t in enumerate(top)]))
    sec.append((bi('ক্যাশ ও আদায়', 'Cash and collections'), [
        (bi('ক্যাশ কম', 'Cash short'), money(g(d, 'cash', 'short', default=0))), (bi('ক্যাশ বেশি', 'Cash over'), money(g(d, 'cash', 'over', default=0))),
        (bi('বাকি আদায়', 'Collections'), money(g(d, 'collections', default=0)))]))
    sec.append((bi('পাওনা-দেনা', 'Dues'), [
        (bi('গ্রাহকের বাকি', 'Customer dues') + f" ({g(d, 'dues', 'customers', default=0)})", money(g(d, 'dues', 'customers_total', default=0))),
        (bi('সরবরাহকারীর পাওনা', 'Supplier payable'), money(g(d, 'dues', 'suppliers', 'payable', default=0))),
        (bi('এর মধ্যে মেয়াদোত্তীর্ণ', 'of which overdue'), money(g(d, 'dues', 'suppliers', 'overdue', default=0)))]))
    sec.append((bi('অপচয়, বাতিল, ডিসকাউন্ট', 'Wastage, voids, discounts'), [
        (bi('অপচয়', 'Wastage') + f" ({g(d, 'wastage', 'count', default=0)})", money(g(d, 'wastage', 'value', default=0))),
        (bi('বাতিল বিল', 'Voided bills') + f" ({g(d, 'voids_discounts', 'void_count', default=0)})", money(g(d, 'voids_discounts', 'void_total', default=0))),
        (bi('ডিসকাউন্ট', 'Discounts') + f" ({g(d, 'voids_discounts', 'discount_count', default=0)})", money(g(d, 'voids_discounts', 'discount_total', default=0)))]))
    sec.append((bi('নজর দিন', 'Needs attention'), [
        (bi('লাল এক্সেপশন', 'Red exceptions'), str(g(d, 'exceptions_open', 'red', default=0))), (bi('হলুদ এক্সেপশন', 'Yellow exceptions'), str(g(d, 'exceptions_open', 'yellow', default=0))),
        (bi('অনুমোদন বাকি', 'Approvals waiting'), str(g(d, 'approvals_pending', default=0))),
        (bi('কম স্টকের আইটেম', 'Low-stock items'), str(g(d, 'stock_alerts', 'low_items', default=0))),
        (bi('মেয়াদ শেষ হতে চলা ব্যাচ', 'Batches expiring'), str(g(d, 'stock_alerts', 'expiring_batches', default=0)))]))
    dc = []
    for sh in g(d, 'day_close', default=[]) or []:
        state = bi('কাগজে', 'paper') if sh.get('mode') == 'paper' else (bi('জমা হয়েছে', 'closed') if sh.get('closed') else bi('জমা হয়নি', 'NOT closed'))
        dc.append((bi(sh.get('name_bn') or '', sh.get('name_en') or ''), state))
    if dc:
        sec.append((bi('দিন-শেষ (০৬-১)', 'Day-close (06-1)'), dc))
    b = g(d, 'backup', default={}) or {}
    if b:
        age = g(b, 'age_hours')
        sec.append((bi('ব্যাকআপ', 'Backup'), [(bi('শেষ সফল', 'Last good one'), (f'{age} ' + bi('ঘণ্টা আগে', 'hours ago')) if age is not None else bi('এখনো নেই', 'none yet')),
                                              (bi('অবস্থা', 'Status'), bi('পুরনো!', 'STALE!') if b.get('stale') else bi('ঠিক আছে', 'ok'))]))
    return sec


def render(subject, heading, sections, footer=''):
    """sections = [(title, [(label, value), ...])]. Returns (text, html)."""
    t = [heading, '=' * min(len(heading), 60)]
    for title, rows in sections:
        t.append('')
        t.append(title)
        t.append('-' * min(len(title), 60))
        t.extend(f'{a}: {b}' if b != '' else a for a, b in rows)
    if footer:
        t += ['', footer]
    h = ['<!doctype html><html><body style="margin:0;padding:12px;background:#f6f1ea;font-family:Arial,Helvetica,sans-serif;color:#222">',
         '<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:10px;padding:14px">',
         f'<h2 style="margin:0 0 8px;font-size:18px">{html.escape(heading)}</h2>']
    for title, rows in sections:
        h.append(f'<h3 style="margin:14px 0 4px;font-size:15px;color:#7a1f2b">{html.escape(title)}</h3><table width="100%" cellpadding="3" cellspacing="0" style="font-size:14px;border-collapse:collapse">')
        for a, b in rows:
            h.append(f'<tr style="border-bottom:1px solid #eee"><td style="vertical-align:top">{html.escape(a)}</td><td align="right" style="vertical-align:top;white-space:nowrap"><b>{html.escape(str(b))}</b></td></tr>')
        h.append('</table>')
    if footer:
        h.append(f'<p style="color:#777;font-size:12px">{html.escape(footer)}</p>')
    h.append('</div></body></html>')
    return '\n'.join(t) + '\n', '\n'.join(h)


def build_digest(d, app_url=''):
    date = g(d, 'date', default='')
    heading = bi('দৈনিক সারাংশ', 'Daily summary') + f' - {date}'
    subject = f"[Islamia BOS] {bi('দৈনিক সারাংশ', 'Daily summary')} {date}"
    text, htm = render(subject, heading, digest_sections(d), app_url)
    return subject, text, htm


def build_urgent(alerts, app_url=''):
    n = len(alerts)
    subject = f"[Islamia BOS] {bi('জরুরি', 'URGENT')}: {n} " + bi('সতর্কতা', 'alert(s)') + ' - ' + (alerts[0].get('title_en') or alerts[0].get('title_bn') or '')[:60]
    rows = []
    for a in alerts:
        rows.append((a.get('title_bn') or '', ''))
        rows.append((a.get('title_en') or '', ''))
        body = ' / '.join(x for x in (a.get('body_bn'), a.get('body_en')) if x)
        if body:
            rows.append(('  ' + body, ''))
    text, htm = render(subject, bi('জরুরি সতর্কতা', 'Urgent alerts'), [(bi('নতুন', 'New'), rows)], app_url)
    return subject, text, htm


def make_message(subject, text, htm, sender, to):
    m = EmailMessage()
    m['Subject'] = subject
    m['From'] = sender
    m['To'] = ', '.join(to)
    m.set_content(text)
    m.add_alternative(htm, subtype='html')
    return m


# ---------- sending ----------
def smtp_send(msg, host='smtp.gmail.com', port=465, user='', password='', security='ssl'):
    """security: 'ssl' (Gmail, default) | 'plain' (only for tests against a local stub server)."""
    if security == 'plain':
        with smtplib.SMTP(host, port, timeout=30) as s:
            s.send_message(msg)
        return
    with smtplib.SMTP_SSL(host, port, context=ssl.create_default_context(), timeout=30) as s:
        s.login(user, password)
        s.send_message(msg)


def parse_recipients(raw):
    out = [x.strip() for x in re.split(r'[,;\s]+', raw or '') if x.strip()]
    bad = [x for x in out if not MAIL_RE.match(x)]
    if bad or not out or len(out) > 10:
        raise SystemExit('MAIL_TO must be 1 to 10 valid e-mail addresses separated by commas')
    return out


# ---------- the run ----------
def dhaka_today(now=None):
    return (now or datetime.datetime.now(DHAKA)).astimezone(DHAKA).date()


def digest_wanted(times, slot):
    times = (times or '08,21').strip()
    if times == 'off':
        return False
    return slot == 'manual' or slot in {x.strip() for x in times.split(',')}


def run(api, send, mode='scan', slot='manual', dry=False, app_url='', now=None, out=print):
    """send(subject, text, html) delivers one mail (the caller binds the recipients and SMTP settings). Returns a summary dict."""
    res = {'scan_created': None, 'urgent': 0, 'urgent_sent': False, 'digest_sent': False, 'email_on': None}
    cfg = api.rpc('notify_config')
    res['email_on'] = bool(cfg.get('email_on'))
    if not dry:
        sc = api.rpc('notify_scan')
        res['scan_created'] = sc.get('created')
        oc.log(f"scan: {sc.get('created')} new notification(s)")
        try:   # bos98 (W1-G): scheduled journal posting. The server answers "skipped" while the switch journal_sched_post_on is OFF (default).
            jp = api.rpc('_w1g_post_scheduled', {'p_dry': False})
            res['journal'] = {k: jp.get(k) for k in ('posted', 'reversed', 'left', 'skipped')} if isinstance(jp, dict) else None
            oc.log('journal posting:', res['journal'])
        except Exception as e:   # the alerts and the digest must never stop because the books could not be posted
            res['journal'] = {'error': type(e).__name__}
            oc.log('journal posting failed:', type(e).__name__)
        try:   # bos326 (CRM-G): in-app task reminders. The server answers "skipped" while the switch crm_task_reminder_on is OFF (default); a failure never stops the alerts.
            ts = api.rpc('_crmg_task_scan', {'p_dry': False})
            res['crm_tasks'] = {k: ts.get(k) for k in ('created', 'people', 'skipped')} if isinstance(ts, dict) else None
            oc.log('task reminders:', res['crm_tasks'])
        except Exception as e:   # the alerts and the digest must never stop because a reminder could not be made
            res['crm_tasks'] = {'error': type(e).__name__}
            oc.log('task reminders failed:', type(e).__name__)
        try:   # bos328 (CRM-H): mark complaints that passed their target time. The server answers "skipped" while the switch crm_complaints_on is OFF (default).
            cs = api.rpc('_crmh_sla_scan', {'p_dry': False})
            res['complaints'] = {k: cs.get(k) for k in ('marked', 'skipped')} if isinstance(cs, dict) else None
            oc.log('complaint check:', res['complaints'])
        except Exception as e:   # the alerts and the digest must never stop because the complaint check failed
            res['complaints'] = {'error': type(e).__name__}
            oc.log('complaint check failed:', type(e).__name__)
    if not res['email_on']:
        oc.log('e-mail is switched OFF in the Switchboard (notify_email_on): nothing is sent')
        return res
    alerts = api.rpc('urgent_alerts', {}) or []
    res['urgent'] = len(alerts)
    if alerts:
        subj, text, htm = build_urgent(alerts, app_url)
        if dry:
            out(f'--- DRY RUN: urgent e-mail ---\nSubject: {subj}\n\n{text}')
        else:
            send(subj, text, htm)
            res['urgent_sent'] = True
            api.rpc('notifications_mark_emailed', {'p_ids': [int(a['id']) for a in alerts]})
    if mode == 'digest' and digest_wanted(cfg.get('digest_times'), slot):
        day = dhaka_today(now)
        if slot == '08':
            day = day - datetime.timedelta(days=1)       # the morning mail reports the day that just ended
        d = api.rpc('daily_digest', {'p_date': day.isoformat()})
        subj, text, htm = build_digest(d, app_url)
        if dry:
            out(f'--- DRY RUN: daily digest ---\nSubject: {subj}\n\n{text}')
        else:
            send(subj, text, htm)
            res['digest_sent'] = True
    return res


def main(argv=None, api=None, send=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--mode', choices=['scan', 'digest'], default='scan', help='scan = scan + urgent mail (every 30 min); digest = also the daily digest')
    ap.add_argument('--slot', default='manual', help='08 | 21 | manual (which scheduled hour this is)')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('NOTIFY_BOT_EMAIL') or oc.env('BOT_EMAIL', required=True), oc.env('NOTIFY_BOT_PASSWORD') or oc.env('BOT_PASSWORD', required=True))
        if send is None and not a.dry_run:
            user, pw = oc.env('GMAIL_USER', required=True), oc.env('GMAIL_APP_PASSWORD', required=True)
            oc.REDACT.add(pw)
            to = parse_recipients(oc.env('MAIL_TO', required=True))
            host, port, sec = oc.env('SMTP_HOST', 'smtp.gmail.com'), int(oc.env('SMTP_PORT', '465')), oc.env('SMTP_SECURITY', 'ssl')

            def send(subject, text, htm):
                smtp_send(make_message(subject, text, htm, user, to), host, port, user, pw, sec)
        r = run(api, send, mode=a.mode, slot=a.slot, dry=a.dry_run, app_url=oc.env('APP_URL', ''))
        oc.log('done:', r)
        return 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('NOTIFY FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""SMS / WhatsApp sender for Islamia BOS. Python 3 standard library only. DEFAULT OFF - it sends nothing unless BOTH switches are on.

What one run does (see supabase/phase62.sql, docs/INTEGRATIONS_P3C.md):
  1. Logs in as the dedicated "ops bot" (purpose 'notify', the same bot as notify_digest.py) with the public anon key - never the service_role key.
  2. notify_outbox_claim(limit) -> the due queued messages (the server returns nothing while the Switchboard switch notify_sms_on is OFF).
  3. For each message calls the provider ONCE over HTTPS (generic JSON POST adapter below) and reports notify_outbox_report(id, ok, provider_ref, error).
     The server counts attempts, backs off (2, 4, 8 ... minutes) and gives up as 'failed' after the maximum tries. A crashed run is safe: rows left 'sending' are re-claimed after 15 minutes.
Sending is a second, local switch: SMS_SEND_ENABLED=1 must be set, otherwise the run claims and sends nothing.
Secrets (environment only, never printed, never in the repo):
  SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL, NOTIFY_BOT_PASSWORD (falls back to BOT_EMAIL / BOT_PASSWORD),
  SMS_PROVIDER_URL (https endpoint of your SMS / WhatsApp gateway), SMS_PROVIDER_TOKEN (bearer token), optional SMS_SENDER (sender id), SMS_SEND_ENABLED=1.
The adapter posts {"to": "+8801...", "message": "...", "channel": "sms|whatsapp", "sender": "..."} with "Authorization: Bearer <token>" and treats any 2xx as accepted;
a "id" / "message_id" / "reference" field of a JSON reply is kept as the provider reference. Providers with another shape: replace post_message() only.
--dry-run: logs in only (to prove the credentials) and sends / claims nothing.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402


def post_message(url, token, row, sender='', timeout=30):
    """Returns (ok, provider_ref, error). Never raises for provider/network errors; the token is never part of an error text."""
    body = json.dumps({'to': row['to'], 'message': row['body'], 'channel': row.get('channel', 'sms'), 'sender': sender}).encode()
    req = urllib.request.Request(url, data=body, method='POST', headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            ref = None
            try:
                j = json.loads(raw) if raw else {}
                if isinstance(j, dict):
                    ref = next((str(j[k]) for k in ('id', 'message_id', 'reference') if j.get(k) is not None), None)
            except ValueError:
                pass
            return True, ref, None
    except urllib.error.HTTPError as e:
        return False, None, f'provider HTTP {e.code}'
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return False, None, f'network error: {type(e).__name__}'


def run(api, send, limit=20, enabled=False, out=print):
    """send(row) -> (ok, ref, error). Returns a summary dict. Does nothing at all unless enabled."""
    res = {'enabled': enabled, 'claimed': 0, 'sent': 0, 'failed': 0, 'server_on': None}
    if not enabled:
        oc.log('SMS_SEND_ENABLED is not 1: nothing is claimed or sent (default OFF)')
        return res
    c = api.rpc('notify_outbox_claim', {'p_limit': limit}) or {}
    res['server_on'] = bool(c.get('on'))
    if not res['server_on']:
        oc.log('notify_sms_on is OFF in the Switchboard: nothing is sent')
        return res
    rows = c.get('rows') or []
    res['claimed'] = len(rows)
    for row in rows:
        ok, ref, err = send(row)
        api.rpc('notify_outbox_report', {'p_id': int(row['id']), 'p_ok': bool(ok), 'p_provider_ref': ref, 'p_error': None if ok else (err or 'error')})
        res['sent' if ok else 'failed'] += 1
    return res


def main(argv=None, api=None, send=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--limit', type=int, default=20)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('NOTIFY_BOT_EMAIL') or oc.env('BOT_EMAIL', required=True), oc.env('NOTIFY_BOT_PASSWORD') or oc.env('BOT_PASSWORD', required=True))
        enabled = oc.env('SMS_SEND_ENABLED', '0') == '1' and not a.dry_run
        if send is None and enabled:
            url, tok = oc.env('SMS_PROVIDER_URL', required=True), oc.env('SMS_PROVIDER_TOKEN', required=True)
            oc.REDACT.add(tok)
            if not url.startswith('https://'):
                raise SystemExit('SMS_PROVIDER_URL must be an https:// address')
            sender = oc.env('SMS_SENDER', '')

            def send(row):
                return post_message(url, tok, row, sender)
        r = run(api, send, limit=max(1, min(a.limit, 100)), enabled=enabled)
        oc.log('done:', r)
        return 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('SMS RUN FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

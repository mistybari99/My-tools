#!/usr/bin/env python3
"""Social publisher for Islamia BOS (X3). Python 3 standard library only. DEFAULT OFF and DRY-RUN: it sends nothing unless BOTH switches are on.

What one run does (see supabase/phase483.sql, docs/integration/X3.md):
  1. Logs in as the ops bot (purpose 'notify', the same login as tools/notify_sms.py) with the public anon key - never the service_role key.
  2. social_publish_claim(limit) -> the due deliveries. The server returns nothing while social_publish_on is OFF, while the emergency stop
     social_stop_all is ON, in quiet hours, when the per-day / per-hour limits are blank or reached, and it re-checks consent for WhatsApp rows.
     Claimed rows get a 15-minute lease, so a crashed run is safe: the server hands the row out again after the lease.
  3. For each row the channel adapter posts ONCE and social_publish_report(id, ok, provider_post_id, permalink, error) is called.
     The server counts attempts, backs off (2, 4, 8 ... minutes) and gives up as 'failed' after social_retry_max tries.
  Nothing is posted twice: each delivery has a unique idempotency key on the server (item and channel, or item and customer).

Sending needs BOTH: the flag --send AND the environment variable SOCIAL_SEND_ENABLED=1. Otherwise a dry run: log in only, claim nothing.

Adapters (UNVERIFIED until live: the request shapes follow Meta's documented Graph API and WhatsApp Cloud API as known when this was written.
Check them against the current Meta documentation and run one test post to a test Page before switching on):
  facebook   Graph API Page posts: POST /{page-id}/feed (text, optional link), /{page-id}/photos (image url), /{page-id}/videos (file_url).
  instagram  Graph API two steps: POST /{ig-user-id}/media (image_url or video_url for REELS), then POST /{ig-user-id}/media_publish.
             Instagram needs a PUBLIC media URL (SOCIAL_MEDIA_BASE_URL).
  whatsapp   WhatsApp Cloud API TEMPLATE message only: POST /{phone-number-id}/messages with type 'template'. Free text is refused by the API outside a
             24-hour window, so only templates are sent. The template language code comes from SOCIAL_WA_LANG (never guessed).
  webhook    generic: POST the row as JSON to SOCIAL_WEBHOOK_URL (https only), Bearer token from SOCIAL_WEBHOOK_TOKEN. Any 2xx = accepted.

Secrets (environment only, never printed, never in the repo or the database):
  SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL, NOTIFY_BOT_PASSWORD (falls back to BOT_EMAIL / BOT_PASSWORD),
  SOCIAL_FB_PAGE_ID, SOCIAL_FB_PAGE_TOKEN, SOCIAL_IG_USER_ID (the page token is used for Instagram too unless SOCIAL_IG_TOKEN is set),
  SOCIAL_WA_PHONE_NUMBER_ID, SOCIAL_WA_TOKEN, SOCIAL_WA_LANG, SOCIAL_WEBHOOK_URL, SOCIAL_WEBHOOK_TOKEN,
  SOCIAL_MEDIA_BASE_URL (public https address the media files are read from; needed when a post has media), SOCIAL_SEND_ENABLED=1.
A channel whose secrets are missing fails its row with a short reason (the failure goes to the failed list; nothing is sent).
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

GRAPH = 'https://graph.facebook.com/v19.0'          # pinned API version; change deliberately after checking Meta's changelog
TIMEOUT = 30


class AdapterError(Exception):
    """A failure with a short, safe reason (never a token, never a URL with a token)."""


def _http_json(method, url, body=None, headers=None, timeout=TIMEOUT):
    """POST/GET JSON. Returns the decoded reply (dict) or raises AdapterError with a safe reason."""
    data = None if body is None else json.dumps(body).encode()
    h = {'Content-Type': 'application/json'}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise AdapterError(f'provider HTTP {e.code}')
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise AdapterError(f'network error: {type(e).__name__}')
    except ValueError:
        return {}


def caption_text(row):
    """Bangla first, English second, then the hashtags. Built from the approved item only."""
    parts = [p for p in (row.get('caption_bn'), row.get('caption_en')) if p]
    tags = ' '.join('#' + str(t).lstrip('#') for t in (row.get('hashtags') or []) if t)
    if tags:
        parts.append(tags)
    return '\n\n'.join(parts)


def media_url(row, index=0):
    base = oc.env('SOCIAL_MEDIA_BASE_URL', '')
    media = row.get('media') or []
    if not media:
        return None
    if not base.startswith('https://'):
        raise AdapterError('media_url_not_configured: SOCIAL_MEDIA_BASE_URL must be an https address')
    return base.rstrip('/') + '/' + urllib.parse.quote(str(media[index]['path']))


class FacebookPageAdapter:
    channel = 'facebook'

    def __init__(self, page_id, token):
        if not page_id or not token:
            raise AdapterError('not_configured: SOCIAL_FB_PAGE_ID / SOCIAL_FB_PAGE_TOKEN')
        self.page_id, self.token = page_id, token
        oc.REDACT.add(token)

    def send(self, row):
        text = caption_text(row)
        media = row.get('media') or []
        q = {'access_token': self.token}
        if not media:
            r = _http_json('POST', f'{GRAPH}/{self.page_id}/feed?' + urllib.parse.urlencode(q), {'message': text})
        elif media[0]['kind'] == 'image':
            r = _http_json('POST', f'{GRAPH}/{self.page_id}/photos?' + urllib.parse.urlencode(q), {'url': media_url(row), 'caption': text})
        else:
            r = _http_json('POST', f'{GRAPH}/{self.page_id}/videos?' + urllib.parse.urlencode(q), {'file_url': media_url(row), 'description': text})
        pid = r.get('id') or r.get('post_id')
        if not pid:
            raise AdapterError('provider gave no post id')
        return str(pid), None


class InstagramAdapter:
    channel = 'instagram'

    def __init__(self, user_id, token):
        if not user_id or not token:
            raise AdapterError('not_configured: SOCIAL_IG_USER_ID / token')
        self.user_id, self.token = user_id, token
        oc.REDACT.add(token)

    def send(self, row):
        media = row.get('media') or []
        if not media:
            raise AdapterError('instagram_needs_media: a post on Instagram needs a picture or a video')
        body = {'caption': caption_text(row)}
        if media[0]['kind'] == 'image':
            body['image_url'] = media_url(row)
        else:
            body.update({'media_type': 'REELS', 'video_url': media_url(row)})
        q = urllib.parse.urlencode({'access_token': self.token})
        c = _http_json('POST', f'{GRAPH}/{self.user_id}/media?{q}', body)
        if not c.get('id'):
            raise AdapterError('provider gave no container id')
        p = _http_json('POST', f'{GRAPH}/{self.user_id}/media_publish?{q}', {'creation_id': c['id']})
        if not p.get('id'):
            raise AdapterError('provider gave no media id')
        return str(p['id']), None


class WhatsAppTemplateAdapter:
    channel = 'whatsapp'

    def __init__(self, phone_number_id, token, lang):
        if not phone_number_id or not token:
            raise AdapterError('not_configured: SOCIAL_WA_PHONE_NUMBER_ID / SOCIAL_WA_TOKEN')
        if not lang:
            raise AdapterError('not_configured: SOCIAL_WA_LANG (the template language code)')
        self.phone_number_id, self.token, self.lang = phone_number_id, token, lang
        oc.REDACT.add(token)

    def send(self, row):
        to = str(row.get('to') or '')
        if not to.startswith('+'):
            raise AdapterError('bad_phone')
        if not row.get('template_code'):
            raise AdapterError('template_required')
        body = {'messaging_product': 'whatsapp', 'to': to[1:], 'type': 'template',
                'template': {'name': row['template_code'], 'language': {'code': self.lang}}}
        r = _http_json('POST', f'{GRAPH}/{self.phone_number_id}/messages', body, headers={'Authorization': 'Bearer ' + self.token})
        msgs = r.get('messages') or []
        ref = msgs[0].get('id') if msgs and isinstance(msgs[0], dict) else None
        return (str(ref) if ref else 'sent'), None


class GenericWebhookAdapter:
    channel = 'webhook'

    def __init__(self, url, token=''):
        if not url or not url.startswith('https://'):
            raise AdapterError('not_configured: SOCIAL_WEBHOOK_URL must be an https address')
        self.url, self.token = url, token
        oc.REDACT.add(token)

    def send(self, row):
        payload = {'item_id': row.get('item_id'), 'channel': 'webhook', 'title': row.get('title'), 'caption': caption_text(row),
                   'media': [{'path': m.get('path'), 'kind': m.get('kind'), 'url': media_url(row, i)} for i, m in enumerate(row.get('media') or [])]}
        headers = {'Authorization': 'Bearer ' + self.token} if self.token else {}
        r = _http_json('POST', self.url, payload, headers=headers)
        ref = r.get('id') if isinstance(r, dict) else None
        return (str(ref) if ref is not None else 'accepted'), None


class _Lazy:
    """Builds the real adapter only when a row for that channel arrives, so a channel with no secrets fails its own rows and nothing else."""

    def __init__(self, factory):
        self.factory = factory

    def send(self, row):
        return self.factory().send(row)


def build_adapters(env=oc.env):
    """One adapter per channel. A channel whose secrets are missing fails its own rows with 'not_configured' (never guessed)."""
    return {
        'facebook': _Lazy(lambda: FacebookPageAdapter(env('SOCIAL_FB_PAGE_ID', ''), env('SOCIAL_FB_PAGE_TOKEN', ''))),
        'instagram': _Lazy(lambda: InstagramAdapter(env('SOCIAL_IG_USER_ID', ''), env('SOCIAL_IG_TOKEN', '') or env('SOCIAL_FB_PAGE_TOKEN', ''))),
        'whatsapp': _Lazy(lambda: WhatsAppTemplateAdapter(env('SOCIAL_WA_PHONE_NUMBER_ID', ''), env('SOCIAL_WA_TOKEN', ''), env('SOCIAL_WA_LANG', ''))),
        'webhook': _Lazy(lambda: GenericWebhookAdapter(env('SOCIAL_WEBHOOK_URL', ''), env('SOCIAL_WEBHOOK_TOKEN', ''))),
    }


def run(api, adapters, limit=10, enabled=False):
    """Claims due rows and reports each result once. Does nothing at all unless enabled. adapters: {channel: obj with send(row) -> (ref, permalink)}."""
    res = {'enabled': enabled, 'claimed': 0, 'published': 0, 'failed': 0, 'server_on': None, 'reason': None}
    if not enabled:
        oc.log('SOCIAL_SEND_ENABLED is not 1 or --send is missing: nothing is claimed or posted (dry run)')
        return res
    c = api.rpc('social_publish_claim', {'p_limit': int(limit)}) or {}
    res['server_on'] = bool(c.get('on'))
    res['reason'] = c.get('reason')
    if not res['server_on']:
        oc.log('the server says publishing is not running now:', res['reason'] or 'off')
        return res
    rows = c.get('rows') or []
    res['claimed'] = len(rows)
    for row in rows:
        ad = adapters.get(row.get('channel'))
        ok, ref, permalink, err = False, None, None, 'unknown_channel'
        if ad is not None:
            try:
                ref, permalink = ad.send(row)
                ok, err = True, None
            except AdapterError as e:
                err = str(e)
            except Exception as e:                       # never let one row stop the run; the reason is the exception type only
                err = f'adapter error: {type(e).__name__}'
        api.rpc('social_publish_report', {'p_id': int(row['id']), 'p_ok': bool(ok), 'p_provider_post_id': ref if ok else None,
                                          'p_permalink': permalink if ok else None, 'p_error': None if ok else (err or 'error')})
        res['published' if ok else 'failed'] += 1
    return res


def main(argv=None, api=None, adapters=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--limit', type=int, default=10)
    ap.add_argument('--send', action='store_true', help='actually post (also needs SOCIAL_SEND_ENABLED=1)')
    ap.add_argument('--dry-run', action='store_true', help='log in only; claim and post nothing (the default)')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('NOTIFY_BOT_EMAIL') or oc.env('BOT_EMAIL', required=True), oc.env('NOTIFY_BOT_PASSWORD') or oc.env('BOT_PASSWORD', required=True))
        enabled = a.send and not a.dry_run and oc.env('SOCIAL_SEND_ENABLED', '0') == '1'
        if adapters is None and enabled:
            adapters = build_adapters()
        r = run(api, adapters or {}, limit=max(1, min(a.limit, 50)), enabled=enabled)
        oc.log('done:', r)
        return 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('SOCIAL PUBLISH RUN FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

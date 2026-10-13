"""Shared helpers for the ops scripts (backup_dump.py, backup_photos.py, notify_digest.py). Python 3 standard library only.

* Api: tiny Supabase client (password login for the dedicated "ops bot" user, PostgREST rpc, Storage) with retries and back-off.
* Redaction: every secret that is handed to the process (passwords, keys) and every token-looking string is replaced by *** in anything that is printed.
Secrets are only ever read from environment variables (GitHub Actions secrets) - never from a file, never printed, never written to the output.
The Supabase service_role key is never used: the scripts send the public anon key plus the bot's own login token.
"""
import decimal
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN_RE = re.compile(r'(eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*)|(?i:bearer\s+)[A-Za-z0-9._\-]{12,}')


class Redactor:
    """Replaces known secret values and token-looking strings by ***."""

    def __init__(self, secrets=()):
        self.secrets = set()
        for s in secrets:
            self.add(s)

    def add(self, s):
        if s and len(str(s)) >= 4:
            self.secrets.add(str(s))

    def __call__(self, text):
        out = str(text)
        for s in sorted(self.secrets, key=len, reverse=True):
            out = out.replace(s, '***')
        return TOKEN_RE.sub('***', out)


REDACT = Redactor()


def log(*parts):
    """Print to stderr, redacted."""
    print(REDACT(' '.join(str(p) for p in parts)), file=sys.stderr, flush=True)


def loads_exact(text):
    """json.loads that keeps every decimal number exactly as written (Decimal, never float): '260.00' stays 260.00 and long numerics lose no digits."""
    return json.loads(text, parse_float=decimal.Decimal)


def dumps_exact(o):
    """Compact, key-sorted JSON that prints Decimals as plain decimal text (no exponent, no float rounding). Counterpart of loads_exact."""
    if isinstance(o, dict):
        return '{' + ','.join(json.dumps(str(k), ensure_ascii=False) + ':' + dumps_exact(v) for k, v in sorted(o.items())) + '}'
    if isinstance(o, (list, tuple)):
        return '[' + ','.join(dumps_exact(v) for v in o) + ']'
    if isinstance(o, decimal.Decimal):
        return format(o, 'f')
    return json.dumps(o, ensure_ascii=False)


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(REDACT(f'HTTP {status}: {message}'))
        self.status = status


def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        raise SystemExit(f'missing environment variable {name} (set it as a GitHub Actions secret; see docs/OPS_SETUP.md)')
    return v


class Api:
    """base_url = https://<project>.supabase.co ; anon_key = the public anon key (not a secret, but never the service_role key)."""

    def __init__(self, base_url, anon_key, retries=4, backoff=1.0, timeout=60, sleep=time.sleep):
        if not base_url or not anon_key:
            raise SystemExit('SUPABASE_URL and SUPABASE_ANON_KEY are required')
        self.base = base_url.rstrip('/')
        self.anon = anon_key
        self.retries, self.backoff, self.timeout, self.sleep = retries, backoff, timeout, sleep
        self.token = None
        self._cred = None
        self.attempts = 0                                 # total HTTP attempts (tests look at this)
        REDACT.add(anon_key)

    # ---- low level ----
    def _once(self, method, path, body, headers, raw):
        data = None if body is None else (body if isinstance(body, (bytes, bytearray)) else json.dumps(body).encode())
        h = {'apikey': self.anon, 'Content-Type': 'application/json'}
        if self.token:
            h['Authorization'] = 'Bearer ' + self.token
        h.update(headers or {})
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=h)
        with urllib.request.urlopen(req, timeout=self.timeout) as r:
            payload = r.read()
        if raw:
            return payload
        return loads_exact(payload) if payload else None

    def request(self, method, path, body=None, headers=None, raw=False):
        """Retries network errors, 408, 429 and 5xx with exponential back-off; a 401 re-logs in once; other 4xx fail at once."""
        last = None
        relogged = False
        for i in range(self.retries + 1):
            self.attempts += 1
            try:
                return self._once(method, path, body, headers, raw)
            except urllib.error.HTTPError as e:
                msg = e.read().decode('utf-8', 'replace')[:500]
                last = ApiError(e.code, msg)
                if e.code == 401 and self._cred and not relogged and not path.startswith('/auth/'):
                    relogged = True
                    self.login(*self._cred)
                    continue
                if e.code not in (408, 429) and e.code < 500:
                    raise last
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
                last = ApiError(0, f'network error: {e}')
            if i < self.retries:
                delay = self.backoff * (2 ** i)
                log(f'retry {i + 1}/{self.retries} in {delay:g}s ({last})')
                self.sleep(delay)
        raise last

    # ---- supabase ----
    def login(self, email, password):
        REDACT.add(password)
        self._cred = (email, password)
        self.token = None
        r = self.request('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': password})
        tok = (r or {}).get('access_token')
        if not tok:
            raise ApiError(0, 'login gave no access token')
        self.token = tok
        REDACT.add(tok)
        return True

    def rpc(self, fn, args=None):
        return self.request('POST', '/rest/v1/rpc/' + urllib.parse.quote(fn), args or {})

    def storage_list(self, bucket, prefix='', limit=1000, offset=0):
        return self.request('POST', f'/storage/v1/object/list/{urllib.parse.quote(bucket)}',
                            {'prefix': prefix, 'limit': limit, 'offset': offset, 'sortBy': {'column': 'name', 'order': 'asc'}})

    def storage_get(self, bucket, path):
        return self.request('GET', f'/storage/v1/object/authenticated/{urllib.parse.quote(bucket)}/{urllib.parse.quote(path)}', raw=True,
                            headers={'Content-Type': 'application/octet-stream'})

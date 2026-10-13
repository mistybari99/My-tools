#!/usr/bin/env python3
"""Full data backup of the Islamia BOS database, run by GitHub Actions (.github/workflows/backup.yml) with no person and no sandbox involved.

How it works (Python 3 standard library only):
  1. Logs in to Supabase Auth as the dedicated "ops bot" user (NOT the owner, NOT the service_role key) with the PUBLIC anon key.
  2. backup_manifest()  -> the list of tables the server allows, their row counts and a schema fingerprint.
  3. backup_dump(table, cursor, limit) page by page (keyset pagination) -> out/<table>.ndjson.gz (one JSON row per line, sorted by primary key,
     gzip with a fixed timestamp so an unchanged table gives byte-identical output and the git history only grows by real changes).
  4. backup_manifest() again. A table passes only if  rows_at_start <= rows_dumped <= rows_at_end  (rows may be added while we read, never lost) and the
     schema fingerprint did not change during the run. Any mismatch = failure.
  5. out/manifest.json (counts, sha256 of every file, schema version/fingerprint, started/finished) and backup_log('ok'|'failed', ...) so the owner's app shows
     the run and warns when the last good backup is too old.
Exit code 0 only when everything is complete. Secrets come from the environment only: SUPABASE_URL, SUPABASE_ANON_KEY, BOT_EMAIL, BOT_PASSWORD. Nothing secret is printed.

Usage:  python3 tools/backup_dump.py [--out out] [--page 2000] [--tables a,b] [--no-log] [--destination github]
"""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

BIG_FILE_BYTES = 90 * 1024 * 1024        # GitHub refuses single files above 100 MB: warn early


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def write_gz(path, lines):
    """Deterministic gzip (mtime 0, no file name) of the given text lines. Returns (rows, bytes, sha256-of-the-file)."""
    buf = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=buf, mtime=0, compresslevel=9) as z:
        n = 0
        for ln in lines:
            z.write(ln.encode('utf-8'))
            z.write(b'\n')
            n += 1
    data = buf.getvalue()
    with open(path, 'wb') as f:
        f.write(data)
    return n, len(data), hashlib.sha256(data).hexdigest()


def dump_table(api, table, page):
    """Yields every row of one table as a compact JSON line, following the server cursor until it is exhausted."""
    cursor, seen, pages = None, set(), 0
    while True:
        r = api.rpc('backup_dump', {'p_table': table, 'p_after_id': cursor, 'p_limit': page})
        if not isinstance(r, dict) or 'rows' not in r:
            raise RuntimeError(f'{table}: unexpected answer from backup_dump')
        for row in r['rows']:
            yield oc.dumps_exact(row)
        cursor = r.get('next')
        pages += 1
        if cursor is None:
            return
        if cursor in seen or pages > 100000:
            raise RuntimeError(f'{table}: the cursor did not advance (stopping to avoid a loop)')
        seen.add(cursor)


def run(api, out_dir, page=2000, only=None, log_run=True, destination='github', clock=now_iso):
    """Returns the manifest dict. Raises on any failure (after trying to record the failure with backup_log)."""
    started = clock()
    os.makedirs(out_dir, exist_ok=True)
    try:
        m0 = api.rpc('backup_manifest')
        names = [t['name'] for t in m0['tables']]
        start_rows = {t['name']: int(t['rows']) for t in m0['tables']}
        if only:
            unknown = [t for t in only if t not in start_rows]
            if unknown:
                raise RuntimeError('tables not allowed or unknown: ' + ', '.join(unknown))
            names = list(only)
        # remove files of tables that no longer exist, so the folder is an exact picture of this run
        for f in ([] if only else os.listdir(out_dir)):
            if f.endswith('.ndjson.gz') and f[:-len('.ndjson.gz')] not in names:
                os.remove(os.path.join(out_dir, f))
        files, warnings, total_rows, total_bytes = {}, [], 0, 0
        for t in names:
            path = os.path.join(out_dir, t + '.ndjson.gz')
            n, size, sha = write_gz(path, dump_table(api, t, page))
            files[t] = {'file': t + '.ndjson.gz', 'rows': n, 'bytes': size, 'sha256': sha}
            total_rows += n
            total_bytes += size
            if size > BIG_FILE_BYTES:
                warnings.append(f'{t}: file is {size} bytes - too big for a normal git push; use the Drive copy')
            oc.log(f'{t}: {n} rows')
        m1 = api.rpc('backup_manifest')
        end_rows = {t['name']: int(t['rows']) for t in m1['tables']}
        problems = []
        if m0.get('fingerprint') != m1.get('fingerprint'):
            problems.append('the database schema changed while the backup ran')
        for t in names:
            lo, hi, got = start_rows[t], end_rows.get(t, start_rows[t]), files[t]['rows']
            if not (lo <= got <= max(lo, hi)):
                problems.append(f'{t}: dumped {got} rows but the server counted {lo}..{hi}')
        if problems:
            raise RuntimeError('; '.join(problems))
        finished = clock()
        manifest = {
            'tool': 'backup_dump.py', 'format': 1, 'schema_version': m0.get('schema_version'), 'schema_fingerprint': m0.get('fingerprint'),
            'started_at': started, 'finished_at': finished, 'table_count': len(names), 'rows': total_rows, 'bytes': total_bytes,
            'tables': {t: {**files[t], 'rows_at_start': start_rows[t], 'rows_at_end': end_rows.get(t)} for t in names},
            'warnings': warnings,
        }
        with open(os.path.join(out_dir, 'manifest.json'), 'w', encoding='utf-8') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')
        if log_run:
            api.rpc('backup_log', {'p_status': 'ok', 'p_detail': {'warnings': warnings, 'schema_fingerprint': m0.get('fingerprint')},
                                   'p_tables': len(names), 'p_rows': total_rows, 'p_bytes': total_bytes, 'p_destination': destination})
        return manifest
    except Exception as e:
        if log_run:
            try:
                api.rpc('backup_log', {'p_status': 'failed', 'p_detail': {'error': oc.REDACT(str(e))[:1500]}, 'p_destination': destination})
            except Exception as e2:  # the failure itself is what matters
                oc.log('could not record the failure:', e2)
        raise


def main(argv=None, api=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='out')
    ap.add_argument('--page', type=int, default=2000)
    ap.add_argument('--tables', default='', help='comma list (for a partial test run)')
    ap.add_argument('--no-log', action='store_true', help='do not call backup_log')
    ap.add_argument('--destination', default='github')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('BOT_EMAIL', required=True), oc.env('BOT_PASSWORD', required=True))
        only = [t for t in a.tables.split(',') if t.strip()] or None
        m = run(api, a.out, page=max(1, min(a.page, 5000)), only=only, log_run=not a.no_log, destination=a.destination)
        oc.log(f"backup OK: {m['table_count']} tables, {m['rows']} rows, {m['bytes']} bytes")
        gh = os.environ.get('GITHUB_OUTPUT')
        if gh:
            with open(gh, 'a') as f:
                f.write(f"rows={m['rows']}\ntables={m['table_count']}\n")
        return 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('BACKUP FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

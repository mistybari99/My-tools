#!/usr/bin/env python3
"""X1 job wrapper for the automation workflow (.github/workflows/automation.yml). Python 3 standard library only.

It does not change any existing script. One run:
  1. Logs in as the ops bot (purpose 'notify') with the public anon key - never the service_role key.
  2. job_run_start(job, dry_run) -> the database decides. automation_on OFF or paused = the run is recorded as skipped and nothing else happens.
  3. Runs the job:
       notify_sms      tools/notify_sms.py (its own switches apply; --dry-run passes through)
       intake_retry    rpc intake_retry_due (not called in a dry run; a dry run only reports that it would call it)
       heartbeat       job_heartbeat only (proves the scheduler and the bot still work)
  4. job_run_finish(run_id, ok, error, counts) - the error text is redacted by the database.
Secrets come only from the environment (GitHub Actions secrets): SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_BOT_EMAIL, NOTIFY_BOT_PASSWORD (falls back to BOT_EMAIL / BOT_PASSWORD).
Default is a DRY RUN: pass --live to act. Live work also needs the database switches (automation_on, the job's own switch).
"""
import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

JOBS = ('notify_sms', 'intake_retry', 'heartbeat')
HERE = os.path.dirname(os.path.abspath(__file__))


def run_notify_sms(dry):
    args = [sys.executable, os.path.join(HERE, 'notify_sms.py')] + (['--dry-run'] if dry else [])
    p = subprocess.run(args, capture_output=True, text=True, timeout=600)
    return p.returncode == 0, {'exit_code': p.returncode}, (p.stderr or '').strip()[-300:]


def run_intake_retry(api, dry):
    if dry:
        return True, {'would_call': 'intake_retry_due'}, None
    r = api.rpc('intake_retry_due', {'p_limit': 20}) or {}
    return True, {k: int(v) for k, v in r.items() if isinstance(v, (int, float))}, None


def run_heartbeat(api, dry):
    api.rpc('job_heartbeat', {'p_job': 'automation_tick', 'p_note': 'dry' if dry else 'live'})
    return True, {}, None


def run(api, job, dry, sms_runner=run_notify_sms):
    """Returns a dict: allowed, run_id, ok, counts, error. Never raises for a job failure (it is recorded)."""
    if job not in JOBS:
        raise SystemExit(f'unknown job {job!r}; one of {", ".join(JOBS)}')
    start = api.rpc('job_run_start', {'p_job': job, 'p_dry': bool(dry)}) or {}
    res = {'job': job, 'allowed': bool(start.get('allowed')), 'run_id': start.get('run_id'), 'reason': start.get('reason'), 'ok': None, 'counts': {}, 'error': None}
    if not res['allowed']:
        oc.log(f'{job}: not run - {start.get("reason")} (recorded as skipped)')
        return res
    try:
        if job == 'notify_sms':
            ok, counts, err = sms_runner(dry)
        elif job == 'intake_retry':
            ok, counts, err = run_intake_retry(api, dry)
        else:
            ok, counts, err = run_heartbeat(api, dry)
    except Exception as e:  # a failing job is recorded, not hidden
        ok, counts, err = False, {}, type(e).__name__
    res.update(ok=bool(ok), counts=counts, error=err)
    if res['run_id'] is not None:
        api.rpc('job_run_finish', {'p_run': int(res['run_id']), 'p_ok': bool(ok), 'p_error': err, 'p_counts': counts})
    oc.log(f'{job}: finished ok={ok} dry={dry}')
    return res


def main(argv=None, api=None, sms_runner=run_notify_sms):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--job', required=True, choices=JOBS)
    ap.add_argument('--live', action='store_true', help='act (default is a dry run)')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('NOTIFY_BOT_EMAIL') or oc.env('BOT_EMAIL', required=True), oc.env('NOTIFY_BOT_PASSWORD') or oc.env('BOT_PASSWORD', required=True))
        r = run(api, a.job, dry=not a.live, sms_runner=sms_runner)
        oc.log('done:', {k: r[k] for k in ('job', 'allowed', 'reason', 'ok')})
        return 0 if (r['ok'] is not False) else 1
    except SystemExit:
        raise
    except Exception as e:
        oc.log('X1 JOB FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())

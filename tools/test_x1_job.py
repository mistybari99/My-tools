#!/usr/bin/env python3
"""Tests for tools/x1_job.py with a fake database (no network). Run: python3 tools/test_x1_job.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import x1_job  # noqa: E402


class FakeApi:
    def __init__(self, allowed=True, intake=None):
        self.allowed, self.calls, self.intake = allowed, [], intake or {'done': 1, 'failed_again': 0, 'dead': 0}

    def rpc(self, fn, args=None):
        self.calls.append((fn, args or {}))
        if fn == 'job_run_start':
            return {'allowed': self.allowed, 'run_id': 7 if self.allowed else 8, 'reason': 'ok' if self.allowed else 'automation_off', 'dry_run': args['p_dry']}
        if fn == 'intake_retry_due':
            return self.intake
        return None


def fns(api):
    return [c[0] for c in api.calls]


fails = 0


def ok(c, m):
    global fails
    if not c:
        fails += 1
        print('FAIL', m)
    else:
        print('PASS', m)


# 1. automation OFF in the database: nothing runs, the skip is recorded by the database (no finish call)
api = FakeApi(allowed=False)
r = x1_job.run(api, 'intake_retry', dry=False)
ok(r['allowed'] is False and r['ok'] is None, 'skipped run reports not allowed')
ok(fns(api) == ['job_run_start'], 'skipped run calls nothing else')

# 2. dry run is the default in main(): intake_retry_due is never called
api = FakeApi()
r = x1_job.run(api, 'intake_retry', dry=True)
ok('intake_retry_due' not in fns(api) and r['ok'] is True, 'dry run does not call intake_retry_due')
ok(fns(api)[-1] == 'job_run_finish', 'dry run is still finished and recorded')

# 3. live intake_retry: called once with the limit, counts saved
api = FakeApi()
r = x1_job.run(api, 'intake_retry', dry=False)
ok(fns(api).count('intake_retry_due') == 1 and api.calls[1][1] == {'p_limit': 20}, 'live run calls intake_retry_due once, limit 20')
ok(r['counts'] == {'done': 1, 'failed_again': 0, 'dead': 0} and api.calls[-1][0] == 'job_run_finish', 'counts are saved with the finish call')

# 4. a failing SMS job is recorded as failed, not hidden
api = FakeApi()
r = x1_job.run(api, 'notify_sms', dry=True, sms_runner=lambda dry: (False, {'exit_code': 1}, 'boom'))
ok(r['ok'] is False and api.calls[-1][1]['p_ok'] is False and api.calls[-1][1]['p_error'] == 'boom', 'a failing job is recorded as failed')

# 5. heartbeat writes only the heartbeat
api = FakeApi()
r = x1_job.run(api, 'heartbeat', dry=True)
ok(fns(api) == ['job_run_start', 'job_heartbeat', 'job_run_finish'], 'heartbeat job calls heartbeat then finish only')

# 6. an unknown job is refused before anything is sent
try:
    x1_job.run(FakeApi(), 'send_everything', dry=False)
    ok(False, 'unknown job refused')
except SystemExit:
    ok(True, 'unknown job refused')

# 7. the sms job passes --dry-run through when dry (checked on the argument list only)
captured = {}


def fake_sms(dry):
    captured['dry'] = dry
    return True, {}, None


api = FakeApi()
x1_job.run(api, 'notify_sms', dry=True, sms_runner=fake_sms)
ok(captured['dry'] is True, 'notify_sms gets dry=True by default')

print('RESULT', 'FAIL' if fails else 'OK', fails)
sys.exit(1 if fails else 0)

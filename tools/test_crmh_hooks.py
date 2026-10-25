#!/usr/bin/env python3
"""Proof of the integration hooks of package CRM-H (docs/integration/CRM-H.md) on SCRATCH COPIES. Nothing in the repository is edited by this test.

Each hook is an exact-text patch (old text -> new text). The test: applies it to a scratch copy (stops if the old text is missing or occurs more than once), proves the
patched copy still passes the existing tests, proves the new behaviour, and checks that the new text is printed verbatim in the integration note.

    python3 -m unittest tools/test_crmh_hooks.py -v
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NOTE = os.path.join(ROOT, 'docs', 'integration', 'CRM-H.md')

# the anchor is the last line of the W1-G block (the repository carries it); the fallback anchor is the original scan line when W1-G is not there
ANCHOR_W1G = "            oc.log('journal posting failed:', type(e).__name__)\n"
ANCHOR_SCAN = """        oc.log(f"scan: {sc.get('created')} new notification(s)")\n"""
NEW = """        try:   # bos328 (CRM-H): mark complaints that passed their target time. The server answers "skipped" while the switch crm_complaints_on is OFF (default).
            cs = api.rpc('_crmh_sla_scan', {'p_dry': False})
            res['complaints'] = {k: cs.get(k) for k in ('marked', 'skipped')} if isinstance(cs, dict) else None
            oc.log('complaint check:', res['complaints'])
        except Exception as e:   # the alerts and the digest must never stop because the complaint check failed
            res['complaints'] = {'error': type(e).__name__}
            oc.log('complaint check failed:', type(e).__name__)
"""
INDEX_TAG = '<script src="crm_feedback.js"></script>'


def patch_notify(root):
    p = os.path.join(root, 'tools', 'notify_digest.py')
    with open(p, encoding='utf-8') as f:
        s = f.read()
    anchor = ANCHOR_W1G if s.count(ANCHOR_W1G) == 1 else ANCHOR_SCAN
    if s.count(anchor) != 1:
        raise AssertionError('patch site found %d times (must be exactly 1)' % s.count(anchor))
    with open(p, 'w', encoding='utf-8') as f:
        f.write(s.replace(anchor, anchor + NEW))


class Hooks(unittest.TestCase):
    def test_every_new_text_is_in_the_integration_note_verbatim(self):
        with open(NOTE, encoding='utf-8') as f:
            note = f.read()
        for ln in NEW.splitlines():
            self.assertIn(ln.strip(), note, 'the note must print this line exactly: ' + ln.strip()[:80])
        self.assertIn(INDEX_TAG, note)
        self.assertTrue(any(l.strip().startswith("rec('crmfeedback'") for l in note.splitlines()), 'the ia.js line is printed')

    def test_ia_line_uses_only_the_allowed_predicates_and_a_known_icon(self):
        with open(NOTE, encoding='utf-8') as f:
            line = [l for l in f.read().splitlines() if l.strip().startswith("rec('crmfeedback'")][0]
        self.assertIn("'cust'", line)
        for use in re.findall(r'\bc\.(\w+)', line):
            self.assertIn(use, ('own', 'GF', 'canPos'), 'only c.own, c.GF.<grant>, c.canPos() are allowed (docs/IA_RULES.md): ' + use)
        with open(os.path.join(ROOT, 'web', 'ia.js'), encoding='utf-8') as f:
            ia = f.read()
        self.assertIn("icon: 'users'", ia)

    def test_index_html_has_the_customers_script_to_sit_next_to(self):
        with open(os.path.join(ROOT, 'web', 'index.html'), encoding='utf-8') as f:
            self.assertEqual(f.read().count('<script src="customers.js"></script>'), 1)

    def test_grant_names_in_the_ia_line_exist_in_the_sql(self):
        with open(os.path.join(ROOT, 'supabase', 'phase328.sql'), encoding='utf-8') as f:
            sql = f.read()
        for g in ('crm_complaint_log', 'crm_complaint_manage', 'crm_feedback_view'):
            self.assertIn("'%s'" % g, sql)

    # ---------- notify workflow hook ----------
    def scratch_tools(self, d):
        t = os.path.join(d, 'tools')
        shutil.copytree(HERE, t, ignore=shutil.ignore_patterns('__pycache__', 'edge', 'kb_playbooks'))
        patch_notify(d)
        return t

    def test_notify_hook_keeps_the_existing_tests_green(self):
        with tempfile.TemporaryDirectory() as d:
            t = self.scratch_tools(d)
            r = subprocess.run([sys.executable, '-m', 'unittest', 'test_ops'], cwd=t, capture_output=True, text=True, timeout=300)
            self.assertEqual(r.returncode, 0, r.stderr[-1500:])

    def load_patched_notify(self, d):
        t = self.scratch_tools(d)
        sys.path.insert(0, t)
        for m in ('notify_digest', 'ops_common'):
            sys.modules.pop(m, None)
        try:
            import notify_digest as nd  # noqa: E402
            return nd
        finally:
            sys.path.remove(t)

    class Api:
        def __init__(self, scan):
            self.calls, self.scan = [], scan

        def rpc(self, fn, args=None):
            self.calls.append((fn, args))
            if fn == 'notify_config':
                return {'email_on': False}
            if fn == 'notify_scan':
                return {'created': 1}
            if fn == '_w1g_post_scheduled':
                return {'ran': False, 'skipped': 'switch_off'}
            if fn == '_crmh_sla_scan':
                if isinstance(self.scan, Exception):
                    raise self.scan
                return self.scan
            raise AssertionError('unexpected rpc ' + fn)

    def test_notify_hook_behaviour(self):
        with tempfile.TemporaryDirectory() as d:
            nd = self.load_patched_notify(d)
            os.environ.pop('SUPABASE_URL', None)
            # switch OFF (default): the server says skipped; the run goes on
            a = self.Api({'ran': False, 'skipped': 'switch_off'})
            res = nd.run(a, lambda *x: None)
            names = [c[0] for c in a.calls]
            self.assertIn('_crmh_sla_scan', names)
            self.assertGreater(names.index('_crmh_sla_scan'), names.index('notify_scan'), 'the check runs after the scan')
            self.assertEqual(a.calls[names.index('_crmh_sla_scan')][1], {'p_dry': False})
            self.assertEqual(res['complaints']['skipped'], 'switch_off')
            self.assertEqual(res['scan_created'], 1)
            # ON: the count is carried
            res = nd.run(self.Api({'ran': True, 'marked': 3}), lambda *x: None)
            self.assertEqual(res['complaints']['marked'], 3)
            # the call fails (old database without phase328, no permission, network): alerts still run, no exception
            for exc in (RuntimeError('boom'), nd.oc.ApiError(404, 'unknown rpc')):
                a = self.Api(exc)
                res = nd.run(a, lambda *x: None)
                self.assertIn('error', res['complaints'])
                self.assertEqual(res['scan_created'], 1)
            # dry run: no call is made
            a = self.Api({'marked': 9})
            nd.run(a, lambda *x: None, dry=True)
            self.assertNotIn('_crmh_sla_scan', [c[0] for c in a.calls])


if __name__ == '__main__':
    unittest.main()

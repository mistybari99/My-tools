#!/usr/bin/env python3
"""Proof of the integration hooks of package CRM-G (docs/integration/CRM-G.md) on SCRATCH COPIES. Nothing in the repository is edited by this test.

Each hook is an exact-text patch (old text -> new text). The test applies it to a scratch copy (stops if the old text is missing or occurs more than once),
proves the patched copy still passes the existing web and notify tests, proves the new behaviour, and checks that every added line is printed verbatim in the integration note.

    python3 -I tests/py/test_crmg_hooks.py -v        (from the repository root; needs node and playwright as the other web tests)
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NOTE = os.path.join(ROOT, 'docs', 'integration', 'CRM-G.md')

# ---- the hooks: (relative path, old text, new text) ----
IA = ('web/ia.js',
      "  rec('customers', 'cust', ['গ্রাহক তালিকা ও স্তর'",
      "  rec('crmleads', 'cust', ['Party and gift enquiries', 'Party and gift enquiries', 'Party and gift enquiries'], { icon: 'doc', ok: (c) => c.own || c.GF.crm_lead_manage === true || c.GF.crm_lead_all === true || c.canPos(), kw: ['enquiry', 'enquiries', 'lead', 'quote', 'quotation', 'party order', 'wholesale', 'corporate', 'gift box', 'hamper', 'follow up', 'won', 'lost', 'pipeline'], verbs: ['new enquiry', 'send a quote', 'follow up an enquiry'] }),\n"
      "  rec('crmtasks', 'cust', ['My tasks', 'My tasks', 'My tasks'], { icon: 'doc', kw: ['task', 'tasks', 'to do', 'reminder', 'follow up', 'overdue', 'snooze'], verbs: ['see my tasks', 'add a task'] }),\n"
      "  rec('customers', 'cust', ['গ্রাহক তালিকা ও স্তর'")
INDEX = ('web/index.html',
         '<script src="customers.js"></script>',
         '<script src="customers.js"></script><script src="crm_tasks.js"></script><script src="crm_leads.js"></script>')
NAV_STRIP = ('web/nav.js',
             "B.freshness.mount(el); }, 0);   // W1-G: the \"last posted at\" strip (silent when the server has no phase 98)\n",
             "B.freshness.mount(el); }, 0);   // W1-G: the \"last posted at\" strip (silent when the server has no phase 98)\n"
             "  setTimeout(() => { const el = $('#hv_tasks'); if (el && B.crmTasks) B.crmTasks.stripHTML().then((h) => { if (h) el.innerHTML = h; }).catch(() => {}); }, 0);   // bos326 (CRM-G): the My tasks strip (silent while tasks are off)\n")
NAV_SLOT = ('web/nav.js',
            "$('#hv_main').innerHTML = `${posBtn}${attn}",
            "$('#hv_main').innerHTML = `${posBtn}<div id=\"hv_tasks\"></div>${attn}")
INBOX_BTN = ('web/inbox.js',
             "<button type=\"button\" class=\"mini\" data-act=\"ib_ignore\" data-id=\"${esc(String(m.id))}\">${esc(T('ignore'))}</button>",
             "<button type=\"button\" class=\"mini\" data-act=\"ib_ignore\" data-id=\"${esc(String(m.id))}\">${esc(T('ignore'))}</button><button type=\"button\" class=\"mini\" data-act=\"ib_track\" data-id=\"${esc(String(m.id))}\">Track as enquiry</button>")
INBOX_ACT = ('web/inbox.js',
             "  ib_addline: () => {",
             "  ib_track: async (a) => { const r = await sb.rpc('inbox_get', { p_id: Number(a.dataset.id) }); if (r.error) return toast(msg(r.error)); const m = r.data; if (m.masked) return toast(T('e_not_allowed')); if (!B.crmLeads) return toast('Enquiry tracking is not installed'); try { await B.crmLeads.track({ id: m.id, location_id: m.location_id, customer_name: m.name, phone: phoneLike(m.handle) }); } catch (e) { toast(e.message); } },   // bos325 (CRM-G): turn a message into an enquiry\n"
             "  ib_addline: () => {")
NOTIFY = ('tools/notify_digest.py',
          "            oc.log('journal posting failed:', type(e).__name__)\n",
          "            oc.log('journal posting failed:', type(e).__name__)\n"
          "        try:   # bos326 (CRM-G): in-app task reminders. The server answers \"skipped\" while the switch crm_task_reminder_on is OFF (default); a failure never stops the alerts.\n"
          "            ts = api.rpc('_crmg_task_scan', {'p_dry': False})\n"
          "            res['crm_tasks'] = {k: ts.get(k) for k in ('created', 'people', 'skipped')} if isinstance(ts, dict) else None\n"
          "            oc.log('task reminders:', res['crm_tasks'])\n"
          "        except Exception as e:   # the alerts and the digest must never stop because a reminder could not be made\n"
          "            res['crm_tasks'] = {'error': type(e).__name__}\n"
          "            oc.log('task reminders failed:', type(e).__name__)\n")
ALL = [IA, INDEX, NAV_STRIP, NAV_SLOT, INBOX_BTN, INBOX_ACT, NOTIFY]


def apply(root, hook):
    rel, old, new = hook
    p = os.path.join(root, rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if new in s:
        return   # already integrated
    n = s.count(old)
    if n != 1:
        raise AssertionError(f'{rel}: patch site found {n} times (must be exactly 1): {old[:60]!r}')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(s.replace(old, new))


def unapply(root, hook):
    rel, old, new = hook
    p = os.path.join(root, rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if new in s:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(s.replace(new, old))


def scratch(d, hooks):
    """A scratch copy of web/, tests/web (js only) and tools/ with the given hooks applied (taken out first, so the original is the start)."""
    shutil.copytree(os.path.join(ROOT, 'web'), os.path.join(d, 'web'))
    os.makedirs(os.path.join(d, 'tests'))
    shutil.copytree(os.path.join(ROOT, 'tests', 'web'), os.path.join(d, 'tests', 'web'), ignore=shutil.ignore_patterns('*.png', '*.jpg', '*.webp'))
    shutil.copytree(os.path.join(ROOT, 'tools'), os.path.join(d, 'tools'), ignore=shutil.ignore_patterns('__pycache__', 'edge', 'kb_playbooks'))
    for h in ALL:
        unapply(d, h)
    for h in hooks:
        apply(d, h)
    return d


def node_test(d, name, *extra):
    t = os.path.join(d, 'tests', 'web')
    r = subprocess.run(['node', os.path.join(t, name), t, d] + list(extra), capture_output=True, text=True, timeout=600)
    return r.stdout + r.stderr


class Hooks(unittest.TestCase):
    def test_every_new_text_is_in_the_integration_note_verbatim(self):
        with open(NOTE, encoding='utf-8') as f:
            note = f.read()
        for rel, old, new in ALL:
            added = [ln for ln in new.splitlines() if ln not in old.splitlines()] or new.splitlines()
            for ln in added:
                self.assertIn(ln.strip(), note, f'{rel}: the note must print this line exactly: {ln.strip()[:80]}')

    def test_patch_sites_exist_exactly_once(self):
        for rel, old, new in ALL:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
                txt = f.read()
            self.assertTrue(txt.count(new) == 1 or txt.count(old) == 1, rel + ': ' + old[:50])

    def test_the_hooks_apply_to_a_scratch_copy_and_the_files_still_parse(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            for rel in ('web/ia.js', 'web/nav.js', 'web/inbox.js'):
                r = subprocess.run(['node', '--check', os.path.join(d, rel)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, rel + ': ' + r.stderr[-500:])
            with open(os.path.join(d, 'web', 'index.html'), encoding='utf-8') as f:
                h = f.read()
            self.assertLess(h.index('customers.js'), h.index('crm_tasks.js'))
            self.assertLess(h.index('crm_tasks.js'), h.index('crm_leads.js'))
            self.assertLess(h.index('crm_leads.js'), h.index('salesx.js'))

    def test_existing_web_tests_stay_green_with_all_hooks(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            for name in ('ia_test.js', 'nav_test.js', 'nav2_test.js', 'control_test.js', 'favsync_test.js', 'settings2_test.js', 'inbox_test.js'):
                out = node_test(d, name)
                self.assertNotRegex(out, r'(?im)assert failures: [1-9]|fail=[1-9]|^FAIL|TEST CRASH', name + ': ' + out[-800:])

    def test_the_two_screens_pass_their_own_test_on_the_patched_copy(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            out = node_test(d, 'crm_leads_test.js')
            self.assertIn('assert failures: 0', out, out[-1500:])
            self.assertIn('errors: none', out, out[-1500:])

    def test_the_new_routes_are_registered_once_and_visible_to_the_right_people(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            with open(os.path.join(d, 'web', 'ia.js'), encoding='utf-8') as f:
                s = f.read()
            self.assertEqual(s.count("rec('crmleads', 'cust'"), 1)
            self.assertEqual(s.count("rec('crmtasks', 'cust'"), 1)

    # ---------- notify job hook ----------
    def load_patched_notify(self, d):
        t = os.path.join(d, 'tools')
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
            if fn == '_crmg_task_scan':
                if isinstance(self.scan, Exception):
                    raise self.scan
                return self.scan
            raise AssertionError('unexpected rpc ' + fn)

    def test_notify_hook_behaviour(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            nd = self.load_patched_notify(d)
            os.environ.pop('SUPABASE_URL', None)
            a = self.Api({'ran': False, 'skipped': 'switch_off'})
            res = nd.run(a, lambda *x: None)
            self.assertEqual([c[0] for c in a.calls][:4], ['notify_config', 'notify_scan', '_w1g_post_scheduled', '_crmg_task_scan'], 'task reminders are asked after the scan and the posting')
            self.assertEqual(a.calls[3][1], {'p_dry': False})
            self.assertEqual(res['crm_tasks']['skipped'], 'switch_off')
            self.assertEqual(res['scan_created'], 1)
            res = nd.run(self.Api({'ran': True, 'people': 4, 'created': 4}), lambda *x: None)
            self.assertEqual((res['crm_tasks']['created'], res['crm_tasks']['people']), (4, 4))
            for exc in (RuntimeError('boom'), nd.oc.ApiError(404, 'unknown rpc')):
                res = nd.run(self.Api(exc), lambda *x: None)
                self.assertIn('error', res['crm_tasks'])
                self.assertEqual(res['scan_created'], 1)
            a = self.Api({'created': 9})
            nd.run(a, lambda *x: None, dry=True)
            self.assertNotIn('_crmg_task_scan', [c[0] for c in a.calls], 'a dry run makes no reminder call')

    def test_notify_hook_keeps_the_existing_tests_green(self):
        with tempfile.TemporaryDirectory() as d:
            scratch(d, ALL)
            r = subprocess.run([sys.executable, '-m', 'unittest', 'test_ops'], cwd=os.path.join(d, 'tools'), capture_output=True, text=True, timeout=300)
            self.assertEqual(r.returncode, 0, r.stderr[-1500:])


if __name__ == '__main__':
    unittest.main()

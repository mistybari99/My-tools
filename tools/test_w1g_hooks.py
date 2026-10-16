#!/usr/bin/env python3
"""Proof of the integration hooks of package W1-G (docs/integration/W1-G.md) on SCRATCH COPIES. Nothing in the repository is edited by this test.

Each hook is an exact-text patch (old text -> new text). The test: applies it to a scratch copy (stops if the old text is missing or occurs more than once), proves the
patched copy still passes the existing tests, proves the new behaviour, and checks that the new text is printed verbatim in the integration note.

    python3 -m unittest tools/test_w1g_hooks.py -v
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NOTE = os.path.join(ROOT, 'docs', 'integration', 'W1-G.md')

# ---- the hooks: (relative path, old text, new text) ----
NOTIFY = ('tools/notify_digest.py',
          """        oc.log(f"scan: {sc.get('created')} new notification(s)")
""",
          """        oc.log(f"scan: {sc.get('created')} new notification(s)")
        try:   # bos98 (W1-G): scheduled journal posting. The server answers "skipped" while the switch journal_sched_post_on is OFF (default).
            jp = api.rpc('_w1g_post_scheduled', {'p_dry': False})
            res['journal'] = {k: jp.get(k) for k in ('posted', 'reversed', 'left', 'skipped')} if isinstance(jp, dict) else None
            oc.log('journal posting:', res['journal'])
        except Exception as e:   # the alerts and the digest must never stop because the books could not be posted
            res['journal'] = {'error': type(e).__name__}
            oc.log('journal posting failed:', type(e).__name__)
""")
BACKUP_ENV = ('.github/workflows/backup.yml',
              "      BOT_PASSWORD: ${{ secrets.BOT_PASSWORD }}\n",
              "      BOT_PASSWORD: ${{ secrets.BOT_PASSWORD }}\n      BACKUP_PASSPHRASE: ${{ secrets.BACKUP_PASSPHRASE }}\n      BACKUP_KDF_SALT: ${{ secrets.BACKUP_KDF_SALT }}\n")
BACKUP_FIND = ('.github/workflows/backup.yml',
               "-type f \\( -name '*.ndjson.gz' -o -name 'manifest.json' \\) -delete",
               "-type f \\( -name '*.ndjson.gz' -o -name '*.ndjson.gz.enc' -o -name 'manifest.json' \\) -delete")
BACKUP_CP_LATEST = ('.github/workflows/backup.yml',
                    "cp out/*.ndjson.gz out/manifest.json data/latest/",
                    "cp out/*.ndjson.gz* out/manifest.json data/latest/")
BACKUP_CP_DAY = ('.github/workflows/backup.yml',
                 'cp out/*.ndjson.gz out/manifest.json "data/$DAY/"',
                 'cp out/*.ndjson.gz* out/manifest.json "data/$DAY/"')
BACKUP_RCLONE = ('.github/workflows/backup.yml',
                 "--include '*.ndjson.gz' --include 'manifest.json'",
                 "--include '*.ndjson.gz' --include '*.ndjson.gz.enc' --include 'manifest.json'")
FORMS = ('web/forms_stock.js',
         "    const [k, v] = a.dataset.v.split(':'), on = v === '1';\n",
         "    const [k, v] = a.dataset.v.split(':'), on = v === '1';\n"
         "    if (k === 'master' && on && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true))) return;   // bos98 (W1-G): say what the switch will lock, before it is saved\n")
PATHS = ('web/paths.js',
         "  const d = D.sw.find((x) => x.domain === dom), c = Object.assign({}, d.cfg, patch);\n",
         "  const d = D.sw.find((x) => x.domain === dom), c = Object.assign({}, d.cfg, patch);\n"
         "  if (patch.primary && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('path:' + dom, patch.primary))) return;   // bos98 (W1-G)\n")
ALL = [NOTIFY, BACKUP_ENV, BACKUP_FIND, BACKUP_CP_LATEST, BACKUP_CP_DAY, BACKUP_RCLONE, FORMS, PATHS]


def apply(root, hook):
    """Applies one hook to a scratch copy. After the Wave 1 integration (phase 99) the repository already carries the new text: then there is nothing to do."""
    rel, old, new = hook
    p = os.path.join(root, rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if s.count(new) >= 1 and old != new and new in s and s.count(old) == s.count(new):
        return   # already integrated (the old text is the first part of the new text)
    n = s.count(old)
    if n != 1:
        raise AssertionError(f'{rel}: patch site found {n} times (must be exactly 1): {old[:60]!r}')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(s.replace(old, new))


def unapply(root, hook):
    """Takes one hook back out of a scratch copy (the original text), so the "before the patch" tests still see the original files after the integration."""
    rel, old, new = hook
    p = os.path.join(root, rel)
    with open(p, encoding='utf-8') as f:
        s = f.read()
    if new in s:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(s.replace(new, old))


class Hooks(unittest.TestCase):
    def test_every_new_text_is_in_the_integration_note_verbatim(self):
        with open(NOTE, encoding='utf-8') as f:
            note = f.read()
        for rel, old, new in ALL:
            added = [ln for ln in new.splitlines() if ln not in old.splitlines()] or new.splitlines()
            for ln in added:
                self.assertIn(ln.strip(), note, f'{rel}: the note must print this line exactly: {ln.strip()[:80]}')

    def test_patch_sites_exist_exactly_once(self):
        # before the integration the old text is there once; after it the new text is there once (the old text is its first part)
        for rel, old, new in ALL:
            with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
                txt = f.read()
            self.assertTrue(txt.count(new) == 1 or txt.count(old) == 1, rel + ': ' + old[:50])

    # ---------- notify workflow hook ----------
    def scratch_tools(self, d):
        t = os.path.join(d, 'tools')
        shutil.copytree(HERE, t, ignore=shutil.ignore_patterns('__pycache__', 'edge', 'kb_playbooks'))
        unapply(d, NOTIFY)   # start from the original file whether or not the repository already carries the hook
        apply(d, NOTIFY)
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
        def __init__(self, journal):
            self.calls, self.journal = [], journal

        def rpc(self, fn, args=None):
            self.calls.append((fn, args))
            if fn == 'notify_config':
                return {'email_on': False}
            if fn == 'notify_scan':
                return {'created': 1}
            if fn == '_w1g_post_scheduled':
                if isinstance(self.journal, Exception):
                    raise self.journal
                return self.journal
            raise AssertionError('unexpected rpc ' + fn)

    def test_notify_hook_behaviour(self):
        with tempfile.TemporaryDirectory() as d:
            nd = self.load_patched_notify(d)
            os.environ.pop('SUPABASE_URL', None)
            # switch OFF (default): the server says skipped; the run goes on
            a = self.Api({'ran': False, 'skipped': 'switch_off'})
            res = nd.run(a, lambda *x: None)
            self.assertEqual([c[0] for c in a.calls], ['notify_config', 'notify_scan', '_w1g_post_scheduled'], 'posting is asked right after the scan')
            self.assertEqual(a.calls[2][1], {'p_dry': False})
            self.assertEqual(res['journal']['skipped'], 'switch_off')
            self.assertEqual(res['scan_created'], 1)
            # ON: counts are carried
            res = nd.run(self.Api({'ran': True, 'posted': 3, 'reversed': 1, 'left': 0}), lambda *x: None)
            self.assertEqual((res['journal']['posted'], res['journal']['reversed']), (3, 1))
            # the posting call fails (old database without phase98, no permission, network): alerts still run, no exception
            for exc in (RuntimeError('boom'), nd.oc.ApiError(404, 'unknown rpc')):
                a = self.Api(exc)
                res = nd.run(a, lambda *x: None)
                self.assertIn('error', res['journal'])
                self.assertEqual(res['scan_created'], 1)
            # dry run: nothing is posted and no posting call is made
            a = self.Api({'posted': 9})
            nd.run(a, lambda *x: None, dry=True)
            self.assertNotIn('_w1g_post_scheduled', [c[0] for c in a.calls])

    # ---------- backup workflow hook ----------
    def patched_workflow(self, d, patches):
        os.makedirs(os.path.join(d, '.github', 'workflows'))
        shutil.copy(os.path.join(ROOT, '.github', 'workflows', 'backup.yml'), os.path.join(d, '.github', 'workflows', 'backup.yml'))
        for h in (BACKUP_ENV, BACKUP_FIND, BACKUP_CP_LATEST, BACKUP_CP_DAY, BACKUP_RCLONE):
            unapply(d, h)   # the original workflow, whether or not the repository already carries the hooks
        for p in patches:
            apply(d, p)
        with open(os.path.join(d, '.github', 'workflows', 'backup.yml'), encoding='utf-8') as f:
            return f.read()

    @staticmethod
    def step_script(yml, name):
        i = yml.index('- name: ' + name)
        j = yml.index('run: |\n', i) + len('run: |\n')
        lines = []
        for ln in yml[j:].splitlines():
            if ln.startswith('          ') or not ln.strip():
                lines.append(ln[10:] if ln.startswith('          ') else '')
            else:
                break
        return '\n'.join(lines)

    def run_pack_step(self, yml, enc):
        """Runs the real 'Put the dump into latest/ and the dated folder' step text on a scratch folder tree."""
        script = self.step_script(yml, 'Put the dump into latest/ and the dated folder')
        with tempfile.TemporaryDirectory() as w:
            os.makedirs(os.path.join(w, 'out'))
            os.makedirs(os.path.join(w, 'data', 'latest'))
            names = ['customers.ndjson.gz.enc', 'sales.ndjson.gz.enc'] if enc else ['customers.ndjson.gz', 'sales.ndjson.gz']
            for n in names + ['manifest.json']:
                with open(os.path.join(w, 'out', n), 'wb') as f:
                    f.write(b'x' + n.encode())
            # an old run left the OTHER kind of file in latest/: it must be removed, photos/ must stay
            stale = 'old.ndjson.gz' if enc else 'old.ndjson.gz.enc'
            with open(os.path.join(w, 'data', 'latest', stale), 'wb') as f:
                f.write(b'old')
            os.makedirs(os.path.join(w, 'data', 'latest', 'photos'))
            with open(os.path.join(w, 'data', 'latest', 'photos', 'p.jpg'), 'wb') as f:
                f.write(b'p')
            env = dict(os.environ, GITHUB_ENV=os.path.join(w, 'ghenv'))
            r = subprocess.run(['bash', '-ec', script], cwd=w, capture_output=True, text=True, env=env)
            latest = sorted(os.listdir(os.path.join(w, 'data', 'latest')))
            day = [f for f in os.listdir(os.path.join(w, 'data')) if f != 'latest']
            dated = []
            for root, _, files in os.walk(os.path.join(w, 'data')):
                if os.sep + 'latest' not in root + os.sep:
                    dated += files
            return r, latest, sorted(dated)

    def test_backup_workflow_before_the_patch_cannot_carry_encrypted_files(self):
        with tempfile.TemporaryDirectory() as d:
            yml = self.patched_workflow(d, [])
            r, latest, dated = self.run_pack_step(yml, enc=True)
            self.assertNotEqual(r.returncode, 0, 'the unpatched step fails on encrypted output (cp finds no .ndjson.gz): that is why the hook is needed')

    def test_backup_workflow_plain_still_works_after_the_patch(self):
        with tempfile.TemporaryDirectory() as d:
            yml = self.patched_workflow(d, [BACKUP_ENV, BACKUP_FIND, BACKUP_CP_LATEST, BACKUP_CP_DAY, BACKUP_RCLONE])
            r, latest, dated = self.run_pack_step(yml, enc=False)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(latest, ['customers.ndjson.gz', 'manifest.json', 'photos', 'sales.ndjson.gz'], 'plain run: plain files only, photos kept, the stale encrypted file removed')
            self.assertEqual(dated, ['customers.ndjson.gz', 'manifest.json', 'sales.ndjson.gz'])

    def test_backup_workflow_encrypted_after_the_patch(self):
        with tempfile.TemporaryDirectory() as d:
            yml = self.patched_workflow(d, [BACKUP_ENV, BACKUP_FIND, BACKUP_CP_LATEST, BACKUP_CP_DAY, BACKUP_RCLONE])
            r, latest, dated = self.run_pack_step(yml, enc=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(latest, ['customers.ndjson.gz.enc', 'manifest.json', 'photos', 'sales.ndjson.gz.enc'], 'encrypted run: encrypted files only; the stale plain file is gone, photos kept')
            self.assertEqual(dated, ['customers.ndjson.gz.enc', 'manifest.json', 'sales.ndjson.gz.enc'])
            self.assertIn('BACKUP_PASSPHRASE: ${{ secrets.BACKUP_PASSPHRASE }}', yml)
            self.assertIn("--include '*.ndjson.gz.enc'", yml)
            for ln in yml.splitlines():
                if 'BACKUP_PASSPHRASE' in ln and not ln.lstrip().startswith('#'):
                    self.assertIn('${{ secrets.BACKUP_PASSPHRASE }}', ln, 'the passphrase is only ever a secret reference, never a value')

    # ---------- web hooks: the existing web test must pass on the patched scratch copy ----------
    def test_forms_and_paths_hooks_keep_the_existing_web_tests_green(self):
        node = shutil.which('node')
        pw = '/opt/node22/lib/node_modules/playwright'
        if not node or not os.path.isdir(pw):
            self.skipTest('node / playwright not available')
        with tempfile.TemporaryDirectory() as d:
            shutil.copytree(os.path.join(ROOT, 'web'), os.path.join(d, 'web'))
            os.makedirs(os.path.join(d, 'tests'))
            shutil.copytree(os.path.join(ROOT, 'tests', 'web'), os.path.join(d, 'tests', 'web'), ignore=shutil.ignore_patterns('*.png'))
            unapply(d, FORMS)
            unapply(d, PATHS)
            apply(d, FORMS)
            apply(d, PATHS)
            for t in ('forms_links_test.js',):
                r = subprocess.run([node, os.path.join(d, 'tests', 'web', t), os.path.join(d, 'tests', 'web')], capture_output=True, text=True, timeout=300)
                self.assertIn('assert failures: 0', r.stdout, t + '\n' + r.stdout[-1500:] + r.stderr[-500:])


if __name__ == '__main__':
    unittest.main()

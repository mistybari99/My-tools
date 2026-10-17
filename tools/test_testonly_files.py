#!/usr/bin/env python3
"""Guards for the TEST-PROJECT-ONLY SQL files (they delete data) and for the demo-name ratchet. Needs nothing but Python 3.

    python3 -m unittest tools/test_testonly_files.py -v          (or: cd tools && python3 -m unittest test_testonly_files -v)

* the files that clear data (supabase/phase84_test_project_only.sql, supabase/phase84b_test_project_only_wave1.sql) are never in the owner paste order (tests/sql/ORDER.txt),
  carry the warning in their first lines, and no script of the repository pastes them anywhere but into a local throwaway database;
* tools/check_no_demo_leak.py really fails on a roster staff name in a NEW test file (the baseline only freezes the old ones).
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEST_ONLY = ['supabase/phase84_test_project_only.sql', 'supabase/phase84b_test_project_only_wave1.sql', 'supabase/phase84c_test_project_only_wave2.sql']


def read(rel):
    with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
        return f.read()


class TestOnlyFiles(unittest.TestCase):
    def test_never_in_the_owner_paste_order(self):
        words = [w for ln in read('tests/sql/ORDER.txt').splitlines() if not ln.startswith('#') for w in ln.split()]
        for w in words:
            self.assertNotIn('test_project_only', w)
            self.assertNotEqual(w, 'phase84b')
        self.assertIn('phase143', words)          # the W1-FIX phases are in the order (they are normal phases)
        self.assertEqual(words, sorted(set(words), key=words.index), 'no phase twice')

    def test_warning_in_the_first_lines(self):
        for rel in TEST_ONLY:
            head = '\n'.join(read(rel).splitlines()[:3]).upper()
            self.assertIn('TEST PROJECT', head, rel)
            self.assertIn('NEVER PASTE', head, rel)

    def test_the_reset_needs_the_three_checks_and_is_not_changed_by_84b(self):
        old, new = read(TEST_ONLY[0]), read(TEST_ONLY[1])
        self.assertIn('DELETE ALL TEST DATA', old)
        code = re.sub(r'--[^\n]*', '', new)
        self.assertIsNone(re.search(r'function\s+public\._e_test_reset\b|\b(select|perform)\s+public\._e_test_reset\s*\(', code), '84b only replaces the two lists; it does not define or call the reset')
        self.assertNotIn('truncate', code.lower())

    def test_no_script_or_workflow_pastes_them_outside_a_local_throwaway_database(self):
        # the only places that name them: SQL tests, the local runner, docs and the demo-leak tool. Nothing under .github/ and no tool that talks to Supabase.
        for d, _, files in os.walk(os.path.join(ROOT, '.github')):
            for f in files:
                with open(os.path.join(d, f), encoding='utf-8', errors='ignore') as fh:
                    t = fh.read()
                self.assertNotIn('test_project_only', t, os.path.join(d, f))
        for f in os.listdir(HERE):
            if f.endswith('.py') and f != os.path.basename(__file__) and f != 'build_ui_inventory.py':      # build_ui_inventory.py only SKIPS those files when it reads the seed SQL
                self.assertNotIn('test_project_only', read('tools/' + f), f)

    def test_84b_lists_cover_the_wave1_tables_named_in_the_header(self):
        new = read(TEST_ONLY[1])
        for t in ['w1c_returns', 'w1c_return_lines', 'late_sales_held', 'open_party_adjustments', 'other_income', 'period_overrides', 'profit_row_exclusions', 'w1e_requests',
                  'w1g_post_runs', 'w1g_post_watermark', 'entry_approvers', 'w1c_return_class_rules', 'w1c_exit_keep', 'w1e_mapping_types', 'w1f_seed_state', 'w1g_sched_state', 'w1g_switch_acks']:
            self.assertIn("'" + t + "'", new, t)
        # no table on both lists
        body = re.sub(r'/\*.*?\*/', '', re.sub(r'--[^\n]*', '', new), flags=re.S)
        lists = re.findall(r'select array\[(.*?)\]::text\[\]', body, flags=re.S)
        self.assertEqual(len(lists), 2)
        a, b = [set(re.findall(r"'([a-z_0-9]+)'", x)) for x in lists]
        self.assertFalse(a & b, a & b)


class DemoLeakRatchet(unittest.TestCase):
    def run_check(self):
        return subprocess.run([sys.executable, os.path.join(HERE, 'check_no_demo_leak.py')], capture_output=True, text=True, cwd=ROOT)

    def test_clean_repository_passes(self):
        r = self.run_check()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('OK', r.stdout)

    def test_a_new_test_file_with_a_roster_name_fails_in_any_letter_case(self):
        name = ''.join(['ka', 'rim']) + '02'          # built from pieces so this file itself carries no roster name
        path = os.path.join(ROOT, 'tests', 'py', 'test_zz_ratchet_tmp.py')
        try:
            with open(path, 'w', encoding='utf-8') as f:
                f.write("x = '" + name + "'\n")
            r = self.run_check()
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn('test_zz_ratchet_tmp.py', r.stdout)
        finally:
            if os.path.exists(path):
                os.remove(path)
        self.assertEqual(self.run_check().returncode, 0)

    def test_baseline_holds_counts_not_names(self):
        with open(os.path.join(HERE, 'demo_leak_test_baseline.json'), encoding='utf-8') as f:
            base = json.load(f)
        self.assertTrue(all(isinstance(v, int) and v > 0 for v in base.values()))
        self.assertFalse(any(k.endswith('wave1_wiring_test.js') for k in base), 'the Wave 1 wiring test is clean and must stay clean')
        text = json.dumps(base).lower()
        names = ['ka' + 'rim', 'sal' + 'ma', 'rah' + 'im']
        self.assertFalse(any(n in text for n in names))


if __name__ == '__main__':
    unittest.main()

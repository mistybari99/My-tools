#!/usr/bin/env python3
"""Tests for tools/make_public_seed.py and tools/backup_retention.py (item U-12). Python 3 only; works on COPIES, never edits data/items_seed.csv.

    python3 -m unittest tools/test_data_protection.py -v
"""
import contextlib
import datetime
import io
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import backup_retention as br  # noqa: E402
import make_public_seed as ms  # noqa: E402

REAL = os.path.join(ROOT, 'data', 'items_seed.csv')


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = ms.main(argv)
    return rc, out.getvalue(), err.getvalue()


class SeedTool(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='w1g_seed_')
        self.seed = os.path.join(self.d, 'items_seed.csv')
        shutil.copy(REAL, self.seed)
        self.orig = open(self.seed, 'rb').read()
        # a private place OUTSIDE the repository
        self.priv = os.path.join(self.d, 'private', 'costs.csv')

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def test_check_reports_counts_never_values(self):
        rc, out, _ = run(['--seed', self.seed, 'check'])
        self.assertEqual(rc, 1)
        self.assertIn('cost_price column', out)
        self.assertNotIn('230', out)
        self.assertNotIn('320', out)

    def test_public_copy_has_no_cost_column_and_leaves_the_seed_alone(self):
        out_path = os.path.join(self.d, 'public', 'items_seed.public.csv')
        rc, out, _ = run(['--seed', self.seed, 'public-copy', '--out', out_path])
        self.assertEqual(rc, 0)
        pub = open(out_path, 'rb').read().decode('utf-8')
        self.assertTrue(pub.startswith('product_name,category,selling_price,stock\r\n'))
        self.assertNotIn('cost_price', pub)
        self.assertEqual(open(self.seed, 'rb').read(), self.orig, 'the seed was not touched')
        self.assertEqual(pub.count('\r\n'), self.orig.decode('utf-8').count('\r\n'), 'same rows')
        self.assertEqual(ms.cost_state(out_path)['has_column'], False)
        self.assertEqual(run(['--seed', out_path, 'check'])[0], 0)
        self.assertEqual(run(['--seed', self.seed, 'public-copy', '--out', self.seed])[0], 2, 'cannot overwrite the seed itself')
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)

    def test_public_copy_keeps_all_other_columns_exactly(self):
        out_path = os.path.join(self.d, 'pub.csv')
        run(['--seed', self.seed, 'public-copy', '--out', out_path])
        a, _, _, _ = ms.parse(self.orig)
        b, _, _, _ = ms.parse(open(out_path, 'rb').read())
        self.assertEqual([[c for j, c in enumerate(r) if j != 3] for r in a], b)

    def test_strip_refuses_without_the_owner_decision(self):
        for argv in (['strip', '--private-costs', self.priv, '--apply'], ['strip', '--private-costs', self.priv, '--owner-decision', 'yes', '--apply'],
                     ['strip', '--private-costs', self.priv, '--owner-decision', 'od-15', '--apply']):
            rc, _, err = run(['--seed', self.seed] + argv)
            self.assertEqual(rc, 2, argv)
            self.assertIn('owner decision', err)
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)
        self.assertFalse(os.path.exists(self.priv))

    def test_strip_without_apply_is_a_dry_run(self):
        rc, out, _ = run(['--seed', self.seed, 'strip', '--private-costs', self.priv, '--owner-decision', 'OD-15'])
        self.assertEqual(rc, 0)
        self.assertIn('DRY RUN', out)
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)
        self.assertFalse(os.path.exists(self.priv))

    def test_strip_refuses_a_private_file_inside_the_repository(self):
        inside = os.path.join(ROOT, 'data', 'w1g_test_costs_must_not_exist.csv')
        rc, _, err = run(['--seed', self.seed, 'strip', '--private-costs', inside, '--owner-decision', 'OD-15', '--apply'])
        self.assertEqual(rc, 2)
        self.assertIn('OUTSIDE', err)
        self.assertFalse(os.path.exists(inside))
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)

    def test_strip_then_restore_is_byte_for_byte(self):
        rc, out, _ = run(['--seed', self.seed, 'strip', '--private-costs', self.priv, '--owner-decision', 'OD-15', '--apply'])
        self.assertEqual(rc, 0, out)
        stripped = open(self.seed, 'rb').read().decode('utf-8')
        self.assertNotIn('cost_price', stripped)
        self.assertNotIn(',230,', stripped)
        self.assertTrue(stripped.startswith('product_name,category,selling_price,stock\r\n'))
        self.assertEqual(run(['--seed', self.seed, 'check'])[0], 0, 'check is clean after strip')
        priv = open(self.priv, 'rb').read().decode('utf-8')
        self.assertTrue(priv.startswith('product_name,category,cost_price\r\n'))
        self.assertIn(',230\r\n', priv)
        self.assertEqual(ms.cost_state(self.seed)['has_column'], False)
        # the cost file is private
        self.assertEqual(os.stat(self.priv).st_mode & 0o077, 0)
        # doing it twice is harmless
        self.assertEqual(run(['--seed', self.seed, 'strip', '--private-costs', self.priv + '2', '--owner-decision', 'OD-15', '--apply'])[0], 0)
        self.assertFalse(os.path.exists(self.priv + '2'))
        # undo
        rc, out, _ = run(['--seed', self.seed, 'restore', '--private-costs', self.priv, '--apply'])
        self.assertEqual(rc, 0, out)
        self.assertEqual(open(self.seed, 'rb').read(), self.orig, 'the original file is back, byte for byte')

    def test_strip_never_overwrites_an_existing_private_file(self):
        os.makedirs(os.path.dirname(self.priv))
        with open(self.priv, 'w') as f:
            f.write('keep me')
        rc, _, err = run(['--seed', self.seed, 'strip', '--private-costs', self.priv, '--owner-decision', 'OD-15', '--apply'])
        self.assertEqual(rc, 2)
        self.assertEqual(open(self.priv).read(), 'keep me')
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)

    def test_restore_refuses_a_changed_seed_and_writes_nothing(self):
        run(['--seed', self.seed, 'strip', '--private-costs', self.priv, '--owner-decision', 'OD-15', '--apply'])
        stripped = open(self.seed, 'rb').read()
        with open(self.seed, 'ab') as f:
            f.write('\r\nনতুন আইটেম,Misty / KG,100,\r\n'.encode('utf-8'))
        before = open(self.seed, 'rb').read()
        rc, _, err = run(['--seed', self.seed, 'restore', '--private-costs', self.priv, '--apply'])
        self.assertEqual(rc, 2)
        self.assertEqual(open(self.seed, 'rb').read(), before)
        self.assertNotEqual(before, stripped)

    def test_restore_when_the_cost_column_is_already_there_is_refused(self):
        run(['--seed', self.seed, 'strip', '--private-costs', self.priv, '--owner-decision', 'OD-15', '--apply'])
        run(['--seed', self.seed, 'restore', '--private-costs', self.priv, '--apply'])
        self.assertEqual(run(['--seed', self.seed, 'restore', '--private-costs', self.priv, '--apply'])[0], 2)
        self.assertEqual(open(self.seed, 'rb').read(), self.orig)

    def test_the_real_seed_file_is_not_modified_by_any_of_this(self):
        # the tests above work on copies; this pins that the repository file still has its cost column (the owner has not decided; docs/integration/W1-G.md)
        self.assertTrue(ms.cost_state(REAL)['has_column'])

    def test_costs_are_not_printed_in_any_message(self):
        for argv in (['check'], ['strip', '--private-costs', self.priv, '--owner-decision', 'OD-15']):
            _, out, err = run(['--seed', self.seed] + argv)
            self.assertNotRegex(out + err, r'\b(230|320)\b')


class Retention(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='w1g_ret_')
        for day in ('2025/01/05', '2025/12/31', '2026/01/01', '2026/06/30', '2026/09/15', '2026/10/16'):
            os.makedirs(os.path.join(self.d, day))
            with open(os.path.join(self.d, day, 'manifest.json'), 'w') as f:
                f.write('{}')
        os.makedirs(os.path.join(self.d, 'latest'))
        os.makedirs(os.path.join(self.d, 'photos'))
        os.makedirs(os.path.join(self.d, '2026', 'notes'))
        os.makedirs(os.path.join(self.d, '2026', '13', '40'))        # impossible date: ignored
        with open(os.path.join(self.d, 'README.md'), 'w') as f:
            f.write('r')

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def go(self, *argv):
        out = []
        rc = br.main(['--root', self.d, '--today', '2026-10-16'] + list(argv), out=out.append)
        return rc, out

    def left(self):
        return [os.path.relpath(p, self.d).replace(os.sep, '/') for _, p in br.dated_folders(self.d)]

    def test_blank_setting_removes_nothing(self):
        rc, out = self.go()
        self.assertEqual(rc, 0)
        self.assertIn('nothing removed', out[0])
        self.assertEqual(len(self.left()), 6)

    def test_dry_run_lists_but_removes_nothing(self):
        rc, out = self.go('--days', '365')
        self.assertEqual(rc, 0)
        txt = '\n'.join(out)
        self.assertIn('would remove 2025/01/05', txt)
        self.assertNotIn('2025/12/31', txt, '2025-12-31 is within 365 days of 2026-10-16 (cutoff 2025-10-16)')
        self.assertIn('DRY RUN', txt)
        self.assertEqual(len(self.left()), 6)

    def test_apply_removes_only_old_dated_folders(self):
        rc, out = self.go('--days', '120', '--apply')
        self.assertEqual(rc, 0)
        self.assertEqual(self.left(), ['2026/06/30', '2026/09/15', '2026/10/16'])
        self.assertFalse(os.path.exists(os.path.join(self.d, '2025')), 'the empty year folder is tidied away')
        self.assertFalse(os.path.exists(os.path.join(self.d, '2026', '01')))
        self.assertTrue(os.path.exists(os.path.join(self.d, '2026', '06', '30')))
        self.assertTrue(os.path.exists(os.path.join(self.d, '2026', '09', '15')))
        self.assertTrue(os.path.exists(os.path.join(self.d, '2026', '10', '16')))
        for keep in ('latest', 'photos', 'README.md', os.path.join('2026', 'notes'), os.path.join('2026', '13', '40')):
            self.assertTrue(os.path.exists(os.path.join(self.d, keep)), keep + ' must never be touched')

    def test_the_newest_dated_folder_is_never_removed(self):
        rc, out = self.go('--days', '1', '--apply')
        self.assertEqual(rc, 0)
        self.assertEqual(self.left(), ['2026/10/16'], 'only the newest is left, however short the period')
        # a stalled backup: the newest folder is old, it still stays
        os.makedirs(os.path.join(self.d, '2025', '03', '03'))
        shutil.rmtree(os.path.join(self.d, '2026', '10', '16'))
        rc, out = self.go('--days', '1', '--apply')
        self.assertEqual(self.left(), ['2025/03/03'])

    def test_bad_days_are_refused(self):
        for bad in ('0', '-5', '99999'):
            self.assertEqual(self.go('--days', bad, '--apply')[0], 2)
        self.assertEqual(len(self.left()), 6)

    def test_run_twice_is_harmless(self):
        self.go('--days', '120', '--apply')
        rc, out = self.go('--days', '120', '--apply')
        self.assertEqual(rc, 0)
        self.assertIn('nothing older', out[0])

    def test_missing_root_is_refused(self):
        self.assertEqual(br.main(['--root', os.path.join(self.d, 'nope'), '--days', '30']), 2)


if __name__ == '__main__':
    unittest.main()

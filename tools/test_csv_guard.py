#!/usr/bin/env python3
"""A browser-built CSV must neutralise spreadsheet formulas (a cell that starts with = + - @ tab CR gets a leading apostrophe). Customer names and notes come from outside the staff
(online order form), so an unguarded export is a formula-injection route into the owner's spreadsheet.   python3 -m unittest tools/test_csv_guard.py -v"""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# the CSV builders: cell functions (accounts, app, assistant, payroll too) and text guards for server-built CSV text (integrations, moneyaccounts, salesx)
# web/attendance.js only IMPORTS a device file, it exports nothing
FILES = ['web/crm_segments.js', 'web/c2rpt.js', 'web/accounts.js', 'web/app.js', 'web/assistant.js', 'web/payroll.js']
TEXT_FILES = ['web/integrations.js', 'web/moneyaccounts.js', 'web/salesx.js']


class T(unittest.TestCase):
    def test_guard_present(self):
        for f in FILES:
            s = open(os.path.join(ROOT, f), encoding='utf8').read()
            self.assertIsNotNone(re.search(r"\^\[=\+\\-@\\t\\r\]", s), f + ': the formula guard is missing in the CSV cell function')
            self.assertIn('"\'" + s', s, f + ': the guard does not add the apostrophe')

    def test_text_guard_present_and_used(self):
        for f in TEXT_FILES:
            s = open(os.path.join(ROOT, f), encoding='utf8').read()
            self.assertIn('const guardCsv = ', s, f + ': the text guard is missing')
            self.assertGreaterEqual(s.count('guardCsv('), 1, f + ': the guard is not applied to the downloaded text')
            self.assertRegex(s, r"\[=\\\+\\-@|\[=\+\\-@", f + ': the guard pattern is missing')


if __name__ == '__main__':
    unittest.main()

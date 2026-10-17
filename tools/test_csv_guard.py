#!/usr/bin/env python3
"""A browser-built CSV must neutralise spreadsheet formulas (a cell that starts with = + - @ tab CR gets a leading apostrophe). Customer names and notes come from outside the staff
(online order form), so an unguarded export is a formula-injection route into the owner's spreadsheet.   python3 -m unittest tools/test_csv_guard.py -v"""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# the CSV builders added by the integrated packages (older screens are listed in the final check report as a known follow-up)
FILES = ['web/crm_segments.js', 'web/c2rpt.js']


class T(unittest.TestCase):
    def test_guard_present(self):
        for f in FILES:
            s = open(os.path.join(ROOT, f), encoding='utf8').read()
            self.assertIsNotNone(re.search(r"\^\[=\+\\-@\\t\\r\]", s), f + ': the formula guard is missing in the CSV cell function')
            self.assertIn('"\'" + s', s, f + ': the guard does not add the apostrophe')


if __name__ == '__main__':
    unittest.main()

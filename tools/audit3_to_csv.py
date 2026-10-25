#!/usr/bin/env python3
"""Integrator tool: turns the matrix of docs/REPORTS_AUDIT_3.md (reports 105-193) into tools/report_registry_merge/audit3.csv, the file
tools/build_report_registry.py merges (columns: no,name_en,name_bn,question_en,question_bn,section,status,route,source,area,note).
name_bn / question_bn repeat the English wording (the audit is English only); the owner's master list can replace them with --master.
route: the first `#/screen` of the "Existing route / equivalent" cell, else the first hub `key` as report/<key>, else planned.
Run:  python3 tools/audit3_to_csv.py   then   python3 tools/build_report_registry.py
"""
import csv, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'docs', 'REPORTS_AUDIT_3.md')
OUT = os.path.join(ROOT, 'tools', 'report_registry_merge', 'audit3.csv')
AREA = {8: 'cash', 9: 'customer', 10: 'staff', 11: 'orders', 12: 'marketing', 13: 'audit', 14: 'planning'}


def route_of(cell):
    m = re.search(r'`#/([a-z0-9_/]+)`', cell)
    if m:
        return m.group(1)
    m = re.search(r'hub[^`|]*`([a-z0-9_]+)`', cell)
    if m:
        return 'report/' + m.group(1)
    m = re.search(r'`([a-z][a-z0-9_]+)`', cell)
    if m and 'none' not in cell.lower()[:6]:
        return None
    return None


rows = []
sec = None
for line in open(SRC, encoding='utf-8'):
    h = re.match(r'### (\d+) ', line)
    if h:
        sec = int(h.group(1))
        continue
    if sec and re.match(r'\| 1\d\d \|', line):
        c = [x.strip() for x in line.strip().strip('|').split('|')]
        status = c[11].lower()
        assert status in ('implemented', 'incomplete', 'unavailable', 'unverified'), (c[0], status)
        name = c[1].strip()
        rows.append({'no': c[0], 'name_en': name, 'name_bn': name, 'question_en': name, 'question_bn': name, 'section': str(sec), 'status': status,
                     'route': route_of(c[2]) or '', 'source': re.sub(r'\s+', ' ', c[3])[:160], 'area': AREA[sec], 'note': re.sub(r'\s+', ' ', c[10])[:200]})
assert len(rows) == 89, len(rows)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
print('wrote', os.path.relpath(OUT, ROOT), len(rows), 'rows')

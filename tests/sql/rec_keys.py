#!/usr/bin/env python3
"""Prints "phase,rule_key" (csv) for every rule inserted by `insert into public.rules` in supabase/phase82.sql .. phase97.sql
(used by supabase/phase101_test.sql: every one of them must have a row in setup_rec_defs81). Run from the repo root."""
import re, os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'supabase')
for n in range(82, 98):
    p = os.path.join(root, 'phase%d.sql' % n)
    if not os.path.exists(p):
        continue
    s = open(p, encoding='utf-8').read()
    for m in re.finditer(r'insert into public\.rules\s*\(.*?\)\s*values(.*?)(?:on conflict|;\s*\n)', s, re.S | re.I):
        for k in re.finditer(r"^\s*\(\s*'([a-z0-9_]+)'\s*,\s*'([a-z0-9_]+)'", m.group(1), re.M):
            print('%d,%s' % (n, k.group(1)))

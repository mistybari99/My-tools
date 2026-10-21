"""CRM-G: the plain-English info sheet (docs/integration/CRM-G_info.json) covers every setting and right of phase323.sql,
is complete and plain ASCII English, and is the same text that web/crm_leads.js carries (BOS.crmLeads.INFO).
Run: python3 -I tests/py/test_crmg_info.py   (from the repository root)"""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
j = json.load(open(os.path.join(ROOT, 'docs/integration/CRM-G_info.json')))
sql = open(os.path.join(ROOT, 'supabase/phase323.sql')).read()
js = open(os.path.join(ROOT, 'web/crm_leads.js')).read()
fails = []


def chk(name, ok):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)


keys = [e['key'] for e in j['entries']]
rules = re.findall(r"^ \('(crm_[a-z_]+)', '(?:switch|number|choice|text)'", sql, flags=re.M)
grants = re.findall(r"^ \('(crm_[a-z_]+)', 'crm', ", sql, flags=re.M)
chk('phase323.sql defines 13 settings and 4 rights', len(rules) == 13 and len(grants) == 4)
chk('every setting has an info entry', all(r in keys for r in rules))
chk('every right has an info entry', all(g in keys for g in grants))
chk('both screens have an info entry', 'screen_crmleads' in keys and 'screen_crmtasks' in keys)
chk('no duplicate keys', len(keys) == len(set(keys)))
need = ('label', 'what_it_does', 'why_it_matters', 'default', 'if_switched', 'who_can_change')
chk('every entry says what it does, why, the default, what changes, who can change it', all(all(isinstance(e.get(k), str) and len(e[k].strip()) >= (3 if k == 'label' else 10) for k in need) for e in j['entries']))
chk('plain ASCII English only', all(all(ord(c) < 128 for c in json.dumps(e, ensure_ascii=False)) for e in j['entries']))
chk('every setting entry says who can change it: the owner', all('owner' in e['who_can_change'].lower() for e in j['entries'] if e['kind'] in ('setting', 'right')))
chk('every setting entry states a default that keeps today (Off, Blank, Owner, Manager, Reason, Given to nobody, Visible)',
    all(re.match(r'(Off|Blank|Owner|Manager|Reason|Given to nobody|Visible)', e['default']) for e in j['entries']))
chk('the label of a setting equals its label in the SQL', all(re.search(re.escape("'" + e['label'] + "'"), sql) for e in j['entries'] if e['kind'] == 'setting'))
m = re.search(r'/\*INFO-BEGIN\*/\s*Object\.assign\(INFO, (.*)\);\s*/\*INFO-END\*/', js, flags=re.S)
chk('web/crm_leads.js carries the info block', m is not None)
if m:
    info = json.loads(m.group(1))
    want = {e['key']: {k: e[k] for k in ('kind', 'label', 'what_it_does', 'why_it_matters', 'default', 'if_switched', 'who_can_change')} for e in j['entries']}
    chk('the block in the screen file equals the JSON file', info == want)
chk('no model names or demo words in the info text', not re.search(r'claude|gpt|opus|sonnet|haiku|DEMO_|IMAGINED', json.dumps(j), flags=re.I))
print('RESULT %d fail' % len(fails))
sys.exit(1 if fails else 0)

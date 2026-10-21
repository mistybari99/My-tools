#!/usr/bin/env python3
"""Checks docs/ai_kb/entries.json (the knowledge entries the AI helpers may quote) before they are proposed in the app.

Rules (mirror supabase/phase485.sql):
  * key: lower-case dotted name; version >= 1; title 2-160 chars; body 10-4000 chars; source and owner present.
  * status proposed | verified | retired. Only a VERIFIED entry is authoritative; a verified entry must name a verifier and a date,
    and the verifier must differ from the proposer. The builder may never verify (the owner verifies in the app).
  * no key-like text (API keys, tokens, passwords) in any entry.
Exit 0 = OK, 1 = a problem (printed). Standard library only. Run: python3 tools/ai_kb_check.py [path]
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT = os.path.join(ROOT, 'docs', 'ai_kb', 'entries.json')
KEY = re.compile(r'^[a-z][a-z0-9_.-]{2,80}$')
SECRET = re.compile(r'(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{20,}|password|service_role)', re.I)


def problems(doc):
    out = []
    if not isinstance(doc, dict) or doc.get('format') != 1 or not isinstance(doc.get('entries'), list):
        return ['file must be {"format": 1, "entries": [...]}']
    seen = set()
    for i, e in enumerate(doc['entries']):
        at = 'entry %d (%s)' % (i, e.get('key') if isinstance(e, dict) else '?')
        if not isinstance(e, dict):
            out.append(at + ': not an object')
            continue
        if not KEY.match(str(e.get('key', ''))):
            out.append(at + ': bad key')
        if not (isinstance(e.get('version'), int) and e['version'] >= 1):
            out.append(at + ': version must be an integer >= 1')
        if (e.get('key'), e.get('version')) in seen:
            out.append(at + ': duplicate key and version')
        seen.add((e.get('key'), e.get('version')))
        t = str(e.get('title', '')).strip()
        if not 2 <= len(t) <= 160:
            out.append(at + ': title 2-160 chars')
        b = str(e.get('body', ''))
        if not 10 <= len(b) <= 4000:
            out.append(at + ': body 10-4000 chars')
        for f in ('source', 'owner_code'):
            if not str(e.get(f, '')).strip():
                out.append(at + ': ' + f + ' missing')
        st = e.get('status')
        if st not in ('proposed', 'verified', 'retired'):
            out.append(at + ': status must be proposed, verified or retired')
        if st == 'verified':
            if not e.get('verified_by') or not e.get('verified_on'):
                out.append(at + ': verified needs verified_by and verified_on')
            if e.get('verified_by') == e.get('proposed_by'):
                out.append(at + ': self-verified (verifier = proposer)')
            if e.get('verified_by') == 'builder':
                out.append(at + ': the builder may not verify (the owner verifies in the app)')
        if SECRET.search(json.dumps(e, ensure_ascii=False)):
            out.append(at + ': key-like text found')
    return out


def main(argv):
    path = argv[1] if len(argv) > 1 else DEFAULT
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
    p = problems(doc)
    for line in p:
        print('PROBLEM', line)
    n = len(doc.get('entries', [])) if isinstance(doc, dict) and isinstance(doc.get('entries'), list) else 0
    print('ai_kb_check: %d entries, %d problem(s)' % (n, len(p)))
    return 1 if p else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

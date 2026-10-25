#!/usr/bin/env python3
"""Apply the Bangla review (docs/i18n/BANGLA_REVIEW.csv) to the web code, idempotently.

For every CSV row that has a suggestion, the tool finds the L(bn, en, mix) call (or the {bn:, mix:, en:} object of
web/i18n.js) in the row's file whose EN slot equals the row's `en` and whose bn slot equals `current_bn`, and rewrites
the bn slot (and the mix slot when the suggestion is not a rough "≈" draft).  Nothing else in the file is touched.

Safety rules
  * en slots are never edited (they are the anchor).
  * OLD text is protected: a triple (bn, en, mix) that exists unchanged in `git show 04eefa4:<file>` is never edited.
  * a row is skipped when the anchor is missing, when the bn slot no longer equals current_bn (somebody edited it),
    when the bn already equals the suggestion ("already"), or when the meaning is ambiguous (Void/Cancel/Reject,
    Cost/Expense, Due/Left/Waiting, ... -> listed with --needs-decision in docs/i18n/NEEDS_DECISION.md).
  * running it twice changes nothing; running it after other branches merged new code only touches strings that
    still match the CSV.

usage
  python3 tools/apply_bangla_review.py [--dry-run] [--files 'web/pos*.js'] [--csv docs/i18n/BANGLA_REVIEW.csv]
         [--base 04eefa4] [--needs-decision docs/i18n/NEEDS_DECISION.md] [--emit-sql supabase/phase108.sql] [-v]
"""
import argparse, csv, fnmatch, os, re, subprocess
from collections import Counter, OrderedDict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BASE_DEFAULT = '04eefa4'

# ---------------------------------------------------------------- JS literal parsing
ESC = {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f', 'v': '\v', '0': '\0', '\\': '\\', "'": "'", '"': '"', '`': '`', '\n': ''}


def parse_lit(t, i):
    """string literal at t[i] -> (value, start, end, quote) or None. Template literals with ${ are not parsed."""
    n = len(t)
    if i >= n or t[i] not in '\'"`':
        return None
    q = t[i]
    j = i + 1
    out = []
    while j < n:
        c = t[j]
        if c == '\\':
            if j + 1 >= n:
                return None
            d = t[j + 1]
            if d == 'u':
                if t[j + 2:j + 3] == '{':
                    k = t.find('}', j)
                    if k < 0:
                        return None
                    out.append(chr(int(t[j + 3:k], 16)))
                    j = k + 1
                else:
                    out.append(chr(int(t[j + 2:j + 6], 16)))
                    j += 6
                continue
            if d == 'x':
                out.append(chr(int(t[j + 2:j + 4], 16)))
                j += 4
                continue
            out.append(ESC.get(d, d))
            j += 2
            continue
        if c == q:
            return ''.join(out), i, j + 1, q
        if q == '`' and c == '$' and t[j + 1:j + 2] == '{':
            return None
        if q != '`' and c == '\n':
            return None
        out.append(c)
        j += 1
    return None


def enc_lit(v, q):
    v = v.replace('\\', '\\\\').replace(q, '\\' + q).replace('\n', '\\n')
    return q + v + q


WS = re.compile(r'(?:\s|/\*.*?\*/|//[^\n]*\n)*', re.S)


def skip_ws(t, i):
    return WS.match(t, i).end()


def find_triples(t):
    """list of dicts {bn, en, mix: (value,start,end,quote)} for every L(a,b,c) and {bn:,mix:,en:}"""
    res = []
    for m in re.finditer(r'(?<![\w$.])L\(', t):
        i = m.end()
        lits = []
        ok = True
        for k in range(3):
            i = skip_ws(t, i)
            lit = parse_lit(t, i)
            if not lit:
                ok = False
                break
            lits.append(lit)
            i = skip_ws(t, lit[2])
            if k < 2:
                if t[i:i + 1] != ',':
                    ok = False
                    break
                i += 1
        if ok:
            res.append({'bn': lits[0], 'en': lits[1], 'mix': lits[2]})
    km_re = re.compile(r'(bn|mix|en)\s*:')
    for m in re.finditer(r'\{\s*(?=(?:bn|mix|en)\s*:)', t):
        i = m.end()
        got = {}
        ok = True
        for k in range(3):
            i = skip_ws(t, i)
            km = km_re.match(t, i)
            if not km:
                ok = False
                break
            i = skip_ws(t, km.end())
            lit = parse_lit(t, i)
            if not lit:
                ok = False
                break
            got[km.group(1)] = lit
            i = skip_ws(t, lit[2])
            if k < 2:
                if t[i:i + 1] != ',':
                    ok = False
                    break
                i += 1
        if ok and len(got) == 3:
            res.append(got)
    return res


def git_show(base, path):
    try:
        return subprocess.run(['git', 'show', '%s:%s' % (base, path)], cwd=ROOT, capture_output=True, check=True).stdout.decode('utf-8')
    except Exception:
        return None


# ---------------------------------------------------------------- ambiguity (judgement cases)
# word -> ({meaning: regex on the EN text}, {canonical bn word of the reviewer's term table: meaning})
AMBIG = OrderedDict([
    ('বাতিল', ({'void': r'\bvoid', 'cancel': r'\bcancel', 'reject': r'reject|refus|declin|deny|denied', 'discard': r'discard|drop|abandon'},
               {'ভয়েড': 'void', 'ক্যান্সেল': 'cancel', 'রিজেক্ট': 'reject', 'ডিসকার্ড': 'discard'})),
    ('খরচ', ({'cost': r'\bcosts?\b|costing|costed', 'expense': r'expens|spend|spent|charge|\bfees?\b|outgo'},
              {'কস্ট': 'cost'})),
    ('বাকি', ({'due': r'\bdue\b|owed|owes|credit|receivable|payable', 'waiting': r'wait|pending|await|not yet', 'left': r'\bleft\b|remain|\brest\b'},
              {'অপেক্ষা': 'waiting', 'ডিউ': 'due'})),
    ('ফেরত', ({'return': r'\breturn', 'refund': r'refund|give back|paid back|pay back', 'change': r'\bchange\b'},
               {'রিফান্ড': 'refund', 'রিটার্ন': 'return', 'খুচরা': 'change'})),
    ('জমা', ({'deposit': r'deposit|paid in|put in', 'submit': r'submit|handed', 'sync': r'\bsync|upload|offline|queue'},
              {'সিঙ্ক': 'sync', 'ডিপোজিট': 'deposit', 'সাবমিট': 'submit'})),
])


def ambiguity(en, cur_bn, cur_mix, sug_bn, sug_mix):
    """None when clear, else (word, meanings found in en, recommended 'A'|'B')"""
    cur = (cur_bn or '') + ' ' + (cur_mix or '')
    sug = (sug_bn or cur_bn or '') + ' ' + (sug_mix or cur_mix or '')
    el = en.lower()
    for w, (meanings, canon) in AMBIG.items():
        if cur.count(w) > sug.count(w):  # the suggestion removes / changes this ambiguous word
            found = [k for k, rx in meanings.items() if re.search(rx, el)]
            if w == 'খরচ':
                if found == ['cost']:
                    continue
            elif len(found) == 1:
                continue
            rec = 'B'
            for cw, mk in canon.items():
                if mk in found and cw in sug:
                    rec = 'A'
            return w, found, rec
    return None


# ---------------------------------------------------------------- csv
def load_rows(path):
    rows = list(csv.DictReader(open(path, encoding='utf-8-sig')))
    for r in rows:
        sb, sm = r['suggested_bn'].strip(), r['suggested_mix'].strip()
        if sm.startswith('≈'):
            sm = ''  # rough draft derived from bn: not applied
            r['_approx_mix'] = True
        if sb.startswith('≈'):
            sb = ''
            r['_approx_bn'] = True
        r['_sb'], r['_sm'] = sb, sm
    return rows


def en_match(csv_en, code_en):
    if csv_en == code_en:
        return True
    if csv_en.endswith('…') and len(csv_en) > 150:  # the CSV cuts very long en texts
        return code_en.startswith(csv_en[:-1])
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv', default='docs/i18n/BANGLA_REVIEW.csv')
    ap.add_argument('--files', default='web/*.js', help="glob on the CSV path, e.g. 'web/pos*.js'")
    ap.add_argument('--base', default=BASE_DEFAULT)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--needs-decision', default=None, help='write the ambiguous rows as a markdown file')
    ap.add_argument('--emit-sql', default=None, help='write the additive SQL migration for the sql: rows (e.g. supabase/phase108.sql)')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    rows = load_rows(os.path.join(ROOT, a.csv))
    uniq = OrderedDict()  # one entry per unique (file, en, current_bn, current_mix, suggestion)
    for r in rows:
        if r['source'] != 'web' or not (r['_sb'] or r['_sm']):
            continue
        f = r['file_line'].rsplit(':', 1)[0]
        if not fnmatch.fnmatch(f, a.files):
            continue
        uniq.setdefault((f, r['en'], r['current_bn'], r['current_mix'], r['_sb'], r['_sm']), r)

    cnt = Counter()
    decisions = []
    by_file = OrderedDict()
    for k, r in uniq.items():
        by_file.setdefault(k[0], []).append((k, r))

    for f, items in by_file.items():
        p = os.path.join(ROOT, f)
        if not os.path.exists(p):
            cnt['skipped: file missing'] += len(items)
            continue
        text = open(p, encoding='utf-8').read()
        triples = find_triples(text)
        old = git_show(a.base, f)
        old_set = set((t['bn'][0], t['en'][0], t['mix'][0]) for t in find_triples(old)) if old else set()
        edits = []
        for (k, r) in items:
            _, en, cbn, cmix, sb, sm = k
            occ = [t for t in triples if en_match(en, t['en'][0])]
            occ = [t for t in occ if t['bn'][0] in (cbn, sb) or (sm and t['mix'][0] in (cmix, sm))]
            if not occ:
                cnt['skipped: anchor missing / text changed'] += 1
                if a.verbose:
                    print('SKIP anchor   %s | %s' % (r['file_line'], en[:60]))
                continue
            row_edits, protected, already = [], 0, 0
            for t in occ:
                if (t['bn'][0], t['en'][0], t['mix'][0]) in old_set:
                    protected += 1
                    continue
                want = []
                if sb and sb != cbn and t['bn'][0] == cbn:
                    want.append(('bn', sb))
                if sm and sm != cmix and t['mix'][0] == cmix:
                    want.append(('mix', sm))
                if want:
                    row_edits.append((t, want))
                else:
                    already += 1
            amb = ambiguity(en, cbn, cmix, sb, sm)
            if row_edits and amb:
                cnt['skipped: needs decision'] += 1
                decisions.append((r, amb))
                continue
            if row_edits:
                for t, want in row_edits:
                    for slot, val in want:
                        edits.append((t[slot][1], t[slot][2], enc_lit(val, t[slot][3])))
                cnt['applied'] += 1
                if a.verbose:
                    print('APPLY         %s | %s' % (r['file_line'], en[:60]))
            elif already:
                cnt['already (idempotent)'] += 1
            elif protected:
                cnt['old-text-protected'] += 1
            else:
                cnt['skipped: anchor missing / text changed'] += 1
        if edits and not a.dry_run:
            out, taken = text, set()
            for s, e, new in sorted(set(edits), key=lambda x: -x[0]):
                if (s, e) in taken:  # two CSV rows for the same slot: first one wins
                    continue
                taken.add((s, e))
                out = out[:s] + new + out[e:]
            open(p, 'w', encoding='utf-8').write(out)

    print('web rows with a suggestion (unique): %d' % len(uniq))
    for k in ('applied', 'already (idempotent)', 'old-text-protected', 'skipped: needs decision', 'skipped: anchor missing / text changed', 'skipped: file missing'):
        print('  %-42s %d' % (k, cnt[k]))
    print('  (rough "≈" mix drafts are never applied: %d web rows carry one)' % sum(1 for r in rows if r.get('_approx_mix') and r['source'] == 'web'))
    if a.dry_run:
        print('DRY RUN: no file written')
    if a.needs_decision:
        write_decisions(os.path.join(ROOT, a.needs_decision), decisions, rows, a)
    if a.emit_sql:
        emit_sql(os.path.join(ROOT, a.emit_sql), rows, a)


def write_decisions(path, decisions, rows, a):
    sqlrows = []
    for r in rows:
        if r['source'].startswith('sql') and (r['_sb'] or r['_sm']):
            amb = ambiguity(r['en'], r['current_bn'], r['current_mix'], r['_sb'], r['_sm'])
            if amb:
                sqlrows.append((r, amb))
    allr = decisions + sqlrows
    seen = set()
    L = ['# Needs a decision (Bangla wording)', '',
         'Generated by `python3 tools/apply_bangla_review.py --needs-decision docs/i18n/NEEDS_DECISION.md`. These strings were NOT changed: the English text allows two meanings for the word the reviewer wants to replace',
         '(বাতিল = Void / Cancel / Reject, খরচ = Cost / Expense, বাকি = Due / Left / Waiting, ফেরত, জমা). Answer per id, e.g. `D3: A`. Option A = apply the reviewer\'s suggestion, option B = keep the current text.',
         'After the answers, re-run the tool with the chosen rows (or edit by hand); rows answered B can be deleted from the CSV.', '']
    items = []
    for r, (w, found, rec) in allr:
        key = (r['file_line'], r['en'])
        if key in seen:
            continue
        seen.add(key)
        items.append((r, w, found, rec))
    L.append('Total: %d items (%d web + sql rows, listed once per file:line).' % (len(items), len(items)))
    L.append('')
    for n, (r, w, found, rec) in enumerate(items, 1):
        L.append('- **D%d** `%s` word `%s` (meanings in en: %s)' % (n, r['file_line'], w, ', '.join(found) or 'none'))
        L.append('  - en: %s' % r['en'].replace('\n', ' '))
        L.append('  - A: bn `%s`%s' % (r['_sb'] or r['current_bn'], ('  mix `%s`' % r['_sm']) if r['_sm'] else ''))
        L.append('  - B: keep bn `%s`' % r['current_bn'])
        L.append('  - recommended: %s' % rec)
    if not a.dry_run:
        open(path, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
    print('needs-decision items: %d -> %s' % (len(items), os.path.relpath(path, ROOT)))


SQL_TABLES = {  # table: (key column, has label_mix)
    'rules': ('key', True), 'grant_defs': ('grant_code', True), 'setup_check_defs81': ('code', True),
    'manual_reason_codes85': ('code', True), 'grant_separation_pairs': ('code', False), 'cost_component_types': ('code', False),
}

SQL_HEAD = """-- ============================================================
-- Phase 108 (bos108) - Bangla wording fixes for the label_bn / label_mix seed rows of phases 72..103 (docs/i18n/BANGLA_REVIEW.md).
--   Generated by tools/apply_bangla_review.py --emit-sql (re-run after the CSV changes; the file is rewritten whole).
--   Needs phases 72..103 pasted first (guard below). Additive + paste-twice safe: every UPDATE fires only while the column STILL equals the old seed
--   text, so an owner edit, an old row (pre-72) or an already-fixed row is never overwritten. No table, column, function or privilege is changed.
--   Phases 104..107 are reserved by other agents.
-- ============================================================

"""
SQL_GUARD = open(os.path.join(os.path.dirname(__file__), 'apply_bangla_review.guard.sql'), encoding='utf-8').read() if os.path.exists(os.path.join(os.path.dirname(__file__), 'apply_bangla_review.guard.sql')) else ''


def q(s):
    return "'" + s.replace("'", "''") + "'"


def emit_sql(path, rows, a):
    stm, seen, skipped = [], set(), Counter()
    for r in rows:
        if not r['source'].startswith('sql') or not (r['_sb'] or r['_sm']):
            continue
        parts = r['source'].split(':')
        tab, key = parts[1], (parts[2] if len(parts) > 2 else '')
        if tab not in SQL_TABLES or not key:
            skipped['table/key not handled'] += 1
            continue
        if ambiguity(r['en'], r['current_bn'], r['current_mix'], r['_sb'], r['_sm']):
            skipped['needs decision'] += 1
            continue
        kc, has_mix = SQL_TABLES[tab]
        for col, new, cur, ok in (('label_bn', r['_sb'], r['current_bn'], True), ('label_mix', r['_sm'], r['current_mix'], has_mix)):
            if not new or not ok:
                continue
            s = "  update public.%s set %s = %s where %s = %s and %s = %s;" % (tab, col, q(new), kc, q(key), col, q(cur))
            if s not in seen:
                seen.add(s)
                stm.append((tab, s))
    body = ['-- %d statements (%s)' % (len(stm), ', '.join('%s %d' % kv for kv in sorted(Counter(t for t, _ in stm).items())))]
    last = None
    for t, s in stm:
        if t != last:
            body.append('\n-- ---------- %s ----------' % t)
            last = t
        body.append(s)
    # one DO block: when the guard raises, none of the UPDATEs runs (psql would otherwise go on with the next statement)
    txt = (SQL_HEAD + "do $g$\ndeclare miss text := ''; m record;\nbegin\n" + SQL_GUARD + '\n'.join(b.replace('\n-- ----------', '  -- ----------') for b in body) + '\nend $g$;\n')
    if not a.dry_run:
        open(path, 'w', encoding='utf-8').write(txt)
    print('sql statements: %d -> %s%s; not emitted: %s' % (len(stm), os.path.relpath(path, ROOT), ' (dry-run, not written)' if a.dry_run else '', dict(skipped)))


if __name__ == '__main__':
    main()

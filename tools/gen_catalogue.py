#!/usr/bin/env python3
"""Generate docs/backend/catalogue/*.md from a built scratch Postgres database.

The catalogue is READ-ONLY documentation: it never touches the live database.
It reads a scratch DB (built by tests/sql/final_build.sh in the paste order of
docs/PASTE_ORDER.md, phases 99..103 included) through the `psql` command line,
plus the SQL files in supabase/ (to find the phase that introduced an object)
and web/ia.js + web/app.js (for the routes).

Usage:
  python3 tools/gen_catalogue.py --build d3cat      # build the scratch DB first, then generate
  python3 tools/gen_catalogue.py --db d3cat         # generate from an existing scratch DB
Env: PGSOCK (default /tmp), PGPORT (default 5544), PGUSER (default postgres).
Needs: python3, psql, node (node only for the routes catalogue).
Output is deterministic (no timestamps): re-running on the same DB gives identical files.
"""
import argparse, json, os, re, subprocess, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SUPA = os.path.join(REPO, 'supabase')
WEB = os.path.join(REPO, 'web')
OUT = os.path.join(REPO, 'docs', 'backend', 'catalogue')
PGSOCK = os.environ.get('PGSOCK', '/tmp')
PGPORT = os.environ.get('PGPORT', '5544')
PGUSER = os.environ.get('PGUSER', 'postgres')

# scratch-only identity used (inside a rolled-back transaction) to call the owner-only recommendation functions
SCRATCH_UID = '00000000-0000-0000-0000-0000000000aa'


# ----------------------------------------------------------------------------- helpers
def psql_base(db):
    return ['psql', '-h', PGSOCK, '-p', PGPORT, '-U', PGUSER, '-d', db, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1']


def q_json(db, sql):
    """Run one SELECT and return the rows as a list of dicts."""
    wrapped = "select coalesce(json_agg(t), '[]'::json) from (" + sql + ") t"
    r = subprocess.run(psql_base(db) + ['-c', wrapped], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('psql failed: ' + r.stderr.strip()[:600] + '\nSQL: ' + sql[:300])
    return json.loads(r.stdout.strip() or '[]')


def q_script(db, script):
    r = subprocess.run(psql_base(db) + ['-f', '-'], input=script, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('psql script failed: ' + r.stderr.strip()[:600])
    return r.stdout


def esc(s):
    """Escape a value for a markdown table cell."""
    if s is None:
        return ''
    s = str(s).replace('\r', ' ').replace('\n', ' ').replace('|', '\\|')
    return re.sub(r'\s+', ' ', s).strip()


def short(s, n=200):
    s = re.sub(r'\s+', ' ', str(s or '')).strip()
    return s if len(s) <= n else s[:n - 1].rstrip() + '...'


def jv(v):
    """Compact JSON value for a cell."""
    if v is None:
        return ''
    if isinstance(v, str):
        return v
    return json.dumps(v, ensure_ascii=False, separators=(',', ':'))


# ----------------------------------------------------------------------------- build order / phases
def canonical_order():
    """Foundation + final_build.sh ORDER + phases 99..103 (102 sits between 101 and 103, see docs/PASTE_ORDER.md)."""
    txt = open(os.path.join(REPO, 'tests', 'sql', 'final_build.sh'), encoding='utf-8').read()
    m = re.search(r'ORDER=\$\{2:-"([^"]*)"\}', txt)
    if not m:
        sys.exit('cannot read ORDER from tests/sql/final_build.sh')
    order = ['schema', 'phase2', 'phase3', 'phase4', 'ALL_NEW'] + m.group(1).split()
    for p in ('phase99', 'phase100', 'phase101', 'phase102', 'phase103'):
        if p not in order:
            order.append(p)
    return [p for p in order if os.path.exists(os.path.join(SUPA, p + '.sql'))]


EXTENDED_ORDER_FOR_BUILD = None


def build_db(db):
    order = canonical_order()
    base = order[5:]  # drop the foundation files that final_build.sh always runs itself
    cmd = ['bash', os.path.join(REPO, 'tests', 'sql', 'final_build.sh'), db, ' '.join(base)]
    env = dict(os.environ, REPO=REPO, PGSOCK=PGSOCK, PGPORT=PGPORT)
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    out = r.stdout + r.stderr
    if 'built ' + db not in out or re.search(r'(^|\n)(ERROR|FAIL)', out):
        sys.exit('build problem:\n' + out[-1500:])
    print('built scratch DB', db)


class Sources:
    def __init__(self):
        self.order = canonical_order()
        self.idx = {p: i for i, p in enumerate(self.order)}
        self.text = {}
        for p in self.order:
            self.text[p] = open(os.path.join(SUPA, p + '.sql'), encoding='utf-8', errors='replace').read()
        self.fn_defs = {}   # name -> [(order_idx, file, pos)]
        self.tbl_defs = {}  # name -> [order_idx, ...]
        fre = re.compile(r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-zA-Z_][a-zA-Z0-9_]*)"?\s*\(', re.I)
        tre = re.compile(r'create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-zA-Z_][a-zA-Z0-9_]*)"?', re.I)
        for p in self.order:
            t = self.text[p]
            for m in fre.finditer(t):
                self.fn_defs.setdefault(m.group(1).lower(), []).append((self.idx[p], p, m.start()))
            for m in tre.finditer(t):
                self.tbl_defs.setdefault(m.group(1).lower(), []).append(self.idx[p])
        # statement chunks of "insert into rules" / "insert into grant_defs"
        self.rule_chunks = self._chunks(r'insert\s+into\s+(?:public\.)?rules\b')
        self.grant_chunks = self._chunks(r'insert\s+into\s+(?:public\.)?grant_defs\b')

    def _chunks(self, pat):
        out = []
        rx = re.compile(pat, re.I)
        for p in self.order:
            t = self.text[p]
            for m in rx.finditer(t):
                # statement ends at the first line that ends with ';'
                end = m.start()
                for ln in re.finditer(r'[^\n]*\n?', t[m.start():]):
                    end = m.start() + ln.end()
                    if ln.group(0).rstrip().endswith(';'):
                        break
                out.append((p, t[m.start():end]))
        return out

    def first_for_key(self, key, chunks):
        needle = "'" + key + "'"
        for p, c in chunks:
            if needle in c:
                return p, False
        for p in self.order:   # fallback: any quoted mention (approximate)
            if needle in self.text[p]:
                return p, True
        return None, False

    def fn_phases(self, name):
        d = self.fn_defs.get(name.lower())
        if not d:
            return None, None, None
        d = sorted(d)
        return d[0][1], d[-1][1], d[-1]

    def leading_comment(self, d):
        """Comment lines (-- ...) directly above the last CREATE of the function."""
        _, p, pos = d
        t = self.text[p]
        lines_above = t[:pos].split('\n')
        # the create may be indented / not at line start; drop the partial last line
        lines_above = lines_above[:-1] if lines_above else []
        got = []
        for ln in reversed(lines_above):
            s = ln.strip()
            if s.startswith('--'):
                got.append(re.sub(r'^-+\s*', '', s).strip(' -='))
            elif s == '':
                if got:
                    break
                continue
            else:
                break
        got = [g for g in reversed(got) if g]
        return ' '.join(got[:2]) if got else ''


def label(p):
    return p if p in ('schema', 'ALL_NEW') else p


# ----------------------------------------------------------------------------- markdown writer
def write(name, text):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
        f.write(text.rstrip('\n') + '\n')


HEADER = ('<!-- GENERATED by tools/gen_catalogue.py from a scratch database built in the order of docs/PASTE_ORDER.md '
          '(phases 72..103 incl. 99..103). Do not edit by hand; re-run the generator (see CATALOGUE_README.md). -->\n')


# ----------------------------------------------------------------------------- main generation
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', help='existing scratch database name')
    ap.add_argument('--build', help='build this scratch database first (drops and recreates it), then generate')
    a = ap.parse_args()
    db = a.build or a.db
    if not db:
        ap.error('give --db NAME or --build NAME')
    if a.build:
        build_db(db)
    src = Sources()
    counts = {}

    # ---------- database facts
    rules = q_json(db, "select * from public.rules order by module, sort, key")
    defs81 = q_json(db, "select code, rule_key, phase, module, rec_value, reason_en from public.setup_rec_defs81 where active order by sort, code")
    grants = q_json(db, "select * from public.grant_defs order by module, sort, grant_code")
    reco_role = q_json(db, "select role_code, grant_code, reason_en from public.perm_reco_role order by grant_code, role_code")
    sep_pairs = q_json(db, "select code, entry_grant, approve_grant, label_en from public.grant_separation_pairs order by code")
    conflicts = q_json(db, "select token_a, token_b, reason_en, active from public.perm_conflict order by token_a, token_b")

    # owner-only recommendation functions, called inside a rolled-back transaction (scratch data only)
    script = f"""begin;
insert into auth.users(id, email) values ('{SCRATCH_UID}', 'scratch@example.invalid');
update public.profiles set status = 'active' where id = '{SCRATCH_UID}';
insert into public.user_roles(user_id, role_code) values ('{SCRATCH_UID}', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', '{SCRATCH_UID}', true);
select 'JSON:guard:' || public.guard_recommendations()::text;
select 'JSON:form:' || public.form_guard_recommendations()::text;
select 'JSON:prod:' || public.production_recommendations()::text;
rollback;
"""
    fn_recs = {}
    for line in q_script(db, script).splitlines():
        m = re.match(r'JSON:(guard|form|prod):(.*)$', line)
        if m:
            fn_recs[m.group(1)] = json.loads(m.group(2))
    for k in ('guard', 'form', 'prod'):
        if k not in fn_recs:
            sys.exit('recommendation function ' + k + ' returned nothing (is the scratch owner set up?)')

    rec_by_key = {}
    for d in defs81:
        rec_by_key.setdefault(d['rule_key'], []).append(
            'advisor (setup_rec_defs81, phase %s): `%s` - %s' % (d['phase'], jv(d['rec_value']) if d['rec_value'] is not None else '(computed when read)', d['reason_en']))
    fn_names = {'guard': 'guard_recommendations()', 'form': 'form_guard_recommendations()', 'prod': 'production_recommendations()'}
    for k, lst in fn_recs.items():
        for it in lst:
            rec_by_key.setdefault(it['key'], []).append(
                '%s: `%s` - %s' % (fn_names[k], jv(it.get('recommended')), it.get('reason_en', '')))

    # ============================================================ RULES
    rule_keys = {r['key'] for r in rules}
    rows = []
    unknown_rule_phase = 0
    approx_rule_phase = 0
    rules_with_rec = 0
    for r in rules:
        p, approx = src.first_for_key(r['key'], src.rule_chunks)
        if p is None:
            ph = 'unknown'
            unknown_rule_phase += 1
        else:
            ph = p + ('~' if approx else '')
            approx_rule_phase += 1 if approx else 0
        spec = []
        if r['choices'] is not None:
            spec.append('choices: ' + jv(r['choices']))
        if r['min_value'] is not None:
            spec.append('min: ' + jv(r['min_value']))
        if r['max_value'] is not None:
            spec.append('max: ' + jv(r['max_value']))
        if r['unit']:
            spec.append('unit: ' + r['unit'])
        rec = rec_by_key.get(r['key'])
        if rec:
            rules_with_rec += 1
        rows.append('| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            r['key'], esc(r['module']), esc(r['kind']), esc('`%s`' % jv(r['default_value']) if r['default_value'] is not None else ''),
            esc('; '.join(spec)), esc(r['label_en'] or '(none)'), esc(r['hint_en'] or ''), esc(ph),
            '<br>'.join(esc(x) for x in rec) if rec else '-'))
    kinds = {}
    for r in rules:
        kinds[r['kind']] = kinds.get(r['kind'], 0) + 1
    counts['rules'] = len(rules)
    md = [HEADER, '# Rules catalogue\n',
          'Every row of `public.rules` in a scratch database built from the canonical paste order (including phases 99..103).\n',
          '- Rows: **%d** (%s).' % (len(rules), ', '.join('%s %d' % (k, v) for k, v in sorted(kinds.items()))),
          '- Rows with a recommendation: **%d**. Sources: `setup_rec_defs81` (%d active advisor rows), `guard_recommendations()` (%d), `form_guard_recommendations()` (%d), `production_recommendations()` (%d).' % (
              rules_with_rec, len(defs81), len(fn_recs['guard']), len(fn_recs['form']), len(fn_recs['prod'])),
          '- Phase = first file in paste order whose `INSERT INTO rules` statement names the key; a trailing `~` means no such insert was found and the first plain mention was used; `unknown` = not found in supabase/*.sql (%d unknown, %d approximate).' % (unknown_rule_phase, approx_rule_phase),
          '- The recommendation functions are owner-only and compute their text from the data; this catalogue calls them on an empty scratch database, so values that depend on live data (for example `purchase_grn_guard`) show the empty-database answer.',
          '- Default = `default_value` column. English labels and hints only; Bangla and mixed texts stay in the database.\n',
          '| key | module | kind | default | choices / min / max / unit | label (en) | hint (en) | introduced | recommended value and reason |',
          '|---|---|---|---|---|---|---|---|---|'] + rows
    write('RULES_CATALOGUE.md', '\n'.join(md))

    # ============================================================ FUNCTIONS
    funcs = q_json(db, """
      select p.oid::int as oid, p.proname as name, pg_get_function_identity_arguments(p.oid) as args,
             pg_get_function_result(p.oid) as result, p.prokind as kind, p.provolatile as vol, p.prosecdef as secdef,
             p.proacl::text as acl,
             has_function_privilege('anon', p.oid, 'execute') as anon_x,
             has_function_privilege('authenticated', p.oid, 'execute') as auth_x,
             has_function_privilege('service_role', p.oid, 'execute') as svc_x,
             exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_x,
             obj_description(p.oid, 'pg_proc') as cmt,
             pg_get_functiondef(p.oid) as def
      from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')
        and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      order by p.proname, pg_get_function_identity_arguments(p.oid)""")
    volname = {'i': 'immutable', 's': 'stable', 'v': 'volatile'}
    frows = []
    f_unknown = 0
    f_secdef = 0
    f_nocomment = 0
    f_tagged = 0
    gate_re = re.compile(r"(is_owner\(\)|has_grant\('[a-z0-9_]+'\)|can_do\('[A-Za-z0-9_]+',\s*'[a-z]+'\)|is_active\(\)|can_loc\([^)]*\))")
    grant_fn_use = {}
    for f in funcs:
        first, last, d = src.fn_phases(f['name'])
        if first is None:
            f_unknown += 1
            ph1 = ph2 = 'unknown'
        else:
            ph1, ph2 = first, last
        body = f['def'] or ''
        tags = sorted(set(re.findall(r'bos\d+', body, re.I)), key=lambda x: int(re.sub(r'\D', '', x)))
        tags = [t.lower() for t in tags]
        if tags:
            f_tagged += 1
        who = []
        if f['public_x']:
            who.append('PUBLIC')
        else:
            if f['anon_x']:
                who.append('anon')
            if f['auth_x']:
                who.append('authenticated')
            if f['svc_x']:
                who.append('service_role')
        who_s = ', '.join(who) if who else 'owner/superuser only'
        gates = sorted(set(m.group(1) for m in gate_re.finditer(body)))
        for g in re.findall(r"has_grant\('([a-z0-9_]+)'\)", body):
            grant_fn_use.setdefault(g, set()).add(f['name'])
        purpose = f['cmt'] or ''
        if not purpose and d:
            purpose = src.leading_comment(d)
        if not purpose:
            # first comment line inside the body (after the opening $$ / begin)
            mm = re.search(r'\$[a-z_]*\$(.*)$', body, re.S)
            inner = mm.group(1) if mm else ''
            for ln in inner.split('\n')[:8]:
                s = ln.strip()
                if s.startswith('--'):
                    purpose = re.sub(r'^-+\s*', '', s).strip(' -=')
                    if purpose:
                        break
        if not purpose:
            f_nocomment += 1
        if f['secdef']:
            f_secdef += 1
        sig = '%s(%s)' % (f['name'], f['args'])
        if f['kind'] == 'p':
            sig = 'PROCEDURE ' + sig
        frows.append('| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            esc(sig), esc(f['result']), volname.get(f['vol'], f['vol']), 'yes' if f['secdef'] else 'no', esc(who_s),
            esc(ph1 if ph1 == ph2 else ph1 + ' -> ' + ph2), esc(', '.join(tags) or '-'), esc(', '.join(gates) or '-'),
            esc(short(purpose, 220)) if purpose else '(no comment)'))
    counts['functions'] = len(funcs)
    names = len({f['name'] for f in funcs})
    md = [HEADER, '# Functions catalogue\n',
          'Every function and procedure in schema `public` of the scratch database (extension-owned objects excluded), one row per signature.\n',
          '- Signatures: **%d** (%d distinct names). Security definer: **%d**. Carrying at least one `bosNN` tag in the body: **%d**.' % (len(funcs), names, f_secdef, f_tagged),
          '- First -> last phase = first and last file, in paste order, that holds a `CREATE [OR REPLACE] FUNCTION <name>(` (by name, so overloads share the span); `unknown` = no such statement in supabase/*.sql (%d). Foundation files are `schema`, `phase2..4`, `ALL_NEW`.' % f_unknown,
          '- Who may execute = real `EXECUTE` privilege in the scratch DB (`PUBLIC` = granted to everyone). The build gives `anon` and `authenticated` default privileges on new functions (like Supabase), so a function that phases never revoke shows both. `owner/superuser only` = revoked from all API roles.',
          '- Body gates = authorisation calls found by pattern in the function text (`is_owner()`, `has_grant(...)`, `can_do(...)`, `is_active()`, `can_loc(...)`); a function that checks through a helper shows `-`. Heuristic, not a proof.',
          '- Purpose = `COMMENT ON FUNCTION` if present, else the comment lines above the last `CREATE` in the SQL file, else the first comment line of the body; `(no comment)` for %d signatures.\n' % f_nocomment,
          '| signature | returns | volatility | security definer | who may execute | first -> last phase | bosNN tags | body gates | purpose |',
          '|---|---|---|---|---|---|---|---|---|'] + frows
    write('FUNCTIONS_CATALOGUE.md', '\n'.join(md))

    # ============================================================ TABLES
    tbls = q_json(db, """
      select c.oid::int as oid, c.relname as name, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls,
             obj_description(c.oid, 'pg_class') as cmt
      from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p')
      order by c.relname""")
    cols = q_json(db, """
      select c.relname as tbl, a.attnum as n, a.attname as col, format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull as nn,
             pg_get_expr(d.adbin, d.adrelid) as def, a.attidentity as ident, a.attgenerated as gen
      from pg_attribute a join pg_class c on c.oid = a.attrelid
      left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p') and a.attnum > 0 and not a.attisdropped
      order by c.relname, a.attnum""")
    pols = q_json(db, """
      select tablename as tbl, policyname as name, cmd, roles::text as roles, qual, with_check
      from pg_policies where schemaname = 'public' order by tablename, policyname""")
    trigs = q_json(db, """
      select c.relname as tbl, t.tgname as name, p.proname as fn, t.tgtype::int as tt,
             pg_get_functiondef(p.oid) as fdef
      from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
      where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
      order by c.relname, t.tgname""")
    cols_by, pols_by, trig_by = {}, {}, {}
    for c in cols:
        cols_by.setdefault(c['tbl'], []).append(c)
    for p in pols:
        pols_by.setdefault(p['tbl'], []).append(p)
    for t in trigs:
        trig_by.setdefault(t['tbl'], []).append(t)
    append_re = re.compile(r'append|immutable|read.?only|never (?:be )?(?:changed|edited|deleted|updated|rewritten)|no_delete|nodel|no_hard_delete|_ro\d*$|_ro_|ledger_immutable', re.I)

    def trig_events(tt):
        ev = []
        if tt & 4:
            ev.append('INSERT')
        if tt & 8:
            ev.append('DELETE')
        if tt & 16:
            ev.append('UPDATE')
        if tt & 32:
            ev.append('TRUNCATE')
        timing = 'BEFORE' if tt & 2 else ('INSTEAD OF' if tt & 64 else 'AFTER')
        return timing, ev

    t_rls = 0
    t_norls = []
    t_append = 0
    t_unknown = 0
    sections = []
    for t in tbls:
        name = t['name']
        d = sorted(src.tbl_defs.get(name.lower(), []))
        if d:
            ph = src.order[d[0]]
        else:
            ph = 'unknown'
            t_unknown += 1
        if t['rls']:
            t_rls += 1
        else:
            t_norls.append(name)
        tr = trig_by.get(name, [])
        ap_list, other = [], []
        for x in tr:
            timing, ev = trig_events(x['tt'])
            guard = timing == 'BEFORE' and ('UPDATE' in ev or 'DELETE' in ev) and 'raise exception' in (x['fdef'] or '').lower() \
                and (append_re.search(x['fn']) or re.search(r'append[_ -]?only|immutable|never (?:be )?(?:changed|edited|deleted|updated)|read-only', x['fdef'] or '', re.I))
            desc = '`%s` %s %s -> `%s()`' % (x['name'], timing, '/'.join(ev), x['fn'])
            (ap_list if guard else other).append(desc)
        if ap_list:
            t_append += 1
        s = ['### `%s`\n' % name,
             '- Introduced: %s' % ph,
             '- RLS enabled: **%s**%s' % ('yes' if t['rls'] else 'no', ' (forced)' if t['force_rls'] else '')]
        if t['cmt']:
            s.append('- Comment: ' + short(t['cmt'], 240))
        s.append('- Append-only / immutable-style triggers (BEFORE UPDATE/DELETE that raise): %s' % ('; '.join(ap_list) if ap_list else 'none'))
        if other:
            s.append('- Other triggers: ' + '; '.join(other))
        ps = pols_by.get(name, [])
        if ps:
            s.append('- Policies:')
            for p in ps:
                cond = ''
                if p['qual']:
                    cond += ' USING ' + short(p['qual'], 140)
                if p['with_check']:
                    cond += ' WITH CHECK ' + short(p['with_check'], 140)
                s.append('  - `%s` %s to %s%s' % (p['name'], p['cmd'], p['roles'].strip('{}'), (':' + cond) if cond else ''))
        else:
            s.append('- Policies: none')
        s.append('- Columns:')
        for c in cols_by.get(name, []):
            extra = []
            if c['nn']:
                extra.append('not null')
            if c['def'] is not None:
                extra.append('default ' + short(c['def'], 80))
            if c['ident']:
                extra.append('identity')
            if c['gen']:
                extra.append('generated')
            s.append('  - `%s` %s%s' % (c['col'], c['typ'], (' (' + ', '.join(extra) + ')') if extra else ''))
        sections.append('\n'.join(s))
    counts['tables'] = len(tbls)
    views = q_json(db, "select count(*)::int as n from pg_class where relnamespace='public'::regnamespace and relkind in ('v','m')")[0]['n']
    counts['views'] = views
    md = [HEADER, '# Tables catalogue\n',
          'Every ordinary table in schema `public` of the scratch database (%d views are not listed here).\n' % views,
          '- Tables: **%d**. RLS enabled on **%d**; RLS **off** on %d: %s.' % (len(tbls), t_rls, len(t_norls), ', '.join('`%s`' % x for x in t_norls) or 'none'),
          '- Tables with at least one append-only / immutable-style trigger: **%d**. Detection is heuristic: a BEFORE UPDATE/DELETE trigger whose function raises and is named or worded like append-only / immutable / read-only / no-delete.' % t_append,
          '- Introduced = first file in paste order with a `CREATE TABLE <name>`; `unknown` (%d) = created some other way (for example dynamically) or not in supabase/*.sql.' % t_unknown,
          '- Policies are shown as in `pg_policies` (condition text shortened to 140 characters). Triggers named `audit_*` (`log_change`) and similar bookkeeping triggers are listed under Other triggers.\n'] + sections
    write('TABLES_CATALOGUE.md', '\n'.join(md))

    # ============================================================ ROUTES (needed by the grants catalogue too)
    routes, groups, route_note = load_routes(rule_keys)

    # ============================================================ GRANTS
    roles_by_grant = {}
    for r in reco_role:
        roles_by_grant.setdefault(r['grant_code'], []).append(r['role_code'])
    gr_routes = {}
    for r in routes:
        for g in r['grants']:
            gr_routes.setdefault(g, []).append(r['id'])
    grows = []
    g_unknown = 0
    g_norole = 0
    for g in grants:
        p, approx = src.first_for_key(g['grant_code'], src.grant_chunks)
        if p is None:
            g_unknown += 1
            ph = 'unknown'
        else:
            ph = p + ('~' if approx else '')
        roles = sorted(roles_by_grant.get(g['grant_code'], []))
        if not roles:
            g_norole += 1
        grows.append('| `%s` | %s | %s | %s | %s | %s | %s | %s | %s |' % (
            g['grant_code'], esc(g['module']), esc(g['label_en'] or '(none)'), esc(g['window_type']), esc(g['emergency_rule'] or '-'),
            esc(', '.join(roles) or 'none (owner delegates by hand)'), esc(ph),
            esc(', '.join(sorted(grant_fn_use.get(g['grant_code'], []))[:6]) + (' ...' if len(grant_fn_use.get(g['grant_code'], [])) > 6 else '') or '-'),
            esc(', '.join(sorted(gr_routes.get(g['grant_code'], []))) or '-')))
    counts['grants'] = len(grants)
    md = [HEADER, '# Grants catalogue\n',
          'Every row of `public.grant_defs` (a grant is a right the owner can hand to one person; the owner always holds all of them).\n',
          '- Grant definitions: **%d**. Default roles come from `perm_reco_role` (%d role/grant pairs over %d roles); %d grants have no default role.' % (
              len(grants), len(reco_role), len({r['role_code'] for r in reco_role}), g_norole),
          '- Window = `once` (one use) or `window` (a time window) as stored in `window_type`. Emergency rule = the `emergency_rule` code, if the grant can be asked for in an emergency.',
          '- Introduced = first file whose `INSERT INTO grant_defs` names the code (`~` = approximate; %d unknown).' % g_unknown,
          '- Functions gated = functions whose body calls `has_grant(\'<code>\')` (first six names). Routes = screens in web/ia.js whose visibility predicate reads `GF.<code>`.\n',
          '| code | module | meaning (en) | window | emergency rule | default roles | introduced | functions gated | routes |',
          '|---|---|---|---|---|---|---|---|---|'] + grows
    md += ['', '## Segregation pairs (`grant_separation_pairs`)\n', '| code | entry grant | approve grant | meaning (en) |', '|---|---|---|---|']
    md += ['| `%s` | `%s` | `%s` | %s |' % (p['code'], p['entry_grant'], p['approve_grant'], esc(p['label_en'])) for p in sep_pairs]
    md += ['', '## Conflicting permission tokens (`perm_conflict`)\n', '| token A | token B | reason (en) | active |', '|---|---|---|---|']
    md += ['| `%s` | `%s` | %s | %s |' % (c['token_a'], c['token_b'], esc(c['reason_en']), 'yes' if c['active'] else 'no') for c in conflicts]
    md += ['', '## Recommended grants per role (`perm_reco_role`)\n', '| role | grant | reason (en) |', '|---|---|---|']
    md += ['| `%s` | `%s` | %s |' % (r['role_code'], r['grant_code'], esc(r['reason_en'])) for r in sorted(reco_role, key=lambda x: (x['role_code'], x['grant_code']))]
    counts['perm_reco_role'] = len(reco_role)
    counts['sep_pairs'] = len(sep_pairs)
    counts['conflicts'] = len(conflicts)
    write('GRANTS_CATALOGUE.md', '\n'.join(md))

    # ============================================================ ROUTES
    rrows = []
    for r in routes:
        rrows.append('| `%s` | %s | %s | %s | %s | %s | %s | %s |' % (
            r['id'], esc(r['group_label']), esc(r['label_en']), esc(r['status'] + ('' if r['drawer'] else ', not in drawer') + ((', alias of ' + r['alias']) if r['alias'] else '')),
            esc(r['gate_text']), esc(', '.join(r['rules']) or '-'), esc(r['script']), esc(r['server_gate'])))
    counts['routes'] = len(routes)
    md = [HEADER, '# Routes catalogue\n',
          'Every record of the screen registry `web/ia.js` (`BOS.IA`). Evaluated with node against stubbed globals; nothing in the browser is run.\n',
          '- Routes: **%d** in **%d** groups. %s' % (len(routes), len(groups), route_note),
          '- Gate = what the record\'s own visibility predicate (`ok`) reads: `owner` (`c.own`), `perm ITEMS:view` (`c.P(code, action)`), `grant x` (`c.GF.x`), `location access` (`locOk`), `POS access` (`canPos`), `any approval right` (`anyApprove`), `control access` (`ctlOk`), `everyone`. The server stays the authority; hiding a screen is a convenience.',
          '- Rules read by the script = rule keys (that exist in `public.rules`) named in `rule(...)` calls in the screen\'s script file(s). Heuristic: it shows which switches the screen reacts to, not a hard gate. ia.js itself reads no rule; the owner\'s Hide choice (`optviews`) can also hide any route.',
          '- Server gate = entry in `OWNER_ONLY` (web/app.js: owners only) and, if any, the grants in `ROUTE_GRANTS` that also open it.',
          '- Script = file in web/ that registers the page in `BOS_PAGES` (or `app.js` for the built-in screens); the page is the first path segment of the route.\n',
          '| route id | group | label (en) | status | gate (ia.js) | rules read by the script | script file | server gate (app.js) |',
          '|---|---|---|---|---|---|---|---|'] + rrows
    write('ROUTES_CATALOGUE.md', '\n'.join(md))

    # ============================================================ README
    extra = {
        'unknown_rule_phase': unknown_rule_phase, 'approx_rule_phase': approx_rule_phase, 'rules_with_rec': rules_with_rec,
        'f_unknown': f_unknown, 'f_secdef': f_secdef, 'f_tagged': f_tagged, 'f_nocomment': f_nocomment, 'names': names,
        't_rls': t_rls, 't_norls': len(t_norls), 't_append': t_append, 't_unknown': t_unknown,
        'g_unknown': g_unknown, 'g_norole': g_norole, 'defs81': len(defs81), 'phases': len(src.order),
    }
    json.dump({'counts': counts, 'extra': extra}, open(os.path.join(OUT, '.counts.json'), 'w'))
    verify = {
        'rules': "select count(*) from public.rules",
        'functions': "select count(*) from pg_proc p where pronamespace='public'::regnamespace and prokind in ('f','p') and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')",
        'tables': "select count(*) from pg_tables where schemaname='public'",
        'grants': "select count(*) from public.grant_defs",
    }
    for k, sql in verify.items():
        n = q_json(db, sql.replace('select count(*)', 'select count(*)::int as n', 1))[0]['n']
        if n != counts[k]:
            sys.exit('COUNT MISMATCH %s: query %d, written %d' % (k, n, counts[k]))
    write_readme(db, counts, extra, kinds)
    os.remove(os.path.join(OUT, '.counts.json'))
    print(json.dumps({'counts': counts, 'extra': extra}, sort_keys=True))


# ----------------------------------------------------------------------------- routes
JS = r"""
const vm = require('vm'), fs = require('fs');
const web = process.argv[1];
const ctx = {}; ctx.window = ctx; ctx.BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (x) => x };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(web + '/i18n.js', 'utf8'), ctx);
vm.runInContext(fs.readFileSync(web + '/ia.js', 'utf8'), ctx);
const T = ctx.BOS_T || {};
const lab = (l) => { if (typeof l === 'string') { if (l.startsWith('t:')) { const e = T[l.slice(2)]; return e ? e.en : l; } return l; } if (Array.isArray(l)) return l[1]; return l && l.en || ''; };
const out = { groups: ctx.BOS.ia.GROUPS.map((g) => ({ id: g.id, en: g.label.en })), routes: ctx.BOS.IA.map((r) => ({ id: r.id, route: r.route, group: r.group, label_en: lab(r.label), ok: String(r.ok), status: r.status, drawer: !!r.drawer, alias: r.alias || '', parent: r.parent || '' })) };
process.stdout.write(JSON.stringify(out));
"""


def load_routes(rule_keys):
    r = subprocess.run(['node', '-e', JS, WEB], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('node failed while reading web/ia.js: ' + r.stderr[:600])
    data = json.loads(r.stdout)
    gl = {g['id']: g['en'] for g in data['groups']}
    # page -> script file
    pages = {}
    rx = re.compile(r'BOS_PAGES\s*=\s*Object\.assign\(\s*window\.BOS_PAGES\s*\|\|\s*\{\}\s*,\s*\{(.*?)\}\s*\)', re.S)
    rx2 = re.compile(r'BOS_PAGES\.([A-Za-z0-9_]+)\s*=')
    scripts = {}
    for fn in sorted(os.listdir(WEB)):
        if not fn.endswith('.js'):
            continue
        txt = open(os.path.join(WEB, fn), encoding='utf-8', errors='replace').read()
        scripts[fn] = txt
        for m in rx.finditer(txt):
            for part in re.split(r',(?![^()]*\))', m.group(1)):
                part = part.strip()
                if not part:
                    continue
                k = re.match(r"['\"]?([A-Za-z0-9_/]+)['\"]?\s*(?::|$)", part)
                if k:
                    pages.setdefault(k.group(1), []).append(fn)
        for m in rx2.finditer(txt):
            pages.setdefault(m.group(1), []).append(fn)
    app = scripts.get('app.js', '')
    mloc = re.search(r'const local = \{(.*?)\};', app, re.S)
    if mloc:
        for k in re.findall(r'([A-Za-z0-9_]+)\s*:', mloc.group(1)):
            pages.setdefault(k, []).append('app.js')
    owner_only = set(re.findall(r"'([a-z0-9_]+)'", (re.search(r'OWNER_ONLY\s*=\s*new Set\(\[(.*?)\]\)', app, re.S) or [None, ''])[1]))
    rg = {}
    mrg = re.search(r'ROUTE_GRANTS\s*=\s*\{(.*?)\n\};', app, re.S)
    if mrg:
        for k, v in re.findall(r"([A-Za-z0-9_]+)\s*:\s*\[(.*?)\]", mrg.group(1), re.S):
            rg[k] = re.findall(r"'([a-z0-9_]+)'", v)
    rule_rx = re.compile(r"\brule\w*\(\s*['\"]([a-z0-9_]+)['\"]")
    routes = []
    missing_script = 0
    for rec in data['routes']:
        page = rec['route'].split('/')[0]
        files = sorted(set(pages.get(page, [])))
        if not files:   # fallback: a BOS_PAGES object literal that was not matched above, entry written as "<page>: <fn>" on its own line
            pr = re.compile(r"^\s*['\"]?" + re.escape(page) + r"['\"]?\s*:\s*[A-Za-z_]", re.M)
            files = sorted(fn for fn, txt in scripts.items() if 'BOS_PAGES' in txt and pr.search(txt))
        if not files:
            missing_script += 1
        src_ok = rec['ok']
        grants = sorted(set(re.findall(r'GF\.([a-z0-9_]+)', src_ok) + re.findall(r"GF\[['\"]([a-z0-9_]+)", src_ok)))
        gate = []
        if re.fullmatch(r'\s*(?:\(\s*c?\s*\)|c)\s*=>\s*true\s*', src_ok):
            gate.append('everyone')
        if 'c.own' in src_ok:
            gate.append('owner')
        for code, act in re.findall(r"c\.P\(\s*'([A-Za-z0-9_]+)'\s*,\s*'([a-z]+)'", src_ok):
            gate.append('perm %s:%s' % (code, act))
        for g in grants:
            gate.append('grant ' + g)
        for fnm, txt in (('locOk', 'location access'), ('canPos', 'POS access'), ('anyApprove', 'any approval right'), ('ctlOk', 'control access')):
            if 'c.' + fnm + '(' in src_ok:
                gate.append(txt)
        if not gate:
            gate.append('unparsed: ' + short(src_ok, 80))
        used = set()
        for fn in files:
            for k in rule_rx.findall(scripts.get(fn, '')):
                if k in rule_keys:
                    used.add(k)
        sg = []
        if page in owner_only:
            sg.append('owner only')
            if page in rg:
                sg.append('or grant ' + '/'.join(rg[page]))
        routes.append({'id': rec['id'], 'group_label': gl.get(rec['group'], rec['group']), 'label_en': rec['label_en'], 'status': rec['status'],
                       'drawer': rec['drawer'], 'alias': rec['alias'], 'gate_text': ' + '.join(gate) if len(gate) > 1 and 'everyone' not in gate else ', '.join(gate),
                       'grants': grants, 'rules': sorted(used), 'script': ', '.join(files) if files else 'unknown (no BOS_PAGES entry found)',
                       'server_gate': ' '.join(sg) if sg else '-'})
    note = 'Script file unknown for %d routes (no `BOS_PAGES` registration found for the page name).' % missing_script
    return routes, data['groups'], note


# ----------------------------------------------------------------------------- README
def write_readme(db, counts, x, kinds):
    md = HEADER + """# Backend catalogue - how it is made and how to regenerate it

This folder is a **generated, read-only reference** of what the database and the screen registry contain after the canonical paste order (docs/PASTE_ORDER.md) including phases 99..103. English only. It holds no secrets and no personal data: the scratch database is built from the repository's SQL files only (no live data), and the one scratch identity used to call the owner-only recommendation functions lives inside a transaction that is rolled back.

| file | what it lists |
|---|---|
| RULES_CATALOGUE.md | every row of `public.rules` with default, limits, English label and hint, the phase that introduced it, and the recommended value with its reason |
| FUNCTIONS_CATALOGUE.md | every `public` function: signature, volatility, security definer, who may execute, first and last phase, `bosNN` tags, body gates, purpose |
| TABLES_CATALOGUE.md | every `public` table: columns, RLS, policies, append-only style triggers, phase |
| GRANTS_CATALOGUE.md | every `grant_defs` row with default roles, plus segregation pairs, conflicting tokens, per-role recommendations |
| ROUTES_CATALOGUE.md | every record of web/ia.js: id, group, English label, gate, rules read by its script, script file |

## Counts (verified against queries on the scratch database)

| object | count | query |
|---|---|---|
| rules | **%(rules)d** (%(kinds)s) | `select count(*) from public.rules` |
| functions (signatures) | **%(functions)d** (%(names)d distinct names) | `select count(*) from pg_proc where pronamespace='public'::regnamespace and prokind in ('f','p')` (no extension-owned objects) |
| tables | **%(tables)d** | `select count(*) from pg_tables where schemaname='public'` (%(views)d views are not catalogued) |
| grant definitions | **%(grants)d** | `select count(*) from public.grant_defs` |
| routes | **%(routes)d** | records in `BOS.IA` of web/ia.js |
| advisor rows | %(defs81)d | active rows of `setup_rec_defs81` |
| per-role grant recommendations | %(perm_reco_role)d | rows of `perm_reco_role` |

The generator re-runs these count queries after writing and stops with an error if a count differs from the number of rows it wrote (routes are counted from the node evaluation of web/ia.js).

## Things that are unknown or approximate (marked in the files)

- Rules: phase `unknown` for %(unknown_rule_phase)d, approximate (`~`) for %(approx_rule_phase)d. %(rules_with_rec)d of the rules have a recommendation; the others show `-` (no advisor row and no recommendation function mentions them).
- Rule recommendations from `guard_recommendations()`, `form_guard_recommendations()` and `production_recommendations()` are computed from data; they are shown for an empty scratch database. `permission_recommendations(uuid)` needs a real user id and is not called; the per-role table `perm_reco_role` is listed in GRANTS_CATALOGUE.md instead.
- Functions: first/last phase `unknown` for %(f_unknown)d signatures (no `CREATE FUNCTION` text found in supabase/*.sql, for example created by dynamic SQL). %(f_nocomment)d have no comment. Security definer: %(f_secdef)d. Functions with a `bosNN` tag: %(f_tagged)d. The files ALL_NEW2..ALL_NEW11c are not in the build order of final_build.sh and are therefore not searched for phases.
- "Who may execute" is the privilege state in the scratch DB, where `anon` and `authenticated` receive default privileges on new objects (the same default Supabase applies). It is not a statement about the live project's roles.
- Tables: %(t_rls)d have RLS enabled, %(t_norls)d do not (listed at the top of TABLES_CATALOGUE.md). %(t_append)d tables have a trigger recognised as append-only/immutable style (heuristic by function name and message). Phase unknown for %(t_unknown)d tables.
- Grants: phase unknown for %(g_unknown)d; %(g_norole)d grants have no default role in `perm_reco_role`.
- Routes: the gate column reports only what the `ok` predicate in web/ia.js reads. Rules read by a script are found by pattern and are not a hard gate. Phase 102 (item images) is included in the build here although docs/PASTE_ORDER.md marks it as built on another branch; it re-creates no function.

## How to regenerate

```
# 1. Postgres 16 scratch cluster on socket /tmp port 5544 (start it if it is down)
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start"

# 2. build the scratch DB in paste order (phases 8..71, 72..98, then 99, 100, 101, 102, 103) and write the five catalogues
python3 tools/gen_catalogue.py --build d3cat

# or, when the scratch DB already exists
python3 tools/gen_catalogue.py --db d3cat
```

- `--build NAME` drops and recreates database NAME through tests/sql/final_build.sh with the order from docs/PASTE_ORDER.md extended by phases 99..103 (final_build.sh's own default stops at phase98).
- Environment: `PGSOCK` (default `/tmp`), `PGPORT` (default `5544`), `PGUSER` (default `postgres`). Needs `psql`, `python3` and `node` (node only evaluates web/ia.js with stubbed globals).
- The output is deterministic: no timestamps, sorted rows. Re-run after any new phase file and commit the changed catalogue files. If a phase is added, add it to the order list in `canonical_order()` of the generator (and to docs/PASTE_ORDER.md).
- The scratch database is the only thing written to; the live database is never touched.
""" % dict(counts, kinds=', '.join('%s %d' % (k, v) for k, v in sorted(kinds.items())), **x)
    write('CATALOGUE_README.md', md)


if __name__ == '__main__':
    main()

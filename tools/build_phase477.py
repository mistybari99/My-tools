#!/usr/bin/env python3
"""Builds supabase/phase477.sql ("re-patch all") from the hook texts the packages shipped.

The hook texts are COPIED from their package files by this script, never retyped:
  docs/integration/RPT-B1_hooks.sql      (B1: 13 patches, markers bos400 / bos401 / bos402)
  tests/sql/rb3_hooks430.sql             (B3: post_purchase, marker bos430)
  tests/sql/phase303_hooks.sql           (CRM-B: notify_enqueue, notify_optin_set, marker bosCRMB)
  docs/integration/CRM-C.md section 3    (CRM-C: notify_scan, marker bosCRMC)
  supabase/phase440.sql, phase441.sql    (RPT-C1: the _c1_patch / _c1_patch_span statements, markers bos440 / bos441*)
Wave 1 (_i1_apply_hooks, phase 99) and W1-FIX (_w1x_apply_hooks, phase 143) have their own apply functions and are only called.

usage: python3 tools/build_phase477.py [--check]     (--check fails when supabase/phase477.sql is not what this script would write)
"""
import re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rd(p):
    with open(os.path.join(ROOT, p), encoding='utf8') as f:
        return f.read()


def split_sql(text):
    """Split into statements on ';' outside quotes / dollar quotes / comments. Comments that sit between statements are dropped,
    comments inside a statement are kept (they are harmless inside a plpgsql body)."""
    out, i, n, cur = [], 0, len(text), []
    while i < n:
        c = text[i]
        if c == '-' and text.startswith('--', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            if ''.join(cur).strip():
                cur.append(text[i:j])
            i = j
            continue
        if c == '/' and text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            if ''.join(cur).strip():
                cur.append(text[i:j])
            i = j
            continue
        if c == "'":
            j = i + 1
            while j < n:
                if text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            cur.append(text[i:j + 1])
            i = j + 1
            continue
        if c == '$':
            m = re.match(r'\$([A-Za-z_]*)\$', text[i:])
            if m:
                tag = m.group(0)
                j = text.find(tag, i + len(tag))
                if j < 0:
                    raise SystemExit('unterminated dollar quote ' + tag)
                cur.append(text[i:j + len(tag)])
                i = j + len(tag)
                continue
        if c == ';':
            s = ''.join(cur).strip()
            if s:
                out.append(s)
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    s = ''.join(cur).strip()
    if s:
        out.append(s)
    return out


def hook_statements(text, must):
    res = []
    for s in split_sql(text):
        if re.match(r'(?is)^select\b', s) and re.search(must, s):
            res.append(s)
    return res


MARK = re.compile(r"'(bos(?:CRM[A-Z]|[0-9]{3}[a-z]?))'")
FN = re.compile(r"'(public\.[a-z0-9_]+\([^']*\))'::regprocedure", re.I)


def meta(stmt, default_marker=None):
    fn = FN.search(stmt)
    mk = MARK.findall(stmt)
    marker = mk[-1] if mk else default_marker
    return (fn.group(1) if fn else None, marker)


def block(name, label, stmts, default_marker=None):
    lines = ["  -- %s" % label, "  n := 0;"]
    exp = []
    for s in stmts:
        body = re.sub(r'(?is)^select\b', '', s, count=1).strip()
        # a regprocedure literal is folded to an OID when the plan is built; after an old phase is pasted again the name has another OID. Resolve the name at run time instead.
        body = re.sub(r"'(public\.[A-Za-z0-9_]+\([^']*\))'::regprocedure", r"to_regprocedure('\1')", body)
        lines.append("  v := coalesce((%s), false); if v then n := n + 1; end if;" % body)
        fn, mk = meta(s, default_marker)
        if fn and mk:
            exp.append((name, fn, mk, 'patch'))
    lines.append("  res := res || jsonb_build_object('%s', n);" % name)
    return '\n'.join(lines), exp


def build():
    exp = []
    parts = []
    # B1
    b1 = hook_statements(rd('docs/integration/RPT-B1_hooks.sql'), r'_rptb1_patch')
    assert len(b1) == 13, len(b1)
    t, e = block('RPT-B1', 'RPT-B1: 13 exact-text patches (docs/integration/RPT-B1_hooks.sql), a section whose phase is not pasted is skipped', b1)
    parts.append(("to_regprocedure('public._rptb1_patch(regprocedure,text,text[])') is not null", t)); exp += e
    # B3
    b3 = hook_statements(rd('tests/sql/rb3_hooks430.sql'), r'_rb3_patch')
    assert len(b3) == 1, len(b3)
    t, e = block('RPT-B3', 'RPT-B3: post_purchase (tests/sql/rb3_hooks430.sql)', b3)
    parts.append(("to_regprocedure('public._rb3_patch(regprocedure,text[],text)') is not null and to_regprocedure('public._rb3_lot_gate(uuid)') is not null", t)); exp += e
    # CRM-B
    cb = hook_statements(rd('tests/sql/phase303_hooks.sql'), r'_crmb_patch')
    assert len(cb) == 2, len(cb)
    t, e = block('CRM-B', 'CRM-B: notify_enqueue and notify_optin_set (tests/sql/phase303_hooks.sql)', cb, 'bosCRMB')
    parts.append(("to_regprocedure('public._crmb_patch(regprocedure,text[],text)') is not null", t)); exp += e
    # CRM-C
    doc = rd('docs/integration/CRM-C.md')
    m = re.search(r"```sql\n(select public\._crmc_patch\(.*?\);)\n```", doc, re.S)
    assert m
    cc = hook_statements(m.group(1), r'_crmc_patch')
    assert len(cc) == 1
    t, e = block('CRM-C', 'CRM-C: notify_scan (docs/integration/CRM-C.md section 3)', cc, 'bosCRMC')
    parts.append(("to_regprocedure('public._crmc_patch(regprocedure,text[],text)') is not null", t)); exp += e
    # C1
    c1 = hook_statements(rd('supabase/phase440.sql'), r'_c1_patch') + hook_statements(rd('supabase/phase441.sql'), r'_c1_patch')
    c1 = [s for s in c1 if 'regprocedure' in s]
    assert len(c1) == 7, len(c1)
    t, e = block('RPT-C1', 'RPT-C1: the _c1_patch / _c1_patch_span statements of phases 440 and 441', c1)
    parts.append(("to_regprocedure('public._c1_patch(regprocedure,text,text[])') is not null", t)); exp += e
    return parts, exp


GLUE_F3 = r"""  n := 0;
  -- INTEGRATION GLUE (bos477): the f3 report ("recipe vs really issued", RPT-B1 R2) counts a RECORD of real use (RPT-B4 production_issue_actual) as a measurement,
  -- exactly like a stock movement posted after the automatic issue. Only when both RPT-B1 (marker bos401) and RPT-B4 (table production_issue_actual) are in.
  if to_regclass('public.production_issue_actual') is not null and to_regprocedure('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)') is not null
     and position('bos401' in pg_get_functiondef(to_regprocedure('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'))) > 0 then
    v := public._i2_patch(to_regprocedure('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'), 'bos477', array[
      $a$  act as (
    select n.run_id, n.ing, -sum(l.qty_delta) as used, bool_or($a$,
      $a$  act as (
   select z.run_id, z.ing, z.used, z.extra from (
    select n.run_id, n.ing, -sum(l.qty_delta) as used, bool_or($a$,
      $a$     group by n.run_id, n.ing),
  g as ($a$,
      $a$     group by n.run_id, n.ing) z
    where not exists (select 1 from public.production_issue_actual pa where pa.run_id = z.run_id and pa.item_id = z.ing and pa.status = 'active')   /* bos477: a record of real use (RPT-B4) replaces the automatic issue */
   union all
   select n.run_id, n.ing, pa.actual_qty, true from need n join public.production_issue_actual pa on pa.run_id = n.run_id and pa.item_id = n.ing and pa.status = 'active'),
  g as ($a$]);
    if v then n := n + 1; end if;
  end if;
  -- (bos477c) ONE privacy switch is enough: CRM-A hides phone numbers on its screens when crm_mask_phone is ON, CRM-B when crm_pii_guard_on is ON. Either switch now masks both (otherwise the owner
  -- who switched on the CRM-B guard would still see full numbers on the Customer 360 page). Both OFF = nothing hidden, as before.
  if to_regprocedure('public._crma_mask_on()') is not null then
    v := public._i2_patch(to_regprocedure('public._crma_mask_on()'), 'bos477c', array[$a$select public.rule_on('crm_mask_phone');$a$, $a$select public.rule_on('crm_mask_phone') or public.rule_on('crm_pii_guard_on'); /* bos477c */$a$]);
    if v then n := n + 1; end if;
  end if;
  if to_regprocedure('public._crma_show_phone()') is not null then
    v := public._i2_patch(to_regprocedure('public._crma_show_phone()'), 'bos477c', array[$a$select not public.rule_on('crm_mask_phone') or public._crma_contact_ok();$a$, $a$select not (public.rule_on('crm_mask_phone') or public.rule_on('crm_pii_guard_on')) /* bos477c */ or public._crma_contact_ok();$a$]);
    if v then n := n + 1; end if;
  end if;
  -- (bos477b) re-pasting phase 60 brings the old 4-argument qc_list back next to the 6-argument one of phase 432 (a call by name becomes ambiguous): drop it again, as phase 432 does
  if to_regprocedure('public.qc_list(integer,date,date,text,uuid,uuid)') is not null and to_regprocedure('public.qc_list(integer,date,date,text)') is not null then
    drop function public.qc_list(integer, date, date, text); n := n + 1;
  end if;"""


def main():
    parts, exp = build()
    exp.append(('INTEGRATION', 'public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)', 'bos477', 'patch'))
    exp.append(('CRM-A', 'public._crma_mask_on()', 'bos477c', 'patch'))
    exp.append(('CRM-A', 'public._crma_show_phone()', 'bos477c', 'patch'))
    # whole-function re-creations (a re-paste of an old phase removes them; they are NOT patched here, the named phase is pasted again)
    repaste = [
        ('RPT-B2', 'public.report_run2(text,jsonb,text,text,integer)', 'bos420', 'repaste phase420'),
        ('RPT-B2', 'public.stock_reconcile(boolean)', 'bos420', 'repaste phase420'),
        ('RPT-B2', 'public._r3q_p4_supplier_score(date,date,integer[],jsonb)', 'bos420', 'repaste phase420'),
        ('RPT-B2', 'public._r3q_k2_count_variance(date,date,integer[],jsonb)', 'bos421', 'repaste phase421'),
        ('RPT-C1', 'public._r3q_x4_compliance(date,date,integer[],jsonb)', 'bos441', 'repaste phase441'),
        ('RPT-B3', 'public._r3q_p2_rate_trend(date,date,integer[],jsonb)', 'sum(r.qty * r.rate) as value', 'repaste phase434'),
    ]
    L = []
    A = L.append
    A("""-- Phase 477: RE-PATCH ALL + integration glue (integrator). Paste LAST (after phase 476). Paste-twice safe. No old phase file is edited.
-- WHAT IT IS: ONE function, public._i2_apply_all(), that puts back every exact-text hook of every package, in this order:
--   1. Wave 1            public._i1_apply_hooks()        (phase 99: 37 hooks)
--   2. W1-FIX            public._w1x_apply_hooks()       (phase 143: 4 hooks)
--   3. RPT-B1            13 patches                      (copied from docs/integration/RPT-B1_hooks.sql)
--   4. RPT-B3            post_purchase                   (copied from tests/sql/rb3_hooks430.sql)
--   5. CRM-B             notify_enqueue, notify_optin_set (copied from tests/sql/phase303_hooks.sql)
--   6. CRM-C             notify_scan                     (copied from docs/integration/CRM-C.md)
--   7. RPT-C1            report_run3, l1, l3, rfm, lapsed, report_run2_core (copied from phases 440 and 441)
--   8. glue (bos477)     f3 "recipe vs really issued" also counts a RPT-B4 record of real use as a measurement
--   plus the Exceptions list: public._i2_exc_kinds_apply() merges the kinds of every package (R1, CRM-G, Wave 1) into the live constraint.
-- WHEN: after you paste ANY older phase file again (phases 3 to 99 re-create functions and remove the hooks), run:   select public._i2_apply_all();
--       (pasting this file again does the same). Then check:  select * from public._i2_state() where not present;   -> must be empty.
-- A package that is not installed is skipped (its helper function is missing). A patch site that is missing STOPS the whole call with the function name; nothing is half patched.
-- The functions that a package RE-CREATES as a whole (not patched) cannot be put back by a patch: _i2_state() lists them with how = 'repaste phaseNNN' (paste that phase again).
-- Generated by tools/build_phase477.py from the package files. Do not edit by hand.
do $g$ begin
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase477 needs phase99 (and the phases before it) pasted first'; end if;
end $g$;

create or replace function public._i2_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos477[a-z]?$' then raise exception 'phase477: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / length(p_pairs[i]);
    if n = 0 then raise exception 'phase477: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'phase477: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'phase477: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

create or replace function public._i2_apply_all() returns jsonb language plpgsql security definer set search_path = public as $i2$
declare res jsonb := '{}'::jsonb; n int; v boolean; r jsonb;
begin
  if not (auth.uid() is null or public.is_owner() or current_user in ('postgres', 'supabase_admin')) then raise exception 'not allowed'; end if;
  -- 1 and 2: the packages that have their own apply function
  r := public._i1_apply_hooks(); res := res || jsonb_build_object('Wave1', (select count(*) from jsonb_each(r) e where e.value = 'true'::jsonb));
  if to_regprocedure('public._w1x_apply_hooks()') is not null then
    r := public._w1x_apply_hooks(); res := res || jsonb_build_object('W1-FIX', (select count(*) from jsonb_each(r) e where e.value = 'true'::jsonb));
  end if;""")
    for cond, text in parts:
        A("  if %s then" % cond)
        A(text.replace('\n', '\n  ').replace('  -- ', '  -- ', 1))
        A("  end if;")
    A(GLUE_F3)
    A("""  res := res || jsonb_build_object('INTEGRATION', n);
  perform public._i2_exc_kinds_apply();
  return res;
end $i2$;""")
    # expectations
    A("""
create or replace function public._i2_expect() returns table(pkg text, fn text, marker text, how text) language sql immutable as $$
  select * from (values""")
    rows = exp + repaste
    A(",\n".join("    (%s, %s, %s, %s)" % tuple("'" + x.replace("'", "''") + "'" for x in r) for r in rows))
    A("""  ) v(pkg, fn, marker, how);
$$;
-- which expected hooks are in. A package that is not installed is not listed (its helper function is missing).
create or replace function public._i2_state() returns table(pkg text, fn text, marker text, how text, present boolean) language plpgsql stable security definer set search_path = public as $$
begin
  return query
  select e.pkg, e.fn, e.marker, e.how,
         position(e.marker in pg_get_functiondef(e.fn::regprocedure)) > 0
    from public._i2_expect() e
   where to_regprocedure(e.fn) is not null
     and exists (select 1 from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = case e.pkg
           when 'RPT-B1' then '_rptb1_patch' when 'RPT-B3' then '_rb3_lot_gate' when 'CRM-B' then '_crmb_patch' when 'CRM-C' then '_crmc_patch'
           when 'RPT-C1' then '_c1_patch' when 'RPT-B2' then '_r4_lockdown' when 'INTEGRATION' then '_rptb1_patch' when 'CRM-A' then '_crma_mask_on' end)
     and (e.pkg <> 'INTEGRATION' or to_regclass('public.production_issue_actual') is not null)
   order by e.pkg, e.fn, e.marker;
end $$;

-- ---------- Exceptions list: the kinds of every package in ONE merge (phase 99 has the Wave 1 list, phase 120 adds one, phase 323 three) ----------
create or replace function public._i2_exc_kinds() returns text[] language sql immutable as $$
  select array(select unnest(public._i1_exc_kinds() || array['r1_unbacked_payment', 'crmg_late_quote', 'crmg_lead_reopen', 'crmg_win_without_quote']) k group by k order by k);
$$;
create or replace function public._i2_exc_kinds_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare con text; def text; cur text[]; want text[];
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase477: the money_exceptions kind check was not found (phase87 missing?)'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\\{([^}]*)\\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase477: the money_exceptions kind check has an unknown shape: %', left(def, 120); end if;
  select array_agg(x order by x) into want from (select unnest(cur) x union select unnest(public._i2_exc_kinds())) z;
  if cur @> want and position('ARRAY[' in def) > 0 then return jsonb_build_object('changed', false, 'kinds', cardinality(want)); end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
  return jsonb_build_object('changed', true, 'kinds', cardinality(want));
end $$;

revoke all on function public._i2_patch(regprocedure, text, text[]), public._i2_apply_all(), public._i2_expect(), public._i2_state(), public._i2_exc_kinds(), public._i2_exc_kinds_apply() from public, anon, authenticated;

select public._i2_apply_all();
select pkg, fn, marker, how from public._i2_state() where not present;      -- must print no rows""")
    return '\n'.join(L) + '\n'


if __name__ == '__main__':
    out = main()
    path = os.path.join(ROOT, 'supabase', 'phase477.sql')
    if '--check' in sys.argv:
        cur = open(path, encoding='utf8').read() if os.path.exists(path) else ''
        if cur != out:
            print('phase477.sql is out of date: run python3 tools/build_phase477.py')
            sys.exit(1)
        print('OK phase477.sql is up to date')
    else:
        with open(path, 'w', encoding='utf8') as f:
            f.write(out)
        print('wrote', path, len(out), 'bytes')

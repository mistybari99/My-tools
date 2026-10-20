-- Phase 535 (UNION-7: the advanced line's logic in 43 shared functions (_acct_all ... bank_recon_match_many) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
-- What: the advanced line changed these functions after phase 79 (rules, scope, audit, templates, cost, ...). Pasting the early phases (8 to 79) again, as the owner's earlier paste of
--   our line did, puts their older text back and the advanced logic is silently gone. A database that was built by pasting the advanced phases and then ONE run of our phases
--   never loses it (this is how the fresh build is ordered), so on a fresh build this file does nothing.
-- What this file does: for every function listed, if its text is a KNOWN older text (the base text of phases 8-79, or the text of the earlier live paste, recognised by md5), it is replaced by the merged
--   text (the advanced text, our line did not change these functions); the old text is saved in public._union_fn_backup first. An unknown text is never overwritten: all such functions are
--   listed in one message and nothing is changed. Nothing here adds a switch or changes a default.
-- Paste AFTER phase534 and after phase 505. Safe to paste twice.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _acct_all()
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_all()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_all()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public._org_on123()
    then (public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')))   -- OFF: phase40
    else (public.is_active() and public.is_owner()) end;                                          -- ON (scope123): owner only
$function$$r0_0$, null),
  ('public._acct_all()', 'known', '94425e97bfc176a99d2a30d27eebd421', null);
-- _acct_inv_split72(text[],text,text[],integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_inv_split72(text[],text,text[],integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_inv_split72(p_ref_types text[], p_ref_id text, p_reasons text[], p_sign integer)
 RETURNS TABLE(t text, amt numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with g as (
    select it.item_type as ty, sum(p_sign * l.qty_delta * l.unit_cost) as raw
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id /* bos96 */
    where l.ref_type = any (p_ref_types) and l.ref_id = p_ref_id and l.reason = any (p_reasons) and l.unit_cost is not null group by it.item_type),
  r as (select ty, round(raw, 2) as a, row_number() over (order by round(raw, 2) desc, ty nulls last) as rn from g),
  d as (select round((select sum(raw) from g), 2) - (select sum(a) from r) as rest)
  select r.ty, r.a + case when r.rn = 1 then (select rest from d) else 0 end from r;
$function$$r0_0$, null),
  ('public._acct_inv_split72(text[],text,text[],integer)', 'known', 'fb2f5b8895308fc29d6f84d6994d80f9', null);
-- _all_locs()
insert into _u_plan (fn, kind, a, b) values
  ('public._all_locs()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._all_locs()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active() and (case when not public._org_on123()
    then (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'))   -- OFF: phase10
    else public.is_owner() end);                                                                                                  -- ON (scope123): owner only
$function$$r0_0$, null),
  ('public._all_locs()', 'known', '9c7db09ef458d68c1ed20fcca6ea91f9', null);
-- _backup_tables()
insert into _u_plan (fn, kind, a, b) values
  ('public._backup_tables()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._backup_tables()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$function$$r0_0$, null),
  ('public._backup_tables()', 'known', 'cc54ed6c9dc11587384e9a9ff260ebf3', null);
-- _c78_rows(date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._c78_rows(date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._c78_rows(p_from date, p_to date)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: same rows as before; rule cost_share_prorate_mode = on takes a monthly share pro rata for the days of the range (default off = the whole month, as before)
  select * from public._c78_rows112(p_from, p_to, coalesce(public.rule_txt('cost_share_prorate_mode'), 'off') = 'on');
$function$$r0_0$, null),
  ('public._c78_rows(date,date)', 'known', 'f286d1e20c5dd0730f626d2df68136e7', null);
-- _cogs_lines72(date,date,integer[])
insert into _u_plan (fn, kind, a, b) values
  ('public._cogs_lines72(date,date,integer[])', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase506 (free-cost item) and phase514 (one report cost switch)
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as materialized (select public._rcs88() as m),   -- bos110: evaluated once (it was inlined into every use = once per row); bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
  cst as (select i.id as iid, coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) as cost_price   -- bos80: a free-cost item without a list cost counts as cost 0
          from public.items i left join public.item_costs ic on ic.item_id = i.id
          where i.count_in_business and coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) is not null),
  docs as (
    select 'sale'::text as src, x.id as doc, x.sale_date as d, x.location_id as loc, (case when x.subtotal > 0 then x.total / x.subtotal else 1 end) as f, x.lines
    from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)
    union all
    select 'return'::text, r.id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, (case when la.s > 0 then r.amount / la.s else 1 end), r.lines
    from public.sale_returns r cross join net_on
    cross join lateral (select coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end), 0) as s
                        from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e) la
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  ln as (
    select docs.src, docs.doc,
           coalesce(case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end, '00000000-0000-0000-0000-000000000000'::uuid) as k,
           coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end * docs.f), 0) as rev,
           coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as qty
    from docs cross join lateral jsonb_array_elements(case when jsonb_typeof(docs.lines) = 'array' then docs.lines else '[]'::jsonb end) e group by 1, 2, 3),
  led as (
    select docs.src, docs.doc, l.item_id as k,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * coalesce(l.unit_cost, 0)) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lc,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lq,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0 and not public._cost_free80(l.item_id)) as uq   -- bos80
    from public.stock_ledger l
    join docs on l.ref_id = docs.doc::text
             and ((docs.src = 'sale' and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out'))
               or (docs.src = 'return' and l.ref_type = 'sale_return' and l.reason = 'sale_return'))
    group by 1, 2, 3),
  keys as (select src, doc, k from ln union select src, doc, k from led),
  j as (
    select docs.src, docs.doc, docs.d, docs.loc, keys.k, coalesce(ln.qty, 0) as jq, coalesce(ln.rev, 0) as rev,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.lc, 0) end as lc, case when rcs.m = 'item_costs' then 0 else coalesce(led.lq, 0) end as lq,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.uq, 0) end as uq, ((led.lq is not null or led.uq is not null) and rcs.m <> 'item_costs') as hl,
           (case when rcs.m = 'ledger_avg' then null else c.cost_price end) as cost_price, rcs.m as m   -- bos88
    from keys join docs on docs.src = keys.src and docs.doc = keys.doc cross join rcs
    left join ln on ln.src = keys.src and ln.doc = keys.doc and ln.k = keys.k
    left join led on led.src = keys.src and led.doc = keys.doc and led.k = keys.k
    left join cst c on c.iid = keys.k),
  q as (select j.*, (case when hl then uq else jq end) as unk_q, (case when hl then lq + uq else jq end) as tot_q from j),
  w as (select q.*, (case when tot_q > 0 then rev * lq / tot_q else 0 end) as lrev from q)
  select w.src, w.doc, w.d, w.loc, nullif(w.k, '00000000-0000-0000-0000-000000000000'::uuid), w.jq, w.rev,
         w.lc + (case when w.m = 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),   -- bos88: item_costs mode = item_costs IS the primary source (no fallback flag)
         w.lrev + (case when w.m = 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.cost_price is null then w.rev - w.lrev else 0 end)
  from w;
$function$$r0_0$, null),
  ('public._cogs_lines72(date,date,integer[])', 'known', 'aebb3a5c12140996670db8c7a1a5c332', null);
-- _conv_cost(uuid,integer,numeric,numeric,date,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._conv_cost(p_recipe uuid, p_loc integer, p_batches numeric, p_out numeric, p_date date, p_force_mode text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare md text; c record; ty record; det jsonb := '[]'::jsonb; tot numeric := 0; complete boolean := true; amt numeric; norm numeric; m date := public._m1(p_date); any_pool boolean := false; ncomp int := 0; why text := null; a numeric; pr jsonb;
        drv boolean := public.rule_on('pool_drivers116'); cfg public.location_cost_cfg; dn text; nd numeric; qd numeric; hrs numeric; prov boolean := false; use_prov boolean := false; pj jsonb; base_u text;   -- bos116
begin
  md := coalesce(p_force_mode, (select mode from public.location_cost_cfg where location_id = p_loc), 'off');
  if md = 'off' then return jsonb_build_object('mode', 'off', 'amount', 0, 'complete', true, 'detail', '[]'::jsonb, 'reason', null); end if;
  if md = 'recipe' then
    for c in select * from public.recipe_cost_components where recipe_id = p_recipe and active order by component_type, id loop
      ncomp := ncomp + 1; amt := null;
      if c.amount is null then complete := false;
      elsif c.basis = 'per_batch' then amt := c.amount * p_batches;
      elsif c.basis = 'per_unit' then amt := c.amount * p_out;
      elsif c.hours_per_batch is null then complete := false;
      else amt := c.amount * c.hours_per_batch * p_batches; end if;
      if amt is not null then tot := tot + amt; end if;
      det := det || jsonb_build_object('type', c.component_type, 'note', c.type_note, 'basis', c.basis, 'amount', case when amt is null then null else round(amt, 6) end, 'incomplete', amt is null);
    end loop;
    if ncomp = 0 then complete := false; why := 'no_components'; end if;
  else
    select * into cfg from public.location_cost_cfg where location_id = p_loc;      -- bos116
    norm := cfg.normal_monthly_output;
    -- bos116: provisional only when the run month has NO pool row at all (nothing typed yet) and the owner switched it on; reprice sets bos.no_prov116 to see the real pool only
    use_prov := public.rule_on('conv_provisional116') and coalesce(current_setting('bos.no_prov116', true), '') <> 'on'
                and not exists (select 1 from public.factory_cost_pools f where f.active and f.location_id = p_loc and f.month = m);
    base_u := lower(coalesce((select public._item_base(r.item_id) from public.recipes r where r.id = p_recipe), ''));
    if not drv then
      if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg';      -- the pool rate is per kg of output: a piece-based product needs recipe rates (or pool_drivers116)
      elsif norm is null or norm <= 0 then complete := false; why := 'normal_output_blank';
      else
        for ty in select code from public.cost_component_types where active order by code loop
          pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
          if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;      -- bos116
          if a is not null then any_pool := true; amt := a / norm * p_out; tot := tot + amt;
            if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
            det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'rate', round(a / norm, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
              || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end; end if;
        end loop;
        if not any_pool then complete := false; why := 'no_pool'; end if;
      end if;
    else
      -- bos116: driver per cost type (type override, else the place default, else output kg = today)
      for ty in select code, driver116 from public.cost_component_types where active order by code loop
        pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
        if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;
        if a is null then continue; end if;
        dn := coalesce(ty.driver116, cfg.driver116, 'output_kg'); nd := null; qd := null;
        if dn = 'output_kg' then
          nd := norm; qd := p_out;
          if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg'; continue; end if;
        elsif dn = 'output_units' then nd := cfg.normal_units116; qd := p_out;
        elsif dn = 'batches' then nd := cfg.normal_batches116; qd := p_batches;
        else
          nd := cfg.normal_labour_hours116;
          select sum(c2.hours_per_batch) into hrs from public.recipe_cost_components c2 where c2.recipe_id = p_recipe and c2.active and c2.basis = 'per_labour_hour' and c2.hours_per_batch is not null;
          qd := hrs * p_batches;
        end if;
        if nd is null or nd <= 0 then complete := false; why := 'normal_' || dn || '_blank'; continue; end if;
        if qd is null then complete := false; why := 'no_labour_hours'; continue; end if;
        any_pool := true; amt := a / nd * qd; tot := tot + amt;
        if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
        det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'driver', dn, 'rate', round(a / nd, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
          || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end;
      end loop;
      if not any_pool and why is null then complete := false; why := 'no_pool'; end if;
    end if;
  end if;
  return jsonb_build_object('mode', md, 'amount', tot, 'complete', complete, 'detail', det, 'reason', why) || case when prov then jsonb_build_object('provisional', true) else '{}'::jsonb end;      -- bos116
end $function$$r0_0$, null),
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'known', 'e37bc4d962076d534a57a048fc879947', null);
-- _cs_push_pools(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public._cs_push_pools(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cs_push_pools(p_bill bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.cost_source_bills; ct text; sh record;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  update public.factory_cost_pools set active = false where source = 'allocated' and ref like 'bill:' || p_bill::text || ':%' and active;
  if b.status <> 'active' then perform public._pool_gl_after_bill117(p_bill); return; end if;      -- bos117
  select t.component_type into ct from public.cost_sources s join public.cost_source_types t on t.code = s.cost_type where s.id = b.source_id;
  for sh in select location_id, sum(amount) amt from public.cost_bill_shares where bill_id = p_bill and active and kind = 'share' and dest = 'factory' group by location_id loop
    if sh.amt > 0 then
      insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, ref, note, created_by)
        values (sh.location_id, b.period_month, coalesce(ct, 'other'), b.period_kind, sh.amt, b.one_off, 'allocated', 'bill:' || p_bill::text || ':' || sh.location_id::text, 'from cost bill ' || p_bill::text, auth.uid());
    end if;
  end loop;
  perform public._pool_gl_after_bill117(p_bill);      -- bos117: pool rows of this bill (new and retired) are mirrored in the books (switch pool_gl_post117)
end $function$$r0_0$, null),
  ('public._cs_push_pools(bigint)', 'known', 'de725d03d263c625b7ab4d9f1c38071f', null);
-- _elp_post_line(entries,integer,text,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._elp_post_line(entries,integer,text,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
        fmode text; rc public.recipes; nr record; tot numeric := 0; cok boolean := true; av numeric; yf numeric;   -- bos83
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
    -- bos83: the slip has no screen record yet: a PENDING link (form -> screen record owed) so unmatched_forms() can list it
    begin perform public.shadow_link_add(public._entry_domain(e.form_code), e.location_id, 'entries', e.id::text, 'stock_screen', null, 'form ' || e.form_code || ' skipped: the screen is the record, screen record owed'); exception when others then null; end;
    return;
  end if;
  -- bos83: owner switch form_051_mode = refuse: the factory daily sheet is not a posting source at all (kept as a reference, line shown as skipped)
  fmode := coalesce(public.rule_txt('form_051_mode'), 'reference');
  if l->>'skip' is null and kind = 'prod' and e.form_code = '05-1' and fmode = 'refuse' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'form051_not_a_source', ref, auth.uid());
    return;
  end if;
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item' and public._m132_at(org_unit_id, e.location_id) /* m132 */;
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    ucb := null;
    if e.form_code = '05-1' and fmode = 'post' then      -- bos83: the finished goods are made FROM the recipe's ingredients, taken out at the average cost
      select r.* into rc from public.recipes r where r.item_id = it.id and r.active and exists (select 1 from public.recipe_lines x where x.recipe_id = r.id and x.active) order by r.version desc limit 1;
      if not found then raise exception 'no_recipe_for_051: %', it.code; end if;
      perform public._recipe_gate73(rc.id);
      yf := public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit);
      if yf is null or not (yf > 0) then raise exception 'unit_unknown: %', it.code; end if;
      for nr in select * from public._recipe_need(rc.id, bq / yf, e.location_id) order by item_id loop
        if not nr.tracked then raise exception 'ingredient_not_tracked: %', coalesce(nr.code, ''); end if;
        if not nr.unit_ok then raise exception 'unit_unknown: %', coalesce(nr.code, ''); end if;
        if nr.need < 0.0001 then continue; end if;
        select b.avg_cost into av from public.stock_balance b where b.item_id = nr.item_id and b.location_id = e.location_id;
        if av is null then cok := false; else tot := tot + nr.need * av; end if;
        perform public.stock_post(nr.item_id, e.location_id, -nr.need, 'issue_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
      end loop;
      ucb := case when cok and bq > 0 then round(tot / bq, 6) end;
    end if;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, ucb, bid, at_, left(note, 200), null, 'none');
    if ucb is null and e.form_code = '05-1' and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'form051_cost_null' and x.status = 'open') then      -- bos83
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (e.id, e.form_code, e.location_id, e.entry_date, 'form051_cost_null', 'yellow', null,
          jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || it.name_bn || ' তৈরি মাল cost ছাড়া stock-এ ঢুকেছে (cost অজানা)',
                             'en', e.form_code || '-' || e.serial || ': ' || coalesce(it.name_en, it.name_bn) || ' entered stock with NO cost (cost unknown)'));
    end if;
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $function$$r0_0$, null),
  ('public._elp_post_line(entries,integer,text,jsonb)', 'known', '8f1b730dc2d6f74e13d818010222e5a1', null);
-- _entries_countseal_guard23()
insert into _u_plan (fn, kind, a, b) values
  ('public._entries_countseal_guard23()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._entries_countseal_guard23()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; cf text; s record; r jsonb; n int; arr jsonb := '[]'::jsonb; it public.items; iid uuid; f numeric; bk numeric;
begin
  if new.form_code not in ('04-1', '04-3') or not public.stock_blind_active(new.form_code, new.location_id) then return new; end if;
  k := case new.form_code when '04-3' then 'rows' else 'lines' end; cf := case new.form_code when '04-3' then 'count' else 'counted' end;
  if tg_op = 'UPDATE' then
    for s in select * from public.entry_count_seals where entry_id = new.id loop
      r := case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k -> (s.line_no - 1) end;
      if r is null or btrim(coalesce(r ->> 'item', '')) <> s.item_code or public._n18(r, cf) <> s.counted then raise exception 'count_locked'; end if;
    end loop;
    if old.status = 'draft' and new.status <> 'draft' then
      for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
        if nullif(btrim(r ->> 'item'), '') is not null and not exists (select 1 from public.entry_count_seals where entry_id = new.id and line_no = n) then raise exception 'count_not_sealed'; end if;
      end loop;
    end if;
  end if;
  if new.form_code = '04-3' and jsonb_typeof(new.data -> k) = 'array' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(new.data -> k) with ordinality x(v, o) loop
      r := case when jsonb_typeof(r) = 'object' then r - 'book' else r end;
      if tg_op = 'UPDATE' and new.status <> 'draft' and jsonb_typeof(r) = 'object' then
        select sl.book_base, i.id into bk, iid from public.entry_count_seals sl left join public.items i on i.code = sl.item_code and public._m132_at(i.org_unit_id, new.location_id) /* m132 */ where sl.entry_id = new.id and sl.line_no = n;
        if found and bk is not null then
          select * into it from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
          f := public._unit_factor_base(it.id, it.unit);
          if f is not null and f > 0 then r := r || jsonb_build_object('book', round(bk / f, 4)::text); end if;
        end if;
      end if;
      arr := arr || jsonb_build_array(r);
    end loop;
    new.data := jsonb_set(new.data, array[k], arr);
  end if;
  return new;
end $function$$r0_0$, null),
  ('public._entries_countseal_guard23()', 'known', '68e035fbee29c9f868eb8f5b9a2b905a', null);
-- _inb_insert_message(jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._inb_insert_message(jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._inb_insert_message(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch public.sales_channels; m public.inbound_messages; n int;
begin
  select * into ch from public.sales_channels where kind = p->>'kind' and account_ref = p->>'account_ref' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  -- bos94: optional per-channel limit of stored messages per minute (rule inbox_rate_max_per_min; empty = no limit = as before). The caller queues the message for a later retry.
  if public.rule_num('inbox_rate_max_per_min') is not null and public.rule_num('inbox_rate_max_per_min') > 0
     and (select count(*) from public.inbound_messages where channel_id = ch.id and received_at > now() - interval '1 minute') >= public.rule_num('inbox_rate_max_per_min') then raise exception 'rate_limited'; end if;   -- bos94
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, attachment_ref)
    values (ch.id, ch.location_id, p->>'external_id', left(p->>'handle', 120), left(p->>'name', 120), left(p->>'text', 4000),
            nullif(p->>'msg_time', '')::timestamptz, left(p->>'attachment', 500))
    on conflict (channel_id, external_id) do nothing returning * into m;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, null, 'new', 'received', auth.uid());
  return jsonb_build_object('duplicate', false, 'id', m.id);
end $function$$r0_0$, null),
  ('public._inb_insert_message(jsonb)', 'known', '8f89c4b249bc129e6a749a0f1332b9a5', null);
-- _inb_pii_cols76()
insert into _u_plan (fn, kind, a, b) values
  ('public._inb_pii_cols76()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._inb_pii_cols76()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cols text;
begin
  if new.key = 'inbox_pii_guard_on' then
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      revoke select (customer_mobile, address, note, draft_note, lines) on public.online_orders from authenticated;   -- bos105: note, draft_note, lines too
    else
      grant select (customer_mobile, address, note, draft_note, lines) on public.online_orders to authenticated;   -- bos105
    end if;
  elsif new.key = 'customers_pii_guard_on' then   -- bos105
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into cols from pg_attribute a
       where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped and a.attname not in ('mobile', 'whatsapp', 'address', 'note');
      revoke select on public.customers from authenticated;
      execute 'grant select (' || cols || ') on public.customers to authenticated';
    else
      grant select on public.customers to authenticated;
    end if;
  end if;
  return new;
end $function$$r0_0$, null),
  ('public._inb_pii_cols76()', 'known', '9115169f930182c0e432c80a0c91de86', null);
-- _intake_fail(text,integer,text,text,jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._intake_fail(text,integer,text,text,jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._intake_fail(p_kind text, p_channel integer, p_ext text, p_err text, p_payload jsonb, p_state text DEFAULT 'failed'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_ bigint; cap94 numeric := public.rule_num('intake_reject_max_per_min');
begin
  -- bos94: a flood of forged calls must not fill the table: over the owner's per-minute limit a rejected line is counted by nobody and stored by nobody (empty rule = no limit = as before)
  if p_state = 'rejected' and cap94 is not null and cap94 > 0
     and (select count(*) from public.intake_failures where state = 'rejected' and created_at > now() - interval '1 minute') >= cap94 then return 0; end if;   -- bos94
  insert into public.intake_failures (kind, channel_id, external_id, error, payload, state, next_try_at)
    values (p_kind, p_channel, left(p_ext, 200), left(p_err, 500), p_payload, p_state,
            case when p_state = 'failed' then now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int)) end)
    returning id into id_;
  return id_;
end $function$$r0_0$, null),
  ('public._intake_fail(text,integer,text,text,jsonb,text)', 'known', '292695e1e05729b885381982772ade6b', null);
-- _item_base(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_base(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_base(p_item uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(nullif(btrim(base_unit), ''), nullif(btrim(unit), '')) from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
$function$$r0_0$, null),
  ('public._item_base(uuid)', 'known', '33fbf5dfa0af34aee227e0a9ec76e6d5', null);
-- _item_flags_apply(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_flags_apply(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_flags_apply(p_item uuid, p_patch jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; f record; ty text;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found then raise exception 'item_not_found'; end if;
  if p_patch ? 'item_type' and nullif(p_patch->>'item_type', '') is not null and (p_patch->>'item_type') is distinct from it.item_type then
    ty := p_patch->>'item_type';
    if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
    select * into f from public._item_type_flags(ty);
    -- a changed type starts from the defaults of the new type, unless the same request also says the flags itself
    update public.items set item_type = ty,
      count_in_business = case when p_patch ? 'count_in_business' then (p_patch->>'count_in_business')::boolean else f.o_count end,
      sellable = case when p_patch ? 'sellable' then (p_patch->>'sellable')::boolean else f.o_sell end where id = p_item;
  else
    if p_patch ? 'count_in_business' then update public.items set count_in_business = (p_patch->>'count_in_business')::boolean where id = p_item; end if;
    if p_patch ? 'sellable' then update public.items set sellable = (p_patch->>'sellable')::boolean where id = p_item; end if;
  end if;
  if p_patch ? 'control_class' then update public.items set control_class = nullif(btrim(p_patch->>'control_class'), '') where id = p_item; end if;
  if p_patch ? 'hidden' then update public.items set hidden = (p_patch->>'hidden')::boolean where id = p_item; end if;
  if p_patch ? 'master_code' then update public.items set master_code = nullif(btrim(p_patch->>'master_code'), '') where id = p_item; end if;
  if p_patch ? 'is_active' then
    if (p_patch->>'is_active')::boolean then update public.items set retired_at = null, retired_reason = null where id = p_item and retired_at is not null;
    else update public.items set retired_at = coalesce(retired_at, now()), retired_reason = coalesce(left(nullif(btrim(p_patch->>'retired_reason'), ''), 200), retired_reason) where id = p_item;
    end if;
  end if;
  if p_patch ? 'locked' then
    if not (public.is_owner() or coalesce(current_setting('bos.item_sys', true), '') = '1') then raise exception 'not allowed'; end if;      -- only the owner locks / unlocks
    update public.items set locked = (p_patch->>'locked')::boolean where id = p_item;
  end if;      -- last: the lock never blocks the changes of the same request
end $function$$r0_0$, null),
  ('public._item_flags_apply(uuid,jsonb)', 'known', '3a55d5efd8bcd78644f084ed31d0bd02', null);
-- _item_link(uuid,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_link(uuid,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_link(p_item uuid, p_dict text, p_via text, p_force boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tid uuid; cls text;
begin
  select id, control_class into tid, cls from public.items where code = p_dict and import_batch is not null;
  if tid is null then raise exception 'master_code_not_found'; end if;
  if tid = p_item then raise exception 'bad_request'; end if;
  -- an old (sold) item stands for a sellable product; linking it to a material / asset / tool code needs the owner's explicit yes
  if not coalesce(p_force, false) and exists (select 1 from public.items where id = tid and public._m132_own(items.org_unit_id) /* m132b:items */ and item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled')) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = p_dict and active and item_id <> p_item) then raise exception 'master_code_taken'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active and dict_code <> p_dict;
  insert into public.item_master_links (item_id, dict_code, via, linked_by) select p_item, p_dict, p_via, auth.uid()
    where not exists (select 1 from public.item_master_links where item_id = p_item and dict_code = p_dict and active);
  update public.items set master_code = p_dict, control_class = coalesce(control_class, cls) where id = p_item;
  update public.items set hidden = true, sellable = false where id = tid;           -- the old item stands for it: no second copy in the pickers
  perform set_config('bos.item_sys', '', true);
end $function$$r0_0$, null),
  ('public._item_link(uuid,text,text,boolean)', 'known', '13b709ad1be3b6724b31e9486e0cb6c5', null);
-- _item_master_classify(jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_master_classify(jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_master_classify(p_rows jsonb)
 RETURNS TABLE(ord integer, code text, cat_no text, category text, name_en text, name_bn text, subcategory text, unit text, control_class text, note text, item_type text, unit_code text, retired boolean, status text, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with r as (
    select e.ord::int ord, btrim(coalesce(e.v->>'code', '')) code, btrim(coalesce(e.v->>'cat_no', '')) cat_no, btrim(coalesce(e.v->>'category', '')) category,
           btrim(coalesce(e.v->>'name_en', '')) name_en, btrim(coalesce(e.v->>'name_bn', '')) name_bn, btrim(coalesce(e.v->>'subcategory', '')) subcategory,
           btrim(coalesce(e.v->>'unit', '')) unit, btrim(coalesce(e.v->>'control_class', '')) control_class, btrim(coalesce(e.v->>'note', '')) note
    from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end) with ordinality e(v, ord)),
  c as (
    select r.*, m.item_type, public._item_unit_code(r.unit) unit_code,
           (r.name_en ~* '^\s*RETIRED' or r.name_bn ~* '^\s*RETIRED' or r.note ~* '^\s*Retired') retired,
           row_number() over (partition by r.code order by r.ord) dup_n
    from r left join public.item_class_map m on m.control_class = r.control_class and m.active)
  select c.ord, c.code, c.cat_no, c.category, c.name_en, c.name_bn, c.subcategory, c.unit, c.control_class, c.note, c.item_type, c.unit_code, c.retired,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' or c.dup_n > 1 or (c.name_en = '' and c.name_bn = '') or c.item_type is null or c.unit_code is null
              or c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'conflict'
         when exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */) then 'skip_existing' else 'create' end,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' then 'bad_code' when c.dup_n > 1 then 'duplicate_in_file' when c.name_en = '' and c.name_bn = '' then 'no_name'
         when c.item_type is null then 'unmapped_class' when c.unit_code is null then 'unknown_unit'
         when c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'category_mismatch'
         when exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */) then 'exists' end
  from c order by c.ord;
$function$$r0_0$, null),
  ('public._item_master_classify(jsonb)', 'known', '3471221fdbac15dc3379aa42a4275fe1', null);
-- _ledger_item_guard()
insert into _u_plan (fn, kind, a, b) values
  ('public._ledger_item_guard()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._ledger_item_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ok boolean;
begin
  if new.reverses_id is not null then return new; end if;                  -- undoing an earlier line is always allowed
  if new.reason = 'sale_out' and new.made_at < now() - interval '2 minutes' then return new; end if;      -- a sale that syncs late has already happened
  select count_in_business into ok from public.items where id = new.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  if ok is distinct from true then raise exception 'item_not_counted' using detail = new.item_id::text; end if;
  return new;
end $function$$r0_0$, null),
  ('public._ledger_item_guard()', 'known', '079b6a10d7af6d3b0fea8149593982a1', null);
-- _notif_ok(uuid,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._notif_ok(uuid,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._notif_ok(p_user uuid, p_aud text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and (p_loc is not null or not public._org_on123()) and exists (select 1 from public.user_roles r where r.user_id = auth.uid()   -- scope123: no place = owner only
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$function$$r0_0$, null),
  ('public._notif_ok(uuid,text,integer)', 'known', '2bde1ebff43d6b52e7e6454303126c85', null);
-- _oo_short77(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._oo_short77(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._oo_short77(p_order uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.online_orders; r record; res jsonb := '[]'::jsonb; rsv boolean := public.rule_on('online_pack_reserve_on'); have numeric; reserved numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then return res; end if;
  for r in select (l->>'item_id')::uuid as item_id, sum((l->>'qty')::numeric) as need from jsonb_array_elements(o.lines) l where nullif(l->>'item_id', '') is not null group by 1 loop
    if not exists (select 1 from public.items i where i.id = r.item_id and i.tracked) then continue; end if;
    select coalesce(b.qty, 0) into have from (select 1) z left join public.stock_balance b on b.item_id = r.item_id and b.location_id = o.location_id;
    reserved := 0;
    if rsv then
      select coalesce(sum((l2->>'qty')::numeric), 0) into reserved from public.online_orders o2, jsonb_array_elements(o2.lines) l2
       where o2.location_id = o.location_id and o2.status = 'packed' and o2.id <> o.id and l2->>'item_id' = r.item_id::text;
    end if;
    if r.need > have - reserved then
      res := res || jsonb_build_object('item_id', r.item_id, 'name', (select name_bn from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */), 'need', r.need, 'have', have, 'reserved', reserved, 'short_by', r.need - (have - reserved));
    end if;
  end loop;
  return res;
end $function$$r0_0$, null),
  ('public._oo_short77(uuid)', 'known', 'fab17db83de4367e24d0698b70aad60f', null);
-- _post_purchase_p13(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._post_purchase_p13(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb; gm text; skipst boolean := false;   -- bos82
begin
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if pb.status = 'posted' then          -- a re-sent request: answered only to someone who may see purchases (or who posted it)
    if not (public._pur_ok(pb.location_id) or pb.posted_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true);
  end if;
  if not (public.has_grant(gcode, pb.location_id) or public._use_em(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.bill_date is distinct from (now() at time zone 'Asia/Dhaka')::date and coalesce(public.rule_txt('purchase_backdate_flag'), 'off') = 'warn' then   -- bos87 (a4-F11): stock is stamped now(), the journal uses bill_date
    perform public._stock_exc(pb.location_id, 'purchase_backdated', 'yellow', 'বিল ' || coalesce(pb.bill_no, '-') || ': তারিখ ' || pb.bill_date::text || ' (আজ নয়) — stock আজকের সময়ে ঢুকেছে, হিসাবের journal বিলের তারিখে',
      'Bill ' || coalesce(pb.bill_no, '-') || ': dated ' || pb.bill_date::text || ' (not today) — the stock is stamped now, the journal uses the bill date', null, pb.bill_date, 'PURCHASE', pb.total);   -- bos87
  end if;   -- bos87
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  if pb.kind = 'return' then
    if pb.ref_bill_id is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
      perform public._stock_exc(pb.location_id, 'purchase_return_unreferenced', 'red', 'বিল ছাড়া ক্রয় ফেরত (বিল ' || coalesce(pb.bill_no, '-') || ')',
        'A purchase return was posted without the original bill (return ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE', pb.total);
    else
      perform 1 from public.purchase_bills where id = pb.ref_bill_id for update;
      select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'description', l.description, 'qty', l.qty, 'unit', l.unit, 'unit_cost', l.unit_cost)), '[]'::jsonb) into norm
        from public.purchase_lines l where l.bill_id = pb.id;
      if not exists (select 1 from public.purchase_bills where id = pb.ref_bill_id and status = 'posted') then raise exception 'bad_ref_bill'; end if;
      perform public._return_check(pb.ref_bill_id, pb.id, norm, true);
    end if;
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  -- bos82: GRN exclusivity. Source = GRN and guard on: the bill keeps money / supplier balance, the GRN holds the stock (no second purchase_in)
  gm := coalesce(public.rule_txt('purchase_grn_guard'), 'off');   -- bos82
  if pb.kind = 'bill' and gm in ('skip', 'link') and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then   -- bos82
    if gm = 'link' and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void') then   -- bos82
      raise exception 'grn_link_required' using detail = 'GRN is the stock source: link this bill to its GRN before posting', hint = 'grn_bill_link';   -- bos82
    end if;   -- bos82
    skipst := true;   -- bos82
  end if;   -- bos82
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one); a return is checked the same way
    if pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ' || case when pb.kind = 'return' then 'ফেরতের' else 'ক্রয়' end || 'মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': ' || case when pb.kind = 'return' then 'return ' else '' end || 'unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked and not (skipst and pb.kind = 'bill') then   -- bos82: stock comes from the GRN
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        -- out at the current average cost (cost null = the average); what the supplier credits beyond / below that is the variance of this return
        lid := public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, null, null, now(), null, null, 'full');
        select unit_cost into av from public.stock_ledger where id = lid;
        var := var + round(bq * (round(ucb * net, 6) - coalesce(av, round(ucb * net, 6))), 2);
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now(), variance = case when pb.kind = 'return' then var end where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum) || case when skipst then jsonb_build_object('stock_from_grn', true) else '{}'::jsonb end;   -- bos82
end $function$$r0_0$, null),
  ('public._post_purchase_p13(uuid,jsonb)', 'known', '7cf22fff506d2bb536e1e40dd01181da', null);
-- _qc_latest60(text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._qc_latest60(text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._qc_latest60(p_type text, p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select status from public.qc_records where source_type = p_type and source_id = p_id and ((select not public._org_on123()) or public._cfgvis133(location_id)) /* scope133 */ order by created_at desc, id desc limit 1;
$function$$r0_0$, null),
  ('public._qc_latest60(text,uuid)', 'known', '4a452166116cebeb49696682abc229ca', null);
-- _recipe_approved_guard()
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_approved_guard()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_approved_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; ap timestamptz;
begin
  if tg_table_name = 'recipes' then
    if old.approved_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
       or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_approved'; end if;
    if old.approved_at is not null and (new.approved_at is distinct from old.approved_at or new.approved_by is distinct from old.approved_by) then raise exception 'recipe_approved'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select approved_at into ap from public.recipes where id = rid and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if ap is not null then raise exception 'recipe_approved'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$$r0_0$, null),
  ('public._recipe_approved_guard()', 'known', 'a3dede9c1d8cf1838e3e33ec05700464', null);
-- _recipe_frozen()
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_frozen()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_frozen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; used timestamptz;
begin
  if tg_table_name = 'recipes' then
    if tg_op = 'DELETE' then
      if old.used_at is not null then raise exception 'recipe_used'; end if;
      raise exception 'no_delete';
    end if;
    if tg_op = 'UPDATE' and old.used_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
        or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_used'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select used_at into used from public.recipes where id = rid and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$$r0_0$, null),
  ('public._recipe_frozen()', 'known', 'b3aaa196019317feca931eeb7913a66c', null);
-- _recipe_gate73(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_gate73(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_gate73(p_recipe uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text := coalesce(public.rule_txt('recipe_approval_required'), 'off'); ap timestamptz;
begin
  select approved_at into ap from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if ap is not null or m = 'off' then return 'ok'; end if;
  if m = 'on' then raise exception 'recipe_not_approved'; end if;
  return 'warn';
end $function$$r0_0$, null),
  ('public._recipe_gate73(uuid)', 'known', '1315b3569fd5008a86cc480c14b3c54e', null);
-- _recipe_need(uuid,numeric,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_need(uuid,numeric,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_need(p_recipe uuid, p_batches numeric, p_loc integer)
 RETURNS TABLE(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from public._recipe_need116(p_recipe, p_batches, p_loc, null::numeric);   -- bos116
$function$$r0_0$, null),
  ('public._recipe_need(uuid,numeric,integer)', 'known', 'feeae75737cf48502013349d01950b51', null);
-- _recipe_set_artisan(uuid,integer,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_set_artisan(uuid,integer,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_set_artisan(p_recipe uuid, p_artisan integer, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; prev jsonb;
begin
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_artisan is not null and not exists (select 1 from public.artisans where id = p_artisan and public._m132_vis('artisans', artisans.org_unit_id, artisans.id::text, false) /* m132b:artisans */ and active) then raise exception 'artisan_not_found'; end if;
  if r.artisan_id is not distinct from p_artisan then return; end if;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipes set artisan_id = p_artisan where id = p_recipe;
  perform public._rv_log(p_recipe, 'artisan_set', prev, left(p_note, 200));
end $function$$r0_0$, null),
  ('public._recipe_set_artisan(uuid,integer,text)', 'known', '1598dc1d7e0839c50982da7d0a56468d', null);
-- _rv_log(uuid,text,jsonb,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._rv_log(uuid,text,jsonb,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._rv_log(p_recipe uuid, p_kind text, p_prev jsonb, p_summary text, p_client uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes;
begin
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  insert into public.recipe_versions (recipe_id, version, seq, kind, changed_by, changed_at, summary, prev, snap, client_id)
    values (p_recipe, r.version, coalesce((select max(seq) from public.recipe_versions where recipe_id = p_recipe), 0) + 1, p_kind, auth.uid(), now(), left(p_summary, 300), p_prev, public._recipe_snapshot(p_recipe), p_client);
end $function$$r0_0$, null),
  ('public._rv_log(uuid,text,jsonb,text,uuid)', 'known', 'ce4e0ae7fbec99a9b239f221712bd556', null);
-- _stock_guard(uuid,integer,text,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._stock_guard(uuid,integer,text,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._stock_guard(p_item uuid, p_loc integer, p_grant text, p_date date DEFAULT NULL::date)
 RETURNS items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if not it.tracked then raise exception 'item_not_tracked'; end if;
  if p_date is not null then perform public.lock_check(p_date); end if;
  return it;
end $function$$r0_0$, null),
  ('public._stock_guard(uuid,integer,text,date)', 'known', 'a380080d4df172de3a1f755b65c00843', null);
-- _sup_balance(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._sup_balance(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._sup_balance(p_supplier uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0)
       + coalesce((select sum(amount) from public.supplier_refunds where supplier_id = p_supplier and not voided), 0);
$function$$r0_0$, null),
  ('public._sup_balance(uuid)', 'known', 'a5964fd9457f19e6d79dd1d479f8ccd2', null);
-- _void_purchase_p13(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._void_purchase_p13(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._void_purchase_p13(p_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; r public.stock_ledger; gmode text; why text; shorts text := ''; kept numeric := 0; z record;   -- bos82
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if pb.status = 'void' then          -- a re-sent request: answered only to someone who may see purchases (or who voided it)
    if not (public._pur_ok(pb.location_id) or pb.void_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true);
  end if;
  if pb.status = 'draft' then
    if not (public.has_grant(case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end, pb.location_id)) then raise exception 'not allowed'; end if;
  elsif not (public.has_grant('purchase_void', pb.location_id) or public._use_em('purchase_void', pb.location_id, 'void_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed';
  end if;
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  perform public.lock_check(pb.bill_date);
  -- bos82: a posted bill that others depend on cannot simply disappear (switch purchase_void_guard: off | warn | refuse)
  gmode := coalesce(public.rule_txt('purchase_void_guard'), 'off');   -- bos82
  if gmode <> 'off' and pb.kind = 'bill' then   -- bos82
    if exists (select 1 from public.purchase_bills x where x.ref_bill_id = pb.id and x.kind = 'return' and x.status = 'posted') then why := 'void_has_return';   -- bos82
    elsif exists (select 1 from public.grn_batch_links gl join public.stock_batches b on b.id = gl.batch_id where gl.source_type = 'purchase' and gl.source_id = pb.id and b.qty_remaining > 0) then why := 'void_has_grn_batch';   -- bos82
    else   -- bos82
      for z in select o.item_id, o.location_id, sum(o.qty_delta) q from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason = 'purchase_in'   -- bos82
               and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) group by 1, 2 order by 1, 2 loop   -- bos82
        perform 1 from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id for update;   -- bos82
        if coalesce((select sb.qty from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id), 0) - z.q < 0 then   -- bos82
          why := 'void_would_go_negative'; shorts := shorts || case when shorts = '' then '' else ', ' end || coalesce((select code from public.items where id = z.item_id and public._m132_own(items.org_unit_id) /* m132b:items */), '?');   -- bos82
        end if;   -- bos82
      end loop;   -- bos82
    end if;   -- bos82
    if why is not null then   -- bos82
      if gmode = 'refuse' then raise exception '%', why using detail = case why when 'void_has_return' then 'A posted purchase return refers to this bill: void the return first' when 'void_has_grn_batch' then 'GRN batches with stock left exist for this bill' else 'Stock used or sold already: voiding would make it negative: ' || shorts end, hint = 'purchase_void_guard'; end if;   -- bos82
      perform public._stock_exc(pb.location_id, 'purchase_void_unsafe', 'red', 'ক্রয় bill বাতিল (ঝুঁকিপূর্ণ): ' || why || ' ' || shorts, 'Purchase bill voided although: ' || why || ' ' || shorts, null, pb.bill_date, 'PURCHASE', pb.total);   -- bos82
    end if;   -- bos82
  end if;   -- bos82
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  if coalesce(public.rule_txt('purchase_void_payments'), 'void') = 'keep' then   -- bos82: cash really left; the payment stays and becomes supplier credit (use supplier_refund to take the money back)
    select coalesce(sum(amount), 0) into kept from public.supplier_payments where bill_id = pb.id and not voided;   -- bos82
    if kept > 0 then perform public._stock_exc(pb.location_id, 'purchase_void_credit', 'yellow', 'বাতিল bill-এর পরিশোধ রাখা হয়েছে, supplier-এর কাছে credit: ' || kept::text, 'Voided bill payment kept as supplier credit: ' || kept::text, null, pb.bill_date, 'PURCHASE', kept); end if;   -- bos82
  else   -- bos82
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  end if;   -- bos82
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void') || case when kept > 0 then jsonb_build_object('payments_kept', kept) else '{}'::jsonb end;   -- bos82
end $function$$r0_0$, null),
  ('public._void_purchase_p13(uuid,text)', 'known', 'a184305d1e9103bddb619f2858e8dee3', null);
-- _wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._wastage_post(p_item uuid, p_loc integer, p_bq numeric, p_reason text, p_note text, p_photo text, p_batch bigint, p_client uuid, p_by uuid, p_staff text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; wid uuid := gen_random_uuid(); lid bigint;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  begin
    lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
    insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
      values (wid, p_item, p_loc, p_bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, p_by, p_staff);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins, this one is the duplicate
    select id into lid from public.stock_ledger where p_client is not null and client_id = p_client and reason = 'wastage' order by id limit 1;
    if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    raise;
  end;
  if p_reason = 'unknown' then
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', it.name_bn || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, it.name_bn) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', p_bq);
end $function$$r0_0$, null),
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)', 'known', '977c0e0b97a6c5fd64bff7b04eac43e4', null);
-- acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_account_save(p_id bigint, p_code text, p_name_bn text, p_name_en text, p_type text, p_parent bigint DEFAULT NULL::bigint, p_active boolean DEFAULT true, p_sort integer DEFAULT NULL::integer, p_contra boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts; side text; par public.coa_accounts;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or length(p_name_bn) > 120 or p_name_en is null or length(btrim(p_name_en)) = 0 or length(p_name_en) > 120 then raise exception 'name_required'; end if;
  if p_parent is not null then
    select * into par from public.coa_accounts where id = p_parent;
    if not found or not par.is_group then raise exception 'bad_parent'; end if;
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
    if p_type is null or p_type not in ('asset', 'liability', 'equity', 'income', 'expense') then raise exception 'bad_type'; end if;
    if par.id is not null and par.type <> p_type then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
    side := case when (p_type in ('asset', 'expense')) <> coalesce(p_contra, false) then 'debit' else 'credit' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, sort, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), p_type, side, p_parent, coalesce(p_sort, 500), auth.uid()) returning * into a;
    return jsonb_build_object('id', a.id, 'code', a.code);
  end if;
  select * into a from public.coa_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if par.id is not null and (par.type <> a.type or par.id = a.id) then raise exception 'bad_parent'; end if;
  if not coalesce(p_active, true) then
    if a.is_system and exists (select 1 from public.acct_mappings where account_id = a.id) then raise exception 'account_in_use_by_mapping'; end if;
    if exists (select 1 from public.coa_accounts where parent_id = a.id and active) then raise exception 'has_active_children'; end if;
  end if;
  update public.coa_accounts set name_bn = btrim(p_name_bn), name_en = btrim(p_name_en), parent_id = coalesce(p_parent, parent_id), active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where id = a.id;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $function$$r0_0$, null),
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'known', '9cfc4b0aff3117417d83fa0b3ff26503', null);
-- acct_mapping_set(text,bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_mapping_set(text,bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_mapping_set(p_key text, p_account bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_key is null or p_key !~ '^[a-z0-9_]{2,48}$' then raise exception 'bad_key'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
  if not exists (select 1 from public.acct_mappings where key = p_key) and p_key not like 'exp\_%' then raise exception 'bad_key'; end if;
  insert into public.acct_mappings (key, account_id, updated_by) values (p_key, p_account, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'account_id', p_account);
end $function$$r0_0$, null),
  ('public.acct_mapping_set(text,bigint)', 'known', '174255f4dac51c1fd71820cb6408ecef', null);
-- acct_opening(jsonb,boolean,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_opening(p_lines jsonb, p_plug boolean DEFAULT false, p_memo text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); ln jsonb; x jsonb; td numeric := 0; tc numeric := 0; diff numeric; plug bigint; r public.journal_entries; id_ bigint; ty text;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = o.id)) then raise exception 'opening_exists'; end if;
  if exists (select 1 from public.journal_entries where entry_date < st and source_type <> 'opening') then raise exception 'postings_before_opening'; end if;
  ln := public._acct_resolve(p_lines, null);
  for x in select * from jsonb_array_elements(ln) loop
    select type into ty from public.coa_accounts where id = (x->>'account_id')::bigint;
    if ty in ('income', 'expense') then raise exception 'opening_balance_sheet_only'; end if;
    td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric;
  end loop;
  diff := round(td - tc, 2);
  if diff <> 0 then
    if not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
    select account_id into plug from public.acct_mappings where key = 'retained';
    if plug is null then raise exception 'mapping_missing:retained'; end if;
    ln := ln || jsonb_build_object('account_id', plug, 'debit', case when diff < 0 then -diff else 0 end, 'credit', case when diff > 0 then diff else 0 end, 'party_type', null, 'party_id', null, 'memo', 'balancing figure', 'location_id', null);
    if diff > 0 then tc := tc + diff; else td := td - diff; end if;
  end if;
  if td <= 0 then raise exception 'no_lines'; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', st, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  id_ := public._acct_write(st, null, 'opening', 'opening:' || coalesce(p_client::text, gen_random_uuid()::text), null, coalesce(nullif(btrim(p_memo), ''), 'Opening balances'), null, ln, null, p_client, null);
  return jsonb_build_object('id', id_, 'date', st, 'plug', diff);
end $function$$r0_0$, null),
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)', 'known', '6ed9f953d2d13665ffe41a5d75d34c3c', null);
-- acct_post_pending(boolean,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_post_pending(boolean,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]'; lk jsonb := '[]'; lw boolean := coalesce(public.rule_txt('period_lock_late_warn'), 'off') = 'on';   -- bos113
begin
  if not (public._acct_manage() or (auth.uid() is null and coalesce(current_setting('bos.autopost85', true), '') = 'on')) then raise exception 'not allowed'; end if;   -- bos85: the scheduler entry point has no signed-in person
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id)) /* scope133 */ order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', d.entry_date); end if; continue; end if;   -- bos113
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', rdate, 'reversal', true); end if; continue; end if;   -- bos113
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;   -- bos72: solved
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      if not p_dry then   -- bos72: keep the failure so the status strip and the accounts page can show it (the browser used to drop it)
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  if lw and not p_dry and locked > 0 then   -- bos113: rule period_lock_late_warn = on: documents the scheduler could not book (their date is in a closed period) are no longer silent
    if exists (select 1 from public.exceptions x where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open') then
      update public.exceptions x set amount = locked where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open';
    else
      perform public._stock_exc((select min(l.id) from public.locations l), 'late_docs_locked', 'yellow',
        locked::text || ' নথি বই-এ ওঠেনি: তারিখ বন্ধ হিসাবকালে', locked::text || ' document(s) are not in the books: their date is in a closed period (reopen the period or post them by hand)', null, public._acct_today(), 'ACCOUNTS', locked);
    end if;
  end if;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped) || case when lw then jsonb_build_object('locked_docs', lk) else '{}'::jsonb end;   -- bos113
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$$r0_0$, null),
  ('public.acct_post_pending(boolean,integer)', 'known', '7f14a329e494717cca39e326267e6e07', null);
-- acct_status()
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_status()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); pend int := 0; lck int := 0; wt int := 0; er int := 0; erl jsonb := '[]'::jsonb;   -- bos72
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is not null then   -- bos72: documents not yet in the books (the same list acct_post_pending would work through)
    with dd as materialized (select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id))), /* scope133 */
    e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null),
           (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries, 'last_at', y.last_at) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, er, erl;
  end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', st,
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries je where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(je.location_id))), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),
    'last_post_at', (select max(created_at) from public.journal_entries where (created_by is not null or exists (select 1 from public.acct_autopost_runs85)) and source_type not in ('manual', 'opening')),   -- bos72 bos85: a scheduler run has no person
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl,   -- bos72
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));   -- bos85
end $function$$r0_0$, null),
  ('public.acct_status()', 'known', '0ec4a16d7f2d7227280832344eee7627', null);
-- artisan_list(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.artisan_list(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.artisan_list(p_include_retired boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._recipe_read() or public.has_grant('recipe_view') or public._artisan_mgr()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active) order by a.id) from public.artisans a where (p_include_retired or a.active) and public._m132_vis('artisans', a.org_unit_id, a.id::text, false) /* m132 */), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.artisan_list(boolean)', 'known', '80c857cff6dadbe00d644af2c40a5333', null);
-- assistant_health()
insert into _u_plan (fn, kind, a, b) values
  ('public.assistant_health()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.assistant_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  f jsonb := '[]'::jsonb; locs int[]; n bigint; n2 bigint; ev jsonb; r record; d date; today date := (now() at time zone 'Asia/Dhaka')::date;
  age int := coalesce(public.rule_num('assistant_closed_age_days'), 45)::int; sid bigint; miss text[]; k text; v jsonb; maxh numeric; last timestamptz; fin boolean;
  keys constant text[] := array['drawer_float', 'cash_tol', 'discount_limit', 'expense_max'];
begin
  if not public._assistant_health_ok() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into locs from public.locations l
   where coalesce(l.status, 'live') in ('live', 'setting_up') and (public.is_owner() or (public.has_grant('head_management') and ((select not public._org_on123()) or public._biz_ok123(l.id))) or public.can_loc(l.id));   /* scope133 */

  -- items
  select count(*), coalesce(jsonb_agg(code order by code) filter (where rn <= 5), '[]') into n, ev from (
    select i.code, row_number() over (order by i.code) rn from public.items i
     where i.is_active and coalesce(i.sellable, true) and not coalesce(i.hidden, false) and i.retired_at is null and (i.sell_price is null or i.sell_price <= 0)) z;
  if n > 0 then f := f || public._ah('items_no_price', 'warn', 'দাম ছাড়া বিক্রয়যোগ্য আইটেম', 'Sellable items without a price', n || ' active sellable items have no selling price', 'bulkitems', jsonb_build_object('count', n, 'sample', ev)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.unit is null and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_no_unit', 'warn', 'একক ছাড়া আইটেম', 'Items without a unit', n || ' active items have no unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.tracked and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_tracked_no_base', 'warn', 'স্টক-হিসাবি আইটেমের মূল একক নেই', 'Stock-tracked items without a base unit', n || ' tracked items have no base unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) filter (where i.tracked), count(*) into n, n2 from public.items i where i.is_active and i.retired_at is null;
  if n2 > 0 and n = 0 then f := f || public._ah('items_none_tracked', 'info', 'কোনো আইটেমে স্টক-হিসাব চালু নেই', 'No item has stock tracking on', 'Stock pages and stock reports stay empty until items are tracked', 'bulkitems', jsonb_build_object('active_items', n2)); end if;

  -- places: settings sheet and key limits (showrooms)
  for r in select l.id, l.code, l.kind from public.locations l where l.id = any (locs) order by l.id loop
    sid := public._sheet_in_force(r.id, today);
    if not exists (select 1 from public.settings_sheets s where s.location_id = r.id and s.status = 'approved') then
      f := f || public._ah('loc_no_sheet', 'warn', 'জায়গার সেটিংস-শিট অনুমোদিত নয়', 'Place has no approved settings sheet', r.code || ': no approved Location Settings Sheet (0-1)', 'locset', jsonb_build_object('location_id', r.id, 'code', r.code));
    end if;
    if coalesce(r.kind, 'showroom') = 'showroom' then
      miss := '{}';
      foreach k in array keys loop
        if sid is null then select value into v from public.location_settings where location_id = r.id and key = k; else select value into v from public.settings_values where sheet_id = sid and key = k; end if;
        if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then miss := miss || k; end if;
        v := null;
      end loop;
      if cardinality(miss) > 0 then
        f := f || public._ah('loc_limit_blank', 'warn', 'জায়গার সীমা ফাঁকা (তথ্য দরকার)', 'Blank limits at a place (data needed)', r.code || ': ' || array_to_string(miss, ', '), 'locset', jsonb_build_object('location_id', r.id, 'code', r.code, 'missing', to_jsonb(miss)));
      end if;
    end if;
  end loop;

  -- rollout
  select count(*) into n from public.form_rollout fr where fr.mode = 'paper' and fr.location_id = any (locs)
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id);
  if n > 0 then f := f || public._ah('paper_never_app', 'info', 'কাগজে চলা ফর্ম, অ্যাপে কখনো লেখা হয়নি', 'Forms on paper never tried in the app', n || ' form x place cells are on Paper and have no app entry yet', 'rollout', jsonb_build_object('count', n)); end if;
  if public.rule_on('parallel_compare_on') then
    select count(*), coalesce(jsonb_agg(fr.form_code || '@' || fr.location_id) filter (where true), '[]') into n, ev from public.form_rollout fr
     where fr.mode = 'parallel' and fr.location_id = any (locs) and not exists (select 1 from public.comparison_pairs p where p.form_code = fr.form_code and p.is_active);
    if n > 0 then f := f || public._ah('parallel_no_pair', 'warn', 'পাশাপাশি চলছে কিন্তু তুলনার জোড়া নেই', 'Parallel without a comparison pair', n || ' parallel cells cannot record a comparison day', 'parallel', jsonb_build_object('count', n, 'cells', ev)); end if;
  end if;
  select count(*) into n from public.form_rollout fr where fr.mode = 'app' and fr.location_id = any (locs) and fr.changed_at < now() - interval '14 days'
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id and e.created_at > now() - interval '14 days');
  if n > 0 then f := f || public._ah('app_unused', 'info', 'অ্যাপে বদলানো ফর্ম ১৪ দিন ব্যবহার হয়নি', 'Forms moved to the app but unused for 14 days', n || ' form x place cells', 'rollout', jsonb_build_object('count', n)); end if;

  -- rule conflicts (each justified in docs/ASSISTANT_AUDIT.md section 6)
  if coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then
    if public.rule_on('forms_post_to_ledger') then
      f := f || public._ah('grn_double_count', 'warn', 'GRN ও ক্রয় পেজ দুটোই স্টক বাড়াতে পারে', 'GRN and the purchase page may both add stock', 'grn_receipt_source = grn and forms_post_to_ledger ON: the purchase page still posts purchase_in; check receipt duplicates', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', true));
    else
      f := f || public._ah('grn_source_no_effect', 'info', 'GRN-কে উৎস করা হয়েছে, কিন্তু ফর্ম লেজারে যায় না', 'GRN chosen as the source but forms do not post', 'grn_receipt_source = grn while forms_post_to_ledger is OFF: the choice has no effect', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', false));
    end if;
  end if;
  if public.rule_on('vat_on') and public.rule_num('vat_rate') is null then
    f := f || public._ah('vat_no_rate', 'bad', 'ভ্যাট চালু কিন্তু হার নেই', 'VAT is on but the rate is blank', 'vat_on ON, vat_rate blank', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('production_requires_recipe') and not exists (select 1 from public.recipes rc where rc.active) then
    f := f || public._ah('production_no_recipe', 'bad', 'রেসিপি বাধ্যতামূলক কিন্তু কোনো রেসিপি নেই', 'Recipe required but no active recipe', 'production_requires_recipe ON: every production is refused', 'recipes', '{}'::jsonb);
  end if;
  if public.rule_on('recipe_waste_required') then
    select count(*) into n from public.recipe_lines rl join public.recipes rc on rc.id = rl.recipe_id where rc.active and rl.active and rl.waste_pct is null;
    if n > 0 then f := f || public._ah('recipe_waste_blank', 'warn', 'রেসিপির লাইনে অপচয় % নেই', 'Recipe lines without waste %', n || ' active lines: production with them is refused', 'recipes', jsonb_build_object('count', n)); end if;
  end if;
  select count(*) into n from public.recipes rc where rc.active and (rc.yield_qty is null or rc.yield_qty <= 0);
  if n > 0 then f := f || public._ah('recipe_no_yield', 'warn', 'রেসিপির উৎপাদন-পরিমাণ (yield) নেই', 'Recipes without yield', n || ' active recipes', 'recipes', jsonb_build_object('count', n)); end if;
  if public.rule_on('blind_count_on') and not exists (select 1 from public.blind_count_cfg b where b.enabled) then
    f := f || public._ah('blind_no_form', 'info', 'ব্লাইন্ড কাউন্ট চালু, কিন্তু কোনো ফর্মে নয়', 'Blind count is on for no form', 'blind_count_on ON but no form x place is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('pin_signature_on') and not exists (select 1 from public.pin_sig_cfg p where p.enabled) then
    f := f || public._ah('pin_no_form', 'info', 'পিন-সই চালু, কিন্তু কোনো ফর্মে নয়', 'PIN signature is on for no form', 'pin_signature_on ON but no form is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if coalesce(public.rule_txt('stock_negative_mode'), 'warn') = 'allow' and not public.rule_on('block_expired_sale') then
    f := f || public._ah('stock_guards_off', 'info', 'বিক্রিতে স্টকের কোনো বাধা নেই (দুর্বল নিয়ন্ত্রণ)', 'No stock guard at the till (weak control)', 'stock_negative_mode = allow and block_expired_sale OFF', 'switchboard', '{}'::jsonb);
  end if;

  -- books and day book
  d := public.rpt_date(public.rule_txt('period_closed_until'));
  if d is null then f := f || public._ah('books_never_closed', 'warn', 'হিসাব কখনো বন্ধ (লক) করা হয়নি', 'Books were never closed', 'period_closed_until is blank: any old date can still be changed', 'rules', '{}'::jsonb);
  elsif d < today - age then f := f || public._ah('books_closed_old', 'info', 'হিসাব বন্ধের তারিখ পুরনো', 'Books-closed date is old', 'closed until ' || d || ' (' || (today - d) || ' days ago)', 'rules', jsonb_build_object('closed_until', d, 'days', today - d)); end if;
  if public.rule_on('daybook_enabled') then
    if public._db_start() is null then f := f || public._ah('daybook_no_start', 'warn', 'দৈনিক খাতার শুরুর তারিখ নেই', 'Day book has no start date', 'running cash / bank / mobile totals are unknown', 'daybook', '{}'::jsonb);
    elsif public.rule_num('daybook_open_cash') is null or public.rule_num('daybook_open_bank') is null or public.rule_num('daybook_open_mobile') is null then
      f := f || public._ah('daybook_no_opening', 'info', 'শুরুর ক্যাশ/ব্যাংক/মোবাইল ব্যালান্স ফাঁকা', 'Opening cash / bank / mobile balance blank', 'closing balances cannot be shown (data needed)', 'daybook', '{}'::jsonb);
    end if;
  end if;
  if public.rule_txt('fiscal_year_start_month') is null or public.rule_txt('week_start') is null then
    f := f || public._ah('calendar_defaults', 'info', 'অর্থবছর / সপ্তাহের শুরু ঠিক করা হয়নি', 'Fiscal year / week start not set', 'reports use the calendar year and Saturday', 'switchboard', '{}'::jsonb);
  end if;

  -- people
  select count(*) into n from public.profiles p where p.status = 'pending';
  if n > 0 then f := f || public._ah('staff_pending', 'warn', 'নতুন স্টাফ অনুমোদনের অপেক্ষায়', 'Staff accounts waiting for approval', n || ' pending', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active'
     and not exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code in ('owner', 'management'))
     and not exists (select 1 from public.user_locations ul where ul.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_location', 'warn', 'সক্রিয় স্টাফের কোনো জায়গা নেই', 'Active staff without a place', n || ' people cannot work anywhere', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active' and not exists (select 1 from public.user_roles ur where ur.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_role', 'warn', 'সক্রিয় স্টাফের ভূমিকা নেই', 'Active staff without a role', n || ' people', 'staff', jsonb_build_object('count', n)); end if;
  foreach k in array array['release_decide', 'wastage_approve', 'change_approve'] loop
    if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where g.grant_code = k and (g.valid_until is null or g.valid_until > now())
                     and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
       and not exists (select 1 from public.rule_grants rg where rg.grant_code = k and rg.allowed and rg.role_code <> 'owner') then
      f := f || public._ah('only_owner_' || k, 'info', 'এই অনুমোদন শুধু মালিক দিতে পারেন', 'Only the owner can decide this', k || ': nobody else holds it (owner absent = waiting)', 'delegation', jsonb_build_object('grant', k));
    end if;
  end loop;
  if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where (g.grant_code like 'report\_%' or g.grant_code = 'view_reports') and (g.valid_until is null or g.valid_until > now())
                   and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
     and not exists (select 1 from public.rule_grants rg where (rg.grant_code like 'report\_%' or rg.grant_code = 'view_reports') and rg.allowed and rg.role_code <> 'owner') then
    f := f || public._ah('reports_owner_only', 'info', 'রিপোর্ট শুধু মালিক দেখেন', 'Only the owner sees reports', 'no report grant is given to anyone else', 'delegation', '{}'::jsonb);
  end if;

  -- parties
  select count(*) into n from public.suppliers s where s.active and s.credit_days is null;
  if n > 0 then f := f || public._ah('supplier_no_credit_days', 'info', 'সরবরাহকারীর বাকির দিন নেই', 'Suppliers without credit days', n || ' suppliers: overdue cannot be worked out for them', 'settings2/suppliers', jsonb_build_object('count', n)); end if;
  select count(*), coalesce(round(sum(c.balance - c.credit_limit), 2), 0) into n, n2 from public.customer_dues() c where c.credit_limit is not null and c.balance > c.credit_limit;
  if n > 0 then f := f || public._ah('customers_over_limit', 'warn', 'বাকির সীমা পেরোনো গ্রাহক', 'Customers over their credit limit', n || ' customers, ' || n2 || ' over in total', 'dues', jsonb_build_object('count', n, 'over_total', n2)); end if;

  -- optional modules (only when installed)
  if to_regclass('public.backup_runs') is not null then
    maxh := coalesce(public.rule_num('backup_max_age_hours'), 36);
    execute 'select max(finished_at) from public.backup_runs where status = ''ok''' into last;
    if last is null then f := f || public._ah('backup_none', 'warn', 'কোনো সফল ব্যাকআপ নেই', 'No successful backup recorded', 'backup_runs has no ok run', 'backup', '{}'::jsonb);
    elsif last < now() - make_interval(hours => maxh::int) then f := f || public._ah('backup_stale', 'bad', 'ব্যাকআপ পুরনো', 'Backup is stale', 'last ok backup ' || round(extract(epoch from now() - last) / 3600) || ' hours ago (limit ' || maxh || ')', 'backup', jsonb_build_object('hours', round(extract(epoch from now() - last) / 3600), 'limit', maxh)); end if;
  end if;
  if exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and public.rule_txt('accounting_start_date') is null then
    f := f || public._ah('accounting_no_start', 'bad', 'হিসাব (অ্যাকাউন্টিং) চালু কিন্তু শুরুর তারিখ / প্রারম্ভিক ব্যালান্স নেই', 'Accounting on without a start date / opening balances', 'accounting_on ON, accounting_start_date blank', 'accounts', '{}'::jsonb);
  elsif exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and to_regclass('public.journal_entries') is not null then
    execute 'select exists (select 1 from public.journal_entries o where o.source_type = ''opening'' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id))' into fin;
    if not fin then f := f || public._ah('accounting_no_opening', 'warn', 'হিসাব চালু কিন্তু প্রারম্ভিক ব্যালান্স (opening journal) নেই', 'Accounting on without an opening journal', 'no active opening journal (phase40 acct_opening)', 'accounts', '{}'::jsonb); end if;
  end if;
  return f;
end $function$$r0_0$, null),
  ('public.assistant_health()', 'known', '7adfcc394b57315d37daa4f1a2634a23', null);
-- bank_recon_candidates(bigint,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_candidates(bigint,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_candidates(p_line bigint, p_days integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('entry_id', c.entry_id, 'line_no', c.line_no, 'date', c.entry_date, 'memo', c.memo, 'source_type', c.source_type,
      'source_id', c.source_id, 'amount', c.amount, 'days_off', c.days_off, 'ref_hit', c.ref_hit)) from (select * from public._a53_cands(p_line, p_days) limit 20) c), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.bank_recon_candidates(bigint,integer)', 'known', '054be453a006c4d3e6aae86837f10377', null);
-- bank_recon_lines(bigint,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_lines(bigint,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_lines(p_account bigint, p_status text DEFAULT 'all'::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  if p_status not in ('all', 'matched', 'unmatched') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(j order by (j->>'date') desc, (j->>'id')::bigint desc) from (
    select jsonb_build_object('id', l.id, 'date', l.line_date, 'amount', l.amount, 'reference', l.reference, 'description', l.description,
      'matched', m.id is not null, 'entry_id', m.entry_id, 'line_no', m.line_no, 'how', m.how) j
    from public.bank_statement_lines l left join public.bank_recon_matches m on m.line_id = l.id and m.active
    where l.account_id = p_account and (p_status = 'all' or (p_status = 'matched') = (m.id is not null))
    order by l.line_date desc, l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.bank_recon_lines(bigint,text,integer)', 'known', '726a495058c1b0a566ed454d4720c08a', null);
-- bank_recon_match(bigint,bigint,integer,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_match(bigint,bigint,integer,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_match(p_line bigint, p_entry bigint, p_line_no integer, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_ bigint;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  id_ := public._a53_match1(p_line, p_entry, p_line_no, 'manual', p_note);
  return jsonb_build_object('match_id', id_);
end $function$$r0_0$, null),
  ('public.bank_recon_match(bigint,bigint,integer,text)', 'known', '8790e217569d918318a64339bb0f2a05', null);
-- bank_recon_match_many(jsonb,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_match_many(jsonb,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_match_many(p_pairs jsonb, p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p jsonb; ok int := 0; fails jsonb := '[]'::jsonb;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_pairs is null or jsonb_typeof(p_pairs) <> 'array' or jsonb_array_length(p_pairs) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_pairs) > 500 then raise exception 'too_many_rows'; end if;
  for p in select * from jsonb_array_elements(p_pairs) loop
    begin
      perform public._a53_match1((p->>'line_id')::bigint, (p->>'entry_id')::bigint, (p->>'line_no')::int, 'suggested', null);
      ok := ok + 1;
      if p_dry then raise exception 'dry_rollback'; end if;
    exception when others then
      if sqlerrm = 'dry_rollback' then null; else fails := fails || jsonb_build_object('line_id', p->'line_id', 'why', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'ok', ok, 'failed', jsonb_array_length(fails), 'failures', fails);
end $function$$r0_0$, null),
  ('public.bank_recon_match_many(jsonb,boolean)', 'known', '6ee94ee0bc05fe82f2dd0d399e06eedc', null);
do $u535$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase535: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase535: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase535: % function(s) changed', nfix;
end $u535$;
drop table if exists _u_plan;

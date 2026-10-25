-- Phase 529 (UNION-1) - what our line's phases 80 to 505 need from the database before they can be pasted on top of the advanced block. Paste-twice safe. Earlier phase files are not edited.
-- Place in the paste order: after the advanced block (phase 135), before phase 80 (tests/sql/ORDER.txt, docs/PASTE_ORDER.md).
-- Two shared functions were changed by the advanced line in a way that stops our line's exact-text hooks and guards:
--   1. lock_check(date): advanced phase113 (bos113) added the owner mode `period_lock_owner_mode`; our phases 87/89/99/477 hook the phase 6 text
--      `if p_date is null or public.is_owner() then return; end if;` and stop with "phase89 patch site not found in lock_check(date)".
--      Only when the body carries bos113 and none of our tags (bos87, bos89), the body is saved in public._union_fn_backup and the phase 6 text is put back.
--      Phase 530 (paste after phase 505) puts the bos113 owner mode back on top of the hooked body. Nothing of bos113 is lost.
--   2. acct_journal_post: the advanced phase511 replaced the 7-argument function by an 8-argument one (extra p_reason, bos85 manual journal guard). Our phases 88/94/99 need
--      the 7-argument function (guard in phase88, text hook of phase99). A call with up to 7 arguments would also be ambiguous while both exist, because p_reason has a default.
--      This file (a) re-creates the 7-argument function from the phase 40 text when it is missing and (b) re-creates the 8-argument one WITHOUT any parameter default, so a call
--      with up to 7 arguments always means the 7-argument function and a call with all 8 arguments always means the 8-argument one. Phase 530 adds the bos85 guard to the 7-argument function
--      and our journal gate to the 8-argument one, so both behave the same.
-- A body that already carries our hooks is never replaced by this file.

create table if not exists public._union_fn_backup (
  id bigserial primary key,
  fn text not null,
  saved_at timestamptz not null default now(),
  why text,
  def text not null
);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

-- 1. lock_check
do $u529$
declare d text;
begin
  if to_regprocedure('public.lock_check(date)') is null then
    raise exception 'phase529 needs lock_check(date) (phase 6)';
  end if;
  d := pg_get_functiondef('public.lock_check(date)'::regprocedure);
  if position('bos113' in d) > 0 and position('bos87' in d) = 0 and position('bos89' in d) = 0 then
    insert into public._union_fn_backup (fn, why, def) values ('public.lock_check(date)', 'phase529: body with the bos113 owner mode, replaced by the phase 6 text so the hooks of phases 87/89 can be applied; phase530 restores bos113', d);
    execute $f$
CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $b$

$f$;
    revoke all on function public.lock_check(date) from public, anon, authenticated;
  end if;
end $u529$;

-- 2. acct_journal_post: one 7-argument function (hooked by our line) and one 8-argument function (p_reason without default)
do $u529b$
declare d8 text;
begin
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null then
    execute $f$
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_memo is null or length(btrim(p_memo)) < 3 then raise exception 'memo_required'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  ln := public._acct_resolve(p_lines, p_loc);
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', p_date, 'total_debit', td, 'total_credit', tc, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $b$

$f$;
    revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) from public, anon;
    grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) to authenticated;
  end if;
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null then
    d8 := pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'::regprocedure);
    if position(' DEFAULT ' in substr(d8, 1, position(E'\n' in d8))) > 0 then
      insert into public._union_fn_backup (fn, why, def) values ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'phase529: the 8-argument function had defaults, so a call with up to 7 arguments was ambiguous; the defaults are removed (a call with 8 arguments means this function)', d8);
      drop function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text);
      execute regexp_replace(substr(d8, 1, position(E'\n' in d8) - 1), ' DEFAULT [A-Za-z0-9_:]+', '', 'g') || substr(d8, position(E'\n' in d8));
      revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) from public, anon;
      grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) to authenticated;
    end if;
  end if;
end $u529b$;

-- _cust_bal(uuid): the advanced body (md5 ed80bafae0dc2eeba6382ebc284bbede) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public._cust_bal(uuid)') is null then raise exception 'phase529: public._cust_bal(uuid) is missing'; end if;
  d := pg_get_functiondef('public._cust_bal(uuid)'::regprocedure);
  if md5(d) = 'ed80bafae0dc2eeba6382ebc284bbede' then
    insert into public._union_fn_backup (fn, why, def) values ('public._cust_bal(uuid)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public._cust_bal(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$function$
$b$;
  end if;
end $u529c$;

-- customer_dues(): the advanced body (md5 14bce6b96ca918b1fb7f9aa72dcd08f5) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.customer_dues()') is null then raise exception 'phase529: public.customer_dues() is missing'; end if;
  d := pg_get_functiondef('public.customer_dues()'::regprocedure);
  if md5(d) = '14bce6b96ca918b1fb7f9aa72dcd08f5' then
    insert into public._union_fn_backup (fn, why, def) values ('public.customer_dues()', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$
$b$;
  end if;
end $u529c$;

-- rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean): the advanced body (md5 803786a2870251caf1679492765cea9b) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)') is null then raise exception 'phase529: public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean) is missing'; end if;
  d := pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure);
  if md5(d) = '803786a2870251caf1679492765cea9b' then
    insert into public._union_fn_backup (fn, why, def) values ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$
$b$;
  end if;
end $u529c$;

-- biz_items(date,date,integer): the advanced body (md5 505a50e08115e25ad02335b958568ee8) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.biz_items(date,date,integer)') is null then raise exception 'phase529: public.biz_items(date,date,integer) is missing'; end if;
  d := pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure);
  if md5(d) = '505a50e08115e25ad02335b958568ee8' then
    insert into public._union_fn_backup (fn, why, def) values ('public.biz_items(date,date,integer)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$
$b$;
  end if;
end $u529c$;

-- ============================================================
-- Phase 117 (bos117) - BATCH 3, part 2: factory overhead reaches the books (audit: docs/audit2/A1_manufacturing_cost.md G2 G3; docs/audit2/A3_real_profit.md gap 5 / G10).
-- Run AFTER phase116 (canonical order, docs/PASTE_ORDER.md section N). Needs phases 72..111 and 116. Additive; paste twice = no change.
-- Both switches below are OFF by default = today's behaviour (a pool is a memo; factory salary also shows on the factory branch):
--   pool_gl_post117            every pool row (typed with pool_set, or coming from a cost bill with dest factory) is also posted as an expense:
--                              Dr the expense account of its cost type, Cr 2400 Other accrued expenses (pool_accrued), dated the last day of the month (today at the latest), source pool_gl117.
--                              This is the matching Dr for the Cr 5950 "overhead absorbed" of production: the unabsorbed part (actual - absorbed) is then simply an expense of the month in the P&L.
--                              A retired pool row (typed again, bill voided) is reversed. Year pools post 1/12 per month. Depreciation is NOT posted (the fixed-asset module does that).
--                              !! Turn it on ONLY if the same factory costs are NOT also entered as expenses / payroll / bills (that would count them twice).
--   factory_labour_absorbed117 the branch P&L (_p27_pl) leaves out of the factory's sheet salary the labour that was already absorbed into product cost, so it is not counted twice (A3 gap 5).
-- Read-only: pool_vs_gl117 (pool vs absorbed vs expense in the books), overhead_trueup117 (the old true-up + what reached the P&L).
-- Functions re-created (tag bos117): pool_set, _cs_push_pools, _p27_pl. Re-paste rule: if phase74/75/79 or phase72 is pasted again, paste phase117 again after it.
-- NOT done (on purpose): booking OVER-absorbed overhead back out of stock needs an actual-output re-rate at month close (risky for stock values); see docs/audit2/B3_REPORT.md.
-- ============================================================

do $g$
declare miss text := ''; m record; d text; t text; bad text := '';
begin
  for m in select * from (values ('116', 'public.production_reprice116(integer,date,boolean)'), ('74', 'public._pool_rate(integer,date,text)'), ('75', 'public._cs_alloc(bigint)'), ('72', 'public._cogs_lines72(date,date,integer[])')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.recipe_std116') is null then miss := miss || ' 116'; end if;
  if miss <> '' then raise exception 'phase117 needs phases 72..111 and 116 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
  for m in select * from (values ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'bos75 bos117'), ('public._cs_push_pools(bigint)', 'bos117'), ('public._p27_pl(date,date,integer[])', 'bos50 bos72 bos117')) v(fn, ok)
  loop
    d := pg_get_functiondef(to_regprocedure(m.fn));
    for t in select distinct x[1] from regexp_matches(d, '(bos[0-9]+)', 'g') x loop
      if position(t in m.ok) = 0 then bad := bad || ' ' || m.fn || '->' || t; end if;
    end loop;
  end loop;
  if bad <> '' then raise exception 'phase117 refuses: a function it re-creates carries a tag it does not know (merge that change into phase117 first):%', bad; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pool_gl_post117', 'stock', 'switch', 'false', null, null, null,
  'কারখানার খরচের পুল হিসাবেও (GL) খরচ হিসেবে উঠবে', 'Factory cost pool GL-এও expense হিসেবে উঠবে', 'Factory cost pools are also posted as an expense in the books',
  'Off (default) = আজকের মতো, পুল শুধু স্মারক (memo); উৎপাদনে "ওভারহেড শোষিত" (5950) জমা হলেও তার বিপরীতে খরচ নাও থাকতে পারে। On = পুলের প্রতিটি সারি খরচ (Dr) / বাকি খরচ 2400 (Cr) হিসেবে ওঠে। সাবধান: একই খরচ আলাদা expense / বেতন / বিল হিসেবে লিখলে দুবার গোনা হবে।',
  'Off (default) = a pool is a memo; production credits "overhead absorbed" (5950) with no matching expense necessarily in the books. On = each pool row is posted Dr expense / Cr 2400 accrued. Careful: if the same cost is also entered as an expense, payroll or bill it is counted twice.', 760),
 ('factory_labour_absorbed117', 'stock', 'switch', 'false', null, null, null,
  'কারখানার বেতন থেকে পণ্যের খরচে ধরা শ্রম বাদ (দুবার গোনা বন্ধ)', 'Factory salary থেকে product cost-এ ধরা labour বাদ (double count বন্ধ)', 'Factory salary leaves out the labour already absorbed into product cost',
  'Off (default) = আজকের মতো: শ্রম পণ্যের খরচে (বিক্রির COGS) আর কারখানার শাখার বেতনে দুবার আসে। On = শাখার P&L-এ কারখানার বেতন থেকে ওই মাসে পণ্যের খরচে ধরা শ্রমের পরিমাণ বাদ যায় (বেতনের বেশি নয়)।',
  'Off (default) = as today: labour appears in product cost (COGS where sold) and again as the factory branch salary. On = the branch P&L takes from the factory salary the labour absorbed into product cost that month (never more than the salary).', 761)
on conflict (key) do nothing;

alter table public.cost_component_types add column if not exists gl_key117 text;
alter table public.cost_component_types add column if not exists gl_post117 boolean not null default true;
update public.cost_component_types set gl_key117 = case code when 'labour' then 'pool_exp_labour' when 'gas' then 'pool_exp_utilities' when 'electricity' then 'pool_exp_utilities'
    when 'factory_rent' then 'pool_exp_rent' when 'machine_repair' then 'pool_exp_repair' when 'licence_fee' then 'pool_exp_other' when 'other' then 'pool_exp_other' end
  where builtin and gl_key117 is null and code <> 'depreciation';
update public.cost_component_types set gl_post117 = false where code = 'depreciation' and gl_key117 is null;
update public.cost_component_types set gl_key117 = 'pool_exp_other' where not builtin and gl_key117 is null;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.bn, v.en from (values
  ('pool_exp_labour', '5200', 'কারখানার শ্রম খরচ (পুল)', 'Factory labour cost (pool)'),
  ('pool_exp_utilities', '5400', 'কারখানার গ্যাস / বিদ্যুৎ (পুল)', 'Factory gas / electricity (pool)'),
  ('pool_exp_rent', '5300', 'কারখানার ভাড়া (পুল)', 'Factory rent (pool)'),
  ('pool_exp_repair', '5600', 'কারখানার যন্ত্র মেরামত (পুল)', 'Factory machine repair (pool)'),
  ('pool_exp_other', '5900', 'কারখানার অন্যান্য খরচ (পুল)', 'Other factory cost (pool)'),
  ('pool_accrued', '2400', 'কারখানার খরচের দেনা (পুল)', 'Factory cost payable (pool)')) v(k, code, bn, en)
join public.coa_accounts a on a.code = v.code
on conflict (key) do nothing;

create table if not exists public.pool_gl_posts117 (
  id bigserial primary key,
  pool_id bigint not null references public.factory_cost_pools(id),
  month date not null check (month = date_trunc('month', month::timestamp)::date),
  amount numeric not null check (amount > 0),
  version int not null default 1,
  entry_id bigint not null references public.journal_entries(id),
  reversal_id bigint references public.journal_entries(id),
  created_by uuid, created_at timestamptz not null default now(),
  unique (pool_id, month, version)
);
drop trigger if exists pgp117_no_delete on public.pool_gl_posts117;
create trigger pgp117_no_delete before delete on public.pool_gl_posts117 for each row execute function public.no_hard_delete();
drop trigger if exists audit_pgp117 on public.pool_gl_posts117;
create trigger audit_pgp117 after insert or update on public.pool_gl_posts117 for each row execute function public.log_change('id');
alter table public.pool_gl_posts117 enable row level security;
drop policy if exists pgp117_read on public.pool_gl_posts117;      -- no browser SELECT (cost secrecy): read through pool_vs_gl117 only
revoke all on public.pool_gl_posts117 from anon, authenticated;
revoke all on sequence public.pool_gl_posts117_id_seq from anon, authenticated;
CREATE OR REPLACE FUNCTION public.pool_set(p_loc integer, p_month date, p_type text, p_amount numeric, p_period_kind text DEFAULT 'month'::text, p_one_off boolean DEFAULT false, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month); alloc boolean;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.factory_cost_pools where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  perform public.lock_check(m);
  update public.factory_cost_pools set active = false where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'manual' and active;
  insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, note, client_id, created_by)
    values (p_loc, m, p_type, p_period_kind, p_amount, coalesce(p_one_off, false), 'manual', left(p_note, 200), p_client, auth.uid()) returning id into nid;
  alloc := exists (select 1 from public.factory_cost_pools where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'allocated' and active);      -- bos75
  if alloc then
    perform public._stock_exc(p_loc, 'pool_double_entry', 'yellow', 'এই মাসের এই খরচ বিল থেকে আগেই এসেছে — হাতে আবার লিখলে দুবার গোনা হবে',
      'A cost bill already feeds this pool - a manual amount on top is counted twice', null, m, 'STOCK');
  end if;
  if public.rule_on('pool_gl_post117') then      -- bos117: the typed pool also becomes the expense in the books (the matching Dr for the Cr 5950 absorbed)
    begin perform public._pool_gl_sync117(p_loc, m);
    exception when others then
      perform public._stock_exc(p_loc, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, m, 'STOCK');
    end;
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $function$;

CREATE OR REPLACE FUNCTION public._cs_push_pools(p_bill bigint)
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
end $function$;

CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ag as (  -- bos72: stock-ledger cost of what was sold (item_costs only as fallback), returns subtracted with their discount share
    select date_trunc('month', h.d)::date as m, h.loc as location_id,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as cr,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cg
    from public._cogs_lines72(d1, d2, locs) h group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)) u group by 1, 2),
  sa0 as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0), 2), round(coalesce(a.cg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$;

-- ---------- the mirror of the pool in the books ----------
-- internal: post / reverse the pool rows of ONE place and month. Needs the switch, accounting on and a start date; nothing is posted into a closed period (reported as skipped).
create or replace function public._pool_gl_sync117(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._m1(p_month); st date := public._acct_start(); today_ date := public._acct_today(); edate date; r record; ent bigint; rev bigint; ver int; amt numeric; nposted int := 0; nrev int := 0; tot numeric := 0; skipped jsonb := '[]'::jsonb;
begin
  if not public.rule_on('pool_gl_post117') or not public.rule_on('accounting_on') or st is null then return jsonb_build_object('off', true); end if;
  edate := least((m + interval '1 month')::date - 1, today_);
  -- 1. a posting whose pool row was retired (typed again, bill voided) is reversed
  for r in select p.* from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id
            where f.location_id = p_loc and p.month = m and p.reversal_id is null and not f.active order by p.id loop
    if public._acct_locked(today_) then skipped := skipped || jsonb_build_object('pool_id', r.pool_id, 'why', 'period_closed'); continue; end if;
    rev := public._acct_reverse(r.entry_id, today_, 'Reversal: factory cost row retired');
    update public.pool_gl_posts117 set reversal_id = rev where id = r.id;
    nrev := nrev + 1;
  end loop;
  -- 2. an active pool row that covers this month and has no live posting yet
  for r in select f.*, t.gl_key117 k, t.gl_post117 gp from public.factory_cost_pools f join public.cost_component_types t on t.code = f.component_type
            where f.active and f.location_id = p_loc
              and ((f.period_kind = 'month' and f.month = m) or (f.period_kind = 'year' and m >= f.month and m < (f.month + interval '12 months')::date))
              and not exists (select 1 from public.pool_gl_posts117 p where p.pool_id = f.id and p.month = m and p.reversal_id is null) order by f.id loop
    if not r.gp or r.k is null then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'type_not_posted'); continue; end if;
    amt := round(case when r.period_kind = 'month' then r.actual_amount else r.actual_amount / 12 end, 2);
    if amt < 0.005 then continue; end if;
    if edate < st then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'before_start'); continue; end if;
    if public._acct_locked(edate) then skipped := skipped || jsonb_build_object('pool_id', r.id, 'why', 'period_closed'); continue; end if;
    select coalesce(max(version), 0) + 1 into ver from public.pool_gl_posts117 p where p.pool_id = r.id and p.month = m;
    ent := public._acct_write(edate, p_loc, 'pool_gl117', r.id::text || ':' || to_char(m, 'YYYY-MM') || ':' || ver::text, null,
      'Factory cost ' || r.component_type || ' ' || to_char(m, 'YYYY-MM'), null,
      public._acct_resolve(jsonb_build_array(jsonb_build_object('a', r.k, 'd', amt), jsonb_build_object('a', 'pool_accrued', 'c', amt)), p_loc));
    insert into public.pool_gl_posts117 (pool_id, month, amount, version, entry_id, created_by) values (r.id, m, amt, ver, ent, auth.uid());
    nposted := nposted + 1; tot := tot + amt;
  end loop;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'posted', nposted, 'reversed', nrev, 'total', round(tot, 2), 'skipped', skipped);
end $$;

-- catch-up / manual run for the people who manage the accounts (also for months where a yearly row now applies)
create or replace function public.pool_gl_sync117(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not public.rule_on('pool_gl_post117') then raise exception 'switch_off: pool_gl_post117'; end if;
  perform pg_advisory_xact_lock(hashtextextended('acct_post', 0));
  return public._pool_gl_sync117(p_loc, p_month);
end $$;

create or replace function public._pool_gl_after_bill117(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; sh record;
begin
  if not public.rule_on('pool_gl_post117') then return; end if;
  select * into b from public.cost_source_bills where id = p_bill;
  if not found then return; end if;
  for sh in select distinct f.location_id from public.factory_cost_pools f where f.source = 'allocated' and f.ref like 'bill:' || p_bill::text || ':%' loop
    begin perform public._pool_gl_sync117(sh.location_id, b.period_month);
    exception when others then
      perform public._stock_exc(sh.location_id, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, b.period_month, 'STOCK');
    end;
  end loop;
end $$;

-- cost type -> expense mapping key / posted or not (owner). Keys come from the chart mappings (acct_mapping_set can point a key to another account).
create or replace function public.cost_type_gl_set117(p_code text, p_key text, p_post boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_key is not null and not exists (select 1 from public.acct_mappings where key = p_key) then raise exception 'mapping_missing:%', p_key; end if;
  update public.cost_component_types set gl_key117 = p_key, gl_post117 = coalesce(p_post, true) where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- A1 G2: is the pool honest against the books? One place, one month.
--   pool_total      = the month's pool (yearly rows / 12)
--   posted_total    = what pool_gl117 entries put into expense for the month (switch pool_gl_post117)
--   absorbed_gl     = what production / re-price entries credited to 5950 at this place in the month
--   expense_gl      = expense accounts (without cost of goods, wastage and 5950) debited at this place in the month, pool postings included
--   absorbed_exceeds_expense = true when more was absorbed into products than any expense in the books explains (profit overstated by that much)
create or replace function public.pool_vs_gl117(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); me date; ptot numeric := 0; posted numeric; absorbed numeric; exp_all numeric; exp_pool numeric; rows_ jsonb := '[]'::jsonb; t record; pm numeric; pp numeric;
begin
  if not (public._acct_view() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  me := (m + interval '1 month')::date - 1;
  for t in select c.code, c.label_en, c.gl_key117, c.gl_post117 from public.cost_component_types c where c.active order by c.code loop
    pm := public._pool_month_actual(p_loc, m, t.code);
    select coalesce(sum(p.amount), 0) into pp from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id where f.location_id = p_loc and p.month = m and p.reversal_id is null and f.component_type = t.code;
    if pm is null and pp = 0 then continue; end if;
    ptot := ptot + coalesce(pm, 0);
    rows_ := rows_ || jsonb_build_object('type', t.code, 'label_en', t.label_en, 'pool', round(pm, 2), 'posted', round(pp, 2), 'mapping_key', t.gl_key117, 'posted_to_gl_type', t.gl_post117);
  end loop;
  select coalesce(sum(p.amount), 0) into posted from public.pool_gl_posts117 p join public.factory_cost_pools f on f.id = p.pool_id where f.location_id = p_loc and p.month = m and p.reversal_id is null;
  select coalesce(sum(l.credit - l.debit), 0) into absorbed from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
    where a.code = '5950' and e.entry_date between m and me and coalesce(l.location_id, e.location_id) = p_loc;
  select coalesce(sum(l.debit - l.credit), 0), coalesce(sum(l.debit - l.credit) filter (where e.source_type = 'pool_gl117'), 0) into exp_all, exp_pool
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
    where a.type = 'expense' and a.code not like '50%' and a.code not like '51%' and a.code <> '5950' and e.entry_date between m and me and coalesce(l.location_id, e.location_id) = p_loc;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'rows', rows_, 'pool_total', round(ptot, 2), 'posted_total', round(posted, 2), 'absorbed_gl', round(absorbed, 2),
    'expense_gl', round(exp_all, 2), 'expense_gl_from_pool', round(exp_pool, 2), 'expense_gl_other', round(exp_all - exp_pool, 2),
    'absorbed_exceeds_expense', absorbed > exp_all + 0.005,
    'unabsorbed_in_pnl', round(exp_all - absorbed, 2),
    'note', 'absorbed_exceeds_expense = true: products were charged overhead for which no expense is in the books (turn pool_gl_post117 on, or enter the cost as an expense). Expense of other kinds at this place is included in expense_gl.');
end $$;

-- the old true-up (report only) plus what really reached the books
create or replace function public.overhead_trueup117(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare tu jsonb; g jsonb; over_ jsonb;
begin
  tu := public.overhead_trueup(p_loc, p_month);
  g := public.pool_vs_gl117(p_loc, p_month);
  over_ := coalesce((select jsonb_agg(jsonb_build_object('type', x->>'type', 'over_absorbed', round(-(x->>'unabsorbed')::numeric, 2)))
                       from jsonb_array_elements(tu->'rows') x where (x->>'unabsorbed') is not null and (x->>'unabsorbed')::numeric < 0), '[]'::jsonb);
  return tu || jsonb_build_object('gl', g, 'over_absorbed_types', over_,
    'note_gl', 'unabsorbed overhead is an expense of the month only when the pool is in the books (pool_gl_post117) or the cost was entered as an expense. Over-absorbed types stay in stock value until a re-price.');
end $$;

revoke all on function public._pool_gl_sync117(int, date), public._pool_gl_after_bill117(bigint) from public, anon, authenticated;
revoke all on function public.pool_gl_sync117(int, date), public.cost_type_gl_set117(text, text, boolean), public.pool_vs_gl117(int, date), public.overhead_trueup117(int, date) from public, anon;
grant execute on function public.pool_gl_sync117(int, date), public.cost_type_gl_set117(text, text, boolean), public.pool_vs_gl117(int, date), public.overhead_trueup117(int, date) to authenticated;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('pool_gl_post117', '117', 'accounts', null::jsonb, '{}'::text[],
  'পুল মোডে উৎপাদন হলে খাতায় "ওভারহেড শোষিত" জমা হয়, কিন্তু পুল নিজে খাতায় খরচ হিসেবে ওঠে না। কারখানার বিদ্যুৎ / গ্যাস / ভাড়া / শ্রম যদি আলাদা expense বা বেতন হিসেবে না লিখে থাকেন, তবে এটি চালু করুন; লিখে থাকলে বন্ধ রাখুন, নইলে দুবার গোনা হবে।',
  'Pool mode-এ production হলে খাতায় overhead absorbed জমা হয়, কিন্তু pool নিজে খাতায় expense হিসেবে ওঠে না। Factory-র বিদ্যুৎ / গ্যাস / ভাড়া / শ্রম যদি আলাদা expense বা বেতন হিসেবে না লিখে থাকেন, তবে এটি চালু করুন; লিখে থাকলে off রাখুন, নইলে double গোনা হবে।',
  'In pool mode production credits overhead absorbed, but the pool itself is not an expense in the books. Switch on if you do NOT also enter the factory electricity, gas, rent and labour as expenses or payroll; keep off if you do, or they are counted twice. It depends on how you enter those costs, so no value is recommended.', 367),
 ('factory_labour_absorbed117', '117', 'accounts', null::jsonb, '{}'::text[],
  'কারখানার শ্রম পণ্যের খরচে ধরা হলে একই টাকা কারখানার শাখার বেতন হিসেবেও দেখায়। চালু করলে শাখার লাভ-ক্ষতিতে পণ্যের খরচে ধরা অংশ বেতন থেকে বাদ যায়। আপনি রেসিপি / পুলে শ্রম ধরলে তবেই চালু করুন।',
  'Factory labour product cost-এ ধরা হলে একই টাকা factory branch-এর salary হিসেবেও দেখায়। চালু করলে branch P&L-এ product cost-এ ধরা অংশ salary থেকে বাদ যায়। আপনি recipe / pool-এ labour ধরলে তবেই চালু করুন।',
  'When factory labour is charged into product cost the same money also shows as the factory branch salary. Switch on to take the absorbed part out of that salary in the branch P&L. Use it only if you charge labour in recipes or pools.', 368)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
on conflict (code) do nothing;

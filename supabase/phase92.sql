-- Phase 92 (bos92) - ONE PROFIT NUMBER (UNIFIED_BUILD_PLAN U-05, package W1-D). Paste after phase87, paste-twice safe. Earlier phase files are not edited.
-- WHY: the management profit (the _p27_pl extraction that feeds the branch P&L L1/L3, the owner sheet L4, break-even L5, the staff-cost ratio, partner_calculate and the owner board)
--      leaves out wastage, count shrinkage, transit loss, cash short and operating cost that was paid by a supplier bill, and it counts factory overhead twice when conversion costing
--      is on (the overhead is in the expenses AND inside the cost of the goods sold). The journal has most of these. Two different profits are two different truths.
-- WHAT THIS FILE DOES (everything is OFF by default; with every setting at its default NO historic figure changes - proved by tests/sql/w1d_before_after.sh)
--   1. Settings (owner, any time, every change is written to audit_log by the existing rules trigger):
--        profit_one_number_on      master switch, default OFF      count the extra rows below in the management profit
--        profit_losses_from        date, default blank             count the extra rows only from this date (blank = every date)
--        profit_loss_wastage / profit_loss_count / profit_loss_transit / profit_loss_cashshort / profit_loss_billopex / profit_overhead_once   one switch per row, default ON (they act only while the master is ON)
--        profit_source             management (default) | ledger  where partner shares take their profit from (acts only while the master is ON)
--   2. _w1d_pl_rows / _w1d_pl_extra: the extra rows by month and place. _p27_pl gets ONE more union (text patch, marker bos92) so ONE function feeds L1, L3, L4, L5, T4,
--      partner_calculate and (through a one-line patch) the partner preview c_partner_month_split. Wastage = stock-ledger cost; count shrinkage = negative count_adjust at ledger cost;
--      transit loss = written-off events of phase81; cash short = approved cases (a short booked as staff receivable is not a loss); supplier-bill opex = the consumable / unclassified
--      part of posted purchase bills; absorbed overhead = conversion cost of finished production runs, SUBTRACTED from the expenses (it is already inside the cost of goods).
--   3. Exception path (needs a written reason, writes audit_log and one yellow line in the Exceptions list): profit_exclude / profit_exclusion_revoke leave ONE named loss out of the management profit.
--   4. profit_recon(from, to, place): management profit versus journal profit, the difference by named cause, and what is still unexplained. profit_exclusions_list().
--   5. Every partner settlement stores the basis it used: partner_calculate returns profit_basis (stored in the settlement calc).
-- NOT DONE (listed in docs/integration/W1-D.md): the ledger source feeds partner shares only (not L1/L3); count surplus is not valued (the ledger row has no cost).
-- !! Re-pasting phase 27, 44, 50, 72, 82, 85 or 86 removes the bos92 patches: paste this file again. The integrator's last phase of the wave must paste it again too.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase92 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public.partner_calculate(bigint,date,date,jsonb)') is null
     or to_regprocedure('public.c_partner_month_split(date)') is null or to_regprocedure('public._d_wallet_fee_rows(date,date,integer[])') is null
     or to_regprocedure('public._acct_purchase_alloc(uuid)') is null or to_regclass('public.shortage_transit_events') is null or to_regclass('public.shortage_cash_cases') is null
     or to_regclass('public.production_runs') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null then
    raise exception 'phase92 needs the shared functions and tables of phases 10, 27, 44, 52, 72, 74, 81, 82, 83';
  end if;
end $g$;

create or replace function public._w1d_p92_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (the phase87 _m_patch idea with the package's own marker) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist, otherwise the paste STOPS and nothing is half changed. Already patched (marker present) = no-op.
create or replace function public._w1d_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2}$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception '% patch site not found in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- settings (rules). Labels are English only (owner rule 5). All defaults keep today's behaviour. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_one_number_on', 'reports', 'switch', 'false', null, null, null, null,
  'One profit number: count losses in the profit', 'One profit number: count losses in the profit', 'One profit number: count losses in the profit',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.', 790),
 ('profit_losses_from', 'reports', 'text', null, null, null, null, null,
  'Count these extra profit rows from this date', 'Count these extra profit rows from this date', 'Count these extra profit rows from this date',
  'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.', 'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.',
  'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.', 791),
 ('profit_loss_wastage', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts wasted stock', 'Profit counts wasted stock', 'Profit counts wasted stock',
  'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.', 'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.',
  'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.', 792),
 ('profit_loss_count', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts stock count shortages', 'Profit counts stock count shortages', 'Profit counts stock count shortages',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.', 793),
 ('profit_loss_transit', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts goods lost in transit', 'Profit counts goods lost in transit', 'Profit counts goods lost in transit',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.', 794),
 ('profit_loss_cashshort', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts cash short and over', 'Profit counts cash short and over', 'Profit counts cash short and over',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.', 795),
 ('profit_loss_billopex', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts running costs paid by supplier bill', 'Profit counts running costs paid by supplier bill', 'Profit counts running costs paid by supplier bill',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.', 796),
 ('profit_overhead_once', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts factory overhead once', 'Profit counts factory overhead once', 'Profit counts factory overhead once',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.', 797),
 ('profit_source', 'reports', 'choice', '"management"', null, '["management","ledger"]', null, null,
  'Partner shares take the profit from', 'Partner shares take the profit from', 'Partner shares take the profit from',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.', 798)
on conflict (key) do nothing;

-- ---------- the exception path: leave ONE named loss out of the management profit (reason required, audit_log, Exceptions list) ----------
create table if not exists public.profit_row_exclusions (
  id bigserial primary key,
  cause text not null check (cause in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed')),
  source_id text not null check (length(source_id) between 1 and 80),
  amount numeric, row_date date, location_id integer,
  reason text not null check (length(btrim(reason)) between 5 and 300),
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoke_reason text check (revoke_reason is null or length(btrim(revoke_reason)) between 5 and 300)
);
create unique index if not exists profit_row_exclusions_one on public.profit_row_exclusions (cause, source_id) where status = 'active';
drop trigger if exists profit_row_exclusions_nodel on public.profit_row_exclusions;
create trigger profit_row_exclusions_nodel before delete on public.profit_row_exclusions for each row execute function public.no_hard_delete();
drop trigger if exists audit_profit_row_exclusions on public.profit_row_exclusions;
create trigger audit_profit_row_exclusions after insert or update on public.profit_row_exclusions for each row execute function public.log_change('id');
alter table public.profit_row_exclusions enable row level security;
revoke all on public.profit_row_exclusions from public, anon, authenticated;

create or replace function public._w1d_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;
create or replace function public._w1d_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
drop policy if exists profit_row_exclusions_read on public.profit_row_exclusions;
create policy profit_row_exclusions_read on public.profit_row_exclusions for select to authenticated using (public._w1d_view());
grant select on public.profit_row_exclusions to authenticated;
grant execute on function public._w1d_view(), public._w1d_mgr() to authenticated;

-- ---------- the extra rows ----------
create or replace function public._w1d_losses_from() returns date language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('profit_losses_from');
begin
  if t is null or t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

-- every candidate row, no setting looked at. amt: a LOSS is positive, absorbed overhead is negative (it lowers the expenses).
create or replace function public._w1d_pl_rows(d1 date, d2 date, locs integer[])
returns table (cause text, source_id text, d date, loc integer, amt numeric)
language sql stable security definer set search_path = public as $$
  -- wastage: stock leaves at its ledger cost (cost 0 or empty = unknown, never guessed; same rule as the journal source 'wastage')
  select 'wastage'::text, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date, l.location_id, round(-l.qty_delta * l.unit_cost, 2)
    from public.stock_ledger l
   where l.ref_type = 'wastage' and l.reason = 'wastage' and l.qty_delta < 0 and coalesce(l.unit_cost, 0) > 0
     and not exists (select 1 from public.stock_ledger r where r.reverses_id = l.id)
     and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  -- count shrinkage: a physical count found less than the book. A surplus carries no cost on its ledger row, so it is not valued.
  select 'count_shrink'::text, l.id::text, (l.made_at at time zone 'Asia/Dhaka')::date, l.location_id, round(-l.qty_delta * l.unit_cost, 2)
    from public.stock_ledger l
   where l.reason = 'count_adjust' and l.qty_delta < 0 and coalesce(l.unit_cost, 0) > 0
     and not exists (select 1 from public.stock_ledger r where r.reverses_id = l.id)
     and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  -- transit loss: only the written-off events (a claim to the carrier is a receivable, not a loss)
  select 'transit_loss'::text, e.id::text, e.event_date, e.location_id, e.amount
    from public.shortage_transit_events e
   where e.kind = 'writeoff' and e.event_date between d1 and d2 and e.location_id = any (locs)
  union all
  -- cash short (+) / over (-): approved cases; a short booked as a staff receivable is not a loss
  select 'cash_short'::text, c.id::text, c.case_date, c.location_id,
         case when c.amount < 0 and coalesce(c.treatment, 'expense') = 'staff_receivable' then 0 else -c.amount end
    from public.shortage_cash_cases c
   where c.status = 'approved' and c.case_date between d1 and d2 and c.location_id = any (locs)
  union all
  -- running cost paid by supplier bill: the part of a posted bill that the journal books on an expense account (consumable or unclassified); a purchase return is negative
  select 'bill_opex'::text, b.id::text, b.bill_date, b.location_id, (case when b.kind = 'return' then -1 else 1 end) * a.amt
    from public.purchase_bills b
    cross join lateral (select coalesce(sum(al.amt), 0) as amt from public._acct_purchase_alloc(b.id) al where al.k in ('purch_consumable', 'purch_unclassified')) a
   where b.status = 'posted' and b.total > 0 and a.amt <> 0 and b.bill_date between d1 and d2 and b.location_id = any (locs)
  union all
  -- absorbed overhead: conversion cost that finished-goods costing already carries (it comes back through the cost of goods sold), so the expenses must lose it
  select 'overhead_absorbed'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, -round(r.conversion_cost, 2)
    from public.production_runs r
   where r.status = 'done' and coalesce(r.conversion_cost, 0) >= 0.005
     and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs);
$$;

create or replace function public._w1d_cause_on(p_cause text) returns boolean language sql stable security definer set search_path = public as $$
  select case p_cause
    when 'wastage' then public.rule_on('profit_loss_wastage') when 'count_shrink' then public.rule_on('profit_loss_count')
    when 'transit_loss' then public.rule_on('profit_loss_transit') when 'cash_short' then public.rule_on('profit_loss_cashshort')
    when 'bill_opex' then public.rule_on('profit_loss_billopex') when 'overhead_absorbed' then public.rule_on('profit_overhead_once') else false end $$;

-- the rows that count NOW: master on, the cause on, date from the start date, and not an excluded row
create or replace function public._w1d_pl_rows_on(d1 date, d2 date, locs integer[])
returns table (cause text, source_id text, d date, loc integer, amt numeric)
language plpgsql stable security definer set search_path = public as $$
declare f date;
begin
  if not public.rule_on('profit_one_number_on') then return; end if;
  f := public._w1d_losses_from();
  return query
    select r.cause, r.source_id, r.d, r.loc, r.amt from public._w1d_pl_rows(greatest(d1, coalesce(f, d1)), d2, locs) r
     where public._w1d_cause_on(r.cause)
       and not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active');
end $$;

-- month x place amounts for _p27_pl (zero rows while the master switch is off)
create or replace function public._w1d_pl_extra(d1 date, d2 date, locs integer[]) returns table (m date, loc integer, amt numeric)
language sql stable security definer set search_path = public as $$
  select date_trunc('month', r.d)::date, r.loc, sum(r.amt) from public._w1d_pl_rows_on(d1, d2, locs) r group by 1, 2 $$;

-- ---------- ONE profit function: the management profit for a period and a set of places (same formula as partner_calculate) ----------
create or replace function public._w1d_mgmt_profit(d1 date, d2 date, locs integer[]) returns numeric language sql stable security definer set search_path = public as $$
  select case when abs(z.ns - z.costed) <= greatest(1, abs(z.ns) * 0.001) then round(round(z.ns - z.cg, 2) - z.ex - z.sal - z.fix, 2) end
    from (select coalesce(sum(o_net), 0) ns, coalesce(sum(o_costed), 0) costed, coalesce(sum(o_cogs), 0) cg, coalesce(sum(o_exp), 0) ex, coalesce(sum(o_sal), 0) sal, coalesce(sum(o_fixed), 0) fix
            from public._p27_pl(d1, d2, locs)) z $$;

-- the journal profit (income minus expense accounts, from the accounting start date); null when accounting has not started
create or replace function public._w1d_ledger_profit(d1 date, d2 date, p_loc integer) returns numeric language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v numeric;
begin
  if st is null or d2 < st then return null; end if;
  select coalesce(sum(l.credit - l.debit), 0) into v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
   where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(d1, st) and d2 and (p_loc is null or l.location_id = p_loc);
  return round(v, 2);
end $$;

-- partner_calculate: the profit override. null = nothing to override (master off or source management). Else {source, net_profit (null = journal unavailable), note}
create or replace function public._w1d_profit_override(d1 date, d2 date, p_loc integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v numeric;
begin
  if not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') <> 'ledger' then return null; end if;
  v := public._w1d_ledger_profit(d1, d2, p_loc);
  return jsonb_build_object('source', 'ledger', 'net_profit', v, 'note', case when v is null then 'The journal has no data for this period (accounting not started): the management profit was used.' end);
end $$;

-- the basis written into every partner settlement calc
create or replace function public._w1d_profit_basis(d1 date, d2 date, locs integer[], lj jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ex jsonb := '{}'::jsonb; c record;
begin
  if locs is not null and public.rule_on('profit_one_number_on') and not (lj is not null and lj ->> 'net_profit' is not null) then
    for c in select r.cause, round(sum(r.amt), 2) amt from public._w1d_pl_rows_on(d1, d2, locs) r group by 1 loop ex := ex || jsonb_build_object(c.cause, c.amt); end loop;
  end if;
  return jsonb_build_object('one_number', public.rule_on('profit_one_number_on'),
    'source', case when locs is null then 'manual' when lj is not null and lj ->> 'net_profit' is not null then 'ledger' else 'management' end,
    'losses_from', public._w1d_losses_from(), 'extra_rows', ex, 'note', lj ->> 'note');
end $$;

-- c_partner_month_split: the base of the preview. null = keep today's journal figure.
create or replace function public._w1d_split_base(d1 date, d2 date, p_loc integer) returns numeric language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') = 'ledger' then null
              else public._w1d_mgmt_profit(d1, d2, case when p_loc is null then array(select id from public.locations) else array[p_loc] end) end $$;
create or replace function public._w1d_split_basis() returns text language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') = 'ledger' then null
              else 'management profit of the month (one profit number: net sales, cost of goods, expenses, salary, fixed cost and the counted losses)' end $$;

-- ============================================================================
-- PATCHES (text patch of the LIVE definition; a missing site stops the paste; marker bos92)
-- ============================================================================
-- _p27_pl: one more union in the expenses, zero rows while the master switch is off
select public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos92', array[
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),$a$,
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),$a$]);

-- partner_calculate: ledger source (only while the master is on and profit_source = ledger) and the basis stored with the settlement
select public._w1d_patch('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure, 'bos92', array[
  $a$ag public.partner_agreements; vn public.partner_ventures;$a$, $a$ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;$a$,
  $a$'warnings', warns, 'wrote', false);$a$, $a$'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);$a$]);

-- c_partner_month_split: the preview uses the same profit as the settlement (while the master is on and the source is management)
select public._w1d_patch('public.c_partner_month_split(date)'::regprocedure, 'bos92', array[
  $a$base := (prof ->> 'net_profit')::numeric;$a$,
  $a$base := coalesce(public._w1d_split_base(greatest(m, st), me, case when a.scope = 'location' then a.location_id end), (prof ->> 'net_profit')::numeric);   /* bos92 */$a$,
  $a$'basis', 'journal net profit of the month (salary accrual included)'$a$, $a$'basis', coalesce(public._w1d_split_basis(), 'journal net profit of the month (salary accrual included)')$a$]);

-- ============================================================================
-- API (security definer, the server decides)
-- ============================================================================
create or replace function public.profit_exclude(p_cause text, p_source_id text, p_reason text) returns bigint language plpgsql security definer set search_path = public as $$
declare r record; id_ bigint; why text := btrim(coalesce(p_reason, '')); amt_ numeric;
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if p_cause is null or p_cause not in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed') then raise exception 'bad_cause'; end if;
  if length(why) < 5 then raise exception 'reason_required'; end if;
  if length(why) > 300 then raise exception 'too_long'; end if;
  select min(x.d) d, min(x.loc) loc, sum(x.amt) amt, count(*) n into r
    from public._w1d_pl_rows(date '2000-01-01', date '2100-01-01', array(select l.id from public.locations l where public.can_loc(l.id))) x where x.cause = p_cause and x.source_id = p_source_id;
  if r.n = 0 then raise exception 'row_not_found'; end if;
  if exists (select 1 from public.profit_row_exclusions where cause = p_cause and source_id = p_source_id and status = 'active') then raise exception 'already_excluded'; end if;
  amt_ := round(r.amt, 2);
  insert into public.profit_row_exclusions (cause, source_id, amount, row_date, location_id, reason) values (p_cause, p_source_id, amt_, r.d, r.loc, why) returning id into id_;
  perform public._stock_exc(r.loc, 'profit_row_excluded', 'yellow', 'Left out of profit by the owner: ' || p_cause || ' ' || amt_::text || ' (' || why || ')',
                            'Left out of profit by the owner: ' || p_cause || ' ' || amt_::text || ' (' || why || ')', null, r.d, 'PROFIT', amt_);
  return id_;
end $$;

create or replace function public.profit_exclusion_revoke(p_id bigint, p_reason text) returns boolean language plpgsql security definer set search_path = public as $$
declare x public.profit_row_exclusions; why text := btrim(coalesce(p_reason, ''));
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if length(why) < 5 then raise exception 'reason_required'; end if;
  select * into x from public.profit_row_exclusions where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if x.status <> 'active' then raise exception 'not_active'; end if;
  update public.profit_row_exclusions set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoke_reason = left(why, 300) where id = p_id;
  perform public._stock_exc(x.location_id, 'profit_row_exclusion_revoked', 'yellow', 'Loss counted in profit again: ' || x.cause || ' ' || coalesce(x.amount::text, '') || ' (' || why || ')',
                            'Loss counted in profit again: ' || x.cause || ' ' || coalesce(x.amount::text, '') || ' (' || why || ')', null, x.row_date, 'PROFIT', x.amount);
  return true;
end $$;

create or replace function public.profit_exclusions_list(p_status text default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'cause', x.cause, 'source_id', x.source_id, 'amount', x.amount, 'row_date', x.row_date, 'location_id', x.location_id,
           'reason', x.reason, 'status', x.status, 'created_at', x.created_at, 'revoked_at', x.revoked_at, 'revoke_reason', x.revoke_reason) order by x.id desc)
    from public.profit_row_exclusions x where p_status is null or x.status = p_status), '[]'::jsonb);
end $$;

-- ---------- profit_recon: management versus journal, the difference by named cause ----------
create or replace function public.profit_recon(p_from date, p_to date, p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  locs int[]; st date := public._acct_start(); f date := public._w1d_losses_from();
  ns numeric; cg numeric; ex_ numeric; sal numeric; fix numeric; wf numeric; xt numeric; mg numeric; lg numeric;
  rows_ jsonb := '[]'::jsonb; k text; mval numeric; lval numeric; df numeric; why text; unposted bigint := 0; explained numeric := 0; unexplained numeric := 0; nex int;
  m_on boolean := public.rule_on('profit_one_number_on'); cand jsonb := '{}'::jsonb; c record; lab text;
  keys text[] := array['sales', 'cogs', 'vouchers', 'wallet_fee', 'salary', 'fixed_cost', 'wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed', 'other'];
  mg_by jsonb := '{}'::jsonb; lg_by jsonb := '{}'::jsonb;
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  -- management side (as the settings are now)
  select coalesce(sum(o_net), 0), coalesce(sum(o_cogs), 0), coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0), coalesce(sum(o_fixed), 0) into ns, cg, ex_, sal, fix from public._p27_pl(p_from, p_to, locs);
  select coalesce(sum(amount), 0) into wf from public._d_wallet_fee_rows(p_from, p_to, locs);
  select coalesce(sum(r.amt), 0) into xt from public._w1d_pl_rows_on(p_from, p_to, locs) r;
  mg := round(ns - cg - ex_ - sal - fix, 2);
  mg_by := jsonb_build_object('sales', ns, 'cogs', -cg, 'vouchers', -(ex_ - wf - xt), 'wallet_fee', -wf, 'salary', -sal, 'fixed_cost', -fix);
  for c in select r.cause, sum(r.amt) amt from public._w1d_pl_rows_on(p_from, p_to, locs) r group by 1 loop mg_by := mg_by || jsonb_build_object(c.cause, -c.amt); end loop;
  -- what each cause WOULD add when counted (ignores the switches, honours exclusions and the start date): lets the owner see the effect before switching on
  for c in select r.cause, round(sum(r.amt), 2) amt, count(*) n from public._w1d_pl_rows(greatest(p_from, coalesce(f, p_from)), p_to, locs) r
            where not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active') group by 1 loop
    cand := cand || jsonb_build_object(c.cause, jsonb_build_object('amount', c.amt, 'rows', c.n));
  end loop;
  -- ledger side (from the accounting start date)
  if st is not null and p_to >= st then
    select coalesce(jsonb_object_agg(g.grp, g.v), '{}'::jsonb) into lg_by from (
      select case when e.source_type in ('sale', 'sale_return') and a.type = 'income' then 'sales' when e.source_type in ('sale', 'sale_return') then 'cogs'
                  when e.source_type in ('expense_voucher', 'quick_expense') then 'vouchers' when e.source_type = 'd_wallet_fee' then 'wallet_fee'
                  when e.source_type in ('payroll_payment', 'payroll_accrual') then 'salary' when e.source_type = 'wastage' then 'wastage'
                  when e.source_type = 'transit_writeoff' then 'transit_loss' when e.source_type = 'cash_short' then 'cash_short'
                  when e.source_type = 'purchase' then 'bill_opex' when e.source_type = 'production' then 'overhead_absorbed' else 'other' end grp,
             round(sum(l.credit - l.debit), 2) v
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
       where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(p_from, st) and p_to
         and (l.location_id = any (locs) or (p_loc is null and l.location_id is null))
       group by 1) g;
    select coalesce(sum(v.value::numeric), 0) into lg from jsonb_each_text(lg_by) v;
    select count(*) into unposted from public._acct_docs(st) d
     where d.live and d.waiting is null and d.entry_date between greatest(p_from, st) and p_to and (d.location_id is null or d.location_id = any (locs))
       and not exists (select 1 from public.journal_entries je where je.source_type = d.source_type and je.source_id = d.source_id and je.reverses_id is null);
  end if;
  foreach k in array keys loop
    mval := coalesce((mg_by ->> k)::numeric, 0); lval := case when st is null or p_to < st then null else coalesce((lg_by ->> k)::numeric, 0) end;
    df := case when lval is null then null else round(mval - lval, 2) end; why := null;
    select count(*) into nex from public.profit_row_exclusions x where x.status = 'active' and x.cause = k and x.row_date between p_from and p_to and x.location_id = any (locs);
    if df is null then why := 'journal_not_started';
    elsif df <> 0 then
      why := case
        when nex > 0 and k in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed') then 'left_out_by_owner_exception'
        when k = 'fixed_cost' then 'fixed_cost_is_management_only'
        when k = 'count_shrink' then 'count_adjustment_not_in_journal_yet'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and not m_on then 'not_counted_in_management_profit_switch_off'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and not public._w1d_cause_on(k) then 'this_cause_is_switched_off'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and f is not null and f > p_from then 'before_the_start_date'
        when k = 'cash_short' and not public.rule_on('cash_short_post_on') then 'cash_short_not_posted_to_journal'
        when k = 'salary' then 'salary_basis_differs_forms_runs_or_payments'
        when k = 'vouchers' then 'voucher_status_basis_differs'
        when k = 'other' then 'journal_only_entries_manual_depreciation_charges_opening'
        when unposted > 0 then 'documents_not_posted_to_journal_yet'
        when st is not null and p_from < st then 'period_starts_before_accounting_start'
        else null end;
    end if;
    if df is not null and df <> 0 then if why is null then unexplained := unexplained + df; else explained := explained + df; end if; end if;
    lab := case k when 'sales' then 'Net sales' when 'cogs' then 'Cost of goods sold' when 'vouchers' then 'Expense vouchers and quick expenses' when 'wallet_fee' then 'Wallet fees'
                  when 'salary' then 'Salary' when 'fixed_cost' then 'Fixed cost (setting)' when 'wastage' then 'Wasted stock' when 'count_shrink' then 'Stock count shortage'
                  when 'transit_loss' then 'Goods lost in transit' when 'cash_short' then 'Cash short and over' when 'bill_opex' then 'Running cost paid by supplier bill'
                  when 'overhead_absorbed' then 'Factory overhead absorbed into products' else 'Other journal entries' end;
    rows_ := rows_ || jsonb_build_object('key', k, 'label_en', lab, 'management', mval, 'ledger', lval, 'difference', df, 'reason', why);
  end loop;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'one_number_on', m_on, 'profit_source', coalesce(public.rule_txt('profit_source'), 'management'), 'losses_from', f,
    'management_profit', mg, 'ledger_profit', case when st is null or p_to < st then null else lg end,
    'difference', case when st is null or p_to < st then null else round(mg - lg, 2) end, 'explained', round(explained, 2), 'unexplained', round(unexplained, 2),
    'unposted_documents', unposted, 'would_add_if_counted', cand, 'rows', rows_,
    'ledger_note', case when st is null then 'Accounting start date is not set: the journal has no figures.' when p_from < st then 'The period starts before the accounting start date: the journal counts only from that date.' end);
end $$;

-- ---------- rights: internals closed, API open to signed-in users (the function checks the person) ----------
revoke all on function public._w1d_patch(regprocedure, text, text[]), public._w1d_p92_present(), public._w1d_losses_from(), public._w1d_pl_rows(date, date, integer[]), public._w1d_cause_on(text),
  public._w1d_pl_rows_on(date, date, integer[]), public._w1d_pl_extra(date, date, integer[]), public._w1d_mgmt_profit(date, date, integer[]), public._w1d_ledger_profit(date, date, integer),
  public._w1d_profit_override(date, date, integer), public._w1d_profit_basis(date, date, integer[], jsonb), public._w1d_split_base(date, date, integer), public._w1d_split_basis() from public, anon, authenticated;
revoke all on function public.profit_exclude(text, text, text), public.profit_exclusion_revoke(bigint, text), public.profit_exclusions_list(text), public.profit_recon(date, date, integer) from public, anon;
grant execute on function public.profit_exclude(text, text, text), public.profit_exclusion_revoke(bigint, text), public.profit_exclusions_list(text), public.profit_recon(date, date, integer) to authenticated;

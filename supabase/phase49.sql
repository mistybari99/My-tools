-- ============================================================
-- Phase 49 - P1 slice 2: READ-ONLY reports (gap #15 + roadmap A1). Nothing is written, no existing record is touched.
-- Run AFTER phase48. Idempotent (create or replace).
--   daybook_vs_journal(from, to, loc)   per payment mode and per kind of money movement: what the day book shows vs what the journal holds,
--                                       with the difference. Owner or accounts_manage only; needs the accounting start date.
--   dup_suspects(from, to)              owner only. Rows that look like the same event keyed on two paths (payroll D1, stock D2, production D3,
--                                       owner money D4, cash handover D8). A suspect list to review one by one - NOT a verdict, nothing is changed.
-- ============================================================

create or replace function public.daybook_vs_journal(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); d1 date; locs int[]; rows jsonb; tot jsonb; own boolean := public.is_owner();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'why', 'accounting_start_date'); end if;
  d1 := greatest(p_from, st);
  select array_agg(l.id) into locs from public.locations l where (p_loc is null or l.id = p_loc) and (own or public.can_loc(l.id));
  if locs is null then raise exception 'not allowed'; end if;
  with db as (  -- the day book, internal hub lines kept apart, signed per mode (card settles to bank in the day book)
    select case when u.typ in ('bill', 'supplier') then 'supplier_payment' else u.typ end as k, u.mode, u.internal, case when u.dir = 'in' then u.amount else -u.amount end as s
      from (select * from public._daybook_lines(locs, locs, d1, p_to) union all select * from public._daybook_lines12(locs, d1, p_to) union all select * from public._daybook_lines23(locs, d1, p_to)) u
  ), jr as (    -- the journal: movement on the cash / bank / mobile accounts, by kind (cash_move keeps its own kind)
    select case je.source_type when 'cash_move' then coalesce(je.subtype, 'cash_move') when 'expense_voucher' then 'expense' when 'quick_expense' then 'expense' else je.source_type end as k,
           case when a.key = 'pay_cash' then 'cash' when a.key = 'pay_mobile' then 'mobile' else 'bank' end as mode, (jl.debit - jl.credit) as s
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')
     where je.entry_date between d1 and p_to and je.source_type <> 'opening' and (je.location_id is null or je.location_id = any (locs))
  ), kk as (
    select k, mode, sum(s) filter (where not internal) as dbs, sum(s) filter (where internal) as dbi, 0::numeric as js from db group by k, mode
    union all select k, mode, null, null, sum(s) from jr group by k, mode
  ), agg as (
    select k, mode, coalesce(sum(dbs), 0) as daybook, coalesce(sum(dbi), 0) as hub_internal, coalesce(sum(js), 0) as journal from kk group by k, mode
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', k, 'mode', mode, 'daybook', daybook, 'journal', journal, 'diff', daybook - journal, 'hub_internal', hub_internal) order by k, mode)
           filter (where abs(daybook - journal) > 0.004 or hub_internal <> 0), '[]'::jsonb),
         jsonb_build_object('daybook', coalesce(sum(daybook), 0), 'journal', coalesce(sum(journal), 0), 'diff', coalesce(sum(daybook - journal), 0),
           'kinds_checked', count(*), 'kinds_differing', count(*) filter (where abs(daybook - journal) > 0.004))
    into rows, tot from agg;
  return jsonb_build_object('from', d1, 'to', p_to, 'location_id', p_loc, 'accounting_start', st, 'rows', rows, 'total', tot,
    'note', 'Day book counts a 10-2 voucher when submitted, the journal only when approved; payroll payments and staff advances are in the day book but have no journal source until the auto-post slice. Reversals post on the day they are made.');
end $$;

create or replace function public.dup_suspects(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb));
end $$;

revoke all on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) from public, anon;
grant execute on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) to authenticated;
notify pgrst, 'reload schema';

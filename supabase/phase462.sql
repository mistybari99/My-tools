-- Phase 462 (RPT-C3, package R8 part 1) - AUDIT AND CONTROL: the audit log pager (#173) and the one register of voided, reversed and corrected records across every module (#182).
-- Paste AFTER phase458. Paste-twice safe. Read-only functions plus two indexes on audit_log (the table stays append-only; an index changes no row). No earlier phase file is edited.
--
--   aud_log_page      the append-only audit_log, newest first, filtered by dates / table / action / staff / text, paged (limit + offset) with the exact total. OWNER ONLY, like the
--                     audit_log table itself (its row-level policy is owner-only; this function does not widen it). CSV is built by the screen page by page; each export is logged.
--   aud_void_register every void, reversal and correction in one list: module, what, record date, WHEN it was voided (null where the module never stored the time - said so, not guessed),
--                     amount, who, reason, place. Nothing is hard-deleted anywhere, so this lists what the modules keep. Salary-related modules (payroll runs / payments, staff advances)
--                     appear only for the owner and holders of salary_view.
-- Access for the register: rpt_access('control') (owner, report_control or view_reports) and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p458_present()') is null then raise exception 'phase462 needs phase458 first'; end if;
end $g$;

create index if not exists audit_log_at on public.audit_log (at desc);
create index if not exists audit_log_table_at on public.audit_log (table_name, at desc);

-- ---------- #173 audit log pager (owner only) ----------
create or replace function public.aud_log_page(p_from date default null, p_to date default null, p_table text default null, p_action text default null, p_staff text default null,
                                               p_search text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 50), 1), 500); off_ int := greatest(coalesce(p_offset, 0), 0); tot bigint; rows_ jsonb; q text := nullif(btrim(coalesce(p_search, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'bad_range'; end if;
  if q is not null and length(q) > 80 then raise exception 'bad_search'; end if;
  select count(*) into tot from public.audit_log a
   where (p_from is null or (a.at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (a.at at time zone 'Asia/Dhaka')::date <= p_to)
     and (p_table is null or a.table_name = p_table) and (p_action is null or a.action = p_action) and (p_staff is null or a.staff_id = p_staff)
     and (q is null or a.record_id ilike '%' || q || '%' or a.detail::text ilike '%' || q || '%');
  select coalesce(jsonb_agg(to_jsonb(z) order by z.at desc, z.id desc), '[]'::jsonb) into rows_ from (
    select a.id, a.at, a.staff_id, a.user_id, a.action, a.table_name, a.record_id, a.detail from public.audit_log a
     where (p_from is null or (a.at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (a.at at time zone 'Asia/Dhaka')::date <= p_to)
       and (p_table is null or a.table_name = p_table) and (p_action is null or a.action = p_action) and (p_staff is null or a.staff_id = p_staff)
       and (q is null or a.record_id ilike '%' || q || '%' or a.detail::text ilike '%' || q || '%')
     order by a.at desc, a.id desc limit lim offset off_) z;
  return jsonb_build_object('key', 'aud_log', 'rows', rows_, 'total', tot, 'limit', lim, 'offset', off_,
    'tables', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct table_name t from public.audit_log) x),
    'actions', (select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (select distinct action t from public.audit_log) x),
    'notes', jsonb_build_array('owner_only', 'append_only', 'times_are_asia_dhaka_dates'),
    'basis', 'Every add, change, export and approval the system wrote, newest first. Rows are never edited or deleted.');
end $$;

-- ---------- #182 voided / reversed / corrected records, all modules ----------
create or replace function public._c3_voids(d1 date, d2 date, locs int[], p_salary boolean)
returns table (module text, kind text, rec_id text, ref text, rec_date date, event_at timestamptz, amount numeric, who text, reason text, location_id int, route text)
language sql stable security definer set search_path = public as $$
  with x as (
    select 'sale'::text m, 'void'::text k, s.id::text rid, 'Receipt ' || s.receipt as ref, s.sale_date as rd, s.void_at as ev, s.total as am, coalesce(s.void_staff, public._c3_staff(s.void_by)) as wh, s.void_note as rs, s.location_id as loc, 'sale'::text as rt
      from public.sales s where s.status = 'void'
    union all select 'sale_payment', 'void', p.id::text, 'Payment ' || p.id, (p.paid_at at time zone 'Asia/Dhaka')::date, null, p.amount, null, p.void_note, p.location_id, 'sale_payment'
      from public.sale_payments p where p.voided
    union all select 'sale_return', 'void', r.id::text, 'Return ' || left(r.id::text, 8), (r.created_at at time zone 'Asia/Dhaka')::date, r.void_at, r.amount, public._c3_staff(r.void_by), r.void_note, r.location_id, 'sale_return'
      from public.sale_returns r where r.status = 'void' or r.void_at is not null
    union all select 'supplier_payment', 'void', p.id::text, 'Supplier payment ' || p.id, (p.paid_at at time zone 'Asia/Dhaka')::date, null, p.amount, public._c3_staff(p.void_by), p.void_note, p.location_id, 'supplier_payment'
      from public.supplier_payments p where p.voided
    union all select 'supplier_refund', 'void', f.id::text, 'Supplier refund ' || f.id, (f.refunded_at at time zone 'Asia/Dhaka')::date, null, f.amount, public._c3_staff(f.void_by), f.void_note, f.location_id, 'supplier_refund'
      from public.supplier_refunds f where f.voided
    union all select 'purchase_bill', 'void', b.id::text, 'Bill ' || coalesce(b.bill_no, left(b.id::text, 8)), b.bill_date, b.void_at, b.total, public._c3_staff(b.void_by), b.void_note, b.location_id, 'purchase'
      from public.purchase_bills b where b.status = 'void'
    union all select 'cash_move', 'void', c.id::text, 'Cash move ' || c.kind, c.move_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, c.location_id, 'cash_move'
      from public.cash_moves c where c.status = 'void' or c.void_at is not null
    union all select 'quick_expense', 'void', q.id::text, 'Quick expense ' || q.head, q.exp_date, q.void_at, q.amount, public._c3_staff(q.void_by), q.void_note, q.location_id, 'quick_expense'
      from public.quick_expenses q where q.status = 'void' or q.void_at is not null
    union all select 'other_income', 'void', o.id::text, 'Other income ' || o.head, o.income_date, o.void_at, o.amount, public._c3_staff(o.void_by), o.void_note, o.location_id, 'other_income'
      from public.other_income o where o.status = 'void' or o.void_at is not null
    union all select 'money_charge', 'void', c.id::text, 'Bank / wallet charge ' || c.kind, c.charge_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, c.location_id, 'money_charge'
      from public.money_charges c where c.status = 'void' or c.void_at is not null
    union all select 'money_transfer', 'void', t.id::text, 'Transfer ' || t.id, t.xfer_date, t.void_at, t.amount, public._c3_staff(t.void_by), t.void_note, t.location_id, 'money_transfer'
      from public.money_transfers t where t.status = 'void' or t.void_at is not null
    union all select 'production_run', 'void', r.id::text, 'Production run ' || left(r.id::text, 8), (r.made_at at time zone 'Asia/Dhaka')::date, r.void_at, null, public._c3_staff(r.void_by), r.void_note, r.location_id, 'production_run'
      from public.production_runs r where r.status = 'void' or r.void_at is not null
    union all select 'wallet_fee', 'void', w.id::text, 'Wallet fee ' || w.id, w.fee_date, w.void_at, w.amount, public._c3_staff(w.void_by), w.void_note, w.location_id, 'wallet_fee'
      from public.d_wallet_fees w where w.voided
    union all select 'wallet_move', 'void', w.id::text, 'Wallet move ' || w.id, w.move_date, w.void_at, w.amount, public._c3_staff(w.void_by), w.void_note, w.location_id, 'wallet_move'
      from public.d_wallet_moves w where w.voided
    union all select 'cost_bill', 'void', c.id::text, 'Cost bill ' || coalesce(c.bill_no, c.id::text), c.bill_date, c.void_at, c.amount, public._c3_staff(c.void_by), c.void_note, null::int, 'cost_bill'
      from public.cost_source_bills c where c.status = 'void' or c.void_at is not null
    union all select 'journal', 'reversal', j.id::text, j.source_type || ' ' || j.source_id, j.entry_date, j.created_at, (select sum(l.debit) from public.journal_lines l where l.entry_id = j.id), coalesce(j.created_staff, public._c3_staff(j.created_by)), j.memo, j.location_id, 'journal'
      from public.journal_entries j where j.reverses_id is not null
    union all select 'form_correction', 'correction', c.id::text, 'Form ' || c.form_code || ' ' || coalesce(c.entry_id, ''), (c.at at time zone 'Asia/Dhaka')::date, c.at, null, c.staff_id, c.note,
                    (select e.location_id from public.entries e where e.id::text = c.entry_id), 'entry'
      from public.corrections c
    union all select 'form_change_request', 'correction', r.id::text, 'Form change request ' || r.id, (r.decided_at at time zone 'Asia/Dhaka')::date, r.decided_at, null, r.decided_staff, r.reason,
                    (select e.location_id from public.entries e where e.id = r.entry_id), 'entry'
      from public.entry_change_requests r where r.status = 'approved'
    union all select 'payroll_run', 'void', r.id::text, 'Payroll run ' || to_char(r.month, 'YYYY-MM'), r.month, r.void_at, null, public._c3_staff(r.void_by), r.void_reason, r.location_id, 'payroll'
      from public.payroll_runs r where p_salary and (r.status = 'void' or r.void_at is not null)
    union all select 'payroll_payment', 'void', p.id::text, 'Payroll payment ' || p.id, p.pay_date, p.void_at, p.amount, public._c3_staff(p.void_by), p.void_reason, p.location_id, 'payroll'
      from public.payroll_payments p where p_salary and (p.status = 'void' or p.void_at is not null)
    union all select 'staff_advance', 'void', a.id::text, 'Staff advance ' || a.id, a.adv_date, a.void_at, a.amount, public._c3_staff(a.void_by), a.void_reason, a.location_id, 'payroll'
      from public.employee_advances a where p_salary and (a.status = 'void' or a.void_at is not null))
  select x.m, x.k, x.rid, x.ref, x.rd, x.ev, x.am, x.wh, x.rs, x.loc, x.rt from x
   where coalesce((x.ev at time zone 'Asia/Dhaka')::date, x.rd) between d1 and d2 and (x.loc is null or x.loc = any (locs))
$$;

create or replace function public.aud_void_register(p_from date, p_to date, p_loc int default null, p_module text default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; sal boolean; lim int := least(greatest(coalesce(p_limit, 500), 1), 2000); rows_ jsonb; tot bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  sal := public.is_owner() or public.rpt_grant('salary_view');
  select count(*) into tot from public._c3_voids(p_from, p_to, locs, sal) v where p_loc is null or v.location_id = p_loc;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.sort_at desc nulls last, z.module), '[]'::jsonb) into rows_ from (
    select v.module, v.kind, v.rec_id, v.ref, v.rec_date, v.event_at, coalesce(v.event_at, v.rec_date::timestamptz) as sort_at, (v.event_at is null) as time_not_captured,
           v.amount, v.who, v.reason, v.location_id, v.route
      from public._c3_voids(p_from, p_to, locs, sal) v
     where (p_loc is null or v.location_id = p_loc) and (p_module is null or v.module = p_module)
     order by coalesce(v.event_at, v.rec_date::timestamptz) desc nulls last limit lim) z;
  return jsonb_build_object('key', 'aud_voids', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'total', tot,
    'by_module', (select coalesce(jsonb_object_agg(v.module, jsonb_build_object('kind', v.kind, 'n', v.n, 'amount', v.amt)), '{}'::jsonb)
                    from (select m.module, min(m.kind) as kind, count(*) as n, round(sum(m.amount), 2) as amt from public._c3_voids(p_from, p_to, locs, sal) m where p_loc is null or m.location_id = p_loc group by m.module) v),
    'salary_hidden', not sal,
    'notes', jsonb_build_array('nothing_is_hard_deleted', 'time_not_captured_where_the_module_stores_none', 'dates_are_the_void_date_else_the_record_date') || case when sal then '[]'::jsonb else jsonb_build_array('salary_modules_hidden') end,
    'basis', 'Every voided record, journal reversal and recorded correction, from the table each module keeps. A blank "when" means that module never stored the time of the void.');
end $$;

revoke all on function public._c3_voids(date, date, int[], boolean) from public, anon, authenticated;
revoke all on function public.aud_log_page(date, date, text, text, text, text, int, int), public.aud_void_register(date, date, int, text, int) from public, anon;
grant execute on function public.aud_log_page(date, date, text, text, text, text, int, int), public.aud_void_register(date, date, int, text, int) to authenticated;
notify pgrst, 'reload schema';

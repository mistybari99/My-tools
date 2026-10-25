-- Phase 93 (bos93) - REPORT PARITY AND DATED BRAND MAP (UNIFIED_BUILD_PLAN U-06, package W1-D). Paste after phase92, paste-twice safe. Earlier phase files are not edited.
-- WHY: salary and expense totals differ between the day book, the P&L, the expense report and the journal (G16, G21, G12), and changing the brand map rewrites the brand P&L of old months.
-- EVERYTHING IS OFF BY DEFAULT: with every setting at its default no figure changes (proved by tests/sql/w1d_before_after.sh).
--   report_salary_source     legacy (default) | app_first    P&L salary: app payroll runs are primary and the 02-2 sheet is the fallback only where NO counted run exists for the month and place.
--                                                           (legacy = today: 02-2 sheets, plus the runs only while payroll_accrual_on is on). One salary is counted once whether or not a form and a run both exist.
--   report_expense_parity_on switch, default OFF             the expense report (expense_by_head) and the control report (E3) drop locked shadow vouchers and ADD quick expenses, as the P&L and E2 already do.
--   expense_count_on         as_today (default) | approved | submitted   which 10-2 vouchers count. as_today = each report as it is now (P&L and day book: submitted + approved, journal: approved only).
--                                                           approved / submitted = the SAME rule in the P&L, the expense reports and (through the integrator hook _w1d_hooks_apply) the day book and the journal.
--   brand_map_dated_on       switch, default OFF             the brand P&L reads the brand of each place AS OF each day (report_brand_map_hist); off = the current map for every day, as today.
-- Always on (no effect on any figure): report_brand_map_hist keeps every change of the map with its dates (a trigger on report_brand_map + backfill of the current rows), brand_map_set() changes the map
--   from a date (a date in the past needs a reason: audit_log + Exceptions list), report_parity() shows the four totals side by side.
-- INTEGRATOR: the day book and the journal are shared functions. _w1d_hooks_apply() patches them (marker bos93, exact text, stops if a site is missing). Call it from the last phase of the wave:  select public._w1d_hooks_apply();
-- NOT DONE: salary_report and _r3q_t3_payroll still read 02-2 sheets only; the brand filter of _r2_locs uses the current map.
-- !! Re-pasting phase 27, 44, 50, 72, 82, 85, 86 or 21/23 removes bos93 patches: paste phase92 and phase93 again (and call _w1d_hooks_apply()).

do $g$ begin
  if to_regprocedure('public._w1d_p92_present()') is null then raise exception 'phase93 needs phase92 first'; end if;
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,integer)') is null or to_regprocedure('public._r3q_e3_weak_control(date,date,integer[],jsonb)') is null
     or to_regprocedure('public._r3q_e2_expense_trend(date,date,integer[],jsonb)') is null or to_regprocedure('public.brand_pnl(date,date,text)') is null
     or to_regprocedure('public.c_salary_by_month(date,date,integer[])') is null or to_regclass('public.report_brand_map') is null or to_regclass('public.quick_expenses') is null then
    raise exception 'phase93 needs the report functions of phases 9, 20, 21, 50, 82';
  end if;
end $g$;

create or replace function public._w1d_p93_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings (English labels only, defaults keep today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_salary_source', 'reports', 'choice', '"legacy"', null, '["legacy","app_first"]', null, null,
  'Salary in the profit comes from', 'Salary in the profit comes from', 'Salary in the profit comes from',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.', 800),
 ('report_expense_parity_on', 'reports', 'switch', 'false', null, null, null, null,
  'Expense report counts quick expenses and skips shadow vouchers', 'Expense report counts quick expenses and skips shadow vouchers', 'Expense report counts quick expenses and skips shadow vouchers',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.', 801),
 ('expense_count_on', 'reports', 'choice', '"as_today"', null, '["as_today","approved","submitted"]', null, null,
  'Expense vouchers count when they are', 'Expense vouchers count when they are', 'Expense vouchers count when they are',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).', 802),
 ('brand_map_dated_on', 'reports', 'switch', 'false', null, null, null, null,
  'Brand reports use the brand each place had on each day', 'Brand reports use the brand each place had on each day', 'Brand reports use the brand each place had on each day',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.', 803)
on conflict (key) do nothing;

create or replace function public._w1d_salary_app_first() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('report_salary_source'), 'legacy') = 'app_first' $$;
create or replace function public._w1d_parity_on() returns boolean language sql stable security definer set search_path = public as $$
  select public.rule_on('report_expense_parity_on') $$;
-- does a 10-2 voucher of this status count? ctx = where it is asked: 'pl' (P&L and expense reports), 'daybook', 'journal'. as_today = each as it is now.
create or replace function public._w1d_exp_status_ok(p_status text, p_ctx text) returns boolean language sql stable security definer set search_path = public as $$
  select case coalesce(public.rule_txt('expense_count_on'), 'as_today')
    when 'approved' then p_status = 'approved'
    when 'submitted' then p_status in ('submitted', 'approved')
    else case when p_ctx = 'journal' then p_status = 'approved' else p_status in ('submitted', 'approved') end end $$;
grant execute on function public._w1d_exp_status_ok(text, text) to authenticated;

-- ---------- dated brand map ----------
create table if not exists public.report_brand_map_hist (
  id bigserial primary key,
  location_id integer not null references public.locations(id),
  brand_code text not null, brand_bn text not null, brand_en text not null,
  valid_from date,                                   -- null = from the beginning
  valid_to date,                                     -- null = still valid
  active boolean not null default true,              -- false = replaced by a dated correction (kept, never deleted)
  reason text check (reason is null or length(btrim(reason)) between 5 and 300),
  changed_by uuid default auth.uid(), changed_at timestamptz not null default now(),
  check (valid_to is null or valid_from is null or valid_to >= valid_from)
);
create index if not exists report_brand_map_hist_loc on public.report_brand_map_hist (location_id, valid_from);
drop trigger if exists report_brand_map_hist_nodel on public.report_brand_map_hist;
create trigger report_brand_map_hist_nodel before delete on public.report_brand_map_hist for each row execute function public.no_hard_delete();
drop trigger if exists audit_report_brand_map_hist on public.report_brand_map_hist;
create trigger audit_report_brand_map_hist after insert or update on public.report_brand_map_hist for each row execute function public.log_change('id');
alter table public.report_brand_map_hist enable row level security;
revoke all on public.report_brand_map_hist from public, anon, authenticated;
drop policy if exists report_brand_map_hist_read on public.report_brand_map_hist;
create policy report_brand_map_hist_read on public.report_brand_map_hist for select to authenticated using (public.is_active());
grant select on public.report_brand_map_hist to authenticated;

-- backfill: every mapping that exists today is valid from the beginning (idempotent)
insert into public.report_brand_map_hist (location_id, brand_code, brand_bn, brand_en, valid_from, reason)
select m.location_id, m.brand_code, m.brand_bn, m.brand_en, null, 'mapping that existed when the history started'
  from public.report_brand_map m where not exists (select 1 from public.report_brand_map_hist h where h.location_id = m.location_id);

-- close the open row of a place and open a new one from e (same-day corrections replace the row of that day)
create or replace function public._w1d_brand_open(p_loc integer, p_code text, p_bn text, p_en text, e date, p_reason text) returns bigint language plpgsql security definer set search_path = public as $$
declare r record; id_ bigint;
begin
  for r in select * from public.report_brand_map_hist where location_id = p_loc and active and (valid_to is null or valid_to >= e) order by valid_from nulls first, id for update loop
    if r.valid_from is null or r.valid_from < e then update public.report_brand_map_hist set valid_to = e - 1 where id = r.id;
    else update public.report_brand_map_hist set active = false where id = r.id; end if;
  end loop;
  if p_code is null then return null; end if;                    -- the mapping was removed: the place is unmapped from e
  insert into public.report_brand_map_hist (location_id, brand_code, brand_bn, brand_en, valid_from, reason) values (p_loc, p_code, p_bn, p_en, e, left(btrim(p_reason), 300)) returning id into id_;
  return id_;
end $$;

-- a direct edit of report_brand_map (owner, SQL or table API) is dated TODAY (a change in the past goes through brand_map_set with a reason)
create or replace function public._w1d_brand_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare e date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if coalesce(current_setting('bos.w1d_brand_skip', true), '') = '1' then return null; end if;
  if tg_op = 'DELETE' then perform public._w1d_brand_open(old.location_id, null, null, null, e, null);
  elsif tg_op = 'INSERT' then perform public._w1d_brand_open(new.location_id, new.brand_code, new.brand_bn, new.brand_en, e, 'mapping added');
  elsif new.brand_code is distinct from old.brand_code or new.brand_bn is distinct from old.brand_bn or new.brand_en is distinct from old.brand_en then
    perform public._w1d_brand_open(new.location_id, new.brand_code, new.brand_bn, new.brand_en, e, 'mapping changed');
  end if;
  return null;
end $$;
drop trigger if exists report_brand_map_w1d on public.report_brand_map;
create trigger report_brand_map_w1d after insert or update or delete on public.report_brand_map for each row execute function public._w1d_brand_trg();

-- the brand of a place on a day: dated history when the switch is on, today's map when it is off
create or replace function public._w1d_brand_at(p_loc integer, p_day date) returns table (brand_code text, brand_bn text, brand_en text) language sql stable security definer set search_path = public as $$
  select m.brand_code, m.brand_bn, m.brand_en from public.report_brand_map m where not public.rule_on('brand_map_dated_on') and m.location_id = p_loc
  union all
  select z.brand_code, z.brand_bn, z.brand_en from (
    select h.brand_code, h.brand_bn, h.brand_en from public.report_brand_map_hist h
     where public.rule_on('brand_map_dated_on') and h.active and h.location_id = p_loc and (h.valid_from is null or h.valid_from <= p_day) and (h.valid_to is null or h.valid_to >= p_day)
     order by h.valid_from nulls first, h.id desc limit 1) z $$;

-- owner: map a place to a brand FROM a date. Today or later in the future is not allowed; a date in the past rewrites history, so it needs a reason (audit_log + Exceptions list).
create or replace function public.brand_map_set(p_loc integer, p_code text, p_bn text, p_en text, p_from date default null, p_reason text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare today_ date := (now() at time zone 'Asia/Dhaka')::date; e date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date); id_ bigint; why text := nullif(btrim(coalesce(p_reason, '')), ''); retro boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_code is null or length(btrim(p_code)) = 0 or length(p_code) > 40 or p_bn is null or length(btrim(p_bn)) = 0 or p_en is null or length(btrim(p_en)) = 0 then raise exception 'bad_brand'; end if;
  if e > today_ then raise exception 'future_date_not_allowed'; end if;
  retro := e < today_;
  if retro and (why is null or length(why) < 5) then raise exception 'reason_required'; end if;
  id_ := public._w1d_brand_open(p_loc, btrim(p_code), btrim(p_bn), btrim(p_en), e, coalesce(why, 'brand map set'));
  perform set_config('bos.w1d_brand_skip', '1', true);
  insert into public.report_brand_map (location_id, brand_code, brand_bn, brand_en) values (p_loc, btrim(p_code), btrim(p_bn), btrim(p_en))
    on conflict (location_id) do update set brand_code = excluded.brand_code, brand_bn = excluded.brand_bn, brand_en = excluded.brand_en;
  perform set_config('bos.w1d_brand_skip', '', true);
  if retro then
    perform public._stock_exc(p_loc, 'brand_map_backdated', 'yellow', 'Brand map changed from a past date (' || e::text || '): ' || btrim(p_code) || ' (' || why || ')',
                              'Brand map changed from a past date (' || e::text || '): ' || btrim(p_code) || ' (' || why || ')', null, e, 'BRAND', null);
  end if;
  return jsonb_build_object('id', id_, 'location_id', p_loc, 'valid_from', e, 'backdated', retro);
end $$;

create or replace function public.brand_map_hist_list(p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'location_id', h.location_id, 'brand_code', h.brand_code, 'brand_bn', h.brand_bn, 'brand_en', h.brand_en,
           'valid_from', h.valid_from, 'valid_to', h.valid_to, 'active', h.active, 'reason', h.reason, 'changed_at', h.changed_at) order by h.location_id, h.valid_from nulls first, h.id)
    from public.report_brand_map_hist h where p_loc is null or h.location_id = p_loc), '[]'::jsonb);
end $$;

-- ============================================================================
-- PATCHES (text patch of the LIVE definition; a missing site stops the paste; marker bos93)
-- ============================================================================
-- _p27_pl: the 10-2 status rule, and the salary source
select public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */$a$,
  $a$where public.rule_on('payroll_accrual_on') /* bos85 bos86 */$a$,
  $a$where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */$a$]);

-- the expense report: same expenses as the P&L (quick expenses in, locked shadow vouchers out) when report_expense_parity_on; status rule from expense_count_on
select public._w1d_patch('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) and e.entry_date between %L and %L and e.location_id = any (%L::int[])
            union all  /* bos93: quick expenses (only while report_expense_parity_on) */
            select null::uuid, q.location_id, q.exp_date, q.amount, case when q.receipt then 'yes' else 'no' end, coalesce(nullif(btrim(q.head), ''), '-') from public.quick_expenses q
            where public._w1d_parity_on() and q.status = 'done' and q.exp_date between %2$L and %3$L and q.location_id = any (%4$L::int[])) x$a$]);

-- E3 control report: status rule, shadows out, and a row for the quick expenses (only while report_expense_parity_on)
select public._w1d_patch('public._r3q_e3_weak_control(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) /* bos93 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$   group by l.id, l.name_bn;$a$,
  $a$   group by l.id, l.name_bn
  union all  /* bos93: quick expenses have no voucher flags; their count and the lines without a receipt are shown so that the control report covers them */
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', 'quick', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', count(*) filter (where not q.receipt), 'no_receipt_amount', coalesce(sum(q.amount) filter (where not q.receipt), 0), 'over_limit_vouchers', null, 'over_limit_amount', null,
      'approval_missing', null, 'reason_missing', null, 'imprest_diff_sheets', null, 'imprest_diff_amount', null)
    from public.quick_expenses q join public.locations l on l.id = q.location_id
   where public._w1d_parity_on() and q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
   group by l.id, l.name_bn;$a$]);

-- E2 expense trend: the status rule only (it already counts quick expenses and drops shadows)
select public._w1d_patch('public._r3q_e2_expense_trend(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$]);

-- brand P&L: the brand of each place AS OF each day (switch brand_map_dated_on; off = today's map)
select public._w1d_patch('public.brand_pnl(date,date,text)'::regprocedure, 'bos93', array[
  $a$left join public.report_brand_map b on b.location_id = d.location_id$a$,
  $a$left join lateral public._w1d_brand_at(d.location_id, d.sale_date) b on true /* bos93 */$a$]);

-- ---------- the integrator's hook: the shared day book and journal use the same voucher rule ----------
-- Call once from the last phase of the wave (and again after any re-paste of phases 13, 23, 50, 52, 79, 85, 87). Exact-text patch, marker bos93, stops if a site is missing. Idempotent.
create or replace function public._w1d_hooks_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare a boolean; b boolean;
begin
  a := public._w1d_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, 'bos93', array[
    $x$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)$x$,
    $x$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'daybook') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)$x$]);
  b := public._w1d_patch('public._acct_docs(date)'::regprocedure, 'bos93', array[
    $x$e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */$x$,
    $x$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$x$]);
  return jsonb_build_object('daybook_lines_patched', a, 'acct_docs_patched', b);
end $$;

-- ---------- report_parity: the same expenses and salary in the day book, the P&L, the expense report and the journal ----------
create or replace function public.report_parity(p_from date, p_to date, p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  locs int[]; st date := public._acct_start(); db_e numeric; db_s numeric; pl_e numeric; pl_s numeric; xt numeric; wf numeric; rep numeric; j_e numeric; j_s numeric; j_rec numeric;
  rr jsonb; agree_e boolean; agree_s boolean; agree_d boolean;
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  -- day book (money out): vouchers and quick expenses = typ expense; salary paid = typ salary
  select coalesce(sum(u.amount) filter (where u.typ = 'expense'), 0), coalesce(sum(u.amount) filter (where u.typ = 'salary'), 0) into db_e, db_s
    from (select * from public._daybook_lines(locs, locs, p_from, p_to) union all select * from public._daybook_lines12(locs, p_from, p_to) union all select * from public._daybook_lines23(locs, p_from, p_to)) u;
  -- P&L: expenses without the wallet fee and the profit-only rows of phase92; salary as the P&L counts it
  select coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0) into pl_e, pl_s from public._p27_pl(p_from, p_to, locs);
  select coalesce(sum(amount), 0) into wf from public._d_wallet_fee_rows(p_from, p_to, locs);
  select coalesce(sum(r.amt), 0) into xt from public._w1d_pl_rows_on(p_from, p_to, locs) r;
  pl_e := pl_e - wf - xt;
  -- the expense report (expense_by_head) total, run through the real report
  begin
    rr := public.report_run2_core('expense_by_head', jsonb_build_object('from', p_from, 'to', p_to, 'locations', to_jsonb(locs)), 'none');
    rep := coalesce((rr #>> '{totals,amount}')::numeric, 0);
  exception when others then rep := null;
  end;
  -- the journal: debits on expense accounts of the voucher / quick expense / payroll sources, net of reversals
  if st is null or p_to < st then j_e := null; j_s := null; j_rec := null;
  else
    select coalesce(sum(l.debit - l.credit) filter (where e.source_type in ('expense_voucher', 'quick_expense') and a.type = 'expense'), 0),
           coalesce(sum(l.debit - l.credit) filter (where e.source_type in ('payroll_payment', 'payroll_accrual') and a.type = 'expense'), 0),
           coalesce(sum(l.credit - l.debit) filter (where e.source_type = 'payroll_payment' and a.code = (select ac.code from public.acct_mappings m join public.coa_accounts ac on ac.id = m.account_id where m.key = 'staff_advance')), 0)
      into j_e, j_s, j_rec
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where e.entry_date between greatest(p_from, st) and p_to and (l.location_id = any (locs) or (p_loc is null and l.location_id is null));
  end if;
  agree_e := j_e is not null and rep is not null and db_e = pl_e and pl_e = rep and rep = j_e;
  agree_s := j_s is not null and pl_s = j_s;
  agree_d := j_s is not null and db_s = j_s - j_rec;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc,
    'expenses', jsonb_build_object('daybook', db_e, 'pl', pl_e, 'expense_report', rep, 'journal', j_e, 'agree', agree_e,
       'note', 'Expense vouchers (10-2) and quick expenses. The journal counts only what is posted; the day book counts money out on the voucher date.'),
    'salary', jsonb_build_object('daybook_paid', db_s, 'pl', coalesce(pl_s, 0), 'journal', j_s, 'journal_advance_recovery', j_rec, 'pl_agrees_journal', agree_s, 'daybook_agrees_journal_less_recovery', agree_d,
       'note', 'The P&L and the journal show the salary expense (net pay plus advance recovery). The day book shows only the money paid out (net pay).'),
    'settings', jsonb_build_object('expense_count_on', coalesce(public.rule_txt('expense_count_on'), 'as_today'), 'report_expense_parity_on', public.rule_on('report_expense_parity_on'),
       'report_salary_source', coalesce(public.rule_txt('report_salary_source'), 'legacy')));
end $$;

-- ---------- rights ----------
revoke all on function public._w1d_p93_present(), public._w1d_salary_app_first(), public._w1d_parity_on(), public._w1d_brand_open(integer, text, text, text, date, text), public._w1d_brand_trg(),
  public._w1d_brand_at(integer, date), public._w1d_hooks_apply() from public, anon, authenticated;
revoke all on function public.brand_map_set(integer, text, text, text, date, text), public.brand_map_hist_list(integer), public.report_parity(date, date, integer) from public, anon;
grant execute on function public.brand_map_set(integer, text, text, text, date, text), public.brand_map_hist_list(integer), public.report_parity(date, date, integer) to authenticated;

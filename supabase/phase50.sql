-- ============================================================
-- Phase 50 - P1 slice 3: payroll (gap #24) and expense (gap #28) - one record + locked shadow copy.
-- Run AFTER phase48 (phase49 is optional). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   PAYROLL  path A = app payroll (payroll_runs / payroll_payments), path B = form 02-2.  Same place + month (+ year) = same event.
--            Owner default: the app payroll is the record; the 02-2 sheet becomes a locked shadow (kept, shown, never counted in the day book).
--            Owner may switch the primary to the form, or "first one wins", or lock either path (Switch board, domain payroll).
--            A voided run releases its shadows: the forms count again.
--   EXPENSE  path A = quick expense typed in the day-book tab (quick_expenses), path B = form 10-2.
--            A quick entry counts at once (day book, journal, P&L). It gets a pending shadow; quick_expense_close_day() builds ONE draft 10-2 from the
--            day's unlinked quick entries (one click) and confirms the shadows. The 10-2 shadow is never counted again.
--   Guards   BEFORE INSERT triggers refuse a new record on a path the owner has locked (payroll_runs, entries of 02-2 / 10-2 / 04-2 / 03-1 / 04-3 / 05-1).
--   Lock     a shadow form that is submitted/approved cannot have its data changed or be re-opened.
--   Counting once: _daybook_lines, _daybook_skipped, _daybook_lines23, _acct_docs, _p27_pl, _r3q_e2_expense_trend are RE-CREATED from their latest definitions;
--            ONLY the blocks marked "bos50" differ.
-- ============================================================

-- ---------- 1. form -> domain map, guard for the form path ----------
create or replace function public._entry_domain(p_form text) returns text language sql immutable as $$
  select case p_form when '02-2' then 'payroll' when '10-2' then 'expense' when '04-2' then 'stock_issue' when '03-1' then 'stock_transfer' when '04-3' then 'stock_count' when '05-1' then 'production' end;
$$;

create or replace function public._entries_path_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text := public._entry_domain(new.form_code);
begin
  if d is not null and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard(d, new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_path_guard50 on public.entries;
create trigger entries_path_guard50 before insert on public.entries for each row execute function public._entries_path_guard50();

-- a shadow form that is submitted / approved is locked: no data change, no re-open
create or replace function public._entries_shadow_lock50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status in ('submitted', 'approved') and (new.data is distinct from old.data or new.status = 'draft') and public.is_shadow('entries', old.id::text) then
    raise exception 'shadow_locked: this form is a locked copy of another record; it cannot be changed or re-opened';
  end if;
  return new;
end $$;
drop trigger if exists entries_shadow_lock50 on public.entries;
create trigger entries_shadow_lock50 before update on public.entries for each row execute function public._entries_shadow_lock50();

-- ---------- 2. PAYROLL: guard, link, release ----------
create or replace function public._payroll_run_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.path_guard('payroll', coalesce(new.location_id, 0), 'a');
  return new;
end $$;
drop trigger if exists payroll_runs_path_guard50 on public.payroll_runs;
create trigger payroll_runs_path_guard50 before insert on public.payroll_runs for each row execute function public._payroll_run_guard50();

-- the month / year a 02-2 sheet is written for (null when it cannot be read)
create or replace function public._entry_pay_month50(p_data jsonb) returns date
language sql immutable as $$
  select case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end;
$$;

create or replace function public._payroll_pair50(p_run bigint, p_entry uuid, p_loc int, p_incoming_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  begin
    if public.path_winner('payroll', p_loc, p_incoming_path) = 'incoming' then
      -- the record that just arrived is the primary: the older one becomes its shadow
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy'); end if;
    else
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy'); end if;
    end if;
  exception when others then
    if sqlerrm not like 'primary_is_already_a_shadow%' and sqlerrm not like 'shadow_is_already_a_primary%' then raise; end if;   -- an older decision already settled this pair
  end;
end $$;

create or replace function public._payroll_run_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'void' then return new; end if;
  for r in select e.id, e.location_id from public.entries e
            where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (new.location_id is null or e.location_id = new.location_id)
              and public._entry_pay_month50(e.data) = new.month loop
    perform public._payroll_pair50(new.id, r.id, r.location_id, 'a');
  end loop;
  return new;
end $$;
drop trigger if exists payroll_runs_link50 on public.payroll_runs;
create trigger payroll_runs_link50 after insert or update of status on public.payroll_runs for each row execute function public._payroll_run_link50();

create or replace function public._payroll_entry_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; m date := public._entry_pay_month50(new.data);
begin
  if m is null or new.form_code <> '02-2' or new.status not in ('submitted', 'approved') then return new; end if;
  for r in select pr.id from public.payroll_runs pr where pr.status <> 'void' and pr.month = m and (pr.location_id is null or pr.location_id = new.location_id) loop
    perform public._payroll_pair50(r.id, new.id, new.location_id, 'b');
  end loop;
  return new;
end $$;
drop trigger if exists entries_payroll_link50 on public.entries;
create trigger entries_payroll_link50 after insert or update of status on public.entries for each row when (new.form_code = '02-2') execute function public._payroll_entry_link50();

-- a voided run releases everything it held: the forms count again
create or replace function public._payroll_run_release50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'released: payroll run voided', 300)
     where domain = 'payroll' and state <> 'void' and ((primary_type = 'payroll_runs' and primary_id = new.id::text) or (shadow_type = 'payroll_runs' and shadow_id = new.id::text));
  end if;
  return new;
end $$;
drop trigger if exists payroll_runs_release50 on public.payroll_runs;
create trigger payroll_runs_release50 after update of status on public.payroll_runs for each row execute function public._payroll_run_release50();

-- ---------- 3. EXPENSE: quick expense (path A) ----------
create table if not exists public.quick_expenses (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  exp_date date not null,
  head text not null check (head ~ '^[a-z0-9_]{2,30}$'),
  paid_to text check (paid_to is null or length(paid_to) <= 120),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  mode text not null default 'cash' check (mode in ('cash', 'bank', 'mobile')),
  receipt boolean not null default false,
  note text check (note is null or length(note) <= 300),
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create index if not exists quick_exp_day on public.quick_expenses (location_id, exp_date);
drop trigger if exists audit_quick_expenses on public.quick_expenses;
create trigger audit_quick_expenses after insert or update on public.quick_expenses for each row execute function public.log_change('id');
create or replace function public._quick_exp_ro50() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'done' and new.status = 'void' and (to_jsonb(new) - 'status' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'status' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: a quick expense cannot be changed or deleted (void it)';
end $$;
drop trigger if exists quick_exp_ro on public.quick_expenses;
create trigger quick_exp_ro before update or delete on public.quick_expenses for each row execute function public._quick_exp_ro50();
alter table public.quick_expenses enable row level security;
revoke all on public.quick_expenses from public, anon, authenticated;
grant select on public.quick_expenses to authenticated;
drop policy if exists quick_expenses_sel on public.quick_expenses;
create policy quick_expenses_sel on public.quick_expenses for select to authenticated using (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(location_id)));

create or replace function public.quick_expense_add(p_loc int, p_date date, p_head text, p_to text, p_amount numeric, p_mode text default 'cash', p_receipt boolean default false,
                                                    p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses; today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into q from public.quick_expenses where client_id = p_client;
    if found then
      if q.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('id', q.id, 'duplicate', true);
    end if;
  end if;
  perform public.path_guard('expense', p_loc, 'a');
  if p_amount is null or p_amount <= 0 then raise exception 'bad_amount'; end if;
  if nullif(btrim(p_head), '') is null then raise exception 'head_needed'; end if;
  if d > today or (d < today - 7 and not public.is_owner()) then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
    values (p_client, p_loc, d, lower(btrim(p_head)), nullif(btrim(p_to), ''), p_amount, coalesce(p_mode, 'cash'), coalesce(p_receipt, false), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into q;
  -- the form copy is owed at day end: a pending shadow
  perform public.shadow_link_add('expense', p_loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
  return jsonb_build_object('id', q.id);
end $$;

create or replace function public.quick_expense_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses;
begin
  select * into q from public.quick_expenses where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (q.created_by = auth.uid() and q.exp_date = (now() at time zone 'Asia/Dhaka')::date and public.can_loc(q.location_id))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  if q.status = 'void' then return jsonb_build_object('id', q.id, 'noop', true); end if;
  perform public.lock_check(q.exp_date);
  if exists (select 1 from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed') then raise exception 'already_in_voucher: the day-end form was made; re-do it first'; end if;
  update public.quick_expenses set status = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = p_id;
  update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'quick expense voided', 300) where primary_type = 'quick_expenses' and primary_id = p_id::text and state = 'pending';
  return jsonb_build_object('id', q.id, 'status', 'void');
end $$;

-- what is typed today and what is still owed to the form
create or replace function public.quick_expense_day(p_loc int, p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('location_id', p_loc, 'date', p_date,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'head', q.head, 'paid_to', q.paid_to, 'amount', q.amount, 'mode', q.mode, 'receipt', q.receipt, 'note', q.note, 'status', q.status,
        'form', (select l.shadow_id from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed' limit 1)) order by q.created_at)
        from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date), '[]'::jsonb),
    'total', coalesce((select sum(q.amount) from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'), 0),
    'owed', (select count(*) from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
              where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'));
end $$;

-- one click at day end: ONE draft 10-2 from the day's quick entries that are not yet in a form; the shadows are confirmed
create or replace function public.quick_expense_close_day(p_loc int, p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lines jsonb; n int; sv jsonb; eid uuid; r record;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('head', q.head, 'to', coalesce(q.paid_to, ''), 'receipt', case when q.receipt then 'yes' else 'no' end, 'amount', q.amount) order by q.created_at), '[]'::jsonb), count(*)
    into lines, n
    from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
   where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  if n = 0 then return jsonb_build_object('made', 0, 'note', 'nothing owed'); end if;
  perform set_config('bos.shadow_create', '1', true);
  sv := public.save_entry(null, '10-2', p_loc, p_date, jsonb_build_object('lines', lines, 'from_quick', true), '[]'::jsonb, 'made from the day''s quick expenses', null);
  perform set_config('bos.shadow_create', '', true);
  eid := (sv->>'id')::uuid;
  update public.shadow_links l set state = 'confirmed', shadow_id = eid::text, confirmed_by = auth.uid(), confirmed_at = now()
    from public.quick_expenses q
   where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending' and q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  return jsonb_build_object('made', n, 'entry_id', eid, 'serial', sv->'serial');
end $$;

revoke all on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) from public, anon;
grant execute on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) to authenticated;
revoke all on function public._entry_domain(text), public._entries_path_guard50(), public._entries_shadow_lock50(), public._payroll_run_guard50(), public._entry_pay_month50(jsonb),
  public._payroll_pair50(bigint, uuid, int, text), public._payroll_run_link50(), public._payroll_entry_link50(), public._payroll_run_release50(), public._quick_exp_ro50() from public, anon, authenticated;

-- ============================================================
-- 4. COUNT ONCE: consumers re-created from their latest definitions. ONLY the lines marked bos50 differ.
-- ============================================================

CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, sp.wallet, sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_skipped(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select (
    (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs) and e.entry_date between p_from and p_to
        and nullif(btrim(l ->> 'amount'), '') is not null and public._db_num(l -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
      where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(a ->> 'amount'), '') is not null and public._db_num(a -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(r ->> 'net'), '') is not null and public._db_num(r -> 'net') is null))::int;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_lines23(p_locs integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) /* bos50 */ and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id))
  union all
  -- bos50: a quick expense typed in the day-book tab (its 10-2 copy is a locked shadow and is not counted again)
  select q.location_id, q.exp_date, 'out', q.mode, 'expense', q.amount, 'Q-' || left(q.id::text, 8), nullif(btrim(concat_ws(' · ', q.paid_to, q.head, q.note)), ''), q.created_staff, q.created_at,
         'quick_expense', q.id::text, false, false
    from public.quick_expenses q
   where q.status = 'done' and q.location_id = any (p_locs) and q.exp_date between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, m.id::text, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done', (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', m.id::text, m.status = 'done');

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
end $function$;

CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)) u group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$;

CREATE OR REPLACE FUNCTION public._r3q_e2_expense_trend(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2
              union all  -- bos50: quick expenses
              select q.exp_date, coalesce(nullif(btrim(q.head), ''), '-'), q.amount from public.quick_expenses q
               where q.status = 'done' and q.location_id = any (locs) and q.exp_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$function$;

notify pgrst, 'reload schema';

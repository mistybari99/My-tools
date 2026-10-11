-- ============================================================
-- BOS tool · Phase 13: DAY BOOK (cash / bank / mobile in and out by day) + SALARY REPORT (forms 02-1 / 02-2 / 02-3) + audited exports.
-- Run AFTER phase8, phase9, phase10 (phases 11 / 12 are independent). ADDITIVE and IDEMPOTENT: safe to run again, paste whole.
--
-- Principles kept:
--   * nothing is invented: the day book only adds up rows that really exist (POS payments, due collections, expense vouchers 10-2,
--     supplier payments, cash handover slips 10-1, staff advances 02-3, salary receipts 02-2). A day book start date is the owner's choice:
--     empty = no opening / closing figures at all ("Data needed"), only the movements.
--   * new grant `view_daybook` (owner can delegate to a role or a person, per location, with an end date, emergency window off by default).
--   * salary lines (advances, salary payments) inside the day book are only returned for people who also hold `salary_view`.
--   * salary_report is for the owner or `salary_view` holders only, and only returns what the forms contain; the sums are exactly the
--     formulas of form 02-2 (gross = due + overtime + other; net = gross - advance deduction - other deduction).
--   * export of either page is audited by log_page_export, which needs the owner or the grant export_data (same rpt_grant as the reports).
--   * RLS untouched (no new tables); new functions are SECURITY DEFINER, search_path=public, no anon, authenticated only.
-- ============================================================

-- ---------- (a) settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('daybook_enabled', 'books', 'switch', 'true', null, null, null, null, 'দিনের খাতা (Day book) চালু', 'Day book চালু', 'Day book is on',
  'বন্ধ করলে মালিক ছাড়া কেউ খুলতে পারবে না', 'When off, only the owner can open it', 160),
 ('daybook_start', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'দিনের খাতার শুরুর তারিখ (এই তারিখ থেকে চলতি জের গোনা হয়)', 'Day book শুরুর তারিখ (এই তারিখ থেকে running total)', 'Day book start date (running totals count from here)',
  'খালি থাকলে শুরু/শেষ জের দেখানো হয় না — শুধু লেনদেন', 'Empty = no opening / closing figures, movements only', 161),
 ('em_view_daybook', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: দিনের খাতা দেখা', 'জরুরি request চলবে: day book দেখা', 'Emergency allowed for: seeing the day book', 'ডিফল্টে বন্ধ', 'Off by default', 55)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('view_daybook', 'reports', 27, 'দিনের খাতা দেখা', 'Day book দেখা', 'See the day book', 'window', 'em_view_daybook')
on conflict (grant_code) do nothing;

-- ---------- (b) small safe parsers (never raise; Infinity / NaN / absurd sizes come back null) ----------
create or replace function public._db_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if j is null or jsonb_typeof(j) not in ('number', 'string') then return null; end if;
  s := btrim(j #>> '{}');
  if s !~ '^-?[0-9]{1,13}(\.[0-9]{1,6})?$' then return null; end if;
  return s::numeric;
end $$;

create or replace function public._db_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return btrim(t)::date;
exception when others then return null;
end $$;

create or replace function public._db_int(j jsonb) returns int
language plpgsql immutable set search_path = public as $$
declare n numeric := public._db_num(j);
begin
  if n is null or n <> trunc(n) or not (n between -100000 and 100000) then return null; end if;
  return n::int;
end $$;

-- the day book start date setting, null when empty / malformed
create or replace function public._db_start() returns date
language sql stable security definer set search_path = public as $$
  select public._db_date(public.rule_txt('daybook_start'));
$$;

-- owner sets / clears the start date (validated here because set_rule only checks "is a string")
create or replace function public.set_daybook_start(p_date date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is not null and not (p_date between date '2000-01-01' and (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  perform public.set_rule('daybook_start', case when p_date is null then null else to_jsonb(to_char(p_date, 'YYYY-MM-DD')) end);
end $$;

-- ---------- (c) the raw movements ----------
-- one row per real money movement. p_locs = locations the caller may see; p_sal = the subset where the caller may also see salary lines.
create or replace function public._daybook_lines(p_locs int[], p_sal int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
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
     and (p.paid_at at time zone 'Asia/Dhaka')::date between p_from and p_to
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
     and (sp.paid_at at time zone 'Asia/Dhaka')::date between p_from and p_to
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
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
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$$;

-- ---------- (d) the day book ----------
-- Result: { from, to, loc, start, opening_known, enabled, salary_hidden, days:[{date, open, in, out, close, lines:[...]}], totals:{open, in, out, close}, notes:[...] }
-- open / in / out / close are {cash, bank, mobile, total}; open and close are null when no start date is set or the day is before it.
-- p_loc null = every location the caller may see; internal hand-over slips (10-1) are then left out of every sum (the hub side is not recorded).
create or replace function public.day_book(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_l jsonb; v_locs int[]; v_sal int[]; v_start date; w_from date; v_all boolean := (p_loc is null);
  v_days jsonb; v_tot jsonb; v_hidden boolean; v_open jsonb; v_close jsonb; v_in jsonb; v_out jsonb; v_known boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if not public.is_owner() and not public.rule_on('daybook_enabled') then raise exception 'daybook_off'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('view_daybook', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l), '{}') into v_sal from unnest(v_locs) l where public.has_grant('salary_view', l);
  v_start := public._db_start();
  w_from := case when v_start is not null and v_start < p_from then v_start else p_from end;

  select coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) into v_l from public._daybook_lines(v_locs, v_sal, w_from, p_to) z;
  v_hidden := cardinality(v_sal) < cardinality(v_locs);

  -- counted = real movement for the totals (internal slips only vanish in the all-locations view)
  with c as (select d, mode, case when dir = 'in' then amount else -amount end as s, dir, amount from jsonb_to_recordset(v_l) as t(loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean) where not (internal and v_all)),
  perday as (select d, sum(s) filter (where mode = 'cash') as cash, sum(s) filter (where mode = 'bank') as bank, sum(s) filter (where mode = 'mobile') as mobile, sum(s) as total
               from c group by d),
  cum as (select d, cash, bank, mobile, total,
                 coalesce(sum(cash) over (order by d rows between unbounded preceding and 1 preceding), 0) as pc,
                 coalesce(sum(bank) over (order by d rows between unbounded preceding and 1 preceding), 0) as pb,
                 coalesce(sum(mobile) over (order by d rows between unbounded preceding and 1 preceding), 0) as pm,
                 coalesce(sum(total) over (order by d rows between unbounded preceding and 1 preceding), 0) as pt
            from (select d, coalesce(cash, 0) cash, coalesce(bank, 0) bank, coalesce(mobile, 0) mobile, coalesce(total, 0) total from perday) z)
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', x.d,
      'open', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc, 'bank', cm.pb, 'mobile', cm.pm, 'total', cm.pt) end,
      'in', jsonb_build_object('cash', x.i_cash, 'bank', x.i_bank, 'mobile', x.i_mobile, 'total', x.i_cash + x.i_bank + x.i_mobile),
      'out', jsonb_build_object('cash', x.o_cash, 'bank', x.o_bank, 'mobile', x.o_mobile, 'total', x.o_cash + x.o_bank + x.o_mobile),
      'close', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc + cm.cash, 'bank', cm.pb + cm.bank, 'mobile', cm.pm + cm.mobile, 'total', cm.pt + cm.total) end,
      'lines', x.lines) order by x.d), '[]'::jsonb)
    into v_days
    from (select t.d,
            coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'cash' and not (t.internal and v_all)), 0) i_cash,
            coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'bank' and not (t.internal and v_all)), 0) i_bank,
            coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'mobile' and not (t.internal and v_all)), 0) i_mobile,
            coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'cash' and not (t.internal and v_all)), 0) o_cash,
            coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'bank' and not (t.internal and v_all)), 0) o_bank,
            coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'mobile' and not (t.internal and v_all)), 0) o_mobile,
            jsonb_agg(jsonb_build_object('loc', t.loc, 'dir', t.dir, 'mode', t.mode, 'type', t.typ, 'amount', t.amount, 'ref', t.ref, 'text', t.txt, 'who', t.who,
                      'at', t.at, 'src', t.src, 'src_id', t.src_id, 'internal', t.internal and v_all, 'sensitive', t.sensitive) order by t.at, t.typ) lines
            from jsonb_to_recordset(v_l) as t(loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean) where t.d between p_from and p_to group by t.d) x
    left join cum cm on cm.d = x.d;

  select jsonb_build_object(
      'in', jsonb_build_object('cash', coalesce(sum(amount) filter (where dir = 'in' and mode = 'cash'), 0), 'bank', coalesce(sum(amount) filter (where dir = 'in' and mode = 'bank'), 0),
                               'mobile', coalesce(sum(amount) filter (where dir = 'in' and mode = 'mobile'), 0), 'total', coalesce(sum(amount) filter (where dir = 'in'), 0)),
      'out', jsonb_build_object('cash', coalesce(sum(amount) filter (where dir = 'out' and mode = 'cash'), 0), 'bank', coalesce(sum(amount) filter (where dir = 'out' and mode = 'bank'), 0),
                                'mobile', coalesce(sum(amount) filter (where dir = 'out' and mode = 'mobile'), 0), 'total', coalesce(sum(amount) filter (where dir = 'out'), 0)))
    into v_tot from jsonb_to_recordset(v_l) as q(loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean) where d between p_from and p_to and not (internal and v_all);

  v_known := v_start is not null and p_to >= v_start;
  if v_known then
    -- opening of the range = running total of everything from the start date up to the day before p_from; closing = that + the range
    with b as (select case when dir = 'in' then amount else -amount end s, mode, d from jsonb_to_recordset(v_l) as q(loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean) where not (internal and v_all) and d >= v_start)
    select jsonb_build_object('cash', coalesce(sum(s) filter (where mode = 'cash' and d < greatest(p_from, v_start)), 0), 'bank', coalesce(sum(s) filter (where mode = 'bank' and d < greatest(p_from, v_start)), 0),
                              'mobile', coalesce(sum(s) filter (where mode = 'mobile' and d < greatest(p_from, v_start)), 0), 'total', coalesce(sum(s) filter (where d < greatest(p_from, v_start)), 0)),
           jsonb_build_object('cash', coalesce(sum(s) filter (where mode = 'cash'), 0), 'bank', coalesce(sum(s) filter (where mode = 'bank'), 0),
                              'mobile', coalesce(sum(s) filter (where mode = 'mobile'), 0), 'total', coalesce(sum(s), 0))
      into v_open, v_close from b;
  end if;

  return jsonb_build_object('from', p_from, 'to', p_to, 'loc', p_loc, 'start', v_start, 'opening_known', v_known, 'enabled', public.rule_on('daybook_enabled'),
    'salary_hidden', v_hidden, 'days', v_days,
    'totals', v_tot || jsonb_build_object('open', v_open, 'close', v_close),
    'notes', jsonb_build_array('card_as_bank', 'imprest_in_cash', 'bank_deposit_not_dated', 'hub_receipt_not_recorded', 'drafts_excluded'));
end $$;

-- ---------- (e) salary report (forms 02-2 sheet, 02-3 advances, 02-1 attendance) ----------
-- p_month is any date inside the month. A sheet belongs to the month written on the form (month + year), else its entry date.
create or replace function public.salary_report(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_locs int[]; m0 date; m1 date; mm int; yy int; v_rows jsonb; v_adv jsonb; v_att jsonb; v_tot jsonb; v_n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_month is null or not (p_month between date '2000-01-01' and date '2100-01-01') then raise exception 'bad_range'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('salary_view', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  m0 := date_trunc('month', p_month)::date; m1 := (m0 + interval '1 month')::date;
  mm := extract(month from m0)::int; yy := extract(year from m0)::int;

  -- salary sheet lines
  with sh as (
    select e.id, e.serial, e.location_id, e.status, e.data, e.entry_date
      from public.entries e
     where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs)
       and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
       and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy),
  ln as (
    select sh.id as entry_id, sh.serial, sh.location_id, sh.status, btrim(coalesce(r ->> 'name', '')) as name,
           public._db_num(r -> 'salary') salary, public._db_num(r -> 'work_days') work_days, public._db_num(r -> 'absent') absent, public._db_num(r -> 'leave') leave_days,
           coalesce(public._db_num(r -> 'due'), 0) due, coalesce(public._db_num(r -> 'overtime'), 0) overtime, coalesce(public._db_num(r -> 'other'), 0) other,
           coalesce(public._db_num(r -> 'adv_ded'), 0) adv_ded, coalesce(public._db_num(r -> 'other_ded'), 0) other_ded, nullif(btrim(r ->> 'remark'), '') remark,
           sh.data -> 'receipts' as rc, z.ord
      from sh cross join lateral jsonb_array_elements(case when jsonb_typeof(sh.data -> 'pay') = 'array' then sh.data -> 'pay' else '[]'::jsonb end) with ordinality as z(r, ord)),
  ln2 as (select * from ln where name <> '' and (due <> 0 or overtime <> 0 or other <> 0 or adv_ded <> 0 or other_ded <> 0 or salary is not null))
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', entry_id, 'serial', serial, 'loc', location_id, 'status', status, 'name', name, 'salary', salary,
        'work_days', work_days, 'absent', absent, 'leave', leave_days, 'due', due, 'overtime', overtime, 'other', other,
        'gross', due + overtime + other, 'adv_ded', adv_ded, 'other_ded', other_ded, 'deductions', adv_ded + other_ded,
        'net', due + overtime + other - adv_ded - other_ded, 'remark', remark,
        'paid', (select sum(public._db_num(q -> 'net')) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)),
        'signed', (select bool_and(coalesce((q ->> 'signed')::boolean, false)) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)))
        order by location_id, serial, ord), '[]'::jsonb),
      jsonb_build_object('people', count(*), 'due', coalesce(sum(due), 0), 'overtime', coalesce(sum(overtime), 0), 'other', coalesce(sum(other), 0),
        'gross', coalesce(sum(due + overtime + other), 0), 'adv_ded', coalesce(sum(adv_ded), 0), 'other_ded', coalesce(sum(other_ded), 0),
        'deductions', coalesce(sum(adv_ded + other_ded), 0), 'net', coalesce(sum(due + overtime + other - adv_ded - other_ded), 0)),
      count(distinct entry_id)::int
    into v_rows, v_tot, v_n from ln2;

  -- advances (02-3): per page = per employee
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'status', e.status, 'staff', e.data ->> 'staff',
        'name', coalesce(pr.full_name, e.data ->> 'staff'), 'post', e.data ->> 'post',
        'given', x.given, 'deducted', x.ded, 'outstanding', x.bal) order by e.location_id, e.serial), '[]'::jsonb)
    into v_adv
    from public.entries e
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
    cross join lateral (select coalesce(sum(public._db_num(a -> 'amount')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) given,
                               coalesce(sum(public._db_num(a -> 'ded_now')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) ded,
                               coalesce(sum(public._db_num(a -> 'balance')), 0) bal,
                               count(*) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1) n_in
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a) x
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and (x.n_in > 0 or (e.entry_date >= m0 and e.entry_date < m1));

  -- attendance (02-1) of the same month
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'name', btrim(r ->> 'name'), 'present', public._db_num(r -> 'present'),
        'late', public._db_num(r -> 'late'), 'absent', public._db_num(r -> 'absent'), 'leave_unpaid', public._db_num(r -> 'leave_unpaid'), 'leave_paid', public._db_num(r -> 'leave_paid'),
        'ot_hours', public._db_num(r -> 'ot_hours')) order by e.location_id, e.serial), '[]'::jsonb)
    into v_att
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
   where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and btrim(coalesce(r ->> 'name', '')) <> ''
     and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
     and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy;

  return jsonb_build_object('month', m0, 'loc', p_loc, 'rows', v_rows, 'totals', v_tot, 'sheets', v_n, 'advances', v_adv, 'attendance', v_att,
    'data_needed', (v_n = 0), 'drafts_excluded', true);
end $$;

-- ---------- (f) audited export of these pages ----------
-- The page calls this BEFORE it builds the file and only builds it when this returns without error, so the check is server-side and the audit row exists.
create or replace function public.log_page_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('daybook', 'salary') then raise exception 'unknown_report'; end if;
  if p_key = 'daybook' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('view_daybook', l.id))) then raise exception 'not allowed'; end if;
  if p_key = 'salary' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('salary_view', l.id))) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._db_num(jsonb), public._db_date(text), public._db_int(jsonb), public._db_start(), public.set_daybook_start(date),
  public._daybook_lines(int[], int[], date, date), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.set_daybook_start(date), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

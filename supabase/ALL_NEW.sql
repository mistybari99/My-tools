-- ============================================================
-- BOS tool · Phase 5: fixed brand names, official location names, paper-form numbering and gap audit.
-- Run AFTER phase3.sql and phase4.sql. Run once. Safe to run again (it only updates names and adds an index/functions).
-- ============================================================

-- ---------- brand and location names exactly as in the guidebook (seven locations) ----------
update public.locations set sort = 1, name_bn = 'ইসলামিয়া মিষ্টি ঘর — মেইন শোরুম ও মেইন (মিষ্টি) কারখানা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — Main Showroom ও Main (মিষ্টি) Factory', name_en = 'ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory' where code = 'main';
update public.locations set sort = 2, name_bn = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_en = 'ISLAMIYA MISTY GHAR — 2nd Branch' where code = 'branch2';
update public.locations set sort = 3, name_bn = 'মিষ্টি বাড়ি', name_mix = 'মিষ্টি বাড়ি', name_en = 'MISTY BARI' where code = 'mishti_bari';
update public.locations set sort = 4, name_bn = 'AL-CAKIZ (বাসার নিচে)', name_mix = 'AL-CAKIZ (বাসার নিচে)', name_en = 'AL-CAKIZ (below the residence)' where code = 'al_cakes';
update public.locations set sort = 5, name_bn = 'কেক কারখানা (বাসার নিচে)', name_mix = 'Cake Factory (বাসার নিচে)', name_en = 'Cake Factory (below the residence)' where code = 'cake_factory';
update public.locations set sort = 6, name_bn = 'মুজগুন্নি মিষ্টি কারখানা (বন্ধ, যন্ত্র রাখা)', name_mix = 'মুজগুন্নি মিষ্টি Factory (বন্ধ, যন্ত্র রাখা)', name_en = 'Mujgunni Sweet Factory (closed, machines stored)' where code = 'mishti_factory';
update public.locations set sort = 7, name_bn = 'গোডাউন (ইসলামিয়ার পাশের গলি)', name_mix = 'Godown (ইসলামিয়ার পাশের গলি)', name_en = 'Godown (lane beside ISLAMIYA MISTY GHAR)' where code = 'godown';
update public.settings set value = '"ইসলামিয়া মিষ্টি ঘর"', label_en = 'Business name (fixed, never translated)' where key = 'business_name';
insert into public.settings (key, value, label_bn, label_mix, label_en)
  values ('business_name_latin', '"ISLAMIYA MISTY GHAR"', 'প্রতিষ্ঠানের নাম (ইংরেজি অক্ষরে, স্থির)', 'প্রতিষ্ঠানের Name (Latin, স্থির)', 'Business name in Latin letters (fixed)')
  on conflict (key) do update set value = excluded.value;

-- ---------- paper form number: the printed serial of the numbered paper book, stored in data.paper_no ----------
-- One printed number can be recorded once per form and location (a duplicate is refused by the database).
create unique index if not exists entries_paper_no_uq on public.entries (form_code, location_id, (btrim(data->>'paper_no')))
  where nullif(btrim(data->>'paper_no'), '') is not null;

-- ---------- gap audit: printed numbers that were never entered (a missing page = a missing transaction) ----------
-- The number is the trailing digits of what was typed (A-0012 -> 12). Works only on numbers that were entered.
create or replace function public.number_audit(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss bigint[]; miss_n bigint; unnum bigint;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  with n as (
    select nullif(substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$'), '')::bigint v
    from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is not null)
  select min(v), max(v), count(v) into lo, hi, cnt from n;
  select count(*) into unnum from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is null;
  if cnt is null or cnt = 0 then return jsonb_build_object('entered', 0, 'without_number', unnum, 'missing', '[]'::jsonb, 'missing_count', 0); end if;
  if hi - lo > 100000 then raise exception 'range too wide'; end if;
  select count(*) into miss_n from generate_series(lo, hi) g where not exists (
    select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
      and substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint = g);
  select coalesce(array_agg(g order by g), '{}') into miss from (
    select g from generate_series(lo, hi) g where not exists (
      select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
        and substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint = g) order by g limit 200) m;
  return jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'without_number', unnum, 'missing_count', miss_n, 'missing', to_jsonb(miss));
end $$;

-- one line per form and location that has at least one gap (for the dashboard)
create or replace function public.number_audit_summary() returns table (form_code text, location_id int, entered bigint, first_no bigint, last_no bigint, missing_count bigint)
language sql stable security definer set search_path = public as $$
  with n as (
    select e.form_code, e.location_id, substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint v
    from public.entries e where nullif(btrim(e.data->>'paper_no'), '') is not null and e.data->>'paper_no' ~ '[0-9]\s*$'),
  g as (select form_code, location_id, count(distinct v) c, min(v) lo, max(v) hi from n group by 1, 2)
  select g.form_code, g.location_id, g.c, g.lo, g.hi, (g.hi - g.lo + 1) - g.c
  from g
  where (g.hi - g.lo + 1) - g.c > 0 and g.hi - g.lo <= 100000
    and (public.is_owner() or (public.can_do(g.form_code, 'approve') and public.can_loc(g.location_id)))
  order by 6 desc;
$$;
revoke all on function public.number_audit(text, int), public.number_audit_summary() from public, anon;
grant execute on function public.number_audit(text, int), public.number_audit_summary() to authenticated;
-- ============================================================
-- BOS tool · Phase 6: customers, partial / split payment, due (baki) ledger, wholesale rules, editable option lists.
-- Run AFTER phase3/4/5. Run once. Existing sales are kept (their payments are back-filled).
-- ============================================================

-- ---------- Bangladesh mobile number: 01XXXXXXXXX (accepts +880 / 880 / Bangla digits / spaces / dashes) ----------
create or replace function public.norm_mobile(p text) returns text
language plpgsql immutable as $$
declare d text;
begin
  if p is null then return null; end if;
  if p ~ '[A-Za-z]' then raise exception 'bad_mobile'; end if;
  d := translate(p, '০১২৩৪৫৬৭৮৯', '0123456789');
  d := regexp_replace(d, '[^0-9+]', '', 'g');
  d := regexp_replace(d, '^(\+|00)?880', '0');
  if d ~ '^00[0-9]{10}$' then d := substr(d, 2); end if;
  if d !~ '^01[3-9][0-9]{8}$' then raise exception 'bad_mobile'; end if;
  return d;
end $$;

-- ---------- customers (one row per mobile number) ----------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  mobile text not null unique,
  name text not null,
  type text not null default 'retail' check (type in ('retail', 'wholesale')),
  credit_limit numeric check (credit_limit is null or credit_limit >= 0),   -- set by the owner; empty = no limit written
  note text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create trigger audit_customers after insert or update on public.customers for each row execute function public.log_change('id');

-- ---------- sales: customer, type, amounts paid / due; payments table ----------
alter table public.sales add column customer_id uuid references public.customers(id);
alter table public.sales add column sale_type text not null default 'retail' check (sale_type in ('retail', 'wholesale'));
alter table public.sales add column paid numeric not null default 0;
alter table public.sales add column due_amount numeric not null default 0;
alter table public.sales drop constraint sales_pay_mode_check;
alter table public.sales add constraint sales_pay_mode_check check (pay_mode in ('cash', 'mobile', 'card', 'due', 'split'));
create index sales_customer on public.sales (customer_id);

create table public.sale_payments (
  id bigserial primary key,
  sale_id uuid references public.sales(id),          -- null for a later collection of dues
  customer_id uuid references public.customers(id),
  location_id int not null references public.locations(id),
  kind text not null check (kind in ('sale', 'collection')),
  mode text not null check (mode in ('cash', 'mobile', 'card')),
  wallet text, ref text,                              -- bKash / Nagad ... and the transaction id
  amount numeric not null check (amount > 0),
  paid_at timestamptz not null default now(),
  note text,
  voided boolean not null default false, void_note text,
  created_by uuid, created_staff text,
  client_id uuid
);
create index sale_payments_client on public.sale_payments (client_id) where client_id is not null;
create index sale_payments_cust on public.sale_payments (customer_id) where not voided;
create index sale_payments_day on public.sale_payments (location_id, paid_at);
create trigger audit_sale_payments after insert or update on public.sale_payments for each row execute function public.log_change('id');

-- back-fill: earlier sales were all paid in full by one mode, except 'due' ones (nothing paid)
update public.sales set paid = case when pay_mode = 'due' then 0 else total end, due_amount = case when pay_mode = 'due' then total else 0 end;
insert into public.sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by, created_staff, voided)
  select id, location_id, 'sale', pay_mode, total, sold_at, created_by, created_staff, status = 'void'
  from public.sales where pay_mode in ('cash', 'mobile', 'card') and total > 0;

-- ---------- balance of a customer = what was sold to them - what they paid (voided entries ignored) ----------
create or replace function public.customer_balance(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then
    coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
    - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0) end;
$$;

-- find a customer by mobile (for the sale screen): name, type, limit, current due
create or replace function public.find_customer(p_mobile text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text := public.norm_mobile(p_mobile); c public.customers;
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where mobile = m;
  if not found then return jsonb_build_object('mobile', m, 'found', false); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', c.mobile, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit, 'balance', public.customer_balance(c.id));
end $$;

-- ---------- record a sale (item lines, custom lines, quick lines; split / partial payment; customer rules) ----------
-- Lines: {item_id, qty, price, override?}  list item (price is fixed by the list unless override)
--        {item_id:null, name, qty, price}  an item that is not in the list yet (flagged for the owner)
--        {item_id:null, name, amount}      quick sale
-- Payments: [{mode: cash|mobile|card, amount, wallet?, ref?, tendered?}]. Whatever is not paid stays due.
-- A customer (mobile + name) is REQUIRED when anything is left due and for every wholesale sale.
create or replace function public.record_sale2(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb,
  p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; credit_over boolean := false; em text;
begin
  perform set_config('bos.em_used', '', true);
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if disc = 'NaN'::numeric then raise exception 'bad_discount'; end if;
  disc := round(disc, 2);
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        if public.rule_on('pos_override_manager') and not public.rule_ok('price_override', p_loc) then raise exception 'override_needs_approval'; end if;
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        shown := nullif(ln->>'price', '')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit, 'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    elsif ln ? 'qty' and ln ? 'price' then            -- an item that is not in the list
      qty := (ln->>'qty')::numeric; pr := (ln->>'price')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      if pr is null or pr = 'NaN'::numeric or pr <= 0 then raise exception 'bad_price'; end if;
      if nullif(btrim(ln->>'name'), '') is null then raise exception 'name_required'; end if;
      if public.rule_txt('pos_unlisted') = 'block' then raise exception 'unlisted_blocked'; end if;
      amt := round(qty * pr, 2); any_custom := coalesce(public.rule_txt('pos_unlisted'), 'flag') = 'flag';
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(btrim(ln->>'name'), 80), 'unit', left(coalesce(ln->>'unit', ''), 20), 'qty', qty, 'price', pr, 'amount', amt, 'override', false, 'custom', true);
    else                                              -- quick sale
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name', ''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > 0 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc) then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    amt := (pay->>'amount')::numeric;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    amt := round(amt, 2); paid_sum := paid_sum + amt;
    if not pm = any (modes) then modes := modes || pm; end if;
  end loop;
  if paid_sum > sub - disc then raise exception 'overpaid'; end if;
  due := sub - disc - paid_sum;
  -- customer
  mob := case when nullif(btrim(p_customer_mobile), '') is not null then public.norm_mobile(p_customer_mobile) end;
  needcust := (due > 0 and public.rule_on('pos_customer_on_due')) or (stype = 'wholesale' and public.rule_on('pos_customer_on_wholesale')) or (disc > 0 and public.rule_on('pos_customer_on_discount'));
  if needcust and mob is null and not public.rule_ok('sale_without_customer', p_loc) then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null and coalesce(public.rule_txt('pos_credit_mode'), 'block') <> 'off' then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit then
        credit_over := true;
        if coalesce(public.rule_txt('pos_credit_mode'), 'block') = 'block' and not public.rule_ok('credit_over_limit', p_loc) then raise exception 'over_credit_limit'; end if;
      end if;
    end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
  end loop;
  -- exceptions for the owner (nothing is blocked here except the customer / credit rules above)
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  if any_custom then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unlisted_item', 'yellow', s.total,
        jsonb_build_object('bn', 'রসিদ ' || n || ': তালিকায় নেই এমন আইটেম বিক্রি — আইটেম তালিকায় যোগ করুন', 'en', 'Receipt ' || n || ': an item that is not in the list was sold — add it to the item list'));
  end if;
  if disc > 0 then
    if lim is null or jsonb_typeof(lim) = 'null' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_no_limit', 'yellow', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট দেওয়া হয়েছে কিন্তু ডিসকাউন্টের সীমা সেটিংসে নেই', 'en', 'Receipt ' || n || ': a discount was given but no discount limit is set'));
    elsif disc > (lim #>> '{}')::numeric then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_over_limit', 'red', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট সীমার উপরে', 'en', 'Receipt ' || n || ': discount above the limit'));
    end if;
  end if;
  if credit_over then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
  for em in select unnest(string_to_array(nullif(current_setting('bos.em_used', true), ''), ',')) loop
    if em <> '' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'emergency_used', 'yellow', s.total,
          jsonb_build_object('bn', 'রসিদ ' || n || ': জরুরি অনুমোদনে সেল (' || split_part(em, ':', 2) || ')', 'en', 'Receipt ' || n || ': sold on an emergency approval (' || split_part(em, ':', 2) || ')'));
    end if;
  end loop;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id);
end $$;

-- ---------- collect money from a customer later (pays the oldest dues first, shown by the ledger) ----------
create or replace function public.collect_payment(p_client uuid, p_loc int, p_customer uuid, p_payments jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform 1 from public.customers where id = p_customer for update;      -- one collection at a time per customer
  if not found then raise exception 'customer_not_found'; end if;
  if p_client is not null and exists (select 1 from public.sale_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public.customer_balance(p_customer)); end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := (pay->>'amount')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  bal := coalesce(public.customer_balance(p_customer), 0);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),
              left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot);
end $$;

-- ---------- dues list (who owes what, since when) and one customer's ledger ----------
create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  -- what is still unpaid on each sale = its total - what was paid at the sale; collections then clear the OLDEST unpaid sales first
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select customer_id, sum(amount) coll from public.sale_payments where kind = 'collection' and not voided and customer_id is not null group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;
create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done'
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided)
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

-- ---------- a wrongly entered collection can be reversed (owner or POS approver, with a reason) ----------
create or replace function public.void_collection(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.sale_payments;
begin
  if not public.can_grant('collection_void') then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.sale_payments where id = p_id and kind = 'collection' for update;
  if not found then raise exception 'not found'; end if;
  if p.voided then raise exception 'already void'; end if;
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.sale_payments set voided = true, void_note = btrim(p_note) where id = p_id;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, 'POS', p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'collection_void', 'yellow', p.amount,
      jsonb_build_object('bn', 'বাকি আদায় বাতিল: ' || btrim(p_note), 'en', 'A collection was reversed: ' || btrim(p_note)));
end $$;

-- ---------- void now also voids the sale's payments ----------
create or replace function public.void_sale(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.sales; sid text;
begin
  if not public.can_grant('sale_void') then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into s from public.sales where id = p_id for update;
  if not found then raise exception 'sale not found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.status = 'void' then raise exception 'already void'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.sales set status = 'void', void_by = auth.uid(), void_staff = sid, void_at = now(), void_note = btrim(p_note) where id = p_id;
  update public.sale_payments set voided = true, void_note = btrim(p_note) where sale_id = p_id and not voided;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, s.id, 'POS', s.location_id, s.sale_date, 'sale_void', 'yellow', s.total,
      jsonb_build_object('bn', 'রসিদ ' || s.receipt || ' বাতিল: ' || btrim(p_note), 'en', 'Receipt ' || s.receipt || ' voided: ' || btrim(p_note)));
end $$;

-- the dashboard summary also carries what was left due
drop function if exists public.sales_summary(date);
create function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric, due numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount), sum(s.due_amount)
  from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- money collected by mode and day (dashboard), and the owner's customer-due total ----------
create or replace function public.payments_summary(p_from date) returns table (pay_date date, location_id int, mode text, kind text, total numeric)
language sql stable security definer set search_path = public as $$
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, p.mode, p.kind, sum(p.amount)
  from public.sale_payments p
  where not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_from and public.can_do('POS', 'view') and public.can_loc(p.location_id)
  group by 1, 2, 3, 4;
$$;

-- staff indicator: the due share now comes from what was really left unpaid
create or replace function public.biz_staff(p_from date, p_to date, p_loc int default null)
returns table (staff_id text, n bigint, revenue numeric, discount_pct numeric, void_pct numeric, override_pct numeric,
               quick_pct numeric, due_pct numeric, med_discount_pct numeric, med_void_pct numeric,
               med_override_pct numeric, med_quick_pct numeric, med_due_pct numeric, peers bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ovr as (select s.id, bool_or(e->>'override' = 'true') o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (
    select s.created_staff st,
           count(*) filter (where s.status = 'done') n,
           coalesce(sum(s.total) filter (where s.status = 'done'), 0) rev,
           coalesce(sum(s.discount) filter (where s.status = 'done'), 0) disc,
           count(*) filter (where s.status = 'void') vn,
           count(*) filter (where s.status = 'done' and o.o) onum,
           count(*) filter (where s.status = 'done' and s.quick) qn,
           coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) duea
    from s left join ovr o on o.id = s.id group by s.created_staff),
  r as (
    select p.st, p.n, p.rev,
           case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end dp,
           case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end vp,
           case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end op,
           case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end qp,
           case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end up
    from per p)
  select r.st, r.n, r.rev, r.dp, r.vp, r.op, r.qp, r.up,
         (select (percentile_cont(0.5) within group (order by x.dp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.vp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.op))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.qp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.up))::numeric from r x),
         (select count(*) from r)
  from r order by r.rev desc;
end $$;

-- ---------- editable option lists (owner edits them in the app; forms read them) ----------
create table public.option_lists (
  list_code text not null, value_code text not null,
  label_bn text not null, label_mix text, label_en text,
  sort int not null default 0, active boolean not null default true,
  extra jsonb not null default '{}',
  primary key (list_code, value_code)
);
create trigger audit_option_lists after insert or update or delete on public.option_lists for each row execute function public.log_change('list_code,value_code');
alter table public.option_lists enable row level security;
create policy option_lists_read on public.option_lists for select to authenticated using (public.is_active());
create policy option_lists_owner on public.option_lists for all to authenticated using (public.is_owner()) with check (public.is_owner());
grant select, insert, update, delete on public.option_lists to authenticated;

insert into public.option_lists (list_code, value_code, label_bn, label_en, sort) values
 ('expense_heads', 'staff_meal', 'স্টাফের খাবার / নাস্তা', 'Staff meals / snacks', 1), ('expense_heads', 'transport', 'যাতায়াত / পরিবহন', 'Transport', 2),
 ('expense_heads', 'hospitality', 'কাস্টমার আপ্যায়ন', 'Customer hospitality', 3), ('expense_heads', 'repair', 'মেরামত / ইউটিলিটি', 'Repairs / utilities', 4),
 ('expense_heads', 'labour', 'অস্থায়ী শ্রমিকের মজুরি', 'Temporary labour wages', 5), ('expense_heads', 'sourcing', 'বাইরের সোর্সিংয়ের মালামাল', 'Outside-sourced goods', 6),
 ('expense_heads', 'other', 'অন্যান্য (লিখুন)', 'Other (write it)', 7),
 ('marketing_heads', '1', 'অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)', 'Online ads & boost (with VAT)', 1), ('marketing_heads', '2', 'কনটেন্ট তৈরি', 'Content creation', 2),
 ('marketing_heads', '3', 'ছাপা', 'Printing', 3), ('marketing_heads', '4', 'স্যাম্পল ও ট্রায়াল', 'Samples & trials', 4),
 ('marketing_heads', '5', 'অফার ও ছাড়ের ক্যাম্পেইন', 'Offer & discount campaigns', 5), ('marketing_heads', '6', 'ডেলিভারি ভর্তুকি', 'Delivery subsidy', 6),
 ('marketing_heads', '7', 'প্ল্যাটফর্ম কমিশন', 'Platform commission', 7), ('marketing_heads', '8', 'উৎসব ও ইভেন্ট', 'Festivals & events', 8),
 ('marketing_heads', '9', 'পার্টনার', 'Partners', 9), ('marketing_heads', '10', 'অন্যান্য (লিখুন)', 'Other (write it)', 10),
 ('wallets', 'bkash', 'বিকাশ', 'bKash', 1), ('wallets', 'nagad', 'Nagad (নগদ)', 'Nagad', 2), ('wallets', 'rocket', 'রকেট', 'Rocket', 3), ('wallets', 'upay', 'উপায়', 'Upay', 4);

-- ---------- privileges and row level security ----------
alter table public.customers enable row level security;
alter table public.sale_payments enable row level security;
create policy customers_read on public.customers for select to authenticated using (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
create policy customers_owner_write on public.customers for update to authenticated using (public.is_owner()) with check (public.is_owner());
create policy sale_payments_read on public.sale_payments for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
grant select on public.customers, public.sale_payments to authenticated;
grant update (credit_limit, note, active, type, name) on public.customers to authenticated;      -- the owner only (policy above)
revoke all on function public.norm_mobile(text), public.customer_balance(uuid), public.find_customer(text),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz),
  public.collect_payment(uuid, int, uuid, jsonb, text), public.customer_dues(), public.customer_ledger(uuid), public.payments_summary(date),
  public.void_sale(uuid, text), public.biz_staff(date, date, int), public.void_collection(bigint, text) from public, anon;
grant execute on function public.norm_mobile(text), public.customer_balance(uuid), public.find_customer(text),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz),
  public.collect_payment(uuid, int, uuid, jsonb, text), public.customer_dues(), public.customer_ledger(uuid), public.payments_summary(date),
  public.void_sale(uuid, text), public.biz_staff(date, date, int), public.void_collection(bigint, text) to authenticated;

-- ---------- books-closed date: after the owner closes a period (Rules page), changes dated on or before it need the grant or an emergency approval ----------
create or replace function public.lock_check(p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null) then return; end if;
  raise exception 'period_closed';
end $$;
create or replace function public.entries_lock() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then perform public.lock_check(old.entry_date); end if;
  perform public.lock_check(new.entry_date);
  return new;
end $$;
create trigger entries_lock before insert or update on public.entries for each row execute function public.entries_lock();
create or replace function public.sales_lock() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then perform public.lock_check(old.sale_date); end if;
  perform public.lock_check(new.sale_date);
  return new;
end $$;
create trigger sales_lock before insert or update on public.sales for each row execute function public.sales_lock();
revoke all on function public.lock_check(date) from public, anon;
-- ============================================================
-- BOS tool · Phase 7: business RULES the owner can edit, role GRANTS (who may do what), EMERGENCY requests.
-- Run AFTER phase6 (phase5/6/7 together are in ALL_NEW.sql). Run once.
--
-- Rules  : switches, numbers and choices (e.g. "customer mobile needed on a due sale: on/off").
-- Grants : which role may do a controlled action (e.g. give a discount above the limit). Owner always may.
-- Emergency: a staff member who is blocked by a rule asks at once; the owner approves for a short time (one use or a
--            short window) and later decides in the Rules page which roles should get the grant for good.
-- ============================================================

-- ---------- rules ----------
create table public.rules (
  key text primary key,
  module text not null,                                   -- pos | books | emergency | entries ...
  kind text not null check (kind in ('switch', 'number', 'text', 'choice')),
  value jsonb,                                            -- null = use the default
  default_value jsonb,
  unit text, choices jsonb,                               -- choices: ["block","warn","off"]
  label_bn text not null, label_mix text, label_en text,
  hint_bn text, hint_mix text, hint_en text,
  sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid
);
create trigger audit_rules after insert or update on public.rules for each row execute function public.log_change('key');
alter table public.rules enable row level security;
create policy rules_read on public.rules for select to authenticated using (public.is_active());
grant select on public.rules to authenticated;

create or replace function public.rule_val(p_key text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(value, default_value) from public.rules where key = p_key;
$$;
create or replace function public.rule_on(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.rule_val(p_key) #>> '{}')::boolean, false);
$$;
create or replace function public.rule_num(p_key text) returns numeric
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '')::numeric;
$$;
create or replace function public.rule_txt(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '');
$$;

-- owner changes a rule (validated by its kind); p_value null = back to the default
create or replace function public.set_rule(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rules;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.rules where key = p_key;
  if not found then raise exception 'rule not found'; end if;
  if p_value is not null and jsonb_typeof(p_value) <> 'null' then
    if r.kind = 'switch' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'bad_value'; end if;
    if r.kind = 'number' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric < 0) then raise exception 'bad_value'; end if;
    if r.kind = 'choice' and not (r.choices @> jsonb_build_array(p_value #>> '{}')) then raise exception 'bad_value'; end if;
    if r.kind = 'text' and jsonb_typeof(p_value) <> 'string' then raise exception 'bad_value'; end if;
    if p_key = 'period_closed_until' then
      if (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
      begin perform (p_value #>> '{}')::date; exception when others then raise exception 'bad_value'; end;
    end if;
  end if;
  update public.rules set value = case when p_value is null or jsonb_typeof(p_value) = 'null' then null else p_value end, updated_at = now(), updated_by = auth.uid() where key = p_key;
end $$;

insert into public.rules (key, module, kind, default_value, unit, choices, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pos_customer_on_due', 'pos', 'switch', 'true', null, null, 'বাকি রেখে সেল করলে গ্রাহকের মোবাইল নম্বর ও নাম লাগবে', 'Due রেখে sale করলে Customer এর mobile number ও নাম লাগবে', 'A customer mobile number and name are required when anything is left due', 'বন্ধ করলে বাকির সেল গ্রাহক ছাড়াই হবে — সুপারিশ করা হয় না', 'If off, a due sale can be made without a customer — not recommended', 10),
 ('pos_customer_on_wholesale', 'pos', 'switch', 'true', null, null, 'পাইকারি সেলে গ্রাহক লাগবে', 'Wholesale sale এ Customer লাগবে', 'A customer is required on every wholesale sale', null, null, 11),
 ('pos_customer_on_discount', 'pos', 'switch', 'false', null, null, 'যেকোনো ডিসকাউন্টে গ্রাহক লাগবে (খুচরা সহ)', 'যেকোনো Discount এ Customer লাগবে (retail সহ)', 'A customer is required on any discount, retail included', null, null, 12),
 ('pos_discount_manager', 'pos', 'switch', 'true', null, null, 'ডিসকাউন্ট সীমার উপরে (বা সীমা লেখা না থাকলে) নির্ধারিত ভূমিকা লাগবে', 'Discount limit এর উপরে (বা limit না থাকলে) নির্ধারিত role লাগবে', 'A granted role is needed for a discount above the limit (or when no limit is written)', 'কে পারবে তা নিচের "কে কী পারবে" ছকে ঠিক হয়', 'Who may is set in the "Who may do what" grid below', 13),
 ('pos_override_manager', 'pos', 'switch', 'true', null, null, 'তালিকার দাম বদলাতে নির্ধারিত ভূমিকা লাগবে', 'List এর দাম বদলাতে নির্ধারিত role লাগবে', 'A granted role is needed to change a list price', null, null, 14),
 ('pos_credit_mode', 'pos', 'choice', '"block"', null, '["block","warn","off"]', 'গ্রাহকের বাকির সীমা পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'Customer এর credit limit পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'When a customer’s credit limit is exceeded: block, warn only, or off', null, null, 15),
 ('pos_unlisted', 'pos', 'choice', '"flag"', null, '["allow","flag","block"]', 'তালিকায় নেই এমন আইটেম বিক্রি: allow = চলবে, flag = চলবে আর মালিককে জানাবে, block = আটকাবে', 'List এ নেই এমন item বিক্রি: allow, flag (মালিককে জানাবে), block', 'Selling an item that is not in the list: allow, flag (tell the owner), or block', null, null, 16),
 ('pos_offline_hours', 'pos', 'number', '72', 'ঘণ্টা', null, 'ফোনে জমা থাকা সেল কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'ফোনে জমা sale কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'How many hours an offline sale keeps its own time', 'এর পরে পাঠালে সেটা পাঠানোর সময়ে বসে', 'Sent later than this, it takes the time it was sent', 17),
 ('period_closed_until', 'books', 'text', null, 'YYYY-MM-DD', null, 'হিসাব বন্ধের তারিখ — এই তারিখ পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'হিসাব বন্ধের date — এই date পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'Books closed until — changing anything dated up to this day needs permission', 'যেমন 2026-09-30। ফাঁকা = কিছু বন্ধ নয়। মালিক সবসময় পারেন', 'e.g. 2026-09-30. Empty = nothing closed. The owner always may', 20),
 ('entry_paper_no_required', 'entries', 'switch', 'false', null, null, 'ফর্ম জমা দিতে কাগজের ছাপা নম্বর বাধ্যতামূলক', 'Form জমা দিতে কাগজের ছাপা number বাধ্যতামূলক', 'The printed paper number is required to submit a form', 'কাগজের ফর্ম আর অ্যাপ একসাথে চালালে চালু করুন', 'Turn on when paper forms run alongside the app', 30),
 ('em_enabled', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চালু', 'জরুরি request চালু', 'Emergency requests are on', 'বন্ধ করলে স্টাফ আটকে গেলে অনুরোধ পাঠাতে পারবে না', 'If off, a blocked staff member cannot send a request', 40),
 ('em_minutes', 'emergency', 'number', '30', 'মিনিট', null, 'জরুরি অনুমোদন কত মিনিট চলবে', 'জরুরি অনুমোদন কত minute চলবে', 'How many minutes an emergency approval lasts', 'এই সময়ের মধ্যে ব্যবহার না হলে মেয়াদ শেষ', 'It expires if unused in this time', 41),
 ('em_discount', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: সীমার উপরে ডিসকাউন্ট', 'জরুরি request চলবে: limit এর উপরে discount', 'Emergency allowed for: discount above the limit', null, null, 42),
 ('em_price', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: দাম বদল', 'জরুরি request চলবে: দাম বদল', 'Emergency allowed for: price change', null, null, 43),
 ('em_credit', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: বাকির সীমা পার', 'জরুরি request চলবে: credit limit পার', 'Emergency allowed for: credit limit exceeded', null, null, 44),
 ('em_customer', 'emergency', 'switch', 'false', null, null, 'জরুরি অনুরোধ চলবে: গ্রাহকের মোবাইল ছাড়া সেল', 'জরুরি request চলবে: Customer এর mobile ছাড়া sale', 'Emergency allowed for: a sale without the customer mobile', 'ডিফল্টে বন্ধ — মোবাইল নম্বর নিয়ম কড়া রাখতে', 'Off by default — keeps the mobile-number rule strict', 45),
 ('em_period', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: বন্ধ হিসাবের তারিখে এন্ট্রি', 'জরুরি request চলবে: বন্ধ হিসাবের date এ entry', 'Emergency allowed for: an entry in a closed period', null, null, 46),
 ('em_access', 'emergency', 'switch', 'true', null, null, 'জরুরি অনুরোধ চলবে: যে ফর্ম বা লোকেশনে অনুমতি নেই', 'জরুরি request চলবে: যে form বা location এ অনুমতি নেই', 'Emergency allowed for: a form or location the person has no access to', null, null, 47);

-- ---------- grants: which role may do a controlled action ----------
create table public.rule_grants (
  grant_code text not null, role_code text not null references public.roles(code) on delete cascade,
  allowed boolean not null default true,
  primary key (grant_code, role_code)
);
create table public.grant_defs (
  grant_code text primary key, module text not null, sort int not null default 0,
  label_bn text not null, label_mix text, label_en text,
  window_type text not null default 'once' check (window_type in ('once', 'window')),     -- an emergency approval is used once, or lasts a short window
  emergency_rule text                                                                        -- the rule switch that allows an emergency request for it
);
create trigger audit_rule_grants after insert or update or delete on public.rule_grants for each row execute function public.log_change('grant_code,role_code');
alter table public.rule_grants enable row level security;
alter table public.grant_defs enable row level security;
create policy rule_grants_read on public.rule_grants for select to authenticated using (public.is_active());
create policy grant_defs_read on public.grant_defs for select to authenticated using (public.is_active());
grant select on public.rule_grants, public.grant_defs to authenticated;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('discount_over_limit', 'pos', 1, 'সীমার উপরে ডিসকাউন্ট দেওয়া', 'Limit এর উপরে discount দেওয়া', 'Give a discount above the limit', 'once', 'em_discount'),
 ('price_override', 'pos', 2, 'তালিকার দাম বদলানো', 'List এর দাম বদলানো', 'Change a list price', 'once', 'em_price'),
 ('credit_over_limit', 'pos', 3, 'গ্রাহকের বাকির সীমার উপরে বাকি দেওয়া', 'Customer এর credit limit এর উপরে due দেওয়া', 'Give credit above a customer’s limit', 'once', 'em_credit'),
 ('sale_without_customer', 'pos', 4, 'গ্রাহকের মোবাইল ছাড়া বাকি/পাইকারি সেল', 'Customer এর mobile ছাড়া due/wholesale sale', 'Make a due / wholesale sale without the customer mobile', 'once', 'em_customer'),
 ('sale_void', 'pos', 5, 'সেল বাতিল করা', 'Sale বাতিল করা', 'Void a sale', 'once', null),
 ('collection_void', 'pos', 6, 'বাকি আদায় বাতিল করা', 'বাকি আদায় বাতিল করা', 'Reverse a collection', 'once', null),
 ('closed_period_edit', 'books', 7, 'বন্ধ হিসাবের তারিখে এন্ট্রি দেওয়া/বদলানো', 'বন্ধ হিসাবের date এ entry দেওয়া/বদলানো', 'Enter or change something in a closed period', 'window', 'em_period'),
 ('form_access', 'access', 8, 'অনুমতি নেই এমন ফর্মে এন্ট্রি (অস্থায়ী)', 'অনুমতি নেই এমন form এ entry (অস্থায়ী)', 'Use a form without the permission (temporary)', 'window', 'em_access'),
 ('loc_access', 'access', 9, 'নিজের নয় এমন লোকেশনে কাজ (অস্থায়ী)', 'নিজের নয় এমন location এ কাজ (অস্থায়ী)', 'Work at a location that is not theirs (temporary)', 'window', 'em_access'),
 ('emergency_decide', 'emergency', 10, 'জরুরি অনুরোধ অনুমোদন করা', 'জরুরি request অনুমোদন করা', 'Decide emergency requests', 'once', null);
-- start the same as today: whoever could approve on the POS form keeps these grants
insert into public.rule_grants (grant_code, role_code)
  select g.grant_code, p.role_code from public.role_form_perms p
  cross join (values ('discount_over_limit'), ('price_override'), ('credit_over_limit'), ('sale_void'), ('collection_void')) g(grant_code)
  where p.form_code = 'POS' and p.can_approve
  on conflict do nothing;

create or replace function public.can_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and exists (
    select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = p_code and g.allowed
    join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid()));
$$;
create or replace function public.set_grant(p_code text, p_role text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_code) then raise exception 'unknown grant'; end if;
  if p_role = 'owner' then return; end if;
  if p_allowed then insert into public.rule_grants (grant_code, role_code) values (p_code, p_role) on conflict (grant_code, role_code) do update set allowed = true;
  else delete from public.rule_grants where grant_code = p_code and role_code = p_role; end if;
end $$;

-- ---------- emergency requests ----------
create table public.emergency_requests (
  id bigserial primary key,
  grant_code text not null references public.grant_defs(grant_code),
  requested_by uuid not null, requested_staff text, location_id int,
  context jsonb not null default '{}',                       -- what was attempted, e.g. {"discount":120} or {"form":"10-2","action":"enter"}
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'used', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  valid_until timestamptz, used_at timestamptz, used_ref text
);
create index emergency_open on public.emergency_requests (status, created_at desc);
create index emergency_user on public.emergency_requests (requested_by, grant_code, status);
create trigger audit_emergency after insert or update on public.emergency_requests for each row execute function public.log_change('id');
alter table public.emergency_requests enable row level security;
create policy emergency_read on public.emergency_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_grant('emergency_decide'));
grant select on public.emergency_requests to authenticated;

create or replace function public.request_emergency(p_grant text, p_loc int, p_context jsonb, p_reason text) returns bigint
language plpgsql security definer set search_path = public as $$
declare d public.grant_defs; sid text; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('em_enabled') then raise exception 'emergency_off'; end if;
  select * into d from public.grant_defs where grant_code = p_grant;
  if not found or d.emergency_rule is null then raise exception 'emergency_not_available'; end if;
  if not public.rule_on(d.emergency_rule) then raise exception 'emergency_off'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if (select count(*) from public.emergency_requests where requested_by = auth.uid() and status = 'pending') >= 5 then raise exception 'too_many_pending'; end if;
  if length(coalesce(p_context, '{}')::text) > 2000 then raise exception 'bad_context'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.emergency_requests (grant_code, requested_by, requested_staff, location_id, context, reason)
    values (p_grant, auth.uid(), sid, p_loc, coalesce(p_context, '{}'), left(btrim(p_reason), 300)) returning id into nid;
  return nid;
end $$;

create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.requested_by = auth.uid() and not public.is_owner() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;

create or replace function public.cancel_emergency(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.emergency_requests set status = 'cancelled' where id = p_id and requested_by = auth.uid() and status = 'pending';
end $$;

-- use an approved request: 'once' grants are consumed, 'window' grants stay valid until they expire
create or replace function public.use_emergency(p_grant text, p_loc int, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; w text;
begin
  select * into r from public.emergency_requests
    where requested_by = auth.uid() and grant_code = p_grant and status = 'approved' and valid_until > now() and (location_id is null or p_loc is null or location_id = p_loc)
    order by id limit 1 for update;
  if not found then return false; end if;
  select window_type into w from public.grant_defs where grant_code = p_grant;
  if w = 'once' then update public.emergency_requests set status = 'used', used_at = now(), used_ref = left(p_ref, 80) where id = r.id; end if;
  perform set_config('bos.em_used', coalesce(current_setting('bos.em_used', true), '') || ',' || r.id || ':' || p_grant, true);
  return true;
end $$;
create or replace function public.rule_ok(p_grant text, p_loc int) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.can_grant(p_grant) or public.use_emergency(p_grant, p_loc, 'rule');
end $$;

-- approved requests that were never used become 'expired' when looked at
create or replace function public.my_emergency() returns table (id bigint, grant_code text, status text, reason text, decision_note text, created_at timestamptz, valid_until timestamptz, context jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.grant_code, case when r.status = 'approved' and r.valid_until <= now() then 'expired' else r.status end, r.reason, r.decision_note, r.created_at, r.valid_until, r.context
  from public.emergency_requests r where r.requested_by = auth.uid() and r.created_at > now() - interval '2 days' order by r.id desc limit 30;
$$;

-- a short-window emergency approval also opens a form or a location for that person
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (
    public.is_active() and (exists (
      select 1 from public.user_roles ur
      join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = auth.uid()
        and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                          when 'approve' then p.can_approve else false end)
    or (p_action in ('view', 'enter') and exists (
      select 1 from public.emergency_requests e
      where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
        and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view')))));
$$;
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
    or exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved' and e.valid_until > now()
               and (e.context->>'loc')::int = p_loc));
$$;

-- the printed paper number can be made mandatory for submitting a form
create or replace function public.entries_paper_required() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' and (tg_op = 'INSERT' or old.status is distinct from 'submitted') and public.rule_on('entry_paper_no_required')
     and nullif(btrim(new.data->>'paper_no'), '') is null then raise exception 'paper_no_required'; end if;
  return new;
end $$;
create trigger entries_paper_required before insert or update on public.entries for each row execute function public.entries_paper_required();

revoke all on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.use_emergency(text, int, text), public.rule_ok(text, int), public.my_emergency() from public, anon;
grant execute on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.my_emergency() to authenticated;

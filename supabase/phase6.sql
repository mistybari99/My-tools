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
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - interval '3 days' then at_ := now(); end if;
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
        if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'override_needs_approval'; end if;
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
      amt := round(qty * pr, 2); any_custom := true;
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
  if disc > 0 and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'discount_needs_approval'; end if;   -- no limit written = approver needed
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
  if (due > 0 or stype = 'wholesale') and mob is null then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'over_credit_limit'; end if;
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
  if cust.id is not null and due > 0 and cust.credit_limit is not null and coalesce(public.customer_balance(cust.id), 0) > cust.credit_limit then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
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
  if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
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
  if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
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

-- ---------- books-closed date: after the owner closes a period, only the owner can add or change anything dated on or before it ----------
insert into public.settings (key, value, label_bn, label_mix, label_en)
  values ('books_closed_until', null, 'হিসাব বন্ধের তারিখ (এই তারিখ পর্যন্ত শুধু মালিক বদলাতে পারবেন) — যেমন 2026-09-30', 'হিসাব বন্ধের তারিখ (এই date পর্যন্ত শুধু Owner বদলাতে পারবেন) — যেমন 2026-09-30', 'Books closed until (only the owner can change anything up to this date), e.g. 2026-09-30')
  on conflict (key) do nothing;
create or replace function public.lock_check(p_date date) returns void
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  select value into v from public.settings where key = 'books_closed_until';
  if v is null or jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := (v #>> '{}')::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date <= d then raise exception 'period_closed'; end if;
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

-- ============================================================
-- Phase 99 (bos99) - STEP Opt: two OPTIONS the owner can switch at any time (both default = today's behaviour; the system only shows a recommendation).
--   Needs phases 72..98 (guard below; phase98 = step INT3, the final merge of _acct_docs of 96 + 97). Paste order: ... phase94, phase96, phase97, phase98, phase99 (LAST).
--   phase98 does not touch the five functions re-created here, and phase99 does not touch _acct_docs; if phase98 or phase89 is ever pasted again nothing of phase99 is lost.
--   Additive + paste-twice safe. Re-created (latest definitions, only lines tagged bos99 differ): inbox_list, inbox_get, online_orders_list, online_order_get, telegram_chat_info.
--   Nothing else existing is re-created: the payment hooks are TRIGGERS on cost_source_bills / purchase_bills / supplier_payments (no function of phase75/82/87/89 is touched).
--
--   DECISION 1 - does a saved cost bill / purchase bill create a payment record by itself?
--     rule cost_bill_creates_payment      off (DEFAULT = today: a cost bill is information only) | ask | auto_cash | auto_bank | auto_by_supplier_default
--     rule purchase_bill_creates_payment  same five values (purchase bill: acts when the bill is POSTED)
--     rule bill_void_payment_mode         void (DEFAULT) | keep_credit    what happens to a payment made through this feature when its bill is voided
--     rule bill_pay_auto_credit_ok        switch, DEFAULT off: auto modes never pay a bill of a party marked "credit terms" (supplier credit_days > 0 or the credit flag) unless on
--     rules bill_pay_large_amount / bill_pay_small_cash_max   numbers the OWNER types (blank = none, nothing built in) used only by payment_recommendation()
--     The payment is the SAME record the rest of the system already counts: a purchase bill payment = supplier_payments (bill_id set, purchase_bills.paid updated);
--     a cost bill payment = quick_expenses (path A of the expense domain: path_guard 'expense' respected, locked shadow 10-2 owed at day end, client_id idempotent,
--     journal source quick_expense unique by je_source_uq, void = status void -> the engine posts the reversing entry). Mode "other" on a cost bill is a NOTE ONLY row
--     (not in the cash book / journal, said so on screen). bill_payments99 is the link ledger (append-only; only active -> void | kept_credit).
--     Never twice: remaining = bill - what is paid (purchase: the supplier open amount after oldest-first credit); a 10-2 or quick expense that looks like the same cost
--     gives a warning that must be confirmed (auto modes skip instead and leave a yellow flag).
--     payment_recommendation(kind, ref): ask for large / credit-term bills, auto_cash (or auto_bank) for small no-credit bills of a party whose default mode is cash (bank), else ask.
--   DECISION 2 - inbox customer phone / address masking.
--     rule inbox_pii_mode  off (DEFAULT = today) | mask_phone | mask_phone_address | mask_all_pii. inbox_pii_guard_on is untouched (guard on = people without the contact right see nothing, as today).
--     inbox_unmask(kind, id, reason): the person with grant inbox_unmask (owner always) reveals ONE message / order; every reveal is written to inbox_unmask_log99 (who, when, which
--     message / order, which fields, reason) and to audit_log; rule inbox_unmask_daily_max (owner types, blank = none; the owner himself is not limited).
--     NOT masked by this rule: direct table reads of online_orders.customer_mobile / address (use inbox_pii_guard_on for that) and the order edit form of salesx.js.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.set_doc_template(text,text,integer)'), ('94', 'public._scan_photo_ok(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.drawer_events') is null then miss := miss || ' 95'; end if;
  if to_regclass('public.opening_stock_actions96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos98%' then miss := miss || ' 98'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)') is null
     or pg_get_functiondef('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure) not like '%bos72%' then miss := miss || ' 79'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is not null
     and pg_get_functiondef('public._cogs_lines72(date,date,integer[])'::regprocedure) not like '%bos89%' then miss := miss || ' 89'; end if;
  if miss <> '' then
    raise exception 'phase99 needs phases 72..98 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cost_bill_creates_payment', 'purchase', 'choice', '"off"', null, '["off","ask","auto_cash","auto_bank","auto_by_supplier_default"]'::jsonb, null, null,
  'cost bill সেভ করলে payment এন্ট্রি হবে কি?', 'Cost bill save করলে payment entry হবে কি?', 'Does saving a cost bill create a payment?',
  'off = আজকের নিয়ম (bill শুধু তথ্য)। ask = সেভের পর "এখনই payment লিখবেন?" জিজ্ঞেস করবে। auto_* = নিজে লিখবে (credit-শর্তের পক্ষ বাদ)।',
  'off = today (a cost bill is information only). ask = after saving it offers "Record payment now?". auto_* = records it by itself (parties with credit terms are skipped).', 641),
 ('purchase_bill_creates_payment', 'purchase', 'choice', '"off"', null, '["off","ask","auto_cash","auto_bank","auto_by_supplier_default"]'::jsonb, null, null,
  'purchase bill পোস্ট করলে payment এন্ট্রি হবে কি?', 'Purchase bill post করলে payment entry হবে কি?', 'Does posting a purchase bill create a payment?',
  'off = আজকের নিয়ম (payment আলাদা বা পোস্টের সময় লেখা)। ask = পোস্টের পর জিজ্ঞেস করবে। auto_* = বাকি পুরোটা নিজে লিখবে (credit-শর্তের supplier বাদ)।',
  'off = today (payment is written separately or at posting). ask = offers it after posting. auto_* = pays the whole open amount by itself (suppliers with credit terms are skipped).', 642),
 ('bill_void_payment_mode', 'purchase', 'choice', '"void"', null, '["void","keep_credit"]'::jsonb, null, null,
  'bill বাতিল হলে এই সুবিধায় লেখা payment-এর কী হবে?', 'Bill void হলে এই feature-এ লেখা payment-এর কী হবে?', 'When the bill is voided, what happens to a payment made through this option?',
  'void = payment-ও বাতিল (উল্টো এন্ট্রি যায়)। keep_credit = payment থাকে; ক্রয়ে supplier-এর credit হয়ে যায়।',
  'void = the payment is voided too (a reversing entry follows). keep_credit = the payment stays; for a purchase it becomes supplier credit.', 643),
 ('bill_pay_auto_credit_ok', 'purchase', 'switch', 'false', null, null, null, null,
  'credit-শর্তের পক্ষেও auto payment চলবে', 'Credit-terms এর পক্ষেও auto payment চলবে', 'Allow auto payment for parties with credit terms',
  'বন্ধ থাকলে auto mode কখনো credit-শর্তের supplier/source-এর bill শোধ করে না।', 'When off, an auto mode never pays a bill of a supplier / source that has credit terms.', 644),
 ('bill_pay_large_amount', 'purchase', 'number', null, 'টাকা', null, 0, 1000000000000, 'বড় bill-এর সীমা (প্রস্তাবনার জন্য)', 'Large bill এর সীমা (recommendation এর জন্য)', 'Large bill amount (for the recommendation)',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। এর সমান বা বেশি হলে প্রস্তাব সবসময় "ask"।', 'You type it; blank = none. At or above it the recommendation is always "ask".', 645),
 ('bill_pay_small_cash_max', 'purchase', 'number', null, 'টাকা', null, 0, 1000000000000, 'ছোট cash bill-এর সীমা (প্রস্তাবনার জন্য)', 'Small cash bill এর সীমা (recommendation এর জন্য)', 'Small cash bill amount (for the recommendation)',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। এর সমান বা কম, credit ছাড়া, cash পক্ষের bill-এ প্রস্তাব "auto_cash"।', 'You type it; blank = none. At or below it, with no credit and a cash party, the recommendation is "auto_cash".', 646),
 ('inbox_pii_mode', 'pos', 'choice', '"off"', null, '["off","mask_phone","mask_phone_address","mask_all_pii"]'::jsonb, null, null,
  'inbox-এ গ্রাহকের তথ্য ঢাকা', 'Inbox এ customer এর তথ্য ঢাকা', 'Mask customer details in the inbox',
  'off = আজকের নিয়ম। mask_phone = phone ঢাকা। mask_phone_address = phone ও address ঢাকা। mask_all_pii = নাম, handle, message-এর লেখা ও attachmentও ঢাকা। অনুমতিপ্রাপ্ত মানুষ একটি একটি করে খুলতে পারেন (log-এ থাকে)।',
  'off = today. mask_phone = phone hidden. mask_phone_address = phone and address hidden. mask_all_pii = name, handle, message text and attachment hidden too. Authorised people reveal one at a time (logged).', 647),
 ('inbox_unmask_daily_max', 'pos', 'number', null, 'বার', null, 1, 100000, 'একজন দিনে সর্বোচ্চ কতবার খুলতে পারবে', 'একজন দিনে সর্বোচ্চ কতবার unmask করতে পারবে', 'Max reveals per person per day',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। মালিকের ওপর সীমা খাটে না।', 'You type it; blank = no limit. The owner is not limited.', 648)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'inbox_unmask', 'pos', 96, 'inbox-এ ঢাকা গ্রাহকের তথ্য খোলা (প্রতিবার log-এ থাকে)', 'Inbox এ ঢাকা customer এর তথ্য খোলা (প্রতিবার log এ থাকে)', 'Reveal masked customer details in the inbox (every reveal is logged)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'inbox_unmask');

-- ---------- tables ----------
-- per supplier / per cost source: the usual payment mode and "has credit terms". Owner writes only (bill_pay_default_set99).
create table if not exists public.bill_pay_defaults99 (
  id bigserial primary key,
  party_kind text not null check (party_kind in ('supplier', 'cost_source')),
  party_id text not null check (char_length(party_id) between 1 and 60),
  pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile', 'card')),
  credit_terms boolean not null default false,
  note text check (note is null or char_length(note) <= 200),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (party_kind, party_id)
);
drop trigger if exists audit_bill_pay_defaults99 on public.bill_pay_defaults99;
create trigger audit_bill_pay_defaults99 after insert or update on public.bill_pay_defaults99 for each row execute function public.log_change('id');
alter table public.bill_pay_defaults99 enable row level security;
revoke all on public.bill_pay_defaults99 from public, anon, authenticated;
drop policy if exists bill_pay_defaults99_sel on public.bill_pay_defaults99;
create policy bill_pay_defaults99_sel on public.bill_pay_defaults99 for select to authenticated using (public.is_owner());

-- the link ledger: one row per payment made through this option (the money itself lives in quick_expenses / supplier_payments)
create table if not exists public.bill_payments99 (
  id bigserial primary key,
  bill_kind text not null check (bill_kind in ('cost', 'purchase')),
  bill_ref text not null,
  location_id int references public.locations(id),
  mode text not null check (mode in ('cash', 'bank', 'mobile', 'card', 'other')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  origin text not null check (origin in ('auto', 'ask')),
  money_type text not null check (money_type in ('quick_expense', 'supplier_payment', 'note_only')),
  money_ref text,
  status text not null default 'active' check (status in ('active', 'void', 'kept_credit')),
  note text check (note is null or char_length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  closed_by uuid, closed_at timestamptz, closed_note text
);
create index if not exists bp99_bill on public.bill_payments99 (bill_kind, bill_ref);
create unique index if not exists bp99_auto_once on public.bill_payments99 (bill_kind, bill_ref) where origin = 'auto' and status = 'active';
drop trigger if exists audit_bill_payments99 on public.bill_payments99;
create trigger audit_bill_payments99 after insert or update on public.bill_payments99 for each row execute function public.log_change('id');
create or replace function public._bp_ro99() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'active' and new.status in ('void', 'kept_credit')
     and (to_jsonb(new) - 'status' - 'closed_by' - 'closed_at' - 'closed_note') = (to_jsonb(old) - 'status' - 'closed_by' - 'closed_at' - 'closed_note') then return new; end if;
  raise exception 'append_only: a bill payment row cannot be changed or deleted (it can only be voided or kept as credit)';
end $$;
drop trigger if exists bp99_ro on public.bill_payments99;
create trigger bp99_ro before update or delete on public.bill_payments99 for each row execute function public._bp_ro99();
alter table public.bill_payments99 enable row level security;
revoke all on public.bill_payments99 from public, anon, authenticated;
grant select on public.bill_payments99 to authenticated;
drop policy if exists bill_payments99_sel on public.bill_payments99;
create policy bill_payments99_sel on public.bill_payments99 for select to authenticated
  using (public.is_owner() or (public.can_loc(location_id) and (case when bill_kind = 'cost' then public._cs_view() else public._pur_ok(location_id) end)));

-- append-only log of every reveal of masked customer details
create table if not exists public.inbox_unmask_log99 (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  kind text not null check (kind in ('message', 'order')),
  ref_id text not null,
  location_id int,
  fields text,
  reason text check (reason is null or char_length(reason) <= 300),
  outcome text not null check (outcome in ('revealed', 'blocked'))
);
create index if not exists iul99_user_day on public.inbox_unmask_log99 (user_id, at);
create or replace function public._inb_unmask_ro99() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the reveal log cannot be changed or deleted'; end $$;
drop trigger if exists iul99_ro on public.inbox_unmask_log99;
create trigger iul99_ro before update or delete on public.inbox_unmask_log99 for each row execute function public._inb_unmask_ro99();
alter table public.inbox_unmask_log99 enable row level security;
revoke all on public.inbox_unmask_log99 from public, anon, authenticated;
drop policy if exists inbox_unmask_log99_sel on public.inbox_unmask_log99;
create policy inbox_unmask_log99_sel on public.inbox_unmask_log99 for select to authenticated using (public.is_owner());
grant select on public.inbox_unmask_log99 to authenticated;

-- ============================================================
-- DECISION 1 helpers
-- ============================================================
create or replace function public._bp_today99() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- the 10-2 head a cost type falls under (same convention as the duplicate guard of cost_bill_add)
create or replace function public._bp_head99(p_cost_type text) returns text language sql immutable as $$
  select case when p_cost_type in ('electricity', 'gas', 'water', 'internet', 'machine_repair') then 'repair' else 'other' end $$;
create or replace function public._bp_uuid99(p_kind text, p_ref text) returns uuid language sql immutable as $$ select md5('bos99auto:' || p_kind || ':' || p_ref)::uuid $$;

-- warnings that this payment may count the same cost a second time: [] when clean
create or replace function public._bp_dup99(p_kind text, p_ref text, p_amount numeric) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare w text[] := '{}'; cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; sn text; heads text[]; locs int[];
begin
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then return w; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select array_agg(location_id) into locs from public.cost_source_locs where source_id = cb.source_id;
    heads := array[public._bp_head99(cs.cost_type)];
    if not cb.dup_ack and exists (
         select 1 from public.entries en cross join lateral jsonb_array_elements(case when jsonb_typeof(en.data->'lines') = 'array' then en.data->'lines' else '[]'::jsonb end) ln
          where en.form_code = '10-2' and en.status in ('submitted', 'approved') and en.location_id = any (coalesce(locs, '{}'))
            and public._m1(en.entry_date) = cb.period_month and lower(coalesce(ln->>'head', '')) = any (heads) and public._acct_num(ln->>'amount') in (cb.amount, p_amount)) then
      w := array_append(w, 'form_10_2_matches');
    end if;
    if exists (select 1 from public.quick_expenses q
                where q.status = 'done' and q.location_id = any (coalesce(locs, '{}')) and q.head = any (heads) and q.amount in (cb.amount, p_amount)
                  and q.exp_date >= cb.period_month
                  and not exists (select 1 from public.bill_payments99 b where b.money_type = 'quick_expense' and b.money_ref = q.id::text)) then
      w := array_append(w, 'quick_expense_similar');
    end if;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then return w; end if;
    select lower(btrim(name)) into sn from public.suppliers where id = pb.supplier_id;
    if sn is not null and exists (select 1 from public.quick_expenses q where q.status = 'done' and q.location_id = pb.location_id and lower(btrim(coalesce(q.paid_to, ''))) = sn
                                   and q.amount = p_amount and q.exp_date >= pb.bill_date
                                   and not exists (select 1 from public.bill_payments99 b where b.money_type = 'quick_expense' and b.money_ref = q.id::text)) then
      w := array_append(w, 'quick_expense_similar');
    end if;
  end if;
  return w;
end $$;

-- THE one place where a payment is written. Cost bill -> quick expense (path A) ; purchase bill -> supplier payment tied to the bill. Callers gate who may call it.
create or replace function public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for update;                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $$;

-- the sheet's call (mode ask) and the list's "record payment" button
create or replace function public.bill_pay_record(p_kind text, p_ref text, p_mode text, p_amount numeric default null, p_client uuid default null, p_note text default null, p_confirm_dup boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; cb public.cost_source_bills; pb public.purchase_bills;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_enter() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'bill_pay:' || p_ref, p_amount)) then raise exception 'not allowed'; end if;
  else
    raise exception 'bad_ref';
  end if;
  return public._bp_pay99(p_kind, p_ref, p_mode, p_amount, 'ask', p_client, p_note, p_confirm_dup);
end $$;

-- ---------- AUTO modes: triggers (a failure never blocks the bill; it leaves a yellow flag and the bill stays in "Bills without payment") ----------
create or replace function public._bp_auto99(p_kind text, p_ref text, p_loc int, p_party_kind text, p_party_id text, p_rule text, p_credit_days int, p_bill_mode text) returns void
language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt(p_rule), 'off'); d public.bill_pay_defaults99; pm text; credit boolean; r jsonb; frm text := case when p_kind = 'cost' then 'STOCK' else 'PURCHASE' end;
begin
  if mode_ not in ('auto_cash', 'auto_bank', 'auto_by_supplier_default') then return; end if;
  begin                                                   -- nothing in here may stop the bill itself from being saved / posted
    select * into d from public.bill_pay_defaults99 where party_kind = p_party_kind and party_id = p_party_id;
    credit := coalesce(d.credit_terms, false) or coalesce(p_credit_days, 0) > 0;
    if credit and not public.rule_on('bill_pay_auto_credit_ok') then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'credit-শর্তের পক্ষ: স্বয়ংক্রিয় payment হয়নি, bill payment-এর অপেক্ষায়', 'Party has credit terms: no automatic payment made; the bill waits for a payment', null, null, frm, null);
      return;
    end if;
    pm := case mode_ when 'auto_cash' then 'cash' when 'auto_bank' then 'bank'
            else coalesce(d.pay_mode, case when p_bill_mode in ('cash', 'bank', 'mobile') then p_bill_mode end) end;
    if pm is null then return; end if;                    -- by_supplier_default with no default known = behaves like "ask" (the list offers it)
    r := public._bp_pay99(p_kind, p_ref, pm, null, 'auto', public._bp_uuid99(p_kind, p_ref), 'automatic (rule ' || p_rule || ')', false);
    if not coalesce((r->>'ok')::boolean, false) then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: একই খরচ আগেই লেখা থাকতে পারে (' || coalesce(r->>'warnings', '') || ')', 'Automatic payment not made: the same cost may already be recorded (' || coalesce(r->>'warnings', '') || ')', null, null, frm, null);
    end if;
  exception when others then
    begin
      perform public._stock_exc(p_loc, 'bill_pay_auto_failed', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: ' || left(sqlerrm, 120), 'Automatic payment failed: ' || left(sqlerrm, 120), null, null, frm, null);
    exception when others then null;
    end;
  end;
end $$;

create or replace function public._bp_cost_auto99() returns trigger language plpgsql security definer set search_path = public as $$
declare loc int;
begin
  if new.status <> 'active' then return new; end if;
  select min(location_id) into loc from public.cost_source_locs where source_id = new.source_id;
  perform public._bp_auto99('cost', new.id::text, loc, 'cost_source', new.source_id::text, 'cost_bill_creates_payment', null, new.pay_mode);
  return new;
end $$;
drop trigger if exists cs_bills_pay99 on public.cost_source_bills;
create trigger cs_bills_pay99 after insert on public.cost_source_bills for each row execute function public._bp_cost_auto99();

create or replace function public._bp_pur_auto99() returns trigger language plpgsql security definer set search_path = public as $$
declare cd int;
begin
  if new.status <> 'posted' or old.status is not distinct from 'posted' or new.kind <> 'bill' or new.paid > 0 then return new; end if;     -- the poster already paid something: his choice stands
  select credit_days into cd from public.suppliers where id = new.supplier_id;
  perform public._bp_auto99('purchase', new.id::text, new.location_id, 'supplier', new.supplier_id::text, 'purchase_bill_creates_payment', cd, null);
  return new;
end $$;
drop trigger if exists purchase_bills_pay99 on public.purchase_bills;
create trigger purchase_bills_pay99 after update of status on public.purchase_bills for each row execute function public._bp_pur_auto99();

-- ---------- VOID of the bill ----------
-- cost bill voided: its payments follow bill_void_payment_mode. void = the quick expense is voided (the engine posts the reversing entry); a payment that is already inside a
-- day-end 10-2 form or sits in a closed period cannot be voided here: it stays (kept_credit) with a yellow flag.
create or replace function public._bp_cost_void99() returns trigger language plpgsql security definer set search_path = public as $$
declare p public.bill_payments99; keep boolean := coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit'; q public.quick_expenses; why text;
begin
  if not (new.status = 'void' and old.status = 'active') then return new; end if;
  for p in select * from public.bill_payments99 where bill_kind = 'cost' and bill_ref = new.id::text and status = 'active' order by id loop
    why := null;
    if not keep and p.money_type = 'quick_expense' then
      select * into q from public.quick_expenses where id = p.money_ref::uuid for update;
      if q.status = 'done' then
        if exists (select 1 from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed') then why := 'already in the day-end 10-2 form';
        else
          begin
            perform public.lock_check(q.exp_date);
            update public.quick_expenses set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left('cost bill #' || new.id::text || ' voided', 300) where id = q.id;
            update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'cost bill voided', 300) where primary_type = 'quick_expenses' and primary_id = q.id::text and state = 'pending';
          exception when others then why := 'period closed';
          end;
        end if;
      end if;
    end if;
    if keep or why is not null then
      update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = left(coalesce(why, 'owner rule: keep'), 300) where id = p.id;
      perform public._stock_exc(p.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment রাখা হয়েছে: ' || p.amount::text || coalesce(' (' || why || ')', ''), 'Payment of a voided cost bill was kept: ' || p.amount::text || coalesce(' (' || why || ')', ''), null, null, 'STOCK', p.amount);
    else
      update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'cost bill voided' where id = p.id;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists cs_bills_void99 on public.cost_source_bills;
create trigger cs_bills_void99 after update of status on public.cost_source_bills for each row execute function public._bp_cost_void99();

-- purchase bill voided: the stock-side void (void_purchase / _void_purchase_p13) voids bill payments BEFORE it flips the bill. keep_credit stops that for payments made through this
-- option: the payment is un-tied from the bill instead, so it remains a payment to the supplier = supplier credit (nothing is un-voided afterwards, nothing is rewritten).
create or replace function public._bp_sp_void99() returns trigger language plpgsql security definer set search_path = public as $$
declare l public.bill_payments99;
begin
  if not (new.voided and not old.voided and old.bill_id is not null) then return new; end if;
  select * into l from public.bill_payments99 where money_type = 'supplier_payment' and money_ref = old.id::text and status = 'active';
  if not found then return new; end if;
  if coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit' then
    new.voided := false; new.void_note := old.void_note; new.void_by := old.void_by; new.bill_id := null;
    update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment kept as supplier credit' where id = l.id;
    perform public._stock_exc(old.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment supplier-এর credit হিসেবে রাখা হয়েছে: ' || old.amount::text, 'Payment of a voided purchase bill kept as supplier credit: ' || old.amount::text, null, null, 'PURCHASE', old.amount);
  else
    update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'purchase bill voided' where id = l.id;
  end if;
  return new;
end $$;
drop trigger if exists supplier_payments_void99 on public.supplier_payments;
create trigger supplier_payments_void99 before update of voided on public.supplier_payments for each row execute function public._bp_sp_void99();

-- a purchase void that left payments alone (existing rule purchase_void_payments = keep): the link rows say so
create or replace function public._bp_pur_void99() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    update public.bill_payments99 l set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment not voided (rule purchase_void_payments = keep)'
     where l.bill_kind = 'purchase' and l.bill_ref = new.id::text and l.status = 'active'
       and exists (select 1 from public.supplier_payments s where s.id::text = l.money_ref and not s.voided);
  end if;
  return new;
end $$;
drop trigger if exists purchase_bills_void99 on public.purchase_bills;
create trigger purchase_bills_void99 after update of status on public.purchase_bills for each row execute function public._bp_pur_void99();

-- ---------- recommendation / info / lists ----------
create or replace function public.payment_recommendation(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare amt numeric; credit boolean := false; dm text; bm text; large numeric := public.rule_num('bill_pay_large_amount'); small numeric := public.rule_num('bill_pay_small_cash_max'); d public.bill_pay_defaults99;
        cb public.cost_source_bills; pb public.purchase_bills; cd int; rec text; why text[]; basis text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_view() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
    amt := cb.amount; bm := cb.pay_mode;
    select * into d from public.bill_pay_defaults99 where party_kind = 'cost_source' and party_id = cb.source_id::text;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public._pur_ok(pb.location_id) then raise exception 'not allowed'; end if;
    amt := pb.total; select credit_days into cd from public.suppliers where id = pb.supplier_id;
    select * into d from public.bill_pay_defaults99 where party_kind = 'supplier' and party_id = pb.supplier_id::text;
  else raise exception 'bad_ref'; end if;
  dm := coalesce(d.pay_mode, case when bm in ('cash', 'bank', 'mobile') then bm end);
  credit := coalesce(d.credit_terms, false) or coalesce(cd, 0) > 0;
  if credit then rec := 'ask'; basis := 'credit';
  elsif large is not null and amt >= large then rec := 'ask'; basis := 'large';
  elsif small is not null and amt <= small and dm = 'cash' then rec := 'auto_cash'; basis := 'small_cash';
  elsif small is not null and amt <= small and dm = 'bank' then rec := 'auto_bank'; basis := 'small_bank';
  else rec := 'ask'; basis := case when large is null and small is null then 'no_numbers' else 'default' end; end if;
  return jsonb_build_object('mode', rec, 'basis', basis, 'amount', amt, 'credit_terms', credit, 'default_pay_mode', dm, 'large_limit', large, 'small_cash_limit', small,
    'never_auto', credit,
    'reason_bn', case basis when 'credit' then 'credit-শর্তের পক্ষ: কখনো নিজে নিজে payment নয়; প্রতিবার জিজ্ঞেস করুন।' when 'large' then 'বড় bill (আপনার দেওয়া সীমার সমান বা বেশি): প্রতিবার জিজ্ঞেস করুন।'
      when 'small_cash' then 'ছোট cash bill, credit নেই: নিজে cash-এ লেখা যায়।' when 'small_bank' then 'ছোট bill, credit নেই, bank-এ দেওয়া হয়: নিজে bank-এ লেখা যায়।'
      when 'no_numbers' then 'কোনো সীমা লেখা নেই, তাই নিরাপদ পথ: জিজ্ঞেস করুন। সীমা লিখলে ছোট cash bill-এ auto প্রস্তাব আসবে।' else 'কোনো নিয়ম মেলেনি: নিরাপদ পথ হলো জিজ্ঞেস করা।' end,
    'reason_mix', case basis when 'credit' then 'Credit-terms এর পক্ষ: কখনো নিজে নিজে payment নয়; প্রতিবার জিজ্ঞেস করুন।' when 'large' then 'Large bill (আপনার দেওয়া সীমার সমান বা বেশি): প্রতিবার জিজ্ঞেস করুন।'
      when 'small_cash' then 'Small cash bill, credit নেই: নিজে cash এ লেখা যায়।' when 'small_bank' then 'Small bill, credit নেই, bank এ দেওয়া হয়: নিজে bank এ লেখা যায়।'
      when 'no_numbers' then 'কোনো সীমা লেখা নেই, তাই safe পথ: জিজ্ঞেস করুন। সীমা লিখলে small cash bill এ auto প্রস্তাব আসবে।' else 'কোনো rule মেলেনি: safe পথ হলো জিজ্ঞেস করা।' end,
    'reason_en', case basis when 'credit' then 'The party has credit terms: never automatic; ask every time.' when 'large' then 'A large bill (at or above the limit you typed): ask every time.'
      when 'small_cash' then 'A small cash bill with no credit: it can be recorded in cash automatically.' when 'small_bank' then 'A small bill with no credit, paid through the bank: it can be recorded in bank automatically.'
      when 'no_numbers' then 'No limits are typed yet, so the safe choice is to ask. Type a small-cash limit to get an automatic suggestion for small cash bills.' else 'No rule matched: the safe choice is to ask.' end);
end $$;

-- what the "Record payment now?" sheet shows
create or replace function public.bill_pay_info99(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; total numeric; paid_sum numeric := 0; rem numeric; rule_ text; nm text; modes jsonb; open_amt numeric; dm text; loc int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_view() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    total := cb.amount; rem := case when cb.status = 'active' then cb.amount - paid_sum else 0 end; rule_ := coalesce(public.rule_txt('cost_bill_creates_payment'), 'off');
    nm := coalesce(cs.provider, cs.code); modes := '["cash","bank","mobile","other"]'::jsonb; dm := cb.pay_mode;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public._pur_ok(pb.location_id) then raise exception 'not allowed'; end if;
    select name into nm from public.suppliers where id = pb.supplier_id;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    total := pb.total; paid_sum := pb.paid; rem := case when pb.status = 'posted' and pb.kind = 'bill' then least(coalesce(open_amt, 0), pb.total - pb.paid) else 0 end;
    rule_ := coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'); modes := '["cash","bank","mobile","card"]'::jsonb; loc := pb.location_id;
    select pay_mode into dm from public.bill_pay_defaults99 where party_kind = 'supplier' and party_id = pb.supplier_id::text;
  else raise exception 'bad_ref'; end if;
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'party', nm, 'total', total, 'paid', paid_sum, 'remaining', greatest(rem, 0), 'rule', rule_, 'modes', modes,
    'suggest_mode', dm, 'location_id', loc, 'recommendation', public.payment_recommendation(p_kind, p_ref),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'mode', b.mode, 'amount', b.amount, 'origin', b.origin, 'status', b.status, 'counted', b.money_type <> 'note_only', 'at', b.created_at) order by b.id)
                            from public.bill_payments99 b where b.bill_kind = p_kind and b.bill_ref = p_ref), '[]'::jsonb));
end $$;

-- "Bills without payment": cost bills and posted purchase bills that still have an open amount (nothing is guessed: the list is the bill minus the recorded payments)
create or replace function public.bills_without_payment99(p_kind text default null, p_loc int default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; lim int := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is not null and p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if (p_kind is null or p_kind = 'cost') and public._cs_view() then
    out_ := out_ || coalesce((select jsonb_agg(z.j order by z.o desc) from (
      select b.id o, jsonb_build_object('kind', 'cost', 'ref', b.id::text, 'party', coalesce(s.provider, s.code), 'bill_no', b.bill_no, 'date', coalesce(b.bill_date, b.period_month), 'total', b.amount,
             'paid', coalesce(pp.paid, 0), 'due', b.amount - coalesce(pp.paid, 0), 'location_id', (select min(location_id) from public.cost_source_locs where source_id = b.source_id)) j
        from public.cost_source_bills b join public.cost_sources s on s.id = b.source_id
        left join lateral (select sum(amount) paid from public.bill_payments99 x where x.bill_kind = 'cost' and x.bill_ref = b.id::text and x.status in ('active', 'kept_credit')) pp on true
       where b.status = 'active' and b.amount - coalesce(pp.paid, 0) > 0.004 and public._cs_src_ok(b.source_id)
         and (p_loc is null or exists (select 1 from public.cost_source_locs l where l.source_id = b.source_id and l.location_id = p_loc))
       order by b.id desc limit lim) z), '[]'::jsonb);
  end if;
  if (p_kind is null or p_kind = 'purchase') then
    out_ := out_ || coalesce((select jsonb_agg(z.j order by z.d desc) from (
      select o.bill_date d, jsonb_build_object('kind', 'purchase', 'ref', o.bill_id::text, 'party', s.name, 'bill_no', o.bill_no, 'date', o.bill_date, 'total', pb.total, 'paid', pb.paid,
             'due', least(o.open_amt, pb.total - pb.paid), 'location_id', o.location_id) j
        from public._sup_open(null) o join public.purchase_bills pb on pb.id = o.bill_id join public.suppliers s on s.id = o.supplier_id
       where o.bill_id is not null and o.open_amt > 0.004 and public._pur_ok(o.location_id) and (p_loc is null or o.location_id = p_loc)
       order by o.bill_date desc nulls last limit lim) z), '[]'::jsonb);
  end if;
  return jsonb_build_object('rows', out_, 'cost_rule', coalesce(public.rule_txt('cost_bill_creates_payment'), 'off'), 'purchase_rule', coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'));
end $$;

-- owner: the usual mode and credit terms of a supplier / cost source (the only way anything reaches bill_pay_defaults99)
create or replace function public.bill_pay_default_set99(p_kind text, p_id text, p_mode text, p_credit boolean default false, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.bill_pay_defaults99;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('supplier', 'cost_source') then raise exception 'bad_kind'; end if;
  if p_mode is not null and p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
  if p_kind = 'supplier' and not exists (select 1 from public.suppliers where id::text = p_id) then raise exception 'not_found'; end if;
  if p_kind = 'cost_source' and not exists (select 1 from public.cost_sources where id::text = p_id) then raise exception 'not_found'; end if;
  insert into public.bill_pay_defaults99 (party_kind, party_id, pay_mode, credit_terms, note, updated_by) values (p_kind, p_id, p_mode, coalesce(p_credit, false), left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (party_kind, party_id) do update set pay_mode = excluded.pay_mode, credit_terms = excluded.credit_terms, note = excluded.note, updated_by = auth.uid(), updated_at = now() returning * into r;
  return jsonb_build_object('id', r.id, 'kind', r.party_kind, 'party', r.party_id, 'mode', r.pay_mode, 'credit', r.credit_terms);
end $$;

create or replace function public.bill_pay_defaults_list99() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('kind', d.party_kind, 'id', d.party_id, 'mode', d.pay_mode, 'credit', d.credit_terms, 'note', d.note,
      'name', case d.party_kind when 'supplier' then (select name from public.suppliers where id::text = d.party_id) else (select coalesce(provider, code) from public.cost_sources where id::text = d.party_id) end) order by d.id)
    from public.bill_pay_defaults99 d), '[]'::jsonb);
end $$;

-- ============================================================
-- DECISION 2: inbox masking
-- ============================================================
create or replace function public._inb_pii_mode99() returns text language sql stable security definer set search_path = public as $$
  select case when coalesce(public.rule_txt('inbox_pii_mode'), 'off') in ('mask_phone', 'mask_phone_address', 'mask_all_pii') then public.rule_txt('inbox_pii_mode') else 'off' end $$;

-- the shown form of a value: phone / handle keeps its last 3 characters, a name keeps its first, address / text / attachment are fully hidden
create or replace function public._inb_mask99(p_field text, p_val text) returns text language sql immutable as $$
  select case
    when p_val is null then null
    when p_field in ('mobile') or (p_field = 'handle' and p_val ~ '^\+?[0-9][0-9 ()-]{5,}$') then repeat('•', greatest(char_length(p_val) - 3, 3)) || right(p_val, least(3, char_length(p_val)))
    when p_field in ('name', 'handle') then left(p_val, 1) || '•••'
    else '••••' end $$;

-- field = mobile | handle | address | name | text | attachment. Returns the value as it may be shown NOW (mode off or an active reveal = unchanged)
create or replace function public._inb_pii_f99(p_field text, p_val text) returns text
language plpgsql stable security definer set search_path = public as $$
declare mode_ text := public._inb_pii_mode99(); hide boolean;
begin
  if mode_ = 'off' or p_val is null then return p_val; end if;
  if coalesce(current_setting('bos.inb_unmask99', true), '') = txid_current()::text then return p_val; end if;      -- inside inbox_unmask only
  hide := case p_field
    when 'mobile' then true
    when 'handle' then mode_ = 'mask_all_pii' or p_val ~ '^\+?[0-9][0-9 ()-]{5,}$'
    when 'address' then mode_ in ('mask_phone_address', 'mask_all_pii')
    else mode_ = 'mask_all_pii' end;
  return case when hide then public._inb_mask99(p_field, p_val) else p_val end;
end $$;

-- the same for a whole order object
create or replace function public._inb_pii_json99(j jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mode_ text := public._inb_pii_mode99();
begin
  if mode_ = 'off' then return j; end if;
  if j ? 'customer_mobile' and jsonb_typeof(j->'customer_mobile') = 'string' then j := jsonb_set(j, '{customer_mobile}', to_jsonb(public._inb_pii_f99('mobile', j->>'customer_mobile'))); end if;
  if j ? 'address' and jsonb_typeof(j->'address') = 'string' then j := jsonb_set(j, '{address}', to_jsonb(public._inb_pii_f99('address', j->>'address'))); end if;
  if j ? 'customer_name' and jsonb_typeof(j->'customer_name') = 'string' then j := jsonb_set(j, '{customer_name}', to_jsonb(public._inb_pii_f99('name', j->>'customer_name'))); end if;
  return j || jsonb_build_object('pii_mode', mode_);
end $$;

-- reveal ONE message / order. Needs the contact right of the place AND grant inbox_unmask (owner always). Limited by inbox_unmask_daily_max (blank = none; owner not limited). Always logged.
create or replace function public.inbox_unmask(p_kind text, p_id text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; m public.inbound_messages; o public.online_orders; mode_ text := public._inb_pii_mode99(); lim numeric := public.rule_num('inbox_unmask_daily_max'); used int; data jsonb; fields text; sid text;
begin
  if p_kind not in ('message', 'order') or p_id is null then raise exception 'bad_input'; end if;
  if p_kind = 'message' then
    if p_id !~ '^[0-9]{1,18}$' then raise exception 'bad_input'; end if;
    select * into m from public.inbound_messages where id = p_id::bigint;
    if not found then raise exception 'not_found'; end if;
    loc := m.location_id; perform public._inb_gate(loc, 'view'); fields := 'handle,name,text,attachment';
  else
    if p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_input'; end if;
    select * into o from public.online_orders where id = p_id::uuid;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
    if not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(loc) then raise exception 'not allowed'; end if;
    fields := 'customer_mobile,address,customer_name';
  end if;
  if not public._inb_contact_ok(loc) then raise exception 'not allowed'; end if;
  if mode_ = 'off' then          -- nothing is masked: the normal read (which has its own view line)
    return jsonb_build_object('ok', true, 'mode', 'off', 'logged', false, 'data', case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end);
  end if;
  if not (public.is_owner() or public.has_grant('inbox_unmask', loc)) then raise exception 'not allowed'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if lim is not null and not public.is_owner() then
    select count(*) into used from public.inbox_unmask_log99 where user_id = auth.uid() and outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date;
    if used >= lim then
      insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'blocked');
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'used', used, 'max', lim);
    end if;
  end if;
  perform set_config('bos.inb_unmask99', txid_current()::text, true);
  begin
    data := case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end;
  exception when others then
    perform set_config('bos.inb_unmask99', '', true); raise;
  end;
  perform set_config('bos.inb_unmask99', '', true);
  insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'revealed');
  perform public._inb_audit_view('inbox_unmask', p_kind || ':' || p_id, jsonb_build_object('fields', fields, 'reason', left(nullif(btrim(p_reason), ''), 300)));
  return jsonb_build_object('ok', true, 'mode', mode_, 'logged', true, 'data', data, 'used', coalesce(used, 0) + 1, 'max', lim);
end $$;

-- owner: who revealed what, when
create or replace function public.inbox_unmask_log_list99(p_limit int default 100, p_user uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'user_id', z.user_id, 'staff', z.staff_id, 'kind', z.kind, 'ref', z.ref_id, 'location_id', z.location_id,
                   'fields', z.fields, 'reason', z.reason, 'outcome', z.outcome) order by z.id desc)
    from (select * from public.inbox_unmask_log99 l where p_user is null or l.user_id = p_user order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- owner cards: current values + counts of both options
create or replace function public.options99_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  w := public.bills_without_payment99(null, null, 500);
  return jsonb_build_object(
    'cost_bill_creates_payment', coalesce(public.rule_txt('cost_bill_creates_payment'), 'off'), 'purchase_bill_creates_payment', coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'),
    'bill_void_payment_mode', coalesce(public.rule_txt('bill_void_payment_mode'), 'void'), 'bill_pay_auto_credit_ok', public.rule_on('bill_pay_auto_credit_ok'),
    'bill_pay_large_amount', public.rule_num('bill_pay_large_amount'), 'bill_pay_small_cash_max', public.rule_num('bill_pay_small_cash_max'),
    'inbox_pii_mode', public._inb_pii_mode99(), 'inbox_pii_guard_on', public.rule_on('inbox_pii_guard_on'), 'inbox_unmask_daily_max', public.rule_num('inbox_unmask_daily_max'),
    'unpaid_cost', (select count(*) from jsonb_array_elements(w->'rows') e where e->>'kind' = 'cost'), 'unpaid_purchase', (select count(*) from jsonb_array_elements(w->'rows') e where e->>'kind' = 'purchase'),
    'reveals_today', (select count(*) from public.inbox_unmask_log99 where outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date),
    'blocked_today', (select count(*) from public.inbox_unmask_log99 where outcome = 'blocked' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date));
end $$;

-- ============================================================
-- re-created from their LATEST definitions (phase76/77/86/89 text); only the /* bos99 */ and -- bos99 lines differ
-- ============================================================

CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('text', left(m.msg_text, 200)) end, 'masked', not public._inb_contact_ok(m.location_id), 'pii_mode', public._inb_pii_mode99()) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.inbox_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.inbound_messages; c public.sales_channels; ok boolean;
begin
  select * into m from public.inbound_messages where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  ok := public._inb_contact_ok(m.location_id);
  if ok then perform public._inb_audit_view('inbound_messages', m.id::text, jsonb_build_object('fields', 'handle,name,text,attachment')); end if;
  return jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
    'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'masked', not ok,
    'handle', case when ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when ok then public._inb_pii_f99('name', m.customer_name) end, 'text', case when ok then public._inb_pii_f99('text', m.msg_text) end, 'attachment_ref', case when ok then public._inb_pii_f99('attachment', m.attachment_ref) end, 'pii_mode', public._inb_pii_mode99(),   /* bos99 */
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, public._inb_pii_f99('name', o.customer_name) as customer_name,   -- bos99
           case when public._inb_contact_ok(o.location_id) then public._inb_pii_f99('mobile', o.customer_mobile) end as customer_mobile,   -- bos76 bos99
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked, public._inb_pii_mode99() as pii_mode,   -- bos76 bos99
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := public._inb_pii_json99(j);                                                                               -- bos99
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.telegram_chat_info(p_msg_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.inbound_messages; c public.sales_channels; chat text; l public.telegram_chat_links; ok boolean; cu public.customers; oo public.online_orders;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  chat := public._tg_chat_of(m.customer_handle);
  if c.kind <> 'telegram' or chat is null then raise exception 'not_telegram'; end if;
  ok := public._inb_contact_ok(m.location_id);
  select * into l from public.telegram_chat_links where channel_id = m.channel_id and chat_id = chat and unlinked_at is null;
  if found and l.customer_id is not null then select * into cu from public.customers where id = l.customer_id; end if;
  if found and l.order_id is not null then select * into oo from public.online_orders where id = l.order_id; end if;
  if ok and found and l.customer_id is not null then
    perform public._inb_audit_view('telegram_chat_links', l.id::text, jsonb_build_object('fields', 'customer_name,customer_mobile'));
  end if;
  return jsonb_build_object('msg_id', m.id, 'linked', l.id is not null, 'masked', not ok,
    'customer_id', l.customer_id, 'customer_name', case when ok then public._inb_pii_f99('name', cu.name) end, 'customer_mobile', case when ok then public._inb_pii_f99('mobile', cu.mobile) end, 'pii_mode', public._inb_pii_mode99(),   -- bos99
    'order_id', l.order_id, 'order_no', oo.order_no, 'note', l.note,
    'message_count', (select count(*) from public.inbound_messages x where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_no', o2.order_no, 'status', o2.status) order by o2.created_at)
                          from public.online_orders o2 where o2.id in (select x.linked_order_id from public.inbound_messages x
                                                                        where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle and x.linked_order_id is not null)), '[]'::jsonb));
end $function$;

-- ============================================================
-- recommendations (shown by setup_recommendations(); ON CONFLICT DO NOTHING; the owner decides, nothing is applied by itself)
-- ============================================================
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('cost_bill_creates_payment', 'cost_bill_creates_payment', '99', 'purchase', '"ask"', '{}',
  'cost bill সেভ করার পর "এখনই payment লিখবেন?" জিজ্ঞেস করা নিরাপদ: টাকা কখনো ভুল করে সরে না, আবার bill ও payment দুটো আলাদা করে type করার ঝামেলাও থাকে না। পুরোপুরি স্বয়ংক্রিয় (auto) করবেন কেবল cash-এ শোধ হওয়া ছোট bill-এর জন্য।',
  'Cost bill save করার পর "এখনই payment লিখবেন?" জিজ্ঞেস করা safe: টাকা কখনো ভুল করে সরে না, আবার bill ও payment দুটো আলাদা করে type করার ঝামেলাও থাকে না। পুরোপুরি auto করবেন কেবল cash এ শোধ হওয়া ছোট bill এর জন্য।',
  'Asking "Record payment now?" after a cost bill is saved is the safe middle: money never moves by mistake and you do not type the bill and the payment twice. Use a fully automatic mode only for small bills paid in cash.', 321),
 ('purchase_bill_creates_payment', 'purchase_bill_creates_payment', '99', 'purchase', '"ask"', '{}',
  'purchase bill পোস্ট করার পর জিজ্ঞেস করা নিরাপদ। credit-শর্তের supplier-এর bill কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধের সুযোগ থাকে।',
  'Purchase bill post করার পর জিজ্ঞেস করা safe। Credit-terms এর supplier এর bill কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধের সুযোগ থাকে।',
  'Asking after a purchase bill is posted is the safe choice. A supplier with credit terms is never paid automatically, so part payment or paying later stays possible.', 322),
 ('bill_void_payment_mode', 'bill_void_payment_mode', '99', 'purchase', '"void"', '{}',
  'bill বাতিল হলে তার payment-ও বাতিল হওয়াই সাধারণ নিয়ম: নইলে বই-এ খরচ থেকে যায় অথচ bill নেই। টাকা সত্যিই দেওয়া হয়ে গেলে keep_credit বেছে নিন।',
  'Bill বাতিল হলে তার payment ও বাতিল হওয়াই সাধারণ নিয়ম: নইলে বই-এ খরচ থেকে যায় অথচ bill নেই। টাকা সত্যিই দেওয়া হয়ে গেলে keep_credit বেছে নিন।',
  'Voiding the payment together with its bill is the normal rule: otherwise the books keep a cost for a bill that no longer exists. Choose keep_credit only when the money really left.', 323),
 ('bill_pay_auto_credit_ok', 'bill_pay_auto_credit_ok', '99', 'purchase', 'false', '{}',
  'বন্ধ থাকুক: credit-শর্তের পক্ষের bill নিজে নিজে শোধ হলে "পরে দেব" শর্তটাই অর্থহীন হয়ে যায়।',
  'Off থাকুক: credit-terms এর পক্ষের bill নিজে নিজে শোধ হলে "পরে দেব" শর্তটাই অর্থহীন হয়ে যায়।',
  'Keep it off: if a bill of a party with credit terms were paid automatically, the credit term itself would mean nothing.', 324),
 ('bill_pay_large_amount', 'bill_pay_large_amount', '99', 'purchase', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা থেকে bill "বড়" তা আপনি লিখবেন; লিখলে বড় bill-এ সিস্টেম সবসময় জিজ্ঞেস করার প্রস্তাব দেবে।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা থেকে bill "বড়" তা আপনি লিখবেন; লিখলে বড় bill এ system সবসময় জিজ্ঞেস করার প্রস্তাব দেবে।',
  'No number is suggested. You type from which amount a bill counts as large; the system then always recommends asking for large bills.', 325),
 ('bill_pay_small_cash_max', 'bill_pay_small_cash_max', '99', 'purchase', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা পর্যন্ত cash bill "ছোট" তা আপনি লিখবেন; লিখলে creditহীন ছোট cash bill-এ auto_cash প্রস্তাব আসবে।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা পর্যন্ত cash bill "ছোট" তা আপনি লিখবেন; লিখলে credit ছাড়া ছোট cash bill এ auto_cash প্রস্তাব আসবে।',
  'No number is suggested. You type up to which amount a cash bill counts as small; the system then recommends auto_cash for small cash bills without credit.', 326),
 ('inbox_pii_mode', 'inbox_pii_mode', '99', 'pos', '"mask_phone_address"', '{}',
  'phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে (message পড়া, order বানানো) পুরো নম্বর লাগে না, আর ফাঁস হলে ক্ষতি বেশি। নাম ও message-এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে অনুমতিপ্রাপ্ত মানুষ একটি একটি করে খুলবেন, আর প্রতিবার log-এ থাকবে।',
  'Phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে (message পড়া, order বানানো) পুরো নম্বর লাগে না, আর leak হলে ক্ষতি বেশি। নাম ও message এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে authorised মানুষ একটি একটি করে খুলবেন, আর প্রতিবার log এ থাকবে।',
  'Hiding phone and address is the better default: most work (reading a message, making an order) does not need the full number, and a leak costs a lot. Name and message text stay visible so work is not blocked. Authorised people reveal one at a time, and every reveal is logged.', 327),
 ('inbox_unmask_daily_max', 'inbox_unmask_daily_max', '99', 'pos', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। দিনে একজন কতবার খুলতে পারবে তা আপনি লিখবেন; ফাঁকা = সীমা নেই। মালিকের ওপর সীমা খাটে না।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। দিনে একজন কতবার unmask করতে পারবে তা আপনি লিখবেন; ফাঁকা = সীমা নেই। Owner এর ওপর সীমা খাটে না।',
  'No number is suggested. You type how many reveals one person may make per day; blank = no limit. The owner is not limited.', 328)
 on conflict (code) do nothing;

-- ============================================================
-- privileges: internals closed, public calls for signed-in users only
-- ============================================================
revoke all on function public._bp_today99(), public._bp_head99(text), public._bp_uuid99(text, text), public._bp_dup99(text, text, numeric),
  public._bp_pay99(text, text, text, numeric, text, uuid, text, boolean), public._bp_auto99(text, text, int, text, text, text, int, text),
  public._bp_cost_auto99(), public._bp_pur_auto99(), public._bp_cost_void99(), public._bp_sp_void99(), public._bp_pur_void99(), public._bp_ro99(),
  public._inb_pii_mode99(), public._inb_mask99(text, text), public._inb_pii_f99(text, text), public._inb_pii_json99(jsonb), public._inb_unmask_ro99() from public, anon, authenticated;
revoke all on function public.bill_pay_record(text, text, text, numeric, uuid, text, boolean), public.payment_recommendation(text, text), public.bill_pay_info99(text, text),
  public.bills_without_payment99(text, int, int), public.bill_pay_default_set99(text, text, text, boolean, text), public.bill_pay_defaults_list99(),
  public.inbox_unmask(text, text, text), public.inbox_unmask_log_list99(int, uuid), public.options99_state() from public, anon;
grant execute on function public.bill_pay_record(text, text, text, numeric, uuid, text, boolean), public.payment_recommendation(text, text), public.bill_pay_info99(text, text),
  public.bills_without_payment99(text, int, int), public.bill_pay_default_set99(text, text, text, boolean, text), public.bill_pay_defaults_list99(),
  public.inbox_unmask(text, text, text), public.inbox_unmask_log_list99(int, uuid), public.options99_state() to authenticated;
revoke all on function public.inbox_list(int, text, int), public.inbox_get(bigint), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.telegram_chat_info(bigint) from public, anon;
grant execute on function public.inbox_list(int, text, int), public.inbox_get(bigint), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.telegram_chat_info(bigint) to authenticated;

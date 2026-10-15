-- ============================================================
-- Phase 127 (marker dl127) - DEALER / HARDWARE-PAINT BUSINESS, part 1: cheque / PDC register (ADDITIVE ONLY).
-- Canonical order: after phase126 (docs/PASTE_ORDER.md). Needs the base schema + phase122 (org_units, locations.org_unit_id) + the customer / supplier ledgers.
-- Paste twice = no change, no error. Rule dealer_cheque_on is OFF by default: while OFF every write function refuses ('feature_off'); reads still work.
--   Table  dealer_cheques         one row per cheque, RECEIVED (from a customer / other) or ISSUED (to a supplier / other). Status registered | deposited |
--                                 cleared | bounced | replaced | cancelled. Amount, bank, cheque no., cheque date, due (deposit) date, bounce reason + charge,
--                                 replacement link (replaced_by), our bank account (coa), bank statement line (reconciliation hook), ledger link.
--   Table  dealer_cheque_events   append-only history of every step (who, when, from -> to, amount). Idempotency key per step.
--   Business scope: every row carries location_id and business_id (the business unit of the location, phase122). Every read / write function checks
--     _dl_ok127(location, grant): owner, or the user is EXPLICITLY assigned to that location (user_locations; the management-role bypass of can_loc is NOT used)
--     AND holds the grant for that location. Another business's cheques are therefore invisible and untouchable. RLS on both tables uses the same check.
--   Money rule (no double counting): registering / depositing / bouncing / replacing a cheque changes NO ledger. Only CLEAR posts: a received cheque writes ONE
--     sale_payments row (kind collection, mode bank, client_id = the cheque id) so the customer's balance goes down once; an issued cheque writes ONE
--     supplier_payments row (mode bank, client_id = the cheque id). The status guard + the client id make a second clear impossible. Over-payment is refused
--     (same rule as collect_payment / pay_supplier). The bank-charge of a bounce is only RECORDED on the cheque (nothing is posted to any ledger).
--     sale_payments.mode check is widened to also allow 'bank' (existing rows and modes unchanged; _acct_paykey already maps 'bank' to the bank account).
--   Reports: cheques_due (aging buckets), cheques_bounced, post_dated_exposure (per party), cheque_ledger_check (cleared cheques whose ledger payment was voided),
--     cheque_bank_candidates + cheque_bank_link (bank reconciliation hook: cleared cheque <-> bank_statement_lines row, same account, same signed amount).
--   Rule dealer_cheque_on (switch, OFF). Grants dealer_cheque_view, dealer_cheque_manage (not given to any role by default).
-- Known limits (documented, not hidden): customers and suppliers are still ONE master list for the whole database (master-data scope is a later stage), so a party
--   can be linked from two businesses; the cheque rows themselves, and every report, are strictly per business.
-- Rollback: leave dealer_cheque_on OFF. To remove: drop the functions, the two tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.org_units') is null or to_regclass('public.customers') is null or to_regclass('public.suppliers') is null
     or to_regclass('public.sale_payments') is null or to_regclass('public.supplier_payments') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.bank_statement_lines') is null or to_regclass('public.coa_accounts') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.setup_rec_defs81') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null or to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._cust_bal(uuid)') is null
     or to_regprocedure('public._sup_balance(uuid)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase127 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 0. grants, rule ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_cheque_view', 127, 'চেক / PDC তালিকা ও রিপোর্ট দেখা', 'Cheque / PDC list ও report দেখা', 'View the cheque / PDC register and its reports'),
  ('dealer_cheque_manage', 128, 'চেক / PDC নিবন্ধন, জমা, ক্লিয়ার, বাউন্স', 'Cheque / PDC register, deposit, clear, bounce', 'Register, deposit, clear and bounce cheques / PDCs')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_cheque_on', 'dealer', 'switch', 'false', null, null, null, null,
  'চেক / PDC খাতা চালু', 'Cheque / PDC register চালু', 'Cheque / PDC register',
  'চালু করলে চেক নিবন্ধন, জমা, ক্লিয়ার ও বাউন্স লেখা যাবে। শুধু ক্লিয়ার হলে গ্রাহক / সাপ্লায়ারের খাতায় টাকা ওঠে।',
  'চালু করলে cheque register, deposit, clear ও bounce লেখা যাবে। শুধু clear হলে customer / supplier এর খাতায় টাকা ওঠে।',
  'When on, cheques can be registered, deposited, cleared and bounced. Only CLEAR moves money in the party ledger.', 1270)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_cheque_on', 'dealer_cheque_on', '127', 'dealer', null::jsonb, '{}'::text[],
  'ডিলার / হার্ডওয়্যার ব্যবসায় চেক ব্যবহার হলে চালু করুন; মিষ্টির ব্যবসায় দরকার নেই।',
  'Dealer / hardware business এ cheque ব্যবহার হলে চালু করুন; মিষ্টির business এ দরকার নেই।',
  'Turn on only for a business that takes or gives cheques (dealer / hardware); the sweets business does not need it.', 1270
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_cheque_on');

-- ---------- 1. shared scope helpers (also used by phase128 / phase129) ----------
-- the business (org unit of kind business) a location belongs to; null when the location is not mapped
-- one read-only window onto the organization layer (phase122): the dealer functions read units only through it
create or replace view public.dl_unit_tree127 as select id, parent_id, kind, code from public.org_units;
revoke all on public.dl_unit_tree127 from public, anon, authenticated;

create or replace function public._dl_biz127(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id, kind) as (
    select o.id, o.parent_id, o.kind from public.dl_unit_tree127 o join public.locations l on l.org_unit_id = o.id where l.id = p_loc
    union all select p.id, p.parent_id, p.kind from public.dl_unit_tree127 p join up on up.parent_id = p.id)
  select id from up where kind = 'business' limit 1;
$$;

-- may the caller use grant p_g1 (or p_g2) at location p_loc? Owner always; others need the grant AND an explicit assignment to that location.
create or replace function public._dl_ok127(p_loc int, p_g1 text, p_g2 text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and exists (select 1 from public.locations l where l.id = p_loc) and (
    public.is_owner()
    or (exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_loc)
        and (public.has_grant(p_g1, p_loc) or (p_g2 is not null and public.has_grant(p_g2, p_loc)))));
$$;

-- the locations the caller may use with grant p_g1 / p_g2
create or replace function public._dl_vis127(p_g1 text, p_g2 text default null) returns setof int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where public._dl_ok127(l.id, p_g1, p_g2);
$$;

-- a business-level check: the caller holds the grant at some location of that business
create or replace function public._dl_biz_ok127(p_biz bigint, p_g1 text, p_g2 text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner()
    or exists (select 1 from public.locations l where public._dl_biz127(l.id) = p_biz and public._dl_ok127(l.id, p_g1, p_g2)));
$$;

create or replace function public._dl_today127() returns date
language sql stable set search_path = public as $$ select (now() at time zone 'Asia/Dhaka')::date; $$;

-- ---------- 2. tables ----------
create table if not exists public.dealer_cheques (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint references public.org_units(id),
  location_id int not null references public.locations(id),
  direction text not null check (direction in ('received', 'issued')),
  party_kind text not null check (party_kind in ('customer', 'supplier', 'other')),
  customer_id uuid references public.customers(id),
  supplier_id uuid references public.suppliers(id),
  party_name text check (party_name is null or length(btrim(party_name)) between 1 and 120),
  bank_name text not null check (length(btrim(bank_name)) between 1 and 80),
  branch_name text check (branch_name is null or length(branch_name) <= 80),
  cheque_no text not null check (length(btrim(cheque_no)) between 1 and 40),
  amount numeric(16,2) not null check (amount > 0 and amount <= 1000000000000),
  cheque_date date not null check (cheque_date >= date '2000-01-01'),
  due_date date not null check (due_date >= date '2000-01-01'),
  status text not null default 'registered' check (status in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled')),
  deposit_date date,
  bank_account_id bigint references public.coa_accounts(id),           -- our bank account (chart of accounts) the cheque goes through
  cleared_on date,
  ledger_kind text check (ledger_kind is null or ledger_kind in ('sale_payment', 'supplier_payment')),
  ledger_id bigint,                                                     -- sale_payments.id / supplier_payments.id written on CLEAR (the only money effect)
  bank_line_id bigint references public.bank_statement_lines(id),       -- bank reconciliation hook
  bounced_on date,
  bounce_reason text check (bounce_reason is null or length(bounce_reason) <= 200),
  bounce_charge numeric(16,2) not null default 0 check (bounce_charge >= 0 and bounce_charge <= 1000000000000),
  replaced_by uuid references public.dealer_cheques(id),
  replaces_id uuid references public.dealer_cheques(id),
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  check (due_date >= cheque_date),
  check ((party_kind = 'customer') = (customer_id is not null)),
  check ((party_kind = 'supplier') = (supplier_id is not null)),
  check (party_kind <> 'other' or party_name is not null),
  check (party_kind <> 'customer' or direction = 'received'),
  check (party_kind <> 'supplier' or direction = 'issued')
);
create unique index if not exists dealer_cheques_uq127 on public.dealer_cheques (coalesce(business_id, 0), direction, lower(btrim(bank_name)), lower(btrim(cheque_no))) where status <> 'cancelled';
create unique index if not exists dealer_cheques_bankline127 on public.dealer_cheques (bank_line_id) where bank_line_id is not null;
create index if not exists dealer_cheques_due127 on public.dealer_cheques (location_id, status, due_date);
create index if not exists dealer_cheques_cust127 on public.dealer_cheques (customer_id) where customer_id is not null;
create index if not exists dealer_cheques_sup127 on public.dealer_cheques (supplier_id) where supplier_id is not null;

create table if not exists public.dealer_cheque_events (
  id bigserial primary key,
  cheque_id uuid not null references public.dealer_cheques(id),
  location_id int not null references public.locations(id),
  action text not null check (action in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled', 'bank_linked')),
  from_status text, to_status text,
  on_date date,
  amount numeric(16,2),
  ref text,
  note text,
  client_id uuid unique,
  actor uuid, at timestamptz not null default now()
);
create index if not exists dealer_cheque_events_ch127 on public.dealer_cheque_events (cheque_id, id);

create or replace function public._dl_append_only127() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;

drop trigger if exists dealer_cheques_no_delete on public.dealer_cheques;
create trigger dealer_cheques_no_delete before delete on public.dealer_cheques for each row execute function public.no_hard_delete();
drop trigger if exists dealer_cheque_events_ro on public.dealer_cheque_events;
create trigger dealer_cheque_events_ro before update or delete on public.dealer_cheque_events for each row execute function public._dl_append_only127();
drop trigger if exists audit_dealer_cheques on public.dealer_cheques;
create trigger audit_dealer_cheques after insert or update on public.dealer_cheques for each row execute function public.log_change('id');

alter table public.dealer_cheques enable row level security;
alter table public.dealer_cheque_events enable row level security;
drop policy if exists dl_cheques_read127 on public.dealer_cheques;
create policy dl_cheques_read127 on public.dealer_cheques for select to authenticated using (public._dl_ok127(location_id, 'dealer_cheque_view', 'dealer_cheque_manage'));
drop policy if exists dl_cheque_events_read127 on public.dealer_cheque_events;
create policy dl_cheque_events_read127 on public.dealer_cheque_events for select to authenticated using (public._dl_ok127(location_id, 'dealer_cheque_view', 'dealer_cheque_manage'));
revoke all on public.dealer_cheques, public.dealer_cheque_events from public, anon, authenticated;
grant select on public.dealer_cheques, public.dealer_cheque_events to authenticated;
revoke all on sequence public.dealer_cheque_events_id_seq from public, anon, authenticated;

-- sale_payments.mode: also allow 'bank' (a cleared cheque is bank money). Existing rows / modes are unchanged; nothing existing writes 'bank' here.
do $m$ begin
  if exists (select 1 from pg_constraint where conrelid = 'public.sale_payments'::regclass and conname = 'sale_payments_mode_check' and pg_get_constraintdef(oid) !~ 'bank') then
    alter table public.sale_payments drop constraint sale_payments_mode_check;
    alter table public.sale_payments add constraint sale_payments_mode_check check (mode in ('cash', 'mobile', 'card', 'bank'));
  end if;
end $m$;

-- ---------- 3. internal helpers ----------
create or replace function public._cheque_gate127(p_loc int, p_manage boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_manage then
    if not public._dl_ok127(p_loc, 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
    if not public.rule_on('dealer_cheque_on') then raise exception 'feature_off'; end if;
  else
    if not public._dl_ok127(p_loc, 'dealer_cheque_view', 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
  end if;
end $$;

-- insert one cheque row + its 'registered' event (used by cheque_register and cheque_replace)
create or replace function public._cheque_ins127(p_client uuid, p_loc int, p_dir text, p_kind text, p_party uuid, p_name text, p_bank text, p_branch text, p_no text,
  p_amount numeric, p_cdate date, p_due date, p_note text, p_replaces uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare amt numeric; due date; today date := public._dl_today127(); cid uuid; cu uuid; su uuid;
begin
  if p_client is null then raise exception 'client_required'; end if;
  if p_dir is null or p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier', 'other') then raise exception 'bad_party_kind'; end if;
  if p_amount is null or p_amount = 'NaN'::numeric or not (abs(p_amount) <= 1000000000000) then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if amt <= 0 then raise exception 'bad_amount'; end if;
  if p_bank is null or length(btrim(p_bank)) not between 1 and 80 then raise exception 'bank_required'; end if;
  if p_no is null or length(btrim(p_no)) not between 1 and 40 then raise exception 'cheque_no_required'; end if;
  if p_branch is not null and length(p_branch) > 80 then raise exception 'branch_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_cdate is null or p_cdate < today - 366 or p_cdate > today + 730 then raise exception 'bad_cheque_date'; end if;
  due := coalesce(p_due, p_cdate);
  if due < p_cdate or due > p_cdate + 366 then raise exception 'bad_due_date'; end if;
  if p_kind = 'customer' then
    if p_dir <> 'received' then raise exception 'customer_cheque_is_received'; end if;
    select id into cu from public.customers where id = p_party and active; if cu is null then raise exception 'customer_not_found'; end if;
  elsif p_kind = 'supplier' then
    if p_dir <> 'issued' then raise exception 'supplier_cheque_is_issued'; end if;
    select id into su from public.suppliers where id = p_party and active; if su is null then raise exception 'supplier_not_found'; end if;
  else
    if p_name is null or length(btrim(p_name)) not between 1 and 120 then raise exception 'party_name_required'; end if;
  end if;
  begin
    insert into public.dealer_cheques (client_id, business_id, location_id, direction, party_kind, customer_id, supplier_id, party_name, bank_name, branch_name, cheque_no,
        amount, cheque_date, due_date, replaces_id, note, created_by, updated_by)
      values (p_client, public._dl_biz127(p_loc), p_loc, p_dir, p_kind, cu, su, nullif(btrim(coalesce(p_name, '')), ''), btrim(p_bank), nullif(btrim(coalesce(p_branch, '')), ''), btrim(p_no),
        amt, p_cdate, due, p_replaces, nullif(btrim(coalesce(p_note, '')), ''), auth.uid(), auth.uid())
      returning id into cid;
  exception when unique_violation then raise exception 'duplicate_cheque';
  end;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (cid, p_loc, 'registered', null, 'registered', today, amt, case when p_replaces is not null then 'replaces ' || p_replaces::text end, left(p_note, 300), p_client, auth.uid());
  return cid;
end $$;

-- ---------- 4. write functions (browser) ----------
create or replace function public.cheque_register(p_client uuid, p_loc int, p_dir text, p_party_kind text, p_party uuid, p_party_name text, p_bank text, p_branch text,
  p_no text, p_amount numeric, p_cheque_date date, p_due_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; cid uuid;
begin
  perform public._cheque_gate127(p_loc, true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into c from public.dealer_cheques where client_id = p_client;
  if found then
    if not public._dl_ok127(c.location_id, 'dealer_cheque_manage') then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true);
  end if;
  cid := public._cheque_ins127(p_client, p_loc, p_dir, p_party_kind, p_party, p_party_name, p_bank, p_branch, p_no, p_amount, p_cheque_date, p_due_date, p_note, null);
  return jsonb_build_object('id', cid, 'status', 'registered');
end $$;

-- common: load + lock one cheque, check scope; a step key already used on ANOTHER cheque is refused
create or replace function public._cheque_load127(p_id uuid, p_client uuid) returns public.dealer_cheques
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  if p_client is not null then perform public._client_lock(p_client); end if;
  select * into c from public.dealer_cheques where id = p_id;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(c.location_id, true);
  if p_client is not null and exists (select 1 from public.dealer_cheque_events e where e.client_id = p_client and e.cheque_id <> p_id) then raise exception 'client_key_used'; end if;
  select * into c from public.dealer_cheques where id = p_id for update;
  return c;
end $$;
create or replace function public._cheque_dup127(p_id uuid, p_client uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_client is not null and exists (select 1 from public.dealer_cheque_events e where e.client_id = p_client and e.cheque_id = p_id);
$$;

create or replace function public.cheque_deposit(p_id uuid, p_date date, p_bank_account bigint default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127();
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'registered' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.cheque_date or p_date > today then raise exception 'bad_date'; end if;
  if p_bank_account is not null and not exists (select 1 from public.coa_accounts a where a.id = p_bank_account) then raise exception 'bad_bank_account'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  perform public.lock_check(p_date);
  update public.dealer_cheques set status = 'deposited', deposit_date = p_date, bank_account_id = coalesce(p_bank_account, bank_account_id), updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, note, client_id, actor)
    values (c.id, c.location_id, 'deposited', c.status, 'deposited', p_date, c.amount, left(p_note, 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'deposited');
end $$;

-- CLEAR: the only step that moves money in a party ledger. p_dry = true checks everything and returns the numbers, writes nothing.
create or replace function public.cheque_clear(p_id uuid, p_date date, p_note text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127(); bal numeric; lid bigint; sid text; at_ timestamptz; kind text;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'deposited' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.deposit_date or p_date > today then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  perform public.lock_check(p_date);
  if c.party_kind = 'customer' then
    perform 1 from public.customers where id = c.customer_id for no key update;           -- one posting at a time per customer
    bal := public._cust_bal(c.customer_id); kind := 'sale_payment';
    if c.amount > bal then raise exception 'overpaid'; end if;
  elsif c.party_kind = 'supplier' then
    perform 1 from public.suppliers where id = c.supplier_id for no key update;
    bal := public._sup_balance(c.supplier_id); kind := 'supplier_payment';
    if c.amount > bal then raise exception 'overpaid'; end if;
  end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'id', c.id, 'amount', c.amount, 'ledger', kind, 'balance_before', bal, 'balance_after', case when bal is not null then bal - c.amount end);
  end if;
  at_ := (p_date::timestamp + time '12:00') at time zone 'Asia/Dhaka';
  select staff_id into sid from public.profiles where id = auth.uid();
  if c.party_kind = 'customer' then
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, ref, amount, paid_at, note, created_by, created_staff, client_id)
      values (null, c.customer_id, c.location_id, 'collection', 'bank', left('CHQ ' || c.bank_name || ' ' || c.cheque_no, 60), c.amount, at_, left(coalesce(p_note, 'cheque cleared'), 200), auth.uid(), sid, c.id)
      returning id into lid;
  elsif c.party_kind = 'supplier' then
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, ref, amount, paid_at, note, created_by, created_staff, client_id)
      values (c.supplier_id, c.location_id, null, 'bank', left('CHQ ' || c.bank_name || ' ' || c.cheque_no, 60), c.amount, at_, left(coalesce(p_note, 'cheque cleared'), 200), auth.uid(), sid, c.id)
      returning id into lid;
  end if;
  update public.dealer_cheques set status = 'cleared', cleared_on = p_date, ledger_kind = kind, ledger_id = lid, updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (c.id, c.location_id, 'cleared', c.status, 'cleared', p_date, c.amount, case when lid is not null then kind || ':' || lid::text end, left(p_note, 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'cleared', 'amount', c.amount, 'ledger', kind, 'ledger_id', lid, 'balance_after', case when bal is not null then bal - c.amount end);
end $$;

-- BOUNCE: no ledger effect. The reason is required; the bank charge is only recorded.
create or replace function public.cheque_bounce(p_id uuid, p_date date, p_reason text, p_charge numeric default 0, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; today date := public._dl_today127(); chg numeric;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status <> 'deposited' then raise exception 'bad_status'; end if;
  if p_date is null or p_date < c.deposit_date or p_date > today then raise exception 'bad_date'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  if p_charge is null or p_charge = 'NaN'::numeric or not (p_charge between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  chg := round(p_charge, 2);
  perform public.lock_check(p_date);
  update public.dealer_cheques set status = 'bounced', bounced_on = p_date, bounce_reason = btrim(p_reason), bounce_charge = chg, updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, note, client_id, actor)
    values (c.id, c.location_id, 'bounced', c.status, 'bounced', p_date, c.amount, 'charge ' || chg::text, left(btrim(p_reason) || coalesce(' / ' || p_note, ''), 300), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'bounced', 'bounce_charge', chg);
end $$;

create or replace function public.cheque_cancel(p_id uuid, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'status', c.status, 'dup', true); end if;
  if c.status not in ('registered', 'bounced') then raise exception 'bad_status'; end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  update public.dealer_cheques set status = 'cancelled', updated_by = auth.uid(), updated_at = now() where id = c.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, note, client_id, actor)
    values (c.id, c.location_id, 'cancelled', c.status, 'cancelled', public._dl_today127(), c.amount, btrim(p_reason), p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'status', 'cancelled');
end $$;

-- REPLACE a bounced cheque by a new one (new registered cheque, same party and direction; the old one becomes 'replaced'). p_client is the key of the NEW cheque.
create or replace function public.cheque_replace(p_old uuid, p_client uuid, p_bank text, p_branch text, p_no text, p_amount numeric, p_cheque_date date, p_due_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.dealer_cheques; n public.dealer_cheques; nid uuid;
begin
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into o from public.dealer_cheques where id = p_old;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(o.location_id, true);
  select * into n from public.dealer_cheques where client_id = p_client;
  if found then
    if n.replaces_id is distinct from p_old then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', n.id, 'old', p_old, 'status', n.status, 'dup', true);
  end if;
  select * into o from public.dealer_cheques where id = p_old for update;
  if o.status <> 'bounced' then raise exception 'bad_status'; end if;
  nid := public._cheque_ins127(p_client, o.location_id, o.direction, o.party_kind, coalesce(o.customer_id, o.supplier_id), o.party_name, p_bank, p_branch, p_no, p_amount, p_cheque_date, p_due_date, p_note, o.id);
  update public.dealer_cheques set status = 'replaced', replaced_by = nid, updated_by = auth.uid(), updated_at = now() where id = o.id;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, actor)
    values (o.id, o.location_id, 'replaced', 'bounced', 'replaced', public._dl_today127(), o.amount, 'by ' || nid::text, auth.uid());
  return jsonb_build_object('id', nid, 'old', o.id, 'status', 'registered');
end $$;

-- ---------- 5. bank reconciliation hook ----------
-- candidates: cleared cheques with our bank account set and no statement line yet, vs statement lines of that account with the same signed amount (+ received, - issued) within 10 days of the clear date
create or replace function public.cheque_bank_candidates(p_business bigint default null)
returns table (cheque_id uuid, direction text, cheque_no text, amount numeric, cleared_on date, line_id bigint, line_date date, line_amount numeric, line_reference text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.direction, c.cheque_no, c.amount, c.cleared_on, l.id, l.line_date, l.amount, l.reference
    from public.dealer_cheques c join public.bank_statement_lines l on l.account_id = c.bank_account_id
      and l.amount = case when c.direction = 'received' then c.amount else -c.amount end and abs(l.line_date - c.cleared_on) <= 10
    where c.status = 'cleared' and c.bank_line_id is null and c.bank_account_id is not null
      and c.location_id in (select public._dl_vis127('dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)
      and not exists (select 1 from public.dealer_cheques x where x.bank_line_id = l.id)
    order by c.cleared_on, c.id, l.line_date, l.id;
end $$;

create or replace function public.cheque_bank_link(p_id uuid, p_line bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.dealer_cheques; l public.bank_statement_lines;
begin
  c := public._cheque_load127(p_id, p_client);
  if public._cheque_dup127(p_id, p_client) then return jsonb_build_object('id', c.id, 'bank_line_id', c.bank_line_id, 'dup', true); end if;
  if c.status <> 'cleared' then raise exception 'bad_status'; end if;
  if c.bank_account_id is null then raise exception 'bank_account_missing'; end if;
  if c.bank_line_id is not null then raise exception 'already_linked'; end if;
  select * into l from public.bank_statement_lines where id = p_line;
  if not found then raise exception 'line_not_found'; end if;
  if l.account_id <> c.bank_account_id then raise exception 'wrong_bank_account'; end if;
  if l.amount <> (case when c.direction = 'received' then c.amount else -c.amount end) then raise exception 'amount_mismatch'; end if;
  begin
    update public.dealer_cheques set bank_line_id = p_line, updated_by = auth.uid(), updated_at = now() where id = c.id;
  exception when unique_violation then raise exception 'line_already_used';
  end;
  insert into public.dealer_cheque_events (cheque_id, location_id, action, from_status, to_status, on_date, amount, ref, client_id, actor)
    values (c.id, c.location_id, 'bank_linked', c.status, c.status, public._dl_today127(), c.amount, 'line ' || p_line::text, p_client, auth.uid());
  return jsonb_build_object('id', c.id, 'bank_line_id', p_line);
end $$;

-- ---------- 6. reads ----------
create or replace function public._cheque_party127(c public.dealer_cheques) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select name from public.customers where id = c.customer_id), (select name from public.suppliers where id = c.supplier_id), c.party_name);
$$;

create or replace function public.cheque_list(p_business bigint default null, p_status text default null, p_dir text default null, p_limit int default 200)
returns table (id uuid, location_id int, direction text, party_kind text, party_name text, bank_name text, cheque_no text, amount numeric, cheque_date date, due_date date,
  status text, deposit_date date, cleared_on date, bounced_on date, bounce_reason text, bounce_charge numeric, replaced_by uuid, replaces_id uuid, bank_line_id bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('registered', 'deposited', 'cleared', 'bounced', 'replaced', 'cancelled') then raise exception 'bad_status'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.id, c.location_id, c.direction, c.party_kind, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.cheque_date, c.due_date, c.status, c.deposit_date, c.cleared_on,
           c.bounced_on, c.bounce_reason, c.bounce_charge, c.replaced_by, c.replaces_id, c.bank_line_id
    from public.dealer_cheques c
    where c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage'))
      and (p_business is null or c.business_id = p_business) and (p_status is null or c.status = p_status) and (p_dir is null or c.direction = p_dir)
    order by c.due_date desc, c.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;

-- cheques still to be deposited / cleared whose due date is within p_days (overdue ones included), with an aging bucket
create or replace function public.cheques_due(p_business bigint default null, p_days int default 7, p_dir text default null, p_asof date default null)
returns table (id uuid, location_id int, direction text, party_name text, bank_name text, cheque_no text, amount numeric, cheque_date date, due_date date, status text, days_to_due int, bucket text)
language plpgsql stable security definer set search_path = public as $$
declare a date := coalesce(p_asof, public._dl_today127());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 0 or p_days > 3650 then raise exception 'bad_days'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.id, c.location_id, c.direction, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.cheque_date, c.due_date, c.status, (c.due_date - a),
           case when c.due_date < a then 'overdue' when c.due_date = a then 'today' when c.due_date <= a + 7 then 'this_week' else 'later' end
    from public.dealer_cheques c
    where c.status in ('registered', 'deposited') and c.due_date <= a + p_days
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage'))
      and (p_business is null or c.business_id = p_business) and (p_dir is null or c.direction = p_dir)
    order by c.due_date, c.id;
end $$;

create or replace function public.cheques_bounced(p_business bigint default null, p_from date default null, p_to date default null)
returns table (id uuid, location_id int, direction text, party_name text, bank_name text, cheque_no text, amount numeric, bounced_on date, bounce_reason text, bounce_charge numeric, status text, replaced_by uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.location_id, c.direction, public._cheque_party127(c), c.bank_name, c.cheque_no, c.amount, c.bounced_on, c.bounce_reason, c.bounce_charge, c.status, c.replaced_by
    from public.dealer_cheques c
    where c.bounced_on is not null and (p_from is null or c.bounced_on >= p_from) and (p_to is null or c.bounced_on <= p_to)
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)
    order by c.bounced_on desc, c.id;
end $$;

-- post-dated exposure per party: cheques not yet cleared whose cheque date is still in the future
-- (received = money we expect and have not got; issued = money we have promised and have not paid)
create or replace function public.post_dated_exposure(p_business bigint default null, p_dir text default null, p_asof date default null)
returns table (direction text, party_kind text, party_id uuid, party_name text, cheques int, total numeric, earliest_due date, latest_due date)
language plpgsql stable security definer set search_path = public as $$
declare a date := coalesce(p_asof, public._dl_today127());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_dir is not null and p_dir not in ('received', 'issued') then raise exception 'bad_direction'; end if;
  return query
    select c.direction, c.party_kind, coalesce(c.customer_id, c.supplier_id), max(public._cheque_party127(c)), count(*)::int, sum(c.amount), min(c.due_date), max(c.due_date)
    from public.dealer_cheques c
    where c.status in ('registered', 'deposited') and c.cheque_date > a
      and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business) and (p_dir is null or c.direction = p_dir)
    group by c.direction, c.party_kind, coalesce(c.customer_id, c.supplier_id), case when c.party_kind = 'other' then lower(btrim(c.party_name)) end
    order by 6 desc, 4;
end $$;

-- control: cleared cheques whose ledger payment was voided elsewhere (void_collection / void_supplier_payment) - the cheque would still say cleared
create or replace function public.cheque_ledger_check(p_business bigint default null)
returns table (id uuid, direction text, cheque_no text, amount numeric, cleared_on date, ledger_kind text, ledger_id bigint, problem text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select z.* from (
      select c.id, c.direction, c.cheque_no, c.amount, c.cleared_on, c.ledger_kind, c.ledger_id,
        case when c.ledger_kind = 'sale_payment' and not exists (select 1 from public.sale_payments p where p.id = c.ledger_id and not p.voided and p.amount = c.amount) then 'ledger_payment_voided_or_changed'
             when c.ledger_kind = 'supplier_payment' and not exists (select 1 from public.supplier_payments p where p.id = c.ledger_id and not p.voided and p.amount = c.amount) then 'ledger_payment_voided_or_changed'
             when c.ledger_kind is null and c.party_kind <> 'other' then 'ledger_link_missing' end as problem
      from public.dealer_cheques c
      where c.status = 'cleared' and c.location_id in (select public._dl_vis127('dealer_cheque_view', 'dealer_cheque_manage')) and (p_business is null or c.business_id = p_business)) z
    where z.problem is not null order by z.cleared_on, z.id;
end $$;

-- history of one cheque
create or replace function public.cheque_events(p_id uuid)
returns table (at timestamptz, action text, from_status text, to_status text, on_date date, amount numeric, ref text, note text)
language plpgsql stable security definer set search_path = public as $$
declare c public.dealer_cheques;
begin
  select * into c from public.dealer_cheques where id = p_id;
  if not found then raise exception 'cheque_not_found'; end if;
  perform public._cheque_gate127(c.location_id, false);
  return query select e.at, e.action, e.from_status, e.to_status, e.on_date, e.amount, e.ref, e.note from public.dealer_cheque_events e where e.cheque_id = p_id order by e.id;
end $$;

-- ---------- 7. grants on functions ----------
revoke all on function public._dl_biz127(int), public._dl_ok127(int, text, text), public._dl_vis127(text, text), public._dl_biz_ok127(bigint, text, text), public._dl_today127(),
  public._dl_append_only127(), public._cheque_gate127(int, boolean), public._cheque_ins127(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text, uuid),
  public._cheque_load127(uuid, uuid), public._cheque_dup127(uuid, uuid), public._cheque_party127(public.dealer_cheques) from public, anon, authenticated;
revoke all on function public.cheque_register(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text), public.cheque_deposit(uuid, date, bigint, text, uuid),
  public.cheque_clear(uuid, date, text, uuid, boolean), public.cheque_bounce(uuid, date, text, numeric, text, uuid), public.cheque_cancel(uuid, text, uuid),
  public.cheque_replace(uuid, uuid, text, text, text, numeric, date, date, text), public.cheque_bank_candidates(bigint), public.cheque_bank_link(uuid, bigint, uuid),
  public.cheque_list(bigint, text, text, int), public.cheques_due(bigint, int, text, date), public.cheques_bounced(bigint, date, date),
  public.post_dated_exposure(bigint, text, date), public.cheque_ledger_check(bigint), public.cheque_events(uuid) from public, anon;
grant execute on function public.cheque_register(uuid, int, text, text, uuid, text, text, text, text, numeric, date, date, text), public.cheque_deposit(uuid, date, bigint, text, uuid),
  public.cheque_clear(uuid, date, text, uuid, boolean), public.cheque_bounce(uuid, date, text, numeric, text, uuid), public.cheque_cancel(uuid, text, uuid),
  public.cheque_replace(uuid, uuid, text, text, text, numeric, date, date, text), public.cheque_bank_candidates(bigint), public.cheque_bank_link(uuid, bigint, uuid),
  public.cheque_list(bigint, text, text, int), public.cheques_due(bigint, int, text, date), public.cheques_bounced(bigint, date, date),
  public.post_dated_exposure(bigint, text, date), public.cheque_ledger_check(bigint), public.cheque_events(uuid) to authenticated;
-- the row policies call it as the signed-in user (it only answers about the caller's own rights)
grant execute on function public._dl_ok127(int, text, text) to authenticated;

commit;

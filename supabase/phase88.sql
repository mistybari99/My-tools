-- Phase 88 (bos88) - OPENING DUES AND PAYABLES LINKED TO THE CUSTOMER AND SUPPLIER SUB-LEDGERS (plan item U-01, package W1-A).
-- Paste AFTER phase87. Paste-twice safe. Earlier phase files are not edited. Nothing in an existing function is changed by THIS file (see "HOOKS" below).
--
-- THE PROBLEM
--   An old customer due (owed before go-live) is in the books (phase80 opening journal: Dr receivable with the customer as party) but NOT in the customer sub-ledger:
--   collect_payment raises "overpaid", the POS credit limit ignores the old due, the dues list does not show it. A supplier opening has to be typed twice
--   (suppliers.opening_balance for the sub-ledger, and again in the opening JSON for the books).
-- WHAT THIS FILE ADDS (all new objects, own prefix _w1a_ / w1a_)
--   customers.opening_balance / opening_date, suppliers.opening_date (suppliers.opening_balance already exists and is already part of _sup_balance)
--   three SETTINGS (rules, module books, safe defaults = today's behaviour, editable by the owner at any time, every change is an audit_log line through audit_rules):
--     open_parties_link         switch  OFF   ON = the typed opening due is part of the customer balance (credit limit, collect, dues list, ledger) and opening_balance_post fills it
--     open_parties_freeze       choice  off   after_opening = once the opening batch is posted a direct change of an opening figure is refused; the way is an adjustment with a reason
--     open_parties_adjust_mode  choice  direct   direct = a holder of Accounts manage adjusts with a reason; approval = a second person decides (the owner's own request follows
--                                               the owner approval setting of phase80/87: self, logged, off or named approvers; nothing is hard-coded)
--   w1a_open_state / w1a_open_list (list with the DIFFERENCE column: books minus sub-ledger) / w1a_open_set / w1a_open_import (paste import, dry run first, all or nothing)
--   w1a_open_json (the customer_dues and supplier_dues sections for the opening screen, from what was typed once) / w1a_open_precheck / w1a_open_from_journal (fill from an
--   opening batch that was posted before this phase) / w1a_open_adjust + w1a_open_adjust_decide + w1a_open_adjust_list (change after the opening: reason required, balanced
--   adjustment journal, one audit_log line, one row in the Exceptions list) / w1a_party_gate (per party: sub-ledger equals general ledger, wraps acct_reconcile and names the cause)
--   _w1a_cust_open / _w1a_opening_apply (the pieces the hooks call) / _w1a_patch (exact-text patch helper with a marker parameter, see below)
-- EXCEPTIONS: every adjustment and every frozen change needs a written reason (min 3 characters), writes audit_log and a row in the Exceptions list (exceptions, flag opening_adjusted).
--   Nothing here is tied to a person or to a role: permission is the existing Accounts manage grant (_acct_manage), the approver of the owner's own request is read from the
--   owner approval setting. Nothing is deleted.
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner turns a setting on: all three defaults keep today's behaviour and the new columns are empty.
--
-- HOOKS (the integrator pastes them in phase99; the exact text is in docs/integration/W1-A.md and in tests/sql/phase88_hooks.sql). This file does NOT patch a shared function.
--   _cust_bal, customer_dues, customer_ledger : read _w1a_cust_open(customer)  (0 while open_parties_link is OFF)
--   opening_balance_post                      : perform _w1a_opening_apply(p_json) after the journal entry
--   !! _m_patch of phase87 cannot patch opening_balance_post again (it stops when the marker bos87 is already inside). Use _w1a_patch (marker bos88).
--   !! Re-pasting phase 6, 12, 80 or 87 removes the hooks: paste the hook file again.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase88 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.opening_balance_post(jsonb,uuid,boolean,boolean)') is null or to_regprocedure('public.acct_reconcile(text)') is null
     or to_regprocedure('public._cust_bal(uuid)') is null or to_regprocedure('public._sup_balance(uuid)') is null or to_regprocedure('public.customer_dues()') is null
     or to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null or to_regprocedure('public._owner_approver_users()') is null then
    raise exception 'phase88 needs the shared functions of phases 6, 12, 40, 80, 87';
  end if;
end $g$;

create or replace function public._p88_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic exact-text patch helper with its OWN marker (phase87 _m_patch is hard-wired to bos87 and cannot patch a function that already carries bos87) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed). Marker already inside = no-op (returns false).
create or replace function public._w1a_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bos88') returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

-- ---------- columns ----------
alter table public.customers add column if not exists opening_balance numeric;
alter table public.customers add column if not exists opening_date date;
alter table public.suppliers add column if not exists opening_date date;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_opening_balance_chk') then
    alter table public.customers add constraint customers_opening_balance_chk check (opening_balance is null or (opening_balance >= 0 and opening_balance <= 1000000000000));
  end if;
end $c$;

-- ---------- settings (rules). Bangla later: the Bangla column carries the English text for now. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('open_parties_link', 'books', 'switch', 'false', null, null, null, null,
  'Count opening dues in customer balances', 'Count opening dues in customer balances', 'Count opening dues in customer balances',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.', 150),
 ('open_parties_freeze', 'books', 'choice', '"off"', null, '["off","after_opening"]', null, null,
  'Lock opening dues after the opening batch', 'Lock opening dues after the opening batch', 'Lock opening dues after the opening batch',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.', 151),
 ('open_parties_adjust_mode', 'books', 'choice', '"direct"', null, '["direct","approval"]', null, null,
  'Who decides a change of an opening due', 'Who decides a change of an opening due', 'Who decides a change of an opening due',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.', 152)
on conflict (key) do nothing;

-- ---------- small helpers ----------
-- who may type, import and adjust openings: a holder of Accounts manage (owner or delegated) who works company-wide (an opening is a company figure, not a place figure)
create or replace function public._w1a_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public._acct_manage() and public._acct_all() $$;
create or replace function public._w1a_batch_exists() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.opening_batches) $$;
create or replace function public._w1a_frozen() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('open_parties_freeze'), 'off') = 'after_opening' and public._w1a_batch_exists() $$;

-- what a customer's opening due adds to the balance. 0 while the switch is OFF, and 0 before the opening date.
create or replace function public._w1a_cust_open(p_customer uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when public.rule_on('open_parties_link')
              then coalesce((select c.opening_balance from public.customers c where c.id = p_customer and (c.opening_date is null or c.opening_date <= (now() at time zone 'Asia/Dhaka')::date)), 0)
              else 0 end $$;
create or replace function public._w1a_cust_open_date(p_customer uuid) returns date language sql stable security definer set search_path = public as $$
  select coalesce(c.opening_date, public._acct_start()) from public.customers c where c.id = p_customer $$;
create or replace function public._w1a_cust_open_at(p_customer uuid) returns timestamptz language sql stable security definer set search_path = public as $$
  select (coalesce((select c.opening_date from public.customers c where c.id = p_customer), public._acct_start(), (now() at time zone 'Asia/Dhaka')::date)::timestamp at time zone 'Asia/Dhaka') $$;

create or replace function public._w1a_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail);
end $$;

-- one row in the Exceptions list (public.exceptions, shown in #/exceptions to the owner and to approvers)
create or replace function public._w1a_exc(p_flag text, p_level text, p_amount numeric, p_en text, p_bn text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, 'ACC', (select min(id) from public.locations), (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, p_amount, jsonb_build_object('bn', p_bn, 'en', p_en));
end $$;

-- ---------- freeze: a direct change of an opening figure after the opening batch (only while open_parties_freeze = after_opening) ----------
create or replace function public._w1a_open_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.opening_balance is not distinct from old.opening_balance and new.opening_date is not distinct from old.opening_date then return new; end if;
  else
    if coalesce(new.opening_balance, 0) = 0 then return new; end if;
  end if;
  if coalesce(current_setting('bos88.api', true), '') = '1' then return new; end if;      -- our own functions (they carry their own reason, audit and exception)
  if public._w1a_frozen() then raise exception 'opening_frozen'; end if;
  return new;
end $$;
drop trigger if exists customers_open_guard88 on public.customers;
create trigger customers_open_guard88 before insert or update of opening_balance, opening_date on public.customers for each row execute function public._w1a_open_guard();
drop trigger if exists suppliers_open_guard88 on public.suppliers;
create trigger suppliers_open_guard88 before insert or update of opening_balance, opening_date on public.suppliers for each row execute function public._w1a_open_guard();

-- ---------- adjustments (append only, decided once) ----------
create table if not exists public.open_party_adjustments (
  id bigserial primary key,
  client_id uuid unique,
  kind text not null check (kind in ('customer', 'supplier')),
  party_id uuid not null,
  party_name text,
  old_amount numeric not null,
  new_amount numeric not null,
  delta numeric not null check (delta <> 0),
  reason text not null check (length(btrim(reason)) >= 3),
  mode text not null default 'direct' check (mode in ('direct', 'approval')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid, requested_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz, decision_note text,
  journal_entry_id bigint
);
create unique index if not exists open_party_adjustments_one_pending on public.open_party_adjustments (kind, party_id) where status = 'pending';
do $t$ begin
  drop trigger if exists open_party_adjustments_nodel on public.open_party_adjustments;
  create trigger open_party_adjustments_nodel before delete on public.open_party_adjustments for each row execute function public.no_hard_delete();
  drop trigger if exists audit_open_party_adjustments on public.open_party_adjustments;
  create trigger audit_open_party_adjustments after insert or update on public.open_party_adjustments for each row execute function public.log_change('id');
  alter table public.open_party_adjustments enable row level security;
  revoke all on public.open_party_adjustments from public, anon, authenticated;
  drop policy if exists open_party_adjustments_read on public.open_party_adjustments;
  create policy open_party_adjustments_read on public.open_party_adjustments for select to authenticated using (public._acct_view());
  grant select on public.open_party_adjustments to authenticated;
  revoke all on sequence public.open_party_adjustments_id_seq from public, anon, authenticated;
end $t$;

-- ============================================================================
-- STATE and LIST
-- ============================================================================
create or replace function public.w1a_open_state() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select id, at into b from public.opening_batches order by id limit 1;
  return jsonb_build_object(
    'link', public.rule_on('open_parties_link'), 'freeze', coalesce(public.rule_txt('open_parties_freeze'), 'off'), 'adjust_mode', coalesce(public.rule_txt('open_parties_adjust_mode'), 'direct'),
    'batch_exists', b.id is not null, 'batch_at', b.at, 'frozen', public._w1a_frozen(), 'accounting_start', public._acct_start(),
    'can_manage', public._w1a_mgr(), 'is_owner', public.is_owner(), 'all_places', public._acct_all(),
    'customers_typed', (select count(*) from public.customers where coalesce(opening_balance, 0) <> 0),
    'customers_typed_total', (select coalesce(sum(opening_balance), 0) from public.customers where coalesce(opening_balance, 0) <> 0),
    'suppliers_typed', (select count(*) from public.suppliers where coalesce(opening_balance, 0) <> 0),
    'suppliers_typed_total', (select coalesce(sum(opening_balance), 0) from public.suppliers where coalesce(opening_balance, 0) <> 0),
    'pending_adjustments', (select count(*) from public.open_party_adjustments where status = 'pending'));
end $$;

-- the list, with the difference column: general ledger (journal, by party) minus the sub-ledger balance. A row with a difference is a party whose books and sub-ledger disagree.
create or replace function public.w1a_open_list(p_kind text, p_search text default null, p_only text default 'all', p_limit int default 300, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ar bigint; ap bigint; lim int := least(greatest(coalesce(p_limit, 300), 1), 1000); off_ int := greatest(coalesce(p_offset, 0), 0); s text := nullif(btrim(coalesce(p_search, '')), ''); res jsonb; mg boolean := public._w1a_mgr();
begin
  if not (public._acct_view() and public._acct_all()) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_only is null or p_only not in ('all', 'opening', 'diff') then raise exception 'bad_value'; end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  if p_kind = 'customer' then
    with j as (
      select l.party_id pid, sum(l.debit - l.credit) gl,
             coalesce(sum(l.debit - l.credit) filter (where e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening')), 0) jo
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = ar and l.party_type = 'customer' group by 1),
    b as (
      select c.id, c.name, c.mobile, c.active, c.opening_balance, c.opening_date, coalesce(j.gl, 0) gl, coalesce(j.jo, 0) jo
        from public.customers c left join j on j.pid = c.id::text
       where (s is null or position(lower(s) in lower(c.name)) > 0 or position(s in c.mobile) > 0)
         and (p_only <> 'opening' or coalesce(c.opening_balance, 0) <> 0 or coalesce(j.jo, 0) <> 0)
       order by lower(c.name), c.id
       limit case when p_only = 'diff' then null else lim + 1 end offset case when p_only = 'diff' then 0 else off_ end),
    d as (select b.*, public._cust_bal(b.id) sub from b),
    f as (select d.*, round(d.gl - d.sub, 2) df from d where p_only <> 'diff' or abs(d.gl - d.sub) > 0.005 order by case when p_only = 'diff' then abs(d.gl - d.sub) end desc nulls last, lower(d.name), d.id
          limit lim + 1 offset case when p_only = 'diff' then off_ else 0 end)
    select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'mobile', case when mg then f.mobile end, 'active', f.active, 'opening', f.opening_balance, 'opening_date', f.opening_date,
             'journal_opening', f.jo, 'journal_balance', f.gl, 'subledger_balance', f.sub, 'difference', f.df) order by case when p_only = 'diff' then abs(f.df) end desc nulls last, lower(f.name), f.id) filter (where f.rn <= lim), '[]'::jsonb),
           'has_more', coalesce(bool_or(f.rn > lim), false))
      into res from (select f0.*, row_number() over (order by case when p_only = 'diff' then abs(f0.df) end desc nulls last, lower(f0.name), f0.id) rn from f f0) f;
  else
    with j as (
      select l.party_id pid, sum(l.credit - l.debit) gl,
             coalesce(sum(l.credit - l.debit) filter (where e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening')), 0) jo
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = ap and l.party_type = 'supplier' group by 1),
    b as (
      select c.id, c.name, c.mobile, c.active, c.opening_balance, c.opening_date, coalesce(j.gl, 0) gl, coalesce(j.jo, 0) jo
        from public.suppliers c left join j on j.pid = c.id::text
       where (s is null or position(lower(s) in lower(c.name)) > 0 or position(s in coalesce(c.mobile, '')) > 0)
         and (p_only <> 'opening' or coalesce(c.opening_balance, 0) <> 0 or coalesce(j.jo, 0) <> 0)
       order by lower(c.name), c.id
       limit case when p_only = 'diff' then null else lim + 1 end offset case when p_only = 'diff' then 0 else off_ end),
    d as (select b.*, public._sup_balance(b.id) sub from b),
    f as (select d.*, round(d.gl - d.sub, 2) df from d where p_only <> 'diff' or abs(d.gl - d.sub) > 0.005 order by case when p_only = 'diff' then abs(d.gl - d.sub) end desc nulls last, lower(d.name), d.id
          limit lim + 1 offset case when p_only = 'diff' then off_ else 0 end)
    select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'mobile', case when mg then f.mobile end, 'active', f.active, 'opening', f.opening_balance, 'opening_date', f.opening_date,
             'journal_opening', f.jo, 'journal_balance', f.gl, 'subledger_balance', f.sub, 'difference', f.df) order by case when p_only = 'diff' then abs(f.df) end desc nulls last, lower(f.name), f.id) filter (where f.rn <= lim), '[]'::jsonb),
           'has_more', coalesce(bool_or(f.rn > lim), false))
      into res from (select f0.*, row_number() over (order by case when p_only = 'diff' then abs(f0.df) end desc nulls last, lower(f0.name), f0.id) rn from f f0) f;
  end if;
  return res || jsonb_build_object('kind', p_kind, 'link', public.rule_on('open_parties_link'), 'frozen', public._w1a_frozen());
end $$;

-- ============================================================================
-- STAGING: type the opening once (before the opening batch). One party, or a paste import.
-- ============================================================================
create or replace function public.w1a_open_set(p_kind text, p_party uuid, p_amount numeric, p_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ numeric; old_d date; amt numeric; nm text;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if public._w1a_batch_exists() then raise exception 'opening_posted_use_adjust'; end if;
  if p_amount is not null and (p_amount = 'NaN'::numeric or abs(p_amount) > 1000000000000) then raise exception 'bad_amount'; end if;
  if p_kind = 'customer' and p_amount < 0 then raise exception 'negative_not_allowed'; end if;
  amt := nullif(round(coalesce(p_amount, 0), 2), 0);
  if p_kind = 'customer' then
    select opening_balance, opening_date, name into old_, old_d, nm from public.customers where id = p_party for update;
  else
    select opening_balance, opening_date, name into old_, old_d, nm from public.suppliers where id = p_party for update;
  end if;
  if not found then raise exception 'unknown_party'; end if;
  perform set_config('bos88.api', '1', true);
  if p_kind = 'customer' then update public.customers set opening_balance = amt, opening_date = coalesce(p_date, opening_date) where id = p_party;
  else update public.suppliers set opening_balance = amt, opening_date = coalesce(p_date, opening_date) where id = p_party; end if;
  perform set_config('bos88.api', '', true);
  perform public._w1a_audit('open_party_set', case p_kind when 'customer' then 'customers' else 'suppliers' end, p_party::text,
    jsonb_build_object('name', nm, 'old', old_, 'new', amt, 'old_date', old_d, 'new_date', coalesce(p_date, old_d), 'note', left(p_note, 200)));
  return jsonb_build_object('kind', p_kind, 'party_id', p_party, 'old', old_, 'new', amt);
end $$;

-- paste import. p_rows: [{party_id | mobile | name, amount, date?, name?}]. Dry run (default) writes nothing. A real run is ALL OR NOTHING: one bad row refuses the whole file.
-- Customers that do not exist yet can be created (p_create, needs mobile and name); suppliers are never created here.
create or replace function public.w1a_open_import(p_kind text, p_rows jsonb, p_dry boolean default true, p_create boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; i int := 0; out_ jsonb := '[]'::jsonb; todo jsonb := '[]'::jsonb; n_ok int := 0; n_same int := 0; n_err int := 0; n_new int := 0; tot numeric := 0;
  pid uuid; st text; txt text; amt numeric; dt date; dg text; cnt int; old_ numeric; old_d date; nm text; seen uuid[] := '{}'; mob text; create_ boolean; t jsonb;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if public._w1a_batch_exists() then raise exception 'opening_posted_use_adjust'; end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; st := null; pid := null; amt := null; dt := null; old_ := null; old_d := null; nm := null; create_ := false; mob := null;
    begin
      if jsonb_typeof(x) <> 'object' then st := 'bad_row'; end if;
      -- amount
      if st is null then
        txt := replace(translate(coalesce(x ->> 'amount', ''), '০১২৩৪৫৬৭৮৯', '0123456789'), ',', '');
        if txt = '' then txt := '0'; end if;
        if txt !~ '^-?[0-9]{1,12}(\.[0-9]{1,2})?$' then st := 'bad_amount'; else amt := txt::numeric; end if;
        if st is null and p_kind = 'customer' and amt < 0 then st := 'negative_not_allowed'; end if;
      end if;
      if st is null and nullif(x ->> 'date', '') is not null then
        if (x ->> 'date') !~ '^\d{4}-\d{2}-\d{2}$' then st := 'bad_date'; else begin dt := (x ->> 'date')::date; exception when others then st := 'bad_date'; end; end if;
      end if;
      -- which party
      if st is null then
        if nullif(x ->> 'party_id', '') is not null then
          if (x ->> 'party_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then st := 'unknown_party';
          else
            pid := (x ->> 'party_id')::uuid;
            if p_kind = 'customer' then select count(*) into cnt from public.customers where id = pid; else select count(*) into cnt from public.suppliers where id = pid; end if;
            if cnt = 0 then st := 'unknown_party'; pid := null; end if;
          end if;
        elsif nullif(x ->> 'mobile', '') is not null then
          mob := right(regexp_replace(translate(x ->> 'mobile', '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9]', '', 'g'), 10);
          if length(mob) <> 10 then st := 'bad_mobile';
          else
            if p_kind = 'customer' then select count(*), min(id::text)::uuid into cnt, pid from public.customers where right(regexp_replace(mobile, '[^0-9]', '', 'g'), 10) = mob;
            else select count(*), min(id::text)::uuid into cnt, pid from public.suppliers where right(regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g'), 10) = mob; end if;
            if cnt > 1 then st := 'ambiguous_party'; pid := null;
            elsif cnt = 0 then
              pid := null;
              if p_kind = 'customer' and p_create and nullif(btrim(coalesce(x ->> 'name', '')), '') is not null then create_ := true; else st := 'unknown_party'; end if;
            end if;
          end if;
        elsif nullif(btrim(coalesce(x ->> 'name', '')), '') is not null then
          if p_kind = 'customer' then select count(*), min(id::text)::uuid into cnt, pid from public.customers where lower(btrim(name)) = lower(btrim(x ->> 'name'));
          else select count(*), min(id::text)::uuid into cnt, pid from public.suppliers where lower(btrim(name)) = lower(btrim(x ->> 'name')); end if;
          if cnt > 1 then st := 'ambiguous_party'; pid := null; elsif cnt = 0 then st := 'unknown_party'; pid := null; end if;
        else st := 'party_missing'; end if;
      end if;
      if st is null and pid is not null then
        if pid = any (seen) then st := 'duplicate_row'; else seen := seen || pid; end if;
      end if;
      if st is null and pid is not null then
        if p_kind = 'customer' then select opening_balance, opening_date, name into old_, old_d, nm from public.customers where id = pid;
        else select opening_balance, opening_date, name into old_, old_d, nm from public.suppliers where id = pid; end if;
        if coalesce(old_, 0) = coalesce(amt, 0) and (dt is null or old_d is not distinct from dt) then st := 'same'; n_same := n_same + 1;
        else st := 'ok'; n_ok := n_ok + 1; tot := tot + coalesce(amt, 0); todo := todo || jsonb_build_object('party', pid, 'amount', amt, 'date', dt); end if;
      elsif st is null and create_ then
        st := 'will_create'; n_new := n_new + 1; nm := left(btrim(x ->> 'name'), 80); tot := tot + coalesce(amt, 0);
        todo := todo || jsonb_build_object('create', true, 'mobile', x ->> 'mobile', 'name', nm, 'amount', amt, 'date', dt);
      end if;
    exception when others then st := 'bad_row'; end;
    if st not in ('ok', 'same', 'will_create') then n_err := n_err + 1; end if;
    out_ := out_ || jsonb_build_object('i', i, 'status', st, 'party_id', pid, 'name', coalesce(nm, left(x ->> 'name', 80)), 'old', old_, 'new', amt);
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'rows', out_, 'ok', n_ok, 'same', n_same, 'create', n_new, 'errors', n_err, 'total_new', tot);
  end if;
  if n_err > 0 then raise exception 'import_has_errors' using detail = n_err::text || ' row(s) are not valid: nothing was written'; end if;
  perform set_config('bos88.api', '1', true);
  for t in select * from jsonb_array_elements(todo) loop
    if (t ->> 'create') = 'true' then
      -- a customer who has never bought here (an old due owed from before go-live)
      begin mob := public.norm_mobile(t ->> 'mobile'); exception when others then raise exception 'bad_mobile'; end;
      insert into public.customers (mobile, name, type, created_by, opening_balance, opening_date)
        values (mob, t ->> 'name', 'retail', auth.uid(), nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), (t ->> 'date')::date)
        on conflict (mobile) do update set opening_balance = excluded.opening_balance, opening_date = coalesce(excluded.opening_date, public.customers.opening_date);
    elsif p_kind = 'customer' then
      update public.customers set opening_balance = nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), opening_date = coalesce((t ->> 'date')::date, opening_date) where id = (t ->> 'party')::uuid;
    else
      update public.suppliers set opening_balance = nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), opening_date = coalesce((t ->> 'date')::date, opening_date) where id = (t ->> 'party')::uuid;
    end if;
  end loop;
  perform set_config('bos88.api', '', true);
  perform public._w1a_audit('open_party_import', case p_kind when 'customer' then 'customers' else 'suppliers' end, null,
    jsonb_build_object('kind', p_kind, 'rows', jsonb_array_length(p_rows), 'changed', n_ok, 'created', n_new, 'unchanged', n_same, 'total_new', tot));
  return jsonb_build_object('dry', false, 'kind', p_kind, 'changed', n_ok, 'created', n_new, 'unchanged', n_same, 'total_new', tot);
end $$;

-- ============================================================================
-- THE OPENING SCREEN: the customer_dues and supplier_dues sections come from what was typed once
-- ============================================================================
create or replace function public.w1a_open_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if public._w1a_batch_exists() then return jsonb_build_object('batch_exists', true, 'customer_dues', '[]'::jsonb, 'supplier_dues', '[]'::jsonb, 'not_postable', '[]'::jsonb); end if;
  return jsonb_build_object('batch_exists', false,
    'customer_dues', coalesce((select jsonb_agg(jsonb_build_object('customer_id', c.id, 'amount', c.opening_balance::text) order by c.id) from public.customers c where coalesce(c.opening_balance, 0) > 0), '[]'::jsonb),
    'supplier_dues', coalesce((select jsonb_agg(jsonb_build_object('supplier_id', s.id, 'amount', s.opening_balance::text) order by s.id) from public.suppliers s where coalesce(s.opening_balance, 0) > 0), '[]'::jsonb),
    'not_postable', coalesce((select jsonb_agg(jsonb_build_object('kind', 'supplier', 'party_id', s.id, 'name', s.name, 'amount', s.opening_balance, 'why', 'a supplier who owes us (negative opening) cannot go in the supplier_dues section: enter it after the opening as an adjustment')
                                order by s.id) from public.suppliers s where coalesce(s.opening_balance, 0) < 0), '[]'::jsonb));
end $$;

-- compare an opening JSON with what is typed on the parties
create or replace function public.w1a_open_precheck(p_json jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb := '[]'::jsonb; x record;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_json is null or jsonb_typeof(p_json) <> 'object' then raise exception 'bad_payload'; end if;
  for x in
    select 'customer' kind, coalesce(a.pid, b.id::text) pid, c.name, a.amt jamt, coalesce(c.opening_balance, 0) typed
      from (select e ->> 'customer_id' pid, sum((e ->> 'amount')::numeric) amt from jsonb_array_elements(coalesce(p_json -> 'customer_dues', '[]'::jsonb)) e group by 1) a
      full join (select id from public.customers where coalesce(opening_balance, 0) <> 0) b on b.id::text = a.pid
      left join public.customers c on c.id::text = coalesce(a.pid, b.id::text)
    union all
    select 'supplier', coalesce(a.pid, b.id::text), c.name, a.amt, coalesce(c.opening_balance, 0)
      from (select e ->> 'supplier_id' pid, sum((e ->> 'amount')::numeric) amt from jsonb_array_elements(coalesce(p_json -> 'supplier_dues', '[]'::jsonb)) e group by 1) a
      full join (select id from public.suppliers where coalesce(opening_balance, 0) <> 0) b on b.id::text = a.pid
      left join public.suppliers c on c.id::text = coalesce(a.pid, b.id::text)
  loop
    rows_ := rows_ || jsonb_build_object('kind', x.kind, 'party_id', x.pid, 'name', x.name, 'json_amount', x.jamt, 'typed', x.typed,
      'status', case when x.jamt is null then 'typed_not_in_json' when x.typed = 0 then 'not_typed' when x.jamt = x.typed then 'same' else 'differs' end);
  end loop;
  return jsonb_build_object('rows', rows_, 'link', public.rule_on('open_parties_link'),
    'differing', (select count(*) from jsonb_array_elements(rows_) r where r ->> 'status' <> 'same'));
end $$;

-- the piece the opening_balance_post hook calls, inside the same transaction as the journal entry. Does nothing while open_parties_link is OFF.
create or replace function public._w1a_opening_apply(p_json jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x record; st date := public._acct_start(); old_ numeric; nc int := 0; ns int := 0;
begin
  if not public.rule_on('open_parties_link') then return; end if;
  perform set_config('bos88.api', '1', true);
  for x in select (e ->> 'customer_id')::uuid pid, round(sum((e ->> 'amount')::numeric), 2) amt from jsonb_array_elements(coalesce(p_json -> 'customer_dues', '[]'::jsonb)) e group by 1 loop
    select opening_balance into old_ from public.customers where id = x.pid;
    update public.customers set opening_balance = nullif(x.amt, 0), opening_date = coalesce(st, opening_date) where id = x.pid;
    nc := nc + 1;
    if coalesce(old_, 0) <> 0 and old_ <> x.amt then perform public._w1a_audit('open_party_json_override', 'customers', x.pid::text, jsonb_build_object('typed', old_, 'posted', x.amt)); end if;
  end loop;
  for x in select (e ->> 'supplier_id')::uuid pid, round(sum((e ->> 'amount')::numeric), 2) amt from jsonb_array_elements(coalesce(p_json -> 'supplier_dues', '[]'::jsonb)) e group by 1 loop
    select opening_balance into old_ from public.suppliers where id = x.pid;
    update public.suppliers set opening_balance = nullif(x.amt, 0), opening_date = coalesce(st, opening_date) where id = x.pid;
    ns := ns + 1;
    if coalesce(old_, 0) <> 0 and old_ <> x.amt then perform public._w1a_audit('open_party_json_override', 'suppliers', x.pid::text, jsonb_build_object('typed', old_, 'posted', x.amt)); end if;
  end loop;
  perform set_config('bos88.api', '', true);
  if nc + ns > 0 then perform public._w1a_audit('open_party_linked', 'opening_batches', null, jsonb_build_object('customers', nc, 'suppliers', ns)); end if;
end $$;

-- an opening batch posted BEFORE this phase: fill the sub-ledger fields from its journal lines (dry run first; a party that already has a different figure is reported, never overwritten)
create or replace function public.w1a_open_from_journal(p_dry boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
declare e record; ar bigint; ap bigint; x record; rows_ jsonb := '[]'::jsonb; n_fill int := 0; n_same int := 0; n_conf int := 0; stt text;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  select o.id, o.entry_date into e from public.journal_entries o
   where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id) order by o.id limit 1;
  if not found then raise exception 'no_opening_posted'; end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  if not p_dry then perform set_config('bos88.api', '1', true); end if;
  for x in
    select 'customer' kind, l.party_id::uuid pid, c.name, c.opening_balance cur, round(sum(l.debit - l.credit), 2) amt
      from public.journal_lines l join public.customers c on c.id::text = l.party_id where l.entry_id = e.id and l.account_id = ar and l.party_type = 'customer' group by l.party_id, c.name, c.opening_balance
    union all
    select 'supplier', l.party_id::uuid, c.name, c.opening_balance, round(sum(l.credit - l.debit), 2)
      from public.journal_lines l join public.suppliers c on c.id::text = l.party_id where l.entry_id = e.id and l.account_id = ap and l.party_type = 'supplier' group by l.party_id, c.name, c.opening_balance
  loop
    continue when x.amt = 0;
    if coalesce(x.cur, 0) = x.amt then stt := 'same'; n_same := n_same + 1;
    elsif coalesce(x.cur, 0) = 0 and not (x.kind = 'customer' and x.amt < 0) then
      stt := 'fill'; n_fill := n_fill + 1;
      if not p_dry then
        if x.kind = 'customer' then update public.customers set opening_balance = x.amt, opening_date = coalesce(opening_date, e.entry_date) where id = x.pid;
        else update public.suppliers set opening_balance = x.amt, opening_date = coalesce(opening_date, e.entry_date) where id = x.pid; end if;
      end if;
    else stt := 'conflict'; n_conf := n_conf + 1; end if;
    rows_ := rows_ || jsonb_build_object('kind', x.kind, 'party_id', x.pid, 'name', x.name, 'typed', x.cur, 'journal', x.amt, 'status', stt);
  end loop;
  if not p_dry then
    perform set_config('bos88.api', '', true);
    if n_fill > 0 then perform public._w1a_audit('open_party_from_journal', 'journal_entries', e.id::text, jsonb_build_object('filled', n_fill, 'same', n_same, 'conflicts', n_conf)); end if;
  end if;
  return jsonb_build_object('dry', p_dry, 'entry_id', e.id, 'rows', rows_, 'filled', n_fill, 'same', n_same, 'conflicts', n_conf);
end $$;

-- ============================================================================
-- CHANGE AFTER THE OPENING: an adjustment with a reason (balanced journal, audit line, Exceptions row)
-- ============================================================================
-- who may decide a request: never the maker, except the owner for his own request while the owner approval setting lets him decide his own entries (self, logged, off).
-- In named mode the named approvers (role or people) decide the owner's request. No role or person is written into this function.
create or replace function public._w1a_may_decide(p_maker uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare owner_maker boolean; rl text; me uuid := auth.uid();
begin
  if me is null or not public._w1a_mgr() then return false; end if;
  owner_maker := exists (select 1 from public.user_roles where user_id = p_maker and role_code = 'owner');
  if owner_maker and public._owner_mode() = 'named' then
    rl := public.rule_txt('owner_approver_role');
    return me <> p_maker and ((rl is not null and exists (select 1 from public.user_roles where user_id = me and role_code = rl)) or me = any (public._owner_approver_users()));
  end if;
  if me = p_maker then return owner_maker; end if;
  return true;
end $$;

create or replace function public._w1a_adj_apply(p_id bigint, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.open_party_adjustments; st date := public._acct_start(); jid bigint; ln jsonb; r jsonb; amt numeric; memo text;
begin
  select * into a from public.open_party_adjustments where id = p_id for update;
  if not found or a.status <> 'pending' then raise exception 'not_pending'; end if;
  amt := abs(a.delta);
  memo := left('Opening ' || a.kind || ' balance adjustment: ' || coalesce(a.party_name, '') || ' - ' || a.reason, 190);
  if st is not null then
    if a.kind = 'customer' then
      ln := case when a.delta > 0
        then jsonb_build_array(jsonb_build_object('a', 'receivable', 'debit', amt, 'party_type', 'customer', 'party_id', a.party_id::text, 'memo', memo), jsonb_build_object('a', 'retained', 'credit', amt, 'memo', memo))
        else jsonb_build_array(jsonb_build_object('a', 'retained', 'debit', amt, 'memo', memo), jsonb_build_object('a', 'receivable', 'credit', amt, 'party_type', 'customer', 'party_id', a.party_id::text, 'memo', memo)) end;
    else
      ln := case when a.delta > 0
        then jsonb_build_array(jsonb_build_object('a', 'retained', 'debit', amt, 'memo', memo), jsonb_build_object('a', 'payable', 'credit', amt, 'party_type', 'supplier', 'party_id', a.party_id::text, 'memo', memo))
        else jsonb_build_array(jsonb_build_object('a', 'payable', 'debit', amt, 'party_type', 'supplier', 'party_id', a.party_id::text, 'memo', memo), jsonb_build_object('a', 'retained', 'credit', amt, 'memo', memo)) end;
    end if;
    r := public.acct_journal_post(greatest(public._acct_today(), st), null, memo, ln, null, null, false);
    jid := (r ->> 'id')::bigint;
  end if;
  perform set_config('bos88.api', '1', true);
  if a.kind = 'customer' then update public.customers set opening_balance = nullif(a.new_amount, 0), opening_date = coalesce(opening_date, st) where id = a.party_id;
  else update public.suppliers set opening_balance = nullif(a.new_amount, 0), opening_date = coalesce(opening_date, st) where id = a.party_id; end if;
  perform set_config('bos88.api', '', true);
  update public.open_party_adjustments set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(coalesce(p_note, '')), 300), journal_entry_id = jid where id = p_id;
  perform public._w1a_audit('open_party_adjust', case a.kind when 'customer' then 'customers' else 'suppliers' end, a.party_id::text,
    jsonb_build_object('adjustment', p_id, 'name', a.party_name, 'old', a.old_amount, 'new', a.new_amount, 'delta', a.delta, 'reason', a.reason, 'journal_entry', jid, 'requested_by', a.requested_by));
  perform public._w1a_exc('opening_adjusted', 'yellow', abs(a.delta),
    'Opening ' || a.kind || ' balance of ' || coalesce(a.party_name, '') || ' changed from ' || a.old_amount::text || ' to ' || a.new_amount::text || '. Reason: ' || a.reason,
    'Opening ' || a.kind || ' balance of ' || coalesce(a.party_name, '') || ' changed from ' || a.old_amount::text || ' to ' || a.new_amount::text || '. Reason: ' || a.reason);
  return jsonb_build_object('id', p_id, 'status', 'approved', 'journal_entry_id', jid, 'delta', a.delta);
end $$;

create or replace function public.w1a_open_adjust(p_kind text, p_party uuid, p_new numeric, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ numeric; nm text; d numeric; nid bigint; ex public.open_party_adjustments; md text := coalesce(public.rule_txt('open_parties_adjust_mode'), 'direct'); newv numeric;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_new is null or p_new = 'NaN'::numeric or abs(p_new) > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_kind = 'customer' and p_new < 0 then raise exception 'negative_not_allowed'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.open_party_adjustments where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', ex.id, 'status', ex.status); end if;
  end if;
  if p_kind = 'customer' then select coalesce(opening_balance, 0), name into old_, nm from public.customers where id = p_party for update;
  else select coalesce(opening_balance, 0), name into old_, nm from public.suppliers where id = p_party for update; end if;
  if not found then raise exception 'unknown_party'; end if;
  newv := round(p_new, 2);
  d := newv - old_;
  if d = 0 then raise exception 'no_change'; end if;
  if exists (select 1 from public.open_party_adjustments where kind = p_kind and party_id = p_party and status = 'pending') then raise exception 'adjust_pending_exists'; end if;
  insert into public.open_party_adjustments (client_id, kind, party_id, party_name, old_amount, new_amount, delta, reason, mode, requested_by)
    values (p_client, p_kind, p_party, nm, old_, newv, d, left(btrim(p_reason), 300), md, auth.uid()) returning id into nid;
  if md = 'direct' then return public._w1a_adj_apply(nid, 'direct') || jsonb_build_object('mode', 'direct'); end if;
  perform public._w1a_audit('open_party_adjust_request', case p_kind when 'customer' then 'customers' else 'suppliers' end, p_party::text,
    jsonb_build_object('adjustment', nid, 'old', old_, 'new', newv, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', nid, 'status', 'pending', 'mode', 'approval');
end $$;

create or replace function public.w1a_open_adjust_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.open_party_adjustments;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.open_party_adjustments where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.status <> 'pending' then raise exception 'not_pending'; end if;
  if not public._w1a_may_decide(a.requested_by) then
    if a.requested_by = auth.uid() then raise exception 'maker_cannot_decide'; end if;
    raise exception 'named_approver_only';
  end if;
  if p_approve is null then raise exception 'bad_value'; end if;
  if not p_approve then
    if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
    update public.open_party_adjustments set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
    perform public._w1a_audit('open_party_adjust_reject', case a.kind when 'customer' then 'customers' else 'suppliers' end, a.party_id::text, jsonb_build_object('adjustment', p_id, 'note', left(btrim(p_note), 300)));
    return jsonb_build_object('id', p_id, 'status', 'rejected');
  end if;
  return public._w1a_adj_apply(p_id, p_note);
end $$;

create or replace function public.w1a_open_adjust_list(p_status text default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select a.id, a.kind, a.party_id, a.party_name, a.old_amount, a.new_amount, a.delta, a.reason, a.mode, a.status, a.requested_by, a.requested_at, a.decided_by, a.decided_at, a.decision_note, a.journal_entry_id,
             (a.status = 'pending' and public._w1a_may_decide(a.requested_by)) as can_decide
        from public.open_party_adjustments a where p_status is null or a.status = p_status order by a.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ============================================================================
-- THE GATE: per party, the sub-ledger equals the general ledger (wraps acct_reconcile, names the cause)
-- ============================================================================
create or replace function public.w1a_party_gate(p_kind text default 'all') returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; cust jsonb := '[]'::jsonb; sup jsonb := '[]'::jsonb; ar bigint; ap bigint; link boolean := public.rule_on('open_parties_link');
begin
  if not (public._acct_view() and public._acct_all()) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('all', 'customer', 'supplier') then raise exception 'bad_kind'; end if;
  if public._acct_start() is null then return jsonb_build_object('status', 'data_needed', 'why', 'accounting_start_date'); end if;
  r := public.acct_reconcile(p_kind);
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  select coalesce(jsonb_agg(z.row_ order by abs((z.row_ ->> 'unexplained')::numeric) desc), '[]'::jsonb) into cust from (
    select x || jsonb_build_object('typed_opening', coalesce(c.opening_balance, 0), 'journal_opening', jo.v,
      'cause', case when abs((x ->> 'unexplained')::numeric) <= 0.005 then null
                    when jo.v > 0 and coalesce(c.opening_balance, 0) = 0 then 'opening_in_books_not_in_subledger'
                    when coalesce(c.opening_balance, 0) > 0 and jo.v = 0 then 'opening_in_subledger_not_in_books'
                    when coalesce(c.opening_balance, 0) <> jo.v then 'opening_amounts_differ'
                    else 'transactions_differ' end) row_
      from jsonb_array_elements(coalesce(r -> 'customers', '[]'::jsonb)) x
      left join public.customers c on c.id::text = x ->> 'party_id'
      left join lateral (select coalesce(sum(l.debit - l.credit), 0) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                          where l.account_id = ar and l.party_type = 'customer' and l.party_id = x ->> 'party_id' and (e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening'))) jo on true) z;
  select coalesce(jsonb_agg(z.row_ order by abs((z.row_ ->> 'unexplained')::numeric) desc), '[]'::jsonb) into sup from (
    select x || jsonb_build_object('typed_opening', coalesce(c.opening_balance, 0), 'journal_opening', jo.v,
      'cause', case when abs((x ->> 'unexplained')::numeric) <= 0.005 then null
                    when jo.v <> 0 and coalesce(c.opening_balance, 0) = 0 then 'opening_in_books_not_in_subledger'
                    when coalesce(c.opening_balance, 0) <> 0 and jo.v = 0 then 'opening_in_subledger_not_in_books'
                    when coalesce(c.opening_balance, 0) <> jo.v then 'opening_amounts_differ'
                    else 'transactions_differ' end) row_
      from jsonb_array_elements(coalesce(r -> 'suppliers', '[]'::jsonb)) x
      left join public.suppliers c on c.id::text = x ->> 'party_id'
      left join lateral (select coalesce(sum(l.credit - l.debit), 0) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                          where l.account_id = ap and l.party_type = 'supplier' and l.party_id = x ->> 'party_id' and (e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening'))) jo on true) z;
  return jsonb_build_object('status', case when jsonb_array_length(cust) + jsonb_array_length(sup) = 0 then 'green' else 'red' end, 'link', link, 'start', r -> 'start',
    'customers', cust, 'suppliers', sup, 'customers_off', jsonb_array_length(cust), 'suppliers_off', jsonb_array_length(sup), 'unattributed_receivable', coalesce(r -> 'unattributed_receivable', '0'::jsonb));
end $$;

-- ============================================================================
-- GRANTS: the API for signed-in users (each function checks the permission itself); internals closed
-- ============================================================================
revoke all on function public._w1a_patch(regprocedure, text[], text), public._p88_present(), public._w1a_mgr(), public._w1a_batch_exists(), public._w1a_frozen(), public._w1a_cust_open(uuid), public._w1a_cust_open_date(uuid),
  public._w1a_cust_open_at(uuid), public._w1a_audit(text, text, text, jsonb), public._w1a_exc(text, text, numeric, text, text), public._w1a_open_guard(), public._w1a_opening_apply(jsonb),
  public._w1a_may_decide(uuid), public._w1a_adj_apply(bigint, text) from public, anon, authenticated;
revoke all on function public.w1a_open_state(), public.w1a_open_list(text, text, text, int, int), public.w1a_open_set(text, uuid, numeric, date, text), public.w1a_open_import(text, jsonb, boolean, boolean),
  public.w1a_open_json(), public.w1a_open_precheck(jsonb), public.w1a_open_from_journal(boolean), public.w1a_open_adjust(text, uuid, numeric, text, uuid),
  public.w1a_open_adjust_decide(bigint, boolean, text), public.w1a_open_adjust_list(text, int), public.w1a_party_gate(text) from public, anon;
grant execute on function public.w1a_open_state(), public.w1a_open_list(text, text, text, int, int), public.w1a_open_set(text, uuid, numeric, date, text), public.w1a_open_import(text, jsonb, boolean, boolean),
  public.w1a_open_json(), public.w1a_open_precheck(jsonb), public.w1a_open_from_journal(boolean), public.w1a_open_adjust(text, uuid, numeric, text, uuid),
  public.w1a_open_adjust_decide(bigint, boolean, text), public.w1a_open_adjust_list(text, int), public.w1a_party_gate(text) to authenticated;

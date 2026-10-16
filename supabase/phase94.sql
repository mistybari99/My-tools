-- Phase 94 (bos94) - CASH AND PAYMENT CONTROLS (package W1-E, item U-07). Paste AFTER phase87 (phases 88-93 of the other packages are independent). Paste-twice safe.
-- Earlier phase files are not edited. No shared function is replaced by this file: every control is a new trigger or a new function with the prefix _w1e_ / w1e_.
--
-- EVERY policy choice is a SETTING (table rules, module books, shown on the Rules page and on #/moneycontrols), English label, hint, owner editable at any time,
-- every change is written to audit_log by the existing audit_rules trigger. Every default keeps TODAY'S behaviour, so pasting this file changes nothing:
--   owner_money_entry_mode     open (default) | approval | owner     who may record owner_draw / owner_topup (cash moves)
--   bank_slip_required         off (default)                          bank_deposit / bank_withdraw need a slip number in the reference
--   bank_move_large_over       blank = off                            yellow exception for a bank move above this amount
--   bank_move_backdate_days    blank = off                            yellow exception for a bank move dated more than N days back
--   supplier_pay_dup_mode      off (default) | flag | block           same supplier, same total, again inside the window
--   supplier_pay_dup_hours     blank = same calendar day              the window
--   supplier_pay_over          blank = off                            a non-owner supplier payment above this amount waits for the approver
--   supplier_dup_mode          off (default) | warn | block           a second supplier with the same name, mobile or TIN
--   employee_pay_dup_mode      off (default) | warn | block           two employees on one bank account or wallet number
--   employee_pay_change_flag   off (default)                          red exception when a pay account is changed
-- APPROVER: a request is decided by the approver the owner chose under phase87 (owner_approval_mode_set2: any role, any named people), or - when a request carries its own
--   approver (w1e_request_approver_set) - by that person or role. Nothing is hard-coded. The maker NEVER decides his own request (also not the owner). The owner may grant one
--   one-off 'approver' exception (phase87 money_exception_grant) with a reason; it is logged in audit_log and in the Exceptions list.
-- EXCEPTIONS: every blocking control has a one-off override through the phase87 grant (rule 'override', event w1e_*), reason required, audit_log line, Exceptions row.
--   Events: w1e_owner_money, w1e_bank_slip, w1e_dup_payment, w1e_pay_over, w1e_vendor_dup, w1e_pay_account (phase95 adds w1e_mapping, w1e_journal_*).
-- HOOKS (integrator, see docs/integration/W1-E.md): pay_supplier (duplicate guard and over-threshold wait need the exact amount of the whole call) and, for display only,
--   cash_move_add (returns pending). Without the hooks the cash move controls, vendor and employee controls still work; the supplier payment controls simply do nothing.
-- Nothing is deleted. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_patch(regprocedure,text[])') is null
     or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regprocedure('public._owner_approver_users()') is null then
    raise exception 'phase94 needs phase87 (and 80-86) first';
  end if;
end $g$;

create or replace function public._p94_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- Exceptions list: more kinds (additive: keeps every kind another package added) ----------
create or replace function public._w1e_add_exc_kinds(p_kinds text[]) returns void language plpgsql set search_path = public as $$
declare con text; def text; cur text[]; allk text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase94: money_exceptions kind check not found'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  allk := cur;
  foreach k in array p_kinds loop if not (k = any (allk)) then allk := allk || k; end if; end loop;
  if allk = cur then return; end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(allk) x));
end $$;
select public._w1e_add_exc_kinds(array['w1e_bank_move_flag', 'w1e_duplicate_payment', 'w1e_pay_over_request', 'w1e_vendor_duplicate', 'w1e_pay_account_duplicate',
  'w1e_pay_account_changed', 'w1e_owner_money_request', 'w1e_journal_request']);

-- ---------- settings (rules). Label and hint in English only (the owner will translate later). ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('owner_money_entry_mode', 'choice', '"open"'::jsonb, null::text, '["open","approval","owner"]'::jsonb, null::numeric, null::numeric,
   'Who may record an owner draw or an owner top-up',
   'open = anyone who has the cash move right (today). approval = an entry by a person who is not the owner waits for the approver chosen under "Approval of the owner''s own entries". owner = only the owner. Recommended: approval or owner.', 740),
 ('bank_slip_required', 'switch', 'false'::jsonb, null, null, null, null,
   'Bank slip number required on a bank deposit and a bank withdraw',
   'When ON, the Reference field of a bank deposit or bank withdraw must hold the slip number. Off = today. Recommended: ON.', 741),
 ('bank_move_large_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'Flag a bank deposit or withdraw above this amount',
   'A yellow line in the Exceptions list. Blank = off. The entry is still saved.', 742),
 ('bank_move_backdate_days', 'number', null, 'days', null, 0, 3650,
   'Flag a bank deposit or withdraw dated more than this many days back',
   'A yellow line in the Exceptions list. Blank = off. The entry is still saved.', 743),
 ('supplier_pay_dup_mode', 'choice', '"off"'::jsonb, null, '["off","flag","block"]'::jsonb, null, null,
   'Same supplier payment entered twice',
   'off = today. flag = save it and add a yellow line to the Exceptions list. block = refuse it unless the owner allows one exception. A payment is a repeat when the supplier and the total are the same inside the window below.', 744),
 ('supplier_pay_dup_hours', 'number', null, 'hours', null, 1, 720,
   'Window for the repeat-payment check',
   'Blank = the same calendar day (Asia/Dhaka). Only used when the repeat-payment check is not off.', 745),
 ('supplier_pay_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'A supplier payment above this amount waits for the approver',
   'Blank = off. A payment entered by someone who is not the owner and above this total is held until the approver decides. The owner is not held.', 746),
 ('supplier_dup_mode', 'choice', '"off"'::jsonb, null, '["off","warn","block"]'::jsonb, null, null,
   'Second supplier with the same name, mobile or TIN',
   'off = today. warn = save it and add a yellow line to the Exceptions list. block = refuse it unless the owner allows one exception.', 747),
 ('employee_pay_dup_mode', 'choice', '"off"'::jsonb, null, '["off","warn","block"]'::jsonb, null, null,
   'Two employees on one pay account (bank account or wallet number)',
   'off = today. warn = save it and add a red line to the Exceptions list. block = refuse it unless the owner allows one exception. Employees who have left are not compared.', 748),
 ('employee_pay_change_flag', 'switch', 'false'::jsonb, null, null, null, null,
   'Red line in the Exceptions list when an employee pay account is changed',
   'Off = today. The line shows only the last 4 characters of the old and new account.', 749)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- requests: one waiting list for the three controls that need an approver (owner money, supplier payment over the limit, journal on a control account) ----------
create table if not exists public.w1e_requests (
  id bigserial primary key,
  kind text not null check (kind in ('owner_money', 'supplier_pay', 'journal_control')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  location_id int, amount numeric, ref_date date,
  summary text not null check (length(summary) <= 300),
  payload jsonb not null,
  client_id uuid unique,
  approver_user uuid, approver_role text, approver_set_by uuid, approver_set_at timestamptz, approver_reason text,
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text, applied_ref text
);
create index if not exists w1e_requests_status on public.w1e_requests (status, id);
drop trigger if exists w1e_requests_nodel on public.w1e_requests;
create trigger w1e_requests_nodel before delete on public.w1e_requests for each row execute function public.no_hard_delete();
drop trigger if exists audit_w1e_requests on public.w1e_requests;
create trigger audit_w1e_requests after insert or update on public.w1e_requests for each row execute function public.log_change('id');
alter table public.w1e_requests enable row level security;
revoke all on public.w1e_requests from public, anon, authenticated;
do $s$ begin
  if exists (select 1 from pg_class where relname = 'w1e_requests_id_seq' and relnamespace = 'public'::regnamespace) then
    execute 'revoke all on sequence public.w1e_requests_id_seq from public, anon, authenticated';
  end if;
end $s$;

-- ---------- helpers ----------
create or replace function public._w1e_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._w1e_staff() returns text language sql stable security definer set search_path = public as $$ select staff_id from public.profiles where id = auth.uid() $$;
create or replace function public._w1e_choice(p_key text, p_default text) returns text language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt(p_key), p_default) $$;
create or replace function public._w1e_nalnum(t text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(coalesce(t, ''), '[^0-9a-zA-Z]', '', 'g')), '') $$;
create or replace function public._w1e_nname(t text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')), '') $$;
-- a mobile number compared on its last 10 digits (+8801712345678 equals 01712345678); shorter than 10 digits is not compared
create or replace function public._w1e_nmobile(t text) returns text language sql immutable as $$
  select case when length(regexp_replace(coalesce(t, ''), '\D', '', 'g')) >= 10 then right(regexp_replace(t, '\D', '', 'g'), 10) end $$;
create or replace function public._w1e_mask(t text) returns text language sql immutable as $$
  select case when t is null or btrim(t) = '' then '-' else '****' || right(btrim(t), 4) end $$;

create or replace function public._w1e_exc(p_kind text, p_ev text, p_amount numeric, p_src_table text, p_src_id text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user) values (p_kind, p_ev, p_amount, p_src_table, left(p_src_id, 120), left(p_reason, 300), auth.uid());
end $$;
create or replace function public._w1e_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), public._w1e_staff(), p_action, p_table, p_id, p_detail);
end $$;

-- who may decide a request: its own approver if the owner set one, else the approver chosen under phase87 (named role / people), else an owner. Never the maker (checked by the caller).
create or replace function public._w1e_user_is_approver(p_uid uuid, r public.w1e_requests) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare rl text;
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid and status = 'active') then return false; end if;
  if r.approver_user is not null or r.approver_role is not null then
    return p_uid = r.approver_user or (r.approver_role is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = r.approver_role));
  end if;
  if public._owner_mode() = 'named' then
    rl := public.rule_txt('owner_approver_role');
    return (rl is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = rl)) or p_uid = any (public._owner_approver_users());
  end if;
  return exists (select 1 from public.user_roles where user_id = p_uid and role_code = 'owner');
end $$;

-- ---------- control 1: cash moves (owner money, bank slip, large and back-dated bank moves). A BEFORE INSERT trigger, so a hidden button is also a refused request. ----------
create or replace function public._w1e_cash_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare mode text; slip text; lim numeric; dys numeric; rid bigint;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if new.kind in ('bank_deposit', 'bank_withdraw') then
    if public.rule_on('bank_slip_required') then
      select u.rest into slip from public._m_untag(new.ref) u;
      if nullif(btrim(coalesce(slip, '')), '') is null
         and not public._m_grant_take('override', 'w1e_bank_slip', new.client_id, null, new.amount, new.move_date, 'cash_moves') then raise exception 'bank_slip_required'; end if;
    end if;
    lim := public.rule_num('bank_move_large_over');
    if lim is not null and new.amount > lim then
      perform public._w1e_exc('w1e_bank_move_flag', 'w1e_bank_large', new.amount, 'cash_moves', new.id::text, new.kind || ' ' || new.amount::text || ' is above the limit ' || lim::text);
    end if;
    dys := public.rule_num('bank_move_backdate_days');
    if dys is not null and new.move_date < public._w1e_today() - dys::int then
      perform public._w1e_exc('w1e_bank_move_flag', 'w1e_bank_backdated', new.amount, 'cash_moves', new.id::text, new.kind || ' dated ' || new.move_date::text || ' is more than ' || dys::text || ' days back');
    end if;
  elsif new.kind in ('owner_topup', 'owner_draw') and not public.is_owner() then
    mode := public._w1e_choice('owner_money_entry_mode', 'open');
    if mode = 'open' then
      perform public._w1e_audit('w1e_owner_money_open', 'cash_moves', new.id::text, jsonb_build_object('kind', new.kind, 'amount', new.amount, 'date', new.move_date, 'mode', 'open'));
    elsif mode = 'owner' then
      if not public._m_grant_take('override', 'w1e_owner_money', new.client_id, null, new.amount, new.move_date, 'cash_moves') then raise exception 'owner_money_owner_only'; end if;
    else                                                                      -- approval: the row is NOT written; it waits in w1e_requests with the same id and client id
      insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
        values ('owner_money', new.location_id, new.amount, new.move_date, left(new.kind || ' ' || new.amount::text || ' on ' || new.move_date::text || ' (' || coalesce(new.mode, '-') || ')', 300),
                to_jsonb(new), new.client_id, coalesce(new.created_by, auth.uid()), coalesce(new.created_staff, public._w1e_staff()))
        on conflict (client_id) do nothing returning id into rid;
      if rid is not null then
        perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'owner_money', 'amount', new.amount, 'cash_move', new.id));
        perform public._w1e_exc('w1e_owner_money_request', 'w1e_owner_money', new.amount, 'w1e_requests', rid::text, new.kind || ' entered by a person who is not the owner; waits for the approver');
      end if;
      return null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_cash_bi on public.cash_moves;
create trigger a94_w1e_cash_bi before insert on public.cash_moves for each row execute function public._w1e_cash_bi();   -- a94 sorts before aa87: the request is held before any money-account check

create or replace function public._w1e_cash_pending(p_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('pending', true, 'request_id', r.id) from public.w1e_requests r where r.kind = 'owner_money' and r.status = 'pending' and r.payload ->> 'id' = p_id::text limit 1), '{}'::jsonb) $$;

-- ---------- control 2: supplier payment (called from the pay_supplier hook with the exact total of the whole call) ----------
create or replace function public._w1e_pay_gate(p_supplier uuid, p_loc int, p_payments jsonb, p_client uuid, p_note text, p_tot numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dm text := public._w1e_choice('supplier_pay_dup_mode', 'off'); hrs numeric := public.rule_num('supplier_pay_dup_hours'); ov numeric := public.rule_num('supplier_pay_over');
  since timestamptz; dup boolean := false; rid bigint; ex public.w1e_requests; bal numeric;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return null; end if;
  if p_client is not null then
    select * into ex from public.w1e_requests where client_id = p_client;
    if found then return jsonb_build_object('pending', true, 'request_id', ex.id, 'paid', 0, 'balance', public._sup_balance(p_supplier), 'dup', true); end if;
  end if;
  if dm <> 'off' then
    since := case when hrs is null then (date_trunc('day', now() at time zone 'Asia/Dhaka')) at time zone 'Asia/Dhaka' else now() - make_interval(secs => (hrs * 3600)::double precision) end;
    select exists (select 1 from (select sum(amount) a, max(paid_at) t from public.supplier_payments
                                   where supplier_id = p_supplier and not voided and bill_id is null and client_id is distinct from p_client
                                   group by coalesce(client_id::text, id::text)) g where g.a = p_tot and g.t >= since)
        or exists (select 1 from public.w1e_requests q where q.kind = 'supplier_pay' and q.status = 'pending' and q.payload ->> 'supplier' = p_supplier::text and (q.payload ->> 'total')::numeric = p_tot and q.requested_at >= since)
      into dup;
    if dup then
      if dm = 'block' then
        if not public._m_grant_take('override', 'w1e_dup_payment', p_client, null, p_tot, public._w1e_today(), 'supplier:' || p_supplier::text) then raise exception 'duplicate_payment'; end if;
      else
        perform public._w1e_exc('w1e_duplicate_payment', 'w1e_dup_payment', p_tot, 'suppliers', p_supplier::text, 'a payment of the same total to the same supplier was already entered inside the window');
      end if;
    end if;
  end if;
  if ov is not null and p_tot > ov and not public.is_owner() then
    if public._m_grant_take('override', 'w1e_pay_over', p_client, null, p_tot, public._w1e_today(), 'supplier:' || p_supplier::text) then return null; end if;
    insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
      values ('supplier_pay', p_loc, p_tot, public._w1e_today(),
              left('Supplier payment ' || p_tot::text || ' to ' || coalesce((select name from public.suppliers where id = p_supplier), '-') || ' (limit ' || ov::text || ')', 300),
              jsonb_build_object('supplier', p_supplier, 'loc', p_loc, 'payments', p_payments, 'client', p_client, 'note', p_note, 'total', p_tot), p_client, auth.uid(), public._w1e_staff())
      returning id into rid;
    perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'supplier_pay', 'amount', p_tot, 'supplier', p_supplier, 'limit', ov));
    perform public._w1e_exc('w1e_pay_over_request', 'w1e_pay_over', p_tot, 'w1e_requests', rid::text, 'supplier payment above the limit ' || ov::text || ' waits for the approver');
    bal := public._sup_balance(p_supplier);
    return jsonb_build_object('pending', true, 'request_id', rid, 'paid', 0, 'balance', bal);
  end if;
  return null;
end $$;

-- ---------- control 3: second supplier with the same name, mobile or TIN ----------
create or replace function public._w1e_vendor_match(p_name text, p_mobile text, p_tin text, p_exclude uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'by', case when public._w1e_nname(s.name) = public._w1e_nname(p_name) then 'name'
                                                                                    when public._w1e_nmobile(s.mobile) is not null and public._w1e_nmobile(s.mobile) = public._w1e_nmobile(p_mobile) then 'mobile' else 'tin' end)), '[]'::jsonb)
    from public.suppliers s
   where s.active and (p_exclude is null or s.id <> p_exclude)
     and ((public._w1e_nname(p_name) is not null and public._w1e_nname(s.name) = public._w1e_nname(p_name))
       or (public._w1e_nmobile(p_mobile) is not null and public._w1e_nmobile(s.mobile) = public._w1e_nmobile(p_mobile))
       or (public._w1e_nalnum(p_tin) is not null and public._w1e_nalnum(s.tin) = public._w1e_nalnum(p_tin))) $$;

create or replace function public._w1e_supplier_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare m text := public._w1e_choice('supplier_dup_mode', 'off'); hit jsonb;
begin
  if m = 'off' or auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.name is not distinct from old.name and new.mobile is not distinct from old.mobile and new.tin is not distinct from old.tin and new.active is not distinct from old.active then return new; end if;
  if not new.active then return new; end if;
  hit := public._w1e_vendor_match(new.name, new.mobile, new.tin, new.id);
  if jsonb_array_length(hit) = 0 then return new; end if;
  if m = 'block' then
    if not public._m_grant_take('override', 'w1e_vendor_dup', null, null, null, public._w1e_today(), 'suppliers:' || new.id::text) then raise exception 'vendor_duplicate' using detail = hit::text; end if;
  else
    perform public._w1e_exc('w1e_vendor_duplicate', 'w1e_vendor_dup', null, 'suppliers', new.id::text, 'same ' || (hit -> 0 ->> 'by') || ' as supplier "' || left(hit -> 0 ->> 'name', 80) || '"');
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_supplier_bi on public.suppliers;
create trigger a94_w1e_supplier_bi before insert or update on public.suppliers for each row execute function public._w1e_supplier_bi();

-- ---------- control 4: one pay account per employee ----------
create or replace function public._w1e_pay_match(p_bank text, p_wallet text, p_exclude uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'by', case when public._w1e_nalnum(p_bank) is not null and public._w1e_nalnum(e.bank_account) = public._w1e_nalnum(p_bank) then 'bank_account' else 'mobile_wallet' end)), '[]'::jsonb)
    from public.employees e
   where (p_exclude is null or e.id <> p_exclude) and e.status not in ('resigned', 'terminated', 'retired', 'discarded')
     and ((public._w1e_nalnum(p_bank) is not null and public._w1e_nalnum(e.bank_account) = public._w1e_nalnum(p_bank))
       or (public._w1e_nmobile(p_wallet) is not null and public._w1e_nmobile(e.mobile_wallet) = public._w1e_nmobile(p_wallet))) $$;

create or replace function public._w1e_employee_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare m text := public._w1e_choice('employee_pay_dup_mode', 'off'); hit jsonb; chg boolean;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.bank_account is not distinct from old.bank_account and new.mobile_wallet is not distinct from old.mobile_wallet then return new; end if;
  if tg_op = 'UPDATE' and public.rule_on('employee_pay_change_flag') then
    chg := (nullif(btrim(coalesce(old.bank_account, '')), '') is not null and new.bank_account is distinct from old.bank_account)
        or (nullif(btrim(coalesce(old.mobile_wallet, '')), '') is not null and new.mobile_wallet is distinct from old.mobile_wallet);
    if chg then
      perform public._w1e_exc('w1e_pay_account_changed', 'w1e_pay_account', null, 'employees', new.id::text,
        'pay account changed: bank ' || public._w1e_mask(old.bank_account) || ' -> ' || public._w1e_mask(new.bank_account) || ', wallet ' || public._w1e_mask(old.mobile_wallet) || ' -> ' || public._w1e_mask(new.mobile_wallet));
    end if;
  end if;
  if m = 'off' then return new; end if;
  hit := public._w1e_pay_match(new.bank_account, new.mobile_wallet, new.id);
  if jsonb_array_length(hit) = 0 then return new; end if;
  if m = 'block' then
    if not public._m_grant_take('override', 'w1e_pay_account', null, null, null, public._w1e_today(), 'employees:' || new.id::text) then raise exception 'pay_account_duplicate'; end if;
  else
    perform public._w1e_exc('w1e_pay_account_duplicate', 'w1e_pay_account', null, 'employees', new.id::text, 'the same ' || (hit -> 0 ->> 'by') || ' is already used by employee ' || coalesce(hit -> 0 ->> 'employee_no', '-'));
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_employee_bi on public.employees;
create trigger a94_w1e_employee_bi before insert or update on public.employees for each row execute function public._w1e_employee_bi();

-- ---------- applying an approved request (one function per kind; phase95 adds journal_control) ----------
create or replace function public._w1e_apply_owner_money(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare d date := (r.payload ->> 'move_date')::date; cid uuid := (r.payload ->> 'id')::uuid;
begin
  perform public.lock_check(d);
  if exists (select 1 from public.cash_moves where id = cid) then raise exception 'request_already_applied'; end if;
  insert into public.cash_moves select * from jsonb_populate_record(null::public.cash_moves, r.payload);
  return 'cash_moves:' || cid::text;
end $$;

create or replace function public._w1e_apply_supplier_pay(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare p jsonb := r.payload; pay jsonb; sup uuid := (r.payload ->> 'supplier')::uuid; tot numeric := (r.payload ->> 'total')::numeric; bal numeric; n int := 0;
begin
  perform 1 from public.suppliers where id = sup for update;
  if not found then raise exception 'supplier_not_found'; end if;
  perform public.lock_check(public._w1e_today());
  bal := public._sup_balance(sup);
  if tot > bal then raise exception 'overpaid'; end if;
  for pay in select * from jsonb_array_elements(p -> 'payments') loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (sup, (p ->> 'loc')::int, null, pay ->> 'mode', left(nullif(pay ->> 'wallet', ''), 30), left(nullif(pay ->> 'ref', ''), 60), round((pay ->> 'amount')::numeric, 2),
              left(nullif(btrim(p ->> 'note'), ''), 200), r.requested_by, r.requested_staff, nullif(p ->> 'client', '')::uuid);
    n := n + 1;
  end loop;
  return 'supplier_payments:' || n::text || ' rows for ' || sup::text;
end $$;

create or replace function public._w1e_apply(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare out text; fname text := '_w1e_apply_' || r.kind;
begin
  if to_regprocedure('public.' || fname || '(public.w1e_requests)') is null then raise exception 'request_kind_unavailable'; end if;
  execute format('select public.%I($1)', fname) into out using r;
  return out;
end $$;

-- ---------- API: requests ----------
create or replace function public.w1e_requests_list(p_status text default 'pending', p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select q.id, q.kind, q.status, q.location_id, q.amount, q.ref_date, q.summary, q.requested_by, q.requested_staff, q.requested_at, q.decided_staff, q.decided_at, q.decision_note,
           q.approver_user, q.approver_role, q.approver_reason, q.applied_ref,
           (q.status = 'pending' and q.requested_by <> me and public._w1e_user_is_approver(me, q)) as can_decide,
           (q.status = 'pending' and (q.requested_by = me or public.is_owner())) as can_cancel,
           (q.requested_by = me) as mine
      from public.w1e_requests q
     where (p_status is null or q.status = p_status)
       and (public.is_owner() or q.requested_by = me or public._w1e_user_is_approver(me, q))
     order by q.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

create or replace function public.w1e_request_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests; ok boolean; ref text; sid text := public._w1e_staff();
begin
  if not public.is_active() or p_approve is null then raise exception 'not allowed'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if r.requested_by = auth.uid() then raise exception 'self_approval'; end if;
  ok := public._w1e_user_is_approver(auth.uid(), r);
  if not ok then
    if public._m_grant_take('approver', 'w1e_' || r.kind, null, null, r.amount, public._w1e_today(), 'w1e_requests:' || r.id::text) then ok := true; end if;
  end if;
  if not ok then raise exception 'approver_only'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  if p_approve then
    perform set_config('w1e.apply', '1', true);
    ref := public._w1e_apply(r);
    perform set_config('w1e.apply', '', true);
  end if;
  update public.w1e_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
         decision_note = left(btrim(p_note), 300), applied_ref = ref where id = p_id;
  perform public._w1e_audit('w1e_request_decide', 'w1e_requests', p_id::text, jsonb_build_object('kind', r.kind, 'approve', p_approve, 'note', left(p_note, 300), 'applied', ref, 'maker', r.requested_by));
  return jsonb_build_object('id', p_id, 'status', case when p_approve then 'approved' else 'rejected' end, 'applied', ref);
end $$;

create or replace function public.w1e_request_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.requested_by <> auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  update public.w1e_requests set status = 'cancelled', decided_by = auth.uid(), decided_staff = public._w1e_staff(), decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  perform public._w1e_audit('w1e_request_cancel', 'w1e_requests', p_id::text, jsonb_build_object('kind', r.kind, 'note', left(p_note, 300)));
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- the owner names the approver of ONE request (a person or a role); reason required; the maker is never the approver
create or replace function public.w1e_request_approver_set(p_id bigint, p_user uuid default null, p_role text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests; rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_user is null and rl is null then raise exception 'approver_required'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if p_user is not null then
    if p_user = r.requested_by then raise exception 'approver_is_maker'; end if;
    if not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  if rl is not null and not exists (select 1 from public.roles where code = rl and active) then raise exception 'bad_role'; end if;
  update public.w1e_requests set approver_user = p_user, approver_role = rl, approver_set_by = auth.uid(), approver_set_at = now(), approver_reason = left(btrim(p_reason), 300) where id = p_id;
  perform public._w1e_audit('w1e_request_approver_set', 'w1e_requests', p_id::text, jsonb_build_object('user', p_user, 'role', rl, 'reason', left(p_reason, 300)));
  return jsonb_build_object('id', p_id, 'approver_user', p_user, 'approver_role', rl);
end $$;

-- ---------- API: exceptions of this package, state, checks ----------
create or replace function public.w1e_exceptions_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select x.id, x.at, x.kind, x.event_type, x.amount, x.src_table, x.src_id, x.reason, x.status, x.resolve_note, x.resolved_at,
             case when x.kind in ('w1e_pay_account_duplicate', 'w1e_pay_account_changed') then 'red' else 'yellow' end as level
        from public.money_exceptions x
       where (x.kind like 'w1e\_%' or x.event_type like 'w1e\_%') and (p_status is null or x.status = p_status)
       order by x.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb),
    'grants', case when public.is_owner() then coalesce((select jsonb_agg(to_jsonb(g) order by g.id desc) from (
        select id, rule, event_type, for_user, client_id, reason, granted_at, expires_at, used_at, revoked from public.money_exception_grants where event_type like 'w1e\_%' or event_type is null order by id desc limit 100) g), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.w1e_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ks text[] := array['owner_money_entry_mode', 'bank_slip_required', 'bank_move_large_over', 'bank_move_backdate_days', 'supplier_pay_dup_mode', 'supplier_pay_dup_hours', 'supplier_pay_over',
  'supplier_dup_mode', 'employee_pay_dup_mode', 'employee_pay_change_flag', 'journal_loc_check', 'mapping_type_guard', 'journal_attach_over', 'journal_control_acct_mode', 'journal_control_prefixes'];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'settings', coalesce((select jsonb_object_agg(r.key, coalesce(r.value, r.default_value)) from public.rules r where r.key = any (ks)), '{}'::jsonb),
    'pending', (select count(*) from public.w1e_requests where status = 'pending'
                  and (public.is_owner() or requested_by = auth.uid() or public._w1e_user_is_approver(auth.uid(), w1e_requests))),
    'approver', jsonb_build_object('mode', public._owner_mode(), 'role', public.rule_txt('owner_approver_role'), 'users', to_jsonb(public._owner_approver_users())),
    'hooks', jsonb_build_object(
      'pay_supplier', position('w1e94' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure)) > 0,
      'cash_move_add', position('w1e94c' in pg_get_functiondef('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure)) > 0,
      'acct_journal_post', coalesce(position('w1e95' in pg_get_functiondef(to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'))) > 0, false)),
    'is_owner', public.is_owner());
end $$;

-- read only: who shares a vendor identity or a pay account right now (owner or accounts); account numbers are masked
create or replace function public.w1e_checks() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'vendors', coalesce((select jsonb_agg(to_jsonb(v)) from (
        select a.id as a_id, a.name as a_name, b.id as b_id, b.name as b_name,
               case when public._w1e_nname(a.name) = public._w1e_nname(b.name) then 'name' when public._w1e_nmobile(a.mobile) is not null and public._w1e_nmobile(a.mobile) = public._w1e_nmobile(b.mobile) then 'mobile' else 'tin' end as by
          from public.suppliers a join public.suppliers b on a.id < b.id and a.active and b.active
           and (public._w1e_nname(a.name) = public._w1e_nname(b.name)
             or (public._w1e_nmobile(a.mobile) is not null and public._w1e_nmobile(a.mobile) = public._w1e_nmobile(b.mobile))
             or (public._w1e_nalnum(a.tin) is not null and public._w1e_nalnum(a.tin) = public._w1e_nalnum(b.tin))) limit 200) v), '[]'::jsonb),
    'pay_accounts', coalesce((select jsonb_agg(to_jsonb(v)) from (
        select a.id as a_id, a.employee_no as a_no, b.id as b_id, b.employee_no as b_no,
               case when public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account) then 'bank_account' else 'mobile_wallet' end as by,
               public._w1e_mask(case when public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account) then a.bank_account else a.mobile_wallet end) as account
          from public.employees a join public.employees b on a.id < b.id and a.status not in ('resigned', 'terminated', 'retired', 'discarded') and b.status not in ('resigned', 'terminated', 'retired', 'discarded')
           and ((public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account))
             or (public._w1e_nmobile(a.mobile_wallet) is not null and public._w1e_nmobile(a.mobile_wallet) = public._w1e_nmobile(b.mobile_wallet))) limit 200) v), '[]'::jsonb));
end $$;

-- pre-checks for the screens (warn before saving)
create or replace function public.w1e_vendor_check(p_name text, p_mobile text default null, p_tin text default null, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public.has_grant('supplier_manage') or public.has_grant('purchase_entry')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('matches', public._w1e_vendor_match(p_name, p_mobile, p_tin, p_exclude), 'mode', public._w1e_choice('supplier_dup_mode', 'off'));
end $$;
create or replace function public.w1e_pay_account_check(p_bank text default null, p_wallet text default null, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public.has_grant('employee_manage')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('matches', public._w1e_pay_match(p_bank, p_wallet, p_exclude), 'mode', public._w1e_choice('employee_pay_dup_mode', 'off'));
end $$;

-- ---------- more separation-of-duty pairs (non blocking suggestions; shown on #/delegation through grant_separation_report) ----------
insert into public.grant_separation_pairs (code, entry_grant, approve_grant, label_bn, label_en) values
 ('cash_move_release', 'cash_move', 'release_decide', 'Cash move entry and release decision', 'Cash move entry and release decision'),
 ('supplier_pay_purchase', 'supplier_pay', 'purchase_entry', 'Supplier payment and purchase entry', 'Supplier payment and purchase entry'),
 ('payroll_employee', 'payroll_manage', 'employee_manage', 'Payroll and employee records', 'Payroll and employee records'),
 ('accounts_purchase', 'accounts_manage', 'purchase_entry', 'Accounts manage and purchase entry', 'Accounts manage and purchase entry'),
 ('supplier_pay_manage', 'supplier_manage', 'supplier_pay', 'Supplier records and supplier payment', 'Supplier records and supplier payment'),
 ('cash_move_accounts', 'cash_move', 'accounts_manage', 'Cash move entry and accounts manage', 'Cash move entry and accounts manage'),
 ('purchase_enter_void', 'purchase_entry', 'purchase_void', 'Purchase entry and purchase void', 'Purchase entry and purchase void')
on conflict (code) do nothing;

-- ---------- privileges: internals closed, API open to signed-in users (each function checks its own permission) ----------
revoke all on function public._p94_present(), public._w1e_add_exc_kinds(text[]), public._w1e_today(), public._w1e_staff(), public._w1e_choice(text, text), public._w1e_nalnum(text), public._w1e_nname(text),
  public._w1e_nmobile(text), public._w1e_mask(text), public._w1e_exc(text, text, numeric, text, text, text), public._w1e_audit(text, text, text, jsonb), public._w1e_user_is_approver(uuid, public.w1e_requests),
  public._w1e_cash_bi(), public._w1e_cash_pending(uuid), public._w1e_pay_gate(uuid, int, jsonb, uuid, text, numeric), public._w1e_vendor_match(text, text, text, uuid), public._w1e_supplier_bi(),
  public._w1e_pay_match(text, text, uuid), public._w1e_employee_bi(), public._w1e_apply_owner_money(public.w1e_requests), public._w1e_apply_supplier_pay(public.w1e_requests), public._w1e_apply(public.w1e_requests)
  from public, anon, authenticated;
revoke all on function public.w1e_requests_list(text, int), public.w1e_request_decide(bigint, boolean, text), public.w1e_request_cancel(bigint, text), public.w1e_request_approver_set(bigint, uuid, text, text),
  public.w1e_exceptions_list(text, int), public.w1e_state(), public.w1e_checks(), public.w1e_vendor_check(text, text, text, uuid), public.w1e_pay_account_check(text, text, uuid) from public, anon, authenticated;
grant execute on function public.w1e_requests_list(text, int), public.w1e_request_decide(bigint, boolean, text), public.w1e_request_cancel(bigint, text), public.w1e_request_approver_set(bigint, uuid, text, text),
  public.w1e_exceptions_list(text, int), public.w1e_state(), public.w1e_checks(), public.w1e_vendor_check(text, text, text, uuid), public.w1e_pay_account_check(text, text, uuid) to authenticated;

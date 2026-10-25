-- Phase 97 (bos97) - W1-F / U-10: CUSTOMER RECEIPT CHANNELS. Bank and cheque on collections and POS split payments, payment source (money account) on customer receipts, reference rules.
-- Paste after phase96 (which needs phase87). Paste-twice safe. Earlier phase files are not edited. collect_payment, record_sale2 and the other shared functions are NOT re-created here:
-- every change to a shared function is a HOOK written in docs/integration/W1-F.md (tests/sql/w1f_hooks97.sql is the exact text, proved on a scratch copy by phase97_test.sql).
--
-- WHAT THIS ADDS
--   * sale_payments.mode accepts 'bank' (and sales.pay_mode too). A cheque is a bank receipt with cheque_no (and cheque_date). New columns: money_account_id, cheque_no, cheque_date, ref_waiver.
--   * Two new event types in money_event_settings: customer_collection (a due paid later) and pos_split_payment (money taken with a sale). They work exactly like the 14 phase87 events:
--     default account, owner fixed source, source required, one-off owner exceptions. The money account travels IN BAND as "ma#<id>;" in front of the wallet text (what web/pay.js already sends when
--     a row has a payment source) or in the column money_account_id.
--   * A BEFORE INSERT trigger on sale_payments resolves the source, sets the mode from the account, refuses bank mode while the switch is OFF and checks the reference rule.
--   * A new route _w1f_collect_payment (same contract as collect_payment plus bank, cheque, money_account_id, reference and an exception reason per payment) so the shared collect_payment need not change;
--     the hook that makes collect_payment itself accept the same fields is in the integration note.
--   * _w1f_receipt_settings and _w1f_receipts_list for the screen.
-- SETTINGS (rules, every change is in audit_log):
--   receipt_bank_on           OFF    bank / cheque receipts are accepted (today's behaviour: refused with bad_mode)
--   receipt_ref_required      off    off | bank (bank receipts need a transaction or cheque number) | bank_mobile (mobile wallet receipts too)
--   receipt_ref_from          blank  the reference rule applies to payments dated on or after this day (blank = at once)
-- A missing reference can be waived per payment with a written reason (ref_waiver): audit_log line + a yellow line in the Exceptions list. Books balance is not involved, so the rule may be waived.
-- Nothing changes for an existing install: with the three settings at their defaults and no money account chosen, every payment is stored exactly as before.

do $g$ begin
  if to_regprocedure('public._w1f_present96()') is null then raise exception 'phase97 needs phase96 (and phase87) first'; end if;
  if to_regclass('public.sale_payments') is null or to_regprocedure('public.customer_balance(uuid)') is null then raise exception 'phase97 needs the POS tables'; end if;
end $g$;

create or replace function public._w1f_present97() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, choices, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('receipt_bank_on', 'pos', 'switch', 'false', null, 'Accept bank transfer and cheque from customers', 'Accept bank transfer and cheque from customers', 'Accept bank transfer and cheque from customers',
  'OFF = only cash, mobile and card', 'OFF (default) = a customer payment can only be cash, mobile or card, as today. ON = bank transfer and cheque (a cheque is a bank receipt with its cheque number) are accepted on due collections and POS split payments.', 962),
 ('receipt_ref_required', 'pos', 'choice', '"off"', '["off","bank","bank_mobile"]', 'Reference number needed on bank receipts', 'Reference number needed on bank receipts', 'Reference number needed on customer bank receipts',
  'off | bank | bank_mobile', 'off (default) = never. bank = a bank or cheque receipt needs a transaction number or a cheque number. bank_mobile = mobile wallet receipts need one too. A missing number can be waived with a written reason.', 963),
 ('receipt_ref_from', 'pos', 'text', null, null, 'The reference rule counts from this date', 'The reference rule counts from this date', 'The reference rule counts from this date (YYYY-MM-DD)',
  'Blank = at once', 'Blank = at once. When set, a payment dated before it is never asked for a number, so an old figure is never touched.', 964)
on conflict (key) do nothing;

-- ---------- columns and constraints ----------
alter table public.sale_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.sale_payments add column if not exists cheque_no text;
alter table public.sale_payments add column if not exists cheque_date date;
alter table public.sale_payments add column if not exists ref_waiver text;
do $c$ declare d text; ck record; begin
  for ck in select * from (values ('sale_payments', 'sale_payments_mode_check', 'array[''cash'',''mobile'',''card'',''bank'']'), ('sales', 'sales_pay_mode_check', 'array[''cash'',''mobile'',''card'',''due'',''split'',''bank'']')) v(t, n, arr) loop
    select pg_get_constraintdef(c.oid) into d from pg_constraint c where c.conrelid = ('public.' || ck.t)::regclass and c.conname = ck.n;
    if d is not null and position('bank' in d) = 0 then
      execute format('alter table public.%I drop constraint %I', ck.t, ck.n);
      execute format('alter table public.%I add constraint %I check (%s)', ck.t, ck.n, case ck.t when 'sale_payments' then 'mode' else 'pay_mode' end || ' = any (' || ck.arr || ')');
    end if;
  end loop;
  if not exists (select 1 from pg_constraint where conrelid = 'public.sale_payments'::regclass and conname = 'sale_payments_w1f_len') then
    alter table public.sale_payments add constraint sale_payments_w1f_len check ((cheque_no is null or length(cheque_no) <= 40) and (ref_waiver is null or length(ref_waiver) <= 200));
  end if;
end $c$;
create index if not exists sale_payments_money_acc on public.sale_payments (money_account_id) where money_account_id is not null;

insert into public.money_event_settings (event_type, label_en, dir, sort) values
 ('customer_collection', 'Customer payment of a due (collection)', 'in', 160),
 ('pos_split_payment', 'Customer payment taken with a sale (POS)', 'in', 170)
on conflict (event_type) do nothing;

-- ---------- helpers ----------
create or replace function public._w1f_receipt_modes() returns text[] language sql stable security definer set search_path = public as $$
  select case when public.rule_on('receipt_bank_on') then array['cash', 'mobile', 'card', 'bank'] else array['cash', 'mobile', 'card'] end $$;
-- readers of one payment object (used by the hook text of collect_payment and record_sale2)
create or replace function public._w1f_pj_text(p jsonb, k text, n int) returns text language sql immutable as $$ select left(nullif(btrim(p ->> k), ''), n) $$;
create or replace function public._w1f_pj_date(p jsonb, k text) returns date language plpgsql immutable as $$
begin return nullif(btrim(p ->> k), '')::date; exception when others then raise exception 'bad_date'; end $$;
create or replace function public._w1f_pj_acc(p jsonb) returns bigint language sql immutable as $$ select case when (p ->> 'money_account_id') ~ '^[0-9]{1,12}$' then (p ->> 'money_account_id')::bigint end $$;

-- ---------- the BEFORE INSERT trigger of sale_payments ----------
create or replace function public._w1f_sp_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare ac bigint; rest text; ev text; src record; usr boolean := auth.uid() is not null; refreq text; frm text; need boolean; dt date;
begin
  select u.acc, u.rest into ac, rest from public._m_untag(new.wallet) u;                   -- the in-band tag "ma#<id>;" of the payment source picker
  if ac is not null then new.wallet := rest; end if;
  ac := coalesce(ac, new.money_account_id);
  dt := (new.paid_at at time zone 'Asia/Dhaka')::date;
  if new.mode = 'bank' and usr and not public.rule_on('receipt_bank_on') then raise exception 'receipt_bank_off'; end if;
  ev := case when new.kind = 'collection' then 'customer_collection' else 'pos_split_payment' end;
  select * into src from public._w1f_pick_source(ev, ac, new.location_id, new.mode, new.amount, new.client_id, dt, 'sale_payments');
  if src.o_acc is not null then
    new.money_account_id := src.o_acc; new.mode := src.o_mode; new.wallet := null;
  end if;
  if nullif(btrim(coalesce(new.cheque_no, '')), '') is not null and new.mode <> 'bank' then raise exception 'cheque_needs_bank'; end if;
  new.ref := nullif(btrim(coalesce(new.ref, '')), '');
  new.cheque_no := nullif(btrim(coalesce(new.cheque_no, '')), '');
  new.ref_waiver := nullif(btrim(coalesce(new.ref_waiver, '')), '');
  -- reference rule (a setting; may be waived with a reason because it is not about balancing the books)
  refreq := coalesce(public.rule_txt('receipt_ref_required'), 'off'); frm := public.rule_txt('receipt_ref_from');
  need := usr and refreq <> 'off' and (new.mode = 'bank' or (refreq = 'bank_mobile' and new.mode = 'mobile'))
          and (frm is null or frm !~ '^\d{4}-\d{2}-\d{2}$' or dt >= frm::date);
  if need and new.ref is null and new.cheque_no is null then
    if new.ref_waiver is null or length(new.ref_waiver) < 3 then raise exception 'receipt_reference_required'; end if;
    perform public._w1f_audit('receipt_reference_waived', 'sale_payments', coalesce(new.client_id::text, new.sale_id::text, '-'),
      jsonb_build_object('kind', new.kind, 'mode', new.mode, 'amount', new.amount, 'location_id', new.location_id, 'reason', new.ref_waiver));
    perform public._w1f_exception('POS', new.location_id, dt, 'receipt_reference_waived', new.amount, 'Receipt without a reference number: ' || new.ref_waiver);
  end if;
  return new;
end $$;

create or replace function public._w1f_sp_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id then raise exception 'money_account_fixed'; end if;
  if new.cheque_no is distinct from old.cheque_no or new.cheque_date is distinct from old.cheque_date then raise exception 'cheque_fixed'; end if;
  return new;
end $$;

drop trigger if exists w1f_sp_bi on public.sale_payments;
create trigger w1f_sp_bi before insert on public.sale_payments for each row execute function public._w1f_sp_bi();
drop trigger if exists w1f_sp_bu on public.sale_payments;
create trigger w1f_sp_bu before update on public.sale_payments for each row execute function public._w1f_sp_bu();

-- ---------- the new route: collect a due with bank, cheque, a payment source and a reference ----------
-- Same contract and checks as collect_payment (POS permission, place, one collection at a time per customer, repeat of the same client id returns the first answer, never more than the due),
-- plus per payment: money_account_id, ref, cheque_no, cheque_date, exception_reason (waives a missing reference).
create or replace function public._w1f_collect_payment(p_client uuid, p_loc integer, p_customer uuid, p_payments jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; modes text[] := public._w1f_receipt_modes(); ids bigint[] := '{}'; nid bigint; cheque_d date;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_client is not null and exists (select 1 from public.sale_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public.customer_balance(p_customer));
  end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay ->> 'mode'; amt := (pay ->> 'amount')::numeric;
    if pm is null or pm <> all (modes) then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    if (pay ->> 'money_account_id') is not null and public._w1f_pj_acc(pay) is null then raise exception 'unknown_money_account'; end if;
    tot := tot + round(amt, 2);
  end loop;
  bal := coalesce(public.customer_balance(p_customer), 0);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay ->> 'mode', public._w1f_pj_text(pay, 'wallet', 30), public._w1f_pj_text(pay, 'ref', 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'),
              public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay ->> 'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client)
      returning id into nid;
    ids := ids || nid;
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot, 'ids', to_jsonb(ids));
end $$;

-- ---------- screen readers ----------
create or replace function public._w1f_receipt_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('bank_on', public.rule_on('receipt_bank_on'), 'ref_required', coalesce(public.rule_txt('receipt_ref_required'), 'off'), 'ref_from', public.rule_txt('receipt_ref_from'),
    'modes', to_jsonb(public._w1f_receipt_modes()),
    'events', coalesce((select jsonb_agg(jsonb_build_object('event_type', s.event_type, 'default_account_id', s.default_account_id, 'allow_override', s.allow_override, 'require_source', s.require_source))
                          from public.money_event_settings s where s.event_type in ('customer_collection', 'pos_split_payment')), '[]'::jsonb));
end $$;

create or replace function public._w1f_receipts_list(p_loc int default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public._acct_view()) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.paid_at desc, z.id desc) from (
      select p.id, p.kind, p.location_id, p.mode, p.amount, p.paid_at, p.ref, p.cheque_no, p.cheque_date, p.money_account_id, a.name_en as account_name, p.ref_waiver, p.voided, p.void_note,
             c.name as customer_name, c.mobile as customer_mobile, s.receipt, p.created_staff
        from public.sale_payments p left join public.money_accounts a on a.id = p.money_account_id left join public.customers c on c.id = p.customer_id left join public.sales s on s.id = p.sale_id
       where (p.mode = 'bank' or p.money_account_id is not null or p.cheque_no is not null) and (p_loc is null or p.location_id = p_loc) and public.can_loc(p.location_id)
         and (p.paid_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2100-01-01')
       order by p.paid_at desc, p.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $pv$ declare f record; pub text[] := array['_w1f_collect_payment', '_w1f_receipt_settings', '_w1f_receipts_list'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
       ('_w1f_receipt_modes', '_w1f_pj_text', '_w1f_pj_date', '_w1f_pj_acc', '_w1f_sp_bi', '_w1f_sp_bu', '_w1f_collect_payment', '_w1f_receipt_settings', '_w1f_receipts_list', '_w1f_present97') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (pub) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $pv$;

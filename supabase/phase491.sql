-- ============================================================
-- Phase 491 - XB package part 1: bKash / Nagad / Rocket payment capture and reconciliation.
-- Run AFTER phase 478 (needs phase61 online_orders, phase83 d_wallets, phase6 sales). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * pay_captures          one row per mobile payment the counter writes down: provider, Trx-ID, sender number, amount, time, wallet,
--                           the order / sale / advance it is for, the amount expected, the flag (ok / overpay / underpay / no_target).
--                           A Trx-ID is unique (a duplicate is refused). Verification: pending -> verified | rejected (approver holds
--                           grant pay_verify or is the owner; never the person who captured it). Append-only (decision fields only).
--   * xb_pay_capture        write a capture (rule pay_capture_on OFF = refused). Nothing is posted to the books: a capture is evidence.
--   * xb_pay_capture_decide approve / reject; a flagged capture needs a note.
--   * xb_pay_capture_screenshot  attach a payment screenshot (private bucket 'payproof', path pay/<place>/<file>.jpg), once.
--   * pay_statement_lines   wallet statement lines imported from CSV / paste (append-only, deduplicated on wallet + Trx-ID + direction).
--   * xb_pay_statement_import   owner or a pay_verify holder (place-less grant) imports a statement; duplicates are counted, not written twice.
--   * xb_pay_tieout         daily tie-out per wallet: captured vs statement, with the lists of what does not match.
--   * Rules (OFF / blank): pay_capture_on (OFF), pay_capture_tol (blank = the amount must match exactly; no tolerance is invented).
-- No merchant API adapter is built: statement and capture records are the only inputs; no outbound call exists anywhere.
-- Paper form code for any printed version: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.d_wallets') is null or to_regclass('public.sales') is null
     or to_regprocedure('public.c2_orders_features()') is null then
    raise exception 'phase540 needs phase61, phase83, phase6 and phase445 pasted first';
  end if;
end $guard$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('pay_verify', 'pos', 90, 'মোবাইল পেমেন্ট যাচাই করা', 'Mobile payment verify করা', 'Verify mobile payments (bKash / Nagad / Rocket)', 'once', null)
on conflict (grant_code) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pay_capture_on', 'pos', 'switch', 'false', null, null, null, null, 'মোবাইল পেমেন্ট (Trx-ID) লেখা চালু', 'Mobile payment (Trx-ID) capture চালু', 'Mobile payment capture is on',
  'চালু হলে বিকাশ/নগদ/রকেটের Trx-ID, নম্বর, টাকা লেখা যাবে; একই Trx-ID দুবার ঢোকে না।', 'When on, bKash / Nagad / Rocket Trx-ID, sender, amount and time can be written; a Trx-ID is never accepted twice.', 540),
 ('pay_capture_tol', 'pos', 'number', null, 'taka', null, 0, 1000000, 'মেলানোর সহনশীলতা (টাকা)', 'Match tolerance (taka)', 'Amount match tolerance (taka)',
  'ফাঁকা = টাকা হুবহু মিলতে হবে। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = the amount must match exactly. No number is assumed.', 541)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.pay_captures (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  provider text not null check (provider in ('bkash', 'nagad', 'rocket', 'other')),
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  sender_no text check (sender_no is null or char_length(sender_no) between 6 and 20),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  paid_at timestamptz not null,
  location_id int not null references public.locations(id),
  target text not null check (target in ('order', 'sale', 'advance', 'none')),
  online_order_id uuid references public.online_orders(id),
  sale_id uuid references public.sales(id),
  expected numeric,
  diff numeric,
  flag text not null check (flag in ('ok', 'overpay', 'underpay', 'no_target')),
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected', 'void')),
  source text not null default 'manual' check (source in ('manual', 'sms_paste')),
  screenshot_path text check (screenshot_path is null or char_length(screenshot_path) <= 200),
  note text check (note is null or char_length(note) <= 300),
  captured_by uuid, captured_staff text, captured_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz, decide_note text check (decide_note is null or char_length(decide_note) <= 300),
  check ((target = 'order') = (online_order_id is not null) or target = 'advance'), check ((target = 'sale') = (sale_id is not null))
);
create unique index if not exists pay_captures_trx_live on public.pay_captures (trx_id) where status <> 'void';
create index if not exists pay_captures_day on public.pay_captures (location_id, paid_at);

create table if not exists public.pay_statement_lines (
  id bigint generated always as identity primary key,
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  direction text not null check (direction in ('in', 'out')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  stmt_at timestamptz not null,
  counterpart text check (counterpart is null or char_length(counterpart) <= 40),
  import_batch uuid not null,
  imported_by uuid, imported_at timestamptz not null default now(),
  unique (wallet_code, trx_id, direction)
);

-- captures: only the decision fields and the screenshot path move; nothing is deleted
create or replace function public._xb540_pay_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a payment capture is never deleted, void it through the decision'; end if;
  if (to_jsonb(new) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path')
     is distinct from (to_jsonb(old) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path') then
    raise exception 'append_only: a payment capture changes only its decision and its screenshot';
  end if;
  if old.screenshot_path is not null and new.screenshot_path is distinct from old.screenshot_path then raise exception 'already_attached'; end if;
  if old.status in ('verified', 'rejected', 'void') and new.status is distinct from old.status then raise exception 'decided: a decided capture cannot change'; end if;
  return new;
end $$;
drop trigger if exists pay_captures_ro on public.pay_captures;
create trigger pay_captures_ro before update or delete on public.pay_captures for each row execute function public._xb540_pay_ro();
drop trigger if exists audit_pay_captures on public.pay_captures;
create trigger audit_pay_captures after insert or update on public.pay_captures for each row execute function public.log_change('id');

create or replace function public._xb540_lines_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: a statement line is never changed or deleted'; end $$;
drop trigger if exists pay_statement_lines_ro on public.pay_statement_lines;
create trigger pay_statement_lines_ro before update or delete on public.pay_statement_lines for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_pay_statement_lines on public.pay_statement_lines;
create trigger audit_pay_statement_lines after insert on public.pay_statement_lines for each row execute function public.log_change('id');

-- ---------- helpers ----------
create or replace function public._xb540_verifier(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or public.has_grant('pay_verify', p_loc);
$$;
create or replace function public._xb540_verifier_any() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'pay_verify' and g.location_id is null);
$$;
create or replace function public._xb540_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_capture_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- ---------- capture ----------
create or replace function public.xb_pay_capture(p_client uuid, p_provider text, p_trx text, p_sender text, p_amount numeric, p_paid_at timestamptz,
  p_wallet text, p_loc int, p_target text, p_order uuid default null, p_sale uuid default null, p_source text default 'manual', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare trx text := upper(btrim(coalesce(p_trx, ''))); o public.online_orders; s public.sales; ex numeric; df numeric; fl text; tol numeric := coalesce(public.rule_num('pay_capture_tol'), 0);
        rec public.pay_captures; wok boolean; id_ bigint; ol uuid; sl uuid; sndr text;
begin
  if p_client is not null then
    select * into rec from public.pay_captures where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'status', rec.status, 'flag', rec.flag, 'dup', true); end if;
  end if;
  perform public._xb540_gate(p_loc);
  if p_provider not in ('bkash', 'nagad', 'rocket', 'other') then raise exception 'bad_provider'; end if;
  if trx !~ '^[A-Z0-9]{6,20}$' then raise exception 'bad_trx_id'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_paid_at is null or p_paid_at > now() + interval '10 minutes' then raise exception 'bad_time'; end if;
  if p_source not in ('manual', 'sms_paste') then raise exception 'bad_source'; end if;
  if p_target not in ('order', 'sale', 'advance', 'none') then raise exception 'bad_target'; end if;
  select exists (select 1 from public.d_wallets w where w.code = p_wallet and w.active) into wok;
  if not wok then raise exception 'bad_wallet'; end if;
  sndr := nullif(btrim(coalesce(p_sender, '')), '');
  if sndr is not null then sndr := public.norm_mobile(sndr); if sndr is null or char_length(sndr) < 6 then raise exception 'bad_sender'; end if; end if;
  if exists (select 1 from public.pay_captures where trx_id = trx and status <> 'void') then raise exception 'duplicate_trx: this Trx-ID is already written'; end if;
  ex := null;
  if p_target = 'order' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
    ex := o.subtotal - o.discount + o.delivery_charge - o.advance; ol := o.id;
  elsif p_target = 'sale' then
    select * into s from public.sales where id = p_sale;
    if not found then raise exception 'not_found'; end if;
    if s.location_id <> p_loc then raise exception 'other_location'; end if;
    ex := s.due_amount; sl := s.id;
  elsif p_target = 'advance' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    ol := o.id;
    ex := case when o.advance > 0 then o.advance end;
  end if;
  if ex is null then fl := 'no_target'; df := null;
  else
    df := round(p_amount - ex, 2);
    fl := case when abs(df) <= tol then 'ok' when df > 0 then 'overpay' else 'underpay' end;
  end if;
  insert into public.pay_captures (client_id, provider, wallet_code, trx_id, sender_no, amount, paid_at, location_id, target, online_order_id, sale_id, expected, diff, flag, source, note, captured_by, captured_staff)
    values (p_client, p_provider, p_wallet, trx, sndr, round(p_amount, 2), p_paid_at, p_loc, p_target, ol, sl, ex, df, fl, p_source, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'status', 'pending', 'flag', fl, 'expected', ex, 'diff', df, 'note_needed_to_verify', fl <> 'ok');
exception when unique_violation then
  raise exception 'duplicate_trx: this Trx-ID is already written';
end $$;

-- ---------- verify (nobody approves the capture they wrote; a flagged or rejected one needs a note) ----------
create or replace function public.xb_pay_capture_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public._xb540_verifier(rec.location_id) then raise exception 'not allowed'; end if;
  if p_approve is null then raise exception 'bad_input'; end if;
  if rec.status <> 'pending' then raise exception 'already_decided'; end if;
  if rec.captured_by = auth.uid() then raise exception 'own_capture: nobody approves the capture they wrote'; end if;
  if (rec.flag <> 'ok' or not p_approve) and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.pay_captures set status = case when p_approve then 'verified' else 'rejected' end, decided_by = auth.uid(), decided_at = now(),
    decide_note = left(nullif(btrim(p_note), ''), 300) where id = rec.id;
  return jsonb_build_object('id', rec.id, 'status', case when p_approve then 'verified' else 'rejected' end, 'flag', rec.flag);
end $$;

create or replace function public.xb_pay_capture_screenshot(p_id bigint, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if rec.screenshot_path is not null then raise exception 'already_attached'; end if;
  if p_path is null or p_path !~ ('^pay/' || rec.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.pay_captures set screenshot_path = p_path where id = rec.id;
  return jsonb_build_object('id', rec.id, 'screenshot_path', p_path);
end $$;

create or replace function public.xb_pay_captures_list(p_loc int default null, p_status text default null, p_day date default null, p_limit int default 200) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(z) order by z.paid_at desc), '[]'::jsonb) from (
    select c.id, c.provider, c.wallet_code, c.trx_id, c.sender_no, c.amount, c.paid_at, c.location_id, c.target, c.online_order_id, c.sale_id, c.expected, c.diff, c.flag, c.status,
           c.screenshot_path is not null as has_screenshot, c.captured_staff, c.decided_at, c.decide_note
      from public.pay_captures c
     where public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(c.location_id)
       and (p_loc is null or c.location_id = p_loc) and (p_status is null or c.status = p_status)
       and (p_day is null or (c.paid_at at time zone 'Asia/Dhaka')::date = p_day)
     order by c.paid_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z;
$$;

-- ---------- statement import and tie-out ----------
create or replace function public.xb_pay_statement_import(p_wallet text, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare batch uuid := gen_random_uuid(); ln jsonb; ins int := 0; dup int := 0; bad int := 0; n int;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.d_wallets where code = p_wallet and active) then raise exception 'bad_wallet'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 2000 then raise exception 'bad_lines'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    if upper(btrim(coalesce(ln->>'trx_id', ''))) !~ '^[A-Z0-9]{6,20}$' or coalesce(ln->>'direction', '') not in ('in', 'out')
       or (ln->>'amount') is null or (ln->>'amount')::numeric <= 0 or (ln->>'at') is null then bad := bad + 1; continue; end if;
    insert into public.pay_statement_lines (wallet_code, trx_id, direction, amount, stmt_at, counterpart, import_batch, imported_by)
      values (p_wallet, upper(btrim(ln->>'trx_id')), ln->>'direction', round((ln->>'amount')::numeric, 2), (ln->>'at')::timestamptz,
              left(nullif(btrim(ln->>'counterpart'), ''), 40), batch, auth.uid())
      on conflict (wallet_code, trx_id, direction) do nothing;
    get diagnostics n = row_count;
    if n = 1 then ins := ins + 1; else dup := dup + 1; end if;
  end loop;
  return jsonb_build_object('wallet', p_wallet, 'batch', batch, 'inserted', ins, 'already_there', dup, 'bad_rows', bad);
end $$;

create or replace function public.xb_pay_tieout(p_date date, p_wallet text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); out_ jsonb := '[]';
        w record; cap numeric; cap_ver numeric; stm_in numeric; stm_out numeric; l_stmt jsonb; l_erp jsonb; l_mis jsonb; nmis int; nstm int; nerp int; has_stm boolean;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  for w in select code, name_en from public.d_wallets where active and (p_wallet is null or code = p_wallet) order by sort, id loop
    select coalesce(sum(amount), 0), coalesce(sum(amount) filter (where status = 'verified'), 0) into cap, cap_ver
      from public.pay_captures where wallet_code = w.code and status in ('pending', 'verified') and (paid_at at time zone 'Asia/Dhaka')::date = d;
    select coalesce(sum(amount) filter (where direction = 'in'), 0), coalesce(sum(amount) filter (where direction = 'out'), 0) into stm_in, stm_out
      from public.pay_statement_lines where wallet_code = w.code and (stmt_at at time zone 'Asia/Dhaka')::date = d;
    has_stm := exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and (s.stmt_at at time zone 'Asia/Dhaka')::date = d);
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', s.trx_id, 'amount', s.amount) order by s.trx_id), '[]'::jsonb), count(*)
      into l_stmt, nstm from public.pay_statement_lines s
     where s.wallet_code = w.code and s.direction = 'in' and (s.stmt_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_captures c where c.trx_id = s.trx_id and c.status <> 'void');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'amount', c.amount, 'status', c.status) order by c.trx_id), '[]'::jsonb), count(*)
      into l_erp, nerp from public.pay_captures c
     where c.wallet_code = w.code and c.status = 'verified' and (c.paid_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and s.trx_id = c.trx_id and s.direction = 'in');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'captured', c.amount, 'statement', s.amount) order by c.trx_id), '[]'::jsonb), count(*)
      into l_mis, nmis from public.pay_captures c join public.pay_statement_lines s on s.wallet_code = c.wallet_code and s.trx_id = c.trx_id and s.direction = 'in'
     where c.wallet_code = w.code and c.status in ('pending', 'verified') and c.amount <> s.amount;
    out_ := out_ || jsonb_build_object('wallet', w.code, 'name_en', w.name_en, 'captured_total', cap, 'captured_verified', cap_ver,
      'statement_in', stm_in, 'statement_out', stm_out, 'statement_lines_without_capture', nstm, 'captured_not_on_statement', nerp,
      'amount_mismatch', nmis, 'statement_only', l_stmt, 'captured_only', l_erp, 'mismatch', l_mis, 'statement_imported', has_stm,
      'status', case when not has_stm then 'no_statement_imported'
                     when nstm = 0 and nerp = 0 and nmis = 0 then 'matched' else 'difference' end);
  end loop;
  return jsonb_build_object('date', d, 'wallets', out_, 'notes', jsonb_build_array('a_capture_is_evidence_not_a_posting', 'blank_tolerance_means_exact_match'));
end $$;

-- ---------- privileges and RLS ----------
alter table public.pay_captures enable row level security;
alter table public.pay_statement_lines enable row level security;
revoke all on public.pay_captures, public.pay_statement_lines from public, anon, authenticated;
grant select on public.pay_captures to authenticated;
grant select on public.pay_statement_lines to authenticated;
drop policy if exists pay_captures_sel on public.pay_captures;
create policy pay_captures_sel on public.pay_captures for select to authenticated
  using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists pay_statement_lines_sel on public.pay_statement_lines;
create policy pay_statement_lines_sel on public.pay_statement_lines for select to authenticated using (public.is_owner() or public._xb540_verifier_any());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('payproof', 'payproof', false, 3145728, array['image/jpeg']) on conflict (id) do nothing;
drop policy if exists xb540_payproof_ins on storage.objects;
create policy xb540_payproof_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and public.can_do('POS', 'enter') and public.can_loc(split_part(name, '/', 2)::int));
drop policy if exists xb540_payproof_read on storage.objects;
create policy xb540_payproof_read on storage.objects for select to authenticated
  using (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(split_part(name, '/', 2)::int));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_pay\_%' or p.proname like '\_xb540\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_pay\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

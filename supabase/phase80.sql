-- Phase 80: (A) one-step opening balance (stock, cash per place, wallets, dues, payables, owner / partner capital) and
--           (B) owner approval modes (G15): one owner-only setting with four modes.
-- Additive; paste-twice safe. Paste after phase79. Own tag: bos80.
-- (A) opening_balance_post(json, client, dry, plug) builds ONE opening journal entry through the existing acct_opening and posts the
--     stock openings through the existing stock_opening in the same transaction. Debit must equal credit, otherwise nothing is
--     written (no balancing figure unless p_plug is true). A second post is refused (opening_exists). Every post writes an
--     append-only opening_batches row and one audit_log line. A dry run writes nothing.
-- (B) rules owner_approval_mode (self | named | logged | off, default self = today's behaviour) and owner_approver_role (blank).
--     owner_approval_mode_set() is owner-only, writes one audit_log line and keeps the legacy switch owner_self_approve in step
--     (self / logged / off = ON, named = OFF), so every existing approval check keeps working. In named mode only a holder of the
--     named role may decide a request made by the owner (trigger on entries and entry_change_requests).

-- ---------- (A) opening batches ----------
create table if not exists public.opening_batches (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  journal_entry_id bigint,
  payload_hash text not null,
  summary jsonb not null default '{}'::jsonb,
  by_user uuid,
  at timestamptz not null default now()
);
alter table public.opening_batches enable row level security;
drop policy if exists opening_batches_read on public.opening_batches;
create policy opening_batches_read on public.opening_batches for select to authenticated using (public._acct_view());
revoke all on public.opening_batches from public, anon, authenticated;
grant select on public.opening_batches to authenticated;
create or replace function public._opening_batches_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: opening_batches is append-only'; end $$;
drop trigger if exists opening_batches_ro on public.opening_batches;
create trigger opening_batches_ro before update or delete on public.opening_batches for each row execute function public._opening_batches_ro();
drop trigger if exists opening_batches_ro_t on public.opening_batches;
create trigger opening_batches_ro_t before truncate on public.opening_batches for each statement execute function public._opening_batches_ro();

-- p_json: {"stock":[{item_id,location_id,qty,unit,unit_cost}], "cash":[{location_id,mode:cash|bank|mobile|card,amount,wallet}],
--          "customer_dues":[{customer_id,amount,location_id}], "supplier_dues":[{supplier_id,amount,location_id}],
--          "capital":[{kind:owner|partner,amount,party_id}], "other":[{code,debit,credit,memo}]}
create or replace function public.opening_balance_post(p_json jsonb, p_client uuid default null, p_dry boolean default false, p_plug boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ln jsonb := '[]'::jsonb; x jsonb; it public.items; amt numeric; td numeric := 0; tc numeric := 0; k text; diff numeric; r jsonb; jid bigint; h text;
  stock_n int := 0; sec text;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_json is null or jsonb_typeof(p_json) <> 'object' then raise exception 'bad_payload'; end if;
  for sec in select jsonb_object_keys(p_json) loop
    if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other') then raise exception 'bad_payload'; end if;
    if jsonb_typeof(p_json->sec) <> 'array' then raise exception 'bad_payload'; end if;
  end loop;
  h := md5(p_json::text);
  if p_client is not null and not p_dry then
    perform public._client_lock(p_client);
    select journal_entry_id into jid from public.opening_batches where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', jid); end if;
  end if;
  -- stock: Dr inventory (by item type) = qty x unit cost; a missing cost is refused (never invented)
  for x in select * from jsonb_array_elements(coalesce(p_json->'stock', '[]')) loop
    select * into it from public.items where id = nullif(x->>'item_id', '')::uuid;
    if not found then raise exception 'unknown_item'; end if;
    if nullif(x->>'unit_cost', '') is null then raise exception 'cost_missing'; end if;
    if (x->>'qty') !~ '^[0-9]{1,9}(\.[0-9]{1,4})?$' or (x->>'unit_cost') !~ '^[0-9]{1,9}(\.[0-9]{1,4})?$' then raise exception 'bad_amount'; end if;
    amt := round((x->>'qty')::numeric * (x->>'unit_cost')::numeric, 2);
    ln := ln || jsonb_build_object('a', public._acct_inv_key(it.item_type), 'debit', amt, 'memo', left('stock ' || coalesce(it.name_en, ''), 120), 'location_id', (x->>'location_id')::int);
    stock_n := stock_n + 1;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'cash', '[]')) loop
    k := public._acct_paykey(x->>'mode');
    if (x->>'mode') not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    ln := ln || jsonb_build_object('a', k, 'debit', x->>'amount', 'memo', left(coalesce(nullif(x->>'wallet', ''), x->>'mode'), 60), 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop
    if nullif(x->>'customer_id', '') is null or not exists (select 1 from public.customers where id = (x->>'customer_id')::uuid) then raise exception 'unknown_party'; end if;
    ln := ln || jsonb_build_object('a', 'receivable', 'debit', x->>'amount', 'party_type', 'customer', 'party_id', x->>'customer_id', 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'supplier_dues', '[]')) loop
    if nullif(x->>'supplier_id', '') is null or not exists (select 1 from public.suppliers where id = (x->>'supplier_id')::uuid) then raise exception 'unknown_party'; end if;
    ln := ln || jsonb_build_object('a', 'payable', 'credit', x->>'amount', 'party_type', 'supplier', 'party_id', x->>'supplier_id', 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'capital', '[]')) loop
    if (x->>'kind') = 'owner' then ln := ln || jsonb_build_object('code', '3100', 'credit', x->>'amount', 'party_type', null, 'party_id', null);
    elsif (x->>'kind') = 'partner' then ln := ln || jsonb_build_object('code', '3200', 'credit', x->>'amount', 'party_type', 'partner', 'party_id', x->>'party_id');
    else raise exception 'bad_kind'; end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'other', '[]')) loop
    ln := ln || jsonb_build_object('code', x->>'code', 'debit', coalesce(x->>'debit', '0'), 'credit', coalesce(x->>'credit', '0'), 'memo', x->>'memo');
  end loop;
  if jsonb_array_length(ln) = 0 then raise exception 'no_lines'; end if;
  -- totals from the resolved lines (dry run answers even when unbalanced; a real post refuses)
  select coalesce(sum((e->>'debit')::numeric), 0), coalesce(sum((e->>'credit')::numeric), 0) into td, tc from jsonb_array_elements(public._acct_resolve(ln, null)) e;
  diff := round(td - tc, 2);
  if p_dry then
    return jsonb_build_object('dry', true, 'total_debit', td, 'total_credit', tc, 'difference', diff, 'balanced', diff = 0, 'lines', jsonb_array_length(ln), 'stock_lines', stock_n);
  end if;
  if diff <> 0 and not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  -- the one journal entry (raises opening_exists on a second post, unbalanced / data_needed otherwise); the whole call is one transaction
  r := public.acct_opening(ln, coalesce(p_plug, false), 'Opening balances', p_client, false);
  jid := (r->>'id')::bigint;
  for x in select * from jsonb_array_elements(coalesce(p_json->'stock', '[]')) loop
    perform public.stock_opening((x->>'item_id')::uuid, (x->>'location_id')::int, (x->>'qty')::numeric, (x->>'unit_cost')::numeric, nullif(x->>'unit', ''), 'opening balance', null);
  end loop;
  insert into public.opening_batches (client_id, journal_entry_id, payload_hash, summary, by_user)
    values (p_client, jid, h, jsonb_build_object('total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n), auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'opening_post', 'journal_entries', jid::text,
      jsonb_build_object('payload_hash', h, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n));
  return jsonb_build_object('id', jid, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n);
end $$;

-- ---------- (B) owner approval modes ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_approval_mode', 'lists', 'choice', '"self"', null, '["self","named","logged","off"]', null, null,
  'মালিকের নিজের এন্ট্রির অনুমোদন', 'Owner এর নিজের entry এর approval', 'Approval of the owner''s own entries',
  'self = মালিক নিজে, named = নির্ধারিত ভূমিকা, logged = নিজে ও সবসময় লগে, off = নিয়ন্ত্রণ বন্ধ', 'self = owner approves, named = a named role approves, logged = owner approves and it is always shown in the log, off = control off', 15),
 ('owner_approver_role', 'lists', 'text', null, null, null, null, null,
  'নির্ধারিত অনুমোদনকারী ভূমিকা (named হলে)', 'Named approver role (named mode)', 'Named approver role (used in named mode)',
  'ফাঁকা থাকলে named মোড চালু করা যায় না', 'Blank blocks named mode', 16)
on conflict (key) do nothing;

create or replace function public._owner_mode() returns text language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('owner_approval_mode'), 'self') $$;

create or replace function public.owner_approval_mode() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'approver_role', public.rule_txt('owner_approver_role'), 'owner_self_approve', public.rule_on('owner_self_approve'));
end $$;

create or replace function public.owner_approval_mode_set(p_mode text, p_role text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if p_mode = 'named' then
    rl := coalesce(rl, old_r);
    if rl is null then raise exception 'data_needed:owner_approver_role'; end if;
    if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
  end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r), 'new', jsonb_build_object('mode', p_mode, 'role', coalesce(rl, old_r)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', coalesce(rl, old_r), 'owner_self_approve', p_mode <> 'named');
end $$;

-- the log display (owner only, every mode): owner-made entries and change requests with who decided and how
create or replace function public.owner_approval_log(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'rows', coalesce((select jsonb_agg(z order by z->>'at' desc) from (
    select jsonb_build_object('kind', 'entry', 'id', e.id, 'form', e.form_code, 'status', e.status, 'maker', e.created_by, 'decided_by', e.checked_by, 'at', e.checked_at,
      'how', case when e.checked_by = e.created_by then 'self' else 'other' end) z
      from public.entries e where e.checked_by is not null and exists (select 1 from public.user_roles ur where ur.user_id = e.created_by and ur.role_code = 'owner')
    union all
    select jsonb_build_object('kind', 'change', 'id', c.id, 'form', null, 'status', c.status, 'maker', c.requested_by, 'decided_by', c.decided_by, 'at', c.decided_at,
      'how', case when c.decided_by = c.requested_by then 'self' else 'other' end)
      from public.entry_change_requests c where c.decided_by is not null and exists (select 1 from public.user_roles ur where ur.user_id = c.requested_by and ur.role_code = 'owner')
    order by 1 desc limit greatest(1, least(coalesce(p_limit, 100), 500))) q), '[]'::jsonb));
end $$;

-- named mode: a decision on the owner's own record must come from a holder of the named role
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  if rl is null or decider is null or not exists (select 1 from public.user_roles where user_id = decider and role_code = rl) then raise exception 'named_approver_only'; end if;
  return new;
end $$;
drop trigger if exists entries_named_guard80 on public.entries;
create trigger entries_named_guard80 before update on public.entries for each row execute function public._owner_named_guard();
drop trigger if exists ecr_named_guard80 on public.entry_change_requests;
create trigger ecr_named_guard80 before update on public.entry_change_requests for each row execute function public._owner_named_guard();

-- the mode rule may only be changed through owner_approval_mode_set (keeps the legacy switch in step)
create or replace function public._rules_mode_guard80() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key in ('owner_approval_mode', 'owner_approver_role') and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos80.setting', true), '') <> '1' then raise exception 'use owner_approval_mode_set'; end if;
  return new;
end $$;
drop trigger if exists rules_mode_guard80 on public.rules;
create trigger rules_mode_guard80 before update on public.rules for each row execute function public._rules_mode_guard80();
revoke all on function public.opening_balance_post(jsonb, uuid, boolean, boolean), public.owner_approval_mode(), public.owner_approval_mode_set(text, text, text), public.owner_approval_log(int),
  public._owner_mode(), public._owner_named_guard(), public._opening_batches_ro(), public._rules_mode_guard80() from public, anon, authenticated;
grant execute on function public.opening_balance_post(jsonb, uuid, boolean, boolean), public.owner_approval_mode(), public.owner_approval_mode_set(text, text, text), public.owner_approval_log(int) to authenticated;

-- Phase 304 (CRM package B, local label 104) - PRIVACY BY ROLE: who sees, exports or prints customer phone numbers and customer lists, with a log.
-- Paste AFTER phase303. Paste-twice safe. No earlier phase file is edited and NO shared function is re-created.
-- The integrator wires the hooks written in docs/integration/CRM-B.md (customers.js reads the list through _crmb_customer_list, the Call button and the Print button ask first).
--
-- WHY (CRM audit rows 57 to 60): customers_read (phase6) lets every POS-view user read every customer row and customer_directory() (phase43) returns name, mobile, address and
-- WhatsApp of up to 20000 customers unmasked. Masking exists for reports (rpt_mobile_ok) and for the inbox (phase76), not for the customer list. There was no log of who looked at
-- a number and no export control for customers.
-- THE SAFE DEFAULT KEEPS TODAY'S BEHAVIOUR: crm_pii_guard_on is OFF, so _crmb_customer_list returns exactly what customer_directory returns. Switching the guard ON masks phone and
-- address for everybody except the owner and holders of the grant crm_contact_view, in the functions below. Direct table reads of customers stay as they are (documented residual
-- exposure: a person with POS view can still read the table through the API; closing that is an owner decision, see CRM-B.md section 5).
-- WHAT THIS FILE ADDS
--   1. _crmb_customer_list(limit, collapse)   masked list with the same columns as customer_directory plus masked / linked_to / linked_count. collapse = one row per person (linked duplicates folded, phase305).
--   1b. _crmb_customer_profile(customer)       customer_profile with phone, WhatsApp and address masked for a person who may not see them (same shape plus masked).
--   2. _crmb_phone_reveal(customer, reason)    returns the full number once and writes crm_view_log (a reason when the setting asks for one).
--   3. _crmb_export(...) + crm_export_log      customer export with reason, row cap, masked columns, one log line; blocked until the owner sets a row cap.
--   4. _crmb_print_log(...)                    writes a print line; with crm_print_needs_export ON, printing a customer list needs the export right.
--   5. _crmb_policy()                          one call for the screens: what this person may do right now.
--   6. _crmb_consent_register(...)             the consent register list (names, masked phone, yes / no / not asked), counts from phase303.
--   7. _crmb_view_log_list / _crmb_export_log_list   owner only.
-- SETTINGS (rules, module crm): crm_pii_guard_on (OFF), crm_mask_style (first3_last2), crm_unmask_reason_required (ON; only matters when the guard is ON), crm_reveal_for_call (OFF),
--   crm_export_on (OFF), crm_export_max_rows (blank = blocked), crm_print_needs_export (OFF).  GRANTS (given by the owner, nobody has them by default): crm_contact_view, crm_export.
-- Accounting: nothing here reads or writes sales payments or the journal beyond what customer_directory already reads.

do $g$ begin
  if to_regprocedure('public._crmb_present()') is null then raise exception 'phase304 needs phase303 first'; end if;
end $g$;

do $r$ begin
  perform public._crmb_rule_seed('crm_pii_guard_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Show customer phone and address only to people who are allowed',
    'OFF = every customer list shows phone numbers as today. ON = the CRM customer list and sheets show a masked number (for example 017******78) and no address, except to the owner and people given "See customers'' full phone and address". Does not stop a person with POS access from reading the table through the API.', 3100);
  perform public._crmb_rule_seed('crm_mask_style', 'choice', '"first3_last2"'::jsonb, null, '["first3_last2","last4"]'::jsonb, null, null,
    'How a hidden phone number looks',
    'first3_last2 shows the first three and last two digits (017******78). last4 shows only the last four digits. Used only while the privacy switch is ON.', 3101);
  perform public._crmb_rule_seed('crm_unmask_reason_required', 'switch', 'true'::jsonb, null, null, null, null,
    'Ask for a reason before showing a full phone number',
    'ON = staff other than the owner write a short reason (at least 3 characters) each time they open a hidden number; it goes in the access log. Used only while the privacy switch is ON.', 3102);
  perform public._crmb_rule_seed('crm_reveal_for_call', 'switch', 'false'::jsonb, null, null, null, null,
    'Let counter staff ask for one number at a time to call',
    'OFF = a masked person cannot open the full number. ON = they can open one number at a time to call, always with a reason, and every look is in the access log. Used only while the privacy switch is ON.', 3103);
  perform public._crmb_rule_seed('crm_export_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Allow the customer list to be exported',
    'OFF = no customer export (today). ON = the owner and people given "Export the customer list" can export, with a row cap and a log line. Blocked until the row cap below is set.', 3104);
  perform public._crmb_rule_seed('crm_export_max_rows', 'number', null, 'rows', null, 1, 20000,
    'Most customers one export may contain',
    'Blank = export stays blocked even when switched on. Set a number to allow it.', 3105);
  perform public._crmb_rule_seed('crm_print_needs_export', 'switch', 'false'::jsonb, null, null, null, null,
    'Printing a customer list needs the export right',
    'OFF = anyone who sees the list can print it (today). ON = only the owner and people given "Export the customer list" can print it. The screen enforces the button; the print is logged either way.', 3106);
end $r$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_contact_view', 'pos', 96, 'See customers'' full phone and address', 'See customers'' full phone and address', 'See customers'' full phone and address', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_contact_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_export', 'pos', 97, 'Export the customer list', 'Export the customer list', 'Export the customer list', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_export');

-- ---------- logs (append only, owner reads) ----------
create table if not exists public.crm_view_log (          -- who opened a hidden contact detail, when, why
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  customer_id uuid references public.customers(id),
  what text not null check (what in ('contact', 'call', 'list', 'profile')),
  reason text check (reason is null or length(reason) <= 200),
  row_count int,
  detail jsonb
);
create index if not exists crm_view_log_at on public.crm_view_log (id desc);
create index if not exists crm_view_log_cust on public.crm_view_log (customer_id, id desc);
create table if not exists public.crm_export_log (        -- every customer export and customer-list print
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  kind text not null check (kind in ('export', 'print')),
  what text not null,
  filter jsonb,
  row_count int not null default 0,
  masked boolean not null default false,
  format text,
  reason text check (reason is null or length(reason) <= 200)
);
drop trigger if exists crm_view_log_ro on public.crm_view_log;
create trigger crm_view_log_ro before update or delete on public.crm_view_log for each row execute function public._crmb_ro();
drop trigger if exists crm_export_log_ro on public.crm_export_log;
create trigger crm_export_log_ro before update or delete on public.crm_export_log for each row execute function public._crmb_ro();
do $t$ declare t text; begin
  foreach t in array array['crm_view_log', 'crm_export_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner())', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_view_log_id_seq, public.crm_export_log_id_seq from public, anon, authenticated;

-- ---------- masking ----------
create or replace function public._crmb_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (not public.rule_on('crm_pii_guard_on') or public.is_owner() or public.has_grant('crm_contact_view'));
$$;

create or replace function public._crmb_mask_phone(p text) returns text language plpgsql stable security definer set search_path = public as $$
declare n int := length(coalesce(p, ''));
begin
  if p is null then return null; end if;
  if n <= 5 then return repeat('*', n); end if;
  if coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'last4' then return repeat('*', n - 4) || right(p, 4); end if;
  return left(p, 3) || repeat('*', n - 5) || right(p, 2);
end $$;

create or replace function public._crmb_view_log_add(p_customer uuid, p_what text, p_reason text, p_count int, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_view_log (user_id, staff_id, customer_id, what, reason, row_count, detail)
    values (auth.uid(), public._crmb_staff(), p_customer, p_what, nullif(btrim(p_reason), ''), p_count, p_detail);
end $$;

-- ---------- the customer list (same columns as customer_directory + masked / linked_to / linked_count) ----------
create or replace function public._crmb_customer_rows(p_limit int, p_collapse boolean, p_log boolean)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int, masked boolean, linked_to uuid, linked_count int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ok boolean; lim int := least(greatest(coalesce(p_limit, 5000), 1), 20000);
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  ok := public._crmb_contact_ok();
  -- while the guard is ON, a person who sees the numbers (not the owner) leaves one line per list they open
  if p_log and ok and public.rule_on('crm_pii_guard_on') and not public.is_owner() then
    perform public._crmb_view_log_add(null, 'list', null, lim, jsonb_build_object('collapse', coalesce(p_collapse, false)));
  end if;
  return query
    with d as (select x.* from public.customer_directory(lim) x),
         lk as (select l.primary_id pid, l.linked_id lid from public._crmb_links_active() l),
         g as (select lk.pid, count(*)::int cnt, sum(dd.spend) sp, sum(dd.orders)::int ord, max(dd.last_sale) ls, sum(dd.points)::int pt
                 from lk join d dd on dd.id = lk.lid group by lk.pid)
    select d.id, case when ok then d.mobile else public._crmb_mask_phone(d.mobile) end, d.name, d.type, d.active, d.tier_id, d.tier_locked, d.birthday, d.anniversary,
           case when ok then d.address end, case when ok then d.whatsapp else public._crmb_mask_phone(d.whatsapp) end, d.note, d.credit_limit, d.customer_since,
           d.balance,                                                                                                  -- a balance is never added up across a link: ledgers stay separate
           case when p_collapse then d.spend + coalesce(g.sp, 0) else d.spend end,
           case when p_collapse then d.orders + coalesce(g.ord, 0) else d.orders end,
           case when p_collapse then greatest(d.last_sale, g.ls) else d.last_sale end,
           case when p_collapse then d.points + coalesce(g.pt, 0) else d.points end,
           not ok, (select lk.pid from lk where lk.lid = d.id), coalesce(g.cnt, 0)
      from d left join g on g.pid = d.id
     where not (coalesce(p_collapse, false) and exists (select 1 from lk where lk.lid = d.id))
     order by lower(d.name), d.mobile;
end $$;

create or replace function public._crmb_customer_list(p_limit int default 5000, p_collapse boolean default false)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int, masked boolean, linked_to uuid, linked_count int)
language sql security definer set search_path = public as $$
  select * from public._crmb_customer_rows(p_limit, p_collapse, true);
$$;

-- the customer profile (customer_profile unchanged) with phone, WhatsApp and address hidden for a person who may not see them; same shape, plus masked
create or replace function public._crmb_customer_profile(p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j jsonb := public.customer_profile(p_customer); ok boolean := public._crmb_contact_ok();
begin
  if ok then
    if public.rule_on('crm_pii_guard_on') and not public.is_owner() then perform public._crmb_view_log_add(p_customer, 'profile', null, 1, null); end if;
    return j || jsonb_build_object('masked', false);
  end if;
  return jsonb_set(j, '{customer}', (j -> 'customer') || jsonb_build_object('mobile', public._crmb_mask_phone(j -> 'customer' ->> 'mobile'), 'whatsapp', public._crmb_mask_phone(j -> 'customer' ->> 'whatsapp'), 'address', null)) || jsonb_build_object('masked', true);
end $$;

-- one number, once, with a log line
create or replace function public._crmb_phone_reveal(p_customer uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; ok boolean; guard boolean := public.rule_on('crm_pii_guard_on');
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if not guard then   -- nothing is hidden today: answer, nothing to log
    return jsonb_build_object('id', c.id, 'name', c.name, 'mobile', c.mobile, 'whatsapp', c.whatsapp, 'address', c.address, 'logged', false);
  end if;
  ok := public._crmb_contact_ok();
  if not ok and not public.rule_on('crm_reveal_for_call') then raise exception 'not allowed'; end if;
  if not public.is_owner() and public.rule_on('crm_unmask_reason_required') and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if p_reason is not null and length(p_reason) > 200 then raise exception 'bad_input'; end if;
  perform public._crmb_view_log_add(c.id, case when ok then 'contact' else 'call' end, p_reason, 1, null);
  return jsonb_build_object('id', c.id, 'name', c.name, 'mobile', c.mobile, 'whatsapp', c.whatsapp, 'address', case when ok then c.address end, 'logged', true);
end $$;

create or replace function public._crmb_view_log_list(p_limit int default 100, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select v.id, v.at, v.staff_id, v.what, v.reason, v.row_count, v.customer_id, c.name as customer_name from public.crm_view_log v left join public.customers c on c.id = v.customer_id
     where p_customer is null or v.customer_id = p_customer order by v.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- export and print ----------
create or replace function public._crmb_export(p_dataset text default 'customers', p_filter jsonb default '{}'::jsonb, p_format text default 'json', p_limit int default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare maxr numeric; lim int; ok boolean; fmt text := lower(coalesce(p_format, 'json')); f jsonb := coalesce(p_filter, '{}'::jsonb); k text; rows jsonb; n int; trunc boolean; logid bigint;
        cols text[] := array['id', 'name', 'mobile', 'whatsapp', 'type', 'tier_id', 'active', 'birthday', 'anniversary', 'address', 'spend', 'orders', 'last_sale', 'points', 'balance'];
        q text; collapse boolean; csv text := ''; r jsonb; c text; line text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_export_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('crm_export')) or not public._cust_pos43() then raise exception 'not allowed'; end if;
  maxr := public.rule_num('crm_export_max_rows');
  if maxr is null then raise exception 'export_limit_not_set'; end if;
  if p_dataset is distinct from 'customers' then raise exception 'bad_dataset'; end if;
  if fmt not in ('json', 'csv') then raise exception 'bad_format'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'bad_filter'; end if;
  for k in select jsonb_object_keys(f) loop
    if k not in ('active', 'tier_id', 'type', 'has_due', 'birthday_month', 'search', 'collapse') then raise exception 'bad_filter'; end if;
  end loop;
  begin
    if f ? 'active' then perform (f ->> 'active')::boolean; end if;
    if f ? 'tier_id' then perform (f ->> 'tier_id')::bigint; end if;
    if f ? 'has_due' then perform (f ->> 'has_due')::boolean; end if;
    if f ? 'collapse' then collapse := (f ->> 'collapse')::boolean; end if;
    if f ? 'birthday_month' and ((f ->> 'birthday_month')::int not between 1 and 12) then raise exception 'x'; end if;
  exception when others then raise exception 'bad_filter';
  end;
  if f ? 'type' and (f ->> 'type') not in ('retail', 'wholesale') then raise exception 'bad_filter'; end if;
  if f ? 'search' and length(f ->> 'search') > 60 then raise exception 'bad_filter'; end if;
  if not public.is_owner() and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if p_reason is not null and length(p_reason) > 200 then raise exception 'bad_input'; end if;
  ok := public._crmb_contact_ok();
  lim := least(greatest(coalesce(p_limit, maxr::int), 1), maxr::int);
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name, 'mobile', z.mobile, 'whatsapp', z.whatsapp, 'type', z.type, 'tier_id', z.tier_id, 'active', z.active,
           'birthday', z.birthday, 'anniversary', z.anniversary, 'address', z.address, 'spend', z.spend, 'orders', z.orders, 'last_sale', z.last_sale, 'points', z.points, 'balance', z.balance)
           order by lower(z.name), z.id), '[]'::jsonb), count(*)::int
    into rows, n
    from (select x.* from public._crmb_customer_rows(20000, coalesce(collapse, false), false) x
           where (not (f ? 'active') or x.active = (f ->> 'active')::boolean)
             and (not (f ? 'tier_id') or x.tier_id = (f ->> 'tier_id')::bigint)
             and (not (f ? 'type') or x.type = f ->> 'type')
             and (not (f ? 'has_due') or (x.balance > 0) = (f ->> 'has_due')::boolean)
             and (not (f ? 'birthday_month') or extract(month from x.birthday) = (f ->> 'birthday_month')::int)
             and (not (f ? 'search') or lower(x.name) like '%' || lower(f ->> 'search') || '%' or (ok and x.mobile like '%' || (f ->> 'search') || '%'))
           order by lower(x.name), x.id limit lim + 1) z;
  trunc := n > lim;
  if trunc then rows := (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(rows) with ordinality t(e, o) order by o limit lim) y); n := lim; end if;
  if fmt = 'csv' then
    csv := (select string_agg(public._i62_csv(c2), ',') from unnest(cols) c2) || E'\n';
    for r in select * from jsonb_array_elements(rows) loop
      line := null;
      foreach c in array cols loop line := coalesce(line || ',', '') || public._i62_csv(r ->> c); end loop;
      csv := csv || line || E'\n';
    end loop;
  end if;
  insert into public.crm_export_log (user_id, staff_id, kind, what, filter, row_count, masked, format, reason)
    values (auth.uid(), public._crmb_staff(), 'export', 'customers', f, n, not ok, fmt, nullif(btrim(p_reason), '')) returning id into logid;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'export', 'customers', logid::text, jsonb_build_object('rows', n, 'masked', not ok, 'format', fmt, 'filter', f));
  return jsonb_build_object('log_id', logid, 'count', n, 'truncated', trunc, 'masked', not ok, 'format', fmt, 'columns', to_jsonb(cols),
                            'rows', case when fmt = 'json' then rows end, 'csv', case when fmt = 'csv' then csv end);
end $$;

create or replace function public._crmb_print_log(p_what text, p_count int, p_reason text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare logid bigint;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if p_what not in ('customer_list', 'customer_sheet', 'customer_labels') or p_count is null or p_count < 0 or p_count > 100000 or (p_reason is not null and length(p_reason) > 200) then raise exception 'bad_input'; end if;
  if public.rule_on('crm_print_needs_export') and not (public.is_owner() or public.has_grant('crm_export')) then raise exception 'not allowed'; end if;
  insert into public.crm_export_log (user_id, staff_id, kind, what, filter, row_count, masked, format, reason)
    values (auth.uid(), public._crmb_staff(), 'print', p_what, null, p_count, not public._crmb_contact_ok(), 'print', nullif(btrim(p_reason), '')) returning id into logid;
  return logid;
end $$;

create or replace function public._crmb_export_log_list(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (select * from public.crm_export_log order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- what may this person do right now (one call for the screens; no customer data inside) ----------
create or replace function public._crmb_policy() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ok boolean; exp boolean; cap numeric := public.rule_num('crm_export_max_rows');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ok := public._crmb_contact_ok();
  exp := public.is_owner() or public.has_grant('crm_export');
  return jsonb_build_object(
    'guard_on', public.rule_on('crm_pii_guard_on'), 'contact_ok', ok, 'mask_style', coalesce(public.rule_txt('crm_mask_style'), 'first3_last2'),
    'can_reveal', ok or (public.rule_on('crm_pii_guard_on') and public.rule_on('crm_reveal_for_call') and public._cust_pos43()),
    'reason_required', public.rule_on('crm_pii_guard_on') and public.rule_on('crm_unmask_reason_required') and not public.is_owner(),
    'export_on', public.rule_on('crm_export_on'), 'export_cap', cap, 'can_export', public.rule_on('crm_export_on') and cap is not null and exp and public._cust_pos43(),
    'print_needs_export', public.rule_on('crm_print_needs_export'), 'can_print', public._cust_pos43() and (not public.rule_on('crm_print_needs_export') or exp),
    'can_consent', public._crmb_consent_ok(), 'can_manage_consent', public._i62_ok(), 'consent_pos_on', public.rule_on('crm_consent_pos_on'),
    'dup_on', public.rule_on('crm_dup_check_on'), 'can_merge', public.is_owner() or public.has_grant('crm_merge'), 'can_link', public.rule_on('crm_dup_check_on') and (public.is_owner() or public.has_grant('crm_merge')),
    'is_owner', public.is_owner());
end $$;

-- ---------- the consent register list (names, masked phone, yes / no / not asked) ----------
create or replace function public._crmb_consent_register(p_status text default null, p_channel text default 'sms', p_search text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ok boolean := public._crmb_contact_ok(); lim int := least(greatest(coalesce(p_limit, 50), 1), 200); off int := greatest(coalesce(p_offset, 0), 0); tot int; rows jsonb; s text := nullif(btrim(p_search), '');
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_channel not in ('sms', 'whatsapp') or (p_status is not null and p_status not in ('in', 'out', 'not_asked', 'dnc')) or (s is not null and length(s) > 60) then raise exception 'bad_input'; end if;
  with base as (
    select c.id, c.name, c.mobile, coalesce(o.status, 'not_asked') st, o.changed_at, coalesce(p.dnc, false) dnc
      from public.customers c left join public.notify_optin o on o.customer_id = c.id and o.channel = p_channel left join public.crm_contact_prefs p on p.customer_id = c.id
     where c.active
       and (s is null or lower(c.name) like '%' || lower(s) || '%' or (ok and c.mobile like '%' || s || '%'))
       and (p_status is null or (p_status = 'dnc' and coalesce(p.dnc, false)) or (p_status <> 'dnc' and coalesce(o.status, 'not_asked') = p_status))),
  pg as (select * from base order by lower(name), id limit lim offset off)
  select (select count(*) from base), coalesce(jsonb_agg(jsonb_build_object('id', pg.id, 'name', pg.name, 'mobile', case when ok then pg.mobile else public._crmb_mask_phone(pg.mobile) end,
           'status', pg.st, 'at', pg.changed_at, 'dnc', pg.dnc,
           'how', (select e.how from public.crm_consent_events e where e.customer_id = pg.id and e.channel = p_channel order by e.id desc limit 1)) order by lower(pg.name), pg.id), '[]'::jsonb)
    into tot, rows from pg;
  return jsonb_build_object('total', tot, 'rows', rows, 'masked', not ok, 'summary', public._crmb_consent_summary());
end $$;

-- ---------- privileges (only the functions of THIS file) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_contact_ok', '_crmb_mask_phone', '_crmb_view_log_add', '_crmb_customer_rows', '_crmb_customer_list', '_crmb_customer_profile', '_crmb_phone_reveal', '_crmb_view_log_list',
              '_crmb_export', '_crmb_print_log', '_crmb_export_log_list', '_crmb_policy', '_crmb_consent_register']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_customer_list(int, boolean), public._crmb_customer_profile(uuid), public._crmb_phone_reveal(uuid, text), public._crmb_view_log_list(int, uuid), public._crmb_export(text, jsonb, text, int, text),
  public._crmb_print_log(text, int, text), public._crmb_export_log_list(int), public._crmb_policy(), public._crmb_consent_register(text, text, text, int, int), public._crmb_contact_ok() to authenticated;

-- Phase 301 (bos301, package CRM-A, local label 101) - CUSTOMER PROFILE PLUS: the write functions.
-- Paste AFTER phase300. Paste-twice safe. No shared function is patched or re-created; customer_save, find_customer, record_sale2 are untouched.
--
-- Every write: (1) the caller must be allowed to register customers (POS enter or customer manager) - a hidden button is also a refused request,
-- (2) the owner's switch crm_on must be ON (otherwise error crm_off and nothing is written), (3) a repeated call changes nothing (client id or natural key),
-- (4) the table audit trigger writes one change-log line. Nothing is deleted: phones, delivery points, dates, tags and notes are retired.
-- Fields that carry money terms (customer type, credit days, account owner) and the tag list need the owner or the customer manager.
-- A second phone that another customer already holds is ACCEPTED and reported (shared_with); a sale is never blocked by it.
--
--   crma_customer_extras_save(customer, {language, preferred_location_id, type_code, credit_days, owner_user}, client)
--   crma_phone_add / crma_phone_retire / crma_phone_make_primary   (extra phones; changing the main number needs a reason and the customer manager)
--   crma_address_save / crma_address_retire                         (delivery points)
--   crma_date_save / crma_date_retire                               (family dates)
--   crma_tag_save (owner or manager) / crma_tag_set
--   crma_note_add / crma_note_retire                                (needs the grant crm_view or the owner)
--   crma_phone_reveal(customer, reason)                             (a masked caller gets the number once; one change-log line)

do $g$ begin
  if to_regprocedure('public._crma_present()') is null then raise exception 'phase301 needs phase300 first'; end if;
end $g$;

create or replace function public._crma_gate() returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._crma_write_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
end $$;

create or replace function public._crma_int(p jsonb, k text, p_min numeric, p_max numeric) returns integer
language plpgsql immutable set search_path = public as $$
declare n numeric := public._n43(p, k, p_min, p_max);
begin
  if n is not null and n <> floor(n) then raise exception 'bad_number'; end if;
  return n::int;
end $$;

create or replace function public._crma_audit(p_action text, p_table text, p_record text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_record, p_detail);
end $$;

-- ---------- profile extras on the customer row ----------
create or replace function public.crma_customer_extras_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; k text; mgr boolean; v text;
  lang text; loc int; tc text; cd int; ou uuid;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('language', 'preferred_location_id', 'type_code', 'credit_days', 'owner_user') then raise exception 'unknown_key: %', k; end if;
  end loop;
  mgr := public._cust_mgr43();
  if (p ? 'type_code' or p ? 'credit_days' or p ? 'owner_user') and not mgr then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into c from public.customers where id = p_id for update;
  if not found then raise exception 'customer_not_found'; end if;
  lang := c.language; loc := c.preferred_location_id; tc := c.type_code; cd := c.credit_days; ou := c.owner_user;
  if p ? 'language' then
    v := nullif(btrim(coalesce(p ->> 'language', '')), '');
    if v is not null and v not in ('bn', 'en') then raise exception 'bad_value'; end if;
    lang := v;
  end if;
  if p ? 'preferred_location_id' then
    v := nullif(btrim(coalesce(p ->> 'preferred_location_id', '')), '');
    if v is null then loc := null;
    else
      begin loc := v::int; exception when others then raise exception 'bad_value'; end;
      if not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'location_not_found'; end if;
    end if;
  end if;
  if p ? 'type_code' then
    v := nullif(btrim(coalesce(p ->> 'type_code', '')), '');
    if v is not null and not exists (select 1 from public.option_lists where list_code = 'customer_types' and value_code = v and active) then raise exception 'type_not_found'; end if;
    tc := v;
  end if;
  if p ? 'credit_days' then
    cd := public._crma_int(p, 'credit_days', 0, 365);
  end if;
  if p ? 'owner_user' then
    v := nullif(btrim(coalesce(p ->> 'owner_user', '')), '');
    if v is null then ou := null;
    else
      begin ou := v::uuid; exception when others then raise exception 'bad_value'; end;
      if not exists (select 1 from public.profiles where id = ou and status = 'active') then raise exception 'user_not_found'; end if;
    end if;
  end if;
  update public.customers set language = lang, preferred_location_id = loc, type_code = tc, credit_days = cd, owner_user = ou where id = p_id;
  return jsonb_build_object('id', p_id, 'saved', true);
end $$;

-- ---------- extra phones ----------
create or replace function public._crma_phone_holders(p_phone text, p_except uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name) order by z.name), '[]'::jsonb)
  from (select c.id, c.name from public.customers c where c.mobile = p_phone and c.id is distinct from p_except
        union select c.id, c.name from public.customer_phones ph join public.customers c on c.id = ph.customer_id where ph.phone = p_phone and ph.active and c.id is distinct from p_except) z;
$$;

create or replace function public.crma_phone_add(p_customer uuid, p_phone text, p_label text default 'mobile', p_wa boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; ph text; lb text := coalesce(nullif(btrim(p_label), ''), 'mobile'); r public.customer_phones; sh jsonb; nt text := left(nullif(btrim(coalesce(p_note, '')), ''), 100);
begin
  perform public._crma_gate();
  if not public.rule_on('crm_second_phone_on') then raise exception 'second_phone_off'; end if;
  if lb not in ('mobile', 'home', 'work', 'other') then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.customer_phones where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'customer_id', r.customer_id); end if;
  end if;
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if nullif(btrim(coalesce(p_phone, '')), '') is null then raise exception 'bad_mobile'; end if;
  ph := public.norm_mobile(p_phone);                                        -- raises bad_mobile
  if ph = c.mobile then return jsonb_build_object('dup', true, 'primary', true, 'customer_id', c.id); end if;
  select * into r from public.customer_phones where customer_id = c.id and phone = ph and active;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'customer_id', c.id); end if;
  if (select count(*) from public.customer_phones where customer_id = c.id and active) >= 10 then raise exception 'too_many_phones'; end if;
  insert into public.customer_phones (customer_id, phone, label, wa_ok, note, client_id, created_by)
    values (c.id, ph, lb, coalesce(p_wa, false), nt, p_client, auth.uid()) returning * into r;
  sh := public._crma_phone_holders(ph, c.id);
  return jsonb_build_object('dup', false, 'id', r.id, 'customer_id', c.id, 'shared_with', sh, 'warning', case when jsonb_array_length(sh) > 0 then 'phone_shared' end);
end $$;

create or replace function public.crma_phone_retire(p_phone_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_phones;
begin
  perform public._crma_gate();
  select * into r from public.customer_phones where id = p_phone_id for update;
  if not found then raise exception 'phone_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_phones set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- the main number (customers.mobile, the key POS and record_sale2 use) is swapped with an extra number: manager only, with a reason, one change-log line.
-- The old main number stays on the profile as an extra number. A number that is the main number of ANOTHER customer is refused (the key is unique).
create or replace function public.crma_phone_make_primary(p_phone_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_phones; c public.customers; why text := left(btrim(coalesce(p_reason, '')), 300); old text;
begin
  perform public._crma_gate();
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.customer_phones where id = p_phone_id for update;
  if not found or not r.active then raise exception 'phone_not_found'; end if;
  select * into c from public.customers where id = r.customer_id for update;
  if exists (select 1 from public.customers x where x.mobile = r.phone and x.id <> c.id) then raise exception 'mobile_taken'; end if;
  old := c.mobile;
  update public.customer_phones set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  update public.customers set mobile = r.phone where id = c.id;
  insert into public.customer_phones (customer_id, phone, label, wa_ok, note, created_by) values (c.id, old, 'other', false, 'was the main number', auth.uid())
    on conflict (customer_id, phone) where active do nothing;
  perform public._crma_audit('crm_primary_phone_changed', 'customers', c.id::text, jsonb_build_object('from', old, 'to', r.phone, 'reason', why));
  return jsonb_build_object('id', c.id, 'mobile', r.phone, 'old_mobile', old);
end $$;

-- ---------- delivery points ----------
create or replace function public.crma_address_save(p_customer uuid, p jsonb, p_id bigint default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; a public.customer_addresses; r public.customer_addresses; lb text; ad text; ar text; lm text; dn text; df boolean;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('label', 'address', 'area', 'landmark', 'delivery_note', 'is_default') then raise exception 'unknown_key: %', k; end if;
  end loop;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.customer_addresses where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into a from public.customer_addresses where false;
  if p_id is not null then
    select * into a from public.customer_addresses where id = p_id and customer_id = p_customer and active for update;
    if not found then raise exception 'address_not_found'; end if;
  end if;
  lb := case when p ? 'label' then coalesce(nullif(btrim(p ->> 'label'), ''), 'home') else coalesce(a.label, 'home') end;
  if lb not in ('home', 'office', 'gift', 'other') then raise exception 'bad_value'; end if;
  ad := case when p ? 'address' then left(btrim(coalesce(p ->> 'address', '')), 200) else a.address end;
  if ad is null or ad = '' then raise exception 'address_required'; end if;
  ar := case when p ? 'area' then left(nullif(btrim(coalesce(p ->> 'area', '')), ''), 80) else a.area end;
  lm := case when p ? 'landmark' then left(nullif(btrim(coalesce(p ->> 'landmark', '')), ''), 120) else a.landmark end;
  dn := case when p ? 'delivery_note' then left(nullif(btrim(coalesce(p ->> 'delivery_note', '')), ''), 200) else a.delivery_note end;
  df := case when p ? 'is_default' then coalesce((p ->> 'is_default')::boolean, false) else coalesce(a.is_default, false) end;
  if p_id is null then
    select * into r from public.customer_addresses where customer_id = p_customer and active and lower(address) = lower(ad) and coalesce(lower(area), '') = coalesce(lower(ar), '');
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
    if (select count(*) from public.customer_addresses where customer_id = p_customer and active) >= 20 then raise exception 'too_many_addresses'; end if;
    if df then update public.customer_addresses set is_default = false where customer_id = p_customer and is_default and active; end if;
    insert into public.customer_addresses (customer_id, label, address, area, landmark, delivery_note, is_default, client_id, created_by)
      values (p_customer, lb, ad, ar, lm, dn, df, p_client, auth.uid()) returning * into r;
    return jsonb_build_object('dup', false, 'id', r.id);
  end if;
  if df then update public.customer_addresses set is_default = false where customer_id = p_customer and is_default and active and id <> p_id; end if;
  update public.customer_addresses set label = lb, address = ad, area = ar, landmark = lm, delivery_note = dn, is_default = df where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.crma_address_retire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_addresses;
begin
  perform public._crma_gate();
  select * into r from public.customer_addresses where id = p_id for update;
  if not found then raise exception 'address_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_addresses set active = false, is_default = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- family dates ----------
create or replace function public.crma_date_save(p_customer uuid, p jsonb, p_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; d public.customer_dates; r public.customer_dates; kd text; pl text; m int; dd int; y int; rb int;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('kind', 'person_label', 'month', 'day', 'year', 'remind_days_before') then raise exception 'unknown_key: %', k; end if;
  end loop;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into d from public.customer_dates where false;
  if p_id is not null then
    select * into d from public.customer_dates where id = p_id and customer_id = p_customer and active for update;
    if not found then raise exception 'date_not_found'; end if;
  end if;
  kd := case when p ? 'kind' then nullif(btrim(p ->> 'kind'), '') else d.kind end;
  if kd is null or kd not in ('birthday', 'anniversary', 'other') then raise exception 'bad_value'; end if;
  pl := case when p ? 'person_label' then left(btrim(coalesce(p ->> 'person_label', '')), 40) else d.person_label end;
  if pl is null or pl = '' then raise exception 'person_required'; end if;
  m := case when p ? 'month' then public._crma_int(p, 'month', 1, 12) else d.month end;
  dd := case when p ? 'day' then public._crma_int(p, 'day', 1, 31) else d.day end;
  if m is null or dd is null or not public._crma_valid_md(m, dd) then raise exception 'bad_date'; end if;
  if p ? 'year' then y := public._crma_int(p, 'year', 1900, 2100); else y := d.year; end if;
  if y is not null and make_date(y, m, case when m = 2 and dd = 29 and not (y % 4 = 0 and (y % 100 <> 0 or y % 400 = 0)) then 28 else dd end) > public._today43() then raise exception 'bad_date'; end if;
  if p ? 'remind_days_before' then rb := public._crma_int(p, 'remind_days_before', 0, 60); else rb := d.remind_days_before; end if;
  select * into r from public.customer_dates where customer_id = p_customer and active and kind = kd and lower(person_label) = lower(pl) and month = m and day = dd and id is distinct from p_id;
  if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if p_id is null then
    if (select count(*) from public.customer_dates where customer_id = p_customer and active) >= 30 then raise exception 'too_many_dates'; end if;
    insert into public.customer_dates (customer_id, kind, person_label, month, day, year, remind_days_before, created_by) values (p_customer, kd, pl, m, dd, y, rb, auth.uid()) returning * into r;
    return jsonb_build_object('dup', false, 'id', r.id);
  end if;
  update public.customer_dates set kind = kd, person_label = pl, month = m, day = dd, year = y, remind_days_before = rb where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.crma_date_retire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_dates;
begin
  perform public._crma_gate();
  select * into r from public.customer_dates where id = p_id for update;
  if not found then raise exception 'date_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_dates set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- tags ----------
create or replace function public.crma_tag_save(p_id bigint, p_code text, p_label text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tags; lb text := left(btrim(coalesce(p_label, '')), 40);
begin
  if not (public.is_active() and (public.is_owner() or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if lb = '' then raise exception 'name_required'; end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.crm_tags where code = p_code) then raise exception 'code_exists'; end if;
    insert into public.crm_tags (code, label, active, created_by) values (p_code, lb, coalesce(p_active, true), auth.uid()) returning * into t;
  else
    select * into t from public.crm_tags where id = p_id for update;
    if not found then raise exception 'tag_not_found'; end if;
    update public.crm_tags set label = lb, active = coalesce(p_active, active) where id = p_id returning * into t;
  end if;
  return jsonb_build_object('id', t.id, 'code', t.code, 'label', t.label, 'active', t.active);
end $$;

create or replace function public.crma_tag_set(p_customer uuid, p_tag bigint, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tags; r public.customer_tags;
begin
  perform public._crma_gate();
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into t from public.crm_tags where id = p_tag;
  if not found then raise exception 'tag_not_found'; end if;
  select * into r from public.customer_tags where customer_id = p_customer and tag_id = p_tag for update;
  if coalesce(p_on, true) then
    if not t.active then raise exception 'tag_not_found'; end if;
    if found and r.active then return jsonb_build_object('dup', true); end if;
    if found then update public.customer_tags set active = true, added_by = auth.uid(), added_at = now(), removed_by = null, removed_at = null where customer_id = p_customer and tag_id = p_tag;
    else insert into public.customer_tags (customer_id, tag_id, added_by) values (p_customer, p_tag, auth.uid()); end if;
    return jsonb_build_object('dup', false, 'on', true);
  end if;
  if not found or not r.active then return jsonb_build_object('dup', true); end if;
  update public.customer_tags set active = false, removed_by = auth.uid(), removed_at = now() where customer_id = p_customer and tag_id = p_tag;
  return jsonb_build_object('dup', false, 'on', false);
end $$;

-- ---------- notes ----------
create or replace function public.crma_note_add(p_customer uuid, p_body text, p_kind text default 'note', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.crm_notes; b text := left(btrim(coalesce(p_body, '')), 1000); kd text := coalesce(nullif(btrim(p_kind), ''), 'note');
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if b = '' then raise exception 'note_required'; end if;
  if kd not in ('note', 'call', 'visit', 'message', 'other') then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.crm_notes where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  insert into public.crm_notes (customer_id, kind, body, client_id, created_by, created_staff)
    values (p_customer, kd, b, p_client, auth.uid(), (select staff_id from public.profiles where id = auth.uid())) returning * into r;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

create or replace function public.crma_note_retire(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.crm_notes; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.crm_notes where id = p_id for update;
  if not found then raise exception 'note_not_found'; end if;
  if r.retired_at is not null then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if not (public.is_owner() or r.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  update public.crm_notes set retired_at = now(), retired_by = auth.uid(), retire_reason = why where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- a masked caller gets the number once, with a reason, and it is written to the change log ----------
create or replace function public.crma_phone_reveal(p_customer uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if public._crma_show_phone() then return jsonb_build_object('mobile', c.mobile, 'whatsapp', c.whatsapp, 'logged', false); end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  perform public._crma_audit('crm_phone_reveal', 'customers', c.id::text, jsonb_build_object('reason', why));
  return jsonb_build_object('mobile', c.mobile, 'whatsapp', c.whatsapp, 'logged', true);
end $$;

-- ---------- find a customer by ANY of their numbers (for a hook in the POS lookup; find_customer itself is not changed) ----------
-- The cashier typed one of this customer's own numbers, and the sale needs the main number to attach to the right customer, so the main number is returned in full
-- (the same exposure find_customer already has for a typed number). Name and balance are what find_customer returns today.
create or replace function public.crma_find_by_any_phone(p_phone text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text; c public.customers; n int; via text := 'mobile';
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  m := public.norm_mobile(p_phone);
  select * into c from public.customers where mobile = m;
  if not found then
    select count(distinct ph.customer_id) into n from public.customer_phones ph where ph.phone = m and ph.active;
    if n = 0 then return jsonb_build_object('mobile', m, 'found', false); end if;
    select cu.* into c from public.customer_phones ph join public.customers cu on cu.id = ph.customer_id where ph.phone = m and ph.active order by cu.active desc, cu.created_at limit 1;
    via := 'extra_phone';
  else n := 1; end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', c.mobile, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit,
    'balance', public.customer_balance(c.id), 'via', via, 'matches', n, 'ambiguous', n > 1);
end $$;

-- ---------- possible duplicates caused by extra phones (manager / owner) ----------
create or replace function public.crma_phone_conflicts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('phone', public._crma_ph(z.phone), 'customers', z.cs) order by z.phone)
    from (select a.phone, jsonb_agg(distinct jsonb_build_object('id', a.cid, 'name', a.name)) cs
          from (select c.mobile phone, c.id cid, c.name from public.customers c
                union all select ph.phone, c.id, c.name from public.customer_phones ph join public.customers c on c.id = ph.customer_id where ph.active) a
          group by a.phone having count(distinct a.cid) > 1) z), '[]'::jsonb);
end $$;

-- ---------- permissions: browser-callable vs internal ----------
revoke all on function public._crma_gate(), public._crma_int(jsonb, text, numeric, numeric), public._crma_audit(text, text, text, jsonb), public._crma_phone_holders(text, uuid) from public, anon, authenticated;
revoke all on function public.crma_customer_extras_save(uuid, jsonb, uuid), public.crma_phone_add(uuid, text, text, boolean, text, uuid), public.crma_phone_retire(bigint),
  public.crma_phone_make_primary(bigint, text), public.crma_address_save(uuid, jsonb, bigint, uuid), public.crma_address_retire(bigint), public.crma_date_save(uuid, jsonb, bigint),
  public.crma_date_retire(bigint), public.crma_tag_save(bigint, text, text, boolean), public.crma_tag_set(uuid, bigint, boolean), public.crma_note_add(uuid, text, text, uuid),
  public.crma_note_retire(bigint, text), public.crma_phone_reveal(uuid, text), public.crma_find_by_any_phone(text), public.crma_phone_conflicts() from public, anon;
grant execute on function public.crma_customer_extras_save(uuid, jsonb, uuid), public.crma_phone_add(uuid, text, text, boolean, text, uuid), public.crma_phone_retire(bigint),
  public.crma_phone_make_primary(bigint, text), public.crma_address_save(uuid, jsonb, bigint, uuid), public.crma_address_retire(bigint), public.crma_date_save(uuid, jsonb, bigint),
  public.crma_date_retire(bigint), public.crma_tag_save(bigint, text, text, boolean), public.crma_tag_set(uuid, bigint, boolean), public.crma_note_add(uuid, text, text, uuid),
  public.crma_note_retire(bigint, text), public.crma_phone_reveal(uuid, text), public.crma_find_by_any_phone(text), public.crma_phone_conflicts() to authenticated;

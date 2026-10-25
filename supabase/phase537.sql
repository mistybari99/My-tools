-- Phase 537 (UNION-9: the advanced line's logic in 32 shared functions (location_save ... recipe_yield_suggestion) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
-- What: the advanced line changed these functions after phase 79 (rules, scope, audit, templates, cost, ...). Pasting the early phases (8 to 79) again, as the owner's earlier paste of
--   our line did, puts their older text back and the advanced logic is silently gone. A database that was built by pasting the advanced phases and then ONE run of our phases
--   never loses it (this is how the fresh build is ordered), so on a fresh build this file does nothing.
-- What this file does: for every function listed, if its text is a KNOWN older text (the base text of phases 8-79, or the text of the earlier live paste, recognised by md5), it is replaced by the merged
--   text (the advanced text, our line did not change these functions); the old text is saved in public._union_fn_backup first. An unknown text is never overwritten: all such functions are
--   listed in one message and nothing is changed. Nothing here adds a switch or changes a default.
-- Paste AFTER phase534 and after phase 505. Safe to paste twice.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- location_save(integer,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.location_save(integer,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.location_save(p_id integer, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.locations; v_code text; base text; n int := 1; v text; k text; sb int; hops int := 0; nid int; po date; sortv int; hubv boolean;
  newname_bn text; newname_en text;
begin
  if p_id is null then
    if not (public._loc_mgr() or public._pc_ok135()) then raise exception 'not allowed'; end if;   /* loc135 */
  elsif not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_patch'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name_bn', 'name_mix', 'name_en', 'kind', 'model', 'supplied_by', 'planned_opening', 'hub_functions', 'note', 'sort', 'code') then raise exception 'unknown_field:%', k; end if;
  end loop;
  if p_patch ? 'code' and p_id is not null and (p_patch->>'code') is distinct from (select l.code from public.locations l where l.id = p_id) then raise exception 'code is immutable'; end if;
  if p_patch ? 'kind' and nullif(p_patch->>'kind', '') is not null and (p_patch->>'kind') not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  if p_patch ? 'model' and nullif(p_patch->>'model', '') is not null
     and not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = p_patch->>'model' and o.active) then raise exception 'bad_model'; end if;
  foreach v in array array['name_bn', 'name_mix', 'name_en', 'note'] loop
    if p_patch ? v and length(coalesce(p_patch->>v, '')) > (case when v = 'note' then 500 else 120 end) then raise exception 'too_long:%', v; end if;
  end loop;
  -- casts: a bad text is a friendly code, never a raw cast error
  if p_patch ? 'planned_opening' and nullif(p_patch->>'planned_opening', '') is not null then
    begin po := (p_patch->>'planned_opening')::date; exception when others then raise exception 'bad_date'; end;
    if po < date '2000-01-01' or po > date '2100-01-01' then raise exception 'bad_date'; end if;
  end if;
  if p_patch ? 'sort' and nullif(p_patch->>'sort', '') is not null then
    begin sortv := (p_patch->>'sort')::int; exception when others then raise exception 'bad_number'; end;
    if not (sortv between 0 and 9999) then raise exception 'bad_number'; end if;
  end if;
  if p_patch ? 'hub_functions' then
    begin hubv := coalesce((p_patch->>'hub_functions')::boolean, false); exception when others then raise exception 'bad_value'; end;
  end if;
  if p_patch ? 'supplied_by' and nullif(p_patch->>'supplied_by', '') is not null then
    begin sb := (p_patch->>'supplied_by')::int; exception when others then raise exception 'bad_number'; end;
    if not exists (select 1 from public.locations where id = sb) then raise exception 'unknown_supplier_location'; end if;
    if p_id is null or sb is distinct from (select l.supplied_by from public.locations l where l.id = p_id) then
      if not exists (select 1 from public.locations where id = sb and is_active and status <> 'closed') then raise exception 'supplier_not_active'; end if;
    end if;
    if p_id is not null then
      if sb = p_id then raise exception 'supplied_by_itself'; end if;
      -- no loop: walk up the supplied_by chain of the chosen supplier
      declare walk int := sb;
      begin
        loop
          select l.supplied_by into walk from public.locations l where l.id = walk; hops := hops + 1;
          exit when walk is null or hops > 20;
          if walk = p_id then raise exception 'supplied_by_loop'; end if;
        end loop;
      end;
    end if;
  end if;

  if p_id is null then
    perform pg_advisory_xact_lock(1600);
    newname_bn := nullif(btrim(coalesce(p_patch->>'name_bn', '')), ''); newname_en := nullif(btrim(coalesce(p_patch->>'name_en', '')), '');
    if newname_bn is null and newname_en is null then raise exception 'name_required'; end if;
    if newname_bn is null then newname_bn := newname_en; end if;
    if exists (select 1 from public.locations x where (not public._pc_ok135() or public._business_of_unit123(x.org_unit_id) is not distinct from public._pc_biz135())
                  and (lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en)))) then raise exception 'name_in_use'; end if;
    if nullif(p_patch->>'code', '') is not null then
      v_code := p_patch->>'code';
      if v_code !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
      if exists (select 1 from public.locations x where x.code = v_code) then raise exception 'code_in_use'; end if;
    else
      base := public._slug(coalesce(newname_en, ''));
      if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'loc'; end if;
      v_code := base;
      while exists (select 1 from public.locations x where x.code = v_code) loop n := n + 1; v_code := left(base, 26) || '_' || n; end loop;
    end if;
    insert into public.locations (code, name_bn, name_mix, name_en, sort, is_active, kind, model, status, supplied_by, planned_opening, hub_functions, note, created_by, created_at, status_by, status_at, org_unit_id)
    values (v_code, newname_bn, nullif(btrim(coalesce(p_patch->>'name_mix', '')), ''), newname_en,
            coalesce(sortv, (select coalesce(max(x.sort), 0) + 1 from public.locations x)), true,
            coalesce(nullif(p_patch->>'kind', ''), 'showroom'), coalesce(nullif(p_patch->>'model', ''), 'A'), 'planned', sb, po,
            coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now(), public._pc_unit135())
    returning id into nid;
    perform public._loc_steps_seed(nid);
    update public.location_setup_steps set done = true, done_by = auth.uid(), done_at = now(), note = 'created with the place' where location_id = nid and step_no = 2;
    perform public._sheet_sync_due();
    return jsonb_build_object('id', nid, 'code', v_code, 'created', true);
  end if;

  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  -- a rename may not collide with another place
  if p_patch ? 'name_bn' and nullif(btrim(p_patch->>'name_bn'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(x.name_bn)) = lower(btrim(p_patch->>'name_bn'))) then raise exception 'name_in_use'; end if;
  if p_patch ? 'name_en' and nullif(btrim(p_patch->>'name_en'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(coalesce(x.name_en, ''))) = lower(btrim(p_patch->>'name_en'))) then raise exception 'name_in_use'; end if;
  update public.locations l set
    name_bn = case when p_patch ? 'name_bn' then coalesce(nullif(btrim(p_patch->>'name_bn'), ''), l.name_bn) else l.name_bn end,
    name_mix = case when p_patch ? 'name_mix' then nullif(btrim(p_patch->>'name_mix'), '') else l.name_mix end,
    name_en = case when p_patch ? 'name_en' then nullif(btrim(p_patch->>'name_en'), '') else l.name_en end,
    kind = case when p_patch ? 'kind' then coalesce(nullif(p_patch->>'kind', ''), l.kind) else l.kind end,
    model = case when p_patch ? 'model' then coalesce(nullif(p_patch->>'model', ''), l.model) else l.model end,
    supplied_by = case when p_patch ? 'supplied_by' then sb else l.supplied_by end,
    planned_opening = case when p_patch ? 'planned_opening' then po else l.planned_opening end,
    hub_functions = case when p_patch ? 'hub_functions' then coalesce(hubv, false) else l.hub_functions end,
    note = case when p_patch ? 'note' then nullif(p_patch->>'note', '') else l.note end,
    sort = coalesce(sortv, l.sort)
  where l.id = p_id;
  perform public._sheet_sync_due();
  return jsonb_build_object('id', p_id, 'code', r.code, 'created', false);
end $function$$r0_0$, null),
  ('public.location_save(integer,jsonb)', 'known', '58511c50bddf09406120f1e54f10affb', null);
-- login_failed(text)
insert into _u_plan (fn, kind, a, b) values
  ('public.login_failed(text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.login_failed(p_staff text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s text := left(lower(btrim(coalesce(p_staff, ''))), 64); mx int := public._login_setting_num('max_fails', 5)::int;
        lm int := public._login_setting_num('lock_minutes', 10)::int; known boolean; f public.login_failures; nf int;
begin
  if s = '' then return; end if;
  select exists (select 1 from public.profiles where staff_id = s) into known;
  -- spam guard: unknown ids share ONE global bucket; known ids get 50 log rows per minute each. Unknown/known look the same to the caller.
  if not public._login_throttle(case when known then 'sid:' || s else 'unknown' end, case when known then 20 else 60 end) then return; end if;
  insert into public.login_attempts (staff_id, ok, ip_hint) values (s, false, null);
  if not known and not public._org_on123() then return; end if;   /* scope133 */
  if not known and random() < 0.02 then delete from public.login_failures lf where lf.last_fail < now() - interval '1 day' and not exists (select 1 from public.profiles p where p.staff_id = lf.staff_id); end if;
  select * into f from public.login_failures where staff_id = s for update;
  if not found then
    insert into public.login_failures (staff_id, fails, locked, locked_until, window_start, last_fail)
      values (s, 1, 1 >= mx, case when 1 >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) end, now(), now())
    on conflict (staff_id) do nothing;
    return;
  end if;
  if f.locked then
    if f.locked_until is not null and f.locked_until <= now() and public._login_auto_release_for(s) then
      update public.login_failures set fails = 1, locked = (1 >= mx), locked_until = case when 1 >= mx then now() + make_interval(mins => lm) end,
        window_start = now(), last_fail = now() where staff_id = s;
    else
      update public.login_failures set last_fail = now() where staff_id = s;   -- still locked: attempts do not extend the lock
    end if;
    return;
  end if;
  if f.window_start < now() - make_interval(mins => lm) then nf := 1; else nf := f.fails + 1; end if;
  update public.login_failures set
    fails = nf, last_fail = now(),
    window_start = case when nf = 1 then now() else f.window_start end,
    locked = nf >= mx,
    locked_until = case when nf >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) else null end
  where staff_id = s;
end $function$$r0_0$, null),
  ('public.login_failed(text)', 'known', 'a929eef6ffcf32ba491b2cc217431d19', null);
-- loyalty_award(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.loyalty_award(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.loyalty_award(p_sale uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; c public.customers; t public.customer_tiers; per numeric; pts int;
begin
  if not public.rule_on('loyalty_points_on') then return 0; end if;
  select * into s from public.sales where id = p_sale;
  if not found or s.customer_id is null or s.status <> 'done' then return 0; end if;
  select * into c from public.customers where id = s.customer_id and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  select * into t from public.customer_tiers where id = c.tier_id;
  per := coalesce(public.rule_num('points_per_100_taka'), 0);
  pts := floor(s.total * per * coalesce(t.points_multiplier, 1) / 100)::int;
  if pts <= 0 then return 0; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, note, by_user, by_staff)
    values (s.customer_id, pts, 'sale', s.id, 'receipt ' || s.receipt, s.created_by, s.created_staff) on conflict do nothing;
  return pts;
end $function$$r0_0$, null),
  ('public.loyalty_award(uuid)', 'known', '5950eb1b451e317891ccff29872a75b2', null);
-- notify_cancel(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_cancel(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_cancel(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  update public.notify_outbox set status = 'cancelled', last_error = 'cancelled_by_staff' where id = p_id and status in ('queued', 'failed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_cancellable'; end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $function$$r0_0$, null),
  ('public.notify_cancel(bigint)', 'known', '76c97ec512ce0bb5005685b1bc2067fc', null);
-- notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_enqueue(p_client uuid, p_customer uuid, p_channel text, p_template text, p_vars jsonb DEFAULT '{}'::jsonb, p_lang text DEFAULT 'bn'::text, p_source_type text DEFAULT NULL::text, p_source_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.notify_templates; c public.customers; ph text; b text; k text; v text; ex public.notify_outbox; nid bigint; mt int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then raise exception 'sms_off'; end if;
  if p_client is null or p_customer is null or p_channel not in ('sms', 'whatsapp') or p_template is null or coalesce(p_lang, 'bn') not in ('bn', 'en')
     or (p_vars is not null and jsonb_typeof(p_vars) <> 'object') or (p_source_type is null) <> (p_source_id is null)
     or (p_source_type is not null and (length(p_source_type) > 40 or length(p_source_id) > 80)) then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.notify_outbox where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  select * into t from public.notify_templates where code = p_template and active;
  if not found then raise exception 'template_not_found'; end if;
  if t.channel <> p_channel then raise exception 'template_channel_mismatch'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found then raise exception 'customer_not_found'; end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
  perform public._crmb_enqueue_guard(p_customer, p_channel); /* bosCRMB: do-not-contact and linked duplicates */
  ph := public._i62_phone(c.mobile);
  if ph is null then raise exception 'bad_phone'; end if;
  b := case when coalesce(p_lang, 'bn') = 'en' then t.body_en else t.body_bn end;
  b := replace(b, '{name}', coalesce(left(c.name, 60), ''));
  for k, v in select key, left(value, 100) from jsonb_each_text(coalesce(p_vars, '{}'::jsonb)) loop
    if k ~ '^[a-z_]{1,20}$' then b := replace(b, '{' || k || '}', v); end if;
  end loop;
  b := regexp_replace(b, '\{[a-z_]{1,20}\}', '', 'g');
  if length(btrim(b)) not between 1 and 480 then raise exception 'bad_body'; end if;
  mt := greatest(least(coalesce(public.rule_num('notify_sms_max_tries'), 5)::int, 20), 1);
  begin
    insert into public.notify_outbox (client_id, customer_id, channel, to_phone, template_code, body, max_attempts, source_type, source_id, created_by)
      values (p_client, p_customer, p_channel, ph, p_template, btrim(b), mt, p_source_type, p_source_id, auth.uid()) returning id into nid;
  exception when unique_violation then
    select * into ex from public.notify_outbox where source_type = p_source_type and source_id = p_source_id and template_code = p_template;
    return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true);
  end;
  return jsonb_build_object('id', nid, 'status', 'queued', 'duplicate', false);
end $function$$r0_0$, null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', '00b01af71f9ed0b0bd9559c027d36136', null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', '81352a4d7577e6ff89e7972e36fe1dbe', null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', 'f2e44de25e88a7c5a3535c18aa38d3f5', null);
-- notify_optin_set(uuid,text,boolean,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_optin_set(p_customer uuid, p_channel text, p_in boolean, p_source text DEFAULT 'owner_entry'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_customer is null or p_in is null or p_channel not in ('sms', 'whatsapp') or coalesce(p_source, 'owner_entry') not in ('customer_consent', 'owner_entry')
     or (p_note is not null and length(p_note) > 200) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */) then raise exception 'customer_not_found'; end if;
  if p_in and public._i62_phone((select mobile from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */)) is null then raise exception 'bad_phone'; end if;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid());
  perform public._crmb_legacy_evidence(p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note); /* bosCRMB: evidence line */
  if not p_in then   -- opting out cancels what is still waiting
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st);
end $function$$r0_0$, null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '2dc63a9a540cd9afa90c223b7c33101c', null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '52eb8bb18690f687a54cdaf3d1e23b86', null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '530a8f4475d3c1670ccc4c4473aa7287', null);
-- notify_outbox_summary()
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_outbox_summary()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_outbox_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('notify_sms_on'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.notify_outbox group by status) s), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts, 'template', template_code,
        'to', left(to_phone, 6) || '****' || right(to_phone, 2), 'last_error', last_error, 'created_at', created_at, 'sent_at', sent_at) order by id desc)
        from (select * from public.notify_outbox order by id desc limit 50) r), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.notify_outbox_summary()', 'known', '811e64958974acb57eab987fccf9b41e', null);
-- online_order_get(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_order_get(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
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
end $function$$r0_0$, null),
  ('public.online_order_get(uuid)', 'known', 'e6647b83d678b5c736619267f7a043b8', null);
-- online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_order_save(p_id uuid, p_client uuid, p_loc integer, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb, p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.online_orders; nl jsonb; sub numeric; n int; mob text; chg numeric := coalesce(p_charge, 0); dsc numeric := coalesce(p_discount, 0); adv numeric := coalesce(p_advance, 0); loc int := p_loc; sid text;
begin
  if p_id is not null then
    select * into o from public.online_orders where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
  else
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into o from public.online_orders where client_id = p_client and created_by = auth.uid();
      if found then return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'dup', true); end if;
    end if;
  end if;
  perform public._oo_gate80(loc, p_id is null);      -- bos80: the dedicated intake bot may CREATE an order, never edit one
  if p_id is not null and o.status not in ('new', 'confirmed') then raise exception 'order_closed: only a new or confirmed order can be edited'; end if;
  if p_channel not in ('website', 'facebook', 'instagram', 'whatsapp', 'phone', 'foodapp', 'other') then raise exception 'bad_channel'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 80 then raise exception 'customer_name_required'; end if;
  mob := public.norm_mobile(p_mobile);
  if mob is null or char_length(mob) < 6 then raise exception 'bad_mobile'; end if;
  if p_delivery_mode not in ('pickup', 'home', 'courier') then raise exception 'bad_delivery_mode'; end if;
  if p_delivery_mode <> 'pickup' and nullif(btrim(p_address), '') is null then raise exception 'address_required'; end if;
  if char_length(coalesce(p_address, '')) > 300 or char_length(coalesce(p_note, '')) > 300 or char_length(coalesce(p_delivery_by, '')) > 60 then raise exception 'too_long'; end if;
  if p_delivery_date is not null and not (p_delivery_date between public._dhaka_today() - 1 and public._dhaka_today() + 365) then raise exception 'bad_date'; end if;
  if chg = 'NaN'::numeric or chg < 0 or chg > 1000000 then raise exception 'bad_amount'; end if;
  if dsc = 'NaN'::numeric or dsc < 0 or adv = 'NaN'::numeric or adv < 0 then raise exception 'bad_amount'; end if;
  nl := public._oo_lines61(p_lines); sub := (nl->>'subtotal')::numeric;
  dsc := round(dsc, 2); adv := round(adv, 2); chg := round(chg, 2);
  if dsc > sub then raise exception 'bad_discount'; end if;
  if adv > sub - dsc + chg then raise exception 'advance_over_total'; end if;
  if adv > 0 and coalesce(p_adv_mode, '') not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
  if adv = 0 then p_adv_mode := null; p_adv_wallet := null; end if;
  if p_id is null then
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.serials (form_code, location_id, last) values ('ORD', loc, 1)
      on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
    insert into public.online_orders (client_id, order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_by, delivery_date,
        delivery_charge, advance, advance_mode, advance_wallet, note, created_by, created_staff)
      values (p_client, n, loc, p_channel, left(btrim(p_name), 80), mob, nullif(btrim(p_address), ''), nl->'lines', sub, dsc, p_delivery_mode, nullif(btrim(p_delivery_by), ''), p_delivery_date,
        chg, adv, p_adv_mode, left(nullif(btrim(p_adv_wallet), ''), 30), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into o;
    perform public._oo_event61(o.id, null, 'new', 'created');
    return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
  end if;
  update public.online_orders set channel = p_channel, customer_name = left(btrim(p_name), 80), customer_mobile = mob, address = nullif(btrim(p_address), ''), lines = nl->'lines', subtotal = sub,
      discount = dsc, delivery_mode = p_delivery_mode, delivery_by = nullif(btrim(p_delivery_by), ''), delivery_date = p_delivery_date, delivery_charge = chg, advance = adv,
      advance_mode = p_adv_mode, advance_wallet = left(nullif(btrim(p_adv_wallet), ''), 30), note = nullif(btrim(p_note), ''), updated_at = now()
    where id = o.id returning * into o;
  perform public._oo_event61(o.id, o.status, o.status, 'edited');
  return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
end $function$$r0_0$, null),
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)', 'known', 'f76b73ddde41b954c0d9b66f4801cba6', null);
-- online_orders_list(integer,text,date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_orders_list(integer,text,date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
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
end $function$$r0_0$, null),
  ('public.online_orders_list(integer,text,date,date,integer)', 'known', 'e0914436e4ad0e16d81d774affd75011', null);
-- packaging_set(uuid,uuid,numeric,text,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text DEFAULT 'sale'::text, p_active boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product and public._m132_own(items.org_unit_id) /* m132b:items */;
  select * into pk from public.items where id = p_packaging and public._m132_own(items.org_unit_id) /* m132b:items */;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $function$$r0_0$, null),
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)', 'known', 'e04a9dcd6c818f716c504c858cc5e734', null);
-- partner_calculate(bigint,date,date,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.partner_calculate(bigint,date,date,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */ locs int[]; k text; r record; cfg jsonb; sh jsonb; er record; er2 record;
  bases jsonb := '{}'::jsonb; src jsonb := '{}'::jsonb; warns jsonb := '[]'::jsonb; steps jsonb := '[]'::jsonb; lines jsonb := '[]'::jsonb; nl jsonb;
  v_gs numeric; v_ns numeric; v_costed numeric; v_cogs numeric; v_exp numeric; v_sal numeric; v_fix numeric; v_gp numeric; v_nf numeric; v_n int;
  pool numeric; poolset boolean := false; incomplete boolean := false; fees numeric := 0;
  rto numeric := 0.01; rmode text := 'nearest';
  carry_in numeric := 0; carry_out numeric := 0; retained numeric := 0; floor_added numeric := 0;
  amt numeric; core numeric; stepamt numeric; pool_before numeric; pid bigint; pct numeric; mths numeric := public._a44_months(p_from, p_to); days int := p_to - p_from + 1;
  capb numeric; due numeric; capc numeric; paid_b numeric; sf_in numeric; short_out numeric; outb numeric; a1 numeric; a2 numeric; used numeric; tgt numeric; lim numeric; tot numeric; exc numeric; rem numeric; red numeric;
  detail jsonb; skipped boolean; remaining numeric; prev_up numeric; size numeric; dist jsonb; d jsonb; need numeric; outside boolean; names jsonb; ptot jsonb; tdist numeric := 0; tout numeric := 0;
  nbase int := 0; newlines jsonb; v_fb numeric;   -- bos80
begin
  perform public._a44_guard();
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then raise exception 'bad_range'; end if;
  select * into ag from public.partner_agreements where id = p_agr;
  if not found then raise exception 'not_found'; end if;
  select * into vn from public.partner_ventures where id = ag.venture_id;
  -- manual figures typed by the owner
  if p_manual is not null then
    if jsonb_typeof(p_manual) <> 'object' then raise exception 'bad_manual'; end if;
    for k in select jsonb_object_keys(p_manual) loop
      if k not in ('gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'manual', 'carry_in') or public._a44_n(p_manual -> k) is null or abs(public._a44_n(p_manual -> k)) > 1000000000000 then raise exception 'bad_manual'; end if;
    end loop;
  end if;
  -- bases from the books (only what can be computed honestly)
  if vn.scope in ('location', 'business') then
    locs := case when vn.scope = 'location' then array[vn.location_id] else array(select id from public.locations) end;
    select count(*), coalesce(sum(o_gross), 0), coalesce(sum(o_net), 0), coalesce(sum(o_costed), 0), coalesce(sum(o_cogs), 0), coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0), sum(o_fixed)
      into v_n, v_gs, v_ns, v_costed, v_cogs, v_exp, v_sal, v_fix from public._p27_pl(p_from, p_to, locs);
    bases := jsonb_build_object('gross_sales', v_gs, 'net_sales', v_ns);
    if abs(v_ns - v_costed) <= greatest(1, abs(v_ns) * 0.001) then
      v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;
      bases := bases || jsonb_build_object('gross_profit', v_gp, 'net_profit_before_fees', v_nf);
    else
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'uncosted_sales', 'detail', round(v_ns - v_costed, 2), 'msg', 'Some sold items have no cost price, so gross profit cannot be computed honestly. Type a manual base.'));
      bases := bases || jsonb_build_object('gross_profit', null, 'net_profit_before_fees', null);
    end if;
    bases := bases || jsonb_build_object('expenses', v_exp, 'salary', v_sal, 'fixed_cost', v_fix, 'cogs', v_cogs);
    -- bos80: part of the cost of goods sold may be an ESTIMATE from the item cost list (no stock-ledger cost). Always shown; partner_base_estimate = refuse stops a settlement SAVE on it.
    select coalesce(sum(o_cogs_fallback), 0) into v_fb from public._p27_src72(p_from, p_to, locs);
    if v_fb > 0.004 then
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'estimated_base', 'detail', round(v_fb, 2), 'refuse', coalesce(public.rule_txt('partner_base_estimate'), 'warn') = 'refuse',
        'msg', 'Part of the cost of goods sold is an estimate from the item cost list, not from the stock ledger.'));
    end if;
    if v_n = 0 then warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_book_rows', 'msg', 'No sales, expenses or salary were recorded in this period.')); end if;
  else
    bases := jsonb_build_object('gross_sales', null, 'net_sales', null, 'gross_profit', null, 'net_profit_before_fees', null);
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'manual_only', 'msg', 'A product-line or custom venture has no books of its own - type the manual base.'));
  end if;
  for k in select jsonb_object_keys(coalesce(p_manual, '{}'::jsonb)) loop
    if k <> 'carry_in' then bases := bases || jsonb_build_object(k, public._a44_n(p_manual -> k)); src := src || jsonb_build_object(k, 'manual'); end if;
  end loop;
  for k in select unnest(array['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees']) loop
    if not src ? k then src := src || jsonb_build_object(k, case when bases -> k is null or jsonb_typeof(bases -> k) = 'null' then 'unavailable' else 'books' end); end if;
  end loop;
  -- loss carried from the earlier settlement
  if p_manual ? 'carry_in' then carry_in := greatest(public._a44_n(p_manual -> 'carry_in'), 0);
  else
    select coalesce(s.carry_out, 0) into carry_in from public.partner_settlements s
     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from order by s.period_to desc limit 1;
    carry_in := coalesce(carry_in, 0);
  end if;

  for r in select * from public.partner_rules where agreement_id = p_agr and active order by step_no loop
    cfg := r.config; stepamt := 0; core := null; detail := '{}'::jsonb; skipped := false; pool_before := pool; short_out := null;
    if r.kind <> 'base' and r.kind <> 'rounding' and not poolset then raise exception 'base_step_first'; end if;
    if incomplete and r.kind <> 'rounding' and r.kind <> 'base' then
      skipped := true; detail := jsonb_build_object('skipped', 'no_base');
    else
    case r.kind
      when 'base' then
        nbase := nbase + 1; if nbase > 1 then raise exception 'base_twice'; end if;
        k := cfg ->> 'base';
        pool := case k when 'fixed_amount' then public._a44_n(cfg -> 'amount')
                       when 'manual' then public._a44_n(bases -> 'manual')
                       when 'net_profit' then case when public._a44_n(bases -> 'net_profit_before_fees') is null then null else public._a44_n(bases -> 'net_profit_before_fees') - fees end
                       else public._a44_n(bases -> k) end;
        poolset := true;
        if pool is null then
          incomplete := true;
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'This base cannot be computed from the books - type a manual base.'));
        end if;
        detail := jsonb_build_object('base', k, 'value', pool); pool_before := null;
      when 'royalty' then
        pid := public._a44_need(p_agr, cfg, r.name); k := coalesce(cfg ->> 'base', 'net_sales');
        if public._a44_n(bases -> k) is null then
          incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The royalty base cannot be computed - type a manual base.'));
        else
          amt := public._a44_round(greatest(public._a44_n(bases -> k), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode);
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'royalty', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt;
          detail := jsonb_build_object('base', k, 'base_value', public._a44_n(bases -> k), 'percent', public._a44_n(cfg -> 'percent'), 'party_id', pid);
        end if;
      when 'management_fee' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'fixed') is not null then
          amt := public._a44_round(public._a44_n(cfg -> 'fixed') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end, rto, rmode);
        else
          k := cfg ->> 'base';
          if k is not null and public._a44_n(bases -> k) is null then amt := null; incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The fee base cannot be computed - type a manual base.'));
          else amt := public._a44_round(greatest(coalesce(public._a44_n(bases -> k), pool), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode); end if;
        end if;
        if amt is not null then
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'fee', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'months', round(mths, 4));
        end if;
      when 'expense_allow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool - amt; stepamt := -amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'expense_disallow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool + amt; stepamt := amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'loss_carry_forward' then
        amt := pool - carry_in;
        if amt < 0 then carry_out := -amt; pool := 0; else carry_out := 0; pool := amt; end if;
        detail := jsonb_build_object('carry_in', carry_in, 'carry_out', carry_out);
      when 'priority_return' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'percent_per_year') is not null then
          due := round(public._a44_capdays(p_agr, pid, p_from, p_to) * public._a44_n(cfg -> 'percent_per_year') / 100 / 365, 2);
        else due := round(public._a44_n(cfg -> 'fixed_monthly') * mths, 2); end if;
        select h.paid_before, h.shortfall_in into paid_b, sf_in from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        if coalesce((cfg ->> 'catch_up')::boolean, false) then due := due + sf_in; else sf_in := 0; end if;
        due := public._a44_round(due, rto, rmode);
        if public._a44_n(cfg -> 'cap') is not null then due := least(due, greatest(public._a44_n(cfg -> 'cap') - paid_b, 0)); end if;
        amt := least(due, greatest(pool, 0));
        short_out := case when coalesce((cfg ->> 'catch_up')::boolean, false) then due - amt else 0 end;
        if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'return', 'amount', amt, 'outside', false)); end if;
        pool := pool - amt; stepamt := amt; core := amt;
        detail := jsonb_build_object('party_id', pid, 'due', due, 'catch_up_in', sf_in, 'paid_before', paid_b, 'shortfall_out', short_out);
        if amt < due and not coalesce((cfg ->> 'catch_up')::boolean, false) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'return_short', 'step_no', r.step_no, 'msg', 'The profit was not enough for the whole priority return.')); end if;
      when 'payback' then
        pid := public._a44_need(p_agr, cfg, r.name); pct := coalesce(public._a44_n(cfg -> 'percent'), 100);
        select h.paid_before into paid_b from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        outb := coalesce(public._a44_n(cfg -> 'target'), public._a44_cap(p_agr, pid, p_to)) - paid_b;
        a1 := 0; a2 := 0;
        if outb > 0 then
          a1 := least(outb, public._a44_round(greatest(pool, 0) * pct / 100, rto, rmode));
          if public._a44_n(cfg -> 'then_percent') is not null and a1 >= outb - 0.004 and greatest(pool, 0) * pct / 100 > outb then
            used := outb / (pct / 100); a2 := public._a44_round(greatest(pool - used, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
          end if;
        elsif public._a44_n(cfg -> 'then_percent') is not null then
          a2 := public._a44_round(greatest(pool, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
        end if;
        if a1 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'payback', 'amount', a1, 'outside', false)); end if;
        if a2 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'share', 'amount', a2, 'outside', false)); end if;
        pool := pool - a1 - a2; stepamt := a1 + a2; core := a1;
        detail := jsonb_build_object('party_id', pid, 'outstanding_before', greatest(outb, 0), 'payback', a1, 'then_share', a2, 'outstanding_after', greatest(outb - a1, 0));
      when 'split' then
        if pool > 0 then
          dist := public._a44_distribute(p_agr, pool, cfg -> 'shares', rto, rmode, r.name);
          for d in select value from jsonb_array_elements(dist) loop
            lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
          end loop;
          stepamt := pool; detail := jsonb_build_object('distributed', pool, 'parts', dist); pool := 0;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
          detail := jsonb_build_object('distributed', 0);
        end if;
      when 'tiered_split' then
        if pool > 0 then
          remaining := pool; prev_up := 0; detail := jsonb_build_object('slabs', '[]'::jsonb);
          for er in select value as v, ord from jsonb_array_elements(cfg -> 'slabs') with ordinality as t(value, ord) order by ord loop
            exit when remaining <= 0;
            size := case when public._a44_n(er.v -> 'upto') is null then remaining else least(remaining, public._a44_n(er.v -> 'upto') - prev_up) end;
            dist := public._a44_distribute(p_agr, size, er.v -> 'shares', rto, rmode, r.name);
            for d in select value from jsonb_array_elements(dist) loop
              lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
            end loop;
            detail := jsonb_set(detail, '{slabs}', (detail -> 'slabs') || jsonb_build_array(jsonb_build_object('slab', er.ord, 'amount', size, 'parts', dist)));
            remaining := remaining - size; stepamt := stepamt + size;
            if public._a44_n(er.v -> 'upto') is not null then prev_up := public._a44_n(er.v -> 'upto'); end if;
          end loop;
          pool := remaining;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
        end if;
      when 'minimum_guarantee', 'floor' then
        if r.kind = 'floor' and coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool < lim then floor_added := floor_added + (lim - pool); stepamt := lim - pool;
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'floor_topup', 'step_no', r.step_no, 'detail', lim - pool, 'msg', 'The pool was lifted to the floor; the difference is funded outside the books.'));
            pool := lim; end if;
          detail := jsonb_build_object('floor', lim, 'added', greatest(stepamt, 0));
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          need := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, true);
          amt := 0; outside := coalesce(cfg ->> 'funded_by', 'pool') = 'outside';
          if tot < need then
            amt := need - tot;
            if not outside then
              if amt > greatest(pool, 0) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'guarantee_short', 'step_no', r.step_no, 'detail', amt - greatest(pool, 0), 'msg', 'The pool could not pay the whole guarantee.')); amt := greatest(pool, 0); end if;
              pool := pool - amt;
            end if;
            amt := public._a44_round(amt, rto, rmode);
            if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'guarantee', 'amount', amt, 'outside', outside)); end if;
          end if;
          stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'needed', need, 'had', tot, 'topup', amt, 'funded_by', case when outside then 'outside' else 'pool' end);
        end if;
      when 'cap' then
        if coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool > lim then retained := retained + (pool - lim); stepamt := -(pool - lim); pool := lim; end if;
          detail := jsonb_build_object('cap', lim, 'retained', retained);
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          lim := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, false); exc := greatest(tot - lim, 0); rem := exc;
          if exc > 0 then
            newlines := '[]'::jsonb;
            for er2 in select value as v, ord from jsonb_array_elements(lines) with ordinality as t(value, ord) order by ord desc loop
              if rem > 0 and (er2.v ->> 'party_id')::bigint = pid and not coalesce((er2.v ->> 'outside')::boolean, false) then
                red := least(rem, (er2.v ->> 'amount')::numeric); rem := rem - red;
                newlines := jsonb_build_array(jsonb_set(er2.v, '{amount}', to_jsonb(round((er2.v ->> 'amount')::numeric - red, 2)))) || newlines;
              else newlines := jsonb_build_array(er2.v) || newlines; end if;
            end loop;
            lines := newlines; pool := pool + exc; stepamt := -exc;
          end if;
          detail := jsonb_build_object('party_id', pid, 'cap', lim, 'had', tot, 'returned_to_pool', exc);
        end if;
      when 'rounding' then
        rto := public._a44_n(cfg -> 'to'); rmode := coalesce(cfg ->> 'mode', 'nearest'); detail := jsonb_build_object('to', rto, 'mode', rmode);
      else raise exception 'bad_kind';
    end case;
    end if;
    steps := steps || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'key', r.step_key, 'name', r.name, 'kind', r.kind, 'skipped', skipped,
        'pool_before', pool_before, 'pool_after', pool, 'amount', round(stepamt, 2), 'core', round(coalesce(core, stepamt), 2), 'shortfall_out', short_out, 'detail', detail));
  end loop;
  if nbase = 0 then raise exception 'base_step_first'; end if;
  if pool is not null and pool > 0.004 then
    retained := retained + pool;
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'retained', 'detail', pool, 'msg', 'Part of the profit was not given to anybody by the rules.'));
  end if;
  select coalesce(sum((e ->> 'amount')::numeric) filter (where not coalesce((e ->> 'outside')::boolean, false)), 0), coalesce(sum((e ->> 'amount')::numeric) filter (where coalesce((e ->> 'outside')::boolean, false)), 0)
    into tdist, tout from jsonb_array_elements(lines) e;
  select coalesce(jsonb_agg(jsonb_build_object('party_id', q.pid, 'name', p.name, 'amount', q.a) order by p.name), '[]'::jsonb) into ptot
    from (select (e ->> 'party_id')::bigint as pid, sum((e ->> 'amount')::numeric) as a from jsonb_array_elements(lines) e group by 1) q join public.partner_parties p on p.id = q.pid;
  return jsonb_build_object('agreement_id', p_agr, 'venture_id', ag.venture_id, 'from', p_from, 'to', p_to, 'days', days, 'months', round(mths, 4),
    'status', case when incomplete then 'incomplete' else 'ok' end, 'bases', bases, 'sources', src, 'manual_used', coalesce(p_manual, '{}'::jsonb),
    'steps', steps, 'lines', lines, 'party_totals', ptot, 'carry_in', carry_in, 'carry_out', carry_out, 'retained', round(retained, 2), 'floor_added', round(floor_added, 2),
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);
end $function$$r0_0$, null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', '307859e61a0dbf410cc0e17b7b63f79d', null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', 'c4072622b8e2e28d903f48b88ea69c99', null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', 'e9c4d1a5df3790be9431b316389276a6', null);
-- partner_settlement_save(bigint,date,date,jsonb,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.partner_agreements; c jsonb; s public.partner_settlements;
begin
  perform public._a44_guard();
  if p_client is not null then perform public._client_lock(p_client); select * into s from public.partner_settlements where client_id = p_client; if found then return to_jsonb(s); end if; end if;
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  if p_from < a.effective_from or (a.effective_to is not null and p_to > a.effective_to) then raise exception 'outside_deed_dates'; end if;
  if p_to > public._a44_today() then raise exception 'bad_date'; end if;
  perform public.lock_check(p_to);
  if exists (select 1 from public.partner_settlements x where x.agreement_id in (select id from public._a44_chain(p_agr)) and x.status <> 'void' and x.period_from <= p_to and x.period_to >= p_from) then raise exception 'period_overlap'; end if;
  c := public.partner_calculate(p_agr, p_from, p_to, p_manual);
  if c ->> 'status' <> 'ok' then raise exception 'calc_incomplete'; end if;
  -- bos80: partner_base_estimate = refuse: a settlement whose profit base uses an ESTIMATED cost of goods is not saved (a typed manual base replaces the book base)
  if coalesce(public.rule_txt('partner_base_estimate'), 'warn') = 'refuse'
     and exists (select 1 from jsonb_array_elements(c -> 'warnings') w where w ->> 'code' = 'estimated_base')
     and exists (select 1 from public.partner_rules r where r.agreement_id = p_agr and r.active and r.config ->> 'base' in ('gross_profit', 'net_profit'))
     and not (coalesce(p_manual, '{}'::jsonb) ? 'gross_profit' or coalesce(p_manual, '{}'::jsonb) ? 'net_profit_before_fees') then
    raise exception 'base_estimated';
  end if;
  insert into public.partner_settlements (agreement_id, period_from, period_to, status, calc, manual_base, total_distributable, carry_out, note, client_id, created_by)
    values (p_agr, p_from, p_to, 'draft', c, p_manual, (c ->> 'total_distributable')::numeric, (c ->> 'carry_out')::numeric, left(p_note, 1000), p_client, auth.uid()) returning * into s;
  insert into public.partner_settlement_lines (settlement_id, party_id, amount, kind, funded_outside)
    select s.id, (e ->> 'party_id')::bigint, round(sum((e ->> 'amount')::numeric), 2), e ->> 'kind', coalesce((e ->> 'outside')::boolean, false)
      from jsonb_array_elements(c -> 'lines') e group by 2, 4, 5 having round(sum((e ->> 'amount')::numeric), 2) > 0;
  return to_jsonb(s);
end $function$$r0_0$, null),
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', 'known', 'dbda3123c8cdeeb2426357531035f0df', null);
-- path_cfg(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.path_cfg(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.path_cfg(p_domain text, p_loc integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('a_open', coalesce(x.a_open, true), 'b_open', coalesce(x.b_open, true), 'primary', coalesce(x.primary_rule, case when d.legacy_rule is not null and public.rule_on(d.legacy_rule) then 'b' else d.default_primary end))
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        and (s.location_id = 0 or public._cfgvis133(s.location_id)) /* scope133 */ order by s.location_id desc limit 1) x on true
   where d.domain = p_domain;
$function$$r0_0$, null),
  ('public.path_cfg(text,integer)', 'known', 'c12ccf4692a26e5a896b3ea6d1486aec', null);
-- pay_supplier(uuid,integer,jsonb,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.pay_supplier(p_supplier uuid, p_loc integer, p_payments jsonb, p_client uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
    if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  if not (tot between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  -- a re-sent request is answered before anything is locked or consumed, but only to someone who may see supplier money (or who made it)
  if p_client is not null then
    select created_by into dupby from public.supplier_payments where client_id = p_client order by id limit 1;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'pay_supplier:' || p_supplier::text, tot)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)           -- one payment at a time per supplier
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
  end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if tot > bal then raise exception 'overpaid'; end if;
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (p_supplier, p_loc, null, pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('paid', tot, 'balance', bal - tot);
end $function$$r0_0$, null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '11c68a538d1adbb2dad1546a563a117f', null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '27ff51231129d7176705ea93bc07cd3a', null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '31cbab604c7a47236bd135753deb4012', null);
-- payment_intent_link(bigint,bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.payment_intent_link(bigint,bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.payment_intent_link(p_id bigint, p_sale_payment bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sale_payments where id = p_sale_payment and ((select not public._org_on123()) or auth.uid() is null or public._biz_ok123(location_id))) then   /* scope133 */ raise exception 'payment_not_found'; end if;
  if exists (select 1 from public.payment_intents where sale_payment_id = p_sale_payment and id <> p_id) then raise exception 'payment_already_linked'; end if;
  update public.payment_intents set sale_payment_id = p_sale_payment, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'sale_payment_id', p_sale_payment);
end $function$$r0_0$, null),
  ('public.payment_intent_link(bigint,bigint)', 'known', 'c7c5c98ed498fc66bbf519123233e89a', null);
-- pool_set(integer,date,text,numeric,text,boolean,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.pool_set(p_loc integer, p_month date, p_type text, p_amount numeric, p_period_kind text DEFAULT 'month'::text, p_one_off boolean DEFAULT false, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month); alloc boolean;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.factory_cost_pools where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  perform public.lock_check(m);
  update public.factory_cost_pools set active = false where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'manual' and active;
  insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, note, client_id, created_by)
    values (p_loc, m, p_type, p_period_kind, p_amount, coalesce(p_one_off, false), 'manual', left(p_note, 200), p_client, auth.uid()) returning id into nid;
  alloc := exists (select 1 from public.factory_cost_pools where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'allocated' and active);      -- bos75
  if alloc then
    perform public._stock_exc(p_loc, 'pool_double_entry', 'yellow', 'এই মাসের এই খরচ বিল থেকে আগেই এসেছে — হাতে আবার লিখলে দুবার গোনা হবে',
      'A cost bill already feeds this pool - a manual amount on top is counted twice', null, m, 'STOCK');
  end if;
  if public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage()) then      -- sec121: owner / accountant only, others rely on the catch-up; bos117: the typed pool also becomes the expense in the books (the matching Dr for the Cr 5950 absorbed)
    begin perform public._pool_gl_sync117(p_loc, m);
    exception when others then
      perform public._stock_exc(p_loc, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, m, 'STOCK');
    end;
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $function$$r0_0$, null),
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'known', '358f68e44003d9b8fb0157547f45cba6', null);
-- production_can_make(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_can_make(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_can_make(p_loc integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not it.is_active then continue; end if;
    mx := null; lim := null; unk := not it.tracked;
    for n in select * from public._recipe_need(r.id, 1, p_loc) loop
      if not n.tracked or not n.unit_ok or n.need <= 0 then unk := true; continue; end if;
      per := n.on_hand / n.need;
      if mx is null or per < mx then mx := per; lim := n.item_id; end if;
    end loop;
    out := out || jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'code', it.code, 'name_bn', it.name_bn, 'name_en', it.name_en,
      'max_batches', case when mx is null then null else greatest(floor(mx * 10000) / 10000, 0) end, 'limiting_item_id', lim, 'unknown', unk,
      'yield_per_batch', public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 'yield_unit', public._item_base(r.item_id));
  end loop;
  return out;
end $function$$r0_0$, null),
  ('public.production_can_make(integer)', 'known', '30c4626c6dddf2b4a19bfa7fd0abf984', null);
-- production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamp with time zone, p_note text, p_actual_yield numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; nocost text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
        outq numeric; conv jsonb; conv_amt numeric := 0; cinc boolean; yvp numeric; ythr numeric;   -- bos74
        prov boolean := false; sn public.recipe_std116; stdu numeric; stdc numeric;   -- bos116
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  it := public._stock_guard(r.item_id, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into run from public.production_runs where client_id = p_client;
    if found then
      if run.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'run_id', run.id, 'ledger_id', run.ledger_in_id, 'batch_id', run.batch_id, 'qty', run.yield_base);
    end if;
  end if;
  if not r.active then raise exception 'recipe_inactive'; end if;
  gate := public._recipe_gate73(r.id);      -- bos73: on = refuse an unapproved recipe; warn = a yellow line below
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_actual_yield is not null and not (round(p_actual_yield, 4) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;      -- bos74
  outq := case when p_actual_yield is null then yb else round(p_actual_yield, 4) end;      -- bos74: what is really booked into stock
  -- everything that leaves the stock: checks first, nothing is posted until all are fine
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  -- bos109: lock every ingredient / packaging balance AND the finished-good balance of this place in ONE item order BEFORE the shortage check, so two cooks (or a cook and a sale)
  -- cannot both pass the check on the same stock, and the later stock_post calls never take a lock in another order (no lock-order deadlock between recipes)
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and (sbl.item_id = r.item_id or sbl.item_id in (select n2.item_id from public._recipe_need116(r.id, p_batches, p_loc, outq) n2)) order by sbl.item_id for update;   -- bos109
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0
         and not public._cost_free80(n.item_id) then      -- bos80: an item marked 'cost really zero' is a known cost
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if public.rule_on('std_snapshot_auto116') and not exists (select 1 from public.recipe_std116 where recipe_id = r.id and location_id = p_loc) then      -- bos116: the first run stores the standard (prices of today, before anything is issued)
    perform public._recipe_std_snap116(r.id, p_loc, 'auto', null, (at_ at time zone 'Asia/Dhaka')::date);
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then cost_ok := false; else tot := tot + n.need * coalesce(av, 0); end if;   -- bos72: cost 0 = unknown; bos80: unless the item is marked 'cost really zero'
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- bos74: conversion cost (layer 2) of this run: off = nothing (today's behaviour); recipe = the recipe's rates; pool = monthly pool / NORMAL output
  conv := public._conv_cost(r.id, p_loc, p_batches, outq, (at_ at time zone 'Asia/Dhaka')::date);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); cinc := (conv->>'mode') <> 'off' and not (conv->>'complete')::boolean;
  prov := coalesce((conv->>'provisional')::boolean, false);      -- bos116
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  select * into sn from public.recipe_std116 where recipe_id = r.id and location_id = p_loc and active;      -- bos116: the stored standard (if any)
  stdu := case when sn.id is not null and sn.complete and sn.mat_per_batch is not null and sn.conv_per_batch is not null then round((sn.mat_per_batch + sn.conv_per_batch) / sn.yield_per_batch, 6) end;      -- bos116
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when public.rule_on('std_cost_true116') then stdu when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      cost_full_yield116 = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, std_unit_cost116 = stdu, conversion_provisional116 = prov,      -- bos116
      conversion_mode = conv->>'mode', conversion_complete = not cinc, conversion_detail = conv->'detail', yield_std = yb, yield_actual = p_actual_yield, yield_var_pct = yvp where id = rid;   -- bos74
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if cinc then      -- bos74
    perform public._stock_exc(p_loc, 'conversion_incomplete', 'yellow', it.name_bn || ': রূপান্তর খরচ অসম্পূর্ণ (খালি ঘর আছে) — যা জানা ছিল শুধু তা ধরা হয়েছে',
      coalesce(it.name_en, it.name_bn) || ': conversion cost incomplete (blank amounts) — only the known part was booked', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if prov then      -- bos116
    perform public._stock_exc(p_loc, 'conversion_provisional', 'yellow', it.name_bn || ': রূপান্তর খরচ সাময়িক (আগের মাসের হারে) — মাসের বিল এলে production_reprice116 দিয়ে ঠিক করুন',
      coalesce(it.name_en, it.name_bn) || ': conversion cost is PROVISIONAL (last month''s rate) — re-price it with production_reprice116 once this month''s bills are in', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $function$$r0_0$, null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', '01a3ef963f29db79b951d3b9df768bef', null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', '6859c81ecf25a25c8e54182f652bc250', null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', 'c9bc08ce76c01947ab33a08ce867a8c4', null);
-- production_preview(integer,uuid,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_preview(integer,uuid,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_preview(p_loc integer, p_recipe uuid, p_batches numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $function$$r0_0$, null),
  ('public.production_preview(integer,uuid,numeric)', 'known', '5ed96727886165b8e3ad862258b6e7ae', null);
-- production_run_costs(integer,date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_run_costs(integer,date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_run_costs(p_loc integer, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', case when coalesce(r.conversion_mode, 'off') = 'off' then null else r.conversion_cost end,   /* bos401 */
        'conversion_status', case when coalesce(r.conversion_mode, 'off') = 'off' then 'not_captured' end,
        'unit_cost_basis', case when coalesce(r.conversion_mode, 'off') = 'off' then 'material_only' else 'material_and_conversion' end, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', case when r.yield_actual is null then null else r.actual_cost end, 'actual_status', case when r.yield_actual is null then 'not_captured' end,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail,
      'cost_full_yield', r.cost_full_yield116, 'std_unit_cost', r.std_unit_cost116, 'conversion_provisional', r.conversion_provisional116,
      'yield_loss_money', case when r.cost_complete and coalesce(r.yield_std, 0) > 0 and r.yield_actual is not null then round((coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) * (1 - r.yield_base / r.yield_std), 2) end) order by r.made_at, r.id)      -- bos116
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.production_run_costs(integer,date,date)', 'known', '7178010da5ac8a62f96efd91be331a39', null),
  ('public.production_run_costs(integer,date,date)', 'known', '7571cb2c8ad74b490d1821ec548d16d6', null),
  ('public.production_run_costs(integer,date,date)', 'known', 'ee6a4845b5baedc33b7170f57253f95a', null);
-- production_void(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_void(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_void(p_run uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare run public.production_runs; r record; b public.stock_batches; n int := 0;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(run.location_id) or not (public.is_owner() or public.has_grant('production_void', run.location_id)) then raise exception 'not allowed'; end if;
  if run.status = 'void' then return jsonb_build_object('id', run.id, 'status', 'void', 'dup', true); end if;
  if exists (select 1 from public.production_reprice116 x where x.run_id = run.id) then raise exception 'run_repriced'; end if;      -- bos116: a re-priced run has an adjustment entry; it cannot be undone silently
  perform public.lock_check((run.made_at at time zone 'Asia/Dhaka')::date);
  -- the finished goods must still be unsold: a partly sold batch cannot be undone (use wastage / count instead)
  if run.batch_id is not null then
    select * into b from public.stock_batches where id = run.batch_id for update;
    if found and b.qty_remaining < b.qty_made - 0.0001 then raise exception 'batch_partly_used'; end if;
  end if;
  for r in select o.* from public.stock_ledger o where o.ref_type = 'production' and o.ref_id = run.id::text and o.reason in ('issue_out', 'production_in')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'production', run.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
    n := n + 1;
  end loop;
  update public.production_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = run.id;
  return jsonb_build_object('id', run.id, 'status', 'void', 'reversed_lines', n);
end $function$$r0_0$, null),
  ('public.production_void(uuid,text)', 'known', '613e15ba809f5360f66544e1c801bc59', null);
-- profit_source_check(date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.profit_source_check(date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.profit_source_check(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); fr date := p_from; locs int[]; r record; jc numeric; cid bigint; pend int := 0; cmp_from date; notes jsonb := '[]'::jsonb; rc numeric; ok boolean;
begin
  if not public.biz_ok() or not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := public._cogs_locs72(p_loc);
  select round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.led_cogs), 0), 2) as led, round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_cogs), 0), 2) as fb,
         round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_rev), 0), 2) as fbr, round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev), 0), 2) as unk,
         round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.rev), 0), 2) as netrev
    into r from public._cogs_lines72(p_from, p_to, locs) h;
  rc := r.led + r.fb;
  -- the books only start at the accounting start date: compare the same days
  cmp_from := case when st is null then null else greatest(p_from, st) end;
  if st is not null and public._acct_view() and cmp_from <= p_to then
    select account_id into cid from public.acct_mappings where key = 'cogs';
    select coalesce(sum(b.dr - b.cr), 0) into jc from public._acct_bal(cmp_from, p_to, p_loc) b where b.account_id = cid;
    select count(*) into pend from public._acct_docs(st) d where d.waiting is null and d.source_type in ('sale', 'sale_return') and d.entry_date between cmp_from and p_to
      and (p_loc is null or d.location_id = p_loc) and ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id));   /* scope133 */
    if cmp_from > p_from then   -- report side for the compared days only
      select round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)), 0), 2) into rc from public._cogs_lines72(cmp_from, p_to, locs) h;
    end if;
  else jc := null; end if;
  if r.fb <> 0 then notes := notes || to_jsonb('fallback_used'::text); end if;
  if r.unk <> 0 then notes := notes || to_jsonb('unknown_cost'::text); end if;
  if pend > 0 then notes := notes || to_jsonb('journal_pending'::text); end if;
  if jc is null then notes := notes || to_jsonb('journal_unavailable'::text); end if;
  ok := jc is not null and abs(rc - jc) <= 0.01 and r.fb = 0 and r.unk = 0 and pend = 0;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc,
    'report_cogs', r.led + r.fb, 'ledger_cogs', r.led, 'fallback_cogs', r.fb, 'fallback_rev', r.fbr, 'unknown_cost_rev', r.unk, 'net_revenue', r.netrev,
    'journal_cogs', jc, 'compared_from', cmp_from, 'compared_report_cogs', case when jc is null then null else rc end,
    'difference', case when jc is null then null else round(rc - jc, 2) end, 'pending_docs', pend, 'agree', ok, 'notes', notes);
end $function$$r0_0$, null),
  ('public.profit_source_check(date,date,integer)', 'known', '33394b1a312ba88565b7d33db94507ed', null);
-- purchase_get(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.purchase_get(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.purchase_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.purchase_bills;
begin
  select * into b from public.purchase_bills where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._pur_ok(b.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(b) || jsonb_build_object('supplier_name', (select name from public.suppliers where id = b.supplier_id and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no) from public.purchase_lines l where l.bill_id = b.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'mode', p.mode, 'wallet', p.wallet, 'ref', p.ref, 'amount', p.amount, 'paid_at', p.paid_at, 'voided', p.voided) order by p.id) from public.supplier_payments p where p.bill_id = b.id), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.purchase_get(uuid)', 'known', '39dfedb32a2c26c7ef5e8c6d0abd3dd4', null);
-- recipe_approve(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_approve(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_approve(p_recipe uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; prev jsonb; selfap boolean := false; sid text;   -- bos87
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch recipe_self_approve)
    if public.is_owner() or public.rule_on('recipe_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'recipes', r.id::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('recipe_id', r.id, 'approved', true) || public._self_approve_hint87(selfap);   -- bos87
end $function$$r0_0$, null),
  ('public.recipe_approve(uuid,text)', 'known', '95d59422fb9334d709ec01809d7925f6', null);
-- recipe_book(integer,boolean,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_book(integer,boolean,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_book(p_artisan integer DEFAULT NULL::integer, p_with_cost boolean DEFAULT false, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.artisans; aid int := coalesce(p_artisan, public._artisan_of_user()); rs jsonb := '[]'::jsonb; r record; ln jsonb; st jsonb; lab jsonb; cst jsonb; cost_on boolean;
begin
  if aid is null or not public._recipe_view_ok(aid) then raise exception 'not allowed'; end if;
  select * into a from public.artisans where id = aid and public._m132_vis('artisans', artisans.org_unit_id, artisans.id::text, false) /* m132b:artisans */;
  if not found then raise exception 'artisan_not_found'; end if;
  cost_on := coalesce(p_with_cost, false) and public._recipe_cost_ok();
  for r in select rc.*, i.code, i.name_bn, i.name_en from public.recipes rc join public.items i on i.id = rc.item_id where rc.artisan_id = aid and rc.active order by i.code, rc.version loop
    select coalesce(jsonb_agg(jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'qty', l.qty, 'unit', coalesce(l.unit, public._item_base(l.ingredient_item_id)),
        'waste_pct', l.waste_pct, 'waste_missing', l.waste_pct is null) order by l.sort, l.id), '[]'::jsonb) into ln
      from public.recipe_lines l join public.items x on x.id = l.ingredient_item_id where l.recipe_id = r.id and l.active;
    select coalesce(jsonb_agg(jsonb_build_object('step_no', s.step_no, 'step_name', s.step_name, 'description', s.description, 'minutes', s.minutes, 'people', s.people, 'fuel', s.fuel, 'fuel_other', s.fuel_other,
        'flame_note', s.flame_note, 'equipment', s.equipment, 'qc_note', s.qc_note, 'resp_post', s.resp_post, 'resp_other', s.resp_other) order by s.step_no), '[]'::jsonb) into st
      from public.recipe_steps s where s.recipe_id = r.id and s.active;
    lab := public.recipe_labour_suggest(r.id);
    cst := null;
    if cost_on then
      begin cst := public.recipe_cost(r.id, p_loc); exception when others then cst := jsonb_build_object('error', sqlerrm); end;
    end if;
    rs := rs || (jsonb_build_object('recipe_id', r.id, 'version', r.version, 'item_id', r.item_id, 'code', r.code, 'name_bn', r.name_bn, 'name_en', r.name_en, 'yield_qty', r.yield_qty,
        'yield_unit', coalesce(r.yield_unit, public._item_base(r.item_id)), 'approved', r.approved_at is not null, 'approved_at', r.approved_at, 'form_ref', r.form_ref,
        'lines', ln, 'steps', st, 'labour', lab) || case when cost_on then jsonb_build_object('cost', cst) else '{}'::jsonb end);
  end loop;
  perform public._audit_view('recipe_book', aid::text, jsonb_build_object('with_cost', cost_on, 'recipes', jsonb_array_length(rs)));
  return jsonb_build_object('artisan', jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active), 'recipes', rs, 'with_cost', cost_on, 'generated_at', now());
end $function$$r0_0$, null),
  ('public.recipe_book(integer,boolean,integer)', 'known', '328fb90f9d21f76d39ca955ffd693f3a', null);
-- recipe_copy(uuid,uuid,boolean,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_copy(uuid,uuid,boolean,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_copy(p_from uuid, p_item uuid DEFAULT NULL::uuid, p_retire_old boolean DEFAULT false, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_client is not null then
    select * into dup from public.recipes where client_id = p_client;
    if found then
      if dup.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', dup.id, 'version', dup.version);
    end if;
  end if;
  select * into tgt from public.items where id = coalesce(p_item, s.item_id);
  if not found then raise exception 'item_not_found'; end if;
  if tgt.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if exists (select 1 from public.recipe_lines where recipe_id = p_from and active and ingredient_item_id = tgt.id) then raise exception 'ingredient_is_product'; end if;
  select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = tgt.id;
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at, artisan_id)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid(), auth.uid(), now(),
            case when tgt.id = s.item_id and exists (select 1 from public.artisans a where a.id = s.artisan_id and a.active) then s.artisan_id end) returning id into rid;   -- bos73
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
    select rid, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, auth.uid()
      from public.recipe_steps where recipe_id = p_from and active;   -- bos73
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  perform public._rv_log(rid, 'created', null, 'copy of version ' || s.version::text);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $function$$r0_0$, null),
  ('public.recipe_copy(uuid,uuid,boolean,uuid)', 'known', 'b690cbb197ca80cd1731e192ec3ad7a5', null);
-- recipe_cost(uuid,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_cost(uuid,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_cost(p_recipe uuid, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  for n in select * from public._recipe_need(p_recipe, 1, coalesce(p_loc, 0)) order by kind, code loop      -- bos74: the same function the production run uses
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = n.item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null and public._cost_free80(n.item_id) then av := 0; end if;   -- bos103: a free-cost item is a known cost 0 (production_post accepts it the same way)
    td := public._today_cost(n.item_id, p_loc);
    if av is null then complete := false;
    elsif n.kind = 'packaging' then pack_t := pack_t + n.need * av; else raw_t := raw_t + n.need * av; end if;
    if td is null then fb := fb + 1; end if;
    if coalesce(td, av) is not null then
      if n.kind = 'packaging' then pack_d := pack_d + n.need * coalesce(td, av); else raw_d := raw_d + n.need * coalesce(td, av); end if;
    end if;
    gl := case when av is not null and av > 0 and td is not null then round((td - av) / av * 100, 2) end;
    ls := ls || jsonb_build_object('ingredient_item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'need_base', n.need, 'unit_cost', av, 'line_cost', case when av is null then null else round(n.need * av, 4) end,
      'today_unit_cost', td, 'gap_pct', gl, 'waste_missing', n.waste_missing);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, (now() at time zone 'Asia/Dhaka')::date, case when p_loc is null then 'recipe' end);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); mode_ := conv->>'mode'; cinc := mode_ <> 'off' and not (conv->>'complete')::boolean;
  mat := raw_t + pack_t; matd := raw_d + pack_d;
  gap := case when complete and mat > 0 then round((matd - mat) / mat * 100, 2) end;
  thr := public.rule_num('cost_gap_warn_pct');
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete,
    'rows', jsonb_build_array(jsonb_build_object('row', 'raw', 'amount', case when complete then round(raw_t, 4) end), jsonb_build_object('row', 'packaging', 'amount', case when complete then round(pack_t, 4) end),
      jsonb_build_object('row', 'conversion', 'amount', round(conv_amt, 4), 'mode', mode_, 'complete', not cinc)),
    'raw_cost', case when complete then round(raw_t, 4) end, 'packaging_cost', case when complete then round(pack_t, 4) end, 'material_cost', case when complete then round(mat, 4) end,
    'conversion_cost', round(conv_amt, 4), 'conversion_mode', mode_, 'conversion_complete', not cinc, 'conversion_detail', conv->'detail', 'conversion_reason', conv->>'reason',
    'conversion_flag', case when cinc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'batch_cost', case when complete then round(mat + conv_amt, 4) end,
    'unit_cost', case when complete and yb > 0 then round((mat + conv_amt) / yb, 6) end, 'yield_base', yb,
    'approved', r.approved_at is not null, 'approval_warn', gate = 'warn',
    'today', jsonb_build_object('raw_cost', round(raw_d, 4), 'packaging_cost', round(pack_d, 4), 'material_cost', round(matd, 4), 'batch_cost', round(matd + conv_amt, 4),
      'unit_cost', case when yb > 0 then round((matd + conv_amt) / yb, 6) end, 'gap_pct', gap, 'gap_warn', thr is not null and gap is not null and abs(gap) > thr,
      'lines_without_purchase_price', fb, 'note', 'display only - never booked'));
end $function$$r0_0$, null),
  ('public.recipe_cost(uuid,integer)', 'known', 'fa76dd3b2076ca1fd8efec9ed92b3c21', null);
-- recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_cost_component_set(p_recipe uuid, p_type text, p_basis text, p_amount numeric, p_hours numeric DEFAULT NULL::numeric, p_type_note text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d public.recipe_cost_components; nid bigint; tn text := nullif(btrim(p_type_note), '');
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.recipe_cost_components where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if not exists (select 1 from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */) then raise exception 'recipe_not_found'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_type = 'other' and tn is null then raise exception 'type_note_needed'; end if;
  if p_basis not in ('per_batch', 'per_unit', 'per_labour_hour') then raise exception 'bad_value'; end if;
  if p_amount is not null and not (p_amount >= 0 and p_amount <= 1000000000) then raise exception 'bad_cost'; end if;
  if p_hours is not null and not (p_hours >= 0 and p_hours <= 100000) then raise exception 'bad_qty'; end if;
  update public.recipe_cost_components set active = false where recipe_id = p_recipe and component_type = p_type and coalesce(type_note, '') = coalesce(tn, '') and active;
  insert into public.recipe_cost_components (recipe_id, component_type, type_note, basis, amount, hours_per_batch, note, set_by, client_id)
    values (p_recipe, p_type, case when p_type = 'other' then left(tn, 80) end, p_basis, p_amount, case when p_basis = 'per_labour_hour' then p_hours end, left(p_note, 200), auth.uid(), p_client) returning id into nid;
  return jsonb_build_object('id', nid, 'incomplete', p_amount is null or (p_basis = 'per_labour_hour' and p_hours is null));
end $function$$r0_0$, null),
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)', 'known', 'a139406c13fcbfed23116ffb450826b3', null);
-- recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_retire_old boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), ''); prev jsonb; /* bos73 */
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.approved_at is not null then raise exception 'recipe_approved'; end if;   -- bos73
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
    prev := public._recipe_snapshot(p_id);   -- bos73
  else
    if p_client is not null then
      select * into r from public.recipes where client_id = p_client;
      if found then
        if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', r.id, 'version', r.version);
      end if;
    end if;
    select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;
  end if;
  if it.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if public._base_qty(it.id, p_yield_qty, yu) is null then raise exception 'unit_unknown' using detail = it.code; end if;
  perform public._recipe_lines_ok(it.id, p_lines);
  if p_id is null then
    select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = it.id;
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid(), auth.uid(), now()) returning id into rid;   -- bos73: changed_by
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300), changed_by = auth.uid(), changed_at = now() where id = rid;   -- bos73
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  perform public._rv_log(rid, case when p_id is null then 'created' else 'edited' end, prev, null);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $function$$r0_0$, null),
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', 'known', '49944936dcab6b7fadc033befd0e3530', null);
-- recipe_steps_save(uuid,jsonb,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_steps_save(uuid,jsonb,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_steps_save(p_recipe uuid, p_steps jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; s jsonb; n int := 0; prev jsonb; mins numeric; ppl int; fu text; rp text; dup public.recipe_versions;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into dup from public.recipe_versions where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'recipe_id', dup.recipe_id); end if;
  end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then raise exception 'recipe_approved'; end if;
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' then raise exception 'bad_value'; end if;
  if jsonb_array_length(p_steps) > 100 then raise exception 'too_many_lines'; end if;
  for s in select x from jsonb_array_elements(p_steps) x loop
    if length(btrim(coalesce(s->>'step_name', ''))) = 0 then raise exception 'step_name_needed'; end if;
    mins := nullif(btrim(s->>'minutes'), '')::numeric;
    if mins is not null and not (mins >= 0 and mins <= 100000) then raise exception 'bad_qty'; end if;
    ppl := nullif(btrim(s->>'people'), '')::int;
    if ppl is not null and not (ppl >= 0 and ppl <= 1000) then raise exception 'bad_qty'; end if;
    fu := nullif(btrim(s->>'fuel'), '');
    if fu is not null and fu not in ('gas', 'electric', 'other') then raise exception 'bad_value'; end if;
    if fu = 'other' and length(btrim(coalesce(s->>'fuel_other', ''))) = 0 then raise exception 'fuel_other_needed'; end if;
    rp := nullif(btrim(s->>'resp_post'), '');
    if rp is not null and rp not in ('karigor', 'chef', 'asst_karigor', 'other') then raise exception 'bad_post'; end if;
  end loop;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipe_steps set active = false where recipe_id = p_recipe and active;          -- old steps are retired, never deleted
  for s in select x from jsonb_array_elements(p_steps) x loop
    n := n + 1;
    insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
      values (p_recipe, n, left(btrim(s->>'step_name'), 120), left(nullif(btrim(s->>'description'), ''), 2000), nullif(btrim(s->>'minutes'), '')::numeric, nullif(btrim(s->>'people'), '')::int,
        nullif(btrim(s->>'fuel'), ''), case when s->>'fuel' = 'other' then left(btrim(s->>'fuel_other'), 60) end, left(nullif(btrim(s->>'flame_note'), ''), 200), left(nullif(btrim(s->>'equipment'), ''), 200),
        left(nullif(btrim(s->>'qc_note'), ''), 300), nullif(btrim(s->>'resp_post'), ''), case when s->>'resp_post' = 'other' then left(btrim(s->>'resp_other'), 60) end, auth.uid());
  end loop;
  update public.recipes set changed_by = auth.uid(), changed_at = now() where id = p_recipe;
  perform public._rv_log(p_recipe, 'steps_edited', prev, n::text || ' steps', p_client);
  return jsonb_build_object('recipe_id', p_recipe, 'steps', n) || (public.recipe_labour_suggest(p_recipe));
end $function$$r0_0$, null),
  ('public.recipe_steps_save(uuid,jsonb,uuid)', 'known', '64bcda698a159f90c96c74e099c8e72e', null);
-- recipe_yield_suggestion(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_yield_suggestion(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_yield_suggestion(p_recipe uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; e record; lines_ jsonb;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  select x.serial, x.entry_date, x.location_id, x.w into e from (
    select en.serial, en.entry_date, en.location_id,
           (select avg(public._r2_num(b -> 'waste') / nullif(coalesce(public._r2_num(b -> 'good'), 0) + coalesce(public._r2_num(b -> 'second'), 0) + coalesce(public._r2_num(b -> 'waste'), 0), 0) * 100)
              from jsonb_array_elements(public._p26_arr(en.data -> 'b')) b where public._r2_num(b -> 'waste') is not null) as w
      from public.entries en where en.form_code = '05-4' and en.status = 'approved' and en.data ->> 'item' = it.code and public.can_loc(en.location_id)
     order by en.entry_date desc, en.serial desc limit 1) x;
  select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'waste_pct', l.waste_pct) order by l.sort, l.id), '[]'::jsonb) into lines_
    from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id where l.recipe_id = p_recipe and l.active;
  return jsonb_build_object('recipe_id', p_recipe, 'suggested_waste_pct', case when e.w is null then null else round(e.w, 2) end, 'source_serial', e.serial, 'source_date', e.entry_date,
    'recipe_lines_waste', lines_, 'note', 'suggestion_only', 'applied', false);
end $function$$r0_0$, null),
  ('public.recipe_yield_suggestion(uuid)', 'known', 'ee5672da78a73843eacb64f6ebbea0a0', null);
do $u537$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase537: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase537: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase537: % function(s) changed', nfix;
end $u537$;
drop table if exists _u_plan;

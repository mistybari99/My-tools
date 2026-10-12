-- ============================================================
-- PHASE 22 (item master P1): bulk item editor + old-item decision tools. Additive and idempotent (paste twice = no error).
-- Needs phase14 (item master). Run after phase8..phase21.
--   1  grant item_bulk, rules items_hide_unpriced_in_pos (ON) and item_map_accept_min_conf (empty)
--   2  item_bulk_batches: one append-only audit row per applied batch
--   3  items_bulk_apply(changes, dry, batch, note): validates every row, dry-run writes nothing, owner / item_bulk / item_create apply at once,
--      others create item_changes requests; idempotent by client batch id; max 200 rows; cost only when the owner sends it
--   4  mapping decisions of the 57 old items: item_map_decide2 (link / keep / later / use_dict / undo), item_map_accept_confident
-- Nothing is deleted. Cost prices are never read or written here unless the owner sends cost_price in a row.
-- ============================================================

-- ---------- 1. grant and rules ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'item_bulk', 'master', 61, 'অনেক আইটেমের দাম / একক / স্টক একসাথে বদল (অনুমোদন ছাড়া)', 'অনেক item-এর দাম / unit / stock একসাথে বদল (approval ছাড়া)',
       'Change prices / units / stock settings of many items at once (no approval)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'item_bulk');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('items_hide_unpriced_in_pos', 'settings', 'switch', 'true', null, null, null, null, 'দাম ছাড়া আইটেম পিকারে দেখাবে না', 'দাম ছাড়া item picker-এ দেখাবে না', 'Hide items without a price from the pickers',
  'POS-এ দাম ছাড়া আইটেম কখনোই বিক্রি হয় না; এটি তালিকা ও পিকারে "দাম বাকি" আইটেম লুকাতে সাহায্য করে', 'POS never sells an item without a price; this keeps "Data needed" items out of the pickers', 70),
 ('item_map_accept_min_conf', 'settings', 'number', null, null, null, 0, 1, 'পুরনো আইটেম: "সব নিশ্চিত মিল মানুন"-এর সর্বনিম্ন মিল (০-১)', 'পুরনো item: "সব confident মিল মানুন"-এর minimum match (0-1)', 'Old items: minimum match (0-1) for "accept all high-confidence"',
  'ফাঁকা = শুধু যেগুলোকে আমদানির সময় নিশ্চিত (auto) ধরা হয়েছে', 'Empty = only the ones marked auto (high confidence) at import', 71)
 on conflict (key) do nothing;

-- ---------- 2. audit table ----------
create table if not exists public.item_bulk_batches (
  id bigserial primary key,
  client_batch text not null,
  created_by uuid not null, created_staff text,
  mode text not null check (mode in ('direct', 'requests')),
  note text,
  rows_n int not null, ok_n int not null default 0, requested_n int not null default 0, skipped_n int not null default 0, error_n int not null default 0,
  results jsonb not null default '[]',
  created_at timestamptz not null default now()
);
create unique index if not exists item_bulk_batches_client_uq on public.item_bulk_batches (created_by, client_batch);
alter table public.item_bulk_batches enable row level security;
drop policy if exists item_bulk_batches_read on public.item_bulk_batches;
create policy item_bulk_batches_read on public.item_bulk_batches for select to authenticated
  using (created_by = auth.uid() or public.is_owner() or public.has_grant('item_bulk'));
revoke all on public.item_bulk_batches from public, anon, authenticated;
grant select on public.item_bulk_batches to authenticated;

create or replace function public._append_only22() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists item_bulk_batches_ro on public.item_bulk_batches;
create trigger item_bulk_batches_ro before update or delete on public.item_bulk_batches for each row execute function public._append_only22();
drop trigger if exists item_bulk_batches_ro_t on public.item_bulk_batches;
create trigger item_bulk_batches_ro_t before truncate on public.item_bulk_batches for each statement execute function public._append_only22();

-- ---------- 3. bulk apply ----------
create or replace function public._bulk_bool(p jsonb) returns boolean language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if p is null or p = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p) = 'boolean' then return (p #>> '{}')::boolean; end if;
  s := lower(btrim(p #>> '{}'));
  if s in ('true', 'yes', 'y', '1', 'on', 'হ্যাঁ') then return true; end if;
  if s in ('false', 'no', 'n', '0', 'off', 'না') then return false; end if;
  raise exception 'bad_flag';
end $$;

create or replace function public._bulk_num(p jsonb, p_what text) returns numeric language plpgsql immutable set search_path = public as $$
declare s text := nullif(btrim(coalesce(p #>> '{}', '')), '');
begin
  if s is null then return null; end if;
  -- plain digits only: no sign, no exponent, no NaN / Infinity (a numeric can hold them)
  if s !~ '^[0-9]{1,10}(\.[0-9]{1,6})?$' or s::numeric > 1000000000 or not (s::numeric between 0 and 1000000000) then raise exception 'bad_price:%', p_what; end if;
  return s::numeric;
end $$;

create or replace function public.items_bulk_apply(p_changes jsonb, p_dry boolean default false, p_batch text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); direct boolean; mode text; e jsonb; i int := 0; it public.items; patch jsonb; chg jsonb; res jsonb := '[]'::jsonb;
  st text; why text; n_ok int := 0; n_req int := 0; n_skip int := 0; n_err int := 0; seen uuid[] := '{}'; k text; num numeric; u text; b boolean; cur_cost numeric;
  sid text; ex public.item_bulk_batches; bid bigint; eff_count boolean; cname text;
begin
  if uid is null or not public.is_active() then raise exception 'not allowed'; end if;
  direct := public.is_owner() or public.has_grant('item_bulk') or public.has_grant('item_create');
  if not (direct or public.can_do('ITEMS', 'enter')) then raise exception 'not allowed'; end if;
  mode := case when direct then 'direct' else 'requests' end;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_changes) > 200 then raise exception 'too_many_rows'; end if;
  if not coalesce(p_dry, false) then
    if nullif(btrim(coalesce(p_batch, '')), '') is null or length(p_batch) > 80 then raise exception 'batch_required'; end if;
    perform pg_advisory_xact_lock(hashtext('items_bulk:' || uid::text || ':' || p_batch));
    select * into ex from public.item_bulk_batches where created_by = uid and client_batch = p_batch;
    if found then
      return jsonb_build_object('dry', false, 'already', true, 'mode', ex.mode, 'batch', ex.client_batch, 'batch_id', ex.id, 'rows', ex.rows_n, 'ok', ex.ok_n, 'requested', ex.requested_n,
        'skipped', ex.skipped_n, 'error', ex.error_n, 'results', ex.results);
    end if;
  end if;
  select staff_id into sid from public.profiles where id = uid;

  for e in select x from jsonb_array_elements(p_changes) x loop
    i := i + 1; st := 'ok'; why := null; chg := '{}'::jsonb; patch := '{}'::jsonb; it := null;
    begin
      if jsonb_typeof(e) <> 'object' then raise exception 'bad_row'; end if;
      if nullif(btrim(coalesce(e->>'item_id', '')), '') is not null then
        if (e->>'item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'item_not_found'; end if;
        select * into it from public.items where id = (e->>'item_id')::uuid;
      elsif nullif(btrim(coalesce(e->>'code', '')), '') is not null then
        select * into it from public.items where code = btrim(e->>'code');
      end if;
      if it.id is null then raise exception 'item_not_found'; end if;
      if it.id = any(seen) then raise exception 'duplicate_row'; end if;
      seen := seen || it.id;
      for k in select jsonb_object_keys(e) loop
        if k not in ('item_id', 'code', 'sell_price', 'wholesale_price', 'unit', 'tracked', 'min_stock', 'count_in_business', 'sellable', 'hidden', 'is_active', 'reason', 'name_bn', 'name_en', 'cost_price') then
          raise exception 'bad_field:%', k;
        end if;
      end loop;
      if it.locked then raise exception 'skip:locked'; end if;
      if exists (select 1 from public.item_map_actions a where a.action = 'use_dict' and (a.item_id = it.id or a.dict_code = it.code)
                 and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id)) then raise exception 'skip:replaced'; end if;
      eff_count := it.count_in_business;

      if e ? 'cost_price' and nullif(btrim(coalesce(e->>'cost_price', '')), '') is not null then      -- costs: owner only, explicit column
        if not public.is_owner() then raise exception 'cost_owner_only'; end if;
        num := public._bulk_num(e->'cost_price', 'cost');
        select cost_price into cur_cost from public.item_costs where item_id = it.id;
        if cur_cost is distinct from num then patch := patch || jsonb_build_object('cost_price', num::text); chg := chg || jsonb_build_object('cost_price', jsonb_build_array('(hidden)', '(hidden)')); end if;
      end if;
      if e ? 'sell_price' then num := public._bulk_num(e->'sell_price', 'sell');
        if num = 0 then raise exception 'bad_price:sell'; end if;                    -- a selling price of 0 is never set in bulk
        if num is not null and it.sell_price is distinct from num then patch := patch || jsonb_build_object('sell_price', num::text); chg := chg || jsonb_build_object('sell_price', jsonb_build_array(it.sell_price, num)); end if; end if;
      if e ? 'wholesale_price' then num := public._bulk_num(e->'wholesale_price', 'wholesale');
        if num is not null and it.wholesale_price is distinct from num then patch := patch || jsonb_build_object('wholesale_price', num::text); chg := chg || jsonb_build_object('wholesale_price', jsonb_build_array(it.wholesale_price, num)); end if; end if;
      if e ? 'min_stock' then num := public._bulk_num(e->'min_stock', 'min_stock');
        if num is not null and it.min_stock is distinct from num then patch := patch || jsonb_build_object('min_stock', num::text); chg := chg || jsonb_build_object('min_stock', jsonb_build_array(it.min_stock, num)); end if; end if;
      if e ? 'unit' and nullif(btrim(coalesce(e->>'unit', '')), '') is not null then
        u := coalesce(public._item_unit_code(btrim(e->>'unit')), btrim(e->>'unit'));
        if u not in ('kg', 'pc', 'lb') and not exists (select 1 from public.option_lists where list_code = 'units' and value_code = u and active) then raise exception 'bad_unit'; end if;
        if it.unit is distinct from u then patch := patch || jsonb_build_object('unit', u); chg := chg || jsonb_build_object('unit', jsonb_build_array(it.unit, u)); end if;
      end if;
      if e ? 'name_bn' and nullif(btrim(coalesce(e->>'name_bn', '')), '') is not null then
        if length(e->>'name_bn') > 200 then raise exception 'name_too_long'; end if;
        if it.name_bn is distinct from btrim(e->>'name_bn') then patch := patch || jsonb_build_object('name_bn', btrim(e->>'name_bn')); chg := chg || jsonb_build_object('name_bn', jsonb_build_array(it.name_bn, btrim(e->>'name_bn'))); end if;
      end if;
      if e ? 'name_en' and e->>'name_en' is not null then
        if length(e->>'name_en') > 200 then raise exception 'name_too_long'; end if;
        if it.name_en is distinct from nullif(btrim(e->>'name_en'), '') then patch := patch || jsonb_build_object('name_en', btrim(e->>'name_en')); chg := chg || jsonb_build_object('name_en', jsonb_build_array(it.name_en, nullif(btrim(e->>'name_en'), ''))); end if;
      end if;
      if e ? 'count_in_business' then b := public._bulk_bool(e->'count_in_business');
        if b is not null and b is distinct from it.count_in_business then
          if b and it.item_type = 'asset' then raise exception 'type_not_counted'; end if;
          if not b and exists (select 1 from public.stock_balance where item_id = it.id and qty <> 0) then raise exception 'item_has_stock'; end if;
          patch := patch || jsonb_build_object('count_in_business', b); chg := chg || jsonb_build_object('count_in_business', jsonb_build_array(it.count_in_business, b)); eff_count := b; end if; end if;
      if e ? 'tracked' then b := public._bulk_bool(e->'tracked');
        if b is not null and b is distinct from it.tracked then
          if b and not eff_count then raise exception 'tracked_needs_count'; end if;
          patch := patch || jsonb_build_object('tracked', b); chg := chg || jsonb_build_object('tracked', jsonb_build_array(it.tracked, b)); end if; end if;
      if e ? 'sellable' then b := public._bulk_bool(e->'sellable');
        if b is not null and b is distinct from it.sellable then
          if b and it.item_type in ('asset', 'raw_material') then raise exception 'type_not_sellable'; end if;
          patch := patch || jsonb_build_object('sellable', b); chg := chg || jsonb_build_object('sellable', jsonb_build_array(it.sellable, b)); end if; end if;
      if e ? 'hidden' then b := public._bulk_bool(e->'hidden');
        if b is not null and b is distinct from it.hidden then patch := patch || jsonb_build_object('hidden', b); chg := chg || jsonb_build_object('hidden', jsonb_build_array(it.hidden, b)); end if; end if;
      if e ? 'is_active' then b := public._bulk_bool(e->'is_active');
        if b is not null and b is distinct from it.is_active then
          if not b then
            if exists (select 1 from public.stock_balance where item_id = it.id and qty <> 0) then raise exception 'item_has_stock'; end if;
            if exists (select 1 from public.item_master_links l where l.active and (l.item_id = it.id or l.dict_code = it.code)) then raise exception 'item_linked'; end if;
          end if;
          patch := patch || jsonb_build_object('is_active', b); chg := chg || jsonb_build_object('is_active', jsonb_build_array(it.is_active, b));
          if not b then patch := patch || jsonb_build_object('retired_reason', left(coalesce(nullif(btrim(e->>'reason'), ''), nullif(btrim(p_note), ''), 'bulk'), 200)); end if;
        end if; end if;

      if patch = '{}'::jsonb then
        st := 'skipped'; why := 'nochange';
      elsif not coalesce(p_dry, false) then
        perform set_config('bos.item_apply', '1', true);
        if direct then
          perform public.apply_item_patch(it.id, patch);
          st := 'ok';
        else
          if patch ? 'cost_price' then raise exception 'cost_owner_only'; end if;
          perform public._item_patch_check(patch);
          insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (it.id, patch, left(coalesce(p_note, 'bulk'), 300), uid, sid);
          st := 'requested';
        end if;
        perform set_config('bos.item_apply', '', true);
      else
        st := case when direct then 'ok' else 'requested' end;
      end if;
    exception when others then
      perform set_config('bos.item_apply', '', true);
      if sqlerrm like 'skip:%' then st := 'skipped'; why := substr(sqlerrm, 6);
      else st := 'error'; why := left(sqlerrm, 120); end if;
      chg := '{}'::jsonb;
    end;
    if st = 'ok' then n_ok := n_ok + 1; elsif st = 'requested' then n_req := n_req + 1; elsif st = 'skipped' then n_skip := n_skip + 1; else n_err := n_err + 1; end if;
    res := res || jsonb_build_array(jsonb_build_object('i', i, 'item_id', it.id, 'code', coalesce(it.code, e->>'code'), 'status', st, 'reason', why, 'changes', chg));
  end loop;

  if coalesce(p_dry, false) then
    return jsonb_build_object('dry', true, 'mode', mode, 'rows', i, 'ok', n_ok, 'requested', n_req, 'skipped', n_skip, 'error', n_err, 'results', res);
  end if;
  insert into public.item_bulk_batches (client_batch, created_by, created_staff, mode, note, rows_n, ok_n, requested_n, skipped_n, error_n, results)
    values (p_batch, uid, sid, mode, left(p_note, 300), i, n_ok, n_req, n_skip, n_err, res) returning id into bid;
  return jsonb_build_object('dry', false, 'already', false, 'mode', mode, 'batch', p_batch, 'batch_id', bid, 'rows', i, 'ok', n_ok, 'requested', n_req, 'skipped', n_skip, 'error', n_err, 'results', res);
end $$;
revoke all on function public.items_bulk_apply(jsonb, boolean, text, text), public._bulk_bool(jsonb), public._bulk_num(jsonb, text) from public, anon, authenticated;
grant execute on function public.items_bulk_apply(jsonb, boolean, text, text) to authenticated;

-- ---------- 4. old item decisions ----------
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid = 'public.item_mapping_review'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%status%';
  if c is not null and exists (select 1 from pg_constraint where conname = c and pg_get_constraintdef(oid) not like '%replaced%') then
    execute format('alter table public.item_mapping_review drop constraint %I', c);
    alter table public.item_mapping_review add constraint item_mapping_review_status_chk check (status in ('pending', 'linked', 'rejected', 'later', 'replaced'));
  end if;
end $$;

create table if not exists public.item_map_actions (
  id bigserial primary key,
  item_id uuid not null references public.items(id),             -- the old item
  dict_code text,
  action text not null check (action in ('link', 'keep', 'later', 'use_dict', 'undo_use_dict', 'undo', 'accept_all')),
  before jsonb not null default '{}', ref_id bigint, note text,
  created_by uuid, created_at timestamptz not null default now()
);
alter table public.item_map_actions enable row level security;
drop policy if exists item_map_actions_read on public.item_map_actions;
create policy item_map_actions_read on public.item_map_actions for select to authenticated using (public.is_owner() or public.has_grant('item_create'));
revoke all on public.item_map_actions from public, anon, authenticated;
grant select on public.item_map_actions to authenticated;
drop trigger if exists item_map_actions_ro on public.item_map_actions;
create trigger item_map_actions_ro before update or delete on public.item_map_actions for each row execute function public._append_only22();
drop trigger if exists item_map_actions_ro_t on public.item_map_actions;
create trigger item_map_actions_ro_t before truncate on public.item_map_actions for each statement execute function public._append_only22();

-- link / keep / later / use_dict / undo of ONE old item. 'use_dict' (copy price + unit to the dictionary item, retire the old item) is the owner's only.
create or replace function public.item_map_decide2(p_item uuid, p_action text, p_dict text default null, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lg public.items; dc public.items; rv public.item_mapping_review; act public.item_map_actions; aid bigint; f record; cur_status text; dstock boolean; bc_moved boolean := false;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_action not in ('link', 'keep', 'later', 'use_dict', 'undo') then raise exception 'bad_request'; end if;
  select * into lg from public.items where id = p_item and import_batch is null;
  if not found then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  select * into rv from public.item_mapping_review where item_id = p_item;
  cur_status := rv.status;

  if p_action = 'link' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, p_dict, 'linked', p_note, p_force);
    insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (p_item, btrim(p_dict), 'link', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'linked');
  elsif p_action = 'keep' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, null, 'rejected', p_note);
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'keep', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'rejected');
  elsif p_action = 'later' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    if cur_status in ('linked', 'rejected') then perform public.item_mapping_decide(p_item, null, 'pending', p_note); end if;
    update public.item_mapping_review set status = 'later', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'later', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'later');
  elsif p_action = 'undo' then
    if cur_status = 'replaced' then
      if not public.is_owner() then raise exception 'not allowed'; end if;           -- undoing a replacement is the owner's only
      select * into act from public.item_map_actions a where a.item_id = p_item and a.action = 'use_dict'
         and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id) order by a.id desc limit 1;
      if not found then raise exception 'nothing_to_undo'; end if;
      select * into dc from public.items where code = act.dict_code and import_batch is not null;
      if (found and dc.locked) or lg.locked then raise exception 'item_locked'; end if;
      if found and not coalesce(p_force, false) and (dc.sell_price is distinct from (act.before->'dict'->>'new_price')::numeric) then raise exception 'changed_since'; end if;
      perform set_config('bos.item_sys', '1', true);
      if found then
        update public.items set sell_price = (act.before->'dict'->>'sell_price')::numeric, wholesale_price = (act.before->'dict'->>'wholesale_price')::numeric, unit = act.before->'dict'->>'unit',
          hidden = (act.before->'dict'->>'hidden')::boolean, sellable = (act.before->'dict'->>'sellable')::boolean, barcode = act.before->'dict'->>'barcode' where id = dc.id;
      end if;
      update public.items set barcode = coalesce(act.before->'legacy'->>'barcode', barcode) where id = p_item and act.before->'legacy'->>'barcode' is not null;
      update public.items set is_active = (act.before->'legacy'->>'is_active')::boolean, retired_at = (act.before->'legacy'->>'retired_at')::timestamptz,
        retired_reason = act.before->'legacy'->>'retired_reason' where id = p_item;
      perform set_config('bos.item_sys', '', true);
      update public.item_mapping_review set status = 'pending', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
      insert into public.item_map_actions (item_id, dict_code, action, ref_id, note, created_by) values (p_item, act.dict_code, 'undo_use_dict', act.id, left(p_note, 300), auth.uid());
    else
      perform public.item_mapping_decide(p_item, null, 'pending', p_note);
      insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'undo', left(p_note, 300), auth.uid());
    end if;
    return jsonb_build_object('status', 'pending');
  end if;

  -- use_dict
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if cur_status = 'replaced' then raise exception 'already_replaced'; end if;
  if lg.master_code is not null then raise exception 'unlink_first'; end if;
  if not lg.is_active then raise exception 'item_inactive'; end if;
  if lg.locked then raise exception 'item_locked'; end if;
  if lg.sell_price is null then raise exception 'legacy_has_no_price'; end if;
  if exists (select 1 from public.stock_balance where item_id = lg.id and qty <> 0) then raise exception 'legacy_has_stock'; end if;
  select * into dc from public.items where code = btrim(coalesce(p_dict, '')) and import_batch is not null for update;
  if not found then raise exception 'master_code_not_found'; end if;
  if not dc.is_active then raise exception 'dict_retired'; end if;
  if dc.locked then raise exception 'item_locked'; end if;
  if dc.item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled') and not coalesce(p_force, false) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = dc.code and active) then raise exception 'master_code_taken'; end if;
  if exists (select 1 from public.item_map_actions a where a.dict_code = dc.code and a.action = 'use_dict'
             and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id)) then raise exception 'master_code_taken'; end if;
  dstock := exists (select 1 from public.stock_balance where item_id = dc.id and qty <> 0);
  if dstock and dc.unit is distinct from lg.unit then raise exception 'dict_unit_has_stock'; end if;      -- never re-label units under stock (no override)
  if not coalesce(p_force, false) then                                                                        -- the owner can confirm these
    if dstock then raise exception 'dict_has_stock'; end if;
    if dc.sell_price is not null and dc.sell_price is distinct from lg.sell_price then raise exception 'dict_price_differs'; end if;
    if dc.unit is not null and dc.unit is distinct from lg.unit then raise exception 'dict_unit_differs'; end if;
  end if;
  select * into f from public._item_type_flags(dc.item_type);
  perform set_config('bos.item_sys', '1', true);
  insert into public.item_map_actions (item_id, dict_code, action, before, note, created_by) values (lg.id, dc.code, 'use_dict', jsonb_build_object(
      'dict', jsonb_build_object('sell_price', dc.sell_price, 'wholesale_price', dc.wholesale_price, 'unit', dc.unit, 'hidden', dc.hidden, 'sellable', dc.sellable, 'new_price', lg.sell_price, 'barcode', dc.barcode),
      'legacy', jsonb_build_object('is_active', lg.is_active, 'retired_at', lg.retired_at, 'retired_reason', lg.retired_reason, 'barcode', case when lg.barcode is not null and dc.barcode is null then lg.barcode end)), left(p_note, 300), auth.uid()) returning id into aid;
  if lg.barcode is not null and dc.barcode is null then            -- the barcode on the shelf now scans the dictionary item (the legacy one is cleared first: barcodes are unique)
    update public.items set barcode = null where id = lg.id; bc_moved := true;
  end if;
  update public.items set sell_price = lg.sell_price, wholesale_price = coalesce(lg.wholesale_price, wholesale_price), unit = lg.unit, hidden = false, sellable = coalesce(f.o_sell, sellable),
    barcode = case when bc_moved then lg.barcode else barcode end where id = dc.id;
  update public.items set is_active = false, retired_at = coalesce(retired_at, now()), retired_reason = 'replaced by ' || dc.code where id = lg.id;
  perform set_config('bos.item_sys', '', true);
  update public.item_mapping_review set status = 'replaced', suggested_code = dc.code, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  return jsonb_build_object('status', 'replaced', 'action_id', aid, 'dict_code', dc.code, 'barcode_moved', bc_moved, 'barcode_kept', (lg.barcode is not null and not bc_moved));
end $$;

-- accept every suggestion that is high confidence: marked auto at import, or match >= rule item_map_accept_min_conf. p_dry = only count.
create or replace function public.item_map_accept_confident(p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; mn numeric; codes text[] := '{}'; skipped int := 0;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  mn := public.rule_num('item_map_accept_min_conf');
  for r in select m.* from public.item_mapping_review m where m.status in ('pending', 'later') and m.suggested_code is not null
           and (m.auto_ok or (mn is not null and m.confidence >= mn)) order by m.id loop
    if not exists (select 1 from public.items t where t.code = r.suggested_code and t.import_batch is not null and t.is_active)
       or exists (select 1 from public.item_master_links l where l.dict_code = r.suggested_code and l.active and l.item_id <> r.item_id)
       or exists (select 1 from public.items t where t.id = r.item_id and t.master_code is not null) then skipped := skipped + 1; continue; end if;
    begin
      if not coalesce(p_dry, true) then
        perform public._item_link(r.item_id, r.suggested_code, 'accepted', false);
        update public.item_mapping_review set status = 'linked', decided_by = auth.uid(), decided_at = now(), note = 'accepted (high confidence)' where id = r.id;
        insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (r.item_id, r.suggested_code, 'accept_all', 'high confidence', auth.uid());
      end if;
      n := n + 1; codes := codes || (select code from public.items where id = r.item_id);
    exception when others then skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accepted', n, 'skipped', skipped, 'codes', to_jsonb(codes));
end $$;
revoke all on function public.item_map_decide2(uuid, text, text, text, boolean), public.item_map_accept_confident(boolean), public._append_only22() from public, anon, authenticated;
grant execute on function public.item_map_decide2(uuid, text, text, text, boolean), public.item_map_accept_confident(boolean) to authenticated;

-- ---------- 5. a late offline sale of an item retired in the meantime ----------
-- record_sale2 refuses an inactive item. A sale made OFFLINE before the item was retired (sold_at older than 2 minutes, item changed after the sale) is accepted and flagged red
-- ('offline_sale_item_changed', the same exception phase14 raises for flag / price changes). Online sales of an inactive item stay refused. Text patch of the current definition
-- (not a rewrite), marker bos22-late; a second trigger sets the flag so phase14's own guard function is not replaced.
do $$
declare o oid; d text;
begin
  select p.oid into o from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'record_sale2' and p.prokind = 'f' limit 1;
  if o is not null then
    d := pg_get_functiondef(o);
    if position('bos22-late' in d) = 0 and position('if not found or not it.is_active then raise exception ''item_not_found''; end if;' in d) > 0 then
      d := replace(d, 'if not found or not it.is_active then raise exception ''item_not_found''; end if;',
        'if not found then raise exception ''item_not_found''; end if; /* bos22-late */ if not it.is_active and not (at_ < now() - interval ''2 minutes'' and it.updated_at > at_) then raise exception ''item_not_found''; end if;');
      execute d;
    end if;
  end if;
end $$;
create or replace function public._sale_item_guard22() returns trigger language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items;
begin
  if new.lines is null or jsonb_typeof(new.lines) <> 'array' or new.sold_at >= now() - interval '2 minutes' then return new; end if;
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if found and not it.is_active and it.updated_at > new.sold_at then perform set_config('bos.offline_item_changed', new.id::text, true); end if;
  end loop;
  return new;
end $$;
drop trigger if exists sales_item_guard22 on public.sales;
create trigger sales_item_guard22 before insert on public.sales for each row execute function public._sale_item_guard22();
revoke all on function public._sale_item_guard22() from public, anon, authenticated;

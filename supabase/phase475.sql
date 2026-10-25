-- Phase 475 (RPT-HUB, part 6): each person's favourites, recently opened reports, saved views and Home pins; export log.
--   rpt_hub_my()                          the caller's own lists (favourites, recent, saved views, pins)
--   rpt_hub_item_save(kind, key, name, params)   add a favourite / saved view / pin (at most 100 of each kind per person)
--   rpt_hub_item_remove(id)               remove one of the caller's own items
--   rpt_hub_touch(key, params)            note that a report / tool was opened (keeps the latest 30 per person)
--   rpt_hub_log_export(key, filters, rows) one audit_log line for a CSV export from the hub (needs the export right)
-- A person reads and changes only their own rows (row level security on rpthub_user_items). No business figure is read or written here.
-- Safe to paste twice. Needs phase470.
do $$ begin if to_regclass('public.rpthub_user_items') is null then raise exception 'rpthub_needs_phase470'; end if; end $$;

create or replace function public.rpt_hub_my() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare u uuid := auth.uid();
begin
  if u is null or not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('generated_at', now(),
    'fav',    coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', i.item_key, 'name', i.name, 'params', i.params, 'at', i.last_opened_at) order by i.created_at desc) from public.rpthub_user_items i where i.user_id = u and i.kind = 'fav'), '[]'::jsonb),
    'view',   coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', i.item_key, 'name', i.name, 'params', i.params, 'at', i.last_opened_at) order by i.created_at desc) from public.rpthub_user_items i where i.user_id = u and i.kind = 'view'), '[]'::jsonb),
    'pin',    coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', i.item_key, 'name', i.name, 'params', i.params, 'at', i.last_opened_at) order by i.created_at desc) from public.rpthub_user_items i where i.user_id = u and i.kind = 'pin'), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'key', i.item_key, 'name', i.name, 'params', i.params, 'at', i.last_opened_at, 'count', i.open_count) order by i.last_opened_at desc) from (select * from public.rpthub_user_items r where r.user_id = u and r.kind = 'recent' order by r.last_opened_at desc limit 30) i), '[]'::jsonb));
end $$;

create or replace function public.rpt_hub_item_save(p_kind text, p_key text, p_name text default null, p_params jsonb default '{}'::jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); id_ bigint; nm text := nullif(btrim(coalesce(p_name, '')), '');
begin
  if u is null or not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind not in ('fav', 'view', 'pin') then raise exception 'bad_kind'; end if;
  if p_key is null or length(btrim(p_key)) < 1 or length(p_key) > 80 then raise exception 'bad_key'; end if;
  if p_kind = 'view' and nm is null then raise exception 'name_required'; end if;
  if nm is not null and length(nm) > 80 then raise exception 'name_too_long'; end if;
  if p_params is null or jsonb_typeof(p_params) <> 'object' or pg_column_size(p_params) > 4000 then raise exception 'bad_params'; end if;
  if (select count(*) from public.rpthub_user_items where user_id = u and kind = p_kind) >= 100
     and not exists (select 1 from public.rpthub_user_items where user_id = u and kind = p_kind and item_key = p_key and coalesce(name, '') = coalesce(nm, '')) then raise exception 'too_many'; end if;
  insert into public.rpthub_user_items (user_id, kind, item_key, name, params) values (u, p_kind, btrim(p_key), nm, p_params)
    on conflict (user_id, kind, item_key, (coalesce(name, ''))) do update set params = excluded.params, last_opened_at = now()
    returning id into id_;
  return id_;
end $$;

create or replace function public.rpt_hub_item_remove(p_id bigint) returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null or not public.is_active() then raise exception 'not allowed'; end if;
  delete from public.rpthub_user_items where id = p_id and user_id = auth.uid(); get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.rpt_hub_touch(p_key text, p_params jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid();
begin
  if u is null or not public.is_active() then raise exception 'not allowed'; end if;
  if p_key is null or length(btrim(p_key)) < 1 or length(p_key) > 80 then raise exception 'bad_key'; end if;
  if p_params is null or jsonb_typeof(p_params) <> 'object' or pg_column_size(p_params) > 4000 then p_params := '{}'::jsonb; end if;
  insert into public.rpthub_user_items (user_id, kind, item_key, name, params, open_count) values (u, 'recent', btrim(p_key), null, p_params, 1)
    on conflict (user_id, kind, item_key, (coalesce(name, ''))) do update set last_opened_at = now(), open_count = public.rpthub_user_items.open_count + 1, params = excluded.params;
  delete from public.rpthub_user_items d where d.user_id = u and d.kind = 'recent'
     and d.id not in (select r.id from public.rpthub_user_items r where r.user_id = u and r.kind = 'recent' order by r.last_opened_at desc limit 30);
end $$;

create or replace function public.rpt_hub_log_export(p_key text, p_filters jsonb, p_rows int) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._rh_area_ok('export') then raise exception 'not allowed'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._rh_staff(auth.uid()), 'hub_export', 'rpt_hub', left(coalesce(p_key, ''), 80), jsonb_build_object('filters', coalesce(p_filters, '{}'::jsonb), 'rows', p_rows));
end $$;

revoke all on function public.rpt_hub_my(), public.rpt_hub_item_save(text, text, text, jsonb), public.rpt_hub_item_remove(bigint), public.rpt_hub_touch(text, jsonb), public.rpt_hub_log_export(text, jsonb, int) from public, anon;
grant execute on function public.rpt_hub_my(), public.rpt_hub_item_save(text, text, text, jsonb), public.rpt_hub_item_remove(bigint), public.rpt_hub_touch(text, jsonb), public.rpt_hub_log_export(text, jsonb, int) to authenticated;

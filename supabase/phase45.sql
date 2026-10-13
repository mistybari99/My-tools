-- Phase 45 · Module E: Owner mode board (customisable "must check" list).
-- Per-user widget list for the owner. The widget KINDS live in web/ownerboard.js (data-driven); this file stores which ones the owner picked,
-- their order, size, thresholds and notes. Additive + idempotent. Writes go only through owner_board_save (SECURITY DEFINER, owner only).
--   owner_board_get()        -> jsonb array of this owner's widgets (sorted)              [owner only]
--   owner_board_save(items)  -> replaces this owner's list atomically, returns the count   [owner only, max 60, validated]
-- Switch: rules key owner_board_on (default ON). OFF = the save is refused and the web page falls back to the normal Home.

create table if not exists public.owner_board_items (
  id bigserial primary key,
  user_id uuid not null,
  widget text not null,
  config jsonb not null default '{}'::jsonb,
  sort int not null default 0,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint owner_board_widget_chk check (widget ~ '^[a-z][a-z0-9_]{1,40}$'),
  constraint owner_board_config_chk check (jsonb_typeof(config) = 'object')
);
create index if not exists owner_board_items_user_idx on public.owner_board_items (user_id, sort);

alter table public.owner_board_items enable row level security;
drop policy if exists owner_board_sel on public.owner_board_items;
create policy owner_board_sel on public.owner_board_items for select to authenticated using (user_id = auth.uid() and public.is_owner());
revoke all on public.owner_board_items from public, anon, authenticated;
grant select on public.owner_board_items to authenticated;
revoke all on sequence public.owner_board_items_id_seq from public, anon, authenticated;

drop trigger if exists audit_owner_board_items on public.owner_board_items;
create trigger audit_owner_board_items after insert or update on public.owner_board_items for each row execute function public.log_change('id');

-- the setting (owner can flip it in #/switchboard)
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_board_on', 'ui', 'switch', 'true', null, null, null, null, 'মালিকের বোর্ড (প্রতিদিন যা দেখতে হবে)', 'Owner-এর board (প্রতিদিন যা দেখতে হবে)', 'Owner mode board (what to check every day)',
  'বন্ধ করলে বোর্ড লুকানো থাকে ও সেভ হয় না; হোম আগের মতো।', 'Off = the board is hidden and cannot be saved; Home stays as before.', 96)
on conflict (key) do nothing;

-- every widget kind the web page knows (the page hides the ones whose module is not installed)
create or replace function public._ob_kinds() returns text[]
language sql immutable set search_path = public as $$
  select array['sales_vs','cash_short','day_close','needs_you','exceptions','approvals','cust_dues','supp_dues','stock_low','wastage','voids_disc','unsent','top_sellers','parallel','rollout','backup','notifications','attendance','payroll','balance_check','report','page','counter','note']::text[];
$$;

create or replace function public.owner_board_get() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'widget', i.widget, 'config', i.config, 'sort', i.sort, 'enabled', i.enabled, 'updated_at', i.updated_at) order by i.sort, i.id)
                     from public.owner_board_items i where i.user_id = auth.uid()), '[]'::jsonb);
end $$;

-- p_items: [{widget, config?, enabled?}] in the wanted order (sort is set from the position)
create or replace function public.owner_board_save(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it jsonb; n int := 0; w text; cfg jsonb; k text; v jsonb; en boolean; kinds text[] := public._ob_kinds();
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('owner_board_on') then raise exception 'feature_off'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 60 then raise exception 'too_many_items'; end if;
  -- validate everything first, write after (atomic anyway: one transaction)
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then raise exception 'bad_item'; end if;
    w := it ->> 'widget';
    if w is null or not (w = any (kinds)) then raise exception 'bad_widget'; end if;
    cfg := coalesce(it -> 'config', '{}'::jsonb);
    if jsonb_typeof(cfg) <> 'object' then raise exception 'bad_config'; end if;
    if octet_length(cfg::text) > 4000 then raise exception 'config_too_big'; end if;
    for k, v in select * from jsonb_each(cfg) loop
      if k in ('warn_gt', 'bad_gt', 'warn_lt', 'bad_lt') then
        if jsonb_typeof(v) not in ('number', 'null') then raise exception 'bad_threshold'; end if;
        if jsonb_typeof(v) = 'number' and abs((v #>> '{}')::numeric) > 1e12 then raise exception 'bad_threshold'; end if;
      elsif k = 'size' then
        if v #>> '{}' not in ('compact', 'wide') then raise exception 'bad_size'; end if;
      elsif k in ('label', 'text', 'route', 'report', 'table', 'preset', 'repeat', 'done_on') then
        if jsonb_typeof(v) <> 'string' and jsonb_typeof(v) <> 'null' then raise exception 'bad_config'; end if;
        if length(coalesce(v #>> '{}', '')) > (case when k = 'text' then 300 else 120 end) then raise exception 'text_too_long'; end if;
      end if;
    end loop;
    if cfg ? 'repeat' and (cfg ->> 'repeat') not in ('daily', 'weekly', 'never') then raise exception 'bad_repeat'; end if;
    if it ? 'enabled' and jsonb_typeof(it -> 'enabled') <> 'boolean' then raise exception 'bad_item'; end if;
  end loop;
  delete from public.owner_board_items where user_id = auth.uid();
  for it in select * from jsonb_array_elements(p_items) loop
    en := coalesce((it ->> 'enabled')::boolean, true);
    insert into public.owner_board_items (user_id, widget, config, sort, enabled, updated_at)
      values (auth.uid(), it ->> 'widget', coalesce(it -> 'config', '{}'::jsonb), n, en, now());
    n := n + 1;
  end loop;
  return jsonb_build_object('count', n);
end $$;

revoke all on function public._ob_kinds() from public, anon, authenticated;
revoke all on function public.owner_board_get(), public.owner_board_save(jsonb) from public, anon;
grant execute on function public.owner_board_get(), public.owner_board_save(jsonb) to authenticated;

-- ============================================================
-- Home favourites in the ⋮ menu: order, own label and "hide from Home" per person (synced with the existing user_favourites rows)
-- ============================================================
alter table public.user_favourites add column if not exists sort int;
alter table public.user_favourites add column if not exists label text;
alter table public.user_favourites add column if not exists hidden boolean not null default false;

-- p_items: [{kind, key}] in the wanted order; the caller's own rows get sort = position (missing rows are created as pinned)
create or replace function public.fav_order_set(p_items jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare it jsonb; n int := 0; k text; ky text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 200 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then raise exception 'bad_item'; end if;
    k := it ->> 'kind'; ky := it ->> 'key';
    if k is null or k not in ('route', 'form') or ky is null or length(ky) = 0 or length(ky) > 120 then raise exception 'bad_item'; end if;
  end loop;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.user_favourites (user_id, kind, key, pinned, sort) values (auth.uid(), it ->> 'kind', it ->> 'key', true, n)
      on conflict (user_id, kind, key) do update set sort = excluded.sort;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.fav_meta_set(p_kind text, p_key text, p_label text, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
declare lb text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('route', 'form') or p_key is null or length(p_key) = 0 or length(p_key) > 120 then raise exception 'bad_item'; end if;
  if lb is not null and length(lb) > 40 then raise exception 'label_too_long'; end if;
  insert into public.user_favourites (user_id, kind, key, pinned, label, hidden) values (auth.uid(), p_kind, p_key, false, lb, coalesce(p_hidden, false))
    on conflict (user_id, kind, key) do update set label = excluded.label, hidden = excluded.hidden;
end $$;

revoke all on function public.fav_order_set(jsonb), public.fav_meta_set(text, text, text, boolean) from public, anon;
grant execute on function public.fav_order_set(jsonb), public.fav_meta_set(text, text, text, boolean) to authenticated;

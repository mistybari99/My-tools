-- Phase 505 (SW-7) - SWEETS STOCK TRACKING: the mapping tool (item type to tracked yes/no). Nothing is flipped by this file.
-- Paste AFTER phase504. Paste-twice safe (create table if not exists, on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, F-10: "all 1,369 items have tracked = false ... do not simply flip tracked=true on all rows; use a
-- reviewed mapping by item type". The plan itself is docs/STOCK_TRACKING_POLICY.md.
-- What this file adds:
--   stock_tracking_map   one row per item type: the PROPOSED tracked value and the reason. Proposals only. Reviewed by the owner (reviewed_by / reviewed_at).
--   stock_tracking_plan()          read-only, owner only: per type, the items in the database, how many are tracked now, the proposal, and how many differ.
--   stock_tracking_review(type, note)   owner only: records that the owner reviewed the proposal for that type (note required).
--   stock_tracking_apply(type, dry_run) owner only. dry_run (default true) only counts. A real run needs the switch tracking_map_apply_on = true AND a
--                                  review for that type. It sets items.tracked to the proposal for that type only, and only for items that differ.
-- The switch tracking_map_apply_on defaults OFF. With it OFF nothing can change any item. Opening stock must be counted before an item is tracked
-- (the owner's count, through the existing opening stock flow); this file does not create stock.

do $g$ begin
  if to_regclass('public.items') is null or to_regclass('public.item_types') is null then raise exception 'phase505 needs the items and item types'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('tracking_map_apply_on', 'stock',
     'স্টক ট্র্যাকিং মানচিত্র প্রয়োগ / Apply the reviewed stock tracking map: on', 'স্টক ট্র্যাকিং মানচিত্র প্রয়োগ / Apply the reviewed stock tracking map: on', 'Apply the reviewed stock tracking map: on', 'OFF = the map can be read and reviewed, nothing changes. ON = the owner can apply the reviewed map to items of one type at a time.', 'OFF = the map can be read and reviewed, nothing changes. ON = the owner can apply the reviewed map to items of one type at a time.', 5041)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

create table if not exists public.stock_tracking_map (
  item_type text primary key references public.item_types(code),
  proposed_tracked boolean not null,
  reason_en text not null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  updated_at timestamptz not null default now()
);
alter table public.stock_tracking_map enable row level security;
revoke all on public.stock_tracking_map from anon, authenticated;

-- the proposals (from the item dictionary's control classes; the live counts are the owner's to check with stock_tracking_plan)
insert into public.stock_tracking_map (item_type, proposed_tracked, reason_en) values
  ('finished_good', true,  'Made and sold goods: stock must be known for sale, production and waste. Count the opening stock first.'),
  ('resale',        true,  'Bought and resold goods (drinks, direct-sale items): stock and cost are needed for the sale.'),
  ('raw_material',  true,  'Ingredients used by production: their stock is consumed by the recipe.'),
  ('packaging',     true,  'Boxes and bags used per cake or sweet: consumed by production and sales.'),
  ('consumable',    false, 'Cleaning and small supplies: expensed on purchase. Track only if the owner asks for it.'),
  ('controlled',    false, 'Controlled tools: the existing rule tools_stock_on decides; not changed by this map.'),
  ('asset',         false, 'Fixed machines and furniture: a register, never a stock item.'),
  ('infrastructure', false, 'Building and utility materials: not a stock item.')
on conflict (item_type) do nothing;

-- read-only plan (owner only)
create or replace function public.stock_tracking_plan()
returns table (item_type text, items_total bigint, tracked_now bigint, proposed_tracked boolean, reviewed_at timestamptz, items_differ bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query
    select m.item_type, count(i.id), count(i.id) filter (where i.tracked), m.proposed_tracked, m.reviewed_at,
           count(i.id) filter (where coalesce(i.tracked, false) <> m.proposed_tracked)
    from public.stock_tracking_map m left join public.items i on i.item_type = m.item_type
    group by m.item_type, m.proposed_tracked, m.reviewed_at
    union all      -- items with no type cannot be mapped until they are classified
    select '(not classified)'::text, count(*), count(*) filter (where x.tracked), null::boolean, null::timestamptz, 0::bigint
    from public.items x where x.item_type is null
    order by 1;
end $$;

-- the owner's review of one type's proposal (the note is required)
create or replace function public.stock_tracking_review(p_item_type text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_required'; end if;
  update public.stock_tracking_map set reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(btrim(p_note), 300), updated_at = now()
    where item_type = p_item_type;
  if not found then raise exception 'type_not_in_map'; end if;
  return jsonb_build_object('item_type', p_item_type, 'reviewed', true);
end $$;

-- apply the reviewed proposal to one type. dry run counts only.
create or replace function public.stock_tracking_apply(p_item_type text, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.stock_tracking_map; n bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into m from public.stock_tracking_map where item_type = p_item_type;
  if not found then raise exception 'type_not_in_map'; end if;
  if coalesce(p_dry_run, true) then
    select count(*) into n from public.items where item_type = p_item_type and coalesce(tracked, false) <> m.proposed_tracked;
    return jsonb_build_object('item_type', p_item_type, 'dry_run', true, 'would_change', n, 'to', m.proposed_tracked, 'reviewed', m.reviewed_at is not null);
  end if;
  if not public.rule_on('tracking_map_apply_on') then raise exception 'tracking_map_apply_off'; end if;
  if m.reviewed_at is null then raise exception 'not_reviewed'; end if;
  update public.items set tracked = m.proposed_tracked where item_type = p_item_type and coalesce(tracked, false) <> m.proposed_tracked;
  get diagnostics n = row_count;
  return jsonb_build_object('item_type', p_item_type, 'dry_run', false, 'changed', n, 'to', m.proposed_tracked);
end $$;

revoke all on function public.stock_tracking_plan() from public, anon;
revoke all on function public.stock_tracking_review(text, text) from public, anon;
revoke all on function public.stock_tracking_apply(text, boolean) from public, anon;
grant execute on function public.stock_tracking_plan() to authenticated;
grant execute on function public.stock_tracking_review(text, text) to authenticated;
grant execute on function public.stock_tracking_apply(text, boolean) to authenticated;

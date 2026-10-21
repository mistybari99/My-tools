-- Phase 504 (SW-6) - SWEETS RECIPES: a made product can be an ingredient of another recipe (two-stage production), behind a switch.
-- Paste AFTER phase503. Paste-twice safe (on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A1 (manufacturing cost): "semi-finished item cannot be a recipe ingredient (e.g. chhana used to make
-- sweets; dough used to make another product). The recorded recipe validator accepts only certain ingredient types."
-- This branch has no separate "semi-finished" item type. The item types here are: raw_material, packaging, resale, finished_good, controlled, consumable,
-- asset, infrastructure. A made intermediate (chhana, dough) is therefore a finished_good item made by its own recipe. The validator refused it.
-- Reproduced on a local throwaway database (before this file): recipe_save with a finished_good ingredient -> bad_ingredient_type.
-- Change, switch recipe_intermediate_on (default OFF; OFF = the validator refuses as before):
--   ON: a finished_good may be an ingredient. A loop is refused (recipe_loop): an ingredient whose active recipe leads back to the product.
--   Production of the product consumes the intermediate's stock at its weighted average cost (production_post is not changed; it already takes any ingredient).
--   Cost: the intermediate's cost comes from its own last production. If it has no cost yet, the usual cost warning (production_requires_cost) applies.
-- Not changed here (docs/PLAN_NEXT.md): late cost pools not repriced, pool bills without an expense, overhead true-up as a report only, actual-yield variance,
-- packaging on actual yield, and recipe_approval_required (its default 'off' is an owner decision).

do $g$ begin
  if to_regclass('public.recipes') is null or to_regclass('public.recipe_lines') is null then raise exception 'phase504 needs the recipe tables'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('recipe_intermediate_on', 'items',
     'তৈরি পণ্য অন্য রেসিপিতে উপাদান / A made product can be an ingredient of another recipe: on', 'তৈরি পণ্য অন্য রেসিপিতে উপাদান / A made product can be an ingredient of another recipe: on', 'A made product can be an ingredient of another recipe: on', 'OFF = only raw material, packaging and resale items can be ingredients (today). ON = a made product (chhana, dough) can be an ingredient; a loop is refused.', 'OFF = only raw material, packaging and resale items can be ingredients (today). ON = a made product (chhana, dough) can be an ingredient; a loop is refused.', 5031)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

-- is the product reachable from p_from through active recipes (the loop test)? Stops at a loop (union).
create or replace function public._recipe_reaches(p_from uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive walk(item) as (
    select p_from
    union
    select l.ingredient_item_id from walk w
      join public.recipes r on r.item_id = w.item and r.active
      join public.recipe_lines l on l.recipe_id = r.id and l.active
  )
  select exists (select 1 from walk where item = p_target);
$$;
revoke all on function public._recipe_reaches(uuid, uuid) from public, anon;

-- the recipe ingredient validator: as before, plus the switch for made products and the loop test
CREATE OR REPLACE FUNCTION public._recipe_lines_ok(p_item uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- phase 504: a made product (finished good) may be an ingredient only when recipe_intermediate_on is on, and never in a loop
      if not (ing.item_type = 'finished_good' and public.rule_on('recipe_intermediate_on')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;
    end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$;

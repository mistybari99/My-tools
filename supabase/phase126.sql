-- ============================================================
-- Phase 126 (marker var126) - LARGE CATALOGUE READINESS: server-side item search + paging (ADDITIVE ONLY; existing item screens and listings unchanged).
-- Needs phase125 (items.org_unit_id, _my_biz125). Canonical order: after phase125. Paste twice = no change, no error.
--   items.brand (nullable text)  the principal / brand of a bought-in item (paint dealer). Sweets items stay null.
--   Indexes on items: (org_unit_id, category), (lower(code) text_pattern_ops), barcode prefix, brand, and - when the extension pg_trgm is available -
--       GIN trigram indexes on name_bn / name_en / name_mix (substring search). Without pg_trgm the fallback is btree prefix indexes on lower(name_*), so a search
--       matches the START of a name (and code / barcode prefixes) instead of any part of it. items_search_info126() tells which mode is active.
--   items_search(p_org, p_q, p_filters, p_limit, p_offset)  one call = one page + summary counts, scoped to the caller's businesses (owner: all; others: the businesses of
--       their assigned locations; a business the caller may not see is refused). Never returns cost. Filters: category, sub_category, brand, style_id, barcode, item_type,
--       active (true default | false | "all"), tracked, counts (false skips the summary). q: code prefix, barcode prefix/exact, name substring (q shorter than 3 characters:
--       name prefix only, because a trigram needs 3 characters).
--   Existing flows do not call it; nothing existing is changed except the new indexes (a small extra cost on item insert / update, measured in docs/regs/variants125.md).
-- Rollback: drop items_search, items_search_info126, the new indexes and items.brand (nothing else refers to them).
-- ============================================================
begin;

do $g$
begin
  if to_regclass('public.items') is null or to_regprocedure('public._my_biz125()') is null or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'org_unit_id') then
    raise exception 'phase126 needs phase125 pasted first (docs/PASTE_ORDER.md)';
  end if;
end $g$;

alter table public.items add column if not exists brand text check (brand is null or length(brand) <= 80);

-- btree indexes (always)
create index if not exists items_org_cat126 on public.items (org_unit_id, category);
create index if not exists items_code_lpfx126 on public.items (lower(code) text_pattern_ops);
create index if not exists items_barcode_pfx126 on public.items (barcode text_pattern_ops) where barcode is not null;
create index if not exists items_org_brand126 on public.items (org_unit_id, brand) where brand is not null;

-- substring search: pg_trgm when it can be installed, otherwise btree prefix indexes on the lower-cased names
do $t$
declare ns text;
begin
  begin
    create schema if not exists extensions;                       -- Supabase already has it; keeps the ~30 pg_trgm helper functions out of the public API schema
    create extension if not exists pg_trgm schema extensions;
  exception when others then
    raise notice 'phase126: pg_trgm not available (%): name search falls back to btree prefix indexes', sqlerrm;
  end;
  select n.nspname into ns from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm';
  if ns is not null then
    execute format('create index if not exists items_name_bn_trgm126 on public.items using gin (name_bn %I.gin_trgm_ops)', ns);
    execute format('create index if not exists items_name_en_trgm126 on public.items using gin (name_en %I.gin_trgm_ops)', ns);
    execute format('create index if not exists items_name_mix_trgm126 on public.items using gin (name_mix %I.gin_trgm_ops)', ns);
  else
    create index if not exists items_name_bn_pfx126 on public.items (lower(name_bn) text_pattern_ops);
    create index if not exists items_name_en_pfx126 on public.items (lower(name_en) text_pattern_ops);
    create index if not exists items_name_mix_pfx126 on public.items (lower(name_mix) text_pattern_ops);
  end if;
exception when others then
  raise notice 'phase126: name index step skipped (%)', sqlerrm;   -- an add-on: it can never block the phase
end $t$;

create or replace function public.items_search_info126() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('trigram', exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'items_name_bn_trgm126'),
    'indexes', (select coalesce(jsonb_agg(indexname order by indexname), '[]'::jsonb) from pg_indexes where schemaname = 'public' and tablename = 'items' and indexname ~ '126$'));
$$;

create or replace function public.items_search(p_org bigint default null, p_q text default null, p_filters jsonb default '{}'::jsonb, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q text := nullif(btrim(coalesce(p_q, '')), ''); f jsonb := coalesce(p_filters, '{}'::jsonb); lim int := coalesce(p_limit, 50); off int := coalesce(p_offset, 0);
  qe text; qlow text; act text; cat text; sub text; br text; sty bigint; bc text; ity text; trk boolean; want_counts boolean := true; res jsonb; allb boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'bad_filters'; end if;
  if p_org is not null and not public._biz_vis125(p_org) then raise exception 'not allowed'; end if;
  if lim < 1 or lim > 200 then raise exception 'bad_limit'; end if;
  if off < 0 or off > 1000000 then raise exception 'bad_offset'; end if;
  if q is not null and length(q) > 80 then raise exception 'bad_query'; end if;
  qlow := lower(coalesce(q, ''));
  qe := replace(replace(replace(qlow, '\', '\\'), '%', '\%'), '_', '\_');
  act := coalesce(f->>'active', 'true');
  if act not in ('true', 'false', 'all') then raise exception 'bad_filters'; end if;
  cat := nullif(f->>'category', ''); sub := nullif(f->>'sub_category', ''); br := nullif(f->>'brand', ''); bc := nullif(f->>'barcode', ''); ity := nullif(f->>'item_type', '');
  sty := nullif(f->>'style_id', '')::bigint; trk := nullif(f->>'tracked', '')::boolean;
  if f ? 'counts' then want_counts := coalesce((f->>'counts')::boolean, true); end if;
  allb := p_org is null and public.is_owner();

  with m as materialized (
    select i.id, i.code, i.is_active, i.style_id, i.category, i.brand,
           case when q is null then 3
                when lower(i.code) = qlow or i.barcode = q then 0
                when lower(i.code) like qe || '%' escape '\' or i.barcode like qe || '%' escape '\' then 1
                else 2 end rk
      from public.items i
     where (case when p_org is not null then i.org_unit_id = p_org when allb then true else i.org_unit_id in (select public._my_biz125()) end)
       and (act = 'all' or i.is_active = (act = 'true'))
       and (cat is null or i.category = cat) and (sub is null or i.sub_category = sub) and (br is null or i.brand = br)
       and (sty is null or i.style_id = sty) and (bc is null or i.barcode = bc) and (ity is null or i.item_type = ity) and (trk is null or i.tracked = trk)
       and (q is null
            or lower(i.code) like qe || '%' escape '\'
            or i.barcode like qe || '%' escape '\'
            or (length(q) >= 3 and (i.name_bn ilike '%' || qe || '%' escape '\' or i.name_en ilike '%' || qe || '%' escape '\' or i.name_mix ilike '%' || qe || '%' escape '\'))
            or (length(q) < 3 and (lower(i.name_bn) like qe || '%' escape '\' or lower(i.name_en) like qe || '%' escape '\' or lower(i.name_mix) like qe || '%' escape '\')))),
  pg as (select m.id, m.rk, m.code from m order by m.rk, m.code limit lim offset off)
  select jsonb_build_object('total', (select count(*) from m), 'limit', lim, 'offset', off,
    'rows', (select coalesce(jsonb_agg((to_jsonb(x) - 'rk') order by x.rk, x.code), '[]'::jsonb) from (
        select i.id, i.code, i.name_bn, i.name_en, i.name_mix, i.category, i.sub_category, i.brand, i.unit, i.sell_price, i.barcode, i.style_id, i.variant_opts, i.is_active, i.tracked, i.org_unit_id, pg.rk
          from pg join public.items i on i.id = pg.id) x),
    'counts', case when want_counts then jsonb_build_object(
        'active', (select count(*) from m where m.is_active), 'inactive', (select count(*) from m where not m.is_active), 'variants', (select count(*) from m where m.style_id is not null),
        'by_category', (select coalesce(jsonb_agg(jsonb_build_object('category', c, 'n', n) order by n desc, c), '[]'::jsonb) from (select coalesce(m.category, '') c, count(*) n from m group by 1 order by n desc, c limit 20) z),
        'by_brand', (select coalesce(jsonb_agg(jsonb_build_object('brand', b, 'n', n) order by n desc, b), '[]'::jsonb) from (select m.brand b, count(*) n from m where m.brand is not null group by 1 order by n desc, b limit 20) z)) end)
  into res;
  return res;
end $$;

revoke all on function public.items_search(bigint, text, jsonb, int, int), public.items_search_info126() from public, anon;
grant execute on function public.items_search(bigint, text, jsonb, int, int), public.items_search_info126() to authenticated;

commit;

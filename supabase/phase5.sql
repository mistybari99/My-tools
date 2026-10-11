-- ============================================================
-- BOS tool · Phase 5: fixed brand names, official location names, paper-form numbering and gap audit.
-- Run AFTER phase3.sql and phase4.sql. Run once. Safe to run again (it only updates names and adds an index/functions).
-- ============================================================

-- ---------- brand and location names exactly as in the guidebook (seven locations) ----------
update public.locations set sort = 1, name_bn = 'ইসলামিয়া মিষ্টি ঘর — মেইন শোরুম ও মেইন (মিষ্টি) কারখানা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — Main Showroom ও Main (মিষ্টি) Factory', name_en = 'ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory' where code = 'main';
update public.locations set sort = 2, name_bn = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_en = 'ISLAMIYA MISTY GHAR — 2nd Branch' where code = 'branch2';
update public.locations set sort = 3, name_bn = 'মিষ্টি বাড়ি', name_mix = 'মিষ্টি বাড়ি', name_en = 'MISTY BARI' where code = 'mishti_bari';
update public.locations set sort = 4, name_bn = 'AL-CAKIZ (বাসার নিচে)', name_mix = 'AL-CAKIZ (বাসার নিচে)', name_en = 'AL-CAKIZ (below the residence)' where code = 'al_cakes';
update public.locations set sort = 5, name_bn = 'কেক কারখানা (বাসার নিচে)', name_mix = 'Cake Factory (বাসার নিচে)', name_en = 'Cake Factory (below the residence)' where code = 'cake_factory';
update public.locations set sort = 6, name_bn = 'মুজগুন্নি মিষ্টি কারখানা (বন্ধ, যন্ত্র রাখা)', name_mix = 'মুজগুন্নি মিষ্টি Factory (বন্ধ, যন্ত্র রাখা)', name_en = 'Mujgunni Sweet Factory (closed, machines stored)' where code = 'mishti_factory';
update public.locations set sort = 7, name_bn = 'গোডাউন (ইসলামিয়ার পাশের গলি)', name_mix = 'Godown (ইসলামিয়ার পাশের গলি)', name_en = 'Godown (lane beside ISLAMIYA MISTY GHAR)' where code = 'godown';
update public.settings set value = '"ইসলামিয়া মিষ্টি ঘর"', label_en = 'Business name (fixed, never translated)' where key = 'business_name';
insert into public.settings (key, value, label_bn, label_mix, label_en)
  values ('business_name_latin', '"ISLAMIYA MISTY GHAR"', 'প্রতিষ্ঠানের নাম (ইংরেজি অক্ষরে, স্থির)', 'প্রতিষ্ঠানের Name (Latin, স্থির)', 'Business name in Latin letters (fixed)')
  on conflict (key) do update set value = excluded.value;

-- ---------- paper form number: the printed serial of the numbered paper book, stored in data.paper_no ----------
-- One printed number can be recorded once per form and location (a duplicate is refused by the database).
create unique index if not exists entries_paper_no_uq on public.entries (form_code, location_id, (btrim(data->>'paper_no')))
  where nullif(btrim(data->>'paper_no'), '') is not null;

-- ---------- gap audit: printed numbers that were never entered (a missing page = a missing transaction) ----------
-- The number is the trailing digits of what was typed (A-0012 -> 12). Works only on numbers that were entered.
create or replace function public.number_audit(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss bigint[]; miss_n bigint; unnum bigint;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  with n as (
    select nullif(substring(btrim(e.data->>'paper_no') from '([0-9]+)\s*$'), '')::bigint v
    from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is not null)
  select min(v), max(v), count(v) into lo, hi, cnt from n;
  select count(*) into unnum from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is null;
  if cnt is null or cnt = 0 then return jsonb_build_object('entered', 0, 'without_number', unnum, 'missing', '[]'::jsonb, 'missing_count', 0); end if;
  if hi - lo > 100000 then raise exception 'range too wide'; end if;
  select count(*) into miss_n from generate_series(lo, hi) g where not exists (
    select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
      and substring(btrim(e.data->>'paper_no') from '([0-9]+)\s*$')::bigint = g);
  select coalesce(array_agg(g order by g), '{}') into miss from (
    select g from generate_series(lo, hi) g where not exists (
      select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
        and substring(btrim(e.data->>'paper_no') from '([0-9]+)\s*$')::bigint = g) order by g limit 200) m;
  return jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'without_number', unnum, 'missing_count', miss_n, 'missing', to_jsonb(miss));
end $$;

-- one line per form and location that has at least one gap (for the dashboard)
create or replace function public.number_audit_summary() returns table (form_code text, location_id int, entered bigint, first_no bigint, last_no bigint, missing_count bigint)
language sql stable security definer set search_path = public as $$
  with n as (
    select e.form_code, e.location_id, substring(btrim(e.data->>'paper_no') from '([0-9]+)\s*$')::bigint v
    from public.entries e where nullif(btrim(e.data->>'paper_no'), '') is not null and e.data->>'paper_no' ~ '[0-9]\s*$'),
  g as (select form_code, location_id, count(distinct v) c, min(v) lo, max(v) hi from n group by 1, 2)
  select g.form_code, g.location_id, g.c, g.lo, g.hi, (g.hi - g.lo + 1) - g.c
  from g
  where (g.hi - g.lo + 1) - g.c > 0 and g.hi - g.lo <= 100000
    and (public.is_owner() or (public.can_do(g.form_code, 'approve') and public.can_loc(g.location_id)))
  order by 6 desc;
$$;
revoke all on function public.number_audit(text, int), public.number_audit_summary() from public, anon;
grant execute on function public.number_audit(text, int), public.number_audit_summary() to authenticated;

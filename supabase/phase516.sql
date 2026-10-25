-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase90.sql there and is already pasted on the live database under that name.
-- Renumbered to phase516.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 516 (bos90) - SCAN: photo of a bill / product list / expense slip -> DRAFT -> human review -> existing save functions.
--   Needs phase8 ... phase510 (tested on 8..84 incl. 72-79, 82, 83). Additive; paste-twice safe. No old phase file is edited. No old function is re-created.
--   Rule of the feature: a photo NEVER posts anything by itself. extract -> DRAFT (scan_jobs.extracted) -> the person edits (scan_jobs.edited) -> a person with
--   the grant scan_confirm presses Confirm -> scan_confirm() calls the EXISTING functions (save_purchase / post_purchase / quick_expense_add / item_new / item_apply
--   / save_supplier) in ONE transaction. There is no auto-confirm anywhere (no such switch, no such function). scan_min_confidence only WARNS.
--   Tables : scan_jobs (one row per photo, status uploaded|extracted|reviewed|confirmed|rejected), scan_events (append-only trail).
--   Settings (rules) : scan_enabled (switch, OFF), scan_engine (manual | browser_ocr | ai_vision, default manual), scan_min_confidence (0..1, warn-only).
--   Grants : scan_upload (take a photo + draft + review own), scan_confirm (confirm / reject others'; what it posts still needs purchase_entry etc.).
--   Functions (browser): scan_create, scan_set_extracted, scan_review_save, scan_confirm, scan_reject, scan_get, scan_list, scan_match_items, scan_match_suppliers.
--   Photos: private bucket 'photos', path SCAN/<place id>/<uuid>.jpg, signed URLs only; policies below let only the uploader / owner / scan_confirm holder read it.
-- ============================================================

-- ---------- 0. guard ----------
do $$
declare miss text := '';
begin
  if to_regprocedure('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)') is null then miss := miss || ' phase10(save_purchase)'; end if;
  if to_regprocedure('public.post_purchase(uuid,jsonb)') is null then miss := miss || ' phase10(post_purchase)'; end if;
  if to_regprocedure('public.item_new(jsonb,text)') is null then miss := miss || ' phase14(item_new)'; end if;
  if to_regprocedure('public.item_apply(uuid,jsonb,text)') is null then miss := miss || ' phase14(item_apply)'; end if;
  if to_regprocedure('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)') is null then miss := miss || ' phase50(quick_expense_add)'; end if;
  if to_regprocedure('public.save_supplier(uuid,jsonb)') is null then miss := miss || ' phase8(save_supplier)'; end if;
  if to_regprocedure('public._append_only23()') is null then miss := miss || ' phase23(_append_only23)'; end if;
  if to_regprocedure('public.rpt_cost_ok()') is null then miss := miss || ' phase21(rpt_cost_ok)'; end if;
  if to_regprocedure('public._client_lock(uuid)') is null then miss := miss || ' phase10(_client_lock)'; end if;
  if to_regclass('public.rule_grants') is null then miss := miss || ' phase8(rule_grants)'; end if;
  if miss <> '' then raise exception 'phase516 needs the earlier phases pasted first, missing:%', miss; end if;
end $$;

-- ---------- 1. settings + grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('scan_enabled', 'purchase', 'switch', 'false', null, null, null, null,
  'ছবি তুলে বিল / তালিকা ঢোকানো (Scan)', 'ছবি তুলে bill / list ঢোকানো (Scan)', 'Scan a photo of a bill or list',
  'বন্ধ = ডিফল্ট। চালু করলে ছবি তুলে খসড়া হয়; মানুষ দেখে Confirm না করলে কিছুই ঢোকে না।',
  'বন্ধ = default। চালু করলে ছবি তুলে draft হয়; মানুষ দেখে Confirm না করলে কিছুই ঢোকে না।',
  'Off = default. On: a photo becomes a DRAFT; nothing is entered until a person reviews and confirms.', 900),
 ('scan_engine', 'purchase', 'choice', '"manual"', null, '["manual","browser_ocr","ai_vision"]'::jsonb, null, null,
  'Scan-এর পাঠ-পদ্ধতি', 'Scan-এর পাঠ-method', 'Scan reading method',
  'manual = ছবির পাশে নিজে লিখবেন (সব সময় চলে)। browser_ocr = ফোনেই বিনামূল্যে পড়া (বাংলা / হাতের লেখায় দুর্বল)। ai_vision = AI (আলাদা সেটআপ ও চাবি লাগে, docs/SCAN_SETUP.md)।',
  'manual = ছবির পাশে নিজে লিখবেন (সব সময় চলে)। browser_ocr = phone-এই free পড়া (বাংলা / handwriting-এ দুর্বল)। ai_vision = AI (আলাদা setup ও key লাগে, docs/SCAN_SETUP.md)।',
  'manual = you type the lines beside the photo (always works). browser_ocr = free reading on the phone (weak on Bangla and handwriting). ai_vision = an AI service (needs the separate setup and key, see docs/SCAN_SETUP.md).', 901),
 ('scan_min_confidence', 'purchase', 'number', '0.6', 'ratio', null, 0, 1,
  'Scan: এর নিচে নিশ্চয়তা হলে সতর্কতা (আটকায় না)', 'Scan: এর নিচে confidence হলে সতর্কতা (আটকায় না)', 'Scan: warn below this confidence (never blocks)',
  'শুধু সতর্কতা। যে ঘর পাঠ-যন্ত্র কম নিশ্চিত ছিল ও আপনি বদলাননি, সেটি হলুদ হয়। Confirm আটকায় না।',
  'শুধু warning। যে field reader কম sure ছিল ও আপনি বদলাননি, সেটি হলুদ হয়। Confirm আটকায় না।',
  'Warning only. A field the reader was unsure about and you did not change is shown yellow. It never blocks Confirm.', 902)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('scan_upload', 'purchase', 90, 'বিল / তালিকার ছবি তুলে খসড়া করা', 'Bill / list-এর ছবি তুলে draft করা', 'Photograph a bill or list and prepare a draft', 'once', null),
   ('scan_confirm', 'purchase', 91, 'ছবি থেকে করা খসড়া Confirm / বাতিল করা', 'ছবি থেকে করা draft Confirm / reject করা', 'Confirm or reject a draft made from a photo', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('scan_upload', 'purchasing'), ('scan_upload', 'storekeeper'), ('scan_upload', 'showroom_manager'), ('scan_upload', 'management'),
    ('scan_confirm', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- 2. tables ----------
create table if not exists public.scan_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  kind text not null check (kind in ('purchase_bill', 'product_list', 'expense', 'other')),
  location_id int not null references public.locations(id),
  image_path text not null check (length(image_path) <= 300 and image_path ~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$'),
  image_hash text check (image_hash is null or image_hash ~ '^[0-9a-f]{16,128}$'),
  status text not null default 'uploaded' check (status in ('uploaded', 'extracted', 'reviewed', 'confirmed', 'rejected')),
  engine text not null default 'manual' check (engine in ('manual', 'browser_ocr', 'ai_vision')),
  extracted jsonb,                       -- what the reader produced (never carries item / supplier ids or decisions)
  confidence jsonb,                      -- per field 0..1 (same shape as extracted; lines = array of objects)
  edited jsonb,                          -- what the person typed / corrected (this is what Confirm uses)
  extract_error text check (extract_error is null or length(extract_error) <= 300),
  note text check (note is null or length(note) <= 300),
  fp text,                               -- duplicate fingerprint (supplier|bill no|total, or place|date|head|amount)
  dups jsonb,                            -- duplicates found at the last review save
  result_type text check (result_type is null or result_type in ('purchase_bills', 'quick_expenses', 'items', 'none')),
  result_id text,                        -- id of the record the existing save function made
  result jsonb,                          -- small summary of what Confirm did
  confirm_client uuid,
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  reviewed_by uuid, reviewed_at timestamptz,
  confirmed_by uuid, confirmed_at timestamptz,
  reject_reason text check (reject_reason is null or length(reject_reason) <= 300), rejected_by uuid, rejected_at timestamptz,
  check (status <> 'confirmed' or (result_type is not null and confirmed_by is not null)),
  check (status <> 'rejected' or reject_reason is not null)
);
create unique index if not exists scan_jobs_image_uq on public.scan_jobs (image_path);
create unique index if not exists scan_jobs_result_uq on public.scan_jobs (result_type, result_id) where result_id is not null;
create index if not exists scan_jobs_status on public.scan_jobs (status, location_id, created_at desc);
create index if not exists scan_jobs_fp on public.scan_jobs (fp) where fp is not null;
create index if not exists scan_jobs_hash on public.scan_jobs (image_hash) where image_hash is not null;

create table if not exists public.scan_events (
  id bigserial primary key,
  job_id uuid not null references public.scan_jobs(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  action text not null check (action in ('created', 'extracted', 'extract_failed', 'saved', 'reviewed', 'confirmed', 'confirm_replay', 'rejected')),
  from_status text, to_status text,
  detail jsonb
);
create index if not exists scan_events_job on public.scan_events (job_id, id);

-- terminal rows never change; identity never changes; nothing is deleted
create or replace function public._scan_jobs_guard90() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – reject it instead'; end if;
  if old.status in ('confirmed', 'rejected') then raise exception 'append_only: a % scan cannot be changed', old.status; end if;
  if new.id <> old.id or new.client_id <> old.client_id or new.kind <> old.kind or new.location_id <> old.location_id or new.image_path <> old.image_path
     or new.created_by <> old.created_by or new.created_at <> old.created_at then raise exception 'identity_immutable'; end if;
  return new;
end $$;
drop trigger if exists scan_jobs_guard90 on public.scan_jobs;
create trigger scan_jobs_guard90 before update or delete on public.scan_jobs for each row execute function public._scan_jobs_guard90();
drop trigger if exists scan_jobs_guard90_t on public.scan_jobs;
create trigger scan_jobs_guard90_t before truncate on public.scan_jobs for each statement execute function public._append_only23();
drop trigger if exists scan_events_ro on public.scan_events;
create trigger scan_events_ro before update or delete on public.scan_events for each row execute function public._append_only23();
drop trigger if exists scan_events_ro_t on public.scan_events;
create trigger scan_events_ro_t before truncate on public.scan_events for each statement execute function public._append_only23();
drop trigger if exists audit_scan_jobs on public.scan_jobs;
create trigger audit_scan_jobs after insert or update on public.scan_jobs for each row execute function public.log_change('id');

alter table public.scan_jobs enable row level security;
alter table public.scan_events enable row level security;
revoke all on public.scan_jobs, public.scan_events from public, anon, authenticated;
grant select on public.scan_jobs, public.scan_events to authenticated;
revoke all on sequence public.scan_events_id_seq from public, anon, authenticated;
-- direct table reads: the owner and the person who took the photo. Reviewers use scan_get / scan_list (they hide purchase costs from people without the cost right).
drop policy if exists scan_jobs_sel on public.scan_jobs;
create policy scan_jobs_sel on public.scan_jobs for select to authenticated using (public.is_owner() or created_by = auth.uid());
drop policy if exists scan_events_sel on public.scan_events;
create policy scan_events_sel on public.scan_events for select to authenticated
  using (public.is_owner() or exists (select 1 from public.scan_jobs j where j.id = job_id and j.created_by = auth.uid()));

-- ---------- 3. visibility + photo policies ----------
create or replace function public._scan_can_see(j public.scan_jobs) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or j.created_by = auth.uid() or (public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id)));
$$;
-- purchase costs: owner, the person who typed it, or a cost-right holder (same rule as the rest of the app)
create or replace function public._scan_content_ok(j public.scan_jobs) returns boolean language sql stable security definer set search_path = public as $$
  select public._scan_can_see(j) and (j.kind <> 'purchase_bill' or public.is_owner() or j.created_by = auth.uid() or public.rpt_cost_ok());
$$;

create or replace function public._scan_photo_ok(p_name text, p_action text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare loc int;
begin
  if p_name is null or p_name !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or not public.is_active() then return false; end if;
  loc := split_part(p_name, '/', 2)::int;
  if p_action = 'enter' then return public.can_loc(loc) and public.has_grant('scan_upload', loc); end if;
  return exists (select 1 from public.scan_jobs j where j.image_path = p_name and public._scan_can_see(j));
end $$;

do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists scan_photos_insert on storage.objects';
    execute 'create policy scan_photos_insert on storage.objects for insert to authenticated with check (bucket_id = ''photos'' and public._scan_photo_ok(name, ''enter''))';
    execute 'drop policy if exists scan_photos_read on storage.objects';
    execute 'create policy scan_photos_read on storage.objects for select to authenticated using (bucket_id = ''photos'' and public._scan_photo_ok(name, ''view''))';
  end if;
  if to_regclass('storage.buckets') is not null then        -- a photo may hold personal data: the bucket must stay private
    execute 'update storage.buckets set public = false where id = ''photos'' and public is distinct from false';
  end if;
end $$;

-- ---------- 4. small parsers (everything typed by a person or read by a machine goes through these) ----------
create or replace function public._scan_txt(p text, p_len int) returns text language sql immutable set search_path = public as $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '[[:cntrl:]]+', ' ', 'g')), p_len), '');
$$;

create or replace function public._scan_num(p text, p_strict boolean, p_what text, p_max numeric default 999999999) returns numeric
language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if p is null then return null; end if;
  s := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯,৳', '0123456789'), '\s+', '', 'g');       -- Bangla digits -> ASCII; ',' the taka sign and spaces are dropped
  if s = '' then return null; end if;
  if s !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$' or s::numeric > p_max then
    if p_strict then raise exception 'bad_number: %', p_what; end if;
    return null;
  end if;
  return s::numeric;
end $$;

create or replace function public._scan_date(p text, p_strict boolean) returns date language plpgsql stable set search_path = public as $$
declare s text := translate(btrim(coalesce(p, '')), '০১২৩৪৫৬৭৮৯', '0123456789'); d date; t text;
begin
  if s = '' then return null; end if;
  begin
    if s ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$' then d := make_date(split_part(s, '-', 1)::int, split_part(s, '-', 2)::int, split_part(s, '-', 3)::int);
    elsif s ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}$' then
      t := regexp_replace(s, '[/.]', '-', 'g');
      d := make_date(split_part(t, '-', 3)::int, split_part(t, '-', 2)::int, split_part(t, '-', 1)::int);
    end if;
  exception when others then d := null;
  end;
  if d is null or d < date '2000-01-01' or d > (now() at time zone 'Asia/Dhaka')::date + 1 then
    if p_strict then raise exception 'bad_date'; end if;
    return null;
  end if;
  return d;
end $$;

create or replace function public._scan_uuid(p text) returns uuid language sql immutable set search_path = public as $$
  select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end;
$$;

-- p_human = true : a person's own corrections (may carry item_id / supplier id / decisions; bad numbers raise)
-- p_human = false: machine output (AI / OCR): ids and decisions are DROPPED (a reader can never pick an item), bad values become null, unknown keys are dropped
create or replace function public._scan_clean(p_kind text, p jsonb, p_human boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare o jsonb := '{}'::jsonb; s jsonb; ln jsonb; ls jsonb := '[]'::jsonb; sup jsonb; sid uuid; dec text; m text; hd text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_payload'; end if;
  if length(p::text) > 300000 then raise exception 'payload_too_large'; end if;
  if p ? 'supplier' then
    s := p -> 'supplier';
    if jsonb_typeof(s) = 'string' then s := jsonb_build_object('name', p ->> 'supplier'); end if;
    if jsonb_typeof(s) = 'object' then
      sup := jsonb_build_object('name', public._scan_txt(s ->> 'name', 120));
      if p_human then
        sid := public._scan_uuid(s ->> 'id');
        if sid is not null then sup := sup || jsonb_build_object('id', sid); end if;
        if (s ->> 'create') = 'true' then sup := sup || jsonb_build_object('create', true); end if;
      end if;
      o := o || jsonb_build_object('supplier', sup);
    end if;
  end if;
  o := o || jsonb_strip_nulls(jsonb_build_object(
      'bill_no', public._scan_txt(p ->> 'bill_no', 40),
      'date', public._scan_date(p ->> 'date', p_human),
      'discount', public._scan_num(p ->> 'discount', p_human, 'discount'),
      'total', public._scan_num(p ->> 'total', p_human, 'total'),
      'note', public._scan_txt(p ->> 'note', 300),
      'title', public._scan_txt(p ->> 'title', 120),
      'paid_to', public._scan_txt(p ->> 'paid_to', 120),
      'amount', public._scan_num(p ->> 'amount', p_human, 'amount')));
  hd := lower(btrim(coalesce(p ->> 'head', '')));
  hd := trim(both '_' from left(regexp_replace(hd, '[^a-z0-9_]+', '_', 'g'), 30));
  if length(hd) >= 2 then o := o || jsonb_build_object('head', hd); end if;
  m := lower(btrim(coalesce(p ->> 'mode', '')));
  if m in ('cash', 'bank', 'mobile') then o := o || jsonb_build_object('mode', m); end if;
  if (p ->> 'receipt') in ('true', 'false') then o := o || jsonb_build_object('receipt', (p ->> 'receipt')::boolean); end if;
  if p ? 'lines' then
    if jsonb_typeof(p -> 'lines') <> 'array' then raise exception 'bad_payload'; end if;
    if jsonb_array_length(p -> 'lines') > 300 then raise exception 'too_many_lines'; end if;
    for ln in select * from jsonb_array_elements(p -> 'lines') loop
      if jsonb_typeof(ln) <> 'object' then continue; end if;
      s := jsonb_strip_nulls(jsonb_build_object(
        'desc', public._scan_txt(ln ->> 'desc', 200),
        'qty', public._scan_num(ln ->> 'qty', p_human, 'qty'),
        'unit', public._scan_txt(ln ->> 'unit', 20),
        'unit_cost', public._scan_num(ln ->> 'unit_cost', p_human, 'unit_cost'),
        'amount', public._scan_num(ln ->> 'amount', p_human, 'amount')));
      if p_human then
        sid := public._scan_uuid(ln ->> 'item_id');
        dec := lower(btrim(coalesce(ln ->> 'decision', '')));
        s := s || jsonb_strip_nulls(jsonb_build_object(
          'item_id', sid,
          'decision', case when dec in ('map', 'create', 'text', 'skip') then dec end,
          'name_bn', public._scan_txt(ln ->> 'name_bn', 120),
          'name_en', public._scan_txt(ln ->> 'name_en', 120),
          'category', public._scan_txt(ln ->> 'category', 60),
          'price', public._scan_num(ln ->> 'price', true, 'price')));
      end if;
      ls := ls || jsonb_build_array(s);
    end loop;
    o := o || jsonb_build_object('lines', ls);
  end if;
  return o;
end $$;

-- confidence: numbers 0..1 only, same shape (header keys + lines array of objects); everything else dropped
create or replace function public._scan_conf(p jsonb) returns jsonb language plpgsql stable set search_path = public as $$
declare o jsonb := '{}'::jsonb; k text; v numeric; ln jsonb; ls jsonb := '[]'::jsonb; s jsonb; kk text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  if length(p::text) > 100000 then return null; end if;
  for k in select jsonb_object_keys(p) loop
    if k = 'lines' then
      if jsonb_typeof(p -> 'lines') = 'array' then
        for ln in select * from jsonb_array_elements(p -> 'lines') limit 300 loop
          s := '{}'::jsonb;
          if jsonb_typeof(ln) = 'object' then
            for kk in select jsonb_object_keys(ln) loop
              if kk in ('desc', 'qty', 'unit', 'unit_cost', 'amount') and jsonb_typeof(ln -> kk) = 'number' then
                v := (ln ->> kk)::numeric; s := s || jsonb_build_object(kk, least(1, greatest(0, v)));
              end if;
            end loop;
          end if;
          ls := ls || jsonb_build_array(s);
        end loop;
        o := o || jsonb_build_object('lines', ls);
      end if;
    elsif k in ('supplier', 'bill_no', 'date', 'discount', 'total', 'note', 'title', 'paid_to', 'amount', 'head', 'mode') and jsonb_typeof(p -> k) = 'number' then
      v := (p ->> k)::numeric; o := o || jsonb_build_object(k, least(1, greatest(0, v)));
    end if;
  end loop;
  return o;
end $$;

-- ---------- 5. fuzzy matching (existing names only; nothing is ever invented) ----------
create or replace function public._scan_norm(p text) returns text language sql immutable set search_path = public as $$
  select btrim(regexp_replace(lower(translate(coalesce(p, ''), '০১২৩৪৫৬৭৮৯', '0123456789')), '[^[:alnum:]ঀ-৿]+', ' ', 'g'));
$$;

-- 0..1 : best of (a) character-pair similarity, (b) share of the shorter name's words found in the other (0.85 max)
create or replace function public._scan_sim(a text, b text) returns numeric language plpgsql immutable set search_path = public as $$
declare na text := public._scan_norm(a); nb text := public._scan_norm(b); ba text[]; bb text[]; common int; d numeric := 0; ta text[]; tb text[]; tc int; c numeric := 0;
begin
  if na = '' or nb = '' then return 0; end if;
  if na = nb then return 1; end if;
  ba := array(select distinct substr(na, i, 2) from generate_series(1, length(na) - 1) i);
  bb := array(select distinct substr(nb, i, 2) from generate_series(1, length(nb) - 1) i);
  if cardinality(ba) > 0 and cardinality(bb) > 0 then
    common := (select count(*) from (select unnest(ba) intersect select unnest(bb)) z);
    d := 2.0 * common / (cardinality(ba) + cardinality(bb));
  end if;
  ta := array(select distinct x from unnest(string_to_array(na, ' ')) x where length(x) > 1);
  tb := array(select distinct x from unnest(string_to_array(nb, ' ')) x where length(x) > 1);
  if cardinality(ta) > 0 and cardinality(tb) > 0 then
    tc := (select count(*) from (select unnest(ta) intersect select unnest(tb)) z);
    c := 0.85 * tc / least(cardinality(ta), cardinality(tb));
  end if;
  return round(greatest(d, c), 3);
end $$;

create or replace function public.scan_match_items(p_text text, p_limit int default 5) returns table (item_id uuid, code text, name_bn text, name_en text, unit text, sell_price numeric, score numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('scan_upload') or public.has_grant('scan_confirm'))) then raise exception 'not allowed'; end if;
  if length(coalesce(p_text, '')) > 200 then raise exception 'too_long'; end if;
  return query
    select z.id, z.icode, z.nbn, z.nen, z.iunit, z.price, z.sc from (
      select i.id, i.code icode, i.name_bn nbn, i.name_en nen, i.unit iunit, i.sell_price price,
             greatest(public._scan_sim(p_text, i.name_bn), public._scan_sim(p_text, i.name_en), public._scan_sim(p_text, i.code)) sc
      from public.items i where i.is_active and not coalesce(i.hidden, false)) z
    where z.sc >= 0.35 order by z.sc desc, z.icode limit least(greatest(coalesce(p_limit, 5), 1), 10);
end $$;

create or replace function public.scan_match_suppliers(p_text text, p_limit int default 5) returns table (supplier_id uuid, name text, score numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('scan_upload') or public.has_grant('scan_confirm'))) then raise exception 'not allowed'; end if;
  if length(coalesce(p_text, '')) > 200 then raise exception 'too_long'; end if;
  return query
    select z.id, z.sname, z.sc from (select s.id, s.name sname, public._scan_sim(p_text, s.name) sc from public.suppliers s where s.active) z
    where z.sc >= 0.35 order by z.sc desc, lower(z.sname) limit least(greatest(coalesce(p_limit, 5), 1), 10);
end $$;

-- ---------- 6. internals: totals, duplicates, warnings, trail ----------
create or replace function public._scan_sum(p_edited jsonb) returns numeric language sql immutable set search_path = public as $$
  select coalesce(sum(round(coalesce((l ->> 'qty')::numeric, 0) * coalesce((l ->> 'unit_cost')::numeric, 0), 2)), 0)
         from jsonb_array_elements(coalesce(p_edited -> 'lines', '[]'::jsonb)) l where coalesce(l ->> 'decision', '') <> 'skip';
$$;

create or replace function public._scan_event(p_job uuid, p_action text, p_from text, p_to text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.scan_events (job_id, by_user, by_staff, action, from_status, to_status, detail) values (p_job, auth.uid(), sid, p_action, p_from, p_to, p_detail);
end $$;

-- fingerprint + duplicate list for a job (same supplier + bill no + total ; same place + day + head + amount)
create or replace function public._scan_fp(j public.scan_jobs, p_edited jsonb) returns text language plpgsql stable security definer set search_path = public as $$
declare tot numeric; sid text; bn text;
begin
  if j.kind = 'purchase_bill' then
    sid := p_edited #>> '{supplier,id}';
    if sid is null then return null; end if;
    tot := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    bn := lower(coalesce(p_edited ->> 'bill_no', ''));
    return 'p|' || sid || '|' || case when bn <> '' then bn else coalesce(p_edited ->> 'date', '') end || '|' || tot::text;
  elsif j.kind = 'expense' then
    if p_edited ->> 'date' is null or p_edited ->> 'head' is null or p_edited ->> 'amount' is null then return null; end if;
    return 'e|' || j.location_id || '|' || (p_edited ->> 'date') || '|' || (p_edited ->> 'head') || '|' || ((p_edited ->> 'amount')::numeric)::text;
  end if;
  return null;
end $$;

create or replace function public._scan_dups(j public.scan_jobs, p_edited jsonb, p_fp text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '[]'::jsonb; x record; tot numeric; bn text;
begin
  if j.kind = 'purchase_bill' and p_fp is not null then
    tot := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    bn := nullif(lower(coalesce(p_edited ->> 'bill_no', '')), '');
    for x in select b.id, b.bill_no, b.total, b.status from public.purchase_bills b
             where b.kind = 'bill' and b.status <> 'void' and b.supplier_id::text = (p_edited #>> '{supplier,id}') and b.total = tot
               and (bn is null or lower(coalesce(b.bill_no, '')) = bn) and (bn is not null or b.bill_date::text = p_edited ->> 'date') loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'purchase_bill', 'id', x.id, 'bill_no', x.bill_no, 'total', x.total, 'status', x.status));
    end loop;
  elsif j.kind = 'expense' and p_fp is not null then
    for x in select q.id, q.amount from public.quick_expenses q
             where q.location_id = j.location_id and q.exp_date::text = p_edited ->> 'date' and q.head = p_edited ->> 'head' and q.amount = (p_edited ->> 'amount')::numeric and q.status = 'done' loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'quick_expense', 'id', x.id, 'amount', x.amount));
    end loop;
  end if;
  if p_fp is not null then
    for x in select s.id, s.status from public.scan_jobs s where s.fp = p_fp and s.id <> j.id and s.status <> 'rejected' loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'scan', 'id', x.id, 'status', x.status));
    end loop;
  end if;
  return r;
end $$;

-- warnings only (never block): total that does not add up, unmatched lines, fields the reader was unsure about and nobody changed
create or replace function public._scan_warn(j public.scan_jobs, p_edited jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w jsonb := '[]'::jsonb; mn numeric := coalesce(public.rule_num('scan_min_confidence'), 0.6); k text; i int; f text; ex jsonb := j.extracted; cf jsonb := j.confidence; calc numeric; ln jsonb; n int := 0; pth text[];
begin
  if j.kind = 'purchase_bill' and p_edited ? 'total' then
    calc := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    if abs(calc - (p_edited ->> 'total')::numeric) > 0.5 then
      w := w || jsonb_build_array(jsonb_build_object('code', 'total_mismatch', 'lines_total', calc, 'paper_total', (p_edited ->> 'total')::numeric));
    end if;
  end if;
  if j.kind in ('purchase_bill', 'product_list') then
    for ln in select * from jsonb_array_elements(coalesce(p_edited -> 'lines', '[]'::jsonb)) loop
      if coalesce(ln ->> 'decision', '') = '' then n := n + 1; end if;
    end loop;
    if n > 0 then w := w || jsonb_build_array(jsonb_build_object('code', 'unmatched_lines', 'n', n)); end if;
  end if;
  if cf is not null and ex is not null then
    for k in select jsonb_object_keys(cf) loop
      if k = 'lines' then
        for i in 0 .. coalesce(jsonb_array_length(cf -> 'lines'), 0) - 1 loop
          for f in select jsonb_object_keys(cf -> 'lines' -> i) loop
            if (cf -> 'lines' -> i ->> f)::numeric < mn and (p_edited -> 'lines' -> i ->> f) is not distinct from (ex -> 'lines' -> i ->> f) and (p_edited -> 'lines' -> i ->> f) is not null
              and coalesce(p_edited -> 'lines' -> i ->> 'decision', '') <> 'skip' then
              w := w || jsonb_build_array(jsonb_build_object('code', 'low_confidence', 'line', i + 1, 'field', f, 'confidence', (cf -> 'lines' -> i ->> f)::numeric));
            end if;
          end loop;
        end loop;
      else
        pth := case when k = 'supplier' then array['supplier', 'name'] else array[k] end;
        if (cf ->> k)::numeric < mn and (p_edited #>> pth) is not distinct from (ex #>> pth) and (p_edited #>> pth) is not null then
          w := w || jsonb_build_array(jsonb_build_object('code', 'low_confidence', 'field', k, 'confidence', (cf ->> k)::numeric));
        end if;
      end if;
    end loop;
  end if;
  return w;
end $$;

-- ---------- 7. browser functions ----------
-- create the job after the photo is uploaded (the client sends the Storage path it just uploaded). Idempotent on p_client.
create or replace function public.scan_create(p_client uuid, p_kind text, p_loc int, p_image_path text, p_image_hash text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; sid text; same jsonb := '[]'::jsonb; x record;
begin
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if not (public.is_active() and public.can_loc(p_loc) and public.has_grant('scan_upload', p_loc)) then raise exception 'not allowed'; end if;
  select * into j from public.scan_jobs where client_id = p_client;
  if found then
    if j.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('id', j.id, 'status', j.status, 'engine', j.engine, 'dup', true);
  end if;
  if not public.rule_on('scan_enabled') then raise exception 'scan_off'; end if;
  if p_kind not in ('purchase_bill', 'product_list', 'expense', 'other') then raise exception 'bad_kind'; end if;
  if p_image_path is null or p_image_path !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or length(p_image_path) > 300 then raise exception 'bad_image_path'; end if;
  if split_part(p_image_path, '/', 2)::int <> p_loc then raise exception 'bad_image_path'; end if;
  if exists (select 1 from public.scan_jobs where image_path = p_image_path) then raise exception 'image_already_used'; end if;
  if p_image_hash is not null and p_image_hash !~ '^[0-9a-f]{16,128}$' then raise exception 'bad_hash'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.scan_jobs (client_id, kind, location_id, image_path, image_hash, engine, note, created_by, created_staff)
    values (p_client, p_kind, p_loc, p_image_path, p_image_hash, coalesce(public.rule_txt('scan_engine'), 'manual'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid)
    returning * into j;
  perform public._scan_event(j.id, 'created', null, 'uploaded', jsonb_build_object('kind', p_kind, 'engine', j.engine));
  if p_image_hash is not null then       -- the same picture twice is only a warning
    for x in select s.id, s.status from public.scan_jobs s where s.image_hash = p_image_hash and s.id <> j.id and s.status <> 'rejected' and public._scan_can_see(s) loop
      same := same || jsonb_build_array(jsonb_build_object('id', x.id, 'status', x.status));
    end loop;
  end if;
  return jsonb_build_object('id', j.id, 'status', j.status, 'engine', j.engine, 'same_photo', same);
end $$;

-- the reader's result (called by the edge function with the USER'S own login, or by the browser for OCR). It can only ever make a DRAFT.
create or replace function public.scan_set_extracted(p_id uuid, p_extracted jsonb, p_confidence jsonb default null, p_engine text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ex jsonb; cf jsonb; eng text;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted') then raise exception 'not_open: %', j.status; end if;
  eng := coalesce(p_engine, j.engine);
  if eng not in ('manual', 'browser_ocr', 'ai_vision') then raise exception 'bad_engine'; end if;
  if p_error is not null then          -- the reader failed: the job stays open, the person types it by hand
    update public.scan_jobs set extract_error = left(btrim(p_error), 300), updated_at = now() where id = p_id;
    perform public._scan_event(p_id, 'extract_failed', j.status, j.status, jsonb_build_object('engine', eng, 'error', left(btrim(p_error), 300)));
    return jsonb_build_object('id', p_id, 'status', j.status, 'failed', true);
  end if;
  ex := public._scan_clean(j.kind, p_extracted, false);
  cf := public._scan_conf(p_confidence);
  update public.scan_jobs set extracted = ex, confidence = cf, engine = eng, status = 'extracted', extract_error = null, updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'extracted', j.status, 'extracted', jsonb_build_object('engine', eng, 'lines', coalesce(jsonb_array_length(ex -> 'lines'), 0)));
  return jsonb_build_object('id', p_id, 'status', 'extracted', 'extracted', case when public._scan_content_ok(j) then ex else null end);
end $$;

-- save the person's edits. p_final = false: keep working (status goes back to extracted / uploaded). p_final = true: mark as REVIEWED (ready for Confirm).
create or replace function public.scan_review_save(p_id uuid, p_edited jsonb, p_final boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ed jsonb; v_fp text; v_dups jsonb; wn jsonb; st text; prev text;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if not public._scan_content_ok(j) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted', 'reviewed') then raise exception 'not_open: %', j.status; end if;
  ed := public._scan_clean(j.kind, p_edited, true);
  v_fp := public._scan_fp(j, ed); v_dups := public._scan_dups(j, ed, v_fp); wn := public._scan_warn(j, ed);
  prev := j.status;
  st := case when coalesce(p_final, false) then 'reviewed' when j.extracted is not null then 'extracted' else 'uploaded' end;
  update public.scan_jobs set edited = ed, fp = v_fp, dups = v_dups, status = st, updated_at = now(),
         reviewed_by = case when st = 'reviewed' then auth.uid() else null end, reviewed_at = case when st = 'reviewed' then now() else null end where id = p_id;
  perform public._scan_event(p_id, case when st = 'reviewed' then 'reviewed' else 'saved' end, prev, st, jsonb_build_object('edited', ed, 'dups', jsonb_array_length(v_dups)));
  return jsonb_build_object('id', p_id, 'status', st, 'dups', v_dups, 'warnings', wn);
end $$;

-- CONFIRM: the only place where a scan becomes a record, and only through the existing save functions, in this one transaction.
create or replace function public.scan_confirm(p_id uuid, p_client uuid, p_ack_dup boolean default false, p_post boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ed jsonb; ln jsonb; lines jsonb := '[]'::jsonb; sup uuid; supn text; r jsonb; pb jsonb; ck uuid; it uuid; patch jsonb; res jsonb := '{}'::jsonb;
        created_n int := 0; updated_n int := 0; made jsonb := '[]'::jsonb; nm text; v_dups jsonb; v_fp text; wn jsonb; dt date; qty numeric; uc numeric; kept int := 0; rid text; rtype text; simsup numeric;
begin
  if p_client is null then raise exception 'client_required'; end if;
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if j.status = 'confirmed' then
    if j.confirm_client = p_client then
      perform public._scan_event(p_id, 'confirm_replay', 'confirmed', 'confirmed', null);
      return jsonb_build_object('id', p_id, 'status', 'confirmed', 'dup', true, 'result_type', j.result_type, 'result_id', j.result_id, 'result', j.result);
    end if;
    raise exception 'already_confirmed';
  end if;
  if not (public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if not public._scan_content_ok(j) then raise exception 'not allowed'; end if;
  if j.status <> 'reviewed' or j.edited is null then raise exception 'not_reviewed'; end if;
  ed := j.edited;
  ck := md5('scan-confirm:' || j.id::text)::uuid;                  -- the same key goes to the existing save function: a replay can never save twice
  v_fp := public._scan_fp(j, ed); v_dups := public._scan_dups(j, ed, v_fp);
  if jsonb_array_length(v_dups) > 0 and not coalesce(p_ack_dup, false) then
    raise exception 'duplicate_suspect: %', v_dups::text;
  end if;
  wn := public._scan_warn(j, ed);

  if j.kind = 'purchase_bill' then
    -- supplier: picked, or created by an explicit owner action (never silently)
    sup := public._scan_uuid(ed #>> '{supplier,id}');
    if sup is null then
      supn := public._scan_txt(ed #>> '{supplier,name}', 120);
      if supn is null or (ed #>> '{supplier,create}') is distinct from 'true' then raise exception 'supplier_not_mapped'; end if;
      select coalesce(max(public._scan_sim(supn, s.name)), 0) into simsup from public.suppliers s where s.active;
      if simsup >= 0.9 then raise exception 'similar_supplier_exists'; end if;
      sup := public.save_supplier(null, jsonb_build_object('name', supn));
    end if;
    dt := public._scan_date(ed ->> 'date', true);
    if dt is null then raise exception 'bad_date'; end if;
    for ln in select * from jsonb_array_elements(coalesce(ed -> 'lines', '[]'::jsonb)) loop
      case coalesce(ln ->> 'decision', '')
        when '' then raise exception 'unmatched_lines';
        when 'skip' then continue;
        when 'map' then
          it := public._scan_uuid(ln ->> 'item_id');
          if it is null or not exists (select 1 from public.items where id = it and is_active) then raise exception 'item_not_found'; end if;
        when 'text' then
          it := null; if public._scan_txt(ln ->> 'desc', 200) is null then raise exception 'description_required'; end if;
        when 'create' then
          nm := coalesce(public._scan_txt(ln ->> 'name_en', 120), public._scan_txt(ln ->> 'name_bn', 120), public._scan_txt(ln ->> 'desc', 120));
          if nm is null then raise exception 'name_required'; end if;
          patch := jsonb_strip_nulls(jsonb_build_object('name_en', coalesce(public._scan_txt(ln ->> 'name_en', 120), case when nm !~ '[ঀ-৿]' then nm end),
                      'name_bn', coalesce(public._scan_txt(ln ->> 'name_bn', 120), case when nm ~ '[ঀ-৿]' then nm end),
                      'unit', public._scan_txt(ln ->> 'unit', 20), 'category', public._scan_txt(ln ->> 'category', 60)));
          r := public.item_new(patch, 'scan ' || left(j.id::text, 8));
          if r ->> 'status' <> 'created' then raise exception 'item_needs_approval'; end if;
          it := (r ->> 'item_id')::uuid; created_n := created_n + 1; made := made || jsonb_build_array(r);
        else raise exception 'bad_decision';
      end case;
      qty := public._scan_num(ln ->> 'qty', true, 'qty'); uc := public._scan_num(ln ->> 'unit_cost', true, 'unit_cost');
      if qty is null or qty <= 0 then raise exception 'bad_qty'; end if;
      if uc is null then raise exception 'bad_cost'; end if;
      lines := lines || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('item_id', it, 'description', case when it is null then public._scan_txt(ln ->> 'desc', 120) end,
                 'qty', qty, 'unit', public._scan_txt(ln ->> 'unit', 20), 'unit_cost', uc)));
      kept := kept + 1;
    end loop;
    if kept = 0 then raise exception 'no_lines'; end if;
    pb := public.save_purchase(ck, null, sup, j.location_id, ed ->> 'bill_no', dt, lines, coalesce((ed ->> 'discount')::numeric, 0), left('scan ' || left(j.id::text, 8) || coalesce(' | ' || (ed ->> 'note'), ''), 300), null, 'bill', null, null);
    rid := pb ->> 'id'; rtype := 'purchase_bills';
    res := jsonb_build_object('purchase', pb, 'items_created', created_n);
    if coalesce(p_post, false) then res := res || jsonb_build_object('posted', public.post_purchase(rid::uuid, null)); end if;

  elsif j.kind = 'expense' then
    dt := public._scan_date(ed ->> 'date', true);
    if dt is null then raise exception 'bad_date'; end if;
    if ed ->> 'head' is null then raise exception 'head_needed'; end if;
    if (ed ->> 'amount') is null then raise exception 'bad_amount'; end if;
    r := public.quick_expense_add(j.location_id, dt, ed ->> 'head', ed ->> 'paid_to', (ed ->> 'amount')::numeric, coalesce(ed ->> 'mode', 'cash'),
                                  coalesce((ed ->> 'receipt')::boolean, false), left('scan ' || left(j.id::text, 8) || coalesce(' | ' || (ed ->> 'note'), ''), 300), ck);
    rid := r ->> 'id'; rtype := 'quick_expenses'; res := jsonb_build_object('expense', r);

  elsif j.kind = 'product_list' then
    for ln in select * from jsonb_array_elements(coalesce(ed -> 'lines', '[]'::jsonb)) loop
      case coalesce(ln ->> 'decision', '')
        when '' then raise exception 'unmatched_lines';
        when 'skip' then continue;
        when 'text' then continue;
        when 'map' then
          it := public._scan_uuid(ln ->> 'item_id');
          if it is null or not exists (select 1 from public.items where id = it) then raise exception 'item_not_found'; end if;
          if (ln ->> 'price') is not null then
            r := public.item_apply(it, jsonb_build_object('sell_price', round((ln ->> 'price')::numeric, 2)::text), 'scan ' || left(j.id::text, 8));
            updated_n := updated_n + 1; made := made || jsonb_build_array(r);
          end if;
        when 'create' then
          nm := coalesce(public._scan_txt(ln ->> 'name_en', 120), public._scan_txt(ln ->> 'name_bn', 120), public._scan_txt(ln ->> 'desc', 120));
          if nm is null then raise exception 'name_required'; end if;
          patch := jsonb_strip_nulls(jsonb_build_object('name_en', coalesce(public._scan_txt(ln ->> 'name_en', 120), case when nm !~ '[ঀ-৿]' then nm end),
                      'name_bn', coalesce(public._scan_txt(ln ->> 'name_bn', 120), case when nm ~ '[ঀ-৿]' then nm end),
                      'unit', public._scan_txt(ln ->> 'unit', 20), 'category', public._scan_txt(ln ->> 'category', 60),
                      'sell_price', case when (ln ->> 'price') is not null then round((ln ->> 'price')::numeric, 2)::text end));
          r := public.item_new(patch, 'scan ' || left(j.id::text, 8));
          created_n := created_n + 1; made := made || jsonb_build_array(r);
        else raise exception 'bad_decision';
      end case;
    end loop;
    if created_n + updated_n = 0 then raise exception 'no_lines'; end if;
    rid := j.id::text; rtype := 'items'; res := jsonb_build_object('created', created_n, 'updated', updated_n, 'items', made);

  else                                   -- 'other' (a report / any paper): kept as a reviewed record, nothing is posted
    rid := null; rtype := 'none'; res := jsonb_build_object('note', 'archived, nothing posted');
  end if;

  update public.scan_jobs set status = 'confirmed', result_type = rtype, result_id = rid, result = res, confirm_client = p_client, confirmed_by = auth.uid(), confirmed_at = now(),
         fp = v_fp, dups = v_dups, updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'confirmed', 'reviewed', 'confirmed', jsonb_build_object('result_type', rtype, 'result_id', rid, 'ack_dup', coalesce(p_ack_dup, false), 'warnings', wn));
  return jsonb_build_object('id', p_id, 'status', 'confirmed', 'result_type', rtype, 'result_id', rid, 'result', res, 'warnings', wn);
end $$;

create or replace function public.scan_reject(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if j.status = 'rejected' then return jsonb_build_object('id', p_id, 'status', 'rejected', 'noop', true); end if;
  if j.status = 'confirmed' then raise exception 'already_confirmed'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if length(coalesce(btrim(p_reason), '')) < 3 then raise exception 'note_needed'; end if;
  update public.scan_jobs set status = 'rejected', reject_reason = left(btrim(p_reason), 300), rejected_by = auth.uid(), rejected_at = now(), updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'rejected', j.status, 'rejected', jsonb_build_object('reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', p_id, 'status', 'rejected');
end $$;

create or replace function public.scan_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j public.scan_jobs; ok boolean; ev jsonb;
begin
  select * into j from public.scan_jobs where id = p_id;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  ok := public._scan_content_ok(j);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'action', e.action, 'from', e.from_status, 'to', e.to_status, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev from public.scan_events e where e.job_id = j.id;
  return jsonb_build_object('id', j.id, 'kind', j.kind, 'location_id', j.location_id, 'status', j.status, 'engine', j.engine, 'image_path', j.image_path, 'note', j.note,
    'extract_error', j.extract_error, 'created_at', j.created_at, 'created_staff', j.created_staff, 'mine', j.created_by = auth.uid(),
    'cost_hidden', not ok, 'extracted', case when ok then j.extracted end, 'confidence', case when ok then j.confidence end, 'edited', case when ok then j.edited end,
    'dups', case when ok then j.dups end, 'warnings', case when ok and j.status in ('extracted', 'reviewed') then public._scan_warn(j, coalesce(j.edited, j.extracted, '{}'::jsonb)) end,
    'result_type', j.result_type, 'result_id', j.result_id, 'reject_reason', j.reject_reason, 'events', ev,
    'can_confirm', public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id) and ok);
end $$;

create or replace function public.scan_list(p_status text default null, p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'kind', z.kind, 'location_id', z.location_id, 'status', z.status, 'engine', z.engine, 'created_at', z.created_at,
      'created_staff', z.created_staff, 'mine', z.created_by = auth.uid(), 'dups', coalesce(jsonb_array_length(z.dups), 0), 'result_type', z.result_type) order by z.created_at desc)
    from (select j.* from public.scan_jobs j where public._scan_can_see(j) and (p_status is null or j.status = p_status) and (p_loc is null or j.location_id = p_loc)
          order by j.created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 8. privileges ----------
revoke all on function public._scan_can_see(public.scan_jobs), public._scan_content_ok(public.scan_jobs), public._scan_photo_ok(text, text),
  public._scan_txt(text, int), public._scan_num(text, boolean, text, numeric), public._scan_date(text, boolean), public._scan_uuid(text),
  public._scan_clean(text, jsonb, boolean), public._scan_conf(jsonb), public._scan_norm(text), public._scan_sim(text, text), public._scan_sum(jsonb),
  public._scan_event(uuid, text, text, text, jsonb), public._scan_fp(public.scan_jobs, jsonb), public._scan_dups(public.scan_jobs, jsonb, text), public._scan_warn(public.scan_jobs, jsonb),
  public._scan_jobs_guard90() from public, anon, authenticated;
-- storage policies run as the caller, so the photo check must stay callable by authenticated
grant execute on function public._scan_photo_ok(text, text) to authenticated;
revoke all on function public.scan_create(uuid, text, int, text, text, text), public.scan_set_extracted(uuid, jsonb, jsonb, text, text), public.scan_review_save(uuid, jsonb, boolean),
  public.scan_confirm(uuid, uuid, boolean, boolean), public.scan_reject(uuid, text), public.scan_get(uuid), public.scan_list(text, int, int),
  public.scan_match_items(text, int), public.scan_match_suppliers(text, int) from public, anon;
grant execute on function public.scan_create(uuid, text, int, text, text, text), public.scan_set_extracted(uuid, jsonb, jsonb, text, text), public.scan_review_save(uuid, jsonb, boolean),
  public.scan_confirm(uuid, uuid, boolean, boolean), public.scan_reject(uuid, text), public.scan_get(uuid), public.scan_list(text, int, int),
  public.scan_match_items(text, int), public.scan_match_suppliers(text, int) to authenticated;
notify pgrst, 'reload schema';

-- ============================================================
-- Phase 520 (X5): ITEM RECOGNITION FOUNDATION (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase14 and phase15 applied first (item_new, _opt_norm, _opt_lev1, items.barcode unique index).
--   * rules (ALL OFF by default): item_similar_check_on, recog_ocr_on, recog_image_match_on, recog_vision_on,
--     recog_vision_consent_on; numbers / text blank by default: recog_image_threshold, recog_ocr_max_px, recog_ocr_langs, recog_vision_budget;
--     recog_ocr_wifi_only ON (safe default)
--   * item_similar(name_bn, name_en, barcode): duplicate / similar check, option_similar contract
--     {status: 'exists' | 'similar' | 'none', similar: [...], barcode_hit: item|null}. No pg_trgm: own normalised match (works on any plan).
--   * item_new2(patch, note, client_id, force): idempotent item creation. Same client_id twice = the first answer again (never a second item).
--     Barcode already used -> 'barcode_exists' (nothing created). Exact name -> 'exists' (never created). Close/contains names -> 'similar'
--     unless force = true. The item itself is still created by the existing item_new (approval rules unchanged).
--     With rule item_similar_check_on OFF the checks in front of item_new are skipped (same result as item_new, plus the client_id answer).
--   * item_new_clients: one row per (user, client_id) with the stored answer (RLS closed, written only by item_new2)
--   * item_recognition_reviews: decisions on an unclear recognition (approved / rejected / ambiguous / manual) with a reason; written by RPC only
--   * item_aliases: an approved alias text -> item (memory, not model training). item_alias_approve (owner or ITEMS approve), item_alias_find
--   * assets: brand, serial_no, warranty_until (new nullable columns); asset_identity_set RPC (same permission as asset_update)
--   Nothing is deleted. No price, limit or date is invented. Every new behaviour is OFF or empty by default.
-- ============================================================

-- ---------- (1) rules (OFF by default) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('item_similar_check_on', 'items', 'switch', 'false', null, null, null, null, 'নতুন আইটেমে নাম/বারকোডের মিল-পরীক্ষা চালু', 'নতুন item এ name/barcode similar-check চালু', 'Similar-name and barcode check when adding an item',
   'চালু থাকলে প্রায় একই নামের আইটেম দেখিয়ে জিজ্ঞাসা করা হয়', 'On হলে similar name দেখিয়ে confirm চাওয়া হবে', 'On = a look-alike name is shown and the person must confirm (or force). Exact same name is always refused. Off = no check (as before)', 520),
 ('recog_ocr_on', 'items', 'switch', 'false', null, null, null, null, 'লেবেল থেকে লেখা পড়া (ফোনের ভেতরে, OCR) চালু', 'Label থেকে লেখা পড়া (phone এ, OCR) চালু', 'Read label text on the phone (OCR)',
   'ছবি ফোন থেকে বাইরে যায় না; প্রথমবার ভাষার ফাইল নামাতে হতে পারে', 'Image phone ছাড়ে না; প্রথমবার language file নামাতে হতে পারে', 'On = the camera label is read on this phone only. The first use may download a language file (Wi-Fi only if the next switch is on)', 521),
 ('recog_image_match_on', 'items', 'switch', 'false', null, null, null, null, 'ছবি মিলিয়ে আইটেম খোঁজা (ফোনের ভেতরে) চালু', 'Photo মিলিয়ে item খোঁজা (phone এ) চালু', 'Match a photo to approved item photos (on the phone)',
   'ছবির তুলনা শুধু ফোনে; ছবি বাইরে যায় না', 'Photo তুলনা শুধু phone এ; ছবি বাইরে যায় না', 'On = the photo is compared with the approved item photos on this phone. Nothing leaves the phone', 522),
 ('recog_vision_on', 'items', 'switch', 'false', null, null, null, null, 'সার্ভার ভিশন সেবা (অর্থ খরচ, মালিকের অনুমতি লাগে) চালু', 'Server vision সেবা (খরচ আছে, owner অনুমতি লাগে) চালু', 'Server vision service (paid, needs consent) on',
   'টাকা খরচ হয়; X1 সংযোগ ছাড়া কাজ করবে না', 'খরচ আছে; X1 connection ছাড়া চলবে না', 'Off by default. Needs the consent switch below as well. The image leaves the phone only when both are on', 523),
 ('recog_vision_consent_on', 'items', 'switch', 'false', null, null, null, null, 'ছবি সার্ভার ভিশন সেবায় পাঠানোর সম্মতি', 'Photo server vision এ পাঠানোর সম্মতি', 'Consent to send label photos to the server vision service',
   'এই সম্মতি না দিলে কোনো ছবি বাইরে যায় না', 'Consent না দিলে কোনো photo বাইরে যায় না', 'Default NO. Only the owner can switch it on', 524),
 ('recog_image_threshold', 'items', 'number', null, null, null, 0, 2, 'ছবি মেলানোর সীমা (দূরত্ব, খালি = বন্ধ)', 'Photo মেলানোর সীমা (distance, খালি = off)', 'Photo match distance limit (blank = not set)',
   'খালি থাকলে ছবি মেলানো কোনো তালিকা দেখাবে না', 'খালি থাকলে photo match list দেখাবে না', 'Nearest matches with a distance above this are not shown. Blank = not set: no photo candidates are shown. Distance is shown as a number, never as a percentage', 525)
on conflict (key) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('recog_ocr_max_px', 'items', 'number', null, 'px', null, 320, 4096, 'লেবেল ছবির সর্বোচ্চ মাপ (পিক্সেল, খালি = বন্ধ)', 'Label ছবির সর্বোচ্চ মাপ (px, খালি = off)', 'Label photo longest side in pixels (blank = not set)',
   'খালি থাকলে লেখা পড়া চালানো যাবে না', 'খালি থাকলে OCR চলবে না', 'Smaller is faster on old phones but reads less. Blank blocks OCR: no size is assumed', 526),
 ('recog_ocr_langs', 'items', 'text', null, null, null, null, null, 'লেখা পড়ার ভাষা (যেমন eng+ben)', 'লেখা পড়ার ভাষা (যেমন eng+ben)', 'Languages to read (for example eng+ben)',
   'খালি থাকলে লেখা পড়া চলবে না', 'খালি থাকলে OCR চলবে না', 'Blank blocks OCR. eng = English, ben = Bangla. Each language is a file that is downloaded once', 527),
 ('recog_ocr_wifi_only', 'items', 'switch', 'true', null, null, null, null, 'ভাষার ফাইল শুধু ওয়াই-ফাইয়ে নামানো', 'Language file শুধু Wi-Fi এ নামানো', 'Download language files on Wi-Fi only',
   'মোবাইল ডেটায় নামবে না', 'Mobile data তে নামবে না', 'On = the language file is downloaded only on Wi-Fi (a file already on the phone is always used)', 528),
 ('recog_vision_budget', 'items', 'number', null, 'calls', null, 0, 100000, 'ভিশন সেবার মাসিক সীমা (বার, খালি = বন্ধ)', 'Vision সেবার মাসিক সীমা (বার, খালি = off)', 'Vision service monthly call cap (blank = not set)',
   'খালি থাকলে ভিশন সেবা চলবে না', 'খালি থাকলে vision চলবে না', 'Blank blocks the vision service. The cap is counted per month; no price is assumed', 529)
on conflict (key) do nothing;

-- ---------- (2) idempotent creation log ----------
create table if not exists public.item_new_clients (
  user_id uuid not null, client_id uuid not null,
  item_id uuid, status text not null, result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, client_id)
);
alter table public.item_new_clients enable row level security;
revoke all on public.item_new_clients from public, anon, authenticated;
drop trigger if exists item_new_clients_no_delete on public.item_new_clients;
create trigger item_new_clients_no_delete before delete on public.item_new_clients for each row execute function public.no_hard_delete();

-- ---------- (3) similar check (option_similar contract) ----------
create or replace function public.item_similar(p_name_bn text default null, p_name_en text default null, p_barcode text default null, p_exclude uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare names text[]; r record; rn text[]; a text; b text; hit text; res jsonb := '[]'::jsonb; bc jsonb := null; bcode text := nullif(btrim(p_barcode), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if length(coalesce(p_name_bn, '')) > 120 or length(coalesce(p_name_en, '')) > 120 then raise exception 'name_too_long'; end if;
  if bcode is not null then
    select jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en) into bc
      from public.items i where i.barcode = bcode and (p_exclude is null or i.id <> p_exclude) limit 1;
  end if;
  names := array(select x from unnest(array[public._opt_norm(p_name_bn), public._opt_norm(p_name_en)]) x where x <> '');
  if coalesce(array_length(names, 1), 0) > 0 then
    for r in select i.* from public.items i where (p_exclude is null or i.id <> p_exclude) order by i.code loop
      rn := array(select x from unnest(array[public._opt_norm(r.name_bn), public._opt_norm(r.name_en), public._opt_norm(r.name_mix)]) x where x <> '');
      hit := null;
      foreach a in array names loop
        foreach b in array rn loop
          if a = b then hit := 'same';
          elsif hit is distinct from 'same' and least(length(a), length(b)) >= 3 and (position(a in b) > 0 or position(b in a) > 0) then hit := coalesce(hit, 'contains');
          elsif hit is null and public._opt_lev1(a, b) then hit := 'close'; end if;
        end loop;
      end loop;
      if hit is not null then
        res := res || jsonb_build_array(jsonb_build_object('item_id', r.id, 'code', r.code, 'name_bn', r.name_bn, 'name_en', r.name_en,
                 'active', r.is_active, 'kind', hit));
      end if;
    end loop;
  end if;
  res := coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(res) e
           order by case e->>'kind' when 'same' then 0 when 'contains' then 1 else 2 end, e->>'code' limit 8) q), '[]'::jsonb);
  return jsonb_build_object('status',
           case when bc is not null then 'barcode_exists'
                when exists (select 1 from jsonb_array_elements(res) e where e->>'kind' = 'same') then 'exists'
                when jsonb_array_length(res) > 0 then 'similar' else 'none' end,
           'similar', res, 'barcode_hit', bc);
end $$;

-- ---------- (4) idempotent creation (wrapper; item_new itself is unchanged) ----------
create or replace function public.item_new2(p_patch jsonb, p_note text default null, p_client uuid default null, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare prev public.item_new_clients; sim jsonb; out_ jsonb; st text; iid uuid;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if p_client is not null then
    select * into prev from public.item_new_clients where user_id = auth.uid() and client_id = p_client;
    if found then return prev.result || jsonb_build_object('repeat', true); end if;
  end if;
  if public.rule_on('item_similar_check_on') then
    sim := public.item_similar(p_patch->>'name_bn', p_patch->>'name_en', p_patch->>'barcode', null);
    st := sim->>'status';
    if st = 'barcode_exists' then return jsonb_build_object('status', 'barcode_exists', 'barcode_hit', sim->'barcode_hit'); end if;
    if st = 'exists' then return jsonb_build_object('status', 'exists', 'similar', sim->'similar'); end if;
    if st = 'similar' and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim->'similar'); end if;
  end if;
  out_ := public.item_new(p_patch, p_note);
  iid := nullif(out_->>'item_id', '')::uuid;
  if p_client is not null then
    insert into public.item_new_clients (user_id, client_id, item_id, status, result)
      values (auth.uid(), p_client, iid, out_->>'status', out_) on conflict (user_id, client_id) do nothing;
  end if;
  return out_;
end $$;

-- ---------- (5) recognition review queue ----------
create table if not exists public.item_recognition_reviews (
  id bigserial primary key,
  item_id uuid references public.items(id),
  engine text not null check (engine in ('barcode', 'ocr', 'image', 'vision', 'manual', 'name')),
  candidate_item_id uuid references public.items(id),
  decision text not null check (decision in ('approved', 'rejected', 'ambiguous', 'manual')),
  reason text check (reason is null or length(reason) <= 300),
  decided_by uuid default auth.uid(), decided_at timestamptz not null default now()
);
create index if not exists item_recog_rev_item_idx on public.item_recognition_reviews (item_id);
alter table public.item_recognition_reviews enable row level security;
drop policy if exists item_recog_rev_read on public.item_recognition_reviews;
create policy item_recog_rev_read on public.item_recognition_reviews for select to authenticated
  using (public.is_owner() or public.can_do('ITEMS', 'approve') or public.can_do('ITEMS', 'enter'));
revoke all on public.item_recognition_reviews from public, anon, authenticated;
grant select on public.item_recognition_reviews to authenticated;
grant usage, select on sequence public.item_recognition_reviews_id_seq to authenticated;
drop trigger if exists audit_item_recog_rev on public.item_recognition_reviews;
create trigger audit_item_recog_rev after insert on public.item_recognition_reviews for each row execute function public.log_change('id');
drop trigger if exists item_recog_rev_no_delete on public.item_recognition_reviews;
create trigger item_recog_rev_no_delete before delete or update on public.item_recognition_reviews for each row execute function public.no_hard_delete();

create or replace function public.item_recognition_review_add(p_item uuid, p_engine text, p_candidate uuid, p_decision text, p_reason text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'enter')) then raise exception 'not allowed'; end if;
  if p_decision not in ('approved', 'rejected', 'ambiguous', 'manual') then raise exception 'bad_decision'; end if;
  if p_decision in ('rejected', 'ambiguous') and nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  if p_decision = 'approved' and p_candidate is null then raise exception 'candidate_required'; end if;
  insert into public.item_recognition_reviews (item_id, engine, candidate_item_id, decision, reason)
    values (p_item, p_engine, p_candidate, p_decision, left(nullif(btrim(p_reason), ''), 300)) returning id into rid;
  return rid;
end $$;

-- ---------- (6) aliases: approved alias text -> item (memory, not training) ----------
create table if not exists public.item_aliases (
  id bigserial primary key,
  alias text not null check (length(alias) between 1 and 120),
  norm text not null,
  item_id uuid not null references public.items(id),
  source text not null check (source in ('barcode', 'label_text', 'photo', 'dictionary', 'manual')),
  approved_by uuid not null default auth.uid(), approved_at timestamptz not null default now(), active boolean not null default true,
  unique (norm, item_id)
);
create index if not exists item_aliases_norm_idx on public.item_aliases (norm);
alter table public.item_aliases enable row level security;
drop policy if exists item_aliases_read on public.item_aliases;
create policy item_aliases_read on public.item_aliases for select to authenticated using (public.is_active());
revoke all on public.item_aliases from public, anon, authenticated;
grant select on public.item_aliases to authenticated;
drop trigger if exists audit_item_aliases on public.item_aliases;
create trigger audit_item_aliases after insert or update on public.item_aliases for each row execute function public.log_change('id');
drop trigger if exists item_aliases_no_delete on public.item_aliases;
create trigger item_aliases_no_delete before delete on public.item_aliases for each row execute function public.no_hard_delete();

create or replace function public.item_alias_approve(p_alias text, p_item uuid, p_source text)
returns bigint language plpgsql security definer set search_path = public as $$
declare aid bigint; n text := public._opt_norm(p_alias);
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve')) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if n = '' then raise exception 'name_required'; end if;
  insert into public.item_aliases (alias, norm, item_id, source) values (left(btrim(p_alias), 120), n, p_item, p_source)
    on conflict (norm, item_id) do update set active = true, approved_at = now() returning id into aid;
  return aid;
end $$;

-- alias text -> the items it was approved for (only active aliases)
create or replace function public.item_alias_find(p_text text)
returns table (item_id uuid, code text, name_bn text, name_en text, source text)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, i.name_bn, i.name_en, a.source
  from public.item_aliases a join public.items i on i.id = a.item_id
  where public.is_active() and a.active and a.norm = public._opt_norm(p_text)
  order by i.code limit 10;
$$;

-- ---------- (7) assets: brand, serial, warranty (nullable; asset_add / asset_update unchanged) ----------
alter table public.assets add column if not exists brand text check (brand is null or length(brand) <= 80);
alter table public.assets add column if not exists serial_no text check (serial_no is null or length(serial_no) <= 80);
alter table public.assets add column if not exists warranty_until date;
create unique index if not exists assets_serial_uq on public.assets (item_id, lower(serial_no)) where serial_no is not null;

create or replace function public.asset_identity_set(p_id uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.assets;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_request'; end if;
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  update public.assets set
    brand = case when p ? 'brand' then left(nullif(btrim(p->>'brand'), ''), 80) else brand end,
    serial_no = case when p ? 'serial_no' then left(nullif(btrim(p->>'serial_no'), ''), 80) else serial_no end,
    warranty_until = case when p ? 'warranty_until' then nullif(p->>'warranty_until', '')::date else warranty_until end
  where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

-- ---------- (8) grants ----------
revoke all on function public.item_similar(text, text, text, uuid), public.item_new2(jsonb, text, uuid, boolean), public.item_recognition_review_add(uuid, text, uuid, text, text),
  public.item_alias_approve(text, uuid, text), public.item_alias_find(text), public.asset_identity_set(uuid, jsonb) from public, anon;
grant execute on function public.item_similar(text, text, text, uuid), public.item_new2(jsonb, text, uuid, boolean), public.item_recognition_review_add(uuid, text, uuid, text, text),
  public.item_alias_approve(text, uuid, text), public.item_alias_find(text), public.asset_identity_set(uuid, jsonb) to authenticated;

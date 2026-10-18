-- ============================================================
-- Phase 491 (X2 website, part 2) - CHECKOUT, HARD STOCK HOLDS, TRACKING, CANCEL / CUSTOM CAKE REQUESTS, OWNER ADMIN, DRIFT, GO-LIVE CHECKLIST.
-- Run AFTER phase490. Additive + idempotent (paste twice = no error). No earlier phase file is edited.
--   1. CHECKOUT      web_checkout_submit(): PUBLIC (anon). Idempotent on a browser-made submission id (same id twice = the same order).
--                    Rate limited per device hash (rule website_rate_max). Re-prices and re-checks the cart on the server (web_quote).
--                    Writes ONE online_orders row (channel 'website', status 'new'). Staff then confirm/pack/deliver with the existing screens.
--                    Payment: COD, or bKash/Nagad manual with a Trx ID (verified by staff; nothing is paid automatically).
--   2. HOLDS         rule website_reserve_on (OFF). When on, checkout locks the items and writes web_stock_holds rows (expire after
--                    website_reserve_minutes). Holds are released on expiry (web_holds_expire, also run inside checkout), released on
--                    cancel, consumed on delivery. Two checkouts can never take the last unit (advisory lock per item and branch).
--   3. TRACKING      web_order_track(code, mobile): customer sees status only (no staff names, no internal notes).
--                    web_order_cancel_request(): customer asks; owner decides (nothing is cancelled by the customer directly).
--   4. CUSTOM CAKE   web_custom_request() (rule website_custom_cake_on): flavour, weight, message, date, slot and a reference photo
--                    in a PRIVATE bucket 'web-refs' (size and type limits on the bucket). Owner confirms; the cake spec is entered by staff.
--   5. PHOTOS        bucket 'web-public' (PUBLIC READ, 800 KB, jpeg/png/webp, owner-only write). An item photo appears on the web only
--                    after the owner approves its row (web_item_images.approved). The private `photos` bucket is not changed.
--   6. OWNER ADMIN   web_admin_* functions (owner only): item publishing (single and bulk by category), images, zones, pickup points,
--                    closures, board, drift report, holds report, web orders, cancel and custom-request decisions, go-live checklist.
--   7. GRANTS        anon: web_checkout_submit, web_order_track, web_order_cancel_request, web_custom_request only (plus phase490 reads).
--                    Every other new function is closed to anon and public.
-- ============================================================

-- ---------- extra columns / tables ----------
alter table public.online_orders add column if not exists web_code text check (web_code is null or web_code ~ '^[A-Z0-9]{6,12}$');
create unique index if not exists online_orders_web_code on public.online_orders (web_code) where web_code is not null;

create table if not exists public.web_rate_hits (
  id bigint generated always as identity primary key, key_hash text not null, at timestamptz not null default now()
);
create index if not exists web_rate_hits_k on public.web_rate_hits (key_hash, at desc);
alter table public.web_rate_hits enable row level security;
revoke all on public.web_rate_hits from public, anon, authenticated;

create table if not exists public.web_cancel_requests (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id),
  reason text not null check (char_length(btrim(reason)) between 1 and 300),
  state text not null default 'open' check (state in ('open', 'approved', 'declined')),
  decided_by uuid, decided_at timestamptz, decide_note text check (decide_note is null or char_length(decide_note) <= 300),
  created_at timestamptz not null default now()
);
create unique index if not exists web_cancel_one_open on public.web_cancel_requests (order_id) where state = 'open';
alter table public.web_cancel_requests enable row level security;
revoke all on public.web_cancel_requests from public, anon, authenticated;
grant select on public.web_cancel_requests to authenticated;
drop policy if exists web_cancel_owner_read on public.web_cancel_requests;
create policy web_cancel_owner_read on public.web_cancel_requests for select to authenticated using (public.is_owner());
drop trigger if exists web_cancel_no_delete on public.web_cancel_requests;
create trigger web_cancel_no_delete before delete on public.web_cancel_requests for each row execute function public.no_hard_delete();
drop trigger if exists audit_web_cancel on public.web_cancel_requests;
create trigger audit_web_cancel after insert or update on public.web_cancel_requests for each row execute function public.log_change('id');

create table if not exists public.web_custom_requests (
  id bigint generated always as identity primary key,
  code text not null unique check (code ~ '^[A-Z0-9]{6,12}$'),
  submission uuid not null unique,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  mobile text not null check (char_length(mobile) between 6 and 20),
  flavour text check (flavour is null or char_length(flavour) <= 80),
  weight_kg numeric check (weight_kg is null or (weight_kg > 0 and weight_kg <= 50)),
  message text check (message is null or char_length(message) <= 200),
  wanted_date date not null,
  slot text check (slot is null or char_length(slot) <= 40),
  ref_path text check (ref_path is null or char_length(ref_path) <= 300),
  state text not null default 'new' check (state in ('new', 'confirmed', 'declined')),
  decided_by uuid, decided_at timestamptz, decide_note text check (decide_note is null or char_length(decide_note) <= 300),
  created_at timestamptz not null default now()
);
alter table public.web_custom_requests enable row level security;
revoke all on public.web_custom_requests from public, anon, authenticated;
grant select on public.web_custom_requests to authenticated;
drop policy if exists web_custom_owner_read on public.web_custom_requests;
create policy web_custom_owner_read on public.web_custom_requests for select to authenticated using (public.is_owner());
drop trigger if exists web_custom_no_delete on public.web_custom_requests;
create trigger web_custom_no_delete before delete on public.web_custom_requests for each row execute function public.no_hard_delete();
drop trigger if exists audit_web_custom on public.web_custom_requests;
create trigger audit_web_custom after insert or update on public.web_custom_requests for each row execute function public.log_change('id');

-- ---------- storage buckets (guarded: only where the storage schema exists) ----------
do $$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice 'phase491: no storage schema here - photo buckets not created';
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('web-refs', 'web-refs', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = false, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('web-public', 'web-public', true, 819200, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do update set public = true, file_size_limit = 819200, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
  drop policy if exists web_refs_anon_insert on storage.objects;
  create policy web_refs_anon_insert on storage.objects for insert to anon, authenticated with check (bucket_id = 'web-refs');
  drop policy if exists web_refs_owner_read on storage.objects;
  create policy web_refs_owner_read on storage.objects for select to authenticated using (bucket_id = 'web-refs' and public.is_owner());
  drop policy if exists web_public_owner_write on storage.objects;
  create policy web_public_owner_write on storage.objects for insert to authenticated with check (bucket_id = 'web-public' and public.is_owner());
  drop policy if exists web_public_owner_delete on storage.objects;
  create policy web_public_owner_delete on storage.objects for delete to authenticated using (bucket_id = 'web-public' and public.is_owner());
end $$;

-- ---------- helpers ----------
create or replace function public._web_rate91(p_key text) returns boolean
language plpgsql security definer set search_path = public as $$
declare mx int := coalesce(public.rule_num('website_rate_max'), 0)::int; win int := greatest(1, coalesce(public.rule_num('website_rate_window_min'), 60)::int); c int;
begin
  if coalesce(p_key, '') = '' then return true; end if;     -- no device hash: the limit cannot apply (the edge caller should always send one)
  if mx > 0 then
    select count(*) into c from public.web_rate_hits where key_hash = p_key and at > now() - make_interval(mins => win);
    if c >= mx then return false; end if;
  end if;
  insert into public.web_rate_hits (key_hash) values (p_key);
  return true;
end $$;

-- release holds whose time is up (nothing is deleted; the row keeps its trail)
create or replace function public.web_holds_expire() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.web_stock_holds set state = 'released', closed_at = now(), close_note = 'expired'
   where state = 'held' and expires_at <= now();
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public._web_hold_sync91() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'cancelled' then
      update public.web_stock_holds set state = 'released', closed_at = now(), close_note = 'order cancelled' where order_id = new.id and state = 'held';
    elsif new.status = 'delivered' then
      update public.web_stock_holds set state = 'consumed', closed_at = now(), close_note = 'delivered' where order_id = new.id and state = 'held';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists online_orders_holds91 on public.online_orders;
create trigger online_orders_holds91 after update of status on public.online_orders for each row execute function public._web_hold_sync91();

create or replace function public._web_newcode91() returns text
language plpgsql volatile set search_path = public as $$
declare c text;
begin
  loop
    c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.online_orders where web_code = c) and not exists (select 1 from public.web_custom_requests where code = c);
  end loop;
  return c;
end $$;

-- ---------- 1. CHECKOUT (PUBLIC) ----------
create or replace function public.web_checkout_submit(p_submission uuid, p_name text, p_mobile text, p_mode text, p_zone int, p_address text, p_lines jsonb,
  p_note text, p_pay text, p_trx text, p_delivery_date date, p_pickup_loc int default null, p_utm jsonb default null, p_key_hash text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; today date := public._dhaka_today(); q jsonb; ex public.online_orders; o public.online_orders; mob text; chg numeric; sub numeric; tot numeric;
  lead int := coalesce(public.rule_num('website_lead_days'), 0)::int; ilead int; cut int := coalesce(public.rule_num('website_cutoff_hour'), 0)::int; n int; src text; cmp text;
  rec record; av text; need numeric; have numeric; bad text; cd text; ps public.web_pickup_points; reserve boolean := public.rule_on('website_reserve_on'); code text;
begin
  if not public.rule_on('website_on') then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if p_submission is null then return jsonb_build_object('ok', false, 'error', 'bad_input'); end if;
  perform pg_advisory_xact_lock(hashtextextended('x2web:' || p_submission::text, 0));
  select * into ex from public.online_orders where channel = 'website' and external_ref = p_submission::text;
  if found then
    return jsonb_build_object('ok', true, 'dup', true, 'order_no', ex.order_no, 'web_code', ex.web_code, 'status', ex.status, 'subtotal', ex.subtotal, 'delivery_charge', ex.delivery_charge, 'total', ex.subtotal - ex.discount + ex.delivery_charge);
  end if;
  if public.rule_on('website_captcha_on') then return jsonb_build_object('ok', false, 'error', 'captcha_required'); end if;
  if not public._web_rate91(p_key_hash) then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  if p_pickup_loc is not null and p_mode = 'pickup' then
    select * into ps from public.web_pickup_points where location_id = p_pickup_loc and public;
    if not found then return jsonb_build_object('ok', false, 'error', 'pickup_point_unavailable'); end if;
    loc := p_pickup_loc;
  else
    loc := coalesce(public.rule_num('website_location_id'), 0)::int;
  end if;
  if loc is null or loc = 0 then return jsonb_build_object('ok', false, 'error', 'orders_closed'); end if;
  if exists (select 1 from public.web_closures c where c.day = today and not c.reopened) then return jsonb_build_object('ok', false, 'error', 'closed_today'); end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 80 then return jsonb_build_object('ok', false, 'error', 'customer_name_required'); end if;
  mob := public.norm_mobile(p_mobile);
  if mob is null or char_length(mob) < 6 or char_length(mob) > 20 then return jsonb_build_object('ok', false, 'error', 'bad_mobile'); end if;
  if p_mode not in ('pickup', 'home') then return jsonb_build_object('ok', false, 'error', 'bad_mode'); end if;
  if p_mode = 'home' and nullif(btrim(p_address), '') is null then return jsonb_build_object('ok', false, 'error', 'address_required'); end if;
  if char_length(coalesce(p_address, '')) > 300 or char_length(coalesce(p_note, '')) > 300 then return jsonb_build_object('ok', false, 'error', 'too_long'); end if;
  if p_delivery_date is null then return jsonb_build_object('ok', false, 'error', 'date_required'); end if;
  if p_delivery_date > today + 365 or p_delivery_date < today then return jsonb_build_object('ok', false, 'error', 'bad_date'); end if;
  if p_pay not in ('cod', 'manual') then return jsonb_build_object('ok', false, 'error', 'bad_pay'); end if;
  if p_pay = 'cod' and not public.rule_on('website_pay_cod_on') then return jsonb_build_object('ok', false, 'error', 'pay_off'); end if;
  if p_pay = 'manual' and (not public.rule_on('website_pay_manual_on') or nullif(public.rule_txt('website_pay_mobile_number'), '') is null) then
    return jsonb_build_object('ok', false, 'error', 'pay_off');
  end if;
  if p_pay = 'manual' and (nullif(btrim(p_trx), '') is null or char_length(btrim(p_trx)) > 80) then return jsonb_build_object('ok', false, 'error', 'trx_required'); end if;

  -- price and availability from the server (never from the browser)
  q := public.web_quote(p_lines, p_zone, p_mode);
  if not coalesce((q->>'ok')::boolean, false) then return jsonb_build_object('ok', false, 'error', q->>'error') || (q - 'ok' - 'error' - 'lines'); end if;
  if jsonb_array_length(q->'problems') > 0 then return jsonb_build_object('ok', false, 'error', 'sold_out', 'problems', q->'problems'); end if;
  sub := (q->>'subtotal')::numeric; chg := (q->>'delivery_charge')::numeric; tot := (q->>'total')::numeric;
  select coalesce(max(p.lead_days), 0) into ilead from public.web_item_pub p where p.item_id in (select (x->>'item_id')::uuid from jsonb_array_elements(q->'lines') x);
  if p_delivery_date < today + greatest(lead, ilead) then return jsonb_build_object('ok', false, 'error', 'too_soon', 'earliest', today + greatest(lead, ilead)); end if;
  if p_delivery_date = today and cut > 0 and extract(hour from (now() at time zone 'Asia/Dhaka')) >= cut then return jsonb_build_object('ok', false, 'error', 'cutoff_passed'); end if;

  -- hard reservation (only when the owner switched it on): lock each tracked item at this branch, then check, then write
  if reserve then
    perform public.web_holds_expire();
    for rec in select distinct (x->>'item_id')::uuid as iid from jsonb_array_elements(q->'lines') x order by 1 loop
      perform pg_advisory_xact_lock(hashtextextended('x2stk:' || rec.iid::text || ':' || loc::text, 0));
    end loop;
    for rec in select (x->>'item_id')::uuid as iid, sum((x->>'qty')::numeric) as qty from jsonb_array_elements(q->'lines') x group by 1 loop
      if (select i.tracked from public.items i where i.id = rec.iid) then
        select coalesce(sb.qty, 0) into have from public.stock_balance sb where sb.item_id = rec.iid and sb.location_id = loc;
        select coalesce(sum(h.qty), 0) into need from public.web_stock_holds h where h.item_id = rec.iid and h.location_id = loc and h.state = 'held' and h.expires_at > now();
        if coalesce(have, 0) - need < rec.qty then return jsonb_build_object('ok', false, 'error', 'sold_out', 'problems', jsonb_build_array(jsonb_build_object('item_id', rec.iid, 'availability', 'sold_out'))); end if;
      end if;
    end loop;
  end if;

  -- writes
  insert into public.serials (form_code, location_id, last) values ('ORD', loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  src := left(nullif(concat_ws('/', nullif(btrim(p_utm->>'source'), ''), nullif(btrim(p_utm->>'medium'), ''), nullif(btrim(p_utm->>'campaign'), '')), ''), 80);
  code := public._web_newcode91();
  insert into public.online_orders (order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_date,
      delivery_charge, advance, note, status, external_ref, source, pay_mode, pay_ref, created_by, created_staff, web_code, is_draft)
    values (n, loc, 'website', left(btrim(p_name), 80), mob, case when p_mode = 'home' then nullif(btrim(p_address), '') end, q->'lines', sub, 0, p_mode, p_delivery_date,
      chg, 0, nullif(btrim(p_note), ''), 'new', p_submission::text, src, case when p_pay = 'cod' then 'cod' else 'mobile' end,
      case when p_pay = 'manual' then left(btrim(p_trx), 80) end, null, 'web', code, false)
    returning * into o;
  insert into public.online_order_events (order_id, from_status, to_status, note, by_user, by_staff) values (o.id, null, 'new', 'web checkout', null, 'web');
  cmp := left(regexp_replace(coalesce(p_utm->>'campaign', ''), '[^A-Za-z0-9_-]', '', 'g'), 40);
  if cmp <> '' then
    insert into public.mkt_order_tags (order_id, campaign_code, location_id, tagged_staff) values (o.id, cmp, loc, 'web') on conflict (order_id) do nothing;
  end if;
  if reserve then
    insert into public.web_stock_holds (submission, order_id, item_id, location_id, qty, expires_at)
      select p_submission, o.id, (x->>'item_id')::uuid, loc, (x->>'qty')::numeric, now() + make_interval(mins => coalesce(public.rule_num('website_reserve_minutes'), 30)::int)
        from jsonb_array_elements(q->'lines') x
       where (select i.tracked from public.items i where i.id = (x->>'item_id')::uuid)
    on conflict (submission, item_id) do nothing;
  end if;
  return jsonb_build_object('ok', true, 'dup', false, 'order_no', o.order_no, 'web_code', o.web_code, 'status', o.status, 'subtotal', sub, 'delivery_charge', chg, 'total', tot,
    'held', reserve, 'pay', p_pay);
end $$;

-- ---------- 3. TRACKING + CANCEL REQUEST (PUBLIC) ----------
create or replace function public.web_order_track(p_code text, p_mobile text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders; mob text := public.norm_mobile(p_mobile);
begin
  if not public.rule_on('website_on') then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  select * into o from public.online_orders where web_code = upper(btrim(coalesce(p_code, ''))) and channel = 'website';
  if not found or mob is null or o.customer_mobile <> mob then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'order_no', o.order_no, 'status', o.status, 'delivery_mode', o.delivery_mode, 'delivery_date', o.delivery_date,
    'subtotal', o.subtotal, 'delivery_charge', o.delivery_charge, 'total', o.subtotal - o.discount + o.delivery_charge, 'pay_mode', o.pay_mode,
    'cancel_requested', exists (select 1 from public.web_cancel_requests r where r.order_id = o.id and r.state = 'open'),
    'can_request_cancel', o.status in ('new', 'confirmed') and not exists (select 1 from public.web_cancel_requests r where r.order_id = o.id and r.state = 'open'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('status', e.to_status, 'at', e.at) order by e.id) from public.online_order_events e where e.order_id = o.id and e.to_status <> 'edited'), '[]'::jsonb));
end $$;

create or replace function public.web_order_cancel_request(p_code text, p_mobile text, p_reason text, p_key_hash text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; mob text := public.norm_mobile(p_mobile); rid bigint;
begin
  if not public.rule_on('website_on') then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if not public._web_rate91(p_key_hash) then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  select * into o from public.online_orders where web_code = upper(btrim(coalesce(p_code, ''))) and channel = 'website';
  if not found or mob is null or o.customer_mobile <> mob then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.status not in ('new', 'confirmed') then return jsonb_build_object('ok', false, 'error', 'too_late', 'status', o.status); end if;
  if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) > 300 then return jsonb_build_object('ok', false, 'error', 'reason_required'); end if;
  insert into public.web_cancel_requests (order_id, reason) values (o.id, btrim(p_reason))
    on conflict (order_id) where state = 'open' do nothing returning id into rid;
  return jsonb_build_object('ok', true, 'requested', rid is not null, 'note', 'The shop will confirm the cancellation.');
end $$;

-- ---------- 4. CUSTOM CAKE REQUEST (PUBLIC) ----------
create or replace function public.web_custom_request(p_submission uuid, p_name text, p_mobile text, p_flavour text, p_weight numeric, p_message text,
  p_wanted date, p_slot text, p_ref_path text, p_key_hash text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mob text := public.norm_mobile(p_mobile); ex public.web_custom_requests; r public.web_custom_requests; ok_ref boolean := true; today date := public._dhaka_today();
begin
  if not (public.rule_on('website_on') and public.rule_on('website_custom_cake_on')) then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if p_submission is null then return jsonb_build_object('ok', false, 'error', 'bad_input'); end if;
  select * into ex from public.web_custom_requests where submission = p_submission;
  if found then return jsonb_build_object('ok', true, 'dup', true, 'code', ex.code, 'state', ex.state); end if;
  if not public._web_rate91(p_key_hash) then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 80 then return jsonb_build_object('ok', false, 'error', 'customer_name_required'); end if;
  if mob is null or char_length(mob) < 6 then return jsonb_build_object('ok', false, 'error', 'bad_mobile'); end if;
  if p_weight is not null and (p_weight <= 0 or p_weight > 50) then return jsonb_build_object('ok', false, 'error', 'bad_weight'); end if;
  if p_wanted is null or p_wanted < today + 1 or p_wanted > today + 365 then return jsonb_build_object('ok', false, 'error', 'bad_date'); end if;
  if char_length(coalesce(p_message, '')) > 200 or char_length(coalesce(p_flavour, '')) > 80 or char_length(coalesce(p_slot, '')) > 40 then return jsonb_build_object('ok', false, 'error', 'too_long'); end if;
  -- the photo must be an object that really sits in the private 'web-refs' bucket (the bucket itself limits size and type)
  if nullif(p_ref_path, '') is not null and to_regclass('storage.objects') is not null then
    execute 'select exists (select 1 from storage.objects where bucket_id = $1 and name = $2)' into ok_ref using 'web-refs', p_ref_path;
    if not ok_ref then return jsonb_build_object('ok', false, 'error', 'photo_not_found'); end if;
  end if;
  insert into public.web_custom_requests (code, submission, name, mobile, flavour, weight_kg, message, wanted_date, slot, ref_path)
    values (public._web_newcode91(), p_submission, btrim(p_name), mob, nullif(btrim(p_flavour), ''), p_weight, nullif(btrim(p_message), ''), p_wanted,
      nullif(btrim(p_slot), ''), nullif(btrim(p_ref_path), ''))
    returning * into r;
  return jsonb_build_object('ok', true, 'dup', false, 'code', r.code, 'state', r.state);
end $$;

-- ---------- 6. OWNER ADMIN ----------
create or replace function public.web_admin_item_save(p_item uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; cur public.web_item_pub; d text[]; pub boolean := coalesce((p->>'published')::boolean, false); av text := coalesce(p->>'avail_mode', 'auto');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into it from public.items where id = p_item;
  if not found then raise exception 'item_not_found'; end if;
  if av not in ('auto', 'preorder', 'sold_out') then raise exception 'bad_avail'; end if;
  d := coalesce(array(select jsonb_array_elements_text(coalesce(p->'diet', '[]'::jsonb))), '{}');
  if not (d <@ array['halal', 'eggless', 'sugar_free', 'vegan']::text[]) then raise exception 'bad_diet'; end if;
  if char_length(coalesce(p->>'desc_bn', '')) > 1000 or char_length(coalesce(p->>'desc_en', '')) > 1000 then raise exception 'too_long'; end if;
  if pub and not (it.is_active and it.sellable and not it.hidden and it.retired_at is null and it.sell_price is not null) then
    raise exception 'item_not_sellable: an item must be active, sellable, not hidden, not retired and priced to show on the web';
  end if;
  select * into cur from public.web_item_pub where item_id = p_item;
  insert into public.web_item_pub (item_id, published, name_bn, name_en, desc_bn, desc_en, category_pub, category_sort, sort, avail_mode, lead_days, allergens, diet,
      price_snapshot, published_at, published_by, updated_at, updated_by)
    values (p_item, pub, nullif(btrim(p->>'name_bn'), ''), nullif(btrim(p->>'name_en'), ''), nullif(btrim(p->>'desc_bn'), ''), nullif(btrim(p->>'desc_en'), ''),
      nullif(btrim(p->>'category_pub'), ''), coalesce((p->>'category_sort')::int, 0), coalesce((p->>'sort')::int, 0), av, coalesce((p->>'lead_days')::int, 0),
      nullif(btrim(p->>'allergens'), ''), d, it.sell_price, case when pub then now() end, case when pub then auth.uid() end, now(), auth.uid())
    on conflict (item_id) do update set published = excluded.published, name_bn = excluded.name_bn, name_en = excluded.name_en, desc_bn = excluded.desc_bn,
      desc_en = excluded.desc_en, category_pub = excluded.category_pub, category_sort = excluded.category_sort, sort = excluded.sort, avail_mode = excluded.avail_mode,
      lead_days = excluded.lead_days, allergens = excluded.allergens, diet = excluded.diet,
      price_snapshot = case when excluded.published then it.sell_price else web_item_pub.price_snapshot end,
      published_at = case when excluded.published and not coalesce(web_item_pub.published, false) then now() else web_item_pub.published_at end,
      published_by = case when excluded.published and not coalesce(web_item_pub.published, false) then auth.uid() else web_item_pub.published_by end,
      updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('item_id', p_item, 'published', pub, 'avail_mode', av);
end $$;

-- bulk publish / unpublish every active sellable item of one ERP category (the owner picks the category; nothing is published by default)
create or replace function public.web_admin_publish_bulk(p_category text, p_published boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; n int := 0;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_category), '') is null then raise exception 'category_required'; end if;
  for it in select * from public.items where category = p_category and is_active and sellable and not hidden and retired_at is null and sell_price is not null loop
    perform public.web_admin_item_save(it.id, jsonb_build_object('published', coalesce(p_published, false),
      'category_pub', coalesce((select p.category_pub from public.web_item_pub p where p.item_id = it.id), it.category_bn, it.category)));
    n := n + 1;
  end loop;
  return jsonb_build_object('category', p_category, 'published', coalesce(p_published, false), 'items', n);
end $$;

create or replace function public.web_admin_image_add(p_item uuid, p_path text, p_mime text, p_bytes int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.web_item_images;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_path is null or p_path not like 'items/' || p_item::text || '/%' or char_length(p_path) > 300 then raise exception 'bad_path: the photo must sit under items/<item id>/'; end if;
  insert into public.web_item_images (item_id, storage_path, mime, bytes, created_by) values (p_item, p_path, p_mime, p_bytes, auth.uid())
    on conflict (item_id, storage_path) do nothing returning * into r;
  if r.id is null then select * into r from public.web_item_images where item_id = p_item and storage_path = p_path; end if;
  return jsonb_build_object('id', r.id, 'approved', r.approved);
end $$;

create or replace function public.web_admin_image_approve(p_id bigint, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.web_item_images;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.web_item_images where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  update public.web_item_images set approved = coalesce(p_approve, false), approved_by = case when coalesce(p_approve, false) then auth.uid() end,
    approved_at = case when coalesce(p_approve, false) then now() end where id = p_id;
  return jsonb_build_object('id', p_id, 'approved', coalesce(p_approve, false));
end $$;

create or replace function public.web_admin_zone_save(p_id int, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.web_zones;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_id is null then
    insert into public.web_zones (name_bn, name_en, charge, min_order, active, sort, updated_by)
      values (btrim(p->>'name_bn'), nullif(btrim(p->>'name_en'), ''), (p->>'charge')::numeric, coalesce((p->>'min_order')::numeric, 0), coalesce((p->>'active')::boolean, true),
        coalesce((p->>'sort')::int, 0), auth.uid()) returning * into r;
  else
    update public.web_zones set name_bn = coalesce(nullif(btrim(p->>'name_bn'), ''), name_bn), name_en = nullif(btrim(p->>'name_en'), ''),
      charge = coalesce((p->>'charge')::numeric, charge), min_order = coalesce((p->>'min_order')::numeric, min_order),
      active = coalesce((p->>'active')::boolean, active), sort = coalesce((p->>'sort')::int, sort), updated_at = now(), updated_by = auth.uid()
      where id = p_id returning * into r;
    if r.id is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'active', r.active, 'charge', r.charge);
end $$;

create or replace function public.web_admin_pickup_save(p_loc int, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'location_not_found'; end if;
  insert into public.web_pickup_points (location_id, public, hours_bn, hours_en, address_public, updated_by) values (p_loc, coalesce((p->>'public')::boolean, false),
      nullif(btrim(p->>'hours_bn'), ''), nullif(btrim(p->>'hours_en'), ''), nullif(btrim(p->>'address'), ''), auth.uid())
    on conflict (location_id) do update set public = excluded.public, hours_bn = excluded.hours_bn, hours_en = excluded.hours_en, address_public = excluded.address_public,
      updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('location_id', p_loc, 'public', coalesce((p->>'public')::boolean, false));
end $$;

create or replace function public.web_admin_closure_save(p_day date, p_bn text, p_en text, p_reopen boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_day is null then raise exception 'bad_date'; end if;
  insert into public.web_closures (day, note_bn, note_en, reopened, created_by) values (p_day, nullif(btrim(p_bn), ''), nullif(btrim(p_en), ''), coalesce(p_reopen, false), auth.uid())
    on conflict (day) do update set note_bn = coalesce(excluded.note_bn, web_closures.note_bn), note_en = coalesce(excluded.note_en, web_closures.note_en), reopened = excluded.reopened;
  return jsonb_build_object('day', p_day, 'closed', not coalesce(p_reopen, false));
end $$;

-- drift between what is published and what the ERP says now (read only)
create or replace function public.web_admin_drift() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int := coalesce(public.rule_num('website_location_id'), 0)::int; price_rows jsonb; off_rows jsonb; hold_rows jsonb; cat_rows jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', p.item_id, 'published_price', p.price_snapshot, 'erp_price', i.sell_price) order by i.name_bn), '[]') into price_rows
    from public.web_item_pub p join public.items i on i.id = p.item_id where p.published and p.price_snapshot is distinct from i.sell_price;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', p.item_id, 'why', case when not i.is_active then 'inactive' when not i.sellable then 'not_sellable'
      when i.hidden then 'hidden' when i.retired_at is not null then 'retired' when i.sell_price is null then 'no_price' end) order by i.name_bn), '[]') into off_rows
    from public.web_item_pub p join public.items i on i.id = p.item_id
    where p.published and (not i.is_active or not i.sellable or i.hidden or i.retired_at is not null or i.sell_price is null);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', h.item_id, 'held', h.held, 'in_stock', coalesce(sb.qty, 0)) order by h.item_id), '[]') into hold_rows
    from (select item_id, sum(qty) as held from public.web_stock_holds where state = 'held' and expires_at > now() and location_id = loc group by item_id) h
    left join public.stock_balance sb on sb.item_id = h.item_id and sb.location_id = loc
    where h.held > coalesce(sb.qty, 0);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', p.item_id) order by p.item_id), '[]') into cat_rows from public.web_item_pub p where p.published and p.category_pub is null;
  return jsonb_build_object('price_changed', price_rows, 'not_sellable', off_rows, 'holds_over_stock', hold_rows, 'no_category', cat_rows,
    'counts', jsonb_build_object('price_changed', jsonb_array_length(price_rows), 'not_sellable', jsonb_array_length(off_rows),
      'holds_over_stock', jsonb_array_length(hold_rows), 'no_category', jsonb_array_length(cat_rows)),
    'note', 'Read only. Price drift is fixed by publishing again (the snapshot is refreshed) or by changing the ERP price back. Nothing is pushed to any shop.');
end $$;

create or replace function public.web_admin_holds_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'held_now', (select count(*) from public.web_stock_holds where state = 'held' and expires_at > now()),
    'held_qty', coalesce((select sum(qty) from public.web_stock_holds where state = 'held' and expires_at > now()), 0),
    'expired_not_closed', (select count(*) from public.web_stock_holds where state = 'held' and expires_at <= now()),
    'released', (select count(*) from public.web_stock_holds where state = 'released'),
    'consumed', (select count(*) from public.web_stock_holds where state = 'consumed'),
    'reserve_on', public.rule_on('website_reserve_on'));
end $$;

create or replace function public.web_admin_board() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('website_on'), 'orders_open', coalesce(public.rule_num('website_location_id'), 0) > 0,
    'published_items', (select count(*) from public.web_item_pub where published),
    'approved_photos', (select count(*) from public.web_item_images where approved),
    'web_orders_today', (select count(*) from public.online_orders where channel = 'website' and (created_at at time zone 'Asia/Dhaka')::date = public._dhaka_today()),
    'web_orders_new', (select count(*) from public.online_orders where channel = 'website' and status = 'new'),
    'cancel_requests_open', (select count(*) from public.web_cancel_requests where state = 'open'),
    'custom_requests_new', (select count(*) from public.web_custom_requests where state = 'new'),
    'holds_held', (select count(*) from public.web_stock_holds where state = 'held' and expires_at > now()),
    'reserve_on', public.rule_on('website_reserve_on'));
end $$;

create or replace function public.web_admin_web_orders(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.order_no, o.web_code, o.location_id, o.customer_name, o.customer_mobile, o.delivery_mode, o.delivery_date, o.subtotal, o.delivery_charge,
           o.pay_mode, o.pay_ref, o.status, o.source, o.sale_id, o.created_at
      from public.online_orders o where o.channel = 'website' order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.web_admin_cancel_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'order_no', o.order_no, 'web_code', o.web_code, 'reason', r.reason, 'status', o.status, 'created_at', r.created_at)
    order by r.created_at) from public.web_cancel_requests r join public.online_orders o on o.id = r.order_id where r.state = 'open'), '[]'::jsonb);
end $$;

create or replace function public.web_admin_cancel_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.web_cancel_requests; o public.online_orders; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.web_cancel_requests where id = p_id for update;
  if not found or r.state <> 'open' then raise exception 'not_open'; end if;
  if coalesce(p_approve, false) then
    select * into o from public.online_orders where id = r.order_id;
    res := public.online_order_cancel(o.id, r.reason, 'none');   -- the existing cancel rules (status, reason, advance) apply
  end if;
  update public.web_cancel_requests set state = case when coalesce(p_approve, false) then 'approved' else 'declined' end, decided_by = auth.uid(), decided_at = now(),
    decide_note = left(nullif(btrim(p_note), ''), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'state', case when coalesce(p_approve, false) then 'approved' else 'declined' end, 'cancel', res);
end $$;

create or replace function public.web_admin_custom_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select id, code, name, mobile, flavour, weight_kg, message, wanted_date, slot, ref_path, state, created_at from public.web_custom_requests order by created_at desc limit 200) z), '[]'::jsonb);
end $$;

create or replace function public.web_admin_custom_decide(p_id bigint, p_state text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_state not in ('confirmed', 'declined') then raise exception 'bad_state'; end if;
  update public.web_custom_requests set state = p_state, decided_by = auth.uid(), decided_at = now(), decide_note = left(nullif(btrim(p_note), ''), 300)
    where id = p_id and state = 'new';
  if not found then raise exception 'not_open'; end if;
  return jsonb_build_object('id', p_id, 'state', p_state);
end $$;

-- go-live checklist: tells honestly what is missing. No secrets are read or shown.
create or replace function public.web_admin_go_live() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'; loc int := coalesce(public.rule_num('website_location_id'), 0)::int; anon_ok boolean;
  function_ok boolean; ok boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  anon_ok := has_function_privilege('anon', 'public.web_catalog_v2(text)', 'execute') and has_function_privilege('anon', 'public.web_checkout_submit(uuid,text,text,text,int,text,jsonb,text,text,text,date,int,jsonb,text)', 'execute');
  function_ok := not has_function_privilege('anon', 'public.web_admin_board()', 'execute') and not has_function_privilege('anon', 'public.web_admin_drift()', 'execute');
  items := items || jsonb_build_object('key', 'site_on', 'required', true, 'ok', public.rule_on('website_on'), 'bn', 'ওয়েবসাইট চালু', 'en', 'Website switched on', 'how_bn', 'সেটিংসে ওয়েবসাইট চালু করুন', 'how_en', 'Turn the website switch on in settings');
  items := items || jsonb_build_object('key', 'branch', 'required', true, 'ok', loc > 0 and exists (select 1 from public.locations where id = loc and is_active),
    'bn', 'ওয়েব অর্ডারের শাখা', 'en', 'Branch for web orders', 'how_bn', 'ওয়েব অর্ডারের শাখা বেছে নিন', 'how_en', 'Choose the branch that receives web orders');
  items := items || jsonb_build_object('key', 'staff_orders', 'required', true, 'ok', public.rule_on('online_orders_on'),
    'bn', 'অর্ডার ব্যবস্থাপনা (online order) চালু', 'en', 'Order screens switched on', 'how_bn', 'অনলাইন অর্ডার চ্যানেল চালু করুন', 'how_en', 'Switch on the online order channel so staff can handle orders');
  items := items || jsonb_build_object('key', 'names', 'required', true, 'ok', nullif(public.rule_txt('website_brand_bn'), '') is not null and nullif(public.rule_txt('website_brand_en'), '') is not null,
    'bn', 'দোকানের নাম (বাংলা ও ইংরেজি)', 'en', 'Shop name in Bangla and English', 'how_bn', 'সেটিংসে নাম লিখুন', 'how_en', 'Enter the name in settings');
  items := items || jsonb_build_object('key', 'published', 'required', true, 'ok', exists (select 1 from public.web_item_pub where published),
    'bn', 'অন্তত একটি আইটেম পাবলিশ', 'en', 'At least one item published', 'how_bn', 'ক্যাটালগে আইটেম পাবলিশ করুন', 'how_en', 'Publish items from the Website screen');
  items := items || jsonb_build_object('key', 'delivery', 'required', true, 'ok', exists (select 1 from public.web_pickup_points where public) or exists (select 1 from public.web_zones where active),
    'bn', 'পিকআপ বিন্দু বা ডেলিভারি এলাকা', 'en', 'A pickup point or a delivery zone', 'how_bn', 'পিকআপ শাখা বা ডেলিভারি এলাকা যোগ করুন', 'how_en', 'Make a branch a public pickup point or add a zone');
  items := items || jsonb_build_object('key', 'payment', 'required', true, 'ok', public.rule_on('website_pay_cod_on') or (public.rule_on('website_pay_manual_on') and nullif(public.rule_txt('website_pay_mobile_number'), '') is not null),
    'bn', 'অন্তত একটি পেমেন্ট পদ্ধতি', 'en', 'At least one payment method', 'how_bn', 'COD অথবা bKash/Nagad চালু করুন', 'how_en', 'Switch on COD, or bKash/Nagad with a number');
  items := items || jsonb_build_object('key', 'anon_grants', 'required', true, 'ok', anon_ok and function_ok,
    'bn', 'পাবলিক ও অ্যাডমিন অনুমতি ঠিক', 'en', 'Public / admin permissions are right', 'how_bn', 'মাইগ্রেশন আবার চালান (phase 490-491)', 'how_en', 'Re-paste phases 490-491 and run the permission test');
  items := items || jsonb_build_object('key', 'domain', 'required', false, 'ok', nullif(public.rule_txt('website_public_url'), '') is not null,
    'bn', 'ডোমেইন/হোস্টিং ঠিকানা', 'en', 'Domain / hosting address', 'how_bn', 'ডোমেইন বা হোস্টিং কিনে ঠিকানা এখানে লিখুন; এর আগে শুধু লোকাল পরীক্ষা', 'how_en', 'Buy a domain or hosting, deploy site/ and enter its address here. Until then: local test only');
  items := items || jsonb_build_object('key', 'https', 'required', false, 'ok', nullif(public.rule_txt('website_public_url'), '') is not null and public.rule_txt('website_public_url') like 'https://%',
    'bn', 'HTTPS ঠিকানা', 'en', 'HTTPS address', 'how_bn', 'ডোমেইনের ঠিকানা https:// দিয়ে শুরু হতে হবে', 'how_en', 'The address must start with https://');
  items := items || jsonb_build_object('key', 'whatsapp', 'required', false, 'ok', nullif(public.rule_txt('website_whatsapp'), '') is not null,
    'bn', 'হোয়াটসঅ্যাপ নম্বর', 'en', 'WhatsApp number', 'how_bn', 'দেশের কোড সহ নম্বর লিখুন', 'how_en', 'Enter the number with country code');
  items := items || jsonb_build_object('key', 'test_order', 'required', true, 'ok', exists (select 1 from public.online_orders where channel = 'website'),
    'bn', 'একটি পরীক্ষা অর্ডার সফলভাবে এসেছে', 'en', 'One test order arrived', 'how_bn', 'লোকাল ঠিকানা থেকে একটি পরীক্ষা অর্ডার দিন এবং বাতিল করুন', 'how_en', 'Place a test order from the local site and cancel it');
  items := items || jsonb_build_object('key', 'drift', 'required', false, 'ok', (public.web_admin_drift()->'counts'->>'price_changed')::int = 0 and (public.web_admin_drift()->'counts'->>'not_sellable')::int = 0,
    'bn', 'পাবলিশড আইটেম ও ERP-র মিল', 'en', 'Published items match the ERP', 'how_bn', 'Drift রিপোর্ট দেখে মেলান', 'how_en', 'Check the drift report and fix the items it lists');
  ok := not exists (select 1 from jsonb_array_elements(items) x where (x->>'required')::boolean and not (x->>'ok')::boolean);
  return jsonb_build_object('ready', ok, 'items', items, 'note', 'Required items must be OK before the public address is shared. Optional items can wait.');
end $$;

-- ---------- grants ----------
-- every new function: closed to public and anon first, then opened only where a role needs it
do $$
declare f text;
begin
  for f in select unnest(array[
      'public._web_rate91(text)', 'public.web_holds_expire()', 'public._web_hold_sync91()', 'public._web_newcode91()',
      'public.web_checkout_submit(uuid,text,text,text,int,text,jsonb,text,text,text,date,int,jsonb,text)',
      'public.web_order_track(text,text)', 'public.web_order_cancel_request(text,text,text,text)', 'public.web_custom_request(uuid,text,text,text,numeric,text,date,text,text,text)',
      'public.web_admin_item_save(uuid,jsonb)', 'public.web_admin_publish_bulk(text,boolean)', 'public.web_admin_image_add(uuid,text,text,int)',
      'public.web_admin_image_approve(bigint,boolean)', 'public.web_admin_zone_save(int,jsonb)', 'public.web_admin_pickup_save(int,jsonb)',
      'public.web_admin_closure_save(date,text,text,boolean)', 'public.web_admin_drift()', 'public.web_admin_holds_report()', 'public.web_admin_board()',
      'public.web_admin_web_orders(int)', 'public.web_admin_cancel_list()', 'public.web_admin_cancel_decide(bigint,boolean,text)', 'public.web_admin_custom_list()',
      'public.web_admin_custom_decide(bigint,text,text)', 'public.web_admin_go_live()']) loop
    execute format('revoke all on function %s from public, anon', f);
  end loop;
  -- the public (anon) entry points of this phase
  grant execute on function public.web_checkout_submit(uuid,text,text,text,int,text,jsonb,text,text,text,date,int,jsonb,text) to anon, authenticated;
  grant execute on function public.web_order_track(text,text) to anon, authenticated;
  grant execute on function public.web_order_cancel_request(text,text,text,text) to anon, authenticated;
  grant execute on function public.web_custom_request(uuid,text,text,text,numeric,text,date,text,text,text) to anon, authenticated;
  -- owner-only admin (each function also checks is_owner() itself)
  grant execute on function public.web_admin_item_save(uuid,jsonb), public.web_admin_publish_bulk(text,boolean), public.web_admin_image_add(uuid,text,text,int),
    public.web_admin_image_approve(bigint,boolean), public.web_admin_zone_save(int,jsonb), public.web_admin_pickup_save(int,jsonb),
    public.web_admin_closure_save(date,text,text,boolean), public.web_admin_drift(), public.web_admin_holds_report(), public.web_admin_board(),
    public.web_admin_web_orders(int), public.web_admin_cancel_list(), public.web_admin_cancel_decide(bigint,boolean,text), public.web_admin_custom_list(),
    public.web_admin_custom_decide(bigint,text,text), public.web_admin_go_live(), public.web_holds_expire() to authenticated;
end $$;

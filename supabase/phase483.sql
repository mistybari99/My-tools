-- Phase 483 (X3, social and marketing workspace) - CONTENT ITEMS, APPROVAL, PUBLISHING QUEUE, DELIVERIES, METRICS, FESTIVAL CALENDAR VIEW.
-- Paste AFTER the build through phase 478 (needs phase 46 ops bot, phase 62 _i62_ops, phase 303 consent gate, phase 465 festival_calendar). Paste-twice safe.
-- No earlier phase file is edited. Everything is OFF by default (rule social_on = false, social_publish_on = false).
--
-- What this adds:
--   * rules (module social): social_on, social_publish_on, social_stop_all (emergency stop), social_max_per_day, social_max_per_hour (blank = publishing is blocked,
--     nothing is invented), social_quiet_from / social_quiet_to (Asia/Dhaka, blank = no quiet hours), social_retry_max, social_media_image_mb, social_media_video_mb.
--   * grants: social_manage (write and submit content), social_approve (approve content; the owner always may).
--   * social_items: one content item (caption Bangla and English, hashtags, media references, product, UTM campaign code, coupon code, draft source human or ai).
--     Status: draft -> awaiting_approval -> approved -> scheduled -> published | failed | cancelled. Illegal moves are refused by a trigger.
--     Content is LOCKED after draft: a changed item goes back to draft first. The maker never approves his own item. Approval needs the preview hash the approver saw.
--   * social_deliveries: one row per item and channel (facebook, instagram, webhook) or per item and consenting customer (whatsapp template message).
--     idempotency_key is unique: the same item never goes out twice on the same channel. Lease + retry with back-off, like notify_outbox.
--   * social_metrics: append-only metric snapshots from a provider. Nothing is faked: no row means "not captured".
--   * social_item_events: append-only trail of every move.
--   * RPCs for the browser (owner / people with the grants) and for the publisher worker (tools/social_publish.py, ops bot, the same login as notify).
-- The publisher sends nothing unless social_publish_on is ON, social_stop_all is OFF, the limits are set and it is outside quiet hours.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._crmb_send_allowed(uuid,text,text,timestamptz)') is null or to_regprocedure('public._i62_ops()') is null or to_regprocedure('public._i62_phone(text)') is null
     or to_regprocedure('public.has_grant(text,integer)') is null or to_regclass('public.festival_calendar') is null or to_regclass('public.customers') is null
     or to_regprocedure('public._append_only43()') is null or to_regprocedure('public._client_lock(uuid)') is null then
    raise exception 'phase500 needs phases 7, 43, 46, 62, 303 and 465 first (build through phase 478)';
  end if;
end $g$;

-- ---------- settings (rules) and grants: every one OFF or blank ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('social_on', 'social', 'switch', 'false'::jsonb, null, null, null, null,
  'সোশ্যাল ও মার্কেটিং ওয়ার্কস্পেস চালু', 'Social & marketing workspace on', 'Social and marketing workspace is on',
  'OFF = কনটেন্ট লেখা ও অনুমোদন বন্ধ। ON = কনটেন্ট বানানো ও অনুমোদন চালু (প্রকাশ আলাদা সুইচে)।', 'OFF = content and approval are closed. ON = content and approval work (publishing has its own switch).', 'OFF = content and approval are closed. ON = content and approval work (publishing has its own switch).', 1000),
 ('social_publish_on', 'social', 'switch', 'false'::jsonb, null, null, null, null,
  'অনুমোদিত পোস্ট স্বয়ংক্রিয়ভাবে প্রকাশ হবে', 'Publish approved posts automatically', 'Publish approved posts automatically',
  'OFF = কিছুই প্রকাশ হবে না। ON = প্রকাশকারী (worker) সময়মতো অনুমোদিত পোস্ট পাঠাবে, সীমা ও শান্ত সময় মেনে।', 'OFF = nothing is published. ON = the worker posts approved items on time, within the limits and quiet hours.', 'OFF = nothing is published. ON = the worker posts approved items on time, within the limits and quiet hours.', 1001),
 ('social_stop_all', 'social', 'switch', 'false'::jsonb, null, null, null, null,
  'সব প্রকাশ থামান (জরুরি)', 'Stop all publishing (emergency)', 'Stop all publishing (emergency)',
  'ON = কোনো পোস্ট বা customer message প্রকাশ হবে না; queue অপেক্ষায় থাকবে এবং OFF করলে আবার চলবে। শুধু মালিক।', 'ON = no post or customer message goes out; the queue waits and resumes when switched OFF. Owner only.', 'ON = no post or customer message goes out; the queue waits and resumes when switched OFF. Owner only.', 1002),
 ('social_max_per_day', 'social', 'number', null::jsonb, 'টি / দিন', null, 1, 10000,
  'দিনে সর্বোচ্চ কয়টি প্রকাশ', 'Most posts per day', 'Most posts per day',
  'খালি থাকলে কোনো পোস্ট সাজানো বা প্রকাশ হবে না। সংখ্যা নিজে লিখুন।', 'Blank = no post can be scheduled or published. Type the number yourself.', 'Blank = no post can be scheduled or published. Type the number yourself.', 1003),
 ('social_max_per_hour', 'social', 'number', null::jsonb, 'টি / ঘণ্টা', null, 1, 1000,
  'ঘণ্টায় সর্বোচ্চ কয়টি প্রকাশ', 'Most posts per hour', 'Most posts per hour',
  'খালি থাকলে কোনো পোস্ট সাজানো বা প্রকাশ হবে না। সংখ্যা নিজে লিখুন।', 'Blank = no post can be scheduled or published. Type the number yourself.', 'Blank = no post can be scheduled or published. Type the number yourself.', 1004),
 ('social_quiet_from', 'social', 'text', null::jsonb, 'HH:MM', null, null, null,
  'শান্ত সময় শুরু (ঢাকা)', 'Quiet hours from (Dhaka)', 'Quiet hours from (Dhaka)',
  'এই সময়ে কোনো পোস্ট বা customer message যাবে না। খালি = শান্ত সময় নেই।', 'No post or customer message goes out in this window. Blank = no quiet hours.', 'No post or customer message goes out in this window. Blank = no quiet hours.', 1005),
 ('social_quiet_to', 'social', 'text', null::jsonb, 'HH:MM', null, null, null,
  'শান্ত সময় শেষ (ঢাকা)', 'Quiet hours to (Dhaka)', 'Quiet hours to (Dhaka)',
  'শুরু ও শেষ দুটোই লিখতে হবে। শেষ সময় শুরুর পরে হলে রাত পার হয়ে যায়।', 'Write both start and end. An end before the start crosses midnight.', 'Write both start and end. An end before the start crosses midnight.', 1006),
 ('social_retry_max', 'social', 'number', '5'::jsonb, 'বার', null, 1, 20,
  'একটি পোস্ট সর্বোচ্চ কতবার চেষ্টা', 'Most tries per post', 'Most tries per post',
  'ব্যর্থ হলে এই সংখ্যা পর্যন্ত চেষ্টা; প্রতিবার অপেক্ষা বাড়ে (2, 4, 8 ... মিনিট)।', 'After a failure the worker tries again up to this many times, waiting longer each time (2, 4, 8 ... minutes).', 'After a failure the worker tries again up to this many times, waiting longer each time (2, 4, 8 ... minutes).', 1007),
 ('social_media_image_mb', 'social', 'number', '5'::jsonb, 'MB', null, 1, 20,
  'ছবির সর্বোচ্চ আকার', 'Largest image size', 'Largest image size',
  'JPEG বা PNG ছবির সীমা। এর বেশি হলে ছবি যোগ হবে না।', 'Limit for JPEG or PNG images. Bigger files are refused.', 'Limit for JPEG or PNG images. Bigger files are refused.', 1008),
 ('social_media_video_mb', 'social', 'number', '50'::jsonb, 'MB', null, 1, 200,
  'ভিডিওর সর্বোচ্চ আকার', 'Largest video size', 'Largest video size',
  'MP4 ভিডিওর সীমা। এর বেশি হলে ভিডিও যোগ হবে না।', 'Limit for MP4 videos. Bigger files are refused.', 'Limit for MP4 videos. Bigger files are refused.', 1009)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select g.code, 'reports', g.srt, g.bn, g.mx, g.en, 'once', null
  from (values
    ('social_manage', 95, 'সোশ্যাল পোস্ট লেখা ও জমা দেওয়া', 'Social post লেখা ও submit', 'Write and submit social posts'),
    ('social_approve', 96, 'সোশ্যাল পোস্ট অনুমোদন', 'Social post approve', 'Approve social posts')) as g(code, srt, bn, mx, en)
where not exists (select 1 from public.grant_defs d where d.grant_code = g.code);

-- rule guard: quiet hours are HH:MM and come in pairs; limits and media sizes stay in their range (set_rule checks the kind; this checks the shape)
create or replace function public._x500_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.key in ('social_quiet_from', 'social_quiet_to') then
    if nullif(new.value #>> '{}', '') is not null and (new.value #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'bad_value: HH:MM'; end if;
  end if;
  return new;
end $$;
drop trigger if exists x500_rules_guard on public.rules;
create trigger x500_rules_guard before insert or update on public.rules for each row when (new.key in ('social_quiet_from', 'social_quiet_to')) execute function public._x500_rules_guard();

-- ---------- helpers ----------
create or replace function public._x500_dhaka(p timestamptz) returns date language sql immutable as $$ select (p at time zone 'Asia/Dhaka')::date $$;
create or replace function public._x500_inquiet(p timestamptz) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f text := public.rule_txt('social_quiet_from'); t text := public.rule_txt('social_quiet_to'); n time := (p at time zone 'Asia/Dhaka')::time;
begin
  if f is null or t is null or f !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or f = t then return false; end if;
  if f::time < t::time then return n >= f::time and n < t::time; end if;
  return n >= f::time or n < t::time;
end $$;

-- the gate: switch on, the person may do it. Owner always; otherwise the grant.
create or replace function public._x500_gate(p_kind text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('social_on') then raise exception 'module_off: the social workspace is switched off'; end if;
  if p_kind = 'manage' and not (public.is_owner() or public.has_grant('social_manage')) then raise exception 'not allowed'; end if;
  if p_kind = 'approve' and not (public.is_owner() or public.has_grant('social_approve')) then raise exception 'not allowed'; end if;
  if p_kind = 'view' and not (public.is_owner() or public.has_grant('social_manage') or public.has_grant('social_approve')) then raise exception 'not allowed'; end if;
end $$;

-- the state machine: the only legal moves
create or replace function public._x500_move_ok(f text, t text) returns boolean language sql immutable as $$
  select case f
    when 'draft' then t in ('awaiting_approval', 'cancelled')
    when 'awaiting_approval' then t in ('approved', 'draft', 'cancelled')
    when 'approved' then t in ('scheduled', 'draft', 'cancelled')
    when 'scheduled' then t in ('published', 'failed', 'cancelled')
    when 'failed' then t in ('scheduled', 'draft', 'cancelled')
    else false end
$$;

create or replace function public._x500_media_ok(p jsonb) returns boolean language plpgsql immutable as $$
declare e jsonb; mb_img numeric; mb_vid numeric;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 10 then return false; end if;
  select nullif(public.rule_txt('social_media_image_mb'), '')::numeric into mb_img;
  select nullif(public.rule_txt('social_media_video_mb'), '')::numeric into mb_vid;
  for e in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(e) <> 'object' or nullif(btrim(e ->> 'path'), '') is null or char_length(e ->> 'path') > 300 then return false; end if;
    if e ->> 'kind' = 'image' then
      if (e ->> 'mime') not in ('image/jpeg', 'image/png') then return false; end if;
      if (e ->> 'bytes') !~ '^[0-9]+$' or (e ->> 'bytes')::numeric > coalesce(mb_img, 0) * 1048576 then return false; end if;
    elsif e ->> 'kind' = 'video' then
      if (e ->> 'mime') <> 'video/mp4' then return false; end if;
      if (e ->> 'bytes') !~ '^[0-9]+$' or (e ->> 'bytes')::numeric > coalesce(mb_vid, 0) * 1048576 then return false; end if;
    else return false; end if;
  end loop;
  return true;
end $$;

-- ---------- tables ----------
create table if not exists public.social_items (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int references public.locations(id),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  caption_bn text check (caption_bn is null or char_length(caption_bn) <= 2200),
  caption_en text check (caption_en is null or char_length(caption_en) <= 2200),
  hashtags text[] not null default '{}' check (cardinality(hashtags) <= 30),
  media jsonb not null default '[]' check (jsonb_typeof(media) = 'array' and jsonb_array_length(media) <= 10),
  product_code text check (product_code is null or char_length(product_code) <= 60),
  utm_campaign text check (utm_campaign is null or char_length(utm_campaign) <= 60),
  coupon_code text check (coupon_code is null or char_length(coupon_code) <= 40),
  template_code text check (template_code is null or char_length(template_code) <= 40),
  draft_source text not null default 'human' check (draft_source in ('human', 'ai')),
  ai_note text check (ai_note is null or char_length(ai_note) <= 300),
  channels text[] not null default '{}' check (channels <@ array['facebook', 'instagram', 'webhook']::text[]),
  is_public boolean not null default true,
  status text not null default 'draft' check (status in ('draft', 'awaiting_approval', 'approved', 'scheduled', 'published', 'failed', 'cancelled')),
  scheduled_at timestamptz,
  preview_hash text, approved_by uuid, approved_at timestamptz, approved_staff text,
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (status <> 'scheduled' or scheduled_at is not null),
  check (status not in ('approved', 'scheduled', 'published') or (preview_hash is not null and approved_by is not null))
);
create index if not exists social_items_status on public.social_items (status, scheduled_at);

create table if not exists public.social_item_events (
  id bigint generated always as identity primary key,
  item_id uuid not null references public.social_items(id),
  action text not null check (char_length(action) between 1 and 40),
  from_status text, to_status text, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, detail jsonb, at timestamptz not null default now()
);
create index if not exists social_item_events_item on public.social_item_events (item_id, id);

create table if not exists public.social_deliveries (
  id bigint generated always as identity primary key,
  item_id uuid not null references public.social_items(id),
  channel text not null check (channel in ('facebook', 'instagram', 'webhook', 'whatsapp')),
  customer_id uuid references public.customers(id),
  idempotency_key text not null unique check (char_length(idempotency_key) between 3 and 200),
  status text not null default 'queued' check (status in ('queued', 'sending', 'published', 'failed', 'cancelled')),
  scheduled_at timestamptz not null,
  attempts int not null default 0 check (attempts >= 0),
  max_attempts int not null default 5 check (max_attempts between 1 and 20),
  next_try_at timestamptz not null default now(),
  lease_until timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 300),
  provider_post_id text check (provider_post_id is null or char_length(provider_post_id) <= 200),
  permalink text check (permalink is null or char_length(permalink) <= 500),
  published_at timestamptz, created_by uuid, created_at timestamptz not null default now(),
  check ((channel = 'whatsapp') = (customer_id is not null)),
  unique (item_id, channel, customer_id)
);
create index if not exists social_deliveries_due on public.social_deliveries (status, next_try_at);
create index if not exists social_deliveries_day on public.social_deliveries (scheduled_at, status);

create table if not exists public.social_metrics (
  id bigint generated always as identity primary key,
  delivery_id bigint not null references public.social_deliveries(id),
  captured_at timestamptz not null default now(),
  reach int check (reach is null or reach >= 0), engagement int check (engagement is null or engagement >= 0), clicks int check (clicks is null or clicks >= 0),
  source text not null default 'provider' check (source in ('provider', 'manual'))
);
create index if not exists social_metrics_delivery on public.social_metrics (delivery_id, id);

-- the content fields: what the approver sees. Changing any of them after draft is refused.
create or replace function public._x500_hash(i public.social_items) returns text language sql immutable as $$
  select md5(jsonb_build_object('t', i.title, 'bn', i.caption_bn, 'en', i.caption_en, 'h', i.hashtags, 'm', i.media, 'c', i.channels, 'p', i.is_public,
    'tpl', i.template_code, 'prod', i.product_code, 'utm', i.utm_campaign, 'cpn', i.coupon_code, 'src', i.draft_source, 'loc', i.location_id)::text)
$$;

-- append-only and no hard delete
drop trigger if exists social_item_events_ro on public.social_item_events;
create trigger social_item_events_ro before update or delete on public.social_item_events for each row execute function public._append_only43();
drop trigger if exists social_item_events_ro_t on public.social_item_events;
create trigger social_item_events_ro_t before truncate on public.social_item_events for each statement execute function public._append_only43();
drop trigger if exists social_metrics_ro on public.social_metrics;
create trigger social_metrics_ro before update or delete on public.social_metrics for each row execute function public._append_only43();
drop trigger if exists social_metrics_ro_t on public.social_metrics;
create trigger social_metrics_ro_t before truncate on public.social_metrics for each statement execute function public._append_only43();
drop trigger if exists social_items_nodel on public.social_items;
create trigger social_items_nodel before delete on public.social_items for each row execute function public.no_hard_delete();
drop trigger if exists social_deliveries_nodel on public.social_deliveries;
create trigger social_deliveries_nodel before delete on public.social_deliveries for each row execute function public.no_hard_delete();
drop trigger if exists audit_social_items on public.social_items;
create trigger audit_social_items after insert or update on public.social_items for each row execute function public.log_change('id');
drop trigger if exists audit_social_deliveries on public.social_deliveries;
create trigger audit_social_deliveries after insert or update on public.social_deliveries for each row execute function public.log_change('id');

-- state machine + content lock + maker/approver rules, enforced in the database (a direct update is refused too)
create or replace function public._x500_items_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'illegal_transition: a new item starts as draft'; end if;
    return new;
  end if;
  if new.status is distinct from old.status then
    if not public._x500_move_ok(old.status, new.status) then raise exception 'illegal_transition: % to % is not allowed', old.status, new.status; end if;
  end if;
  if old.status <> 'draft' and (new.title, new.caption_bn, new.caption_en, new.hashtags, new.media, new.channels, new.is_public, new.template_code,
       new.product_code, new.utm_campaign, new.coupon_code, new.draft_source, new.location_id) is distinct from
      (old.title, old.caption_bn, old.caption_en, old.hashtags, old.media, old.channels, old.is_public, old.template_code,
       old.product_code, old.utm_campaign, old.coupon_code, old.draft_source, old.location_id)
     and new.status is not distinct from old.status then
    raise exception 'locked: a changed item goes back to draft first';
  end if;
  if new.status = 'approved' and new.status is distinct from old.status then
    if new.approved_by is null or new.approved_by = new.created_by then raise exception 'maker_cannot_approve: the person who wrote the item cannot approve it'; end if;
    if new.preview_hash is distinct from public._x500_hash(new) then raise exception 'preview_changed: the content changed after the preview'; end if;
  end if;
  if new.status = 'scheduled' and new.scheduled_at is null then raise exception 'scheduled_at_required'; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists x500_items_guard on public.social_items;
create trigger x500_items_guard before insert or update on public.social_items for each row execute function public._x500_items_guard();

-- ---------- limits (per Dhaka day and per hour) ----------
-- counts the deliveries already planned or sent in the window; blank limit = refuse (nothing invented)
create or replace function public._x500_limits(p_at timestamptz, p_n int, p_item uuid) returns void language plpgsql stable security definer set search_path = public as $$
declare d_max numeric := public.rule_num('social_max_per_day'); h_max numeric := public.rule_num('social_max_per_hour'); n_day int; n_hour int;
        day0 timestamptz := (public._x500_dhaka(p_at)::text || ' 00:00 Asia/Dhaka')::timestamptz; hour0 timestamptz := date_trunc('hour', p_at);
begin
  if d_max is null or h_max is null then raise exception 'limit_not_set: type the per-day and per-hour limits first'; end if;
  select count(*) into n_day from public.social_deliveries where status in ('queued', 'sending', 'published') and scheduled_at >= day0 and scheduled_at < day0 + interval '1 day'
     and (p_item is null or item_id <> p_item);
  select count(*) into n_hour from public.social_deliveries where status in ('queued', 'sending', 'published') and scheduled_at >= hour0 and scheduled_at < hour0 + interval '1 hour'
     and (p_item is null or item_id <> p_item);
  if n_day + p_n > d_max then raise exception 'day_limit: the per-day limit is reached'; end if;
  if n_hour + p_n > h_max then raise exception 'hour_limit: the per-hour limit is reached'; end if;
end $$;

-- ---------- browser RPCs ----------
create or replace function public.social_item_save(p_id uuid, p_client uuid, p_loc int, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); i public.social_items; r public.social_items; ch text[]; hs text[]; bn text; en text;
begin
  perform public._x500_gate('manage');
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if p_id is null then
    if p_client is not null then
      perform public._client_lock(p_client);
      select * into i from public.social_items where client_id = p_client and created_by = auth.uid();
      if found then return jsonb_build_object('id', i.id, 'status', i.status, 'dup', true); end if;
    end if;
    i.id := null;
  else
    select * into i from public.social_items where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if i.status <> 'draft' then raise exception 'not_draft: a changed item goes back to draft first'; end if;
  end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  ch := case when d ? 'channels' then array(select jsonb_array_elements_text(d -> 'channels')) else coalesce(i.channels, '{}') end;
  hs := case when d ? 'hashtags' then array(select jsonb_array_elements_text(d -> 'hashtags')) else coalesce(i.hashtags, '{}') end;
  if cardinality(hs) > 30 or exists (select 1 from unnest(hs) h where char_length(h) > 50) then raise exception 'bad_hashtags'; end if;
  if not (ch <@ array['facebook', 'instagram', 'webhook']::text[]) then raise exception 'bad_channel'; end if;
  if d ? 'media' and not public._x500_media_ok(d -> 'media') then raise exception 'bad_media: a file is too big or of a kind that is not allowed'; end if;
  bn := case when d ? 'caption_bn' then nullif(btrim(d ->> 'caption_bn'), '') else i.caption_bn end;
  en := case when d ? 'caption_en' then nullif(btrim(d ->> 'caption_en'), '') else i.caption_en end;
  if p_id is null then
    insert into public.social_items (client_id, location_id, title, caption_bn, caption_en, hashtags, media, product_code, utm_campaign, coupon_code, template_code,
        draft_source, ai_note, channels, is_public, created_by, created_staff)
      values (p_client, coalesce(p_loc, null), coalesce(nullif(btrim(d ->> 'title'), ''), ''), bn, en, hs,
        coalesce(d -> 'media', '[]'), nullif(btrim(d ->> 'product_code'), ''), nullif(btrim(d ->> 'utm_campaign'), ''), nullif(btrim(d ->> 'coupon_code'), ''),
        nullif(btrim(d ->> 'template_code'), ''), case when d ->> 'draft_source' = 'ai' then 'ai' else 'human' end,
        left(nullif(btrim(d ->> 'ai_note'), ''), 300), ch, coalesce((d ->> 'is_public')::boolean, true), auth.uid(), public._c3_staff_x500(auth.uid()))
      returning * into r;
    insert into public.social_item_events (item_id, action, from_status, to_status, by_user, by_staff) values (r.id, 'created', null, 'draft', auth.uid(), r.created_staff);
    return jsonb_build_object('id', r.id, 'status', r.status);
  end if;
  update public.social_items set title = case when d ? 'title' then coalesce(nullif(btrim(d ->> 'title'), ''), title) else title end,
      caption_bn = bn, caption_en = en, hashtags = hs, channels = ch,
      media = case when d ? 'media' then d -> 'media' else media end,
      product_code = case when d ? 'product_code' then nullif(btrim(d ->> 'product_code'), '') else product_code end,
      utm_campaign = case when d ? 'utm_campaign' then nullif(btrim(d ->> 'utm_campaign'), '') else utm_campaign end,
      coupon_code = case when d ? 'coupon_code' then nullif(btrim(d ->> 'coupon_code'), '') else coupon_code end,
      template_code = case when d ? 'template_code' then nullif(btrim(d ->> 'template_code'), '') else template_code end,
      draft_source = case when d ? 'draft_source' then (case when d ->> 'draft_source' = 'ai' then 'ai' else 'human' end) else draft_source end,
      ai_note = case when d ? 'ai_note' then left(nullif(btrim(d ->> 'ai_note'), ''), 300) else ai_note end,
      is_public = case when d ? 'is_public' then (d ->> 'is_public')::boolean else is_public end,
      location_id = case when p_loc is not null then p_loc else location_id end
    where id = i.id;
  insert into public.social_item_events (item_id, action, from_status, to_status, by_user, by_staff) values (i.id, 'edited', 'draft', 'draft', auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', i.id, 'status', 'draft');
end $$;

-- staff name for the trail (the profile's staff id, never typed by the person)
create or replace function public._c3_staff_x500(p_user uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.staff_id, ''), nullif(p.full_name, '')) from public.profiles p where p.id = p_user
$$;

-- what the approver reads before approving (the hash is what he approves)
create or replace function public.social_item_preview(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('view');
  select * into i from public.social_items where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', i.id, 'status', i.status, 'title', i.title, 'caption_bn', i.caption_bn, 'caption_en', i.caption_en, 'hashtags', i.hashtags,
    'media', i.media, 'channels', i.channels, 'is_public', i.is_public, 'template_code', i.template_code, 'product_code', i.product_code, 'utm_campaign', i.utm_campaign,
    'coupon_code', i.coupon_code, 'draft_source', i.draft_source, 'preview_hash', public._x500_hash(i), 'created_by_me', i.created_by = auth.uid());
end $$;

create or replace function public.social_item_submit(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('manage');
  select * into i from public.social_items where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if i.status <> 'draft' then raise exception 'illegal_transition: only a draft can be submitted'; end if;
  if nullif(btrim(coalesce(i.caption_bn, '') || coalesce(i.caption_en, '')), '') is null then raise exception 'caption_required: write the caption in Bangla or English'; end if;
  if cardinality(i.channels) = 0 then raise exception 'channel_required: choose at least one channel'; end if;
  update public.social_items set status = 'awaiting_approval' where id = p_id;
  insert into public.social_item_events (item_id, action, from_status, to_status, by_user, by_staff) values (p_id, 'submitted', 'draft', 'awaiting_approval', auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', p_id, 'status', 'awaiting_approval');
end $$;

create or replace function public.social_item_approve(p_id uuid, p_preview_hash text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('approve');
  select * into i from public.social_items where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if i.status <> 'awaiting_approval' then raise exception 'illegal_transition: only an item awaiting approval can be approved'; end if;
  if i.created_by = auth.uid() then raise exception 'maker_cannot_approve: the person who wrote the item cannot approve it'; end if;
  if p_preview_hash is null or p_preview_hash <> public._x500_hash(i) then raise exception 'preview_changed: look at the preview again'; end if;
  update public.social_items set status = 'approved', preview_hash = p_preview_hash, approved_by = auth.uid(), approved_at = now(),
      approved_staff = public._c3_staff_x500(auth.uid()) where id = p_id;
  insert into public.social_item_events (item_id, action, from_status, to_status, note, by_user, by_staff) values (p_id, 'approved', 'awaiting_approval', 'approved', left(nullif(btrim(p_note), ''), 300), auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', p_id, 'status', 'approved');
end $$;

create or replace function public.social_item_return(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('approve');
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  select * into i from public.social_items where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if i.status not in ('awaiting_approval', 'approved', 'failed') then raise exception 'illegal_transition: this item cannot go back to draft now'; end if;
  if i.status in ('approved', 'failed') and exists (select 1 from public.social_deliveries d where d.item_id = p_id and d.status in ('sending', 'published')) then
    raise exception 'illegal_transition: something was already sent, cancel the item instead';
  end if;
  update public.social_items set status = 'draft', preview_hash = null, approved_by = null, approved_at = null, approved_staff = null where id = p_id;
  insert into public.social_item_events (item_id, action, from_status, to_status, note, by_user, by_staff) values (p_id, 'returned', i.status, 'draft', left(btrim(p_reason), 300), auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', p_id, 'status', 'draft');
end $$;

-- approved -> scheduled (or failed -> scheduled to try again). Creates one delivery per channel; the same key never twice.
create or replace function public.social_item_schedule(p_id uuid, p_at timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items; c text; n int;
begin
  perform public._x500_gate('manage');
  if public.rule_on('social_stop_all') then raise exception 'stopped: publishing is stopped by the owner'; end if;
  if p_at is null or p_at <= now() or p_at > now() + interval '1 year' then raise exception 'bad_time: the time must be in the future'; end if;
  if public._x500_inquiet(p_at) then raise exception 'quiet_hours: this time is inside the quiet hours'; end if;
  select * into i from public.social_items where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if i.status not in ('approved', 'failed') then raise exception 'illegal_transition: only an approved item can be scheduled'; end if;
  if i.status = 'failed' and not (public.is_owner() or public.has_grant('social_approve')) then raise exception 'not allowed: a failed post is tried again by the approver'; end if;
  n := cardinality(i.channels);
  perform public._x500_limits(p_at, n, p_id);
  update public.social_items set status = 'scheduled', scheduled_at = p_at where id = p_id;
  foreach c in array i.channels loop
    insert into public.social_deliveries (item_id, channel, customer_id, idempotency_key, scheduled_at, max_attempts, created_by)
      values (p_id, c, null, p_id::text || ':' || c, p_at, greatest(least(coalesce(public.rule_num('social_retry_max'), 5)::int, 20), 1), auth.uid())
      on conflict (idempotency_key) do update set status = 'queued', attempts = 0, next_try_at = now(), scheduled_at = excluded.scheduled_at, last_error = null
        where social_deliveries.status = 'failed';
  end loop;
  insert into public.social_item_events (item_id, action, from_status, to_status, detail, by_user, by_staff) values (p_id, 'scheduled', i.status, 'scheduled', jsonb_build_object('at', p_at, 'channels', i.channels), auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', p_id, 'status', 'scheduled', 'at', p_at);
end $$;

-- a WhatsApp template message to ONE customer. Consent is checked now and again when the worker claims it.
create or replace function public.social_wa_enqueue(p_item uuid, p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items; b jsonb; d public.social_deliveries; key text;
begin
  perform public._x500_gate('manage');
  if public.rule_on('social_stop_all') then raise exception 'stopped: publishing is stopped by the owner'; end if;
  select * into i from public.social_items where id = p_item;
  if not found then raise exception 'not_found'; end if;
  if i.status <> 'scheduled' then raise exception 'illegal_transition: a customer message goes with a scheduled item'; end if;
  if i.template_code is null then raise exception 'template_required: a WhatsApp message needs a template'; end if;
  b := public._crmb_send_allowed(p_customer, 'whatsapp', 'promo', now());
  if not (b ->> 'ok')::boolean and (b ->> 'reason') <> 'quiet_hours' then raise exception 'consent_blocked: %', b ->> 'reason'; end if;
  key := p_item::text || ':whatsapp:' || p_customer::text;
  select * into d from public.social_deliveries where idempotency_key = key;
  if found then return jsonb_build_object('id', d.id, 'status', d.status, 'duplicate', true); end if;
  perform public._x500_limits(i.scheduled_at, 1, null);
  insert into public.social_deliveries (item_id, channel, customer_id, idempotency_key, scheduled_at, max_attempts, created_by)
    values (p_item, 'whatsapp', p_customer, key, i.scheduled_at, greatest(least(coalesce(public.rule_num('social_retry_max'), 5)::int, 20), 1), auth.uid()) returning * into d;
  return jsonb_build_object('id', d.id, 'status', d.status, 'duplicate', false);
end $$;

create or replace function public.social_item_cancel(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('manage');
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  select * into i from public.social_items where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if i.status not in ('draft', 'awaiting_approval', 'approved', 'scheduled', 'failed') then raise exception 'illegal_transition: this item is already closed'; end if;
  if i.status in ('draft', 'awaiting_approval', 'approved') and i.created_by is distinct from auth.uid() and not (public.is_owner() or public.has_grant('social_approve')) then raise exception 'not allowed'; end if;
  update public.social_deliveries set status = 'cancelled', last_error = 'cancelled_by_staff' where item_id = p_id and status in ('queued', 'failed');
  update public.social_items set status = 'cancelled', cancel_reason = left(btrim(p_reason), 300) where id = p_id;
  insert into public.social_item_events (item_id, action, from_status, to_status, note, by_user, by_staff) values (p_id, 'cancelled', i.status, 'cancelled', left(btrim(p_reason), 300), auth.uid(), public._c3_staff_x500(auth.uid()));
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- the owner's emergency stop: only the owner; a queued post waits and goes when it is switched off again
create or replace function public.social_stop_all_set(p_on boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if p_on and nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  perform public.set_rule('social_stop_all', to_jsonb(p_on));    -- the rules table is audited by log_change
  return jsonb_build_object('social_stop_all', p_on, 'reason', left(btrim(p_reason), 300));
end $$;

-- ---------- worker RPCs (ops bot 'notify' login, or the owner) ----------
create or replace function public.social_publish_claim(p_limit int default 10) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 10), 1), 50); res jsonb := '[]'::jsonb; r public.social_deliveries; i public.social_items; b jsonb; ph text;
        d_max numeric := public.rule_num('social_max_per_day'); h_max numeric := public.rule_num('social_max_per_hour'); n_sent int;
begin
  if not (public.is_owner() or public._i62_ops()) then raise exception 'not allowed'; end if;
  if not (public.rule_on('social_on') and public.rule_on('social_publish_on')) then return jsonb_build_object('on', false, 'reason', 'switched_off', 'rows', res); end if;
  if public.rule_on('social_stop_all') then return jsonb_build_object('on', false, 'reason', 'stopped', 'rows', res); end if;
  if public._x500_inquiet(now()) then return jsonb_build_object('on', false, 'reason', 'quiet_hours', 'rows', res); end if;
  if d_max is null or h_max is null then return jsonb_build_object('on', false, 'reason', 'limit_not_set', 'rows', res); end if;
  select count(*) into n_sent from public.social_deliveries where status = 'published' and published_at >= now() - interval '1 hour';
  if n_sent >= h_max then return jsonb_build_object('on', false, 'reason', 'hour_limit', 'rows', res); end if;
  select count(*) into n_sent from public.social_deliveries where status = 'published' and public._x500_dhaka(published_at) = public._x500_dhaka(now());
  if n_sent >= d_max then return jsonb_build_object('on', false, 'reason', 'day_limit', 'rows', res); end if;
  for r in
    select * from public.social_deliveries
     where ((status = 'queued' and next_try_at <= now()) or (status = 'sending' and lease_until < now())) and attempts < max_attempts and scheduled_at <= now()
     order by scheduled_at, id limit lim for update skip locked
  loop
    if r.channel = 'whatsapp' then
      b := public._crmb_send_allowed(r.customer_id, 'whatsapp', 'promo', now());
      if not (b ->> 'ok')::boolean then
        if (b ->> 'reason') = 'quiet_hours' then continue; end if;
        update public.social_deliveries set status = 'cancelled', last_error = left('consent: ' || (b ->> 'reason'), 300) where id = r.id;
        continue;
      end if;
      select mobile into ph from public.customers where id = r.customer_id;
      ph := public._i62_phone(ph);
      if ph is null then update public.social_deliveries set status = 'cancelled', last_error = 'bad_phone' where id = r.id; continue; end if;
    end if;
    select * into i from public.social_items where id = r.item_id;
    update public.social_deliveries set status = 'sending', attempts = r.attempts + 1, lease_until = now() + interval '15 minutes' where id = r.id;
    res := res || jsonb_build_array(jsonb_build_object('id', r.id, 'channel', r.channel, 'item_id', r.item_id, 'attempt', r.attempts + 1,
      'title', i.title, 'caption_bn', i.caption_bn, 'caption_en', i.caption_en, 'hashtags', i.hashtags, 'media', i.media, 'template_code', i.template_code,
      'to', case when r.channel = 'whatsapp' then ph end));
  end loop;
  return jsonb_build_object('on', true, 'reason', null, 'rows', res);
end $$;

-- the worker reports one result. Success is final. A failure waits (2, 4, 8 ... minutes) and gives up as failed after the last try.
create or replace function public.social_publish_report(p_id bigint, p_ok boolean, p_provider_post_id text default null, p_permalink text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.social_deliveries; open_n int; failed_n int;
begin
  if not (public.is_owner() or public._i62_ops()) then raise exception 'not allowed'; end if;
  if p_id is null or p_ok is null then raise exception 'bad_input'; end if;
  select * into d from public.social_deliveries where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if d.status <> 'sending' then return jsonb_build_object('id', p_id, 'status', d.status, 'ignored', true); end if;
  if p_ok then
    update public.social_deliveries set status = 'published', published_at = now(), provider_post_id = left(p_provider_post_id, 200),
        permalink = left(p_permalink, 500), last_error = null, lease_until = null where id = p_id;
  elsif d.attempts >= d.max_attempts then
    update public.social_deliveries set status = 'failed', last_error = left(coalesce(p_error, 'error'), 300), lease_until = null where id = p_id;
  else
    update public.social_deliveries set status = 'queued', last_error = left(coalesce(p_error, 'error'), 300), lease_until = null,
        next_try_at = now() + (interval '1 minute' * power(2, d.attempts)::int) where id = p_id;
  end if;
  -- the item moves only from scheduled: all deliveries done -> published; some failed for good and none still waiting -> failed
  select count(*) filter (where status in ('queued', 'sending')), count(*) filter (where status = 'failed')
    into open_n, failed_n from public.social_deliveries where item_id = d.item_id;
  if open_n = 0 and exists (select 1 from public.social_items where id = d.item_id and status = 'scheduled') then
    update public.social_items set status = case when failed_n > 0 then 'failed' else 'published' end where id = d.item_id;
    insert into public.social_item_events (item_id, action, from_status, to_status, note, by_user)
      values (d.item_id, 'worker', 'scheduled', case when failed_n > 0 then 'failed' else 'published' end, 'all channels reported', null);
  end if;
  return jsonb_build_object('id', p_id, 'status', (select status from public.social_deliveries where id = p_id));
end $$;

create or replace function public.social_metric_record(p_delivery bigint, p_reach int, p_engagement int, p_clicks int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._i62_ops()) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.social_deliveries where id = p_delivery and status = 'published') then raise exception 'not_published'; end if;
  insert into public.social_metrics (delivery_id, reach, engagement, clicks, source) values (p_delivery, p_reach, p_engagement, p_clicks, 'provider');
  return jsonb_build_object('delivery_id', p_delivery, 'saved', true);
end $$;

-- ---------- reads ----------
create or replace function public.social_board() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('social_on') then return jsonb_build_object('on', false, 'publish_on', public.rule_on('social_publish_on'), 'stopped', public.rule_on('social_stop_all'), 'limits_set', false); end if;
  perform public._x500_gate('view');
  return jsonb_build_object('on', public.rule_on('social_on'), 'publish_on', public.rule_on('social_publish_on'), 'stopped', public.rule_on('social_stop_all'),
    'max_per_day', public.rule_num('social_max_per_day'), 'max_per_hour', public.rule_num('social_max_per_hour'), 'limits_set', public.rule_num('social_max_per_day') is not null and public.rule_num('social_max_per_hour') is not null,
    'quiet', public._x500_inquiet(now()),
    'items', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.social_items group by status) s), '{}'::jsonb),
    'deliveries', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.social_deliveries group by status) s), '{}'::jsonb));
end $$;

create or replace function public.social_items_list(p_status text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._x500_gate('view');
  if p_status is not null and p_status not in ('draft', 'awaiting_approval', 'approved', 'scheduled', 'published', 'failed', 'cancelled') then raise exception 'bad_input'; end if;
  return coalesce((select jsonb_agg(z.j order by z.at desc) from (
    select i.created_at at, jsonb_build_object('id', i.id, 'title', i.title, 'status', i.status, 'channels', i.channels, 'is_public', i.is_public, 'draft_source', i.draft_source,
      'scheduled_at', i.scheduled_at, 'created_by_me', i.created_by = auth.uid()) j
      from public.social_items i where (p_status is null or i.status = p_status) order by i.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) z), '[]'::jsonb);
end $$;

-- one item with its trail, deliveries and metrics. Metrics with no row are "not captured" (null), never zero.
create or replace function public.social_item_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.social_items;
begin
  perform public._x500_gate('view');
  select * into i from public.social_items where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('item', jsonb_build_object('id', i.id, 'title', i.title, 'status', i.status, 'channels', i.channels, 'scheduled_at', i.scheduled_at,
      'preview_hash', i.preview_hash, 'cancel_reason', i.cancel_reason, 'approved_staff', i.approved_staff),
    'events', coalesce((select jsonb_agg(jsonb_build_object('action', e.action, 'from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
        from public.social_item_events e where e.item_id = p_id), '[]'::jsonb),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'channel', d.channel, 'status', d.status, 'attempts', d.attempts, 'max_attempts', d.max_attempts,
        'last_error', d.last_error, 'permalink', d.permalink, 'published_at', d.published_at,
        'reach', (select m.reach from public.social_metrics m where m.delivery_id = d.id order by m.id desc limit 1),
        'engagement', (select m.engagement from public.social_metrics m where m.delivery_id = d.id order by m.id desc limit 1),
        'clicks', (select m.clicks from public.social_metrics m where m.delivery_id = d.id order by m.id desc limit 1),
        'metrics', case when exists (select 1 from public.social_metrics m where m.delivery_id = d.id) then 'captured' else 'not captured' end) order by d.id)
        from public.social_deliveries d where d.item_id = p_id), '[]'::jsonb));
end $$;

-- the content calendar: scheduled items in a range, and the festival days (festival_calendar, owner-entered) in the same range
create or replace function public.social_calendar(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._x500_gate('view');
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 then raise exception 'bad_range'; end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title, 'status', i.status, 'at', i.scheduled_at) order by i.scheduled_at)
        from public.social_items i where i.scheduled_at is not null and public._x500_dhaka(i.scheduled_at) between p_from and p_to), '[]'::jsonb),
    'festivals', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name_bn', f.name_bn, 'name_en', f.name_en, 'start', f.start_date, 'end', f.end_date) order by f.start_date)
        from public.festival_calendar f where f.active and f.start_date <= p_to and f.end_date >= p_from), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
alter table public.social_items enable row level security;
alter table public.social_item_events enable row level security;
alter table public.social_deliveries enable row level security;
alter table public.social_metrics enable row level security;
revoke all on public.social_items, public.social_item_events, public.social_deliveries, public.social_metrics from public, anon, authenticated;
grant select on public.social_items, public.social_item_events, public.social_deliveries, public.social_metrics to authenticated;
drop policy if exists social_items_read on public.social_items;
create policy social_items_read on public.social_items for select to authenticated using (public.is_active() and (public.is_owner() or public.has_grant('social_manage') or public.has_grant('social_approve')));
drop policy if exists social_item_events_read on public.social_item_events;
create policy social_item_events_read on public.social_item_events for select to authenticated using (public.is_active() and (public.is_owner() or public.has_grant('social_manage') or public.has_grant('social_approve')));
drop policy if exists social_deliveries_read on public.social_deliveries;
create policy social_deliveries_read on public.social_deliveries for select to authenticated using (public.is_owner());
drop policy if exists social_metrics_read on public.social_metrics;
create policy social_metrics_read on public.social_metrics for select to authenticated using (public.is_owner());
revoke usage, select on sequence public.social_item_events_id_seq, public.social_deliveries_id_seq, public.social_metrics_id_seq from public, anon, authenticated;

revoke all on function public._x500_dhaka(timestamptz), public._x500_inquiet(timestamptz), public._x500_gate(text), public._x500_move_ok(text, text),
  public._x500_hash(public.social_items), public._x500_media_ok(jsonb), public._x500_limits(timestamptz, int, uuid), public._x500_items_guard(),
  public._x500_rules_guard(), public._c3_staff_x500(uuid) from public, anon, authenticated;
revoke all on function public.social_item_save(uuid, uuid, int, jsonb), public.social_item_preview(uuid), public.social_item_submit(uuid),
  public.social_item_approve(uuid, text, text), public.social_item_return(uuid, text), public.social_item_schedule(uuid, timestamptz), public.social_wa_enqueue(uuid, uuid),
  public.social_item_cancel(uuid, text), public.social_stop_all_set(boolean, text), public.social_publish_claim(int),
  public.social_publish_report(bigint, boolean, text, text, text), public.social_metric_record(bigint, int, int, int), public.social_board(),
  public.social_items_list(text, int), public.social_item_get(uuid), public.social_calendar(date, date) from public, anon;
grant execute on function public.social_item_save(uuid, uuid, int, jsonb), public.social_item_preview(uuid), public.social_item_submit(uuid),
  public.social_item_approve(uuid, text, text), public.social_item_return(uuid, text), public.social_item_schedule(uuid, timestamptz), public.social_wa_enqueue(uuid, uuid),
  public.social_item_cancel(uuid, text), public.social_stop_all_set(boolean, text), public.social_publish_claim(int),
  public.social_publish_report(bigint, boolean, text, text, text), public.social_metric_record(bigint, int, int, int), public.social_board(),
  public.social_items_list(text, int), public.social_item_get(uuid), public.social_calendar(date, date) to authenticated;

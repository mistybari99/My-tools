-- ============================================================
-- Phase 490 (X2 website, part 1) - SETTINGS, CATALOGUE PUBLISHING, PUBLIC READ RPCs.
-- Run AFTER phase478 (the whole build). Additive + idempotent (paste twice = no error). No existing function or table is changed.
--   1. SETTINGS     every website setting is a row in `rules` (owner-only set_rule, audited). All switches default OFF; numbers default to a safe "not set" value.
--   2. PUBLISHING   web_item_pub: one row per item the owner chooses to show on the web (published flag, public name/description bn+en,
--                   category order, availability mode, allergen / diet tags, lead days, price snapshot for the drift report).
--                   web_item_images: an image is shown on the web only after the owner approves it (private `photos` bucket stays private).
--   3. LOCATIONS    web_pickup_points (which outlet can be a pickup point, public hours) and web_zones (delivery zones, charge, minimum order).
--   4. CALENDAR     web_closures (holiday closure days, shown as a banner; orders for a closed day are refused by phase491).
--   5. PUBLIC READ  web_site_config(), web_catalog_v2(), web_quote(); anon may call ONLY these (grants at the end of this file).
--                   They return published data only: no cost, no supplier, no staff, no exact stock number, no internal codes.
-- Every behaviour is OFF until the owner switches it on: website_on = false means the public RPCs answer {on:false}.
-- ============================================================

-- ---------- 1. settings (rules) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('website_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েবসাইট (দোকানের অনলাইন পাতা) চালু', 'Website (online shop) চালু', 'Website (online shop) is on',
  'বন্ধ থাকলে পাবলিক পাতা খালি দেখায় এবং কোনো অর্ডার নেয় না। ডোমেইন/হোস্টিং না থাকলেও এটি চালু করে স্থানীয়ভাবে পরীক্ষা করা যায়।',
  'When off the public pages show nothing and take no orders. You can switch it on to test locally before a domain exists.', 700),
 ('website_location_id', 'pos', 'number', '0', null, null, 0, 100000, 'ওয়েবের অর্ডার কোন শাখায় যাবে (শাখা নম্বর)', 'Web order কোন branch-এ (branch id)', 'Branch that receives web orders (location id)',
  '০ = এখনও ঠিক করা হয়নি; তখন ওয়েব অর্ডার নেওয়া হবে না।', '0 = not chosen yet; web orders are refused until a branch is set.', 701),
 ('website_brand_bn', 'pos', 'text', '""', null, null, null, null, 'ওয়েবসাইটের নাম (বাংলা)', 'Website নাম (বাংলা)', 'Website name (Bangla)',
  'দোকানের নাম যেমন পাবলিকে দেখাবে।', 'Shop name as the public sees it.', 702),
 ('website_brand_en', 'pos', 'text', '""', null, null, null, null, 'ওয়েবসাইটের নাম (ইংরেজি)', 'Website name (English)', 'Website name (English)', null, null, 703),
 ('website_whatsapp', 'pos', 'text', '""', null, null, null, null, 'হোয়াটসঅ্যাপ নম্বর (অর্ডার/যোগাযোগ)', 'WhatsApp নম্বর (order/যোগাযোগ)', 'WhatsApp number (orders / contact)',
  'দেশের কোড সহ, যেমন 8801XXXXXXXXX। খালি থাকলে হোয়াটসঅ্যাপ বাটন দেখায় না।', 'With country code, e.g. 8801XXXXXXXXX. Blank hides the WhatsApp button.', 704),
 ('website_public_url', 'pos', 'text', '""', null, null, null, null, 'ওয়েবসাইটের পাবলিক ঠিকানা (ডোমেইন/হোস্টিং)', 'Website public URL (domain/hosting)', 'Website public URL (domain/hosting)',
  'ডোমেইন কেনার পর এখানে লিখুন। খালি থাকলে শুধু স্থানীয় পরীক্ষার ঠিকানা ব্যবহার হবে।', 'Set when a domain or hosting exists. Blank = local test only.', 705),
 ('website_stock_threshold', 'pos', 'number', '5', 'একক', null, 0, 1000000, 'স্টক এত কম হলে "সীমিত" দেখাবে', 'Stock এত কম হলে "limited" দেখাবে', 'Show "limited" at or below this stock',
  'ওয়েবে স্টকের সঠিক সংখ্যা দেখানো হয় না; শুধু অবস্থা: আছে / সীমিত / শেষ।', 'The exact stock number is never shown; only in stock / limited / sold out.', 706),
 ('website_min_order', 'pos', 'number', '0', 'টাকা', null, 0, 1000000000, 'সর্বনিম্ন অর্ডার (টাকা)', 'Minimum order (Tk)', 'Minimum order (Tk)',
  '০ = কোনো সর্বনিম্ন নেই।', '0 = no minimum.', 707),
 ('website_cutoff_hour', 'pos', 'number', '0', 'ঘণ্টা (০-২৩)', null, 0, 23, 'আজকের অর্ডার বন্ধ হবে (ঘণ্টা)', 'আজকের order বন্ধ (ঘণ্টা)', 'Same-day order cut-off (hour, Dhaka)',
  '০ = কোনো cut-off নেই। যেমন 18 = সন্ধ্যা ৬টার পর আজকের ডেলিভারি নয়।', '0 = no cut-off. 18 = after 6 pm no same-day delivery.', 708),
 ('website_lead_days', 'pos', 'number', '0', 'দিন', null, 0, 60, 'অর্ডারের ন্যূনতম আগাম দিন', 'Order-এর ন্যূনতম আগাম দিন', 'Minimum lead days for an order',
  'কেকের মতো আইটেমের আলাদা আগাম সময় আইটেমে লেখা যায়; এটি সবার জন্য ন্যূনতম।', 'Shop-wide minimum; items can add their own lead days.', 709),
 ('website_pay_cod_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব: ডেলিভারিতে নগদ (COD) নেওয়া', 'Web: COD নেওয়া', 'Web: accept cash on delivery',
  'বন্ধ থাকলে COD অপশন দেখায় না।', 'Off hides the COD option.', 710),
 ('website_pay_manual_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব: bKash/Nagad ম্যানুয়াল (Trx ID লিখে) নেওয়া', 'Web: bKash/Nagad manual (Trx ID)', 'Web: bKash/Nagad manual (enter Trx ID)',
  'গ্রাহক টাকা পাঠিয়ে Trx ID লেখেন; দোকান যাচাই করে। কোনো অটো-পেমেন্ট নয়।', 'Customer sends money and types the Trx ID; the shop checks it. No automatic payment.', 711),
 ('website_pay_mobile_number', 'pos', 'text', '""', null, null, null, null, 'bKash/Nagad নম্বর (গ্রাহককে দেখানো)', 'bKash/Nagad নম্বর (দেখানো)', 'bKash/Nagad number shown to customers',
  'খালি থাকলে ম্যানুয়াল অপশন দেখায় না।', 'Blank hides the manual option.', 712),
 ('website_reserve_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব অর্ডারে স্টক ধরে রাখা (রিজার্ভেশন)', 'Web order-এ stock reserve চালু', 'Hard stock reservation at web checkout',
  'চালু হলে চেকআউটে স্টক আলাদা করে রাখা হয়; সময় শেষ বা বাতিল হলে ছেড়ে দেওয়া হয়। বন্ধ থাকলে আগের মতো শুধু দেখানো হয়।',
  'When on, checkout holds the stock and releases it on expiry or cancel. Off = availability is only shown.', 713),
 ('website_reserve_minutes', 'pos', 'number', '30', 'মিনিট', null, 5, 1440, 'রিজার্ভ স্টক কত মিনিট ধরা থাকবে', 'Reserve কত মিনিট ধরা থাকবে', 'Reservation hold time (minutes)',
  'এর মধ্যে অর্ডার নিশ্চিত না হলে স্টক ছেড়ে দেওয়া হবে।', 'If the order is not confirmed in time the stock is released.', 714),
 ('website_rate_max', 'pos', 'number', '5', 'বার', null, 0, 1000, 'ওয়েব অর্ডার: এক ডিভাইস সর্বোচ্চ কতবার', 'Web order: এক device-এ সর্বোচ্চ', 'Web order: max per device',
  '০ = সীমা নেই (প্রস্তাবিত নয়)।', '0 = no limit (not recommended).', 715),
 ('website_rate_window_min', 'pos', 'number', '60', 'মিনিট', null, 1, 1440, 'ওয়েব অর্ডার সীমার সময়ের জানালা', 'Web order rate window', 'Web order rate window (minutes)', null, null, 716),
 ('website_captcha_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব অর্ডারে ক্যাপচা লাগবে', 'Web order-এ captcha লাগবে', 'Web order needs a captcha pass',
  'ক্যাপচা সরবরাহকারী এখনও যুক্ত নয়; চালু করলে অর্ডার বন্ধ থাকবে যতক্ষণ না যুক্ত হয়।', 'No captcha provider is wired yet; when on, orders stay refused until one is added.', 717),
 ('website_custom_cake_on', 'pos', 'switch', 'false', null, null, null, null, 'কাস্টম কেকের অনুরোধ ফর্ম চালু', 'Custom cake request form চালু', 'Custom cake request form is on',
  'গ্রাহক স্বাদ, ওজন, লেখা, তারিখ ও ছবি দিয়ে অনুরোধ পাঠান; দোকান দেখে নিশ্চিত করে।', 'Customers send flavour, weight, message, date and a photo; the shop confirms.', 718),
 ('website_holiday_text_bn', 'pos', 'text', '""', null, null, null, null, 'ছুটির ব্যানার (বাংলা)', 'ছুটির banner (বাংলা)', 'Closure banner (Bangla)', null, null, 719),
 ('website_holiday_text_en', 'pos', 'text', '""', null, null, null, null, 'ছুটির ব্যানার (ইংরেজি)', 'ছুটির banner (English)', 'Closure banner (English)', null, null, 720),
 ('website_festival_mode_on', 'pos', 'switch', 'false', null, null, null, null, 'ঈদ/উৎসব প্রি-অর্ডার মোড', 'ঈদ/উৎসব pre-order mode', 'Festival pre-order mode',
  'চালু হলে আইটেমের "প্রি-অর্ডার" অবস্থা দেখানো যায় এবং আগাম দিন মানা হয়। বন্ধ = সাধারণ মোড।', 'On enables the pre-order state and lead days. Off = normal mode.', 721),
 ('website_pixel_id', 'pos', 'text', '""', null, null, null, null, 'Facebook Pixel ID (খালি = বন্ধ)', 'Facebook Pixel ID (blank = off)', 'Facebook Pixel ID (blank = off)',
  'শুধু আইডি সেট থাকলে এবং গ্রাহক সম্মতি দিলে স্ক্রিপ্ট লোড হয়।', 'The script loads only when this id is set AND the visitor accepted cookies.', 722),
 ('website_ga_id', 'pos', 'text', '""', null, null, null, null, 'Google Analytics ID (খালি = বন্ধ)', 'Google Analytics ID (blank = off)', 'Google Analytics ID (blank = off)',
  'শুধু আইডি সেট থাকলে এবং গ্রাহক সম্মতি দিলে স্ক্রিপ্ট লোড হয়।', 'Loads only when set AND cookies accepted.', 723),
 ('website_messenger_url', 'pos', 'text', '""', null, null, null, null, 'Messenger পেজের লিংক (খালি = বন্ধ)', 'Messenger page link (blank = off)', 'Messenger page link (blank = off)',
  'শুধু লিংক; ওয়েবে "মেসেঞ্জারে লিখুন" বাটন দেখায়।', 'Only a link; shows a "message us on Messenger" button.', 730),
 ('website_policy_privacy_bn', 'pos', 'text', '""', null, null, null, null, 'গোপনীয়তা নীতি (বাংলা)', 'গোপনীয়তা নীতি (বাংলা)', 'Privacy policy (Bangla)',
  'মালিক নিজে লিখবেন। খালি থাকলে পাতায় "শীঘ্রই" লেখা দেখায়।', 'Written by the owner. Blank shows "coming soon".', 724),
 ('website_policy_privacy_en', 'pos', 'text', '""', null, null, null, null, 'Privacy policy (English)', 'Privacy policy (English)', 'Privacy policy (English)', null, null, 725),
 ('website_policy_terms_bn', 'pos', 'text', '""', null, null, null, null, 'শর্তাবলি (বাংলা)', 'শর্তাবলি (বাংলা)', 'Terms (Bangla)', null, null, 726),
 ('website_policy_terms_en', 'pos', 'text', '""', null, null, null, null, 'Terms (English)', 'Terms (English)', 'Terms (English)', null, null, 727),
 ('website_policy_refund_bn', 'pos', 'text', '""', null, null, null, null, 'ফেরত ও বাতিল নীতি (বাংলা)', 'ফেরত ও বাতিল নীতি (বাংলা)', 'Refund and cancellation (Bangla)', null, null, 728),
 ('website_policy_refund_en', 'pos', 'text', '""', null, null, null, null, 'Refund and cancellation (English)', 'Refund and cancellation (English)', 'Refund and cancellation (English)', null, null, 729)
 on conflict (key) do nothing;

-- ---------- 2. publishing ----------
create table if not exists public.web_item_pub (
  item_id uuid primary key references public.items(id),
  published boolean not null default false,
  name_bn text check (name_bn is null or char_length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or char_length(name_en) <= 120),
  desc_bn text check (desc_bn is null or char_length(desc_bn) <= 1000),
  desc_en text check (desc_en is null or char_length(desc_en) <= 1000),
  category_pub text check (category_pub is null or char_length(category_pub) <= 60),
  category_sort int not null default 0 check (category_sort between 0 and 9999),
  sort int not null default 0 check (sort between 0 and 9999),
  avail_mode text not null default 'auto' check (avail_mode in ('auto', 'preorder', 'sold_out')),
  lead_days int not null default 0 check (lead_days between 0 and 60),
  allergens text check (allergens is null or char_length(allergens) <= 300),
  diet text[] not null default '{}' check (diet <@ array['halal', 'eggless', 'sugar_free', 'vegan']::text[]),
  price_snapshot numeric check (price_snapshot is null or price_snapshot >= 0),
  published_at timestamptz, published_by uuid, updated_at timestamptz not null default now(), updated_by uuid
);
create index if not exists web_item_pub_pub on public.web_item_pub (published, category_sort, sort);
alter table public.web_item_pub enable row level security;
revoke all on public.web_item_pub from public, anon, authenticated;
grant select on public.web_item_pub to authenticated;
drop policy if exists web_item_pub_owner_read on public.web_item_pub;
create policy web_item_pub_owner_read on public.web_item_pub for select to authenticated using (public.is_owner());
drop trigger if exists web_item_pub_no_delete on public.web_item_pub;
create trigger web_item_pub_no_delete before delete on public.web_item_pub for each row execute function public.no_hard_delete();
drop trigger if exists audit_web_item_pub on public.web_item_pub;
create trigger audit_web_item_pub after insert or update on public.web_item_pub for each row execute function public.log_change('item_id');

-- an image is shown on the web only after the owner approves it. The file lives in a PRIVATE bucket; the site gets a signed/approved path only.
create table if not exists public.web_item_images (
  id bigint generated always as identity primary key,
  item_id uuid not null references public.items(id),
  storage_path text not null check (char_length(storage_path) between 3 and 300),
  mime text not null check (mime in ('image/jpeg', 'image/png', 'image/webp')),
  bytes int not null check (bytes between 1 and 3145728),
  sort int not null default 0,
  approved boolean not null default false, approved_by uuid, approved_at timestamptz,
  created_by uuid, created_at timestamptz not null default now(),
  unique (item_id, storage_path)
);
alter table public.web_item_images enable row level security;
revoke all on public.web_item_images from public, anon, authenticated;
grant select on public.web_item_images to authenticated;
drop policy if exists web_item_images_owner_read on public.web_item_images;
create policy web_item_images_owner_read on public.web_item_images for select to authenticated using (public.is_owner());
drop trigger if exists web_item_images_no_delete on public.web_item_images;
create trigger web_item_images_no_delete before delete on public.web_item_images for each row execute function public.no_hard_delete();
drop trigger if exists audit_web_item_images on public.web_item_images;
create trigger audit_web_item_images after insert or update on public.web_item_images for each row execute function public.log_change('id');

-- ---------- 3. locations, zones ----------
create table if not exists public.web_pickup_points (
  location_id int primary key references public.locations(id),
  public boolean not null default false,
  hours_bn text check (hours_bn is null or char_length(hours_bn) <= 120),
  hours_en text check (hours_en is null or char_length(hours_en) <= 120),
  address_public text check (address_public is null or char_length(address_public) <= 300),
  updated_at timestamptz not null default now(), updated_by uuid
);
alter table public.web_pickup_points enable row level security;
revoke all on public.web_pickup_points from public, anon, authenticated;
grant select on public.web_pickup_points to authenticated;
drop policy if exists web_pickup_owner_read on public.web_pickup_points;
create policy web_pickup_owner_read on public.web_pickup_points for select to authenticated using (public.is_owner());

create table if not exists public.web_zones (
  id int generated always as identity primary key,
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  charge numeric not null check (charge >= 0 and charge <= 100000),
  min_order numeric not null default 0 check (min_order >= 0 and min_order <= 1000000000),
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), updated_by uuid
);
alter table public.web_zones enable row level security;
revoke all on public.web_zones from public, anon, authenticated;
grant select on public.web_zones to authenticated;
drop policy if exists web_zones_owner_read on public.web_zones;
create policy web_zones_owner_read on public.web_zones for select to authenticated using (public.is_owner());
drop trigger if exists web_zones_no_delete on public.web_zones;
create trigger web_zones_no_delete before delete on public.web_zones for each row execute function public.no_hard_delete();
drop trigger if exists audit_web_zones on public.web_zones;
create trigger audit_web_zones after insert or update on public.web_zones for each row execute function public.log_change('id');

-- ---------- 4. closures ----------
create table if not exists public.web_closures (
  day date primary key,
  note_bn text check (note_bn is null or char_length(note_bn) <= 120),
  note_en text check (note_en is null or char_length(note_en) <= 120),
  reopened boolean not null default false,            -- nothing is deleted: a closure is reopened, not removed
  created_by uuid, created_at timestamptz not null default now()
);
alter table public.web_closures enable row level security;
revoke all on public.web_closures from public, anon, authenticated;
grant select on public.web_closures to authenticated;
drop policy if exists web_closures_owner_read on public.web_closures;
create policy web_closures_owner_read on public.web_closures for select to authenticated using (public.is_owner());
drop trigger if exists web_closures_no_delete on public.web_closures;
create trigger web_closures_no_delete before delete on public.web_closures for each row execute function public.no_hard_delete();

-- stock holds (hard reservation): written by phase 491 checkout; read here so the catalogue shows the true free quantity.
create table if not exists public.web_stock_holds (
  id bigint generated always as identity primary key,
  submission uuid not null, order_id uuid references public.online_orders(id),
  item_id uuid not null references public.items(id), location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0 and qty <= 1000000),
  state text not null default 'held' check (state in ('held', 'released', 'consumed')),
  expires_at timestamptz not null, created_at timestamptz not null default now(), closed_at timestamptz, close_note text
);
create index if not exists web_stock_holds_live on public.web_stock_holds (item_id, location_id, state, expires_at);
create unique index if not exists web_stock_holds_one on public.web_stock_holds (submission, item_id);
alter table public.web_stock_holds enable row level security;
revoke all on public.web_stock_holds from public, anon, authenticated;
grant select on public.web_stock_holds to authenticated;
drop policy if exists web_stock_holds_owner_read on public.web_stock_holds;
create policy web_stock_holds_owner_read on public.web_stock_holds for select to authenticated using (public.is_owner());
drop trigger if exists web_stock_holds_no_delete on public.web_stock_holds;
create trigger web_stock_holds_no_delete before delete on public.web_stock_holds for each row execute function public.no_hard_delete();

-- ---------- helpers ----------
-- availability of one item for the web (never the number): auto = from stock at the web branch minus live holds
create or replace function public._web_avail(p_item uuid, p_loc int) returns text
language plpgsql stable security definer set search_path = public as $$
declare p public.web_item_pub; it public.items; q numeric; held numeric := 0; th numeric := coalesce(public.rule_num('website_stock_threshold'), 5);
begin
  select * into p from public.web_item_pub where item_id = p_item;
  if not found then return 'hidden'; end if;
  if p.avail_mode = 'sold_out' then return 'sold_out'; end if;
  if p.avail_mode = 'preorder' then return 'preorder'; end if;
  select * into it from public.items where id = p_item;
  if not it.tracked then return 'in_stock'; end if;
  select coalesce(sb.qty, 0) into q from public.stock_balance sb where sb.item_id = p_item and sb.location_id = p_loc;
  q := coalesce(q, 0);
  if public.rule_on('website_reserve_on') then
    select coalesce(sum(h.qty), 0) into held from public.web_stock_holds h
     where h.item_id = p_item and h.location_id = p_loc and h.state = 'held' and h.expires_at > now();
  end if;
  q := q - held;
  if q <= 0 then
    return case when coalesce(p.lead_days, 0) > 0 and public.rule_on('website_festival_mode_on') then 'preorder' else 'sold_out' end;
  end if;
  return case when q <= th then 'limited' else 'in_stock' end;
end $$;

-- ---------- 5. PUBLIC READ RPCs (anon may call these) ----------
create or replace function public.web_site_config() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int := coalesce(public.rule_num('website_location_id'), 0)::int;
begin
  if not public.rule_on('website_on') then return jsonb_build_object('on', false); end if;
  return jsonb_build_object(
    'on', true,
    'brand', jsonb_build_object('bn', public.rule_txt('website_brand_bn'), 'en', public.rule_txt('website_brand_en')),
    'whatsapp', nullif(public.rule_txt('website_whatsapp'), ''),
    'public_url', nullif(public.rule_txt('website_public_url'), ''),
    'orders_open', loc > 0,
    'holiday', jsonb_build_object('bn', nullif(public.rule_txt('website_holiday_text_bn'), ''), 'en', nullif(public.rule_txt('website_holiday_text_en'), '')),
    'closed_today', exists (select 1 from public.web_closures c where c.day = public._dhaka_today() and not c.reopened),
    'closures', coalesce((select jsonb_agg(jsonb_build_object('day', c.day, 'bn', c.note_bn, 'en', c.note_en) order by c.day)
                          from public.web_closures c where c.day between public._dhaka_today() and public._dhaka_today() + 60 and not c.reopened), '[]'::jsonb),
    'min_order', coalesce(public.rule_num('website_min_order'), 0),
    'cutoff_hour', coalesce(public.rule_num('website_cutoff_hour'), 0),
    'lead_days', coalesce(public.rule_num('website_lead_days'), 0),
    'festival', public.rule_on('website_festival_mode_on'),
    'payments', jsonb_build_object('cod', public.rule_on('website_pay_cod_on'),
                                   'manual', public.rule_on('website_pay_manual_on') and nullif(public.rule_txt('website_pay_mobile_number'), '') is not null,
                                   'manual_number', case when public.rule_on('website_pay_manual_on') then nullif(public.rule_txt('website_pay_mobile_number'), '') end),
    'policies', jsonb_build_object(
       'privacy', jsonb_build_object('bn', public.rule_txt('website_policy_privacy_bn'), 'en', public.rule_txt('website_policy_privacy_en')),
       'terms', jsonb_build_object('bn', public.rule_txt('website_policy_terms_bn'), 'en', public.rule_txt('website_policy_terms_en')),
       'refund', jsonb_build_object('bn', public.rule_txt('website_policy_refund_bn'), 'en', public.rule_txt('website_policy_refund_en'))),
    'messenger', nullif(public.rule_txt('website_messenger_url'), ''),
    'custom_cake', public.rule_on('website_custom_cake_on'),
    'analytics', jsonb_build_object('pixel_id', nullif(public.rule_txt('website_pixel_id'), ''), 'ga_id', nullif(public.rule_txt('website_ga_id'), '')),
    'pickup', coalesce((select jsonb_agg(jsonb_build_object('id', p.location_id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'hours_bn', p.hours_bn, 'hours_en', p.hours_en, 'address', p.address_public)
                                          order by l.sort)
                        from public.web_pickup_points p join public.locations l on l.id = p.location_id where p.public and l.is_active), '[]'::jsonb),
    'zones', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'name_bn', z.name_bn, 'name_en', z.name_en, 'charge', z.charge, 'min_order', z.min_order) order by z.sort, z.id)
                       from public.web_zones z where z.active), '[]'::jsonb));
end $$;

create or replace function public.web_catalog_v2(p_category text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int := coalesce(public.rule_num('website_location_id'), 0)::int;
begin
  if not public.rule_on('website_on') then return jsonb_build_object('on', false, 'items', '[]'::jsonb); end if;
  return jsonb_build_object('on', true, 'items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', i.id, 'name_bn', coalesce(p.name_bn, i.name_bn), 'name_en', coalesce(p.name_en, i.name_en),
      'description_bn', p.desc_bn, 'description_en', p.desc_en,
      'category', coalesce(p.category_pub, 'other'), 'category_sort', p.category_sort,
      'unit', i.unit, 'price', i.sell_price, 'availability', public._web_avail(i.id, loc),
      'lead_days', p.lead_days, 'allergens', p.allergens, 'diet', to_jsonb(p.diet),
      'images', coalesce((select jsonb_agg(im.storage_path order by im.sort, im.id) from public.web_item_images im where im.item_id = i.id and im.approved), '[]'::jsonb)
    ) order by p.category_sort, p.sort, coalesce(p.name_bn, i.name_bn))
    from public.web_item_pub p join public.items i on i.id = p.item_id
    where p.published and i.is_active and i.sellable and not i.hidden and i.retired_at is null and i.sell_price is not null
      and (p_category is null or p.category_pub = p_category)
  ), '[]'::jsonb));
end $$;

-- re-prices a cart on the server. The browser sends item ids and quantities only.
create or replace function public.web_quote(p_lines jsonb, p_zone int default null, p_mode text default 'pickup') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int := coalesce(public.rule_num('website_location_id'), 0)::int; ln jsonb; it public.items; q numeric; sub numeric := 0; out jsonb := '[]'; z public.web_zones; chg numeric := 0; problems jsonb := '[]';
  av text;
begin
  if not public.rule_on('website_on') then return jsonb_build_object('ok', false, 'error', 'off'); end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 1 and 100 then return jsonb_build_object('ok', false, 'error', 'no_lines'); end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    begin q := (ln->>'qty')::numeric; exception when others then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end;
    if q is null or q <= 0 or q > 1000 or q <> trunc(q) then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
    if coalesce(ln->>'item_id', '') !~ '^[0-9a-fA-F-]{36}$' then return jsonb_build_object('ok', false, 'error', 'item_unavailable'); end if;
    select i.* into it from public.items i join public.web_item_pub p on p.item_id = i.id where i.id = (ln->>'item_id')::uuid and p.published;
    if not found or it.id is null or not it.is_active or not it.sellable or it.hidden or it.retired_at is not null or it.sell_price is null then
      return jsonb_build_object('ok', false, 'error', 'item_unavailable', 'item_id', ln->>'item_id');
    end if;
    av := public._web_avail(it.id, loc);
    if av in ('sold_out', 'hidden') then problems := problems || jsonb_build_array(jsonb_build_object('item_id', it.id, 'availability', av)); end if;
    out := out || jsonb_build_object('item_id', it.id, 'qty', q, 'price', it.sell_price, 'amount', round(q * it.sell_price, 2));
    sub := sub + round(q * it.sell_price, 2);
  end loop;
  if p_mode = 'home' then
    select * into z from public.web_zones where id = p_zone and active;
    if not found then return jsonb_build_object('ok', false, 'error', 'zone_required', 'subtotal', sub); end if;
    if sub < z.min_order then return jsonb_build_object('ok', false, 'error', 'below_zone_min', 'min_order', z.min_order, 'subtotal', sub); end if;
    chg := z.charge;
  elsif p_mode <> 'pickup' then
    return jsonb_build_object('ok', false, 'error', 'bad_mode');
  end if;
  if sub < coalesce(public.rule_num('website_min_order'), 0) then
    return jsonb_build_object('ok', false, 'error', 'below_min_order', 'min_order', public.rule_num('website_min_order'), 'subtotal', sub);
  end if;
  return jsonb_build_object('ok', true, 'lines', out, 'subtotal', sub, 'delivery_charge', chg, 'total', sub + chg, 'problems', problems);
end $$;

-- ---------- grants: anon sees ONLY these three public reads ----------
revoke all on function public.web_site_config(), public.web_catalog_v2(text), public.web_quote(jsonb, int, text), public._web_avail(uuid, int) from public, anon, authenticated;
grant execute on function public.web_site_config(), public.web_catalog_v2(text), public.web_quote(jsonb, int, text) to anon, authenticated;

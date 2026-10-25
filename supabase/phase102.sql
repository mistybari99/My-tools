-- ============================================================
-- Phase 102 (bos102) - STEP Img: item photos on the item cards / pickers. Owner option, DEFAULT = today's behaviour (off).
--   Needs phases 72..98 (guard below). Canonical order: ... phase524, phase525, (phase100, phase101 in their own steps), phase102. Additive + paste-twice safe.
--   Nothing existing is re-created (no function of phases 72..101 is touched). Strictly a display option: no sale, stock, price, journal or permission changes.
--   rule item_images_mode           off (DEFAULT = today) | pos_only (POS item cards only) | everywhere (POS + item pickers / lists)
--   rule item_images_thumb_only     on (recommended) | off : load the small thumbnail (<path>.t.jpg) when it exists, else the original
--   rule item_images_cache_hours    number the OWNER types (blank = keep signed links / pictures for the session only)
--   rows in setup_rec_defs81 (advisory; ON CONFLICT DO NOTHING). Recommendation: item_images_mode = pos_only (see the reason text), thumb_only = on, cache hours = none.
--   RPC items_first_image(item_ids uuid[]) -> (item_id, path): first photo path only, SECURITY INVOKER so the items row policy / grants apply exactly as for a select on items.
--     No cost, price or stock column is returned. At most 500 ids per call.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.set_doc_template(text,text,integer)'), ('94', 'public._scan_photo_ok(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.drawer_events') is null then miss := miss || ' 95'; end if;
  if to_regclass('public.opening_stock_actions96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos98%' then miss := miss || ' 98'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)') is null
     or pg_get_functiondef('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure) not like '%bos72%' then miss := miss || ' 79'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is not null
     and pg_get_functiondef('public._cogs_lines72(date,date,integer[])'::regprocedure) not like '%bos89%' then miss := miss || ' 89'; end if;
  if miss <> '' then
    raise exception 'phase102 needs phases 72..98 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('item_images_mode', 'pos', 'choice', '"off"', null, '["off","pos_only","everywhere"]'::jsonb, null, null,
  'আইটেমের ছবি দেখানো', 'Item এর photo দেখানো', 'Show item photos',
  'off = আজকের নিয়ম (ছবি শুধু আইটেম ফর্মে)। pos_only = শুধু POS-এর আইটেম কার্ডে। everywhere = POS ও সব আইটেম বাছাই/তালিকায়। ছবি না থাকলে নামের প্রথম অক্ষর দেখায়।',
  'off = today (photos only in the item form). pos_only = POS item cards only. everywhere = POS and every item picker / list. An item without a photo shows its first letter.', 661),
 ('item_images_thumb_only', 'pos', 'choice', '"on"', null, '["on","off"]'::jsonb, null, null,
  'ছোট thumbnail আগে লোড', 'ছোট thumbnail আগে load', 'Load the small thumbnail first',
  'on = নতুন তোলা ছবির ছোট কপি থাকলে সেটাই লোড হয় (কম data)। ছোট কপি না থাকলে আসল ছবি। off = সবসময় আসল ছবি।',
  'on = when a photo has a small copy (uploaded with it) only that is loaded (less data). Without a small copy the original is used. off = always the original.', 662),
 ('item_images_cache_hours', 'pos', 'number', null, 'ঘণ্টা', null, 1, 720, 'ছবির link/cache কত ঘণ্টা রাখবে', 'Photo link/cache কত ঘণ্টা রাখবে', 'Hours to keep photo links and pictures',
  'আপনি লিখবেন; ফাঁকা = শুধু এই সেশন। বেশি ঘণ্টা দিলে ধীর নেটে বা অফলাইনে ছবি আসে, কিন্তু বদলানো ছবি দেরিতে দেখা যায়। ১ ঘণ্টার বেশি দিলেও সাইন করা link সর্বোচ্চ ১ ঘণ্টা চলে; ছবির নিজস্ব কপি এই সময় ধরে থাকে।',
  'You type it; blank = this session only. A longer time helps on slow data or offline, but a changed photo shows later. Signed links themselves last at most 1 hour; the picture copy is kept for this time.', 663)
 on conflict (key) do nothing;

-- ---------- first image path of many items (one round trip instead of full item rows) ----------
create or replace function public.items_first_image(item_ids uuid[]) returns table (item_id uuid, path text)
language sql stable security invoker set search_path = public as $$
  select i.id, i.images[1] from public.items i
   where i.id = any(item_ids) and coalesce(array_length(item_ids, 1), 0) <= 500
     and coalesce(array_length(i.images, 1), 0) > 0 and i.images[1] is not null and i.images[1] <> ''
$$;
revoke all on function public.items_first_image(uuid[]) from public, anon;
grant execute on function public.items_first_image(uuid[]) to authenticated;

-- ---------- setup advisor rows (advisory only) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('item_images_mode', '102', 'pos', '"pos_only"'::jsonb, '{}'::text[],
  'ছবি ডেটা খরচ করে। POS-এ ছবি থাকলে ব্যস্ত সময়ে ঠিক আইটেম চেনা সহজ, আর কার্ডের সংখ্যা সীমিত; তাই pos_only সুপারিশ। everywhere দিলে লম্বা তালিকায় অনেক ছবি লোড হয়, ধীর মোবাইল নেটে খরচ বাড়ে। মোবাইল নেট ভালো হলে পরে everywhere দিতে পারেন।',
  'Photo data খরচ করে। POS-এ photo থাকলে busy সময়ে ঠিক item চেনা সহজ, আর card এর সংখ্যা সীমিত; তাই pos_only recommend। everywhere দিলে লম্বা list এ অনেক photo load হয়, slow mobile data তে খরচ বাড়ে। Data ভালো হলে পরে everywhere দিতে পারেন।',
  'Photos use mobile data. On the POS a photo helps pick the right item in busy hours and the number of cards on screen is limited, so pos_only is recommended. Everywhere loads many pictures in long lists, which costs more on slow data. Switch to everywhere later if your data is good.', 361),
 ('item_images_thumb_only', '102', 'pos', '"on"'::jsonb, '{}'::text[],
  'ছোট কপি আসল ছবির চেয়ে অনেক কম data নেয়। যে ছবির ছোট কপি নেই তার আসল ছবিই আসে, তাই on রাখা নিরাপদ।',
  'ছোট copy আসল photo এর চেয়ে অনেক কম data নেয়। যে photo র ছোট copy নেই তার আসল photo ই আসে, তাই on রাখা safe।',
  'The small copy uses much less data than the original. A photo without a small copy falls back to the original, so on is safe.', 362),
 ('item_images_cache_hours', '102', 'pos', null::jsonb, '{}'::text[],
  'ঘণ্টা আপনার নেটের অবস্থার উপর নির্ভর করে, তাই কোনো মান ঠিক করে দেওয়া হয়নি। ফাঁকা = শুধু এই সেশন।',
  'ঘণ্টা আপনার net এর অবস্থার উপর নির্ভর করে, তাই কোনো value ঠিক করে দেওয়া হয়নি। ফাঁকা = শুধু এই session।',
  'The hours depend on your network, so no value is recommended. Blank = this session only.', 363)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
where to_regclass('public.setup_rec_defs81') is not null
on conflict do nothing;

-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase81.sql there and is already pasted on the live database under that name.
-- Renumbered to phase507.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 507 (bos81) - Step S2: RECOMMENDATIONS + ACTIVATION GUIDE ("চালু করার গাইড"). Run AFTER phase79 (phase506 is NOT needed).
-- Additive + idempotent (paste twice = no error). Strictly ADVISORY: nothing here blocks, changes or re-routes any sale, purchase, production,
-- journal or order. The only write path is the owner's own tap on "recommended apply".
--   1. setup_recommendations()      every rule / switch added in phases 72..79 (+ the base switches the guide needs) with the recommended value,
--                                   the reason (bn / mix / en), the current value and a status:
--                                     ok (already the recommended value) | recommended (not yet; one tap) | owner_chosen (the owner set another value: left alone)
--                                     | info (no value is recommended: the owner types it, or it needs an outside setup) | not_installed (rule row missing)
--                                   DATA-DRIVEN: rows live in setup_rec_defs81 (seeded additively with ON CONFLICT DO NOTHING). Later phases (e.g. phase506) add their
--                                   rules by plain INSERT into that table; a row whose rule does not exist yet is simply shown as not_installed.
--   2. setup_recommend_apply()      owner only. Applies the recommended value of the chosen codes (or all) through set_rule. NEVER overwrites a value the
--                                   owner already chose unless p_overwrite=true AND the code is named in p_codes. Rows whose readiness checks are not clean are
--                                   skipped (reason not_ready) unless p_ignore_ready=true. Idempotent by client id. Append-only trail + audit_log.
--   3. setup_readiness([topic])     "before you switch it on": checks per topic (stock tracking, accounting, production, cost sources, online orders).
--                                   Counts only - never an amount or a cost value (cost secrecy). Result is advice; the switch itself is never blocked.
--   4. setup_flow_check()           after a system is on: "does the data flow where it should?" (documents waiting to be posted, posting errors, negative stock,
--                                   productions with unknown cost, unseen messages, failed intakes, open order flags ...). Systems that are off show 'na'.
--   5. setup_apply_history()        the owner's own trail of what was applied.
-- No rule default, rate, limit or amount is changed or invented here. Numbers (rate limits, hours, tries) are shown as "keep the shipped default or type your own":
-- the recommendation for a number is always "info".
-- ============================================================

do $$ begin
  if to_regclass('public.sales_channels') is null or to_regclass('public.location_cost_attribution') is null or to_regclass('public.recipe_versions') is null
     or to_regclass('public.online_order_flags') is null then
    raise exception 'phase507 needs phases 72..79 pasted first';
  end if;
end $$;

-- ---------- tables ----------
-- the recommendation list (one row per rule); texts in 3 modes
create table if not exists public.setup_rec_defs81 (
  code text primary key,
  rule_key text not null,                     -- the row in public.rules this is about
  phase text not null,                        -- the phase that added the rule ('72'..'79', 'base' = older switch the guide needs)
  module text not null default 'general',
  rec_value jsonb,                            -- the recommended value; null = no value recommended (info only)
  ready_checks text[] not null default '{}',  -- check codes that should show 0 problems before the one-tap apply
  reason_bn text not null, reason_mix text, reason_en text not null,
  sort int not null default 0,
  active boolean not null default true
);
-- the readiness / flow checks (texts only; the counting lives in _setup_chk81)
create table if not exists public.setup_check_defs81 (
  code text primary key,
  topic text not null,
  kind text not null default 'ready' check (kind in ('ready', 'flow')),
  gate_rule text,                             -- flow checks apply only while this switch is on (null = always)
  level text not null default 'warn' check (level in ('warn', 'info')),
  label_bn text not null, label_mix text, label_en text not null,
  fix_bn text, fix_mix text, fix_en text,
  nav text,                                   -- web screen key that fixes it (optional)
  sort int not null default 0,
  active boolean not null default true
);
create table if not exists public.setup_topic_defs81 (
  topic text primary key,
  gate_rule text,                             -- the switch this topic prepares (null = no single switch)
  label_bn text not null, label_mix text, label_en text not null,
  sort int not null default 0
);
-- what the owner applied (append-only)
create table if not exists public.setup_apply_batches81 (
  client_id uuid primary key,
  applied_by uuid not null, applied_at timestamptz not null default now(),
  overwrite boolean not null default false, ignore_ready boolean not null default false,
  result jsonb not null
);
create table if not exists public.setup_apply_lines81 (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.setup_apply_batches81(client_id),
  code text not null, rule_key text not null,
  old_value jsonb,                            -- null = the rule had no own value (was on its default)
  new_value jsonb not null,
  overwrote boolean not null default false,   -- true only when the owner asked to replace a value he had chosen
  created_at timestamptz not null default now()
);
create or replace function public._setup_ro81() returns trigger language plpgsql as $$
begin raise exception 'append_only: the setup trail is never changed or deleted'; end $$;
drop trigger if exists setup_batches_ro81 on public.setup_apply_batches81;
create trigger setup_batches_ro81 before update or delete on public.setup_apply_batches81 for each row execute function public._setup_ro81();
drop trigger if exists setup_lines_ro81 on public.setup_apply_lines81;
create trigger setup_lines_ro81 before update or delete on public.setup_apply_lines81 for each row execute function public._setup_ro81();
drop trigger if exists audit_setup_batches81 on public.setup_apply_batches81;
create trigger audit_setup_batches81 after insert on public.setup_apply_batches81 for each row execute function public.log_change('client_id');

-- ---------- seed: topics ----------
insert into public.setup_topic_defs81 (topic, gate_rule, label_bn, label_mix, label_en, sort) values
 ('stock_tracking', null, 'স্টক ট্র্যাকিং চালু করার আগে', 'Stock tracking চালু করার আগে', 'Before you start stock tracking', 10),
 ('accounting', 'accounting_on', 'হিসাব (অ্যাকাউন্টিং) চালু করার আগে', 'Accounting চালু করার আগে', 'Before you switch accounting on', 20),
 ('production', null, 'উৎপাদন (production) শুরুর আগে', 'Production শুরুর আগে', 'Before you start production', 30),
 ('cost_sources', 'cost_attrib_in_pl', 'খরচের বিল ভাগ করার আগে', 'Cost bill ভাগ করার আগে', 'Before you split cost bills', 40),
 ('online', 'online_orders_on', 'অনলাইন অর্ডার ও মেসেজ চালুর আগে', 'Online order ও message চালুর আগে', 'Before you start online orders and messages', 50)
 on conflict (topic) do nothing;

-- ---------- seed: checks ----------
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort) values
 ('stk_tracked', 'stock_tracking', 'ready', null, 'warn', 'কোনো আইটেম "ট্র্যাক" করা নেই', 'কোনো item "tracked" করা নেই', 'No item is marked as tracked', 'যে আইটেমের স্টক গুনতে চান সেগুলো ট্র্যাক করুন', 'যে item এর stock গুনতে চান সেগুলো track করুন', 'Mark the items whose stock you want to count', 'items', 10),
 ('stk_unit', 'stock_tracking', 'ready', null, 'warn', 'ট্র্যাক করা আইটেমে বেস ইউনিট নেই', 'Tracked item এ base unit নেই', 'Tracked items without a base unit', 'প্রতিটি আইটেমের বেস ইউনিট বসান', 'প্রতিটি item এর base unit বসান', 'Set the base unit of each item', 'items', 11),
 ('stk_opening', 'stock_tracking', 'ready', null, 'warn', 'ট্র্যাক করা আইটেমের শুরুর স্টক (opening) তোলা হয়নি', 'Tracked item এর opening stock তোলা হয়নি', 'Tracked items with no opening stock entered', 'গুনে প্রতিটি জায়গার শুরুর স্টক তুলুন', 'গুনে প্রতিটি জায়গার opening stock তুলুন', 'Count and enter the opening stock of each place', 'stock', 12),
 ('stk_conv', 'stock_tracking', 'ready', null, 'warn', 'বিক্রির ইউনিটের রূপান্তর (conversion) নেই', 'Sell unit এর conversion নেই', 'Sell units with no unit conversion', 'কেজি/গ্রাম/পিস ইত্যাদির রূপান্তর বসান', 'কেজি/গ্রাম/পিস এর conversion বসান', 'Add the conversion between selling and base units', 'items', 13),
 ('stk_cost', 'stock_tracking', 'ready', null, 'warn', 'স্টক আছে কিন্তু খরচ জানা নেই (ফাঁকা বা ০ = অজানা)', 'Stock আছে কিন্তু cost জানা নেই (blank বা 0 = অজানা)', 'Items in stock whose cost is unknown (blank or 0 = unknown)', 'কেনা বা শুরুর দাম বসান; সত্যিই বিনা খরচ হলে আলাদা করে চিহ্নিত করুন', 'কেনা বা opening দাম বসান; সত্যিই free হলে আলাদা mark করুন', 'Enter the purchase or opening cost; mark a truly free item separately', 'costsources', 14),
 ('stk_neg', 'stock_tracking', 'ready', null, 'warn', 'মাইনাস স্টক আছে', 'Minus stock আছে', 'Negative stock balances exist', 'কেন মাইনাস হলো দেখে গুনে ঠিক করুন', 'কেন minus হলো দেখে count করে ঠিক করুন', 'Find out why and fix with a count', 'stock', 15),
 ('acc_start', 'accounting', 'ready', null, 'warn', 'হিসাব শুরুর তারিখ বসানো নেই', 'Accounting start date বসানো নেই', 'No accounting start date', 'শুরুর তারিখ বসান', 'Start date বসান', 'Set the start date', 'accounts', 20),
 ('acc_coa', 'accounting', 'ready', null, 'warn', 'অ্যাকাউন্টের তালিকা (chart) ফাঁকা', 'Chart of accounts ফাঁকা', 'The chart of accounts is empty', 'অ্যাকাউন্টের তালিকা তৈরি করুন', 'Chart of accounts তৈরি করুন', 'Create the chart of accounts', 'accounts', 21),
 ('acc_map', 'accounting', 'ready', null, 'warn', 'দরকারি অ্যাকাউন্ট ম্যাপিং নেই বা বন্ধ অ্যাকাউন্টে', 'দরকারি account mapping নেই বা বন্ধ account এ', 'Required account mappings missing or pointing to an inactive account', 'ম্যাপিং ঠিক করুন', 'Mapping ঠিক করুন', 'Fix the mappings', 'accounts', 22),
 ('acc_opening', 'accounting', 'ready', null, 'warn', 'শুরুর ব্যালান্স (opening entry) নেই', 'Opening balance entry নেই', 'No opening balance entry', 'শুরুর জের এন্ট্রি দিন', 'Opening balance entry দিন', 'Post the opening balances', 'accounts', 23),
 ('acc_wait', 'accounting', 'ready', null, 'info', 'কিছু কাগজ খরচ অজানা বলে অপেক্ষায় আছে', 'কিছু document cost অজানা বলে অপেক্ষায় আছে', 'Documents waiting because a cost is unknown', 'খরচ বসালে এগুলো নিজে থেকে ঢুকবে', 'Cost বসালে এগুলো নিজে থেকে ঢুকবে', 'They post by themselves once the cost is entered', 'accounts', 24),
 ('acc_err', 'accounting', 'ready', null, 'warn', 'অটো-পোস্টে ভুল জমে আছে', 'Autopost এ error জমে আছে', 'Auto-posting errors are waiting', 'ভুলের তালিকা দেখে ঠিক করুন', 'Error list দেখে ঠিক করুন', 'Open the error list and fix', 'accounts', 25),
 ('prd_recipes', 'production', 'ready', null, 'warn', 'কোনো চালু রেসিপি নেই', 'কোনো active recipe নেই', 'No active recipe', 'রেসিপি লিখুন', 'Recipe লিখুন', 'Write the recipes', 'recipes', 30),
 ('prd_lines', 'production', 'ready', null, 'warn', 'উপাদান ছাড়া রেসিপি', 'Ingredient ছাড়া recipe', 'Recipes with no ingredient line', 'উপাদান যোগ করুন', 'Ingredient যোগ করুন', 'Add the ingredients', 'recipes', 31),
 ('prd_yield', 'production', 'ready', null, 'warn', 'রেসিপির ফলন (yield) নেই', 'Recipe এর yield নেই', 'Recipes with no yield', 'এক ব্যাচে কত হয় বসান', 'এক batch এ কত হয় বসান', 'Enter what one batch makes', 'recipes', 32),
 ('prd_approve', 'production', 'ready', null, 'info', 'অনুমোদন (approve) হয়নি এমন রেসিপি', 'Approve হয়নি এমন recipe', 'Recipes not approved yet', 'মালিক নিজে বা অনুমতি পাওয়া কেউ অনুমোদন দিন', 'Owner নিজে বা অনুমতি পাওয়া কেউ approve করুন', 'The owner or a person granted the right approves', 'recipebook', 33),
 ('prd_icost', 'production', 'ready', null, 'warn', 'উপাদানের খরচ অজানা (ফাঁকা বা ০)', 'Ingredient এর cost অজানা (blank বা 0)', 'Ingredients whose cost is unknown (blank or 0)', 'কেনা দাম বা শুরুর দাম বসান', 'কেনা দাম বা opening দাম বসান', 'Enter the purchase or opening cost', 'costing', 34),
 ('prd_unit', 'production', 'ready', null, 'warn', 'রেসিপির ইউনিটের রূপান্তর নেই', 'Recipe unit এর conversion নেই', 'Recipe lines whose unit has no conversion', 'রূপান্তর বসান', 'Conversion বসান', 'Add the conversion', 'items', 35),
 ('prd_conv', 'production', 'ready', null, 'warn', 'কারখানার খরচের পদ্ধতি অসম্পূর্ণ (pool-এ স্বাভাবিক মাসিক উৎপাদন নেই / recipe-এ খরচের ধরন নেই)', 'Factory cost method অসম্পূর্ণ (pool এ normal monthly output নেই / recipe এ cost component নেই)', 'Factory cost method incomplete (pool without normal monthly output / recipe mode without cost components)', 'অসম্পূর্ণ জায়গার তথ্য বসান', 'অসম্পূর্ণ জায়গার তথ্য বসান', 'Complete the missing figures for that place', 'costing', 36),
 ('cs_sources', 'cost_sources', 'ready', null, 'info', 'কোনো খরচের উৎস (বিল) বসানো নেই', 'কোনো cost source (bill) বসানো নেই', 'No cost source entered', 'বিদ্যুৎ, ভাড়া ইত্যাদির উৎস যোগ করুন', 'Electricity, rent ইত্যাদির source যোগ করুন', 'Add the sources such as electricity and rent', 'costsources', 40),
 ('cs_rule', 'cost_sources', 'ready', null, 'warn', 'অনুমোদিত ভাগের নিয়ম নেই এমন উৎস', 'Approved allocation rule নেই এমন source', 'Active sources with no approved allocation rule', 'ভাগের নিয়ম লিখে অন্য একজনকে দিয়ে অনুমোদন করান', 'Rule লিখে অন্য একজনকে দিয়ে approve করান', 'Write the rule and let another person approve it', 'costsources', 41),
 ('cs_attrib', 'cost_sources', 'ready', null, 'info', 'কোন খরচ কোন শোরুমের তা এখনো ঠিক করা নেই', 'কোন cost কোন showroom এর তা এখনো ঠিক করা নেই', 'No cost-to-showroom assignment yet', 'জায়গাভিত্তিক বরাদ্দ বসান', 'Place অনুযায়ী assignment বসান', 'Set the assignment per place', 'costattrib', 42),
 ('onl_channels', 'online', 'ready', null, 'warn', 'কোনো চালু বিক্রির চ্যানেল নেই', 'কোনো active sales channel নেই', 'No active sales channel', 'ওয়েব ফর্ম, ফোন, কাউন্টার চ্যানেল যোগ করুন', 'Web form, phone, walk-in channel যোগ করুন', 'Add the web form, phone and walk-in channels', 'inbox', 50),
 ('onl_url', 'online', 'ready', null, 'info', 'ওয়েব ফর্ম চালু কিন্তু পাবলিক ঠিকানা (URL) বসানো নেই', 'Web form on কিন্তু public URL বসানো নেই', 'Web form is on but the public URL is empty', 'ঠিকানা বসান (বাইরের সেটআপ লাগে)', 'URL বসান (বাইরের setup লাগে)', 'Enter the URL (needs an outside setup)', 'inbox', 51),
 ('onl_bot', 'online', 'ready', null, 'info', 'মেসেজ ইনটেক চালু কিন্তু কোনো চালু ইনটেক ইউজার নেই', 'Message intake on কিন্তু active intake user নেই', 'Message intake is on but no active intake user', 'ফোনে করা যায় না — আলাদা সেটআপ', 'Phone থেকে করা যায় না — আলাদা setup', 'Cannot be done from the phone - separate setup', null, 52),
 ('flw_acc_old', 'accounting', 'flow', 'accounting_on', 'warn', 'আগের দিনের কাগজ এখনো হিসাবে ঢোকেনি', 'আগের দিনের document এখনো books এ ঢোকেনি', 'Documents from earlier days are not in the books yet', 'অটো-পোস্ট চালু আছে কিনা দেখুন; না হলে পেন্ডিং পোস্ট করুন', 'Autopost on আছে কিনা দেখুন; না হলে pending post করুন', 'Check autopost is on; otherwise post the pending list', 'accounts', 60),
 ('flw_acc_err', 'accounting', 'flow', 'accounting_on', 'warn', 'অটো-পোস্টে ভুল জমে আছে', 'Autopost এ error জমে আছে', 'Auto-posting errors are waiting', 'ভুলের তালিকা দেখুন', 'Error list দেখুন', 'Open the error list', 'accounts', 61),
 ('flw_acc_wait', 'accounting', 'flow', 'accounting_on', 'info', 'খরচ অজানা বলে কাগজ অপেক্ষায়', 'Cost অজানা বলে document অপেক্ষায়', 'Documents waiting for a cost', 'খরচ বসালে ঢুকবে', 'Cost বসালে ঢুকবে', 'They post once the cost is entered', 'accounts', 62),
 ('flw_neg', 'stock_tracking', 'flow', null, 'warn', 'মাইনাস স্টক আছে', 'Minus stock আছে', 'Negative stock balances exist', 'কারণ খুঁজে গুনে ঠিক করুন', 'কারণ খুঁজে count করে ঠিক করুন', 'Find the reason and fix with a count', 'stock', 63),
 ('flw_prod_cost', 'production', 'flow', null, 'warn', 'খরচ অসম্পূর্ণ রেখে হওয়া উৎপাদন', 'Cost অসম্পূর্ণ রেখে হওয়া production', 'Productions made with an incomplete cost', 'অজানা খরচ বসান', 'অজানা cost বসান', 'Enter the unknown costs', 'costing', 64),
 ('flw_inbox_new', 'online', 'flow', 'inbox_on', 'warn', 'আগের দিনের মেসেজ এখনো দেখা হয়নি', 'আগের দিনের message এখনো দেখা হয়নি', 'Messages from earlier days not seen yet', 'ইনবক্স খুলে দেখুন', 'Inbox খুলে দেখুন', 'Open the inbox', 'inbox', 65),
 ('flw_inbox_silent', 'online', 'flow', 'inbox_on', 'warn', 'নির্ধারিত সময়ের বেশি কোনো মেসেজ আসেনি (সংযোগ ঠিক আছে তো?)', 'নির্ধারিত সময়ের বেশি কোনো message আসেনি (connection ঠিক আছে তো?)', 'No message for longer than the set silence hours (is the connection fine?)', 'সংযোগ পরীক্ষা করুন', 'Connection check করুন', 'Check the connection', 'inbox', 66),
 ('flw_intake_fail', 'online', 'flow', 'inbox_on', 'warn', 'ইনটেক ব্যর্থ হয়ে আছে', 'Intake fail হয়ে আছে', 'Failed intakes are waiting', 'ব্যর্থ তালিকা দেখুন', 'Failed list দেখুন', 'Open the failed list', 'inbox', 67),
 ('flw_oo_flags', 'online', 'flow', 'online_orders_on', 'warn', 'অনলাইন অর্ডারের খোলা ফ্ল্যাগ (বাতিল বিক্রি) আছে', 'Online order এর open flag (voided sale) আছে', 'Open online-order flags (voided sale)', 'ফ্ল্যাগ দেখে রিভিউ করুন', 'Flag দেখে review করুন', 'Review the flags', 'onlineorders', 68),
 ('flw_pool', 'production', 'flow', null, 'warn', 'pool পদ্ধতির জায়গায় এই মাসের খরচ বসানো নেই', 'Pool method এর জায়গায় এই মাসের cost বসানো নেই', 'Pool-method places with no pool figures this month', 'এই মাসের খরচ বসান', 'এই মাসের cost বসান', 'Enter this month''s figures', 'costing', 69)
 on conflict (code) do nothing;

-- ---------- seed: recommendations (one row per rule) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('production_requires_cost', 'production_requires_cost', '72', 'stock', '"refuse"', '{prd_icost}',
  'কোনো উপাদানের খরচ অজানা থাকলে উৎপাদন আটকে যাবে, তাই ভুল বা শূন্য খরচের মাল তৈরি হবে না। সব উপাদানের খরচ বসানোর পরই চালু করা ভালো; তার আগে "সতর্কতা" (warn) থাকুক।',
  'কোনো ingredient এর cost অজানা থাকলে production আটকে যাবে, তাই ভুল বা শূন্য cost এর মাল তৈরি হবে না। সব ingredient এর cost বসানোর পরই চালু করা ভালো; তার আগে warn থাকুক।',
  'Production stops when an ingredient cost is unknown, so goods are never made at a wrong or zero cost. Switch to refuse only after every ingredient cost is entered; until then keep warn.', 10),
 ('accounting_on', 'accounting_on', 'base', 'books', 'true', '{acc_start,acc_coa,acc_map,acc_opening,stk_opening}',
  'হিসাব চালু করলে বিক্রি, ক্রয়, উৎপাদন নিজে থেকে খাতায় ঢোকে। শুরুর তারিখ, অ্যাকাউন্ট ম্যাপিং, শুরুর ব্যালান্স ও শুরুর স্টক ঠিক হলে তবেই চালু করুন। কখন চালু হবে সেটা মালিকের সিদ্ধান্ত।',
  'Accounting on করলে sale, purchase, production নিজে থেকে books এ ঢোকে। Start date, account mapping, opening balance ও opening stock ঠিক হলে তবেই on করুন। কখন on হবে সেটা owner এর সিদ্ধান্ত।',
  'With accounting on, sales, purchases and production post to the books by themselves. Switch on only when the start date, account mappings, opening balances and opening stock are in place. When to start is the owner''s decision.', 20),
 ('accounting_autopost', 'accounting_autopost', '72', 'books', 'true', '{}',
  'অটো-পোস্ট চালু থাকলে আজকের কাগজ হাতে পোস্ট করতে হয় না এবং "পেন্ডিং" জমে না।',
  'Autopost on থাকলে আজকের document হাতে post করতে হয় না এবং pending জমে না।',
  'With autopost on nobody has to post documents by hand and nothing piles up as pending.', 21),
 ('reports_net_of_returns', 'reports_net_of_returns', '72', 'reports', 'true', '{}',
  'ফেরত বাদ দিয়ে রিপোর্ট দেখালে বিক্রি ও লাভ বাস্তবের কাছাকাছি থাকে।',
  'Return বাদ দিয়ে report দেখালে sale ও profit বাস্তবের কাছাকাছি থাকে।',
  'Reports net of returns keep sales and profit close to what really happened.', 22),
 ('recipe_approval_required', 'recipe_approval_required', '73', 'stock', '"warn"', '{}',
  'অনুমোদনের আগে রেসিপি ব্যবহার হলে হলুদ সতর্কতা দেখায় কিন্তু কাজ আটকায় না। মালিক চাইলে নিজে অনুমোদন দিতে পারেন বা অন্যকে অনুমতি দিতে পারেন; পরে চাইলে "on" (আটকানো) করা যায়।',
  'Approve এর আগে recipe ব্যবহার হলে yellow warning দেখায় কিন্তু কাজ আটকায় না। Owner চাইলে নিজে approve করতে পারেন বা অন্যকে অনুমতি দিতে পারেন; পরে চাইলে on (আটকানো) করা যায়।',
  'A recipe used before approval shows a yellow warning and nothing is blocked. The owner may approve himself or grant the right to another person; later you may switch to on (refuse).', 30),
 ('recipe_self_approve', 'recipe_self_approve', '73', 'stock', 'false', '{}',
  'যে রেসিপি বদলায় সে নিজে অনুমোদন না দিলে ভুল ধরা পড়ার সুযোগ থাকে। মালিক সবসময় নিজে অনুমোদন দিতে পারেন।',
  'যে recipe বদলায় সে নিজে approve না দিলে ভুল ধরা পড়ার সুযোগ থাকে। Owner সবসময় নিজে approve দিতে পারেন।',
  'When the person who changed a recipe cannot approve it, mistakes get caught. The owner can always approve himself.', 31),
 ('artisan_self_view', 'artisan_self_view', '73', 'stock', 'false', '{}',
  'কারিগরদের নিজস্ব লগইন হওয়ার পর শুধু নিজের রেসিপি দেখানোর জন্য চালু করুন; তার আগে বন্ধ থাকুক।',
  'Artisan দের নিজস্ব login হওয়ার পর শুধু নিজের recipe দেখানোর জন্য on করুন; তার আগে off থাকুক।',
  'Switch on to show an artisan only his own recipes after artisans have their own logins; keep off until then.', 32),
 ('production_manual_needs_reason', 'production_manual_needs_reason', '74', 'stock', 'true', '{}',
  'রেসিপি ছাড়া সরাসরি উৎপাদন তোলার সময় কারণ লিখতে বললে হাতে-তোলা এন্ট্রি ধরা সহজ হয়।',
  'Recipe ছাড়া direct production তোলার সময় reason লিখতে বললে হাতে-তোলা entry ধরা সহজ হয়।',
  'Asking for a reason on a direct production-in makes hand-typed entries easy to trace.', 33),
 ('production_requires_recipe', 'production_requires_recipe', '74', 'stock', null, '{}',
  'কে কীভাবে উৎপাদন তুলবে তা মালিক মাঠের অবস্থা দেখে ঠিক করবেন; কোনো মান প্রস্তাব করা হয়নি।',
  'কে কীভাবে production তুলবে তা owner মাঠের অবস্থা দেখে ঠিক করবেন; কোনো value প্রস্তাব করা হয়নি।',
  'Who records production and how is the owner''s call in the field; no value is recommended.', 34),
 ('recipe_waste_required', 'recipe_waste_required', '73', 'stock', null, '{}',
  'অপচয়ের শতাংশ বাধ্যতামূলক করা হবে কিনা মালিক ঠিক করবেন; কোনো মান প্রস্তাব করা হয়নি।',
  'Waste % বাধ্যতামূলক করা হবে কিনা owner ঠিক করবেন; কোনো value প্রস্তাব করা হয়নি।',
  'Whether the waste percentage is mandatory is the owner''s call; no value is recommended.', 35),
 ('cost_gap_warn_pct', 'cost_gap_warn_pct', '74', 'stock', null, '{}',
  'আজকের কেনা দামের সঙ্গে গড় খরচের ফারাকের সীমা প্রথম কিছু বাস্তব কেনার পর মালিক নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'আজকের কেনা দাম আর average cost এর ফারাকের limit প্রথম কিছু বাস্তব কেনার পর owner নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'The owner types the gap limit between today''s purchase price and the average cost after the first real purchases. No number is recommended.', 36),
 ('yield_variance_warn_pct', 'yield_variance_warn_pct', '74', 'stock', null, '{}',
  'রেসিপির ফলন আর আসল ফলনের ফারাকের সীমা কিছু বাস্তব উৎপাদনের পর মালিক নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Recipe yield আর actual yield এর ফারাকের limit কিছু বাস্তব production এর পর owner নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'The owner types the limit for the gap between recipe yield and actual yield after some real productions. No number is recommended.', 37),
 ('cost_rule_self_approve', 'cost_rule_self_approve', '75', 'stock', 'false', '{}',
  'যে ভাগের নিয়ম লিখেছে সে নিজে অনুমোদন না দিলে ভুল ধরা পড়ে। অন্য একজনকে অনুমোদনের অনুমতি দিন।',
  'যে allocation rule লিখেছে সে নিজে approve না দিলে ভুল ধরা পড়ে। অন্য একজনকে approve এর অনুমতি দিন।',
  'When the person who wrote an allocation rule cannot approve it, errors get caught. Grant the approval right to another person.', 40),
 ('cost_attrib_in_pl', 'cost_attrib_in_pl', '78', 'stock', 'true', '{cs_attrib}',
  'শোরুম ও অ্যাডমিন খরচের ভাগ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখায়। কোন খরচ কোন শোরুমের তা বসানোর পর চালু করুন।',
  'Showroom ও admin cost এর ভাগ branch P&L এ আলাদা row তে দেখায়। কোন cost কোন showroom এর তা বসানোর পর on করুন।',
  'Shows the showroom and admin cost shares as separate rows in the branch P&L. Switch on after the cost-to-showroom assignment is set.', 41),
 ('online_orders_on', 'online_orders_on', 'base', 'pos', 'true', '{onl_channels}',
  'অনলাইন অর্ডারের খাতা চালু রাখুন: ওয়েব ফর্ম, ফোন ও কাউন্টার দিয়ে শুরু করা সহজ।',
  'Online order এর খাতা on রাখুন: web form, phone ও walk-in দিয়ে শুরু করা সহজ।',
  'Keep the online-order book on; the web form, phone and walk-in are the easy way to start.', 50),
 ('inbox_on', 'inbox_on', '76', 'pos', 'true', '{onl_channels}',
  'সব বার্তা এক জায়গায় দেখতে ইনবক্স চালু রাখুন। ওয়েব ফর্ম, ফোন ও কাউন্টার দিয়ে শুরু করুন।',
  'সব message এক জায়গায় দেখতে inbox on রাখুন। Web form, phone ও walk-in দিয়ে শুরু করুন।',
  'Keep the inbox on to see every message in one place. Start with the web form, phone and walk-in.', 51),
 ('web_form_on', 'web_form_on', '76', 'pos', 'true', '{onl_channels}',
  'ওয়েব ফর্ম থেকে অর্ডার নিতে চালু করুন। দাম সার্ভারে ঠিক হয়, ডুপ্লিকেট আটকানো থাকে। পাবলিক ঠিকানা বসানো বাইরের সেটআপ।',
  'Web form থেকে order নিতে on করুন। দাম server এ ঠিক হয়, duplicate আটকানো থাকে। Public URL বসানো বাইরের setup।',
  'Switch on to take orders from the web form. Prices are fixed on the server and duplicates are caught. The public URL is an outside setup.', 52),
 ('meta_intake_on', 'meta_intake_on', '76', 'pos', 'false', '{}',
  'Messenger, Instagram, WhatsApp-এর সংযোগ না হওয়া পর্যন্ত বন্ধ থাকুক। সংযোগ ফোন থেকে করা যায় না, আলাদা সেটআপ লাগে।',
  'Messenger, Instagram, WhatsApp এর connection না হওয়া পর্যন্ত off থাকুক। Connection phone থেকে করা যায় না, আলাদা setup লাগে।',
  'Keep Messenger, Instagram and WhatsApp off until the connection exists. The connection cannot be made from the phone; it is a separate setup.', 53),
 ('inbox_autodraft_on', 'inbox_autodraft_on', '76', 'pos', 'false', '{}',
  'মেসেজ থেকে অর্ডারের খসড়া নিজে নিজে হওয়া শুরুতে বন্ধ থাকুক; প্রথমে স্টাফ হাতে যাচাই করুক।',
  'Message থেকে order draft নিজে নিজে হওয়া শুরুতে off থাকুক; প্রথমে staff হাতে check করুক।',
  'Keep automatic order drafts from messages off at the start; staff check them by hand first.', 54),
 ('inbox_pii_guard_on', 'inbox_pii_guard_on', '76', 'pos', 'true', '{}',
  'গ্রাহকের ফোন ও ঠিকানা শুধু অনুমতি পাওয়া মানুষ দেখবে; প্রতিটি দেখা লগে থাকে। অনুমতি দিন সেই শাখার বিক্রয়কর্মী ও মালিককে।',
  'Customer এর phone ও address শুধু অনুমতি পাওয়া মানুষ দেখবে; প্রতিটি দেখা log এ থাকে। অনুমতি দিন সেই branch এর POS staff ও owner কে।',
  'Customer phone and address are seen only by authorised people, and every view is logged. Grant the right to the POS staff of that branch and to the owner.', 55),
 ('web_form_captcha_on', 'web_form_captcha_on', '76', 'pos', null, '{}',
  'ক্যাপচা চালাতে বাইরের চাবি লাগে (ফোন থেকে করা যায় না)। সেটআপ হলে মালিক চালু করবেন।',
  'Captcha চালাতে বাইরের key লাগে (phone থেকে করা যায় না)। Setup হলে owner on করবেন।',
  'The captcha needs an outside key (not possible from the phone). The owner switches it on once that is set up.', 56),
 ('web_form_rate_max', 'web_form_rate_max', '76', 'pos', null, '{}',
  'প্রতি ডিভাইসে সর্বোচ্চ ফর্ম সংখ্যা: দেওয়া সীমার ভেতরে নিজের সংখ্যা লিখুন, বা পাঠানো ডিফল্ট রাখুন। নতুন কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Per device max form সংখ্যা: দেওয়া range এর ভেতরে নিজের সংখ্যা লিখুন, বা shipped default রাখুন। নতুন কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Maximum forms per device: type your own number inside the shown range, or keep the shipped default. No new number is recommended.', 57),
 ('web_form_rate_window_min', 'web_form_rate_window_min', '76', 'pos', null, '{}',
  'ফর্ম সীমার সময়-জানালা: দেওয়া সীমার ভেতরে নিজের মান লিখুন, বা পাঠানো ডিফল্ট রাখুন।',
  'Form limit এর time window: দেওয়া range এর ভেতরে নিজের value লিখুন, বা shipped default রাখুন।',
  'Time window of the form limit: type your own value inside the shown range, or keep the shipped default.', 58),
 ('inbox_silence_hours', 'inbox_silence_hours', '76', 'pos', null, '{}',
  'কত ঘণ্টা মেসেজ না এলে সতর্ক করবে: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'কত ঘণ্টা message না এলে warn করবে: নিজের value লিখুন বা shipped default রাখুন।',
  'After how many hours without a message to warn: type your own value or keep the shipped default.', 59),
 ('intake_max_tries', 'intake_max_tries', '76', 'pos', null, '{}',
  'ব্যর্থ ইনটেক কয়বার আবার চেষ্টা হবে: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'Failed intake কয়বার retry হবে: নিজের value লিখুন বা shipped default রাখুন।',
  'How many times a failed intake is retried: type your own value or keep the shipped default.', 60),
 ('intake_retry_min', 'intake_retry_min', '76', 'pos', null, '{}',
  'আবার চেষ্টার মধ্যে কত মিনিট অপেক্ষা: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'Retry এর মধ্যে কত minute অপেক্ষা: নিজের value লিখুন বা shipped default রাখুন।',
  'Minutes to wait between retries: type your own value or keep the shipped default.', 61),
 ('web_form_public_url', 'web_form_public_url', '76', 'pos', null, '{}',
  'ওয়েব ফর্মের পাবলিক ঠিকানা বাইরের সেটআপ শেষ হলে বসবে; ফোন থেকে তৈরি করা যায় না।',
  'Web form এর public URL বাইরের setup শেষ হলে বসবে; phone থেকে তৈরি করা যায় না।',
  'The public URL of the web form is entered once the outside setup is done; it cannot be created from the phone.', 62),
 ('online_pack_warn_on', 'online_pack_warn_on', '77', 'pos', 'true', '{}',
  'প্যাক করার সময় স্টক কম থাকলে সতর্ক করে, কিন্তু কিছু আটকায় না।',
  'Pack করার সময় stock কম থাকলে warn করে, কিন্তু কিছু আটকায় না।',
  'Warns at pack time when stock is short; nothing is blocked.', 70),
 ('online_pack_reserve_on', 'online_pack_reserve_on', '77', 'pos', null, '{}',
  'প্যাক হওয়া অন্য অর্ডারের স্টক সতর্কতার হিসাব থেকে বাদ দেয় (কাউন্টার আটকায় না)। কোনো মান প্রস্তাব করা হয়নি — মালিক দেখে ঠিক করবেন।',
  'Packed অন্য order এর stock warning এর হিসাব থেকে বাদ দেয় (counter আটকায় না)। কোনো value প্রস্তাব করা হয়নি — owner দেখে ঠিক করবেন।',
  'Deducts the stock of other packed orders in the warning (the counter is not blocked). No value is recommended; the owner decides.', 71),
 ('online_keep_order_price', 'online_keep_order_price', '77', 'pos', 'true', '{}',
  'অর্ডারে যে দাম বলা হয়েছিল ডেলিভারিতে সেটাই থাকে; ভিন্ন দাম হলে ম্যানেজারের অনুমতি ও হলুদ এক্সেপশন লাগে।',
  'Order এ যে দাম বলা হয়েছিল delivery তে সেটাই থাকে; ভিন্ন দাম হলে manager এর approval ও yellow exception লাগে।',
  'The price quoted on the order is kept at delivery; a different price needs the manager''s approval and logs a yellow exception.', 72)
 on conflict (code) do nothing;

-- ---------- internal: one check -> {n problems, total, applies} (counts only, never amounts) ----------
create or replace function public._setup_chk81(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare n bigint := 0; tot bigint := 0; ap boolean := true; st date := public._acct_start(); td date := public._acct_today(); h numeric; last_in timestamptz;
        req text[] := array['sales', 'cogs', 'inv_finished', 'inv_raw', 'inv_pack', 'payable', 'receivable', 'pay_cash', 'owner_capital', 'overhead_absorbed'];
begin
  case p_code
  when 'stk_tracked' then
    select count(*) into tot from public.items where tracked and coalesce(is_active, true);
    n := case when tot = 0 then 1 else 0 end;
  when 'stk_unit' then
    select count(*), count(*) filter (where nullif(btrim(coalesce(base_unit, '')), '') is null) into tot, n from public.items where tracked and coalesce(is_active, true);
  when 'stk_opening' then
    select count(*), count(*) filter (where not exists (select 1 from public.stock_ledger l where l.item_id = i.id)) into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_conv' then
    select count(*), count(*) filter (where exists (select 1 from unnest(coalesce(i.sell_units, '{}'::text[])) u where u is not null and u <> '' and public._unit_factor_base(i.id, u) is null))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_cost' then   -- stock on hand with no known cost; blank or 0 = unknown
    select count(*), count(*) filter (where not exists (select 1 from public.stock_balance b where b.item_id = i.id and b.avg_cost > 0)
                                      and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price > 0))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true) and exists (select 1 from public.stock_balance b2 where b2.item_id = i.id and b2.qty > 0);
  when 'stk_neg', 'flw_neg' then
    select count(*) into n from public.stock_balance where qty < 0;
    select count(*) into tot from public.stock_balance;
  when 'acc_start' then
    n := case when st is null then 1 else 0 end; tot := 1;
  when 'acc_coa' then
    select count(*) into tot from public.coa_accounts where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'acc_map' then
    tot := array_length(req, 1);
    select count(*) into n from unnest(req) k where not exists (select 1 from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k and a.active);
  when 'acc_opening' then
    tot := 1;
    n := case when exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)) then 0 else 1 end;
  when 'acc_wait', 'flw_acc_wait' then
    if st is null then ap := false; else select count(*) into n from public._acct_docs(st) d where d.waiting is not null; end if;
  when 'acc_err', 'flw_acc_err' then
    if st is null then ap := false; else
      select count(*) into n from public.acct_post_errors72 x where exists (select 1 from public._acct_docs(st) dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null);
    end if;
  when 'flw_acc_old' then   -- not yet in the books and dated before today (no invented age limit: "earlier than today")
    if st is null then ap := false; else
      select count(*) into n from public._acct_docs(st) d where d.waiting is null and d.entry_date < td;
    end if;
  when 'prd_recipes' then
    select count(*) into tot from public.recipes where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'prd_lines' then
    select count(*), count(*) filter (where not exists (select 1 from public.recipe_lines l where l.recipe_id = r.id and l.active)) into tot, n from public.recipes r where r.active;
  when 'prd_yield' then
    select count(*), count(*) filter (where r.yield_qty is null or r.yield_qty <= 0) into tot, n from public.recipes r where r.active;
  when 'prd_approve' then
    select count(*), count(*) filter (where r.approved_at is null) into tot, n from public.recipes r where r.active;
  when 'prd_icost' then
    select count(distinct l.ingredient_item_id), count(distinct l.ingredient_item_id) filter (where not exists (select 1 from public.stock_balance b where b.item_id = l.ingredient_item_id and b.avg_cost > 0)
                                                              and not exists (select 1 from public.item_costs c where c.item_id = l.ingredient_item_id and c.cost_price > 0))
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_unit' then
    select count(*), count(*) filter (where nullif(l.unit, '') is not null and public._unit_factor_base(l.ingredient_item_id, l.unit) is null)
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_conv' then
    select count(*), count(*) filter (where (c.mode = 'pool' and coalesce(c.normal_monthly_output, 0) <= 0)
                                         or (c.mode = 'recipe' and not exists (select 1 from public.recipe_cost_components x where x.active)))
      into tot, n from public.location_cost_cfg c where c.mode <> 'off';
  when 'flw_prod_cost' then
    select count(*) into tot from public.production_runs where status is distinct from 'void';
    select count(*) into n from public.production_runs where status is distinct from 'void' and cost_complete is false;
  when 'flw_pool' then
    select count(*), count(*) filter (where not exists (select 1 from public.factory_cost_pools p where p.location_id = c.location_id and p.active and p.month = date_trunc('month', td)::date))
      into tot, n from public.location_cost_cfg c where c.mode = 'pool';
    ap := tot > 0;
  when 'cs_sources' then
    select count(*) into tot from public.cost_sources where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'cs_rule' then
    select count(*), count(*) filter (where not exists (select 1 from public.cost_source_rules r where r.source_id = s.id and r.status = 'approved')) into tot, n from public.cost_sources s where s.active;
  when 'cs_attrib' then
    select count(*) into tot from public.location_cost_attribution where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_channels' then
    select count(*) into tot from public.sales_channels where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_url' then
    ap := public.rule_on('web_form_on'); n := case when ap and coalesce(public.rule_txt('web_form_public_url'), '') = '' then 1 else 0 end; tot := 1;
  when 'onl_bot' then
    ap := public.rule_on('meta_intake_on'); n := case when ap and not exists (select 1 from public.intake_bots where active) then 1 else 0 end; tot := 1;
  when 'flw_inbox_new' then
    select count(*) into n from public.inbound_messages where status = 'new' and (received_at at time zone 'Asia/Dhaka')::date < td;
    select count(*) into tot from public.inbound_messages;
  when 'flw_inbox_silent' then
    h := public.rule_num('inbox_silence_hours');
    if coalesce(h, 0) <= 0 then ap := false; else
      select max(received_at) into last_in from public.inbound_messages;
      n := case when last_in is not null and last_in < now() - make_interval(hours => h::int) then 1 else 0 end; tot := 1;
    end if;
  when 'flw_intake_fail' then
    select count(*) into n from public.intake_failures where state = 'failed';
    select count(*) into tot from public.intake_failures;
  when 'flw_oo_flags' then
    select count(*) into n from public.online_order_flags where state = 'open';
    select count(*) into tot from public.online_order_flags;
  else
    return jsonb_build_object('n', null, 'total', null, 'applies', false, 'unknown_check', true);
  end case;
  return jsonb_build_object('n', n, 'total', tot, 'applies', ap);
end $$;

-- may the caller read the guide (owner, or a person who may see costs)?
create or replace function public._setup_view81() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.biz_cost_ok());
$$;

-- ---------- 1. the recommendation list ----------
create or replace function public.setup_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; d record; r public.rules; eff jsonb; st text; chosen boolean; iss jsonb; c record; cj jsonb;
        cnt_ok int := 0; cnt_rec int := 0; cnt_own int := 0; cnt_info int := 0; cnt_ni int := 0; ready boolean;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for d in select * from public.setup_rec_defs81 where active order by sort, code loop
    select * into r from public.rules where key = d.rule_key;
    iss := '[]'::jsonb; ready := true;
    if not found then
      st := 'not_installed'; cnt_ni := cnt_ni + 1; eff := null; chosen := false;
    else
      eff := coalesce(r.value, r.default_value); chosen := r.value is not null;
      if d.rec_value is null then st := 'info'; cnt_info := cnt_info + 1;
      elsif eff is not distinct from d.rec_value then st := 'ok'; cnt_ok := cnt_ok + 1;
      elsif chosen then st := 'owner_chosen'; cnt_own := cnt_own + 1;
      else st := 'recommended'; cnt_rec := cnt_rec + 1; end if;
      for c in select x.code, x.label_bn, x.label_mix, x.label_en from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then
          ready := false;
          iss := iss || jsonb_build_object('code', c.code, 'n', (cj->>'n')::bigint, 'label_bn', c.label_bn, 'label_mix', c.label_mix, 'label_en', c.label_en);
        end if;
      end loop;
    end if;
    out_ := out_ || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'phase', d.phase, 'module', d.module, 'kind', r.kind,
      'status', st, 'recommended', d.rec_value, 'current', eff, 'default', r.default_value, 'owner_chosen', chosen,
      'min', r.min_value, 'max', r.max_value, 'unit', r.unit, 'choices', r.choices,
      'ready', ready, 'ready_issues', iss,
      'rule_label_bn', r.label_bn, 'rule_label_mix', r.label_mix, 'rule_label_en', r.label_en,
      'reason_bn', d.reason_bn, 'reason_mix', coalesce(d.reason_mix, d.reason_bn), 'reason_en', d.reason_en, 'sort', d.sort);
  end loop;
  return jsonb_build_object('advisory', true, 'can_apply', public.is_owner(),
    'summary', jsonb_build_object('total', jsonb_array_length(out_), 'ok', cnt_ok, 'recommended', cnt_rec, 'owner_chosen', cnt_own, 'info', cnt_info, 'not_installed', cnt_ni),
    'items', out_);
end $$;

-- ---------- 2. the one-tap recommended apply (owner only, audited, never over an owner's choice unless asked) ----------
create or replace function public.setup_recommend_apply(p_client uuid, p_codes text[] default null, p_overwrite boolean default false, p_ignore_ready boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if d.rec_value is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from d.rec_value then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
    owr := r.value is not null;                       -- the owner already chose another value
    if owr and not (p_overwrite and p_codes is not null) then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'owner_chosen'); continue; end if;
    ready := true;
    if not p_ignore_ready then
      for c in select x.code from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then ready := false; end if;
      end loop;
    end if;
    if not ready then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_ready'); continue; end if;
    begin
      perform public.set_rule(d.rule_key, d.rec_value);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', d.rec_value, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $$;

-- ---------- 3. readiness: "before you switch it on" (advice only) ----------
create or replace function public.setup_readiness(p_topic text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; t record; c record; cj jsonb; cl jsonb; nprob int; napp int;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for t in select * from public.setup_topic_defs81 where p_topic is null or topic = p_topic order by sort loop
    cl := '[]'::jsonb; nprob := 0; napp := 0;
    for c in select * from public.setup_check_defs81 where topic = t.topic and kind = 'ready' and active order by sort loop
      cj := public._setup_chk81(c.code);
      if coalesce((cj->>'applies')::boolean, false) then
        napp := napp + 1;
        if coalesce((cj->>'n')::bigint, 0) > 0 then nprob := nprob + 1; end if;
      end if;
      cl := cl || jsonb_build_object('code', c.code, 'level', c.level, 'applies', coalesce((cj->>'applies')::boolean, false), 'problems', cj->'n', 'total', cj->'total',
        'ok', coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) = 0,
        'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en,
        'fix_bn', c.fix_bn, 'fix_mix', coalesce(c.fix_mix, c.fix_bn), 'fix_en', c.fix_en, 'nav', c.nav);
    end loop;
    out_ := out_ || jsonb_build_object('topic', t.topic, 'gate_rule', t.gate_rule, 'gate_on', case when t.gate_rule is null then null else public.rule_on(t.gate_rule) end,
      'label_bn', t.label_bn, 'label_mix', coalesce(t.label_mix, t.label_bn), 'label_en', t.label_en,
      'ready', nprob = 0, 'problem_checks', nprob, 'checks', cl);
  end loop;
  return jsonb_build_object('advisory', true, 'topics', out_);
end $$;

-- ---------- 4. post-activation flow checks: "is everything flowing?" ----------
create or replace function public.setup_flow_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; c record; cj jsonb; on_ boolean; lvl text; nwarn int := 0;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for c in select * from public.setup_check_defs81 where kind = 'flow' and active order by sort loop
    on_ := case when c.gate_rule is null then true else public.rule_on(c.gate_rule) end;
    if not on_ then
      out_ := out_ || jsonb_build_object('code', c.code, 'topic', c.topic, 'level', 'na', 'gate_rule', c.gate_rule, 'problems', 0,
        'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en, 'nav', c.nav);
      continue;
    end if;
    cj := public._setup_chk81(c.code);
    lvl := case when not coalesce((cj->>'applies')::boolean, false) then 'na' when coalesce((cj->>'n')::bigint, 0) = 0 then 'ok' else c.level end;
    if lvl = 'warn' then nwarn := nwarn + 1; end if;
    out_ := out_ || jsonb_build_object('code', c.code, 'topic', c.topic, 'level', lvl, 'gate_rule', c.gate_rule, 'problems', cj->'n', 'total', cj->'total',
      'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en,
      'fix_bn', c.fix_bn, 'fix_mix', coalesce(c.fix_mix, c.fix_bn), 'fix_en', c.fix_en, 'nav', c.nav);
  end loop;
  return jsonb_build_object('advisory', true, 'warnings', nwarn, 'checks', out_);
end $$;

-- ---------- 5. the owner's trail ----------
create or replace function public.setup_apply_history(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('client_id', b.client_id, 'applied_at', b.applied_at, 'applied_by', b.applied_by, 'overwrite', b.overwrite, 'ignore_ready', b.ignore_ready,
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', l.code, 'rule_key', l.rule_key, 'old', l.old_value, 'new', l.new_value, 'overwrote', l.overwrote) order by l.id), '[]'::jsonb) from public.setup_apply_lines81 l where l.batch_id = b.client_id)) order by b.applied_at desc)
    from (select * from public.setup_apply_batches81 order by applied_at desc limit greatest(1, least(coalesce(p_limit, 30), 200))) b), '[]'::jsonb);
end $$;

-- ---------- RLS + privileges ----------
alter table public.setup_rec_defs81 enable row level security;
alter table public.setup_check_defs81 enable row level security;
alter table public.setup_topic_defs81 enable row level security;
alter table public.setup_apply_batches81 enable row level security;
alter table public.setup_apply_lines81 enable row level security;
revoke all on public.setup_rec_defs81, public.setup_check_defs81, public.setup_topic_defs81, public.setup_apply_batches81, public.setup_apply_lines81 from public, anon, authenticated;
grant select on public.setup_rec_defs81, public.setup_check_defs81, public.setup_topic_defs81 to authenticated;
grant select on public.setup_apply_batches81, public.setup_apply_lines81 to authenticated;
drop policy if exists setup_rec_defs81_sel on public.setup_rec_defs81;
create policy setup_rec_defs81_sel on public.setup_rec_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_check_defs81_sel on public.setup_check_defs81;
create policy setup_check_defs81_sel on public.setup_check_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_topic_defs81_sel on public.setup_topic_defs81;
create policy setup_topic_defs81_sel on public.setup_topic_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_apply_batches81_sel on public.setup_apply_batches81;
create policy setup_apply_batches81_sel on public.setup_apply_batches81 for select to authenticated using (public.is_owner());
drop policy if exists setup_apply_lines81_sel on public.setup_apply_lines81;
create policy setup_apply_lines81_sel on public.setup_apply_lines81 for select to authenticated using (public.is_owner());
revoke usage, select on sequence public.setup_apply_lines81_id_seq from public, anon, authenticated;
revoke all on function public.setup_recommendations(), public.setup_recommend_apply(uuid, text[], boolean, boolean), public.setup_readiness(text), public.setup_flow_check(), public.setup_apply_history(int),
  public._setup_chk81(text), public._setup_view81(), public._setup_ro81() from public, anon, authenticated;
grant execute on function public._setup_view81() to authenticated;   -- used by the read policies
grant execute on function public.setup_recommendations(), public.setup_recommend_apply(uuid, text[], boolean, boolean), public.setup_readiness(text), public.setup_flow_check(), public.setup_apply_history(int) to authenticated;
notify pgrst, 'reload schema';

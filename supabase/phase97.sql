-- ============================================================
-- Phase 97 (bos97) - STEP Land: LANDED COST with every practical option (audit finding a1-F9).
--   Needs phases 72..88, 90, 91 and phase89 (the final merged bodies) pasted first - guard below. Paste order: ... phase89, phase97.
--   If phase89 is ever pasted AGAIN, paste phase97 again after it (phase89 re-creates _acct_docs without the landed-cost block).
--   Additive, paste-twice safe. Exactly ONE existing function is re-created: _acct_docs (phase89 body + two bos97 blocks at the end). One table check constraint is widened
--   (stock_ledger.reason gets 'cost_adjust'). Nothing else existing is changed. No old phase file is edited.
--
--   WHEN landed cost matters (each has a built-in option; with the mode OFF - the default - an item costs exactly its invoice price, as today):
--     imported goods; freight / transport in; loading and unloading; customs duty; insurance; clearing agent fee; bank / LC charges; packaging bought for the lot;
--     non-recoverable tax; a local purchase with a delivery charge; a late bill that arrives after the goods were already sold or consumed; returns of such a
--     purchase; a charge billed in a foreign currency (currency conversion); exchange-rate difference.
--   Rules (module purchase):
--     landed_cost_mode               off (default) | manual | per_bill | per_shipment
--     landed_alloc_default           value (default) | qty | weight | volume | manual | equal            how a charge is spread over the item lines
--     landed_late_mode               split_remaining_and_cogs (default) | post_to_remaining_stock | variance_account     what to do with the part of the lot already sold / consumed
--     landed_cost_requires_approval  warn (default) | required
--     landed_reminder_on             switch, default off  ("Landed cost not added?" list for bills of imported / flagged suppliers)
--     landed_reminder_days           number, how many days back the reminder list looks
--     landed_base_currency           text, default BDT
--   Tables (closed to the browser; every read / write is a SECURITY DEFINER function; cost-right + grant needed):
--     cost_charge_types  freight, duty, insurance, clearing, loading, unloading, bank, packaging, vat_nonrec (capitalise) / vat_recov (recoverable tax) /
--                        freight_exp, bank_exp (expense only) / delivery, fx_diff, other ... the owner can add more (landed_charge_type_save)
--     landed_costs (header: draft|approved|posted|void), landed_cost_docs (bill / GRN refs), landed_cost_lines (charges, currency + rate), landed_cost_basis (weight / volume / %
--     per purchase line), landed_cost_alloc + landed_cost_stock (APPEND-ONLY: what was spread where, what the stock ledger got), item_logistics (weight / volume per base unit),
--     landed_supplier_flags (imported / extra charges), landed_skips (append-only "no landed cost needed" notes).
--   Stock: a posted cost is added to the average cost through ledger rows with reason 'cost_adjust' (a pair: the on-hand quantity out at the old average, back in at the new
--     average, ref_type 'landed'). The ledger stays immutable and replayable (stock_reconcile and inventory_vs_gl need no change); the value of the pair is exactly the amount added.
--   Journal: _acct_docs gets 'landed_cost' (Dr inventory raw / pack / finished for the stock share, Dr landed_variance for the sold share, Dr expense / vat_input for charges that are
--     not capitalised; Cr landed_payable / pay_cash / pay_bank / pay_mobile) and 'landed_cost_void' (the counter entry). New mapping keys: vat_input, landed_payable, landed_variance.
--   RPCs: landed_preview, landed_recommendation, landed_save, landed_approve, landed_post, landed_void, landed_get, landed_list, landed_reminders, landed_return_info,
--     landed_charge_types, landed_charge_type_save, landed_logistics_set, landed_supplier_flag_set, landed_skip.
--   A posted purchase bill that has a posted landed cost cannot be voided until the landed cost is voided (trigger).
-- Tag: bos97 marks every added line inside the re-created function.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := '';
begin
  if to_regclass('public.purchase_bills') is null or to_regclass('public.purchase_lines') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_balance') is null
     or to_regclass('public.journal_entries') is null or to_regclass('public.rules') is null or to_regclass('public.shadow_links') is null or to_regclass('public.suppliers') is null then
    miss := miss || ' base-tables';
  end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null or to_regprocedure('public._acct_need(text,text,boolean)') is null
     or to_regprocedure('public._acct_inv_key(text)') is null or to_regprocedure('public._acct_paykey(text,boolean)') is null or to_regprocedure('public._acct_merge(jsonb)') is null
     or to_regprocedure('public._cost_ok(integer)') is null or to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null
     or to_regprocedure('public._item_base(uuid)') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public.log_change()') is null then
    miss := miss || ' functions';
  end if;
  if to_regprocedure('public._acct_docs(date)') is null
     or (pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos89%' and pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos97%') then
    miss := miss || ' phase89';
  end if;
  if miss <> '' then
    raise exception 'phase97 needs phases 72..88, 90, 91 and phase89 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- accounts and mapping keys (additive; the owner can re-map every key) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, parent_id, normal_side, is_group, is_system, sort)
select v.code, v.bn, v.en, v.ty, (select id from public.coa_accounts where code = v.par), v.side, false, true, v.srt
from (values
  ('1240', 'VAT / কর ফেরতযোগ্য (input)', 'VAT input recoverable', 'asset', '1200', 'debit', 24),
  ('2150', 'Landed cost খরচ — দেনা', 'Landed cost charges payable', 'liability', '2000', 'credit', 102),
  ('5150', 'বিক্রি হয়ে যাওয়া মালের landed cost', 'Landed cost on goods already sold', 'expense', null, 'debit', 4150)
) v(code, bn, en, ty, par, side, srt)
on conflict (code) do nothing;
update public.coa_accounts set parent_id = (select parent_id from public.coa_accounts where code = '2100') where code = '2150' and parent_id is null and exists (select 1 from public.coa_accounts where code = '2100');

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.bn, v.en from (values
  ('vat_input', '1240', 'ফেরতযোগ্য VAT / কর (input)', 'Recoverable VAT / tax (input)'),
  ('landed_payable', '2150', 'Landed cost খরচের দেনা (পরিবহন, শুল্ক, clearing ...)', 'Landed cost charges payable (freight, duty, clearing ...)'),
  ('landed_variance', '5150', 'বিক্রি হয়ে যাওয়া মালের landed cost', 'Landed cost on goods already sold')) v(k, code, bn, en)
join public.coa_accounts a on a.code = v.code
on conflict (key) do nothing;

-- ---------- rules (every default = today's behaviour: the whole feature is OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('landed_cost_mode', 'purchase', 'choice', '"off"', null, '["off","manual","per_bill","per_shipment"]'::jsonb, null, null,
  'Landed cost (মালের সাথে আসা খরচ) যোগ করা: বন্ধ / হাতে / প্রতি বিল / প্রতি চালান', 'Landed cost (মালের সাথে আসা খরচ) যোগ করা: off / manual / per bill / per shipment', 'Landed cost (freight, duty ...) added to item cost: off / manual / per bill / per shipment',
  'বন্ধ = আজকের মতো, মালের দাম = বিলের দাম। হাতে = দরকার হলে নিজে যোগ করবেন। প্রতি বিল = প্রতিটি বিলের জন্য একটি করে। প্রতি চালান = একাধিক বিল / GRN মিলিয়ে একটি চালান (lot)। সুপারিশ: আমদানি করলে প্রতি চালান, স্থানীয় ভাড়া দিলে হাতে।',
  'off = আগের মতো, item cost = bill-এর price। manual = দরকার হলে নিজে add করবেন। per bill = প্রতি bill-এ একটি। per shipment = একাধিক bill / GRN মিলিয়ে একটি shipment (lot)। Recommended: import হলে per shipment, local ভাড়া হলে manual।',
  'off = as today, item cost = the invoice price. manual = you add it when you need it. per bill = one landed cost per bill. per shipment = one landed cost spread over several bills / GRNs of one shipment (lot). Recommended: per shipment for imports, manual for a local delivery charge.', 970),
 ('landed_alloc_default', 'purchase', 'choice', '"value"', null, '["value","qty","weight","volume","manual","equal"]'::jsonb, null, null,
  'খরচ ভাগ করার ডিফল্ট পদ্ধতি: দাম / পরিমাণ / ওজন / আয়তন / হাতে % / সমান', 'খরচ ভাগ করার default method: value / qty / weight / volume / manual % / equal', 'Default way to spread a charge over the item lines: value / qty / weight / volume / manual % / equal',
  'দাম = দামি মালের উপর বেশি। পরিমাণ = প্রতি একক সমান। ওজন বা আয়তন = ভাড়ার জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (অনুমান করা হয় না)। হাতে % = আপনি ভাগ বলে দেবেন। সমান = প্রতি লাইনে সমান। সুপারিশ: দাম, আর ভাড়ার জন্য ওজন যদি সব লাইনে জানা থাকে।',
  'value = দামি মালে বেশি। qty = প্রতি unit সমান। weight বা volume = ভাড়ার জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (অনুমান করা হয় না)। manual % = আপনি ভাগ বলে দেবেন। equal = প্রতি line-এ সমান। Recommended: value, আর freight-এর জন্য weight যদি সব line-এ জানা থাকে।',
  'value = costly goods take more. qty = the same per unit. weight or volume = best for freight, but the weight must be known (it is never guessed). manual % = you give the shares. equal = the same per line. Recommended: value, and weight for freight when every line has a known weight.', 971),
 ('landed_late_mode', 'purchase', 'choice', '"split_remaining_and_cogs"', null, '["split_remaining_and_cogs","post_to_remaining_stock","variance_account"]'::jsonb, null, null,
  'দেরিতে আসা খরচ, মাল আগেই বিক্রি হয়ে গেলে: ভাগ করে / বাকি স্টকে / variance খাতে', 'দেরিতে আসা খরচ, মাল আগেই বিক্রি হলে: split remaining + COGS / সব remaining stock-এ / variance account-এ', 'A charge that arrives after part of the lot was sold or used: split remaining stock and COGS / all to remaining stock / variance account',
  'ভাগ করে = যে অংশ এখনো আছে সেটা স্টকের দামে, যে অংশ বিক্রি হয়ে গেছে সেটা লাভ-ক্ষতির খরচে (landed variance)। বাকি স্টকে = পুরো খরচ যা আছে তার দামে জোড়া (দাম বেশি দেখাবে)। variance খাতে = স্টক ছোঁবে না, পুরোটা খরচ। সুপারিশ: ভাগ করে।',
  'split = যে অংশ এখনো আছে সেটা stock cost-এ, যে অংশ বিক্রি হয়ে গেছে সেটা landed variance-এ (P&L)। remaining stock = পুরো charge যা আছে তার cost-এ জোড়া (cost বেশি দেখাবে)। variance account = stock ছোঁবে না, পুরোটা খরচ। Recommended: split।',
  'split = the part still on the shelf goes into stock cost, the part already sold goes to the landed-cost variance (profit and loss). remaining stock = the whole charge is added to what is left (its cost looks higher). variance account = stock is not touched, the whole charge is an expense. Recommended: split.', 972),
 ('landed_cost_requires_approval', 'purchase', 'choice', '"warn"', null, '["warn","required"]'::jsonb, null, null,
  'Landed cost পোস্টের আগে অনুমোদন: সতর্কতা / বাধ্যতামূলক', 'Landed cost post-এর আগে approval: warn / required', 'Approval before a landed cost is posted: warn / required',
  'সতর্কতা = অনুমোদন ছাড়া পোস্ট করা যায়, কিন্তু একটি হলুদ সতর্কবার্তা জমে। বাধ্যতামূলক = অনুমোদিত না হলে পোস্ট হয় না, আর যিনি বানিয়েছেন তিনি নিজে অনুমোদন করতে পারেন না (মালিক পারেন)। সুপারিশ: বড় লেনদেনে বাধ্যতামূলক।',
  'warn = approval ছাড়া post করা যায়, কিন্তু একটি yellow সতর্কবার্তা জমে। required = approved না হলে post হয় না, আর যিনি বানিয়েছেন তিনি নিজে approve করতে পারেন না (owner পারেন)। Recommended: বড় amount-এ required।',
  'warn = it can be posted without approval, but a yellow warning is kept. required = it cannot be posted until approved, and the person who made it cannot approve it (the owner can). Recommended: required for big amounts.', 973),
 ('landed_reminder_on', 'purchase', 'switch', 'false', null, null, null, null,
  '"Landed cost যোগ হয়নি?" মনে করিয়ে দেওয়ার তালিকা', '"Landed cost যোগ হয়নি?" reminder list', '"Landed cost not added?" reminder list',
  'চালু করলে আমদানি / চিহ্নিত সাপ্লায়ারের বিল, যেগুলোর landed cost নেই, একটি তালিকায় দেখা যায়। বন্ধ = কোনো তালিকা নেই। সুপারিশ: আমদানি করলে চালু।',
  'চালু করলে imported / flagged supplier-এর bill, যেগুলোর landed cost নেই, একটি list-এ দেখা যায়। off = কোনো list নেই। Recommended: import করলে on।',
  'When on, bills of imported or flagged suppliers that have no landed cost are listed. Off = no list. Recommended: on if you import.', 974),
 ('landed_reminder_days', 'purchase', 'number', '30', 'days', null, 1, 3650,
  'মনে করানোর তালিকা কত দিন পিছনে দেখবে', 'Reminder list কত দিন পিছনে দেখবে', 'How many days back the reminder list looks',
  'এর চেয়ে পুরোনো বিল তালিকায় আসে না।', 'এর চেয়ে পুরোনো bill list-এ আসে না।', 'Older bills do not appear in the list.', 975),
 ('landed_base_currency', 'purchase', 'text', '"BDT"', null, null, null, null,
  'Landed cost-এর মূল মুদ্রা (কোড)', 'Landed cost-এর base currency (code)', 'Base currency of landed costs (code)',
  'অন্য মুদ্রার খরচ এই মুদ্রায় রূপান্তরিত হয়ে বসে; রূপান্তরের হার আপনি নিজে লেখেন।', 'অন্য currency-র charge এই currency-তে convert হয়ে বসে; rate আপনি নিজে লেখেন।', 'A charge in another currency is converted to this one; you type the rate yourself.', 976)
on conflict (key) do nothing;

-- ---------- grants (module purchase; the owner can always do everything) ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('landed_entry', 'purchase', 95, 'Landed cost লেখা ও পোস্ট করা', 'Landed cost লেখা ও post করা', 'Write and post landed costs (freight, duty ...)', 'once', null),
   ('landed_approve', 'purchase', 96, 'Landed cost অনুমোদন ও বাতিল (void)', 'Landed cost approve ও void করা', 'Approve and void landed costs', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('landed_entry', 'purchasing'), ('landed_entry', 'management'), ('landed_approve', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
on conflict do nothing;

-- phase91 (per-user permission recommendations) lists what each role usually needs: add the two new grants so a later paste of phase91 changes nothing
do $r$ begin
  if to_regclass('public.perm_reco_role') is not null then
    insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
      select g.role_code, g.grant_code, 'এই ভূমিকায় সাধারণত দরকার (আজকের ডিফল্ট)', 'এই role-এ সাধারণত দরকার (আজকের default)', 'Usually needed by this role (today''s default)'
        from public.rule_grants g where g.allowed and g.grant_code in ('landed_entry', 'landed_approve') and exists (select 1 from public.roles r where r.code = g.role_code) and exists (select 1 from public.grant_defs d where d.grant_code = g.grant_code)
      on conflict do nothing;
  end if;
end $r$;

-- ---------- the stock ledger may carry a cost adjustment ----------
do $c$
declare def text; lst text;
begin
  select pg_get_constraintdef(oid) into def from pg_constraint where conname = 'stock_ledger_reason_check' and conrelid = 'public.stock_ledger'::regclass;
  if def is not null and def not like '%cost_adjust%' then
    select string_agg(quote_literal(m[1]), ',') into lst from regexp_matches(def, '''([a-z_]+)''::text', 'g') m;
    execute 'alter table public.stock_ledger drop constraint stock_ledger_reason_check';
    execute 'alter table public.stock_ledger add constraint stock_ledger_reason_check check (reason = any (array[' || lst || ',''cost_adjust'']))';
  end if;
end $c$;

-- ---------- tables ----------
create table if not exists public.cost_charge_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,32}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (length(btrim(name_en)) between 1 and 80),
  name_mix text,
  treatment text not null check (treatment in ('capitalise', 'expense_only', 'recoverable_tax')),
  expense_key text check (expense_key is null or expense_key ~ '^[a-z0-9_]{2,48}$'),
  default_alloc text check (default_alloc is null or default_alloc in ('qty', 'value', 'weight', 'volume', 'equal')),
  hint_bn text, hint_mix text, hint_en text,
  sort int not null default 0,
  active boolean not null default true,
  is_system boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);
alter table public.cost_charge_types enable row level security;
drop policy if exists cct_read97 on public.cost_charge_types;
create policy cct_read97 on public.cost_charge_types for select to authenticated using (public.is_active());
revoke all on table public.cost_charge_types from public, anon, authenticated;
grant select on table public.cost_charge_types to authenticated;

insert into public.cost_charge_types (code, name_bn, name_en, name_mix, treatment, expense_key, default_alloc, hint_bn, hint_mix, hint_en, sort, is_system) values
 ('freight', 'পরিবহন / ভাড়া (মাল আনা)', 'Freight / transport in', 'Freight / পরিবহন ভাড়া', 'capitalise', null, 'weight', 'ওজন জানা থাকলে ওজন ধরে ভাগ করা ভালো', 'weight জানা থাকলে weight ধরে ভাগ করা ভালো', 'Best spread by weight when the weights are known', 10, true),
 ('duty', 'আমদানি শুল্ক (customs duty)', 'Customs duty', 'Customs duty / শুল্ক', 'capitalise', null, 'value', 'শুল্ক সাধারণত দামের হারে ধরা হয়', 'Duty সাধারণত value-র হারে ধরা হয়', 'Duty is normally charged on value', 20, true),
 ('insurance', 'বীমা (insurance)', 'Insurance', 'Insurance / বীমা', 'capitalise', null, 'value', 'বীমা দামের হারে', 'Insurance value-র হারে', 'Insurance follows value', 30, true),
 ('clearing', 'Clearing agent ফি', 'Clearing agent fee', 'Clearing agent fee', 'capitalise', null, 'value', 'দামের হারে, বা সমান', 'Value-র হারে, বা equal', 'By value, or equal', 40, true),
 ('loading', 'মাল তোলা (loading)', 'Loading', 'Loading / মাল তোলা', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 50, true),
 ('unloading', 'মাল নামানো (unloading)', 'Unloading', 'Unloading / মাল নামানো', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 60, true),
 ('bank', 'ব্যাংক / LC খরচ', 'Bank / LC charges', 'Bank / LC charges', 'capitalise', null, 'value', 'দামের হারে। শুধু ব্যাংকের সাধারণ চার্জ হলে "bank_exp" ব্যবহার করুন', 'Value-র হারে। শুধু সাধারণ bank charge হলে "bank_exp" ব্যবহার করুন', 'By value. For an ordinary bank fee that is not part of this lot use "bank_exp"', 70, true),
 ('packaging', 'এই চালানের জন্য কেনা প্যাকেজিং', 'Packaging bought for the lot', 'Packaging (এই lot-এর জন্য)', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 80, true),
 ('vat_nonrec', 'ফেরত-অযোগ্য VAT / কর', 'Non-recoverable tax', 'Non-recoverable VAT / tax', 'capitalise', null, 'value', 'ফেরত পাওয়া যায় না, তাই মালের দামে যোগ হয়', 'ফেরত পাওয়া যায় না, তাই item cost-এ যোগ হয়', 'Cannot be claimed back, so it is part of the item cost', 90, true),
 ('vat_recov', 'ফেরতযোগ্য VAT / কর (input)', 'Recoverable tax (input)', 'Recoverable VAT / tax (input)', 'recoverable_tax', null, null, 'মালের দামে যোগ হয় না; ফেরতযোগ্য সম্পদ হিসেবে থাকে', 'Item cost-এ যোগ হয় না; recoverable asset হিসেবে থাকে', 'Not added to item cost; kept as a recoverable asset', 100, true),
 ('delivery', 'স্থানীয় ডেলিভারি চার্জ', 'Local delivery charge', 'Local delivery charge', 'capitalise', null, 'qty', 'স্থানীয় কেনায় গাড়ি / ডেলিভারি ভাড়া', 'Local purchase-এ গাড়ি / delivery ভাড়া', 'Van or delivery fee on a local purchase', 110, true),
 ('fx_diff', 'বিনিময় হারের পার্থক্য', 'Exchange-rate difference', 'Exchange-rate difference', 'capitalise', null, 'value', 'বিলের হার আর পরিশোধের হারের পার্থক্য (ঋণাত্মক হতে পারে)', 'Bill rate আর payment rate-এর পার্থক্য (negative হতে পারে)', 'Difference between the bill rate and the payment rate (may be negative)', 120, true),
 ('freight_exp', 'ভাড়া — খরচ হিসেবে (মালের দামে যোগ নয়)', 'Freight — expense only (not added to cost)', 'Freight — expense only', 'expense_only', 'exp_transport', null, 'মালের দামে যোগ হয় না; সোজা পরিবহন খরচ', 'Item cost-এ যোগ হয় না; সোজা transport expense', 'Not added to item cost; goes straight to transport expense', 130, true),
 ('bank_exp', 'ব্যাংক চার্জ — খরচ হিসেবে', 'Bank charge — expense only', 'Bank charge — expense only', 'expense_only', 'bank_charges', null, 'মালের দামে যোগ হয় না; সোজা ব্যাংক চার্জ খরচ', 'Item cost-এ যোগ হয় না; সোজা bank charge expense', 'Not added to item cost; goes straight to bank charges', 140, true),
 ('other', 'অন্যান্য landed খরচ', 'Other landed charge', 'Other landed charge', 'capitalise', null, 'value', 'যেটা অন্য কোনোটায় পড়ে না', 'যেটা অন্য কোনোটায় পড়ে না', 'Anything that fits none of the above', 900, true)
on conflict (code) do nothing;

create table if not exists public.landed_costs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  status text not null default 'draft' check (status in ('draft', 'approved', 'posted', 'void')),
  location_id int not null references public.locations(id),
  shipment_ref text check (shipment_ref is null or length(shipment_ref) <= 80),
  title text check (title is null or length(title) <= 120),
  note text check (note is null or length(note) <= 500),
  cost_date date not null default ((now() at time zone 'Asia/Dhaka')::date),
  alloc_method text not null default 'value' check (alloc_method in ('qty', 'value', 'weight', 'volume', 'manual', 'equal')),
  late_mode text check (late_mode is null or late_mode in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account')),
  late_mode_used text,
  mode_at_save text,
  total numeric not null default 0,
  post_client uuid,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  posted_by uuid, posted_at timestamptz,
  void_by uuid, void_at timestamptz, void_reason text
);
create unique index if not exists landed_costs_client97 on public.landed_costs (client_id) where client_id is not null;
create unique index if not exists landed_costs_postclient97 on public.landed_costs (post_client) where post_client is not null;
create index if not exists landed_costs_status97 on public.landed_costs (status, location_id, cost_date);

create table if not exists public.landed_cost_docs (
  cost_id uuid not null references public.landed_costs(id),
  bill_id uuid not null references public.purchase_bills(id),
  doc_type text not null default 'bill' check (doc_type in ('bill', 'grn')),
  doc_id uuid not null,
  primary key (cost_id, bill_id)
);
create index if not exists landed_cost_docs_bill97 on public.landed_cost_docs (bill_id);

create table if not exists public.landed_cost_lines (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  line_no int not null,
  charge_type text not null references public.cost_charge_types(code),
  amount_ccy numeric not null check (amount_ccy <> 0 and abs(amount_ccy) <= 1000000000000),
  ccy text not null default 'BDT' check (ccy ~ '^[A-Z]{3}$'),
  rate numeric not null default 1 check (rate > 0 and rate <= 1000000000),
  amount numeric not null check (amount <> 0 and abs(amount) <= 1000000000000),
  alloc_method text check (alloc_method is null or alloc_method in ('qty', 'value', 'weight', 'volume', 'manual', 'equal')),
  pay_mode text not null default 'payable' check (pay_mode in ('payable', 'cash', 'bank', 'mobile')),
  supplier_id uuid references public.suppliers(id),
  ref_no text check (ref_no is null or length(ref_no) <= 60),
  note text check (note is null or length(note) <= 200),
  unique (cost_id, line_no)
);

create table if not exists public.landed_cost_basis (
  cost_id uuid not null references public.landed_costs(id),
  bill_line_id bigint not null references public.purchase_lines(id),
  weight_kg numeric check (weight_kg is null or weight_kg >= 0),
  volume_l numeric check (volume_l is null or volume_l >= 0),
  manual_pct numeric check (manual_pct is null or (manual_pct >= 0 and manual_pct <= 100)),
  primary key (cost_id, bill_line_id)
);

create table if not exists public.landed_cost_alloc (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  kind text not null check (kind in ('post', 'void')),
  charge_line_id bigint not null references public.landed_cost_lines(id),
  bill_line_id bigint references public.purchase_lines(id),
  item_id uuid references public.items(id),
  location_id int not null,
  part text not null check (part in ('stock', 'cogs', 'expense', 'tax')),
  amount numeric not null,
  dr_key text not null,
  method text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists landed_cost_alloc_cost97 on public.landed_cost_alloc (cost_id, kind);
create index if not exists landed_cost_alloc_line97 on public.landed_cost_alloc (bill_line_id);

create table if not exists public.landed_cost_stock (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  kind text not null check (kind in ('post', 'void')),
  item_id uuid not null references public.items(id),
  location_id int not null,
  lot_qty numeric not null,
  on_hand_before numeric not null,
  avg_before numeric,
  avg_after numeric,
  stock_value numeric not null,
  cogs_value numeric not null,
  ledger_out bigint, ledger_in bigint,
  flags text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists landed_cost_stock_cost97 on public.landed_cost_stock (cost_id, kind);

create table if not exists public.item_logistics (
  item_id uuid primary key references public.items(id),
  unit_weight_kg numeric check (unit_weight_kg is null or unit_weight_kg > 0),
  unit_volume_l numeric check (unit_volume_l is null or unit_volume_l > 0),
  note text check (note is null or length(note) <= 200),
  set_by uuid, set_at timestamptz not null default now()
);

create table if not exists public.landed_supplier_flags (
  supplier_id uuid primary key references public.suppliers(id),
  kind text not null check (kind in ('imported', 'extra_charges')),
  active boolean not null default true,
  note text check (note is null or length(note) <= 200),
  set_by uuid, set_at timestamptz not null default now()
);

create table if not exists public.landed_skips (
  id bigint generated always as identity primary key,
  bill_id uuid not null references public.purchase_bills(id),
  reason text not null check (length(btrim(reason)) between 3 and 200),
  by_user uuid default auth.uid(), at timestamptz not null default now()
);
create unique index if not exists landed_skips_bill97 on public.landed_skips (bill_id);

do $t$
declare t text;
begin
  foreach t in array array['landed_costs', 'landed_cost_docs', 'landed_cost_lines', 'landed_cost_basis', 'landed_cost_alloc', 'landed_cost_stock', 'item_logistics', 'landed_supplier_flags', 'landed_skips'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);      -- the browser never touches these tables: functions only
  end loop;
end $t$;

-- ---------- triggers: append-only, locked after posting, audit ----------
create or replace function public._landed_ro97() returns trigger language plpgsql as $$
begin raise exception 'landed_append_only' using hint = 'This table is append-only: a mistake is fixed with a void, never by editing'; end $$;
revoke all on function public._landed_ro97() from public, anon, authenticated;
do $t$
declare t text;
begin
  foreach t in array array['landed_cost_alloc', 'landed_cost_stock', 'landed_skips'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro97', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public._landed_ro97()', t || '_ro97', t);
    execute format('drop trigger if exists %I on public.%I', t || '_rot97', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._landed_ro97()', t || '_rot97', t);
  end loop;
end $t$;

create or replace function public._landed_hdr_guard97() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'landed_no_delete' using hint = 'Void it instead'; end if;
  if old.status = 'void' then raise exception 'landed_locked' using hint = 'A voided landed cost cannot change'; end if;
  if old.status = 'posted' then
    if new.status <> 'void' and new.status <> 'posted' then raise exception 'landed_locked'; end if;
    if new.status = 'posted' then raise exception 'landed_locked'; end if;
    if new.location_id is distinct from old.location_id or new.total is distinct from old.total or new.cost_date is distinct from old.cost_date or new.alloc_method is distinct from old.alloc_method
       or new.late_mode_used is distinct from old.late_mode_used or new.posted_at is distinct from old.posted_at then raise exception 'landed_locked'; end if;
  end if;
  if new.status = 'draft' and old.status not in ('draft', 'approved') then raise exception 'landed_locked'; end if;
  return new;
end $$;
revoke all on function public._landed_hdr_guard97() from public, anon, authenticated;
drop trigger if exists landed_costs_guard97 on public.landed_costs;
create trigger landed_costs_guard97 before update or delete on public.landed_costs for each row execute function public._landed_hdr_guard97();

create or replace function public._landed_child_guard97() returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid := coalesce(case when tg_op = 'DELETE' then old.cost_id else new.cost_id end, null); st text;
begin
  select status into st from public.landed_costs where id = cid;
  if st is distinct from 'draft' then raise exception 'landed_locked' using hint = 'Only a draft landed cost can be edited'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke all on function public._landed_child_guard97() from public, anon, authenticated;
do $t$
declare t text;
begin
  foreach t in array array['landed_cost_docs', 'landed_cost_lines', 'landed_cost_basis'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_g97', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public._landed_child_guard97()', t || '_g97', t);
  end loop;
end $t$;

do $t$
declare r record;
begin
  for r in select * from (values ('landed_costs', 'id'), ('landed_cost_lines', 'id'), ('landed_cost_alloc', 'id'), ('landed_cost_stock', 'id'), ('cost_charge_types', 'code'),
                                 ('item_logistics', 'item_id'), ('landed_supplier_flags', 'supplier_id'), ('landed_skips', 'id')) v(t, k) loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || r.t || '97', r.t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || r.t || '97', r.t, r.k);
  end loop;
end $t$;

-- a posted bill that carries a posted landed cost cannot be voided before that landed cost is voided
create or replace function public._landed_bill_void_guard97() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' and exists (
       select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = old.id and c.status = 'posted') then
    raise exception 'landed_cost_posted' using hint = 'Void the landed cost of this bill first';
  end if;
  return new;
end $$;
revoke all on function public._landed_bill_void_guard97() from public, anon, authenticated;
drop trigger if exists purchase_bills_landed_guard97 on public.purchase_bills;
create trigger purchase_bills_landed_guard97 before update of status on public.purchase_bills for each row execute function public._landed_bill_void_guard97();

-- ============================================================
-- helpers (internal: closed to the browser)
-- ============================================================
create or replace function public._landed_ok97(p_loc integer, p_need text default 'entry') returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and public.can_loc(p_loc) and public._cost_ok(p_loc)
     and (public.is_owner() or case p_need when 'approve' then public.has_grant('landed_approve', p_loc)
                                  else public.has_grant('landed_entry', p_loc) or public.has_grant('landed_approve', p_loc) end);
$$;

-- weight in kg / volume in litres of ONE base unit, only when the unit itself says so (never a guess)
create or replace function public._landed_unit_w97(p_unit text) returns numeric language sql immutable as $$
  select case lower(btrim(coalesce(p_unit, ''))) when 'kg' then 1 when 'kilogram' then 1 when 'g' then 0.001 when 'gm' then 0.001 when 'gram' then 0.001
                                                 when 'ton' then 1000 when 'tonne' then 1000 when 'mt' then 1000 end;
$$;
create or replace function public._landed_unit_v97(p_unit text) returns numeric language sql immutable as $$
  select case lower(btrim(coalesce(p_unit, ''))) when 'l' then 1 when 'ltr' then 1 when 'litre' then 1 when 'liter' then 1 when 'ml' then 0.001 end;
$$;

-- exact proportional split (2 dp); the rounding remainder goes to the biggest share, so the parts always add up to the amount
create or replace function public._landed_split97(p_amt numeric, p_w numeric[]) returns numeric[]
language plpgsql immutable as $$
declare n int := coalesce(array_length(p_w, 1), 0); r numeric[] := '{}'; i int; tot numeric := 0; s numeric := 0; big int := 1;
begin
  if n = 0 then return r; end if;
  for i in 1 .. n loop
    if p_w[i] < 0 then raise exception 'bad_weight'; end if;
    tot := tot + p_w[i]; if p_w[i] > p_w[big] then big := i; end if;
  end loop;
  if tot <= 0 then raise exception 'weights_zero'; end if;
  for i in 1 .. n loop r[i] := round(p_amt * p_w[i] / tot, 2); s := s + r[i]; end loop;
  r[big] := r[big] + (p_amt - s);
  return r;
end $$;

-- the purchase lines of the chosen bills, with everything a method needs (cost data: closed to the browser)
create or replace function public._landed_rows97(p_bills uuid[], p_basis jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(z) order by z.bill_date, z.bill_no, z.line_no), '[]'::jsonb) from (
    select pl.id as bill_line_id, b.id as bill_id, b.bill_no, b.bill_date, pl.line_no, pl.item_id, it.code, it.name_bn, it.name_en, it.item_type,
           coalesce(it.base_unit, it.unit) as unit, b.location_id as loc, pl.base_qty,
           round(coalesce(pl.unit_cost_base, 0) * case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end, 6) as ucb_net,
           round(coalesce(pl.base_qty, 0) * coalesce(pl.unit_cost_base, 0) * case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end, 2) as value,
           coalesce(nullif(bx.weight_kg, 0), case when lg.unit_weight_kg is not null then round(pl.base_qty * lg.unit_weight_kg, 4) end,
                    case when public._landed_unit_w97(coalesce(it.base_unit, it.unit)) is not null then round(pl.base_qty * public._landed_unit_w97(coalesce(it.base_unit, it.unit)), 4) end) as weight,
           case when nullif(bx.weight_kg, 0) is not null then 'line' when lg.unit_weight_kg is not null then 'item' when public._landed_unit_w97(coalesce(it.base_unit, it.unit)) is not null then 'unit' end as weight_src,
           coalesce(nullif(bx.volume_l, 0), case when lg.unit_volume_l is not null then round(pl.base_qty * lg.unit_volume_l, 4) end,
                    case when public._landed_unit_v97(coalesce(it.base_unit, it.unit)) is not null then round(pl.base_qty * public._landed_unit_v97(coalesce(it.base_unit, it.unit)), 4) end) as volume,
           case when nullif(bx.volume_l, 0) is not null then 'line' when lg.unit_volume_l is not null then 'item' when public._landed_unit_v97(coalesce(it.base_unit, it.unit)) is not null then 'unit' end as volume_src,
           bx.manual_pct as pct,
           (pl.item_id is not null and coalesce(it.tracked, false) and coalesce(it.count_in_business, false) and coalesce(pl.base_qty, 0) > 0) as in_scope,
           case when pl.item_id is null then 'no_item' when not coalesce(it.tracked, false) then 'not_tracked' when not coalesce(it.count_in_business, false) then 'not_counted' when coalesce(pl.base_qty, 0) <= 0 then 'no_qty' end as why_out
    from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id left join public.items it on it.id = pl.item_id
    left join lateral (select x.weight_kg, x.volume_l, x.manual_pct from jsonb_to_recordset(coalesce(p_basis, '[]'::jsonb)) as x(bill_line_id bigint, weight_kg numeric, volume_l numeric, manual_pct numeric)
                        where x.bill_line_id = pl.id limit 1) bx on true
    left join public.item_logistics lg on lg.item_id = pl.item_id
    where b.id = any (p_bills) and b.kind = 'bill' and b.status = 'posted') z;
$$;

-- charges: validate, convert the currency, add the charge type (treatment, expense key, default method)
create or replace function public._landed_norm_charges97(p_charges jsonb, p_check_active boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e jsonb; n int := 0; out jsonb := '[]'::jsonb; t public.cost_charge_types; base text := upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT'));
        cc text; rt numeric; ac numeric; am numeric; meth text; pm text; sup uuid;
begin
  if p_charges is null or jsonb_typeof(p_charges) <> 'array' then return '[]'::jsonb; end if;
  for e in select * from jsonb_array_elements(p_charges) loop
    n := n + 1;
    if jsonb_typeof(e) <> 'object' then raise exception 'bad_charge'; end if;
    select * into t from public.cost_charge_types where code = e->>'charge_type' and (active or not p_check_active);
    if not found then raise exception 'bad_charge_type'; end if;
    cc := upper(coalesce(nullif(btrim(e->>'ccy'), ''), base));
    if cc !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
    begin ac := coalesce(nullif(e->>'amount_ccy', ''), nullif(e->>'amount', ''))::numeric; exception when others then raise exception 'bad_amount'; end;
    if ac is null or ac = 0 or abs(ac) > 1000000000000 then raise exception 'bad_amount'; end if;
    if cc = base then rt := 1;
    else
      begin rt := nullif(e->>'rate', '')::numeric; exception when others then raise exception 'bad_rate'; end;
      if rt is null then raise exception 'rate_required' using hint = 'Type the exchange rate for ' || cc; end if;
      if not (rt > 0 and rt <= 1000000000) then raise exception 'bad_rate'; end if;
    end if;
    am := round(ac * rt, 2);
    if am = 0 then raise exception 'bad_amount'; end if;
    meth := nullif(e->>'alloc_method', '');
    if meth is not null and meth not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
    pm := coalesce(nullif(e->>'pay_mode', ''), 'payable');
    if pm not in ('payable', 'cash', 'bank', 'mobile') then raise exception 'bad_pay_mode'; end if;
    begin sup := nullif(e->>'supplier_id', '')::uuid; exception when others then raise exception 'bad_supplier'; end;
    if sup is not null and not exists (select 1 from public.suppliers where id = sup) then raise exception 'supplier_not_found'; end if;
    out := out || jsonb_build_object('i', n, 'charge_type', t.code, 'treatment', t.treatment, 'expense_key', coalesce(t.expense_key, 'exp_other'), 'default_alloc', t.default_alloc,
      'name_bn', t.name_bn, 'name_en', t.name_en, 'name_mix', coalesce(t.name_mix, t.name_en), 'amount_ccy', ac, 'ccy', cc, 'rate', rt, 'amount', am, 'alloc_method', meth, 'pay_mode', pm,
      'supplier_id', sup, 'ref_no', left(nullif(btrim(e->>'ref_no'), ''), 60), 'note', left(nullif(btrim(e->>'note'), ''), 200));
  end loop;
  return out;
end $$;

-- which allocation methods can be used for these (stocked) lines; unknown weight / volume / % is reported, never guessed
create or replace function public._landed_avail97(p_rows jsonb) returns jsonb
language plpgsql immutable as $$
declare r jsonb; n int := 0; q numeric := 0; v numeric := 0; w numeric := 0; vo numeric := 0; p numeric := 0;
        nw int := 0; nv int := 0; np int := 0; units text[] := '{}'; mixed boolean := false; wl jsonb := '[]'::jsonb; vl jsonb := '[]'::jsonb; pl jsonb := '[]'::jsonb; out jsonb := '{}'::jsonb;
begin
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop
    n := n + 1; q := q + coalesce((r->>'base_qty')::numeric, 0); v := v + coalesce((r->>'value')::numeric, 0);
    if not (coalesce(r->>'unit', '') = any (units)) then units := units || coalesce(r->>'unit', ''); end if;
    if r->>'weight' is null then wl := wl || to_jsonb(coalesce(r->>'code', '?')); else nw := nw + 1; w := w + (r->>'weight')::numeric; end if;
    if r->>'volume' is null then vl := vl || to_jsonb(coalesce(r->>'code', '?')); else nv := nv + 1; vo := vo + (r->>'volume')::numeric; end if;
    if r->>'pct' is null then pl := pl || to_jsonb(coalesce(r->>'code', '?')); else np := np + 1; p := p + (r->>'pct')::numeric; end if;
  end loop;
  mixed := coalesce(array_length(units, 1), 0) > 1;
  out := jsonb_build_object(
    'lines', n,
    'qty', jsonb_build_object('ok', n = 1 or q > 0, 'why', case when n > 1 and q <= 0 then 'qty_zero' end, 'mixed_units', mixed),
    'value', jsonb_build_object('ok', n = 1 or v > 0, 'why', case when n > 1 and v <= 0 then 'value_zero' end),
    'weight', jsonb_build_object('ok', n = 1 or (nw = n and w > 0), 'why', case when n > 1 and nw < n then 'weight_unknown' when n > 1 and w <= 0 then 'weight_zero' end, 'missing', case when n > 1 and nw < n then wl else '[]'::jsonb end),
    'volume', jsonb_build_object('ok', n = 1 or (nv = n and vo > 0), 'why', case when n > 1 and nv < n then 'volume_unknown' when n > 1 and vo <= 0 then 'volume_zero' end, 'missing', case when n > 1 and nv < n then vl else '[]'::jsonb end),
    'manual', jsonb_build_object('ok', n = 1 or (np = n and abs(p - 100) <= 0.01), 'why', case when n > 1 and np < n then 'manual_missing' when n > 1 and abs(p - 100) > 0.01 then 'manual_sum' end, 'sum', p, 'missing', case when n > 1 and np < n then pl else '[]'::jsonb end),
    'equal', jsonb_build_object('ok', n >= 1, 'why', case when n < 1 then 'no_lines' end));
  return out;
end $$;

-- the weights of one method over the stocked lines (error method_unavailable:<m> when a number is unknown)
create or replace function public._landed_weights97(p_rows jsonb, p_method text, p_avail jsonb) returns numeric[]
language plpgsql immutable as $$
declare r jsonb; w numeric[] := '{}'; n int := 0;
begin
  if p_method not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  if not coalesce((p_avail->p_method->>'ok')::boolean, false) then raise exception 'method_unavailable:%', p_method using detail = coalesce(p_avail->p_method->>'why', ''); end if;
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop
    n := n + 1;
    if (p_avail->>'lines')::int = 1 then w[n] := 1;
    else w[n] := case p_method when 'qty' then (r->>'base_qty')::numeric when 'value' then (r->>'value')::numeric when 'weight' then (r->>'weight')::numeric
                               when 'volume' then (r->>'volume')::numeric when 'manual' then (r->>'pct')::numeric else 1 end;
    end if;
  end loop;
  return w;
end $$;

-- spread every charge: [{ci, bl (bill line id or null), amt, method}] . method_force replaces every method (used for the side-by-side preview)
create or replace function public._landed_spread97(p_rows jsonb, p_charges jsonb, p_header_method text, p_force text, p_avail jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; out jsonb := '[]'::jsonb; ids bigint[] := '{}'; r jsonb; n int := 0; w numeric[]; parts numeric[]; m text; i int;
begin
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop n := n + 1; ids[n] := (r->>'bill_line_id')::bigint; end loop;
  for c in select * from jsonb_array_elements(p_charges) loop
    if c->>'treatment' <> 'capitalise' then
      out := out || jsonb_build_object('ci', (c->>'i')::int, 'bl', null, 'amt', (c->>'amount')::numeric, 'method', null);
      continue;
    end if;
    if n = 0 then raise exception 'no_stock_lines' using hint = 'None of the lines is a counted, tracked item'; end if;
    m := coalesce(p_force, nullif(c->>'alloc_method', ''), p_header_method);
    w := public._landed_weights97(p_rows, m, p_avail);
    parts := public._landed_split97((c->>'amount')::numeric, w);
    for i in 1 .. n loop
      out := out || jsonb_build_object('ci', (c->>'i')::int, 'bl', ids[i], 'amt', parts[i], 'method', m);
    end loop;
  end loop;
  return out;
end $$;

-- the stock plan: per item and place, how much of the capitalised charge goes into the stock cost and how much is already sold (variance). Reads balances (the poster locks them first).
create or replace function public._landed_plan97(p_rows jsonb, p_charges jsonb, p_spread jsonb, p_late text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g record; items jsonb := '[]'::jsonb; rowsout jsonb := '[]'::jsonb; a record; bal public.stock_balance; on_hand numeric; av numeric; q numeric; amt numeric; stk numeric; flag text; late_q numeric;
        phi numeric; s numeric; sum_s numeric; ik text; ct jsonb; avg_after numeric; mode_ text := coalesce(p_late, 'split_remaining_and_cogs');
begin
  if mode_ not in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account') then raise exception 'bad_late_mode'; end if;
  -- charges that are not capitalised: one row each, no stock
  for a in select s2 from jsonb_array_elements(p_spread) s2 where (s2->>'bl') is null loop
    ct := (select c from jsonb_array_elements(p_charges) c where (c->>'i')::int = (a.s2->>'ci')::int);
    rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', null, 'item_id', null, 'loc', (select (x->>'loc')::int from jsonb_array_elements(p_rows) x limit 1),
      'part', case when ct->>'treatment' = 'recoverable_tax' then 'tax' else 'expense' end, 'amount', (a.s2->>'amt')::numeric,
      'dr_key', case when ct->>'treatment' = 'recoverable_tax' then 'vat_input' else ct->>'expense_key' end, 'method', null);
  end loop;
  -- stocked items
  for g in
    select (x->>'item_id')::uuid as item_id, (x->>'loc')::int as loc, max(x->>'item_type') as item_type, sum((x->>'base_qty')::numeric) as q
      from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean group by 1, 2 order by 1, 2 loop
    select * into bal from public.stock_balance where item_id = g.item_id and location_id = g.loc;
    on_hand := greatest(coalesce(bal.qty, 0), 0); av := bal.avg_cost; q := g.q; flag := null;
    select coalesce(sum((s2->>'amt')::numeric), 0) into amt from jsonb_array_elements(p_spread) s2
      where (s2->>'bl') is not null and (s2->>'bl')::bigint in (select (x->>'bill_line_id')::bigint from jsonb_array_elements(p_rows) x where (x->>'item_id')::uuid = g.item_id and (x->>'loc')::int = g.loc and (x->>'in_scope')::boolean);
    late_q := greatest(q - on_hand, 0);
    if amt = 0 then stk := 0;
    elsif late_q <= 0.0005 then stk := amt;
    elsif mode_ = 'post_to_remaining_stock' then stk := case when on_hand > 0 then amt else 0 end;
    elsif mode_ = 'split_remaining_and_cogs' then stk := round(amt * on_hand / q, 2);
    else stk := 0; end if;
    if stk <> 0 and (on_hand <= 0 or av is null) then stk := 0; flag := case when av is null and on_hand > 0 then 'avg_unknown' else 'no_stock_left' end; end if;
    if stk < 0 and on_hand > 0 and av is not null then
      if -stk > round(on_hand * av, 2) then stk := -round(on_hand * av, 2); flag := 'credit_capped'; end if;
    end if;
    if late_q > 0.0005 then flag := coalesce(flag || ',', '') || 'late'; end if;
    phi := case when amt = 0 then 0 else stk / amt end; sum_s := 0;
    ik := public._acct_inv_key(g.item_type);
    for a in select s2, x from jsonb_array_elements(p_spread) s2 join jsonb_array_elements(p_rows) x on (s2->>'bl') is not null and (s2->>'bl')::bigint = (x->>'bill_line_id')::bigint
               where (x->>'item_id')::uuid = g.item_id and (x->>'loc')::int = g.loc and (x->>'in_scope')::boolean loop
      s := round((a.s2->>'amt')::numeric * phi, 2); sum_s := sum_s + s;
      if s <> 0 then
        rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', (a.s2->>'bl')::bigint, 'item_id', g.item_id, 'loc', g.loc, 'part', 'stock', 'amount', s, 'dr_key', ik, 'method', a.s2->>'method');
      end if;
      if (a.s2->>'amt')::numeric - s <> 0 then
        rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', (a.s2->>'bl')::bigint, 'item_id', g.item_id, 'loc', g.loc, 'part', 'cogs', 'amount', (a.s2->>'amt')::numeric - s, 'dr_key', 'landed_variance', 'method', a.s2->>'method');
      end if;
    end loop;
    avg_after := case when sum_s <> 0 and on_hand > 0 and av is not null then round((on_hand * av + sum_s) / on_hand, 6) end;
    items := items || jsonb_build_object('item_id', g.item_id, 'loc', g.loc, 'lot_qty', q, 'on_hand', on_hand, 'avg', av, 'late_qty', late_q, 'amount', amt, 'stock', sum_s, 'cogs', amt - sum_s, 'avg_after', avg_after, 'flags', flag);
  end loop;
  return jsonb_build_object('items', items, 'rows', rowsout, 'late_mode', mode_);
end $$;
revoke all on function public._landed_ok97(integer, text), public._landed_unit_w97(text), public._landed_unit_v97(text), public._landed_split97(numeric, numeric[]), public._landed_rows97(uuid[], jsonb),
  public._landed_norm_charges97(jsonb, boolean), public._landed_avail97(jsonb), public._landed_weights97(jsonb, text, jsonb), public._landed_spread97(jsonb, jsonb, text, text, jsonb),
  public._landed_plan97(jsonb, jsonb, jsonb, text) from public, anon, authenticated;

-- ============================================================
-- messages (bn / mix / en) used by the recommendation. English strings carry no Bangla character.
-- ============================================================
create or replace function public._landed_msg97(p_code text, p_a text default null, p_b text default null) returns jsonb
language sql immutable as $$
  select case p_code
    when 'm_weight' then jsonb_build_object('bn', 'Freight ওজন ধরে ভাগ করাই ভালো: সব line-এর ওজন জানা আছে।', 'mix', 'Freight weight ধরে ভাগ করাই ভালো: সব line-এর weight জানা আছে।', 'en', 'Freight is best spread by weight: every line has a known weight.')
    when 'm_volume' then jsonb_build_object('bn', 'আয়তন ধরে ভাগ করা ভালো: সব line-এর আয়তন জানা আছে।', 'mix', 'Volume ধরে ভাগ করা ভালো: সব line-এর volume জানা আছে।', 'en', 'Best spread by volume: every line has a known volume.')
    when 'm_value' then jsonb_build_object('bn', 'দাম ধরে ভাগ: দামি মালের উপর খরচ বেশি পড়ে।', 'mix', 'Value ধরে ভাগ: দামি মালে charge বেশি পড়ে।', 'en', 'Spread by value: costly goods carry more of the charge.')
    when 'm_qty' then jsonb_build_object('bn', 'পরিমাণ ধরে ভাগ: প্রতি একক সমান খরচ।', 'mix', 'Qty ধরে ভাগ: প্রতি unit সমান charge।', 'en', 'Spread by quantity: every unit carries the same.')
    when 'm_equal' then jsonb_build_object('bn', 'প্রতি line-এ সমান ভাগ।', 'mix', 'প্রতি line-এ equal ভাগ।', 'en', 'The same share for every line.')
    when 'm_weight_fallback' then jsonb_build_object('bn', 'ওজন ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর ওজন জানা নেই (অনুমান করা হয়নি), তাই দাম ধরা হলো। ওজন লিখলে ওজন ধরে ভাগ হবে।', 'mix', 'Weight ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর weight জানা নেই (অনুমান করা হয়নি), তাই value ধরা হলো। Weight লিখলে weight ধরে ভাগ হবে।', 'en', 'Weight would be best, but the weight of some lines is unknown (it is never guessed), so value is used. Enter the weights to spread by weight.')
    when 'm_volume_fallback' then jsonb_build_object('bn', 'আয়তন ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর আয়তন জানা নেই (অনুমান করা হয়নি), তাই দাম ধরা হলো।', 'mix', 'Volume ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর volume জানা নেই (অনুমান করা হয়নি), তাই value ধরা হলো।', 'en', 'Volume would be best, but the volume of some lines is unknown (it is never guessed), so value is used.')
    when 'm_qty_mixed' then jsonb_build_object('bn', 'Line গুলোর একক আলাদা (কেজি, পিস ...), তাই পরিমাণ ধরে ভাগ অর্থহীন; দাম ধরা হলো।', 'mix', 'Line গুলোর unit আলাদা (kg, pcs ...), তাই qty ধরে ভাগ অর্থহীন; value ধরা হলো।', 'en', 'The lines use different units (kg, pieces ...), so a split by quantity is not meaningful; value is used.')
    when 'm_single' then jsonb_build_object('bn', 'শুধু একটি stock line আছে: পুরো খরচ সেটার উপরই পড়বে, পদ্ধতি যাই হোক।', 'mix', 'শুধু একটি stock line আছে: পুরো charge সেটার উপরই পড়বে, method যাই হোক।', 'en', 'There is only one stocked line: the whole charge goes to it, whatever the method.')
    when 'w_late' then jsonb_build_object('bn', 'এই lot-এর ' || coalesce(p_a, '?') || ' একক আগেই বিক্রি বা ব্যবহার হয়ে গেছে। "ভাগ করে" পদ্ধতিতে বিক্রি হওয়া অংশ লাভ-ক্ষতিতে (landed variance) যাবে, শুধু বাকিটা stock cost-এ।', 'mix', 'এই lot-এর ' || coalesce(p_a, '?') || ' unit আগেই sold বা used হয়ে গেছে। Split করলে sold অংশ P&L-এ (landed variance) যাবে, শুধু বাকিটা stock cost-এ।', 'en', coalesce(p_a, '?') || ' units of this lot are already sold or used. With a split, the sold part goes to the landed-cost variance (profit and loss) and only the rest into stock cost.')
    when 'w_late_all' then jsonb_build_object('bn', 'এই lot-এর সব মাল বিক্রি হয়ে গেছে, stock-এ কিছু নেই: পুরো খরচ variance খাতে যাওয়াই যুক্তিসঙ্গত।', 'mix', 'এই lot-এর সব মাল sold, stock-এ কিছু নেই: পুরো charge variance account-এ যাওয়াই যুক্তিসঙ্গত।', 'en', 'All of this lot is already sold and nothing is left in stock: the whole charge belongs in the variance account.')
    when 'w_weight_unknown' then jsonb_build_object('bn', 'ওজন জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না — line-এর ওজন বা item-এর ওজন লিখুন।', 'mix', 'Weight জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না — line-এর weight বা item-এর weight লিখুন।', 'en', 'Weight is unknown for: ' || coalesce(p_a, '') || '. It is not guessed: enter the line weight or the item weight.')
    when 'w_volume_unknown' then jsonb_build_object('bn', 'আয়তন জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না।', 'mix', 'Volume জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না।', 'en', 'Volume is unknown for: ' || coalesce(p_a, '') || '. It is not guessed.')
    when 'w_fx' then jsonb_build_object('bn', 'কোনো খরচ বিদেশি মুদ্রায়: আপনার লেখা রূপান্তর হার (rate) আবার দেখে নিন।', 'mix', 'কোনো charge foreign currency-তে: আপনার লেখা rate আবার দেখে নিন।', 'en', 'A charge is in a foreign currency: check the exchange rate you typed.')
    when 'w_avg_unknown' then jsonb_build_object('bn', 'কোনো item-এর গড় cost জানা নেই, তাই তার ভাগ stock-এ যোগ হবে না (variance খাতে যাবে)।', 'mix', 'কোনো item-এর average cost জানা নেই, তাই তার ভাগ stock-এ যোগ হবে না (variance account-এ যাবে)।', 'en', 'The average cost of an item is unknown, so its share is not added to stock (it goes to the variance account).')
    when 'w_no_stock' then jsonb_build_object('bn', 'এই বিলগুলোতে গোনা ও tracked কোনো item নেই: stock-এ কিছু যোগ করার নেই।', 'mix', 'এই bill গুলোতে counted ও tracked কোনো item নেই: stock-এ কিছু যোগ করার নেই।', 'en', 'There is no counted, tracked item in these bills: nothing can be added to stock.')
    when 'w_untracked' then jsonb_build_object('bn', coalesce(p_a, '0') || 'টি line stock item নয়, সেগুলো ভাগ পায় না।', 'mix', coalesce(p_a, '0') || 'টি line stock item নয়, সেগুলো ভাগ পায় না।', 'en', coalesce(p_a, '0') || ' line(s) are not stock items, so they take no share.')
    when 'w_noncap' then jsonb_build_object('bn', 'কিছু খরচ মালের দামে যোগ হয় না (শুধু খরচ বা ফেরতযোগ্য কর): সেগুলো সরাসরি হিসাবে যায়।', 'mix', 'কিছু charge item cost-এ যোগ হয় না (expense only বা recoverable tax): সেগুলো সরাসরি accounts-এ যায়।', 'en', 'Some charges are not added to item cost (expense only or recoverable tax): they go straight to the accounts.')
    when 'w_credit_capped' then jsonb_build_object('bn', 'ঋণাত্মক খরচ (ফেরত) stock-এর মূল্যের চেয়ে বেশি ছিল, তাই বাকিটা variance খাতে গেছে।', 'mix', 'Negative charge (refund) stock value-র চেয়ে বেশি ছিল, তাই বাকিটা variance account-এ গেছে।', 'en', 'A negative charge (refund) was larger than the stock value, so the rest goes to the variance account.')
    when 'w_nocap' then jsonb_build_object('bn', 'কোনো খরচ মালের দামে যোগ হচ্ছে না, তাই এখানে ভাগ করার কিছু নেই।', 'mix', 'কোনো charge item cost-এ যোগ হচ্ছে না, তাই এখানে ভাগ করার কিছু নেই।', 'en', 'No charge is added to item cost, so there is nothing to spread.')
    else jsonb_build_object('bn', coalesce(p_code, ''), 'mix', coalesce(p_code, ''), 'en', coalesce(p_code, ''))
  end;
$$;
revoke all on function public._landed_msg97(text, text, text) from public, anon, authenticated;

-- the recommendation, from the numbers only
create or replace function public._landed_reco97(p_rows jsonb, p_charges jsonb, p_avail jsonb, p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; n int := (p_avail->>'lines')::int; per jsonb := '[]'::jsonb; reasons jsonb := '[]'::jsonb; warns jsonb := '[]'::jsonb; pref text; m text; rc text; big numeric := -1; hdr text;
        it jsonb; late_total numeric := 0; late_all boolean := true; any_late boolean := false; late_rec text; miss text; ncap int := 0; nuntr int; fx boolean := false; nonc boolean := false;
        flags text; rule_late text := coalesce(public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs');
begin
  select count(*) into nuntr from jsonb_array_elements(p_rows) x where not (x->>'in_scope')::boolean;
  if n = 0 then
    warns := warns || (public._landed_msg97('w_no_stock') || jsonb_build_object('code', 'no_stock_lines'));
    return jsonb_build_object('method', null, 'per_charge', '[]'::jsonb, 'late_mode', rule_late, 'reasons', reasons, 'warnings', warns);
  end if;
  for c in select * from jsonb_array_elements(p_charges) loop
    if c->>'ccy' <> upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT')) then fx := true; end if;
    if c->>'treatment' <> 'capitalise' then nonc := true; continue; end if;
    ncap := ncap + 1;
    pref := coalesce(c->>'default_alloc', public.rule_txt('landed_alloc_default'), 'value'); if pref = 'manual' then pref := 'value'; end if;
    m := pref; rc := 'm_' || pref;
    if n = 1 then m := 'value'; rc := 'm_single';
    elsif pref in ('weight', 'volume') and not coalesce((p_avail->pref->>'ok')::boolean, false) then
      m := 'value'; rc := 'm_' || pref || '_fallback';
      miss := (select string_agg(v, ', ') from jsonb_array_elements_text(p_avail->pref->'missing') v);
      if not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_' || pref || '_unknown') then
        warns := warns || (public._landed_msg97('w_' || pref || '_unknown', coalesce(miss, '')) || jsonb_build_object('code', 'w_' || pref || '_unknown', 'items', p_avail->pref->'missing'));
      end if;
    elsif pref = 'qty' and coalesce((p_avail->'qty'->>'mixed_units')::boolean, false) then m := 'value'; rc := 'm_qty_mixed';
    end if;
    if m = 'value' and not coalesce((p_avail->'value'->>'ok')::boolean, false) then m := 'equal'; rc := 'm_equal'; end if;
    per := per || jsonb_build_object('i', (c->>'i')::int, 'charge_type', c->>'charge_type', 'method', m, 'reason', public._landed_msg97(rc) || jsonb_build_object('code', rc));
    if abs((c->>'amount')::numeric) > big then big := abs((c->>'amount')::numeric); hdr := m; end if;
  end loop;
  if hdr is null then
    hdr := coalesce(public.rule_txt('landed_alloc_default'), 'value');
    if hdr = 'manual' or not coalesce((p_avail->hdr->>'ok')::boolean, false) then hdr := 'value'; end if;
    if jsonb_array_length(p_charges) > 0 and ncap = 0 then warns := warns || (public._landed_msg97('w_nocap') || jsonb_build_object('code', 'w_nocap')); end if;
  end if;
  -- the chosen header method explained once (the reason of the biggest capitalised charge)
  select p->'reason' into it from jsonb_array_elements(per) p where p->>'method' = hdr order by (case when (p->>'i')::int is not null then 0 end) limit 1;
  if it is not null then reasons := reasons || it; end if;
  -- late goods
  for it in select * from jsonb_array_elements(p_items) loop
    if (it->>'late_qty')::numeric > 0.0005 then any_late := true; late_total := late_total + (it->>'late_qty')::numeric; if (it->>'on_hand')::numeric > 0 then late_all := false; end if; end if;
  end loop;
  late_rec := rule_late;
  if any_late then
    late_rec := case when late_all then 'variance_account' else 'split_remaining_and_cogs' end;
    warns := warns || (public._landed_msg97(case when late_all then 'w_late_all' else 'w_late' end, trim_scale(late_total)::text) || jsonb_build_object('code', case when late_all then 'late_all_sold' else 'late_goods_sold' end, 'qty', late_total));
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    flags := it->>'flags';
    if flags like '%avg_unknown%' and not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_avg_unknown') then warns := warns || (public._landed_msg97('w_avg_unknown') || jsonb_build_object('code', 'w_avg_unknown')); end if;
    if flags like '%credit_capped%' and not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_credit_capped') then warns := warns || (public._landed_msg97('w_credit_capped') || jsonb_build_object('code', 'w_credit_capped')); end if;
  end loop;
  if fx then warns := warns || (public._landed_msg97('w_fx') || jsonb_build_object('code', 'w_fx')); end if;
  if nuntr > 0 then warns := warns || (public._landed_msg97('w_untracked', nuntr::text) || jsonb_build_object('code', 'w_untracked', 'count', nuntr)); end if;
  if nonc then warns := warns || (public._landed_msg97('w_noncap') || jsonb_build_object('code', 'w_noncap')); end if;
  return jsonb_build_object('method', hdr, 'per_charge', per, 'late_mode', late_rec, 'reasons', reasons, 'warnings', warns, 'late_qty', late_total);
end $$;
revoke all on function public._landed_reco97(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- the whole picture for a set of bills + charges (no writes)
create or replace function public._landed_calc97(p_bills uuid[], p_charges jsonb, p_basis jsonb, p_method text, p_late text, p_check boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; chg jsonb; av jsonb; hm text; lm text; sp jsonb; pl jsonb; mx jsonb := '{}'::jsonb; m text; sx jsonb; lines_ jsonb := '[]'::jsonb; r jsonb; per jsonb; chosen jsonb;
        cap numeric := 0; exp_ numeric := 0; tax numeric := 0; err text := null; reco jsonb; nb int; c jsonb; la numeric; uadd numeric;
begin
  rows_ := public._landed_rows97(p_bills, p_basis);
  select count(distinct x->>'bill_id') into nb from jsonb_array_elements(rows_) x;
  if nb <> (select count(distinct b) from unnest(p_bills) b) then raise exception 'bill_not_found' using hint = 'Only posted purchase bills (not returns) can take a landed cost'; end if;
  chg := public._landed_norm_charges97(p_charges, p_check);
  av := public._landed_avail97(rows_);
  hm := coalesce(p_method, public.rule_txt('landed_alloc_default'), 'value');
  if hm not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  lm := coalesce(p_late, public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs');
  for c in select * from jsonb_array_elements(chg) loop
    if c->>'treatment' = 'capitalise' then cap := cap + (c->>'amount')::numeric; elsif c->>'treatment' = 'expense_only' then exp_ := exp_ + (c->>'amount')::numeric; else tax := tax + (c->>'amount')::numeric; end if;
  end loop;
  -- every method side by side (all capitalised charges spread by that one method)
  if cap <> 0 or exists (select 1 from jsonb_array_elements(chg) x where x->>'treatment' = 'capitalise') then
    foreach m in array array['qty', 'value', 'weight', 'volume', 'manual', 'equal'] loop
      if coalesce((av->m->>'ok')::boolean, false) and (av->>'lines')::int > 0 then
        sx := public._landed_spread97(rows_, chg, hm, m, av);
        mx := mx || jsonb_build_object(m, (select coalesce(jsonb_object_agg(bl::text, a), '{}'::jsonb) from (select (e->>'bl')::bigint bl, sum((e->>'amt')::numeric) a from jsonb_array_elements(sx) e where (e->>'bl') is not null group by 1) q));
      end if;
    end loop;
  end if;
  -- the saved / chosen way (charge overrides honoured)
  begin
    sp := public._landed_spread97(rows_, chg, hm, null, av);
    pl := public._landed_plan97(rows_, chg, sp, lm);
  exception when others then
    err := sqlerrm; sp := '[]'::jsonb; pl := jsonb_build_object('items', '[]'::jsonb, 'rows', '[]'::jsonb, 'late_mode', lm);
  end;
  for r in select * from jsonb_array_elements(rows_) loop
    per := '{}'::jsonb;
    if (r->>'in_scope')::boolean then
      foreach m in array array['qty', 'value', 'weight', 'volume', 'manual', 'equal'] loop
        if mx ? m then
          la := coalesce((mx->m->>(r->>'bill_line_id'))::numeric, 0); uadd := round(la / (r->>'base_qty')::numeric, 6);
          per := per || jsonb_build_object(m, jsonb_build_object('alloc', la, 'unit_add', uadd, 'new_unit_cost', round((r->>'ucb_net')::numeric + uadd, 6),
                   'pct_up', case when (r->>'ucb_net')::numeric > 0 then round(uadd / (r->>'ucb_net')::numeric * 100, 2) end));
        end if;
      end loop;
      la := coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint), 0);
      uadd := round(la / (r->>'base_qty')::numeric, 6);
      chosen := jsonb_build_object('alloc', la, 'unit_add', uadd, 'new_unit_cost', round((r->>'ucb_net')::numeric + uadd, 6),
                   'stock', coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint and e->>'part' = 'stock'), 0),
                   'cogs', coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint and e->>'part' = 'cogs'), 0));
    else chosen := null; end if;
    lines_ := lines_ || (r - 'item_type' || jsonb_build_object('methods', per, 'chosen', chosen));
  end loop;
  reco := public._landed_reco97(rows_, chg, av, pl->'items');
  return jsonb_build_object('ok', err is null, 'error', err, 'method', hm, 'late_mode', lm, 'avail', av, 'lines', lines_, 'items', pl->'items',
    'charges', (select coalesce(jsonb_agg(ch - 'name_mix' - 'expense_key' - 'default_alloc'), '[]'::jsonb) from jsonb_array_elements(chg) ch),
    'totals', jsonb_build_object('capitalised', cap, 'expense_only', exp_, 'recoverable_tax', tax, 'all', cap + exp_ + tax),
    'recommendation', reco, '_plan', pl, '_chg', chg, '_rows', rows_, '_spread', sp);
end $$;
revoke all on function public._landed_calc97(uuid[], jsonb, jsonb, text, text, boolean) from public, anon, authenticated;

-- ============================================================
-- public RPCs
-- ============================================================
create or replace function public.landed_preview(p_bills uuid[], p_charges jsonb default '[]'::jsonb, p_basis jsonb default '[]'::jsonb, p_method text default null, p_late text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int; locs int[]; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_bills is null or coalesce(array_length(p_bills, 1), 0) = 0 then raise exception 'no_bills'; end if;
  select array_agg(distinct location_id) into locs from public.purchase_bills where id = any (p_bills);
  if locs is null or array_length(locs, 1) <> 1 then raise exception 'bill_not_found' using hint = 'The bills must exist and belong to one place'; end if;
  loc := locs[1];
  if not public._landed_ok97(loc, 'entry') then raise exception 'not allowed'; end if;
  r := public._landed_calc97(p_bills, p_charges, p_basis, p_method, p_late);
  return (r - '_plan' - '_chg' - '_rows' - '_spread') || jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'location_id', loc);
end $$;

create or replace function public.landed_recommendation(p_bills uuid[] default null, p_cost uuid default null, p_charges jsonb default null, p_basis jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bills uuid[] := p_bills; chg jsonb := p_charges; bs jsonb := p_basis; h public.landed_costs; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_cost is not null then
    select * into h from public.landed_costs where id = p_cost;
    if not found then raise exception 'not found'; end if;
    if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
    bills := array(select bill_id from public.landed_cost_docs where cost_id = p_cost);
    chg := coalesce(chg, (select coalesce(jsonb_agg(jsonb_build_object('charge_type', l.charge_type, 'amount_ccy', l.amount_ccy, 'ccy', l.ccy, 'rate', l.rate, 'alloc_method', l.alloc_method, 'pay_mode', l.pay_mode, 'supplier_id', l.supplier_id) order by l.line_no), '[]'::jsonb) from public.landed_cost_lines l where l.cost_id = p_cost));
    bs := coalesce(bs, (select coalesce(jsonb_agg(jsonb_build_object('bill_line_id', b.bill_line_id, 'weight_kg', b.weight_kg, 'volume_l', b.volume_l, 'manual_pct', b.manual_pct)), '[]'::jsonb) from public.landed_cost_basis b where b.cost_id = p_cost));
  end if;
  if bills is null or coalesce(array_length(bills, 1), 0) = 0 then raise exception 'no_bills'; end if;
  if p_cost is null and not exists (select 1 from public.purchase_bills b where b.id = any (bills) and public._landed_ok97(b.location_id, 'entry')) then raise exception 'not allowed'; end if;
  r := public._landed_calc97(bills, coalesce(chg, '[]'::jsonb), coalesce(bs, '[]'::jsonb), case when p_cost is not null then h.alloc_method end, case when p_cost is not null then h.late_mode end);
  return r->'recommendation' || jsonb_build_object('avail', r->'avail', 'totals', r->'totals');
end $$;


-- bills / GRNs the person picked -> the posted purchase bills they stand for (a GRN counts through the bill it is linked to)
create or replace function public._landed_resolve97(p_docs jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; ty text; did uuid; bid uuid; bills uuid[] := '{}'; docrows jsonb := '[]'::jsonb;
begin
  if p_docs is null or jsonb_typeof(p_docs) <> 'array' or jsonb_array_length(p_docs) = 0 then raise exception 'no_bills'; end if;
  for d in select * from jsonb_array_elements(p_docs) loop
    ty := coalesce(d->>'type', 'bill');
    begin did := (d->>'id')::uuid; exception when others then raise exception 'bill_not_found'; end;
    if ty = 'bill' then bid := did;
    elsif ty = 'grn' then
      select x.shadow_id::uuid into bid from public.shadow_links x where x.domain = 'grn' and x.primary_type = 'entries' and x.primary_id = did::text and x.shadow_type = 'purchase_bills' and x.state <> 'void' and x.shadow_id is not null order by x.id limit 1;
      if bid is null then raise exception 'grn_not_linked' using hint = 'Link the GRN to its purchase bill first'; end if;
    else raise exception 'bad_doc_type'; end if;
    if not exists (select 1 from public.purchase_bills where id = bid and kind = 'bill' and status = 'posted') then raise exception 'bill_not_found' using hint = 'Only posted purchase bills (not returns) can take a landed cost'; end if;
    if not (bid = any (bills)) then bills := bills || bid; docrows := docrows || jsonb_build_object('type', ty, 'doc_id', did, 'bill_id', bid); end if;
  end loop;
  return jsonb_build_object('bills', to_jsonb(bills), 'docrows', docrows);
end $$;
revoke all on function public._landed_resolve97(jsonb) from public, anon, authenticated;

create or replace function public.landed_resolve_docs(p_docs jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rs jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  rs := public._landed_resolve97(p_docs);
  if not exists (select 1 from public.purchase_bills b where b.id in (select (x)::uuid from jsonb_array_elements_text(rs->'bills') x) and public._landed_ok97(b.location_id, 'entry')) then raise exception 'not allowed'; end if;
  return rs->'docrows';
end $$;
revoke all on function public.landed_resolve_docs(jsonb) from public, anon;
grant execute on function public.landed_resolve_docs(jsonb) to authenticated;

-- save a draft (also edits a draft / re-opens an approved one). Idempotent on p_client.
create or replace function public.landed_save(p_client uuid, p_id uuid, p_header jsonb, p_docs jsonb, p_lines jsonb, p_basis jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); h public.landed_costs; d jsonb; bills uuid[] := '{}'; docrows jsonb := '[]'::jsonb; loc int; locs int[]; chg jsonb; c jsonb; b jsonb; sid text;
        meth text; late text; cdate date; tot numeric := 0; nid uuid := p_id; n int := 0; ref text; ttl text; nt text; rs jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if mode_ = 'off' then raise exception 'landed_off' using hint = 'Switch landed_cost_mode on first'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and p_id is null then
    select * into h from public.landed_costs where client_id = p_client;
    if found then
      if h.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', h.id, 'status', h.status, 'total', h.total, 'dup', true);
    end if;
  end if;
  if p_docs is null or jsonb_typeof(p_docs) <> 'array' or jsonb_array_length(p_docs) = 0 then raise exception 'no_bills'; end if;
  rs := public._landed_resolve97(p_docs); bills := array(select (x)::uuid from jsonb_array_elements_text(rs->'bills') x); docrows := rs->'docrows';
  select array_agg(distinct location_id) into locs from public.purchase_bills where id = any (bills);
  if array_length(locs, 1) <> 1 then raise exception 'one_place_only' using hint = 'One landed cost covers bills of one place'; end if;
  loc := locs[1];
  if not public._landed_ok97(loc, 'entry') then raise exception 'not allowed'; end if;
  ref := left(nullif(btrim(p_header->>'shipment_ref'), ''), 80);
  if mode_ = 'per_bill' and array_length(bills, 1) <> 1 then raise exception 'per_bill_one_bill' using hint = 'In per_bill mode one landed cost covers one bill'; end if;
  if mode_ = 'per_shipment' and ref is null then raise exception 'shipment_ref_needed' using hint = 'Give the shipment / lot a reference'; end if;
  meth := coalesce(nullif(p_header->>'alloc_method', ''), public.rule_txt('landed_alloc_default'), 'value');
  if meth not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  late := nullif(p_header->>'late_mode', '');
  if late is not null and late not in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account') then raise exception 'bad_late_mode'; end if;
  begin cdate := coalesce(nullif(p_header->>'cost_date', '')::date, (now() at time zone 'Asia/Dhaka')::date); exception when others then raise exception 'bad_date'; end;
  if cdate > (now() at time zone 'Asia/Dhaka')::date + 1 then raise exception 'bad_date'; end if;
  ttl := left(nullif(btrim(p_header->>'title'), ''), 120); nt := left(nullif(btrim(p_header->>'note'), ''), 500);
  chg := public._landed_norm_charges97(p_lines);
  if jsonb_array_length(chg) = 0 then raise exception 'no_charges'; end if;
  for c in select * from jsonb_array_elements(chg) loop tot := tot + (c->>'amount')::numeric; end loop;
  if p_basis is null or jsonb_typeof(p_basis) <> 'array' then p_basis := '[]'::jsonb; end if;
  for b in select * from jsonb_array_elements(p_basis) loop
    if jsonb_typeof(b) <> 'object' or not exists (select 1 from public.purchase_lines l where l.id = nullif(b->>'bill_line_id', '')::bigint and l.bill_id = any (bills)) then raise exception 'bad_basis_line'; end if;
    begin
      if (nullif(b->>'weight_kg', '') is not null and (b->>'weight_kg')::numeric < 0) or (nullif(b->>'volume_l', '') is not null and (b->>'volume_l')::numeric < 0)
         or (nullif(b->>'manual_pct', '') is not null and not ((b->>'manual_pct')::numeric between 0 and 100)) then raise exception 'bad_basis_value'; end if;
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'bad_basis_value'; end;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_id is not null then
    select * into h from public.landed_costs where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    if h.status not in ('draft', 'approved') then raise exception 'not_editable'; end if;
    if h.location_id <> loc then raise exception 'one_place_only'; end if;
    if h.status = 'approved' then update public.landed_costs set status = 'draft', approved_by = null, approved_at = null where id = p_id; end if;
    delete from public.landed_cost_docs where cost_id = p_id; delete from public.landed_cost_lines where cost_id = p_id; delete from public.landed_cost_basis where cost_id = p_id;
    update public.landed_costs set shipment_ref = ref, title = ttl, note = nt, cost_date = cdate, alloc_method = meth, late_mode = late, total = tot, mode_at_save = mode_ where id = p_id;
  else
    insert into public.landed_costs (client_id, location_id, shipment_ref, title, note, cost_date, alloc_method, late_mode, mode_at_save, total, created_by, created_staff)
      values (p_client, loc, ref, ttl, nt, cdate, meth, late, mode_, tot, auth.uid(), sid) returning id into nid;
  end if;
  for d in select * from jsonb_array_elements(docrows) loop
    insert into public.landed_cost_docs (cost_id, bill_id, doc_type, doc_id) values (nid, (d->>'bill_id')::uuid, d->>'type', (d->>'doc_id')::uuid);
  end loop;
  for c in select * from jsonb_array_elements(chg) loop
    n := n + 1;
    insert into public.landed_cost_lines (cost_id, line_no, charge_type, amount_ccy, ccy, rate, amount, alloc_method, pay_mode, supplier_id, ref_no, note)
      values (nid, n, c->>'charge_type', (c->>'amount_ccy')::numeric, c->>'ccy', (c->>'rate')::numeric, (c->>'amount')::numeric, c->>'alloc_method', c->>'pay_mode', nullif(c->>'supplier_id', '')::uuid, c->>'ref_no', c->>'note');
  end loop;
  for b in select * from jsonb_array_elements(p_basis) loop
    insert into public.landed_cost_basis (cost_id, bill_line_id, weight_kg, volume_l, manual_pct)
      values (nid, (b->>'bill_line_id')::bigint, nullif(b->>'weight_kg', '')::numeric, nullif(b->>'volume_l', '')::numeric, nullif(b->>'manual_pct', '')::numeric)
      on conflict (cost_id, bill_line_id) do update set weight_kg = excluded.weight_kg, volume_l = excluded.volume_l, manual_pct = excluded.manual_pct;
  end loop;
  return jsonb_build_object('id', nid, 'status', 'draft', 'total', tot, 'dup', false);
end $$;

-- what the stored draft looks like now (helper for approve / post / get)
create or replace function public._landed_saved97(p_id uuid, p_check_active boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h public.landed_costs; bills uuid[]; chg jsonb; bs jsonb;
begin
  select * into h from public.landed_costs where id = p_id;
  if not found then raise exception 'not found'; end if;
  bills := array(select bill_id from public.landed_cost_docs where cost_id = p_id order by bill_id);
  select coalesce(jsonb_agg(jsonb_build_object('charge_type', l.charge_type, 'amount_ccy', l.amount_ccy, 'ccy', l.ccy, 'rate', l.rate, 'alloc_method', l.alloc_method, 'pay_mode', l.pay_mode,
           'supplier_id', l.supplier_id, 'ref_no', l.ref_no, 'note', l.note) order by l.line_no), '[]'::jsonb) into chg from public.landed_cost_lines l where l.cost_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('bill_line_id', b.bill_line_id, 'weight_kg', b.weight_kg, 'volume_l', b.volume_l, 'manual_pct', b.manual_pct)), '[]'::jsonb) into bs from public.landed_cost_basis b where b.cost_id = p_id;
  return public._landed_calc97(bills, chg, bs, h.alloc_method, h.late_mode, p_check_active) || jsonb_build_object('_bills', to_jsonb(bills));
end $$;
revoke all on function public._landed_saved97(uuid, boolean) from public, anon, authenticated;

-- ---------- journal lines of a landed cost (used by _acct_docs; closed to the browser) ----------
create or replace function public._landed_jlines97(p_id uuid, p_kind text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(j), '[]'::jsonb) from (
    select jsonb_build_object('a', a.dr_key, 'd', a.amount) as j from public.landed_cost_alloc a where a.cost_id = p_id and a.kind = p_kind
    union all
    select jsonb_build_object('a', case l.pay_mode when 'payable' then 'landed_payable' when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'pay_mobile' end, 'c', sum(a.amount),
             'pt', case when l.pay_mode = 'payable' and l.supplier_id is not null then 'supplier' end, 'pid', case when l.pay_mode = 'payable' then l.supplier_id::text end)
      from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id where a.cost_id = p_id and a.kind = p_kind group by l.id, l.pay_mode, l.supplier_id) z;
$$;
revoke all on function public._landed_jlines97(uuid, text) from public, anon, authenticated;

-- the journal of a landed cost lives in _acct_docs (bos97). If phase89 was pasted again after phase97, that block is gone: refuse to post rather than change the stock without the books
create or replace function public._landed_journal_ready97() returns boolean language sql stable security definer set search_path = public as $$
  select position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0;
$$;
revoke all on function public._landed_journal_ready97() from public, anon, authenticated;

-- ---------- approve ----------
create or replace function public.landed_approve(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; s jsonb; req text := coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'approve') then raise exception 'not allowed'; end if;
  if h.status = 'approved' then return jsonb_build_object('id', h.id, 'status', 'approved', 'dup', true); end if;
  if h.status <> 'draft' then raise exception 'not_draft'; end if;
  if req = 'required' and h.created_by = auth.uid() and not public.is_owner() then raise exception 'approver_must_differ' using hint = 'Somebody else approves what you made'; end if;
  s := public._landed_saved97(p_id, false);
  if not (s->>'ok')::boolean then raise exception '%', s->>'error'; end if;      -- e.g. method_unavailable:weight (the weight of some line is unknown)
  update public.landed_costs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'approved');
end $$;

-- ---------- post: spread, add to the stock cost (ledger pair), keep the rows (the journal follows through _acct_docs) ----------
create or replace function public.landed_post(p_id uuid, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); req text := coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn');
        s jsonb; pl jsonb; it jsonb; rw jsonb; stk numeric; q numeric; av numeric; na numeric; lo bigint; li bigint; k text; late_any boolean := false; nrows int := 0; nstock int := 0; sum_stock numeric := 0; sum_cogs numeric := 0;
        cl bigint; cnt int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if h.status = 'posted' then return jsonb_build_object('id', h.id, 'status', 'posted', 'dup', true, 'posted', 0, 'total', h.total); end if;     -- a second press posts nothing
  if p_client is not null and exists (select 1 from public.landed_costs x where x.post_client = p_client and x.id <> h.id) then raise exception 'client_id_taken'; end if;
  if h.status = 'void' then raise exception 'landed_void'; end if;
  if mode_ = 'off' then raise exception 'landed_off' using hint = 'Switch landed_cost_mode on first'; end if;
  if req = 'required' and h.status <> 'approved' then raise exception 'approval_required'; end if;
  perform public.lock_check(h.cost_date);
  if public.rule_on('accounting_on') and not public._landed_journal_ready97() then raise exception 'journal_not_ready' using hint = 'Paste phase97 again (phase89 was pasted after it)'; end if;
  perform 1 from public.stock_balance b where b.location_id = h.location_id
      and b.item_id in (select pl2.item_id from public.landed_cost_docs d join public.purchase_lines pl2 on pl2.bill_id = d.bill_id where d.cost_id = p_id and pl2.item_id is not null) order by b.item_id for update;
  s := public._landed_saved97(p_id, false);
  if not (s->>'ok')::boolean then raise exception '%', s->>'error'; end if;
  pl := s->'_plan';
  if jsonb_array_length(pl->'rows') = 0 then raise exception 'nothing_to_post'; end if;
  if public.rule_on('accounting_on') then       -- the journal needs these accounts; fail now, not later
    for k in select distinct x from (select r->>'dr_key' x from jsonb_array_elements(pl->'rows') r
               union select case l.pay_mode when 'payable' then 'landed_payable' when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'pay_mobile' end from public.landed_cost_lines l where l.cost_id = p_id) z loop
      if not exists (select 1 from public.acct_mappings m where m.key = k) then raise exception 'mapping_missing:%', k; end if;
    end loop;
  end if;
  for rw in select * from jsonb_array_elements(pl->'rows') loop
    select id into cl from public.landed_cost_lines where cost_id = p_id and line_no = (rw->>'ci')::int;
    insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method)
      values (p_id, 'post', cl, nullif(rw->>'bl', '')::bigint, nullif(rw->>'item_id', '')::uuid, h.location_id, rw->>'part', (rw->>'amount')::numeric, rw->>'dr_key', rw->>'method');
    nrows := nrows + 1;
  end loop;
  for it in select * from jsonb_array_elements(pl->'items') loop
    stk := (it->>'stock')::numeric; q := (it->>'on_hand')::numeric; av := nullif(it->>'avg', '')::numeric; na := null; lo := null; li := null;
    if stk <> 0 and q > 0 and av is not null then
      na := round((q * av + stk) / q, 6);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values ((it->>'item_id')::uuid, h.location_id, -q, av, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost: stock out at the old average', auth.uid()) returning id into lo;
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values ((it->>'item_id')::uuid, h.location_id, q, na, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost: stock back in at the new average', auth.uid()) returning id into li;
      nstock := nstock + 1;
    end if;
    insert into public.landed_cost_stock (cost_id, kind, item_id, location_id, lot_qty, on_hand_before, avg_before, avg_after, stock_value, cogs_value, ledger_out, ledger_in, flags)
      values (p_id, 'post', (it->>'item_id')::uuid, h.location_id, (it->>'lot_qty')::numeric, q, av, coalesce(na, av), stk, (it->>'cogs')::numeric, lo, li, it->>'flags');
    sum_stock := sum_stock + stk; sum_cogs := sum_cogs + (it->>'cogs')::numeric;
    if (it->>'late_qty')::numeric > 0.0005 then late_any := true; end if;
  end loop;
  update public.landed_costs set status = 'posted', posted_by = auth.uid(), posted_at = now(), late_mode_used = pl->>'late_mode', post_client = p_client where id = p_id;
  if req = 'warn' and h.status <> 'approved' then
    perform public._stock_exc(h.location_id, 'landed_unapproved', 'yellow', 'Landed cost অনুমোদন ছাড়াই post হয়েছে, মোট ' || h.total::text, 'A landed cost was posted without approval, total ' || h.total::text, null, h.cost_date, 'PURCHASE', h.total);
  end if;
  if late_any then
    perform public._stock_exc(h.location_id, 'landed_late_cost', 'yellow', 'Landed cost এসেছে মাল আংশিক বিক্রি হওয়ার পর (পদ্ধতি: ' || (pl->>'late_mode') || ')', 'A landed cost arrived after part of the goods was sold or used (mode: ' || (pl->>'late_mode') || ')', null, h.cost_date, 'PURCHASE', h.total);
  end if;
  return jsonb_build_object('id', p_id, 'status', 'posted', 'dup', false, 'posted', nrows, 'total', h.total, 'stock_added', sum_stock, 'to_variance', sum_cogs, 'items_adjusted', nstock, 'late', late_any);
end $$;

-- ---------- void (reversal): only the part still on the shelf leaves the stock cost; the sold part is released from the variance account ----------
create or replace function public.landed_void(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; st public.landed_cost_stock; a public.landed_cost_alloc; bal public.stock_balance; q_now numeric; f numeric; v numeric; fac jsonb := '{}'::jsonb; sumv jsonb := '{}'::jsonb;
        sv numeric; lo bigint; li bigint; na numeric; tot_orig numeric; nrows int := 0; ikey text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'approve') then raise exception 'not allowed'; end if;
  if h.status = 'void' then return jsonb_build_object('id', h.id, 'status', 'void', 'dup', true); end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if h.status in ('draft', 'approved') then
    update public.landed_costs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'void', 'reversed_rows', 0);
  end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  perform 1 from public.stock_balance b where b.location_id = h.location_id and b.item_id in (select item_id from public.landed_cost_stock where cost_id = p_id and kind = 'post') order by b.item_id for update;
  for st in select * from public.landed_cost_stock where cost_id = p_id and kind = 'post' order by item_id loop
    select * into bal from public.stock_balance where item_id = st.item_id and location_id = st.location_id;
    q_now := greatest(coalesce(bal.qty, 0), 0);
    if st.stock_value = 0 or q_now <= 0 or bal.avg_cost is null or st.on_hand_before <= 0 then f := 0;
    else
      f := least(1, q_now / st.on_hand_before);
      v := round(st.stock_value * f, 2);
      if v > 0 then v := least(v, round(q_now * bal.avg_cost, 2)); end if;
      f := v / st.stock_value;
    end if;
    fac := fac || jsonb_build_object(st.item_id::text, f);
  end loop;
  for a in select * from public.landed_cost_alloc where cost_id = p_id and kind = 'post' order by id loop
    if a.part = 'stock' then
      f := coalesce((fac->>a.item_id::text)::numeric, 0); v := round(a.amount * f, 2);
      if v <> 0 then
        insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, 'stock', -v, a.dr_key, a.method);
        nrows := nrows + 1;
        sumv := jsonb_set(sumv, array[a.item_id::text], to_jsonb(coalesce((sumv->>a.item_id::text)::numeric, 0) + v));
      end if;
      if a.amount - v <> 0 then
        insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, 'cogs', -(a.amount - v), 'landed_variance', a.method);
        nrows := nrows + 1;
      end if;
    else
      insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, a.part, -a.amount, a.dr_key, a.method);
      nrows := nrows + 1;
    end if;
  end loop;
  for st in select * from public.landed_cost_stock where cost_id = p_id and kind = 'post' order by item_id loop
    sv := coalesce((sumv->>st.item_id::text)::numeric, 0); lo := null; li := null; na := null;
    select * into bal from public.stock_balance where item_id = st.item_id and location_id = st.location_id;
    q_now := greatest(coalesce(bal.qty, 0), 0);
    if sv <> 0 and q_now > 0 and bal.avg_cost is not null then
      na := round((q_now * bal.avg_cost - sv) / q_now, 6);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (st.item_id, st.location_id, -q_now, bal.avg_cost, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost void: stock out at the average', auth.uid()) returning id into lo;
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (st.item_id, st.location_id, q_now, na, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost void: stock back in at the corrected average', auth.uid()) returning id into li;
    end if;
    tot_orig := (select coalesce(sum(amount), 0) from public.landed_cost_alloc where cost_id = p_id and kind = 'post' and item_id = st.item_id);
    insert into public.landed_cost_stock (cost_id, kind, item_id, location_id, lot_qty, on_hand_before, avg_before, avg_after, stock_value, cogs_value, ledger_out, ledger_in, flags)
      values (p_id, 'void', st.item_id, st.location_id, st.lot_qty, q_now, bal.avg_cost, coalesce(na, bal.avg_cost), -sv, -(tot_orig - sv), lo, li, case when sv = 0 and st.stock_value <> 0 then 'nothing_left' end);
  end loop;
  update public.landed_costs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'void', 'reversed_rows', nrows);
end $$;

-- ---------- read: one landed cost, a list, the reminder list, the return view ----------
create or replace function public.landed_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h public.landed_costs; s jsonb := null;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
  if h.status in ('draft', 'approved') then
    begin s := public._landed_saved97(p_id, false); s := s - '_plan' - '_chg' - '_rows' - '_spread' - '_bills'; exception when others then s := jsonb_build_object('ok', false, 'error', sqlerrm); end;
  end if;
  return jsonb_build_object(
    'header', to_jsonb(h) - 'client_id' - 'post_client',
    'docs', coalesce((select jsonb_agg(jsonb_build_object('bill_id', d.bill_id, 'doc_type', d.doc_type, 'doc_id', d.doc_id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier', sp.name, 'total', b.total) order by b.bill_date, b.bill_no)
                      from public.landed_cost_docs d join public.purchase_bills b on b.id = d.bill_id join public.suppliers sp on sp.id = b.supplier_id where d.cost_id = p_id), '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'cost_id' order by l.line_no) from public.landed_cost_lines l where l.cost_id = p_id), '[]'::jsonb),
    'basis', coalesce((select jsonb_agg(to_jsonb(b) - 'cost_id') from public.landed_cost_basis b where b.cost_id = p_id), '[]'::jsonb),
    'alloc', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'charge_line_id', a.charge_line_id, 'bill_line_id', a.bill_line_id, 'item_id', a.item_id, 'part', a.part, 'amount', a.amount, 'dr_key', a.dr_key) order by a.id)
                       from public.landed_cost_alloc a where a.cost_id = p_id), '[]'::jsonb),
    'stock', coalesce((select jsonb_agg(to_jsonb(x) - 'cost_id' order by x.id) from public.landed_cost_stock x where x.cost_id = p_id), '[]'::jsonb),
    'preview', s,
    'can', jsonb_build_object('approve', public._landed_ok97(h.location_id, 'approve'), 'entry', true),
    'rules', jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'requires_approval', coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn')));
end $$;

create or replace function public.landed_list(p_status text default null, p_bill uuid default null, p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(z order by z.cost_date desc, z.created_at desc) from (
    select c.id, c.status, c.location_id, c.shipment_ref, c.title, c.cost_date, c.total, c.alloc_method, c.created_staff, c.created_at, c.posted_at,
           (select count(*) from public.landed_cost_docs d where d.cost_id = c.id) as n_bills
      from public.landed_costs c
     where (p_status is null or c.status = p_status) and (p_bill is null or exists (select 1 from public.landed_cost_docs d where d.cost_id = c.id and d.bill_id = p_bill))
       and public._landed_ok97(c.location_id, 'entry')
     order by c.cost_date desc, c.created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.landed_reminders(p_days integer default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare days int := coalesce(p_days, public.rule_num('landed_reminder_days')::int, 30); mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); rows_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('landed_reminder_on') then return jsonb_build_object('on', false, 'mode', mode_, 'rows', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(z order by z.bill_date desc, z.bill_no), '[]'::jsonb) into rows_ from (
    select b.id as bill_id, b.bill_no, b.bill_date, b.total, b.location_id, b.supplier_id, s.name as supplier, f.kind as flag,
           case when f.supplier_id is not null then 'supplier_' || f.kind else 'every_bill' end as why,
           exists (select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = b.id and c.status in ('draft', 'approved')) as in_progress
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
      left join public.landed_supplier_flags f on f.supplier_id = b.supplier_id and f.active
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date >= (now() at time zone 'Asia/Dhaka')::date - days
       and (f.supplier_id is not null or mode_ = 'per_bill')
       and not exists (select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = b.id and c.status = 'posted')
       and not exists (select 1 from public.landed_skips k where k.bill_id = b.id)
       and public._landed_ok97(b.location_id, 'entry')
     order by b.bill_date desc limit 200) z;
  return jsonb_build_object('on', true, 'mode', mode_, 'days', days, 'rows', rows_, 'count', jsonb_array_length(rows_));
end $$;

create or replace function public.landed_return_info(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.purchase_bills; orig uuid; items_ jsonb; tot numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(b.location_id, 'entry') then raise exception 'not allowed'; end if;
  orig := case when b.kind = 'return' then b.ref_bill_id else b.id end;
  if orig is null then return jsonb_build_object('original', null, 'has_landed', false, 'items', '[]'::jsonb, 'total', 0); end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'returned_qty', z.rq, 'lot_qty', z.lq, 'landed_per_unit', z.lpu, 'landed_on_returned', round(z.rq * z.lpu, 2)) order by z.code), '[]'::jsonb),
         coalesce(sum(round(z.rq * z.lpu, 2)), 0) into items_, tot
  from (
    select pl.item_id, it.code, sum(pl.base_qty) as lq,
           coalesce((select sum(r.base_qty) from public.purchase_bills rb join public.purchase_lines r on r.bill_id = rb.id
                      where rb.kind = 'return' and rb.status = 'posted' and rb.ref_bill_id = orig and r.item_id = pl.item_id and (b.kind <> 'return' or rb.id = b.id)), 0) as rq,
           coalesce((select sum(a.amount) from public.landed_cost_alloc a join public.landed_costs c on c.id = a.cost_id join public.landed_cost_docs d on d.cost_id = c.id and d.bill_id = orig
                      where a.item_id = pl.item_id and c.status = 'posted' and a.part in ('stock', 'cogs') and a.kind = 'post'), 0) / nullif(sum(pl.base_qty), 0) as lpu
      from public.purchase_lines pl join public.items it on it.id = pl.item_id where pl.bill_id = orig and pl.item_id is not null group by pl.item_id, it.code) z
  where z.lpu is not null and z.lpu <> 0;
  return jsonb_build_object('original', orig, 'has_landed', jsonb_array_length(items_) > 0, 'items', items_, 'total', tot,
    'note', jsonb_build_object('bn', 'ফেরতের মালের সাথে যে landed cost যুক্ত ছিল তা সরবরাহকারী ফেরত দেয় না — ক্রয় ফেরতের দামের পার্থক্য (purchase variance) হিসেবে থেকে যায়। সরবরাহকারী ওই ভাড়া ফেরত দিলে একটি ঋণাত্মক landed খরচ লিখুন।',
      'mix', 'ফেরত দেওয়া মালের সাথে যে landed cost যুক্ত ছিল তা supplier ফেরত দেয় না — purchase return variance হিসেবে থেকে যায়। Supplier ওই charge ফেরত দিলে একটি negative landed charge লিখুন।',
      'en', 'The landed cost carried by the returned goods is not refunded by the supplier: it stays as a purchase return price variance. If the supplier also refunds that charge, enter a negative landed charge.'));
end $$;

create or replace function public.landed_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'alloc_default', coalesce(public.rule_txt('landed_alloc_default'), 'value'),
    'late_mode', coalesce(public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs'), 'requires_approval', coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn'),
    'reminder_on', public.rule_on('landed_reminder_on'), 'journal_ready', public._landed_journal_ready97(), 'base_currency', upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT')),
    'can_entry', public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now())),
    'can_approve', public.is_owner() or public.has_grant('landed_approve', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'landed_approve' and (g.valid_until is null or g.valid_until > now())),
    'charge_types', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'name_mix', coalesce(t.name_mix, t.name_en), 'treatment', t.treatment, 'default_alloc', t.default_alloc,
                      'hint_bn', t.hint_bn, 'hint_mix', t.hint_mix, 'hint_en', t.hint_en, 'active', t.active, 'is_system', t.is_system) order by t.sort, t.code) from public.cost_charge_types t where t.active or public.is_owner()), '[]'::jsonb));
end $$;

-- ---------- small owner / entry tools ----------
create or replace function public.landed_charge_type_save(p_code text, p_name_bn text, p_name_en text, p_name_mix text, p_treatment text, p_expense_key text default null, p_default_alloc text default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.cost_charge_types;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,32}$' then raise exception 'bad_code'; end if;
  if p_treatment not in ('capitalise', 'expense_only', 'recoverable_tax') then raise exception 'bad_treatment'; end if;
  if p_default_alloc is not null and p_default_alloc not in ('qty', 'value', 'weight', 'volume', 'equal') then raise exception 'bad_method'; end if;
  if p_treatment = 'expense_only' and p_expense_key is not null and not exists (select 1 from public.acct_mappings where key = p_expense_key) then raise exception 'mapping_missing:%', p_expense_key; end if;
  select * into t from public.cost_charge_types where code = p_code;
  if found then
    update public.cost_charge_types set treatment = p_treatment, expense_key = case when p_treatment = 'expense_only' then p_expense_key end, default_alloc = case when p_treatment = 'capitalise' then p_default_alloc end, active = coalesce(p_active, active),
           name_bn = case when is_system then name_bn else coalesce(nullif(btrim(p_name_bn), ''), name_bn) end,
           name_en = case when is_system then name_en else coalesce(nullif(btrim(p_name_en), ''), name_en) end,
           name_mix = case when is_system then name_mix else coalesce(nullif(btrim(p_name_mix), ''), name_mix) end where code = p_code;
  else
    if nullif(btrim(p_name_bn), '') is null or nullif(btrim(p_name_en), '') is null then raise exception 'name_required'; end if;
    insert into public.cost_charge_types (code, name_bn, name_en, name_mix, treatment, expense_key, default_alloc, sort, active, is_system, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), nullif(btrim(p_name_mix), ''), p_treatment, case when p_treatment = 'expense_only' then p_expense_key end, case when p_treatment = 'capitalise' then p_default_alloc end, 500, coalesce(p_active, true), false, auth.uid());
  end if;
  return jsonb_build_object('code', p_code, 'treatment', p_treatment);
end $$;

create or replace function public.landed_logistics_set(p_item uuid, p_weight_kg numeric, p_volume_l numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now()))) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if (p_weight_kg is not null and not (p_weight_kg > 0 and p_weight_kg < 1000000)) or (p_volume_l is not null and not (p_volume_l > 0 and p_volume_l < 1000000)) then raise exception 'bad_value'; end if;
  insert into public.item_logistics (item_id, unit_weight_kg, unit_volume_l, note, set_by) values (p_item, p_weight_kg, p_volume_l, left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (item_id) do update set unit_weight_kg = excluded.unit_weight_kg, unit_volume_l = excluded.unit_volume_l, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('item_id', p_item, 'unit_weight_kg', p_weight_kg, 'unit_volume_l', p_volume_l);
end $$;

create or replace function public.landed_supplier_flag_set(p_supplier uuid, p_kind text, p_active boolean default true, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now()))) then raise exception 'not allowed'; end if;
  if p_kind not in ('imported', 'extra_charges') then raise exception 'bad_kind'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier) then raise exception 'supplier_not_found'; end if;
  insert into public.landed_supplier_flags (supplier_id, kind, active, note, set_by) values (p_supplier, p_kind, coalesce(p_active, true), left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (supplier_id) do update set kind = excluded.kind, active = excluded.active, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('supplier_id', p_supplier, 'kind', p_kind, 'active', coalesce(p_active, true));
end $$;

create or replace function public.landed_skip(p_bill uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.purchase_bills;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(b.location_id, 'entry') then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  insert into public.landed_skips (bill_id, reason) values (p_bill, left(btrim(p_reason), 200)) on conflict (bill_id) do nothing;
  return jsonb_build_object('bill_id', p_bill, 'skipped', true);
end $$;

-- ---------- privileges: signed-in users call the RPCs; every internal function stays closed ----------
revoke all on function public.landed_preview(uuid[], jsonb, jsonb, text, text), public.landed_recommendation(uuid[], uuid, jsonb, jsonb), public.landed_save(uuid, uuid, jsonb, jsonb, jsonb, jsonb),
  public.landed_approve(uuid), public.landed_post(uuid, uuid), public.landed_void(uuid, text), public.landed_get(uuid), public.landed_list(text, uuid, integer), public.landed_reminders(integer),
  public.landed_return_info(uuid), public.landed_info(), public.landed_charge_type_save(text, text, text, text, text, text, text, boolean), public.landed_logistics_set(uuid, numeric, numeric, text),
  public.landed_supplier_flag_set(uuid, text, boolean, text), public.landed_skip(uuid, text) from public, anon;
grant execute on function public.landed_preview(uuid[], jsonb, jsonb, text, text), public.landed_recommendation(uuid[], uuid, jsonb, jsonb), public.landed_save(uuid, uuid, jsonb, jsonb, jsonb, jsonb),
  public.landed_approve(uuid), public.landed_post(uuid, uuid), public.landed_void(uuid, text), public.landed_get(uuid), public.landed_list(text, uuid, integer), public.landed_reminders(integer),
  public.landed_return_info(uuid), public.landed_info(), public.landed_charge_type_save(text, text, text, text, text, text, text, boolean), public.landed_logistics_set(uuid, numeric, numeric, text),
  public.landed_supplier_flag_set(uuid, text, boolean, text), public.landed_skip(uuid, text) to authenticated;

-- ---------- the accounts follow: _acct_docs = phase89 body + two bos97 blocks ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase89 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos89: merge of phase80 (free-cost) and phase85 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._acct_paykey(v.pm, true) /* bos85 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' else 'Stock transfer' end) || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' else 'stock_transfer' end)::text st) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);
end $function$;

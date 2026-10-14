-- ============================================================
-- Phase 114 (bos114) - BATCH 2 "stock safety", part 1 (sales / stock / units / batches / item lifecycle).
--   Source: docs/audit2/A2_sales_stock_reconciliation.md (gaps G3, G5, G6, G8, G9; G4 is already an advisor row, see below).
--   Needs phases 72..103 pasted first (guard below). Independent of 112/113/116..121. Paste twice = no change.
--   EVERY behaviour change is behind a rules switch whose default is OFF = today's behaviour. Nothing here is switched on by this file.
--
--   Rules (all switches, default false)                          what ON does
--     late_sale_follows_block   G3  a sale that arrives online with an OLD p_sold_at (phone clock behind / direct API call) is no longer
--                                   treated as a "late offline sync": stock_negative_mode = block applies to it. A real offline-queue replay
--                                   (record_sale_offline, manager override) is untouched.
--     transfer_needs_stock      G6  a transfer cannot send more than the sender holds (the sell_below_zero permission / emergency approval
--                                   still lets the owner through). Also stops "negative stock on send" (A5 GAP-8). Row-locked: two phones cannot both pass.
--     return_uses_sale_rows     G5  a sale return puts back what the SALE took out (ledger rows, in proportion to the returned part of the line),
--                                   not today's unit factor. A factor edited after the sale no longer shifts the book.
--     item_unit_change_needs_zero G5 the base unit (the unit the stock number is counted in) cannot be changed while stock is on hand.
--     item_lifecycle_needs_zero G9  an item cannot be set "not tracked" or inactive while stock is on hand (same error item_has_stock as "count in business").
--     batch_for_adjustments     G8  a count GAIN and an OPENING stock get an adjustment batch (no expiry), so FEFO / expiry lists see the stock.
--     batch_refill_cap          G8  a new batch that refills a NEGATIVE balance only keeps the part that is really on hand (balance -2, batch 10 -> batch 8).
--   Functions
--     new       stock_batch_reconcile(p_fix)   owner: batch sum vs balance per item / place; p_fix adds an adjustment batch for the missing part only
--               _adj_batch114, _stock_batch_refill114 (trigger), _items_stock_guard114 (trigger)  internal
--     patched   _sale_stock_out, stock_transfer, sale_return, stock_count_adjust, stock_opening - each by an exact-text insert into the CURRENT body
--               (helper _b2_patch114, dropped at the end of this file): every older bosNN tag of the function is kept by construction, a body that no longer
--               contains the expected line makes this file stop with a clear message instead of overwriting anything. Tag bos114.
--   Not done here (see docs/audit2 + the batch report): combo / kit (G7), item merge (G9), stock_levels listing inactive items, statement report (G1/G2).
--   G4 (unit conversion missing -> block): already exists as rule unit_conv_required = refuse (phase82) and is already an advisor row (recommended refuse).
--   Money / cost secrecy: no cost is read or written by anything new; RLS / grants unchanged; internal functions have no privilege for anyone.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.stock_batches') is null or to_regclass('public.rules') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase114 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- helper: exact-text patch of a live function body (dropped at the end of this file) ----------
create or replace function public._b2_patch114(p_sig text, p_anchor text, p_repl text, p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int;
begin
  if f is null then raise exception 'phase114: function % not found - paste phases 72..103 first', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  n := (length(d) - length(replace(d, p_anchor, ''))) / length(p_anchor);
  if n <> 1 then raise exception 'phase114: % expected text found % times (need exactly 1) in %; the function changed - merge by hand', p_marker, n, p_sig; end if;
  execute replace(d, p_anchor, p_repl);
end $$;

-- ---------- rules (all OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('late_sale_follows_block', 'stock', 'switch', 'false', null, null, null, null,
  'পুরনো সময়ের অনলাইন বিক্রিতেও "block" নিয়ম খাটবে', 'পুরনো সময়ের online sale-এও block নিয়ম খাটবে', 'The block rule also applies to online sales that carry an old time',
  'বন্ধ = আগের মতোই (ডিফল্ট): ২ মিনিটের বেশি পুরনো সময় সহ আসা যেকোনো বিক্রি stock-এর হিসাবে "দেরিতে আসা" ধরা হয়, তাই block থাকলেও আটকায় না। চালু = শুধু আসল offline সারি (replay) থেকে আসা বিক্রিই ছাড় পায়; ফোনের ঘড়ি পিছিয়ে থাকলে বা সরাসরি API-তে পাঠালে block কাজ করে।',
  'Off = আগের মতোই (default): 2 মিনিটের বেশি পুরনো সময় সহ আসা যেকোনো sale stock-এর হিসাবে "late" ধরা হয়, তাই block থাকলেও আটকায় না। On = শুধু আসল offline queue (replay) থেকে আসা sale ছাড় পায়; phone-এর ঘড়ি পিছিয়ে থাকলে বা সরাসরি API-তে পাঠালে block কাজ করে।',
  'Off = as before (default): any sale that arrives with a time more than 2 minutes old counts as a late sync and is not stopped by block mode. On = only a real offline-queue replay is exempt; a phone with a slow clock or a direct API call is stopped by block like any other sale.', 1140),
 ('transfer_needs_stock', 'stock', 'switch', 'false', null, null, null, null,
  'Transfer-এ প্রেরকের stock-এর বেশি পাঠানো যাবে না', 'Transfer-এ sender-এর stock-এর বেশি পাঠানো যাবে না', 'A transfer cannot send more than the sender holds',
  'বন্ধ = আগের মতোই (ডিফল্ট): stock_negative_mode = warn থাকলে বেশি পাঠানো যায়, প্রেরকের stock মাইনাস হয় ও প্রাপক শূন্য থেকে stock পায়। চালু = প্রেরকের হাতে যা আছে তার বেশি পাঠানো যায় না ("stock-এর নিচে বিক্রি" অনুমতি বা জরুরি অনুমোদন থাকলে ছাড়)। আগে stock গুনে ঠিক করে নিন।',
  'Off = আগের মতোই (default): stock_negative_mode = warn হলে বেশি পাঠানো যায়, sender-এর stock minus হয় ও receiver শূন্য থেকে stock পায়। On = sender-এর হাতে যা আছে তার বেশি পাঠানো যায় না (sell-below-zero permission বা emergency approval থাকলে ছাড়)। আগে stock গুনে ঠিক করে নিন।',
  'Off = as before (default): in warn mode a transfer above the sender''s stock is accepted, the sender goes negative and the receiver gets stock from nothing. On = a transfer above what the sender holds is refused (the sell-below-zero permission or an emergency approval still lets it through). Count your stock first.', 1141),
 ('return_uses_sale_rows', 'stock', 'switch', 'false', null, null, null, null,
  'বিক্রি ফেরতে বিক্রির সময়ে যা stock থেকে বেরিয়েছিল ঠিক তাই ফেরত আসবে', 'Sale return-এ বিক্রির সময়ে যা stock থেকে বেরিয়েছিল ঠিক তাই ফেরত আসবে', 'A sale return puts back what the sale took out',
  'বন্ধ = আগের মতোই (ডিফল্ট): ফেরতের পরিমাণ আজকের unit factor দিয়ে হিসাব হয়; বিক্রির পরে factor বদলালে stock ভুল হয়। চালু = বিক্রির নিজের stock-খাতার সারি থেকে আনুপাতিক হারে ফেরত হয়।',
  'Off = আগের মতোই (default): ফেরতের পরিমাণ আজকের unit factor দিয়ে হিসাব হয়; sale-এর পরে factor বদলালে stock ভুল হয়। On = sale-এর নিজের stock ledger row থেকে আনুপাতিক হারে ফেরত হয়।',
  'Off = as before (default): the returned quantity is converted with today''s unit factor, so a factor edited after the sale shifts the book. On = the return is taken from the sale''s own stock ledger rows, in proportion to the returned part of the line.', 1142),
 ('item_unit_change_needs_zero', 'items', 'switch', 'false', null, null, null, null,
  'Stock থাকা অবস্থায় পণ্যের base unit বদলানো যাবে না', 'Stock থাকা অবস্থায় item-এর base unit বদলানো যাবে না', 'The base unit cannot change while stock is on hand',
  'বন্ধ = আগের মতোই (ডিফল্ট): kg থেকে pc করলে খাতার সংখ্যাটির মানেই বদলে যায়। চালু = কোনো জায়গায় stock শূন্য না হলে base unit বদলানো যায় না (আগে গুনে শূন্য করুন)।',
  'Off = আগের মতোই (default): kg থেকে pc করলে খাতার সংখ্যাটির মানেই বদলে যায়। On = কোথাও stock শূন্য না হলে base unit বদলানো যায় না (আগে count করে শূন্য করুন)।',
  'Off = as before (default): changing kg to pc silently changes what the stock number means. On = the base unit cannot be changed unless the stock is zero everywhere (count it down first).', 1143),
 ('item_lifecycle_needs_zero', 'items', 'switch', 'false', null, null, null, null,
  'Stock থাকা পণ্য "ট্র্যাক বন্ধ" বা নিষ্ক্রিয় করা যাবে না', 'Stock থাকা item "tracking বন্ধ" বা inactive করা যাবে না', 'An item with stock cannot be untracked or deactivated',
  'বন্ধ = আগের মতোই (ডিফল্ট): ট্র্যাক বন্ধ করে বিক্রি চললে খাতার stock আর মেলে না; নিষ্ক্রিয় পণ্যের stock তালিকা থেকে লুকায় কিন্তু মূল্যে গোনা হয়। চালু = stock শূন্য না হলে দুটোই আটকায়।',
  'Off = আগের মতোই (default): tracking বন্ধ করে sale চললে book stock আর মেলে না; inactive item-এর stock list থেকে লুকায় কিন্তু valuation-এ গোনা হয়। On = stock শূন্য না হলে দুটোই আটকায়।',
  'Off = as before (default): selling after tracking is switched off leaves the book wrong; a deactivated item''s stock vanishes from the stock list but is still valued. On = both are refused until the stock is zero.', 1144),
 ('batch_for_adjustments', 'stock', 'switch', 'false', null, null, null, null,
  'গণনায় বাড়া stock ও শুরুর (opening) stock-এর জন্য batch খোলা হবে', 'Count-এ বাড়া stock ও opening stock-এর জন্য batch খোলা হবে', 'Count gains and opening stock get an adjustment batch',
  'বন্ধ = আগের মতোই (ডিফল্ট): এই stock-এর কোনো batch থাকে না, তাই মেয়াদ/FEFO তালিকায় আসে না এবং সবার শেষে বিক্রি হয়। চালু = মেয়াদহীন একটি adjustment batch খোলা হয়, ফলে batch-এর যোগফল খাতার stock-এর সমান থাকে।',
  'Off = আগের মতোই (default): এই stock-এর কোনো batch থাকে না, তাই expiry/FEFO list-এ আসে না এবং সবার শেষে sell হয়। On = expiry ছাড়া একটি adjustment batch খোলা হয়, ফলে batch-এর যোগফল book stock-এর সমান থাকে।',
  'Off = as before (default): this stock has no batch, so it is missing from expiry / FEFO lists and is sold last. On = a no-expiry adjustment batch is opened so the batches add up to the book stock.', 1145),
 ('batch_refill_cap', 'stock', 'switch', 'false', null, null, null, null,
  'মাইনাস stock পূরণ করা নতুন batch-এ শুধু আসল মজুত ধরা হবে', 'Minus stock পূরণ করা নতুন batch-এ শুধু আসল মজুত ধরা হবে', 'A batch that refills a negative balance only keeps what is really on hand',
  'বন্ধ = আগের মতোই (ডিফল্ট): stock -২ থাকা অবস্থায় ১০ উৎপাদন হলে খাতায় ৮ কিন্তু batch-এ ১০ দেখায় (২টি ভুতুড়ে)। চালু = batch-এ ৮ ধরা হয়। বাতিল (void) করার সময় এই batch "আংশিক ব্যবহৃত" ধরা পড়তে পারে।',
  'Off = আগের মতোই (default): stock -2 থাকা অবস্থায় 10 production হলে book-এ 8 কিন্তু batch-এ 10 দেখায় (2টি phantom)। On = batch-এ 8 ধরা হয়। Void করার সময় এই batch "partly used" ধরা পড়তে পারে।',
  'Off = as before (default): producing 10 while the balance is -2 leaves 8 in the book but 10 in the batch (2 phantom). On = the batch keeps 8. Voiding such a run may report "batch partly used".', 1146)
on conflict (key) do nothing;

-- ---------- setup advisor rows (advisory only; apply goes through set_rule) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('late_sale_follows_block', 'late_sale_follows_block', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'stock "block" দিলে আপনি চান বেশি বিক্রি আটকাক। ফোনের ঘড়ি পিছিয়ে থাকলে সেই আটকানো ফাঁকি দেওয়া যায়। এটি চালু করলে শুধু আসল offline বিক্রি ছাড় পায়; block না থাকলে কিছুই বদলায় না।',
  'Stock block দিলে আপনি চান বেশি sale আটকাক। Phone-এর ঘড়ি পিছিয়ে থাকলে সেই আটকানো ফাঁকি দেওয়া যায়। এটি চালু করলে শুধু আসল offline sale ছাড় পায়; block না থাকলে কিছুই বদলায় না।',
  'If you chose block you want oversells stopped, but a phone with a slow clock gets around it. With this on only a real offline sale is exempt; if block is not used nothing changes.', 1140),
 ('transfer_needs_stock', 'transfer_needs_stock', '114', 'stock', null::jsonb, '{}'::text[],
  'চালু করলে প্রেরকের হাতে যা নেই তা পাঠানো যায় না, ফলে শূন্য থেকে stock তৈরি হয় না। কিন্তু খাতার stock ভুল থাকলে বৈধ transfer-ও আটকে যেতে পারে, তাই প্রথম stock গোনার পরে নিজে চালু করুন; এখানে মান ঠিক করে দেওয়া হয়নি।',
  'চালু করলে sender-এর হাতে যা নেই তা পাঠানো যায় না, ফলে শূন্য থেকে stock তৈরি হয় না। কিন্তু book stock ভুল থাকলে বৈধ transfer-ও আটকে যেতে পারে, তাই প্রথম stock count-এর পরে নিজে চালু করুন; এখানে value ঠিক করে দেওয়া হয়নি।',
  'On, a transfer above what the sender holds is refused so no stock appears from nothing. If the book stock is wrong a genuine transfer may be stopped, so switch it on yourself after the first stock count; no value is recommended here.', 1141),
 ('return_uses_sale_rows', 'return_uses_sale_rows', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'unit factor বদলালে পুরনো বিক্রির ফেরত ভুল পরিমাণ stock-এ ওঠে। চালু করলে ফেরত ঠিক সেই পরিমাণ ওঠে যা বিক্রির সময় বেরিয়েছিল। আগের কোনো হিসাব বদলায় না।',
  'Unit factor বদলালে পুরনো sale-এর return ভুল পরিমাণ stock-এ ওঠে। চালু করলে return ঠিক সেই পরিমাণ ওঠে যা sale-এর সময় বেরিয়েছিল। আগের কোনো হিসাব বদলায় না।',
  'After a unit factor is edited, a return of an old sale puts the wrong quantity back. With this on the return restores exactly what the sale took out. Nothing already booked changes.', 1142),
 ('item_unit_change_needs_zero', 'item_unit_change_needs_zero', '114', 'items', 'true'::jsonb, '{}'::text[],
  'stock থাকা অবস্থায় base unit বদলালে খাতার সংখ্যার মানে চুপচাপ বদলে যায়। চালু করলে আগে stock শূন্য করতে হয়; তাতে ভুল হওয়ার পথ বন্ধ হয়।',
  'Stock থাকা অবস্থায় base unit বদলালে book-এর সংখ্যার মানে চুপচাপ বদলে যায়। চালু করলে আগে stock শূন্য করতে হয়; তাতে ভুল হওয়ার পথ বন্ধ হয়।',
  'Changing the base unit while stock is on hand silently changes what the number means. With this on the stock must be zero first, which closes that mistake.', 1143),
 ('item_lifecycle_needs_zero', 'item_lifecycle_needs_zero', '114', 'items', 'true'::jsonb, '{}'::text[],
  'ট্র্যাক বন্ধ বা নিষ্ক্রিয় করা পণ্যের stock খাতায় থেকে যায় অথচ কেউ দেখে না। চালু করলে আগে stock শূন্য (গণনা/ব্যবহার) করতে হয়।',
  'Tracking বন্ধ বা inactive করা item-এর stock book-এ থেকে যায় অথচ কেউ দেখে না। চালু করলে আগে stock শূন্য (count/use) করতে হয়।',
  'Stock of an untracked or deactivated item stays in the books where nobody sees it. With this on the stock must be brought to zero (count / use) first.', 1144),
 ('batch_for_adjustments', 'batch_for_adjustments', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'গণনায় বাড়া ও শুরুর stock-এর batch না থাকায় মেয়াদ ও FEFO তালিকা থেকে সেই মাল বাদ পড়ে। চালু করলে মেয়াদহীন একটি batch খোলা হয়; stock বা দাম বদলায় না।',
  'Count-এ বাড়া ও opening stock-এর batch না থাকায় expiry ও FEFO list থেকে সেই মাল বাদ পড়ে। চালু করলে expiry ছাড়া একটি batch খোলা হয়; stock বা দাম বদলায় না।',
  'Stock added by a count or an opening has no batch, so it is missing from expiry and FEFO lists. With this on a no-expiry batch is opened; stock and costs do not change.', 1145),
 ('batch_refill_cap', 'batch_refill_cap', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'মাইনাস stock পূরণ করা উৎপাদন/ক্রয়ের batch-এ ভুতুড়ে পরিমাণ থেকে যায়, মেয়াদের তালিকা বেশি দেখায়। চালু করলে batch-এ শুধু আসল মজুত থাকে।',
  'Minus stock পূরণ করা production/purchase-এর batch-এ phantom পরিমাণ থেকে যায়, expiry list বেশি দেখায়। চালু করলে batch-এ শুধু আসল মজুত থাকে।',
  'A production or purchase batch that refills a negative balance keeps a phantom quantity and the expiry list shows too much. With this on the batch keeps only what is really on hand.', 1146)
on conflict (code) do nothing;

-- ---------- internal: adjustment batch for a count gain / opening ----------
create or replace function public._adj_batch114(p_item uuid, p_loc integer, p_qty numeric, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  if p_qty is null or p_qty <= 0 or not public.rule_on('batch_for_adjustments') then return null; end if;      -- bos114: off = no batch, as before
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, note, created_by)
    values (p_item, p_loc, now(), round(p_qty, 4), round(p_qty, 4), null, left(p_note, 200), auth.uid()) returning id into bid;
  return bid;
end $$;
revoke all on function public._adj_batch114(uuid, integer, numeric, text) from public, anon, authenticated;

-- ---------- trigger: a new batch that refills a negative balance keeps only what is really on hand ----------
create or replace function public._stock_batch_refill114() returns trigger
language plpgsql security definer set search_path = public as $$
declare q numeric;
begin
  if not public.rule_on('batch_refill_cap') then return new; end if;                                     -- bos114: off = as before
  if new.qty_remaining is distinct from new.qty_made then return new; end if;                            -- only a fresh, untouched batch
  select b.qty into q from public.stock_balance b where b.item_id = new.item_id and b.location_id = new.location_id for update;   -- same row stock_post locks next
  if q is not null and q < 0 then new.qty_remaining := greatest(0, round(new.qty_made + q, 4)); end if;
  return new;
end $$;
revoke all on function public._stock_batch_refill114() from public, anon, authenticated;
drop trigger if exists stock_batch_refill114 on public.stock_batches;
create trigger stock_batch_refill114 before insert on public.stock_batches for each row execute function public._stock_batch_refill114();

-- ---------- trigger: base unit change / untrack / deactivate with stock on hand ----------
create or replace function public._items_stock_guard114() returns trigger
language plpgsql security definer set search_path = public as $$
declare busy boolean;
begin
  if tg_op <> 'UPDATE' then return new; end if;
  if (public.rule_on('item_lifecycle_needs_zero') and ((old.tracked and not new.tracked) or (old.is_active and not new.is_active)))
     or (public.rule_on('item_unit_change_needs_zero') and coalesce(nullif(btrim(old.base_unit), ''), old.unit) is distinct from coalesce(nullif(btrim(new.base_unit), ''), new.unit)) then
    select exists (select 1 from public.stock_balance where item_id = new.id and qty <> 0) into busy;      -- bos114
    if busy then raise exception 'item_has_stock' using detail = 'Stock is on hand for ' || new.code || ': bring it to zero first', hint = new.code; end if;
  end if;
  return new;
end $$;
revoke all on function public._items_stock_guard114() from public, anon, authenticated;
drop trigger if exists items_stock_guard114 on public.items;
create trigger items_stock_guard114 after update on public.items for each row
  when (old.tracked is distinct from new.tracked or old.is_active is distinct from new.is_active or old.base_unit is distinct from new.base_unit or old.unit is distinct from new.unit)
  execute function public._items_stock_guard114();

-- ---------- batch sum vs balance (owner) ----------
create or replace function public.stock_batch_reconcile(p_fix boolean default false)
returns table(item_id uuid, location_id integer, balance numeric, batch_sum numeric, diff numeric, fixed boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; bq numeric; bs numeric; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();
  for r in select k.iid, k.lid from (select b.item_id iid, b.location_id lid from public.stock_batches b group by 1, 2) k order by 1, 2 loop
    if p_fix then perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update; end if;
    bq := coalesce((select z.qty from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid), 0);
    bs := coalesce((select sum(x.qty_remaining) from public.stock_batches x where x.item_id = r.iid and x.location_id = r.lid), 0);
    if abs(bs - greatest(bq, 0)) >= 0.0005 then
      item_id := r.iid; location_id := r.lid; balance := bq; batch_sum := bs; diff := round(bs - greatest(bq, 0), 4); fixed := false;
      if p_fix and diff < 0 then          -- stock the batches do not know about: an adjustment batch for exactly that part; the other direction (phantom batch stock) is only reported
        insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, note, created_by)
          values (r.iid, r.lid, now(), -diff, -diff, null, 'reconcile: adjustment batch', auth.uid());
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
          values (auth.uid(), sid, 'batch_reconcile_fix', 'stock_batches', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('balance', bq, 'batch_sum_before', bs, 'added', -diff, 'src', 'phase114'));
        fixed := true;
      end if;
      return next;
    end if;
  end loop;
end $$;
revoke all on function public.stock_batch_reconcile(boolean) from public, anon;
grant execute on function public.stock_batch_reconcile(boolean) to authenticated;

-- ---------- patches of the live bodies (each keeps every older tag; a changed body stops the file) ----------
-- G3: a late sale is exempt from "block" only when it really is an offline replay
do $do$ begin perform public._b2_patch114('public._sale_stock_out()',
$a$  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'$a$,
$a$  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'$a$,
'bos114:late-sale'); end $do$;

-- G6: a transfer cannot create stock
do $do$ begin perform public._b2_patch114('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)',
$a$  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out'$a$,
$a$  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out'$a$,
'bos114:xfer-stock'); end $do$;

-- G5: a return restores what the sale took out
do $do$ begin perform public._b2_patch114('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)',
$a$    bq := public._base_qty(it.id, ln.q, ln.u);$a$,
$a$    bq := public._base_qty(it.id, ln.q, ln.u);
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * ln.q / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select sum(nullif(e->>'qty', '')::numeric) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
              where e->>'item_id' = it.id::text and (e->>'unit') is not distinct from ln.u) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;$a$,
'bos114:return-rows'); end $do$;

-- G8: a count gain gets an adjustment batch
do $do$ begin perform public._b2_patch114('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)',
$a$ the average does not move */, null, now(), left(p_note, 200), null, 'none', null, p_client);$a$,
$a$ the average does not move */, public._adj_batch114(p_item, p_loc, d, 'count gain'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:count-batch$a$,
'bos114:count-batch'); end $do$;

-- G8: opening stock gets an adjustment batch
do $do$ begin perform public._b2_patch114('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)',
$a$  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, null, now(), left(p_note, 200), null, 'none', null, p_client);$a$,
$a$  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, public._adj_batch114(p_item, p_loc, bq, 'opening stock'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:opening-batch$a$,
'bos114:opening-batch'); end $do$;

drop function public._b2_patch114(text, text, text, text);

commit;

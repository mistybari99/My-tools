-- ============================================================
-- Phase 113 (bos113) - BATCH 1b "books truth": the drawer shortage reaches the books, advances stop being collected twice, closed periods stop being silent,
--   the day book agrees with the journal, a bank statement fee can be posted from the statement line.
--   Source: docs/audit2/A4_cash_accounting_reconciliation.md gaps G01 (drawer shortage / overage never posted; account 5800 unused), G03 (customer_dues ignores the advance already used, new list function customer_dues_net113; a collection after the advance
--   clears the debt twice), G04 (owner changes a closed period without trace; the scheduler skips late documents silently), G05 (day book vs journal: 10-2 voucher paid by bank shown as cash, card fee missing),
--   G08 (a bank statement line without a ledger entry has no action), G06 (card over-settlement: the option card_settle_over_mode from phase109 is the guard; this phase only tests it).
--   Needs phases 72..111 pasted first (guard below). Additive, paste-twice safe. NOTHING changes by default: six new rules, all default off = today's behaviour, six advisor rows recommend a value.
--     drawer_short_post        off | on    on = a submitted / approved drawer count (form 14-1) with a difference posts "cash short / over" (Dr 5800 Cr cash; over: the reverse); the day book shows the same row.
--     dues_net_advance         off | on    on = collect_payment refuses a collection above what is still due after the advance already applied (cash move "advance used"), and the app reads the dues list from customer_dues_net113 (customer_dues itself is not changed).
--     period_lock_owner_mode   off | warn  warn = the owner can still change a closed period (as before) but a yellow exception "closed_period_owner" is written (once per date and day).
--     period_lock_late_warn    off | on    on = acct_post_pending (the scheduler) logs a yellow exception "late_docs_locked" when documents were skipped because their date is in a closed period, and returns locked_docs.
--     daybook_align_mode       off | on    on = the day book reads the pay mode of a 10-2 voucher (bank / mobile / card) like the journal and shows the card fee of a card settlement (bank side).
--     bank_stmt_post_on        off | on    on = bank_stmt_post113(line, 'fee' | 'interest') posts the statement line (Dr 5810 / Cr bank, or Dr bank / Cr 4900) and matches it in one step.
--   New: mapping key cash_short -> account 5800 (if missing), RPC bank_stmt_post113. New: customer_dues_net113 (list net of the advance used). Re-created (tag bos113 next to the older tags): _acct_docs, acct_post_pending, _daybook_lines, collect_payment, lock_check. customer_dues stays as phase105 left it (so a re-paste of 103 + 105 still works).
--   NOT changed on purpose: the journal of any existing document, sale_return / void_sale (a void of a settled card sale is still a manual job), printed forms 05-3 / 05-4 / 10-2, the owner bypass in lock_check by default.
--   Body guard: a live body with a tag this file does not know is never overwritten. Tag: bos113.
-- ============================================================

do $g$ begin perform set_config('phase113.ok', 'off', false); end $g$;
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public.acct_post_pending(boolean,integer)') is null then miss := miss || ' 98'; end if;
  if to_regprocedure('public._daybook_lines(integer[],integer[],date,date)') is null then miss := miss || ' 50'; end if;
  if to_regprocedure('public.customer_dues()') is null or to_regprocedure('public.collect_payment(uuid,integer,uuid,jsonb,text)') is null then miss := miss || ' 12'; end if;
  if to_regprocedure('public._cust_pii103(text,text)') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public.lock_check(date)') is null then miss := miss || ' 6'; end if;
  if to_regprocedure('public._a53_match1(bigint,bigint,integer,text,text)') is null or to_regclass('public.bank_statement_lines') is null then miss := miss || ' 53'; end if;
  if to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null then miss := miss || ' 18'; end if;
  if to_regclass('public.entry_counts') is null or to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if not exists (select 1 from public.rules where key = 'card_settle_over_mode') then miss := miss || ' 109'; end if;
  if miss <> '' then
    raise exception 'phase113 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase113.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase113.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._acct_docs(date)', array['bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89', 'bos96', 'bos97', 'bos98', 'bos103', 'bos113']::text[]),
    ('public.acct_post_pending(boolean,integer)', array['bos72', 'bos85', 'bos113']::text[]),
    ('public._daybook_lines(integer[],integer[],date,date)', array['bos50', 'bos113']::text[]),
    ('public.collect_payment(uuid,integer,uuid,jsonb,text)', array['bos113']::text[]),
    ('public.lock_check(date)', array['bos113']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase113: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase113.ok', 'on', false);
end $g$;

-- ---------- 1. rules (default off = today) + advisor rows + the cash short / over mapping ----------
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('drawer_short_post', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ক্যাশ গণনার কম / বেশি হিসাব খাতায় তোলা: বন্ধ / চালু', 'Cash count-এর কম / বেশি হিসাব খাতায় তোলা: off / on', 'Post the drawer count difference to the books: off or on',
  'বন্ধ = আগের মতো (কম / বেশি শুধু লাল-হলুদ সতর্কতা, হিসাব খাতার ক্যাশ আসল ক্যাশের চেয়ে বেশি থাকে)। চালু = জমা দেওয়া ফর্ম ১৪-১ গণনায় কম বা বেশি থাকলে "ক্যাশ কম / বেশি" (৫৮০০) এন্ট্রি হয় এবং ডে-বুকে সেই সারি আসে।',
  'off = আগের মতো (কম / বেশি শুধু লাল-হলুদ সতর্কতা, books-এর cash আসল cash-এর চেয়ে বেশি থাকে)। on = submit করা Form 14-1 count-এ কম বা বেশি থাকলে "Cash short / over" (5800) entry হয় এবং Day book-এ সেই row আসে।',
  'off = as before (the difference is only the yellow / red flag and the books keep more cash than the till holds). on = a submitted or approved drawer count (form 14-1) with a difference posts Cash short / over (5800) and the day book shows the same row. A form that stops being final is reversed.', 987),
 ('dues_net_advance', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'বাকির তালিকায় ও আদায়ে আগে-নেওয়া অগ্রিম বাদ: বন্ধ / চালু', 'Dues list ও collection-এ ব্যবহৃত advance বাদ: off / on', 'Dues list and collection net of the advance already used: off or on',
  'বন্ধ = আগের মতো (অগ্রিম দিয়ে শোধ করা বাকিও তালিকায় দেখায়, আবার আদায় করলে দুইবার শোধ হয়)। চালু = বাকির তালিকা ও আদায় থেকে ব্যবহৃত অগ্রিম বাদ যায়।',
  'off = আগের মতো (advance দিয়ে শোধ করা due-ও list-এ দেখায়, আবার collect করলে দুইবার শোধ হয়)। on = Dues list ও collection থেকে ব্যবহৃত advance বাদ যায়।',
  'off = as before (a due already paid off with an advance still shows and can be collected a second time). on = the dues list (customer_dues_net113) and collect_payment subtract the advance already applied to bills.', 988),
 ('period_lock_owner_mode', 'books', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'বন্ধ হিসাবকালে মালিকের পরিবর্তন: বন্ধ / warn', 'বন্ধ period-এ owner-এর পরিবর্তন: off / warn', 'Owner changes inside a closed period: off or warn',
  'বন্ধ = আগের মতো (মালিক বাধা ছাড়াই লিখতে পারেন, কোনো চিহ্ন থাকে না)। warn = মালিক তবুও পারেন, কিন্তু হলুদ সতর্কতা লেখা হয় (প্রতি তারিখ ও দিনে একবার)।',
  'off = আগের মতো (owner বাধা ছাড়াই লিখতে পারেন, কোনো চিহ্ন থাকে না)। warn = owner তবুও পারেন, কিন্তু yellow exception লেখা হয় (প্রতি date ও দিনে একবার)।',
  'off = as before (the owner can write into a closed period and nothing is left behind). warn = the owner still can, and a yellow exception closed_period_owner is written (once per date and day). Nobody else is affected: they are still refused.', 989),
 ('period_lock_late_warn', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'বন্ধ হিসাবকালে আটকে-থাকা নথির সতর্কতা: বন্ধ / চালু', 'বন্ধ period-এ আটকে-থাকা document-এর warning: off / on', 'Warn about documents the scheduler could not book (closed period): off or on',
  'বন্ধ = আগের মতো (শুধু গোনা হয়)। চালু = হলুদ সতর্কতা "late_docs_locked" লেখা হয় এবং উত্তরে তালিকা (locked_docs) আসে।',
  'off = আগের মতো (শুধু গোনা হয়)। on = yellow exception "late_docs_locked" লেখা হয় এবং result-এ list (locked_docs) আসে।',
  'off = as before (they are only counted). on = a yellow exception late_docs_locked is written and the result lists them (locked_docs). The documents stay unbooked until the period is reopened.', 990),
 ('daybook_align_mode', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ডে-বুক হিসাব খাতার সাথে মেলানো: বন্ধ / চালু', 'Day book হিসাব খাতার সাথে মেলানো: off / on', 'Day book follows the journal: off or on',
  'বন্ধ = আগের মতো। চালু = ১০-২ ভাউচার ব্যাংক / মোবাইলে দিলে ডে-বুকেও তাই দেখায় (এখন সবই ক্যাশ), এবং কার্ড সেটেলমেন্টের ফি ব্যাংক দিকে আসে।',
  'off = আগের মতো। on = Voucher 10-2 bank / mobile-এ দিলে Day book-এও তাই দেখায় (এখন সবই cash), এবং card settlement-এর fee bank দিকে আসে।',
  'off = as before. on = a 10-2 voucher paid by bank or mobile shows with that mode in the day book (today every voucher is cash) and the card fee of a settlement leaves the bank side. daybook_vs_journal then shows no difference for these kinds.', 991),
 ('bank_stmt_post_on', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ব্যাংক স্টেটমেন্ট লাইন থেকে ফি / সুদ এন্ট্রি: বন্ধ / চালু', 'Bank statement line থেকে fee / interest entry: off / on', 'Post bank fee / interest from a statement line: off or on',
  'বন্ধ = আগের মতো (মিলানো না-যাওয়া লাইনের জন্য হাতে জার্নাল লিখতে হয়)। চালু = ব্যাংক মেলানোর পর্দায় "ফি" বা "সুদ" বেছে এক ধাপে এন্ট্রি ও মিল হয়। "ব্যাংক মেলানো" চালু থাকা লাগবে।',
  'off = আগের মতো (মেলে-না এমন line-এর জন্য হাতে journal লিখতে হয়)। on = Bank reconciliation-এ "fee" বা "interest" বেছে এক ধাপে entry ও match হয়। "Bank reconciliation" চালু থাকা লাগবে।',
  'off = as before (an unmatched statement line needs a manual journal). on = bank_stmt_post113 posts the line (fee: Dr bank charges 5810 / Cr bank; interest: Dr bank / Cr other income 4900) and matches it in one step. Needs the rule bank_recon_on.', 992)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('drawer_short_post', 'drawer_short_post', '113', 'books', '"on"', '{}'::text[],
  'ক্যাশ কম হলে হিসাব খাতার ক্যাশ ও আসল ক্যাশ আলাদা হয়ে যায়। চালু করলে কম / বেশি খরচ হিসেবে খাতায় ওঠে। সিদ্ধান্ত মালিকের।',
  'Cash কম হলে books-এর cash ও আসল cash আলাদা হয়ে যায়। on করলে কম / বেশি খাতায় ওঠে। সিদ্ধান্ত owner-এর।',
  'When a till is short, the cash in the books stays higher than the real cash. With this on the difference is posted (cash short / over) so the books agree with the count. The owner decides.', 363),
 ('dues_net_advance', 'dues_net_advance', '113', 'books', '"on"', '{}'::text[],
  'অগ্রিম দিয়ে শোধ হওয়া বাকি তালিকায় থাকলে একই টাকা দুইবার আদায় হতে পারে। চালু করলে তা আর দেখায় না। সিদ্ধান্ত মালিকের।',
  'Advance দিয়ে শোধ হওয়া due list-এ থাকলে একই টাকা দুইবার collect হতে পারে। on করলে তা আর দেখায় না। সিদ্ধান্ত owner-এর।',
  'A due already paid with an advance stays on the list and can be collected twice. With this on it no longer shows and cannot be collected again. The owner decides.', 364),
 ('period_lock_owner_mode', 'period_lock_owner_mode', '113', 'books', '"warn"', '{}'::text[],
  'বন্ধ হিসাবকালে মালিকের লেখা এখন নিঃশব্দ। warn করলে বাধা না দিয়ে হলুদ সতর্কতা লেখা থাকে। সিদ্ধান্ত মালিকের।',
  'বন্ধ period-এ owner-এর লেখা এখন নিঃশব্দ। warn করলে বাধা না দিয়ে yellow exception লেখা থাকে। সিদ্ধান্ত owner-এর।',
  'Today the owner can change a closed period without any trace. With warn nothing is blocked but a yellow exception is left behind. The owner decides.', 365),
 ('period_lock_late_warn', 'period_lock_late_warn', '113', 'books', '"on"', '{}'::text[],
  'স্বয়ংক্রিয় পোস্টিং বন্ধ হিসাবকালের নথি বাদ দিলে এখন কেউ জানে না। চালু করলে হলুদ সতর্কতা আসে। সিদ্ধান্ত মালিকের।',
  'Auto posting বন্ধ period-এর document বাদ দিলে এখন কেউ জানে না। on করলে yellow exception আসে। সিদ্ধান্ত owner-এর।',
  'When the automatic posting skips documents of a closed period nobody is told. With this on a yellow exception says how many. The owner decides.', 366),
 ('daybook_align_mode', 'daybook_align_mode', '113', 'books', '"on"', '{}'::text[],
  'ডে-বুক ও হিসাব খাতার ক্যাশ / ব্যাংক এক না হলে মালিক দুই রকম অঙ্ক দেখেন। চালু করলে মিলে যায়। সিদ্ধান্ত মালিকের।',
  'Day book ও books-এর cash / bank এক না হলে owner দুই রকম অঙ্ক দেখেন। on করলে মিলে যায়। সিদ্ধান্ত owner-এর।',
  'When the day book and the books show different cash and bank figures the owner reads two numbers. With this on they agree for vouchers paid by bank and for the card fee. The owner decides.', 367),
 ('bank_stmt_post_on', 'bank_stmt_post_on', '113', 'books', '"on"', '{}'::text[],
  'ব্যাংক ফি স্টেটমেন্টে থাকে কিন্তু হিসাব খাতায় নেই। চালু করলে এক ধাপে এন্ট্রি হয়। সিদ্ধান্ত মালিকের।',
  'Bank fee statement-এ থাকে কিন্তু books-এ নেই। on করলে এক ধাপে entry হয়। সিদ্ধান্ত owner-এর।',
  'A bank fee shows on the statement but not in the books. With this on it is posted from the statement line in one step. The owner decides.', 368)
on conflict do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select 'cash_short', a.id, 'ক্যাশ কম / বেশি', 'Cash short / over' from public.coa_accounts a where a.code = '5800'
  on conflict (key) do nothing;
end if; end $p113$;

-- public._acct_docs(date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase89 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase98 = phase89 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase96 nor phase97 can erase the other
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
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);

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
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
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
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
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

  -- bos113: a drawer count difference reaches the books (rule drawer_short_post = on; default off = as before, the difference is only the yellow / red exception flag).
  --   Short (count < expected): Dr cash short / over (5800), Cr cash. Over: Dr cash, Cr 5800. One entry per final (submitted / approved) form 14-1 revision; a form that is no longer final is reversed by the second query.
  return query
  select 'cash_variance'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id,
    (case when k.diff < 0 then 'Cash short, drawer count ' else 'Cash over, drawer count ' end || e.entry_date::text)::text, null::text, true, null::date, null::text, null::text,
    case when k.diff < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', -k.diff), jsonb_build_object('a', 'pay_cash', 'c', -k.diff))
         else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', k.diff), jsonb_build_object('a', 'cash_short', 'c', k.diff)) end
  from public.entry_counts k join public.entries e on e.id = k.entry_id
  where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date >= p_start
    and coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on'
    and public._acct_need('cash_variance', e.id::text || ':' || coalesce(e.rev_no, 0)::text, true);
  return query
  select 'cash_variance'::text, je.source_id, je.entry_date, je.location_id, 'Drawer count no longer final'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'cash_variance' and je.reverses_id is null
    and not exists (select 1 from public.entry_counts k join public.entries e on e.id = k.entry_id
                     where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);
end $function$
$f$; end if; end $p113$;

-- public.acct_post_pending(boolean,integer)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]'; lk jsonb := '[]'; lw boolean := coalesce(public.rule_txt('period_lock_late_warn'), 'off') = 'on';   -- bos113
begin
  if not (public._acct_manage() or (auth.uid() is null and coalesce(current_setting('bos.autopost85', true), '') = 'on')) then raise exception 'not allowed'; end if;   -- bos85: the scheduler entry point has no signed-in person
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', d.entry_date); end if; continue; end if;   -- bos113
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', rdate, 'reversal', true); end if; continue; end if;   -- bos113
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;   -- bos72: solved
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      if not p_dry then   -- bos72: keep the failure so the status strip and the accounts page can show it (the browser used to drop it)
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  if lw and not p_dry and locked > 0 then   -- bos113: rule period_lock_late_warn = on: documents the scheduler could not book (their date is in a closed period) are no longer silent
    if exists (select 1 from public.exceptions x where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open') then
      update public.exceptions x set amount = locked where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open';
    else
      perform public._stock_exc((select min(l.id) from public.locations l), 'late_docs_locked', 'yellow',
        locked::text || ' নথি বই-এ ওঠেনি: তারিখ বন্ধ হিসাবকালে', locked::text || ' document(s) are not in the books: their date is in a closed period (reopen the period or post them by hand)', null, public._acct_today(), 'ACCOUNTS', locked);
    end if;
  end if;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped) || case when lw then jsonb_build_object('locked_docs', lk) else '{}'::jsonb end;   -- bos113
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$
$f$; end if; end $p113$;

-- public._daybook_lines(integer[],integer[],date,date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, sp.wallet, sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end /* bos113: how the voucher was paid, as the journal reads it */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to
  union all
  -- bos113 (rule daybook_align_mode = on): the card fee kept back at the settlement leaves the bank side of the day book on the settlement day, as the journal posts it (5810)
  select c.location_id, c.settle_date, 'out'::text, 'bank'::text, 'card_settlement'::text, c.fee, null::text, 'card fee'::text, c.created_staff, c.created_at, 'card_settlement'::text, c.id::text, false, false
    from public.card_settlements85 c
   where coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' and c.status = 'done' and c.fee between 0.01 and 1000000000000 and c.location_id = any (p_locs) and c.settle_date between p_from and p_to
  union all
  -- bos113 (rule drawer_short_post = on): a final drawer count difference is a cash movement of the day (short = out, over = in)
  select e.location_id, e.entry_date, case when k.diff < 0 then 'out' else 'in' end, 'cash'::text, 'cash_variance'::text, abs(k.diff), '#' || e.serial::text, 'drawer count difference'::text, e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry'::text, e.id::text, false, false
    from public.entry_counts k join public.entries e on e.id = k.entry_id
   where coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on' and k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved')
     and e.location_id = any (p_locs) and e.entry_date between p_from and p_to;
$function$
$f$; end if; end $p113$;

-- public.customer_dues_net113()
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_dues_net113()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos113: customer_dues() with the advance already applied to bills (cash move "advance used") taken off. Rows, mobile masking and rights come from customer_dues() itself (phase105 owns it);
  -- the oldest open sale date is recomputed on the same running total as customer_dues, with the advance counted as a payment.
  with b as (select * from public.customer_dues()),
  adv as (select m.customer_id as cid, sum(m.amount) as a from public.cash_moves m where m.kind = 'cust_advance_used' and m.status = 'done' and m.customer_id is not null group by 1),
  s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id in (select b2.id from b b2)),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select b.id, b.name, b.mobile, b.type, b.credit_limit, b.balance - coalesce(adv.a, 0),
         (select min(k.sale_date) from cum k where k.customer_id = b.id and k.cr > (coalesce(t.rem, 0) - b.balance) + coalesce(adv.a, 0))
  from b left join adv on adv.cid = b.id left join t on t.customer_id = b.id
  where b.balance - coalesce(adv.a, 0) > 0
  order by 6 desc;
$function$
$f$; end if; end $p113$;

-- public.collect_payment(uuid,integer,uuid,jsonb,text)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.collect_payment(p_client uuid, p_loc integer, p_customer uuid, p_payments jsonb, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform 1 from public.customers where id = p_customer for update;      -- one collection at a time per customer
  if not found then raise exception 'customer_not_found'; end if;
  if p_client is not null and exists (select 1 from public.sale_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public.customer_balance(p_customer)); end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := (pay->>'amount')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  bal := coalesce(public.customer_balance(p_customer), 0);
  if coalesce(public.rule_txt('dues_net_advance'), 'off') = 'on' then   -- bos113: what an advance already paid off is not collected again
    bal := greatest(bal - coalesce((select sum(m.amount) from public.cash_moves m where m.customer_id = p_customer and m.kind = 'cust_advance_used' and m.status = 'done'), 0), 0);
  end if;
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),
              left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot);
end $function$
$f$; end if; end $p113$;

-- public.lock_check(date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public.is_owner() then
    om := coalesce(public.rule_txt('period_lock_owner_mode'), 'off');   -- bos113: warn = the owner may still change a closed period (as before) but it is written down as a yellow exception
    if om <> 'warn' then return; end if;
    v := public.rule_txt('period_closed_until');
    if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
    begin d := v::date; exception when others then return; end;
    if p_date > d then return; end if;
    if not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
      perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
        'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
    end if;
    return;
  end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $function$
$f$; end if; end $p113$;

-- ---------- bank statement line -> journal entry + match (rule bank_stmt_post_on) ----------
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.bank_stmt_post113(p_line bigint, p_kind text, p_loc integer DEFAULT NULL::integer, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.bank_statement_lines; st date := public._acct_start(); amt numeric; ln jsonb; eid bigint; r public.journal_entries; memo text;
begin   -- bos113
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if coalesce(public.rule_txt('bank_stmt_post_on'), 'off') <> 'on' then raise exception 'switch_off: bank_stmt_post_on'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_kind is null or p_kind not in ('fee', 'interest') then raise exception 'bad_kind'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into s from public.bank_statement_lines where id = p_line for update;
  if not found then raise exception 'not found'; end if;
  perform public._a53_bank_acct(s.account_id);                                         -- only a cash / bank account (child of 1100)
  if (p_kind = 'fee' and s.amount >= 0) or (p_kind = 'interest' and s.amount <= 0) then raise exception 'wrong_sign'; end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;
  if exists (select 1 from public.journal_entries where source_type = 'bank_stmt_line' and source_id = p_line::text and reverses_id is null) then raise exception 'already_posted'; end if;
  if s.line_date < st then raise exception 'before_start'; end if;
  perform public.lock_check(s.line_date);
  amt := abs(s.amount);
  ln := public._acct_resolve(case p_kind
    when 'fee' then jsonb_build_array(jsonb_build_object('account_id', s.account_id, 'credit', amt), jsonb_build_object('a', 'bank_charges', 'debit', amt))
    else jsonb_build_array(jsonb_build_object('account_id', s.account_id, 'debit', amt), jsonb_build_object('code', '4900', 'credit', amt)) end, p_loc);
  if p_dry then return jsonb_build_object('dry', true, 'date', s.line_date, 'kind', p_kind, 'amount', amt, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  memo := case p_kind when 'fee' then 'Bank charge from statement ' else 'Bank interest from statement ' end || s.line_date::text;
  eid := public._acct_write(s.line_date, p_loc, 'bank_stmt_line', p_line::text, p_kind, memo, null, ln, null, p_client);
  perform public._a53_match1(p_line, eid, 1, 'manual', coalesce(nullif(btrim(p_note), ''), 'posted from the statement line'));
  return jsonb_build_object('id', eid, 'kind', p_kind, 'amount', amt, 'matched', true);
end $function$
$f$; end if; end $p113$;

do $p113$ begin if current_setting('phase113.ok', true) = 'on' then
  revoke all on function public.bank_stmt_post113(bigint, text, integer, text, uuid, boolean) from public, anon;
  grant execute on function public.bank_stmt_post113(bigint, text, integer, text, uuid, boolean) to authenticated;
end if; end $p113$;

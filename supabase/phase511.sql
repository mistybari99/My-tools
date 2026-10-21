-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase85.sql there and is already pasted on the live database under that name.
-- Renumbered to phase511.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- Phase 511 (Phase D of the audit fixes): stock movements that missed the books, manual-journal guard, autopost scheduler, card settlement, expense payment mode.
-- Additive, paste-twice safe. Paste AFTER phase79 (it re-creates functions from their LATEST definition, phase79 bodies included). Every new switch defaults to today's behaviour:
-- with all of them at their default nothing new is posted and no existing report changes.
--
--   D1 STOCK MOVES   _acct_docs gets one entry per stock-ledger row (source_id = ledger id, so je_source_uq keeps it once) for
--                      count adjustment  (rule acct_count_adjust)       Dr/Cr stock_adjust (5110)          against the inventory account of the item type
--                      opening stock     (rule acct_stock_opening)      Dr inventory / Cr stock_opening_equity (owner capital 3100 by default)
--                      own-use issue     (rule acct_issue_out)          Dr stock_issue_use (5120) / Cr inventory   (stock_issue and 04-2 form lines)
--                      transfers         (rule acct_transfer_mode: off | location_tagged | company_wide)
--                                        location_tagged = a pair of entries, each tagged with its own place and each balanced alone, through the inter-location clearing account
--                                        (interloc_clearing = 1230); company_wide = the owner decided the books are company-wide, nothing is posted for the pair
--                      short receipt     (rule acct_transit_loss + acct_transit_loss_at sender|receiver) Dr transit_loss (5130) / Cr clearing (location_tagged) or inventory
--                      purchase return   (rule acct_purchase_variance)  stock left at average cost, the supplier credit was at bill price: the difference goes to purchase_variance (5140)
--                    A reversal row of the stock ledger (entry revised / transfer cancelled) is posted as the mirror entry. A row without a known cost is NOT posted: it waits
--                    as cost_missing (nothing is invented). Optional rule acct_stock_moves_from (date): older rows are left out.
--                    stock_count_adjust (screen) records a gain at the current average cost when acct_count_adjust is on, so the gain has a known cost (average does not move).
--                    inventory_vs_gl: the reasons now count the new entries, so a posted movement is no longer "unexplained".
--   D4 GUARD         rule manual_journal_guard (off | on). on: a manual journal that touches an inventory / COGS / sales / payable / receivable / stock-adjust account needs a reason code
--                    (table manual_reason_codes85, owner can add) and payable / receivable lines need a party. acct_journal_post gets an optional p_reason.
--   D5 SCHEDULER     acct_autopost_tick() = the same posting as acct_post_pending, callable without a signed-in person by a scheduler (pg_cron / edge schedule) when the rule
--                    acct_scheduler_on is on; each run is kept in acct_autopost_runs85. acct_scheduler_enable(cron) / acct_scheduler_disable() schedule it through pg_cron WHEN the
--                    extension exists. acct_pending_alert85(): documents waiting longer than the alert days and the list of period-locked documents. Locks are respected.
--   D6 CARD / EXPENSE card_settle(...) books a card settlement (Dr bank, Dr bank charges, Cr card receivable) from numbers the person types; card_settle_void; card_settlement_list.
--                    The 10-2 expense voucher credits the account of data.pay_mode (cash | bank | mobile | card -> bank); no value = cash as before.
-- Tag: bos85 marks every changed line inside a re-created function.

-- ---------- guard ----------
do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public.production_post(integer, uuid, numeric, uuid, timestamp with time zone, text, numeric)') is null then
    raise exception 'phase511 needs phases 72..79 pasted first';
  end if;
  if position('bos72' in pg_get_functiondef('public.production_post(integer, uuid, numeric, uuid, timestamp with time zone, text, numeric)'::regprocedure)) = 0
     or position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0
     or position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase511 needs phase79 pasted (final merged function bodies)';
  end if;
end $g$;

-- ---------- rules (all default = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('acct_count_adjust', 'books', 'switch', 'false', null, null, null,
  'Stock গণনার পার্থক্য journal এ তোলা (stock gain / loss)', 'Stock count এর difference journal এ post করা', 'Post stock count differences to the books (stock gain / loss)',
  'বন্ধ থাকলে আগের মতোই: গণনার পার্থক্য শুধু stock এ যায়, হিসাবের খাতায় নয়।', 'Off = as before: a count difference changes the stock only, not the books. On = one entry per count adjustment against the stock gain / loss account.', 950),
 ('acct_stock_opening', 'books', 'switch', 'false', null, null, null,
  'Opening stock journal এ তোলা (owner capital এর বিপরীতে)', 'Opening stock journal এ post করা (owner capital এর against এ)', 'Post opening stock to the books (against owner capital)',
  'শুধু হিসাব শুরুর তারিখ বা তার পরের opening ধরা হয়। শুরুর জের (acct_opening) এ stock আগেই দিলে এটি চালাবেন না, নইলে দুইবার গোনা হবে।', 'Only openings dated on or after the accounting start are posted. If the stock is already inside the opening balance (acct_opening) leave this off, it would count twice.', 951),
 ('acct_issue_out', 'books', 'switch', 'false', null, null, null,
  'নিজের কাজে stock issue journal এ তোলা', 'Own-use stock issue journal এ post করা', 'Post own-use stock issues to the books',
  'বন্ধ থাকলে আগের মতোই: issue শুধু stock কমায়, খরচ হিসাবে আসে না।', 'Off = as before: an issue lowers the stock only. On = Dr stock issued for own use / Cr inventory at the ledger cost.', 952),
 ('acct_transfer_mode', 'books', 'choice', '"off"', '["off","location_tagged","company_wide"]', null, null,
  'Stock transfer এর হিসাব: বন্ধ / স্থানভিত্তিক জোড়া / পুরো কোম্পানি', 'Stock transfer এর accounting: off / location-tagged pair / company-wide', 'Stock transfer accounting: off, location-tagged pair, or company-wide',
  'স্থানভিত্তিক জোড়া = পাঠানো ও গ্রহণ আলাদা entry, প্রতিটি নিজের স্থানের ট্যাগসহ, মাঝখানে inter-location clearing। পুরো কোম্পানি = balance sheet শুধু কোম্পানি-ব্যাপী, জোড়া আলাদা করে তোলা হবে না।', 'location_tagged = a send entry and a receive entry, each tagged with its own place, through the inter-location clearing account. company_wide = the books are company-wide only, the pair is not posted. off = as before.', 953),
 ('acct_transit_loss', 'books', 'switch', 'false', null, null, null,
  'পথে কম পৌঁছানো মাল (transit loss) journal এ তোলা', 'Transit এ কম পৌঁছানো stock journal এ post করা', 'Post stock short in transit to the books',
  'Transfer গ্রহণের সময় কম পেলে কমতির খরচ transit loss খাতে যায়।', 'When a transfer is received short, the missing cost goes to the transit loss account.', 954),
 ('acct_transit_loss_at', 'books', 'choice', '"receiver"', '["receiver","sender"]', null, null,
  'Transit loss কোন স্থানের খরচ: গ্রহণকারী / প্রেরক', 'Transit loss কোন place এর cost: receiver / sender', 'Which place carries a transit loss: receiver or sender',
  null, 'Used only when transit loss posting is on.', 955),
 ('acct_purchase_variance', 'books', 'switch', 'false', null, null, null,
  'Purchase return এর দামের পার্থক্য journal এ তোলা', 'Purchase return এর price variance journal এ post করা', 'Post the price variance of purchase returns to the books',
  'Return এ stock গড় খরচে বের হয়, সরবরাহকারীর credit বিলের দামে; পার্থক্য purchase variance খাতে যায়।', 'A return takes the stock out at average cost while the supplier credit is at bill price. On = the difference goes to the purchase variance account.', 956),
 ('acct_stock_moves_from', 'books', 'text', '""', null, null, null,
  'Stock movement journal এর শুরুর তারিখ (ফাঁকা = হিসাব শুরু থেকে)', 'Stock movement journal এর start date (ফাঁকা = accounting start থেকে)', 'Stock movement posting from this date (blank = from the accounting start)',
  'YYYY-MM-DD। এর আগের তারিখের movement আর তোলা হবে না।', 'Format YYYY-MM-DD. Older stock movements are left out.', 957),
 ('manual_journal_guard', 'books', 'choice', '"off"', '["off","on"]', null, null,
  'হাতে লেখা journal এর পাহারা: বন্ধ / চালু', 'Manual journal guard: off / on', 'Manual journal guard: off or on',
  'চালু হলে inventory, COGS, sales, payable, receivable ইত্যাদি খাতে হাতে লিখতে কারণ-কোড লাগবে, আর payable / receivable লাইনে party লাগবে।', 'On = a manual journal on an inventory, COGS, sales, payable, receivable or stock-adjust account needs a reason code, and payable / receivable lines need a party.', 958),
 ('acct_scheduler_on', 'books', 'switch', 'false', null, null, null,
  'নির্ধারিত সময়ে নিজে নিজে posting (scheduler)', 'Scheduled auto posting (scheduler)', 'Scheduled auto posting (scheduler)',
  'চালু হলে scheduler acct_autopost_tick() ডাকলে বাকি document গুলো journal এ উঠবে। scheduler চালু করা server এর কাজ।', 'On = a scheduler calling acct_autopost_tick() posts the waiting documents. Starting the scheduler itself is a server setup.', 959),
 ('acct_pending_alert_days', 'books', 'number', '1', null, 0, 365, 
  'কত দিনের বেশি পুরোনো বাকি document এ সতর্কতা', 'কত দিনের বেশি পুরোনো pending document এ alert', 'Alert for documents waiting longer than this many days',
  null, 'A document dated before (today minus this many days) that is still not in the books is counted as waiting too long.', 960)
on conflict (key) do nothing;

-- ---------- accounts and mapping keys (additive; the owner may re-point any key with acct_mapping_set) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort) values
 ('5110', 'স্টক গণনার লাভ / ক্ষতি', 'Stock count gain / loss', 'expense', 'debit', false, true, 4110),
 ('5120', 'নিজের কাজে stock issue', 'Stock issued for own use', 'expense', 'debit', false, true, 4120),
 ('5130', 'পথে কম পৌঁছানো মাল (transit loss)', 'Stock short in transit', 'expense', 'debit', false, true, 4130),
 ('5140', 'ক্রয় ফেরতের দামের পার্থক্য', 'Purchase price variance', 'expense', 'debit', false, true, 4140)
on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select v.k, a.id, v.bn, v.en from (values
    ('stock_adjust', '5110', 'স্টক গণনার লাভ / ক্ষতি', 'Stock count gain / loss'),
    ('stock_issue_use', '5120', 'নিজের কাজে stock issue', 'Stock issued for own use'),
    ('transit_loss', '5130', 'পথে কম পৌঁছানো মাল', 'Stock short in transit'),
    ('purchase_variance', '5140', 'ক্রয় ফেরতের দামের পার্থক্য', 'Purchase price variance'),
    ('stock_opening_equity', '3100', 'Opening stock এর বিপরীত (owner capital)', 'Opening stock counterpart (owner capital)'),
    ('interloc_clearing', '1230', 'স্থানান্তরের inter-location clearing', 'Inter-location clearing for transfers'),
    ('bank_charges', '5810', 'ব্যাংক / কার্ড চার্জ', 'Bank / card charges')) v(k, code, bn, en)
  join public.coa_accounts a on a.code = v.code
  on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.acct_autopost_runs85 (
  id bigint generated always as identity primary key, ran_at timestamptz not null default now(),
  posted int not null default 0, reversed int not null default 0, errors int not null default 0, locked int not null default 0, waiting int not null default 0,
  more boolean not null default false, note text);
alter table public.acct_autopost_runs85 enable row level security;
revoke all on public.acct_autopost_runs85 from public, anon, authenticated;

create table if not exists public.manual_reason_codes85 (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,39}$'), label_bn text not null, label_mix text, label_en text not null,
  active boolean not null default true, sort int not null default 0, updated_at timestamptz not null default now(), updated_by uuid);
alter table public.manual_reason_codes85 enable row level security;
revoke all on public.manual_reason_codes85 from public, anon, authenticated;
grant select on public.manual_reason_codes85 to authenticated;
drop policy if exists manual_reason_codes85_sel on public.manual_reason_codes85;
create policy manual_reason_codes85_sel on public.manual_reason_codes85 for select to authenticated using (public._acct_view());
insert into public.manual_reason_codes85 (code, label_bn, label_mix, label_en, sort) values
 ('correction', 'আগের entry সংশোধন', 'আগের entry এর correction', 'Correction of an earlier entry', 10),
 ('reclass', 'অন্য খাতে সরানো', 'অন্য account এ reclass', 'Moved to another account', 20),
 ('audit_adjust', 'অডিটরের সমন্বয়', 'Auditor এর adjustment', 'Auditor adjustment', 30),
 ('other', 'অন্য কারণ (note এ লিখুন)', 'অন্য reason (memo তে লিখুন)', 'Other reason (write it in the memo)', 90)
on conflict (code) do nothing;
drop trigger if exists audit_manual_reason_codes85 on public.manual_reason_codes85;
create trigger audit_manual_reason_codes85 after insert or update on public.manual_reason_codes85 for each row execute function public.log_change('code');

create table if not exists public.card_settlements85 (
  id uuid primary key default gen_random_uuid(), client_id uuid unique, location_id int not null references public.locations(id),
  settle_date date not null, gross numeric(14,2) not null check (gross > 0), fee numeric(14,2) not null default 0 check (fee >= 0 and fee < gross),
  bank_mode text not null default 'bank' check (bank_mode in ('bank', 'mobile')), note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_note text);
create index if not exists card_settlements85_loc on public.card_settlements85 (location_id, settle_date);
alter table public.card_settlements85 enable row level security;
revoke all on public.card_settlements85 from public, anon, authenticated;
grant select on public.card_settlements85 to authenticated;
drop policy if exists card_settlements85_sel on public.card_settlements85;
create policy card_settlements85_sel on public.card_settlements85 for select to authenticated using (public._acct_view() and public.can_loc(location_id));
create or replace function public._card_settle_ro85() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.status = 'done' and new.status = 'void' and (to_jsonb(new) - 'status' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'status' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: a card settlement cannot be changed or deleted (void it)';
end $$;
drop trigger if exists card_settle_ro85 on public.card_settlements85;
create trigger card_settle_ro85 before update or delete on public.card_settlements85 for each row execute function public._card_settle_ro85();
drop trigger if exists audit_card_settlements85 on public.card_settlements85;
create trigger audit_card_settlements85 after insert or update on public.card_settlements85 for each row execute function public.log_change('id');

-- ---------- helpers ----------
create or replace function public._acct_from85() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('acct_stock_moves_from');
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return v::date; exception when others then return null; end;
end $$;

-- one row per stock-ledger row that belongs to a movement the books did not have; only the movements whose rule is on
create or replace function public._acct_stock_moves85(p_start date)
returns table(lid bigint, cls text, d date, loc int, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
language sql stable security definer set search_path = public as $$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer' end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal')
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$$;

-- purchase return: stock left at ledger cost, supplier credit was at bill price (per inventory account); the lines that fix the books
create or replace function public._pvar85(p_bill uuid)
returns table(nulls int, nonzero boolean, lines jsonb) language sql stable security definer set search_path = public as $$
  with lo as (select public._acct_buy_key(it.item_type) k, sum(round(-l.qty_delta * coalesce(l.unit_cost, 0), 2)) a, count(*) filter (where coalesce(l.unit_cost, 0) = 0) n
                from public.stock_ledger l join public.items it on it.id = l.item_id
               where l.ref_type = 'purchase' and l.reason = 'purchase_return' and l.ref_id = p_bill::text and public._acct_buy_key(it.item_type) in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       jc as (select al.k, sum(al.amt) a from public._acct_purchase_alloc(p_bill) al where al.k in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       dd as (select coalesce(lo.k, jc.k) k, round(coalesce(lo.a, 0) - coalesce(jc.a, 0), 2) df from lo full join jc on jc.k = lo.k),
       nz as (select * from dd where df <> 0),
       tot as (select coalesce(sum(df), 0) net from nz)
  select coalesce((select sum(n) from lo), 0)::int, exists (select 1 from nz),
         (select jsonb_agg(j) from (
            select jsonb_build_object('a', k, case when df > 0 then 'c' else 'd' end, abs(df)) j from nz
            union all select jsonb_build_object('a', 'purchase_variance', case when net > 0 then 'd' else 'c' end, abs(net)) from tot where net <> 0) x);
$$;

-- reserved accounts for the manual-journal guard (mapping keys) and the check itself
create or replace function public._manual_guard_keys85() returns text[] language sql immutable as $$
  select array['inv_finished', 'inv_raw', 'inv_pack', 'cogs', 'sales', 'sales_returns', 'sales_discount', 'payable', 'receivable', 'wastage', 'stock_adjust', 'stock_issue_use', 'transit_loss',
               'purchase_variance', 'overhead_absorbed']::text[];
$$;
create or replace function public._manual_guard85(p_lines jsonb, p_reason text) returns void language plpgsql stable security definer set search_path = public as $$
declare res bigint[]; par bigint[]; x jsonb; touched boolean := false; aid bigint;
begin
  res := array(select account_id from public.acct_mappings where key = any (public._manual_guard_keys85()));
  par := array(select account_id from public.acct_mappings where key in ('payable', 'receivable'));
  for x in select * from jsonb_array_elements(p_lines) loop
    aid := (x->>'account_id')::bigint;
    if aid = any (res) then touched := true; end if;
    if aid = any (par) and (nullif(x->>'party_type', '') is null or nullif(x->>'party_id', '') is null) then raise exception 'party_required'; end if;
  end loop;
  if touched then
    if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
    if not exists (select 1 from public.manual_reason_codes85 c where c.code = p_reason and c.active) then raise exception 'bad_reason'; end if;
  end if;
end $$;


-- ---------- re-created functions (latest definitions = phase79 bodies; changed lines carry bos85) ----------

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
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
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
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
end $function$
;

CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]';
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
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
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
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
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
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped);
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$
;

CREATE OR REPLACE FUNCTION public.stock_count_adjust(p_item uuid, p_loc integer, p_counted numeric, p_note text, p_unit text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; bal public.stock_balance; d numeric; lid bigint; tol numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_count_adjust', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'count_adjust' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_counted is null or not (p_counted between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  bq := public._base_qty(p_item, p_counted, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_count_adjust', p_loc, 'count:' || p_item::text) then raise exception 'not allowed'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;
  d := round(bq - bal.qty, 4);
  if d = 0 then return jsonb_build_object('ledger_id', null, 'delta', 0, 'qty', bal.qty); end if;
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, case when d > 0 and public.rule_on('acct_count_adjust') then bal.avg_cost end /* bos85: a gain is recorded at the average cost so it has a known cost; the average does not move */, null, now(), left(p_note, 200), null, 'none', null, p_client);
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $function$
;

CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null then
    if not public._acct_all() or exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  elsif not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  basis := case when d >= t then 'average_cost' else 'ledger_replay' end;
  foreach k in array array['inv_finished', 'inv_raw', 'inv_pack'] loop
    select m.account_id, a.code, a.name_bn, a.name_en into acct, acode, anbn, anen from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
    if acct is null then continue; end if;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(x.v), 0) as lv_all, coalesce(sum(x.v) filter (where x.cib), 0) as lv_cib,
           coalesce(sum(x.v) filter (where x.reason = 'count_adjust'), 0) as g_count,
           coalesce(sum(x.v) filter (where x.reason = 'opening'), 0) as g_opening,
           coalesce(sum(x.v) filter (where x.reason in ('transfer_out', 'transfer_in') or x.ref_type = 'transfer'), 0) as g_transfer,
           coalesce(sum(x.v) filter (where x.reason = 'issue_out' and x.ref_type in ('issue', 'entry')), 0) as g_issue,
           coalesce(sum(x.v) filter (where (x.reason = 'production_in' and not x.has_run) or (x.reason = 'purchase_in' and x.ref_type = 'entry') or (x.reason = 'reversal' and x.ref_type = 'entry')), 0) as g_manual_in,
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger sl join public.items it on it.id = sl.item_id
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening') /* bos85 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger sl join public.items it on it.id = sl.item_id
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in, 2)),
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret + j_var, 2)),   -- bos85
      jsonb_build_object('code', 'production_cost_missing', 'amount', round(g_prod, 2)),
      jsonb_build_object('code', 'manual_journal', 'amount', round(g_man, 2)));
    ex := df - (select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(rs) x);
    rows_ := rows_ || jsonb_build_object('key', k, 'code', acode, 'name_bn', anbn, 'name_en', anen, 'gl', round(gl, 2), 'valuation', round(v, 2), 'ledger_value', round(rw.lv_all, 2),
                'diff', df, 'reasons', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(rs) x where abs((x->>'amount')::numeric) >= 0.005), 'unexplained', round(ex, 2));
    tg := tg + gl; tv := tv + v; tx := tx + ex;
  end loop;
  ok := abs(tg - tv) < 0.05;
  return jsonb_build_object('as_of', d, 'location_id', p_loc, 'start', st, 'accounting_on', public.rule_on('accounting_on'), 'valuation_basis', basis, 'rows', rows_,
    'total', jsonb_build_object('gl', round(tg, 2), 'valuation', round(tv, 2), 'diff', round(tg - tv, 2), 'unexplained', round(tx, 2)), 'agree', ok,
    'note', 'Read only: nothing is posted. Reasons are movements the books or the stock ledger do not have; "unexplained" is what is left.');
end $function$
;

CREATE OR REPLACE FUNCTION public.acct_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); pend int := 0; lck int := 0; wt int := 0; er int := 0; erl jsonb := '[]'::jsonb;   -- bos72
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is not null then   -- bos72: documents not yet in the books (the same list acct_post_pending would work through)
    with dd as materialized (select * from public._acct_docs(st)),
    e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null),
           (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries, 'last_at', y.last_at) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, er, erl;
  end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', st,
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),
    'last_post_at', (select max(created_at) from public.journal_entries where (created_by is not null or exists (select 1 from public.acct_autopost_runs85)) and source_type not in ('manual', 'opening')),   -- bos72 bos85: a scheduler run has no person
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl,   -- bos72
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));   -- bos85
end $function$
;

drop function if exists public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean);   -- bos85: one function with the optional reason code (callers with named or fewer arguments are unaffected)
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_memo is null or length(btrim(p_memo)) < 3 then raise exception 'memo_required'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  ln := public._acct_resolve(p_lines, p_loc);
  if coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' then perform public._manual_guard85(ln, p_reason); end if;   -- bos85
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', p_date, 'total_debit', td, 'total_credit', tc, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $function$
;

-- ---------- D5: scheduler entry point, pending alert ----------
create or replace function public.acct_autopost_tick() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; i int := 0; posted int := 0; rev int := 0; er int := 0; lk int := 0; wt int := 0; mr boolean := false;
begin
  if auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;      -- a scheduler has no signed-in person; a person must be the owner
  if auth.uid() is null and not public.rule_on('acct_scheduler_on') then return jsonb_build_object('skipped', 'scheduler_off'); end if;
  perform set_config('bos.autopost85', 'on', true);
  begin
    loop
      i := i + 1;
      r := public.acct_post_pending(false, 1500);
      if r ? 'data_needed' then insert into public.acct_autopost_runs85 (note) values ('data_needed'); perform set_config('bos.autopost85', '', true); return r; end if;
      posted := posted + coalesce((r->>'posted')::int, 0); rev := rev + coalesce((r->>'reversed')::int, 0); lk := lk + coalesce((r->>'locked')::int, 0);
      er := er + jsonb_array_length(coalesce(r->'errors', '[]'::jsonb));
      wt := (select coalesce(sum(value::int), 0) from jsonb_each_text(coalesce(r->'waiting', '{}'::jsonb)));
      mr := coalesce((r->>'more')::boolean, false);
      exit when not mr or i >= 5;
    end loop;
  exception when others then
    insert into public.acct_autopost_runs85 (note) values (left(sqlerrm, 200));
    perform set_config('bos.autopost85', '', true);
    return jsonb_build_object('error', sqlerrm);
  end;
  insert into public.acct_autopost_runs85 (posted, reversed, errors, locked, waiting, more) values (posted, rev, er, lk, wt, mr);
  perform set_config('bos.autopost85', '', true);
  return jsonb_build_object('posted', posted, 'reversed', rev, 'errors', er, 'locked', lk, 'waiting', wt, 'more', mr, 'runs', i);
end $$;

create or replace function public.acct_pending_alert85(p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); t date := public._acct_today(); days int; oc int; od date; lc int; wc int; ll jsonb; cl date; cv text := public.rule_txt('period_closed_until');
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  days := coalesce(public.rule_num('acct_pending_alert_days'), 1)::int;
  if cv ~ '^\d{4}-\d{2}-\d{2}$' then begin cl := cv::date; exception when others then cl := null; end; end if;   -- who sees the list is not asked: the owner bypasses the lock, everyone else (and the scheduler) is held by it
  with p as materialized (select d.source_type, d.source_id, case when d.live then d.entry_date else coalesce(d.void_date, t) end eff, d.memo, d.live, d.waiting from public._acct_docs(st) d)
  select count(*) filter (where waiting is null and eff < t - days), min(eff) filter (where waiting is null and eff < t - days),
         count(*) filter (where waiting is null and (cl is not null and eff <= cl)), count(*) filter (where waiting is not null),
         (select coalesce(jsonb_agg(jsonb_build_object('source_type', z.source_type, 'source_id', z.source_id, 'date', z.eff, 'memo', z.memo, 'reversal', not z.live) order by z.eff, z.source_type, z.source_id), '[]'::jsonb)
            from (select * from p where waiting is null and (cl is not null and eff <= cl) order by eff, source_type, source_id limit least(greatest(coalesce(p_limit, 50), 1), 500)) z)
    into oc, od, lc, wc, ll from p;
  return jsonb_build_object('days', days, 'old_count', oc, 'oldest', od, 'alert', oc > 0, 'locked_count', lc, 'locked', ll, 'force_by', 'owner', 'waiting_cost', wc,
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));
end $$;

-- schedule through pg_cron only when the extension exists (starting it is a server setting; nothing here installs it)
create or replace function public.acct_scheduler_enable(p_cron text) returns jsonb language plpgsql security definer set search_path = public as $$
declare jid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_cron is null or btrim(p_cron) !~ '^[0-9*/,\-]+( [0-9*/,\-]+){4}$' then raise exception 'bad_cron'; end if;
  if to_regnamespace('cron') is null then return jsonb_build_object('scheduled', false, 'reason', 'pg_cron_missing'); end if;
  execute format('select cron.schedule(%L, %L, %L)', 'bos_acct_autopost', btrim(p_cron), 'select public.acct_autopost_tick()') into jid;
  update public.rules set value = 'true'::jsonb, updated_at = now(), updated_by = auth.uid() where key = 'acct_scheduler_on';
  return jsonb_build_object('scheduled', true, 'job', jid, 'cron', btrim(p_cron));
end $$;
create or replace function public.acct_scheduler_disable() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.rules set value = 'false'::jsonb, updated_at = now(), updated_by = auth.uid() where key = 'acct_scheduler_on';
  if to_regnamespace('cron') is not null then execute format('select cron.unschedule(%L)', 'bos_acct_autopost'); end if;
  return jsonb_build_object('scheduled', false);
end $$;

-- ---------- D4: reason codes ----------
create or replace function public.manual_reason_set(p_code text, p_bn text, p_mix text, p_en text, p_active boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(p_bn), '') is null or nullif(btrim(p_en), '') is null then raise exception 'label_required'; end if;
  insert into public.manual_reason_codes85 (code, label_bn, label_mix, label_en, active, updated_by) values (p_code, btrim(p_bn), nullif(btrim(p_mix), ''), btrim(p_en), coalesce(p_active, true), auth.uid())
    on conflict (code) do update set label_bn = excluded.label_bn, label_mix = excluded.label_mix, label_en = excluded.label_en, active = excluded.active, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('code', p_code);
end $$;
create or replace function public.manual_reasons85() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'label_bn', c.label_bn, 'label_mix', c.label_mix, 'label_en', c.label_en, 'active', c.active) order by c.sort, c.code) from public.manual_reason_codes85 c), '[]'::jsonb);
end $$;

-- ---------- D6: card settlement ----------
create or replace function public.card_settle(p_loc int, p_date date, p_gross numeric, p_fee numeric default 0, p_note text default null, p_client uuid default null, p_bank_mode text default 'bank') returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.card_settlements85; sid text; t date := public._acct_today(); d date := coalesce(p_date, public._acct_today()); fee numeric := coalesce(p_fee, 0); bal numeric;
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.card_settlements85 where client_id = p_client;
    if found then
      if c.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', c.id, 'dup', true);
    end if;
  end if;
  if p_gross is null or not (p_gross > 0 and p_gross <= 1000000000000) then raise exception 'bad_amount'; end if;
  if not (fee >= 0 and fee < p_gross) then raise exception 'bad_fee'; end if;
  if coalesce(p_bank_mode, 'bank') not in ('bank', 'mobile') then raise exception 'bad_mode'; end if;
  if d > t then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  select coalesce(sum(jl.debit - jl.credit), 0) into bal from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc;
  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)
    values (p_client, p_loc, d, round(p_gross, 2), round(fee, 2), coalesce(p_bank_mode, 'bank'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid) returning * into c;
  return jsonb_build_object('id', c.id, 'unsettled', bal, 'over', round(p_gross, 2) > bal);
end $$;

create or replace function public.card_settle_void(p_id uuid, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.card_settlements85;
begin
  select * into c from public.card_settlements85 where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._acct_manage() and public.can_loc(c.location_id)) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  if c.status = 'void' then return jsonb_build_object('id', c.id, 'noop', true); end if;
  perform public.lock_check(c.settle_date);
  update public.card_settlements85 set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', c.id, 'status', 'void');
end $$;

create or replace function public.card_settlement_list(p_loc int, p_from date default null, p_to date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._acct_view() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return jsonb_build_object('location_id', p_loc,
    'unsettled', (select coalesce(sum(jl.debit - jl.credit), 0) from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'date', c.settle_date, 'gross', c.gross, 'fee', c.fee, 'net', c.gross - c.fee, 'bank_mode', c.bank_mode, 'note', c.note, 'status', c.status) order by c.settle_date desc, c.created_at desc)
                       from public.card_settlements85 c where c.location_id = p_loc and (p_from is null or c.settle_date >= p_from) and (p_to is null or c.settle_date <= p_to)), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
revoke all on function public._acct_from85(), public._acct_stock_moves85(date), public._pvar85(uuid), public._manual_guard_keys85(), public._manual_guard85(jsonb, text), public._card_settle_ro85() from public, anon, authenticated;
revoke all on function public.acct_autopost_tick(), public.acct_pending_alert85(int), public.acct_scheduler_enable(text), public.acct_scheduler_disable(), public.manual_reason_set(text, text, text, text, boolean), public.manual_reasons85(),
  public.card_settle(int, date, numeric, numeric, text, uuid, text), public.card_settle_void(uuid, text), public.card_settlement_list(int, date, date),
  public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean, text) from public, anon;
grant execute on function public.acct_autopost_tick(), public.acct_pending_alert85(int), public.acct_scheduler_enable(text), public.acct_scheduler_disable(), public.manual_reason_set(text, text, text, text, boolean), public.manual_reasons85(),
  public.card_settle(int, date, numeric, numeric, text, uuid, text), public.card_settle_void(uuid, text), public.card_settlement_list(int, date, date),
  public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean, text) to authenticated;
do $s$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then grant execute on function public.acct_autopost_tick() to service_role; end if;
end $s$;

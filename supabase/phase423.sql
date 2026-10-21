-- ============================================================
-- BOS tool · Phase 423 (RPT-B2 R3): RECONCILIATION and integrity of stock. Read-only. Paste after phase422. Safe to paste twice. Open to report_stock holders at their own places.
--   #72 stock_integrity      (engine 3, viewer #/report/stock_integrity)  negative balances, a cached balance that differs from the ledger, batches that hold more than the balance
--   #75 stock_recon_period(from, to, loc)                                   opening (ledger replay) + in - out = closing per item and place, in-transit and short transfer lines,
--                                                                           and a check of the ledger against the cached balance (web/stockrep.js #/stockrep/recon)
--   #82 daily_closing        (engine 3)  the closing stock of each day against the NEXT day's sales and loss (empty, not 0, while the next day has not happened)
--   #73 item_turnover        (engine 3)  consumption / average stock, and days on hand; empty where there is no consumption or no stock (no division by zero, no estimate)
-- Quantities are per item in its own base unit and are never added across items. The stock identity is: opening + received - issued = closing, on the ledger (made_at in Asia/Dhaka days).
-- ============================================================

-- daily closing stock per item and place from the ledger (also gives the day's net sales and loss); day d1 .. d2 + 1 (the extra day is the "next day" of d2)
create or replace function public._r4_closing_daily(d1 date, d2 date, locs int[], ty text[], cat text[])
returns table (day date, item_id uuid, location_id int, closing numeric, sales_net numeric, loss numeric, received numeric)
language sql stable security definer set search_path = public as $$
  with p as (
    select l.item_id, l.location_id from public.stock_ledger l join public.items it on it.id = l.item_id
     where l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date <= d2 + 1 and it.is_active and (ty is null or it.item_type = any (ty)) and (cat is null or it.category = any (cat))
     group by l.item_id, l.location_id),
  dn as (
    select l.item_id, l.location_id, (l.made_at at time zone 'Asia/Dhaka')::date as d, sum(l.qty_delta) as net,
           -sum(l.qty_delta) filter (where l.reason in ('sale_out', 'sale_void_in', 'sale_return')) as sales_net,
           -sum(l.qty_delta) filter (where l.reason = 'wastage') as loss,
           sum(l.qty_delta) filter (where l.reason in ('purchase_in', 'production_in', 'transfer_in')) as received
      from public.stock_ledger l join p on p.item_id = l.item_id and p.location_id = l.location_id
     where (l.made_at at time zone 'Asia/Dhaka')::date <= d2 + 1 group by 1, 2, 3),
  op as (select dn.item_id, dn.location_id, sum(dn.net) as o from dn where dn.d < d1 group by 1, 2),
  g as (select p.item_id, p.location_id, s::date as dd from p cross join generate_series(d1, d2 + 1, interval '1 day') s)
  select g.dd, g.item_id, g.location_id, coalesce(op.o, 0) + sum(coalesce(dn.net, 0)) over (partition by g.item_id, g.location_id order by g.dd),
         coalesce(dn.sales_net, 0), coalesce(dn.loss, 0), coalesce(dn.received, 0)
    from g left join dn on dn.item_id = g.item_id and dn.location_id = g.location_id and dn.d = g.dd
           left join op on op.item_id = g.item_id and op.location_id = g.location_id;
$$;
revoke all on function public._r4_closing_daily(date, date, int[], text[], text[]) from public, anon, authenticated;

-- ---------- #72 negative balances and integrity ----------
create or replace function public._r3q_stock_integrity(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c, public._r4_types(flt) as ty),
  lg as (select l.item_id, l.location_id, sum(l.qty_delta) as q from public.stock_ledger l where l.location_id = any (locs) group by 1, 2),
  bt as (select b.item_id, b.location_id, sum(b.qty_remaining) as q from public.stock_batches b where b.location_id = any (locs) and b.qty_remaining > 0 group by 1, 2),
  base as (
    select sb.item_id, sb.location_id, sb.qty as cached, coalesce(lg.q, 0) as ledger, coalesce(bt.q, 0) as batched
      from public.stock_balance sb left join lg on lg.item_id = sb.item_id and lg.location_id = sb.location_id left join bt on bt.item_id = sb.item_id and bt.location_id = sb.location_id
     where sb.location_id = any (locs)),
  neg as (
    select b.item_id, b.location_id, b.cached, b.ledger,
           (select min(r.d) from (select (l.made_at at time zone 'Asia/Dhaka')::date as d, sum(l.qty_delta) over (order by l.made_at, l.id) as run from public.stock_ledger l
                                   where l.item_id = b.item_id and l.location_id = b.location_id) r where r.run < 0) as since,
           (select coalesce(sum(-l.qty_delta), 0) from public.stock_ledger l where l.item_id = b.item_id and l.location_id = b.location_id and l.qty_delta < 0 and l.batch_id is null
               and l.reason in ('sale_out', 'issue_out', 'transfer_out', 'wastage')) as unbatched_out
      from base b where b.cached < 0)
  select jsonb_build_object('issue', 'negative', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', n.cached, 'ledger_qty', n.ledger, 'diff', round(n.cached - n.ledger, 4), 'short_qty', -n.cached, 'since', n.since, 'unbatched_out_qty', n.unbatched_out,
      'detail', 'More went out than the book had. The oversold part is posted with no batch, so it cannot be traced to a production or receipt.',
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, n.location_id))
    from neg n join public.items it on it.id = n.item_id join public.locations lo on lo.id = n.location_id cross join cat where (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty))
  union all
  select jsonb_build_object('issue', 'cache_differs', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', b.cached, 'ledger_qty', b.ledger, 'diff', round(b.cached - b.ledger, 4), 'short_qty', null, 'since', null, 'unbatched_out_qty', null,
      'detail', 'The cached balance differs from the sum of the ledger. The ledger is the truth; the owner can repair the cache on the stock screen (typed confirmation).',
      'drill', format('#/stockrep/ledger?item=%s&loc=%s', it.id, b.location_id))
    from base b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id cross join cat
   where abs(b.cached - b.ledger) > 0.00005 and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty))
  union all
  select jsonb_build_object('issue', 'batches_exceed_balance', 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'cached_qty', b.cached, 'ledger_qty', b.ledger, 'diff', round(b.batched - b.cached, 4), 'short_qty', null, 'since', null, 'unbatched_out_qty', null,
      'detail', 'Open batches hold more (' || round(b.batched, 4) || ') than the balance (' || b.cached || '). A batch can never hold more than the item''s balance.',
      'drill', format('#/batchrep/batches?item=%s&loc=%s', it.id, b.location_id))
    from base b join public.items it on it.id = b.item_id join public.locations lo on lo.id = b.location_id cross join cat
   where b.batched > greatest(b.cached, 0) + 0.0005 and (cat.c is null or it.category = any (cat.c)) and (cat.ty is null or it.item_type = any (cat.ty));
$$;

create or replace function public._r4d_stock_integrity(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; n_all int := coalesce((p_res #>> '{page,groups}')::int, 0);
begin
  if n_all = 0 then
    return public._r4_addnote(res, public._r4_note('info', 'Nothing to report: no negative balance, no cached balance that differs from the ledger, no batch that holds more than the balance (for the places and filters chosen).',
      'কিছু নেই: কোনো ঋণাত্মক ব্যালান্স নেই, ক্যাশ ব্যালান্স খাতার সাথে মেলে, কোনো ব্যাচ ব্যালান্সের চেয়ে বেশি ধরে না (বাছা লোকেশন ও ফিল্টারে)।'));
  end if;
  return public._r4_addnote(res, public._r4_note('info', 'Three checks: a NEGATIVE balance (more went out than the book had), a cached balance that DIFFERS from the ledger, and batches that hold MORE than the balance. Each row opens the ledger of that item and place.',
    'তিনটি যাচাই: ঋণাত্মক ব্যালান্স (বইয়ে যা ছিল তার চেয়ে বেশি বের হয়েছে), ক্যাশ ব্যালান্স খাতার সাথে অমিল, এবং ব্যালান্সের চেয়ে বেশি ধরা ব্যাচ। প্রতিটি সারি সেই আইটেম ও জায়গার খাতা খোলে।'));
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('stock_integrity', 'S7', 'stock', 'ঋণাত্মক স্টক ও হিসাবের গরমিল', 'Negative stock and integrity', 'ঋণাত্মক Stock ও হিসাবের গরমিল',
  '[["issue","সমস্যা","Issue","text"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["cached_qty","ক্যাশ ব্যালান্স","Cached balance","num"],["ledger_qty","খাতার যোগফল","Ledger total","num"],["diff","পার্থক্য","Difference","num"],["short_qty","ঘাটতি (বেশি বেরিয়েছে)","Oversold by","num"],["since","কবে থেকে","Since","date"],["unbatched_out_qty","ব্যাচ ছাড়া বেরিয়েছে","Out with no batch","num"],["detail","বিবরণ","Detail","text"]]'::jsonb,
  '{}', 'issue', 'asc', array['locations','brands','categories','item_types'], true, false, false, 4207)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #75 period reconciliation ----------
create or replace function public.stock_recon_period(p_from date, p_to date, p_loc int default null, p_types text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; locs int[]; rows_ jsonb; transit jsonb; short_ jsonb; sm jsonb; cost_ok boolean; ty text[]; n bigint; cap constant int := 1500;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  locs := coalesce(array(select l.id from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)), '{}');
  ty := case when p_types is null or cardinality(p_types) = 0 then null else coalesce(array(select t.code from public.item_types t where t.code = any (p_types)), '{}') end;
  cost_ok := public.rpt_cost_ok();
  with a as (
    select l.item_id, l.location_id,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date < p_from) as opening,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as period,
           sum(l.qty_delta) filter (where (l.made_at at time zone 'Asia/Dhaka')::date <= p_to) as closing_replay,
           sum(l.qty_delta) as total_all,
           sum(l.qty_delta) filter (where l.reason = 'opening' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as opening_entry,
           sum(l.qty_delta) filter (where l.reason = 'purchase_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as purchase_in,
           sum(l.qty_delta) filter (where l.reason = 'production_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as production_in,
           sum(l.qty_delta) filter (where l.reason = 'transfer_in' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as transfer_in,
           sum(l.qty_delta) filter (where l.reason in ('sale_void_in', 'sale_return') and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as sales_back,
           sum(l.qty_delta) filter (where l.reason = 'sale_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as sale_out,
           sum(l.qty_delta) filter (where l.reason = 'issue_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as issue_out,
           sum(l.qty_delta) filter (where l.reason = 'wastage' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as wastage,
           sum(l.qty_delta) filter (where l.reason = 'transfer_out' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as transfer_out,
           sum(l.qty_delta) filter (where l.reason = 'purchase_return' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as purchase_return,
           sum(l.qty_delta) filter (where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as count_adjust,
           sum(l.qty_delta) filter (where l.reason = 'reversal' and (l.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to) as reversal
      from public.stock_ledger l join public.items it on it.id = l.item_id
     where l.location_id = any (locs) and (ty is null or it.item_type = any (ty)) group by l.item_id, l.location_id),
  c as (
    select a.*, coalesce(a.opening, 0) as o, coalesce(a.period, 0) as pd,
           coalesce(a.opening_entry, 0) + coalesce(a.purchase_in, 0) + coalesce(a.production_in, 0) + coalesce(a.transfer_in, 0) + coalesce(a.sales_back, 0) + coalesce(a.sale_out, 0) + coalesce(a.issue_out, 0)
             + coalesce(a.wastage, 0) + coalesce(a.transfer_out, 0) + coalesce(a.purchase_return, 0) + coalesce(a.count_adjust, 0) + coalesce(a.reversal, 0) as listed
      from a where coalesce(a.opening, 0) <> 0 or coalesce(a.period, 0) <> 0 or coalesce(a.closing_replay, 0) <> 0),
  t as (                                                -- still on the road at the end of p_to: sent by then, not received by then
    select x.from_location_id as lid, x.item_id, sum(x.qty) as q from public.stock_transfers x
     where (x.sent_at at time zone 'Asia/Dhaka')::date <= p_to and x.from_location_id = any (locs)
       and (x.status = 'sent' or (x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date > p_to) or (x.status = 'cancelled' and (x.cancelled_at at time zone 'Asia/Dhaka')::date > p_to))
     group by 1, 2),
  r as (
    select c.*, it.code, it.name_bn, coalesce(it.name_en, it.name_bn) as name_en, public._item_base(it.id) as unit, it.item_type, lo.name_bn as lbn, coalesce(lo.name_en, lo.name_bn) as len,
           c.o + c.pd as closing, sb.qty as cached, coalesce(t.q, 0) as in_transit_out, row_number() over (order by lo.id, it.code) as rn, count(*) over () as cnt
      from c join public.items it on it.id = c.item_id join public.locations lo on lo.id = c.location_id
        left join public.stock_balance sb on sb.item_id = c.item_id and sb.location_id = c.location_id left join t on t.lid = c.location_id and t.item_id = c.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', r.item_id, 'location_id', r.location_id, 'location_bn', r.lbn, 'location_en', r.len, 'item_code', r.code, 'item_name', r.name_bn, 'item_name_en', r.name_en,
      'unit', r.unit, 'item_type', r.item_type, 'opening', r.o, 'opening_entry', coalesce(r.opening_entry, 0), 'purchase_in', coalesce(r.purchase_in, 0), 'production_in', coalesce(r.production_in, 0),
      'transfer_in', coalesce(r.transfer_in, 0), 'sales_back', coalesce(r.sales_back, 0), 'sale_out', coalesce(r.sale_out, 0), 'issue_out', coalesce(r.issue_out, 0), 'wastage', coalesce(r.wastage, 0),
      'transfer_out', coalesce(r.transfer_out, 0), 'purchase_return', coalesce(r.purchase_return, 0), 'count_adjust', coalesce(r.count_adjust, 0), 'reversal', coalesce(r.reversal, 0),
      'unclassified', round(r.pd - r.listed, 4), 'closing', r.closing, 'identity_diff', round(r.closing - coalesce(r.closing_replay, 0), 4),
      'later_qty', round(coalesce(r.total_all, 0) - coalesce(r.closing_replay, 0), 4), 'ledger_total', coalesce(r.total_all, 0), 'cached', coalesce(r.cached, 0),
      'cache_diff', round(coalesce(r.cached, 0) - coalesce(r.total_all, 0), 4), 'in_transit_out', r.in_transit_out,
      'state', case when abs(r.pd - r.listed) > 0.00005 or abs(r.closing - coalesce(r.closing_replay, 0)) > 0.00005 then 'unclassified'
                    when abs(coalesce(r.cached, 0) - coalesce(r.total_all, 0)) > 0.00005 then 'cache_differs' else 'ok' end) order by r.rn) filter (where r.rn <= cap), '[]'::jsonb), max(r.cnt)
    into rows_, n from r;
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'from_location_id', x.from_location_id, 'to_location_id', x.to_location_id,
      'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn), 'item_code', it.code, 'item_name', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'qty', x.qty,
      'days', p_to - (x.sent_at at time zone 'Asia/Dhaka')::date) order by x.sent_at), '[]'::jsonb) into transit
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
   where (x.sent_at at time zone 'Asia/Dhaka')::date <= p_to and (x.from_location_id = any (locs) or x.to_location_id = any (locs)) and (ty is null or it.item_type = any (ty))
     and (x.status = 'sent' or (x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date > p_to) or (x.status = 'cancelled' and (x.cancelled_at at time zone 'Asia/Dhaka')::date > p_to));
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'sent_day', (x.sent_at at time zone 'Asia/Dhaka')::date, 'received_day', (x.received_at at time zone 'Asia/Dhaka')::date,
      'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn), 'item_code', it.code, 'item_name', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id),
      'sent_qty', x.qty, 'received_qty', x.received_qty, 'short_qty', round(x.qty - x.received_qty, 4), 'claim', st.status,
      'short_value', case when cost_ok then st.value end, 'value_missing', cost_ok and st.id is not null and st.value is null) order by x.received_at), '[]'::jsonb) into short_
    from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      left join public.shortage_transit st on st.transfer_id = x.id
   where x.status = 'received' and x.received_qty < x.qty and (x.received_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (x.from_location_id = any (locs) or x.to_location_id = any (locs))
     and (ty is null or it.item_type = any (ty));
  sm := jsonb_build_object('pairs', n,
    'ok', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'ok'), 'cache_differs', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'cache_differs'),
    'unclassified', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'unclassified'),
    'later_rows', (select count(*) from jsonb_array_elements(rows_) e where (e ->> 'later_qty')::numeric <> 0),
    'in_transit_lines', jsonb_array_length(transit), 'short_lines', jsonb_array_length(short_),
    'identity_holds', not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'state' = 'unclassified'),
    'cache_checked', p_to >= today);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'rows', rows_, 'transit', transit, 'short', short_, 'summary', sm, 'truncated', coalesce(n, 0) > cap, 'cost_shown', cost_ok,
    'notes', jsonb_build_array(
      public._r4_note('info', 'Opening = the ledger replayed to the day before ' || p_from || '. Closing = opening + the movements of the period. Each item is in its own base unit, so rows are never added together. "In transit" is stock that left the sender and has not been received by ' || p_to || ': it is already out of the sender and not yet in the receiver.',
        'শুরু = ' || p_from || ' এর আগের দিন পর্যন্ত খাতার যোগফল। শেষ = শুরু + সময়ের নড়াচড়া। প্রতিটি আইটেম নিজের এককে, তাই সারি যোগ করা হয়নি। "পথে" = প্রেরক থেকে বেরিয়েছে কিন্তু ' || p_to || ' পর্যন্ত গ্রহণ হয়নি।'),
      case when p_to < today then public._r4_note('info', 'The check against the cached balance compares the cached balance now with the ledger total now; the period ends before today, so later movements are shown in "later" and are not an error.',
        'ক্যাশ ব্যালান্সের সাথে যাচাই এখনকার ক্যাশ ও এখনকার খাতার যোগফলের; সময় আজকের আগে শেষ, তাই পরের নড়াচড়া "পরে" ঘরে দেখানো, ভুল নয়।') end));
end $$;
revoke all on function public.stock_recon_period(date, date, int, text[]) from public, anon;
grant execute on function public.stock_recon_period(date, date, int, text[]) to authenticated;

-- ---------- #82 closing stock of each day against the next day's sales and loss ----------
create or replace function public._r3q_daily_closing(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select (now() at time zone 'Asia/Dhaka')::date as today, public.rpt_cost_ok() as cost),
  cd as (select * from public._r4_closing_daily(d1, d2, locs, public._r4_types(flt), public.rpt_arr_text(flt -> 'categories')))
  select jsonb_build_object('day', c.day, 'location_bn', lo.name_bn, 'location_en', coalesce(lo.name_en, lo.name_bn), 'item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn),
      'unit', public._item_base(it.id), 'closing_qty', round(c.closing, 4), 'received_qty', round(c.received, 4),
      'next_sales_qty', case when c.day + 1 <= p.today then round(n.sales_net, 4) end, 'next_loss_qty', case when c.day + 1 <= p.today then round(n.loss, 4) end,
      'sales_pct', case when c.day + 1 <= p.today and c.closing > 0 then round(n.sales_net * 100.0 / c.closing, 1) end,
      'loss_pct', case when c.day + 1 <= p.today and c.closing > 0 then round(n.loss * 100.0 / c.closing, 1) end,
      'closing_value', case when p.cost and sb.avg_cost is not null then round(c.closing * sb.avg_cost, 2) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when c.day + 1 > p.today then 'next_sales_qty' end, case when c.day + 1 > p.today then 'next_loss_qty' end,
               case when c.day + 1 > p.today or c.closing <= 0 then 'sales_pct' end, case when c.day + 1 > p.today or c.closing <= 0 then 'loss_pct' end,
               case when p.cost and sb.avg_cost is null then 'closing_value' end]) z where z is not null),
      'drill', format('#/stockrep/ledger?item=%s&loc=%s&from=%s&to=%s', it.id, c.location_id, c.day, c.day + 1))
    from cd c left join cd n on n.item_id = c.item_id and n.location_id = c.location_id and n.day = c.day + 1
      join public.items it on it.id = c.item_id join public.locations lo on lo.id = c.location_id left join public.stock_balance sb on sb.item_id = c.item_id and sb.location_id = c.location_id cross join p
   where c.day between d1 and d2 and (c.closing <> 0 or coalesce(n.sales_net, 0) <> 0 or coalesce(n.loss, 0) <> 0);
$$;

create or replace function public._r4d_daily_closing(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb;
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Closing stock at the end of each day (the ledger replayed by business day), beside what was sold and what was lost (wastage) on the NEXT day. For today the next day has not happened, so those cells are empty (not captured yet), not 0. % = next day quantity / closing. Value uses the average cost now.',
    'প্রতিটি দিনের শেষের স্টক (খাতা দিন ধরে), পাশে পরের দিন কত বিক্রি ও কত নষ্ট হয়েছে। আজকের পরের দিন এখনও আসেনি, তাই সেই ঘর ফাঁকা (এখনও নেই), ০ নয়। % = পরের দিনের পরিমাণ / শেষের স্টক। মূল্য এখনকার গড় খরচে।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' <> 'closing_value' then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('daily_closing', 'S8', 'stock', 'দিনের শেষের স্টক বনাম পরের দিনের বিক্রি ও ক্ষতি', 'Closing stock vs next-day sales and loss', 'দিনের শেষের Stock বনাম পরের দিনের বিক্রি ও ক্ষতি',
  '[["day","দিন","Day","date"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"],["closing_qty","দিনের শেষে স্টক","Closing stock","num"],["received_qty","সেদিন পাওয়া","Received that day","num"],["next_sales_qty","পরের দিন বিক্রি","Next-day sales","num"],["next_loss_qty","পরের দিন নষ্ট","Next-day loss","num"],["sales_pct","বিক্রি % (শেষের স্টকের)","Sales % of closing","pct"],["loss_pct","নষ্ট % (শেষের স্টকের)","Loss % of closing","pct"],["closing_value","শেষের স্টকের মূল্য","Closing value","money"]]'::jsonb,
  '{}', 'day', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4208)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- #73 turnover and days on hand ----------
create or replace function public._r3q_item_turnover(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select (d2 - d1 + 1) as days, public.rpt_cost_ok() as cost, public.rpt_arr_text(flt -> 'categories') as cat, public._r4_types(flt) as ty),
  cd as (select * from public._r4_closing_daily(d1, d2, locs, (select ty from p), (select cat from p))),
  perday as (select item_id, day, sum(closing) as q from cd where day between d1 and d2 group by 1, 2),
  av as (select item_id, avg(q) as avg_q from perday group by 1),
  used as (select cd.item_id, sum(cd.sales_net) filter (where cd.day between d1 and d2) as sold from cd group by 1),
  iss as (select l.item_id, coalesce(-sum(l.qty_delta), 0) as q from public.stock_ledger l where l.reason = 'issue_out' and l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1),
  now_ as (select b.item_id, sum(b.qty) as q, sum(b.qty * b.avg_cost) filter (where b.avg_cost is not null) as v, count(*) filter (where b.qty <> 0 and b.avg_cost is null) as unc from public.stock_balance b where b.location_id = any (locs) group by 1)
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'item_name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'item_type', coalesce(t.label_bn, it.item_type),
      'sold_qty', round(coalesce(u.sold, 0), 4), 'issued_qty', round(coalesce(i.q, 0), 4), 'used_qty', round(coalesce(u.sold, 0) + coalesce(i.q, 0), 4), 'avg_stock_qty', round(a.avg_q, 4), 'on_hand_qty', round(coalesce(n.q, 0), 4),
      'turnover', case when a.avg_q > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round((coalesce(u.sold, 0) + coalesce(i.q, 0)) / a.avg_q, 3) end,
      'days_on_hand', case when a.avg_q > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round(a.avg_q * p.days / (coalesce(u.sold, 0) + coalesce(i.q, 0)), 1) end,
      'cover_days_now', case when coalesce(n.q, 0) > 0 and coalesce(u.sold, 0) + coalesce(i.q, 0) > 0 then round(n.q * p.days / (coalesce(u.sold, 0) + coalesce(i.q, 0)), 1) end,
      'value_on_hand', case when p.cost then round(n.v, 2) end, 'uncosted_places', case when p.cost then coalesce(n.unc, 0) end,
      '_nc', (select coalesce(jsonb_agg(z), '[]'::jsonb) from unnest(array[case when a.avg_q <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'turnover' end, case when a.avg_q <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'days_on_hand' end,
               case when coalesce(n.q, 0) <= 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <= 0 then 'cover_days_now' end]) z where z is not null),
      'drill', format('#/stockrep/recon?from=%s&to=%s', d1, d2))
    from av a join public.items it on it.id = a.item_id cross join p left join public.item_types t on t.code = it.item_type left join used u on u.item_id = a.item_id left join iss i on i.item_id = a.item_id left join now_ n on n.item_id = a.item_id
   where a.avg_q <> 0 or coalesce(u.sold, 0) + coalesce(i.q, 0) <> 0;
$$;

create or replace function public._r4d_item_turnover(p_flt jsonb, p_res jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := p_res; cost_ok boolean := public.rpt_cost_ok(); col jsonb; cols jsonb := '[]'::jsonb;
begin
  res := public._r4_addnote(res, public._r4_note('info', 'Used = sold (net of voids and refunds) + issued to production, in the item''s base unit. Average stock = the mean of the book closing stock of every day of the period (all chosen places together). Turnover = used / average stock. Days on hand = average stock x days of the period / used. Where nothing was used, or the average stock is not above 0, these are empty (they cannot be worked out), never 0 and never an estimate. Wastage and transfers are not "used".',
    'ব্যবহার = বিক্রি (বাতিল ও ফেরত বাদে) + উৎপাদনে ইস্যু, আইটেমের নিজের এককে। গড় স্টক = সময়ের প্রতিদিনের বইয়ের শেষ স্টকের গড় (বাছা সব জায়গা মিলিয়ে)। টার্নওভার = ব্যবহার / গড় স্টক। দিন হাতে = গড় স্টক × সময়ের দিন / ব্যবহার। কিছু ব্যবহার না হলে বা গড় স্টক ০-র বেশি না হলে ঘর ফাঁকা (হিসাব করা যায় না), ০ বা আন্দাজ নয়। নষ্ট ও ট্রান্সফার "ব্যবহার" নয়।'));
  if not cost_ok then
    for col in select * from jsonb_array_elements(res -> 'columns') loop if col ->> 'key' not in ('value_on_hand', 'uncosted_places') then cols := cols || jsonb_build_array(col); end if; end loop;
    res := jsonb_set(res, '{columns}', cols); res := public._r4_addnote(res, jsonb_build_object('code', 'cost_hidden'));
  end if;
  return res;
end $$;

insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('item_turnover', 'S9', 'stock', 'স্টক টার্নওভার ও কত দিনের মাল হাতে', 'Stock turnover and days on hand', 'Stock turnover ও কত দিনের মাল হাতে',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["item_type","ধরন","Type","text"],["unit","একক","Unit","text"],["sold_qty","বিক্রি (নিট)","Sold (net)","num"],["issued_qty","উৎপাদনে ইস্যু","Issued to production","num"],["used_qty","ব্যবহার","Used","num"],["avg_stock_qty","গড় স্টক","Average stock","num"],["turnover","টার্নওভার","Turnover","num"],["days_on_hand","কত দিনের মাল","Days on hand","num"],["on_hand_qty","এখন হাতে","On hand now","num"],["cover_days_now","এখনকার মাল কত দিনের","Days of cover now","num"],["value_on_hand","এখনকার মূল্য (খরচ জানা অংশ)","Value now (costed part)","money"],["uncosted_places","খরচ অজানা লাইন","Lines with no cost","int"]]'::jsonb,
  '{}', 'turnover', 'desc', array['locations','brands','categories','item_types'], false, false, false, 4209)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
select public._r4_lockdown();
notify pgrst, 'reload schema';

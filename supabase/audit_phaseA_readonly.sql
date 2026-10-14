-- ধাপ A: শুধু-পড়া (SELECT) পরীক্ষা। কিছু লেখে না, বদলায় না। Supabase SQL Editor-এ পুরোটা Paste করে Run দিন।
-- ফল একটি ছকে আসবে (sec / label / val)। ছকটির ছবি বা কপি পাঠান।
with cfg as (select nullif(coalesce(value, default_value) #>> '{}', '')::date as st from rules where key = 'accounting_start_date'),
neg as (select i.code || ' @লোকেশন ' || b.location_id as label, b.qty::text as val from stock_balance b join items i on i.id = b.item_id where b.qty < 0 order by b.qty limit 40),
unitbad as (select i.code as label, coalesce(i.unit, '-') || ' ≠ ' || coalesce(i.base_unit, '-') as val from items i
  where i.tracked and nullif(i.unit, '') is not null and i.unit is distinct from i.base_unit
    and not exists (select 1 from unit_conversions c where c.active and (c.item_id = i.id or c.item_id is null)
      and ((c.from_unit = i.unit and c.to_unit = i.base_unit) or (c.from_unit = i.base_unit and c.to_unit = i.unit))) order by i.code limit 40),
nocost as (select i.code as label, 'বইয়ের খরচ ' || coalesce(ic.cost_price::text, 'নেই') || ' · স্টক ' || sum(b.qty)::text || ' · গড় ' || coalesce(max(b.avg_cost)::text, 'নেই') as val
  from items i left join item_costs ic on ic.item_id = i.id left join stock_balance b on b.item_id = i.id
  where i.tracked group by i.code, ic.cost_price having coalesce(ic.cost_price, 0) = 0 or (sum(b.qty) > 0 and coalesce(max(b.avg_cost), 0) = 0) order by 1 limit 40),
mon as (select date_trunc('month', s.sale_date)::date as m, sum(s.subtotal) as rev,
    sum((select coalesce(sum((l ->> 'qty')::numeric * coalesce(ic.cost_price, 0)), 0) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) l
        left join item_costs ic on ic.item_id = case when l ->> 'item_id' ~ '^[0-9a-f-]{36}$' then (l ->> 'item_id')::uuid end where l ->> 'qty' ~ '^[0-9.]+$')) as rep_cogs
  from sales s where s.status = 'done' and s.sale_date >= (current_date - interval '3 months') group by 1),
jc as (select date_trunc('month', je.entry_date)::date as m, sum(jl.debit - jl.credit) as cogs from journal_entries je join journal_lines jl on jl.entry_id = je.id
  join acct_mappings am on am.account_id = jl.account_id and am.key = 'cogs' where je.entry_date >= (current_date - interval '3 months') group by 1),
glv as (select ca.code, sum(jl.debit - jl.credit) as gl from journal_lines jl join coa_accounts ca on ca.id = jl.account_id where ca.code in ('1310', '1320', '1330') group by ca.code),
val as (select ca.code, sum(b.qty * coalesce(b.avg_cost, 0)) as v from stock_balance b join items i on i.id = b.item_id
  join acct_mappings am on am.key = _acct_inv_key(i.item_type) join coa_accounts ca on ca.id = am.account_id group by ca.code),
want(k) as (values ('grn_receipt_source'), ('production_requires_recipe'), ('stock_negative_mode'), ('packaging_consume_on'), ('block_expired_sale'), ('costing_method'), ('em_sell_below_zero'),
  ('accounting_on'), ('accounting_autopost'), ('accounting_start_date')),
out as (
  select 10 as o, '১ মাইনাস স্টক' as sec, 'মোট আইটেম-লোকেশন' as label, (select count(*)::text from stock_balance where qty < 0) as val
  union all select 11, '১ মাইনাস স্টক', label, val from neg
  union all select 20, '২ ইউনিট ≠ বেস ইউনিট, রূপান্তর নেই (tracked)', 'মোট', (select count(*)::text from items i where i.tracked and nullif(i.unit, '') is not null and i.unit is distinct from i.base_unit
      and not exists (select 1 from unit_conversions c where c.active and (c.item_id = i.id or c.item_id is null) and ((c.from_unit = i.unit and c.to_unit = i.base_unit) or (c.from_unit = i.base_unit and c.to_unit = i.unit))))
  union all select 21, '২ ইউনিট ≠ বেস ইউনিট, রূপান্তর নেই (tracked)', label, val from unitbad
  union all select 30, '৩ খরচহীন বা শূন্য-খরচ আইটেম (tracked)', 'মোট tracked আইটেম', (select count(*)::text from items where tracked)
  union all select 31, '৩ খরচহীন বা শূন্য-খরচ আইটেম (tracked)', label, val from nocost
  union all select 40, '৪ খরচ-অজানা (cogs_missing / cost_complete=false)', 'বিক্রির লেজার সারি যার খরচ নেই', (select count(*)::text from stock_ledger where reason = 'sale_out' and unit_cost is null)
  union all select 41, '৪ খরচ-অজানা (cogs_missing / cost_complete=false)', 'প্রোডাকশন রান (done) খরচ অসম্পূর্ণ', (select count(*)::text from production_runs where status = 'done' and cost_complete is not true)
  union all select 42, '৪ খরচ-অজানা (cogs_missing / cost_complete=false)', 'জার্নাল এন্ট্রি cogs_missing চিহ্নিত', (select count(*)::text from journal_entries where flags like '%cogs_missing%')
  union all select 43, '৪ খরচ-অজানা (cogs_missing / cost_complete=false)', 'প্রোডাকশন রান মোট (done)', (select count(*)::text from production_runs where status = 'done')
  union all select 50, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'হিসাব শুরুর তারিখ', coalesce((select st::text from cfg), 'নেই — হিসাব চালু হয়নি')
  union all select 51, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'বিক্রি (done) জার্নালে নেই', (select count(*)::text from sales s, cfg where cfg.st is not null and s.status = 'done' and s.subtotal > 0 and s.sale_date >= cfg.st
      and not exists (select 1 from journal_entries j where j.source_type = 'sale' and j.source_id = s.id::text and j.reverses_id is null))
  union all select 52, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'প্রোডাকশন (done) জার্নালে নেই', (select count(*)::text from production_runs r, cfg where cfg.st is not null and r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date >= cfg.st
      and not exists (select 1 from journal_entries j where j.source_type = 'production' and j.source_id = r.id::text and j.reverses_id is null))
  union all select 53, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'ক্রয় বিল (posted) জার্নালে নেই', (select count(*)::text from purchase_bills b, cfg where cfg.st is not null and b.status = 'posted' and b.total > 0 and b.bill_date >= cfg.st
      and not exists (select 1 from journal_entries j where j.source_type = 'purchase' and j.source_id = b.id::text and j.reverses_id is null))
  union all select 54, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'ক্যাশ মুভ (done) জার্নালে নেই', (select count(*)::text from cash_moves m, cfg where cfg.st is not null and m.status = 'done' and m.move_date >= cfg.st
      and not exists (select 1 from journal_entries j where j.source_type = 'cash_move' and j.source_id = m.id::text and j.reverses_id is null))
  union all select 55, '৫ অপেক্ষমাণ পোস্টিং (আনুমানিক; locked/errors SELECT-এ জানা যায় না: যাচাই হয়নি)', 'সর্বশেষ জার্নাল পোস্ট (স্বয়ংক্রিয় উৎস)', coalesce((select max(created_at)::text from journal_entries where created_by is not null and source_type not in ('manual', 'opening')), 'কখনো নয়')
  union all select 60, '৬ সুইচের বর্তমান মান (নেই = এই কী ডাটাবেসে নেই)', w.k, coalesce((select coalesce(r.value, r.default_value)::text || case when r.value is null then ' (ডিফল্ট)' else ' (বদলানো)' end from rules r where r.key = w.k), 'নেই') from want w
  union all select 70, '৭ ইনভেন্টরি: জার্নাল (GL) বনাম স্টক-মূল্য (গড় খরচে)', a.code || ' GL ' || coalesce(g.gl, 0)::text, 'স্টক-মূল্য ' || coalesce(v.v, 0)::text || ' · ফারাক ' || (coalesce(g.gl, 0) - coalesce(v.v, 0))::text
    from (values ('1310'), ('1320'), ('1330')) a(code) left join glv g on g.code = a.code left join val v on v.code = a.code
  union all select 80, '৮ রিপোর্টের খরচ বনাম জার্নালের খরচ (গত ৩ মাস)', coalesce(mon.m::text, jc.m::text),
      'আয় ' || coalesce(mon.rev, 0)::text || ' · রিপোর্টের COGS (বইয়ের খরচ) ' || round(coalesce(mon.rep_cogs, 0), 2)::text || ' · জার্নালের COGS ' || round(coalesce(jc.cogs, 0), 2)::text || ' · ফারাক ' || round(coalesce(jc.cogs, 0) - coalesce(mon.rep_cogs, 0), 2)::text
    from mon full join jc on jc.m = mon.m
  union all select 90, '৯ রেসিপি', 'রেসিপি (সক্রিয়)', (select count(*)::text from recipes where active)
  union all select 91, '৯ রেসিপি', 'কারিগর বা প্রসেস-ধাপের কলাম/টেবিল আছে কি', case when exists (select 1 from information_schema.columns where table_name = 'recipes' and column_name ~ 'artisan')
      or to_regclass('public.recipe_steps') is not null or to_regclass('public.artisans') is not null then 'আছে' else 'নেই — সব সক্রিয় রেসিপিতেই কারিগর/ধাপের তথ্য নেই' end
  union all select 100, '১০ অনলাইন অর্ডার', 'টেবিলের কলাম', (select string_agg(column_name, ', ' order by ordinal_position) from information_schema.columns where table_name = 'online_orders' and table_schema = 'public')
  union all select 101, '১০ অনলাইন অর্ডার', 'মোট অর্ডার', (select count(*)::text from online_orders)
  union all select 102, '১০ অনলাইন অর্ডার', 'অবস্থা অনুযায়ী: ' || s.status, s.n::text from (select status, count(*) n from online_orders group by status) s
  union all select 103, '১০ অনলাইন অর্ডার', 'চ্যানেল অনুযায়ী: ' || s.channel, s.n::text from (select channel, count(*) n from online_orders group by channel) s
  union all select 104, '১০ অনলাইন অর্ডার', 'চ্যানেল / ইনবক্স / webhook নামের টেবিল', coalesce((select string_agg(table_name, ', ') from information_schema.tables where table_schema = 'public' and table_name ~ 'channel|inbound|webhook|inbox'), 'নেই')
  union all select 105, '১০ অনলাইন অর্ডার', 'online_order নামের ফাংশন', (select string_agg(distinct proname, ', ') from pg_proc where pronamespace = 'public'::regnamespace and proname like 'online_order%')
  union all select 106, '১০ অনলাইন অর্ডার', 'কে দেখতে পায় (RLS নীতি)', coalesce((select string_agg(polname || ': ' || coalesce(pg_get_expr(polqual, polrelid), '-'), ' | ') from pg_policy where polrelid = 'public.online_orders'::regclass), 'নীতি নেই')
  union all select 107, '১০ অনলাইন অর্ডার', 'বাইরে থেকে নিজে-ঢোকার পথ (ফেসবুক/ইনস্টা/ওয়েব ফর্ম)', 'ডাটাবেসে কোনো চ্যানেল/ইনবক্স/webhook টেবিল না থাকলে = নেই (ওপরের লাইন ১০৪ দেখুন); edge function ডাটাবেস থেকে জানা যায় না: যাচাই হয়নি'
)
select sec, label, val from out order by o, label;

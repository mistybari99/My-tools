-- READ-ONLY combined check for phases 103-111 (Runs 11-14). Writes nothing.
select * from (
with fn as (select p.proname::text as proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
tb as (select table_name::text as t from information_schema.tables where table_schema = 'public'),
rl as (select r.key::text as k from public.rules r),
cd as (select d.code::text as c from public.setup_check_defs81 d),
gd as (select g.grant_code::text as c from public.grant_defs g),
want(phase, kind, name, marker) as (values
  (103, 't', 'opening_stock_followups103', null),
  (103, 'r', 'acct_manual_prod_in103', null),
  (103, 'c', 'flw_grn_double103', null),
  (103, 'g', 'view_customer_mobile', null),
  (103, 's', 'recipe_cost', 'bos103'),
  (103, 's', '_acct_docs', 'bos103')),
chk as (select w.phase, w.name, w.marker,
  case w.kind
    when 't' then exists (select 1 from tb where tb.t = w.name)
    when 'r' then exists (select 1 from rl where rl.k = w.name)
    when 'c' then exists (select 1 from cd where cd.c = w.name)
    when 'g' then exists (select 1 from gd where gd.c = w.name)
    else exists (select 1 from fn where fn.proname = w.name and strpos(fn.prosrc, w.marker) > 0) end as ok
  from want w)
select 'Phase ' || phase as phase,
  case when bool_and(ok) then '✅ done' else '❌ missing' end as status,
  count(*) filter (where ok) || '/' || count(*) as found,
  coalesce(string_agg(name || coalesce(' [' || marker || ']', ''), ', ') filter (where not ok), '') as missing
from chk group by chk.phase order by chk.phase
) c11
union all
select * from (
with fn as (select p.proname::text as proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
tb as (select table_name::text as t from information_schema.tables where table_schema = 'public'),
rl as (select r.key::text as k from public.rules r),
rl2 as (select r.key::text as k, r.label_bn::text as lb from public.rules r),
rd as (select d.code::text as c from public.setup_rec_defs81 d),
want(phase, kind, name, marker) as (values
  (104, 't', 'dash_layouts', null), (104, 'f', 'dash_layout_save', null), (104, 'f', 'dash_layout_get', null),
  (105, 'r', 'customers_pii_guard_on', null), (105, 't', 'bos_salt105', null), (105, 'f', '_bp_auto_ok105', null), (105, 's', 'customer_profile', 'bos105'),
  (106, 'f', 'backup_coverage106', null), (106, 'f', '_backup_tables', null),
  (107, 't', 'client_errors', null), (107, 'f', 'client_error_log', null), (107, 'f', 'client_errors_list', null), (107, 'r', 'client_errors_on', null),
  (108, 'l', 'production_requires_cost', 'উৎপাদনে কোনো উপকরণের খরচ অজানা (ফাঁকা বা ০) থাকলে: সতর্কতা / আটকানো'),
  (108, 'l', 'recipe_approval_required', 'রেসিপি অনুমোদনের আগে খরচ/উৎপাদন: বন্ধ / হলুদ সতর্কতা / আটকানো'),
  (108, 'l', 'recipe_self_approve', 'যে রেসিপি বদলেছে সে-ই অনুমোদন করতে পারবে'),
  (108, 'l', 'cost_gap_warn_pct', '"আজকের কেনা দাম" ও গড় দামের ফারাক % — এর বেশি হলে হলুদ সতর্কতা'),
  (108, 'l', 'production_manual_needs_reason', 'সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) বাধ্যতামূলক'),
  (108, 'l', 'cost_rule_self_approve', 'যে ভাগের নিয়ম লিখেছে সে-ই অনুমোদন করতে পারবে')),
chk as (select w.phase, w.name, w.marker,
  case w.kind
    when 'f' then exists (select 1 from fn where fn.proname = w.name)
    when 't' then exists (select 1 from tb where tb.t = w.name)
    when 'r' then exists (select 1 from rl where rl.k = w.name)
    when 'd' then exists (select 1 from rd where rd.c = w.name)
    when 'l' then exists (select 1 from rl2 where rl2.k = w.name and rl2.lb is distinct from w.marker)
    else exists (select 1 from fn where fn.proname = w.name and strpos(fn.prosrc, w.marker) > 0) end as ok
  from want w)
select 'Phase ' || phase as phase,
  case when bool_and(ok) then '✅ done' else '❌ missing' end as status,
  count(*) filter (where ok) || '/' || count(*) as found,
  coalesce(string_agg(name || coalesce(' [' || case when length(marker) > 20 then left(marker, 20) || '...' else marker end || ']', ''), ', ') filter (where not ok), '') as missing
from chk group by chk.phase order by chk.phase
) c12
union all
select * from (
with fn as (select p.proname::text as proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
tb as (select table_name::text as t from information_schema.tables where table_schema = 'public'),
rl as (select r.key::text as k from public.rules r),
rl2 as (select r.key::text as k, r.label_bn::text as lb from public.rules r),
rd as (select d.code::text as c from public.setup_rec_defs81 d),
want(phase, kind, name, marker) as (values
  (109, 'r', 'card_settle_over_mode', null), (109, 'd', 'card_settle_over_mode', null), (109, 's', 'production_post', 'bos109'), (109, 's', 'card_settle', 'bos109'),
  (111, 's', '_bp_pay99', 'bos105'), (111, 's', '_bp_pay99', 'bos109'), (111, 's', '_bp_pay99', 'bos111')),
chk as (select w.phase, w.name, w.marker,
  case w.kind
    when 'f' then exists (select 1 from fn where fn.proname = w.name)
    when 't' then exists (select 1 from tb where tb.t = w.name)
    when 'r' then exists (select 1 from rl where rl.k = w.name)
    when 'd' then exists (select 1 from rd where rd.c = w.name)
    when 'l' then exists (select 1 from rl2 where rl2.k = w.name and rl2.lb is distinct from w.marker)
    else exists (select 1 from fn where fn.proname = w.name and strpos(fn.prosrc, w.marker) > 0) end as ok
  from want w)
select 'Phase ' || phase as phase,
  case when bool_and(ok) then '✅ done' else '❌ missing' end as status,
  count(*) filter (where ok) || '/' || count(*) as found,
  coalesce(string_agg(name || coalesce(' [' || case when length(marker) > 20 then left(marker, 20) || '...' else marker end || ']', ''), ', ') filter (where not ok), '') as missing
from chk group by chk.phase order by chk.phase
) c13
union all
select * from (
with ix as (select i.indexname::text as n from pg_indexes i where i.schemaname = 'public'),
fn as (select p.proname::text as proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
want(phase, kind, name, marker) as (values
  (110, 'i', 'stock_ledger_refid_idx', null), (110, 'i', 'stock_ledger_item_loc_reason_idx', null), (110, 'i', 'production_runs_idtext_idx', null), (110, 'i', 'purchase_bills_idtext_idx', null),
  (110, 'i', 'stock_ledger_reason_made_idx', null), (110, 'i', 'stock_ledger_lastcost_idx', null), (110, 'i', 'audit_log_tbl_rec_id_idx', null), (110, 'i', 'audit_log_view_at_idx', null),
  (110, 's', '_cogs_lines72', 'bos110'), (110, 's', '_item_cost_eff88', 'bos110'), (110, 's', '_rcs88', 'bos110'), (110, 's', 'rpt_agg_sql', 'bos110'),
  (110, 's', 'inbox_list', 'perf110'), (110, 's', '_acct_stock_moves85', 'perf110')),
chk as (select w.phase, w.name, w.marker,
  case w.kind
    when 'i' then exists (select 1 from ix where ix.n = w.name)
    else exists (select 1 from fn where fn.proname = w.name and strpos(fn.prosrc, w.marker) > 0) end as ok
  from want w)
select 'Phase ' || phase as phase,
  case when bool_and(ok) then '✅ done' else '❌ missing' end as status,
  count(*) filter (where ok) || '/' || count(*) as found,
  coalesce(string_agg(name || coalesce(' [' || marker || ']', ''), ', ') filter (where not ok), '') as missing
from chk group by chk.phase order by chk.phase
) c14;

-- READ-ONLY CHECK for phases 112..121 (Run 15). One SELECT: it writes, changes and deletes nothing.
-- Paste in Supabase SQL editor -> Run once. Result: one row per phase (112..118, 121) with a tick or a cross; "missing" lists what is not there yet.
-- Phase 119 and 120 do not exist as SQL files in this batch (no row). All new rules are OFF by default: a tick here does not change anything you see in the app.
with fn as (select p.proname::text as proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
tb as (select table_name::text as t from information_schema.tables where table_schema = 'public'),
rl as (select r.key::text as k from public.rules r),
want(phase, kind, name, marker) as (values
  (112, 'r', 'profit_truth_mode', null), (112, 'r', 'cost_share_prorate_mode', null), (112, 'r', 'items_net_of_returns', null),
  (112, 's', '_c78_rows112', 'bos112'), (112, 's', '_c78_rows', 'bos112'), (112, 's', '_pl_extra112', 'bos112'),
  (112, 's', '_pnl_truth112', 'bos112'), (112, 's', '_r3q_l3_shop_pnl', 'bos112'), (112, 's', 'profit_truth112', 'bos112'),
  (112, 's', 'biz_items', 'bos112'), (113, 'r', 'drawer_short_post', null), (113, 'r', 'dues_net_advance', null),
  (113, 'r', 'period_lock_owner_mode', null), (113, 'r', 'period_lock_late_warn', null), (113, 'r', 'daybook_align_mode', null),
  (113, 'r', 'bank_stmt_post_on', null), (113, 's', '_acct_docs', 'bos113'), (113, 's', 'acct_post_pending', 'bos113'),
  (113, 's', '_daybook_lines', 'bos113'), (113, 's', 'customer_dues_net113', 'bos113'), (113, 's', 'collect_payment', 'bos113'),
  (113, 's', 'lock_check', 'bos113'), (113, 's', 'bank_stmt_post113', 'bos113'), (114, 'r', 'late_sale_follows_block', null),
  (114, 'r', 'transfer_needs_stock', null), (114, 'r', 'return_uses_sale_rows', null), (114, 'r', 'item_unit_change_needs_zero', null),
  (114, 'r', 'item_lifecycle_needs_zero', null), (114, 'r', 'batch_for_adjustments', null), (114, 'r', 'batch_refill_cap', null),
  (114, 's', '_adj_batch114', 'bos114'), (114, 's', '_stock_batch_refill114', 'bos114'), (114, 's', '_items_stock_guard114', 'bos114'),
  (114, 'f', 'stock_batch_reconcile', null), (115, 'r', 'transfer_late_receive', null), (115, 'r', 'transfer_return_marker', null),
  (115, 'r', 'transfer_notify_receiver', null), (115, 'r', 'transit_loss_gl_fix', null), (115, 'f', 'stock_receive_more', null),
  (115, 'f', 'stock_return_transfer', null), (116, 'r', 'semi_finished_ingredient116', null), (116, 'r', 'packaging_on_actual_yield116', null),
  (116, 'r', 'std_snapshot_auto116', null), (116, 'r', 'std_cost_true116', null), (116, 'r', 'pool_drivers116', null),
  (116, 'r', 'conv_provisional116', null), (116, 'r', 'cost_supply_to_avg116', null), (116, 't', 'recipe_std116', null),
  (116, 't', 'production_reprice116', null), (116, 'f', '_recipe_reaches116', null), (116, 's', '_recipe_lines_ok', 'bos116'),
  (116, 's', '_recipe_need116', 'bos116'), (116, 's', '_recipe_need', 'bos116'), (116, 'f', '_pool_rate_prov116', null),
  (116, 's', '_conv_cost', 'bos116'), (116, 's', 'production_post', 'bos116'), (116, 's', 'production_run_costs', 'bos116'),
  (116, 's', 'production_void', 'bos116'), (116, 's', 'cost_wait_supply96', 'bos116'), (116, 'f', '_recipe_std_snap116', null),
  (116, 'f', 'recipe_std_set116', null), (116, 'f', 'production_variance116', null), (116, 'f', 'loc_cost_driver_set116', null),
  (116, 'f', 'cost_type_driver_set116', null), (116, 'f', '_cw_apply_avg116', null), (116, 'f', '_cw_run_recost116', null),
  (116, 'f', 'production_cost_queue116', null), (116, 'f', 'production_reprice116', null), (116, 'f', 'recipe_stage_cost116', null),
  (116, 'f', 'production_recost116', null), (117, 'r', 'pool_gl_post117', null), (117, 'r', 'factory_labour_absorbed117', null),
  (117, 't', 'pool_gl_posts117', null), (117, 's', 'pool_set', 'bos117'), (117, 's', '_cs_push_pools', 'bos117'),
  (117, 's', '_p27_pl', 'bos117'), (117, 'f', '_pool_gl_sync117', null), (117, 'f', 'pool_gl_sync117', null),
  (117, 'f', '_pool_gl_after_bill117', null), (117, 'f', 'cost_type_gl_set117', null), (117, 'f', 'pool_vs_gl117', null),
  (117, 'f', 'overhead_trueup117', null), (118, 'r', 'profit_variable_heads', null), (118, 'r', 'branch_stmt_ageing_hours', null),
  (118, 's', '_rc118_locs', 'bos118'), (118, 's', '_rc118_buckets', 'bos118'), (118, 's', '_rc118_gap', 'bos118'),
  (118, 'f', '_rc118_gap_summary', null), (118, 's', 'stock_recon_statement', 'bos118'), (118, 's', 'stock_sales_unmatched', 'bos118'),
  (118, 's', 'factory_branch_statement', 'bos118'), (118, 's', 'net_profit_report', 'bos118'), (118, 'f', 'recon_export_log118', null),
  (121, 's', '_pool_gl_after_bill117', 'sec121'), (121, 's', 'bank_stmt_post113', 'sec121'), (121, 's', 'cost_wait_supply96', 'sec121'),
  (121, 's', 'pool_set', 'sec121'), (121, 's', 'production_recost116', 'sec121'), (121, 's', 'sale_return', 'sec121'),
  (121, 's', 'stock_return_transfer', 'sec121')),
chk as (select w.phase, w.name, w.marker,
  case w.kind
    when 'r' then exists (select 1 from rl where rl.k = w.name)
    when 't' then exists (select 1 from tb where tb.t = w.name)
    when 'f' then exists (select 1 from fn where fn.proname = w.name)
    else exists (select 1 from fn where fn.proname = w.name and strpos(fn.prosrc, w.marker) > 0) end as ok
  from want w)
select 'Phase ' || phase as phase,
  case when bool_and(ok) then '✅ done' else '❌ missing' end as status,
  count(*) filter (where ok) || '/' || count(*) as found,
  coalesce(string_agg(name || coalesce(' [' || marker || ']', ''), ', ') filter (where not ok), '') as missing
from chk group by chk.phase order by chk.phase;

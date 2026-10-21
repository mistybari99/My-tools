-- PERF indexes (additive, paste-twice safe, no CONCURRENTLY, fine inside the Supabase SQL-editor transaction).
-- Each CREATE INDEX takes a SHARE lock on its table while it builds (reads work, writes wait): paste at a quiet time.
-- On the 184k-row scratch ledger every build took under 0.5 s; expect roughly 1-2 s per million rows.
set local lock_timeout = '10s';   -- give up instead of queueing behind a long writer; paste again later

-- 1. _cogs_lines72 (biz_daily, _p27_pl, biz_items) joins stock_ledger on ref_id alone (the ref_type test depends on the outer row, so the existing (ref_type, ref_id) index cannot be used for it)
create index if not exists stock_ledger_refid_idx on public.stock_ledger (ref_id, ref_type);

-- 2. unmatched_forms: "is there a ledger row for this item + place + reason" per form line (the existing (item_id, location_id, id) index walks every row of a big item)
create index if not exists stock_ledger_item_loc_reason_idx on public.stock_ledger (item_id, location_id, reason, made_at);

-- 3. inventory_vs_gl compares production_runs.id::text / purchase_bills.id::text with stock_ledger.ref_id (text) for every ledger row: expression indexes make that a lookup instead of a table scan
create index if not exists production_runs_idtext_idx on public.production_runs ((id::text));
create index if not exists purchase_bills_idtext_idx on public.purchase_bills ((id::text));

-- 4. items_with_cost / _item_cost_eff88 take the last positive-cost ledger row of every item (order by id desc limit 1): a partial index makes each lookup one probe
create index if not exists stock_ledger_lastcost_idx on public.stock_ledger (item_id, id desc) where coalesce(unit_cost, 0) > 0 and qty_delta > 0;

-- 5. audit_log has only its primary key: the item-history popup (table_name + record_id, newest first) and pii_exposure_report94 (action = 'view') scan the whole table
create index if not exists audit_log_tbl_rec_id_idx on public.audit_log (table_name, record_id, id desc);
create index if not exists audit_log_view_at_idx on public.audit_log (table_name, at) where action = 'view';

-- 6. (preventive) urgent_alerts reads the "bad, not yet e-mailed, owner" notifications of the last 2 days: with 300k notification rows it takes 82 ms by seq scan, 3 ms with this partial index (today's volume does not need it)
create index if not exists notifications_urgent_idx on public.notifications (created_at) where level = 'bad' and emailed_at is null and user_id is null;

analyze public.stock_ledger;
analyze public.production_runs;
analyze public.purchase_bills;
analyze public.audit_log;
analyze public.notifications;

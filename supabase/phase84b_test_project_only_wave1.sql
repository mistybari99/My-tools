-- Phase 84b - GUARDED TEST-PROJECT RESET, WAVE 1 TABLES. TEST PROJECTS ONLY. NEVER PASTE THIS FILE INTO THE LIVE PROJECT.
-- It is NOT part of the owner paste order (tests/sql/ORDER.txt never lists it) and it is not a numbered build phase: it belongs to phase84_test_project_only.sql.
-- Paste order in a TEST project: ... phase84.sql ... phase99.sql (and 140 to 143) first, then phase84_test_project_only.sql, then THIS file. Paste-twice safe.
-- If phase84_test_project_only.sql is pasted again later, paste this file again afterwards (the old file puts the old lists back).
--
-- WHY: phase84_test_project_only.sql has two lists, the tables a test reset clears (_e_reset_tables) and the tables it must never touch (_e_reset_protected).
-- It was written before phase 87 and Wave 1 (phases 88 to 99). On a database that has them it REFUSES to run
-- ("tables outside the clear list point at cleared tables: entry_approvers -> entries, w1c_returns -> sale_returns, w1c_returns -> sales"), and the Wave 1
-- tables that hold records (returns, held late sales, other income, requests, ...) were in neither list. This file replaces the two functions with the old
-- lists PLUS the tables below. The reset itself (_e_test_reset), its three checks (owner, rule allow_test_reset ON, phrase DELETE ALL TEST DATA), the
-- one-reset-per-switch behaviour and the reset log are NOT changed. The old file is not edited. Nothing here runs a reset.
--
-- ADDED TO THE CLEAR LIST (records made by the daily work; the rows are test records)
--   phase 87: entry_approvers (chosen approver of an entry), money_transfers, money_charges, money_checks, money_exceptions, money_exception_grants
--   Wave 1:   w1c_returns, w1c_return_lines (return disposition), late_sales_held, open_party_adjustments, other_income, period_overrides,
--             profit_row_exclusions (owner decisions about single rows that no longer exist), w1e_requests, w1g_post_runs, w1g_post_watermark (posting progress of a journal that is cleared)
-- ADDED TO THE PROTECTED LIST (setup, people, owner choices, history of settings; a reset never touches them)
--   phase 87: money_accounts, money_recurring, money_event_settings
--   Wave 1:   w1c_return_class_rules, w1c_exit_keep, w1c_exit_log (staff are protected, so is their exit history), w1e_mapping_types, w1f_seed_state,
--             w1g_sched_state, w1g_switch_acks, report_brand_map, report_brand_map_hist
-- A table that is on both lists stops the reset (checked by the old function). Tables that exist in neither list are simply left alone, as before.

do $g$ begin
  if to_regprocedure('public._e_test_reset(text)') is null or to_regprocedure('public._e_reset_tables()') is null or to_regprocedure('public._e_reset_protected()') is null then
    raise exception 'phase84b needs phase84_test_project_only.sql pasted first (test projects only)';
  end if;
end $g$;

-- Transactional tables a test reset may clear (only those that exist are used). Old list of phase84_test_project_only.sql (+ phases 80-83) plus the tables above.
create or replace function public._e_reset_tables() returns text[] language sql immutable as $$
  select array[
    'journal_lines', 'journal_entries', 'acct_post_errors72', 'year_closes',
    'stock_ledger', 'stock_balance', 'stock_batches', 'stock_wastage', 'stock_transfers', 'wastage_requests', 'grn_batch_links', 'qc_records', 'production_runs',
    'sales', 'sale_payments', 'sale_returns', 'sale_tier_use', 'sale_form_links',
    'purchase_bills', 'purchase_lines', 'supplier_payments', 'supplier_refunds',
    'cash_moves', 'quick_expenses',
    'payroll_runs', 'payroll_lines', 'payroll_payments', 'payroll_bonus_events', 'employee_advances', 'employee_advance_recoveries',
    'attendance_punches', 'attendance_days',
    'entries', 'entry_change_requests', 'entry_revisions', 'entry_signatures', 'entry_counts', 'entry_count_seals', 'entry_count_peeks', 'entry_ledger_posts',
    'customer_points_ledger', 'online_orders', 'online_order_events', 'online_order_flags', 'order_dup_flags', 'inbound_messages', 'inbound_message_events',
    'bank_statement_lines', 'bank_recon_matches', 'bank_recon_trail', 'fa_depr_posts',
    'partner_capital', 'partner_settlement_lines', 'partner_settlement_payments', 'partner_settlements',
    'release_requests', 'sales_fact_t', 'customer_gifts', 'assets', 'asset_costs',
    'shortage_transit_events', 'shortage_transit', 'shortage_cash_cases', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks', 'c_month_close_log', 'opening_batches', /* bos85: tables of phases 80-83 */
    'shadow_links', 'corrections', 'exceptions', 'payment_intents', 'payment_webhook_log', 'notify_outbox',
    /* phase84b: phase 87 */
    'entry_approvers', 'money_transfers', 'money_charges', 'money_checks', 'money_exceptions', 'money_exception_grants',
    /* phase84b: Wave 1 (phases 88 to 99) */
    'w1c_returns', 'w1c_return_lines', 'late_sales_held', 'open_party_adjustments', 'other_income', 'period_overrides', 'profit_row_exclusions',
    'w1e_requests', 'w1g_post_runs', 'w1g_post_watermark']::text[]
$$;

-- Tables a test reset must NEVER touch (setup, people, rules, audit). Checked before anything runs; a name in both lists stops the reset.
create or replace function public._e_reset_protected() returns text[] language sql immutable as $$
  select array[
    'items', 'item_types', 'item_costs', 'item_class_map', 'item_price_history', 'unit_conversions', 'recipes', 'recipe_lines', 'recipe_versions', 'recipe_steps', 'recipe_cost_components', 'product_packaging',
    'rules', 'rule_grants', 'grant_defs', 'user_grants', 'roles', 'user_roles', 'role_form_perms', 'role_favourites', 'user_favourites', 'staff_roles', 'profiles', 'user_locations',
    'locations', 'location_settings', 'location_setup_steps', 'location_cost_cfg', 'forms', 'form_rollout', 'forms_ledger_cfg',
    'option_lists', 'list_defs', 'list_managers', 'list_other_entries', 'option_requests',
    'coa_accounts', 'acct_mappings', 'settings', 'settings_keys', 'settings_sheets', 'settings_values', 'path_domains', 'path_switch',
    'customers', 'suppliers', 'employees', 'employee_locations', 'employee_pay', 'employee_pay_components', 'sales_channels', 'serials',
    'd_wallets', 'd_material_roles', 'd_item_roles', 'd_product_role_req', 'd_material_fixed_price', 'audit_log', 'backup_runs', 'restore_drills', 'login_attempts', 'login_failures', 'login_throttle', '_e_reset_log',
    /* phase84b: phase 87 */
    'money_accounts', 'money_recurring', 'money_event_settings',
    /* phase84b: Wave 1 (phases 88 to 99) */
    'w1c_return_class_rules', 'w1c_exit_keep', 'w1c_exit_log', 'w1e_mapping_types', 'w1f_seed_state', 'w1g_sched_state', 'w1g_switch_acks', 'report_brand_map', 'report_brand_map_hist']::text[]
$$;

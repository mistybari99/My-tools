-- Phase 84c - GUARDED TEST-PROJECT RESET, TABLES OF PHASES 120 TO 477. TEST PROJECTS ONLY. NEVER PASTE THIS FILE INTO THE LIVE PROJECT.
-- It is NOT part of the owner paste order (tests/sql/ORDER.txt never lists it) and it is not a numbered build phase: it extends phase84b_test_project_only_wave1.sql.
-- Paste order in a TEST project: the whole owner paste list (phases 8 to 477), then phase84_test_project_only.sql, then phase84b_test_project_only_wave1.sql, then THIS file. Paste-twice safe.
-- If phase84_test_project_only.sql or phase84b_test_project_only_wave1.sql is pasted again later, paste this file again afterwards (they put their shorter lists back).
--
-- WHY: the two lists of phase 84 / 84b (_e_reset_tables = what a test reset clears, _e_reset_protected = what it must never touch) were written before phases 120 to 477.
-- On a database that has them, the reset REFUSES to run ("tables outside the clear list point at cleared tables: crm_leads -> sales, order_refunds -> cash_moves ..."),
-- because the new record tables point at tables the reset clears. This file ADDS the new tables to the two lists (the old lists stay as they are, the union is taken, so it works on
-- top of phase 84 alone or 84 + 84b). The reset itself (_e_test_reset), its three checks (owner, rule allow_test_reset ON, phrase DELETE ALL TEST DATA), the one-reset-per-switch
-- behaviour and the reset log are NOT changed. The old files are not edited. Nothing here runs a reset.
--
-- CLEARED (records made by the daily work; test rows): pay requests and their events/exceptions (R1), enquiries/leads, quotes, tasks, complaints, feedback and their events (CRM-G/H),
--   coupon uses, referrals, points-expiry runs and lines, voucher postings, hook grants (CRM-F), customer metrics (CRM-C, derived), order advance/refund/promise/cake/delivery records and
--   campaign tags and posting decisions (RPT-C2/C3), production plans, orders, crew, labour, loss, actual use and run links (RPT-B4), receipt lots, recall cases, stock-out log, price overrides,
--   KPI snapshots, derived tables of the reports.
-- PROTECTED (setup, people, owner choices, audit and legal history): extra phones/addresses/dates/tags/notes/links of customers, consent preferences and events, duplicate reviews, segments,
--   lead lists, coupon definitions and scope, hooks, referral codes, production lines, capacity ratings, item-supplier prices, festival calendar, sales targets, announcements, to-do list, roster,
--   saved hub items, report notice topics, account classes, and every export / view log.
-- A table that is on both lists stops the reset (checked by the old function). Tables that exist in neither list are simply left alone, as before.

do $g$ begin
  if to_regprocedure('public._e_test_reset(text)') is null or to_regprocedure('public._e_reset_tables()') is null or to_regprocedure('public._e_reset_protected()') is null then
    raise exception 'phase84c needs phase84_test_project_only.sql (and phase84b_test_project_only_wave1.sql) pasted first (test projects only)';
  end if;
end $g$;

-- the first paste keeps the function that was there (84 or 84b) under another name; a second paste does not overwrite that copy
do $k$ begin
  if to_regprocedure('public._e_reset_tables_84b()') is null then
    alter function public._e_reset_tables() rename to _e_reset_tables_84b;
    alter function public._e_reset_protected() rename to _e_reset_protected_84b;
  end if;
end $k$;

create or replace function public._e_reset_tables() returns text[] language sql immutable as $$
  select array(select distinct x from unnest(public._e_reset_tables_84b() || array[
    /* phase84c: R1 pay requests (120) */
    'pay_requests', 'pay_request_events', 'pay_request_exceptions',
    /* CRM-F (316-319) */
    'crmf_coupon_uses', 'crmf_expiry_lines', 'crmf_expiry_runs', 'crmf_hook_grants', 'crmf_liab_postings', 'crmf_referrals',
    /* CRM-C derived values (306) */
    'crm_metrics', 'crm_metrics_runs',
    /* CRM-G (323-327) and CRM-H (328-329) */
    'crm_leads', 'crm_lead_events', 'crm_lead_quotes', 'crm_tasks', 'crm_task_events', 'crm_complaints', 'crm_complaint_events', 'crm_complaint_returns', 'crm_feedback',
    /* RPT-B4 production (404-416) */
    'production_plans', 'production_orders', 'production_crew', 'production_labour', 'production_loss', 'production_issue_actual', 'production_run_links', 'production_run_orders',
    'kpi_snapshots',
    /* RPT-B3 (430-436) */
    'receipt_lots', 'recall_cases', 'recall_batches', 'stockout_log',
    /* RPT-C1 / C2 / C3 (440-468) */
    'sale_price_overrides', 'order_advance_posts', 'order_refunds', 'order_promises', 'order_cake_specs', 'order_delivery_costs',
    'mkt_order_tags', 'mkt_sale_tags', 'mkt_post_decisions']) x order by x)
$$;

create or replace function public._e_reset_protected() returns text[] language sql immutable as $$
  select array(select distinct x from unnest(public._e_reset_protected_84b() || array[
    /* phase84c: CRM-A / B / C / F / G (300-329) */
    'customer_phones', 'customer_addresses', 'customer_dates', 'customer_tags', 'crm_tags', 'crm_notes',
    'crm_contact_prefs', 'crm_consent_events', 'crm_customer_links', 'crm_dup_reviews', 'crm_view_log', 'crm_export_log', 'crmc_export_log',
    'crm_segments', 'crm_segment_members', 'crm_lead_lists',
    'crmf_coupons', 'crmf_coupon_scope', 'crmf_hooks', 'crmf_referral_codes', 'festival_calendar',
    /* R2 (130-132) and the hub (470-476) */
    'r2_announcements', 'r2_announce_seen', 'r2_roster_days', 'r2_todos', 'rpthub_user_items',
    /* reports (400-468) */
    'production_lines', 'capacity_ratings', 'item_suppliers', 'supplier_item_prices', 'sales_targets', 'report_notice_topics', 'coa_report_class']) x order by x)
$$;

revoke all on function public._e_reset_tables_84b(), public._e_reset_protected_84b() from public, anon, authenticated;

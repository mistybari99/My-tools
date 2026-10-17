-- RPT-B1 hooks (markers bos400, bos401, bos402). For the integrator: paste after phases 400, 401 and 402, and again in the re-patch phase after any older phase that re-creates one of these functions.
-- Each call reads the LIVE definition, replaces exact texts, stops with a message if one text is missing (nothing is half changed), and does nothing the second time (the marker is already inside).
-- The helper public._rptb1_patch(fn, marker, pairs) is shipped by phase400. Section 2 needs phase401, section 3 needs phase402; a section whose phase is not pasted is skipped (prints false).
-- Before the hooks every report returns exactly what it returned before. With the hooks every OLD column is identical; only NEW columns and notes appear
-- (proved by supabase/phase400_test.sql, phase401_test.sql, phase402_test.sql).

-- ============================================================================
-- 1. R1 (bos400): returns and refunds in the first report engine
-- ============================================================================
-- 1a. rpt_meas: new measures. They are placeholders (null); _rptb1_agg_wrap fills them, because returns come from other rows than sales.
select case when to_regprocedure('public._rptb1_p400_present()') is not null then public._rptb1_patch('public.rpt_meas(text)'::regprocedure, 'bos400', array[
  $a$select case p_src$a$,
  $a$select /* bos400 */ case p_src$a$,
  $a$"override_lines":{"expr":"coalesce(sum({T}.override_lines), 0)"$a$,
  $a$"returns_amt":{"expr":"null::numeric","bn":"বিক্রি-ফেরত","en":"Returns","type":"money"},
   "net_after_returns":{"expr":"null::numeric","bn":"ফেরত বাদে বিক্রি","en":"Sales after returns","type":"money"},
   "override_lines":{"expr":"coalesce(sum({T}.override_lines), 0)"$a$,
  $a$"override_lines":{"expr":"count(*) filter (where {T}.override)"$a$,
  $a$"returns_amt":{"expr":"null::numeric","bn":"বিক্রি-ফেরত","en":"Returns","type":"money"},
   "returns_qty":{"expr":"null::numeric","bn":"ফেরত পরিমাণ","en":"Returned qty","type":"num"},
   "net_after_returns":{"expr":"null::numeric","bn":"ফেরত বাদে বিক্রি","en":"Sales after returns","type":"money"},
   "qty_after_returns":{"expr":"null::numeric","bn":"ফেরত বাদে পরিমাণ","en":"Qty after returns","type":"num"},
   "override_lines":{"expr":"count(*) filter (where {T}.override)"$a$,
  $a$"share_pct":{"expr":"round(100 * sum({T}.amount)$a$,
  $a$"refund_paid":{"expr":"null::numeric","bn":"ফেরতে দেওয়া টাকা","en":"Refunds paid out","type":"money"},
   "net_after_refunds":{"expr":"null::numeric","bn":"ফেরত দেওয়ার পর টাকা","en":"Amount after refunds","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.amount)$a$]) end;

-- 1b. rpt_def: the new columns are listed on the reports (appended at the END, so the first columns and the summary strip stay as they are); POS day close gets 4 columns.
select case when to_regprocedure('public._rptb1_p400_present()') is not null then public._rptb1_patch('public.rpt_def(text)'::regprocedure, 'bos400', array[
  $a$select ($c${$a$,
  $a$select /* bos400 */ ($c${$a$,
  $a$"measures":["bills","gross","discount","discount_pct","net","avg_bill","paid","due","void_bills","void_amt"]$a$,
  $a$"measures":["bills","gross","discount","discount_pct","net","avg_bill","paid","due","void_bills","void_amt","returns_amt","net_after_returns"]$a$,
  $a$"measures":["bills","net","avg_bill","discount","void_bills"]$a$,
  $a$"measures":["bills","net","avg_bill","discount","void_bills","returns_amt","net_after_returns"]$a$,
  $a$"measures":["bills","gross","discount","net","avg_bill","share_pct","paid","due","void_amt"]$a$,
  $a$"measures":["bills","gross","discount","net","avg_bill","share_pct","paid","due","void_amt","returns_amt","net_after_returns"]$a$,
  $a$"measures":["qty","bills","gross","disc","net","avg_price","share_pct","override_lines","cogs","gp","gp_pct","uncosted_pct"]$a$,
  $a$"measures":["qty","bills","gross","disc","net","avg_price","share_pct","override_lines","cogs","gp","gp_pct","uncosted_pct","returns_amt","returns_qty","net_after_returns","qty_after_returns"]$a$,
  $a$"measures":["qty","bills","gross","disc","net","share_pct","cogs","gp","gp_pct","uncosted_pct"]$a$,
  $a$"measures":["qty","bills","gross","disc","net","share_pct","cogs","gp","gp_pct","uncosted_pct","returns_amt","returns_qty","net_after_returns","qty_after_returns"]$a$,
  $a$"measures":["payments","sale_amount","collection_amount","amount","share_pct"]$a$,
  $a$"measures":["payments","sale_amount","collection_amount","amount","share_pct","refund_paid","net_after_refunds"]$a$,
  $a$"Expected cash in drawer","money"]]$a$,
  $a$"Expected cash in drawer","money"],["refund_cash","ক্যাশ ফেরত দেওয়া","Cash refunds paid out","money"],["refund_mobile","মোবাইলে ফেরত দেওয়া","Mobile refunds paid out","money"],["refund_card","কার্ডে ফেরত দেওয়া","Card refunds paid out","money"],["expected_cash_after_refunds","ফেরত দেওয়ার পর ড্রয়ারে থাকার কথা (ক্যাশ)","Expected cash in drawer after refunds","money"]]$a$]) end;

-- 1c. rpt_agg_build: the grouped query gets the new columns just before it is returned.
select case when to_regprocedure('public._rptb1_p400_present()') is not null then public._rptb1_patch('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure, 'bos400', array[
  $a$return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);$a$,
  $a$wj := public._rptb1_agg_wrap(p_def, p_gl, p_mkeys, p_flt, p_allowed, p_from, p_to, p_dexpr, p_ws, p_fym, p_mobok, p_costok, t, tot);   -- bos400: returns and refund columns
  t := wj ->> 't'; tot := wj ->> 'tot';
  return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);$a$]) end;

-- 1d. rpt_raw: POS day close gets refund_cash / refund_mobile / refund_card / expected_cash_after_refunds (expected_cash is unchanged).
select case when to_regprocedure('public._rptb1_p400_present()') is not null then public._rptb1_patch('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure, 'bos400', array[
  $a$from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);$a$,
  $a$from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);
    sql := public._rptb1_day_close_wrap(sql, p_flt, p_allowed, p_from, p_to, al, p_mobok);   -- bos400: cash handed back to customers$a$,
  $a$sum(expected_cash) as expected_cash$f$;$a$,
  $a$sum(expected_cash) as expected_cash, sum(refund_cash) as refund_cash, sum(refund_mobile) as refund_mobile, sum(refund_card) as refund_card,
      sum(expected_cash_after_refunds) as expected_cash_after_refunds$f$;$a$]) end;

-- 1e. report_run: the plain notes under a report that has the new columns (basis of the figures, rule off).
select case when to_regprocedure('public._rptb1_p400_present()') is not null then public._rptb1_patch('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure, 'bos400', array[
  $a$-- line reports read the facts: if some done sales in this range have no fact rows$a$,
  $a$notes := notes || public._rptb1_notes(def, gl, mkeys);   -- bos400: returns and refund notes
    -- line reports read the facts: if some done sales in this range have no fact rows$a$]) end;

-- ============================================================================
-- 2. R2 (bos401): "data not captured" notices. Needs phase401.
-- ============================================================================
-- 2a. f3: "Actually issued" is filled only when something was posted for the batch AFTER the automatic recipe issue (same transaction = same created_at). Otherwise empty + actual_status.
select case when to_regprocedure('public._rptb1_p401_present()') is not null then public._rptb1_patch('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'::regprocedure, 'bos401', array[
  $a$select n.run_id, n.ing, -sum(l.qty_delta) as used$a$,
  $a$select n.run_id, n.ing, -sum(l.qty_delta) as used, bool_or(l.created_at is distinct from (select pr.created_at from public.production_runs pr where pr.id = n.run_id)) as extra   /* bos401: a movement after the automatic issue = a real measurement */$a$,
  $a$sum(a.used) as actual,$a$,
  $a$case when count(a.used) filter (where a.extra) = count(*) then sum(a.used) end as actual, count(a.used) filter (where a.extra) as n_act,$a$,
  $a$'waste_missing', g.waste_missing)$a$,
  $a$'waste_missing', g.waste_missing, 'actual_status', case when g.n_act = 0 then 'not captured' when g.n_act < g.runs then 'partly (' || g.n_act || ' of ' || g.runs || ' runs)' else 'measured' end)$a$]) end;

-- 2b. l1 / l3: the gaps column also names the losses that are left out of the profit.
select case when to_regprocedure('public._rptb1_p401_present()') is not null then public._rptb1_patch('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos401', array[
  $a$then 'cogs(uncosted)' end), '')$a$,
  $a$then 'cogs(uncosted)' end, public._rptb1_loss_gaps(greatest(d1, p.o_m), least(d2, (p.o_m + interval '1 month - 1 day')::date), p.o_loc) /* bos401 */), '')$a$]) end;
select case when to_regprocedure('public._rptb1_p401_present()') is not null then public._rptb1_patch('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure, 'bos401', array[
  $a$then 'cogs(uncosted)' end), '')$a$,
  $a$then 'cogs(uncosted)' end, public._rptb1_loss_gaps(d1, d2, a.o_loc) /* bos401 */), '')$a$]) end;

-- 2c. report_run3: the notes under f3 / l1 / l3.
select case when to_regprocedure('public._rptb1_p401_present()') is not null then public._rptb1_patch('public.report_run3(text,jsonb,text,text,integer)'::regprocedure, 'bos401', array[
  $a$if jsonb_array_length(rows_) = 0 or ng = 0 then$a$,
  $a$notes := notes || public._rptb1_r3_notes(p_key, d1, d2, eff, flt);   -- bos401: "not captured" and "left out of the profit" notes (also when the list is empty)
  if jsonb_array_length(rows_) = 0 or ng = 0 then$a$]) end;

-- 2d. production_run_costs (costing Runs tab): no 0 for a conversion cost that was never costed, no "actual" that is only the standard.
select case when to_regprocedure('public._rptb1_p401_present()') is not null then public._rptb1_patch('public.production_run_costs(integer,date,date)'::regprocedure, 'bos401', array[
  $a$'conversion_cost', r.conversion_cost,$a$,
  $a$'conversion_cost', case when coalesce(r.conversion_mode, 'off') = 'off' then null else r.conversion_cost end,   /* bos401 */
      'conversion_status', case when coalesce(r.conversion_mode, 'off') = 'off' then 'not_captured' end,
      'unit_cost_basis', case when coalesce(r.conversion_mode, 'off') = 'off' then 'material_only' else 'material_and_conversion' end,$a$,
  $a$'actual_cost', r.actual_cost,$a$,
  $a$'actual_cost', case when r.yield_actual is null then null else r.actual_cost end, 'actual_status', case when r.yield_actual is null then 'not_captured' end,$a$]) end;

-- ============================================================================
-- 3. R7 (bos402): one cost basis for item sales and the business analysis. Needs phase402. Nothing changes until the owner sets reports_cost_basis = ledger_first;
--    the notes under the reports appear with the hooks.
-- ============================================================================
-- 3a. rpt_agg_sql: the cost join of the first-engine reports. Default basis = the exact text of today.
select case when to_regprocedure('public._rptb1_p402_present()') is not null then public._rptb1_patch('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure, 'bos402', array[
  $a$' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id'$a$,
  $a$case when public._rptb1_cost_basis() = 'ledger_first' then ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no'      /* bos402: ledger cost first */
          else ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' end$a$]) end;

-- 3b. report_run: the unknown-cost notes.
select case when to_regprocedure('public._rptb1_p402_present()') is not null then public._rptb1_patch('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure, 'bos402', array[
  $a$-- line reports read the facts: if some done sales in this range have no fact rows$a$,
  $a$notes := notes || public._rptb1_cost_notes(def, flt, allowed, d1, d2, mob_ok, cost_ok);   -- bos402: unknown-cost notes
    -- line reports read the facts: if some done sales in this range have no fact rows$a$]) end;

-- 3c. biz_items: the cost rows come from one function (default basis = the same rows as before).
select case when to_regprocedure('public._rptb1_p402_present()') is not null then public._rptb1_patch('public.biz_items(date,date,integer)'::regprocedure, 'bos402', array[
  $a$(select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id$a$,
  $a$(select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc) c /* bos402 */ on c.item_id = i.id$a$]) end;

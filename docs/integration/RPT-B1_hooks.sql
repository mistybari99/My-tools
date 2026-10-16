-- RPT-B1 hooks (markers bos400, bos401, bos402). For the integrator: paste after phases 400, 401 and 402, and again in the re-patch phase after any older phase that re-creates one of these functions.
-- Each call reads the LIVE definition, replaces exact texts, stops with a message if one text is missing (nothing is half changed), and does nothing the second time (the marker is already inside).
-- The helper public._rptb1_patch(fn, marker, pairs) is shipped by phase400. Section 2 needs phase401, section 3 needs phase402; a section whose phase is not pasted is skipped (prints false).
-- Before the hooks every report returns exactly what it returned before. With the hooks every OLD column is identical; only NEW columns and notes appear
-- (proved by supabase/phase400_test.sql, phase401_test.sql, phase402_test.sql).

-- ============================================================================
-- 1. R1 (bos400): returns and refunds in the first report engine
-- ============================================================================
-- 1a. rpt_meas: new measures. They are placeholders (null); _rptb1_agg_wrap fills them, because returns come from other rows than sales.
select public._rptb1_patch('public.rpt_meas(text)'::regprocedure, 'bos400', array[
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
   "share_pct":{"expr":"round(100 * sum({T}.amount)$a$]);

-- 1b. rpt_def: the new columns are listed on the reports (appended at the END, so the first columns and the summary strip stay as they are); POS day close gets 4 columns.
select public._rptb1_patch('public.rpt_def(text)'::regprocedure, 'bos400', array[
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
  $a$"Expected cash in drawer","money"],["refund_cash","ক্যাশ ফেরত দেওয়া","Cash refunds paid out","money"],["refund_mobile","মোবাইলে ফেরত দেওয়া","Mobile refunds paid out","money"],["refund_card","কার্ডে ফেরত দেওয়া","Card refunds paid out","money"],["expected_cash_after_refunds","ফেরত দেওয়ার পর ড্রয়ারে থাকার কথা (ক্যাশ)","Expected cash in drawer after refunds","money"]]$a$]);

-- 1c. rpt_agg_build: the grouped query gets the new columns just before it is returned.
select public._rptb1_patch('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure, 'bos400', array[
  $a$return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);$a$,
  $a$wj := public._rptb1_agg_wrap(p_def, p_gl, p_mkeys, p_flt, p_allowed, p_from, p_to, p_dexpr, p_ws, p_fym, p_mobok, p_costok, t, tot);   -- bos400: returns and refund columns
  t := wj ->> 't'; tot := wj ->> 'tot';
  return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);$a$]);

-- 1d. rpt_raw: POS day close gets refund_cash / refund_mobile / refund_card / expected_cash_after_refunds (expected_cash is unchanged).
select public._rptb1_patch('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure, 'bos400', array[
  $a$from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);$a$,
  $a$from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);
    sql := public._rptb1_day_close_wrap(sql, p_flt, p_allowed, p_from, p_to, al, p_mobok);   -- bos400: cash handed back to customers$a$,
  $a$sum(expected_cash) as expected_cash$f$;$a$,
  $a$sum(expected_cash) as expected_cash, sum(refund_cash) as refund_cash, sum(refund_mobile) as refund_mobile, sum(refund_card) as refund_card,
      sum(expected_cash_after_refunds) as expected_cash_after_refunds$f$;$a$]);

-- 1e. report_run: the plain notes under a report that has the new columns (basis of the figures, rule off).
select public._rptb1_patch('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure, 'bos400', array[
  $a$-- line reports read the facts: if some done sales in this range have no fact rows$a$,
  $a$notes := notes || public._rptb1_notes(def, gl, mkeys);   -- bos400: returns and refund notes
    -- line reports read the facts: if some done sales in this range have no fact rows$a$]);

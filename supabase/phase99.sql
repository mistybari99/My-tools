-- Phase 99 (bos99) - WAVE 1 INTEGRATION (UNIFIED_BUILD_PLAN section 4.3, package I-1). Paste LAST, after phases 88 to 98. Paste-twice safe. Earlier phase files are not edited.
-- Needs phase87 and every Wave 1 phase: 88 (open parties), 89 (period integrity), 90 and 91 (exit, return rules), 92 and 93 (one profit number, report parity), 94 and 95 (money controls),
-- 96 and 97 (other income, chart, receipt channels), 98 (scheduled posting, freshness). The file stops with a clear message that names what is missing.
--
-- What it does (and nothing else):
--   1. _i1_apply_hooks(): applies EVERY exact-text hook the seven packages shipped to the shared functions, in ONE fixed order (A, B, C, D, E, F, then C's optional scan hook), using the helper each
--      package shipped (_w1a_patch, _w1b_patch, _w1c_patch, _w1d_patch / _w1d_hooks_apply, _m_patch for W1-E, _w1f_patch). Every call reads the LIVE definition, replaces exact text,
--      stops with "patch site not found" if a text is missing (the whole call is one transaction: nothing is half patched) and does nothing the second time (each hook carries its marker).
--      After the patches it checks that every expected marker is inside its function (_i1_expect) and stops with a message if one is missing (a helper that skipped a function is caught).
--   2. _i1_exc_kinds() / _i1_exc_kinds_apply(): the Exceptions list (money_exceptions) accepts the UNION of the kinds of phase87, 89 and 94. The final check constraint is written from this one list
--      (merged with whatever the live constraint holds, so a kind added by a later phase is never lost).
--   Defaults: every hook is inert while its setting is at the default; the before / after snapshot (tests/sql/phase99_before_after.sh) proves P&L, balance sheet, trial balance, cash flow, day book,
--   stock reports and journal lines are identical to a database built only through phase 87.
-- Re-paste hazard: re-pasting phase 6, 8, 10, 12, 13, 14, 19, 23, 27, 40, 41, 43, 44, 50, 52, 72, 73, 74, 79, 80, 82, 85, 86 or 87 removes the matching hooks. Run   select public._i1_apply_hooks();   (or paste this file again).
-- Tag bos99. Test data only (test_*).

do $g$ declare miss text := '';
begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_patch(regprocedure,text[])') is null then miss := miss || ' phase87'; end if;
  if to_regprocedure('public._p88_present()') is null or to_regprocedure('public._w1a_patch(regprocedure,text[],text)') is null then miss := miss || ' phase88'; end if;
  if to_regprocedure('public._p89_present()') is null or to_regprocedure('public._w1b_patch(regprocedure,text,text[])') is null then miss := miss || ' phase89'; end if;
  if to_regprocedure('public._w1c_present90()') is null then miss := miss || ' phase90'; end if;
  if to_regprocedure('public._w1c_present91()') is null or to_regprocedure('public._w1c_patch(regprocedure,text[],text)') is null then miss := miss || ' phase91'; end if;
  if to_regprocedure('public._w1d_p92_present()') is null or to_regprocedure('public._w1d_patch(regprocedure,text,text[])') is null then miss := miss || ' phase92'; end if;
  if to_regprocedure('public._w1d_p93_present()') is null or to_regprocedure('public._w1d_hooks_apply()') is null then miss := miss || ' phase93'; end if;
  if to_regprocedure('public._p94_present()') is null then miss := miss || ' phase94'; end if;
  if to_regprocedure('public._p95_present()') is null then miss := miss || ' phase95'; end if;
  if to_regprocedure('public._w1f_present96()') is null or to_regprocedure('public._w1f_patch(regprocedure,text[],text)') is null then miss := miss || ' phase96'; end if;
  if to_regprocedure('public._w1f_present97()') is null then miss := miss || ' phase97'; end if;
  if to_regprocedure('public._w1g_present()') is null then miss := miss || ' phase98'; end if;
  if miss <> '' then raise exception 'phase99 needs these phases pasted first (in this order, each once):%', miss; end if;
end $g$;

create or replace function public._p99_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. The Exceptions list: ONE list of kinds, ONE place that writes the check constraint
-- ============================================================================
-- phase87: negative_warn, negative_block_exception, source_required_exception, override_exception, period_lock_exception, approver_exception, recon_diff
-- phase89 (W1-B): late_sale_held, late_sale_redated, backdate_exception
-- phase94 (W1-E): w1e_bank_move_flag, w1e_duplicate_payment, w1e_pay_over_request, w1e_vendor_duplicate, w1e_pay_account_duplicate, w1e_pay_account_changed, w1e_owner_money_request, w1e_journal_request
create or replace function public._i1_exc_kinds() returns text[] language sql immutable as $$
  select array[
    'approver_exception', 'backdate_exception', 'late_sale_held', 'late_sale_redated', 'negative_block_exception', 'negative_warn', 'override_exception', 'period_lock_exception',
    'recon_diff', 'source_required_exception',
    'w1e_bank_move_flag', 'w1e_duplicate_payment', 'w1e_journal_request', 'w1e_owner_money_request', 'w1e_pay_account_changed', 'w1e_pay_account_duplicate', 'w1e_pay_over_request', 'w1e_vendor_duplicate'
  ]::text[]
$$;

-- Reads the live constraint in either form (ARRAY['a'::text, ...] or '{a,b}'::text[]), adds the known list, keeps any other kind it finds, writes it back sorted. Same list = nothing changes.
create or replace function public._i1_exc_kinds_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare con text; def text; cur text[]; want text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase99: the money_exceptions kind check was not found (phase87 missing?)'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase99: the money_exceptions kind check has an unknown shape: %', left(def, 120); end if;
  select array_agg(x order by x) into want from (select unnest(cur) x union select unnest(public._i1_exc_kinds())) z;
  if cur = want and position('ARRAY[' in def) > 0 then return jsonb_build_object('changed', false, 'kinds', cardinality(want)); end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
  return jsonb_build_object('changed', true, 'kinds', cardinality(want));
end $$;

-- ============================================================================
-- 2. What each shared function must carry after the hooks (used by the check at the end of _i1_apply_hooks and by the tests)
-- ============================================================================
create or replace function public._i1_expect() returns table (pkg text, fn text, marker text) language sql immutable as $$
  select * from (values
    ('W1-A', 'public._cust_bal(uuid)', 'bos88'), ('W1-A', 'public.customer_dues()', 'bos88'), ('W1-A', 'public.customer_ledger(uuid)', 'bos88'),
    ('W1-A', 'public.opening_balance_post(jsonb,uuid,boolean,boolean)', 'bos88'),
    ('W1-B', 'public.lock_check(date)', 'bos89'), ('W1-B', 'public._acct_locked(date)', 'bos89'),
    ('W1-B', 'public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'bos89'),
    ('W1-B', 'public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'bos89'),
    ('W1-B', 'public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)', 'bos89'),
    ('W1-B', 'public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'bos89'),
    ('W1-B', 'public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'bos89'),
    ('W1-C', 'public.employee_status_set(uuid,text,date,text)', 'bos90'), ('W1-C', 'public.notify_scan()', 'bos90'),
    ('W1-C', 'public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'bos91'), ('W1-C', 'public.void_sale_return(uuid,text)', 'bos91'),
    ('W1-D', 'public._p27_pl(date,date,integer[])', 'bos92'), ('W1-D', 'public.partner_calculate(bigint,date,date,jsonb)', 'bos92'), ('W1-D', 'public.c_partner_month_split(date)', 'bos92'),
    ('W1-D', 'public._p27_pl(date,date,integer[])', 'bos93'), ('W1-D', 'public.report_run2_core(text,jsonb,text,text,integer)', 'bos93'),
    ('W1-D', 'public._r3q_e3_weak_control(date,date,integer[],jsonb)', 'bos93'), ('W1-D', 'public._r3q_e2_expense_trend(date,date,integer[],jsonb)', 'bos93'),
    ('W1-D', 'public.brand_pnl(date,date,text)', 'bos93'), ('W1-D', 'public._daybook_lines(integer[],integer[],date,date)', 'bos93'), ('W1-D', 'public._acct_docs(date)', 'bos93'),
    ('W1-E', 'public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'w1e94'), ('W1-E', 'public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'w1e94c'),
    ('W1-E', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'w1e95'),
    ('W1-F', 'public._acct_docs(date)', 'bos96'), ('W1-F', 'public._daybook_lines(integer[],integer[],date,date)', 'bos96'), ('W1-F', 'public._e_balance_check(date,integer,integer)', 'bos96'),
    ('W1-F', 'public.acct_cash_flow(date,date,integer)', 'bos96'), ('W1-F', 'public.daybook_vs_journal(date,date,integer)', 'bos96'),
    ('W1-F', 'public._acct_docs(date)', 'bos97'), ('W1-F', 'public._daybook_lines(integer[],integer[],date,date)', 'bos97'), ('W1-F', 'public.collect_payment(uuid,integer,uuid,jsonb,text)', 'bos97'),
    ('W1-F', 'public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'bos97')
  ) v(pkg, fn, marker)
$$;

create or replace function public._i1_hooks_state() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('pkg', e.pkg, 'fn', e.fn, 'marker', e.marker,
           'present', to_regprocedure(e.fn) is not null and position(e.marker in pg_get_functiondef(to_regprocedure(e.fn))) > 0) order by e.pkg, e.fn, e.marker), '[]'::jsonb)
    from public._i1_expect() e
$$;

-- ============================================================================
-- 3. The hooks, in the fixed order A, B, C, D, E, F (F96 before F97), C's scan hook last. Returns one entry per patch: true = patched now, false = already there.
-- ============================================================================
create or replace function public._i1_apply_hooks() returns jsonb language plpgsql security definer set search_path = public as $i1$
declare res jsonb := '{}'::jsonb; r boolean; bad text;
begin
  perform pg_advisory_xact_lock(hashtext('bos99_hooks'));
  -- ===== W1-A (marker bos88): opening dues and payables in the customer and supplier sub-ledgers =====
  r := public._w1a_patch('public._cust_bal(uuid)'::regprocedure, array[
  $a$select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$,
  $a$select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$]);
  res := res || jsonb_build_object('bos88:_cust_bal', r);
  r := public._w1a_patch('public.customer_dues()'::regprocedure, array[
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),$a$,
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),$a$,
  $a$(select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))$a$,
  $a$(case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)$a$,
  $a$from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$and t.rem - coalesce(c.coll, 0) > 0$a$,
  $a$and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0$a$]);
  res := res || jsonb_build_object('bos88:customer_dues', r);
  r := public._w1a_patch('public.customer_ledger(uuid)'::regprocedure, array[
  $a$select s.sold_at at, 'sale'::text kind,$a$,
  $a$select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind,$a$]);
  res := res || jsonb_build_object('bos88:customer_ledger', r);
  r := public._w1a_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$,
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */ perform public._w1a_opening_apply(p_json); /* bos88 */$a$]);
  res := res || jsonb_build_object('bos88:opening_balance_post', r);
  -- ===== W1-B (marker bos89): period integrity =====
  r := public._w1b_patch('public.lock_check(date)'::regprocedure, 'bos89', array[
  $a$if p_date is null or public.is_owner() then return; end if;$a$,
  $a$if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$a$]);
  res := res || jsonb_build_object('bos89:lock_check', r);
  r := public._w1b_patch('public._acct_locked(date)'::regprocedure, 'bos89', array[
  $a$begin perform public.lock_check(p_date); return false;$a$,
  $a$begin if public._w1b_pure_posting() then return public._w1b_is_locked(p_date); end if; /* bos89 */ perform public.lock_check(p_date); return false;$a$]);
  res := res || jsonb_build_object('bos89:_acct_locked', r);
  r := public._w1b_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43$a$,
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
  lt89 jsonb;   -- bos89$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;$a$]);
  res := res || jsonb_build_object('bos89:record_sale2', r);
  r := public._w1b_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, 'bos89', array[
  $a$if p_dry then$a$,
  $a$perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then$a$]);
  res := res || jsonb_build_object('bos89:cash_move_add', r);
  r := public._w1b_patch('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'::regprocedure, 'bos89', array[
  $a$perform public.lock_check(d);$a$,
  $a$perform public.lock_check(d);
  perform public._w1b_backdate_check('expense', d, p_client, 'quick_expenses');   -- bos89$a$]);
  res := res || jsonb_build_object('bos89:quick_expense_add', r);
  r := public._w1b_patch('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'::regprocedure, 'bos89', array[
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;$a$,
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;$a$]);
  res := res || jsonb_build_object('bos89:save_purchase', r);
  r := public._w1b_patch('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;$a$,
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89$a$]);
  res := res || jsonb_build_object('bos89:production_post', r);
  -- ===== W1-C (markers bos90, bos91): staff exit, sale return =====
  r := public._w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);',
  E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'
], 'bos90');
  res := res || jsonb_build_object('C:employee_status_set', r);
  r := public._w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);',
  E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'
], 'bos91');
  res := res || jsonb_build_object('C:sale_return', r);
  r := public._w1c_patch('public.void_sale_return(uuid,text)'::regprocedure, array[
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;',
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;\n  perform public._w1c_return_void_guard(p_id); /* bos91 */'
], 'bos91');
  res := res || jsonb_build_object('C:void_sale_return', r);
  -- ===== W1-D (markers bos92, bos93): one profit number, report parity (the patches of phases 92 and 93 again, then the day book and journal hook) =====
  r := public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos92', array[
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),$a$,
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),$a$]);
  res := res || jsonb_build_object('bos92:_p27_pl', r);
  r := public._w1d_patch('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure, 'bos92', array[
  $a$ag public.partner_agreements; vn public.partner_ventures;$a$, $a$ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;$a$,
  $a$'warnings', warns, 'wrote', false);$a$, $a$'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);$a$]);
  res := res || jsonb_build_object('bos92:partner_calculate', r);
  r := public._w1d_patch('public.c_partner_month_split(date)'::regprocedure, 'bos92', array[
  $a$base := (prof ->> 'net_profit')::numeric;$a$,
  $a$base := coalesce(public._w1d_split_base(greatest(m, st), me, case when a.scope = 'location' then a.location_id end), (prof ->> 'net_profit')::numeric);   /* bos92 */$a$,
  $a$'basis', 'journal net profit of the month (salary accrual included)'$a$, $a$'basis', coalesce(public._w1d_split_basis(), 'journal net profit of the month (salary accrual included)')$a$]);
  res := res || jsonb_build_object('bos92:c_partner_month_split', r);
  r := public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */$a$,
  $a$where public.rule_on('payroll_accrual_on') /* bos85 bos86 */$a$,
  $a$where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */$a$]);
  res := res || jsonb_build_object('bos93:_p27_pl', r);
  r := public._w1d_patch('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) and e.entry_date between %L and %L and e.location_id = any (%L::int[])
            union all  /* bos93: quick expenses (only while report_expense_parity_on) */
            select null::uuid, q.location_id, q.exp_date, q.amount, case when q.receipt then 'yes' else 'no' end, coalesce(nullif(btrim(q.head), ''), '-') from public.quick_expenses q
            where public._w1d_parity_on() and q.status = 'done' and q.exp_date between %2$L and %3$L and q.location_id = any (%4$L::int[])) x$a$]);
  res := res || jsonb_build_object('bos93:report_run2_core', r);
  r := public._w1d_patch('public._r3q_e3_weak_control(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) /* bos93 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$   group by l.id, l.name_bn;$a$,
  $a$   group by l.id, l.name_bn
  union all  /* bos93: quick expenses have no voucher flags; their count and the lines without a receipt are shown so that the control report covers them */
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', 'quick', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', count(*) filter (where not q.receipt), 'no_receipt_amount', coalesce(sum(q.amount) filter (where not q.receipt), 0), 'over_limit_vouchers', null, 'over_limit_amount', null,
      'approval_missing', null, 'reason_missing', null, 'imprest_diff_sheets', null, 'imprest_diff_amount', null)
    from public.quick_expenses q join public.locations l on l.id = q.location_id
   where public._w1d_parity_on() and q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
   group by l.id, l.name_bn;$a$]);
  res := res || jsonb_build_object('bos93:_r3q_e3_weak_control', r);
  r := public._w1d_patch('public._r3q_e2_expense_trend(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$]);
  res := res || jsonb_build_object('bos93:_r3q_e2_expense_trend', r);
  r := public._w1d_patch('public.brand_pnl(date,date,text)'::regprocedure, 'bos93', array[
  $a$left join public.report_brand_map b on b.location_id = d.location_id$a$,
  $a$left join lateral public._w1d_brand_at(d.location_id, d.sale_date) b on true /* bos93 */$a$]);
  res := res || jsonb_build_object('bos93:brand_pnl', r);
  res := res || jsonb_build_object('bos93:_w1d_hooks_apply', public._w1d_hooks_apply());
  -- ===== W1-E (markers w1e94, w1e94c, w1e95; phase87 helper _m_patch): supplier payment, cash move display, manual journal =====
  r := public._m_patch('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure, array[
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;$h$,
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
$h$]);
  res := res || jsonb_build_object('w1e:pay_supplier', r);
  r := public._m_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, array[
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));$h$,
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */$h$]);
  res := res || jsonb_build_object('w1e:cash_move_add', r);
  r := public._m_patch('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure, array[
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;$h$,
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */$h$,
 $h$  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$,
 $h$  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$]);
  res := res || jsonb_build_object('w1e:acct_journal_post', r);
  -- ===== W1-F (markers bos96, bos97): other income, legacy wallets, receipt channels =====
  r := public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$,
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_acct_docs', r);
  r := public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$,
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_daybook_lines', r);
  r := public._w1f_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$  begin   -- bos96: mapping coverage (amber): every key the posting needs points to an active account
    xc := xc || jsonb_build_object('mapping_coverage', public._w1f_mapping_coverage());
    if not coalesce((xc #>> '{mapping_coverage,ok}')::boolean, true) then warn := warn || to_jsonb('mapping_coverage'::text); end if;
  exception when others then xc := xc || jsonb_build_object('mapping_coverage', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_e_balance_check', r);
  r := public._w1f_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$union select coa_account_id from public.money_accounts) z; /* bos87 */$a$,
  $a$union select coa_account_id from public.money_accounts union select account_id from public.acct_mappings where key like 'd\_wallet\_%' /* bos96: legacy wallets */) z; /* bos87 */$a$], 'bos96');
  res := res || jsonb_build_object('bos96:acct_cash_flow', r);
  r := public._w1f_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$from public.acct_mappings m0 union select ma.coa_account_id$a$,
  $a$from public.acct_mappings m0 union select w0.account_id, 'pay_mobile' from public.acct_mappings w0 where w0.key like 'd\_wallet\_%' /* bos96: legacy wallets */ union select ma.coa_account_id$a$], 'bos96');
  res := res || jsonb_build_object('bos96:daybook_vs_journal', r);
  r := public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode$a$,
  $a$jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),$a$], 'bos97');
  res := res || jsonb_build_object('bos97:_acct_docs', r);
  r := public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,$a$,
  $a$nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,$a$], 'bos97');
  res := res || jsonb_build_object('bos97:_daybook_lines', r);
  r := public._w1f_patch('public.collect_payment(uuid,integer,uuid,jsonb,text)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2),$a$], 'bos97');
  res := res || jsonb_build_object('bos97:collect_payment', r);
  r := public._w1f_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_,$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_,$a$], 'bos97');
  res := res || jsonb_build_object('bos97:record_sale2', r);
  -- ===== W1-C optional hook 4 (marker bos90): the exit alert scan runs inside notify_scan (does nothing until exit_alert_hours is set) =====
  r := public._w1c_patch('public.notify_scan()'::regprocedure, array[
  E'  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);',
  E'  perform public._w1c_exit_scan_run(); /* bos90 */\n  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);'
], 'bos90');
  res := res || jsonb_build_object('C4:notify_scan', r);
  -- every expected marker must now be inside its function (a helper that skipped a function silently is caught here)
  select string_agg(x ->> 'fn' || ' (' || (x ->> 'marker') || ')', ', ') into bad from jsonb_array_elements(public._i1_hooks_state()) x where not (x ->> 'present')::boolean;
  if bad is not null then raise exception 'phase99: hook missing after patching: %', bad; end if;
  return res;
end $i1$;

revoke all on function public._p99_present(), public._i1_exc_kinds(), public._i1_exc_kinds_apply(), public._i1_expect(), public._i1_hooks_state(), public._i1_apply_hooks() from public, anon, authenticated;

-- ============================================================================
-- 4. Run
-- ============================================================================
select public._i1_exc_kinds_apply();
select public._i1_apply_hooks();

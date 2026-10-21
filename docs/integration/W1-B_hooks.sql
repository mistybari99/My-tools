-- W1-B hooks (marker bos89). For the integrator: paste after phase89, and again in the wave's re-patch phase (phase99) after any older phase that re-creates one of these functions.
-- Each call reads the LIVE definition, replaces exact texts, stops with a message if one text is missing (nothing is half changed), and does nothing the second time (marker bos89).
-- With every W1-B setting at its default these hooks change no behaviour (proved by supabase/phase89_test.sql and tests/sql/phase89_before_after.sh).
-- The helper _w1b_patch(fn, marker, pairs) is shipped by phase89 because the phase87 helper _m_patch only knows the marker bos87 and lock_check already carries it.

-- 1. lock_check: a pure date test; the owner is no longer silent when owner_closed_period_mode is log or reason; override windows. The old body stays below the new lines and is no longer reached.
select public._w1b_patch('public.lock_check(date)'::regprocedure, 'bos89', array[
  $a$if p_date is null or public.is_owner() then return; end if;$a$,
  $a$if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$a$]);

-- 2. _acct_locked: a document is in or out of a closed month the same way for every user (only when owner_closed_period_mode is log or reason; with off nothing changes)
select public._w1b_patch('public._acct_locked(date)'::regprocedure, 'bos89', array[
  $a$begin perform public.lock_check(p_date); return false;$a$,
  $a$begin if public._w1b_pure_posting() then return public._w1b_is_locked(p_date); end if; /* bos89 */ perform public.lock_check(p_date); return false;$a$]);

-- 3. record_sale2: a sale older than pos_offline_hours follows late_sale_policy (redate = as today, redate_flag, park). The new variable is declared next to the bos43 ones.
select public._w1b_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43$a$,
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
  lt89 jsonb;   -- bos89$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;$a$]);

-- 4. cash_move_add: back-date window for cash moves (after the duplicate check, so a retry of a saved move is never refused)
select public._w1b_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, 'bos89', array[
  $a$if p_dry then$a$,
  $a$perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then$a$]);

-- 5. quick_expense_add: back-date window for quick expenses
select public._w1b_patch('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'::regprocedure, 'bos89', array[
  $a$perform public.lock_check(d);$a$,
  $a$perform public.lock_check(d);
  perform public._w1b_backdate_check('expense', d, p_client, 'quick_expenses');   -- bos89$a$]);

-- 6. save_purchase: back-date window for the bill date (a draft that keeps its date is not asked again)
select public._w1b_patch('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'::regprocedure, 'bos89', array[
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;$a$,
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;$a$]);

-- 7. production_post (7 arguments; the 6-argument form calls it): back-date window for the made-at day
select public._w1b_patch('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;$a$,
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89$a$]);

-- W1-F hooks for phase 97 (marker bos97). THESE ARE NOT PART OF phase97.sql: the wave integrator pastes them (docs/integration/W1-F.md section 3).
-- phase97_test.sql runs this file inside a transaction that is rolled back, so the patched shared functions only ever exist on a scratch copy.
-- Every pair is [old exact text, new exact text]. A missing site stops the paste (nothing half changed). Paste twice = no-op (marker bos97).

-- H97-1 _acct_docs: a sale payment and a collection post to the payment's own money account when it has one (generic cash / bank / mobile account otherwise, exactly as before)
select public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode$a$,
  $a$jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),$a$], 'bos97');

-- H97-2 _daybook_lines: the day book line of a customer receipt names the money account and the cheque number
select public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,$a$,
  $a$nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,$a$], 'bos97');

-- H97-3 collect_payment: the old route accepts the same channels as _w1f_collect_payment (optional: the screen can call the new route instead)
select public._w1f_patch('public.collect_payment(uuid,integer,uuid,jsonb,text)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2),$a$], 'bos97');

-- H97-4 record_sale2: POS split payments accept bank (and cheque) and carry the payment source and the reference fields
select public._w1f_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_,$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_,$a$], 'bos97');

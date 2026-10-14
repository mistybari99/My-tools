-- ============================================================
-- Phase 105 (bos105) - STEP Sec2: fixes of the second security review (docs/briefs_p2p3/step_Sec2_REPORT.md). Goes LAST (phase104 is reserved for the dashboard step and is NOT needed).
--   Needs phases 72..103 pasted first (guard below, incl. the phase103 advisor row flw_grn_double103). Additive, paste-twice safe: every function is re-created from its LATEST body,
--   only lines tagged bos105 differ, every older bosNN tag is kept (a body guard refuses to overwrite a body that carries a tag this file does not know).
--   Defaults: everything keeps today's behaviour. Pure bug fixes are on at once; the only new switch (customers_pii_guard_on) is OFF.
--   H1  customer phone / address bypass paths. customer_dues, customer_advances, customer_profile (the "customer card") now follow inbox_pii_mode through _cust_pii103, exactly like
--       customer_directory / find_customer (owner and view_customer_mobile holders see everything; inbox_pii_mode = off changes nothing). The online_orders column guard
--       (inbox_pii_guard_on) now also hides note, draft_note and lines. New opt-in switch customers_pii_guard_on (OFF): the browser may then not read customers.mobile / whatsapp /
--       address / note with a plain table read (screens that do so must move to the RPCs first - see the report). customer_save ignores a masked value (it holds the mask dot) so a masked
--       screen value is never saved over the real one.
--   M1  inbox_unmask: the daily limit is counted under an advisory lock (parallel calls can no longer all pass).
--   M2  automatic bill payment honours bill_pay_large_amount and (purchase bills) the supplier_pay grant of the person who posts; otherwise it is skipped with the yellow flag
--       bill_pay_auto_skipped and the bill waits for a payment.
--   M3  keep_credit trigger: a direct void of a bill-linked payment is refused with void_the_bill instead of being dropped silently (the bill void keeps working as before).
--   M6  phone number typed in free text: separators space, tab, no-break space, ( ) . - / _ (1..3 of them) are followed; dates such as 14/10/2026 are left alone.
--   L3  automatic payment client id: md5 of kind + ref + a private random salt (bos_salt105, closed table). L4 a known client id of another bill raises client_id_reused.
--   L5  blocked unmask attempts: at most one log line per person per minute. L6 customer_directory name follows mask_all_pii (first letter + dots); the one changed line there is marked
--       sec2-L6 (not bos105) so that phase103's body guard still accepts the function: after a re-paste of phase89 / 94 / 96 / 97 / 98 paste phase103 and then phase105 again.
--   Tag: bos105.
-- ============================================================

do $g$ begin perform set_config('phase105.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._bp_auto99(text,text,integer,text,text,text,integer,text)'), ('99', 'public.inbox_unmask(text,text,text)'),
    ('103', 'public._cust_pii103(text,text)'), ('103', 'public._inb_mask_phones103(text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_check_defs81') is null or not exists (select 1 from public.setup_check_defs81 where code = 'flw_grn_double103') then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase105 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase105.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase105.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._bp_uuid99(text,text)', array['bos99', 'bos105']::text[]),                       -- 'bos99' = the text of the literal 'bos99auto:'
    ('public._bp_auto99(text,text,integer,text,text,text,integer,text)', array['bos105']::text[]),
    ('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)', array['bos105']::text[]),
    ('public._bp_sp_void99()', array['bos105']::text[]),
    ('public.inbox_unmask(text,text,text)', array['bos105']::text[]),
    ('public._inb_mask_phones103(text)', array['bos105']::text[]),
    ('public._cust_pii103(text,text)', array['bos105']::text[]),
    ('public.customer_dues()', array['bos105']::text[]),
    ('public.customer_advances()', array['bos105']::text[]),
    ('public.customer_profile(uuid)', array['bos105']::text[]),
    ('public.customer_directory(integer)', array['bos103']::text[]),                         -- carries the marker sec2-L6 instead of a bosNN tag: phase103's own body guard must still accept it (a re-paste of 103 is followed by 105)
    ('public.customer_save(uuid,jsonb,uuid)', array['bos105']::text[]),
    ('public._inb_pii_cols76()', array['bos105']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase105: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase105.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- L3: the automatic-payment client id is no longer a guessable md5 of kind+ref (a private random salt, kept in a closed table) ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
  create table if not exists public.bos_salt105 (k text primary key, v text not null);
  alter table public.bos_salt105 enable row level security;
  revoke all on public.bos_salt105 from public, anon, authenticated;
  insert into public.bos_salt105 (k, v) values ('auto99', gen_random_uuid()::text || gen_random_uuid()::text) on conflict (k) do nothing;
end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._bp_uuid99(p_kind text, p_ref text) returns uuid language sql stable security definer set search_path = public as $$
  select md5('bos99auto:' || p_kind || ':' || p_ref || ':' || (select v from public.bos_salt105 where k = 'auto99'))::uuid   -- bos105 (L3): unguessable, still one fixed id per bill
$$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._bp_auto_ok105(p_kind text, p_ref text, p_loc int) returns text
language plpgsql stable security definer set search_path = public as $$
-- bos105 (M2): an automatic payment keeps the limits a person would meet: the owner-typed large-bill limit, and (purchase) the poster must hold supplier_pay. NULL = go ahead, else the reason.
declare lim numeric := public.rule_num('bill_pay_large_amount'); amt numeric;
begin
  if p_kind = 'cost' then select b.amount into amt from public.cost_source_bills b where b.id = p_ref::bigint;
  else select b.total - b.paid into amt from public.purchase_bills b where b.id = p_ref::uuid; end if;
  if lim is not null and amt is not null and amt >= lim then return 'large_bill'; end if;
  if p_kind = 'purchase' and not (public.is_owner() or public.has_grant('supplier_pay', p_loc)) then return 'no_supplier_pay'; end if;
  return null;
end $$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_auto99(p_kind text, p_ref text, p_loc integer, p_party_kind text, p_party_id text, p_rule text, p_credit_days integer, p_bill_mode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := coalesce(public.rule_txt(p_rule), 'off'); d public.bill_pay_defaults99; pm text; credit boolean; r jsonb; why text; frm text := case when p_kind = 'cost' then 'STOCK' else 'PURCHASE' end;
begin
  if mode_ not in ('auto_cash', 'auto_bank', 'auto_by_supplier_default') then return; end if;
  begin                                                   -- nothing in here may stop the bill itself from being saved / posted
    select * into d from public.bill_pay_defaults99 where party_kind = p_party_kind and party_id = p_party_id;
    credit := coalesce(d.credit_terms, false) or coalesce(p_credit_days, 0) > 0;
    if credit and not public.rule_on('bill_pay_auto_credit_ok') then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'credit-শর্তের পক্ষ: স্বয়ংক্রিয় payment হয়নি, bill payment-এর অপেক্ষায়', 'Party has credit terms: no automatic payment made; the bill waits for a payment', null, null, frm, null);
      return;
    end if;
    why := public._bp_auto_ok105(p_kind, p_ref, p_loc);   -- bos105 (M2)
    if why is not null then   -- bos105
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি (' || why || '): বড় bill বা payment-এর অনুমতি নেই', 'Automatic payment skipped (' || why || '): a large bill, or the person has no payment right', null, null, frm, null);   -- bos105
      return;   -- bos105
    end if;   -- bos105
    pm := case mode_ when 'auto_cash' then 'cash' when 'auto_bank' then 'bank'
            else coalesce(d.pay_mode, case when p_bill_mode in ('cash', 'bank', 'mobile') then p_bill_mode end) end;
    if pm is null then return; end if;                    -- by_supplier_default with no default known = behaves like "ask" (the list offers it)
    r := public._bp_pay99(p_kind, p_ref, pm, null, 'auto', public._bp_uuid99(p_kind, p_ref), 'automatic (rule ' || p_rule || ')', false);
    if not coalesce((r->>'ok')::boolean, false) then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: একই খরচ আগেই লেখা থাকতে পারে (' || coalesce(r->>'warnings', '') || ')', 'Automatic payment not made: the same cost may already be recorded (' || coalesce(r->>'warnings', '') || ')', null, null, frm, null);
    end if;
  exception when others then
    begin
      perform public._stock_exc(p_loc, 'bill_pay_auto_failed', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: ' || left(sqlerrm, 120), 'Automatic payment failed: ' || left(sqlerrm, 120), null, null, frm, null);
    exception when others then null;
    end;
  end;
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found and (ex.bill_kind <> p_kind or ex.bill_ref <> p_ref) then raise exception 'client_id_reused'; end if;   -- bos105 (L4): a known id of ANOTHER bill is never answered "paid"
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for update;                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_sp_void99()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l public.bill_payments99; ctx text;
begin
  if not (new.voided and not old.voided and old.bill_id is not null) then return new; end if;
  select * into l from public.bill_payments99 where money_type = 'supplier_payment' and money_ref = old.id::text and status = 'active';
  if not found then return new; end if;
  if coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit' then
    get diagnostics ctx = pg_context;   -- bos105 (M3): only the void of the BILL may turn its payment into supplier credit; a direct void of the payment is refused loudly, never dropped silently
    if position('_void_purchase_p13' in ctx) = 0 and not exists (select 1 from public.purchase_bills b where b.id = old.bill_id and b.status = 'void') then raise exception 'void_the_bill'; end if;   -- bos105
    new.voided := false; new.void_note := old.void_note; new.void_by := old.void_by; new.bill_id := null;
    update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment kept as supplier credit' where id = l.id;
    perform public._stock_exc(old.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment supplier-এর credit হিসেবে রাখা হয়েছে: ' || old.amount::text, 'Payment of a voided purchase bill kept as supplier credit: ' || old.amount::text, null, null, 'PURCHASE', old.amount);
  else
    update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'purchase bill voided' where id = l.id;
  end if;
  return new;
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inbox_unmask(p_kind text, p_id text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare loc int; m public.inbound_messages; o public.online_orders; mode_ text := public._inb_pii_mode99(); lim numeric := public.rule_num('inbox_unmask_daily_max'); used int; data jsonb; fields text; sid text;
begin
  if p_kind not in ('message', 'order') or p_id is null then raise exception 'bad_input'; end if;
  if p_kind = 'message' then
    if p_id !~ '^[0-9]{1,18}$' then raise exception 'bad_input'; end if;
    select * into m from public.inbound_messages where id = p_id::bigint;
    if not found then raise exception 'not_found'; end if;
    loc := m.location_id; perform public._inb_gate(loc, 'view'); fields := 'handle,name,text,attachment';
  else
    if p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_input'; end if;
    select * into o from public.online_orders where id = p_id::uuid;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
    if not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(loc) then raise exception 'not allowed'; end if;
    fields := 'customer_mobile,address,customer_name';
  end if;
  if not public._inb_contact_ok(loc) then raise exception 'not allowed'; end if;
  if mode_ = 'off' then          -- nothing is masked: the normal read (which has its own view line)
    return jsonb_build_object('ok', true, 'mode', 'off', 'logged', false, 'data', case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end);
  end if;
  if not (public.is_owner() or public.has_grant('inbox_unmask', loc)) then raise exception 'not allowed'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if lim is not null and not public.is_owner() then
    perform pg_advisory_xact_lock(hashtextextended('inb_unmask99:' || auth.uid()::text, 0));   -- bos105 (M1): parallel calls of one person are counted one after the other
    select count(*) into used from public.inbox_unmask_log99 where user_id = auth.uid() and outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date;
    if used >= lim then
      if not exists (select 1 from public.inbox_unmask_log99 z where z.user_id = auth.uid() and z.outcome = 'blocked' and z.at > now() - interval '1 minute') then   -- bos105 (L5): at most one blocked line per person per minute
      insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'blocked');
      end if;   -- bos105
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'used', used, 'max', lim);
    end if;
  end if;
  perform set_config('bos.inb_unmask99', txid_current()::text, true);
  begin
    data := case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end;
  exception when others then
    perform set_config('bos.inb_unmask99', '', true); raise;
  end;
  perform set_config('bos.inb_unmask99', '', true);
  insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'revealed');
  perform public._inb_audit_view('inbox_unmask', p_kind || ':' || p_id, jsonb_build_object('fields', fields, 'reason', left(nullif(btrim(p_reason), ''), 300)));
  return jsonb_build_object('ok', true, 'mode', mode_, 'logged', true, 'data', data, 'used', coalesce(used, 0) + 1, 'max', lim);
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._inb_mask_phones103(p text) returns text
language plpgsql immutable set search_path = public as $b$
-- masks every phone-number-like digit run (ASCII or Bangla digits, optional +, 8..15 digits, keeps the last 3). Between digits (bos105, M6): up to 3 of space, tab, no-break space, ( ) . - / _ ;
-- a date written 2026-10-14, 2026.10.14, 14/10/2026 or 14-10-2026 is left alone
declare r text := p; m text[]; dg text; nd int; sep text := '[\s' || chr(160) || '()./_-]';
begin
  if p is null or p !~ '[0-9০-৯]' then return p; end if;
  for m in select regexp_matches(p, '(\+?[0-9০-৯](?:[0-9০-৯]|' || sep || '{1,3}(?=[0-9০-৯])){6,})', 'g') loop
    dg := regexp_replace(m[1], '[^0-9০-৯]', '', 'g'); nd := char_length(dg);
    if nd between 8 and 15 and m[1] !~ '^[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}$' and m[1] !~ '^[0-9]{1,2}[-./][0-9]{1,2}[-./][0-9]{4}$' then
      r := replace(r, m[1], repeat('•', greatest(nd - 3, 3)) || right(dg, 3));
    end if;
  end loop;
  return r;
end $b$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cust_pii103(p_field text, p_val text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- customer fields follow inbox_pii_mode; owner and view_customer_mobile holders see them as before
declare mode_ text := public._inb_pii_mode99();
begin
  if p_val is null or btrim(p_val) = '' or mode_ = 'off' then return p_val; end if;
  if public.is_owner() or public.rpt_grant('view_customer_mobile') then return p_val; end if;
  return case p_field
    when 'name' then case when mode_ = 'mask_all_pii' then public._inb_mask99('name', p_val) else p_val end   -- bos105 (L6): names are hidden only in mask_all_pii
    when 'mobile' then public._inb_mask99('mobile', p_val)
    when 'address' then case when mode_ in ('mask_phone_address', 'mask_all_pii') then public._inb_mask99('address', p_val) else public._inb_mask_phones103(p_val) end
    else case when mode_ = 'mask_all_pii' then public._inb_mask99('text', p_val) else public._inb_mask_phones103(p_val) end end;
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_advances()
 RETURNS TABLE(customer_id uuid, name text, mobile text, balance numeric, last_at date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, public._cust_pii103('mobile', c.mobile) /* bos105 */, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_profile(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; res jsonb;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'mobile', public._cust_pii103('mobile', c.mobile) /* bos105 */, 'name', c.name, 'type', c.type, 'active', c.active, 'tier_id', c.tier_id, 'tier_locked', c.tier_locked, 'birthday', c.birthday,
        'anniversary', c.anniversary, 'address', public._cust_pii103('address', c.address), 'whatsapp', public._cust_pii103('mobile', c.whatsapp), 'note', public._cust_pii103('text', c.note) /* bos105 */, 'source', c.source, 'credit_limit', c.credit_limit, 'customer_since', c.customer_since),
    'spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'first_sale', st.first_sale, 'last_sale', st.last_sale,
    'avg_bill', case when st.orders > 0 then round(st.spend / st.orders, 2) end,
    'balance', public._cust_bal(p_customer),
    'points', coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', h.at, 'from_tier', h.from_tier, 'to_tier', h.to_tier, 'reason', h.reason, 'note', h.note, 'by', h.by_staff) order by h.at desc, h.id desc)
                         from (select * from public.customer_tier_history where customer_id = p_customer order by at desc, id desc limit 30) h), '[]'::jsonb),
    'gifts', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'text_bn', g.gift_text_bn, 'text_en', g.gift_text_en, 'value', g.value_taka, 'issued_at', g.issued_at, 'valid_until', g.valid_until, 'claimed_at', g.claimed_at)
                                        order by g.issued_at desc) from (select * from public.customer_gifts where customer_id = p_customer order by issued_at desc limit 30) g), '[]'::jsonb),
    'points_log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'delta', l.delta, 'reason', l.reason, 'note', l.note) order by l.at desc, l.id desc)
                            from (select * from public.customer_points_ledger where customer_id = p_customer order by at desc, id desc limit 30) l), '[]'::jsonb),
    'recent_sales', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'receipt', z.receipt, 'date', z.sale_date, 'total', z.total, 'due', z.due_amount, 'status', z.status, 'loc', z.location_id) order by z.sold_at desc)
                              from (select * from public.sales x where x.customer_id = p_customer and public.can_loc(x.location_id) order by x.sold_at desc limit 10) z), '[]'::jsonb));
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
 RETURNS TABLE(id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text, credit_limit numeric, customer_since date, balance numeric, spend numeric, orders integer, last_sale date, points integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return query
    with s as (select x.customer_id cid, sum(x.total) tot, count(*)::int n, max(x.sale_date) last_d from public.sales x
               where x.status = 'done' and x.customer_id is not null and public.can_loc(x.location_id) group by 1),
         r as (select y.customer_id cid, sum(y.amount) amt from public.sale_returns y join public.sales z on z.id = y.sale_id
               where y.status = 'done' and y.customer_id is not null and public.can_loc(z.location_id) group by 1),
         d as (select q.id cid, q.balance bal from public.customer_dues() q),
         p as (select l.customer_id cid, sum(l.delta)::int pts from public.customer_points_ledger l group by 1)
    select c.id, public._cust_pii103('mobile', c.mobile) /* bos103 */, public._cust_pii103('name', c.name) /* sec2-L6 */, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, public._cust_pii103('address', c.address), public._cust_pii103('mobile', c.whatsapp), public._cust_pii103('text', c.note), c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_save(p_id uuid, p jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mob text; c public.customers; nm text; ty text; mgr boolean; tid bigint; wa text; old_tier bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  mgr := public._cust_mgr43();
  if not (mgr or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if (p ? 'birthday' and public._d43(p, 'birthday') > public._today43()) or (p ? 'anniversary' and public._d43(p, 'anniversary') > public._today43()) then raise exception 'bad_date'; end if;
  if p_id is not null then p := p - array(select e.key from jsonb_each_text(p) e where e.key in ('name', 'address', 'note', 'whatsapp') and e.value like '%•%'); end if;   -- bos105: a masked value read from the screen is never saved back over the real one
  perform public._client_lock(p_client);
  if p ? 'name' then
    nm := left(btrim(coalesce(p ->> 'name', '')), 80);
    if nm = '' then raise exception 'customer_name_required'; end if;
  end if;
  if p ? 'type' then ty := p ->> 'type'; if ty is null or ty not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if; end if;
  if p ? 'whatsapp' then
    wa := nullif(btrim(coalesce(p ->> 'whatsapp', '')), '');
    if wa is not null then wa := public.norm_mobile(wa); end if;
  end if;
  if p_id is null then
    if nullif(btrim(coalesce(p ->> 'mobile', '')), '') is null then raise exception 'bad_mobile'; end if;
    mob := public.norm_mobile(p ->> 'mobile');
    if nm is null then raise exception 'customer_name_required'; end if;
    select * into c from public.customers where mobile = mob;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'name', c.name, 'active', c.active); end if;
    if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit') and not mgr then raise exception 'not allowed'; end if;
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null and not exists (select 1 from public.customer_tiers where id = tid and active) then raise exception 'tier_not_found'; end if;
    insert into public.customers (mobile, name, type, created_by, tier_id, tier_locked, birthday, anniversary, address, note, source, whatsapp, credit_limit)
      values (mob, nm, coalesce(ty, 'retail'), auth.uid(), tid, coalesce((p ->> 'tier_locked')::boolean, tid is not null), public._d43(p, 'birthday'), public._d43(p, 'anniversary'),
              left(nullif(btrim(p ->> 'address'), ''), 200), left(nullif(btrim(p ->> 'note'), ''), 500), left(nullif(btrim(p ->> 'source'), ''), 60), wa, public._n43(p, 'credit_limit', 0))
      returning * into c;
    if tid is not null and tid is distinct from (select id from public.customer_tiers where is_default limit 1) then
      insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
        values (c.id, (select id from public.customer_tiers where is_default limit 1), tid, 'manual', 'at registration', auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
    end if;
    return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
  end if;
  select * into c from public.customers where id = p_id for update;
  if not found then raise exception 'customer_not_found'; end if;
  if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit' or p ? 'active') and not mgr then raise exception 'not allowed'; end if;
  update public.customers set
    name = coalesce(nm, name), type = coalesce(ty, type),
    birthday = case when p ? 'birthday' then public._d43(p, 'birthday') else birthday end,
    anniversary = case when p ? 'anniversary' then public._d43(p, 'anniversary') else anniversary end,
    address = case when p ? 'address' then left(nullif(btrim(p ->> 'address'), ''), 200) else address end,
    note = case when p ? 'note' then left(nullif(btrim(p ->> 'note'), ''), 500) else note end,
    source = case when p ? 'source' then left(nullif(btrim(p ->> 'source'), ''), 60) else source end,
    whatsapp = case when p ? 'whatsapp' then wa else whatsapp end,
    credit_limit = case when p ? 'credit_limit' then public._n43(p, 'credit_limit', 0) else credit_limit end,
    tier_locked = case when p ? 'tier_locked' then coalesce((p ->> 'tier_locked')::boolean, tier_locked) else tier_locked end,
    active = case when p ? 'active' then coalesce((p ->> 'active')::boolean, active) else active end
  where id = p_id returning * into c;
  if p ? 'tier_id' then
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null then perform public.customer_set_tier(p_id, tid, coalesce(nullif(btrim(p ->> 'tier_reason'), ''), 'edited'), case when p ? 'tier_locked' then (p ->> 'tier_locked')::boolean end); end if;
  end if;
  return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
end $function$
$f$; end if; end $p105$;

-- ---------- H1: the new opt-in switch (default OFF = today) ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('customers_pii_guard_on', 'pos', 'switch', 'false', null, null, null, null,
  'গ্রাহকের ফোন/ঠিকানা table থেকে সরাসরি পড়া বন্ধ', 'Customer এর ফোন/ঠিকানা table থেকে সরাসরি পড়া বন্ধ', 'Block direct table reads of customer phone / address',
  'বন্ধ = আজকের মতো। চালু করলে mobile, whatsapp, address, note সরাসরি পড়া যায় না; শুধু customer_directory / customer_profile / customer_dues পড়ায় (inbox_pii_mode মানে)। আগে মোবাইল দিয়ে খোঁজার পর্দাগুলো ঠিক করুন।',
  'Off = as today. On = the browser can no longer read mobile, whatsapp, address, note with a plain table read; only customer_directory / customer_profile / customer_dues show them (following inbox_pii_mode). Screens that search customers by mobile must be moved first.', 990)
on conflict (key) do nothing;
end if; end $p105$;

-- ---------- H1: the existing guard trigger now also covers more online_orders columns and the customers table ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._inb_pii_cols76() returns trigger language plpgsql security definer set search_path = public as $$
declare cols text;
begin
  if new.key = 'inbox_pii_guard_on' then
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      revoke select (customer_mobile, address, note, draft_note, lines) on public.online_orders from authenticated;   -- bos105: note, draft_note, lines too
    else
      grant select (customer_mobile, address, note, draft_note, lines) on public.online_orders to authenticated;   -- bos105
    end if;
  elsif new.key = 'customers_pii_guard_on' then   -- bos105
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into cols from pg_attribute a
       where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped and a.attname not in ('mobile', 'whatsapp', 'address', 'note');
      revoke select on public.customers from authenticated;
      execute 'grant select (' || cols || ') on public.customers to authenticated';
    else
      grant select on public.customers to authenticated;
    end if;
  end if;
  return new;
end $$
$f$; end if; end $p105$;

-- ---------- grants: the new helper is internal; the salt table is closed ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
  revoke all on function public._bp_auto_ok105(text, text, int) from public, anon, authenticated;
  revoke all on function public._bp_uuid99(text, text) from public, anon, authenticated;
end if; end $p105$;

-- ---------- marker: phase105 pasted (tests read this) ----------
do $g$ begin
  if current_setting('phase105.ok', true) = 'on' then
    raise notice 'phase105 applied (bos105)';
  else
    raise notice 'phase105 NOT applied: a guard stopped it';
  end if;
end $g$;
